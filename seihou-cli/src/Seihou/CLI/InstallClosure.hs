-- | Acquisition is completed and validated before any installed entry changes.
module Seihou.CLI.InstallClosure (installClosure, installClosureInto, stageClosuresInto, ClosureArtifact (..), normalizePayload, writeStagedText, publishStagedClosure, readContents) where

import Control.Exception (IOException, displayException, mask, onException, throwIO, try)
import Control.Monad (forM, forM_, unless, when)
import Data.Generics.Labels ()
import Data.IORef
import Data.List (find)
import Data.Map.Strict qualified as Map
import Data.Maybe (maybeToList)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.InstallShared
import Seihou.CLI.ValidateRecipeReport (recipeLoadErrorText)
import Seihou.Composition.RecipeChain (loadRecipeChain)
import Seihou.Core.AgentPrompt (validateAgentPrompt)
import Seihou.Core.ArtifactIdentity (normalizeOriginUrl)
import Seihou.Core.Blueprint (validateBlueprintForInstall)
import Seihou.Core.Module (validateModule)
import Seihou.Core.Recipe (validateRecipe, validateRecipeVersion)
import Seihou.Core.Registry
import Seihou.Core.Types
import Seihou.Dhall.Eval
import Seihou.Prelude
import System.Directory
import System.Exit (ExitCode (..))
import System.FilePath (isAbsolute, makeRelative, splitDirectories)
import System.IO.Temp (createTempDirectory, withSystemTempDirectory)
import System.Process (readProcessWithExitCode)

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

-- | Normalized artifacts in the caller-owned staging directory. No temporary
-- checkout paths escape; revision and provenance are captured before cleanup.
data ClosureArtifact = ClosureArtifact
  { name :: !Text,
    sourceUrl :: !Text,
    repoName :: !(Maybe Text),
    version :: !(Maybe Text),
    tags :: ![Text],
    sourceRevision :: !(Maybe Text),
    directory :: !FilePath
  }
  deriving stock (Eq, Show, Generic)

data Repo = Repo FilePath Text RepoContents

data ExpectedArtifact = AnyArtifact | ModuleArtifact | RecipeArtifact RecipeReference

data Requirement = Requirement Text (Maybe Text) ExpectedArtifact

