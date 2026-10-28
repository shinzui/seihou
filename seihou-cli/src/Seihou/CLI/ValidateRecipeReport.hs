module Seihou.CLI.ValidateRecipeReport (recipeLoadErrorText) where

import Data.Text (Text)
import Data.Text qualified as T
import Seihou.Core.Types (ModuleLoadError (..), ModuleName (..))

-- Keep the evaluator's useful parser/type diagnostic without exposing the
-- internal error constructor or mistaking the recipe for a module.
recipeLoadErrorText :: ModuleLoadError -> Text
recipeLoadErrorText (DhallEvalError _ reason) = "Cannot evaluate recipe.dhall: " <> reason
recipeLoadErrorText (DhallDecodeError _ reason) = "Cannot decode recipe.dhall: " <> reason
recipeLoadErrorText (ValidationError _ problems) = T.intercalate "; " problems
recipeLoadErrorText (ModuleNotFound (ModuleName name) searched) =
  "Module '" <> name <> "' not found; searched: " <> T.intercalate ", " (map T.pack searched)
recipeLoadErrorText (CircularDependency names) =
  "Circular dependency: " <> T.intercalate " -> " [name | ModuleName name <- names]
recipeLoadErrorText (MissingSourceFile (ModuleName name) path) =
  "Module '" <> name <> "' is missing source file " <> T.pack path
recipeLoadErrorText (RegistryEvalError source reason) =
  "Cannot evaluate registry '" <> source <> "': " <> reason
