module Seihou.Engine.Preview
  ( FileStatus (..),
    PreviewLine (..),
    buildPreview,
    renderPreviewPlain,
  )
where

import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Seihou.Core.Types

-- | Status of a file relative to the manifest and disk.
data FileStatus
  = FsNew
  | FsModified
  | FsUnchanged
  | FsConflict
  | FsOrphaned
  | FsUnknown
  deriving stock (Eq, Show)

-- | One line in the dry-run preview.
data PreviewLine
  = FilePreview
      { previewStatus :: FileStatus,
        previewVerb :: Text,
        previewPath :: FilePath,
        previewAnnotation :: Text
      }
  | DirPreview FilePath
  | CommandPreview Text
  | OrphanPreview FilePath ModuleName
  deriving stock (Eq, Show)

-- | Build a structured preview from operations and an optional diff result.
-- When no DiffResult is provided (first run, no manifest), all file
-- operations are treated as new.
buildPreview :: [Operation] -> Maybe DiffResult -> [PreviewLine]
buildPreview ops mDiff =
  let opLines = map (opToPreview mDiff) ops
      orphanLines = case mDiff of
        Nothing -> []
        Just diff ->
          -- Only include orphans whose path is NOT produced by any operation
          let producedPaths = Set.fromList [p | op <- ops, Just p <- [destOfOp op]]
           in [ OrphanPreview (orphanedPath o) (orphanedModule o)
              | o <- diffOrphaned diff,
                not (Set.member (orphanedPath o) producedPaths)
              ]
   in opLines ++ orphanLines

-- | Convert a single operation to a preview line.
opToPreview :: Maybe DiffResult -> Operation -> PreviewLine
opToPreview mDiff (WriteFileOp dest _ strat) =
  FilePreview
    { previewStatus = lookupStatus dest mDiff,
      previewVerb = "write",
      previewPath = dest,
      previewAnnotation = "(" <> strategyName strat <> ")"
    }
opToPreview _ (CreateDirOp path) = DirPreview path
opToPreview mDiff (CopyFileOp _ dest) =
  FilePreview
    { previewStatus = lookupStatus dest mDiff,
      previewVerb = "copy",
      previewPath = dest,
      previewAnnotation = "(copy)"
    }
opToPreview _ (RunCommandOp cmd _) = CommandPreview cmd
opToPreview mDiff (PatchFileOp dest _ patchOp' _ modName') =
  FilePreview
    { previewStatus = lookupStatus dest mDiff,
      previewVerb = "patch",
      previewPath = dest,
      previewAnnotation = "(" <> patchOpName patchOp' <> " from " <> unModuleName modName' <> ")"
    }

-- | Look up a file's status in the diff result.
lookupStatus :: FilePath -> Maybe DiffResult -> FileStatus
lookupStatus _ Nothing = FsNew
lookupStatus path (Just diff)
  | any (\f -> plannedPath f == path) (diffNew diff) = FsNew
  | any (\f -> modifiedPath f == path) (diffModified diff) = FsModified
  | path `elem` diffUnchanged diff = FsUnchanged
  | any (\f -> conflictPath f == path) (diffConflict diff) = FsConflict
  | any (\f -> orphanedPath f == path) (diffOrphaned diff) = FsOrphaned
  | otherwise = FsUnknown

-- | Render preview lines as plain text (no ANSI codes).
renderPreviewPlain :: [PreviewLine] -> Text
renderPreviewPlain lines' =
  if null lines'
    then "No operations to perform.\n"
    else T.unlines (map renderPlainLine lines')

renderPlainLine :: PreviewLine -> Text
renderPlainLine (FilePreview status verb path annotation) =
  "  " <> statusSymbol status <> " " <> verb <> "  " <> T.pack path <> "  " <> annotation
renderPlainLine (DirPreview path) =
  "    mkdir  " <> T.pack path
renderPlainLine (CommandPreview cmd) =
  "    run    " <> cmd
renderPlainLine (OrphanPreview path modName') =
  "  - " <> T.pack path <> "  (orphaned from " <> unModuleName modName' <> ")"

statusSymbol :: FileStatus -> Text
statusSymbol FsNew = "+"
statusSymbol FsModified = "~"
statusSymbol FsUnchanged = "="
statusSymbol FsConflict = "!"
statusSymbol FsOrphaned = "-"
statusSymbol FsUnknown = " "

strategyName :: Strategy -> Text
strategyName Copy = "copy"
strategyName Template = "template"
strategyName DhallText = "dhall-text"
strategyName Structured = "structured"

patchOpName :: PatchOp -> Text
patchOpName AppendFile = "append-file"
patchOpName PrependFile = "prepend-file"
patchOpName AppendSection = "append-section"

-- | Extract the destination path from a file-producing operation.
destOfOp :: Operation -> Maybe FilePath
destOfOp (WriteFileOp d _ _) = Just d
destOfOp (CopyFileOp _ d) = Just d
destOfOp (PatchFileOp d _ _ _ _) = Just d
destOfOp _ = Nothing
