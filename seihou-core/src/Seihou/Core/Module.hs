module Seihou.Core.Module
  ( discoverModule,
    defaultSearchPaths,
    validateModule,
    loadModule,
    discoverAllModules,
    DiscoveredModule (..),
    ModuleSource (..),

    -- * Individual check functions (for structured reports)
    checkNameFormat,
    checkUniqueVars,
    checkPromptRefs,
    checkFileExistence,
    checkExportRefs,
    checkDependencyNames,
    checkSafeDestinations,
    checkDestVarRefs,
    checkCommandSafety,
    isValidModuleName,
    extractPlaceholders,
  )
where

import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import GHC.Generics (Generic)
import Seihou.Core.Types
import Seihou.Dhall.Eval (evalModuleFromFile)
import System.Directory (XdgDirectory (..), doesDirectoryExist, doesFileExist, getCurrentDirectory, getXdgDirectory, listDirectory)
import System.FilePath ((</>))

-- | Search for a module by name in the given directories.
-- Returns the path to the directory containing @module.dhall@, or
-- 'ModuleNotFound' listing the directories that were searched.
discoverModule :: [FilePath] -> ModuleName -> IO (Either ModuleLoadError FilePath)
discoverModule searchPaths name = go searchPaths
  where
    nameStr = T.unpack (unModuleName name)
    go [] = pure $ Left (ModuleNotFound name searchPaths)
    go (dir : rest) = do
      let candidate = dir </> nameStr
      let dhallFile = candidate </> "module.dhall"
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
          <> checkUniqueVars m
          <> checkPromptRefs m
          <> checkExportRefs m
          <> checkDependencyNames m
          <> checkSafeDestinations m
          <> checkDestVarRefs m
          <> checkCommandSafety m
      allErrors = pureErrors <> fileErrors
  pure $
    if null allErrors
      then Right m
      else Left (ValidationError (moduleName m) allErrors)

-- Rule 1: Module name must be non-empty and match [a-z][a-z0-9-]*
checkNameFormat :: Module -> [Text]
checkNameFormat m =
  let name = unModuleName (moduleName m)
   in if T.null name || not (isValidModuleName name)
        then ["module name must match [a-z][a-z0-9-]*, got: " <> name]
        else []

isValidModuleName :: Text -> Bool
isValidModuleName t = case T.uncons t of
  Nothing -> False
  Just (c, rest) ->
    (c >= 'a' && c <= 'z')
      && T.all (\ch -> (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') || ch == '-') rest

-- Rule 2: All variable names must be unique
checkUniqueVars :: Module -> [Text]
checkUniqueVars m =
  let names = map (unVarName . varName) (moduleVars m)
   in map (\n -> "duplicate variable name: " <> n) (findDupes Set.empty Set.empty names)

findDupes :: Set.Set Text -> Set.Set Text -> [Text] -> [Text]
findDupes _ _ [] = []
findDupes seen reported (x : xs)
  | Set.member x seen && not (Set.member x reported) = x : findDupes seen (Set.insert x reported) xs
  | otherwise = findDupes (Set.insert x seen) reported xs

-- Rule 3: Every prompt must reference a declared variable
checkPromptRefs :: Module -> [Text]
checkPromptRefs m =
  let varNames = Set.fromList (map varName (moduleVars m))
   in concatMap
        ( \p ->
            if Set.member (promptVar p) varNames
              then []
              else ["prompt references undeclared variable: " <> unVarName (promptVar p)]
        )
        (modulePrompts m)

-- Rule 4: Every step source file must exist in the module's files/ directory
checkFileExistence :: FilePath -> Module -> IO [Text]
checkFileExistence baseDir m =
  concat
    <$> mapM
      ( \s -> do
          let path = baseDir </> "files" </> stepSrc s
          exists <- doesFileExist path
          pure $
            if exists
              then []
              else ["step source file not found: " <> T.pack (stepSrc s)]
      )
      (moduleSteps m)

-- Rule 5: Every export must reference a declared variable
checkExportRefs :: Module -> [Text]
checkExportRefs m =
  let varNames = Set.fromList (map varName (moduleVars m))
   in concatMap
        ( \e ->
            if Set.member (exportVar e) varNames
              then []
              else ["export references undeclared variable: " <> unVarName (exportVar e)]
        )
        (moduleExports m)

-- Rule 6: Every dependency name must be well-formed
checkDependencyNames :: Module -> [Text]
checkDependencyNames m =
  concatMap
    ( \dep ->
        let name = unModuleName dep
         in if isValidModuleName name
              then []
              else ["invalid dependency name: " <> name]
    )
    (moduleDependencies m)

-- Rule 7: Every step destination must be a safe relative path
checkSafeDestinations :: Module -> [Text]
checkSafeDestinations m =
  concatMap
    ( \s ->
        let dest = stepDest s
         in if T.isPrefixOf "/" dest
              then ["step destination must be relative: " <> dest]
              else
                if ".." `T.isInfixOf` dest
                  then ["step destination must not contain '..': " <> dest]
                  else []
    )
    (moduleSteps m)

-- Rule 8: Variables referenced in step dest placeholders must be declared
checkDestVarRefs :: Module -> [Text]
checkDestVarRefs m =
  let varNames = Set.fromList (map (unVarName . varName) (moduleVars m))
   in concatMap
        ( \s ->
            let refs = extractPlaceholders (stepDest s)
             in concatMap
                  ( \ref ->
                      if Set.member ref varNames
                        then []
                        else ["step destination references undeclared variable: " <> ref]
                  )
                  refs
        )
        (moduleSteps m)

-- Rule 9: Command text must be non-empty and workDir must be safe
checkCommandSafety :: Module -> [Text]
checkCommandSafety m =
  concatMap
    ( \c ->
        let emptyRun =
              if T.null (T.strip (cmdRun c))
                then ["command text must not be empty"]
                else []
            unsafeWorkDir = case cmdWorkDir c of
              Nothing -> []
              Just wd
                | T.isPrefixOf "/" wd -> ["command workDir must be relative: " <> wd]
                | ".." `T.isInfixOf` wd -> ["command workDir must not contain '..': " <> wd]
                | otherwise -> []
         in emptyRun <> unsafeWorkDir
    )
    (moduleCommands m)

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
