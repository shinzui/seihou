module Seihou.CLI.Extension
  ( ExtensionRunOpts (..),
    ExtensionRunError (..),
    extensionExecutableName,
    runExtension,
    handleExtensionRun,
  )
where

import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.Prelude
import System.Directory (findExecutable)
import System.Exit (ExitCode (..), exitWith)
import System.IO (hPutStrLn, stderr)
import System.Process (rawSystem)

data ExtensionRunOpts = ExtensionRunOpts
  { extensionName :: Text,
    extensionArgs :: [String]
  }
  deriving stock (Eq, Show)

data ExtensionRunError
  = ExtensionNotFound Text String
  | ExtensionExited Text ExitCode
  deriving stock (Eq, Show)

extensionExecutableName :: Text -> String
extensionExecutableName name =
  "seihou-" <> T.unpack name <> "-extension"

runExtension :: ExtensionRunOpts -> IO (Either ExtensionRunError ())
runExtension opts = do
  let exeName = extensionExecutableName opts.extensionName
  found <- findExecutable exeName
  case found of
    Nothing ->
      pure (Left (ExtensionNotFound opts.extensionName exeName))
    Just exePath -> do
      code <- rawSystem exePath opts.extensionArgs
      pure $ case code of
        ExitSuccess -> Right ()
        failure -> Left (ExtensionExited opts.extensionName failure)

handleExtensionRun :: ExtensionRunOpts -> IO ()
handleExtensionRun opts = do
  result <- runExtension opts
  case result of
    Right () ->
      pure ()
    Left (ExtensionNotFound _ exeName) -> do
      hPutStrLn stderr ("error: extension executable not found: " <> exeName)
      exitWith (ExitFailure 127)
    Left (ExtensionExited name code) -> do
      TIO.hPutStrLn stderr ("error: extension '" <> name <> "' exited with " <> T.pack (show code))
      exitWith code
