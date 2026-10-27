{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}

-- | Native complete-file publication with no replacement. Kept independent of
-- the effect stack so the same implementation can be checked on each host OS.
module Seihou.Filesystem.Exclusive
  ( ExclusiveCreateResult (..),
    createFileExclusiveWith,
    createFileExclusiveWithIdentity,
    createFileExclusiveAnchored,
  )
where

import Control.Exception (IOException, bracket, catch, try)
import Data.Text (Text)
import Data.Text qualified as T
import GHC.Generics (Generic)
import System.Directory (removeFile)
import System.FilePath (takeDirectory)
import System.IO (Handle, hClose, openBinaryTempFile)
import System.IO.Error (isAlreadyExistsError)
import System.Posix.Files qualified as Posix

data ExclusiveCreateResult = ExclusiveCreated | ExclusiveOccupied | ExclusiveFailure Text
  deriving stock (Eq, Show, Generic)

-- | The callback writes only to a private temporary file on the same filesystem.
-- link(2) publishes all bytes at once and fails for every existing entry, including
-- dangling symlinks. Cleanup never removes the public destination.
createFileExclusiveWith :: (Handle -> IO ()) -> FilePath -> IO ExclusiveCreateResult
createFileExclusiveWith writeContent path = fst <$> createFileExclusiveWithIdentity writeContent path

-- | Device/inode evidence comes from the private object, never a later lookup
-- of the public path, so recovery can distinguish an identical replacement.
createFileExclusiveWithIdentity :: (Handle -> IO ()) -> FilePath -> IO (ExclusiveCreateResult, Maybe (Integer, Integer))
createFileExclusiveWithIdentity = createFileExclusiveAnchored Nothing

-- | A transaction may retain a private hard-link anchor until commit/recovery.
-- Keeping the original inode alive prevents inode reuse from making an identical
-- replacement look like this transaction's object.
createFileExclusiveAnchored :: Maybe FilePath -> (Handle -> IO ()) -> FilePath -> IO (ExclusiveCreateResult, Maybe (Integer, Integer))
createFileExclusiveAnchored anchor writeContent path = do
  result <-
    try @IOException $
      bracket
        (openBinaryTempFile (takeDirectory path) ".seihou-seed")
        (\(temporary, handle) -> hClose handle >> (removeFile temporary `catch` \(_ :: IOException) -> pure ()))
        ( \(temporary, handle) -> do
            writeContent handle
            hClose handle
            status <- Posix.getFileStatus temporary
            maybe (pure ()) (Posix.createLink temporary) anchor
            Posix.createLink temporary path
            pure (fromIntegral (Posix.deviceID status), fromIntegral (Posix.fileID status))
        )
  pure $ case result of
    Right identity -> (ExclusiveCreated, Just identity)
    Left err | isAlreadyExistsError err -> (ExclusiveOccupied, Nothing)
    Left err -> (ExclusiveFailure (T.pack (show err)), Nothing)
