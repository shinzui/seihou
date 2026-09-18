-- | Upgrade a @.seihou\/manifest.json@ through the ordered schema steps of
-- "Seihou.Manifest.Upgrade", one adjacent step at a time, and establish the
-- shared-write evidence schema 7 can record.
--
-- Most of this module is the one inference-bearing step, schema 5 to 6: the
-- conversion of machine-local artifact paths into portable origins.
--
-- Schema-5-and-earlier manifests record, for each applied artifact, the
-- absolute directory that artifact occupied on the machine that ran seihou —
-- entries like @\/Users\/shinzui\/.config\/seihou\/installed\/haskell-base@.
-- That string is meaningless in any other clone, which is why
-- docs\/adr\/0001-manifest-is-a-checked-in-machine-independent-artifact.md
-- forbids it and why
-- 'Seihou.Manifest.Types.checkManifestVersion' refuses such a manifest
-- outright rather than misreading it.
--
-- This module turns those paths into 'ArtifactOrigin' values. Doing so
-- requires inference — the recorded path belongs to somebody else's machine,
-- so the upstream URL has to be recovered from what is installed here — and
-- inference that happens silently inside a file that is committed to git is
-- exactly what this initiative exists to remove. So the conversion is an
-- explicit command with a printed report rather than an automatic upgrade on
-- first read, and every entry says how confident it is.
--
-- The document is manipulated as an 'Aeson.Value' rather than decoded into
-- mirror records. The upgrade only needs to find three keys and replace them;
-- every other field — resolved variables, file records, baseline references,
-- command receipts, blueprint migration receipts — must survive untouched,
-- and walking the 'Aeson.Value' guarantees that where decode-and-re-encode
-- would risk dropping a key some later schema version added.
module Seihou.CLI.ManifestUpgrade
  ( -- * Reading a legacy manifest
    LegacyRef (..),
    LegacyManifest (..),
    readLegacyManifest,

    -- * Inferring a portable origin
    InferenceOutcome (..),
    inferredOrigin,
    inferOriginFromLegacyPath,

    -- * Rewriting the document
    UpgradeReportEntry (..),
    UpgradeStepReport (..),
    SharedWriteReportEntry (..),
    UpgradeResult (..),
    applyUpgrade,
    convertMachineLocalPaths,
    formatUpgradeReport,

    -- * The command
    ManifestUpgradeOpts (..),
    UpgradeOutcome (..),
    manifestRelativePath,
    formatUpgradeRefusal,
    runManifestUpgrade,
    renderUpgradeOutcome,
    handleManifestUpgrade,
  )
where

