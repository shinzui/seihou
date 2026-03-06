module Seihou.CLI.NewModule
  ( handleNewModule,
  )
where

import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.Commands (NewModuleOpts (..))
import Seihou.CLI.Shared (logIO)
import Seihou.Core.Scaffold (moduleDhall, readmeTemplate)
import Seihou.Core.Types (LogLevel (..))
import Seihou.Effect.Logger (logError)
import Seihou.Prelude
import System.Directory (createDirectoryIfMissing, doesDirectoryExist)
import System.Exit (exitFailure)

handleNewModule :: NewModuleOpts -> IO ()
handleNewModule nopts = do
  let name = newModuleName nopts

  -- Validate module name format
  if not (isValidModuleName name)
    then do
      logIO LogNormal $ do
        logError $ "invalid module name '" <> name <> "'."
        logError "Module names must match [a-z][a-z0-9-]*."
      exitFailure
    else pure ()

  -- Determine output directory
  let outputDir = case newModulePath nopts of
        Just p -> p
        Nothing -> T.unpack name

  -- Check that the target directory does not already exist
  exists <- doesDirectoryExist outputDir
  if exists
    then do
      logIO LogNormal (logError $ "directory '" <> T.pack outputDir <> "' already exists.")
      exitFailure
    else pure ()

  -- Create directory structure
  createDirectoryIfMissing True (outputDir </> "files")

  -- Write module.dhall
  let dhallContent = moduleDhall name
  writeFile (outputDir </> "module.dhall") (T.unpack dhallContent)
  TIO.putStrLn $ "Created " <> T.pack (outputDir </> "module.dhall")

  -- Write files/README.md.tpl
  let templateContent = readmeTemplate
  writeFile (outputDir </> "files" </> "README.md.tpl") (T.unpack templateContent)
  TIO.putStrLn $ "Created " <> T.pack (outputDir </> "files" </> "README.md.tpl")

  TIO.putStrLn $ "Module '" <> name <> "' created at " <> T.pack outputDir <> "/"

-- | Check if a module name matches [a-z][a-z0-9-]*
isValidModuleName :: Text -> Bool
isValidModuleName t = case T.uncons t of
  Nothing -> False
  Just (c, rest) ->
    (c >= 'a' && c <= 'z')
      && T.all (\ch -> (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') || ch == '-') rest
