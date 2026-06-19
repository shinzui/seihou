module Seihou.CLI.NewPrompt
  ( handleNewPrompt,
  )
where

import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.Commands (NewPromptOpts (..))
import Seihou.CLI.SchemaVersion (schemaHash, schemaUrl)
import Seihou.CLI.Shared (logIO)
import Seihou.Core.Module (isValidModuleName)
import Seihou.Core.Scaffold (exampleAgentPromptMarkdown, promptDhall)
import Seihou.Core.Types (LogLevel (..))
import Seihou.Effect.Logger (logError)
import Seihou.Prelude
import System.Directory (createDirectoryIfMissing, doesDirectoryExist)
import System.Exit (exitFailure)

handleNewPrompt :: NewPromptOpts -> IO ()
handleNewPrompt nopts = do
  let name = nopts.newPromptName

  if not (isValidModuleName name)
    then do
      logIO LogNormal $ do
        logError $ "invalid prompt name '" <> name <> "'."
        logError "Prompt names must match [a-z][a-z0-9-]*."
      exitFailure
    else pure ()

  let outputDir = case nopts.newPromptPath of
        Just p -> p
        Nothing -> T.unpack name

  exists <- doesDirectoryExist outputDir
  if exists
    then do
      logIO LogNormal (logError $ "directory '" <> T.pack outputDir <> "' already exists.")
      exitFailure
    else pure ()

  createDirectoryIfMissing True (outputDir </> "files")

  let dhallContent = promptDhall name schemaUrl schemaHash
  writeFile (outputDir </> "prompt.dhall") (T.unpack dhallContent)
  TIO.putStrLn $ "Created " <> T.pack (outputDir </> "prompt.dhall")

  writeFile (outputDir </> "prompt.md") (T.unpack exampleAgentPromptMarkdown)
  TIO.putStrLn $ "Created " <> T.pack (outputDir </> "prompt.md")

  TIO.putStrLn $ "Created " <> T.pack (outputDir </> "files/")
  TIO.putStrLn $ "Prompt '" <> name <> "' created at " <> T.pack outputDir <> "/"
