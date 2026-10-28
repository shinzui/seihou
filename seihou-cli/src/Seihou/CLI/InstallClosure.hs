-- | Acquisition is completed and validated before any installed entry changes.
module Seihou.CLI.InstallClosure (installClosure, installClosureInto) where

import Control.Exception (IOException, displayException, mask, onException, throwIO, try)
import Control.Monad (forM, forM_, unless, when)
import Data.Generics.Labels ()
import Data.IORef
import Data.List (find)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.InstallShared
import Seihou.Core.AgentPrompt (validateAgentPrompt)
import Seihou.Core.ArtifactIdentity (normalizeOriginUrl)
import Seihou.Core.Blueprint (validateBlueprintForInstall)
import Seihou.Core.Module (validateModule)
import Seihou.Core.Recipe (validateRecipe)
import Seihou.Core.Registry
import Seihou.Core.Types
import Seihou.Dhall.Eval
import Seihou.Prelude
import System.Directory
import System.FilePath (isAbsolute, makeRelative, splitDirectories)
import System.IO.Temp (createTempDirectory, withSystemTempDirectory)

-- Paths refer to temporary checkouts until every selected root passes preflight.
data Entry = Entry
  { entryName :: !Text,
    entrySource :: !Text,
    entryDir :: !FilePath,
    entryFile :: !FilePath,
    entryVersion :: !(Maybe Text),
    entryRegistry :: !(Maybe Text),
    entryTags :: ![Text],
    entryChain :: !Text
  }
  deriving stock (Generic)

data Repo = Repo FilePath Text RepoContents

-- | Roots are registry entries, or a name and directory for a single artifact.
-- All failures discovered across selected roots are reported before staging.
installClosure :: Bool -> FilePath -> Text -> [(Text, FilePath)] -> IO (Either Text ())
installClosure force rootDir recorded roots = do
  cache <- installedRoot
  installClosureInto cache force rootDir recorded roots

