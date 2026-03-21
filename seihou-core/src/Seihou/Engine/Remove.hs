module Seihou.Engine.Remove
  ( RemovalFile (..),
    RemovalPlan (..),
    RemovalError (..),
    computeRemovalPlan,
    executeRemoval,
  )
where

import Data.List (nub, sortBy)
import Data.Map.Strict qualified as Map
import Data.Ord (Down (..))
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Time (UTCTime)
import Seihou.Core.Types
import Seihou.Effect.Filesystem (Filesystem, doesFileExist, readFileText, removeDirectoryIfEmpty, removeFile)
import Seihou.Manifest.Hash (hashContent)
import Seihou.Prelude
import System.FilePath (takeDirectory)

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

-- | Errors that prevent removal.
data RemovalError
  = -- | The module is not in the manifest's applied modules list.
    ModuleNotApplied ModuleName
  | -- | The module's removable flag is False.
    ModuleNotRemovable ModuleName
  deriving stock (Eq, Show)

-- | Compute a removal plan for the given module.
-- Checks that the module is applied and removable, then classifies
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
      | not am.removable -> pure (Left (ModuleNotRemovable modName))
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

-- Helpers

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

-- | Classify a single file for removal.
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
