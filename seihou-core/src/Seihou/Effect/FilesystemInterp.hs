module Seihou.Effect.FilesystemInterp
  ( runFilesystem,
  )
where

import Data.Text.IO qualified as TIO
import Effectful
import Effectful.Dispatch.Dynamic
import Seihou.Effect.Filesystem (Filesystem (..))
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
