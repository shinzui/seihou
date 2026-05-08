module Seihou.Core.Blueprint
  ( validateBlueprint,
    validateBlueprintWith,
    checkBlueprintNameFormat,
    checkBlueprintVersionPresent,
    checkBlueprintPromptNonEmpty,
    checkBlueprintUniqueVars,
    checkBlueprintPromptRefs,
    checkBlueprintBaseModules,
    checkBlueprintBaseModulesWith,
    checkBlueprintFiles,
    checkBlueprintTags,
    checkBlueprintAllowedTools,
  )
where

import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as T
import Seihou.Core.Module (defaultSearchPaths, discoverRunnable, isValidModuleName)
import Seihou.Core.Types
import Seihou.Prelude
import System.Directory (doesFileExist)

-- | Validate a decoded 'Blueprint' against the documented rules.
-- The 'FilePath' is the blueprint's base directory (containing
-- @blueprint.dhall@).
--
-- Validation rules:
--
--   1. Name format: matches @[a-z][a-z0-9-]*@.
--   2. Version, when given, is non-empty (blueprints may legitimately
--      omit a version during early authoring; we only reject @Just ""@).
--   3. Prompt body is non-empty after trimming.
--   4. Variable names declared in @vars@ are unique.
--   5. Every interactive prompt references a declared variable.
--   6. Each @baseModules@ entry is well-formed (name format and var
--      binding names) and resolves to a module or recipe — not another
--      blueprint and not nothing.
--   7. Every @files@ entry exists at @baseDir/files/SRC@.
--   8. Every tag is non-empty.
--   9. Every @allowedTools@ entry, when set, is non-empty.
validateBlueprint :: FilePath -> Blueprint -> IO (Either ModuleLoadError Blueprint)
validateBlueprint baseDir b = do
  searchPaths <- defaultSearchPaths
  validateBlueprintWith searchPaths baseDir b

-- | Same as 'validateBlueprint' but takes the search paths used for
-- resolving base-module references explicitly. Useful for tests that
-- need to pin the lookup roots; production code should call
-- 'validateBlueprint' which pulls them from 'defaultSearchPaths'.
validateBlueprintWith ::
  [FilePath] ->
  FilePath ->
  Blueprint ->
  IO (Either ModuleLoadError Blueprint)
validateBlueprintWith searchPaths baseDir b = do
  fileErrs <- checkBlueprintFiles baseDir b
  baseErrs <- checkBlueprintBaseModulesWith searchPaths b
  let pureErrs =
        checkBlueprintNameFormat b
          <> checkBlueprintVersionPresent b
          <> checkBlueprintPromptNonEmpty b
          <> checkBlueprintUniqueVars b
          <> checkBlueprintPromptRefs b
          <> checkBlueprintTags b
          <> checkBlueprintAllowedTools b
      allErrs = pureErrs <> fileErrs <> baseErrs
  pure $
    if null allErrs
      then Right b
      else Left (ValidationError b.name allErrs)

-- Rule 1: blueprint name must match [a-z][a-z0-9-]*
checkBlueprintNameFormat :: Blueprint -> [Text]
checkBlueprintNameFormat b =
  let n = b.name.unModuleName
   in if T.null n || not (isValidModuleName n)
        then ["blueprint name must match [a-z][a-z0-9-]*, got: " <> n]
        else []

-- Rule 2: if a version is given it must not be empty
checkBlueprintVersionPresent :: Blueprint -> [Text]
checkBlueprintVersionPresent b = case b.version of
  Nothing -> []
  Just v
    | T.null (T.strip v) -> ["blueprint version, if specified, must not be empty"]
    | otherwise -> []

-- Rule 3: prompt body must not be empty after trimming
checkBlueprintPromptNonEmpty :: Blueprint -> [Text]
checkBlueprintPromptNonEmpty b
  | T.null (T.strip b.prompt) = ["blueprint prompt must not be empty"]
  | otherwise = []

