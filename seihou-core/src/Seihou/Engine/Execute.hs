module Seihou.Engine.Execute
  ( executePlan,
    dryRunPlan,
  )
where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (UTCTime)
import Effectful
import Seihou.Core.Types
import Seihou.Effect.Filesystem
import Seihou.Manifest.Hash (hashContent)
import System.FilePath ((</>))

-- | Execute a list of operations against the filesystem.
-- Returns a map of file paths to FileRecord entries for the manifest.
executePlan ::
  (Filesystem :> es) =>
  FilePath ->
  [Operation] ->
  ModuleName ->
  UTCTime ->
  Eff es (Map FilePath FileRecord)
executePlan targetDir ops moduleName now = do
  records <- mapM (executeOp targetDir moduleName now) ops
  pure (Map.fromList [(k, v) | Just (k, v) <- records])

-- | Execute a single operation and return a FileRecord if a file was written.
executeOp ::
  (Filesystem :> es) =>
  FilePath ->
  ModuleName ->
  UTCTime ->
  Operation ->
  Eff es (Maybe (FilePath, FileRecord))
executeOp targetDir moduleName now op = case op of
  WriteFileOp dest content strat -> do
    let fullPath = targetDir </> dest
    writeFileText fullPath content
    let record =
          FileRecord
            { fileHash = hashContent content,
              fileModule = moduleName,
              fileStrategy = strat,
              fileGeneratedAt = now
            }
    pure (Just (dest, record))
  CreateDirOp path -> do
    let fullPath = targetDir </> path
    createDirectoryIfMissing True fullPath
    pure Nothing
  CopyFileOp src dest -> do
    let fullDest = targetDir </> dest
    content <- readFileText src
    writeFileText fullDest content
    let record =
          FileRecord
            { fileHash = hashContent content,
              fileModule = moduleName,
              fileStrategy = Copy,
              fileGeneratedAt = now
            }
    pure (Just (dest, record))
  RunCommandOp _ _ -> do
    -- Command execution is deferred to the CLI layer.
    pure Nothing

-- | Format a human-readable description of the plan without executing anything.
dryRunPlan :: [Operation] -> Text
dryRunPlan ops =
  if null ops
    then "No operations to perform."
    else T.unlines (map formatOp ops)
  where
    formatOp :: Operation -> Text
    formatOp (WriteFileOp dest _ _) = "  write " <> T.pack dest
    formatOp (CreateDirOp path) = "  mkdir " <> T.pack path
    formatOp (CopyFileOp src dest) = "  copy  " <> T.pack src <> " -> " <> T.pack dest
    formatOp (RunCommandOp cmd _) = "  run   " <> cmd
