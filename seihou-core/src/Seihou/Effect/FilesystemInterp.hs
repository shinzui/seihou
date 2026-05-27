module Seihou.Effect.FilesystemInterp
  ( runFilesystem,
  )
where

import Control.Monad (when)
import Data.Text.IO qualified as TIO
import Seihou.Effect.Filesystem (Filesystem (..))
import Seihou.Prelude
import System.Directory qualified as Dir

-- | Real IO interpreter for the Filesystem effect.
-- Delegates to System.Directory and Data.Text.IO.
runFilesystem :: (IOE :> es) => Eff (Filesystem : es) a -> Eff es a
runFilesystem = interpret $ \_ -> \case
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
