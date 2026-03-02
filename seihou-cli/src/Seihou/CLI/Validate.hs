module Seihou.CLI.Validate
  ( handleValidateModule,
  )
where

import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.Commands (ValidateOpts (..))
import Seihou.Core.Module (validateModule)
import Seihou.Core.Types
import Seihou.Dhall.Eval (evalModuleFromFile)
import System.Directory (doesFileExist, getCurrentDirectory)
import System.Exit (exitFailure)
import System.FilePath ((</>))

handleValidateModule :: ValidateOpts -> IO ()
handleValidateModule vopts = do
  -- Determine module path
  moduleDir <- case validatePath vopts of
    Just p -> pure p
    Nothing -> getCurrentDirectory

  let dhallFile = moduleDir </> "module.dhall"

  -- Check that module.dhall exists
  exists <- doesFileExist dhallFile
  if not exists
    then do
      TIO.putStrLn $ "Error: " <> T.pack dhallFile <> " not found."
      exitFailure
    else pure ()

  -- Evaluate Dhall
  decoded <- evalModuleFromFile dhallFile
  modul <- case decoded of
    Left (DhallEvalError _ msg) -> do
      TIO.putStrLn $ "Dhall evaluation error: " <> msg
      exitFailure
    Left (DhallDecodeError _ msg) -> do
      TIO.putStrLn $ "Dhall decode error: " <> msg
      exitFailure
    Left err -> do
      TIO.putStrLn $ "Error: " <> T.pack (show err)
      exitFailure
    Right m -> pure m

  -- Validate
  result <- validateModule moduleDir modul
  case result of
    Right _ ->
      TIO.putStrLn $ "Module '" <> unModuleName (moduleName modul) <> "' is valid."
    Left (ValidationError _ errors) -> do
      TIO.putStrLn $ T.pack (show (length errors)) <> " error(s) found. Module is invalid."
      mapM_ (\e -> TIO.putStrLn $ "  - " <> e) errors
      exitFailure
    Left err -> do
      TIO.putStrLn $ "Error: " <> T.pack (show err)
      exitFailure
