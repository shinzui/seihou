module Seihou.CLI.Update
  ( UpdateSelection (..),
    PromptPolicy (..),
    UpdateRequest (..),
    VersionChange (..),
    InputChangeSummary (..),
    CandidateArtifactKind (..),
    CandidateArtifact (..),
    PlannedUpdateMigration (..),
    UpdateWarning (..),
    UpdatePlan (..),
    CommandSummary (..),
    UpdateResult (..),
    UpdateError (..),
    planProjectUpdate,
    applyProjectUpdate,
    withProjectUpdate,
    isUpdateNoOp,
  )
where

import Control.Exception (SomeException, displayException, try)
import Control.Monad (foldM, forM, forM_, when)
import Data.Foldable (traverse_)
import Data.List (find, isPrefixOf)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust, mapMaybe, maybeToList)
import Data.Set qualified as Set
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Time (UTCTime, getCurrentTime)
import Effectful (runEff)
import Seihou.CLI.CommandExecution
import Seihou.CLI.InstallShared (installModuleDir)
import Seihou.CLI.Shared (deriveNamespace, toVarNameMap)
import Seihou.CLI.Update.Migrations
import Seihou.CLI.Update.Recovery
import Seihou.CLI.Update.Selection
import Seihou.CLI.Update.Source
import Seihou.CLI.Update.Types
import Seihou.Composition.Instance (ModuleInstance (..))
import Seihou.Composition.Plan (compileComposedPlan)
import Seihou.Composition.Recipe (expandRecipe)
import Seihou.Composition.Resolve
  ( PromptPermission (..),
    SavedInstanceValues,
    loadComposition,
    resolveWithPromptPermission,
  )
import Seihou.Core.Application (buildAppliedComposition, replaceAppliedComposition)
import Seihou.Core.Module (defaultSearchPaths, discoverRunnable)
import Seihou.Core.Types
import Seihou.Core.Version (parseVersion)
import Seihou.Effect.BaselineStore (pruneBaselines)
import Seihou.Effect.BaselineStoreInterp (runBaselineStore)
import Seihou.Effect.ConfigReader
import Seihou.Effect.ConfigReaderInterp (runConfigReader)
import Seihou.Effect.ConsoleInterp (runConsole)
import Seihou.Effect.FilesystemInterp (runFilesystem)
import Seihou.Effect.FilesystemPure (PureFS (..))
import Seihou.Effect.ManifestStore (readManifest, writeManifest)
import Seihou.Effect.ManifestStoreInterp (runManifestStore)
import Seihou.Effect.ProcessInterp (runProcessIO)
import Seihou.Engine.Baseline (manifestBaselineRefs)
import Seihou.Engine.Migrate (ExecutedMigrationPlan (..), MigrationOpInstance (..), classifyMigration, executeMigration)
import Seihou.Engine.Reconcile
import Seihou.Engine.UpdateTransaction
import Seihou.Manifest.Hash (hashContent)
import Seihou.Manifest.Types (currentManifestVersion)
import Seihou.Prelude
import System.Directory qualified as Directory
import System.Environment (getEnvironment)
import System.FilePath (takeDirectory)
import System.IO.Temp (createTempDirectory, getCanonicalTemporaryDirectory, withSystemTempDirectory)

-- | Lifetime-safe public planning entry point. Candidate clones exist for the
-- callback only, so an 'UpdatePlan' cannot accidentally outlive its sources.
withProjectUpdate ::
  UpdateRequest ->
  (Either UpdateError UpdatePlan -> IO a) ->
  IO a
withProjectUpdate request callback =
  withSystemTempDirectory "seihou-project-update" $ \sessionDirectory ->
    planProjectUpdateIn sessionDirectory request >>= callback

-- | Internal/test-facing planner. Prefer 'withProjectUpdate'; this form keeps
-- its temporary session until process exit or a test removes it.
planProjectUpdate :: UpdateRequest -> IO (Either UpdateError UpdatePlan)
planProjectUpdate request = do
  temporaryRoot <- getCanonicalTemporaryDirectory
  sessionDirectory <- createTempDirectory temporaryRoot "seihou-project-update"
  result <- planProjectUpdateIn sessionDirectory request
  case result of
    Left _ -> Directory.removePathForcibly sessionDirectory
    Right _ -> pure ()
  pure result

