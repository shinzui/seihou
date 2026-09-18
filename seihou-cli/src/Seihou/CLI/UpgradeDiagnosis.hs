-- | What stands between a project and a plain @seihou update MODULE@?
--
-- @seihou agent upgrade@ answers that question before it hands a project to
-- a coding agent, and @seihou agent upgrade MODULE --check@ answers it again
-- as the definition of done. This module is the answer: a set of guarded,
-- read-only probes ('diagnoseUpgrade'), the readiness checks computed from
-- them ('readiness'), and the pure renderers for the upgrade brief and the
-- readiness report.
--
-- Two properties matter more than any single probe:
--
-- * Diagnosis never throws. Every probe runs under 'guarded' (or
--   'guardedWithin' when it can block on the network), so a missing
--   manifest, a corrupt one, or a bug in a probe becomes a finding rather
--   than an exception.
-- * Diagnosis writes nothing under the project, the install cache, or the
--   manifest. Planning an update would roll back an interrupted transaction
--   before planning, so the update probe is skipped whenever one is
--   pending; the agent performs that recovery in the open.
--
-- See docs/adr/0016-agent-assisted-upgrade-diagnoses-read-only-and-never-fails.md.
module Seihou.CLI.UpgradeDiagnosis
  ( -- * Diagnosis
    DiagnosisEnv (..),
    diagnosisEnvFor,
    Probe (..),
    ManifestState (..),
    TargetState (..),
    InstalledCopy (..),
    SharedUnknownPath (..),
    LocalOriginRecord (..),
    UpdateProbe (..),
    GitState (..),
    UpgradeDiagnosis (..),
    diagnoseUpgrade,
    emptyDiagnosis,

    -- * Readiness
    ReadinessStatus (..),
    ReadinessCheck (..),
    readiness,
    isReady,
    renderReadinessReport,

    -- * The upgrade brief
    briefSections,
    BriefLocation (..),
    createBriefDirectory,
    writeBrief,
  )
where

import Control.Concurrent (forkIO, killThread)
import Control.Concurrent.MVar (newEmptyMVar, putMVar, takeMVar)
import Control.Exception (SomeException, displayException, evaluate, try)
import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy qualified as LBS
import Data.Char (isAlphaNum, toUpper)
import Data.Generics.Labels ()
import Data.List (nub)
import Data.Map.Strict qualified as Map
import Data.Maybe (mapMaybe)
import Data.Set qualified as Set
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Time (defaultTimeLocale, formatTime, getCurrentTime)
import Seihou.CLI.ApplicationDisplay (applicationLabel)
import Seihou.CLI.CommandExecution (CommandPolicy (..))
import Seihou.CLI.ManifestGuard (ArtifactCheck (..), blockingChecks, checkAppliedArtifactsFor, localModuleVersion, summarizeCheck)
import Seihou.CLI.ManifestRepairOrigins (OriginSite (..), localOriginUrls)
import Seihou.CLI.ManifestUpgrade (ManifestUpgradeOpts (..), renderUpgradeOutcome, runManifestUpgrade)
import Seihou.CLI.Update (PromptPolicy (..), UpdateRequest (..), UpdateSelection (..), isUpdateNoOp, withProjectUpdate)
import Seihou.CLI.Update.Recovery (pendingUpdateRecovery)
import Seihou.CLI.Update.Render (errorCode, errorOutput, planOutput, renderUpdateHuman)
import Seihou.CLI.Update.Selection (MatchedApplications (..), applicationRef, matchApplications)
import Seihou.CLI.Update.Types (ApplicationRef (..), VersionChange (..))
import Seihou.Core.ArtifactRef (resolveArtifactOrigin)
import Seihou.Core.Types
import Seihou.Manifest.Types (currentManifestVersion, manifestFromJSON, oldestDecodableManifestVersion)
import Seihou.Manifest.Upgrade (documentSchemaVersion, renderManifestUpgradeError)
import Seihou.Prelude
import System.Directory qualified as Directory
import System.Exit (ExitCode (..))
import System.FilePath (takeDirectory)
import System.Process (readProcessWithExitCode)
import System.Timeout (timeout)

-- ----------------------------------------------------------------------------
-- Diagnosis
-- ----------------------------------------------------------------------------

-- | Where and how to diagnose. Search paths are passed in rather than read
-- from the environment inside a probe, so a test can point them at a
-- fixture.
data DiagnosisEnv = DiagnosisEnv
  { projectRoot :: !FilePath,
    searchPaths :: ![FilePath],
    -- | Upper bound for each probe that can reach the network, in seconds
    -- (180 in production).
    updateTimeoutSeconds :: !Int
  }
  deriving stock (Eq, Show, Generic)

-- | The production environment for a project root: the same search paths
-- 'Seihou.Core.Module.defaultSearchPaths' builds for that directory.
diagnosisEnvFor :: FilePath -> IO DiagnosisEnv
diagnosisEnvFor root = do
  xdgConfig <- Directory.getXdgDirectory Directory.XdgConfig "seihou"
  pure
    DiagnosisEnv
      { projectRoot = root,
        searchPaths =
          [ root </> ".seihou" </> "modules",
            xdgConfig </> "modules",
            xdgConfig </> "installed"
          ],
        updateTimeoutSeconds = 180
      }