-- Rule 4: declared variable names must be unique
checkBlueprintUniqueVars :: Blueprint -> [Text]
checkBlueprintUniqueVars b =
  let names = map (\d -> d.name.unVarName) b.vars
   in map (\n -> "duplicate variable name: " <> n) (findDupes Set.empty Set.empty names)

findDupes :: Set.Set Text -> Set.Set Text -> [Text] -> [Text]
findDupes _ _ [] = []
findDupes seen reported (x : xs)
  | Set.member x seen && not (Set.member x reported) = x : findDupes seen (Set.insert x reported) xs
  | otherwise = findDupes (Set.insert x seen) reported xs

-- Rule 5: every prompt references a declared variable
checkBlueprintPromptRefs :: Blueprint -> [Text]
checkBlueprintPromptRefs b =
  let varNames = Set.fromList (map (.name) b.vars)
   in concatMap
        ( \p ->
            if Set.member p.var varNames
              then []
              else ["prompt references undeclared variable: " <> p.var.unVarName]
        )
        b.prompts

-- Rule 6: base modules must be well-formed and resolve to a module or
-- recipe (not another blueprint). The check uses the same default
-- search paths as @seihou run@; tests can pass custom roots via
-- 'checkBlueprintBaseModulesWith'.
checkBlueprintBaseModules :: Blueprint -> IO [Text]
checkBlueprintBaseModules b = do
  searchPaths <- defaultSearchPaths
  checkBlueprintBaseModulesWith searchPaths b

checkBlueprintBaseModulesWith :: [FilePath] -> Blueprint -> IO [Text]
checkBlueprintBaseModulesWith searchPaths b =
  concat <$> mapM (checkOne searchPaths) b.baseModules
  where
    checkOne :: [FilePath] -> Dependency -> IO [Text]
    checkOne paths dep = do
      let n = dep.depModule.unModuleName
          nameErrs =
            [ "invalid baseModule name: " <> n
            | not (isValidModuleName n)
            ]
          bindingErrs =
            [ "baseModule '" <> n <> "' has invalid var binding name: " <> vn
            | (VarName vn) <- Map.keys dep.depVars,
              not (isValidVarBindingName vn)
            ]
      resolveErrs <-
        if not (isValidModuleName n)
          then pure []
          else do
            result <- discoverRunnable paths dep.depModule
            pure $ case result of
              Right (RunnableModule _ _) -> []
              Right (RunnableRecipe _ _) -> []
              Right (RunnableBlueprint _ _) ->
                [ "baseModule '"
                    <> n
                    <> "' resolves to a blueprint; baseModules must be modules or recipes"
                ]
              Left (ModuleNotFound _ _) ->
                ["baseModule '" <> n <> "' not found in any search path"]
              Left _ ->
                ["baseModule '" <> n <> "' failed to load"]
      pure (nameErrs <> bindingErrs <> resolveErrs)

    isValidVarBindingName :: Text -> Bool
    isValidVarBindingName t = case T.uncons t of
      Nothing -> False
      Just (c, rest) ->
        (c >= 'a' && c <= 'z')
          && T.all
            (\ch -> (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') || ch == '-' || ch == '.')
            rest

-- Rule 7: every @files@ entry's source must exist on disk relative to
-- @baseDir/files/@
checkBlueprintFiles :: FilePath -> Blueprint -> IO [Text]
checkBlueprintFiles baseDir b =
  concat
    <$> mapM
      ( \bf -> do
          let p = baseDir </> "files" </> bf.src
          exists <- doesFileExist p
          pure $
            if exists
              then []
              else ["blueprint file not found: " <> T.pack bf.src]
      )
      b.files

-- Rule 8: tags must not be empty strings
checkBlueprintTags :: Blueprint -> [Text]
checkBlueprintTags b =
  [ "tag must not be empty"
  | t <- b.tags,
    T.null (T.strip t)
  ]

-- Rule 9: @allowedTools@, when set, must contain only non-empty entries
checkBlueprintAllowedTools :: Blueprint -> [Text]
checkBlueprintAllowedTools b = case b.allowedTools of
  Nothing -> []
  Just xs ->
    [ "allowedTools entry must not be empty"
    | t <- xs,
      T.null (T.strip t)
    ]
