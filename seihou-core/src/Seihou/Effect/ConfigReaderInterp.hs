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
--
-- Missing files are silently treated as empty maps. Invalid Dhall
-- is reported as @Left (ConfigParseError ...)@.
runConfigReader :: (IOE :> es) => Eff (ConfigReader : es) a -> Eff es a
runConfigReader = interpret $ \_ -> \case
  ReadGlobalConfig -> liftIO $ do
    base <- getXdgDirectory XdgConfig "seihou"
    let path = base </> "config.dhall"
    result <- evalConfigFileIfExists path
    case result of
      Left err -> pure (Left (ConfigParseError path err))
      Right m -> pure (Right m)
  ReadLocalConfig -> liftIO $ do
    cwd <- getCurrentDirectory
    let path = cwd </> ".seihou" </> "config.dhall"
    result <- evalConfigFileIfExists path
    case result of
      Left err -> pure (Left (ConfigParseError path err))
      Right m -> pure (Right m)
  ReadNamespaceConfig ns -> liftIO $ do
    if T.null ns
      then pure (Right Map.empty)
      else
        if ".." `T.isInfixOf` ns || "/" `T.isInfixOf` ns
          then pure (Left (InvalidNamespace ns "namespace must not contain '..' or '/'"))
          else do
            base <- getXdgDirectory XdgConfig "seihou"
            let path = base </> "namespaces" </> T.unpack ns </> "config.dhall"
            result <- evalConfigFileIfExists path
            case result of
              Left err -> pure (Left (ConfigParseError path err))
              Right m -> pure (Right m)