planProjectUpdateIn :: FilePath -> UpdateRequest -> IO (Either UpdateError UpdatePlan)
planProjectUpdateIn sessionDirectory request = do
  projectRoot <- Directory.getCurrentDirectory
  installedDirectory <- standardInstalledDirectory
  recovery <- recoverAtEntry projectRoot
  case recovery of
    Left err -> pure (Left err)
    Right () -> do
      let manifestPath = projectRoot </> ".seihou" </> "manifest.json"
          baselineDirectory = projectRoot </> ".seihou" </> "baselines"
      manifestResult <- readManifestIO manifestPath
      case manifestResult of
        Left err -> pure (Left err)
        Right manifest -> do
          now <- getCurrentTime
          seeded <- selectAndSeedLegacy request manifest now
          case seeded of
            Left err -> pure (Left err)
            Right (selected, seedWarnings) -> do
              staged <- stageCandidateSources sessionDirectory selected
              case staged of
                Left err -> pure (Left err)
                Right (catalog, sourceWarnings) -> do
                  plannedApplicationsResult <- traverse (planApplication request installedDirectory catalog now) selected
                  case sequence plannedApplicationsResult of
                    Left err -> pure (Left err)
                    Right plannedApplications -> do
                      let applicationInputs =
                            [ (Just previous, planned.modulesInOrder)
                            | (previous, planned) <- zip selected plannedApplications
                            ]
                      stagedMigrations <- planAndStageMigrations projectRoot manifest catalog applicationInputs
                      case stagedMigrations of
                        Left err -> pure (Left err)
                        Right migrationStage -> do
                          let (operations, owners, compositionWarnings) = combineApplicationPlans plannedApplications
                              selectedIds = Set.fromList (map (.candidate.applicationId) plannedApplications)
                          stageRoot <- materializeStagedProject sessionDirectory projectRoot migrationStage.filesystem operations
                          reconciliationResult <-
                            runEff $
                              runFilesystem $
                                runBaselineStore baselineDirectory $
                                  planReconciliation stageRoot migrationStage.manifest selectedIds operations owners
                          case reconciliationResult of
                            Left err -> pure (Left (UpdateReconciliationFailed err))
                            Right reconciliation -> do
                              evidence <- versionEvidence catalog selected plannedApplications
                              case evidence of
                                Left err -> pure (Left err)
                                Right (versionChanges, versionWarnings) -> do
                                  let usedArtifacts = artifactsUsedBy catalog plannedApplications
                                      priorReceipts = Map.unions (map (.commandReceipts) selected)
                                      commandPlan = planCommands request.commandPolicy priorReceipts operations
                                      warnings =
                                        seedWarnings
                                          <> sourceWarnings
                                          <> migrationStage.warnings
                                          <> compositionWarnings
                                          <> versionWarnings
                                      inputChanges = summarizeInputChanges seedWarnings plannedApplications
                                      transactionTargets = transactionTargetPaths manifest reconciliation migrationStage.plans
                                  observedProjectHashes <-
                                    observePaths
                                      projectRoot
                                      (Set.insert (".seihou" </> "manifest.json") transactionTargets)
                                  let snapshot =
                                        UpdateSnapshot
                                          { sessionDirectory,
                                            projectRoot,
                                            manifestPath,
                                            baselineDirectory,
                                            installedDirectory,
                                            originalManifest = manifest,
                                            candidateHashes = Map.fromList [(artifact.originalDirectory, artifact.contentHash) | artifact <- usedArtifacts],
                                            observedProjectHashes,
                                            transactionTargets
                                          }
                                  pure
                                    ( Right
                                        UpdatePlan
                                          { applications = map (.candidate) plannedApplications,
                                            versionChanges,
                                            inputChanges,
                                            migrations = migrationStage.plans,
                                            reconciliation,
                                            commandPlan,
                                            candidateArtifacts = usedArtifacts,
                                            warnings,
                                            request,
                                            snapshot,
                                            plannedApplications
                                          }
                                    )

applyProjectUpdate :: UpdatePlan -> IO (Either UpdateError UpdateResult)
applyProjectUpdate plan =
  Directory.withCurrentDirectory plan.snapshot.projectRoot $ do
    recovery <- recoverAtEntry plan.snapshot.projectRoot
    case recovery of
      Left err -> pure (Left err)
      Right () -> do
        stale <- stalePlanPaths plan
        if not (Set.null stale)
          then pure (Left (UpdatePlanStale stale))
          else
            if plan.request.dryRun
              then pure (Right (dryRunResult plan))
              else
                if not (Set.null (unresolvedPaths plan.reconciliation))
                  then pure (Left (UpdateHasUnresolvedPaths (unresolvedPaths plan.reconciliation)))
                  else
                    if isStructuredNoOp plan
                      then pure (Right (noOpResult plan))
                      else applyAcceptedPlan plan

applyAcceptedPlan :: UpdatePlan -> IO (Either UpdateError UpdateResult)
applyAcceptedPlan plan = do
  transactionResult <- beginUpdateTransaction plan.snapshot.projectRoot plan.snapshot.transactionTargets
  case transactionResult of
    Left err -> pure (Left (UpdateTransactionFailed err))
    Right transaction -> do
      backupResult <- prepareServiceBackups transaction plan.snapshot.installedDirectory plan.migrations plan.candidateArtifacts
      case backupResult of
        Left err -> abortUpdate transaction err
        Right () -> do
          now <- getCurrentTime
          migrated <- runRealMigrations now plan.snapshot.originalManifest plan.migrations
          case migrated of
            Left err -> abortUpdate transaction err
            Right migratedManifest -> do
              actualReconciliation <- planActualReconciliation plan migratedManifest
              case actualReconciliation of
                Left err -> abortUpdate transaction err
                Right actual -> case reapplyPlannedResolutions plan.reconciliation actual of
                  Left _ ->
                    abortUpdate
                      transaction
                      ( UpdateChangedAfterMigrationCommand
                          (reconciliationSummary plan.reconciliation)
                          (reconciliationSummary actual)
                      )
                  Right resolvedActual
                    | resolvedActual /= plan.reconciliation ->
                        abortUpdate
                          transaction
                          ( UpdateChangedAfterMigrationCommand
                              (reconciliationSummary plan.reconciliation)
                              (reconciliationSummary resolvedActual)
                          )
                    | otherwise -> do
                        let reconciliationManifest = migratedManifest {genAt = now}
                        appliedFiles <- applyReconciliation transaction resolvedActual reconciliationManifest
                        case appliedFiles of
                          Left err -> abortUpdate transaction (UpdateTransactionFailed err)
                          Right filesManifest -> do
                            commandResult <-
                              runEff $
                                runProcessIO $
                                  executeCommandPlan now plan.commandPlan
                            case commandResult of
                              Left err ->
                                abortUpdate
                                  transaction
                                  (UpdateCommandFailed err [ArbitraryCommandSideEffectsMayRemain])
                              Right completedReceipts -> do
                                let finalManifest = buildFinalManifest now plan filesManifest completedReceipts
                                markerResult <- setCommitMarkers transaction finalManifest
                                case markerResult of
                                  Left err -> abortUpdate transaction err
                                  Right () -> do
                                    publication <- publishCandidates plan.candidateArtifacts
                                    case publication of
                                      Left err -> abortUpdate transaction err
                                      Right () -> do
                                        written <- writeManifestIO plan.snapshot.manifestPath finalManifest
                                        case written of
                                          Left err -> abortUpdate transaction err
                                          Right () -> finishCommitted transaction plan finalManifest completedReceipts

