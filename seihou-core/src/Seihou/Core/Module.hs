module Seihou.Core.Module
  ( discoverModule,
    discoverBlueprint,
    discoverRunnable,
    defaultSearchPaths,
    validateModule,
    loadModule,
    discoverAllModules,
    discoverAllRunnables,
    DiscoveredModule (..),
    DiscoveredRunnable (..),
    RunnableKind (..),
    ModuleSource (..),

    -- * Individual check functions (for structured reports)
    checkNameFormat,
    checkVersionPresent,
    checkUniqueVars,
    checkPromptRefs,
    checkFileExistence,
    checkExportRefs,
    checkDependencyNames,
    checkDependencyVarBindings,
    checkSafeDestinations,
    checkDestVarRefs,
    checkCommandSafety,
    isValidModuleName,
    extractPlaceholders,
    validateProjectRelativePath,
  )
where

import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as T
import GHC.Generics (Generic)
import Seihou.Core.Path (validateProjectRelativePath)
import Seihou.Core.Types
import Seihou.Dhall.Eval (evalBlueprintFromFile, evalModuleFromFile, evalRecipeFromFile)
import Seihou.Prelude
import System.Directory (XdgDirectory (..), doesDirectoryExist, doesFileExist, getCurrentDirectory, getXdgDirectory, listDirectory)

-- | Search for a module by name in the given directories.
-- Returns the path to the directory containing @module.dhall@, or
-- 'ModuleNotFound' listing the directories that were searched.
discoverModule :: [FilePath] -> ModuleName -> IO (Either ModuleLoadError FilePath)
discoverModule searchPaths name = go searchPaths
  where
    nameStr = T.unpack name.unModuleName
    go [] = pure $ Left (ModuleNotFound name searchPaths)
    go (dir : rest) = do
      let candidate = dir </> nameStr
      let dhallFile = candidate </> "module.dhall"
      exists <- doesFileExist dhallFile
      if exists
        then pure (Right candidate)
        else go rest

-- | Search for a runnable (module, recipe, or blueprint) by name in the
-- given directories. For each search path, checks @module.dhall@ first
-- (returning 'RunnableModule'), then @recipe.dhall@
-- (returning 'RunnableRecipe'), then @blueprint.dhall@
-- (returning 'RunnableBlueprint'). Within a single candidate directory
-- the priority is module > recipe > blueprint, so a stray
-- @module.dhall@ next to a @blueprint.dhall@ silently surfaces the
-- module — the more specific, deterministic artifact. Returns
-- 'ModuleNotFound' if none is found in any search path.
discoverRunnable :: [FilePath] -> ModuleName -> IO (Either ModuleLoadError Runnable)
discoverRunnable searchPaths name = go searchPaths
  where
    nameStr = T.unpack name.unModuleName
    go [] = pure $ Left (ModuleNotFound name searchPaths)
    go (dir : rest) = do
      let candidate = dir </> nameStr
          moduleDhall = candidate </> "module.dhall"
          recipeDhall = candidate </> "recipe.dhall"
          blueprintDhall = candidate </> "blueprint.dhall"
      isModule <- doesFileExist moduleDhall
      if isModule
        then do
          result <- evalModuleFromFile moduleDhall
          case result of
            Left err -> pure (Left err)
            Right m -> pure (Right (RunnableModule m candidate))
        else do
          isRecipe <- doesFileExist recipeDhall
          if isRecipe
            then do
              result <- evalRecipeFromFile recipeDhall
              case result of
                Left err -> pure (Left err)
                Right r -> pure (Right (RunnableRecipe r candidate))
            else do
              isBlueprint <- doesFileExist blueprintDhall
              if isBlueprint
                then do
                  result <- evalBlueprintFromFile blueprintDhall
                  case result of
                    Left err -> pure (Left err)
                    Right b -> pure (Right (RunnableBlueprint b candidate))
                else go rest

-- | Search for a blueprint by name in the given directories. Returns
-- the path to the directory containing @blueprint.dhall@, or
-- 'ModuleNotFound' listing the directories that were searched. Mirrors
-- 'discoverModule' for callers that only care about discovering a
-- blueprint by name.
discoverBlueprint :: [FilePath] -> ModuleName -> IO (Either ModuleLoadError FilePath)
discoverBlueprint searchPaths name = go searchPaths
  where
    nameStr = T.unpack name.unModuleName
    go [] = pure $ Left (ModuleNotFound name searchPaths)
    go (dir : rest) = do
      let candidate = dir </> nameStr
      let dhallFile = candidate </> "blueprint.dhall"
      exists <- doesFileExist dhallFile
      if exists
        then pure (Right candidate)
        else go rest

