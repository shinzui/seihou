module Seihou.Effect.ConfigWriterInterp
  ( runConfigWriter,
  )
where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.Core.Types (ConfigError (..), ConfigScope (..))
import Seihou.Dhall.Config (evalConfigFileIfExists, serializeConfig)
import Seihou.Effect.ConfigWriter (ConfigWriter (..))
import Seihou.Prelude
import System.Directory
  ( XdgDirectory (..),
    createDirectoryIfMissing,
    getCurrentDirectory,
    getXdgDirectory,
  )
import System.FilePath (takeDirectory)

-- | IO interpreter for the ConfigWriter effect.
--
-- Performs read-modify-write on Dhall config files. Creates parent
-- directories as needed. Path resolution matches 'ConfigReaderInterp':
--
--   * 'ScopeLocal': @.seihou\/config.dhall@ relative to cwd
--   * 'ScopeNamespace' ns: @~\/.config\/seihou\/namespaces\/\<ns\>\/config.dhall@
--   * 'ScopeGlobal': @~\/.config\/seihou\/config.dhall@
runConfigWriter :: (IOE :> es) => Eff (ConfigWriter : es) a -> Eff es a
runConfigWriter = interpret $ \_ -> \case
  WriteConfigValue scope key val -> liftIO $ do
    path <- resolvePath scope
    m <- readOrEmpty path
    let updated = Map.insert key val m
    ensureParent path
    TIO.writeFile path (serializeConfig updated)
  DeleteConfigValue scope key -> liftIO $ do
    path <- resolvePath scope
    m <- readOrEmpty path
    let updated = Map.delete key m
    ensureParent path
    TIO.writeFile path (serializeConfig updated)
  ListConfigValues scope -> liftIO $ do
    path <- resolvePath scope
    result <- evalConfigFileIfExists path
    case result of
      Left err -> pure (Left (ConfigParseError path err))
      Right m -> pure (Right m)

-- | Resolve the config file path for a given scope.
resolvePath :: ConfigScope -> IO FilePath
resolvePath ScopeLocal = do
  cwd <- getCurrentDirectory
  pure (cwd </> ".seihou" </> "config.dhall")
resolvePath (ScopeNamespace ns) = do
  base <- getXdgDirectory XdgConfig "seihou"
  pure (base </> "namespaces" </> T.unpack ns </> "config.dhall")
resolvePath ScopeGlobal = do
  base <- getXdgDirectory XdgConfig "seihou"
  pure (base </> "config.dhall")

-- | Read an existing config file, returning an empty map if the file
-- does not exist. Throws on Dhall parse errors.
readOrEmpty :: FilePath -> IO (Map.Map T.Text T.Text)
readOrEmpty path = do
  result <- evalConfigFileIfExists path
  case result of
    Left err -> fail (T.unpack err)
    Right m -> pure m

-- | Create parent directories for a file path if they don't exist.
ensureParent :: FilePath -> IO ()
ensureParent path = createDirectoryIfMissing True (takeDirectory path)