planApplication ::
  UpdateRequest ->
  FilePath ->
  CandidateCatalog ->
  UTCTime ->
  AppliedComposition ->
  IO (Either UpdateError PlannedApplication)
planApplication request installedDirectory catalog now previous = do
  fallback <- defaultSearchPaths
  case candidateRoot catalog previous of
    Left err -> pure (Left err)
    Right (primary, recipeAdditional, recipeOverrides, targetArtifact) -> do
      let allAdditional = recipeAdditional <> previous.additionalModules
      loaded <- loadComposition (catalog.searchRoot : fallback) primary allAdditional
      case loaded of
        Left err -> pure (Left (CandidateLoadFailed primary.unModuleName err))
        Right modulesInOrder -> do
          let savedValues
                | request.reconfigure = Map.empty
                | otherwise = savedInstanceValues previous
              namespace = fromMaybe (deriveNamespace primary) previous.namespace
              context = fromMaybe "" previous.context
          resolved <- resolveApplicationValues request namespace context savedValues recipeOverrides modulesInOrder
          case resolved of
            Left err -> pure (Left err)
            Right resolvedValues -> do
              compiled <-
                compileComposedPlan
                  [ (instanceId, modul, directory, Map.map (.value) (resolvedValues Map.! instanceId))
                  | (instanceId, modul, directory) <- modulesInOrder
                  ]
              case compiled of
                Left errors -> pure (Left (UpdateCompositionFailed errors))
                Right (operations, compositionWarnings, rawOwners) -> do
                  let targetSource = publishedArtifactSource installedDirectory targetArtifact
                      candidate0 =
                        ( buildAppliedComposition
                            previous.target
                            targetSource
                            targetArtifact.version
                            previous.additionalModules
                            (Just namespace)
                            previous.context
                            modulesInOrder
                            resolvedValues
                            now
                        )
                          { applicationId = previous.applicationId
                          }
                      candidate =
                        setCompositionState
                          (map (publishInstanceSource installedDirectory catalog) candidate0.instances)
                          previous.commandReceipts
                          candidate0
                      desiredOwners =
                        Map.map
                          (\owner -> DesiredFileOwner owner (Set.singleton candidate.applicationId))
                          rawOwners
                      renderedWarnings = map compositionWarning compositionWarnings
                  pure
                    ( Right
                        PlannedApplication
                          { previous = Just previous,
                            candidate,
                            modulesInOrder,
                            resolvedValues,
                            operations,
                            desiredOwners
                          }
                    )
  where
    compositionWarning (FileOverwritten path old new) = CrossApplicationLastWriter path old new
    compositionWarning (ContentMerged path old new) = CrossApplicationLastWriter path old new

candidateRoot ::
  CandidateCatalog ->
  AppliedComposition ->
  Either UpdateError (ModuleName, [ModuleName], Map VarName Text, CandidateArtifact)
candidateRoot catalog previous = case previous.target of
  AppliedModuleTarget name -> do
    artifact <- lookupArtifact catalog CandidateModule name.unModuleName
    Right (name, [], Map.empty, artifact)
  AppliedRecipeTarget name -> do
    artifact <- lookupArtifact catalog CandidateRecipe name.unRecipeName
    recipe <- maybe (Left (CandidateArtifactMissing CandidateRecipe name.unRecipeName)) Right artifact.recipeDefinition
    (primary, additional, overrides, _, _) <- first (CandidateRepositoryInvalid name.unRecipeName) (expandRecipe recipe)
    Right (primary, additional, overrides, artifact)

lookupArtifact :: CandidateCatalog -> CandidateArtifactKind -> Text -> Either UpdateError CandidateArtifact
lookupArtifact catalog kind name =
  maybe (Left (CandidateArtifactMissing kind name)) Right (Map.lookup (kind, name) catalog.artifacts)

resolveApplicationValues ::
  UpdateRequest ->
  Text ->
  Text ->
  SavedInstanceValues ->
  Map VarName Text ->
  [(ModuleInstance, Module, FilePath)] ->
  IO (Either UpdateError (Map ModuleInstance (Map VarName ResolvedVar)))
resolveApplicationValues request namespace context saved recipeOverrides modulesInOrder = do
  envPairs <- getEnvironment
  configs <- loadConfigMaps namespace context
  case configs of
    Left err -> pure (Left err)
    Right (localConfig, namespaceConfig, contextConfig, globalConfig) -> do
      let cli = Map.fromList [(VarName name, value) | (name, value) <- request.varOverrides]
          overrides = Map.union cli recipeOverrides
          env = Map.fromList [(T.pack key, T.pack value) | (key, value) <- envPairs]
          promptPermission = case request.promptPolicy of
            AllowPrompts -> PromptsAllowed
            ForbidPrompts -> PromptsForbidden
      result <-
        runEff $
          runConsole $
            resolveWithPromptPermission
              promptPermission
              modulesInOrder
              saved
              overrides
              env
              namespace
              context
              localConfig
              namespaceConfig
              contextConfig
              globalConfig
      pure (first UpdateVariableErrors result)

loadConfigMaps :: Text -> Text -> IO (Either UpdateError (Map VarName Text, Map VarName Text, Map VarName Text, Map VarName Text))
loadConfigMaps namespace context =
  runEff $ runConfigReader $ do
    local <- readLocalConfig
    namespaceValues <- readNamespaceConfig namespace
    contextValues <- readContextConfig context
    global <- readGlobalConfig
    pure $ do
      local' <- configResult local
      namespace' <- configResult namespaceValues
      context' <- configResult contextValues
      global' <- configResult global
      Right (toVarNameMap local', toVarNameMap namespace', toVarNameMap context', toVarNameMap global')
  where
    configResult = first (UpdateConfigurationFailed . T.pack . show)

