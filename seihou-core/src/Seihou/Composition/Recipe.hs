module Seihou.Composition.Recipe
  ( expandRecipe,
  )
where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Seihou.Core.Types

-- | Expand a 'Recipe' into the inputs that the existing composition pipeline
-- expects: a primary module name, additional module names, variable overrides,
-- recipe-level variable declarations, and recipe-level prompts.
--
-- The first module in the recipe's list becomes the primary module (used for
-- config namespace derivation). All remaining modules become additional modules.
-- Variable overrides are collected from each module entry's @depVars@ bindings.
expandRecipe :: Recipe -> (ModuleName, [ModuleName], Map VarName Text, [VarDecl], [Prompt])
expandRecipe recipe =
  let deps = recipe.modules
      primaryName = (.depModule) (head deps)
      additionalNames = map (.depModule) (tail deps)
      overrides = Map.unions (map (.depVars) deps)
   in (primaryName, additionalNames, overrides, recipe.vars, recipe.prompts)
