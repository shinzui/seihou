module Seihou.Engine.Checkout
  ( observeCheckoutOutputs,
    prepareCheckoutPlan,
    prepareCheckoutApplication,
    applyCheckoutPlan,
    applyCheckoutPlanWithHook,
    rollbackCheckout,
    CheckoutExecution (..),
    CheckoutUndo (..),
    checkoutGitRoot,
    safeCheckoutManifest,
  )
where

import Control.Exception (IOException)
import Control.Monad (foldM, forM, forM_, unless, when)
import Data.Generics.Labels ()
import Data.List (sortOn)
import Data.Map.Strict qualified as Map
import Data.Maybe (maybeToList)
import Data.Set qualified as Set
import Data.Text qualified as T
import Effectful.Exception qualified as E
import Seihou.Core.Checkout
import Seihou.Core.Types
import Seihou.Effect.Filesystem
import Seihou.Effect.Process
import Seihou.Prelude
import System.Exit (ExitCode (..))
import System.FilePath.Posix qualified as P

checkoutGitRoot :: (Filesystem :> es, Process :> es, IOE :> es) => FilePath -> Eff es (Maybe FilePath)
checkoutGitRoot root = do
  result <- E.try @IOException (runProcess "git" ["rev-parse", "--show-toplevel"] (Just root))
  case result of
    Right (ExitSuccess, path, _) -> Just <$> normalizePath (T.unpack (T.stripEnd path))
    _ -> pure Nothing

-- | Inspect metadata before opening it; a manifest must be a real file.
safeCheckoutManifest :: (Filesystem :> es) => FilePath -> Eff es (Either CheckoutError ())
safeCheckoutManifest root = do
  dir <- inspectPath (root </> ".seihou")
  file <- if dir == EntryDirectory then inspectPath (root </> ".seihou/manifest.json") else pure EntryMissing
  pure $
    if dir == EntryDirectory && file == EntryFile
      then Right ()
      else Left (checkoutError "checkout_manifest_unsafe" "require a real .seihou directory and manifest.json file; run seihou run to record declarations, or move symlinked metadata aside")

ancestors :: FilePath -> [FilePath]
ancestors path = reverse (go (P.takeDirectory path))
  where
    go "." = []; go "" = []; go p = p : go (P.takeDirectory p)