-- | Explicit cache root for isolated callers and concurrent tests.
installClosureInto :: FilePath -> Bool -> FilePath -> Text -> [(Text, FilePath)] -> IO (Either Text ())
installClosureInto cache force rootDir recorded roots = withSystemTempDirectory "seihou-closure" $ \tmp -> do
  repos <- newIORef Map.empty
  contents <- readContents rootDir
  modifyIORef' repos (Map.insert (normalizeOriginUrl recorded) (Repo rootDir recorded contents))
  nodes <- newIORef Map.empty
  ordered <- newIORef []
  let failWith = throwIO . userError . T.unpack
      getRepo source = do
        known <- readIORef repos
        case Map.lookup (normalizeOriginUrl source) known of
          Just repo -> pure repo
          Nothing -> do
            let dir = tmp </> ("repo-" ++ show (Map.size known))
            cloneRepo source dir >>= either failWith pure
            origin <- recordedSourceUrl <$> resolveRecordedSource source
            discovered <- readContents dir
            let repo = Repo dir origin discovered
            modifyIORef' repos (Map.insert (normalizeOriginUrl source) repo . Map.insert (normalizeOriginUrl origin) repo)
            pure repo
      visit active chain repo@(Repo repoDir origin _) name dir mustBeModule = do
        let key = (normalizeOriginUrl origin, name)
            context = chain <> name <> " [" <> origin <> "]"
        unless (safeName name) $ failWith (context <> ": unsafe install name")
        when (key `elem` active) $ failWith (context <> ": dependency cycle")
        known <- readIORef nodes
        case Map.lookup name known of
          Just (other, _) | other /= fst key -> failWith (context <> ": conflicting sources for " <> name <> "; also required from " <> other)
          _ -> pure ()
        checkTree repoDir dir
        (file, deps, version) <- inspect dir mustBeModule `withContext` context
        case Map.lookup name known of
          Just _ -> pure ()
          Nothing -> do
            modifyIORef' nodes (Map.insert name (fst key, context))
            -- Evaluate every declaration independently of generation bindings.
            forM_ deps $ \dep -> do
              let depName = dep ^. #module_ . #unModuleName
              depRepo <- case dep ^. #source of
                Nothing -> pure repo
                Just src -> do
                  when (T.null (T.strip src) || "${" `T.isInfixOf` src) $ failWith (context <> ": invalid dependency source")
                  getRepo src `withContext` context
              depDir <- locate depRepo depName `withContext` context
              visit (key : active) (context <> " -> ") depRepo depName depDir True
            let tags = case repo of
                  Repo _ _ (MultiModule reg) -> maybe [] (^. #tags) (find ((== name) . (^. #name . #unModuleName)) (entries reg))
                  _ -> []
                registry = case repo of
                  Repo _ _ (MultiModule reg) -> Just (reg ^. #repoName)
                  _ -> Nothing
            checkTree repoDir dir
            modifyIORef' ordered (++ [Entry name origin dir file version registry tags context])
      rootRepo = Repo rootDir recorded contents
  outcomes <- forM roots $ \(name, dir) -> try @IOException (visit [] "" rootRepo name dir False)
  let errors = [T.pack (displayException e) | Left e <- outcomes]
  if not (null errors)
    then pure (Left (T.intercalate "\n" errors))
    else do
      planned <- readIORef ordered
      collisions <- forM planned $ \e -> classifyInstallCollision (cache </> T.unpack (e ^. #entryName)) (e ^. #entrySource)
      let refusals = [(e ^. #entryChain) <> "\n" <> formatInstallRefusal (T.unpack (e ^. #entryName)) (e ^. #entrySource) c | (e, c) <- zip planned collisions, blocked c, not force]
      if not (null refusals)
        then pure (Left (T.intercalate "\n" refusals))
        else do
          result <- try @IOException $ do
            -- Normalize all imports before the source checkouts disappear.
            forM_ planned $ \e -> do
              let stage = tmp </> "stage" </> T.unpack (e ^. #entryName)
              createDirectoryIfMissing True stage
              copyDirectoryRecursive (e ^. #entryDir) stage
              normalizePayload (e ^. #entryDir) stage (e ^. #entryFile)
              definition <- normalizeInstalledDefinition (e ^. #entrySource) ((e ^. #entryDir) </> (e ^. #entryFile))
              TIO.writeFile (stage </> (e ^. #entryFile)) definition
            -- Build metadata with the existing writer, entirely outside the cache.
            forM_ planned $ \e -> do
              let name = T.unpack (e ^. #entryName)
              _ <- installModuleDirInto (tmp </> "ready") False (tmp </> "stage" </> name) name (e ^. #entrySource) (e ^. #entryRegistry) (e ^. #entryVersion) (e ^. #entryTags)
              pure ()
            current <- forM planned $ \e -> classifyInstallCollision (cache </> T.unpack (e ^. #entryName)) (e ^. #entrySource)
            unless (current == collisions) $ failWith "Install cache changed during preparation; retry the same install command."
            createDirectoryIfMissing True cache
            -- Keep recovery data on the same filesystem as the destination.
            transaction <- createTempDirectory cache ".seihou-transaction"
            let commit = do
                  changed <- newIORef []
                  let rollback =
                        readIORef changed
                          >>= mapM_
                            ( \(dest, backup, existed) -> do
                                present <- doesDirectoryExist dest
                                when present (removeDirectoryRecursive dest)
                                when existed (renameDirectory backup dest)
                            )
                  mask $ \restore ->
                    ( forM_ (zip planned collisions) $ \(e, c) -> do
                        let name = T.unpack (e ^. #entryName)
                            dest = cache </> name
                            backup = transaction </> name
                        latest <- classifyInstallCollision dest (e ^. #entrySource)
                        unless (latest == c) $ failWith ("Install cache changed for " <> (e ^. #entryName) <> "; retry.")
                        when (blocked c) $ TIO.putStrLn (formatInstallOverride name (e ^. #entrySource) c)
                        exists <- doesDirectoryExist dest
                        when exists (renameDirectory dest backup)
                        modifyIORef' changed ((dest, backup, exists) :)
                        createDirectoryIfMissing True dest
                        restore (copyDirectoryRecursive (tmp </> "ready" </> name) dest)
                    )
                      `onException` rollback
            commit `onException` TIO.putStrLn ("Install failed; any retained recovery data is in " <> T.pack transaction)
            removeDirectoryRecursive transaction
          case result of
            Left e -> pure (Left (T.pack (displayException e)))
            Right () -> do
              forM_ planned $ \e -> TIO.putStrLn $ "  Installed " <> (e ^. #entryName) <> " from " <> (e ^. #entrySource) <> if (e ^. #entryName) `elem` map fst roots then " (selected)" else " (required)"
              TIO.putStrLn $ T.pack (show (length planned)) <> " entries installed; selected artifacts are ready."
              pure (Right ())

withContext :: IO a -> Text -> IO a
withContext action context = do
  result <- try @IOException action
  either (throwIO . userError . ((T.unpack context <> " -> ") <>) . displayException) pure result

blocked :: InstallCollision -> Bool
blocked (DifferentSource _) = True
blocked UnknownSource = True
blocked _ = False

safeName :: Text -> Bool
safeName name = not (T.null name) && name /= "." && name /= ".." && T.all (\c -> c /= '/' && c /= '\\' && c /= '\0') name

entries :: Registry -> [RegistryEntry]
entries reg = reg ^. #modules ++ reg ^. #recipes ++ reg ^. #blueprints ++ reg ^. #prompts

locate :: Repo -> Text -> IO FilePath
locate (Repo dir origin contents) name = case contents of
  MultiModule reg -> case find ((== name) . (^. #name . #unModuleName)) (entries reg) of
    Just entry -> do
      let candidate = dir </> (entry ^. #path)
      checkTree dir candidate
      pure candidate
    Nothing -> missing
  SingleModule _ -> do
    m <- evalModuleFromFile (dir </> "module.dhall") >>= decoded
    if m ^. #name . #unModuleName == name then pure dir else missing
  _ -> missing
  where
    missing = throwIO (userError (T.unpack (name <> " not found as a module in " <> origin)))

-- Reject escapes and symlinks rather than copying files from outside the clone.
checkTree :: FilePath -> FilePath -> IO ()
checkTree root candidate = do
  root' <- canonicalizePath root
  path <- canonicalizePath candidate
  let rel = makeRelative root' path
  when (isAbsolute rel || ".." `elem` splitDirectories rel) $ throwIO (userError ("Artifact path escapes repository: " <> candidate))
  walk candidate
  where
    walk path = do
      link <- pathIsSymbolicLink path
      when link $ throwIO (userError ("Symbolic links are not supported in installed payloads: " <> path))
      dir <- doesDirectoryExist path
      when dir $ listDirectory path >>= mapM_ (\name -> unless (name == ".git") (walk (path </> name)))

decoded :: (Show e) => Either e a -> IO a
decoded = either (throwIO . userError . show) pure

inspect :: FilePath -> Bool -> IO (FilePath, [Dependency], Maybe Text)
inspect dir mustBeModule = do
  hasModule <- doesFileExist (dir </> "module.dhall")
  if hasModule
    then do
      m <- evalModuleFromFile (dir </> "module.dhall") >>= decoded
      _ <- validateModule dir m >>= decoded
      pure ("module.dhall", m ^. #dependencies, m ^. #version)
    else
      if mustBeModule
        then throwIO (userError ("Expected module at " <> dir))
        else do
          recipe <- doesFileExist (dir </> "recipe.dhall")
          blueprint <- doesFileExist (dir </> "blueprint.dhall")
          if recipe
            then do
              r <- evalRecipeFromFile (dir </> "recipe.dhall") >>= decoded
              _ <- decoded (validateRecipe r)
              pure ("recipe.dhall", r ^. #modules, r ^. #version)
            else
              if blueprint
                then do
                  b <- evalBlueprintFromFile (dir </> "blueprint.dhall") >>= decoded
                  _ <- validateBlueprintForInstall dir b >>= decoded
                  pure ("blueprint.dhall", b ^. #baseModules, b ^. #version)
                else do
                  p <- evalAgentPromptFromFile (dir </> "prompt.dhall") >>= decoded
                  _ <- validateAgentPrompt dir p >>= decoded
                  pure ("prompt.dhall", [], p ^. #version)

-- A malformed registry must not silently fall back to a stray root module.
readContents :: FilePath -> IO RepoContents
readContents dir = do
  registry <- doesFileExist (dir </> "seihou-registry.dhall")
  if registry
    then MultiModule <$> (evalRegistryFromFile (dir </> "seihou-registry.dhall") >>= decoded)
    else discoverRepoContents evalRegistryFromFile dir

-- Dhall source files used by generation can also import siblings of an artifact.
normalizePayload :: FilePath -> FilePath -> FilePath -> IO ()
normalizePayload sourceDir stagedDir definition = do
  children <- listDirectory sourceDir
  forM_ children $ \name -> unless (name == ".git" || name == definition) $ do
    let src = sourceDir </> name
        dst = stagedDir </> name
    directory <- doesDirectoryExist src
    if directory
      then normalizePayload src dst ""
      else when (".dhall" `T.isSuffixOf` T.pack name) $ normalizeDhallFile src >>= TIO.writeFile dst
