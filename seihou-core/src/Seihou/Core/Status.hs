module Seihou.Core.Status
  ( computeTrackedFileStatuses,
  )
where

import Data.List (sortOn)
import Data.Map.Strict qualified as Map
import Seihou.Core.Types
import Seihou.Effect.Filesystem (Filesystem, doesFileExist, readFileText)
import Seihou.Manifest.Hash (hashContent)
import Seihou.Prelude

-- | Compare each file in the manifest against its current disk content.
-- Returns a sorted list of tracked files with their status:
-- 'TfsUnchanged' if the disk hash matches, 'TfsModified' if it differs,
-- 'TfsDeleted' if the file no longer exists on disk.
computeTrackedFileStatuses :: (Filesystem :> es) => Manifest -> Eff es [TrackedFile]
computeTrackedFileStatuses manifest = do
  results <- mapM classifyFile (Map.toAscList manifest.files)
  pure (sortOn (.path) results)
  where
    classifyFile :: (Filesystem :> es') => (FilePath, FileRecord) -> Eff es' TrackedFile
    classifyFile (path, record) = do
      exists <- doesFileExist path
      status <-
        if not exists
          then pure TfsDeleted
          else do
            content <- readFileText path
            let diskHash = hashContent content
            pure
              ( if diskHash == record.hash
                  then TfsUnchanged
                  else TfsModified
              )
      pure
        TrackedFile
          { path = path,
            moduleName = record.moduleName,
            status = status
          }