selectAndSeedLegacy ::
  UpdateRequest ->
  Manifest ->
  UTCTime ->
  IO (Either UpdateError ([AppliedComposition], [UpdateWarning]))
selectAndSeedLegacy request manifest now = case selectApplications request.selection manifest of
  Left err -> pure (Left err)
  Right (RecordedSelection selected) -> pure (Right (selected, []))
  Right (LegacySelection name) -> seedLegacyApplication request manifest now name

seedLegacyApplication ::
  UpdateRequest -> Manifest -> UTCTime -> Text -> IO (Either UpdateError ([AppliedComposition], [UpdateWarning]))
seedLegacyApplication request manifest now requested = do
  searchPaths <- defaultSearchPaths
  discovered <- discoverRunnable searchPaths (ModuleName requested)
  case discovered of
    Left err -> pure (Left (CandidateLoadFailed requested err))
    Right runnable -> do
      let root = case runnable of
            RunnableModule modul directory -> Right (AppliedModuleTarget modul.name, modul.name, [], Map.empty, directory, modul.version)
            RunnableRecipe recipe directory -> do
              (primary, additional, overrides, _, _) <- first (CandidateRepositoryInvalid requested) (expandRecipe recipe)
              Right (AppliedRecipeTarget recipe.name, primary, additional, overrides, directory, recipe.version)
            _ -> Left (CandidateArtifactMissing CandidateModule requested)
      case root of
        Left err -> pure (Left err)
        Right (target, primary, additional, recipeOverrides, targetSource, targetVersion) -> do
          loaded <- loadComposition searchPaths primary additional
          case loaded of
            Left err -> pure (Left (CandidateLoadFailed requested err))
            Right modulesInOrder -> do
              let (saved, warnings) = legacySavedValues manifest modulesInOrder
                  namespace = deriveNamespace primary
              resolved <- resolveApplicationValues request namespace "" saved recipeOverrides modulesInOrder
              case resolved of
                Left err -> pure (Left err)
                Right resolvedValues -> do
                  let provisional0 =
                        buildAppliedComposition target targetSource targetVersion [] (Just namespace) Nothing modulesInOrder resolvedValues now
                      provisional = provisional0 {instances = map (restoreLegacyVersion manifest) provisional0.instances}
                  pure (Right ([provisional], warnings))

legacySavedValues ::
  Manifest ->
  [(ModuleInstance, Module, FilePath)] ->
  (SavedInstanceValues, [UpdateWarning])
legacySavedValues manifest modulesInOrder = (saved, warnings)
  where
    declarations = [(instanceId, declaration) | (instanceId, modul, _) <- modulesInOrder, declaration <- modul.vars]
    counts = Map.fromListWith (+) [(declaration.name, 1 :: Int) | (_, declaration) <- declarations]
    saved =
      Map.fromListWith
        Map.union
        [ (instanceId, Map.singleton declaration.name value)
        | (instanceId, declaration) <- declarations,
          Map.lookup declaration.name counts == Just 1,
          Just value <- [Map.lookup declaration.name manifest.vars]
        ]
    ambiguous =
      [ AmbiguousLegacyValue name
      | (name, count) <- Map.toAscList counts,
        count > 1,
        Map.member name manifest.vars
      ]
    missing =
      [ MissingLegacyValue declaration.name
      | (_, declaration) <- declarations,
        declaration.required,
        Map.notMember declaration.name manifest.vars
      ]
    warnings = ambiguous <> missing

restoreLegacyVersion :: Manifest -> AppliedInstanceState -> AppliedInstanceState
restoreLegacyVersion manifest state =
  case find (\applied -> applied.name == state.name && applied.parentVars == state.parentVars) manifest.modules of
    Nothing -> state
    Just applied ->
      AppliedInstanceState
        { name = state.name,
          parentVars = state.parentVars,
          source = applied.source,
          moduleVersion = applied.moduleVersion,
          resolvedVars = state.resolvedVars
        }

savedInstanceValues :: AppliedComposition -> SavedInstanceValues
savedInstanceValues application =
  Map.fromList
    [ (ModuleInstance state.name state.parentVars, state.resolvedVars)
    | state <- application.instances
    ]

combineApplicationPlans ::
  [PlannedApplication] ->
  ([Operation], Map FilePath DesiredFileOwner, [UpdateWarning])
combineApplicationPlans = foldl' addApplication ([], Map.empty, [])
  where
    addApplication (operations, owners, warnings) application =
      let crossWarnings =
            [ CrossApplicationLastWriter path prior.moduleName next.moduleName
            | (path, next) <- Map.toAscList application.desiredOwners,
              Just prior <- [Map.lookup path owners],
              prior.moduleName /= next.moduleName
            ]
          mergedOwners = Map.unionWith mergeOwner application.desiredOwners owners
       in (operations <> application.operations, mergedOwners, warnings <> crossWarnings)
    mergeOwner newest prior =
      DesiredFileOwner newest.moduleName (Set.union newest.applicationIds prior.applicationIds)

materializeStagedProject :: FilePath -> FilePath -> PureFS -> [Operation] -> IO FilePath
materializeStagedProject sessionDirectory projectRoot filesystem operations = do
  let stageRoot = sessionDirectory </> "staged-project"
  Directory.createDirectoryIfMissing True stageRoot
  forM_ (Map.toAscList filesystem.files) $ \(path, content) -> writeStageFile stageRoot path content
  forM_ (Set.toAscList filesystem.dirs) $ \path -> Directory.createDirectoryIfMissing True (stageRoot </> path)
  forM_ (Set.toAscList (Set.fromList (mapMaybe operationDestination operations))) $ \path -> do
    stagedExists <- Directory.doesFileExist (stageRoot </> path)
    when (not stagedExists) $ do
      let projectPath = projectRoot </> path
      projectExists <- Directory.doesFileExist projectPath
      when projectExists (TIO.readFile projectPath >>= writeStageFile stageRoot path)
  pure stageRoot

