{-# LANGUAGE TemplateHaskell #-}

module Seihou.CLI.AgentMigrate
  ( handleAgentMigrate,
  )
where

import Baikai.Trace.Sink (TraceSink)
import Control.Applicative ((<|>))
import Control.Monad (unless, when)
import Data.FileEmbed (embedFile)
import Data.Generics.Labels ()
import Data.Maybe (fromMaybe, listToMaybe, maybeToList)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Data.Time.Clock (getCurrentTime)
import Seihou.CLI.AgentCompletion
  ( AgentModelConfig (..),
    AgentProvider (..),
    buildAgentCompletionRequestWith,
    runAgentCompletion,
  )
import Seihou.CLI.AgentConfig
  ( PendingAgentConfig,
    agentLaunchDeclaration,
    resolveDeclaredAgentConfig,
  )
import Seihou.CLI.AgentGuard (enforceAgentArtifactGuard)
import Seihou.CLI.AgentLaunch (gatherAgentContext)
import Seihou.CLI.AgentLaunchExec (launchConfiguredAgentAddingDirs)
import Seihou.CLI.AgentTrace (traceSinkForConfig)
import Seihou.CLI.AppliedBlueprintMigration (recordAppliedBlueprintMigration)
import Seihou.CLI.BlueprintExecution
  ( BlueprintExecutionRequest (..),
    PreparedBlueprintExecution (..),
    prepareBlueprintExecution,
  )
import Seihou.CLI.BlueprintMigration
  ( BlueprintMigrationLaunchFailure (..),
    BlueprintMigrationLaunchResult (..),
    BlueprintMigrationRunResult (..),
    formatBlueprintMigrationDebugOutput,
    parseNotApplicableSignal,
    pendingBlueprintMigrations,
    renderBlueprintMigrationSystemPrompt,
    runBlueprintMigrationsWith,
    unstatedNotApplicableReason,
  )
import Seihou.CLI.Commands (BlueprintMigrationOpts (..))
import Seihou.CLI.Shared (formatVarError, logIO)
import Seihou.Core.ArtifactOriginDetect (detectArtifactOrigin)
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
import System.Directory
  ( createDirectoryIfMissing,
    doesFileExist,
    getCurrentDirectory,
    removeFile,
  )
import System.Exit (ExitCode (..), exitFailure, exitWith)
import System.FilePath (takeDirectory)

migrationPromptTemplate :: Text
migrationPromptTemplate = TE.decodeUtf8 $(embedFile "data/blueprint-migration-prompt.md")

handleAgentMigrate :: Bool -> PendingAgentConfig -> BlueprintMigrationOpts -> IO ()
handleAgentMigrate debug pendingConfig opts = do
  let level = if opts ^. #verbose then LogVerbose else LogNormal
      manifestPath = ".seihou" </> "manifest.json"

  (blueprint, blueprintDir) <- discoverMigrationBlueprint level (opts ^. #name)
  validationResult <- validateBlueprint blueprintDir blueprint
  case validationResult of
    Left err -> exitErr level (renderModuleLoadError err)
    Right _ -> pure ()

  -- Classify the blueprint's discovery directory into a portable origin once
  -- per command. The blueprint does not move mid-run, and every receipt this
  -- command writes belongs to the same blueprint identity, so one filesystem
  -- read is enough. Receipts are keyed by this origin, not by the name the
  -- user typed, so a blueprint of the same name from another repository has
  -- its own receipts.
  projectRoot <- getCurrentDirectory
  blueprintOrigin <- detectArtifactOrigin projectRoot blueprintDir

  -- Pre-flight downgrade and origin guard, before a single edge is planned.
  -- Placing it before planning is the point rather than an implementation
  -- detail: a substituted blueprint's edges do not match this project's
  -- receipts, so without the check the command would report that every edge in
  -- the window already has a receipt and exit successfully, having silently
  -- skipped work that never ran. The refusal happens before any receipt is
  -- written, so the manifest is left byte-identical.
  --
  -- No baseline modules are in scope: migration mode applies no baseModules
  -- (see docs/user/blueprint-migrations.md), and refusing for artifacts this
  -- command will not touch would violate the scoping rule in
  -- docs/adr/0003-a-stale-or-substituted-artifact-is-a-hard-error.md.
  --
  -- --debug performs no check at all: it contacts no provider and writes
  -- nothing, so a prompt can still be inspected on any machine.
  unless debug $
    enforceAgentArtifactGuard
      (opts ^. #allowDowngrade)
      manifestPath
      (blueprint ^. #name)
      mempty

  -- Finish provider/model/effort resolution now that the blueprint is loaded:
  -- `agent migrate` reads the same Blueprint record as `agent run`, so it
  -- honors the same launch declaration.
  modelConfig <-
    resolveDeclaredAgentConfig
      level
      ("blueprint '" <> blueprint ^. #name . #unModuleName <> "'")
      pendingConfig
      (agentLaunchDeclaration (blueprint ^. #launch))

  current <- parseRequestedVersion level "--from" (opts ^. #from)
  target <- parseRequestedVersion level "--to" (opts ^. #to)
  planned <-
    case planBlueprintMigrationChain (blueprint ^. #name . #unModuleName) (blueprint ^. #migrations) current target of
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
              (opts ^. #rerun)
              blueprintOrigin
              (blueprint ^. #name)
              receipts
              migrationPlan
      if null pending
        then reportNoPending migrationPlan
        else do
          prepared <- prepare level modelConfig opts blueprint blueprintDir
          traceSink <- traceSinkForConfig level modelConfig
          context <- gatherAgentContext
          let signalPath = notApplicableSignalPath projectRoot
              renderStep position total migration =
                renderBlueprintMigrationSystemPrompt
                  migrationPromptTemplate
                  signalPath
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
                    (opts ^. #prompt)

          if debug
            then
              TIO.putStrLn $
                "Blueprint migrations for "
                  <> blueprint ^. #name . #unModuleName
                  <> ": "
                  <> renderVersion (migrationPlan ^. #from)
                  <> " -> "
                  <> renderVersion (migrationPlan ^. #to)
                  <> "\n"
                  <> formatBlueprintMigrationDebugOutput renderDebugStep pending
            else do
              -- The agent needs somewhere to put the signal file, and the
              -- directory is created by the first receipt anyway.
              createDirectoryIfMissing True (takeDirectory signalPath)
              result <-
                runBlueprintMigrationsWith
                  (launchMigration traceSink modelConfig opts prepared signalPath renderStep)
                  (recordMigration manifestPath blueprintOrigin blueprint)
                  pending
              handleRunResult level (blueprint ^. #name) result

discoverMigrationBlueprint :: LogLevel -> ModuleName -> IO (Blueprint, FilePath)
discoverMigrationBlueprint level requestedName = do
  searchPaths <- defaultSearchPaths
  runnableResult <- discoverRunnable searchPaths requestedName
  case runnableResult of
    Right (RunnableBlueprint blueprint dir) -> pure (blueprint, dir)
    Right (RunnableModule _ _) ->
      exitErr level $ "'" <> requestedName ^. #unModuleName <> "' is a module, not a blueprint."
    Right (RunnableRecipe _ _) ->
      exitErr level $ "'" <> requestedName ^. #unModuleName <> "' is a recipe, not a blueprint."
    Right (RunnableAgentPrompt _ _) ->
      exitErr level $ "'" <> requestedName ^. #unModuleName <> "' is a prompt, not a blueprint."
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
    Right (Just manifest) -> pure (manifest ^. #blueprintMigrations)

prepare ::
  LogLevel ->
  AgentModelConfig ->
  BlueprintMigrationOpts ->
  Blueprint ->
  FilePath ->
  IO PreparedBlueprintExecution
prepare level modelConfig opts blueprint blueprintDir = do
  let providerCanMountFiles =
        modelConfig ^. #provider == AgentProviderClaudeCli
          || modelConfig ^. #provider == AgentProviderCodexCli
  result <-
    prepareBlueprintExecution
      BlueprintExecutionRequest
        { blueprint = blueprint,
          blueprintDir = blueprintDir,
          variableOverrides = opts ^. #vars,
          namespaceOverride = opts ^. #namespace,
          contextOverride = opts ^. #context,
          canMountFiles = providerCanMountFiles,
          logLevel = level
        }
  case result of
    Left errs -> do
      logIO level $ logError "Error resolving blueprint migration variables:"
      mapM_ (logIO level . logError . ("  " <>) . formatVarError) errs
      exitFailure
    Right prepared -> pure prepared

-- | Where an edge reports that it does not apply.
--
-- It lives under @.seihou\/@ rather than in the working tree so a signal a
-- crashed run left behind never shows up in @git status@, and the leading dot
-- keeps it out of the way of @.seihou@'s own contents.
notApplicableSignalPath :: FilePath -> FilePath
notApplicableSignalPath projectRoot = projectRoot </> ".seihou" </> ".migrate-signal"

-- | Delete a signal left behind by an earlier edge or a crashed run, so it
-- cannot be misread as this edge's answer.
clearNotApplicableSignal :: FilePath -> IO ()
clearNotApplicableSignal signalPath = do
  exists <- doesFileExist signalPath
  when exists (removeFile signalPath)

-- | Read and consume the signal an edge may have written.
--
-- The file's existence is the signal: an agent creates it deliberately, with
-- its own tools, at a path only this command names. An empty one therefore
-- still means "not applicable", it just fails to say why.
readNotApplicableSignal :: FilePath -> IO (Maybe Text)
readNotApplicableSignal signalPath = do
  exists <- doesFileExist signalPath
  if not exists
    then pure Nothing
    else do
      contents <- TIO.readFile signalPath
      removeFile signalPath
      let firstLine = listToMaybe (filter (not . T.null) (map T.strip (T.lines contents)))
      pure (Just (fromMaybe unstatedNotApplicableReason firstLine))

launchMigration ::
  -- | built once per command, so every migration edge appends to one destination
  TraceSink ->
  AgentModelConfig ->
  BlueprintMigrationOpts ->
  PreparedBlueprintExecution ->
  -- | where this edge reports that it does not apply
  FilePath ->
  (Int -> Int -> BlueprintMigration -> Text) ->
  Int ->
  Int ->
  BlueprintMigration ->
  IO (Either BlueprintMigrationLaunchFailure BlueprintMigrationLaunchResult)
launchMigration traceSink modelConfig opts prepared signalPath renderStep position total migration = do
  TIO.putStrLn $
    "Running blueprint migration "
      <> stepLabel
      <> ": "
      <> migration ^. #from
      <> " -> "
      <> (migration ^. #to)
  clearNotApplicableSignal signalPath
  let systemPrompt = renderStep position total migration
  case modelConfig ^. #provider of
    AgentProviderClaudeCli -> launchInteractive systemPrompt
    AgentProviderCodexCli -> launchInteractive systemPrompt
    AgentProviderAnthropic -> launchCompletion systemPrompt
    AgentProviderOpenAI -> launchCompletion systemPrompt
  where
    stepLabel = T.pack (show position) <> "/" <> T.pack (show total)

    -- An interactive session communicates only through its exit code, so the
    -- signal file is the one channel an agent has to report inapplicability.
    launchInteractive systemPrompt = do
      exitCode <-
        launchConfiguredAgentAddingDirs
          (maybeToList (prepared ^. #mountedFilesDir))
          modelConfig
          (prepared ^. #allowedTools)
          False
          systemPrompt
          (opts ^. #prompt)
      case exitCode of
        ExitSuccess -> Right <$> sessionResultFromSignal Nothing
        failure -> do
          -- A failed session's signal is not this edge's answer.
          clearNotApplicableSignal signalPath
          pure (Left (BlueprintMigrationProcessFailure failure))

    -- An API provider hands us its reply directly, so the marker line works.
    -- The signal file is still checked, because a provider given tool access
    -- may take the prompt's first instruction rather than its fallback.
    launchCompletion systemPrompt = do
      result <-
        runAgentCompletion
          (buildAgentCompletionRequestWith traceSink modelConfig systemPrompt (opts ^. #prompt))
      case result of
        Left err -> do
          clearNotApplicableSignal signalPath
          pure (Left (BlueprintMigrationProviderFailure err))
        Right assistantText -> do
          TIO.putStrLn assistantText
          Right <$> sessionResultFromSignal (parseNotApplicableSignal assistantText)

    sessionResultFromSignal parsedReason = do
      fileReason <- readNotApplicableSignal signalPath
      case fileReason <|> parsedReason of
        Nothing -> pure BlueprintMigrationSessionReturned
        Just reason -> do
          TIO.putStrLn $
            "Blueprint migration "
              <> stepLabel
              <> ": "
              <> migration ^. #from
              <> " -> "
              <> (migration ^. #to)
              <> " — not applicable: "
              <> reason
          pure (BlueprintMigrationSessionNotApplicable reason)

recordMigration ::
  FilePath ->
  -- | the owning blueprint's portable identity, computed once per command
  ArtifactOrigin ->
  Blueprint ->
  BlueprintMigration ->
  MigrationOutcome ->
  IO (Either Text ())
recordMigration manifestPath blueprintOrigin blueprint migration migrationOutcome = do
  now <- getCurrentTime
  recordAppliedBlueprintMigration
    manifestPath
    AppliedBlueprintMigration
      { name = blueprint ^. #name,
        origin = blueprintOrigin,
        blueprintVersion = blueprint ^. #version,
        fromVersion = migration ^. #from,
        toVersion = migration ^. #to,
        outcome = migrationOutcome,
        appliedAt = now,
        agentSessionId = Nothing
      }

handleRunResult :: LogLevel -> ModuleName -> BlueprintMigrationRunResult -> IO ()
handleRunResult level blueprintName = \case
  BlueprintMigrationNoWork ->
    TIO.putStrLn "No pending blueprint migrations."
  BlueprintMigrationComplete completed -> do
    let notApplicable = length [() | (_, MigrationNotApplicable _) <- completed]
    TIO.putStrLn $
      "Completed "
        <> T.pack (show (length completed))
        <> " blueprint migration(s) for '"
        <> blueprintName ^. #unModuleName
        <> "'"
        <> ( if notApplicable > 0
               then " (" <> T.pack (show notApplicable) <> " not applicable)"
               else ""
           )
        <> "."
  BlueprintMigrationLaunchFailed migration failure -> do
    let prefix =
          "Blueprint migration "
            <> migration ^. #from
            <> " -> "
            <> migration ^. #to
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
          <> migration ^. #from
          <> " -> "
          <> migration ^. #to
          <> ", but its receipt could not be recorded: "
          <> err
          <> ". The next edge was not started; repair manifest access, then rerun the same command."
    exitFailure

reportNoPending :: BlueprintMigrationPlan -> IO ()
reportNoPending migrationPlan
  | null (migrationPlan ^. #steps) =
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
      <> name ^. #unModuleName
      <> "' not found. Searched in:\n"
      <> T.intercalate "\n" (map (("  " <>) . T.pack) searched)
  DhallEvalError name msg ->
    "Failed to evaluate '" <> name ^. #unModuleName <> "': " <> msg
  DhallDecodeError name msg ->
    "Failed to decode '" <> name ^. #unModuleName <> "': " <> msg
  ValidationError name msgs ->
    "Validation failed for '"
      <> name ^. #unModuleName
      <> "':\n"
      <> T.intercalate "\n" (map ("  " <>) msgs)
  CircularDependency names ->
    "Circular dependency detected: " <> T.intercalate " -> " (map (^. #unModuleName) names)
  MissingSourceFile name path ->
    "Missing source file in '" <> name ^. #unModuleName <> "': " <> T.pack path
  RegistryEvalError path msg ->
    "Failed to evaluate registry at '" <> path <> "': " <> msg

exitErr :: LogLevel -> Text -> IO a
exitErr level msg = do
  logIO level (logError msg)
  exitFailure
