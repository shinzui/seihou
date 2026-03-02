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
import Seihou.CLI.Shared (deriveNamespace, formatConfigError, formatVarError, toVarNameMap)
import Seihou.Core.Module (defaultSearchPaths, loadModule)
import Seihou.Core.Types
import Seihou.Core.Variable (formatExplain, resolveVariables)
import Seihou.Effect.ConfigReader (readGlobalConfig, readLocalConfig, readNamespaceConfig)
import Seihou.Effect.ConfigReaderInterp (runConfigReader)
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
      TIO.putStrLn $ "Module '" <> unModuleName modName <> "' not found."
      TIO.putStrLn "Searched in:"
      mapM_ (\p -> TIO.putStrLn $ "  " <> T.pack p) searched
      exitFailure
    Left err -> do
      TIO.putStrLn $ "Error: " <> T.pack (show err)
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
      TIO.putStrLn $ "Variables for module '" <> unModuleName (moduleName modul) <> "':"
      TIO.putStrLn ""
      mapM_ printVarDecl vars

printVarDecl :: VarDecl -> IO ()
printVarDecl decl = do
  let name = unVarName (varName decl)
      ty = formatType (varType decl)
      defStr = case varDefault decl of
        Nothing -> "required"
        Just v -> "default: " <> formatValue v
      desc = case varDescription decl of
        Nothing -> ""
        Just d -> "  " <> d
  TIO.putStrLn $ "  " <> name <> " (" <> ty <> ", " <> defStr <> ")" <> desc

formatType :: VarType -> Text
formatType VTText = "text"
formatType VTBool = "bool"
formatType VTInt = "int"
formatType (VTList t) = "list[" <> formatType t <> "]"
formatType (VTChoice opts) = "choice[" <> T.intercalate "|" opts <> "]"

formatValue :: VarValue -> Text
formatValue (VText t) = "\"" <> t <> "\""
formatValue (VBool True) = "true"
formatValue (VBool False) = "false"
formatValue (VInt n) = T.pack (show n)
formatValue (VList vs) = "[" <> T.intercalate ", " (map formatValue vs) <> "]"

-- | Explain mode: resolve variables and show provenance
explainMode :: Module -> VarsOpts -> IO ()
explainMode modul vopts = do
  envPairs <- getEnvironment
  let cliOverrides = Map.fromList [(VarName k, v) | (k, v) <- varsVars vopts]
      envVars = Map.fromList [(T.pack k, T.pack v) | (k, v) <- envPairs]
      namespace = fromMaybe (deriveNamespace (varsModule vopts)) (varsNamespace vopts)
  result <- runEff $ runConfigReader $ do
    localCfg <- readLocalConfig >>= unwrapConfig
    namespaceCfg <- readNamespaceConfig namespace >>= unwrapConfig
    globalCfg <- readGlobalConfig >>= unwrapConfig
    let localMap = toVarNameMap localCfg
        nsMap = toVarNameMap namespaceCfg
        globalMap = toVarNameMap globalCfg
    pure $ resolveVariables (moduleVars modul) cliOverrides envVars localMap nsMap globalMap
  case result of
    Left errs -> do
      TIO.putStrLn "Error resolving variables:"
      mapM_ (TIO.putStrLn . ("  " <>) . formatVarError) errs
      exitFailure
    Right resolved -> do
      TIO.putStrLn $ "Variable provenance for module '" <> unModuleName (moduleName modul) <> "':"
      TIO.putStrLn ""
      TIO.putStr (formatExplain resolved)

-- | Unwrap an 'Either ConfigError' in an effectful context, printing an error
-- and exiting on 'Left'.
unwrapConfig :: (IOE :> es) => Either ConfigError a -> Eff es a
unwrapConfig (Right a) = pure a
unwrapConfig (Left err) = liftIO $ do
  TIO.putStrLn $ "Error reading config: " <> formatConfigError err
  exitFailure
