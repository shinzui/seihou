module Seihou.CLI.Update.Migrations
  ( StagedMigrations (..),
    planAndStageMigrations,
    planAndStageMigrationsWithSeeds,
    migrationTouchedPaths,
    migrationTouchesDirectories,
  )
where

import Control.Monad (guard)
import Data.Generics.Labels ()
import Data.List (find)
import Data.Map.Strict qualified as Map
import Data.Maybe (mapMaybe)
import Data.Set qualified as Set
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Effectful (runEff, runPureEff)
import Seihou.CLI.Update.Types
import Seihou.Composition.Instance (ModuleInstance (..))
import Seihou.Core.Migration (Migration (..), MigrationOp (..), MigrationPlan (..), planMigrationChain)
import Seihou.Core.Path (validateProjectRelativePath)
import Seihou.Core.Types
import Seihou.Core.Version (parseVersion)
import Seihou.Effect.Filesystem (PathEntry (..), inspectPath)
import Seihou.Effect.FilesystemInterp (runFilesystem)
import Seihou.Effect.FilesystemPure (PureFS (..), runFilesystemPure)
import Seihou.Effect.ProcessPure (ProcessMock (..), runProcessPure)
import Seihou.Engine.Migrate
  ( ExecutedMigrationPlan (..),
    MigrationOpInstance (..),
    classifyMigration,
    executeMigration,
    validateSeedMigration,
  )
import Seihou.Prelude
import System.Directory qualified as Directory
import System.Exit (ExitCode (..))
import System.FilePath (takeDirectory)

data StagedMigrations = StagedMigrations
  { plans :: ![PlannedUpdateMigration],
    manifest :: !Manifest,
    filesystem :: !PureFS,
    warnings :: ![UpdateWarning]
  }
  deriving stock (Eq, Generic, Show)

data Transition = Transition
  { moduleName :: !ModuleName,
    originUrl :: !(Maybe Text),
    fromVersion :: !Text,
    toVersion :: !Text,
    candidateModule :: !Module,
    sourceDirectory :: !FilePath
  }
  deriving stock (Generic)

-- | Deduplicate equal module transitions and simulate them against a complete
-- snapshot of tracked project text. Shell commands are mocked as successful
-- and retained as explicit warnings for the real apply/revalidation phase.
planAndStageMigrations ::
  FilePath ->
  Manifest ->
  CandidateCatalog ->
  [(Maybe AppliedComposition, [(ModuleInstance, Module, FilePath)])] ->
  IO (Either UpdateError StagedMigrations)
