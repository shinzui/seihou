-- | @seihou manifest repair-origins@: rewrite origins recorded as a path on
-- the machine that wrote them.
--
-- @.seihou\/manifest.json@ is checked in and must mean the same thing on every
-- machine (docs\/adr\/0001-manifest-is-a-checked-in-machine-independent-artifact.md).
-- Before plan 98, @seihou install \<local checkout\>@ stored the checkout's
-- path as the installed copy's @sourceUrl@, and every command that records
-- applied state copied it into the manifest as a 'RemoteOrigin'. Once the
-- artifact was reinstalled from its real remote, the guard reported an
-- origin mismatch that no command could clear. 'detectArtifactOrigin' no
-- longer lets a path through, but manifests written before that still hold
-- one. This command finds them, proposes a remote for each with the evidence
-- for it, and rewrites them.
--
-- Choosing a remote for a recorded path is inference, so the command is
-- explicit and prints everything it concludes, as
-- docs\/adr\/0005-legacy-manifests-convert-through-an-explicit-command.md
-- requires. It rewrites by URL rather than by record: every origin recorded
-- under one path gets the same new URL, because blueprint migration receipts
-- use the origin as part of their identity (docs\/adr\/0002) and rewriting
-- some records for a path but not others would split one artifact in two.
--
-- The core ('localOriginUrls', 'planRepair', 'applyRepair',
-- 'renderRepairOutcome') is pure. 'gatherOriginEvidence' and
-- 'runRepairOrigins' are the IO shell.
module Seihou.CLI.ManifestRepairOrigins
  ( -- * Options and outcome
    RepairOriginsOpts (..),
    RepairOutcome (..),

    -- * Sites, evidence, decisions
    SiteKind (..),
    OriginSite (..),
    OriginEvidence (..),
    RepairDecision (..),
    evidenceUrl,

    -- * Pure core
    localOriginUrls,
    validateOverrides,
    planRepair,
    applyRepair,
    overManifestOrigins,
    sameRepository,

    -- * IO shell
    gatherOriginEvidence,
    runRepairOrigins,
    renderRepairOutcome,
    handleRepairOrigins,
  )
where

import Control.Applicative ((<|>))
import Control.Monad (when)
import Data.Aeson qualified as Aeson
import Data.Aeson.Types (parseMaybe, (.:))
import Data.ByteString.Lazy qualified as LBS
import Data.Char (isDigit, toLower)
import Data.Generics.Labels ()
import Data.List (nub, nubBy)
import Data.Map.Strict qualified as Map
import Data.Maybe (mapMaybe)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.ApplicationDisplay (appliedModuleLabel, appliedTargetName, moduleNameText)
import Seihou.CLI.InstallShared (expandLocalPath)
import Seihou.Core.ArtifactIdentity (isMachineLocalOriginUrl, normalizeOriginUrl)
import Seihou.Core.ArtifactOriginDetect (readOriginInfo)
import Seihou.Core.ArtifactRef (resolveArtifactOrigin)
import Seihou.Core.Module (defaultSearchPaths)
import Seihou.Core.Types
  ( AppliedTarget (..),
    ArtifactOrigin (..),
    Manifest,
    ManifestSchemaVersion (..),
  )
import Seihou.Manifest.Types (currentManifestVersion, manifestFromJSON, manifestToJSON)
import Seihou.Prelude
import System.Directory (doesDirectoryExist, doesFileExist, getCurrentDirectory, renamePath)
import System.Exit (ExitCode (..), exitFailure)
import System.Process (readProcessWithExitCode)

-- ----------------------------------------------------------------------------
-- Types
-- ----------------------------------------------------------------------------

-- | Flags parsed for @seihou manifest repair-origins@.
data RepairOriginsOpts = RepairOriginsOpts
  { -- | Print the report without writing the manifest.
    dryRun :: !Bool,
    -- | @--set NAME=URL@, in order: the remote for the path under which the
    -- artifact @NAME@ is recorded.
    overrides :: ![(Text, Text)]
  }
  deriving stock (Eq, Show, Generic)

-- | Which of the six origin-bearing manifest records a site is.
data SiteKind
  = SiteModule
  | SiteApplicationTarget
  | SiteApplicationInstance
  | SiteRecipe
  | SiteBlueprint
  | SiteBlueprintMigration
  deriving stock (Eq, Ord, Show, Generic)

