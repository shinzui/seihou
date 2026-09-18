-- | Find an artifact exactly as it was when it declared a recorded version,
-- in the git history of its recorded origin.
--
-- Certifying a shared path compiles every co-owner from the version the
-- manifest records. The install cache holds one version per name, normally
-- the newest, so as soon as a co-owner is upgraded on this machine its
-- recorded release is no longer installed. This module recovers that
-- release from the recorded remote instead: it clones the repository into a
-- caller-owned session directory and finds the newest commit at which an
-- artifact of the recorded name declares the recorded version.
--
-- The release is identified by content, not by tag. The main module
-- registry has no tags, but every commit's definition file states its
-- @version@, which is exactly what the manifest records. Among the commits
-- that declare it, the newest is the author's final word on that version.
--
-- Nothing here writes outside the session directory, and the install cache
-- is never consulted or changed
-- (docs\/adr\/0006-the-install-cache-will-not-silently-substitute-an-artifact.md).
-- Only the exact recorded version is ever returned; another version is not
-- a substitute for it
-- (docs\/adr\/0003-a-stale-or-substituted-artifact-is-a-hard-error.md).
module Seihou.CLI.RecordedRelease
  ( RecordedRelease (..),
    RecordedReleaseError (..),
    RevisionSearch (..),
    locateRecordedRelease,
    chooseRevision,
    planRevisionSearch,
    renderRecordedReleaseError,
  )
where

import Data.Containers.ListUtils (nubOrd)
import Data.Generics.Labels ()
import Data.List (find)
import Data.Maybe (fromMaybe, listToMaybe, mapMaybe)
import Data.Set qualified as Set
import Data.Text qualified as T
import Seihou.Core.ArtifactIdentity (normalizeOriginUrl)
import Seihou.Core.Registry (RepoContents (..), discoverRepoContents)
import Seihou.Core.Types (Module (..), ModuleName (..), Recipe (..), RecipeName (..), SHA256 (..))
import Seihou.Dhall.Eval (evalModuleFromFile, evalRecipeFromFile, evalRegistryFromFile)
import Seihou.Manifest.Hash (hashContent)
import Seihou.Prelude
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, doesFileExist)
import System.Environment (getEnvironment)
import System.Exit (ExitCode (..))
import System.FilePath (makeRelative, takeFileName)
import System.Process (CreateProcess (..), proc, readCreateProcessWithExitCode)

-- | An artifact's recorded release, checked out in the session directory.
data RecordedRelease = RecordedRelease
  { -- | The artifact's own directory, holding its definition file.
    directory :: !FilePath,
    -- | The short id of the commit it was read at.
    revision :: !Text
  }
  deriving stock (Eq, Show, Generic)

-- | Why a recorded release could not be found.
data RecordedReleaseError
  = -- | The origin could not be cloned: the URL and git's message.
    RecordedReleaseCloneFailed !Text !Text
  | -- | No commit declares the artifact at the version: the URL, the
    --   artifact name, the version, and how many revisions were searched.
    RecordedReleaseNotFound !Text !Text !Text !Int
  | -- | A git command other than the clone failed: what was being done, and
    --   git's message.
    RecordedReleaseGitFailed !Text !Text
  deriving stock (Eq, Show, Generic)

-- | Which revisions to evaluate.
data RevisionSearch
  = -- | These revisions, found by searching for the version literal.
    SearchRevisions ![Text]
  | -- | The literal never appears, so the version is computed rather than
    --   written out: walk recent history instead.
    WalkRecentHistory
  deriving stock (Eq, Show, Generic)

-- | How many commits the fallback walk evaluates at most.
historyWalkLimit :: Int
historyWalkLimit = 200

-- | Decide which revisions to evaluate from the commits whose count of the
-- version literal changed, each with its first parent, and the tip.
--
-- A commit that introduces the literal may be the newest to declare it; one
-- that removes it has the newest declaring commit as its parent; and a
-- version still current is declared at the tip. Those are all the places
-- the newest declaring commit can be. No hit at all means the literal is
-- not written anywhere, so a narrowed search cannot find it.
planRevisionSearch :: Text -> [(Text, Maybe Text)] -> RevisionSearch
planRevisionSearch tip hits
  | null hits = WalkRecentHistory
  | otherwise = SearchRevisions (nubOrd (tip : concat [commit : maybe [] pure parent | (commit, parent) <- hits]))

-- | The first revision, newest first, that declares the version.
chooseRevision :: Text -> [(Text, Maybe Text)] -> Maybe Text
chooseRevision version = fmap fst . find (declares version . snd)

