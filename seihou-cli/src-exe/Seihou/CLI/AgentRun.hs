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

import Control.Monad (when)
import Data.FileEmbed (embedFile)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Set qualified as Set
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Data.Time (UTCTime)
import Data.Time.Clock (getCurrentTime)
import Seihou.CLI.AgentCompletion
  ( AgentModelConfig (..),
    AgentProvider (..),
    buildAgentCompletionRequest,
    runAgentCompletion,
  )
import Seihou.CLI.AgentLaunch
  ( AgentContext (..),
    BaselineStatus (..),
    formatAvailableModules,
    formatBaselineStatus,
    formatLocalModules,
    formatManifestState,
    formatModuleDhallState,
    formatReferenceFiles,
    formatSeihouProjectState,
    gatherAgentContext,
    setupAllowedTools,
    substitute,
  )
import Seihou.CLI.AgentLaunchExec (launchConfiguredAgent)
import Seihou.CLI.AppliedBlueprint (recordAppliedBlueprint)
import Seihou.CLI.Commands (BlueprintRunOpts (..))
import Seihou.CLI.Shared
  ( deriveNamespace,
    formatVarError,
    logIO,
    toVarNameMap,
    unwrapConfig,
  )
import Seihou.Composition.Instance (ModuleInstance (..), primaryInstance, qualifiedName)
import Seihou.Composition.Plan (compileComposedPlan)
import Seihou.Composition.Resolve (loadComposition, resolveWithPrompts)
import Seihou.Core.Context (resolveContext)
import Seihou.Core.Module (defaultSearchPaths, discoverRunnable)
import Seihou.Core.Types
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
import Seihou.Effect.Logger (logError, logInfo)
import Seihou.Effect.ManifestStore (readManifest, writeManifest)
import Seihou.Effect.ManifestStoreInterp (runManifestStore)
import Seihou.Engine.Conflict (resolveConflicts)
import Seihou.Engine.Diff (computeDiff)
import Seihou.Engine.Execute (executePlan)
import Seihou.Manifest.Types (currentManifestVersion, emptyManifest)
import Seihou.Prelude
import System.Environment (getEnvironment)
import System.Exit (ExitCode (..), exitFailure, exitWith)
import System.FilePath (takeDirectory)

-- | The prompt template, embedded at compile time from data/blueprint-prompt.md.
promptTemplate :: Text
promptTemplate = TE.decodeUtf8 $(embedFile "data/blueprint-prompt.md")

