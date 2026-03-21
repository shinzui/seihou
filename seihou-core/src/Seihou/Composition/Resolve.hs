module Seihou.Composition.Resolve
  ( loadComposition,
    resolveComposedVariables,
    resolveWithPrompts,
    exportedVars,
    collectParentVars,
  )
where

import Control.Monad.Trans.Except (ExceptT (..), runExceptT)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as T
import Seihou.Composition.Graph (buildGraph, topoSort)
import Seihou.Core.Module (discoverModule, validateModule)
import Seihou.Core.Types
import Seihou.Core.Variable (resolveVariables)
import Seihou.Dhall.Eval (evalModuleFromFile)
import Seihou.Effect.Console (Console, isInteractive, putText)
import Seihou.Interaction.Prompt (runPrompts)
import Seihou.Prelude

-- | Load all modules in a composition: primary + additional + transitive deps.
-- Additional modules are treated as implicit dependencies of the primary module.
-- Returns modules with their directories in execution order (dependencies first).
loadComposition ::
  [FilePath] ->
  ModuleName ->
  [ModuleName] ->
  IO (Either ModuleLoadError [(Module, FilePath)])
loadComposition searchPaths primary additional = runExceptT $ do
  (primaryMod, primaryDir) <- ExceptT $ loadModuleWithDir searchPaths primary
  let effectiveDeps = primaryMod.dependencies ++ map simpleDep additional
      effectivePrimary = primaryMod {dependencies = nubOrdBy (.depModule) effectiveDeps}
      loaded = Map.singleton primary (effectivePrimary, primaryDir)
  allModules <- ExceptT $ loadTransitive searchPaths loaded (depModuleNames effectivePrimary.dependencies)
  let graph = buildGraph (map fst (Map.elems allModules))
  order <- ExceptT . pure $ topoSort graph
  pure [(m, d) | name <- order, Just (m, d) <- [Map.lookup name allModules]]

-- | Resolve variables for all modules in a composition with export visibility.
--
-- For each module in execution order:
-- 1. Collect exported variables from its direct dependencies.
-- 2. Inject those exports as defaults for any matching declared variables.
-- 3. Call 'resolveVariables' with the adjusted declarations.
-- 4. Record the module's exports for downstream modules.
--
-- Exported values override the module's own defaults but are still lower
-- priority than CLI overrides and environment variables.
resolveComposedVariables ::
  [(Module, FilePath)] ->
  Map VarName Text ->
  Map Text Text ->
  Text ->
  Text ->
  Map VarName Text ->
  Map VarName Text ->
  Map VarName Text ->
  Map VarName Text ->
  Either [VarError] (Map ModuleName (Map VarName ResolvedVar))
resolveComposedVariables modulesInOrder cliOverrides envVars namespace context localConfig nsConfig ctxConfig globalConfig =
  let allParentVars = collectParentVars modulesInOrder
   in go allParentVars modulesInOrder Map.empty Map.empty
  where
    go ::
      Map ModuleName (Map VarName (Text, ModuleName)) ->
      [(Module, FilePath)] ->
      Map ModuleName (Map VarName ResolvedVar) ->
      Map ModuleName (Map VarName VarValue) ->
      Either [VarError] (Map ModuleName (Map VarName ResolvedVar))
    go _ [] perModule _ = Right perModule
    go parentVarsMap ((m, _dir) : rest) perModule allExports = do
      let deps = depModuleNames m.dependencies
          -- Collect exports from direct dependencies only
          visibleExports =
            Map.unions [Map.findWithDefault Map.empty dep allExports | dep <- deps]
          -- Inject exported values as defaults for declared variables
          adjustedDecls = map (injectExportDefault visibleExports) m.vars
          -- Parent-supplied vars for this module
          myParentVars = Map.findWithDefault Map.empty m.name parentVarsMap
      -- Resolve this module's declared variables
      resolved <- resolveVariables adjustedDecls cliOverrides envVars namespace context localConfig nsConfig ctxConfig globalConfig myParentVars
      -- Add inherited (non-declared) exports to the resolved map
      let declaredNames = Set.fromList (map (.name) m.vars)
          inherited =
            Map.mapWithKey
              makeInheritedResolved
              (Map.filterWithKey (\k _ -> not (Set.member k declaredNames)) visibleExports)
          fullResolved = resolved `Map.union` inherited
      -- Compute this module's exports
      let myExports = exportedVars m fullResolved
      go
        parentVarsMap
        rest
        (Map.insert m.name fullResolved perModule)
        (Map.insert m.name myExports allExports)

