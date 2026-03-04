module Seihou.CLI.Vars
  ( handleVars,
  )
where

import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Effectful
import Seihou.CLI.Commands (VarsOpts (..))
import Seihou.CLI.Shared (deriveNamespace, formatVarError, logIO, toVarNameMap, unwrapConfig)
import Seihou.Core.Module (defaultSearchPaths, loadModule)
import Seihou.Core.Types
import Seihou.Core.Variable (formatDeclarations, formatExplain, resolveVariables)
import Seihou.Effect.ConfigReader (readGlobalConfig, readLocalConfig, readNamespaceConfig)
import Seihou.Effect.ConfigReaderInterp (runConfigReader)
import Seihou.Effect.Logger (logError)
import System.Environment (getEnvironment)
import System.Exit (exitFailure)

handleVars :: VarsOpts -> IO ()
handleVars vopts = do
  let modName = varsModule vopts

  -- Load the module
  searchPaths <- defaultSearchPaths
  result <- loadModule searchPaths modName
  modul <- case result of
    Left (ModuleNotFound _ searched) -> do
      logIO LogNormal $ do
        logError $ "Module '" <> unModuleName modName <> "' not found."
        logError "Searched in:"
        mapM_ (\p -> logError $ "  " <> T.pack p) searched
      exitFailure
    Left err -> do
      logIO LogNormal (logError $ T.pack (show err))
      exitFailure
    Right m -> pure m

  if varsExplain vopts
    then explainMode modul vopts
    else declarationMode modul

-- | Default mode: show variable declarations
declarationMode :: Module -> IO ()
declarationMode modul = do
  let vars = moduleVars modul
  if null vars
    then TIO.putStrLn "No variables declared."
    else do
      TIO.putStrLn $ "Variables for " <> unModuleName (moduleName modul) <> ":"
      TIO.putStrLn ""
      TIO.putStr (formatDeclarations vars)

-- | Explain mode: resolve variables and show provenance
explainMode :: Module -> VarsOpts -> IO ()
explainMode modul vopts = do
  envPairs <- getEnvironment
  let cliOverrides = Map.fromList [(VarName k, v) | (k, v) <- varsVars vopts]
      envVars = Map.fromList [(T.pack k, T.pack v) | (k, v) <- envPairs]
      namespace = fromMaybe (deriveNamespace (varsModule vopts)) (varsNamespace vopts)
  result <- runEff $ runConfigReader $ do
    localCfg <- readLocalConfig >>= unwrapConfig LogNormal
    namespaceCfg <- readNamespaceConfig namespace >>= unwrapConfig LogNormal
    globalCfg <- readGlobalConfig >>= unwrapConfig LogNormal
    let localMap = toVarNameMap localCfg
        nsMap = toVarNameMap namespaceCfg
        globalMap = toVarNameMap globalCfg
    pure $ resolveVariables (moduleVars modul) cliOverrides envVars namespace localMap nsMap globalMap
  case result of
    Left errs -> do
      logIO LogNormal $ do
        logError "Error resolving variables:"
        mapM_ (logError . ("  " <>) . formatVarError) errs
      exitFailure
    Right resolved -> do
      TIO.putStrLn $ "Variables for " <> unModuleName (moduleName modul) <> ":"
      TIO.putStrLn ""
      TIO.putStr (formatExplain resolved)
