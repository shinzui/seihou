module Seihou.Effect.ConfigReaderInterp
  ( runConfigReader,
  )
where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Seihou.Core.Types (ConfigError (..))
import Seihou.Dhall.Config (evalConfigFileIfExists)
import Seihou.Effect.ConfigReader (ConfigReader (..))
import Seihou.Prelude
import System.Directory (XdgDirectory (..), getCurrentDirectory, getXdgDirectory)

-- | Real IO interpreter for the ConfigReader effect.
--
-- Resolves config file paths using standard locations:
--
--   * Global: @~\/.config\/seihou\/config.dhall@
--   * Local: @.seihou\/config.dhall@ (relative to current directory)
--   * Namespace: @~\/.config\/seihou\/namespaces\/\<ns\>\/config.dhall@
--   * Context: @~\/.config\/seihou\/contexts\/\<ctx\>\/config.dhall@
--
-- Missing files are silently treated as empty maps. Invalid Dhall
-- is reported as @Left (ConfigParseError ...)@.
runConfigReader :: (IOE :> es) => Eff (ConfigReader : es) a -> Eff es a
runConfigReader = interpret $ \_ -> \case
  ReadGlobalConfig -> liftIO $ do
    base <- getXdgDirectory XdgConfig "seihou"
    let path = base </> "config.dhall"
    first (ConfigParseError path) <$> evalConfigFileIfExists path
  ReadLocalConfig -> liftIO $ do
    cwd <- getCurrentDirectory
    let path = cwd </> ".seihou" </> "config.dhall"
    first (ConfigParseError path) <$> evalConfigFileIfExists path
  ReadNamespaceConfig ns -> liftIO $ loadNamespacedConfig "namespaces" ns "namespace must not contain '..' or '/'"
  ReadContextConfig ctx -> liftIO $ loadNamespacedConfig "contexts" ctx "context name must not contain '..' or '/'"

-- | Load config from a named subdirectory under XDG config, with path-traversal validation.
loadNamespacedConfig :: String -> Text -> Text -> IO (Either ConfigError (Map Text Text))
loadNamespacedConfig subdir name errMsg
  | T.null name = pure (Right Map.empty)
  | hasPathTraversal name = pure (Left (InvalidNamespace name errMsg))
  | otherwise = do
      base <- getXdgDirectory XdgConfig "seihou"
      let path = base </> subdir </> T.unpack name </> "config.dhall"
      first (ConfigParseError path) <$> evalConfigFileIfExists path
  where
    hasPathTraversal t = ".." `T.isInfixOf` t || "/" `T.isInfixOf` t