declares :: Text -> Maybe Text -> Bool
declares version declared = declared == Just version

-- | Locate the release of @name@ that declares @version@ in the repository
-- at @url@, cloning it into @session@ if this session has not already.
locateRecordedRelease ::
  -- | Session directory; everything is written below it.
  FilePath ->
  -- | Origin URL.
  Text ->
  -- | Artifact name.
  Text ->
  -- | Definition file, @module.dhall@ or @recipe.dhall@.
  FilePath ->
  -- | Recorded version.
  Text ->
  IO (Either RecordedReleaseError RecordedRelease)
locateRecordedRelease session url name definitionFile version = do
  cloned <- cloneForHistory session url
  case cloned of
    Left err -> pure (Left err)
    Right clone -> do
      tip <- git ["-C", clone, "rev-parse", "HEAD"]
      case T.strip <$> tip of
        Left err -> pure (Left (RecordedReleaseGitFailed "read the default branch" err))
        Right tipRevision -> do
          -- Where the artifact lives now narrows the search to its own
          -- definition file. The tip is always a candidate, so this
          -- evaluation is reused rather than repeated.
          atTip <- declaredAt session clone name definitionFile tipRevision
          case atTip of
            Left err -> pure (Left err)
            Right located -> do
              let scope = (\(directory, _) -> makeRelative (worktreeFor session clone tipRevision) directory) <$> located
              candidates <- candidateRevisions clone tipRevision version (fmap (</> definitionFile) scope) scope
              case candidates of
                Left err -> pure (Left err)
                Right revisions -> search clone revisions (0 :: Int)
  where
    search _ [] searched = pure (Left (RecordedReleaseNotFound url name version searched))
    search clone (revision : rest) searched = do
      evaluated <- declaredAt session clone name definitionFile revision
      case evaluated of
        Left err -> pure (Left err)
        Right (Just (directory, declared))
          | chooseRevision version [(revision, declared)] == Just revision ->
              pure (Right RecordedRelease {directory, revision = T.take 7 revision})
        Right _ -> search clone rest (searched + 1)

