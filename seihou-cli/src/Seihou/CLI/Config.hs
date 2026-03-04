module Seihou.CLI.Config
  ( handleConfig,
  )
where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Effectful
import Seihou.CLI.Commands (ConfigAction (..), ConfigOpts (..))
import Seihou.CLI.Shared (formatConfigError, logIO)
import Seihou.Core.Types (ConfigError, ConfigScope (..), LogLevel (..))
import Seihou.Effect.ConfigReader (readGlobalConfig, readLocalConfig, readNamespaceConfig)
import Seihou.Effect.ConfigReaderInterp (runConfigReader)
import Seihou.Effect.ConfigWriter (deleteConfigValue, listConfigValues, writeConfigValue)
import Seihou.Effect.ConfigWriterInterp (runConfigWriter)
import Seihou.Effect.Logger (logError)
import System.Exit (exitFailure)

handleConfig :: ConfigOpts -> IO ()
handleConfig ConfigOpts {configAction, configGlobal, configNamespace} = do
  let scope = resolveScope configGlobal configNamespace
  case configAction of
    ConfigSet key value -> handleSet scope key value
    ConfigGet key -> handleGet scope key
    ConfigUnset key -> handleUnset scope key
    ConfigList -> handleList configGlobal configNamespace

resolveScope :: Bool -> Maybe Text -> ConfigScope
resolveScope True _ = ScopeGlobal
resolveScope _ (Just ns) = ScopeNamespace ns
resolveScope _ _ = ScopeLocal

scopeLabel :: ConfigScope -> Text
scopeLabel ScopeLocal = "local"
scopeLabel (ScopeNamespace ns) = "namespace " <> ns
scopeLabel ScopeGlobal = "global"

handleSet :: ConfigScope -> Text -> Text -> IO ()
handleSet scope key value = do
  runEff $ runConfigWriter $ writeConfigValue scope key value
  TIO.putStrLn $ "Set " <> key <> " = " <> value <> " in " <> scopeLabel scope <> " config"

handleGet :: ConfigScope -> Text -> IO ()
handleGet scope key = do
  result <- runEff $ runConfigWriter $ listConfigValues scope
  case result of
    Left err -> configError err
    Right m -> case Map.lookup key m of
      Just val -> TIO.putStrLn val
      Nothing -> TIO.putStrLn $ key <> " is not set in " <> scopeLabel scope <> " config"

handleUnset :: ConfigScope -> Text -> IO ()
handleUnset scope key = do
  result <- runEff $ runConfigWriter $ listConfigValues scope
  case result of
    Left err -> configError err
    Right m ->
      if Map.member key m
        then do
          runEff $ runConfigWriter $ deleteConfigValue scope key
          TIO.putStrLn $ "Removed " <> key <> " from " <> scopeLabel scope <> " config"
        else TIO.putStrLn $ key <> " is not set in " <> scopeLabel scope <> " config"

handleList :: Bool -> Maybe Text -> IO ()
handleList isGlobal mNamespace
  | isGlobal = listScope ScopeGlobal
  | Just ns <- mNamespace = listScope (ScopeNamespace ns)
  | otherwise = listAllScopes

listScope :: ConfigScope -> IO ()
listScope scope = do
  result <- runEff $ runConfigWriter $ listConfigValues scope
  case result of
    Left err -> configError err
    Right m
      | Map.null m -> TIO.putStrLn $ "No config values in " <> scopeLabel scope <> " scope"
      | otherwise -> do
          TIO.putStrLn $ scopeLabel scope <> " config:"
          mapM_ printEntry (Map.toAscList m)

listAllScopes :: IO ()
listAllScopes = do
  results <- runEff $ runConfigReader $ do
    l <- readLocalConfig
    g <- readGlobalConfig
    pure (l, g)
  let (localResult, globalResult) = results
  printScopeIfNonEmpty "local" localResult
  printScopeIfNonEmpty "global" globalResult

printScopeIfNonEmpty :: Text -> Either ConfigError (Map.Map Text Text) -> IO ()
printScopeIfNonEmpty label result =
  case result of
    Left err -> do
      TIO.putStrLn $ label <> " config: " <> formatConfigError err
    Right m
      | Map.null m -> pure ()
      | otherwise -> do
          TIO.putStrLn $ label <> " config:"
          mapM_ printEntry (Map.toAscList m)
          TIO.putStrLn ""

printEntry :: (Text, Text) -> IO ()
printEntry (key, value) = TIO.putStrLn $ "  " <> key <> " = " <> value

configError :: ConfigError -> IO ()
configError err = do
  logIO LogNormal (logError $ "Config error: " <> formatConfigError err)
  exitFailure
