module Seihou.CLI.Install
  ( handleInstall,
  )
where

import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.Commands (InstallOpts (..))
import Seihou.Core.Module (validateModule)
import Seihou.Core.Types
import Seihou.Dhall.Eval (evalModuleFromFile)
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
      TIO.putStrLn $ "Error: module '" <> T.pack name <> "' is already installed at " <> T.pack installDir
      TIO.putStrLn "Remove the existing installation first to reinstall."
      exitFailure
    else pure ()

  -- Clone into a temporary directory
  withSystemTempDirectory "seihou-install" $ \tmpDir -> do
    let cloneDir = tmpDir </> name
    TIO.putStrLn $ "Cloning " <> source <> " ..."
    (exitCode, _stdout, stderr) <- readProcessWithExitCode "git" ["clone", "--depth", "1", T.unpack source, cloneDir] ""
    case exitCode of
      ExitFailure _ -> do
        TIO.putStrLn $ "Error: git clone failed for '" <> source <> "'."
        TIO.putStrLn $ "  " <> T.pack stderr
        exitFailure
      ExitSuccess -> pure ()

    -- Validate the cloned module
    let dhallFile = cloneDir </> "module.dhall"
    decoded <- evalModuleFromFile dhallFile
    modul <- case decoded of
      Left err -> do
        TIO.putStrLn "Error: cloned repository is not a valid seihou module."
        TIO.putStrLn $ "  " <> T.pack (show err)
        exitFailure
      Right m -> pure m

    result <- validateModule cloneDir modul
    case result of
      Left (ValidationError _ errors) -> do
        TIO.putStrLn "Error: cloned module has validation errors:"
        mapM_ (\e -> TIO.putStrLn $ "  - " <> e) errors
        exitFailure
      Left err -> do
        TIO.putStrLn $ "Error: " <> T.pack (show err)
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
