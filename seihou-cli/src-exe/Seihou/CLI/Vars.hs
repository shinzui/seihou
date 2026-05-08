module Seihou.CLI.Vars
  ( handleVars,
  )
where

import Control.Monad (when)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.Commands (VarsOpts (..))
import Seihou.CLI.Shared (deriveNamespace, formatVarError, logIO, toVarNameMap, unwrapConfig)
import Seihou.Composition.Instance (ModuleInstance (..))
import Seihou.Composition.Resolve (loadComposition, resolveWithPrompts)
import Seihou.Core.Context (resolveContext)
import Seihou.Core.Module (defaultSearchPaths, discoverRunnable)
import Seihou.Core.Types
import Seihou.Core.Variable (diagnoseResolution, formatDeclarations, formatExplain)
import Seihou.Effect.ConfigReader (readContextConfig, readGlobalConfig, readLocalConfig, readNamespaceConfig)
import Seihou.Effect.ConfigReaderInterp (runConfigReader)
import Seihou.Effect.ConsoleInterp (runConsole)
import Seihou.Effect.FzfInterp (runFzfIO)
import Seihou.Effect.Logger (logError, logInfo)
import Seihou.Fzf (FzfResult (..), detectFzfConfig, isFzfUsable)
import Seihou.Fzf.Selector (selectModule)
import Seihou.Prelude
import System.Environment (getEnvironment)
import System.Exit (ExitCode (..), exitFailure, exitWith)

handleVars :: VarsOpts -> IO ()
handleVars vopts = do
  -- Resolve module name (from argument or fzf picker)
  modName <- case vopts.varsModule of
    Just name -> pure name
    Nothing -> do
      fzfCfg <- detectFzfConfig
      if isFzfUsable fzfCfg
        then do
          result <- runEff $ runFzfIO fzfCfg $ selectModule
          case result of
            FzfSelected name -> pure name
            FzfCancelled -> exitWith ExitSuccess
            FzfNoMatch -> do
              logIO LogNormal (logError "No modules found.")
              exitFailure
            FzfError err -> do
              logIO LogNormal (logError $ "fzf error: " <> err)
              exitFailure
        else do
          logIO LogNormal (logError "MODULE argument is required when fzf is not available.")
          exitFailure

  -- Resolve the runnable's kind first so we can dispatch correctly:
  -- modules go through the existing module/composition pipeline,
  -- recipes show their declared vars in declaration mode, and
  -- blueprints get their own declaration-mode formatter and refuse
  -- @--explain@ entirely (resolving a blueprint's variables is the
  -- agent runner's job, not vars').
  searchPaths <- defaultSearchPaths
  discResult <- discoverRunnable searchPaths modName
  case discResult of
    Left (ModuleNotFound _ searched) -> do
      logIO LogNormal $ do
        logError $ "Module '" <> modName.unModuleName <> "' not found."
        logError "Searched in:"
        mapM_ (\p -> logError $ "  " <> T.pack p) searched
      exitFailure
    Left err -> do
      logIO LogNormal (logError $ T.pack (show err))
      exitFailure
    Right (RunnableModule m _) ->
      if vopts.varsExplain
        then explainMode modName vopts
        else declarationModeModule m
    Right (RunnableRecipe r _) ->
      if vopts.varsExplain
        then explainMode modName vopts
        else declarationModeRecipe r
    Right (RunnableBlueprint b _) ->
      if vopts.varsExplain
        then do
          logIO LogNormal $ do
            logError $ "'" <> modName.unModuleName <> "' is a blueprint; --explain is not supported in this release."
            logError "Resolving a blueprint's variables requires the agent runner."
            logError "Run `seihou agent run <blueprint>` instead (when EP-31 ships)."
            logError "For a read-only listing of declared variables, omit --explain."
          exitFailure
        else declarationModeBlueprint b

-- | Declaration mode for a module: list declared variables.
declarationModeModule :: Module -> IO ()
declarationModeModule modul = do
  let vs = modul.vars
  if null vs
    then TIO.putStrLn "No variables declared."
    else do
      TIO.putStrLn $ "Variables for " <> modul.name.unModuleName <> ":"
      TIO.putStrLn ""
      TIO.putStr (formatDeclarations vs)

-- | Declaration mode for a recipe: list its declared variables. Recipes
-- carry their own @vars@ list (separately from the modules they
-- compose); this prints those without expanding the recipe.
declarationModeRecipe :: Recipe -> IO ()
declarationModeRecipe r = do
  let vs = r.vars
  if null vs
    then TIO.putStrLn "No variables declared."
    else do
      TIO.putStrLn $ "Variables for " <> r.name.unRecipeName <> " (recipe):"
      TIO.putStrLn ""
      TIO.putStr (formatDeclarations vs)

