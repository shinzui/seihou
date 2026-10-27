module Seihou.Effect.Filesystem
  ( Filesystem (..),
    PathEntry (..),
    ExclusiveCreateResult (..),
    createFileExclusive,
    inspectPath,
    createLink,
    removeLink,
    normalizePath,
    readFileText,
    writeFileText,
    copyFile,
    listDirectory,
    createDirectoryIfMissing,
    doesFileExist,
    doesDirectoryExist,
    getCurrentDirectory,
    removeFile,
    removeDirectoryIfEmpty,
    renamePath,
    removeDirectoryRecursive,
  )
where

import Seihou.Filesystem.Exclusive (ExclusiveCreateResult (..))
import Seihou.Prelude

-- | A filesystem entry, observed without following its final component.
data PathEntry = EntryMissing | EntryFile | EntryDirectory | EntrySymlink FilePath
  deriving stock (Eq, Show, Generic)

data Filesystem :: Effect where
  CreateFileExclusive :: FilePath -> Text -> Filesystem m ExclusiveCreateResult
  InspectPath :: FilePath -> Filesystem m PathEntry
  CreateDirectoryLink :: FilePath -> FilePath -> Filesystem m ()
  RemoveLink :: FilePath -> Filesystem m ()
  NormalizePath :: FilePath -> Filesystem m FilePath
  ReadFileText :: FilePath -> Filesystem m Text
  WriteFileText :: FilePath -> Text -> Filesystem m ()
  CopyFile :: FilePath -> FilePath -> Filesystem m ()
  ListDirectory :: FilePath -> Filesystem m [FilePath]
  CreateDirectoryIfMissing :: Bool -> FilePath -> Filesystem m ()
  DoesFileExist :: FilePath -> Filesystem m Bool
  DoesDirectoryExist :: FilePath -> Filesystem m Bool
  GetCurrentDirectory :: Filesystem m FilePath
  RemoveFile :: FilePath -> Filesystem m ()
  RemoveDirectoryIfEmpty :: FilePath -> Filesystem m ()
  -- | Rename a file or directory atomically (within a filesystem).
  -- Backed by 'System.Directory.renamePath' in IO.
  RenamePath :: FilePath -> FilePath -> Filesystem m ()
  -- | Recursively delete a directory and all its contents. Backed by
  -- 'System.Directory.removeDirectoryRecursive' in IO. The pure
  -- interpreter drops every map entry under the prefix.
  RemoveDirectoryRecursive :: FilePath -> Filesystem m ()

type instance DispatchOf Filesystem = Dynamic

readFileText :: (Filesystem :> es) => FilePath -> Eff es Text
readFileText path = send (ReadFileText path)

writeFileText :: (Filesystem :> es) => FilePath -> Text -> Eff es ()
writeFileText path content = send (WriteFileText path content)

copyFile :: (Filesystem :> es) => FilePath -> FilePath -> Eff es ()
copyFile src dest = send (CopyFile src dest)

listDirectory :: (Filesystem :> es) => FilePath -> Eff es [FilePath]
listDirectory path = send (ListDirectory path)

createDirectoryIfMissing :: (Filesystem :> es) => Bool -> FilePath -> Eff es ()
createDirectoryIfMissing parents path = send (CreateDirectoryIfMissing parents path)

doesFileExist :: (Filesystem :> es) => FilePath -> Eff es Bool
doesFileExist path = send (DoesFileExist path)

doesDirectoryExist :: (Filesystem :> es) => FilePath -> Eff es Bool
doesDirectoryExist path = send (DoesDirectoryExist path)

getCurrentDirectory :: (Filesystem :> es) => Eff es FilePath
getCurrentDirectory = send GetCurrentDirectory

removeFile :: (Filesystem :> es) => FilePath -> Eff es ()
removeFile path = send (RemoveFile path)

removeDirectoryIfEmpty :: (Filesystem :> es) => FilePath -> Eff es ()
removeDirectoryIfEmpty path = send (RemoveDirectoryIfEmpty path)

renamePath :: (Filesystem :> es) => FilePath -> FilePath -> Eff es ()
renamePath src dest = send (RenamePath src dest)

removeDirectoryRecursive :: (Filesystem :> es) => FilePath -> Eff es ()
removeDirectoryRecursive path = send (RemoveDirectoryRecursive path)

inspectPath :: (Filesystem :> es) => FilePath -> Eff es PathEntry
inspectPath = send . InspectPath

createLink :: (Filesystem :> es) => FilePath -> FilePath -> Eff es ()
createLink target path = send (CreateDirectoryLink target path)

removeLink :: (Filesystem :> es) => FilePath -> Eff es ()
removeLink = send . RemoveLink

normalizePath :: (Filesystem :> es) => FilePath -> Eff es FilePath
normalizePath = send . NormalizePath

createFileExclusive :: (Filesystem :> es) => FilePath -> Text -> Eff es ExclusiveCreateResult
createFileExclusive path content = send (CreateFileExclusive path content)
