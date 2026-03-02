module Seihou.Effect.ConfigReaderInterp
  ( runConfigReader,
  )
where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Effectful
import Effectful.Dispatch.Dynamic
import Seihou.Dhall.Config (evalConfigFileIfExists)
import Seihou.Effect.ConfigReader (ConfigReader (..))
import System.Directory (XdgDirectory (..), getCurrentDirectory, getXdgDirectory)
import System.FilePath ((</>))

-- | Real IO interpreter for the ConfigReader effect.
--
-- Resolves config file paths using standard locations:
--
--   * Global: @~\/.config\/seihou\/config.dhall@
--   * Local: @.seihou\/config.dhall@ (relative to current directory)
--   * Namespace: @~\/.config\/seihou\/namespaces\/\<ns\>\/config.dhall@
--
-- Missing files are silently treated as empty maps. Invalid Dhall
-- is reported via 'error' (propagated as an IO exception).
runConfigReader :: (IOE :> es) => Eff (ConfigReader : es) a -> Eff es a
runConfigReader = interpret $ \_ -> \case
  ReadGlobalConfig -> liftIO $ do
    base <- getXdgDirectory XdgConfig "seihou"
    let path = base </> "config.dhall"
    result <- evalConfigFileIfExists path
    case result of
      Left err -> error (T.unpack err)
      Right m -> pure m
  ReadLocalConfig -> liftIO $ do
    cwd <- getCurrentDirectory
    let path = cwd </> ".seihou" </> "config.dhall"
    result <- evalConfigFileIfExists path
    case result of
      Left err -> error (T.unpack err)
      Right m -> pure m
  ReadNamespaceConfig ns -> liftIO $ do
    if T.null ns
      then pure Map.empty
      else do
        base <- getXdgDirectory XdgConfig "seihou"
        let path = base </> "namespaces" </> T.unpack ns </> "config.dhall"
        result <- evalConfigFileIfExists path
        case result of
          Left err -> error (T.unpack err)
          Right m -> pure m
