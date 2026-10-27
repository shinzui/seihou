module Seihou.Effect.FilesystemInterp
  ( runFilesystem,
    createFileExclusiveWith,
  )
where

import Control.Exception (IOException, catch, throwIO)
import Control.Monad (when)
import Data.ByteString qualified as BS
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Seihou.Effect.Filesystem (ExclusiveCreateResult (..), Filesystem (..), PathEntry (..))
import Seihou.Filesystem.Exclusive (createFileExclusiveWith)
import Seihou.Prelude
import System.Directory qualified as Dir
import System.IO.Error (isDoesNotExistError)

-- | Real IO interpreter for the Filesystem effect.
-- Delegates to System.Directory and Data.Text.IO.
runFilesystem :: (IOE :> es) => Eff (Filesystem : es) a -> Eff es a
runFilesystem = interpret $ \_ -> \case
  CreateFileExclusive path content -> liftIO (createFileExclusiveWith (\handle -> BS.hPut handle (TE.encodeUtf8 content)) path)
  InspectPath path -> liftIO $ do
    linked <- Dir.pathIsSymbolicLink path `catch` \(err :: IOException) -> if isDoesNotExistError err then pure False else throwIO err
    if linked
      then EntrySymlink <$> Dir.getSymbolicLinkTarget path
      else do
        directory <- Dir.doesDirectoryExist path
        file <- Dir.doesFileExist path
        pure (if directory then EntryDirectory else if file then EntryFile else EntryMissing)
  CreateDirectoryLink target path -> liftIO (Dir.createDirectoryLink target path)
  RemoveLink path -> liftIO $ do
    linked <- Dir.pathIsSymbolicLink path
    if linked then Dir.removeDirectoryLink path else ioError (userError "refusing to unlink a regular entry")
  NormalizePath path -> liftIO (Dir.canonicalizePath path)
  ReadFileText path -> liftIO (TIO.readFile path)
  WriteFileText path content -> liftIO (TIO.writeFile path content)
  CopyFile src dest -> liftIO (Dir.copyFile src dest)
  ListDirectory path -> liftIO (Dir.listDirectory path)
  CreateDirectoryIfMissing parents path ->
    liftIO (Dir.createDirectoryIfMissing parents path)
  DoesFileExist path -> liftIO (Dir.doesFileExist path)
  DoesDirectoryExist path -> liftIO (Dir.doesDirectoryExist path)
  GetCurrentDirectory -> liftIO Dir.getCurrentDirectory
  RemoveFile path -> liftIO (Dir.removeFile path)
  RemoveDirectoryIfEmpty path -> liftIO $ do
    -- Treat a missing directory as a no-op so this matches the pure
    -- interpreter's semantics. Without this guard, callers that walk
    -- a list of "maybe-now-empty" parents (e.g. cleanupEmptyDirs in
    -- Engine.Migrate / Engine.Remove) crash whenever a sibling
    -- operation — typically a user-authored 'rm -rf' RunCommand step
    -- in a migration chain — has already removed the directory.
    exists <- Dir.doesDirectoryExist path
    when exists $ do
      entries <- Dir.listDirectory path
      when (null entries) (Dir.removeDirectory path)
  RenamePath src dest -> liftIO (Dir.renamePath src dest)
  RemoveDirectoryRecursive path -> liftIO (Dir.removeDirectoryRecursive path)
