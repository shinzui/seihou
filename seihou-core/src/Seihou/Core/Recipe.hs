module Seihou.Core.Recipe
  ( validateRecipe,
  )
where

import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Seihou.Core.Module (isValidModuleName)
import Seihou.Core.Types

-- | Validate a 'Recipe' against recipe-specific rules.
-- Returns 'Right' with the recipe if all rules pass, or 'Left' with a
-- list of all violations.
--
-- Validation rules:
--   1. Name matches @[a-z][a-z0-9-]*@
--   2. At least one module listed
--   3. No duplicate module names in the list
--   4. All variable binding names in module entries match @[a-z][a-z0-9.-]*@
validateRecipe :: Recipe -> Either [Text] Recipe
validateRecipe recipe =
  let errs =
        checkRecipeNameFormat recipe
          <> checkNonEmptyModules recipe
          <> checkNoDuplicateModules recipe
          <> checkVarBindingNames recipe
   in if null errs
        then Right recipe
        else Left errs

-- Rule 1: Recipe name must match [a-z][a-z0-9-]*
checkRecipeNameFormat :: Recipe -> [Text]
checkRecipeNameFormat recipe =
  let n = recipe.name.unRecipeName
   in if T.null n || not (isValidModuleName n)
        then ["recipe name must match [a-z][a-z0-9-]*, got: " <> n]
        else []

-- Rule 2: At least one module must be listed
checkNonEmptyModules :: Recipe -> [Text]
checkNonEmptyModules recipe
  | null recipe.modules = ["recipe must list at least one module"]
  | otherwise = []

-- Rule 3: No duplicate module names
checkNoDuplicateModules :: Recipe -> [Text]
checkNoDuplicateModules recipe =
  let names = map (.depModule.unModuleName) recipe.modules
   in map (\n -> "duplicate module in recipe: " <> n) (findDupes Set.empty Set.empty names)

findDupes :: Set.Set Text -> Set.Set Text -> [Text] -> [Text]
findDupes _ _ [] = []
findDupes seen reported (x : xs)
  | Set.member x seen && not (Set.member x reported) = x : findDupes seen (Set.insert x reported) xs
  | otherwise = findDupes (Set.insert x seen) reported xs

-- Rule 4: Variable binding names must match [a-z][a-z0-9.-]*
checkVarBindingNames :: Recipe -> [Text]
checkVarBindingNames recipe =
  concatMap checkDep recipe.modules
  where
    checkDep dep =
      concatMap
        ( \(VarName vn) ->
            if isValidVarBindingName vn
              then []
              else ["invalid var binding name '" <> vn <> "' in module '" <> dep.depModule.unModuleName <> "'"]
        )
        (Map.keys dep.depVars)

    isValidVarBindingName :: Text -> Bool
    isValidVarBindingName t = case T.uncons t of
      Nothing -> False
      Just (c, rest) ->
        (c >= 'a' && c <= 'z')
          && T.all (\ch -> (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') || ch == '-' || ch == '.') rest
