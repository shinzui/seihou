-- | Compare what @.seihou\/manifest.json@ records against what is actually
-- installed on this machine, before anything is generated.
--
-- The manifest is checked into version control (see
-- docs\/adr\/0001-manifest-is-a-checked-in-machine-independent-artifact.md),
-- so the copy of a module a developer has locally is not necessarily the copy
-- the manifest describes. Without a check, a developer whose install cache
-- lags behind the manifest regenerates every file from the older module and
-- rewrites the manifest to name it — a silent regression that looks like an
-- ordinary diff in code review.
--
-- This module answers "should we generate from what is here?". Answering
-- "where is it?" is 'Seihou.Core.ArtifactRef'.
--
-- The comparison itself ('judgeArtifact') is pure so it can be tested without
-- a filesystem; 'checkAppliedArtifacts' is the IO shell that locates each
-- recorded artifact and reads its version and provenance.
module Seihou.CLI.ManifestGuard
  ( -- * Verdicts
    ArtifactVerdict (..),
    ArtifactCheck (..),
    judgeArtifact,

    -- * Checking a manifest against this machine
    checkAppliedArtifacts,
    checkAppliedArtifactsFor,
    checkAppliedBlueprint,
    checkRecordedBlueprint,
    blockingChecks,

    -- * Enforcing
    enforceArtifactGuard,

    -- * Rendering
    formatGuardRefusal,
    formatGuardOverride,
    summarizeCheck,
  )
where

import Data.Generics.Labels ()
import Data.List (maximumBy, nubBy)
import Data.Maybe (fromMaybe)
import Data.Ord (comparing)
import Data.Set qualified as Set
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.Core.ArtifactIdentity (normalizeOriginUrl, normalizeProjectPath)
import Seihou.Core.ArtifactOriginDetect (detectArtifactOrigin)
import Seihou.Core.ArtifactRef
  ( ArtifactRefError,
    renderArtifactRefError,
    resolveArtifactOrigin,
  )
import Seihou.Core.Types
  ( AppliedBlueprint (..),
    AppliedBlueprintMigration (..),
    AppliedModule (..),
    ArtifactOrigin (..),
    Blueprint (..),
    Manifest (..),
    Module (..),
    ModuleName (..),
  )
import Seihou.Core.Version (parseVersion)
import Seihou.Dhall.Eval (evalBlueprintFromFile, evalModuleFromFile)
import Seihou.Prelude
import System.Exit (exitFailure)

-- ----------------------------------------------------------------------------
-- Verdicts
-- ----------------------------------------------------------------------------

-- | What the guard concluded about one applied artifact.
data ArtifactVerdict
  = -- | Local copy matches or is newer than what the manifest records,
    -- and the origin agrees. Nothing to say.
    ArtifactOk
  | -- | Local copy is strictly older than the recorded version.
    -- Fields: recorded version, local version.
    ArtifactStale !Text !Text
  | -- | A module of this name is installed, but from a different origin
    -- than the manifest records. Fields: recorded origin, local origin.
    ArtifactOriginMismatch !ArtifactOrigin !ArtifactOrigin
  | -- | The recorded artifact is not installed on this machine at all.
    ArtifactUnresolvable !ArtifactRefError
  | -- | Either side has a version string that 'parseVersion' rejects, so
    -- no ordering can be established. Fields: recorded, local.
    ArtifactVersionIncomparable !(Maybe Text) !(Maybe Text)
  | -- | The recorded origin carries no provenance seihou can check against
    -- what was found, so identity cannot be verified. The version was
    -- still compared and did not indicate a downgrade.
    ArtifactUnverifiableOrigin
  deriving stock (Eq, Show, Generic)

-- | One artifact's guard result, ready for rendering.
--
-- The recorded origin is carried alongside the verdict rather than inside
-- it: it is a property of the artifact that was checked, not of the
-- conclusion, and every rendered block wants it.
data ArtifactCheck = ArtifactCheck
  { name :: !ModuleName,
    origin :: !ArtifactOrigin,
    verdict :: !ArtifactVerdict
  }
  deriving stock (Eq, Show, Generic)

-- | How much the recorded origin and the origin of the copy found locally
-- agree.
data OriginRelation
  = -- | Both sides carry provenance and it is the same provenance.
    OriginMatches
  | -- | Both sides carry provenance and it disagrees.
    OriginDiffers
  | -- | At least one side carries no provenance, so identity is unknowable.
    OriginUnverifiable
  deriving stock (Eq, Show)

