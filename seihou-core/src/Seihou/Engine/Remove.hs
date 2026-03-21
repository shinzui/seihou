module Seihou.Engine.Remove
  ( RemovalFile (..),
    RemovalPlan (..),
    RemovalError (..),
    RemovalOp (..),
    RemovalFileStatus (..),
    ExecutedRemovalPlan (..),
    computeRemovalPlan,
    executeRemoval,
    buildRemovalOps,
    executeRemovalOps,
  )
where

import Control.Monad (foldM)
import Data.List (nub, sortBy)
import Data.Map.Strict qualified as Map
import Data.Ord (Down (..))
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text qualified as T
import Data.Time (UTCTime)
import Seihou.Core.Types
import Seihou.Effect.Filesystem (Filesystem, doesFileExist, readFileText, removeDirectoryIfEmpty, removeFile, writeFileText)
import Seihou.Engine.Section (removeSection)
import Seihou.Manifest.Hash (hashContent)
import Seihou.Prelude
import System.FilePath (takeDirectory)

-- ============================================================
-- Legacy types (used by current CLI handler, Milestone 4 replaces)
-- ============================================================

-- | Classification of a file during removal planning.
data RemovalFile
  = -- | Disk hash matches manifest hash — safe to delete.
    RemovalSafe FilePath
  | -- | User modified the file since generation — needs confirmation.
    RemovalConflict FilePath
  | -- | File was already deleted from disk.
    RemovalGone FilePath
  deriving stock (Eq, Show)

-- | A plan describing what files to remove for a given module.
data RemovalPlan = RemovalPlan
  { targetModule :: ModuleName,
    files :: [RemovalFile]
  }
  deriving stock (Eq, Show)

-- ============================================================
-- New step-based removal types
-- ============================================================

-- | A concrete removal operation ready to execute.
data RemovalOp
  = -- | Delete a file, with its current status.
    DeleteFileOp FilePath RemovalFileStatus
  | -- | Strip this module's section markers from a file.
    StripSectionOp FilePath
  | -- | Apply a Dhall text function to rewrite a file.
    RewriteOp FilePath FilePath
  | -- | Run a shell command during removal.
    RemovalCommandOp Text (Maybe Text)
  deriving stock (Eq, Show)

-- | Status of a file targeted for deletion.
data RemovalFileStatus
  = -- | Disk hash matches manifest — safe to delete.
    RFSafe
  | -- | User modified the file since generation.
    RFConflict
  | -- | File already deleted from disk.
    RFGone
  deriving stock (Eq, Show)

-- | A removal plan built from declared removal steps.
data ExecutedRemovalPlan = ExecutedRemovalPlan
  { targetModule :: ModuleName,
    ops :: [RemovalOp]
  }
  deriving stock (Eq, Show)

-- | Errors that prevent removal.
data RemovalError
  = -- | The module is not in the manifest's applied modules list.
    ModuleNotApplied ModuleName
  | -- | The module has no removal specification.
    ModuleNotRemovable ModuleName
  deriving stock (Eq, Show)

-- ============================================================
-- Legacy compute/execute (preserves current CLI behavior)
-- ============================================================

-- | Compute a removal plan for the given module.
-- Checks that the module is applied and has a removal spec, then classifies
-- each file it owns as safe, conflicted, or already gone.
computeRemovalPlan ::
  (Filesystem :> es) =>
  Manifest ->
  ModuleName ->
  Eff es (Either RemovalError RemovalPlan)
computeRemovalPlan manifest modName = do
  case findApplied manifest modName of
    Nothing -> pure (Left (ModuleNotApplied modName))
    Just am
      | Nothing <- am.removal -> pure (Left (ModuleNotRemovable modName))
      | otherwise -> do
          let ownedFiles = moduleFiles manifest modName
          classified <- mapM classifyForRemoval ownedFiles
          pure (Right (RemovalPlan {targetModule = modName, files = classified}))