-- | Observe entries themselves, never the targets of destination symlinks.
observeCheckoutOutputs :: (Filesystem :> es, Process :> es, IOE :> es) => FilePath -> Map FilePath CheckoutOutputRecord -> Map FilePath CheckoutOutputRecord -> Eff es (Map FilePath CheckoutObservation)
observeCheckoutOutputs root prior candidate = do
  gitRoot <- checkoutGitRoot root
  indexed <- case gitRoot of
    Nothing -> pure (Right [])
    Just _ -> do
      (code, out, _) <- runProcess "git" ["ls-files", "--cached", "-z"] (Just root)
      pure $ if code == ExitSuccess then Right (map T.unpack (filter (not . T.null) (T.splitOn "\0" out))) else Left (checkoutError "checkout_git_unavailable" "cannot inspect Git's index")
  metadataAlias <- inspectPath (root </> ".GIT")
  let nativeOverlap a b = pathsOverlap a b || (metadataAlias /= EntryMissing && pathsOverlap (T.unpack (T.toCaseFold (T.pack a))) (T.unpack (T.toCaseFold (T.pack b))))
  pairs <- forM allPaths $ \dest -> do
    let active = Map.lookup dest candidate
        record = case active of Just r -> r; Nothing -> prior Map.! dest
        source = checkoutSource (record ^. #spec)
    result <- E.try @IOException $ do
      parentProblems <- (<>) <$> checkAncestors (ancestors dest) <*> (if active == Nothing then pure [] else checkAncestors (ancestors source))
      entry <- if null parentProblems then inspectPath (root </> dest) else pure EntryMissing
      sourceEntry <- if active == Nothing || not (null parentProblems) then pure EntryMissing else inspectPath (root </> source)
      sourceAlias <- if active == Nothing || not (null parentProblems) then pure [] else checkSpelling source
      destAlias <- if null parentProblems then checkSpelling dest else pure []
      (ignored, ignoreProblems) <-
        if gitRoot == Nothing
          then pure (False, [])
          else do
            (code, _, _) <- runProcess "git" ["check-ignore", "-q", "--", "./" <> T.pack dest] (Just root)
            pure $ case code of
              ExitSuccess -> (True, [])
              ExitFailure 1 -> (False, [])
              _ -> (False, [checkoutError "checkout_git_unavailable" "cannot inspect ignore rules; check Git configuration"])

      let trackedProblems = case indexed of
            Left err -> [err]
            Right paths -> [checkoutError "checkout_path_tracked" "destination overlaps a tracked path (including an indexed ancestor); change the declaration or untrack it explicitly" | any (nativeOverlap dest) paths]
          aliasClaims =
            [ checkoutError "checkout_native_alias" "checkout declarations have ambiguous case spellings; use distinct portable destinations"
            | any (\other -> other /= dest && T.toCaseFold (T.pack other) == T.toCaseFold (T.pack dest)) allPaths
            ]
      pure (CheckoutObservation entry (sourceEntry == EntryDirectory) (parentProblems <> trackedProblems <> ignoreProblems <> sourceAlias <> destAlias <> aliasClaims <> [checkoutError "checkout_source_not_directory" "source is not a real directory; move the object aside" | active /= Nothing, sourceEntry `notElem` [EntryMissing, EntryDirectory]]) (gitRoot /= Nothing) ignored)
    pure
      ( dest,
        case result of
          Right obs -> obs
          Left err -> CheckoutObservation EntryMissing False [checkoutError "checkout_path_inaccessible" ("cannot inspect '" <> T.pack dest <> "': " <> T.pack (show err))] (gitRoot /= Nothing) False
      )
  pure (Map.fromList pairs)
  where
    allPaths = Set.toAscList (Map.keysSet prior <> Map.keysSet candidate)
    checkAncestors [] = pure []
    checkAncestors (path : rest) =
      inspectPath (root </> path) >>= \case
        EntrySymlink _ -> pure [checkoutError "checkout_parent_symlink" ("ancestor '" <> T.pack path <> "' is a symlink; replace it with a real directory")]
        EntryFile -> pure [checkoutError "checkout_parent_not_directory" ("ancestor '" <> T.pack path <> "' is a file; move it aside")]
        EntryMissing -> pure []
        EntryDirectory -> checkAncestors rest
    -- Native path lookup may accept a different spelling on case-insensitive volumes.
    checkSpelling path = fmap concat $ forM (ancestors path <> [path]) $ \part -> do
      parent <- inspectPath (root </> P.takeDirectory part)
      if parent /= EntryDirectory
        then pure []
        else do
          names <- listDirectory (root </> P.takeDirectory part)
          exists <- inspectPath (root </> part)
          pure [checkoutError "checkout_native_alias" ("path '" <> T.pack part <> "' resolves through a different native spelling") | exists /= EntryMissing, P.takeFileName part `notElem` names]

prepareCheckoutPlan :: (Filesystem :> es, Process :> es, IOE :> es) => CheckoutIntent -> CheckoutPolicy -> FilePath -> Manifest -> Manifest -> [FilePath] -> Eff es (Either CheckoutError CheckoutPlan)
prepareCheckoutPlan intent policy root prior candidate pending = case validateCheckoutRecords candidate pending of
  Left err -> pure (Left err)
  Right () -> do
    observations <- observeCheckoutOutputs root (prior ^. #checkoutOutputs) (candidate ^. #checkoutOutputs)
    pure (Right (planCheckoutOutputs intent policy (prior ^. #checkoutOutputs) (candidate ^. #checkoutOutputs) observations))

-- | An undo entry describes only this attempt's own writes.
data CheckoutUndo = CheckoutUndo
  {dest :: !FilePath, before :: !PathEntry, after :: !PathEntry, parents :: ![FilePath]}
  deriving stock (Eq, Show, Generic)

data CheckoutExecution = CheckoutExecution
  {outcomes :: !(Map FilePath Text), undo :: ![CheckoutUndo], failure :: !(Maybe CheckoutError)}
  deriving stock (Eq, Show, Generic)

rollbackCheckout :: (Filesystem :> es, IOE :> es) => FilePath -> [CheckoutUndo] -> Eff es (Map FilePath Text)
rollbackCheckout root writes =
  Map.fromList
    <$> forM
      writes
      ( \write -> do
          result <- E.try @IOException $ do
            let path = root </> (write ^. #dest)
            parentsSafe <- and <$> mapM (\p -> (== EntryDirectory) <$> inspectPath (root </> p)) (ancestors (write ^. #dest))
            current <- if parentsSafe then inspectPath path else pure EntryFile
            if current /= write ^. #after
              then pure "rollback-conflicted"
              else do
                case current of EntrySymlink _ -> removeLink path; _ -> pure ()
                case write ^. #before of EntrySymlink target -> createLink target path; _ -> pure ()
                forM_ (reverse (write ^. #parents)) (\p -> inspectPath (root </> p) >>= \kind -> when (kind == EntryDirectory) (removeDirectoryIfEmpty (root </> p)))
                pure "rolled-back"
          pure (write ^. #dest, either (const "rollback-conflicted") id result)
      )

-- | Recheck immediately before mutation. Supports a single cooperating writer;
-- portable path checks do not protect against hostile concurrent substitution.
applyCheckoutPlan :: (Filesystem :> es, Process :> es, IOE :> es) => CheckoutPolicy -> FilePath -> CheckoutPlan -> Eff es CheckoutExecution
applyCheckoutPlan = applyCheckoutPlanWithHook (const (pure ()))

-- | Failure injection after each completed link mutation, for rollback contract tests.
applyCheckoutPlanWithHook :: (Filesystem :> es, Process :> es, IOE :> es) => (Int -> Eff es ()) -> CheckoutPolicy -> FilePath -> CheckoutPlan -> Eff es CheckoutExecution
applyCheckoutPlanWithHook afterMutation policy root plan
  | not (checkoutApplicable plan) = pure (CheckoutExecution Map.empty [] (Just (checkoutError "checkout_preflight_refused" "checkout preflight refused; no outputs were changed")))
  | otherwise = go Map.empty [] (plan ^. #entries)
  where
    go outcomes writes [] = pure (CheckoutExecution outcomes writes Nothing)
    go outcomes writes (entry : rest)
      | entry ^. #action `notElem` [CreateLink, ReplaceLink, RetireLink] = go (Map.insert (entry ^. #dest) "unchanged" outcomes) writes rest
      | otherwise = do
          let dest = entry ^. #dest
              toMap spec = Map.singleton dest (CheckoutOutputRecord spec Map.empty)
              old = maybe Map.empty toMap (entry ^. #previous)
              new = maybe Map.empty toMap (entry ^. #candidate)
              expected = maybe EntryMissing (EntrySymlink . expectedTarget dest) (entry ^. #candidate)
          result <- E.try @IOException $ do
            observations <- observeCheckoutOutputs root old new
            let observed = observations Map.! dest
                changed = observed ^. #entry /= entry ^. #observation . #entry
                errors =
                  observed ^. #problems
                    <> [checkoutError "checkout_source_missing" "source directory disappeared" | entry ^. #candidate /= Nothing, not (observed ^. #sourceDirectory)]
                    <> [checkoutError "checkout_not_ignored" "destination is no longer ignored" | policy == SyncIgnoredOnly, entry ^. #candidate /= Nothing, not (observed ^. #ignored)]
                    <> [checkoutError "checkout_git_required" "Git evidence disappeared" | policy == SyncIgnoredOnly, not (observed ^. #gitAvailable)]
            when (changed || not (null errors)) $ E.throwIO (userError ("checkout precondition changed for " <> dest))
            missingParents <- filterM (\p -> (== EntryMissing) <$> inspectPath (root </> p)) (ancestors dest)
            -- Record and undo even a failure after unlink or during parent creation.
            let write = CheckoutUndo dest (observed ^. #entry) expected missingParents
            mutate <- E.try @IOException $ do
              forM_ missingParents (createDirectoryIfMissing False . (root </>))
              case entry ^. #action of
                CreateLink -> createLink (linkText entry) (root </> dest)
                ReplaceLink -> do
                  removeLink (root </> dest)
                  createLink (linkText entry) (root </> dest) `E.onException` createLink (oldText observed) (root </> dest)
                RetireLink -> removeLink (root </> dest)
                _ -> pure ()
            case mutate of
              Left err -> do
                forM_ (reverse missingParents) (\p -> inspectPath (root </> p) >>= \kind -> when (kind == EntryDirectory) (removeDirectoryIfEmpty (root </> p)))
                E.throwIO err
              Right () -> pure write
          case result of
            Right write -> do
              hooked <- E.try @IOException (afterMutation (length writes + 1))
              case hooked of
                Right () -> go (Map.insert dest "applied" outcomes) (write : writes) rest
                Left err -> do
                  reverted <- rollbackCheckout root (write : writes)
                  pure (CheckoutExecution (Map.union reverted outcomes) [] (Just (checkoutError "checkout_apply_failed" (T.pack (show err)))))
            Left err -> do
              reverted <- rollbackCheckout root writes
              pure (CheckoutExecution (Map.insert dest "failed" (Map.union reverted outcomes)) [] (Just (checkoutError "checkout_apply_failed" ("cannot apply '" <> T.pack dest <> "': " <> T.pack (show err) <> "; check symlink permissions and retry"))))
    linkText entry = case entry ^. #candidate of Just spec -> expectedTarget (entry ^. #dest) spec; Nothing -> ""
    oldText observed = case observed ^. #entry of EntrySymlink target -> target; _ -> ""

filterM :: (Monad m) => (a -> m Bool) -> [a] -> m [a]
filterM predicate = foldM (\acc x -> predicate x >>= \keep -> pure (if keep then acc <> [x] else acc)) []

-- | Before ordinary generation, a source directory may be scheduled to appear
-- through deterministic file output. Shell commands cannot satisfy this dependency.
prepareCheckoutApplication :: (Filesystem :> es, Process :> es, IOE :> es) => FilePath -> Manifest -> Manifest -> [Operation] -> Eff es (Either CheckoutError CheckoutPlan)
prepareCheckoutApplication root prior candidate operations = case validateCheckoutRecords candidate bytePaths of
  Left err -> pure (Left err)
  Right () -> do
    observed <- observeCheckoutOutputs root (prior ^. #checkoutOutputs) (candidate ^. #checkoutOutputs)
    let allowGenerated dest obs = case Map.lookup dest (candidate ^. #checkoutOutputs) of
          Just record | any (\path -> T.pack (checkoutSource (record ^. #spec) <> "/") `T.isPrefixOf` T.pack path) bytePaths -> obs & #sourceDirectory .~ True
          _ -> obs
    pure (Right (planCheckoutOutputs Reconcile ApplyDeclaration (prior ^. #checkoutOutputs) (candidate ^. #checkoutOutputs) (Map.mapWithKey allowGenerated observed)))
  where
    bytePaths =
      [ dest
      | op <- operations,
        dest <- case op of
          WriteFileOp {dest} -> [dest]
          CopyFileOp {dest} -> [dest]
          PatchFileOp {dest} -> [dest]
          _ -> []
      ]