-- | A blobless clone of @url@ with full history, shared by every lookup in
-- the session that names the same origin.
cloneForHistory :: FilePath -> Text -> IO (Either RecordedReleaseError FilePath)
cloneForHistory session url = do
  let key = T.take 16 (hashContent (normalizeOriginUrl url) ^. #unSHA256)
      clone = releasesRoot session </> T.unpack ("clone-" <> key)
  existing <- doesDirectoryExist clone
  if existing
    then pure (Right clone)
    else do
      createDirectoryIfMissing True (releasesRoot session)
      -- Servers and local paths that ignore the filter fall back to a full
      -- clone, which is slower but equally correct.
      result <- git ["clone", "--filter=blob:none", "--no-checkout", "--quiet", T.unpack url, clone]
      pure (either (Left . RecordedReleaseCloneFailed url) (const (Right clone)) result)

-- | Revisions to evaluate, newest first.
--
-- With the artifact's current definition file and directory known, the
-- literal is searched only in that file and the fallback walk only visits
-- commits that touch that directory. Without them, which happens when the
-- default branch no longer holds the artifact, every Dhall file and every
-- commit is in scope.
--
-- Newest means topological order, children before parents, so commits made
-- within the same second still come out in the order they were made.
candidateRevisions :: FilePath -> Text -> Text -> Maybe FilePath -> Maybe FilePath -> IO (Either RecordedReleaseError [Text])
candidateRevisions clone tip version definitionPath artifactPath = do
  hits <-
    git
      ( ["-C", clone, "log", "--all", "--format=%H %P", "-S\"" <> T.unpack version <> "\"", "--"]
          <> [fromMaybe "*.dhall" definitionPath]
      )
  history <- git ["-C", clone, "rev-list", "--all", "--topo-order"]
  case (,) <$> hits <*> history of
    Left err -> pure (Left (RecordedReleaseGitFailed "search the history" err))
    Right (hitText, historyText) ->
      case planRevisionSearch tip (mapMaybe parseHit (T.lines hitText)) of
        WalkRecentHistory ->
          either (Left . RecordedReleaseGitFailed "list the history") (Right . T.lines)
            <$> git
              ( ["-C", clone, "rev-list", "--all", "--topo-order", "-n", show historyWalkLimit]
                  <> maybe [] (\path -> ["--", path]) artifactPath
              )
        SearchRevisions revisions ->
          let wanted = Set.fromList revisions
           in pure (Right (filter (`Set.member` wanted) (T.lines historyText)))
  where
    parseHit line = case T.words line of
      commit : parents -> Just (commit, listToMaybe parents)
      [] -> Nothing

-- | Check a revision out and read the declared version of the named
-- artifact there, with the artifact's directory. 'Nothing' when the
-- revision holds no such artifact or its definition does not evaluate.
declaredAt :: FilePath -> FilePath -> Text -> FilePath -> Text -> IO (Either RecordedReleaseError (Maybe (FilePath, Maybe Text)))
declaredAt session clone name definitionFile revision = do
  -- One worktree per commit, shared by every lookup in the session that
  -- visits it, and left in place: the whole session is removed at the end.
  let worktree = worktreeFor session clone revision
  existing <- doesDirectoryExist worktree
  added <-
    if existing
      then pure (Right "")
      else git ["-C", clone, "worktree", "add", "--detach", "--quiet", worktree, T.unpack revision]
  case added of
    Left err -> pure (Left (RecordedReleaseGitFailed ("check out " <> T.take 7 revision) err))
    Right _ -> do
      located <- artifactDirectory worktree name definitionFile
      case located of
        Nothing -> pure (Right Nothing)
        Just directory -> do
          declared <- declaredIdentity (directory </> definitionFile)
          pure $ Right $ case declared of
            Just (declaredName, declaredVersion) | declaredName == name -> Just (directory, declaredVersion)
            _ -> Nothing

-- | Where a checked-out repository keeps the named artifact.
artifactDirectory :: FilePath -> Text -> FilePath -> IO (Maybe FilePath)
artifactDirectory root name definitionFile = do
  contents <- discoverRepoContents evalRegistryFromFile root
  case contents of
    MultiModule registry ->
      let entries
            | definitionFile == "recipe.dhall" = registry ^. #recipes
            | otherwise = registry ^. #modules
       in case find ((== name) . (^. #name . #unModuleName)) entries of
            Just entry -> existingDefinition (root </> (entry ^. #path))
            Nothing -> pure Nothing
    _ -> existingDefinition root
  where
    existingDefinition directory = do
      present <- doesFileExist (directory </> definitionFile)
      pure (if present then Just directory else Nothing)

-- | The name and version a definition file declares.
declaredIdentity :: FilePath -> IO (Maybe (Text, Maybe Text))
declaredIdentity path
  | takeFileName path == "recipe.dhall" =
      either (const Nothing) (\recipe -> Just (recipe ^. #name . #unRecipeName, recipe ^. #version))
        <$> evalRecipeFromFile path
  | otherwise =
      either (const Nothing) (\modul -> Just (modul ^. #name . #unModuleName, modul ^. #version))
        <$> evalModuleFromFile path

-- | Where a commit of a clone is checked out. The clone's name keeps two
-- origins' identical commits apart.
worktreeFor :: FilePath -> FilePath -> Text -> FilePath
worktreeFor session clone revision =
  releasesRoot session </> ("wt-" <> takeFileName clone <> "-" <> T.unpack revision)

releasesRoot :: FilePath -> FilePath
releasesRoot session = session </> "recorded-releases"

-- | Run git without ever prompting: a remote that wants credentials fails
-- like any other unreachable remote.
git :: [String] -> IO (Either Text Text)
git arguments = do
  inherited <- getEnvironment
  let environment = ("GIT_TERMINAL_PROMPT", "0") : filter ((/= "GIT_TERMINAL_PROMPT") . fst) inherited
  (exitCode, out, err) <- readCreateProcessWithExitCode ((proc "git" arguments) {env = Just environment}) ""
  pure $ case exitCode of
    ExitSuccess -> Right (T.pack out)
    ExitFailure _ -> Left (T.strip (T.pack err))

-- | One sentence, suitable as the tail of a certification gap.
renderRecordedReleaseError :: RecordedReleaseError -> Text
renderRecordedReleaseError = \case
  RecordedReleaseCloneFailed url err ->
    "its recorded origin " <> url <> " could not be cloned (" <> firstLine err <> ")"
  RecordedReleaseNotFound url name version searched ->
    "no commit of "
      <> url
      <> " declares "
      <> name
      <> " "
      <> version
      <> " (searched "
      <> T.pack (show searched)
      <> (if searched == 1 then " revision)" else " revisions)")
  RecordedReleaseGitFailed what err ->
    "git could not " <> what <> " of its recorded origin (" <> firstLine err <> ")"
  where
    firstLine text = case T.lines text of
      line : _ -> line
      [] -> "no message"
