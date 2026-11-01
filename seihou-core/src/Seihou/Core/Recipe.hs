module Seihou.Core.Recipe
  ( validateRecipe,
    validateRecipeVersion,
  )
where

import Control.Lens ((^.))
import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Maybe (isNothing)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Seihou.Core.Expr (exprRefs)
import Seihou.Core.Module (isValidModuleName)
import Seihou.Core.Types
import Seihou.Core.Variable (isValidVarBindingName, validateVarPattern)
import Seihou.Core.Version (Version, parseVersion)

-- | Validate a 'Recipe' against recipe-specific rules.
-- Returns 'Right' with the recipe if all rules pass, or 'Left' with a
-- list of all violations.
--
-- Validation rules:
--   1. Name matches @[a-z][a-z0-9-]*@
--   2. A root lists at least one module; a derived recipe may add none
--   3. No duplicate module names in the list
--   4. All variable binding names in module entries match @[a-z][A-Za-z0-9.-]*@
--   5. Recipe variable declarations are unique
--   6. Flat prompt references are local; inherited references are checked on expansion
validateRecipe :: Recipe -> Either [Text] Recipe
validateRecipe recipe =
  let errs =
        checkRecipeNameFormat recipe
          <> checkNonEmptyModules recipe
          <> checkNoDuplicateModules recipe
          <> checkVarBindingNames recipe
          <> checkRecipeVarsAndPrompts recipe
          <> checkExtension recipe
   in if null errs
        then Right recipe
        else Left errs