-- | Compare one recorded artifact against what was found locally.
--
-- @recordedOrigin@ and @recordedVersion@ come from the manifest.
-- @localOrigin@ and @localVersion@ come from the artifact actually found on
-- this machine — the origin by reading @.seihou-origin.json@ beside it, the
-- version from its @module.dhall@.
--
-- Identity is checked before version, because a differing origin URL means a
-- different module and its version number is not comparable to the recorded
-- one at all. When identity cannot be disproved but also cannot be confirmed,
-- the version comparison still runs: a version does come from the artifact
-- itself, so "older than recorded" is meaningful even when "the same module"
-- is not provable.
judgeArtifact ::
  ArtifactOrigin ->
  Maybe Text ->
  ArtifactOrigin ->
  Maybe Text ->
  ArtifactVerdict
judgeArtifact recordedOrigin recordedVersion localOrigin localVersion =
  case originRelation recordedOrigin localOrigin of
    OriginDiffers -> ArtifactOriginMismatch recordedOrigin localOrigin
    OriginMatches -> fromMaybe ArtifactOk versionVerdict
    OriginUnverifiable -> fromMaybe ArtifactUnverifiableOrigin versionVerdict
  where
    versionVerdict = judgeVersion recordedVersion localVersion

-- | The version half of the comparison. 'Nothing' means "nothing to report".
judgeVersion :: Maybe Text -> Maybe Text -> Maybe ArtifactVerdict
judgeVersion recorded@(Just rawRecorded) local@(Just rawLocal)
  | Just parsedRecorded <- parseVersion rawRecorded,
    Just parsedLocal <- parseVersion rawLocal =
      if parsedLocal < parsedRecorded
        then Just (ArtifactStale rawRecorded rawLocal)
        else Nothing
  | otherwise = Just (ArtifactVersionIncomparable recorded local)
judgeVersion recorded local = Just (ArtifactVersionIncomparable recorded local)

-- | Decide how much the two origins agree.
--
-- A 'RemoteOrigin' on both sides is the only case where identity can be
-- confirmed or refuted outright. A 'RemoteOrigin' recorded against a locally
-- discovered copy with no provenance (a personal module shadowing an installed
-- one) is honestly unverifiable rather than a mismatch — a developer who
-- deliberately shadows a module should not be told they have the wrong one.
-- A recorded 'ProjectOrigin' resolves against the project root and nowhere
-- else, so anything but the same project path is a genuine inconsistency.
originRelation :: ArtifactOrigin -> ArtifactOrigin -> OriginRelation
originRelation recorded local = case (recorded, local) of
  (RemoteOrigin recordedUrl _ _, RemoteOrigin localUrl _ _)
    | normalizeOriginUrl recordedUrl == normalizeOriginUrl localUrl -> OriginMatches
    | otherwise -> OriginDiffers
  (RemoteOrigin {}, _) -> OriginUnverifiable
  (ProjectOrigin recordedPath, ProjectOrigin localPath)
    | normalizeProjectPath recordedPath == normalizeProjectPath localPath -> OriginMatches
    | otherwise -> OriginDiffers
  (ProjectOrigin {}, _) -> OriginDiffers
  (LocalOrigin {}, _) -> OriginUnverifiable

-- ----------------------------------------------------------------------------
-- Checking a manifest against this machine
-- ----------------------------------------------------------------------------

-- | Check every module recorded in the manifest against this machine.
--
-- @projectRoot@ is the absolute directory holding @.seihou@. @searchPaths@ is
-- normally 'Seihou.Core.Module.defaultSearchPaths'. Returns one
-- 'ArtifactCheck' per distinct recorded module, in manifest order,
-- deduplicated by module name — two instances of the same module with
-- different parent variables resolve to the same directory and would produce
-- the same verdict twice.
checkAppliedArtifacts ::
  FilePath ->
  [FilePath] ->
  Manifest ->
  IO [ArtifactCheck]
checkAppliedArtifacts projectRoot searchPaths =
  checkAppliedArtifactsFor projectRoot searchPaths Nothing