writeStageFile :: FilePath -> FilePath -> Text -> IO ()
writeStageFile root path content = do
  Directory.createDirectoryIfMissing True (takeDirectory (root </> path))
  TIO.writeFile (root </> path) content

operationDestination :: Operation -> Maybe FilePath
operationDestination WriteFileOp {dest} = Just dest
operationDestination CopyFileOp {dest} = Just dest
operationDestination PatchFileOp {dest} = Just dest
operationDestination _ = Nothing

versionEvidence ::
  CandidateCatalog ->
  [AppliedComposition] ->
  [PlannedApplication] ->
  IO (Either UpdateError ([VersionChange], [UpdateWarning]))
versionEvidence catalog previousApplications plannedApplications = do
  evidence <- fmap concat $ sequence (zipWith applicationEvidence previousApplications plannedApplications)
  pure $ do
    changes <- sequence evidence
    let actualChanges = filter isActualChange changes
    traverse_ validateVersionChange actualChanges
    let unique = Map.elems (Map.fromList [(versionKey change, change) | change <- actualChanges])
        warnings =
          [ SameVersionContentChanged change.name
          | change <- unique,
            change.sameVersionContentChanged,
            isJust change.fromVersion
          ]
    Right (unique, warnings)
  where
    applicationEvidence previous planned = do
      instanceEvidence <- traverse (instanceVersionEvidence previous) planned.modulesInOrder
      targetEvidence <- targetVersionEvidence previous
      pure (targetEvidence : instanceEvidence)

    instanceVersionEvidence previous (instanceId, candidateModule, _) = do
      let prior = find (\state -> state.name == instanceId.instanceModule && state.parentVars == instanceId.instanceParentVars) previous.instances
      case prior of
        Nothing -> pure (Right (VersionChange candidateModule.name.unModuleName Nothing candidateModule.version False))
        Just old -> compareArtifact old.name.unModuleName old.moduleVersion candidateModule.version old.source CandidateModule

    targetVersionEvidence previous = case previous.target of
      AppliedModuleTarget _ -> pure (Right (VersionChange "" Nothing Nothing False))
      AppliedRecipeTarget name -> compareArtifact name.unRecipeName previous.targetVersion (candidateVersion CandidateRecipe name.unRecipeName) previous.targetSource CandidateRecipe

    candidateVersion kind name = (.version) =<< Map.lookup (kind, name) catalog.artifacts

    compareArtifact name fromVersion toVersion oldSource kind = do
      oldHashResult <- try @SomeException (hashArtifactDirectory oldSource)
      let candidateHash = (.contentHash) <$> Map.lookup (kind, name) catalog.artifacts
          changed = case (oldHashResult, candidateHash) of
            (Right oldHash, Just newHash) -> oldHash /= newHash
            _ -> True
      pure
        ( Right
            VersionChange
              { name,
                fromVersion,
                toVersion,
                sameVersionContentChanged = changed && fromVersion == toVersion
              }
        )

    versionKey change = (change.name, change.fromVersion, change.toVersion, change.sameVersionContentChanged)
    isActualChange change =
      not (T.null change.name)
        && (change.fromVersion /= change.toVersion || change.sameVersionContentChanged)

validateVersionChange :: VersionChange -> Either UpdateError ()
validateVersionChange change
  | T.null change.name = Right ()
  | otherwise = case (change.fromVersion, change.toVersion) of
      (Just fromText, Just toText) -> do
        fromVersion <- maybe (Left (CandidateVersionInvalid change.name fromText)) Right (parseVersion fromText)
        toVersion <- maybe (Left (CandidateVersionInvalid change.name toText)) Right (parseVersion toText)
        if toVersion < fromVersion
          then Left (CandidateDowngrade change.name change.fromVersion change.toVersion)
          else Right ()
      _ -> Right ()

artifactsUsedBy :: CandidateCatalog -> [PlannedApplication] -> [CandidateArtifact]
artifactsUsedBy catalog planned = Map.elems (Map.restrictKeys catalog.artifacts keys)
  where
    keys =
      Set.fromList $
        concatMap applicationKeys planned
    applicationKeys application =
      targetKey application.candidate.target
        : [(CandidateModule, modul.name.unModuleName) | (_, modul, _) <- application.modulesInOrder]
    targetKey (AppliedModuleTarget name) = (CandidateModule, name.unModuleName)
    targetKey (AppliedRecipeTarget name) = (CandidateRecipe, name.unRecipeName)

summarizeInputChanges :: [UpdateWarning] -> [PlannedApplication] -> InputChangeSummary
summarizeInputChanges seedWarnings planned =
  foldl' summarizeApplication emptySummary planned
  where
    emptySummary =
      InputChangeSummary
        { reused = 0,
          overridden = 0,
          newlyResolved = 0,
          removed = 0,
          ambiguousLegacy = [name | AmbiguousLegacyValue name <- seedWarnings]
        }
    summarizeApplication summary application =
      let prior = maybe Map.empty savedInstanceValues application.previous
          candidateValues = application.resolvedValues
          resolvedList =
            [ (instanceId, name, value)
            | (instanceId, values) <- Map.toList candidateValues,
              (name, value) <- Map.toList values
            ]
          reusedCount = length [() | (_, _, value) <- resolvedList, value.source == FromApplication]
          overriddenCount =
            length
              [ ()
              | (instanceId, name, value) <- resolvedList,
                value.source == FromCLI,
                Map.member name (Map.findWithDefault Map.empty instanceId prior)
              ]
          newCount =
            length
              [ ()
              | (instanceId, name, _) <- resolvedList,
                Map.notMember name (Map.findWithDefault Map.empty instanceId prior)
              ]
          removedCount =
            length
              [ ()
              | (instanceId, oldValues) <- Map.toList prior,
                name <- Map.keys oldValues,
                Map.notMember name (Map.findWithDefault Map.empty instanceId candidateValues)
              ]
       in summary
            { reused = summary.reused + reusedCount,
              overridden = summary.overridden + overriddenCount,
              newlyResolved = summary.newlyResolved + newCount,
              removed = summary.removed + removedCount
            }