planAndStageMigrations root manifest catalog applications = planAndStageMigrationsWithSeeds root manifest catalog applications (Map.keysSet (manifest ^. #seeds))

planAndStageMigrationsWithSeeds :: FilePath -> Manifest -> CandidateCatalog -> [(Maybe AppliedComposition, [(ModuleInstance, Module, FilePath)])] -> Set FilePath -> IO (Either UpdateError StagedMigrations)
planAndStageMigrationsWithSeeds projectRoot manifest catalog applications protected = do
  let declaredTargets = either (const []) id $ do
        transitions <- collectTransitions catalog applications
        planned <- traverse planTransition (deduplicateTransitions transitions)
        pure [safe | (_, sourcePlan) <- planned, migration <- sourcePlan ^. #steps, op@(RemoveLine path _) <- migration ^. #ops, Right safe <- [validateProjectRelativePath (T.pack path)], Right () <- [validateSeedMigration protected [op]]]
  initialFilesystem <- snapshotTrackedFiles projectRoot (manifest & #files %~ (`Map.withoutKeys` protected)) declaredTargets
  pure $ do
    transitions <- collectTransitions catalog applications
    planned <- traverse planTransition (deduplicateTransitions transitions)
    mapM_ (\(transition, sourcePlan) -> first (UpdateMigrationStageFailed (transition ^. #moduleName)) (validateSeedMigration protected (concatMap (^. #ops) (sourcePlan ^. #steps)))) planned
    let processMocks = concatMap commandMocks planned
        ((stageResult, finalFilesystem)) =
          runPureEff $
            runFilesystemPure initialFilesystem $
              runProcessPure processMocks $
                stageAll manifest [] planned
    (finalManifest, stagedPlans) <- stageResult
    let warnings =
          [ MigrationCommandNotSimulated (plannedMigration ^. #moduleName) command
          | plannedMigration <- stagedPlans,
            RunCommandInst command _ <- plannedMigration ^. #stagedPlan . #ops
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
    Left err -> pure (Left (UpdateMigrationStageFailed (transition ^. #moduleName) err))
    Right stagedPlan -> do
      executed <- executeMigration False stagedPlan manifest (manifest ^. #genAt)
      case executed of
        Left err -> pure (Left (UpdateMigrationStageFailed (transition ^. #moduleName) err))
        Right nextManifest ->
          let planned =
                PlannedUpdateMigration
                  { moduleName = transition ^. #moduleName,
                    sourceDirectory = transition ^. #sourceDirectory,
                    sourcePlan,
                    stagedPlan,
                    containsCommands = any isCommand (stagedPlan ^. #ops)
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
          [ ((transition ^. #moduleName, transition ^. #originUrl), Set.singleton (transition ^. #fromVersion))
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
      prior <- find (matches instanceId) (previous ^. #instances)
      fromVersion <- (prior ^. #moduleVersion)
      toVersion <- (candidateModule ^. #version)
      guard (fromVersion /= toVersion)
      let artifact = Map.lookup (CandidateModule, candidateModule ^. #name . #unModuleName) (catalog ^. #artifacts)
      pure
        Transition
          { moduleName = candidateModule ^. #name,
            originUrl = artifact >>= (^. #sourceUrl),
            fromVersion,
            toVersion,
            candidateModule,
            sourceDirectory
          }

    matches instanceId state =
      state ^. #name == instanceId ^. #module_
        && state ^. #parentVars == (instanceId ^. #parentVars)

deduplicateTransitions :: [Transition] -> [Transition]
deduplicateTransitions = go Set.empty
  where
    go _ [] = []
    go seen (transition : rest)
      | Set.member (transitionKey transition) seen = go seen rest
      | otherwise = transition : go (Set.insert (transitionKey transition) seen) rest

    transitionKey transition =
      ( transition ^. #moduleName,
        transition ^. #originUrl,
        transition ^. #fromVersion,
        transition ^. #toVersion
      )

planTransition :: Transition -> Either UpdateError (Transition, MigrationPlan)
planTransition transition = do
  fromVersion <-
    maybe
      (Left (CandidateVersionInvalid (transition ^. #moduleName . #unModuleName) (transition ^. #fromVersion)))
      Right
      (parseVersion (transition ^. #fromVersion))
  toVersion <-
    maybe
      (Left (CandidateVersionInvalid (transition ^. #moduleName . #unModuleName) (transition ^. #toVersion)))
      Right
      (parseVersion (transition ^. #toVersion))
  planned <-
    first
      (UpdateMigrationPlanFailed (transition ^. #moduleName))
      (planMigrationChain (transition ^. #moduleName . #unModuleName) (transition ^. #candidateModule . #migrations) fromVersion toVersion)
  case planned of
    Nothing -> error "planTransition received unequal versions but no migration plan"
    Just sourcePlan -> Right (transition, sourcePlan)

commandMocks :: (Transition, MigrationPlan) -> [ProcessMock]
commandMocks (_, sourcePlan) =
  [ ProcessMock
      { command = "/bin/sh",
        args = ["-c", command],
        result = (ExitSuccess, "", "")
      }
  | migration <- sourcePlan ^. #steps,
    RunCommand command _ <- migration ^. #ops
  ]

snapshotTrackedFiles :: FilePath -> Manifest -> [FilePath] -> IO PureFS
snapshotTrackedFiles projectRoot manifest declaredTargets = do
  let tracked = Set.toAscList (Set.fromList (Map.keys (manifest ^. #files) <> declaredTargets))
      components = Set.toAscList (Set.fromList (tracked <> concatMap parents tracked))
  entries <- Map.fromList <$> traverse (\path -> (path,) <$> runEff (runFilesystem (inspectPath (projectRoot </> path)))) components
  let links = Map.mapMaybe (\case EntrySymlink target -> Just target; _ -> Nothing) entries
      directories = Map.keysSet (Map.filter (== EntryDirectory) entries)
  files <- fmap Map.fromList . fmap concat $ traverse (readTracked links entries) tracked
  pure PureFS {files, dirs = directories, links}
  where
    readTracked links _ path | any (`Map.member` links) (path : parents path) = pure []
    readTracked _ entries path = case Map.lookup path entries of
      Just EntryFile -> do
        content <- TIO.readFile (projectRoot </> path)
        pure [(path, content)]
      _ -> pure []

    parents path = takeWhile (\directory -> directory /= "." && directory /= "") (iterate takeDirectory (takeDirectory path))

migrationTouchedPaths :: [PlannedUpdateMigration] -> Set FilePath
migrationTouchedPaths = Set.fromList . concatMap (concatMap touched . (^. #stagedPlan . #ops))
  where
    touched (MoveFileInst source destination _) = [source, destination]
    touched (MoveDirInst source destination) = [source, destination]
    touched (DeleteFileInst path _) = [path]
    touched (DeleteDirInst path) = [path]
    touched (RemoveLineInst path _) = [path]
    touched RunCommandInst {} = []

migrationTouchesDirectories :: PlannedUpdateMigration -> Bool
migrationTouchesDirectories migration = any touchesDirectory (migration ^. #stagedPlan . #ops)
  where
    touchesDirectory MoveDirInst {} = True
    touchesDirectory DeleteDirInst {} = True
    touchesDirectory _ = False