-- | Resolve variables for all modules with interactive prompt support.
--
-- Same as 'resolveComposedVariables' but when a module has unresolved required
-- variables, prompts the user via the Console effect (if interactive).
-- In non-interactive mode, missing required variables remain as errors.
resolveWithPrompts ::
  (Console :> es) =>
  [(Module, FilePath)] ->
  Map VarName Text ->
  Map Text Text ->
  Text ->
  Text ->
  Map VarName Text ->
  Map VarName Text ->
  Map VarName Text ->
  Map VarName Text ->
  Eff es (Either [VarError] (Map ModuleName (Map VarName ResolvedVar)))
resolveWithPrompts modulesInOrder cliOverrides envVars namespace context localConfig nsConfig ctxConfig globalConfig = do
  interactive <- isInteractive
  let allParentVars = collectParentVars modulesInOrder
  goPrompt interactive allParentVars modulesInOrder Map.empty Map.empty
  where
    goPrompt ::
      (Console :> es) =>
      Bool ->
      Map ModuleName (Map VarName (Text, ModuleName)) ->
      [(Module, FilePath)] ->
      Map ModuleName (Map VarName ResolvedVar) ->
      Map ModuleName (Map VarName VarValue) ->
      Eff es (Either [VarError] (Map ModuleName (Map VarName ResolvedVar)))
    goPrompt _ _ [] perModule _ = pure (Right perModule)
    goPrompt interactive parentVarsMap ((m, _dir) : rest) perModule allExports = do
      let deps = depModuleNames m.dependencies
          visibleExports =
            Map.unions [Map.findWithDefault Map.empty dep allExports | dep <- deps]
          adjustedDecls = map (injectExportDefault visibleExports) m.vars
          myParentVars = Map.findWithDefault Map.empty m.name parentVarsMap
      case resolveVariables adjustedDecls cliOverrides envVars namespace context localConfig nsConfig ctxConfig globalConfig myParentVars of
        Right resolved -> do
          let declaredNames = Set.fromList (map (.name) m.vars)
              inherited =
                Map.mapWithKey
                  makeInheritedResolved
                  (Map.filterWithKey (\k _ -> not (Set.member k declaredNames)) visibleExports)
              resolvedWithInherited = resolved `Map.union` inherited
          -- Prompt for optional variables that have prompts but no value
          let optionalDecls =
                [ d
                | d <- adjustedDecls,
                  not d.required,
                  not (Map.member d.name resolvedWithInherited),
                  any (\p -> p.var == d.name) m.prompts
                ]
          optionalPrompted <-
            if interactive && not (null optionalDecls)
              then do
                let currentBindings = Map.map (.value) (Map.unions (Map.elems perModule))
                    allBindings = Map.union (Map.map (.value) resolvedWithInherited) currentBindings
                putText ""
                putText "Optional configuration:"
                runPrompts m.prompts optionalDecls allBindings
              else pure Map.empty
          let fullResolved = resolvedWithInherited `Map.union` optionalPrompted
              myExports = exportedVars m fullResolved
          goPrompt
            interactive
            parentVarsMap
            rest
            (Map.insert m.name fullResolved perModule)
            (Map.insert m.name myExports allExports)
        Left errs -> do
          -- Separate MissingRequiredVar from other errors
          let (missing, fatal) = partitionErrors errs
          if not (null fatal)
            then pure (Left (fatal ++ missing))
            else
              if not interactive || null missing
                then pure (Left errs)
                else do
                  -- Build the currently-resolved bindings for condition evaluation
                  let currentBindings = Map.map (.value) (Map.unions (Map.elems perModule))
                      missingDecls = [d | d <- adjustedDecls, d.name `elem` map getMissingName missing]
                  -- Run prompts for unresolved variables
                  prompted <- runPrompts m.prompts missingDecls currentBindings
                  -- Check if all missing variables are now resolved
                  let stillMissing = [e | e <- missing, not (Map.member (getMissingName e) prompted)]
                  if not (null stillMissing)
                    then pure (Left stillMissing)
                    else do
                      -- Re-resolve: merge prompted values as CLI overrides
                      let promptedOverrides =
                            Map.union cliOverrides $
                              Map.map (varValueToText . (.value)) prompted
                      case resolveVariables adjustedDecls promptedOverrides envVars namespace context localConfig nsConfig ctxConfig globalConfig myParentVars of
                        Left errs' -> pure (Left errs')
                        Right resolved -> do
                          -- Replace source for prompted vars with FromPrompt
                          let resolvedWithPromptSource =
                                Map.mapWithKey
                                  ( \vn rv ->
                                      case Map.lookup vn prompted of
                                        Just pv -> pv
                                        Nothing -> rv
                                  )
                                  resolved
                              declaredNames = Set.fromList (map (.name) m.vars)
                              inherited =
                                Map.mapWithKey
                                  makeInheritedResolved
                                  (Map.filterWithKey (\k _ -> not (Set.member k declaredNames)) visibleExports)
                              resolvedWithInherited' = resolvedWithPromptSource `Map.union` inherited
                          -- Prompt for optional variables (same logic as success path)
                          let optionalDecls' =
                                [ d
                                | d <- adjustedDecls,
                                  not d.required,
                                  not (Map.member d.name resolvedWithInherited'),
                                  any (\p -> p.var == d.name) m.prompts
                                ]
                          optionalPrompted' <-
                            if not (null optionalDecls')
                              then do
                                let cb = Map.map (.value) (Map.unions (Map.elems perModule))
                                    ab = Map.union (Map.map (.value) resolvedWithInherited') cb
                                putText ""
                                putText "Optional configuration:"
                                runPrompts m.prompts optionalDecls' ab
                              else pure Map.empty
                          let fullResolved = resolvedWithInherited' `Map.union` optionalPrompted'
                              myExports = exportedVars m fullResolved
                          goPrompt
                            interactive
                            parentVarsMap
                            rest
                            (Map.insert m.name fullResolved perModule)
                            (Map.insert m.name myExports allExports)

-- | Extract the variable name from a MissingRequiredVar error.
getMissingName :: VarError -> VarName
getMissingName (MissingRequiredVar n) = n
getMissingName _ = VarName ""

-- | Partition errors into MissingRequiredVar and other (fatal) errors.
partitionErrors :: [VarError] -> ([VarError], [VarError])
partitionErrors = foldr go ([], [])
  where
    go e@(MissingRequiredVar _) (missing, fatal) = (e : missing, fatal)
    go e (missing, fatal) = (missing, e : fatal)

-- | Convert a VarValue to its text representation for use as an override.
varValueToText :: VarValue -> Text
varValueToText (VText t) = t
varValueToText (VBool True) = "true"
varValueToText (VBool False) = "false"
varValueToText (VInt n) = T.pack (show n)
varValueToText (VList vs) = T.intercalate "," (map varValueToText vs)

-- | Extract exported variables from a module's resolved values.
-- Uses the alias name if provided, otherwise the original variable name.
exportedVars :: Module -> Map VarName ResolvedVar -> Map VarName VarValue
exportedVars m resolved =
  Map.fromList
    [ (exportName e, rv.value)
    | e <- m.exports,
      Just rv <- [Map.lookup e.var resolved]
    ]
  where
    exportName e = case e.alias of
      Just a -> a
      Nothing -> e.var

-- Internal helpers

-- | Load a module and return both the module and its directory path.
loadModuleWithDir :: [FilePath] -> ModuleName -> IO (Either ModuleLoadError (Module, FilePath))
loadModuleWithDir searchPaths name = do
  discovered <- discoverModule searchPaths name
  case discovered of
    Left err -> pure (Left err)
    Right moduleDir -> do
      let dhallFile = moduleDir </> "module.dhall"
      decoded <- evalModuleFromFile dhallFile
      case decoded of
        Left err -> pure (Left err)
        Right m -> do
          validated <- validateModule moduleDir m
          case validated of
            Left err -> pure (Left err)
            Right m' -> pure (Right (m', moduleDir))

-- | Recursively load transitive dependencies.
-- Tracks already-loaded modules to handle diamond dependencies.
loadTransitive ::
  [FilePath] ->
  Map ModuleName (Module, FilePath) ->
  [ModuleName] ->
  IO (Either ModuleLoadError (Map ModuleName (Module, FilePath)))
loadTransitive _ loaded [] = pure (Right loaded)
loadTransitive searchPaths loaded (name : rest)
  | Map.member name loaded = loadTransitive searchPaths loaded rest
  | otherwise = do
      result <- loadModuleWithDir searchPaths name
      case result of
        Left err -> pure (Left err)
        Right (m, dir) -> do
          let loaded' = Map.insert name (m, dir) loaded
              newDeps = depModuleNames m.dependencies
          loadTransitive searchPaths loaded' (rest ++ newDeps)

-- | Inject an exported value as the default for a variable declaration.
-- The export replaces any existing default, giving it precedence over
-- the module author's default while still being overridable by CLI/env.
injectExportDefault :: Map VarName VarValue -> VarDecl -> VarDecl
injectExportDefault exports decl =
  case Map.lookup decl.name exports of
    Just val -> decl {default_ = Just val}
    Nothing -> decl

-- | Create a ResolvedVar for an inherited (non-declared) export variable.
makeInheritedResolved :: VarName -> VarValue -> ResolvedVar
makeInheritedResolved n val =
  ResolvedVar
    { value = val,
      source = FromDefault,
      decl =
        VarDecl
          { name = n,
            type_ = inferType val,
            default_ = Just val,
            description = Nothing,
            required = False,
            validation = Nothing
          }
    }

-- | Infer the VarType from a VarValue.
inferType :: VarValue -> VarType
inferType (VText _) = VTText
inferType (VBool _) = VTBool
inferType (VInt _) = VTInt
inferType (VList []) = VTList VTText
inferType (VList (v : _)) = VTList (inferType v)

-- | Collect all parent-supplied variable bindings across the composition.
-- Returns a map from module name to the vars supplied to it by its dependents.
-- Each value includes the raw text value and the name of the parent module
-- that supplied it (for provenance tracking via 'FromParent').
collectParentVars :: [(Module, FilePath)] -> Map ModuleName (Map VarName (Text, ModuleName))
collectParentVars modules =
  Map.fromListWith
    Map.union
    [ (dep.depModule, Map.map (,m.name) dep.depVars)
    | (m, _) <- modules,
      dep <- m.dependencies,
      not (Map.null dep.depVars)
    ]

-- | Remove duplicates from a list while preserving order, using a key function.
nubOrdBy :: (Ord k) => (a -> k) -> [a] -> [a]
nubOrdBy f = go Set.empty
  where
    go _ [] = []
    go seen (x : xs)
      | Set.member (f x) seen = go seen xs
      | otherwise = x : go (Set.insert (f x) seen) xs
