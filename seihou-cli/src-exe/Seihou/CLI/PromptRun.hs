module Seihou.CLI.PromptRun
  ( handlePromptRun,
  )
where

import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Set qualified as Set
import Data.Text qualified as T
import Seihou.CLI.AgentCompletion (AgentModelConfig)
import Seihou.CLI.AgentLaunch (gatherAgentContext, setupAllowedTools)
import Seihou.CLI.AgentRun (runRenderedAgentPrompt)
import Seihou.CLI.Commands (PromptRunOpts (..))
import Seihou.CLI.PromptRender (renderPromptBody, renderPromptSystemPrompt)
import Seihou.CLI.Shared
  ( deriveNamespace,
    formatVarError,
    logIO,
    toVarNameMap,
    unwrapConfig,
  )
import Seihou.Composition.Instance (primaryInstance)
import Seihou.Composition.Resolve (resolveWithPrompts)
import Seihou.Core.AgentPrompt (validateAgentPrompt)
import Seihou.Core.CommandVar (resolveCommandVars)
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
import Seihou.Effect.Logger (logError)
import Seihou.Effect.ProcessInterp (runProcessIO)
import Seihou.Prelude
import System.Environment (getEnvironment)
import System.Exit (exitFailure)

handlePromptRun :: AgentModelConfig -> PromptRunOpts -> IO ()
handlePromptRun modelConfig opts = do
  let level = if opts.runPromptVerbose then LogVerbose else LogNormal

  searchPaths <- defaultSearchPaths
  runnableResult <- discoverRunnable searchPaths opts.runPromptName
  (prompt, promptDir) <- case runnableResult of
    Right (RunnableAgentPrompt p dir) -> pure (p, dir)
    Right (RunnableModule _ _) ->
      exitErr level $
        "'"
          <> opts.runPromptName.unModuleName
          <> "' is a module, not a prompt. Did you mean 'seihou run "
          <> opts.runPromptName.unModuleName
          <> "'?"
    Right (RunnableRecipe _ _) ->
      exitErr level $
        "'"
          <> opts.runPromptName.unModuleName
          <> "' is a recipe, not a prompt. Did you mean 'seihou run "
          <> opts.runPromptName.unModuleName
          <> "'?"
    Right (RunnableBlueprint _ _) ->
      exitErr level $
        "'"
          <> opts.runPromptName.unModuleName
          <> "' is a blueprint, not a prompt. Did you mean 'seihou agent run "
          <> opts.runPromptName.unModuleName
          <> "'?"
    Left err -> exitErr level (renderModuleLoadError err)

  validation <- validateAgentPrompt promptDir prompt
  case validation of
    Left err -> exitErr level (renderModuleLoadError err)
    Right _ -> pure ()

  let placeholderModule =
        Module
          { name = prompt.name,
            version = prompt.version,
            description = prompt.description,
            vars = relaxCommandVarDecls prompt.commandVars prompt.vars,
            exports = [],
            prompts = prompt.prompts,
            steps = [],
            commands = [],
            dependencies = [],
            removal = Nothing,
            migrations = []
          }
      placeholderInst = primaryInstance prompt.name
      placeholderTriple = (placeholderInst, placeholderModule, promptDir)

  envPairs <- getEnvironment
  let cliOverrides = Map.fromList [(VarName k, v) | (k, v) <- opts.runPromptVars]
      envVars = Map.fromList [(T.pack k, T.pack v) | (k, v) <- envPairs]
      namespace = fromMaybe (deriveNamespace prompt.name) opts.runPromptNamespace
  context <- resolveContext opts.runPromptContext envVars
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

  resolvedNormal <- case resolveResult of
    Left errs -> do
      logIO level $ do
        logError "Error resolving prompt variables:"
        mapM_ (logError . ("  " <>) . formatVarError) errs
      exitFailure
    Right r -> pure (Map.findWithDefault Map.empty placeholderInst r)

  commandResult <- runEff $ runProcessIO $ resolveCommandVars prompt.vars prompt.commandVars resolvedNormal
  resolved <- case commandResult of
    Left errs -> do
      logIO level $ do
        logError "Error resolving command variables:"
        mapM_ (logError . ("  " <>) . formatVarError) errs
      exitFailure
    Right r -> pure r

  let renderedPrompt = renderPromptBody resolved prompt.prompt
  ctx <- gatherAgentContext
  let systemPrompt = renderPromptSystemPrompt ctx prompt resolved renderedPrompt opts.runPromptPrompt

  _ <-
    runRenderedAgentPrompt
      opts.runPromptDebug
      modelConfig
      setupAllowedTools
      Nothing
      systemPrompt
      opts.runPromptPrompt
  pure ()

relaxCommandVarDecls :: [CommandVar] -> [VarDecl] -> [VarDecl]
relaxCommandVarDecls commandVars =
  map relaxOne
  where
    commandNames = Set.fromList (map (.name) commandVars)
    relaxOne decl
      | Set.member decl.name commandNames = decl {required = False}
      | otherwise = decl

exitErr :: LogLevel -> Text -> IO a
exitErr level msg = do
  logIO level (logError msg)
  exitFailure

renderModuleLoadError :: ModuleLoadError -> Text
renderModuleLoadError = \case
  ModuleNotFound name searched ->
    "Prompt '"
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
