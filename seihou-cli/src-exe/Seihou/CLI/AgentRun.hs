{-# LANGUAGE TemplateHaskell #-}

-- | Agent runner for blueprints. Loads a blueprint, resolves its
-- variables (with the same precedence chain as @seihou run@), optionally
-- applies its declared @baseModules@, renders the prompt template, and
-- sends the rendered prompt through the configured Baikai provider. See EP-31
-- (docs/plans/31-blueprint-agent-runner.md) for the full design.
module Seihou.CLI.AgentRun
  ( handleAgentRun,
    appliedBlueprintFromOutcome,
    runRenderedAgentPrompt,
  )
where

import Control.Exception (IOException, displayException, try)
import Control.Monad (unless, when)
import Data.FileEmbed (embedFile)
import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, maybeToList)
import Data.Set qualified as Set
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Data.Time (UTCTime)
import Data.Time.Clock (getCurrentTime)
import Seihou.CLI.AgentCompletion
  ( AgentModelConfig (..),
    AgentProvider (..),
    buildAgentCompletionRequestWith,
    runAgentCompletionWithCliAccess,
  )
import Seihou.CLI.AgentConfig
  ( PendingAgentConfig,
    agentLaunchDeclaration,
    resolveDeclaredAgentConfig,
  )
import Seihou.CLI.AgentGuard (enforceAgentArtifactGuard)
import Seihou.CLI.AgentLaunch
  ( AgentContext (..),
    BaselineStatus (..),
    formatAvailableModules,
    formatBaselineStatus,
    formatLocalModules,
    formatManifestState,
    formatModuleDhallState,
    formatSeihouProjectState,
    gatherAgentContext,
    substitute,
  )
import Seihou.CLI.AgentLaunchExec (launchConfiguredAgentAddingDirs)
import Seihou.CLI.AgentTrace (traceSinkForConfig)
import Seihou.CLI.AppliedBlueprint (recordAppliedBlueprint)
import Seihou.CLI.BlueprintExecution
  ( BlueprintExecutionRequest (..),
    PreparedBlueprintExecution (..),
    prepareBlueprintExecution,
    varValueToText,
  )
import Seihou.CLI.Commands (BlueprintRunOpts (..))
import Seihou.CLI.Shared
  ( deriveNamespace,
    formatVarError,
    logIO,
    toVarNameMap,
    unwrapConfig,
  )
import Seihou.Composition.Instance (ModuleInstance (..), qualifiedName)
import Seihou.Composition.Plan (compileComposedPlan)
import Seihou.Composition.Resolve (loadComposition, resolveWithPrompts)
import Seihou.Core.ArtifactOriginDetect (detectArtifactOrigin)
import Seihou.Core.Context (resolveContext)
import Seihou.Core.Module (defaultSearchPaths, discoverRunnable)
import Seihou.Core.Types
import Seihou.Effect.BaselineStore (pruneBaselines)
import Seihou.Effect.BaselineStoreInterp (runBaselineStore)
import Seihou.Effect.ConfigReader
  ( readContextConfig,
    readGlobalConfig,
    readLocalConfig,
    readNamespaceConfig,
  )
import Seihou.Effect.ConfigReaderInterp (runConfigReader)
import Seihou.Effect.ConsoleInterp (runConsole)
import Seihou.Effect.Filesystem (createDirectoryIfMissing)
import Seihou.Effect.FilesystemInterp (runFilesystem)
import Seihou.Effect.Logger (logError, logInfo, logWarn)
import Seihou.Effect.ManifestStore (readManifest, writeManifest)
import Seihou.Effect.ManifestStoreInterp (runManifestStore)
import Seihou.Engine.Baseline (manifestBaselineRefs, recordGeneratedBaselines)
import Seihou.Engine.Conflict (resolveConflicts)
import Seihou.Engine.Diff (computeDiff)
import Seihou.Engine.Execute (executePlan)
import Seihou.Manifest.Types (currentManifestVersion, emptyManifest)
import Seihou.Prelude
import System.Directory (getCurrentDirectory)
import System.Environment (getEnvironment)
import System.Exit (ExitCode (..), exitFailure, exitWith)
import System.FilePath (takeDirectory, (</>))
import System.IO (hIsTerminalDevice, stdin)

-- | The prompt template, embedded at compile time from data/blueprint-prompt.md.
promptTemplate :: Text
promptTemplate = TE.decodeUtf8 $(embedFile "data/blueprint-prompt.md")

