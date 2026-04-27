module Seihou.CLI.Config
  ( handleConfig,
  )
where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.Commands (ConfigAction (..), ConfigOpts (..))
import Seihou.CLI.Shared (formatConfigError, logIO)
import Seihou.Core.Types (ConfigError, ConfigScope (..), LogLevel (..))
import Seihou.Effect.ConfigReader (readContextConfig, readGlobalConfig, readLocalConfig, readNamespaceConfig)
import Seihou.Effect.ConfigReaderInterp (runConfigReader)
import Seihou.Effect.ConfigWriter (deleteConfigValue, listConfigValues, writeConfigValue)
import Seihou.Effect.ConfigWriterInterp (runConfigWriter)
import Seihou.Effect.Logger (logError)
import Seihou.Prelude
import System.Exit (exitFailure)

handleConfig :: ConfigOpts -> IO ()
handleConfig ConfigOpts {configAction, configGlobal, configNamespace, configContext, configEffective} = do
  let scope = resolveScope configGlobal configNamespace configContext
  case configAction of
    ConfigSet key value -> handleSet scope key value
    ConfigGet key -> handleGet scope key
    ConfigUnset key -> handleUnset scope key
    ConfigList
      | configEffective -> handleListEffective configNamespace configContext
      | otherwise -> handleList configGlobal configNamespace configContext

resolveScope :: Bool -> Maybe Text -> Maybe Text -> ConfigScope
resolveScope True _ _ = ScopeGlobal
resolveScope _ (Just ns) _ = ScopeNamespace ns
resolveScope _ _ (Just ctx) = ScopeContext ctx
resolveScope _ _ _ = ScopeLocal

scopeLabel :: ConfigScope -> Text
scopeLabel ScopeLocal = "local"
scopeLabel (ScopeNamespace ns) = "namespace " <> ns
scopeLabel (ScopeContext ctx) = "context " <> ctx
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

handleList :: Bool -> Maybe Text -> Maybe Text -> IO ()
handleList isGlobal mNamespace mContext
  | isGlobal = listScope ScopeGlobal
  | Just ns <- mNamespace = listScope (ScopeNamespace ns)
  | Just ctx <- mContext = listScope (ScopeContext ctx)
  | otherwise = listAllScopes

-- | Show the merged effective config across all scopes.
-- Precedence: local > namespace > global (matching variable resolution order).
handleListEffective :: Maybe Text -> Maybe Text -> IO ()
handleListEffective mNamespace mContext = do
  results <- runEff $ runConfigReader $ do
    l <- readLocalConfig
    n <- case mNamespace of
      Just ns -> readNamespaceConfig ns
      Nothing -> pure (Right Map.empty)
    c <- case mContext of
      Just ctx -> readContextConfig ctx
      Nothing -> pure (Right Map.empty)
    g <- readGlobalConfig
    pure (l, n, c, g)
  let (localResult, nsResult, ctxResult, globalResult) = results
  case (globalResult, ctxResult, nsResult, localResult) of
    (Left err, _, _, _) -> configError err
    (_, Left err, _, _) -> configError err
    (_, _, Left err, _) -> configError err
    (_, _, _, Left err) -> configError err
    (Right globalMap, Right ctxMap, Right nsMap, Right localMap) -> do
      -- Build merged map with source tracking: local > namespace > context > global
      let taggedGlobal = Map.map (\v -> (v, "global" :: Text)) globalMap
          taggedCtx = Map.map (\v -> (v, maybe "context" (\ctx -> "context: " <> ctx) mContext)) ctxMap
          taggedNs = Map.map (\v -> (v, maybe "namespace" (\ns -> "namespace: " <> ns) mNamespace)) nsMap
          taggedLocal = Map.map (\v -> (v, "local")) localMap
          merged = taggedLocal `Map.union` taggedNs `Map.union` taggedCtx `Map.union` taggedGlobal
      if Map.null merged
        then TIO.putStrLn "No config values set in any scope."
        else do
          TIO.putStrLn "Effective config:"
          let entries = Map.toAscList merged
              maxKeyLen = maximum (0 : map (T.length . fst) entries)
              maxValLen = maximum (0 : map (T.length . fst . snd) entries)
          mapM_ (printEffectiveEntry maxKeyLen maxValLen) entries

printEffectiveEntry :: Int -> Int -> (Text, (Text, Text)) -> IO ()
printEffectiveEntry maxKeyLen maxValLen (key, (value, source)) = do
  let keyPad = T.replicate (maxKeyLen - T.length key) " "
      valPad = T.replicate (maxValLen - T.length value) " "
  TIO.putStrLn $ "  " <> key <> keyPad <> " = " <> value <> valPad <> "  [" <> source <> "]"

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