handleAgentRun :: Bool -> AgentModelConfig -> BlueprintRunOpts -> IO ()
handleAgentRun debug modelConfig opts = do
  let level = if opts.runBlueprintVerbose then LogVerbose else LogNormal

  -- (a) Discover and validate. discoverRunnable resolves by directory
  -- name (priority: module > recipe > blueprint).
  searchPaths <- defaultSearchPaths
  runnableResult <- discoverRunnable searchPaths opts.runBlueprintName
  (bp, blueprintDir) <- case runnableResult of
    Right (RunnableBlueprint b dir) -> pure (b, dir)
    Right (RunnableModule _ _) ->
      exitErr level $
        "'"
          <> opts.runBlueprintName.unModuleName
          <> "' is a module, not a blueprint. Did you mean 'seihou run "
          <> opts.runBlueprintName.unModuleName
          <> "'?"
    Right (RunnableRecipe _ _) ->
      exitErr level $
        "'"
          <> opts.runBlueprintName.unModuleName
          <> "' is a recipe, not a blueprint. Did you mean 'seihou run "
          <> opts.runBlueprintName.unModuleName
          <> "'?"
    Left err -> exitErr level (renderModuleLoadError err)

  -- (b) Resolve blueprint variables. Wrap the blueprint's vars/prompts
  -- in a placeholder Module so 'resolveWithPrompts' can run the
  -- standard precedence chain (CLI > env > local > namespace > context
  -- > global > defaults > interactive prompts).
  let placeholderModule =
        Module
          { name = bp.name,
            version = bp.version,
            description = bp.description,
            vars = bp.vars,
            exports = [],
            prompts = bp.prompts,
            steps = [],
            commands = [],
            dependencies = [],
            removal = Nothing,
            migrations = []
          }
      placeholderInst = primaryInstance bp.name
      placeholderTriple = (placeholderInst, placeholderModule, blueprintDir)

  envPairs <- getEnvironment
  let cliOverrides = Map.fromList [(VarName k, v) | (k, v) <- opts.runBlueprintVars]
      envVars = Map.fromList [(T.pack k, T.pack v) | (k, v) <- envPairs]
      namespace = fromMaybe (deriveNamespace bp.name) opts.runBlueprintNamespace
  context <- resolveContext opts.runBlueprintContext envVars
  let contextName = fromMaybe "" context

  resolveResult <- runEff $ runConfigReader $ runConsole $ do
    localCfg <- readLocalConfig >>= unwrapConfig level
    nsCfg <- readNamespaceConfig namespace >>= unwrapConfig level
    ctxCfg <- readContextConfig contextName >>= unwrapConfig level
    gCfg <- readGlobalConfig >>= unwrapConfig level
    resolveWithPrompts
      [placeholderTriple]
      cliOverrides
      envVars
      namespace
      contextName
      (toVarNameMap localCfg)
      (toVarNameMap nsCfg)
      (toVarNameMap ctxCfg)
      (toVarNameMap gCfg)

  resolved <- case resolveResult of
    Left errs -> do
      logIO level $ logError "Error resolving blueprint variables:"
      mapM_ (logIO level . logError . ("  " <>) . formatVarError) errs
      exitFailure
    Right r -> pure (Map.findWithDefault Map.empty placeholderInst r)

  -- (c) Baseline.
  baseline <-
    if opts.runBlueprintNoBaseline
      then pure BaselineSkipped
      else
        if null bp.baseModules
          then pure BaselineEmpty
          else applyBaseline level opts bp.baseModules cliOverrides resolved

  -- (d) Render the user prompt: substitute resolved vars into bp.prompt.
  let renderedUser = renderUserPrompt resolved bp.prompt

  -- (e) Render the system prompt around the user body.
  ctx <- gatherAgentContext
  let systemPrompt = renderSystemPrompt ctx bp baseline renderedUser

  -- (f) Launch.
  launchSucceeded <-
    runRenderedAgentPrompt debug modelConfig systemPrompt opts.runBlueprintPrompt

  -- (g) Record the applied-blueprint provenance into
  -- .seihou/manifest.json only after a successful provider response. In
  -- debug mode, keep the previous successful dry-launch behavior by recording
  -- after the rendered prompt is printed successfully.
  when launchSucceeded $ do
    now <- getCurrentTime
    let entry = appliedBlueprintFromOutcome bp baseline opts now
        manifestPath = ".seihou" </> "manifest.json"
    writeRes <- recordAppliedBlueprint manifestPath entry
    case writeRes of
      Right () -> pure ()
      Left err ->
        logIO level $
          logError $
            "Warning: agent succeeded but recording the applied-blueprint entry failed: "
              <> err

runRenderedAgentPrompt :: Bool -> AgentModelConfig -> Text -> Maybe Text -> IO Bool
runRenderedAgentPrompt debug modelConfig systemPrompt initialPrompt
  | debug = do
      TIO.putStr systemPrompt
      pure True
  | modelConfig.agentProvider == AgentProviderClaudeCli || modelConfig.agentProvider == AgentProviderCodexCli = do
      exitCode <- launchConfiguredAgent modelConfig setupAllowedTools debug systemPrompt initialPrompt
      case exitCode of
        ExitSuccess -> pure True
        ExitFailure _ -> exitWith exitCode
  | otherwise = do
      result <- runAgentCompletion (buildAgentCompletionRequest modelConfig systemPrompt initialPrompt)
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
  Blueprint -> BaselineStatus -> BlueprintRunOpts -> UTCTime -> AppliedBlueprint
