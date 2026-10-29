module Seihou.Composition.Resolve
  ( loadComposition,
    verifyDependencySources,
    SavedInstanceValues,
    PromptPermission (..),
    resolveComposedVariables,
    resolveComposedVariablesWithSaved,
    resolveWithPrompts,
    resolveWithPromptPermission,
    RecipeInputSpec (..),
    resolveRecipeWithPrompts,
    varValueToText,
    exportedVars,
    collectParentVars,
  )
where

import Control.Monad (unless)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Except (ExceptT (..), runExceptT)
import Data.Generics.Labels ()
import Data.List (find)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Set qualified as Set
import Data.Text qualified as T
import Seihou.Composition.Graph (buildGraph, topoSort)
import Seihou.Composition.Instance (ModuleInstance (..), mkInstance, primaryInstance)
import Seihou.Core.ArtifactIdentity (normalizeOriginUrl)
import Seihou.Core.ArtifactOriginDetect (OriginInfo (..), readOriginInfo)
import Seihou.Core.Module (discoverModule, validateModule)
import Seihou.Core.Types
import Seihou.Core.Variable (coerceValue, resolveVariablesWithSaved, resolveVariablesWithSources)
import Seihou.Dhall.Eval (evalModuleFromFile)
import Seihou.Effect.Console (Console, isInteractive, putText)
import Seihou.Interaction.Prompt (promptForVar, runPrompts, runPromptsChecked)
import Seihou.Prelude

-- | Values captured by a previously accepted composition, kept distinct per
-- parameterized module instance.
type SavedInstanceValues = Map ModuleInstance (Map VarName Text)

-- | Whether resolution may consult the Console prompt layer. Even when
-- allowed, prompts are used only for an interactive Console interpreter.
data PromptPermission = PromptsAllowed | PromptsForbidden
  deriving stock (Eq, Show)

-- | Load all modules in a composition: primary + additional + transitive deps.
-- Additional modules are treated as implicit dependencies of the primary module.
-- Returns modules with their directories in execution order (dependencies first).
--
-- Each entry carries a 'ModuleInstance' identifying the exact invocation.
-- Two dependency edges to the same module with different @vars@ produce
-- two distinct entries; identical edges dedupe.
loadComposition ::
  [FilePath] ->
  ModuleName ->
  [ModuleName] ->
  IO (Either ModuleLoadError [(ModuleInstance, Module, FilePath)])