moduleRequirements :: [Dependency] -> [Requirement]
moduleRequirements = map (\dep -> Requirement (dep ^. #module_ . #unModuleName) (dep ^. #source) ModuleArtifact)

-- | Roots are registry entries, or a name and directory for a single artifact.
-- All failures discovered across selected roots are reported before staging.
installClosure :: Bool -> FilePath -> Text -> [(Text, FilePath)] -> IO (Either Text ())
installClosure force rootDir recorded roots = do
  cache <- installedRoot
  installClosureInto cache force rootDir recorded roots

-- | Explicit cache root for isolated callers and concurrent tests.
installClosureInto :: FilePath -> Bool -> FilePath -> Text -> [(Text, FilePath)] -> IO (Either Text ())
installClosureInto cache force rootDir recorded roots =
  fmap (fmap (const ())) $
    stageClosuresInto True cache force [(rootDir, recorded, roots)]

-- | The acquisition planner is shared by install and read-only candidate work.
-- The caller chooses an isolated directory for previews; publication into the
-- real cache remains the accepting command's transaction.
stageClosuresInto :: Bool -> FilePath -> Bool -> [(FilePath, Text, [(Text, FilePath)])] -> IO (Either Text [ClosureArtifact])
stageClosuresInto report cache force groups = withSystemTempDirectory "seihou-closure" $ \tmp -> do
  rootRepos <- forM groups $ \(rootDir, recorded, roots) -> do
    contents <- readContents rootDir
    pure (Repo rootDir recorded contents, roots)
  repos <- newIORef (Map.fromList [(normalizeOriginUrl recorded, repo) | (repo@(Repo _ recorded _), _) <- rootRepos])
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
      visit active chain repo@(Repo repoDir origin _) name dir expectedArtifact = do
        let key = (normalizeOriginUrl origin, name)
            context = chain <> name <> " [" <> origin <> "]"
        unless (safeName name) $ failWith (context <> ": unsafe install name")
        when (key `elem` active) $ failWith (context <> ": dependency cycle")
        known <- readIORef nodes
        case Map.lookup name known of
          Just (other, _) | other /= fst key -> failWith (context <> ": conflicting sources for " <> name <> "; also required from " <> other)
          _ -> pure ()
        checkTree repoDir dir
        (file, deps, version) <- inspect dir expectedArtifact `withContext` context
        case Map.lookup name known of
          Just _ -> pure ()
          Nothing -> do
            modifyIORef' nodes (Map.insert name (fst key, context))
            -- Evaluate every declaration independently of generation bindings.
            forM_ deps $ \(Requirement depName source expected) -> do
              depRepo <- case source of
                Nothing -> pure repo
                Just src -> do
                  when (T.null (T.strip src) || "${" `T.isInfixOf` src) $ failWith (context <> ": invalid dependency source")
                  getRepo src `withContext` context
              depDir <- locate depRepo depName expected `withContext` context
              visit (key : active) (context <> " -> ") depRepo depName depDir expected
            let tags = case repo of
                  Repo _ _ (MultiModule reg) -> maybe [] (^. #tags) (find ((== name) . (^. #name . #unModuleName)) (entries reg))
                  _ -> []
                registry = case repo of
                  Repo _ _ (MultiModule reg) -> Just (reg ^. #repoName)
                  _ -> Nothing
            checkTree repoDir dir
            modifyIORef' ordered (++ [Entry name origin dir file version registry tags context])
  outcomes <- fmap concat $ forM rootRepos $ \(repo, roots) ->
    forM roots $ \(name, dir) -> try @IOException (visit [] "" repo name dir AnyArtifact)
  let repairs = T.concat ["\nRetry: seihou install " <> recorded <> T.concat [" --module " <> name | (name, _) <- roots] | (_, recorded, roots) <- groups]
  let errors = [T.pack (displayException e) | Left e <- outcomes]
  if not (null errors)
    then pure (Left (T.intercalate "\n" errors <> repairs))
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
              writeStagedText (stage </> (e ^. #entryFile)) definition
            -- Build metadata with the existing writer, entirely outside the cache.
            forM_ planned $ \e -> do
              let name = T.unpack (e ^. #entryName)
              _ <- installModuleDirInto (tmp </> "ready") False (tmp </> "stage" </> name) name (e ^. #entrySource) (e ^. #entryRegistry) (e ^. #entryVersion) (e ^. #entryTags)
              pure ()
            -- Validate every merged recipe against only this staged closure.
            -- No ambient cache entry can hide a missing or contradictory edge.
            forM_ planned $ \e -> when (e ^. #entryFile == "recipe.dhall") $ do
              let ready = tmp </> "ready"
                  dir = ready </> T.unpack (e ^. #entryName)
              recipe <- evalRecipeFromFile (dir </> "recipe.dhall") >>= decoded
              unless (recipe ^. #name . #unRecipeName == e ^. #entryName) $
                failWith ("Recipe descriptor name must match registry entry '" <> e ^. #entryName <> "'")
              _ <- loadRecipeChain tmp [ready] recipe dir >>= either (failWith . recipeLoadErrorText) pure
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
              when report $ do
                forM_ planned $ \e -> TIO.putStrLn $ "  Installed " <> (e ^. #entryName) <> " from " <> (e ^. #entrySource) <> if (e ^. #entryName) `elem` [name | (_, _, roots) <- groups, (name, _) <- roots] then " (selected)" else " (required)"
                TIO.putStrLn $ T.pack (show (length planned)) <> " entries installed; selected artifacts are ready."
              artifacts <- forM planned $ \e -> do
                revision <- try @IOException (readProcessWithExitCode "git" ["-C", e ^. #entryDir, "rev-parse", "HEAD"] "")
                pure
                  ( ClosureArtifact
                      (e ^. #entryName)
                      (e ^. #entrySource)
                      (e ^. #entryRegistry)
                      (e ^. #entryVersion)
                      (e ^. #entryTags)
                      (case revision of Right (ExitSuccess, out, _) -> Just (T.strip (T.pack out)); _ -> Nothing)
                      (cache </> T.unpack (e ^. #entryName))
                  )
              pure (Right artifacts)

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

locate :: Repo -> Text -> ExpectedArtifact -> IO FilePath
locate (Repo dir origin contents) name expected = case contents of
  MultiModule reg -> case find ((== name) . (^. #name . #unModuleName)) (allowedEntries reg) of
    Just entry -> do
      let candidate = dir </> (entry ^. #path)
      checkTree dir candidate
      pure candidate
    Nothing -> missing
  SingleModule _ -> do
    m <- evalModuleFromFile (dir </> "module.dhall") >>= decoded
    if m ^. #name . #unModuleName == name && isModule then pure dir else missing
  SingleRecipe _ -> do
    r <- evalRecipeFromFile (dir </> "recipe.dhall") >>= decoded
    if r ^. #name . #unRecipeName == name && isRecipe then pure dir else missing
  _ -> missing
  where
    allowedEntries reg = case expected of
      AnyArtifact -> entries reg
      ModuleArtifact -> reg ^. #modules
      RecipeArtifact _ -> reg ^. #recipes
    isModule = case expected of RecipeArtifact _ -> False; _ -> True
    isRecipe = case expected of ModuleArtifact -> False; _ -> True
    kind = case expected of RecipeArtifact _ -> "recipe"; ModuleArtifact -> "module"; AnyArtifact -> "artifact"
    missing = throwIO (userError (T.unpack (name <> " not found as a " <> kind <> " in " <> origin)))

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

inspect :: FilePath -> ExpectedArtifact -> IO (FilePath, [Requirement], Maybe Text)
inspect dir expected = do
  hasModule <- doesFileExist (dir </> "module.dhall")
  hasRecipe <- doesFileExist (dir </> "recipe.dhall")
  case expected of
    ModuleArtifact | not hasModule -> wrong "module"
    RecipeArtifact _ | not hasRecipe -> wrong "recipe"
    _ -> pure ()
  case expected of
    RecipeArtifact ref -> recipe (Just ref)
    _ | hasModule -> do
      m <- evalModuleFromFile (dir </> "module.dhall") >>= decoded
      _ <- validateModule dir m >>= decoded
      pure ("module.dhall", moduleRequirements (m ^. #dependencies), m ^. #version)
    _ | hasRecipe -> recipe Nothing
    _ -> do
      blueprint <- doesFileExist (dir </> "blueprint.dhall")
      if blueprint
        then do
          b <- evalBlueprintFromFile (dir </> "blueprint.dhall") >>= decoded
          _ <- validateBlueprintForInstall dir b >>= decoded
          pure ("blueprint.dhall", moduleRequirements (b ^. #baseModules), b ^. #version)
        else do
          p <- evalAgentPromptFromFile (dir </> "prompt.dhall") >>= decoded
          _ <- validateAgentPrompt dir p >>= decoded
          pure ("prompt.dhall", [], p ^. #version)
  where
    wrong kind = throwIO (userError ("Expected " <> kind <> " at " <> dir))
    recipe requirement = do
      r <- evalRecipeFromFile (dir </> "recipe.dhall") >>= decoded
      _ <- decoded (validateRecipe r)
      forM_ requirement $ \ref -> decoded (validateRecipeVersion ref r)
      let base = [Requirement (ref ^. #recipe . #unRecipeName) (ref ^. #source) (RecipeArtifact ref) | ref <- maybeToList (r ^. #extends)]
      pure ("recipe.dhall", base <> moduleRequirements (r ^. #modules), r ^. #version)

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
      else when (".dhall" `T.isSuffixOf` T.pack name) $ normalizeDhallFile src >>= writeStagedText dst

-- | Normalization replaces only disposable staging bytes. A copied source may
-- be read-only (including immutable schema imports); do not change its original
-- permissions or lose executable bits merely to write the normalized copy.
writeStagedText :: FilePath -> Text -> IO ()
writeStagedText destination content = do
  permissions <- getPermissions destination
  setPermissions destination (setOwnerWritable True permissions)
  TIO.writeFile destination content

-- | Publish already validated staged bytes atomically across cache entries on
-- handled failures. No acquisition or project writes occur here.
publishStagedClosure :: FilePath -> [ClosureArtifact] -> IO (Either Text ())
publishStagedClosure cache artifacts = do
  collisions <- forM artifacts $ \artifact -> classifyInstallCollision (cache </> T.unpack (artifact ^. #name)) (artifact ^. #sourceUrl)
  let refused = [formatInstallRefusal (T.unpack (artifact ^. #name)) (artifact ^. #sourceUrl) collision | (artifact, collision) <- zip artifacts collisions, blocked collision]
  if not (null refused)
    then pure (Left (T.intercalate "\n" refused))
    else do
      result <- try @IOException $ do
        createDirectoryIfMissing True cache
        transaction <- createTempDirectory cache ".seihou-transaction"
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
          ( forM_ (zip artifacts collisions) $ \(artifact, collision) -> do
              let name = T.unpack (artifact ^. #name)
                  dest = cache </> name
                  backup = transaction </> name
              current <- classifyInstallCollision dest (artifact ^. #sourceUrl)
              unless (current == collision) $ throwIO (userError "Install cache changed during recipe upgrade; retry the same upgrade command.")
              exists <- doesDirectoryExist dest
              when exists (renameDirectory dest backup)
              modifyIORef' changed ((dest, backup, exists) :)
              restore $ do
                createDirectoryIfMissing True dest
                copyDirectoryRecursive (artifact ^. #directory) dest
          )
            `onException` rollback
        removeDirectoryRecursive transaction
      pure (first (T.pack . displayException) result)