-- | Execute a removal plan: delete files, clean up empty directories,
-- and return the updated manifest.
executeRemoval ::
  (Filesystem :> es) =>
  Manifest ->
  RemovalPlan ->
  Set FilePath ->
  UTCTime ->
  Eff es Manifest
executeRemoval manifest plan keepSet now = do
  let toDelete = filesToDelete plan keepSet
  mapM_ removeFile toDelete
  cleanupEmptyDirs toDelete
  pure (removeFromManifest manifest plan.targetModule now)

-- ============================================================
-- New step-based removal engine
-- ============================================================

-- | Build a list of removal operations from declared removal steps.
-- Classifies remove-file targets by checking the manifest and disk state.
buildRemovalOps ::
  (Filesystem :> es) =>
  Manifest ->
  ModuleName ->
  Removal ->
  Eff es (Either RemovalError ExecutedRemovalPlan)
buildRemovalOps manifest modName removal = do
  case findApplied manifest modName of
    Nothing -> pure (Left (ModuleNotApplied modName))
    Just _ -> do
      stepOps <- mapM (buildStepOp manifest modName) removal.removalSteps
      let cmdOps = map (\c -> RemovalCommandOp c.run c.workDir) removal.removalCommands
      pure
        ( Right
            ExecutedRemovalPlan
              { targetModule = modName,
                ops = stepOps ++ cmdOps
              }
        )

-- | Build a single removal operation from a removal step.
buildStepOp ::
  (Filesystem :> es) =>
  Manifest ->
  ModuleName ->
  RemovalStep ->
  Eff es RemovalOp
buildStepOp manifest _modName step = case step.action of
  RemoveFileAction -> do
    let path = T.unpack step.dest
    status <- classifyFileStatus manifest path
    pure (DeleteFileOp path status)
  RemoveSectionAction ->
    pure (StripSectionOp (T.unpack step.dest))
  RewriteFileAction ->
    let src = case step.src of
          Just s -> s
          Nothing -> error "rewrite-file step requires a src field"
     in pure (RewriteOp (T.unpack step.dest) src)

-- | Classify a file's status for removal by comparing disk to manifest.
classifyFileStatus ::
  (Filesystem :> es) =>
  Manifest ->
  FilePath ->
  Eff es RemovalFileStatus
classifyFileStatus manifest path = do
  exists <- doesFileExist path
  if not exists
    then pure RFGone
    else case Map.lookup path manifest.files of
      Nothing -> pure RFSafe -- Not in manifest, treat as safe to delete
      Just rec -> do
        content <- readFileText path
        let diskHash = hashContent content
        if diskHash == rec.hash
          then pure RFSafe
          else pure RFConflict

-- | Execute a list of removal operations and return the updated manifest.
executeRemovalOps ::
  (Filesystem :> es) =>
  Manifest ->
  ExecutedRemovalPlan ->
  Set FilePath ->
  UTCTime ->
  Eff es Manifest
executeRemovalOps manifest plan keepSet now = do
  let modName = plan.targetModule
  deletedPaths <- foldM (execOp modName keepSet) [] plan.ops
  cleanupEmptyDirs deletedPaths
  pure (removeFromManifest manifest modName now)

-- | Execute a single removal operation. Returns accumulated deleted paths.
execOp ::
  (Filesystem :> es) =>
  ModuleName ->
  Set FilePath ->
  [FilePath] ->
  RemovalOp ->
  Eff es [FilePath]
execOp _ keepSet acc (DeleteFileOp path status) =
  if Set.member path keepSet
    then pure acc
    else case status of
      RFSafe -> do
        removeFile path
        pure (path : acc)
      RFConflict -> do
        -- Conflicts are deleted unless in keepSet (handled by CLI)
        removeFile path
        pure (path : acc)
      RFGone -> pure acc
execOp modName _ acc (StripSectionOp path) = do
  exists <- doesFileExist path
  if exists
    then do
      content <- readFileText path
      let prefix = guessCommentPrefix path
          cleaned = removeSection modName prefix content
      writeFileText path cleaned
      pure acc
    else pure acc