-- Rule 1: Recipe name must match [a-z][a-z0-9-]*
checkRecipeNameFormat :: Recipe -> [Text]
checkRecipeNameFormat recipe =
  let n = (recipe ^. #name . #unRecipeName)
   in if T.null n || not (isValidModuleName n)
        then ["recipe name must match [a-z][a-z0-9-]*, got: " <> n]
        else []

-- Rule 2: At least one module must be listed
checkNonEmptyModules :: Recipe -> [Text]
checkNonEmptyModules recipe
  | null (recipe ^. #modules) && isNothing (recipe ^. #extends) = ["modules: recipe must list at least one module"]
  | otherwise = []

-- Rule 3: No duplicate module names
checkNoDuplicateModules :: Recipe -> [Text]
checkNoDuplicateModules recipe =
  let names = map (^. #module_ . #unModuleName) (recipe ^. #modules)
   in map (\n -> "modules: duplicate module in recipe: " <> n) (findDupes Set.empty Set.empty names)

findDupes :: Set.Set Text -> Set.Set Text -> [Text] -> [Text]
findDupes _ _ [] = []
findDupes seen reported (x : xs)
  | Set.member x seen && not (Set.member x reported) = x : findDupes seen (Set.insert x reported) xs
  | otherwise = findDupes (Set.insert x seen) reported xs

-- Rule 4: Variable binding names must match [a-z][A-Za-z0-9.-]*
checkVarBindingNames :: Recipe -> [Text]
checkVarBindingNames recipe =
  concatMap checkDep (recipe ^. #modules <> [Dependency (o ^. #module_) (o ^. #vars) Nothing | o <- recipe ^. #moduleOverrides])
  where
    checkDep dep =
      concatMap
        ( \(VarName vn) ->
            if isValidVarBindingName vn
              then []
              else ["modules.vars: invalid var binding name '" <> vn <> "' in module '" <> dep ^. #module_ . #unModuleName <> "'"]
        )
        (Map.keys (dep ^. #vars))

-- Descriptor-local checks deliberately require no values or member schemas.
checkRecipeVarsAndPrompts :: Recipe -> [Text]
checkRecipeVarsAndPrompts recipe =
  let names = map (^. #name . #unVarName) (recipe ^. #vars)
      declared = Set.fromList names
      undeclared (VarName name) = Set.notMember name declared
      promptErrors prompt =
        let target = prompt ^. #var . #unVarName
            refs = maybe [] exprRefs (prompt ^. #condition)
         in ["prompts: target '" <> target <> "' is undeclared; add it to vars" | undeclared (prompt ^. #var)]
              <> [ "prompts: '" <> target <> "' when references undeclared variable '" <> ref <> "'; add it to vars"
                 | (name@(VarName ref), _) <- refs,
                   undeclared name
                 ]
      patternErrors = ["vars: '" <> name <> "' " <> msg | d <- recipe ^. #vars, Left (ValidationFailed (VarName name) msg) <- [validateVarPattern d]]
   in patternErrors
        <> map (\name -> "vars: duplicate variable declaration '" <> name <> "'") (findDupes Set.empty Set.empty names)
        <> (if isNothing (recipe ^. #extends) then concatMap promptErrors (recipe ^. #prompts) else [])

-- | Producer intervals are requirements, independent of consumer downgrade flags.
validateRecipeVersion :: RecipeReference -> Recipe -> Either [Text] ()
validateRecipeVersion ref base = case ref ^. #versionRange of
  Nothing -> Right ()
  Just range -> case (parseNumericVersion (range ^. #minimum), parseNumericVersion (range ^. #before), (base ^. #version) >>= parseNumericVersion) of
    (Just low, Just high, Just selected) | low < high && low <= selected && selected < high -> Right ()
    _ ->
      Left
        [ "Base '"
            <> ref ^. #recipe . #unRecipeName
            <> "' version "
            <> maybe "<unversioned>" id (base ^. #version)
            <> " is outside required interval ["
            <> range ^. #minimum
            <> ", "
            <> range ^. #before
            <> ")"
        ]

checkExtension :: Recipe -> [Text]
checkExtension recipe =
  let overrides = recipe ^. #moduleOverrides
      promptOverrides = recipe ^. #promptOverrides
      names = map (^. #module_ . #unModuleName) overrides
      targets = map (^. #var . #unVarName) promptOverrides
      localNames = map (^. #module_ . #unModuleName) (recipe ^. #modules)
      localTargets = map (^. #var . #unVarName) (recipe ^. #prompts)
      badSource src = T.null (T.strip src) || "${" `T.isInfixOf` src
      refErrors ref =
        ["extends.recipe: invalid recipe name" | not (isValidModuleName (ref ^. #recipe . #unRecipeName))]
          <> ["extends.source: expected a nonempty literal Git source" | Just src <- [ref ^. #source], badSource src]
          <> case ref ^. #versionRange of
            Nothing -> []
            Just range -> case (parseNumericVersion (range ^. #minimum), parseNumericVersion (range ^. #before)) of
              (Just low, Just high) | low < high -> []
              _ -> ["extends.versionRange: numeric minimum must be strictly below before"]
   in maybe [] refErrors (recipe ^. #extends)
        <> ["moduleOverrides: duplicate target '" <> n <> "'" | n <- findDupes Set.empty Set.empty names]
        <> ["promptOverrides: duplicate target '" <> n <> "'" | n <- findDupes Set.empty Set.empty targets]
        <> ["moduleOverrides: target also declared in modules: " <> n | n <- names, n `elem` localNames]
        <> ["promptOverrides: target also declared in prompts: " <> n | n <- targets, n `elem` localTargets]
        <> ["moduleOverrides: invalid module name: " <> n | n <- names, not (isValidModuleName n)]
        <> ["modules: invalid module name: " <> n | n <- localNames, not (isValidModuleName n)]
        <> ["modules.source: expected a nonempty literal Git source" | dep <- recipe ^. #modules, Just src <- [dep ^. #source], badSource src]
        <> ["overrides require extends" | isNothing (recipe ^. #extends), not (null overrides && null promptOverrides)]

-- Keep author intervals numeric even though the legacy parser accepts the
-- whitespace and sign syntax of Haskell's Read instance.
parseNumericVersion :: Text -> Maybe Version
parseNumericVersion raw
  | T.all (\c -> (c >= '0' && c <= '9') || c == '.') raw = parseVersion raw
  | otherwise = Nothing