import Control.Monad (unless)
import Data.Aeson qualified as Aeson
import Data.Aeson.Key (Key)
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString.Lazy qualified as LBS
import Data.Foldable (toList)
import Data.Generics.Labels ()
import Data.List (foldl')
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Vector qualified as V
import Seihou.CLI.ManifestCapabilityUpgrade
  ( CertificationScope (..),
    EvidencePolicy (..),
    EvidenceSource (..),
    SharedWriteCertification (..),
    SharedWriteCertificationEntry (..),
    certifiedChanges,
    certifySharedWriteModesIO,
    renderCertificationGap,
    renderEvidenceSource,
  )
import Seihou.CLI.ManifestGuard
  ( ArtifactCheck,
    blockingChecks,
    checkAppliedArtifacts,
    summarizeCheck,
  )
import Seihou.Core.ArtifactOriginDetect (detectArtifactOrigin)
import Seihou.Core.ArtifactRef (resolveArtifactOrigin)
import Seihou.Core.Module (defaultSearchPaths)
import Seihou.Core.Types
  ( ArtifactOrigin (..),
    Manifest,
    ManifestCapability (..),
    ManifestSchemaVersion (..),
    SharedWriteMode (..),
  )
import Seihou.Manifest.Types
  ( currentManifestVersion,
    manifestSupports,
    oldestDecodableManifestVersion,
    sharedWriteModeToText,
  )
import Seihou.Manifest.Upgrade
  ( ManifestUpgradeStep (..),
    UpgradeStepAction (..),
    UpgradeStepKind (..),
    applyLosslessUpgradeStep,
    documentSchemaVersion,
    planManifestUpgrade,
    renderManifestUpgradeError,
    setDocumentSchemaVersion,
    upgradeStepKind,
  )
import Seihou.Prelude
import System.Directory (doesFileExist, getCurrentDirectory, renamePath)
import System.Exit (exitFailure)
import System.IO.Temp (withSystemTempDirectory)
import Text.Read (readMaybe)

-- ----------------------------------------------------------------------------
-- Reading a legacy manifest
-- ----------------------------------------------------------------------------

-- | One legacy artifact reference found in a schema-5-or-earlier manifest.
--
-- @jsonPointer@ locates the reference inside the document so the rewriter can
-- put the converted origin back in the right place, and so the report can say
-- which record it came from. It is a list of object keys and array indices
-- ending in the key that holds the path, for example
-- @["modules", "0", "source"]@ or
-- @["applications", "0", "instances", "1", "source"]@.
--
-- @definitionFile@ is the file that must be present for a directory to count
-- as this artifact — @module.dhall@ for a module, @recipe.dhall@ for an
-- application whose target is a recipe. Inference needs it because it looks
-- the artifact up by name in the local search paths.
data LegacyRef = LegacyRef
  { jsonPointer :: ![Text],
    artifactName :: !Text,
    legacyPath :: !FilePath,
    recordedVersion :: !(Maybe Text),
    definitionFile :: !FilePath
  }
  deriving stock (Eq, Show, Generic)

-- | Every legacy reference in a document, together with the document itself
-- so the rewriter can operate on it directly.
data LegacyManifest = LegacyManifest
  { schemaVersion :: !Int,
    document :: !Aeson.Value,
    refs :: ![LegacyRef]
  }
  deriving stock (Eq, Show, Generic)

-- | Parse a manifest document whose artifact references are still
-- machine-local paths.
--
-- Returns 'Nothing' when the document's @version@ is already portable
-- (schema 6 or later), so a schema-6 document can never reach 'collectRefs'.
-- A manifest from a /newer/ seihou is also 'Nothing': there is nothing here
-- to convert, and complaining about it is the step planner's job.
readLegacyManifest :: LBS.ByteString -> Either String (Maybe LegacyManifest)
readLegacyManifest bytes = do
  value <- Aeson.eitherDecode bytes
  fields <- case value of
    Aeson.Object fields -> Right fields
    _ -> Left "manifest is not a JSON object"
  schemaVersion <- case KeyMap.lookup "version" fields of
    Just (Aeson.Number n) -> Right (truncate n :: Int)
    Just _ -> Left "manifest 'version' is not a number"
    Nothing -> Left "manifest has no 'version' field"
  pure $
    if schemaVersion >= oldestDecodableManifestVersion ^. #unManifestSchemaVersion
      then Nothing
      else
        Just
          LegacyManifest
            { schemaVersion = schemaVersion,
              document = value,
              refs = collectRefs value
            }

-- | Every machine-specific path recorded in a legacy document, in the order a
-- reader meets them.
--
-- Three keys hold such a path: @source@ inside each entry of @modules@,
-- @targetSource@ on each application, and @source@ inside each of an
-- application's @instances@. Everything else in the format is already
-- portable.
collectRefs :: Aeson.Value -> [LegacyRef]
collectRefs value =
  concatMap moduleRef (withIndices (arrayAt value "modules"))
    <> concatMap applicationRefs (withIndices (arrayAt value "applications"))
  where
    moduleRef (index, element) =
      mkRef
        ["modules", index, "source"]
        "module.dhall"
        (textAt element "name")
        (textAt element "source")
        (textAt element "version")

    applicationRefs (index, element) =
      mkRef
        ["applications", index, "targetSource"]
        (targetDefinitionFile element)
        (objectAt element "target" >>= \target -> textAt target "name")
        (textAt element "targetSource")
        (textAt element "targetVersion")
        <> concatMap (instanceRef index) (withIndices (arrayAt element "instances"))

    instanceRef applicationIndex (index, element) =
      mkRef
        ["applications", applicationIndex, "instances", index, "source"]
        "module.dhall"
        (textAt element "name")
        (textAt element "source")
        (textAt element "version")

-- | An application's target is either a module or a recipe, and the two are
-- discovered by different definition files.
targetDefinitionFile :: Aeson.Value -> FilePath
targetDefinitionFile application =
  case objectAt application "target" >>= \target -> textAt target "kind" of
    Just "recipe" -> "recipe.dhall"
    _ -> "module.dhall"

-- | Build a reference, or nothing when the record lacks a name or a path.
--
-- A record with no @source@ is not an error: a hand-edited manifest, or a
-- record a future field made optional, simply has nothing to convert.
mkRef ::
  [Text] ->
  FilePath ->
  Maybe Text ->
  Maybe Text ->
  Maybe Text ->
  [LegacyRef]
mkRef pointer definitionFile mName mSource mVersion =
  case (mName, mSource) of
    (Just name, Just source) ->
      [ LegacyRef
          { jsonPointer = pointer,
            artifactName = name,
            legacyPath = T.unpack source,
            recordedVersion = mVersion,
            definitionFile = definitionFile
          }
      ]
    _ -> []

-- ----------------------------------------------------------------------------
-- Inferring a portable origin
-- ----------------------------------------------------------------------------

-- | How confident the upgrade is about a converted origin.
--
-- The distinction is not decoration: it is what the printed report shows the
-- developer, and it is the difference between a manifest entry that names its
-- upstream and one that admits it cannot.
data InferenceOutcome
  = -- | The artifact resolved locally and its install metadata gave a URL.
    -- Strongest result.
    InferredFromLocalInstall !ArtifactOrigin
  | -- | The legacy path names a directory inside the project, so it converts
    -- to a 'ProjectOrigin' by path arithmetic alone. Exact rather than
    -- inferred: a project-relative path means the same thing in every clone.
    InferredFromProjectPath !ArtifactOrigin
  | -- | Nothing local matched, or what matched carries no provenance; fell
    -- back to 'LocalOrigin' with only the recorded name. The developer can
    -- improve this by reinstalling from the real upstream and re-running the
    -- upgrade.
    InferredAsUnverifiable !ArtifactOrigin
  deriving stock (Eq, Show, Generic)

-- | The converted origin, whatever the confidence.
inferredOrigin :: InferenceOutcome -> ArtifactOrigin
inferredOrigin (InferredFromLocalInstall origin) = origin
inferredOrigin (InferredFromProjectPath origin) = origin
inferredOrigin (InferredAsUnverifiable origin) = origin

-- | Convert one legacy reference into a portable origin.
--
-- @projectRoot@ is the absolute directory holding @.seihou@. @searchPaths@ is
-- normally 'Seihou.Core.Module.defaultSearchPaths'.
--
-- Inference proceeds in three steps.
--
-- First, path arithmetic that needs no local state. The recorded path was
-- written by another machine, so its project-root prefix is that machine's
-- checkout, not this one — which is why the test is on the /suffix/: a path
-- ending in @.seihou\/modules\/\<name\>@ names a project-local artifact in
-- every clone. Containment inside this machine's project root is checked
-- second, as confirmation, for a layout the suffix test does not recognise.
--
-- Second, a local lookup by name through @searchPaths@, which is exactly what
-- 'Seihou.Core.ArtifactRef.resolveArtifactOrigin' does for a 'LocalOrigin'.
-- What is found is classified by 'detectArtifactOrigin', so an installed copy
-- with a @.seihou-origin.json@ yields the upstream URL the legacy path had
-- thrown away.
--
-- Third, 'LocalOrigin' carrying only the recorded name — the honest
-- representation of "this came from somewhere on that developer's machine and
-- we cannot say where".
inferOriginFromLegacyPath ::
  FilePath ->
  [FilePath] ->
  LegacyRef ->
  IO InferenceOutcome
inferOriginFromLegacyPath projectRoot searchPaths ref =
  case projectModuleSuffix (ref ^. #legacyPath) of
    Just relative -> pure (InferredFromProjectPath (ProjectOrigin relative))
    Nothing -> do
      recorded <- detectArtifactOrigin projectRoot (ref ^. #legacyPath)
      case recorded of
        ProjectOrigin _ -> pure (InferredFromProjectPath recorded)
        _ -> fromLocalLookup
  where
    name = ref ^. #artifactName

    fromLocalLookup = do
      resolved <-
        resolveArtifactOrigin
          projectRoot
          searchPaths
          (ref ^. #definitionFile)
          (LocalOrigin name)
      case resolved of
        Left _ -> pure (InferredAsUnverifiable (LocalOrigin name))
        Right directory -> do
          found <- detectArtifactOrigin projectRoot directory
          pure $ case found of
            RemoteOrigin {} -> InferredFromLocalInstall found
            ProjectOrigin {} -> InferredFromProjectPath found
            LocalOrigin {} -> InferredAsUnverifiable found

-- | The project-relative form of a legacy path that names an artifact under
-- @.seihou\/modules\/@, whichever machine's checkout it was written on.
projectModuleSuffix :: FilePath -> Maybe FilePath
projectModuleSuffix path = case reverse (pathSegments path) of
  (name : "modules" : ".seihou" : _) -> Just (".seihou/modules/" <> name)
  _ -> Nothing

-- | Whether a legacy path has the shape of an entry in the install cache,
-- @\<xdg-config\>\/seihou\/installed\/\<name\>@.
--
-- A path with that shape says the original author had the artifact installed
-- from an upstream, so when inference still falls back to 'LocalOrigin' the
-- report can say the URL was lost rather than that there never was one.
legacyPathWasInstalled :: FilePath -> Bool
legacyPathWasInstalled path = case reverse (pathSegments path) of
  (_ : "installed" : "seihou" : _) -> True
  _ -> False

-- | Split a recorded path into its segments, tolerating either separator: the
-- path may have been written by a machine that is not this one.
pathSegments :: FilePath -> [FilePath]
pathSegments = filter (not . null) . foldr split [[]]
  where
    split character segments@(current : rest)
      | character == '/' || character == '\\' = [] : segments
      | otherwise = (character : current) : rest
    split _ [] = []

-- ----------------------------------------------------------------------------
-- Rewriting the document
-- ----------------------------------------------------------------------------

-- | One line of the upgrade report.
data UpgradeReportEntry = UpgradeReportEntry
  { artifactName :: !Text,
    legacyPath :: !FilePath,
    outcome :: !InferenceOutcome
  }
  deriving stock (Eq, Show, Generic)

-- | One adjacent schema step that ran.
data UpgradeStepReport = UpgradeStepReport
  { fromVersion :: !ManifestSchemaVersion,
    toVersion :: !ManifestSchemaVersion,
    kind :: !UpgradeStepKind,
    summary :: !Text
  }
  deriving stock (Eq, Show, Generic)

-- | An upgraded document plus the reviewable account of how it was reached.
data UpgradeResult = UpgradeResult
  { -- | The schema the document was read at.
    fromVersion :: !ManifestSchemaVersion,
    -- | The schema of the last step that actually ran.
    toVersion :: !ManifestSchemaVersion,
    -- | Every step that ran, in order.
    steps :: ![UpgradeStepReport],
    -- | The origin conversions of the schema 5 to 6 step, if it ran.
    entries :: ![UpgradeReportEntry],
    -- | Shared-write modes established after reaching schema 7, including
    -- paths that stayed unknown and why.
    certification :: ![SharedWriteReportEntry],
    -- | The recorded releases fetched from their remotes to establish that
    -- evidence, because no installed copy was the recorded version.
    evidenceSources :: ![EvidenceSource],
    upgradedDocument :: !Aeson.Value
  }
  deriving stock (Eq, Show, Generic)

-- | One path's shared-write outcome, with any gap already rendered.
data SharedWriteReportEntry = SharedWriteReportEntry
  { path :: !FilePath,
    previousMode :: !SharedWriteMode,
    certifiedMode :: !SharedWriteMode,
    reasons :: ![Text]
  }
  deriving stock (Eq, Show, Generic)

sharedWriteReportEntry :: Manifest -> SharedWriteCertificationEntry -> SharedWriteReportEntry
sharedWriteReportEntry manifest entry =
  SharedWriteReportEntry
    { path = entry ^. #path,
      previousMode = entry ^. #previousMode,
      certifiedMode = entry ^. #certifiedMode,
      reasons = map (renderCertificationGap manifest) (entry ^. #gaps)
    }

stepReport :: ManifestUpgradeStep -> UpgradeStepReport
stepReport step =
  UpgradeStepReport
    { fromVersion = step ^. #fromVersion,
      toVersion = step ^. #toVersion,
      kind = upgradeStepKind (step ^. #action),
      summary = step ^. #summary
    }

-- | Convert a legacy manifest straight to schema 6. Pure given the
-- inferences, so the report and the resulting bytes can both be asserted on
-- without a filesystem. The steps below 5 only stamp the version, so they
-- are reported but need no transform here.
applyUpgrade :: LegacyManifest -> [(LegacyRef, InferenceOutcome)] -> UpgradeResult
applyUpgrade legacy conversions =
  UpgradeResult
    { fromVersion = source,
      toVersion = oldestDecodableManifestVersion,
      steps = either (const []) (map stepReport) (planManifestUpgrade source oldestDecodableManifestVersion),
      entries = reportEntries,
      certification = [],
      evidenceSources = [],
      upgradedDocument = document
    }
  where
    source = ManifestSchemaVersion (legacy ^. #schemaVersion)
    (reportEntries, document) = convertMachineLocalPaths legacy conversions

-- | The schema 5 to 6 step: each reference's recorded path is deleted and
-- the portable origin written in its place — @source@ becomes @origin@,
-- @targetSource@ becomes @targetOrigin@ — and the document is stamped
-- schema 6. Nothing else in the document is touched.
convertMachineLocalPaths :: LegacyManifest -> [(LegacyRef, InferenceOutcome)] -> ([UpgradeReportEntry], Aeson.Value)
convertMachineLocalPaths legacy conversions =
  ( dedupeEntries (map reportEntry conversions),
    setDocumentSchemaVersion oldestDecodableManifestVersion (foldl' rewrite (legacy ^. #document) conversions)
  )
  where
    rewrite document (ref, outcome) =
      replaceAt (ref ^. #jsonPointer) (Aeson.toJSON (inferredOrigin outcome)) document

    reportEntry (ref, outcome) =
      UpgradeReportEntry
        { artifactName = ref ^. #artifactName,
          legacyPath = ref ^. #legacyPath,
          outcome = outcome
        }

-- | One line per distinct artifact-and-path pair, in first-seen order.
--
-- The same module typically appears three times — once in @modules@, once as
-- an application's target, once as an instance — and the report should show it
-- once. Two records naming the same artifact at /different/ paths stay
-- separate, because that is a real thing the developer should see.
dedupeEntries :: [UpgradeReportEntry] -> [UpgradeReportEntry]
dedupeEntries = go []
  where
    go _ [] = []
    go seen (entry : rest)
      | key entry `elem` seen = go seen rest
      | otherwise = entry : go (key entry : seen) rest

    key entry = (entry ^. #artifactName, entry ^. #legacyPath)

-- | Replace the key at the end of a pointer with its portable counterpart.
replaceAt :: [Text] -> Aeson.Value -> Aeson.Value -> Aeson.Value
replaceAt [] _ document = document
replaceAt pointer origin document =
  updateAt (init pointer) (renameKey (last pointer)) document
  where
    renameKey legacyKey (Aeson.Object fields) =
      Aeson.Object
        ( KeyMap.insert
            (Key.fromText (portableKey legacyKey))
            origin
            (KeyMap.delete (Key.fromText legacyKey) fields)
        )
    renameKey _ other = other

-- | The schema-6 name of a key that used to hold an absolute path.
portableKey :: Text -> Text
portableKey "source" = "origin"
portableKey "targetSource" = "targetOrigin"
portableKey other = other

-- | Apply a function to the value a pointer names, leaving the document
-- unchanged when the pointer does not lead anywhere.
updateAt :: [Text] -> (Aeson.Value -> Aeson.Value) -> Aeson.Value -> Aeson.Value
updateAt [] f value = f value
updateAt (step : rest) f value = case value of
  Aeson.Object fields ->
    let name = Key.fromText step
     in case KeyMap.lookup name fields of
          Just child -> Aeson.Object (KeyMap.insert name (updateAt rest f child) fields)
          Nothing -> value
  Aeson.Array elements ->
    case readMaybe (T.unpack step) of
      Just index
        | index >= 0 && index < V.length elements ->
            Aeson.Array (elements V.// [(index, updateAt rest f (elements V.! index))])
      _ -> value
  _ -> value

-- | Render the upgrade account shown in the terminal, without the closing
-- line — whether the file was written is the caller's news to deliver.
--
-- Steps are listed in the order they ran; the origin conversions sit under
-- the 5 to 6 step that made them, and the shared-write evidence follows the
-- steps because it is established once the document can record it.
formatUpgradeReport :: UpgradeResult -> Text
formatUpgradeReport result =
  T.unlines (header : "" : concatMap stepLines (result ^. #steps) <> certificationLines)
  where
    header =
      "Reading "
        <> T.pack manifestRelativePath
        <> " (schema version "
        <> showVersion (result ^. #fromVersion)
        <> ")"

    stepLines step =
      [ "  "
          <> showVersion (step ^. #fromVersion)
          <> " -> "
          <> showVersion (step ^. #toVersion)
          <> "  "
          <> step ^. #summary
          <> (if step ^. #kind == InferenceBearingUpgrade then "  (inferred; review before committing)" else "")
      ]
        <> ( if step ^. #toVersion == oldestDecodableManifestVersion
               then "" : concatMap entryLines (result ^. #entries)
               else []
           )

    nameColumn =
      maximum (5 : map (T.length . (^. #artifactName)) (result ^. #entries)) + 5

    entryLines entry =
      [ "  " <> T.justifyLeft nameColumn ' ' (entry ^. #artifactName) <> T.pack (entry ^. #legacyPath),
        T.replicate (nameColumn - 1) " " <> "→  " <> describeOutcome (entry ^. #outcome)
      ]
        <> map (\note -> T.replicate (nameColumn + 2) " " <> note) (outcomeNotes entry)
        <> [""]

    describeOutcome outcome = case inferredOrigin outcome of
      RemoteOrigin url _ _ -> "remote " <> url
      ProjectOrigin path -> "project " <> T.pack path
      LocalOrigin name -> "local " <> name <> "  (no upstream recorded)"

    outcomeNotes entry = case entry ^. #outcome of
      InferredAsUnverifiable _
        | legacyPathWasInstalled (entry ^. #legacyPath) ->
            [ "was installed from an upstream on the original machine, but no",
              "local copy is available here to recover the URL"
            ]
      _ -> []

    certificationLines = case result ^. #certification of
      [] -> []
      entries ->
        ""
          : "  shared-write evidence"
          : concatMap certificationEntryLines entries
            <> [ "    (" <> renderEvidenceSource source <> ")"
               | source <- result ^. #evidenceSources
               ]

    pathColumn =
      maximum (5 : map (T.length . T.pack . (^. #path)) (result ^. #certification)) + 2

    certificationEntryLines entry =
      ( "  "
          <> T.justifyLeft pathColumn ' ' (T.pack (entry ^. #path))
          <> ( if entry ^. #previousMode == entry ^. #certifiedMode
                 then sharedWriteModeToText (entry ^. #certifiedMode) <> " (unchanged)"
                 else sharedWriteModeToText (entry ^. #previousMode) <> " -> " <> sharedWriteModeToText (entry ^. #certifiedMode)
             )
      )
        : [ T.replicate (pathColumn + 4) " " <> gapText
          | gapText <- entry ^. #reasons
          ]

showVersion :: ManifestSchemaVersion -> Text
showVersion (ManifestSchemaVersion v) = T.pack (show v)

-- ----------------------------------------------------------------------------
-- The command
-- ----------------------------------------------------------------------------

-- | Where a project's manifest lives, relative to the project root. Also the
-- name the report prints, so the two can never drift apart.
manifestRelativePath :: FilePath
manifestRelativePath = ".seihou" </> "manifest.json"

-- | Flags parsed for @seihou manifest upgrade@.
data ManifestUpgradeOpts = ManifestUpgradeOpts
  { dryRun :: !Bool,
    -- | Write even when the converted manifest names artifacts this machine
    -- cannot satisfy. For the developer who is upgrading a manifest on a
    -- machine that deliberately does not have every artifact installed.
    -- Only the inference-bearing 5 to 6 step consults it.
    force :: !Bool,
    -- | Stop at this schema. 'Nothing' means the current schema.
    targetVersion :: !(Maybe ManifestSchemaVersion)
  }
  deriving stock (Eq, Show, Generic)

-- | Terminal outcome of an upgrade run, decoupled from printing and exit codes
-- so it can be asserted on directly.
data UpgradeOutcome
  = -- | Nothing to change: the document is at the requested schema and no
    -- shared-write evidence could be added. Carries the schema and every path
    -- that is still unknown, with why.
    UpgradeNotNeeded !ManifestSchemaVersion ![SharedWriteReportEntry]
  | -- | @--dry-run@: the document was upgraded and thrown away. Carries any
    -- check that would have blocked a real write.
    UpgradeWouldWrite UpgradeResult ![ArtifactCheck]
  | -- | The upgraded document was written over the manifest.
    UpgradeWritten UpgradeResult
  | -- | The path conversion succeeded but writing it would leave the project
    -- naming artifacts this machine cannot satisfy, so nothing was written
    -- and no later step ran.
    UpgradeBlocked UpgradeResult ![ArtifactCheck]
  | -- | Nothing was written; carries the message to show the user.
    UpgradeFailed Text
  deriving stock (Eq, Show, Generic)

-- | Testable core of @seihou manifest upgrade@: read the manifest in the
-- current directory, run each adjacent step up to the requested schema,
-- establish shared-write evidence once the document can record it, and —
-- unless this is a dry run — write the result back.
runManifestUpgrade :: ManifestUpgradeOpts -> IO UpgradeOutcome
runManifestUpgrade opts = do
  projectRoot <- getCurrentDirectory
  let manifestPath = projectRoot </> manifestRelativePath
  present <- doesFileExist manifestPath
  if not present
    then
      pure
        ( UpgradeFailed
            ( "No "
                <> T.pack manifestRelativePath
                <> " here. Run this from the root of a project seihou has generated into."
            )
        )
    else do
      bytes <- LBS.readFile manifestPath
      case Aeson.eitherDecode bytes >>= \document -> first (T.unpack . renderManifestUpgradeError) ((document,) <$> documentSchemaVersion document) of
        Left err -> pure (UpgradeFailed (T.pack manifestRelativePath <> " could not be read: " <> T.pack err))
        Right (document, source) -> do
          let target = fromMaybe currentManifestVersion (opts ^. #targetVersion)
          case planManifestUpgrade source target of
            Left err -> pure (UpgradeFailed (renderManifestUpgradeError err))
            Right steps -> do
              searchPaths <- defaultSearchPaths
              chained <- runSteps projectRoot searchPaths source document steps
              case chained of
                Left err -> pure (UpgradeFailed err)
                Right (result, blocking)
                  | not (null blocking) ->
                      pure $
                        if opts ^. #dryRun
                          then UpgradeWouldWrite result blocking
                          else UpgradeBlocked result blocking
                  | otherwise -> do
                      -- A co-owner whose recorded release is no longer
                      -- installed is read from its recorded remote into this
                      -- temporary directory, never into the install cache.
                      certified <-
                        withSystemTempDirectory "seihou-manifest-upgrade" $ \session ->
                          certifyDocument (FetchRecordedReleases session) projectRoot searchPaths result
                      case certified of
                        Left err -> pure (UpgradeFailed err)
                        Right final
                          | null (final ^. #steps) && not (any changed (final ^. #certification)) ->
                              pure (UpgradeNotNeeded (final ^. #toVersion) (final ^. #certification))
                          | opts ^. #dryRun -> pure (UpgradeWouldWrite final [])
                          | otherwise -> do
                              writeDocument manifestPath (final ^. #upgradedDocument)
                              pure (UpgradeWritten final)
  where
    runSteps projectRoot searchPaths source document =
      go
        UpgradeResult
          { fromVersion = source,
            toVersion = source,
            steps = [],
            entries = [],
            certification = [],
            evidenceSources = [],
            upgradedDocument = document
          }
      where
        go result [] = pure (Right (result, []))
        go result (step : rest) = do
          ran <- runStep projectRoot searchPaths step (result ^. #upgradedDocument)
          case ran of
            Left err -> pure (Left err)
            Right (conversions, next, blocking) -> do
              let advanced =
                    result
                      & #steps
                      %~ (<> [stepReport step])
                      & #entries
                      %~ (<> conversions)
                      & #toVersion
                      .~ (step ^. #toVersion)
                      & #upgradedDocument
                      .~ next
              if null blocking
                then go advanced rest
                else pure (Right (advanced, blocking))

    runStep projectRoot searchPaths step document = case step ^. #action of
      ConvertMachineLocalPaths -> do
        let legacy =
              LegacyManifest
                { schemaVersion = step ^. #fromVersion . #unManifestSchemaVersion,
                  document = document,
                  refs = collectRefs document
                }
        conversions <-
          traverse
            (\ref -> (ref,) <$> inferOriginFromLegacyPath projectRoot searchPaths ref)
            (legacy ^. #refs)
        let (reported, converted) = convertMachineLocalPaths legacy conversions
        case validateDocument converted of
          Left err -> pure (Left err)
          Right manifest -> do
            blocking <-
              if opts ^. #force
                then pure []
                else blockingChecks <$> checkAppliedArtifacts projectRoot searchPaths manifest
            pure (Right (reported, converted, blocking))
      _ -> case applyLosslessUpgradeStep step document of
        Left err -> pure (Left (renderManifestUpgradeError err))
        Right next
          | step ^. #toVersion >= oldestDecodableManifestVersion ->
              pure ((\_ -> ([], next, [])) <$> validateDocument next)
          | otherwise -> pure (Right ([], next, []))

    -- Evidence is established only once the document is at a schema that
    -- can record every answer, which is exactly the capability that needs it.
    certifyDocument policy projectRoot searchPaths result
      | result ^. #toVersion < oldestDecodableManifestVersion = pure (Right result)
      | otherwise = case validateDocument (result ^. #upgradedDocument) of
          Left err -> pure (Left err)
          Right manifest
            | not (manifestSupports TargetedAdditiveSharedPathUpdate manifest) -> pure (Right result)
            | otherwise -> do
                certification <-
                  certifySharedWriteModesIO policy projectRoot searchPaths CertifyAllUnknownPaths manifest Map.empty
                let document =
                      foldl'
                        (\current entry -> setRecordedSharedWriteMode (entry ^. #path) (entry ^. #certifiedMode) current)
                        (result ^. #upgradedDocument)
                        (certifiedChanges certification)
                    reported = map (sharedWriteReportEntry manifest) (certification ^. #entries)
                    certified =
                      result
                        & #certification
                        .~ reported
                        & #evidenceSources
                        .~ (certification ^. #fetchedSources)
                        & #upgradedDocument
                        .~ document
                pure (certified <$ validateDocument document)

    changed entry = entry ^. #previousMode /= entry ^. #certifiedMode

-- | Set one file record's @sharedWriteMode@ in a schema-7 raw document,
-- leaving every other member alone.
setRecordedSharedWriteMode :: FilePath -> SharedWriteMode -> Aeson.Value -> Aeson.Value
setRecordedSharedWriteMode path mode =
  updateAt ["files", T.pack path] $ \case
    Aeson.Object record ->
      Aeson.Object (KeyMap.insert "sharedWriteMode" (Aeson.String (sharedWriteModeToText mode)) record)
    other -> other

-- | Decode a document with the ordinary manifest decoder, which turns every
-- write into a correctness check: whatever is about to land on disk is
-- proven readable by every command that will read it.
validateDocument :: Aeson.Value -> Either Text Manifest
validateDocument document =
  case Aeson.fromJSON document of
    Aeson.Error err ->
      Left
        ( "The upgraded manifest is not one this build can read, so nothing was\n\
          \written. This is a bug in 'seihou manifest upgrade'; please report it.\n\n\
          \  "
            <> T.pack err
        )
    Aeson.Success manifest -> Right manifest

-- | Write the converted document, atomically.
--
-- The bytes are the rewritten 'Aeson.Value' rather than a re-encoded
-- 'Manifest', so any field this build does not know about survives the round
-- trip. That rules out reusing 'Seihou.Effect.ManifestStore.writeManifest',
-- which encodes a typed manifest, so the write-to-temp-then-rename it performs
-- is replicated here.
writeDocument :: FilePath -> Aeson.Value -> IO ()
writeDocument manifestPath document = do
  let temporaryPath = manifestPath <> ".tmp"
  LBS.writeFile temporaryPath (Aeson.encode document)
  renamePath temporaryPath manifestPath

-- | Explain why an upgrade this machine cannot satisfy was not written.
--
-- The blocking verdicts are the guard's, but the remedy is this command's, so
-- the wording is here rather than reusing
-- 'Seihou.CLI.ManifestGuard.formatGuardRefusal' — that one ends by naming
-- @--allow-downgrade@, which is a flag on @seihou run@ and @seihou migrate@,
-- not on this command.
formatUpgradeRefusal :: Text -> [ArtifactCheck] -> Text
formatUpgradeRefusal leadIn checks =
  T.unlines $
    [leadIn, ""]
      <> ["  " <> summary | Just summary <- map summarizeCheck checks]
      <> [ "",
           "Upgrading now would record what this machine can see rather than what",
           "the project uses: an artifact that is missing or stale here converts to",
           "an origin seihou had to guess at, and that guess would be committed.",
           "",
           "Install or upgrade the artifacts above and run this again, or re-run",
           "with --force to accept the conversions exactly as shown."
         ]

-- | Print the outcome and exit non-zero on failure.
handleManifestUpgrade :: ManifestUpgradeOpts -> IO ()
handleManifestUpgrade opts = do
  outcome <- runManifestUpgrade opts
  TIO.putStr (renderUpgradeOutcome outcome)
  case outcome of
    UpgradeBlocked {} -> exitFailure
    UpgradeFailed {} -> exitFailure
    _ -> pure ()

-- | Everything @seihou manifest upgrade@ prints for an outcome, exactly as
-- the command prints it. Pure, so a reader other than the command (the
-- upgrade diagnosis behind @seihou agent upgrade@) can show the same report.
renderUpgradeOutcome :: UpgradeOutcome -> Text
renderUpgradeOutcome = \case
  UpgradeNotNeeded version stillUnknown ->
    ( "✓ "
        <> T.pack manifestRelativePath
        <> " is already at schema version "
        <> showVersion version
        <> "; nothing to do.\n"
    )
      <> (if null stillUnknown then "" else formatStillUnknown stillUnknown)
  UpgradeWouldWrite result blocking ->
    formatUpgradeReport result
      <> (if null blocking then "" else formatUpgradeRefusal "! Without --force, this upgrade would be refused." blocking)
      <> "--dry-run: nothing was written.\n"
  UpgradeBlocked result blocking ->
    formatUpgradeReport result
      <> formatUpgradeRefusal
        ("✗ Refusing to write " <> T.pack manifestRelativePath <> ".")
        blocking
  UpgradeWritten result ->
    formatUpgradeReport result
      <> ( "✓ Upgraded "
             <> T.pack manifestRelativePath
             <> " to schema version "
             <> showVersion (result ^. #toVersion)
             <> ".\n"
         )
      <> ("  Review the diff and commit it: git diff " <> T.pack manifestRelativePath <> "\n")
  UpgradeFailed message -> message <> "\n"

-- | The paths an up-to-date manifest still cannot answer for, and why.
formatStillUnknown :: [SharedWriteReportEntry] -> Text
formatStillUnknown entries =
  T.unlines $
    [ "",
      "  The shared-write mode of these paths is still unknown, so a targeted",
      "  update that leaves one of their owners out will be refused:"
    ]
      <> concat
        [ ("    " <> T.pack (entry ^. #path)) : ["      " <> reason | reason <- entry ^. #reasons]
        | entry <- entries,
          entry ^. #certifiedMode == SharedWriteUnknown
        ]

-- ----------------------------------------------------------------------------
-- Small JSON accessors
-- ----------------------------------------------------------------------------

-- | Pair every element of a list with its index, rendered as the text an
-- array position takes inside a pointer.
withIndices :: [a] -> [(Text, a)]
withIndices = zip (map (T.pack . show) [(0 :: Int) ..])

objectAt :: Aeson.Value -> Key -> Maybe Aeson.Value
objectAt (Aeson.Object fields) name = KeyMap.lookup name fields
objectAt _ _ = Nothing

textAt :: Aeson.Value -> Key -> Maybe Text
textAt value name = case objectAt value name of
  Just (Aeson.String text) -> Just text
  _ -> Nothing

arrayAt :: Aeson.Value -> Key -> [Aeson.Value]
arrayAt value name = case objectAt value name of
  Just (Aeson.Array elements) -> toList elements
  _ -> []
