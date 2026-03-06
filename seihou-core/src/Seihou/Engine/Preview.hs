module Seihou.Engine.Preview
  ( FileStatus (..),
    PreviewLine (..),
    buildPreview,
    renderPreviewPlain,
    formatPlanView,
  )
where

import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as T
import Seihou.Core.Types
import Seihou.Prelude

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
        previewPath :: FilePath,
        previewAnnotation :: Text,
        previewModule :: Maybe ModuleName
      }
  | DirPreview FilePath
  | CommandPreview Text
  | OrphanPreview FilePath ModuleName
  deriving stock (Eq, Show)

-- | Build a structured preview from operations and an optional diff result.
-- The ownership map tracks which module produced each file path.
-- When no DiffResult is provided (first run, no manifest), all file
-- operations are treated as new.
buildPreview :: [Operation] -> Maybe DiffResult -> Map FilePath ModuleName -> [PreviewLine]
buildPreview ops mDiff ownerMap =
  let opLines = map (opToPreview mDiff ownerMap) ops
      orphanLines = case mDiff of
        Nothing -> []
        Just diff ->
          -- Only include orphans whose path is NOT produced by any operation
          let producedPaths = Set.fromList [p | op <- ops, Just p <- [destOfOp op]]
           in [ OrphanPreview o.path o.moduleName
              | o <- diff.orphaned,
                not (Set.member o.path producedPaths)
              ]
   in opLines ++ orphanLines

-- | Convert a single operation to a preview line.
opToPreview :: Maybe DiffResult -> Map FilePath ModuleName -> Operation -> PreviewLine
opToPreview mDiff ownerMap (WriteFileOp dest _ strat) =
  FilePreview
    { previewStatus = lookupStatus dest mDiff,
      previewPath = dest,
      previewAnnotation = strategyName strat,
      previewModule = Map.lookup dest ownerMap
    }
opToPreview _ _ (CreateDirOp path) = DirPreview path
opToPreview mDiff ownerMap (CopyFileOp _ dest) =
  FilePreview
    { previewStatus = lookupStatus dest mDiff,
      previewPath = dest,
      previewAnnotation = "copy",
      previewModule = Map.lookup dest ownerMap
    }
opToPreview _ _ (RunCommandOp cmd _) = CommandPreview cmd
opToPreview mDiff ownerMap (PatchFileOp dest _ _patchOp' _ modName') =
  FilePreview
    { previewStatus = lookupStatus dest mDiff,
      previewPath = dest,
      previewAnnotation = "patch",
      previewModule = Just modName'
    }

-- | Look up a file's status in the diff result.
lookupStatus :: FilePath -> Maybe DiffResult -> FileStatus
lookupStatus _ Nothing = FsNew
lookupStatus path (Just diff)
  | any (\f -> f.path == path) diff.new = FsNew
  | any (\f -> f.path == path) diff.modified = FsModified
  | path `elem` diff.unchanged = FsUnchanged
  | any (\f -> f.path == path) diff.conflicts = FsConflict
  | any (\f -> f.path == path) diff.orphaned = FsOrphaned
  | otherwise = FsUnknown

-- | Render preview lines as plain text (no ANSI codes).
renderPreviewPlain :: [PreviewLine] -> Text
renderPreviewPlain lines' =
  if null lines'
    then "No operations to perform.\n"
    else T.unlines (map (renderPlainLine maxPathLen) fileLines ++ map renderNonFileLine nonFileLines)
  where
    fileLines = [l | l@(FilePreview {}) <- lines']
    nonFileLines = [l | l <- lines', not (isFileLine l)]
    maxPathLen = maximum (0 : map (T.length . T.pack . (.previewPath)) fileLines)

renderPlainLine :: Int -> PreviewLine -> Text
renderPlainLine maxPath (FilePreview status path annotation mMod) =
  let pathText = T.pack path
      pathPad = T.replicate (maxPath - T.length pathText) " "
      modSuffix = case mMod of
        Just mn -> ", " <> mn.unModuleName
        Nothing -> ""
   in "    " <> statusTag status <> "  " <> pathText <> pathPad <> "  (" <> annotation <> modSuffix <> ")"
renderPlainLine _ other = renderNonFileLine other

renderNonFileLine :: PreviewLine -> Text
renderNonFileLine (DirPreview path) =
  "    mkdir  " <> T.pack path
renderNonFileLine (CommandPreview cmd) =
  "    run    " <> cmd
renderNonFileLine (OrphanPreview path modName') =
  "    [orphaned]  " <> T.pack path <> "  (orphaned from " <> modName'.unModuleName <> ")"
renderNonFileLine _ = ""

isFileLine :: PreviewLine -> Bool
isFileLine (FilePreview {}) = True
isFileLine _ = False

statusTag :: FileStatus -> Text
statusTag FsNew = "[new]"
statusTag FsModified = "[modified]"
statusTag FsUnchanged = "[unchanged]"
statusTag FsConflict = "[conflict]"
statusTag FsOrphaned = "[orphaned]"
statusTag FsUnknown = "[unknown]"

strategyName :: Strategy -> Text
strategyName Copy = "copy"
strategyName Template = "template"
strategyName DhallText = "dhall-text"
strategyName Structured = "structured"

-- | Format a complete plan view with header, variables, operations, and summary.
formatPlanView :: [ModuleName] -> Map VarName VarValue -> [PreviewLine] -> DiffResult -> Text
formatPlanView moduleNames vars preview diff =
  T.unlines $
    [header, ""]
      ++ varsSection
      ++ ["  Operations:"]
      ++ map ("  " <>) (T.lines (renderPreviewPlain preview))
      ++ [""]
      ++ [summaryText]
  where
    header =
      "Generation Plan ("
        <> T.intercalate " + " (map (.unModuleName) moduleNames)
        <> "):"

    varsSection =
      if Map.null vars
        then []
        else
          "  Variables:"
            : map formatVar (Map.toAscList vars)
            ++ [""]

    maxVarLen = maximum (0 : map (\(VarName n, _) -> T.length n) (Map.toAscList vars))

    formatVar (VarName name, val) =
      let namePad = T.replicate (maxVarLen - T.length name) " "
       in "    " <> name <> namePad <> " = " <> showVarValue val

    showVarValue (VText t) = "\"" <> t <> "\""
    showVarValue (VBool True) = "true"
    showVarValue (VBool False) = "false"
    showVarValue (VInt n) = T.pack (show n)
    showVarValue (VList vs) = "[" <> T.intercalate ", " (map showVarValue vs) <> "]"

    nFiles = length diff.new + length diff.modified
    nConflicts = length diff.conflicts
    summaryText =
      "  "
        <> T.pack (show nFiles)
        <> " files to write, "
        <> T.pack (show nConflicts)
        <> " conflicts"

-- | Extract the destination path from a file-producing operation.
destOfOp :: Operation -> Maybe FilePath
destOfOp (WriteFileOp d _ _) = Just d
destOfOp (CopyFileOp _ d) = Just d
destOfOp (PatchFileOp d _ _ _ _) = Just d
destOfOp _ = Nothing