transactionTargetPaths :: Manifest -> ReconciliationPlan -> [PlannedUpdateMigration] -> Set FilePath
transactionTargetPaths manifest reconciliation migrations =
  Map.keysSet reconciliation.files `Set.union` Set.fromList (concatMap migrationTargets migrations)
  where
    migrationTargets migration = concatMap targets migration.stagedPlan.planOps
    targets (MoveFileInst source destination _) = [source, destination]
    targets (DeleteFileInst path _) = [path]
    targets (MoveDirInst source destination) =
      concatMap (moveDirectoryTarget source destination) (Map.keys manifest.files)
    targets (DeleteDirInst path) = filter (isPathAtOrBelow path) (Map.keys manifest.files)
    targets RunCommandInst {} = []
    moveDirectoryTarget source destination path
      | isPathAtOrBelow source path = [path, replacePrefix source destination path]
      | isPathAtOrBelow destination path = [path]
      | otherwise = []

isPathAtOrBelow :: FilePath -> FilePath -> Bool
isPathAtOrBelow directory path = path == directory || (directory <> "/") `isPrefixOf` path

replacePrefix :: FilePath -> FilePath -> FilePath -> FilePath
replacePrefix source destination path
  | path == source = destination
  | otherwise = destination <> drop (length source) path

observePaths :: FilePath -> Set FilePath -> IO (Map FilePath (Maybe SHA256))
observePaths projectRoot paths =
  Map.fromList <$> traverse observe (Set.toAscList paths)
  where
    observe path = do
      let fullPath = projectRoot </> path
      exists <- Directory.doesFileExist fullPath
      hash <- if exists then Just . hashContent <$> TIO.readFile fullPath else pure Nothing
      pure (path, hash)

stalePlanPaths :: UpdatePlan -> IO (Set FilePath)
stalePlanPaths plan = do
  currentProject <-
    observePaths
      plan.snapshot.projectRoot
      (Map.keysSet plan.snapshot.observedProjectHashes)
  candidateChecks <- forM (Map.toAscList plan.snapshot.candidateHashes) $ \(path, expected) -> do
    current <- try @SomeException (hashArtifactDirectory path)
    pure $ case current of
      Right actual | actual == expected -> []
      _ -> [path]
  let projectChanges =
        Map.keysSet
          (Map.filterWithKey (\path observed -> Map.lookup path currentProject /= Just observed) plan.snapshot.observedProjectHashes)
  pure (Set.union projectChanges (Set.fromList (concat candidateChecks)))

planActualReconciliation :: UpdatePlan -> Manifest -> IO (Either UpdateError ReconciliationPlan)
planActualReconciliation plan manifest = do
  let (operations, owners, _) = combineApplicationPlans plan.plannedApplications
      selected = Set.fromList (map (.applicationId) plan.applications)
  result <-
    runEff $
      runFilesystem $
        runBaselineStore plan.snapshot.baselineDirectory $
          planReconciliation plan.snapshot.projectRoot manifest selected operations owners
  pure (first UpdateReconciliationFailed result)

-- | Reapply choices gathered after the initial read-only plan to the
-- reconciliation rebuilt after real migration commands. Exact equality is
-- still required afterward, so a command-induced classification or content
-- change remains a stale-plan failure rather than inheriting an old choice.
reapplyPlannedResolutions ::
  ReconciliationPlan ->
  ReconciliationPlan ->
  Either ReconciliationError ReconciliationPlan
reapplyPlannedResolutions planned actual =
  foldM reapplyOne actual (Map.toAscList planned.files)
  where
    reapplyOne actual (path, FileConflict _ _ _ _ _ _ (Just resolved)) =
      resolveFileConflict path resolved.choice actual
    reapplyOne actual (path, FileOrphanEdited _ _ _ _ (Just choice)) =
      resolveEditedOrphan path choice actual
    reapplyOne actual _ = Right actual

runRealMigrations :: UTCTime -> Manifest -> [PlannedUpdateMigration] -> IO (Either UpdateError Manifest)
runRealMigrations now manifest migrations =
  runEff $ runFilesystem $ runProcessIO $ go manifest migrations
  where
    go current [] = pure (Right current)
    go current (migration : rest) = do
      classified <- classifyMigration current migration.sourcePlan
      case classified of
        Left err -> pure (Left (UpdateMigrationFailed migration.moduleName err))
        Right executable -> do
          executed <- executeMigration False executable current now
          case executed of
            Left err -> pure (Left (UpdateMigrationFailed migration.moduleName err))
            Right next -> go next rest

