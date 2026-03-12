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
import Seihou.Composition.Resolve (loadComposition, resolveWithPrompts)
import Seihou.Core.Context (resolveContext)
import Seihou.Core.Module (defaultSearchPaths, loadModule)
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

  if vopts.varsExplain
    then explainMode modName vopts
    else do
      -- Declaration mode: load single module, show declarations
      searchPaths <- defaultSearchPaths
      result <- loadModule searchPaths modName
      modul <- case result of
        Left (ModuleNotFound _ searched) -> do
          logIO LogNormal $ do
            logError $ "Module '" <> modName.unModuleName <> "' not found."
            logError "Searched in:"
            mapM_ (\p -> logError $ "  " <> T.pack p) searched
          exitFailure
        Left err -> do
          logIO LogNormal (logError $ T.pack (show err))
          exitFailure
        Right m -> pure m
      declarationMode modul

-- | Default mode: show variable declarations
declarationMode :: Module -> IO ()
declarationMode modul = do
  let vs = modul.vars
  if null vs
    then TIO.putStrLn "No variables declared."
    else do
      TIO.putStrLn $ "Variables for " <> modul.name.unModuleName <> ":"
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
      -- Show only the target module's resolved variables
      let targetResolved = Map.findWithDefault Map.empty modName resolved
      TIO.putStrLn $ "Variables for " <> modName.unModuleName <> ":"
      TIO.putStrLn ""
      if Map.null targetResolved
        then TIO.putStrLn "  (no variables resolved)"
        else TIO.putStr (formatExplain targetResolved)

      -- Show diagnostics
      let allDecls = concatMap ((.vars) . fst) modulesInOrder
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
