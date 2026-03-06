module Seihou.Effect.Filesystem
  ( Filesystem (..),
    readFileText,
    writeFileText,
    copyFile,
    listDirectory,
    createDirectoryIfMissing,
    doesFileExist,
    doesDirectoryExist,
    getCurrentDirectory,
  )
where

import Seihou.Prelude

data Filesystem :: Effect where
  ReadFileText :: FilePath -> Filesystem m Text
  WriteFileText :: FilePath -> Text -> Filesystem m ()
  CopyFile :: FilePath -> FilePath -> Filesystem m ()
  ListDirectory :: FilePath -> Filesystem m [FilePath]
  CreateDirectoryIfMissing :: Bool -> FilePath -> Filesystem m ()
  DoesFileExist :: FilePath -> Filesystem m Bool
  DoesDirectoryExist :: FilePath -> Filesystem m Bool
  GetCurrentDirectory :: Filesystem m FilePath

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