-- | 'checkAppliedArtifacts' restricted to a subset of module names.
--
-- 'Nothing' means "every applied module" and is what @seihou status@ wants.
-- @'Just' names@ keeps only modules whose name is in the set, which is what
-- @seihou run@ wants: a stale module unrelated to the composition being
-- generated must not block the run, exactly as
-- 'Seihou.CLI.PendingMigrations.detectPendingMigrations' already treats an
-- unrelated pending migration.
checkAppliedArtifactsFor ::
  FilePath ->
  [FilePath] ->
  Maybe (Set ModuleName) ->
  Manifest ->
  IO [ArtifactCheck]
checkAppliedArtifactsFor projectRoot searchPaths mFilter manifest =
  traverse checkOne (dedupeByName (filter wanted (manifest ^. #modules)))
  where
    wanted applied = case mFilter of
      Nothing -> True
      Just names -> Set.member (applied ^. #name) names

    dedupeByName = nubBy (\a b -> a ^. #name == b ^. #name)

    checkOne applied =
      checkRecordedArtifact
        projectRoot
        searchPaths
        "module.dhall"
        localModuleVersion
        (applied ^. #name)
        (applied ^. #origin)
        (applied ^. #moduleVersion)

-- | Check the blueprint the manifest records, if any, against this machine.
--
-- 'Nothing' means no @seihou agent run@ has been recorded in this project.
--
-- This is the reporting form: it checks whatever blueprint the manifest
-- happens to record, which is what @seihou status@ wants. A command about to
-- *use* a blueprint wants 'checkRecordedBlueprint', which is scoped to that
-- one blueprint.
checkAppliedBlueprint :: FilePath -> [FilePath] -> Manifest -> IO (Maybe ArtifactCheck)
checkAppliedBlueprint projectRoot searchPaths manifest =
  traverse checkOne (manifest ^. #blueprint)
  where
    checkOne applied =
      checkBlueprintIdentity
        projectRoot
        searchPaths
        (applied ^. #name)
        (applied ^. #origin)
        (applied ^. #blueprintVersion)

-- | Check one named blueprint — the one a command is about to use — against
-- what this project already records about it.
--
-- A project records a blueprint's identity in two independent places, and
-- either is enough. @seihou agent run@ writes the applied-blueprint entry;
-- @seihou agent migrate@ writes one receipt per completed edge and never
-- touches that entry, so a project may well have migrated a blueprint it
-- never ran. The applied-blueprint entry wins when both exist, because it is
-- rewritten on every run and is therefore the more recent statement; among
-- receipts the most recently applied one wins for the same reason.
--
-- 'Nothing' means this project records nothing about this blueprint, so there
-- is nothing to compare and the caller proceeds. A record naming a
-- *different* blueprint is deliberately ignored: docs\/adr\/0003 scopes each
-- refusal to the artifacts the command is actually about to use, so an
-- unrelated stale artifact must not block unrelated work.
checkRecordedBlueprint ::
  FilePath ->
  [FilePath] ->
  ModuleName ->
  Manifest ->
  IO (Maybe ArtifactCheck)
checkRecordedBlueprint projectRoot searchPaths blueprintName manifest =
  traverse checkOne recorded
  where
    checkOne (recordedOrigin, recordedVersion) =
      checkBlueprintIdentity projectRoot searchPaths blueprintName recordedOrigin recordedVersion

    recorded = case appliedEntry of
      Just entry -> Just (entry ^. #origin, entry ^. #blueprintVersion)
      Nothing -> latestReceipt

    appliedEntry = case manifest ^. #blueprint of
      Just entry | entry ^. #name == blueprintName -> Just entry
      _ -> Nothing

    latestReceipt =
      case filter (\receipt -> receipt ^. #name == blueprintName) (manifest ^. #blueprintMigrations) of
        [] -> Nothing
        receipts ->
          let newest = maximumBy (comparing (^. #appliedAt)) receipts
           in Just (newest ^. #origin, newest ^. #blueprintVersion)

-- | One recorded blueprint identity, checked against the copy installed here.
checkBlueprintIdentity ::
  FilePath ->
  [FilePath] ->
  ModuleName ->
  ArtifactOrigin ->
  Maybe Text ->
  IO ArtifactCheck
checkBlueprintIdentity projectRoot searchPaths =
  checkRecordedArtifact projectRoot searchPaths "blueprint.dhall" localBlueprintVersion

-- | Locate one recorded artifact on this machine and judge it.
--
-- Shared by every caller so there is one verdict vocabulary regardless of
-- what kind of artifact is being checked. Only two things vary: the file that
-- makes a directory count as this kind of artifact (@module.dhall@ versus
-- @blueprint.dhall@), and how the local copy's version is read out of it.
checkRecordedArtifact ::
  FilePath ->
  [FilePath] ->
  FilePath ->
  (FilePath -> IO (Maybe Text)) ->
  ModuleName ->
  ArtifactOrigin ->
  Maybe Text ->
  IO ArtifactCheck
checkRecordedArtifact projectRoot searchPaths definitionFile readLocalVersion name recordedOrigin recordedVersion = do
  resolved <- resolveArtifactOrigin projectRoot searchPaths definitionFile recordedOrigin
  verdict <- case resolved of
    Left refErr -> pure (ArtifactUnresolvable refErr)
    Right directory -> do
      localOrigin <- detectArtifactOrigin projectRoot directory
      localVersion <- readLocalVersion directory
      pure (judgeArtifact recordedOrigin recordedVersion localOrigin localVersion)
  pure
    ArtifactCheck
      { name = name,
        origin = recordedOrigin,
        verdict = verdict
      }

-- | The version the locally installed @module.dhall@ declares.
--
-- A module that does not evaluate yields 'Nothing', which becomes
-- 'ArtifactVersionIncomparable'. That is deliberate: a broken @module.dhall@
-- is a separate problem, and the generation path reports it far better than
-- the guard could.
localModuleVersion :: FilePath -> IO (Maybe Text)
localModuleVersion directory = do
  result <- evalModuleFromFile (directory </> "module.dhall")
  pure $ case result of
    Left _ -> Nothing
    Right modul -> modul ^. #version

-- | The version the locally installed @blueprint.dhall@ declares, on the same
-- terms as 'localModuleVersion'.
localBlueprintVersion :: FilePath -> IO (Maybe Text)
localBlueprintVersion directory = do
  result <- evalBlueprintFromFile (directory </> "blueprint.dhall")
  pure $ case result of
    Left _ -> Nothing
    Right blueprint -> blueprint ^. #version

-- | Whether any verdict is severe enough to stop the command.
--
-- 'ArtifactStale', 'ArtifactOriginMismatch' and 'ArtifactUnresolvable' block:
-- each one means generating now would produce files from something other than
-- what the project records. 'ArtifactVersionIncomparable' and
-- 'ArtifactUnverifiableOrigin' are reported but never block, because neither
-- is evidence of a problem — only evidence that seihou cannot prove there
-- isn't one.
blockingChecks :: [ArtifactCheck] -> [ArtifactCheck]
blockingChecks = filter (isBlocking . (^. #verdict))
  where
    isBlocking = \case
      ArtifactStale {} -> True
      ArtifactOriginMismatch {} -> True
      ArtifactUnresolvable {} -> True
      ArtifactOk -> False
      ArtifactVersionIncomparable {} -> False
      ArtifactUnverifiableOrigin -> False

-- ----------------------------------------------------------------------------
-- Enforcing
-- ----------------------------------------------------------------------------

-- | Apply the downgrade / origin-mismatch policy to whatever 'blockingChecks'
-- kept.
--
-- The 'Bool' is the command's @--allow-downgrade@ flag. Every command that
-- generates from an artifact spells that flag the same way and behaves the
-- same way once it is set, so the policy lives here rather than being
-- reimplemented per command.
--
-- Without @--allow-downgrade@: the command refuses before a single file is
-- written, so the project and its manifest are left byte-identical.
--
-- With @--allow-downgrade@: the same blocks are printed under a "proceeding
-- anyway" lead-in and the command continues. They are printed rather than
-- suppressed on purpose — a deliberate downgrade is still a downgrade, and
-- the diff it produces should not be the first time anyone hears about it.
enforceArtifactGuard :: Bool -> [ArtifactCheck] -> IO ()
enforceArtifactGuard _ [] = pure ()
enforceArtifactGuard allowDowngrade blocking
  | allowDowngrade = TIO.putStr (formatGuardOverride blocking)
  | otherwise = do
      TIO.putStr (formatGuardRefusal blocking)
      exitFailure

-- ----------------------------------------------------------------------------
-- Rendering
-- ----------------------------------------------------------------------------

-- | Render blocking verdicts as the multi-line refusal message, one block per
-- artifact, followed by a paragraph naming the escape hatch.
formatGuardRefusal :: [ArtifactCheck] -> Text
formatGuardRefusal [] = ""
formatGuardRefusal checks =
  T.intercalate "\n\n" (map (refusalBlock "✗ Refusing to run") checks)
    <> "\n\n"
    <> T.intercalate
      "\n"
      [ "To proceed anyway — pinning this project to what is installed here —",
        "re-run with --allow-downgrade."
      ]
    <> "\n"

-- | The same blocks, printed when @--allow-downgrade@ was passed. A
-- deliberate downgrade should still be visible in the terminal; silently
-- honouring the flag would hide exactly the change this module exists to
-- make legible.
formatGuardOverride :: [ArtifactCheck] -> Text
formatGuardOverride [] = ""
formatGuardOverride checks =
  T.intercalate "\n\n" (map (refusalBlock "! Proceeding anyway (--allow-downgrade)") checks) <> "\n"

-- | One artifact's block, under a caller-supplied lead-in. The lead-in
-- carries its own status symbol, because a refusal and a deliberate override
-- print the same body but are not the same news.
refusalBlock :: Text -> ArtifactCheck -> Text
refusalBlock leadIn check = case check ^. #verdict of
  ArtifactStale recordedVersion localVersion ->
    T.intercalate "\n" $
      [ leadIn <> ": your local copy of '" <> label <> "' is older than the",
        "  version this project expects.",
        "",
        "  Recorded in .seihou/manifest.json:  " <> recordedVersion,
        "  Installed on this machine:          " <> localVersion
      ]
        <> originLine
        <> [ "",
             "  Update your local copy first:",
             "    seihou upgrade " <> label
           ]
  ArtifactOriginMismatch recorded local ->
    T.intercalate "\n" $
      [ leadIn <> ": '" <> label <> "' is installed from a different source",
        "  than this project records.",
        "",
        "  Recorded in .seihou/manifest.json:  " <> originDescription recorded,
        "  Installed on this machine:          " <> originDescription local,
        "",
        "  These are different artifacts that happen to share a name."
      ]
        <> case recorded of
          RemoteOrigin url _ _ ->
            [ "  Install the one this project records:",
              "    seihou install " <> url
            ]
          _ -> []
  ArtifactUnresolvable refErr ->
    leadIn <> ".\n\n" <> renderArtifactRefError refErr
  ArtifactVersionIncomparable recorded local ->
    T.intercalate
      "\n"
      [ "! '" <> label <> "' cannot be version-checked against this project.",
        "",
        "  Recorded in .seihou/manifest.json:  " <> describeVersion recorded,
        "  Installed on this machine:          " <> describeVersion local
      ]
  ArtifactUnverifiableOrigin ->
    T.intercalate
      "\n"
      [ "! '" <> label <> "' has no recorded provenance, so seihou cannot confirm",
        "  the copy installed here is the one this project was generated from."
      ]
  ArtifactOk -> ""
  where
    label = check ^. #name . #unModuleName

    originLine = case check ^. #origin of
      RemoteOrigin url _ _ -> ["  Origin: " <> url]
      _ -> []

    describeVersion = fromMaybe "(none recorded)"

-- | A one-line summary of anything worth mentioning, for reporting commands
-- like @seihou status@ that must never fail on a verdict. 'Nothing' means
-- there is nothing to say.
summarizeCheck :: ArtifactCheck -> Maybe Text
summarizeCheck check = case check ^. #verdict of
  ArtifactOk -> Nothing
  ArtifactStale recordedVersion localVersion ->
    Just $
      label
        <> ": this project expects "
        <> recordedVersion
        <> " but "
        <> localVersion
        <> " is installed here (run 'seihou upgrade "
        <> label
        <> "')"
  ArtifactOriginMismatch recorded local ->
    Just $
      label
        <> ": this project records "
        <> originDescription recorded
        <> " but "
        <> originDescription local
        <> " is installed here"
  ArtifactUnresolvable _ ->
    Just (label <> ": recorded in the manifest but not installed on this machine")
  ArtifactVersionIncomparable _ _ ->
    Just (label <> ": versions cannot be compared, so staleness is unknown")
  ArtifactUnverifiableOrigin ->
    Just (label <> ": no recorded provenance, so its identity cannot be verified")
  where
    label = check ^. #name . #unModuleName

-- | How to name an origin in a comparison line.
originDescription :: ArtifactOrigin -> Text
originDescription (RemoteOrigin url _ _) = url
originDescription (ProjectOrigin path) = T.pack path <> " (inside this project)"
originDescription (LocalOrigin artifact) = artifact <> " (no recorded provenance)"