-- | Declaration mode for a blueprint: list its declared variables. The
-- blueprint kind is surfaced in the heading so users can tell at a
-- glance that this is the agent-driven runnable, not a module/recipe.
declarationModeBlueprint :: Blueprint -> IO ()
declarationModeBlueprint b = do
  let vs = b.vars
  if null vs
    then TIO.putStrLn "No variables declared."
    else do
      TIO.putStrLn $ "Variables for " <> b.name.unModuleName <> " (blueprint):"
      TIO.putStrLn ""
      TIO.putStr (formatDeclarations vs)

-- | Explain mode: load full composition, resolve variables with exports, show provenance
explainMode :: ModuleName -> VarsOpts -> IO ()
explainMode modName vopts = do
  -- Load the full composition (target module + transitive dependencies)
  searchPaths <- defaultSearchPaths
  compositionResult <- loadComposition searchPaths modName []
  modulesInOrder <- case compositionResult of
    Left (ModuleNotFound name searched) -> do
      logIO LogNormal $ do
        logError $ "Module '" <> name.unModuleName <> "' not found."
        logError "Searched in:"
        mapM_ (\p -> logError $ "  " <> T.pack p) searched
      exitFailure
    Left (CircularDependency names) -> do
      logIO LogNormal $ do
        logError "Circular dependency detected:"
        logError $ "  " <> T.intercalate " -> " (map (.unModuleName) names)
      exitFailure
    Left err -> do
      logIO LogNormal (logError $ T.pack (show err))
      exitFailure
    Right ms -> pure ms

  -- Report composition when multiple modules are involved
  when (length modulesInOrder > 1) $
    logIO LogNormal $
      logInfo $
        "Resolving with "
          <> T.pack (show (length modulesInOrder))
          <> " modules in composition"

  -- Resolve variables with the full composition pipeline
  envPairs <- getEnvironment
  let cliOverrides = Map.fromList [(VarName k, v) | (k, v) <- vopts.varsVars]
      envVars = Map.fromList [(T.pack k, T.pack v) | (k, v) <- envPairs]
      namespace = fromMaybe (deriveNamespace modName) vopts.varsNamespace
  context <- resolveContext vopts.varsContext envVars
  let contextName = fromMaybe "" context
  (resolveResult, localMap, nsMap, ctxMap, globalMap) <- runEff $ runConfigReader $ runConsole $ do
    localCfg <- readLocalConfig >>= unwrapConfig LogNormal
    namespaceCfg <- readNamespaceConfig namespace >>= unwrapConfig LogNormal
    contextCfg <- readContextConfig contextName >>= unwrapConfig LogNormal
    globalCfg <- readGlobalConfig >>= unwrapConfig LogNormal
    let lm = toVarNameMap localCfg
        nm = toVarNameMap namespaceCfg
        cm = toVarNameMap contextCfg
        gm = toVarNameMap globalCfg
    r <- resolveWithPrompts modulesInOrder cliOverrides envVars namespace contextName lm nm cm gm
    pure (r, lm, nm, cm, gm)
  case resolveResult of
    Left errs -> do
      logIO LogNormal $ do
        logError "Error resolving variables:"
        mapM_ (logError . ("  " <>) . formatVarError) errs
      exitFailure
    Right resolved -> do
      -- Show only the target module's resolved variables. `seihou vars` is
      -- scoped to a module name, so if multiple instances exist we merge
      -- their resolved maps (last wins on overlap — matches how a user
      -- reads "the variables of module X" before any disambiguation UI).
      let targetResolved =
            Map.unions
              [ vs
              | (inst, vs) <- Map.toList resolved,
                inst.instanceModule == modName
              ]
      TIO.putStrLn $ "Variables for " <> modName.unModuleName <> ":"
      TIO.putStrLn ""
      if Map.null targetResolved
        then TIO.putStrLn "  (no variables resolved)"
        else TIO.putStr (formatExplain targetResolved)

      -- Show diagnostics
      let allDecls = concatMap (\(_, m, _) -> m.vars) modulesInOrder
          allResolved = Map.unions [vs | vs <- Map.elems resolved]
          (unusedKeys, unresolvedOpt) = diagnoseResolution allResolved allDecls localMap nsMap ctxMap globalMap
      when (not (null unusedKeys)) $ do
        TIO.putStrLn ""
        TIO.putStrLn "Unused config keys (not matching any declared variable):"
        mapM_ (\(VarName n) -> TIO.putStrLn $ "  " <> n) unusedKeys
      when (not (null unresolvedOpt)) $ do
        TIO.putStrLn ""
        TIO.putStrLn "Unresolved optional variables:"
        mapM_ (\(VarName n) -> TIO.putStrLn $ "  " <> n) unresolvedOpt
