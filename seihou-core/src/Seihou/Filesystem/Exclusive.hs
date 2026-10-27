{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}

-- | Native complete-file publication with no replacement. Kept independent of
-- the effect stack so the same implementation can be checked on each host OS.
module Seihou.Filesystem.Exclusive
  ( ExclusiveCreateResult (..),
    createFileExclusiveWith,
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
createFileExclusiveWith writeContent path = do
  result <-
    try @IOException $
      bracket
        (openBinaryTempFile (takeDirectory path) ".seihou-seed")
        (\(temporary, handle) -> hClose handle >> (removeFile temporary `catch` \(_ :: IOException) -> pure ()))
        (\(temporary, handle) -> writeContent handle >> hClose handle >> Posix.createLink temporary path)
  pure $ case result of
    Right () -> ExclusiveCreated
    Left err | isAlreadyExistsError err -> ExclusiveOccupied
    Left err -> ExclusiveFailure (T.pack (show err))