-- | One manifest record whose origin is a machine-local path.
data OriginSite = OriginSite
  { kind :: !SiteKind,
    -- | Where the record is, for the report, e.g. @modules[nix-haskell-flake]@.
    location :: !Text,
    -- | The URL exactly as recorded, before normalisation.
    recordedUrl :: !Text,
    artifactName :: !Text,
    repoName :: !(Maybe Text),
    -- | The file that makes a directory count as this kind of artifact, used
    -- to find its installed copy.
    definitionFile :: !FilePath
  }
  deriving stock (Eq, Show, Generic)

-- | Why a remote is proposed for a recorded path.
data OriginEvidence
  = -- | The recorded path is a checkout on this machine whose @origin@ remote
    -- is this URL.
    FromCheckoutRemote !Text
  | -- | The installed copy of this artifact records this URL, and its
    -- repository name agrees with the manifest's. Fields: artifact name,
    -- URL, repository name.
    FromInstalledCopy !Text !Text !(Maybe Text)
  | -- | The user passed @--set NAME=URL@. Fields: artifact name, URL.
    FromOverride !Text !Text
  deriving stock (Eq, Show, Generic)

-- | What to do about one recorded path.
data RepairDecision
  = -- | Rewrite every origin recorded under the path. Fields: the path as
    -- recorded, the new URL, the evidence, the records affected.
    Rewrite !Text !Text ![OriginEvidence] ![OriginSite]
  | -- | The evidence names more than one repository; nothing is written for
    -- this path.
    Conflicting !Text ![OriginEvidence] ![OriginSite]
  | -- | Nothing on this machine suggests a remote.
    Unresolved !Text ![OriginSite]
  deriving stock (Eq, Show, Generic)

-- | Terminal outcome of a run, decoupled from printing and exit codes so it
-- can be asserted on directly.
data RepairOutcome
  = -- | No origin is recorded as a machine-local path.
    RepairNotNeeded
  | -- | @--dry-run@: the decisions a real run would carry out.
    RepairWouldWrite ![RepairDecision]
  | -- | The manifest was rewritten according to these decisions.
    RepairWritten ![RepairDecision]
  | -- | Not a dry run, but no path had a remote to rewrite to, so the manifest
    -- was left alone.
    RepairUnwritten ![RepairDecision]
  | -- | Nothing was written; carries the message to show the user.
    RepairFailed !Text
  deriving stock (Eq, Show, Generic)

-- | The URL a piece of evidence proposes.
evidenceUrl :: OriginEvidence -> Text
evidenceUrl = \case
  FromCheckoutRemote url -> url
  FromInstalledCopy _ url _ -> url
  FromOverride _ url -> url

-- ----------------------------------------------------------------------------
-- Pure core
-- ----------------------------------------------------------------------------