buildFinalManifest :: UTCTime -> UpdatePlan -> Manifest -> [CommandReceipt] -> Manifest
buildFinalManifest now plan filesManifest completedReceipts =
  Manifest
    { version = currentManifestVersion,
      genAt = now,
      modules = updateAppliedModules filesManifest.modules filesManifest.applications plan.plannedApplications now,
      vars = Map.union candidateVars filesManifest.vars,
      files = filesManifest.files,
      applications = foldl' (flip replaceAppliedComposition) filesManifest.applications finalApplications,
      recipe = updatedRecipe,
      blueprint = filesManifest.blueprint
    }
  where
    finalApplications = map finalizeApplication plan.plannedApplications
    finalizeApplication application =
      let priorReceipts = maybe Map.empty (.commandReceipts) application.previous
          applicationPlan = planCommands plan.request.commandPolicy priorReceipts application.operations
          receipts = finalizeCommandReceipts applicationPlan completedReceipts priorReceipts
       in setCompositionState application.candidate.instances receipts application.candidate
    candidateVars =
      Map.unions
        [ Map.map (varValueToText . (.value)) values
        | application <- plan.plannedApplications,
          values <- Map.elems application.resolvedValues
        ]
    updatedRecipe =
      foldl' updateRecipe filesManifest.recipe finalApplications
    updateRecipe current application = case application.target of
      AppliedRecipeTarget name -> Just AppliedRecipe {name, recipeVersion = application.targetVersion, appliedAt = now}
      AppliedModuleTarget _ -> current

updateAppliedModules :: [AppliedModule] -> [AppliedComposition] -> [PlannedApplication] -> UTCTime -> [AppliedModule]
updateAppliedModules existing recordedApplications applications now =
  let modulesInOrder = concatMap (.modulesInOrder) applications
      candidateKeys = Set.fromList [(instanceId.instanceModule, instanceId.instanceParentVars) | (instanceId, _, _) <- modulesInOrder]
      selectedIds = Set.fromList (map (.candidate.applicationId) applications)
      priorSelectedKeys =
        Set.fromList
          [ (state.name, state.parentVars)
          | application <- applications,
            previous <- maybeToList application.previous,
            state <- previous.instances
          ]
      protectedKeys =
        Set.fromList
          [ (state.name, state.parentVars)
          | application <- recordedApplications,
            Set.notMember application.applicationId selectedIds,
            state <- application.instances
          ]
      replacedOrRemoved key =
        Set.member key candidateKeys
          || (Set.member key priorSelectedKeys && Set.notMember key protectedKeys)
      retained = filter (not . replacedOrRemoved . (\applied -> (applied.name, applied.parentVars))) existing
      updated =
        [ AppliedModule
            { name = instanceId.instanceModule,
              parentVars = instanceId.instanceParentVars,
              source = publishInstanceDirectory application instanceId,
              moduleVersion = modul.version,
              appliedAt = now,
              removal = modul.removal
            }
        | (application, instanceId, modul) <- deduplicateInstances applications
        ]
   in retained <> updated
  where
    deduplicateInstances = go Set.empty . concatMap expand
      where
        expand application =
          [ (application, instanceId, modul)
          | (instanceId, modul, _) <- application.modulesInOrder
          ]
        go _ [] = []
        go seen (entry@(_, instanceId, _) : rest)
          | Set.member key seen = go seen rest
          | otherwise = entry : go (Set.insert key seen) rest
          where
            key = (instanceId.instanceModule, instanceId.instanceParentVars)

    publishInstanceDirectory application instanceId =
      case find (\state -> state.name == instanceId.instanceModule && state.parentVars == instanceId.instanceParentVars) application.candidate.instances of
        Just state -> state.source
        Nothing -> error "candidate application lost a loaded module instance"

setCompositionState :: [AppliedInstanceState] -> Map CommandFingerprint CommandReceipt -> AppliedComposition -> AppliedComposition
setCompositionState instances receipts composition =
  AppliedComposition
    { applicationId = composition.applicationId,
      target = composition.target,
      targetSource = composition.targetSource,
      targetVersion = composition.targetVersion,
      additionalModules = composition.additionalModules,
      namespace = composition.namespace,
      context = composition.context,
      instances,
      commandReceipts = receipts,
      appliedAt = composition.appliedAt
    }

publishInstanceSource :: FilePath -> CandidateCatalog -> AppliedInstanceState -> AppliedInstanceState
publishInstanceSource installedDirectory catalog state =
  case Map.lookup (CandidateModule, state.name.unModuleName) catalog.artifacts of
    Nothing -> state
    Just artifact ->
      AppliedInstanceState
        { name = state.name,
          parentVars = state.parentVars,
          source = publishedArtifactSource installedDirectory artifact,
          moduleVersion = state.moduleVersion,
          resolvedVars = state.resolvedVars
        }

publishedArtifactSource :: FilePath -> CandidateArtifact -> FilePath
publishedArtifactSource installedDirectory artifact =
  if isJust artifact.sourceUrl
    then installedDirectory </> T.unpack artifact.name
    else artifact.originalDirectory

publishCandidates :: [CandidateArtifact] -> IO (Either UpdateError ())
publishCandidates artifacts = do
  result <- try @SomeException $
    forM_ artifacts $ \artifact -> case artifact.sourceUrl of
      Nothing -> pure ()
      Just sourceUrl ->
        installModuleDir
          artifact.originalDirectory
          (T.unpack artifact.name)
          sourceUrl
          artifact.repoName
          artifact.version
          artifact.tags
  pure $ first (UpdateCachePublicationFailed . T.pack . displayException) result

setCommitMarkers :: UpdateTransaction -> Manifest -> IO (Either UpdateError ())
setCommitMarkers transaction manifest = do
  core <- setUpdateTransactionExpectedManifest transaction manifest
  case core of
    Left err -> pure (Left (UpdateTransactionFailed err))
    Right () -> setServiceExpectedManifest transaction manifest

writeManifestIO :: FilePath -> Manifest -> IO (Either UpdateError ())
writeManifestIO path manifest = do
  result <- try @SomeException $ runEff $ runFilesystem $ runManifestStore path $ writeManifest manifest
  pure $ first (UpdateManifestWriteFailed . T.pack . displayException) result

