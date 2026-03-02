module Seihou.Composition.Resolve
  ( loadComposition,
    resolveComposedVariables,
    exportedVars,
  )
where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Seihou.Composition.Graph (buildGraph, topoSort)
import Seihou.Core.Module (discoverModule, validateModule)
import Seihou.Core.Types
import Seihou.Core.Variable (resolveVariables)
import Seihou.Dhall.Eval (evalModuleFromFile)
import System.FilePath ((</>))

-- | Load all modules in a composition: primary + additional + transitive deps.
-- Additional modules are treated as implicit dependencies of the primary module.
-- Returns modules with their directories in execution order (dependencies first).
loadComposition ::
  [FilePath] ->
  ModuleName ->
  [ModuleName] ->
  IO (Either ModuleLoadError [(Module, FilePath)])
loadComposition searchPaths primary additional = do
  -- Load the primary module
  primaryResult <- loadModuleWithDir searchPaths primary
  case primaryResult of
    Left err -> pure (Left err)
    Right (primaryMod, primaryDir) -> do
      -- Add additional modules as implicit dependencies of the primary
      let effectiveDeps = moduleDependencies primaryMod ++ additional
          effectivePrimary = primaryMod {moduleDependencies = nubOrd effectiveDeps}
          loaded = Map.singleton primary (effectivePrimary, primaryDir)
      -- Recursively load all transitive dependencies
      transResult <- loadTransitive searchPaths loaded (moduleDependencies effectivePrimary)
      case transResult of
        Left err -> pure (Left err)
        Right allModules -> do
          -- Build graph and topological sort
          let graph = buildGraph (map fst (Map.elems allModules))
          case topoSort graph of
            Left err -> pure (Left err)
            Right order ->
              pure $ Right [(m, d) | name <- order, Just (m, d) <- [Map.lookup name allModules]]

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
  Either [VarError] (Map ModuleName (Map VarName ResolvedVar))
resolveComposedVariables modulesInOrder cliOverrides envVars =
  go modulesInOrder Map.empty Map.empty
  where
    go ::
      [(Module, FilePath)] ->
      Map ModuleName (Map VarName ResolvedVar) ->
      Map ModuleName (Map VarName VarValue) ->
      Either [VarError] (Map ModuleName (Map VarName ResolvedVar))
    go [] perModule _ = Right perModule
    go ((m, _dir) : rest) perModule allExports = do
      let deps = moduleDependencies m
          -- Collect exports from direct dependencies only
          visibleExports =
            Map.unions [Map.findWithDefault Map.empty dep allExports | dep <- deps]
          -- Inject exported values as defaults for declared variables
          adjustedDecls = map (injectExportDefault visibleExports) (moduleVars m)
      -- Resolve this module's declared variables
      resolved <- resolveVariables adjustedDecls cliOverrides envVars
      -- Add inherited (non-declared) exports to the resolved map
      let declaredNames = Set.fromList (map varName (moduleVars m))
          inherited =
            Map.mapWithKey
              makeInheritedResolved
              (Map.filterWithKey (\k _ -> not (Set.member k declaredNames)) visibleExports)
          fullResolved = resolved `Map.union` inherited
      -- Compute this module's exports
      let myExports = exportedVars m fullResolved
      go
        rest
        (Map.insert (moduleName m) fullResolved perModule)
        (Map.insert (moduleName m) myExports allExports)

-- | Extract exported variables from a module's resolved values.
-- Uses the alias name if provided, otherwise the original variable name.
exportedVars :: Module -> Map VarName ResolvedVar -> Map VarName VarValue
exportedVars m resolved =
  Map.fromList
    [ (exportName e, resolvedValue rv)
    | e <- moduleExports m,
      Just rv <- [Map.lookup (exportVar e) resolved]
    ]
  where
    exportName e = case exportAs e of
      Just alias -> alias
      Nothing -> exportVar e

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
              newDeps = moduleDependencies m
          loadTransitive searchPaths loaded' (rest ++ newDeps)

-- | Inject an exported value as the default for a variable declaration.
-- The export replaces any existing default, giving it precedence over
-- the module author's default while still being overridable by CLI/env.
injectExportDefault :: Map VarName VarValue -> VarDecl -> VarDecl
injectExportDefault exports decl =
  case Map.lookup (varName decl) exports of
    Just val -> decl {varDefault = Just val}
    Nothing -> decl

-- | Create a ResolvedVar for an inherited (non-declared) export variable.
makeInheritedResolved :: VarName -> VarValue -> ResolvedVar
makeInheritedResolved name val =
  ResolvedVar
    { resolvedValue = val,
      resolvedSource = FromDefault,
      resolvedDecl =
        VarDecl
          { varName = name,
            varType = inferType val,
            varDefault = Just val,
            varDescription = Nothing,
            varRequired = False,
            varValidation = Nothing
          }
    }

-- | Infer the VarType from a VarValue.
inferType :: VarValue -> VarType
inferType (VText _) = VTText
inferType (VBool _) = VTBool
inferType (VInt _) = VTInt
inferType (VList []) = VTList VTText
inferType (VList (v : _)) = VTList (inferType v)

-- | Remove duplicates from a list while preserving order.
nubOrd :: (Ord a) => [a] -> [a]
nubOrd = go Set.empty
  where
    go _ [] = []
    go seen (x : xs)
      | Set.member x seen = go seen xs
      | otherwise = x : go (Set.insert x seen) xs