-- | The three standard module search paths, in priority order:
-- 1. @.seihou/modules/@ relative to the current directory
-- 2. @~/.config/seihou/modules/@
-- 3. @~/.config/seihou/installed/@
defaultSearchPaths :: IO [FilePath]
defaultSearchPaths = do
  cwd <- getCurrentDirectory
  xdgConfig <- getXdgDirectory XdgConfig "seihou"
  pure
    [ cwd </> ".seihou" </> "modules",
      xdgConfig </> "modules",
      xdgConfig </> "installed"
    ]

-- | Validate a decoded 'Module' against the nine validation rules.
-- The 'FilePath' is the module's base directory (containing @module.dhall@).
-- Returns 'Right' with the module if all rules pass, or 'Left' with a
-- 'ValidationError' listing all violations.
validateModule :: FilePath -> Module -> IO (Either ModuleLoadError Module)
validateModule baseDir m = do
  fileErrors <- checkFileExistence baseDir m
  let pureErrors =
        checkNameFormat m
          <> checkVersionPresent m
          <> checkUniqueVars m
          <> checkPromptRefs m
          <> checkExportRefs m
          <> checkDependencyNames m
          <> checkDependencyVarBindings m
          <> checkSafeDestinations m
          <> checkDestVarRefs m
          <> checkCommandSafety m
      allErrors = pureErrors <> fileErrors
  pure $
    if null allErrors
      then Right m
      else Left (ValidationError m.name allErrors)

-- Rule 1: Module name must be non-empty and match [a-z][a-z0-9-]*
checkNameFormat :: Module -> [Text]
checkNameFormat m =
  let n = m.name.unModuleName
   in if T.null n || not (isValidModuleName n)
        then ["module name must match [a-z][a-z0-9-]*, got: " <> n]
        else []

