module Seihou.CLI.Install
  ( handleInstall,
  )
where

import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.Commands (InstallOpts (..))
import Seihou.CLI.Shared (logIO)
import Seihou.Core.Module (validateModule)
import Seihou.Core.Types
import Seihou.Dhall.Eval (evalModuleFromFile)
import Seihou.Effect.Logger (logError)
import System.Directory
  ( XdgDirectory (..),
    copyFile,
    createDirectoryIfMissing,
    doesDirectoryExist,
    getXdgDirectory,
    listDirectory,
  )
import System.Exit (ExitCode (..), exitFailure)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (readProcessWithExitCode)

handleInstall :: InstallOpts -> IO ()
handleInstall iopts = do
  let source = installSource iopts
      name = case installName iopts of
        Just n -> T.unpack n
        Nothing -> parseModuleName source

  -- Check if the module is already installed
  xdgConfig <- getXdgDirectory XdgConfig "seihou"
  let installDir = xdgConfig </> "installed" </> name

  exists <- doesDirectoryExist installDir
  if exists
    then do
      logIO LogNormal $ do
        logError $ "module '" <> T.pack name <> "' is already installed at " <> T.pack installDir
        logError "Remove the existing installation first to reinstall."
      exitFailure
    else pure ()

  -- Clone into a temporary directory
  withSystemTempDirectory "seihou-install" $ \tmpDir -> do
    let cloneDir = tmpDir </> name
    TIO.putStrLn $ "Cloning " <> source <> " ..."
    (exitCode, _stdout, stderr) <- readProcessWithExitCode "git" ["clone", "--depth", "1", T.unpack source, cloneDir] ""
    case exitCode of
      ExitFailure _ -> do
        logIO LogNormal $ do
          logError $ "git clone failed for '" <> source <> "'."
          logError $ "  " <> T.pack stderr
        exitFailure
      ExitSuccess -> pure ()

    -- Validate the cloned module
    let dhallFile = cloneDir </> "module.dhall"
    decoded <- evalModuleFromFile dhallFile
    modul <- case decoded of
      Left err -> do
        logIO LogNormal $ do
          logError "cloned repository is not a valid seihou module."
          logError $ "  " <> T.pack (show err)
        exitFailure
      Right m -> pure m

    result <- validateModule cloneDir modul
    case result of
      Left (ValidationError _ errors) -> do
        logIO LogNormal $ do
          logError "cloned module has validation errors:"
          mapM_ (\e -> logError $ "  - " <> e) errors
        exitFailure
      Left err -> do
        logIO LogNormal (logError $ T.pack (show err))
        exitFailure
      Right _ -> pure ()

    -- Copy the module to the install directory
    createDirectoryIfMissing True installDir
    copyDirectoryRecursive cloneDir installDir
    TIO.putStrLn $ "Installed module '" <> unModuleName (moduleName modul) <> "' to " <> T.pack installDir

-- | Parse a module name from a git URL by extracting the last path segment
-- and stripping a trailing .git extension.
parseModuleName :: Text -> String
parseModuleName url =
  let stripped = T.stripSuffix ".git" url
      base = maybe url id stripped
      segments = T.splitOn "/" base
      lastSeg = if null segments then base else last segments
   in T.unpack lastSeg

-- | Recursively copy a directory tree.
copyDirectoryRecursive :: FilePath -> FilePath -> IO ()
copyDirectoryRecursive src dst = do
  entries <- listDirectory src
  mapM_ (copyEntry src dst) entries
  where
    copyEntry s d entry = do
      let srcPath = s </> entry
          dstPath = d </> entry
      isDir <- doesDirectoryExist srcPath
      if isDir
        then do
          createDirectoryIfMissing True dstPath
          copyDirectoryRecursive srcPath dstPath
        else copyFile srcPath dstPath