execOp _ _ acc (RewriteOp _ _) = do
  -- RewriteFileAction is deferred to a future milestone (requires Dhall eval)
  pure acc
execOp _ _ acc (RemovalCommandOp _ _) = do
  -- Commands are executed by the CLI handler, not the engine
  pure acc

-- | Guess the comment prefix for a file based on its extension.
guessCommentPrefix :: FilePath -> Text
guessCommentPrefix path
  | ".hs" `T.isSuffixOf` T.pack path = "--"
  | ".cabal" `T.isSuffixOf` T.pack path = "--"
  | ".yaml" `T.isSuffixOf` T.pack path = "#"
  | ".yml" `T.isSuffixOf` T.pack path = "#"
  | ".toml" `T.isSuffixOf` T.pack path = "#"
  | ".nix" `T.isSuffixOf` T.pack path = "#"
  | otherwise = "#"

-- ============================================================
-- Shared helpers
-- ============================================================

-- | Find an applied module by name.
findApplied :: Manifest -> ModuleName -> Maybe AppliedModule
findApplied manifest modName =
  case filter (\am -> am.name == modName) manifest.modules of
    (am : _) -> Just am
    [] -> Nothing

-- | Get the file paths owned by a module in the manifest.
moduleFiles :: Manifest -> ModuleName -> [(FilePath, FileRecord)]
moduleFiles manifest modName =
  [ (path, rec)
  | (path, rec) <- Map.toList manifest.files,
    rec.moduleName == modName
  ]

-- | Classify a single file for removal (legacy).
classifyForRemoval :: (Filesystem :> es) => (FilePath, FileRecord) -> Eff es RemovalFile
classifyForRemoval (path, rec) = do
  exists <- doesFileExist path
  if not exists
    then pure (RemovalGone path)
    else do
      content <- readFileText path
      let diskHash = hashContent content
      if diskHash == rec.hash
        then pure (RemovalSafe path)
        else pure (RemovalConflict path)

-- | Determine which files should actually be deleted.
filesToDelete :: RemovalPlan -> Set FilePath -> [FilePath]
filesToDelete plan keepSet =
  [ path
  | rf <- plan.files,
    let path = removalFilePath rf,
    shouldDelete rf,
    not (Set.member path keepSet)
  ]
  where
    shouldDelete (RemovalSafe _) = True
    shouldDelete (RemovalConflict _) = True
    shouldDelete (RemovalGone _) = False

-- | Extract the path from a RemovalFile.
removalFilePath :: RemovalFile -> FilePath
removalFilePath (RemovalSafe p) = p
removalFilePath (RemovalConflict p) = p
removalFilePath (RemovalGone p) = p

-- | After deleting files, try to remove their now-empty parent directories.
-- Walks parents bottom-up (deepest first) to correctly cascade.
cleanupEmptyDirs :: (Filesystem :> es) => [FilePath] -> Eff es ()
cleanupEmptyDirs paths = do
  let parentDirs = nub $ concatMap allParents paths
      -- Sort deepest-first so children are removed before parents
      sorted = sortBy (\a b -> compare (Down (length a)) (Down (length b))) parentDirs
  mapM_ removeDirectoryIfEmpty sorted

-- | Get all parent directories of a path, excluding "." and "".
allParents :: FilePath -> [FilePath]
allParents path = go (takeDirectory path)
  where
    go "." = []
    go "" = []
    go "/" = []
    go dir = dir : go (takeDirectory dir)

-- | Remove a module and its files from the manifest.
removeFromManifest :: Manifest -> ModuleName -> UTCTime -> Manifest
removeFromManifest manifest modName now =
  manifest
    { modules = filter (\am -> am.name /= modName) manifest.modules,
      files = Map.filter (\rec -> rec.moduleName /= modName) manifest.files,
      genAt = now
    }
