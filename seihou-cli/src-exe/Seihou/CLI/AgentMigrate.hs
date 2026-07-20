{-# LANGUAGE TemplateHaskell #-}

module Seihou.CLI.AgentMigrate
  ( handleAgentMigrate,
  )
where

import Data.FileEmbed (embedFile)
import Data.Maybe (maybeToList)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Data.Time.Clock (getCurrentTime)
import Seihou.CLI.AgentCompletion
  ( AgentModelConfig (..),
    AgentProvider (..),
    buildAgentCompletionRequest,
    runAgentCompletion,
  )
import Seihou.CLI.AgentLaunch (gatherAgentContext)
import Seihou.CLI.AgentLaunchExec (launchConfiguredAgentAddingDirs)
import Seihou.CLI.AppliedBlueprintMigration (recordAppliedBlueprintMigration)
import Seihou.CLI.BlueprintExecution
  ( BlueprintExecutionRequest (..),
    PreparedBlueprintExecution (..),
    prepareBlueprintExecution,
  )
import Seihou.CLI.BlueprintMigration
  ( BlueprintMigrationLaunchFailure (..),
    BlueprintMigrationRunResult (..),
    formatBlueprintMigrationDebugOutput,
    pendingBlueprintMigrations,
    renderBlueprintMigrationSystemPrompt,
    runBlueprintMigrationsWith,
  )
import Seihou.CLI.Commands (BlueprintMigrationOpts (..))
import Seihou.CLI.Shared (formatVarError, logIO)
import Seihou.Core.Blueprint (validateBlueprint)
import Seihou.Core.Migration
  ( BlueprintMigration (..),
    BlueprintMigrationPlan (..),
    MigrationPlanError (..),
    planBlueprintMigrationChain,
  )
import Seihou.Core.Module (defaultSearchPaths, discoverRunnable)
import Seihou.Core.Types
import Seihou.Core.Version (Version, parseVersion, renderVersion)
import Seihou.Effect.FilesystemInterp (runFilesystem)
import Seihou.Effect.Logger (logError)
import Seihou.Effect.ManifestStore (readManifest)
import Seihou.Effect.ManifestStoreInterp (runManifestStore)
import Seihou.Prelude
import System.Exit (ExitCode (..), exitFailure, exitWith)

migrationPromptTemplate :: Text
migrationPromptTemplate = TE.decodeUtf8 $(embedFile "data/blueprint-migration-prompt.md")

handleAgentMigrate :: Bool -> AgentModelConfig -> BlueprintMigrationOpts -> IO ()
handleAgentMigrate debug modelConfig opts = do
  let level = if opts.migrateBlueprintVerbose then LogVerbose else LogNormal
      manifestPath = ".seihou" </> "manifest.json"

  (blueprint, blueprintDir) <- discoverMigrationBlueprint level opts.migrateBlueprintName
  validationResult <- validateBlueprint blueprintDir blueprint
  case validationResult of
    Left err -> exitErr level (renderModuleLoadError err)
    Right _ -> pure ()

  current <- parseRequestedVersion level "--from" opts.migrateBlueprintFrom
  target <- parseRequestedVersion level "--to" opts.migrateBlueprintTo
  planned <-
    case planBlueprintMigrationChain blueprint.name.unModuleName blueprint.migrations current target of
      Left err -> exitErr level (renderPlanError err)
      Right Nothing -> do
        TIO.putStrLn "No blueprint migration needed: --from and --to resolve to the same version."
        pure Nothing
      Right (Just migrationPlan) -> pure (Just migrationPlan)

  case planned of
    Nothing -> pure ()
    Just migrationPlan -> do
      receipts <- readMigrationReceipts level manifestPath
      let pending =
            pendingBlueprintMigrations
              opts.migrateBlueprintRerun
              blueprint.name
              receipts
              migrationPlan
      if null pending
        then reportNoPending migrationPlan
        else do
          prepared <- prepare level modelConfig opts blueprint blueprintDir
          context <- gatherAgentContext
          let renderStep position total migration =
                renderBlueprintMigrationSystemPrompt
                  migrationPromptTemplate
                  context
                  prepared
                  position
                  total
                  migration
              renderDebugStep position total migration =
                renderStep position total migration
                  <> maybe
                    ""
                    ("\n\n===== Initial user instruction =====\n" <>)
                    opts.migrateBlueprintPrompt

          if debug
            then TIO.putStrLn (formatBlueprintMigrationDebugOutput renderDebugStep pending)
            else do
              result <-
                runBlueprintMigrationsWith
                  (launchMigration modelConfig opts prepared renderStep)
                  (recordMigration manifestPath blueprint)
                  pending
              handleRunResult level blueprint.name result

discoverMigrationBlueprint :: LogLevel -> ModuleName -> IO (Blueprint, FilePath)
discoverMigrationBlueprint level requestedName = do
  searchPaths <- defaultSearchPaths
  runnableResult <- discoverRunnable searchPaths requestedName
  case runnableResult of
    Right (RunnableBlueprint blueprint dir) -> pure (blueprint, dir)
    Right (RunnableModule _ _) ->
      exitErr level $ "'" <> requestedName.unModuleName <> "' is a module, not a blueprint."
    Right (RunnableRecipe _ _) ->
      exitErr level $ "'" <> requestedName.unModuleName <> "' is a recipe, not a blueprint."
    Right (RunnableAgentPrompt _ _) ->
      exitErr level $ "'" <> requestedName.unModuleName <> "' is a prompt, not a blueprint."
    Left err -> exitErr level (renderModuleLoadError err)

parseRequestedVersion :: LogLevel -> Text -> Text -> IO Version
parseRequestedVersion level flag raw =
  case parseVersion raw of
    Just version -> pure version
    Nothing -> exitErr level (flag <> " value '" <> raw <> "' is not a valid dotted numeric version.")

readMigrationReceipts :: LogLevel -> FilePath -> IO [AppliedBlueprintMigration]
readMigrationReceipts level manifestPath = do
  result <- runEff $ runFilesystem $ runManifestStore manifestPath readManifest
  case result of
    Left err -> exitErr level ("Error reading migration receipts: " <> err)
    Right Nothing -> pure []
    Right (Just manifest) -> pure manifest.blueprintMigrations

prepare ::
  LogLevel ->
  AgentModelConfig ->
  BlueprintMigrationOpts ->
  Blueprint ->
  FilePath ->
  IO PreparedBlueprintExecution
prepare level modelConfig opts blueprint blueprintDir = do
  let providerCanMountFiles =
        modelConfig.agentProvider == AgentProviderClaudeCli
          || modelConfig.agentProvider == AgentProviderCodexCli
  result <-
    prepareBlueprintExecution
      BlueprintExecutionRequest
        { executionBlueprint = blueprint,
          executionBlueprintDir = blueprintDir,
          executionVariableOverrides = opts.migrateBlueprintVars,
          executionNamespaceOverride = opts.migrateBlueprintNamespace,
          executionContextOverride = opts.migrateBlueprintContext,
          executionCanMountFiles = providerCanMountFiles,
          executionLogLevel = level
        }
  case result of
    Left errs -> do
      logIO level $ logError "Error resolving blueprint migration variables:"
      mapM_ (logIO level . logError . ("  " <>) . formatVarError) errs
      exitFailure
    Right prepared -> pure prepared

launchMigration ::
  AgentModelConfig ->
  BlueprintMigrationOpts ->
  PreparedBlueprintExecution ->
  (Int -> Int -> BlueprintMigration -> Text) ->
  Int ->
  Int ->
  BlueprintMigration ->
  IO (Either BlueprintMigrationLaunchFailure ())
launchMigration modelConfig opts prepared renderStep position total migration = do
  TIO.putStrLn $
    "Running blueprint migration "
      <> T.pack (show position)
      <> "/"
      <> T.pack (show total)
      <> ": "
      <> migration.from
      <> " -> "
      <> migration.to
  let systemPrompt = renderStep position total migration
  case modelConfig.agentProvider of
    AgentProviderClaudeCli -> launchInteractive systemPrompt
    AgentProviderCodexCli -> launchInteractive systemPrompt
    AgentProviderAnthropic -> launchCompletion systemPrompt
    AgentProviderOpenAI -> launchCompletion systemPrompt
  where
    launchInteractive systemPrompt = do
      exitCode <-
        launchConfiguredAgentAddingDirs
          (maybeToList prepared.preparedMountedFilesDir)
          modelConfig
          prepared.preparedAllowedTools
          False
          systemPrompt
          opts.migrateBlueprintPrompt
      pure $ case exitCode of
        ExitSuccess -> Right ()
        failure -> Left (BlueprintMigrationProcessFailure failure)

    launchCompletion systemPrompt = do
      result <-
        runAgentCompletion
          (buildAgentCompletionRequest modelConfig systemPrompt opts.migrateBlueprintPrompt)
      case result of
        Left err -> pure (Left (BlueprintMigrationProviderFailure err))
        Right assistantText -> do
          TIO.putStrLn assistantText
          pure (Right ())

recordMigration ::
  FilePath ->
  Blueprint ->
  BlueprintMigration ->
  IO (Either Text ())
recordMigration manifestPath blueprint migration = do
  now <- getCurrentTime
  recordAppliedBlueprintMigration
    manifestPath
    AppliedBlueprintMigration
      { name = blueprint.name,
        blueprintVersion = blueprint.version,
        fromVersion = migration.from,
        toVersion = migration.to,
        appliedAt = now,
        agentSessionId = Nothing
      }

handleRunResult :: LogLevel -> ModuleName -> BlueprintMigrationRunResult -> IO ()
handleRunResult level blueprintName = \case
  BlueprintMigrationNoWork ->
    TIO.putStrLn "No pending blueprint migrations."
  BlueprintMigrationComplete completed ->
    TIO.putStrLn $
      "Completed "
        <> T.pack (show (length completed))
        <> " blueprint migration(s) for '"
        <> blueprintName.unModuleName
        <> "'."
  BlueprintMigrationLaunchFailed migration failure -> do
    let prefix =
          "Blueprint migration "
            <> migration.from
            <> " -> "
            <> migration.to
            <> " failed; completed earlier edges remain recorded. "
        retry = "Fix the provider error, then rerun the same command to resume."
    case failure of
      BlueprintMigrationProcessFailure exitCode -> do
        logIO level $ logError $ prefix <> "Provider exited with " <> T.pack (show exitCode) <> ". " <> retry
        exitWith exitCode
      BlueprintMigrationProviderFailure err -> do
        logIO level $ logError $ prefix <> err <> " " <> retry
        exitFailure
  BlueprintMigrationRecordFailed migration err -> do
    logIO level $
      logError $
        "Agent completed blueprint migration "
          <> migration.from
          <> " -> "
          <> migration.to
          <> ", but its receipt could not be recorded: "
          <> err
          <> ". The next edge was not started; repair manifest access, then rerun the same command."
    exitFailure

reportNoPending :: BlueprintMigrationPlan -> IO ()
reportNoPending migrationPlan
  | null migrationPlan.blueprintPlanSteps =
      TIO.putStrLn "No blueprint migrations are declared inside the requested version window."
  | otherwise =
      TIO.putStrLn "All blueprint migrations in the requested version window already have receipts."

renderPlanError :: MigrationPlanError -> Text
renderPlanError (MigrationVersionUnparseable raw) =
  "the blueprint declares an unparseable migration version: '" <> raw <> "'."
renderPlanError (MigrationDowngradeNotSupported current target) =
  "blueprint migration downgrades are not supported: --from "
    <> renderVersion current
    <> ", --to "
    <> renderVersion target
    <> "."
renderPlanError (MigrationDuplicateEdge fromVersion _) =
  "the blueprint declares more than one migration starting at "
    <> renderVersion fromVersion
    <> "; the author must merge or remove the duplicate."

renderModuleLoadError :: ModuleLoadError -> Text
renderModuleLoadError = \case
  ModuleNotFound name searched ->
    "Blueprint '"
      <> name.unModuleName
      <> "' not found. Searched in:\n"
      <> T.intercalate "\n" (map (("  " <>) . T.pack) searched)
  DhallEvalError name msg ->
    "Failed to evaluate '" <> name.unModuleName <> "': " <> msg
  DhallDecodeError name msg ->
    "Failed to decode '" <> name.unModuleName <> "': " <> msg
  ValidationError name msgs ->
    "Validation failed for '"
      <> name.unModuleName
      <> "':\n"
      <> T.intercalate "\n" (map ("  " <>) msgs)
  CircularDependency names ->
    "Circular dependency detected: " <> T.intercalate " -> " (map (.unModuleName) names)
  MissingSourceFile name path ->
    "Missing source file in '" <> name.unModuleName <> "': " <> T.pack path
  RegistryEvalError path msg ->
    "Failed to evaluate registry at '" <> path <> "': " <> msg

exitErr :: LogLevel -> Text -> IO a
exitErr level msg = do
  logIO level (logError msg)
  exitFailure