-- | Every record whose origin is a 'RemoteOrigin' with a machine-local URL,
-- grouped by the normalised URL, in manifest order within each group.
localOriginUrls :: Manifest -> Map Text [OriginSite]
localOriginUrls manifest =
  Map.fromListWith
    (\later earlier -> earlier <> later)
    [ (normalizeOriginUrl (site ^. #recordedUrl), [site])
    | site <- allSites,
      isMachineLocalOriginUrl (site ^. #recordedUrl)
    ]
  where
    allSites =
      mapMaybe moduleSite (manifest ^. #modules)
        <> concatMap applicationSites (manifest ^. #applications)
        <> maybe [] (maybe [] pure . recipeSite) (manifest ^. #recipe)
        <> maybe [] (maybe [] pure . blueprintSite) (manifest ^. #blueprint)
        <> mapMaybe migrationSite (manifest ^. #blueprintMigrations)

    moduleSite applied =
      site SiteModule ("modules[" <> appliedModuleLabel applied <> "]") "module.dhall" (applied ^. #origin)

    applicationSites application =
      let targetName = appliedTargetName (application ^. #target)
          targetDefinition = case application ^. #target of
            AppliedModuleTarget _ -> "module.dhall"
            AppliedRecipeTarget _ -> "recipe.dhall"
          instanceSite state =
            site
              SiteApplicationInstance
              ( "applications["
                  <> targetName
                  <> "].instances["
                  <> moduleNameText (state ^. #name)
                  <> "]"
              )
              "module.dhall"
              (state ^. #origin)
       in maybe [] pure (site SiteApplicationTarget ("applications[" <> targetName <> "]") targetDefinition (application ^. #targetOrigin))
            <> mapMaybe instanceSite (application ^. #instances)

    recipeSite applied =
      site SiteRecipe ("recipe[" <> applied ^. #name . #unRecipeName <> "]") "recipe.dhall" (applied ^. #origin)

    blueprintSite applied =
      site SiteBlueprint ("blueprint[" <> moduleNameText (applied ^. #name) <> "]") "blueprint.dhall" (applied ^. #origin)

    migrationSite receipt =
      site
        SiteBlueprintMigration
        ( "blueprintMigrations["
            <> moduleNameText (receipt ^. #name)
            <> " "
            <> receipt ^. #fromVersion
            <> "->"
            <> receipt ^. #toVersion
            <> "]"
        )
        "blueprint.dhall"
        (receipt ^. #origin)

    site siteKind loc definition = \case
      RemoteOrigin url name repo ->
        Just
          OriginSite
            { kind = siteKind,
              location = loc,
              recordedUrl = url,
              artifactName = name,
              repoName = repo,
              definitionFile = definition
            }
      _ -> Nothing

-- | Check @--set@ overrides before anything is planned. A URL that is itself
-- a machine-local path would reproduce the problem being repaired, and a name
-- recorded under no local path is almost certainly a typo.
validateOverrides :: Map Text [OriginSite] -> [(Text, Text)] -> Either Text ()
validateOverrides sites overrides =
  case (localOverrides, unknownNames) of
    ((name, url) : _, _) ->
      Left
        ( "--set "
            <> name
            <> "="
            <> url
            <> ": "
            <> url
            <> " is a path on this machine, which is what this command removes.\n"
            <> "Give the URL other developers clone the artifact from."
        )
    ([], name : _) ->
      Left
        ( "--set "
            <> name
            <> "=...: no origin recorded as a machine-local path names "
            <> name
            <> ".\nRecorded under local paths: "
            <> T.intercalate ", " (nub [s ^. #artifactName | s <- concat (Map.elems sites)])
        )
    ([], []) -> Right ()
  where
    localOverrides = filter (isMachineLocalOriginUrl . snd) overrides
    recordedNames = [s ^. #artifactName | s <- concat (Map.elems sites)]
    unknownNames = [name | (name, _) <- overrides, name `notElem` recordedNames]

-- | Decide, for each recorded path, what to rewrite it to.
--
-- An override for any artifact recorded under the path wins over evidence.
-- Otherwise the evidence must agree on one repository ('sameRepository', so
-- an @ssh@ checkout remote and an @https@ install of the same repository
-- agree). The URL written is the installed copy's spelling when there is one,
-- because that is what the guard compares the manifest against on this
-- machine; otherwise the checkout remote's.
planRepair :: Map Text [OriginSite] -> Map Text [OriginEvidence] -> [(Text, Text)] -> [RepairDecision]
planRepair sites evidence overrides =
  [ decide key siteList
  | (key, siteList) <- Map.toList sites,
    not (null siteList)
  ]
  where
    decide key siteList =
      let old = recordedAs siteList
          names = map (^. #artifactName) siteList
          overriding = [FromOverride name url | (name, url) <- overrides, name `elem` names]
          gathered = Map.findWithDefault [] key evidence
       in case overriding of
            (chosen : _)
              | agrees overriding -> Rewrite old (evidenceUrl chosen) (overriding <> gathered) siteList
              | otherwise -> Conflicting old overriding siteList
            []
              | null gathered -> Unresolved old siteList
              | agrees gathered -> Rewrite old (preferredUrl gathered) gathered siteList
              | otherwise -> Conflicting old gathered siteList

    recordedAs siteList = case siteList of
      (first' : _) -> first' ^. #recordedUrl
      [] -> ""

    agrees items = case map evidenceUrl items of
      [] -> True
      (url : rest) -> all (sameRepository url) rest

    preferredUrl items =
      case [url | FromInstalledCopy _ url _ <- items] <> map evidenceUrl items of
        (url : _) -> url
        [] -> ""

-- | Rewrite every origin whose normalised URL is the old path of a
-- 'Rewrite'. The artifact name is kept; a missing repository name is filled
-- in from an installed copy that supplied the new URL.
applyRepair :: [RepairDecision] -> Manifest -> Manifest
applyRepair decisions = overManifestOrigins rewrite
  where
    table =
      Map.fromList
        [ (normalizeOriginUrl old, (new, repoFrom new evidence))
        | Rewrite old new evidence _ <- decisions
        ]

    repoFrom new evidence =
      case [repo | FromInstalledCopy _ url (Just repo) <- evidence, sameRepository url new] of
        (repo : _) -> Just repo
        [] -> Nothing

    rewrite origin = case origin of
      RemoteOrigin url name repo
        | isMachineLocalOriginUrl url,
          Just (new, evidenceRepo) <- Map.lookup (normalizeOriginUrl url) table ->
            RemoteOrigin new name (repo <|> evidenceRepo)
      _ -> origin

-- | Apply a function to every origin the manifest records, across all six
-- origin-bearing record kinds.
overManifestOrigins :: (ArtifactOrigin -> ArtifactOrigin) -> Manifest -> Manifest
overManifestOrigins f manifest =
  manifest
    & #modules
    . traverse
    . #origin
    %~ f
    & #applications
    . traverse
    . #targetOrigin
    %~ f
    & #applications
    . traverse
    . #instances
    . traverse
    . #origin
    %~ f
    & #recipe
    . _Just
    . #origin
    %~ f
    & #blueprint
    . _Just
    . #origin
    %~ f
    & #blueprintMigrations
    . traverse
    . #origin
    %~ f

-- | Whether two git URLs name the same repository regardless of transport:
-- @git\@github.com:o\/r.git@, @ssh:\/\/git\@github.com\/o\/r@ and
-- @https:\/\/github.com\/o\/r.git@ all agree.
sameRepository :: Text -> Text -> Bool
sameRepository left right = repositoryKey left == repositoryKey right

repositoryKey :: Text -> Text
repositoryKey raw =
  let url = normalizeOriginUrl raw
      (schemeless, hadScheme) = case T.breakOn "://" url of
        (_, rest) | not (T.null rest) -> (T.drop 3 rest, True)
        _ -> (url, False)
      withoutUser = case T.breakOn "@" schemeless of
        (_, rest)
          | not (T.null rest),
            not (T.isInfixOf "/" (T.takeWhile (/= '@') schemeless)) ->
              T.drop 1 rest
        _ -> schemeless
      (host, path) =
        if hadScheme
          then T.breakOn "/" withoutUser
          else case T.breakOn ":" withoutUser of
            (h, rest)
              | not (T.null rest),
                not (T.isInfixOf "/" h) ->
                  (h, "/" <> T.drop 1 rest)
            _ -> T.breakOn "/" withoutUser
      hostWithoutPort = case T.breakOn ":" host of
        (h, port) | not (T.null port), T.all isDigit (T.drop 1 port) -> h
        _ -> host
   in T.map toLower hostWithoutPort <> "/" <> T.dropWhile (== '/') path

-- ----------------------------------------------------------------------------
-- IO shell
-- ----------------------------------------------------------------------------

-- | For each recorded path, what this machine can observe about its remote:
-- the path's own @origin@ remote if the checkout still exists here, and the
-- remote recorded by the installed copy of each artifact recorded under it.
gatherOriginEvidence :: FilePath -> [FilePath] -> Map Text [OriginSite] -> IO (Map Text [OriginEvidence])
gatherOriginEvidence projectRoot searchPaths = traverse gatherFor
  where
    gatherFor siteList = do
      fromCheckout <- concat <$> traverse checkoutRemote (nub (map (^. #recordedUrl) siteList))
      fromInstalled <- concat <$> traverse (installedCopy siteList) (nubBy sameArtifact siteList)
      pure (fromCheckout <> fromInstalled)

    sameArtifact a b =
      a ^. #artifactName == b ^. #artifactName && a ^. #definitionFile == b ^. #definitionFile

    checkoutRemote recorded = do
      dir <- expandLocalPath recorded
      exists <- doesDirectoryExist dir
      if not exists
        then pure []
        else do
          (code, out, _) <- readProcessWithExitCode "git" ["-C", dir, "remote", "get-url", "origin"] ""
          let remote = T.strip (T.pack out)
          pure
            [ FromCheckoutRemote remote
            | code == ExitSuccess,
              not (T.null remote),
              not (isMachineLocalOriginUrl remote)
            ]

    installedCopy siteList representative = do
      let name = representative ^. #artifactName
          recordedRepos = [s ^. #repoName | s <- siteList, s ^. #artifactName == name]
      located <- resolveArtifactOrigin projectRoot searchPaths (representative ^. #definitionFile) (LocalOrigin name)
      case located of
        Left _ -> pure []
        Right dir -> do
          info <- readOriginInfo dir
          pure $ case info of
            Just origin
              | not (isMachineLocalOriginUrl (origin ^. #sourceUrl)),
                all (maybe True (\repo -> Just repo == origin ^. #repoName)) recordedRepos ->
                  [FromInstalledCopy name (origin ^. #sourceUrl) (origin ^. #repoName)]
            _ -> []

-- | Where a project's manifest lives, relative to the project root.
manifestRelativePath :: FilePath
manifestRelativePath = ".seihou" </> "manifest.json"

-- | Testable core of @seihou manifest repair-origins@: read the manifest in
-- the current directory, plan a repair for every origin recorded as a
-- machine-local path, and, unless this is a dry run, write the result.
runRepairOrigins :: RepairOriginsOpts -> IO RepairOutcome
runRepairOrigins opts = do
  projectRoot <- getCurrentDirectory
  let manifestPath = projectRoot </> manifestRelativePath
  present <- doesFileExist manifestPath
  if not present
    then
      pure
        ( RepairFailed
            ( "No "
                <> T.pack manifestRelativePath
                <> " here. Run this from the root of a project seihou has generated into."
            )
        )
    else do
      bytes <- LBS.readFile manifestPath
      case readCurrentManifest bytes of
        Left message -> pure (RepairFailed message)
        Right manifest -> do
          let sites = localOriginUrls manifest
          if Map.null sites
            then pure RepairNotNeeded
            else case validateOverrides sites (opts ^. #overrides) of
              Left message -> pure (RepairFailed message)
              Right () -> do
                searchPaths <- defaultSearchPaths
                evidence <- gatherOriginEvidence projectRoot searchPaths sites
                let decisions = planRepair sites evidence (opts ^. #overrides)
                    rewrites = [d | d@Rewrite {} <- decisions]
                case () of
                  _
                    | opts ^. #dryRun -> pure (RepairWouldWrite decisions)
                    | null rewrites -> pure (RepairUnwritten decisions)
                    | otherwise -> do
                        writeManifestAtomically manifestPath (applyRepair decisions manifest)
                        pure (RepairWritten decisions)

-- | Decode a manifest at the current schema. An older schema is refused with
-- the command that upgrades it: this command works on the decoded manifest,
-- and the upgrade to the current schema is lossless.
readCurrentManifest :: LBS.ByteString -> Either Text Manifest
readCurrentManifest bytes =
  case Aeson.eitherDecode bytes of
    Left err -> Left (unreadable (T.pack err))
    Right (Aeson.Object object)
      | Just version <- parseMaybe (.: "version") object,
        ManifestSchemaVersion version /= currentManifestVersion ->
          Left
            ( T.pack manifestRelativePath
                <> " is at schema version "
                <> T.pack (show (version :: Int))
                <> "; this command needs schema version "
                <> T.pack (show (currentManifestVersion ^. #unManifestSchemaVersion))
                <> ".\nRun 'seihou manifest upgrade' first, then run this again."
            )
    Right _ -> first (unreadable . T.pack) (manifestFromJSON bytes)
  where
    unreadable err = T.pack manifestRelativePath <> " could not be read: " <> err

-- | Write to a temporary file beside the manifest, then rename over it, so an
-- interrupted run never leaves a half-written manifest.
writeManifestAtomically :: FilePath -> Manifest -> IO ()
writeManifestAtomically manifestPath manifest = do
  let temporaryPath = manifestPath <> ".tmp"
  LBS.writeFile temporaryPath (manifestToJSON manifest)
  renamePath temporaryPath manifestPath

-- | The report printed for an outcome.
renderRepairOutcome :: RepairOutcome -> Text
renderRepairOutcome = \case
  RepairNotNeeded ->
    "✓ " <> T.pack manifestRelativePath <> " records no origin as a machine-local path; nothing to repair.\n"
  RepairWouldWrite decisions ->
    renderDecisions decisions <> "--dry-run: nothing was written.\n"
  RepairWritten decisions ->
    renderDecisions decisions
      <> "✓ Rewrote "
      <> T.pack (show (length (concat [sites | Rewrite _ _ _ sites <- decisions])))
      <> " recorded origin(s) in "
      <> T.pack manifestRelativePath
      <> ".\n  Review the diff and commit it: git diff "
      <> T.pack manifestRelativePath
      <> "\n"
  RepairUnwritten decisions ->
    renderDecisions decisions <> "No recorded path had a remote to rewrite to; nothing was written.\n"
  RepairFailed message -> message <> "\n"

renderDecisions :: [RepairDecision] -> Text
renderDecisions = T.concat . map renderDecision

renderDecision :: RepairDecision -> Text
renderDecision = \case
  Rewrite old new evidence sites ->
    T.unlines $
      [old, "  -> " <> new]
        <> map (("     evidence: " <>) . describeEvidence new) evidence
        <> ["     records: " <> describeSites sites]
  Conflicting old evidence sites ->
    T.unlines $
      [old, "  ! the evidence names different repositories; nothing is written for this path"]
        <> map (("     evidence: " <>) . describeEvidence "") evidence
        <> ["     records: " <> describeSites sites, remedy sites]
  Unresolved old sites ->
    T.unlines
      [ old,
        "  ! no remote found for this path",
        "     records: " <> describeSites sites,
        remedy sites
      ]
  where
    remedy sites =
      "     pass --set "
        <> maybe "<name>" (^. #artifactName) (headMay sites)
        <> "=<url> for the artifact recorded under this path"

    headMay = \case
      (x : _) -> Just x
      [] -> Nothing

-- | One evidence line. When the evidence proposes the URL being written, it
-- says "this remote" instead of repeating it.
describeEvidence :: Text -> OriginEvidence -> Text
describeEvidence chosen evidence = case evidence of
  FromCheckoutRemote url -> "the checkout at this path has 'origin' remote " <> remote url
  FromInstalledCopy name url _ -> "the installed copy of " <> name <> " records " <> remote url
  FromOverride name url -> "--set " <> name <> "=" <> url
  where
    remote url
      | not (T.null chosen) && normalizeOriginUrl url == normalizeOriginUrl chosen = "this remote"
      | otherwise = url

-- | The records under one path: each module, application, recipe, and
-- blueprint by name, and instances and migration receipts by count.
describeSites :: [OriginSite] -> Text
describeSites sites =
  T.intercalate ", " (named <> counted SiteApplicationInstance "application instance" <> counted SiteBlueprintMigration "blueprint migration receipt")
  where
    named = nub [site ^. #location | site <- sites, site ^. #kind `notElem` [SiteApplicationInstance, SiteBlueprintMigration]]
    counted siteKind noun =
      case length (filter ((== siteKind) . (^. #kind)) sites) of
        0 -> []
        1 -> ["1 " <> noun]
        n -> [T.pack (show n) <> " " <> noun <> "s"]

-- | Print the report and exit non-zero when anything is left for the user to
-- do: a failure, or any path that could not be resolved, even when others
-- were written.
handleRepairOrigins :: RepairOriginsOpts -> IO ()
handleRepairOrigins opts = do
  outcome <- runRepairOrigins opts
  TIO.putStr (renderRepairOutcome outcome)
  when (needsAttention outcome) exitFailure
  where
    needsAttention = \case
      RepairNotNeeded -> False
      RepairFailed _ -> True
      RepairWouldWrite decisions -> any unfinished decisions
      RepairWritten decisions -> any unfinished decisions
      RepairUnwritten decisions -> any unfinished decisions
    unfinished = \case
      Rewrite {} -> False
      Conflicting {} -> True
      Unresolved {} -> True
