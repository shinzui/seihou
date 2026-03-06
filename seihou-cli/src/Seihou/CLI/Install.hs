module Seihou.CLI.Install
  ( handleInstall,
  )
where

import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.Commands (InstallOpts (..))
import Seihou.CLI.Shared (logIO)
import Seihou.Core.Install (parseModuleName)
import Seihou.Core.Module (validateModule)
import Seihou.Core.Types
import Seihou.Dhall.Eval (evalModuleFromFile)
import Seihou.Effect.Logger (logError, logWarn)
import Seihou.Prelude
import System.Directory
  ( XdgDirectory (..),
    copyFile,
    createDirectoryIfMissing,
    doesDirectoryExist,
    getXdgDirectory,
    listDirectory,
    removeDirectoryRecursive,
  )
import System.Exit (ExitCode (..), exitFailure)
import System.IO.Temp (withSystemTempDirectory)
import System.Process (readProcessWithExitCode)

handleInstall :: InstallOpts -> IO ()
handleInstall iopts = do
  let source = iopts.installSource
      name = case iopts.installName of
        Just n -> T.unpack n
        Nothing -> parseModuleName source

  -- Check if the module is already installed
  xdgConfig <- getXdgDirectory XdgConfig "seihou"
  let installDir = xdgConfig </> "installed" </> name

  TIO.putStrLn $ "Installing module from " <> source <> "..."

  exists <- doesDirectoryExist installDir
  if exists
    then do
      logIO LogNormal (logWarn $ "overwriting existing installation of '" <> T.pack name <> "'")
      removeDirectoryRecursive installDir
    else pure ()

  -- Clone into a temporary directory
  withSystemTempDirectory "seihou-install" $ \tmpDir -> do
    let cloneDir = tmpDir </> name
    (exitCode, _stdout, stderr) <- readProcessWithExitCode "git" ["clone", "--depth", "1", T.unpack source, cloneDir] ""
    case exitCode of
      ExitFailure _ -> do
        logIO LogNormal $ do
          logError $ "git clone failed for '" <> source <> "'."
          logError $ "  " <> T.pack stderr
        exitFailure
      ExitSuccess -> pure ()
    TIO.putStrLn "  Cloned repository"

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
    TIO.putStrLn "  Validated module definition"

    -- Copy the module to the install directory (excluding .git)
    createDirectoryIfMissing True installDir
    copyDirectoryRecursive cloneDir installDir
    TIO.putStrLn $ "  Installed as: " <> T.pack name

  TIO.putStrLn ""
  TIO.putStrLn $ "Module available as: " <> T.pack name

-- | Recursively copy a directory tree, excluding the @.git@ directory.
copyDirectoryRecursive :: FilePath -> FilePath -> IO ()
copyDirectoryRecursive src dst = do
  entries <- listDirectory src
  mapM_ (copyEntry src dst) entries
  where
    copyEntry s d entry
      | entry == ".git" = pure ()
      | otherwise = do
          let srcPath = s </> entry
              dstPath = d </> entry
          isDir <- doesDirectoryExist srcPath
          if isDir
            then do
              createDirectoryIfMissing True dstPath
              copyDirectoryRecursive srcPath dstPath
            else copyFile srcPath dstPath
