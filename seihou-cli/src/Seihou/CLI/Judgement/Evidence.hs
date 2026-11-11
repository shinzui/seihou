-- | Complete, checked capture of the evidence a judgement reviews.
--
-- Staged evidence is read from the Git index only: the snapshot is derived
-- from indexed paths, modes and blob IDs, and blob contents come from the
-- object database, never the working tree. Every Git call is an argument
-- vector with NUL-delimited output, external diff and text conversion are
-- disabled, and a failed Git read is an error rather than empty evidence.
-- The index is never refreshed or written.
--
-- Unsupported content (binary, submodules, symlinks, LFS pointers, files over
-- the size limit) is reported as uncovered unless a path filter excludes it;
-- it never silently disappears from coverage.
module Seihou.CLI.Judgement.Evidence
  ( -- * Snapshots
    FileChange (..),
    EvidenceFile (..),
    Snapshot (..),
    captureStaged,
    captureRange,
    sourcePath,
    GitRunner,
    gitBytes,

    -- * Selection and rendering
    pathMatches,
    selectForDefinition,
    renderFile,
    Chunk (..),
    chunkEvidence,
    evidenceIndex,
  )
where

import Control.Exception (IOException, try)
import Control.Monad (forM)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.Generics.Labels ()
import Data.List (foldl', sortOn)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.Encoding.Error qualified as TEE
import Seihou.Core.Judgement
import Seihou.Core.Types (SHA256 (..))
import Seihou.Manifest.Hash (hashContent)
import Seihou.Prelude
import System.Exit (ExitCode (..))
import System.IO (hClose)
import System.Process qualified as P

data FileChange = Added | Modified | Deleted | TypeChanged
  deriving stock (Eq, Ord, Show, Bounded, Enum, Generic)

-- | One changed path with its before/after identity. Content is the
-- post-change bytes ('Nothing' for a deletion); 'before' holds the
-- pre-change bytes, which are scanned locally but never transmitted.
data EvidenceFile = EvidenceFile
  { path :: !FilePath,
    change :: !FileChange,
    mode :: !Text,
    beforeBlob :: !(Maybe Text),
    afterBlob :: !(Maybe Text),
    content :: !(Maybe ByteString),
    before :: !(Maybe ByteString),
    -- | For an intermediate version in a commit range, the commit that
    -- introduced it and the file's own path; 'path' is then
    -- @<path>\@<short commit>@ so each version is reviewed and cited apart.
    revision :: !(Maybe (Text, FilePath))
  }
  deriving stock (Eq, Show, Generic)

-- | The project path a file stands for, used for path filters.
sourcePath :: EvidenceFile -> FilePath
sourcePath f = maybe (f ^. #path) snd (f ^. #revision)

data Snapshot = Snapshot
  { scope :: !EvidenceScopeKind,
    -- | Digest of the ordered index paths, modes and blob IDs.
    identity :: !Text,
    files :: ![EvidenceFile],
    uncovered :: ![(FilePath, Text)]
  }
  deriving stock (Eq, Show, Generic)

-- | Run git with an argument vector in a directory, returning stdout bytes.
type GitRunner = [String] -> IO (Either Text ByteString)

-- | The production runner. Text conversion, external diff and pagers are
-- disabled for every call; ambient GIT_* overrides that would redirect the
-- index or object database are left to Git's own semantics for linked
-- worktrees.
gitBytes :: FilePath -> GitRunner
gitBytes dir args = do
  let cmd = (P.proc "git" (["-c", "core.quotePath=false", "-c", "diff.external=", "--no-pager"] <> args)) {P.cwd = Just dir, P.std_in = P.CreatePipe, P.std_out = P.CreatePipe, P.std_err = P.CreatePipe}
  attempted <- try $ P.withCreateProcess cmd $ \hin hout herr ph -> do
    mapM_ hClose hin
    out <- maybe (pure BS.empty) BS.hGetContents hout
    err <- maybe (pure BS.empty) BS.hGetContents herr
    code <- P.waitForProcess ph
    pure (code, out, err)
  pure $ case attempted of
    Left (e :: IOException) -> Left ("could not run git: " <> T.pack (show e))
    Right (ExitSuccess, out, _) -> Right out
    Right (ExitFailure n, _, err) -> Left ("git " <> T.pack (unwords (take 2 args)) <> " exited " <> T.pack (show n) <> ": " <> T.take 300 (decodeLenient err))

decodeLenient :: ByteString -> Text
decodeLenient = TE.decodeUtf8With TEE.lenientDecode

emptyTree :: String
emptyTree = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"

-- | Capture every change Git would commit from the current index.
captureStaged :: CoverageLimits -> GitRunner -> IO (Either Text Snapshot)
captureStaged limits git = do
  stage <- git ["ls-files", "--stage", "-z"]
  headRef <- git ["rev-parse", "--verify", "--quiet", "HEAD^{commit}"]
  let base = either (const emptyTree) (BC.unpack . BC.strip) headRef
  raw <- git ["diff-index", "--cached", "--raw", "-z", "--no-renames", "--full-index", "--no-ext-diff", "--no-textconv", base, "--"]
  case (stage, raw) of
    (Left e, _) -> pure (Left e)
    (_, Left e) -> pure (Left e)
    (Right stageOut, Right rawOut) -> do
      let entries = filter (not . BS.null) (BS.split 0 stageOut)
          unresolved = [p | e <- entries, let (meta, p) = BS.break (== 9) e, stageNumber meta /= "0", not (BS.null p)]
      if not (null unresolved)
        then pure (Left ("the index has unresolved merge entries: " <> T.intercalate ", " (map (decodeLenient . BS.drop 1) unresolved) <> "; resolve them before checking"))
        else do
          let identity = case hashContent (decodeLenient stageOut <> "\0" <> T.pack base) of SHA256 h -> h
          case parseRaw rawOut of
            Left e -> pure (Left e)
            Right changes -> do
              captured <- forM changes $ \(oldMode, newMode, oldSha, newSha, status, p) -> do
                let zero = T.all (== '0')
                    beforeId = if zero oldSha then Nothing else Just oldSha
                    afterId = if zero newSha then Nothing else Just newSha
                    change = case status of
                      "A" -> Added
                      "D" -> Deleted
                      "T" -> TypeChanged
                      _ -> Modified
                    m = if change == Deleted then oldMode else newMode
                afterBytes <- readBlobIf (supportedMode newMode) afterId
                beforeBytes <- readBlobIf (supportedMode oldMode) beforeId
                pure $ do
                  a <- afterBytes
                  b <- beforeBytes
                  Right (EvidenceFile p change m beforeId afterId a b Nothing)
              pure $ do
                fs <- sequence captured
                let cover f = (f, unsupported limits f)
                    judged = map cover fs
                Right
                  Snapshot
                    { scope = StagedChangesScope,
                      identity = identity,
                      files = [f | (f, Nothing) <- judged],
                      uncovered = [(f ^. #path, why) | (f, Just why) <- judged]
                    }
  where
    stageNumber meta = case BC.words meta of
      [_, _, s] -> s
      _ -> "?"
    readBlobIf ok = \case
      Just sha | ok -> fmap Just <$> git ["cat-file", "blob", T.unpack sha]
      _ -> pure (Right Nothing)

-- | Capture every change introduced by the commits in @BASE..HEAD@, not
-- merely the net difference: a file added and then removed inside the range
-- is still captured, so the scanner sees it. Both ends are resolved to
-- commits first, and the index and worktree are never read. Each commit is
-- compared with its first parent. The final version of each path keeps its
-- path; earlier distinct versions appear as @path\@<short commit>@.
captureRange :: CoverageLimits -> GitRunner -> Text -> Text -> IO (Either Text Snapshot)
captureRange limits git baseRef headRef = do
  resolved <- (,) <$> resolve baseRef <*> resolve headRef
  case resolved of
    (Left e, _) -> pure (Left e)
    (_, Left e) -> pure (Left e)
    (Right base, Right hd) -> do
      shallow <- git ["rev-parse", "--is-shallow-repository"]
      mergeBase <- git ["merge-base", base, hd]
      case (shallow, mergeBase) of
        (Right s, Left _)
          | BC.strip s == "true" ->
              pure (Left ("this clone is shallow and does not contain the history between " <> baseRef <> " and " <> headRef <> "; fetch it with git fetch --unshallow (or set fetch-depth: 0 in CI)"))
        _ ->
          git ["rev-list", "--reverse", "--topo-order", base <> ".." <> hd] >>= \case
            Left e -> pure (Left e)
            Right listing -> do
              let commits = map BC.unpack (filter (not . BS.null) (BC.lines listing))
              perCommit <- forM commits $ \c ->
                git ["diff-tree", "-r", "-z", "--raw", "--no-renames", "--full-index", "--no-ext-diff", "--no-textconv", "--no-commit-id", "--root", "--diff-merges=first-parent", c, "--"] >>= \case
                  Left e -> pure (Left e)
                  Right out -> pure (fmap (map (c,)) (parseRaw out))
              case sequence perCommit of
                Left e -> pure (Left e)
                Right nested -> do
                  let changes = concat nested
                      lastFor = foldl' (\m (c, (_, _, _, _, _, p)) -> Map.insert p c m) Map.empty changes
                      introduced = [(c, ch) | (c, ch@(_, _, _, ns, st, _)) <- changes, st /= "D", not (T.all (== '0') ns)]
                      distinct = Map.elems (Map.fromList [((p, ns), (c, ch)) | (c, ch@(_, _, _, ns, _, p)) <- introduced])
                  captured <- forM distinct $ \(c, (_, nm, os, ns, st, p)) -> do
                    bytes <- if supportedMode nm then fmap Just <$> git ["cat-file", "blob", T.unpack ns] else pure (Right Nothing)
                    let final = Map.lookup p lastFor == Just c
                        short = T.pack (take 7 c)
                        shown = if final then p else p <> "@" <> T.unpack short
                        change = case st of
                          "A" -> Added
                          "T" -> TypeChanged
                          _ -> Modified
                        beforeId = if T.all (== '0') os then Nothing else Just os
                    pure (fmap (\b -> EvidenceFile shown change nm beforeId (Just ns) b Nothing (if final then Nothing else Just (T.pack c, p))) bytes)
                  pure $ do
                    fs <- sequence captured
                    let judged = [(f, unsupported limits f) | f <- fs]
                        identity = case hashContent (T.pack (base <> ".." <> hd) <> "\0" <> T.intercalate "\0" [T.pack c <> " " <> ns <> " " <> T.pack p | (c, (_, _, _, ns, _, p)) <- changes]) of SHA256 h -> h
                    Right
                      Snapshot
                        { scope = CommitRangeScope,
                          identity = identity,
                          files = [f | (f, Nothing) <- judged],
                          uncovered = [(sourcePath f, why) | (f, Just why) <- judged]
                        }
  where
    resolve ref =
      git ["rev-parse", "--verify", "--quiet", T.unpack ref <> "^{commit}"] <&> \case
        Right out -> Right (BC.unpack (BC.strip out))
        Left _ -> Left ("'" <> ref <> "' does not name a commit in this clone; fetch it first (for example git fetch origin " <> ref <> ")")

supportedMode :: Text -> Bool
supportedMode m = m == "100644" || m == "100755"

-- | Why a captured file cannot be reviewed, if it cannot.
unsupported :: CoverageLimits -> EvidenceFile -> Maybe Text
unsupported limits f
  | f ^. #mode == "160000" = Just "submodules are not reviewed"
  | f ^. #mode == "120000" = Just "symlinks are not followed"
  | not (supportedMode (f ^. #mode)) && f ^. #change /= Deleted = Just ("unsupported file mode " <> f ^. #mode)
  | otherwise = case f ^. #content of
      Nothing -> Nothing
      Just bytes
        | BS.length bytes > limits ^. #maxFileBytes -> Just ("larger than the declared limit of " <> T.pack (show (limits ^. #maxFileBytes)) <> " bytes")
        | BS.elem 0 (BS.take 8000 bytes) -> Just "binary content is not supported"
        | "version https://git-lfs.github.com/spec/" `BS.isPrefixOf` bytes -> Just "Git LFS content is not supported"
        | otherwise -> Nothing

-- | Parse @git diff-index --raw -z --full-index@ output.
parseRaw :: ByteString -> Either Text [(Text, Text, Text, Text, Text, FilePath)]
parseRaw bytes = go (BS.split 0 bytes)
  where
    go [] = Right []
    go [x] | BS.null x = Right []
    go (meta : p : rest)
      | ":" `BS.isPrefixOf` meta,
        [om, nm, os, ns, st] <- BC.words (BS.drop 1 meta) =
          ((decodeLenient om, decodeLenient nm, decodeLenient os, decodeLenient ns, T.take 1 (decodeLenient st), T.unpack (decodeLenient p)) :) <$> go rest
    go other = Left ("unexpected git diff-index output near " <> T.take 80 (T.pack (show (take 2 other))))

-- ---------------------------------------------------------------------------
-- Selection

-- | Git-style glob over a project-relative path: @*@ and @?@ never match a
-- slash, @**@ matches any number of directories, and a pattern without a
-- slash matches the basename anywhere.
pathMatches :: Text -> FilePath -> Bool
pathMatches pat fp
  | "/" `T.isInfixOf` pat = matchSegs (T.splitOn "/" pat) segs
  | otherwise = any (glob (T.unpack pat)) segs
  where
    segs = T.splitOn "/" (T.pack fp)
    matchSegs [] [] = True
    matchSegs ["**"] _ = True
    matchSegs ("**" : ps) ss = any (matchSegs ps) (tailsOf ss)
    matchSegs (p : ps) (s : ss) = glob (T.unpack p) s && matchSegs ps ss
    matchSegs _ _ = False
    tailsOf xs =
      xs : case xs of
        [] -> []
        (_ : r) -> tailsOf r
    glob p s = globS p (T.unpack s)
    globS [] [] = True
    globS ('*' : ps) s = any (globS ps) (suffixes s)
    globS ('?' : ps) (_ : s) = globS ps s
    globS (c : ps) (x : s) = c == x && globS ps s
    globS _ _ = False
    suffixes s =
      s : case s of
        [] -> []
        (_ : r) -> suffixes r

-- | Apply a definition's include/exclude patterns. Returns the selected files
-- and the deliberately excluded paths, which are counted, never dropped.
selectForDefinition :: JudgementDefinition -> Snapshot -> ([EvidenceFile], [FilePath], [(FilePath, Text)])
selectForDefinition def snap =
  ( filter (selected . sourcePath) (snap ^. #files),
    [f ^. #path | f <- snap ^. #files, not (selected (sourcePath f))] <> [p | (p, _) <- snap ^. #uncovered, not (selected p)],
    [(p, why) | (p, why) <- snap ^. #uncovered, selected p]
  )
  where
    incl = def ^. #evidence . #include
    excl = def ^. #evidence . #exclude
    selected p = (null incl || any (`pathMatches` p) incl) && not (any (`pathMatches` p) excl)

-- ---------------------------------------------------------------------------
-- Rendering and chunking

renderChange :: FileChange -> Text
renderChange = \case
  Added -> "added"
  Modified -> "modified"
  Deleted -> "deleted"
  TypeChanged -> "type changed"

-- | The numbered post-change lines of a file, as the model sees them.
fileLines :: EvidenceFile -> [Text]
fileLines f = maybe [] (T.lines . decodeLenient) (f ^. #content)

renderFile :: EvidenceFile -> Text
renderFile f = renderSlice f 1 (fileLines f)

renderSlice :: EvidenceFile -> Int -> [Text] -> Text
renderSlice f start ls =
  T.unlines $
    ("== " <> T.pack (f ^. #path) <> " (" <> renderChange (f ^. #change) <> ")")
      : if f ^. #change == Deleted
        then ["(file deleted; its previous content is not sent)"]
        else zipWith (\n l -> T.pack (show n) <> " | " <> l) [start :: Int ..] ls

data Chunk = Chunk
  { index :: !Int,
    text :: !Text,
    paths :: ![FilePath]
  }
  deriving stock (Eq, Show, Generic)

-- | Pack files into chunks of at most 'maxChunkBytes', splitting a large
-- file by lines with its header repeated. Files that do not fit within
-- 'maxChunks' are returned as uncovered rather than truncated.
chunkEvidence :: CoverageLimits -> [EvidenceFile] -> ([Chunk], [(FilePath, Text)])
chunkEvidence limits files =
  let pieces = concatMap piecesOf (sortOn (^. #path) files)
      packed = reverse (map finish (foldl' pack [] pieces))
      (kept, dropped) = splitAt (limits ^. #maxChunks) packed
      keptPaths = concatMap (^. #paths) kept
      over = [(p, "did not fit within the declared limit of " <> T.pack (show (limits ^. #maxChunks)) <> " evidence chunks") | p <- dedupe (concatMap (^. #paths) dropped), p `notElem` keptPaths]
   in (zipWith (\i c -> c & #index .~ i) [0 ..] kept, over)
  where
    budget = limits ^. #maxChunkBytes
    size = BS.length . TE.encodeUtf8
    piecesOf f =
      let ls = fileLines f
          whole = renderFile f
       in if size whole <= budget || f ^. #change == Deleted
            then [(f ^. #path, whole)]
            else splitLines f 1 ls
    splitLines _ _ [] = []
    splitLines f start ls =
      let headerCost = size (renderSlice f start [])
          go acc n [] = (reverse acc, n, [])
          go acc n (l : rest)
            | n + size l + 8 > budget - headerCost && not (null acc) = (reverse acc, n, l : rest)
            | otherwise = go (l : acc) (n + size l + 8) rest
          (taken, _, rest) = go [] 0 ls
       in (f ^. #path, renderSlice f start taken) : splitLines f (start + length taken) rest
    pack [] (p, t) = [(size t, [p], [t])]
    pack ((n, ps, ts) : done) (p, t)
      | n + size t <= budget = (n + size t, ps <> [p], ts <> [t]) : done
      | otherwise = (size t, [p], [t]) : (n, ps, ts) : done
    finish (_, ps, ts) = Chunk 0 (T.concat ts) (dedupe ps)
    dedupe = Map.keys . Map.fromList . map (,())

-- | The files a reply may cite, with their post-change line counts.
evidenceIndex :: [EvidenceFile] -> EvidenceIndex
evidenceIndex fs = EvidenceIndex (Map.fromList [(f ^. #path, length (fileLines f)) | f <- fs])
