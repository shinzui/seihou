module Seihou.CLI.ValidateRecipe (handleValidateRecipe) where

import Control.Exception (IOException, displayException, try)
import Control.Lens ((^.))
import Data.Generics.Labels ()
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.Commands (ValidateRecipeOpts (..))
import Seihou.CLI.ValidateRecipeReport (recipeLoadErrorText)
import Seihou.Core.Recipe (validateRecipe)
import Seihou.Dhall.Eval (evalRecipeFromFile)
import System.Directory (doesFileExist, getCurrentDirectory)
import System.Exit (ExitCode (..), exitWith)
import System.FilePath ((</>))

handleValidateRecipe :: ValidateRecipeOpts -> IO ()
handleValidateRecipe opts = do
  dir <- maybe getCurrentDirectory pure (opts ^. #path)
  let descriptor = dir </> "recipe.dhall"
      invalid :: [Text] -> Int -> IO a
      invalid errors code = do
        TIO.putStrLn $ "Recipe is invalid: " <> T.pack descriptor
        mapM_ (TIO.putStrLn . ("  " <>)) errors
        exitWith (ExitFailure code)
  checked <- try (doesFileExist descriptor)
  exists <- case checked of
    Left (err :: IOException) -> invalid ["Cannot inspect recipe.dhall: " <> T.pack (displayException err)] 1
    Right value -> pure value
  if not exists
    then invalid ["recipe.dhall not found. Choose a directory containing recipe.dhall."] 4
    else do
      decoded <- evalRecipeFromFile descriptor
      case decoded of
        Left err -> invalid [recipeLoadErrorText err] 1
        Right recipe -> case validateRecipe recipe of
          Left errors -> invalid errors 1
          Right valid -> TIO.putStrLn $ "Recipe '" <> valid ^. #name . #unRecipeName <> "' is valid."
