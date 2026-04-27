module Seihou.CLI.NewRecipe
  ( handleNewRecipe,
  )
where

import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.Commands (NewRecipeOpts (..))
import Seihou.CLI.Shared (logIO)
import Seihou.Core.Types (LogLevel (..))
import Seihou.Effect.Logger (logError)
import Seihou.Prelude
import System.Directory (createDirectoryIfMissing, doesDirectoryExist)
import System.Exit (exitFailure)

handleNewRecipe :: NewRecipeOpts -> IO ()
handleNewRecipe ropts = do
  let name = ropts.newRecipeName

  -- Validate recipe name format
  if not (isValidRecipeName name)
    then do
      logIO LogNormal $ do
        logError $ "invalid recipe name '" <> name <> "'."
        logError "Recipe names must match [a-z][a-z0-9-]*."
      exitFailure
    else pure ()

  -- Determine output directory
  let outputDir = case ropts.newRecipePath of
        Just p -> p
        Nothing -> T.unpack name

  -- Check that the target directory does not already exist
  exists <- doesDirectoryExist outputDir
  if exists
    then do
      logIO LogNormal (logError $ "directory '" <> T.pack outputDir <> "' already exists.")
      exitFailure
    else pure ()

  -- Create directory
  createDirectoryIfMissing True outputDir

  -- Write recipe.dhall
  let dhallContent = recipeDhall name ropts.newRecipeModules
  writeFile (outputDir </> "recipe.dhall") (T.unpack dhallContent)
  TIO.putStrLn $ "Created " <> T.pack (outputDir </> "recipe.dhall")

  TIO.putStrLn $ "Recipe '" <> name <> "' created at " <> T.pack outputDir <> "/"

-- | Check if a recipe name matches [a-z][a-z0-9-]*
isValidRecipeName :: Text -> Bool
isValidRecipeName t = case T.uncons t of
  Nothing -> False
  Just (c, rest) ->
    (c >= 'a' && c <= 'z')
      && T.all (\ch -> (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') || ch == '-') rest

-- | Generate recipe.dhall content.
recipeDhall :: Text -> [Text] -> Text
recipeDhall name mods =
  "{ name = \""
    <> name
    <> "\"\n"
    <> ", version = Some \"0.1.0\"\n"
    <> ", description = Some \"\"\n"
    <> ", modules =\n"
    <> modulesSection mods
    <> ", vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }\n"
    <> ", prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }\n"
    <> "}\n"

modulesSection :: [Text] -> Text
modulesSection [] =
  "  [] : List { module : Text, vars : List { name : Text, value : Text } }\n"
modulesSection mods =
  "  [ "
    <> T.intercalate "\n  , " (map formatModEntry mods)
    <> "\n  ]\n"
  where
    formatModEntry m =
      "{ module = \""
        <> m
        <> "\", vars = [] : List { name : Text, value : Text } }"