isValidModuleName :: Text -> Bool
isValidModuleName t = case T.uncons t of
  Nothing -> False
  Just (c, rest) ->
    (c >= 'a' && c <= 'z')
      && T.all (\ch -> (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') || ch == '-') rest

-- Rule 1b: Module must declare a version
checkVersionPresent :: Module -> [Text]
checkVersionPresent m = case m.version of
  Nothing -> ["module must declare a version"]
  Just v
    | T.null (T.strip v) -> ["module must declare a version"]
    | otherwise -> []

-- Rule 2: All variable names must be unique
checkUniqueVars :: Module -> [Text]
checkUniqueVars m =
  let names = map (\d -> d.name.unVarName) m.vars
   in map (\n -> "duplicate variable name: " <> n) (findDupes Set.empty Set.empty names)

findDupes :: Set.Set Text -> Set.Set Text -> [Text] -> [Text]
findDupes _ _ [] = []
findDupes seen reported (x : xs)
  | Set.member x seen && not (Set.member x reported) = x : findDupes seen (Set.insert x reported) xs
  | otherwise = findDupes (Set.insert x seen) reported xs

-- Rule 3: Every prompt must reference a declared variable
checkPromptRefs :: Module -> [Text]
checkPromptRefs m =
  let varNames = Set.fromList (map (.name) m.vars)
   in concatMap
        ( \p ->
            if Set.member p.var varNames
              then []
              else ["prompt references undeclared variable: " <> p.var.unVarName]
        )
        m.prompts

-- Rule 4: Every step source file must exist in the module's files/ directory
checkFileExistence :: FilePath -> Module -> IO [Text]
checkFileExistence baseDir m =
  concat
    <$> mapM
      ( \s -> do
          let p = baseDir </> "files" </> s.src
          exists <- doesFileExist p
          pure $
            if exists
              then []
              else ["step source file not found: " <> T.pack s.src]
      )
      m.steps

-- Rule 5: Every export must reference a declared variable
checkExportRefs :: Module -> [Text]
checkExportRefs m =
  let varNames = Set.fromList (map (.name) m.vars)
   in concatMap
        ( \e ->
            if Set.member e.var varNames
              then []
              else ["export references undeclared variable: " <> e.var.unVarName]
        )
        m.exports

-- Rule 6: Every dependency name must be well-formed
checkDependencyNames :: Module -> [Text]
checkDependencyNames m =
  concatMap
    ( \dep ->
        let n = dep.depModule.unModuleName
         in if isValidModuleName n
              then []
              else ["invalid dependency name: " <> n]
    )
    m.dependencies

-- Rule 6b: Dependency var binding names must be non-empty
checkDependencyVarBindings :: Module -> [Text]
checkDependencyVarBindings m =
  concatMap
    ( \dep ->
        concatMap
          ( \(VarName vn) ->
              if T.null vn
                then ["dependency '" <> dep.depModule.unModuleName <> "' has empty var binding name"]
                else []
          )
          (Map.keys dep.depVars)
    )
    m.dependencies

-- Rule 7: Every step destination must be a safe relative path
checkSafeDestinations :: Module -> [Text]
checkSafeDestinations m = concatMap checkDest m.steps
  where
    checkDest s =
      case validateProjectRelativePath s.dest of
        Left err -> ["step destination " <> err]
        Right _ -> []

-- Rule 8: Variables referenced in step dest placeholders must be declared
checkDestVarRefs :: Module -> [Text]
checkDestVarRefs m =
  let varNames = Set.fromList (map (\d -> d.name.unVarName) m.vars)
   in concatMap (checkStep varNames) m.steps
  where
    checkStep varNames s =
      [ "step destination references undeclared variable: " <> ref
      | ref <- extractPlaceholders s.dest,
        not (Set.member ref varNames)
      ]

-- Rule 9: Command text must be non-empty and workDir must be safe
checkCommandSafety :: Module -> [Text]
checkCommandSafety m = concatMap checkCmd m.commands
  where
    checkCmd c = checkEmptyRun c <> checkWorkDir c.workDir

    checkEmptyRun c
      | T.null (T.strip c.run) = ["command text must not be empty"]
      | otherwise = []

    checkWorkDir Nothing = []
    checkWorkDir (Just wd) =
      case validateProjectRelativePath wd of
        Left err -> ["command workDir " <> err]
        Right _ -> []

-- | Extract placeholder variable references from a text like @"src/{{project.name}}/Main.hs"@.
extractPlaceholders :: Text -> [Text]
extractPlaceholders t = case T.breakOn "{{" t of
  (_, rest)
    | T.null rest -> []
    | otherwise ->
        let afterOpen = T.drop 2 rest
         in case T.breakOn "}}" afterOpen of
              (ref, rest')
                | T.null rest' -> []
                | otherwise -> T.strip ref : extractPlaceholders (T.drop 2 rest')

-- | Load a module by name: discover, evaluate, decode, and validate.
loadModule :: [FilePath] -> ModuleName -> IO (Either ModuleLoadError Module)
loadModule searchPaths name = do
  discovered <- discoverModule searchPaths name
  case discovered of
    Left err -> pure (Left err)
    Right moduleDir -> do
      let dhallFile = moduleDir </> "module.dhall"
      decoded <- evalModuleFromFile dhallFile
      case decoded of
        Left err -> pure (Left err)
        Right m -> validateModule moduleDir m

-- | Which search path category a module was found in.
data ModuleSource = SourceProject | SourceUser | SourceInstalled
  deriving stock (Eq, Show, Generic)

-- | A module discovered during enumeration, with its load result and source.
data DiscoveredModule = DiscoveredModule
  { discoveredResult :: Either ModuleLoadError Module,
    discoveredSource :: ModuleSource,
    discoveredDir :: FilePath
  }
  deriving stock (Show)

-- | Enumerate all modules across the given search paths.
-- The search paths must be in the same order as 'defaultSearchPaths':
-- project-local, user, installed. Each subdirectory containing a
-- @module.dhall@ file is loaded; failures are captured in 'discoveredResult'.
discoverAllModules :: [FilePath] -> IO [DiscoveredModule]
discoverAllModules searchPaths = do
  let tagged = zip searchPaths (sources ++ repeat SourceInstalled)
  concat <$> mapM (uncurry scanPath) tagged
  where
    sources = [SourceProject, SourceUser, SourceInstalled]

    scanPath :: FilePath -> ModuleSource -> IO [DiscoveredModule]
    scanPath dir src = do
      exists <- doesDirectoryExist dir
      if not exists
        then pure []
        else do
          entries <- listDirectory dir
          candidates <- filterM (isModuleDir dir) entries
          mapM (loadOne dir src) candidates

    isModuleDir :: FilePath -> FilePath -> IO Bool
    isModuleDir parent entry = do
      let candidate = parent </> entry </> "module.dhall"
      doesFileExist candidate

    filterM :: (a -> IO Bool) -> [a] -> IO [a]
    filterM _ [] = pure []
    filterM p (x : xs) = do
      keep <- p x
      rest <- filterM p xs
      pure (if keep then x : rest else rest)

    loadOne :: FilePath -> ModuleSource -> FilePath -> IO DiscoveredModule
    loadOne dir src entry = do
      let moduleDir = dir </> entry
          dhallFile = moduleDir </> "module.dhall"
      decoded <- evalModuleFromFile dhallFile
      result <- case decoded of
        Left err -> pure (Left err)
        Right m -> validateModule moduleDir m
      pure DiscoveredModule {discoveredResult = result, discoveredSource = src, discoveredDir = moduleDir}

-- | Whether a discovered item is a module, a recipe, or a blueprint.
data RunnableKind = KindModule | KindRecipe | KindBlueprint
  deriving stock (Eq, Show, Generic)

-- | A module or recipe discovered during enumeration, with its load result, kind, and source.
data DiscoveredRunnable = DiscoveredRunnable
  { drName :: Text,
    drDescription :: Maybe Text,
    drKind :: RunnableKind,
    drSource :: ModuleSource,
    drDir :: FilePath,
    drIsError :: Bool,
    drError :: Maybe Text
  }
  deriving stock (Show)

-- | Enumerate all modules and recipes across the given search paths.
-- Returns a unified list of discovered items, each tagged with its kind.
discoverAllRunnables :: [FilePath] -> IO [DiscoveredRunnable]
discoverAllRunnables searchPaths = do
  let tagged = zip searchPaths (sources ++ repeat SourceInstalled)
  concat <$> mapM (uncurry scanRunnablePath) tagged
  where
    sources = [SourceProject, SourceUser, SourceInstalled]

    scanRunnablePath :: FilePath -> ModuleSource -> IO [DiscoveredRunnable]
    scanRunnablePath dir src = do
      exists <- doesDirectoryExist dir
      if not exists
        then pure []
        else do
          entries <- listDirectory dir
          concat <$> mapM (loadRunnable dir src) entries

    loadRunnable :: FilePath -> ModuleSource -> FilePath -> IO [DiscoveredRunnable]
    loadRunnable dir src entry = do
      let entryDir = dir </> entry
          moduleDhall = entryDir </> "module.dhall"
          recipeDhall = entryDir </> "recipe.dhall"
          blueprintDhall = entryDir </> "blueprint.dhall"
      isModule <- doesFileExist moduleDhall
      isRecipe <- doesFileExist recipeDhall
      isBlueprint <- doesFileExist blueprintDhall
      if isModule
        then do
          decoded <- evalModuleFromFile moduleDhall
          pure
            [ case decoded of
                Left err ->
                  DiscoveredRunnable
                    { drName = T.pack entry,
                      drDescription = Nothing,
                      drKind = KindModule,
                      drSource = src,
                      drDir = entryDir,
                      drIsError = True,
                      drError = Just (briefLoadError err)
                    }
                Right m ->
                  DiscoveredRunnable
                    { drName = m.name.unModuleName,
                      drDescription = m.description,
                      drKind = KindModule,
                      drSource = src,
                      drDir = entryDir,
                      drIsError = False,
                      drError = Nothing
                    }
            ]
        else
          if isRecipe
            then do
              decoded <- evalRecipeFromFile recipeDhall
              pure
                [ case decoded of
                    Left err ->
                      DiscoveredRunnable
                        { drName = T.pack entry,
                          drDescription = Nothing,
                          drKind = KindRecipe,
                          drSource = src,
                          drDir = entryDir,
                          drIsError = True,
                          drError = Just (briefLoadError err)
                        }
                    Right r ->
                      DiscoveredRunnable
                        { drName = r.name.unRecipeName,
                          drDescription = r.description,
                          drKind = KindRecipe,
                          drSource = src,
                          drDir = entryDir,
                          drIsError = False,
                          drError = Nothing
                        }
                ]
            else
              if isBlueprint
                then do
                  decoded <- evalBlueprintFromFile blueprintDhall
                  pure
                    [ case decoded of
                        Left err ->
                          DiscoveredRunnable
                            { drName = T.pack entry,
                              drDescription = Nothing,
                              drKind = KindBlueprint,
                              drSource = src,
                              drDir = entryDir,
                              drIsError = True,
                              drError = Just (briefLoadError err)
                            }
                        Right b ->
                          DiscoveredRunnable
                            { drName = b.name.unModuleName,
                              drDescription = b.description,
                              drKind = KindBlueprint,
                              drSource = src,
                              drDir = entryDir,
                              drIsError = False,
                              drError = Nothing
                            }
                    ]
                else pure []

    briefLoadError :: ModuleLoadError -> Text
    briefLoadError (DhallEvalError _ _) = "Dhall evaluation failed"
    briefLoadError (DhallDecodeError _ _) = "Dhall decode failed"
    briefLoadError (ValidationError _ _) = "validation failed"
    briefLoadError (ModuleNotFound _ _) = "not found"
    briefLoadError (MissingSourceFile _ _) = "missing source file"
    briefLoadError (CircularDependency _) = "circular dependency"
    briefLoadError (RegistryEvalError _ _) = "registry eval failed"
