module Seihou.CLI.Update.Migrations
  ( StagedMigrations (..),
    planAndStageMigrations,
    migrationTouchedPaths,
    migrationTouchesDirectories,
  )
where

import Control.Monad (guard)
import Data.List (find)
import Data.Map.Strict qualified as Map
import Data.Maybe (mapMaybe)
import Data.Set qualified as Set
import Data.Text.IO qualified as TIO
import Effectful (runPureEff)
import Seihou.CLI.Update.Types
import Seihou.Composition.Instance (ModuleInstance (..))
import Seihou.Core.Migration (Migration (..), MigrationOp (..), MigrationPlan (..), planMigrationChain)
import Seihou.Core.Types
import Seihou.Core.Version (parseVersion)
import Seihou.Effect.FilesystemPure (PureFS (..), runFilesystemPure)
import Seihou.Effect.ProcessPure (ProcessMock (..), runProcessPure)
import Seihou.Engine.Migrate
  ( ExecutedMigrationPlan (..),
    MigrationOpInstance (..),
    classifyMigration,
    executeMigration,
  )
import Seihou.Prelude
import System.Directory qualified as Directory
import System.Exit (ExitCode (..))
import System.FilePath (takeDirectory)

data StagedMigrations = StagedMigrations
  { plans :: [PlannedUpdateMigration],
    manifest :: Manifest,
    filesystem :: PureFS,
    warnings :: [UpdateWarning]
  }
  deriving stock (Eq, Show)

data Transition = Transition
  { moduleName :: ModuleName,
    originUrl :: Maybe Text,
    fromVersion :: Text,
    toVersion :: Text,
    candidateModule :: Module,
    sourceDirectory :: FilePath
  }

-- | Deduplicate equal module transitions and simulate them against a complete
-- snapshot of tracked project text. Shell commands are mocked as successful
-- and retained as explicit warnings for the real apply/revalidation phase.
planAndStageMigrations ::
  FilePath ->
  Manifest ->
  CandidateCatalog ->
  [(Maybe AppliedComposition, [(ModuleInstance, Module, FilePath)])] ->
  IO (Either UpdateError StagedMigrations)
planAndStageMigrations projectRoot manifest catalog applications = do
  initialFilesystem <- snapshotTrackedFiles projectRoot manifest
  pure $ do
    transitions <- collectTransitions catalog applications
    planned <- traverse planTransition (deduplicateTransitions transitions)
    let processMocks = concatMap commandMocks planned
        ((stageResult, finalFilesystem)) =
          runPureEff $
            runFilesystemPure initialFilesystem $
              runProcessPure processMocks $
                stageAll manifest [] planned
    (finalManifest, stagedPlans) <- stageResult
    let warnings =
          [ MigrationCommandNotSimulated plannedMigration.moduleName command
          | plannedMigration <- stagedPlans,
            RunCommandInst command _ <- plannedMigration.stagedPlan.planOps
          ]
    Right
      StagedMigrations
        { plans = stagedPlans,
          manifest = finalManifest,
          filesystem = finalFilesystem,
          warnings
        }

stageAll manifest completed [] = pure (Right (manifest, reverse completed))
stageAll manifest completed ((transition, sourcePlan) : rest) = do
  classified <- classifyMigration manifest sourcePlan
  case classified of
    Left err -> pure (Left (UpdateMigrationStageFailed transition.moduleName err))
    Right stagedPlan -> do
      executed <- executeMigration False stagedPlan manifest manifest.genAt
      case executed of
        Left err -> pure (Left (UpdateMigrationStageFailed transition.moduleName err))
        Right nextManifest ->
          let planned =
                PlannedUpdateMigration
                  { moduleName = transition.moduleName,
                    sourceDirectory = transition.sourceDirectory,
                    sourcePlan,
                    stagedPlan,
                    containsCommands = any isCommand stagedPlan.planOps
                  }
           in stageAll nextManifest (planned : completed) rest
  where
    isCommand RunCommandInst {} = True
    isCommand _ = False

collectTransitions ::
  CandidateCatalog ->
  [(Maybe AppliedComposition, [(ModuleInstance, Module, FilePath)])] ->
  Either UpdateError [Transition]