readManifestIO :: FilePath -> IO (Either UpdateError Manifest)
readManifestIO path = do
  result <- try @SomeException $ runEff $ runFilesystem $ runManifestStore path readManifest
  pure $ case result of
    Left err -> Left (UpdateManifestUnreadable path (T.pack (displayException err)))
    Right (Left err) -> Left (UpdateManifestUnreadable path err)
    Right (Right Nothing) -> Left (UpdateManifestMissing path)
    Right (Right (Just manifest)) -> Right manifest

abortUpdate :: UpdateTransaction -> UpdateError -> IO (Either UpdateError a)
abortUpdate transaction original = do
  serviceRestore <- restoreServiceBackups transaction
  coreRestore <- rollbackUpdateTransaction transaction
  pure $ case (serviceRestore, coreRestore) of
    (Left restoreError, _) -> Left restoreError
    (_, Left restoreError) -> Left (UpdateTransactionFailed restoreError)
    _ -> Left original

finishCommitted ::
  UpdateTransaction ->
  UpdatePlan ->
  Manifest ->
  [CommandReceipt] ->
  IO (Either UpdateError UpdateResult)
finishCommitted transaction plan manifest completedReceipts = do
  completion <- completeUpdateTransaction transaction
  pruneResult <-
    try @SomeException $
      runEff $
        runFilesystem $
          runBaselineStore plan.snapshot.baselineDirectory $
            pruneBaselines (manifestBaselineRefs manifest)
  let cleanupWarnings = case completion of
        Left err -> [RecoveryCleanupDeferred (T.pack (show err))]
        Right () -> []
      pruneWarnings = case pruneResult of
        Left err -> [BaselinePruneFailed (T.pack (displayException err))]
        Right _ -> []
      summary = summarizeCommandPlan plan.commandPlan
      originalBaselineRefs = manifestBaselineRefs plan.snapshot.originalManifest
      finalBaselineRefs = manifestBaselineRefs manifest
      changedBaselineRefs =
        (originalBaselineRefs Set.\\ finalBaselineRefs)
          `Set.union` (finalBaselineRefs Set.\\ originalBaselineRefs)
      baselinePaths =
        Set.map
          (\ref -> ".seihou" </> "baselines" </> T.unpack ref.unBaselineRef.unSHA256)
          changedBaselineRefs
      touched =
        plan.snapshot.transactionTargets
          `Set.union` baselinePaths
          `Set.union` Set.singleton (".seihou" </> "manifest.json")
  pure
    ( Right
        UpdateResult
          { updatedApplications = map (.applicationId) plan.applications,
            manifest,
            versions = plan.versionChanges,
            fileSummary = reconciliationSummary plan.reconciliation,
            commandSummary =
              CommandSummary
                { executed = length completedReceipts,
                  skippedUnchanged = summary.skippedUnchanged,
                  skippedDisabled = summary.skippedDisabled
                },
            touchedPaths = touched,
            warnings = plan.warnings <> cleanupWarnings <> pruneWarnings
          }
    )

recoverAtEntry :: FilePath -> IO (Either UpdateError ())
recoverAtEntry projectRoot = do
  serviceResults <- recoverServiceBackups projectRoot
  case [err | Left err <- serviceResults] of
    firstFailure : _ -> pure (Left firstFailure)
    [] -> do
      coreResults <- recoverIncompleteTransactions projectRoot
      let failures = [err | Left err <- coreResults]
      pure $ if null failures then Right () else Left (UpdateRecoveryFailed failures)

standardInstalledDirectory :: IO FilePath
standardInstalledDirectory = do
  searchPaths <- defaultSearchPaths
  pure (last searchPaths)

dryRunResult :: UpdatePlan -> UpdateResult
dryRunResult plan =
  (noOpResult plan)
    { versions = plan.versionChanges,
      fileSummary = reconciliationSummary plan.reconciliation,
      commandSummary = commandSummaryForPlan plan.commandPlan,
      warnings = plan.warnings
    }

noOpResult :: UpdatePlan -> UpdateResult
noOpResult plan =
  UpdateResult
    { updatedApplications = [],
      manifest = plan.snapshot.originalManifest,
      versions = [],
      fileSummary = reconciliationSummary plan.reconciliation,
      commandSummary = CommandSummary 0 0 0,
      touchedPaths = Set.empty,
      warnings = plan.warnings
    }

commandSummaryForPlan :: CommandPlan -> CommandSummary
commandSummaryForPlan commandPlan =
  let summary = summarizeCommandPlan commandPlan
   in CommandSummary summary.willRun summary.skippedUnchanged summary.skippedDisabled

isUpdateNoOp :: UpdatePlan -> Bool
isUpdateNoOp plan =
  null plan.versionChanges
    && null plan.migrations
    && plan.inputChanges.overridden == 0
    && plan.inputChanges.newlyResolved == 0
    && plan.inputChanges.removed == 0
    && (summarizeCommandPlan plan.commandPlan).willRun == 0
    && all unchangedFile (Map.elems plan.reconciliation.files)
    && and (zipWith sameApplication (mapMaybe (.previous) plan.plannedApplications) plan.applications)
  where
    unchangedFile FileUnchanged {} = True
    unchangedFile _ = False
    sameApplication previous candidate =
      previous.target == candidate.target
        && previous.targetSource == candidate.targetSource
        && previous.targetVersion == candidate.targetVersion
        && previous.additionalModules == candidate.additionalModules
        && previous.namespace == candidate.namespace
        && previous.context == candidate.context
        && previous.instances == candidate.instances
        && previous.commandReceipts == candidate.commandReceipts

isStructuredNoOp :: UpdatePlan -> Bool
isStructuredNoOp = isUpdateNoOp

varValueToText :: VarValue -> Text
varValueToText (VText value) = value
varValueToText (VBool True) = "true"
varValueToText (VBool False) = "false"
varValueToText (VInt value) = T.pack (show value)
varValueToText (VList values) = T.intercalate "," (map varValueToText values)