-- | The outcome of one guarded probe. Never an exception.
data Probe a
  = ProbeOk !a
  | -- | The probe was not run; the reason says why.
    ProbeSkipped !Text
  | -- | The probe raised an exception; the text says which probe and what.
    ProbeFailed !Text
  | -- | The probe did not finish within this many seconds.
    ProbeTimedOut !Int
  deriving stock (Eq, Show, Generic, Functor)

data ManifestState
  = ManifestAbsent
  | ManifestNotJson !Text
  | -- | Parsed as JSON, has this schema, did not decode (for example schema 5).
    ManifestUndecodable !ManifestSchemaVersion !Text
  | -- | Parsed as JSON, but its schema version could not be read.
    ManifestSchemaUnreadable !Text
  | ManifestDecoded !ManifestSchemaVersion !Manifest
  deriving stock (Eq, Show, Generic)

data TargetState
  = -- | The matched applications, and each recorded version of the target
    -- module as @name version@.
    TargetMatched ![ApplicationRef] ![Text]
  | -- | The targets the manifest does record.
    TargetNotFound ![Text]
  | -- | The manifest records no applications: the legacy shape one
    -- targeted update seeds.
    TargetLegacyManifest
  deriving stock (Eq, Show, Generic)

-- | The installed copy of one module the upgrade concerns.
data InstalledCopy = InstalledCopy
  { name :: !Text,
    -- | Where the recorded origin resolves on this machine, if anywhere.
    directory :: !(Maybe FilePath),
    -- | The version the installed @module.dhall@ declares.
    version :: !(Maybe Text),
    -- | The version the manifest records.
    recordedVersion :: !(Maybe Text)
  }
  deriving stock (Eq, Show, Generic)

-- | A managed path the target shares with an application outside it, whose
-- shared-write mode nothing records.
data SharedUnknownPath = SharedUnknownPath
  { path :: !FilePath,
    otherOwners :: ![ApplicationRef]
  }
  deriving stock (Eq, Show, Generic)

-- | One origin URL recorded as a path on the machine that wrote it, with
-- the artifacts recorded under it.
data LocalOriginRecord = LocalOriginRecord
  { url :: !Text,
    artifacts :: ![Text]
  }
  deriving stock (Eq, Show, Generic)

-- | What @seihou update TARGET --dry-run@ said.
data UpdateProbe = UpdateProbe
  { errorCode :: !(Maybe Text),
    noOp :: !Bool,
    -- | One line naming the version changes, for the readiness report.
    headline :: !Text,
    -- | The human rendering, exactly as @seihou update@ prints it.
    rendered :: !Text
  }
  deriving stock (Eq, Show, Generic)

data GitState = GitState
  { isRepository :: !Bool,
    dirtyPaths :: ![Text]
  }
  deriving stock (Eq, Show, Generic)

data UpgradeDiagnosis = UpgradeDiagnosis
  { target :: !Text,
    projectRoot :: !FilePath,
    manifest :: !(Probe ManifestState),
    pendingRecovery :: !(Probe Bool),
    targetState :: !(Probe TargetState),
    installedCopies :: !(Probe [InstalledCopy]),
    installedChecks :: !(Probe [ArtifactCheck]),
    unknownSharedPaths :: !(Probe [SharedUnknownPath]),
    -- | Project-wide count of paths with more than one owner and an unknown
    -- shared-write mode, as context.
    projectUnknownCount :: !(Probe Int),
    localOrigins :: !(Probe [LocalOriginRecord]),
    -- | @seihou manifest upgrade --dry-run@, rendered as the command prints it.
    manifestUpgrade :: !(Probe Text),
    updateDryRun :: !(Probe UpdateProbe),
    git :: !(Probe GitState)
  }
  deriving stock (Eq, Show, Generic)

-- | A diagnosis in which nothing ran, for a caller whose diagnosis escaped
-- with an exception despite every guard.
emptyDiagnosis :: FilePath -> Text -> Text -> UpgradeDiagnosis
emptyDiagnosis root target reason =
  UpgradeDiagnosis
    { target,
      projectRoot = root,
      manifest = ProbeFailed reason,
      pendingRecovery = skipped,
      targetState = skipped,
      installedCopies = skipped,
      installedChecks = skipped,
      unknownSharedPaths = skipped,
      projectUnknownCount = skipped,
      localOrigins = skipped,
      manifestUpgrade = skipped,
      updateDryRun = skipped,
      git = skipped
    }
  where
    skipped = ProbeSkipped "the diagnosis did not run"