handleAgentRun :: Bool -> PendingAgentConfig -> BlueprintRunOpts -> IO ()
handleAgentRun debug pending opts = do
  let level = if opts ^. #verbose then LogVerbose else LogNormal
  stdinIsTerminal <- hIsTerminalDevice stdin
  let batch = opts ^. #batch || not stdinIsTerminal

  -- (a) Discover and validate. discoverRunnable resolves by directory
  -- name (priority: module > recipe > blueprint).
  searchPaths <- defaultSearchPaths
  runnableResult <- discoverRunnable searchPaths (opts ^. #name)
  (bp, blueprintDir) <- case runnableResult of
    Right (RunnableBlueprint b dir) -> pure (b, dir)
    Right (RunnableModule _ _) ->
      exitErr level $
        "'"
          <> opts ^. #name . #unModuleName
          <> "' is a module, not a blueprint. Did you mean 'seihou run "
          <> opts ^. #name . #unModuleName
          <> "'?"
    Right (RunnableRecipe _ _) ->
      exitErr level $
        "'"
          <> opts ^. #name . #unModuleName
          <> "' is a recipe, not a blueprint. Did you mean 'seihou run "
          <> opts ^. #name . #unModuleName
          <> "'?"
    Left err -> exitErr level (renderModuleLoadError err)

  -- (a2) Resolve the baseline composition — every declared base module plus
  -- its transitive dependencies — before anything is written. 'seihou run'
  -- guards every module in the composition it is about to generate from, not
  -- just the ones named at the top level, so the guard below needs the
  -- resolved composition rather than the blueprint's declared baseModules
  -- list. Resolving it here rather than inside 'applyBaseline' also means the
  -- Dhall evaluation happens exactly once.
  baselineComposition <-
    if opts ^. #noBaseline || null (bp ^. #baseModules)
      then pure Nothing
      else Just <$> loadBaselineComposition level (bp ^. #baseModules)

  -- (a3) Pre-flight downgrade and origin guard. This runs before the baseline
  -- is applied, before any variable is prompted for, and before the manifest
  -- is touched, so a refusal leaves the working tree and
  -- .seihou/manifest.json byte-identical — the property
  -- docs/adr/0003-a-stale-or-substituted-artifact-is-a-hard-error.md relies
  -- on. It covers the blueprint itself and every module the baseline would
  -- generate from, and nothing else: an artifact this run will not touch must
  -- not block it.
  --
  -- --debug performs no check at all. It contacts no provider, applies no
  -- baseline and writes nothing, so a developer inspecting a prompt on a
  -- machine that has never installed the artifact has nothing to be refused
  -- for. The condition sits here rather than inside the guard so that debug
  -- mode is structurally check-free on reading.
  unless debug $
    enforceAgentArtifactGuard
      (opts ^. #allowDowngrade)
      (".seihou" </> "manifest.json")
      (bp ^. #name)
      (baselineComposedNames baselineComposition)

  -- Finish provider/model/effort resolution now that the blueprint is loaded
  -- and its launch declaration is known. This must precede the
  -- providerCanMountFiles computation below, which depends on the final
  -- provider.
  modelConfig <-
    resolveDeclaredAgentConfig
      level
      ("blueprint '" <> bp ^. #name . #unModuleName <> "'")
      pending
      (agentLaunchDeclaration (bp ^. #launch))

  let providerCanMountFiles =
        modelConfig ^. #provider == AgentProviderClaudeCli
          || modelConfig ^. #provider == AgentProviderCodexCli
  -- (b) Resolve variables and prepare the shared prompt/reference/tool state.
  preparedResult <-
    prepareBlueprintExecution
      BlueprintExecutionRequest
        { blueprint = bp,
          blueprintDir = blueprintDir,
          variableOverrides = opts ^. #vars,
          namespaceOverride = opts ^. #namespace,
          contextOverride = opts ^. #context,
          canMountFiles = providerCanMountFiles,
          logLevel = level
        }
  prepared <- case preparedResult of
    Left errs -> do
      logIO level $ logError "Error resolving blueprint variables:"
      mapM_ (logIO level . logError . ("  " <>) . formatVarError) errs
      exitFailure
    Right result -> pure result
  let resolved = (prepared ^. #resolvedVariables)
      cliOverrides = Map.fromList [(VarName k, v) | (k, v) <- opts ^. #vars]

  -- (c) Baseline.
  baseline <-
    if opts ^. #noBaseline
      then pure BaselineSkipped
      else case baselineComposition of
        Nothing -> pure BaselineEmpty
        Just composition -> applyBaseline level opts composition cliOverrides resolved

  -- (d) Render the system prompt around the prepared shared body.
  ctx <- gatherAgentContext
  let systemPrompt = renderSystemPrompt ctx prepared baseline

  -- (f) Launch.
  launchSucceeded <-
    runRenderedAgentPromptMode
      debug
      batch
      modelConfig
      (prepared ^. #allowedTools)
      (prepared ^. #mountedFilesDir)
      systemPrompt
      (opts ^. #prompt)

  -- (g) Record the applied-blueprint provenance into
  -- .seihou/manifest.json only after a successful provider response. In
  -- debug mode, keep the previous successful dry-launch behavior by recording
  -- after the rendered prompt is printed successfully.
  when launchSucceeded $ do
    now <- getCurrentTime
    -- Classify the blueprint's discovery directory into a portable origin, so
    -- the recorded entry names the artifact rather than a directory that means
    -- nothing on another developer's machine.
    projectRoot <- getCurrentDirectory
    blueprintOrigin <- detectArtifactOrigin projectRoot blueprintDir
    let entry = appliedBlueprintFromOutcome bp blueprintOrigin baseline opts now
        manifestPath = ".seihou" </> "manifest.json"
    writeRes <- recordAppliedBlueprint manifestPath entry
    case writeRes of
      Right () -> pure ()
      Left err ->
        logIO level $
          logError $
            "Warning: agent succeeded but recording the applied-blueprint entry failed: "
              <> err

runRenderedAgentPrompt :: Bool -> AgentModelConfig -> [String] -> Maybe FilePath -> Text -> Maybe Text -> IO Bool
runRenderedAgentPrompt debug = runRenderedAgentPromptMode debug False

runRenderedAgentPromptMode :: Bool -> Bool -> AgentModelConfig -> [String] -> Maybe FilePath -> Text -> Maybe Text -> IO Bool
runRenderedAgentPromptMode debug batch modelConfig tools mFilesDir systemPrompt initialPrompt
  | debug = do
      TIO.putStr systemPrompt
      pure True
  | not batch && (modelConfig ^. #provider == AgentProviderClaudeCli || modelConfig ^. #provider == AgentProviderCodexCli) = do
      exitCode <-
        launchConfiguredAgentAddingDirs
          (maybeToList mFilesDir)
          modelConfig
          tools
          debug
          systemPrompt
          initialPrompt
      case exitCode of
        ExitSuccess -> pure True
        ExitFailure _ -> exitWith exitCode
  | otherwise = do
      sink <- traceSinkForConfig LogNormal modelConfig
      result <-
        runAgentCompletionWithCliAccess
          (maybeToList mFilesDir)
          tools
          (buildAgentCompletionRequestWith sink modelConfig systemPrompt initialPrompt)
      case result of
        Right assistantText -> do
          TIO.putStrLn assistantText
          pure True
        Left err -> do
          TIO.putStrLn $ "Error: " <> err
          exitFailure

-- | Project the runner's local state into the persistent
-- 'AppliedBlueprint' shape. Pure so the manifest writer remains a
-- one-liner at the call site and so cross-plan tests can drive it
-- with synthetic inputs.
appliedBlueprintFromOutcome ::
  Blueprint -> ArtifactOrigin -> BaselineStatus -> BlueprintRunOpts -> UTCTime -> AppliedBlueprint
appliedBlueprintFromOutcome bp blueprintOrigin baseline opts now =
  AppliedBlueprint
    { name = bp ^. #name,
      origin = blueprintOrigin,
      blueprintVersion = bp ^. #version,
      appliedAt = now,
      baselineModules = case baseline of
        BaselineApplied entries -> map fst entries
        BaselineEmpty -> []
        BaselineSkipped -> [],
      noBaseline = case baseline of
        BaselineSkipped -> True
        _ -> False,
      userPrompt = opts ^. #prompt,
      agentSessionId = Nothing
    }

-- | One resolved baseline composition: the primary base module, and every
-- module the baseline would generate from — the declared base modules plus
-- their transitive dependencies — in dependency order, each paired with the
-- directory it was discovered in.
type BaselineComposition = (ModuleName, [(ModuleInstance, Module, FilePath)])

-- | Load the blueprint's baseline composition without applying it.
--
-- Split out of 'applyBaseline' so the pre-flight artifact guard can see
-- exactly the module set the baseline would generate from before anything is
-- written, and so the composition's Dhall evaluation happens once per run
-- rather than once for the guard and once for the application.
loadBaselineComposition :: LogLevel -> [Dependency] -> IO BaselineComposition
loadBaselineComposition level baseModules = do
  searchPaths <- defaultSearchPaths
  (primary, additionals) <- case baseModules of
    d : rs -> pure (d ^. #module_, map (^. #module_) rs)
    [] -> exitErr level "internal error: loadBaselineComposition called with empty baseModules"
  compositionResult <- loadComposition searchPaths primary additionals
  case compositionResult of
    Left err -> do
      logIO level $ logError $ "Baseline error: " <> renderModuleLoadError err
      exitFailure
    Right modulesInOrder -> pure (primary, modulesInOrder)

-- | The module names a baseline application would generate from, as the
-- artifact guard's filter wants them. Mirrors @composedModuleNames@ in
-- "Seihou.CLI.Run". Empty when no baseline will be applied, which the guard
-- reads as "no modules are in scope for this run".
baselineComposedNames :: Maybe BaselineComposition -> Set ModuleName
baselineComposedNames =
  maybe mempty (\(_, modulesInOrder) -> Set.fromList [m ^. #name | (_, m, _) <- modulesInOrder])

-- | Apply the blueprint's @baseModules@ to the cwd. Mirrors the
-- composition pipeline in @Seihou.CLI.Run.handleRun@: take the composition
-- resolved by 'loadBaselineComposition', resolve its variables through the
-- same precedence chain (with the blueprint's own resolved vars folded into
-- the CLI override map so the agent's prompt and the base modules see the
-- same values), compile the composed plan, compute the diff, resolve
-- conflicts, execute the plan, and write the resulting manifest. Returns
-- 'BaselineApplied' listing each module's (name, version) for the prompt's
-- "Baseline" section.
applyBaseline ::
  LogLevel ->
  BlueprintRunOpts ->
  BaselineComposition ->
  Map VarName Text ->
  Map VarName ResolvedVar ->
  IO BaselineStatus
applyBaseline level opts (primary, modulesInOrder) cliOverridesIn resolvedBlueprintVars = do
  -- Classify every baseline module's discovery directory into a portable
  -- origin before anything is recorded, so the manifest stays meaningful on
  -- another developer's machine.
  projectRoot <- getCurrentDirectory
  originedModules <-
    traverse
      (\(inst, m, dir) -> (inst,m,) <$> detectArtifactOrigin projectRoot dir)
      modulesInOrder

  -- Fold the blueprint's resolved vars into the CLI override map for
  -- the base modules. CLI overrides (already present in cliOverridesIn)
  -- win over blueprint values, mirroring 'seihou run' semantics.
  let blueprintAsOverrides =
        Map.fromList
          [(vn, varValueToText (rv ^. #value)) | (vn, rv) <- Map.toList resolvedBlueprintVars]
      cliOverrides = Map.union cliOverridesIn blueprintAsOverrides

  envPairs <- getEnvironment
  let envVars = Map.fromList [(T.pack k, T.pack v) | (k, v) <- envPairs]
      namespace = fromMaybe (deriveNamespace primary) (opts ^. #namespace)
  context <- resolveContext (opts ^. #context) envVars
  let contextName = fromMaybe "" context

  baseResolveResult <- runEff $ runConfigReader $ runConsole $ do
    localCfg <- readLocalConfig >>= unwrapConfig level
    nsCfg <- readNamespaceConfig namespace >>= unwrapConfig level
    ctxCfg <- readContextConfig contextName >>= unwrapConfig level
    gCfg <- readGlobalConfig >>= unwrapConfig level
    resolveWithPrompts
      modulesInOrder
      cliOverrides
      envVars
      namespace
      contextName
      (toVarNameMap localCfg)
      (toVarNameMap nsCfg)
      (toVarNameMap ctxCfg)
      (toVarNameMap gCfg)

  baseResolved <- case baseResolveResult of
    Left errs -> do
      logIO level $ logError "Error resolving baseline variables:"
      mapM_ (logIO level . logError . ("  " <>) . formatVarError) errs
      exitFailure
    Right r -> pure r

  -- Compile the plan.
  let quads =
        [ (inst, m, dir, Map.map (^. #value) (baseResolved Map.! inst))
        | (inst, m, dir) <- modulesInOrder
        ]
  planResult <- compileComposedPlan quads
  (ops, _warnings, ownerMap) <- case planResult of
    Left errs -> do
      logIO level $ logError "Errors compiling baseline plan:"
      mapM_ (logIO level . logError . ("  " <>)) errs
      exitFailure
    Right r -> pure r

  -- Read the manifest, compute the diff, resolve conflicts, execute,
  -- write the manifest. Mirrors Seihou.CLI.Run.handleRun.
  now <- getCurrentTime
  let manifestPath = ".seihou" </> "manifest.json"
      baselineDir = ".seihou" </> "baselines"
      planned =
        [(dest, content, primary, Nothing) | WriteFileOp dest content _ <- ops]
          ++ [(dest, content, mName, Just pOp) | PatchFileOp dest content pOp _ mName <- ops]

  existingRes <- runEff $ runFilesystem $ runManifestStore manifestPath $ do
    createDirectoryIfMissing True (takeDirectory manifestPath)
    readManifest
  manifest <- case existingRes of
    Left err -> do
      logIO level $ logError $ "Error reading manifest: " <> err
      exitFailure
    Right m -> pure (fromMaybe (emptyManifest now) m)

  diff <- runEff $ runFilesystem $ runManifestStore manifestPath $ do
    let composedNames =
          Set.fromList $
            concatMap (\(inst, _, _) -> [inst ^. #module_, qualifiedName inst]) modulesInOrder
    computeDiff manifest composedNames planned

  resolutions <-
    runEff $ runConsole $ resolveConflicts (opts ^. #force) (diff ^. #conflicts)
  case resolutions of
    Nothing -> do
      logIO level $ logError "Baseline conflicts detected (use --force to overwrite):"
      mapM_ (\c -> logIO level (logError ("  ! " <> T.pack (c ^. #path)))) (diff ^. #conflicts)
      exitFailure
    Just conflictResolved -> do
      let keepRecords =
            Map.fromList
              [ ( c ^. #path,
                  case Map.lookup (c ^. #path) (manifest ^. #files) of
                    Just existing ->
                      ( existing
                          & #hash
                          .~ c
                          ^. #diskHash
                          & #generatedAt
                          .~ now
                      )
                    Nothing ->
                      FileRecord
                        { hash = c ^. #diskHash,
                          moduleName = c ^. #moduleName,
                          strategy = Template,
                          generatedAt = now,
                          baseline = Nothing,
                          applicationIds = mempty
                        }
                )
              | (c, KeepCurrent) <- conflictResolved
              ]
          skipPaths = [c ^. #path | (c, Skip) <- conflictResolved]
          excludePaths = Set.fromList (Map.keys keepRecords ++ skipPaths)
          opsForExec = filter (not . opTargetsPath excludePaths) ops

      generationAttempt <-
        try @IOException $
          runEff $
            runFilesystem $
              runBaselineStore baselineDir $
                runManifestStore manifestPath $ do
                  recs <- executePlan "" opsForExec ownerMap primary now
                  baselineResult <- recordGeneratedBaselines "" recs
                  case baselineResult of
                    Left err -> pure (Left err)
                    Right baselineRecords -> do
                      let orphanedPaths = map (^. #path) (diff ^. #orphaned)
                          cleanedFiles = foldr Map.delete (manifest ^. #files) orphanedPaths
                          allModuleEntries = updateAllModules (manifest ^. #modules) originedModules now
                          allResolvedVals =
                            Map.unions [Map.map (^. #value) vs | vs <- Map.elems baseResolved]
                          newManifest =
                            Manifest
                              { version = currentManifestVersion,
                                genAt = now,
                                modules = allModuleEntries,
                                vars = Map.union (Map.map varValueToText allResolvedVals) (manifest ^. #vars),
                                files = Map.unions [baselineRecords, keepRecords, cleanedFiles],
                                applications = manifest ^. #applications,
                                recipe = manifest ^. #recipe,
                                blueprint = manifest ^. #blueprint,
                                blueprintMigrations = manifest ^. #blueprintMigrations
                              }
                      writeManifest newManifest
                      pure (Right newManifest)

      newManifest <- case generationAttempt of
        Left err -> do
          logIO level $ logError $ "Error applying baseline files or storing generated baselines: " <> T.pack (displayException err)
          exitFailure
        Right (Left err) -> do
          logIO level $ logError $ "Error storing generated baselines: " <> T.pack (show err)
          exitFailure
        Right (Right saved) -> pure saved

      pruneAttempt <-
        try @IOException $
          runEff $
            runFilesystem $
              runBaselineStore baselineDir $
                pruneBaselines (manifestBaselineRefs newManifest)
      case pruneAttempt of
        Left err ->
          logIO level $ logWarn $ "Warning: could not prune generated baselines: " <> T.pack (displayException err)
        Right _ -> pure ()

      let nNew = length (diff ^. #new)
          nMod = length (diff ^. #modified)
          nUnch = length (diff ^. #unchanged)
      logIO level $
        logInfo $
          "Baseline applied: "
            <> T.pack (show nNew)
            <> " new, "
            <> T.pack (show nMod)
            <> " modified, "
            <> T.pack (show nUnch)
            <> " unchanged."
      pure $
        BaselineApplied
          [(m ^. #name, m ^. #version) | (_, m, _) <- modulesInOrder]

-- | Stitch the system-prompt template together. Each block in
-- @blueprint-prompt.md@ has a @{{key}}@ placeholder filled here.
renderSystemPrompt :: AgentContext -> PreparedBlueprintExecution -> BaselineStatus -> Text
renderSystemPrompt ctx prepared baseline =
  let bp = (prepared ^. #blueprint)
   in substitute
        [ ("cwd", ctx ^. #cwd),
          ("seihou_project_state", formatSeihouProjectState ctx),
          ("manifest_state", formatManifestState ctx),
          ("module_dhall_state", formatModuleDhallState ctx),
          ("local_modules", formatLocalModules ctx),
          ("available_modules", formatAvailableModules ctx),
          ("blueprint_name", bp ^. #name . #unModuleName),
          ("blueprint_version", fromMaybe "(unspecified)" (bp ^. #version)),
          ("blueprint_description", fromMaybe "(no description)" (bp ^. #description)),
          ("baseline_status", formatBaselineStatus baseline),
          ("reference_files", prepared ^. #referenceFiles),
          ("reference_files_dir", prepared ^. #referenceFilesAccess),
          ("user_prompt", prepared ^. #sharedPrompt)
        ]
        promptTemplate

-- | Whether an operation targets a file in the given path set. Local
-- copy of @Seihou.CLI.Run.opTargetsPath@.
opTargetsPath :: Set FilePath -> Operation -> Bool
opTargetsPath paths (WriteFileOp dest _ _) = Set.member dest paths
opTargetsPath paths (PatchFileOp dest _ _ _ _) = Set.member dest paths
opTargetsPath _ _ = False

-- | Merge freshly-composed module instances into the manifest's
-- applied-modules list. Local copy of @Seihou.CLI.Run.updateAllModules@.
updateAllModules ::
  [AppliedModule] ->
  [(ModuleInstance, Module, ArtifactOrigin)] ->
  UTCTime ->
  [AppliedModule]
updateAllModules existing modulesInOrder now =
  let composedKeys =
        Set.fromList
          [ (inst ^. #module_, inst ^. #parentVars)
          | (inst, _, _) <- modulesInOrder
          ]
      filtered =
        filter (\am -> not (Set.member (am ^. #name, am ^. #parentVars) composedKeys)) existing
      new =
        [ AppliedModule
            { name = inst ^. #module_,
              parentVars = inst ^. #parentVars,
              origin = origin,
              moduleVersion = m ^. #version,
              appliedAt = now,
              removal = m ^. #removal
            }
        | (inst, m, origin) <- modulesInOrder
        ]
   in filtered ++ new

-- | Print an error message and exit with code 1.
exitErr :: LogLevel -> Text -> IO a
exitErr level msg = do
  logIO level (logError msg)
  exitFailure

-- | Render a 'ModuleLoadError' for display.
renderModuleLoadError :: ModuleLoadError -> Text
renderModuleLoadError = \case
  ModuleNotFound name searched ->
    "Module '"
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
    "Circular dependency detected: "
      <> T.intercalate " -> " (map (^. #unModuleName) names)
  MissingSourceFile name path ->
    "Missing source file in '"
      <> name ^. #unModuleName
      <> "': "
      <> T.pack path
  RegistryEvalError path msg ->
    "Failed to evaluate registry at '" <> path <> "': " <> msg