appliedBlueprintFromOutcome bp baseline opts now =
  AppliedBlueprint
    { name = bp.name,
      blueprintVersion = bp.version,
      appliedAt = now,
      baselineModules = case baseline of
        BaselineApplied entries -> map fst entries
        BaselineEmpty -> []
        BaselineSkipped -> [],
      noBaseline = case baseline of
        BaselineSkipped -> True
        _ -> False,
      userPrompt = opts.runBlueprintPrompt,
      agentSessionId = Nothing
    }

-- | Apply the blueprint's @baseModules@ to the cwd. Mirrors the
-- composition pipeline in @Seihou.CLI.Run.handleRun@: load every
-- declared base module (plus transitive deps), resolve their variables
-- through the same precedence chain (with the blueprint's own resolved
-- vars folded into the CLI override map so the agent's prompt and the
-- base modules see the same values), compile the composed plan,
-- compute the diff, resolve conflicts, execute the plan, and write the
-- resulting manifest. Returns 'BaselineApplied' listing each module's
-- (name, version) for the prompt's "Baseline" section.
applyBaseline ::
  LogLevel ->
  BlueprintRunOpts ->
  [Dependency] ->
  Map VarName Text ->
  Map VarName ResolvedVar ->
  IO BaselineStatus
applyBaseline level opts baseModules cliOverridesIn resolvedBlueprintVars = do
  searchPaths <- defaultSearchPaths
  (primary, additionals) <- case baseModules of
    d : rs -> pure (d.depModule, map (.depModule) rs)
    [] -> exitErr level "internal error: applyBaseline called with empty baseModules"
  compositionResult <- loadComposition searchPaths primary additionals
  modulesInOrder <- case compositionResult of
    Left err -> do
      logIO level $ logError $ "Baseline error: " <> renderModuleLoadError err
      exitFailure
    Right ms -> pure ms

  -- Fold the blueprint's resolved vars into the CLI override map for
  -- the base modules. CLI overrides (already present in cliOverridesIn)
  -- win over blueprint values, mirroring 'seihou run' semantics.
  let blueprintAsOverrides =
        Map.fromList
          [(vn, varValueToText rv.value) | (vn, rv) <- Map.toList resolvedBlueprintVars]
      cliOverrides = Map.union cliOverridesIn blueprintAsOverrides

  envPairs <- getEnvironment
  let envVars = Map.fromList [(T.pack k, T.pack v) | (k, v) <- envPairs]
      namespace = fromMaybe (deriveNamespace primary) opts.runBlueprintNamespace
  context <- resolveContext opts.runBlueprintContext envVars
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
        [ (inst, m, dir, Map.map (.value) (baseResolved Map.! inst))
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
            concatMap (\(inst, _, _) -> [inst.instanceModule, qualifiedName inst]) modulesInOrder
    computeDiff manifest composedNames planned

  resolutions <-
    runEff $ runConsole $ resolveConflicts opts.runBlueprintForce diff.conflicts
  case resolutions of
    Nothing -> do
      logIO level $ logError "Baseline conflicts detected (use --force to overwrite):"
      mapM_ (\c -> logIO level (logError ("  ! " <> T.pack c.path))) diff.conflicts
      exitFailure
    Just conflictResolved -> do
      let keepRecords =
            Map.fromList
              [ ( c.path,
                  case Map.lookup c.path manifest.files of
                    Just existing -> existing {hash = c.diskHash, generatedAt = now}
                    Nothing ->
                      FileRecord
                        { hash = c.diskHash,
                          moduleName = c.moduleName,
                          strategy = Template,
                          generatedAt = now
                        }
                )
              | (c, KeepCurrent) <- conflictResolved
              ]
          skipPaths = [c.path | (c, Skip) <- conflictResolved]
          excludePaths = Set.fromList (Map.keys keepRecords ++ skipPaths)
          opsForExec = filter (not . opTargetsPath excludePaths) ops

      runEff $ runFilesystem $ runManifestStore manifestPath $ do
        recs <- executePlan "" opsForExec ownerMap primary now

        let orphanedPaths = map (.path) diff.orphaned
            cleanedFiles = foldr Map.delete manifest.files orphanedPaths
            allModuleEntries = updateAllModules manifest.modules modulesInOrder now
            allResolvedVals =
              Map.unions [Map.map (.value) vs | vs <- Map.elems baseResolved]
            newManifest =
              Manifest
                { version = currentManifestVersion,
                  genAt = now,
                  modules = allModuleEntries,
                  vars = Map.union (Map.map varValueToText allResolvedVals) manifest.vars,
                  files = Map.unions [recs, keepRecords, cleanedFiles],
                  recipe = manifest.recipe,
                  blueprint = manifest.blueprint
                }
        writeManifest newManifest

      let nNew = length diff.new
          nMod = length diff.modified
          nUnch = length diff.unchanged
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
          [(m.name, m.version) | (_, m, _) <- modulesInOrder]

-- | Stitch the system-prompt template together. Each block in
-- @blueprint-prompt.md@ has a @{{key}}@ placeholder filled here.
renderSystemPrompt :: AgentContext -> Blueprint -> BaselineStatus -> Text -> Text
renderSystemPrompt ctx bp baseline userPrompt =
  substitute
    [ ("cwd", ctx.cwd),
      ("seihou_project_state", formatSeihouProjectState ctx),
      ("manifest_state", formatManifestState ctx),
      ("module_dhall_state", formatModuleDhallState ctx),
      ("local_modules", formatLocalModules ctx),
      ("available_modules", formatAvailableModules ctx),
      ("blueprint_name", bp.name.unModuleName),
      ("blueprint_version", fromMaybe "(unspecified)" bp.version),
      ("blueprint_description", fromMaybe "(no description)" bp.description),
      ("baseline_status", formatBaselineStatus baseline),
      ("reference_files", formatReferenceFiles bp.files),
      ("user_prompt", userPrompt)
    ]
    promptTemplate

-- | Substitute resolved blueprint variables into the user prompt body.
renderUserPrompt :: Map VarName ResolvedVar -> Text -> Text
renderUserPrompt resolved tpl =
  substitute
    [(vn.unVarName, varValueToText rv.value) | (vn, rv) <- Map.toList resolved]
    tpl

-- | Local copy of @Seihou.CLI.Run.varValueToText@. Kept in sync with the
-- original; if a third caller appears, lift it into Seihou.CLI.Shared.
varValueToText :: VarValue -> Text
varValueToText (VText t) = t
varValueToText (VBool True) = "true"
varValueToText (VBool False) = "false"
varValueToText (VInt n) = T.pack (show n)
varValueToText (VList vs) = T.intercalate "," (map varValueToText vs)

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
  [(ModuleInstance, Module, FilePath)] ->
  UTCTime ->
  [AppliedModule]
updateAllModules existing modulesInOrder now =
  let composedKeys =
        Set.fromList
          [ (inst.instanceModule, inst.instanceParentVars)
          | (inst, _, _) <- modulesInOrder
          ]
      filtered =
        filter (\am -> not (Set.member (am.name, am.parentVars) composedKeys)) existing
      new =
        [ AppliedModule
            { name = inst.instanceModule,
              parentVars = inst.instanceParentVars,
              source = dir,
              moduleVersion = m.version,
              appliedAt = now,
              removal = m.removal
            }
        | (inst, m, dir) <- modulesInOrder
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
    "Circular dependency detected: "
      <> T.intercalate " -> " (map (.unModuleName) names)
  MissingSourceFile name path ->
    "Missing source file in '"
      <> name.unModuleName
      <> "': "
      <> T.pack path
  RegistryEvalError path msg ->
    "Failed to evaluate registry at '" <> path <> "': " <> msg