-- | Diagnose a project for upgrading one module. Never throws, and writes
-- nothing under the project, the install cache, or the manifest.
diagnoseUpgrade :: DiagnosisEnv -> Text -> IO UpgradeDiagnosis
diagnoseUpgrade env target = do
  let root = env ^. #projectRoot
      seconds = env ^. #updateTimeoutSeconds
  manifestProbe <- guarded "reading the manifest" (probeManifest root)
  pending <- guarded "looking for an interrupted update" (pendingUpdateRecovery root)
  let decoded = case manifestProbe of
        ProbeOk (ManifestDecoded _ recorded) -> Just recorded
        _ -> Nothing
      needsManifest :: Probe a
      needsManifest = ProbeSkipped "the manifest could not be decoded"
      fromManifest :: Text -> (Manifest -> IO a) -> IO (Probe a)
      fromManifest label action = maybe (pure needsManifest) (guarded label . action) decoded
  targetProbe <- fromManifest "matching the target" (pure . matchTarget target)
  let matchedIds = case (decoded, targetProbe) of
        (Just recorded, ProbeOk TargetMatched {}) -> matchedApplicationIds target recorded
        _ -> Set.empty
      concernedModules recorded = targetModules target recorded matchedIds
  copies <- fromManifest "locating the installed copy" $ \recorded ->
    traverse (installedCopy root (env ^. #searchPaths)) (targetAppliedModules (concernedModules recorded) recorded)
  checks <- fromManifest "checking the installed copy" $ \recorded ->
    checkAppliedArtifactsFor root (env ^. #searchPaths) (Just (concernedModules recorded)) recorded
  unknown <- fromManifest "reading shared-write evidence" (pure . sharedUnknownPaths matchedIds)
  unknownCount <- fromManifest "counting unknown shared paths" (pure . projectUnknownPaths)
  locals <- fromManifest "reading recorded origins" (pure . machineLocalOrigins)
  upgradeProbe <- case manifestProbe of
    ProbeOk ManifestAbsent -> pure (ProbeSkipped "there is no manifest")
    ProbeOk (ManifestNotJson _) -> pure (ProbeSkipped "the manifest is not valid JSON")
    _ ->
      guardedWithin "seihou manifest upgrade --dry-run" seconds $
        Directory.withCurrentDirectory root $ do
          outcome <- runManifestUpgrade ManifestUpgradeOpts {dryRun = True, force = False, targetVersion = Nothing}
          let rendered = renderUpgradeOutcome outcome
          _ <- evaluate (T.length rendered)
          pure rendered
  updateProbe <- case (pending, decoded) of
    (ProbeOk True, _) ->
      pure (ProbeSkipped "an interrupted update is waiting to be recovered, and planning an update would recover it")
    (ProbeOk False, Just _) -> guardedWithin ("seihou update " <> target <> " --dry-run") seconds (probeUpdate root target)
    (ProbeOk False, Nothing) -> pure needsManifest
    _ -> pure (ProbeSkipped "whether an interrupted update is waiting could not be determined")
  gitProbe <- guarded "reading git state" (probeGit root)
  pure
    UpgradeDiagnosis
      { target,
        projectRoot = root,
        manifest = manifestProbe,
        pendingRecovery = pending,
        targetState = targetProbe,
        installedCopies = copies,
        installedChecks = checks,
        unknownSharedPaths = unknown,
        projectUnknownCount = unknownCount,
        localOrigins = locals,
        manifestUpgrade = upgradeProbe,
        updateDryRun = updateProbe,
        git = gitProbe
      }

-- | Run a probe, turning any exception into 'ProbeFailed'.
guarded :: Text -> IO a -> IO (Probe a)
guarded label action = do
  result <- try @SomeException (action >>= evaluate)
  pure $ case result of
    Left err -> ProbeFailed (failureText label err)
    Right value -> ProbeOk value

-- | 'guarded', bounded in time. The probe runs on its own thread and is
-- abandoned (and sent a kill) when the deadline passes. The deadline is
-- enforced by waiting on the result rather than by interrupting the probe,
-- because the update planner catches every exception in places, which would
-- swallow an interrupting timeout and report it as a planning error.
guardedWithin :: Text -> Int -> IO a -> IO (Probe a)
guardedWithin label seconds action = do
  box <- newEmptyMVar
  worker <- forkIO (try @SomeException (action >>= evaluate) >>= putMVar box)
  outcome <- timeout (seconds * 1000000) (takeMVar box)
  case outcome of
    Nothing -> do
      _ <- forkIO (killThread worker)
      pure (ProbeTimedOut seconds)
    Just (Left err) -> pure (ProbeFailed (failureText label err))
    Just (Right value) -> pure (ProbeOk value)

failureText :: Text -> SomeException -> Text
failureText label err = label <> " failed: " <> T.strip (T.pack (displayException err))

probeManifest :: FilePath -> IO ManifestState
probeManifest root = do
  let path = root </> ".seihou" </> "manifest.json"
  present <- Directory.doesFileExist path
  if not present
    then pure ManifestAbsent
    else do
      bytes <- LBS.readFile path
      pure $ case Aeson.eitherDecode @Aeson.Value bytes of
        Left err -> ManifestNotJson (T.pack err)
        Right document -> case documentSchemaVersion document of
          Left err -> ManifestSchemaUnreadable (renderManifestUpgradeError err)
          Right schema -> case manifestFromJSON bytes of
            Left err -> ManifestUndecodable schema (T.pack err)
            Right recorded -> ManifestDecoded schema recorded

matchTarget :: Text -> Manifest -> TargetState
matchTarget target recorded =
  case matchApplications (NamedUpdateTargets [target]) recorded of
    Right (MatchedNamed ids) ->
      TargetMatched
        (map (applicationRef recorded) (Set.toAscList ids))
        (nub [nameAndVersion applied | applied <- recorded ^. #modules, applied ^. #name . #unModuleName == target])
    Right (MatchedLegacy _) -> TargetLegacyManifest
    Right (MatchedAll _) -> TargetLegacyManifest
    Left _ -> TargetNotFound (availableTargetsOf recorded)
  where
    nameAndVersion applied =
      applied ^. #name . #unModuleName <> " " <> maybe "(no recorded version)" id (applied ^. #moduleVersion)

availableTargetsOf :: Manifest -> [Text]
availableTargetsOf recorded =
  nub
    ( [targetText (application ^. #target) | application <- recorded ^. #applications]
        <> [state ^. #name . #unModuleName | application <- recorded ^. #applications, state <- application ^. #instances]
    )
  where
    targetText (AppliedModuleTarget name) = name ^. #unModuleName
    targetText (AppliedRecipeTarget name) = name ^. #unRecipeName

matchedApplicationIds :: Text -> Manifest -> Set ApplicationId
matchedApplicationIds target recorded =
  case matchApplications (NamedUpdateTargets [target]) recorded of
    Right (MatchedNamed ids) -> ids
    _ -> Set.empty

-- | The modules an upgrade of the target concerns: the target itself, and
-- every module instance of the applications it matched (a recipe target
-- names no module of its own).
targetModules :: Text -> Manifest -> Set ApplicationId -> Set ModuleName
targetModules target recorded ids =
  Set.insert
    (ModuleName target)
    ( Set.fromList
        [ state ^. #name
        | application <- recorded ^. #applications,
          Set.member (application ^. #applicationId) ids,
          state <- application ^. #instances
        ]
    )

targetAppliedModules :: Set ModuleName -> Manifest -> [AppliedModule]
targetAppliedModules names recorded =
  dedupe [applied | applied <- recorded ^. #modules, Set.member (applied ^. #name) names]
  where
    dedupe = go Set.empty
    go _ [] = []
    go seen (applied : rest)
      | Set.member (applied ^. #name) seen = go seen rest
      | otherwise = applied : go (Set.insert (applied ^. #name) seen) rest

installedCopy :: FilePath -> [FilePath] -> AppliedModule -> IO InstalledCopy
installedCopy root paths applied = do
  resolved <- resolveArtifactOrigin root paths "module.dhall" (applied ^. #origin)
  case resolved of
    Left _ -> pure (copy Nothing Nothing)
    Right directory -> copy (Just directory) <$> localModuleVersion directory
  where
    copy directory version =
      InstalledCopy
        { name = applied ^. #name . #unModuleName,
          directory,
          version,
          recordedVersion = applied ^. #moduleVersion
        }

sharedUnknownPaths :: Set ApplicationId -> Manifest -> [SharedUnknownPath]
sharedUnknownPaths selected recorded =
  [ SharedUnknownPath path (map (applicationRef recorded) (Set.toAscList others))
  | (path, record) <- Map.toAscList (recorded ^. #files),
    record ^. #sharedWriteMode == SharedWriteUnknown,
    let owners = record ^. #applicationIds,
    not (Set.null (Set.intersection owners selected)),
    let others = owners Set.\\ selected,
    not (Set.null others)
  ]

projectUnknownPaths :: Manifest -> Int
projectUnknownPaths recorded =
  length
    [ ()
    | record <- Map.elems (recorded ^. #files),
      record ^. #sharedWriteMode == SharedWriteUnknown,
      Set.size (record ^. #applicationIds) > 1
    ]

machineLocalOrigins :: Manifest -> [LocalOriginRecord]
machineLocalOrigins recorded =
  [ LocalOriginRecord recordedUrl (nub (map (^. #artifactName) sites))
  | (_, sites@(site : _)) <- Map.toAscList (localOriginUrls recorded),
    let recordedUrl = site ^. #recordedUrl
  ]

probeUpdate :: FilePath -> Text -> IO UpdateProbe
probeUpdate root target =
  Directory.withCurrentDirectory root $
    withProjectUpdate request $ \result -> do
      let probe = case result of
            Left err ->
              UpdateProbe
                { errorCode = Just (errorCode err),
                  noOp = False,
                  headline = "",
                  rendered = renderUpdateHuman False (errorOutput err)
                }
            Right plan ->
              UpdateProbe
                { errorCode = Nothing,
                  noOp = isUpdateNoOp plan,
                  headline = versionHeadline (plan ^. #versionChanges),
                  rendered =
                    if isUpdateNoOp plan
                      then "Already up to date.\n"
                      else renderUpdateHuman False (planOutput plan)
                }
      _ <- evaluate (T.length (probe ^. #rendered) + T.length (probe ^. #headline))
      pure probe
  where
    request =
      UpdateRequest
        { selection = NamedUpdateTargets [target],
          varOverrides = [],
          reconfigure = False,
          promptPolicy = ForbidPrompts,
          commandPolicy = RunChangedCommands,
          dryRun = True,
          allowDowngrade = False,
          includeSharedOwners = False
        }

versionHeadline :: [VersionChange] -> Text
versionHeadline [] = "no version changes"
versionHeadline changes = T.intercalate ", " (map one changes)
  where
    one change =
      change ^. #name
        <> " "
        <> maybe "(none)" id (change ^. #fromVersion)
        <> " -> "
        <> maybe "(none)" id (change ^. #toVersion)

probeGit :: FilePath -> IO GitState
probeGit root = do
  (insideCode, insideOut, _) <- readProcessWithExitCode "git" ["-C", root, "rev-parse", "--is-inside-work-tree"] ""
  if insideCode /= ExitSuccess || T.strip (T.pack insideOut) /= "true"
    then pure GitState {isRepository = False, dirtyPaths = []}
    else do
      -- --no-optional-locks keeps status from refreshing the index, which is
      -- a write.
      (statusCode, statusOut, statusErr) <-
        readProcessWithExitCode "git" ["--no-optional-locks", "-C", root, "status", "--porcelain"] ""
      case statusCode of
        ExitSuccess -> pure GitState {isRepository = True, dirtyPaths = filter (not . T.null) (T.lines (T.pack statusOut))}
        ExitFailure _ -> ioError (userError ("git status failed: " <> statusErr))

-- ----------------------------------------------------------------------------
-- Readiness
-- ----------------------------------------------------------------------------

-- | A check's verdict. 'CouldNotDetermine' counts as needing attention: an
-- upgrade cannot be called ready on a question nobody answered.
data ReadinessStatus = Ready | NeedsAttention | CouldNotDetermine
  deriving stock (Eq, Show, Generic)

data ReadinessCheck = ReadinessCheck
  { -- | Stable, used in the report, e.g. @manifest-readable@.
    name :: !Text,
    status :: !ReadinessStatus,
    -- | One line: what was found, or for a failing check, what is wrong and
    -- how to repair it.
    detail :: !Text
  }
  deriving stock (Eq, Show, Generic)

-- | The checks behind a plain @seihou update TARGET@, in report order.
-- Git state is reported in the brief but is not a check: a dirty tree does
-- not make a future upgrade need an agent.
readiness :: UpgradeDiagnosis -> [ReadinessCheck]
readiness diagnosis =
  [ check "manifest-readable" manifestReadable,
    check "manifest-schema-current" schemaCurrent,
    check "no-interrupted-update" noInterruptedUpdate,
    check "target-recorded" targetRecorded,
    check "installed-copy-trusted" installedTrusted,
    check "origins-portable" originsPortable,
    check "shared-evidence-known" sharedEvidenceKnown,
    check "update-plans-cleanly" updatePlansCleanly
  ]
  where
    check checkName (checkStatus, checkDetail) = ReadinessCheck checkName checkStatus checkDetail
    ready = (Ready,)
    attention = (NeedsAttention,)
    unknown = (CouldNotDetermine,)
    target = diagnosis ^. #target
    manifestFile = ".seihou/manifest.json"

    manifestReadable = case diagnosis ^. #manifest of
      ProbeOk ManifestAbsent ->
        attention (manifestFile <> " does not exist; run this from the root of a seihou project")
      ProbeOk (ManifestNotJson err) -> attention (manifestFile <> " is not valid JSON: " <> firstLine err)
      ProbeOk (ManifestSchemaUnreadable err) -> attention (manifestFile <> ": " <> err)
      ProbeOk (ManifestUndecodable schema err)
        | schema < oldestDecodableManifestVersion ->
            attention (manifestFile <> " is schema " <> schemaText schema <> ", which only seihou manifest upgrade converts")
        | otherwise ->
            attention (manifestFile <> " is schema " <> schemaText schema <> " and does not decode: " <> firstLine err)
      ProbeOk (ManifestDecoded schema _) -> ready (manifestFile <> " is schema " <> schemaText schema <> " and decodes")
      other -> undetermined other

    schemaCurrent = case diagnosis ^. #manifest of
      ProbeOk (ManifestDecoded schema _) -> judgeSchema schema
      ProbeOk (ManifestUndecodable schema _) -> judgeSchema schema
      ProbeOk _ -> unknown "the manifest's schema could not be read"
      other -> undetermined other

    judgeSchema schema
      | schema == currentManifestVersion = ready ("schema " <> schemaText schema <> " is current")
      | schema > currentManifestVersion =
          attention
            ( "schema "
                <> schemaText schema
                <> " is newer than this seihou reads ("
                <> schemaText currentManifestVersion
                <> "); upgrade seihou"
            )
      | schema < oldestDecodableManifestVersion =
          attention
            ( "schema "
                <> schemaText schema
                <> " is older than "
                <> schemaText oldestDecodableManifestVersion
                <> "; run seihou manifest upgrade"
            )
      | otherwise =
          attention
            ( "schema "
                <> schemaText schema
                <> " is older than "
                <> schemaText currentManifestVersion
                <> "; seihou update steps it forward, or run seihou manifest upgrade"
            )

    noInterruptedUpdate = case diagnosis ^. #pendingRecovery of
      ProbeOk False -> ready "no update transaction is waiting to be recovered"
      ProbeOk True ->
        attention "an interrupted update is waiting under .seihou/transactions; run seihou update --dry-run once to recover it"
      other -> undetermined other

    targetRecorded = case diagnosis ^. #targetState of
      ProbeOk (TargetMatched refs _) -> ready (T.intercalate ", " (map applicationLabel refs))
      ProbeOk (TargetNotFound available) ->
        attention
          ( target
              <> " is not a recorded target"
              <> (if null available then "" else "; recorded targets: " <> T.intercalate ", " available)
          )
      ProbeOk TargetLegacyManifest ->
        attention ("the manifest records no applications; run seihou update " <> target <> " once to seed the record")
      other -> undetermined other

    installedTrusted = case (diagnosis ^. #targetState, diagnosis ^. #installedChecks) of
      (ProbeOk (TargetNotFound _), _) -> unknown (target <> " is not recorded, so there is no installed copy to check")
      (_, ProbeOk checks) -> case blockingChecks checks of
        [] -> ready (installedSummary (diagnosis ^. #installedCopies))
        blocking -> attention (T.intercalate "; " (mapMaybe summarizeCheck blocking))
      (_, other) -> undetermined other

    installedSummary = \case
      ProbeOk [] -> "no recorded module needs an installed copy"
      ProbeOk copies -> T.intercalate "; " (map copyText copies) <> ", matching the manifest's source"
      _ -> "the installed copy matches the manifest's source"
      where
        copyText copy =
          "module " <> copy ^. #name <> maybe "" (" " <>) (copy ^. #version) <> " is installed"

    originsPortable = case diagnosis ^. #localOrigins of
      ProbeOk [] -> ready "every recorded origin is a remote URL or a project path"
      ProbeOk records ->
        attention
          ( T.intercalate "; " [record ^. #url <> " is recorded for " <> T.intercalate ", " (record ^. #artifacts) | record <- records]
              <> "; run seihou manifest repair-origins"
          )
      other -> undetermined other

    sharedEvidenceKnown = case diagnosis ^. #unknownSharedPaths of
      ProbeOk [] -> ready "no path shared with another application has an unknown write mode"
      ProbeOk paths ->
        attention
          ( T.intercalate
              "; "
              [ T.pack (shared ^. #path)
                  <> " is shared with "
                  <> T.intercalate ", " (map applicationLabel (shared ^. #otherOwners))
                  <> " and its write mode is unknown"
              | shared <- paths
              ]
          )
      other -> undetermined other

    updatePlansCleanly = case diagnosis ^. #updateDryRun of
      ProbeOk probe -> case probe ^. #errorCode of
        Just code ->
          attention ("seihou update " <> target <> " --dry-run failed [" <> code <> "]: " <> failureMessage (probe ^. #rendered))
        Nothing
          | probe ^. #noOp -> ready ("seihou update " <> target <> " --dry-run: already up to date")
          | otherwise -> ready ("seihou update " <> target <> " --dry-run: " <> probe ^. #headline)
      other -> undetermined other

    undetermined :: Probe a -> (ReadinessStatus, Text)
    undetermined probe = unknown (probeProblem probe)

-- | Why a probe produced no value, as one line.
probeProblem :: Probe a -> Text
probeProblem = \case
  ProbeOk _ -> "the probe succeeded"
  ProbeSkipped reason -> "not checked: " <> reason
  ProbeFailed reason -> firstLine reason
  ProbeTimedOut seconds -> "did not finish within " <> T.pack (show seconds) <> " seconds"

-- | The first line of an @Update failed [code]: message@ rendering, without
-- the lead-in.
failureMessage :: Text -> Text
failureMessage rendered =
  let line = firstLine rendered
      (_, rest) = T.breakOn "]: " line
   in if T.null rest then line else T.drop 3 rest

firstLine :: Text -> Text
firstLine text = case T.lines (T.strip text) of
  line : _ -> line
  [] -> ""

schemaText :: ManifestSchemaVersion -> Text
schemaText schema = T.pack (show (schema ^. #unManifestSchemaVersion))

isReady :: [ReadinessCheck] -> Bool
isReady = all ((== Ready) . (^. #status))

-- | The readiness report. Its last line is exactly @Upgrade readiness: ready@
-- or @Upgrade readiness: not ready (N check(s) need(s) attention)@, and it
-- uses no colour, so scripts can read it through a pipe.
renderReadinessReport :: Text -> [ReadinessCheck] -> Text
renderReadinessReport target checks =
  T.unlines $
    ["Upgrade readiness for " <> target]
      <> map line checks
      <> [verdict]
  where
    width = 2 + maximum (0 : map (T.length . (^. #name)) checks)
    line item = "  " <> mark (item ^. #status) <> " " <> T.justifyLeft width ' ' (item ^. #name) <> item ^. #detail
    mark = \case
      Ready -> "✓"
      NeedsAttention -> "✗"
      CouldNotDetermine -> "?"
    failing = length (filter ((/= Ready) . (^. #status)) checks)
    verdict
      | failing == 0 = "Upgrade readiness: ready"
      | failing == 1 = "Upgrade readiness: not ready (1 check needs attention)"
      | otherwise = "Upgrade readiness: not ready (" <> T.pack (show failing) <> " checks need attention)"

-- ----------------------------------------------------------------------------
-- The upgrade brief
-- ----------------------------------------------------------------------------

-- | Placeholder name/value pairs for the upgrade prompt template. Findings
-- from the caller (a configuration fallback, an escaped exception) are
-- rendered into @findings_section@ after the diagnosis' own.
briefSections :: UpgradeDiagnosis -> [Text] -> [(Text, Text)]
briefSections diagnosis callerFindings =
  [ ("module", diagnosis ^. #target),
    ("cwd", T.pack (diagnosis ^. #projectRoot)),
    ("diagnosis_summary", fenced (renderReadinessReport (diagnosis ^. #target) (readiness diagnosis))),
    ("manifest_section", manifestSection),
    ("target_section", targetSection),
    ("installed_section", installedSection),
    ("shared_evidence_section", sharedSection),
    ("manifest_upgrade_section", upgradeSection),
    ("update_dry_run_section", updateSection),
    ("git_section", gitSection),
    ("findings_section", findingsSection)
  ]
  where
    target = diagnosis ^. #target
    manifestFile = "`.seihou/manifest.json`"

    manifestSection = case diagnosis ^. #manifest of
      ProbeOk ManifestAbsent ->
        "There is no "
          <> manifestFile
          <> " here. Either this is not the root of a seihou project, or nothing has been generated\
             \ into it yet. Ask the user which project they meant before doing anything else."
      ProbeOk (ManifestNotJson err) ->
        manifestFile
          <> " exists but is not valid JSON ("
          <> firstLine err
          <> "). Nothing can repair that through seihou. Look at `git log -p -- .seihou/manifest.json`,\
             \ restore the last good version with the user's agreement, and diagnose again."
      ProbeOk (ManifestSchemaUnreadable err) ->
        manifestFile <> " is JSON, but its schema version cannot be read: " <> err <> "."
      ProbeOk (ManifestUndecodable schema err)
        | schema < oldestDecodableManifestVersion ->
            manifestFile
              <> " is at schema "
              <> schemaText schema
              <> ". This seihou reads schema "
              <> schemaText oldestDecodableManifestVersion
              <> " and newer, and only `seihou manifest upgrade` converts an older one, because the conversion\
                 \ infers artifact origins from paths on the machine that wrote it."
        | otherwise ->
            manifestFile <> " is at schema " <> schemaText schema <> " but does not decode: " <> firstLine err
      ProbeOk (ManifestDecoded schema recorded) ->
        manifestFile
          <> " is at schema "
          <> schemaText schema
          <> " (current is "
          <> schemaText currentManifestVersion
          <> "). It records "
          <> countOf (length (recorded ^. #applications)) "application"
          <> ", "
          <> countOf (length (recorded ^. #modules)) "module instance"
          <> ", and "
          <> countOf (Map.size (recorded ^. #files)) "managed file"
          <> "."
      other -> "The manifest could not be read. " <> sentence other

    targetSection = case diagnosis ^. #targetState of
      ProbeOk (TargetMatched refs versions) ->
        "`"
          <> target
          <> "` matches these recorded applications: "
          <> T.intercalate ", " (map applicationLabel refs)
          <> "."
          <> (if null versions then "" else "\nRecorded versions: " <> T.intercalate ", " versions <> ".")
      ProbeOk (TargetNotFound available) ->
        "`"
          <> target
          <> "` is not a recorded target in this project."
          <> ( if null available
                 then ""
                 else " The recorded targets are: " <> T.intercalate ", " available <> ". Ask the user which one they meant."
             )
      ProbeOk TargetLegacyManifest ->
        "The manifest records no applications (a manifest written before applications were recorded).\
        \ One `seihou update "
          <> target
          <> "` seeds the record."
      other -> sentence other

    installedSection =
      T.unlines $
        ( case diagnosis ^. #installedCopies of
            ProbeOk [] -> ["No recorded module instance of `" <> target <> "` needs an installed copy."]
            ProbeOk copies -> map copyLine copies
            other -> ["Installed copies were not located. " <> sentence other]
        )
          <> ( case diagnosis ^. #installedChecks of
                 ProbeOk checks -> case mapMaybe summarizeCheck checks of
                   [] -> ["The artifact guard has nothing to report: each installed copy matches the manifest's source and is not older than recorded."]
                   summaries -> "The artifact guard reports:" : map ("- " <>) summaries
                 other -> ["The artifact guard did not run. " <> sentence other]
             )

    copyLine copy =
      "- "
        <> copy ^. #name
        <> ": recorded at "
        <> maybe "no version" id (copy ^. #recordedVersion)
        <> "; "
        <> case copy ^. #directory of
          Nothing -> "not installed on this machine"
          Just directory ->
            "installed at `"
              <> T.pack directory
              <> "`, declaring "
              <> maybe "no readable version" ("version " <>) (copy ^. #version)

    sharedSection =
      T.unlines $
        ( case diagnosis ^. #unknownSharedPaths of
            ProbeOk [] -> ["No path `" <> target <> "` shares with another application has an unknown shared-write mode."]
            ProbeOk paths ->
              "These paths are shared with applications outside the upgrade, and nothing records how their owners write them:"
                : [ "- `"
                      <> T.pack (shared ^. #path)
                      <> "`: also owned by "
                      <> T.intercalate ", " (map applicationLabel (shared ^. #otherOwners))
                  | shared <- paths
                  ]
            other -> [sentence other]
        )
          <> ( case diagnosis ^. #projectUnknownCount of
                 ProbeOk count
                   | count > 0 -> ["Project-wide, " <> countOf count "shared path" <> " record an unknown write mode."]
                 _ -> []
             )
          <> ( case diagnosis ^. #localOrigins of
                 ProbeOk [] -> []
                 ProbeOk records ->
                   "These recorded origins are paths on the machine that wrote the manifest, not remote URLs:"
                     : [ "- `" <> record ^. #url <> "`: recorded for " <> T.intercalate ", " (record ^. #artifacts)
                       | record <- records
                       ]
                 other -> ["Recorded origins were not read. " <> sentence other]
             )

    upgradeSection = case diagnosis ^. #manifestUpgrade of
      ProbeOk rendered -> "`seihou manifest upgrade --dry-run` reports:\n\n" <> fenced rendered
      other -> "`seihou manifest upgrade --dry-run` did not run. " <> sentence other

    updateSection = case diagnosis ^. #updateDryRun of
      ProbeOk probe ->
        "`seihou update "
          <> target
          <> " --dry-run` "
          <> maybe "planned:" (\code -> "failed with `" <> code <> "`:") (probe ^. #errorCode)
          <> "\n\n"
          <> fenced (probe ^. #rendered)
      other -> "`seihou update " <> target <> " --dry-run` did not run. " <> sentence other

    gitSection = case diagnosis ^. #git of
      ProbeOk state
        | not (state ^. #isRepository) ->
            "This directory is not inside a git repository, so there is no easy undo. Tell the user before changing anything."
        | null (state ^. #dirtyPaths) -> "The git working tree is clean."
        | otherwise ->
            "The git working tree has uncommitted changes. Ask the user before working on top of them:\n\n"
              <> fenced (T.unlines (take 40 (state ^. #dirtyPaths)))
      other -> "Git state was not read. " <> sentence other

    findingsSection = case probeFindings <> callerFindings of
      [] -> "None. Every probe ran."
      findings -> T.unlines (map ("- " <>) findings)

    probeFindings =
      mapMaybe
        (\(label, problem) -> ((label <> ": ") <>) <$> problem)
        [ ("manifest", failureOf (diagnosis ^. #manifest)),
          ("interrupted-update check", failureOf (diagnosis ^. #pendingRecovery)),
          ("target", failureOf (diagnosis ^. #targetState)),
          ("installed copy", failureOf (diagnosis ^. #installedCopies)),
          ("artifact guard", failureOf (diagnosis ^. #installedChecks)),
          ("shared-write evidence", failureOf (diagnosis ^. #unknownSharedPaths)),
          ("recorded origins", failureOf (diagnosis ^. #localOrigins)),
          ("manifest upgrade dry run", failureOf (diagnosis ^. #manifestUpgrade)),
          ("update dry run", failureOf (diagnosis ^. #updateDryRun)),
          ("git", failureOf (diagnosis ^. #git))
        ]

    -- Skipped probes are explained in their own sections; only a failure or
    -- a timeout is a finding.
    failureOf :: Probe a -> Maybe Text
    failureOf = \case
      probe@ProbeFailed {} -> Just (probeProblem probe)
      probe@ProbeTimedOut {} -> Just (probeProblem probe)
      _ -> Nothing

-- | 'probeProblem' as a sentence of its own.
sentence :: Probe a -> Text
sentence probe = case T.uncons (probeProblem probe) of
  Just (initial, rest) -> T.cons (toUpper initial) rest <> "."
  Nothing -> ""

fenced :: Text -> Text
fenced body = "```text\n" <> T.stripEnd body <> "\n```"

countOf :: Int -> Text -> Text
countOf 1 noun = "1 " <> noun
countOf n noun = T.pack (show n) <> " " <> noun <> "s"

-- | Where the brief was written, or why it could not be.
data BriefLocation = BriefSaved !FilePath | BriefNotSaved !Text
  deriving stock (Eq, Show, Generic)

-- | Create a fresh directory for one run's brief and manifest backups:
-- @\<XDG state\>\/seihou\/agent-upgrade\/\<UTC stamp\>-\<module\>@, or the
-- same name under the system temporary directory when the state directory
-- cannot be created. It lives outside the project because the brief holds
-- machine-local paths
-- (docs/adr/0001-manifest-is-a-checked-in-machine-independent-artifact.md).
-- Never throws; a 'Left' says why neither location worked.
createBriefDirectory :: Text -> IO (Either Text FilePath)
createBriefDirectory target = do
  stampResult <- try @SomeException (formatTime defaultTimeLocale "%Y%m%dT%H%M%SZ" <$> getCurrentTime)
  let stamp = either (const "run") id stampResult
      leaf = stamp <> "-" <> safeName target
  stateAttempt <- try @SomeException $ do
    state <- Directory.getXdgDirectory Directory.XdgState "seihou"
    fresh (state </> "agent-upgrade" </> leaf)
  case stateAttempt of
    Right directory -> pure (Right directory)
    Left stateError -> do
      tempAttempt <- try @SomeException $ do
        temporary <- Directory.getTemporaryDirectory
        fresh (temporary </> "seihou-agent-upgrade" </> leaf)
      pure $ case tempAttempt of
        Right directory -> Right directory
        Left tempError ->
          Left
            ( "the brief directory could not be created ("
                <> T.pack (displayException stateError)
                <> "; "
                <> T.pack (displayException tempError)
                <> ")"
            )
  where
    -- A second run within the same second gets a numbered sibling rather
    -- than sharing (and overwriting) the first one's directory.
    fresh base = go (0 :: Int)
      where
        go attempt = do
          let candidate = if attempt == 0 then base else base <> "-" <> show attempt
          exists <- Directory.doesPathExist candidate
          if exists && attempt < 100
            then go (attempt + 1)
            else do
              Directory.createDirectoryIfMissing True (takeDirectory candidate)
              Directory.createDirectory candidate
              pure candidate

    safeName name =
      case T.unpack (T.map (\c -> if isAlphaNum c || c `elem` ("-_." :: String) then c else '_') name) of
        "" -> "module"
        cleaned -> cleaned

-- | Write the brief into the directory 'createBriefDirectory' made. Never
-- throws.
writeBrief :: Either Text FilePath -> Text -> IO BriefLocation
writeBrief (Left reason) _ = pure (BriefNotSaved reason)
writeBrief (Right directory) brief = do
  let path = directory </> "brief.md"
  result <- try @SomeException (TIO.writeFile path brief)
  pure $ case result of
    Left err -> BriefNotSaved ("the brief could not be written to " <> T.pack path <> ": " <> T.pack (displayException err))
    Right () -> BriefSaved path
