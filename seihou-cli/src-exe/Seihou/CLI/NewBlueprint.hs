module Seihou.CLI.NewBlueprint
  ( handleNewBlueprint,
  )
where

import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.Commands (NewBlueprintOpts (..))
import Seihou.CLI.SchemaVersion (schemaHash, schemaUrl)
import Seihou.CLI.Shared (logIO)
import Seihou.Core.Scaffold (blueprintDhall, examplePromptMarkdown)
import Seihou.Core.Types (LogLevel (..))
import Seihou.Effect.Logger (logError)
import Seihou.Prelude
import System.Directory (createDirectoryIfMissing, doesDirectoryExist)
import System.Exit (exitFailure)

handleNewBlueprint :: NewBlueprintOpts -> IO ()
handleNewBlueprint nopts = do
  let name = nopts.newBlueprintName

  -- Validate blueprint name format
  if not (isValidBlueprintName name)
    then do
      logIO LogNormal $ do
        logError $ "invalid blueprint name '" <> name <> "'."
        logError "Blueprint names must match [a-z][a-z0-9-]*."
      exitFailure
    else pure ()

  -- Determine output directory
  let outputDir = case nopts.newBlueprintPath of
        Just p -> p
        Nothing -> T.unpack name

  -- Refuse to overwrite an existing directory
  exists <- doesDirectoryExist outputDir
  if exists
    then do
      logIO LogNormal (logError $ "directory '" <> T.pack outputDir <> "' already exists.")
      exitFailure
    else pure ()

  -- Create directory structure (output dir + empty files/ subdir)
  createDirectoryIfMissing True (outputDir </> "files")

  -- Write blueprint.dhall
  let dhallContent = blueprintDhall name schemaUrl schemaHash
  writeFile (outputDir </> "blueprint.dhall") (T.unpack dhallContent)
  TIO.putStrLn $ "Created " <> T.pack (outputDir </> "blueprint.dhall")

  -- Write prompt.md
  writeFile (outputDir </> "prompt.md") (T.unpack examplePromptMarkdown)
  TIO.putStrLn $ "Created " <> T.pack (outputDir </> "prompt.md")

  -- Announce the empty files/ subdir so the user knows it is intentional
  TIO.putStrLn $ "Created " <> T.pack (outputDir </> "files/")

  TIO.putStrLn $ "Blueprint '" <> name <> "' created at " <> T.pack outputDir <> "/"

-- | Check if a blueprint name matches [a-z][a-z0-9-]*. Mirrors
-- 'Seihou.CLI.NewModule.isValidModuleName' so the rule stays a single
-- source of truth across all three runnable kinds.
isValidBlueprintName :: Text -> Bool
isValidBlueprintName t = case T.uncons t of
  Nothing -> False
  Just (c, rest) ->
    (c >= 'a' && c <= 'z')
      && T.all (\ch -> (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') || ch == '-') rest
