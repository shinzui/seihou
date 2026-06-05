module Seihou.Composition.Recipe
  ( expandRecipe,
  )
where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Seihou.Core.Recipe (validateRecipe)
import Seihou.Core.Types

type ExpandedRecipe = (ModuleName, [ModuleName], Map VarName Text, [VarDecl], [Prompt])

-- | Expand a 'Recipe' into the inputs that the existing composition pipeline
-- expects: a primary module name, additional module names, variable overrides,
-- recipe-level variable declarations, and recipe-level prompts.
--
-- The first module in the recipe's list becomes the primary module (used for
-- config namespace derivation). All remaining modules become additional modules.
-- Variable overrides are collected from each module entry's @depVars@ bindings.
expandRecipe :: Recipe -> Either [Text] ExpandedRecipe
expandRecipe recipe = do
  validated <- validateRecipe recipe
  case validated.modules of
    [] -> Left ["recipe must list at least one module"]
    primary : additional ->
      let primaryName = primary.depModule
          additionalNames = map (.depModule) additional
          overrides = Map.unions (map (.depVars) validated.modules)
       in Right (primaryName, additionalNames, overrides, validated.vars, validated.prompts)