loadComposition searchPaths primary additional = runExceptT $ do
  (primaryMod, primaryDir) <- ExceptT $ loadModuleWithDir searchPaths primary
  let effectiveDeps = primaryMod ^. #dependencies ++ map simpleDep additional
      effectivePrimary = (primaryMod & #dependencies .~ nubOrdBy (\dep -> (dep ^. #module_, parentVarsFromDep dep)) effectiveDeps)
      primaryInst = primaryInstance primary
      loaded = Map.singleton primaryInst (effectivePrimary, primaryDir)
      seeds = [(mkInstance (dep ^. #module_) (parentVarsFromDep dep)) | dep <- effectivePrimary ^. #dependencies]
  allInstances <- ExceptT $ loadTransitive searchPaths loaded seeds
  mapM_ (\(inst, (m, dir)) -> ExceptT (verifyDependencySources searchPaths dir ((if inst == primaryInst then primaryMod else m) ^. #dependencies))) (Map.toList allInstances)
  let entries = [(inst, m) | (inst, (m, _)) <- Map.toList allInstances]
      graph = buildGraph entries
  order <- ExceptT . pure $ topoSort graph
  pure [(inst, m, d) | inst <- order, Just (m, d) <- [Map.lookup inst allInstances]]

-- | Resolve variables for all modules in a composition with export visibility.
--
-- For each module-instance in execution order:
-- 1. Collect exported variables from its direct dependency edges (resolved
--    to the exact child instance along that edge, not just the module name).
-- 2. Inject those exports as defaults for any matching declared variables.
-- 3. Call 'resolveVariables' with the adjusted declarations.
-- 4. Record the instance's exports for downstream modules.
--
-- Exported values override the module's own defaults but are still lower
-- priority than CLI overrides and environment variables.
resolveComposedVariables ::
  [(ModuleInstance, Module, FilePath)] ->
  Map VarName Text ->
  Map Text Text ->
  Text ->
  Text ->
  Map VarName Text ->
  Map VarName Text ->
  Map VarName Text ->
  Map VarName Text ->
  Either [VarError] (Map ModuleInstance (Map VarName ResolvedVar))
resolveComposedVariables modulesInOrder cliOverrides envVars namespace context localConfig nsConfig ctxConfig globalConfig =
  resolveComposedVariablesWithSaved modulesInOrder Map.empty cliOverrides envVars namespace context localConfig nsConfig ctxConfig globalConfig

-- | Resolve a composition while replaying values saved for matching module
-- instances. Candidate declarations still own coercion and validation.
resolveComposedVariablesWithSaved ::
  [(ModuleInstance, Module, FilePath)] ->
  SavedInstanceValues ->
  Map VarName Text ->
  Map Text Text ->
  Text ->
  Text ->
  Map VarName Text ->
  Map VarName Text ->
  Map VarName Text ->
  Map VarName Text ->
  Either [VarError] (Map ModuleInstance (Map VarName ResolvedVar))
resolveComposedVariablesWithSaved modulesInOrder savedValues cliOverrides envVars namespace context localConfig nsConfig ctxConfig globalConfig =
  let allParentVars = collectParentVars modulesInOrder
   in go allParentVars modulesInOrder Map.empty Map.empty
  where
    go ::
      Map ModuleInstance (Map VarName (Text, ModuleName)) ->
      [(ModuleInstance, Module, FilePath)] ->
      Map ModuleInstance (Map VarName ResolvedVar) ->
      Map ModuleInstance (Map VarName VarValue) ->
      Either [VarError] (Map ModuleInstance (Map VarName ResolvedVar))
    go _ [] perModule _ = Right perModule
    go parentVarsMap ((inst, m, _dir) : rest) perModule allExports = do
      let visibleExports = gatherEdgeExports m allExports
          adjustedDecls = map (injectExportDefault visibleExports) (m ^. #vars)
          myParentVars = Map.findWithDefault Map.empty inst parentVarsMap
          saved = Map.findWithDefault Map.empty inst savedValues
      resolved <- resolveVariablesWithSaved adjustedDecls cliOverrides saved envVars namespace context localConfig nsConfig ctxConfig globalConfig myParentVars
      let declaredNames = Set.fromList (map (^. #name) (m ^. #vars))
          inherited =
            Map.mapWithKey
              makeInheritedResolved
              (Map.filterWithKey (\k _ -> not (Set.member k declaredNames)) visibleExports)
          fullResolved = resolved `Map.union` inherited
      let myExports = exportedVars m fullResolved
      go
        parentVarsMap
        rest
        (Map.insert inst fullResolved perModule)
        (Map.insert inst myExports allExports)

-- | Resolve variables for all modules with interactive prompt support.
--
-- Same as 'resolveComposedVariables' but when a module has unresolved required
-- variables, prompts the user via the Console effect (if interactive).
-- In non-interactive mode, missing required variables remain as errors.
resolveWithPrompts ::
  (Console :> es) =>
  [(ModuleInstance, Module, FilePath)] ->
  Map VarName Text ->
  Map Text Text ->
  Text ->
  Text ->
  Map VarName Text ->
  Map VarName Text ->
  Map VarName Text ->
  Map VarName Text ->
  Eff es (Either [VarError] (Map ModuleInstance (Map VarName ResolvedVar)))
resolveWithPrompts modulesInOrder cliOverrides envVars namespace context localConfig nsConfig ctxConfig globalConfig = do
  resolveWithPromptPermission PromptsAllowed modulesInOrder Map.empty cliOverrides envVars namespace context localConfig nsConfig ctxConfig globalConfig

-- | Prompt-aware resolver with explicit permission and saved application
-- values. 'PromptsForbidden' never asks the Console interpreter whether a TTY
-- is present and therefore remains deterministic in JSON/non-TTY callers.
resolveWithPromptPermission ::
  (Console :> es) =>
  PromptPermission ->
  [(ModuleInstance, Module, FilePath)] ->
  SavedInstanceValues ->
  Map VarName Text ->
  Map Text Text ->
  Text ->
  Text ->
  Map VarName Text ->
  Map VarName Text ->
  Map VarName Text ->
  Map VarName Text ->
  Eff es (Either [VarError] (Map ModuleInstance (Map VarName ResolvedVar)))
resolveWithPromptPermission permission modulesInOrder savedValues cliOverrides =
  resolveWithSources permission modulesInOrder savedValues (Map.map (\raw -> (raw, FromCLI)) cliOverrides)

resolveWithSources ::
  (Console :> es) =>
  PromptPermission ->
  [(ModuleInstance, Module, FilePath)] ->
  SavedInstanceValues ->
  Map VarName (Text, VarSource) ->
  Map Text Text ->
  Text ->
  Text ->
  Map VarName Text ->
  Map VarName Text ->
  Map VarName Text ->
  Map VarName Text ->
  Eff es (Either [VarError] (Map ModuleInstance (Map VarName ResolvedVar)))
resolveWithSources permission modulesInOrder savedValues cliOverrides envVars namespace context localConfig nsConfig ctxConfig globalConfig = do
  interactive <- case permission of
    PromptsAllowed -> isInteractive
    PromptsForbidden -> pure False
  let allParentVars = collectParentVars modulesInOrder
  goPrompt interactive allParentVars modulesInOrder Map.empty Map.empty
  where
    goPrompt ::
      (Console :> es) =>
      Bool ->
      Map ModuleInstance (Map VarName (Text, ModuleName)) ->
      [(ModuleInstance, Module, FilePath)] ->
      Map ModuleInstance (Map VarName ResolvedVar) ->
      Map ModuleInstance (Map VarName VarValue) ->
      Eff es (Either [VarError] (Map ModuleInstance (Map VarName ResolvedVar)))
    goPrompt _ _ [] perModule _ = pure (Right perModule)
    goPrompt interactive parentVarsMap ((inst, m, _dir) : rest) perModule allExports = do
      let visibleExports = gatherEdgeExports m allExports
          adjustedDecls = map (injectExportDefault visibleExports) (m ^. #vars)
          myParentVars = Map.findWithDefault Map.empty inst parentVarsMap
          saved = Map.findWithDefault Map.empty inst savedValues
      case resolveVariablesWithSources adjustedDecls cliOverrides saved envVars namespace context localConfig nsConfig ctxConfig globalConfig myParentVars of
        Right resolved -> do
          let declaredNames = Set.fromList (map (^. #name) (m ^. #vars))
              inherited =
                Map.mapWithKey
                  makeInheritedResolved
                  (Map.filterWithKey (\k _ -> not (Set.member k declaredNames)) visibleExports)
              resolvedWithInherited = resolved `Map.union` inherited
          let optionalDecls =
                [ d
                | d <- adjustedDecls,
                  not (d ^. #required),
                  not (Map.member (d ^. #name) resolvedWithInherited),
                  any (\p -> p ^. #var == d ^. #name) (m ^. #prompts)
                ]
          optionalPrompted <-
            if interactive && not (null optionalDecls)
              then do
                let currentBindings = Map.map (^. #value) (Map.unions (Map.elems perModule))
                    allBindings = Map.union (Map.map (^. #value) resolvedWithInherited) currentBindings
                putText ""
                putText "Optional configuration:"
                runPrompts (m ^. #prompts) optionalDecls allBindings
              else pure Map.empty
          let fullResolved = resolvedWithInherited `Map.union` optionalPrompted
              myExports = exportedVars m fullResolved
          goPrompt
            interactive
            parentVarsMap
            rest
            (Map.insert inst fullResolved perModule)
            (Map.insert inst myExports allExports)
        Left errs -> do
          let (missing, fatal) = partitionErrors errs
          if not (null fatal)
            then pure (Left (fatal ++ missing))
            else
              if not interactive || null missing
                then pure (Left errs)
                else do
                  let currentBindings = Map.map (^. #value) (Map.unions (Map.elems perModule))
                      missingDecls = [d | d <- adjustedDecls, (d ^. #name) `elem` map getMissingName missing]
                  prompted <- runPrompts (m ^. #prompts) missingDecls currentBindings
                  let stillMissing = [e | e <- missing, not (Map.member (getMissingName e) prompted)]
                  if not (null stillMissing)
                    then pure (Left stillMissing)
                    else do
                      let promptedOverrides =
                            Map.union cliOverrides $
                              Map.map (\rv -> (varValueToText (rv ^. #value), FromPrompt)) prompted
                      case resolveVariablesWithSources adjustedDecls promptedOverrides saved envVars namespace context localConfig nsConfig ctxConfig globalConfig myParentVars of
                        Left errs' -> pure (Left errs')
                        Right resolved -> do
                          let resolvedWithPromptSource =
                                Map.mapWithKey
                                  ( \vn rv ->
                                      case Map.lookup vn prompted of
                                        Just pv -> pv
                                        Nothing -> rv
                                  )
                                  resolved
                              declaredNames = Set.fromList (map (^. #name) (m ^. #vars))
                              inherited =
                                Map.mapWithKey
                                  makeInheritedResolved
                                  (Map.filterWithKey (\k _ -> not (Set.member k declaredNames)) visibleExports)
                              resolvedWithInherited' = resolvedWithPromptSource `Map.union` inherited
                          let optionalDecls' =
                                [ d
                                | d <- adjustedDecls,
                                  not (d ^. #required),
                                  not (Map.member (d ^. #name) resolvedWithInherited'),
                                  any (\p -> p ^. #var == d ^. #name) (m ^. #prompts)
                                ]
                          optionalPrompted' <-
                            if not (null optionalDecls')
                              then do
                                let cb = Map.map (^. #value) (Map.unions (Map.elems perModule))
                                    ab = Map.union (Map.map (^. #value) resolvedWithInherited') cb
                                putText ""
                                putText "Optional configuration:"
                                runPrompts (m ^. #prompts) optionalDecls' ab
                              else pure Map.empty
                          let fullResolved = resolvedWithInherited' `Map.union` optionalPrompted'
                              myExports = exportedVars m fullResolved
                          goPrompt
                            interactive
                            parentVarsMap
                            rest
                            (Map.insert inst fullResolved perModule)
                            (Map.insert inst myExports allExports)

-- | Recipe declarations are resolved before any consuming module defaults.
-- Nothing denotes historical inputs that have not yet been adopted; Just empty
-- records an accepted omission of all optional inputs.
data RecipeInputSpec = RecipeInputSpec [VarDecl] [Prompt] (Maybe (Map VarName Text))

resolveRecipeWithPrompts ::
  (Console :> es) =>
  PromptPermission ->
  Bool ->
  RecipeInputSpec ->
  [(ModuleInstance, Module, FilePath)] ->
  SavedInstanceValues ->
  Map VarName Text ->
  Map VarName Text ->
  Map Text Text ->
  Text ->
  Text ->
  Map VarName Text ->
  Map VarName Text ->
  Map VarName Text ->
  Map VarName Text ->
  Eff es (Either [VarError] (Map VarName ResolvedVar, Map ModuleInstance (Map VarName ResolvedVar)))
resolveRecipeWithPrompts permission confirmRecipe (RecipeInputSpec decls prompts recorded) modules saved cli literals env ns ctx local nsCfg ctxCfg global = do
  interactive <- case permission of
    PromptsForbidden -> pure False
    PromptsAllowed -> isInteractive
  let explicit = Map.union (Map.map (\raw -> (raw, FromCLI)) cli) (Map.map (\raw -> (raw, FromRecipeBinding)) literals)
      historical d =
        nubOrdBy
          id
          [ either (const raw) varValueToText (coerceValue (d ^. #name) (d ^. #type_) raw)
          | (inst, m, _) <- modules,
            any ((== d ^. #name) . (^. #name)) (m ^. #vars),
            Just raw <- [Map.lookup inst saved >>= Map.lookup (d ^. #name)]
          ]
      conflicts =
        [ ValidationFailed (d ^. #name) ("conflicting saved recipe inputs; supply --var " <> d ^. #name . #unVarName <> "=VALUE or use --reconfigure")
        | d <- decls,
          recorded == Nothing,
          not (Map.member (d ^. #name) explicit),
          length (historical d) > 1
        ]
      replay = fromMaybe (Map.fromList [(d ^. #name, raw) | d <- decls, [raw] <- [historical d]]) recorded
      results = [resolveVariablesWithSources [d] explicit replay env ns ctx local nsCfg ctxCfg global Map.empty | d <- decls]
      values = Map.unions [v | Right v <- results]
      errors = concat [e | Left e <- results]
      (_, fatal) = partitionErrors errors
  if not (null (conflicts ++ fatal))
    then pure (Left (conflicts ++ fatal))
    else do
      confirmed <- if interactive && confirmRecipe then confirmValues (Map.toList values) values else pure (Right values)
      case confirmed of
        Left errs -> pure (Left errs)
        Right initial -> do
          let missing = [d | d <- decls, not (Map.member (d ^. #name) initial)]
              eligible = case recorded of
                Just _ -> filter (^. #required) missing
                Nothing -> missing
              required = filter (^. #required) eligible
              optional = filter (not . (^. #required)) eligible
          firstAnswers <- if interactive then runPromptsChecked prompts required (Map.map (^. #value) initial) else pure (Right Map.empty)
          case firstAnswers of
            Left errs -> pure (Left errs)
            Right answers -> do
              let current = Map.union answers initial
              secondAnswers <- if interactive then runPromptsChecked prompts optional (Map.map (^. #value) current) else pure (Right Map.empty)
              case secondAnswers of
                Left errs -> pure (Left errs)
                Right extras -> do
                  let recipeValues = Map.union extras current
                      omissions = [MissingRequiredVar (d ^. #name) | d <- decls, d ^. #required, not (Map.member (d ^. #name) recipeValues)]
                      broadcast = Map.map (\rv -> (varValueToText (rv ^. #value), rv ^. #source)) recipeValues
                  if not (null omissions)
                    then pure (Left omissions)
                    else do
                      let owned = Set.fromList (map (^. #name) decls)
                          consumers = [(i, m & #prompts %~ filter (\p -> not (Set.member (p ^. #var) owned)), dir) | (i, m, dir) <- modules]
                      resolved <- resolveWithSources permission consumers saved (Map.union explicit broadcast) env ns ctx local nsCfg ctxCfg global
                      pure $ fmap (\perModule -> (recipeValues, perModule)) resolved
  where
    confirmValues [] acc = pure (Right acc)
    confirmValues ((name, rv) : rest) acc
      | rv ^. #source /= FromDefault = confirmValues rest acc
      | otherwise = do
          let decl = rv ^. #decl
              prompt = fromMaybe (Prompt name (name ^. #unVarName) Nothing Nothing) (find ((== name) . (^. #var)) prompts)
          answer <- promptForVar prompt decl (Map.map (^. #value) acc)
          case answer of
            Left err -> pure (Left [err])
            Right accepted -> confirmValues rest (Map.insert name accepted acc)

-- | Collect the exports visible along a module's dependency edges.
--
-- Each dependency edge is resolved to the exact child instance
-- @(module_, vars)@, not just the module name, so that two
-- sibling instances of the same module contribute their own
-- per-instance exports without interference.
gatherEdgeExports ::
  Module ->
  Map ModuleInstance (Map VarName VarValue) ->
  Map VarName VarValue
gatherEdgeExports m allExports =
  Map.unions
    [ Map.findWithDefault Map.empty childInst allExports
    | dep <- m ^. #dependencies,
      let childInst = mkInstance (dep ^. #module_) (parentVarsFromDep dep)
    ]

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
    [ (exportName e, rv ^. #value)
    | e <- m ^. #exports,
      Just rv <- [Map.lookup (e ^. #var) resolved]
    ]
  where
    exportName e = case e ^. #alias of
      Just a -> a
      Nothing -> (e ^. #var)

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
--
-- Work-list entries are 'ModuleInstance' values — the caller has already
-- baked the parent-supplied bindings into each entry. An instance whose
-- @(name, parentVars)@ pair is already loaded is skipped, so two
-- dependency edges with identical parent bindings dedupe. Distinct
-- bindings produce distinct loaded entries even when the bare module
-- name is the same.
loadTransitive ::
  [FilePath] ->
  Map ModuleInstance (Module, FilePath) ->
  [ModuleInstance] ->
  IO (Either ModuleLoadError (Map ModuleInstance (Module, FilePath)))
loadTransitive _ loaded [] = pure (Right loaded)
loadTransitive searchPaths loaded (inst : rest)
  | Map.member inst loaded = loadTransitive searchPaths loaded rest
  | otherwise = do
      result <- loadModuleWithDir searchPaths (inst ^. #module_)
      case result of
        Left err -> pure (Left err)
        Right (m, dir) -> do
          let loaded' = Map.insert inst (m, dir) loaded
              newInstances =
                [ mkInstance (dep ^. #module_) (parentVarsFromDep dep)
                | dep <- m ^. #dependencies
                ]
          loadTransitive searchPaths loaded' (rest ++ newInstances)

-- | Inject an exported value as the default for a variable declaration.
-- The export replaces any existing default, giving it precedence over
-- the module author's default while still being overridable by CLI/env.
injectExportDefault :: Map VarName VarValue -> VarDecl -> VarDecl
injectExportDefault exports decl =
  case Map.lookup (decl ^. #name) exports of
    Just val -> (decl & #default_ ?~ val)
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
--
-- Returns a map keyed by 'ModuleInstance' — not by bare 'ModuleName' —
-- so two sibling invocations of the same child, each supplied with
-- different bindings by different parents, carry their own edge
-- decorations independently. A child edge's @vars@ uniquely
-- identifies the target instance, so no merging of overlapping
-- bindings is required: each @(ModuleInstance, edgeVars)@ pair is
-- distinct by construction.
collectParentVars ::
  [(ModuleInstance, Module, FilePath)] ->
  Map ModuleInstance (Map VarName (Text, ModuleName))
collectParentVars modules =
  Map.fromList
    [ (childInst, Map.map (,m ^. #name) (dep ^. #vars))
    | (_, m, _) <- modules,
      dep <- m ^. #dependencies,
      not (Map.null (dep ^. #vars)),
      let childInst = mkInstance (dep ^. #module_) (parentVarsFromDep dep)
    ]

-- | Remove duplicates from a list while preserving order, using a key function.
nubOrdBy :: (Ord k) => (a -> k) -> [a] -> [a]
nubOrdBy f = go Set.empty
  where
    go _ [] = []
    go seen (x : xs)
      | Set.member (f x) seen = go seen xs
      | otherwise = x : go (Set.insert (f x) seen) xs

-- | Verify producer requirements locally, including on the first generation.
-- A local shadow without provenance cannot satisfy an explicit source.
verifyDependencySources :: [FilePath] -> FilePath -> [Dependency] -> IO (Either ModuleLoadError ())
verifyDependencySources paths _declaringDir deps = runExceptT $ do
  mapM_ check deps
  where
    check dep = case dep ^. #source of
      Nothing -> pure ()
      Just required -> do
        let name = dep ^. #module_
        dir <- ExceptT (discoverModule paths name)
        actual <- liftIO (readOriginInfo dir)
        unless (maybe False (\info -> normalizeOriginUrl (info ^. #sourceUrl) == normalizeOriginUrl required) actual) $
          ExceptT $
            pure $
              Left $
                ValidationError
                  name
                  [ "Dependency '"
                      <> name ^. #unModuleName
                      <> "' requires "
                      <> required
                      <> "; resolved copy at "
                      <> T.pack dir
                      <> " has different or unknown provenance. Reinstall the declaring artifact and remove or correct the local shadow."
                  ]