collectTransitions catalog applications = do
  let raw = concatMap applicationTransitions applications
      priorByModule =
        Map.fromListWith
          Set.union
          [ ((transition.moduleName, transition.originUrl), Set.singleton transition.fromVersion)
          | transition <- raw
          ]
  case [ (name, Set.toAscList versions)
       | ((name, _), versions) <- Map.toAscList priorByModule,
         Set.size versions > 1
       ] of
    (name, versions) : _ -> Left (UpdateConflictingPriorVersions name versions)
    [] -> Right raw
  where
    applicationTransitions (Nothing, _) = []
    applicationTransitions (Just previous, candidates) =
      mapMaybe (transitionFor previous) candidates

    transitionFor previous (instanceId, candidateModule, sourceDirectory) = do
      prior <- find (matches instanceId) previous.instances
      fromVersion <- prior.moduleVersion
      toVersion <- candidateModule.version
      guard (fromVersion /= toVersion)
      let artifact = Map.lookup (CandidateModule, candidateModule.name.unModuleName) catalog.artifacts
      pure
        Transition
          { moduleName = candidateModule.name,
            originUrl = artifact >>= (.sourceUrl),
            fromVersion,
            toVersion,
            candidateModule,
            sourceDirectory
          }

    matches instanceId state =
      state.name == instanceId.instanceModule
        && state.parentVars == instanceId.instanceParentVars

deduplicateTransitions :: [Transition] -> [Transition]
deduplicateTransitions = go Set.empty
  where
    go _ [] = []
    go seen (transition : rest)
      | Set.member (transitionKey transition) seen = go seen rest
      | otherwise = transition : go (Set.insert (transitionKey transition) seen) rest

    transitionKey transition =
      ( transition.moduleName,
        transition.originUrl,
        transition.fromVersion,
        transition.toVersion
      )

planTransition :: Transition -> Either UpdateError (Transition, MigrationPlan)
planTransition transition = do
  fromVersion <-
    maybe
      (Left (CandidateVersionInvalid transition.moduleName.unModuleName transition.fromVersion))
      Right
      (parseVersion transition.fromVersion)
  toVersion <-
    maybe
      (Left (CandidateVersionInvalid transition.moduleName.unModuleName transition.toVersion))
      Right
      (parseVersion transition.toVersion)
  planned <-
    first
      (UpdateMigrationPlanFailed transition.moduleName)
      (planMigrationChain transition.moduleName.unModuleName transition.candidateModule.migrations fromVersion toVersion)
  case planned of
    Nothing -> error "planTransition received unequal versions but no migration plan"
    Just sourcePlan -> Right (transition, sourcePlan)

commandMocks :: (Transition, MigrationPlan) -> [ProcessMock]
commandMocks (_, sourcePlan) =
  [ ProcessMock
      { mockCommand = "/bin/sh",
        mockArgs = ["-c", command],
        mockResult = (ExitSuccess, "", "")
      }
  | migration <- sourcePlan.planSteps,
    RunCommand command _ <- migration.ops
  ]

snapshotTrackedFiles :: FilePath -> Manifest -> IO PureFS
snapshotTrackedFiles projectRoot manifest = do
  files <- fmap Map.fromList . fmap concat $ traverse readTracked (Map.keys manifest.files)
  let directories =
        Set.fromList
          [ directory
          | path <- Map.keys files,
            directory <- parents path
          ]
  pure PureFS {files, dirs = directories}
  where
    readTracked path = do
      let fullPath = projectRoot </> path
      exists <- Directory.doesFileExist fullPath
      if exists
        then do
          content <- TIO.readFile fullPath
          pure [(path, content)]
        else pure []

    parents path = takeWhile (\directory -> directory /= "." && directory /= "") (iterate takeDirectory (takeDirectory path))

migrationTouchedPaths :: [PlannedUpdateMigration] -> Set FilePath
migrationTouchedPaths = Set.fromList . concatMap (concatMap touched . (.stagedPlan.planOps))
  where
    touched (MoveFileInst source destination _) = [source, destination]
    touched (MoveDirInst source destination) = [source, destination]
    touched (DeleteFileInst path _) = [path]
    touched (DeleteDirInst path) = [path]
    touched RunCommandInst {} = []

migrationTouchesDirectories :: PlannedUpdateMigration -> Bool
migrationTouchesDirectories migration = any touchesDirectory migration.stagedPlan.planOps
  where
    touchesDirectory MoveDirInst {} = True
    touchesDirectory DeleteDirInst {} = True
    touchesDirectory _ = False
