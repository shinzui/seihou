module Seihou.Composition.Plan
  ( compileComposedPlan,
    mergeOperations,
    mergeStructuredContent,
    deepMergeJSON,
  )
where

import Data.Aeson qualified as Aeson
import Data.Aeson.Encode.Pretty qualified as AesonPretty
import Data.Aeson.KeyMap qualified as KM
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.Lazy qualified as TL
import Data.Text.Lazy.Encoding qualified as TLE
import Data.Yaml qualified as Yaml
import Seihou.Core.Types
import Seihou.Engine.Plan (compilePlan)
import Seihou.Engine.Section (applyTextPatch)
import System.FilePath (takeExtension)

-- | Compile plans for all modules in execution order and merge into a
-- single operation list. File conflicts are resolved by last-writer-wins
-- with 'CompositionWarning' entries for overwritten files.
compileComposedPlan ::
  [(Module, FilePath, Map VarName VarValue)] ->
  IO (Either [Text] ([Operation], [CompositionWarning], Map FilePath ModuleName))
compileComposedPlan modules = do
  results <- mapM compileOne modules
  let (errs, opsPerModule) = partitionResults results
  if null errs
    then pure (Right (mergeOperations opsPerModule))
    else pure (Left (concat errs))
  where
    compileOne (m, dir, vars) = do
      result <- compilePlan dir m vars
      case result of
        Left errs -> pure (Left errs)
        Right ops -> pure (Right (moduleName m, ops))

-- | Merge operation lists from multiple modules, handling file conflicts.
--
-- When two modules produce a 'WriteFileOp' or 'CopyFileOp' targeting the
-- same destination path, the later module (later in execution order) wins
-- and a 'FileOverwritten' warning is recorded.
--
-- 'CreateDirOp' operations are silently deduplicated.
-- 'RunCommandOp' operations are always included.
mergeOperations ::
  [(ModuleName, [Operation])] ->
  ([Operation], [CompositionWarning], Map FilePath ModuleName)
mergeOperations moduleOps =
  let tagged = [(name, op) | (name, ops) <- moduleOps, op <- ops]
      (result, warnings, owners) = go tagged Map.empty Set.empty [] []
   in (reverse result, warnings, owners)
  where
    go [] fileOwner _ opsAcc warningsAcc = (opsAcc, warningsAcc, fileOwner)
    go ((name, op) : rest) fileOwner seenDirs opsAcc warningsAcc =
      case op of
        CreateDirOp p
          | Set.member p seenDirs -> go rest fileOwner seenDirs opsAcc warningsAcc
          | otherwise -> go rest fileOwner (Set.insert p seenDirs) (op : opsAcc) warningsAcc
        WriteFileOp dest _ _ ->
          handleFileOp name op dest rest fileOwner seenDirs opsAcc warningsAcc
        CopyFileOp _ dest ->
          handleFileOp name op dest rest fileOwner seenDirs opsAcc warningsAcc
        RunCommandOp {} ->
          go rest fileOwner seenDirs (op : opsAcc) warningsAcc
        PatchFileOp dest newContent patchOp' _ patchModName ->
          handlePatchOp name dest newContent patchOp' patchModName rest fileOwner seenDirs opsAcc warningsAcc

    -- \| Handle a PatchFileOp: if the target file exists in the accumulator,
    -- apply the patch to the existing content. Otherwise, treat it like a
    -- new file operation (the patch creates the file from empty).
    handlePatchOp name dest newContent patchOp' patchModName rest fileOwner seenDirs opsAcc warningsAcc =
      case findWriteOp dest opsAcc of
        Just (WriteFileOp _ existingContent strat, otherOps) ->
          -- Apply patch to the existing WriteFileOp's content
          case applyTextPatch patchOp' patchModName "#" existingContent newContent of
            Left _err ->
              -- On patch failure, fall back to last-writer-wins
              handleFileOp name (WriteFileOp dest newContent Template) dest rest fileOwner seenDirs opsAcc warningsAcc
            Right merged ->
              let baseName = case Map.lookup dest fileOwner of
                    Just n -> n
                    Nothing -> name
                  updatedOp = WriteFileOp dest merged strat
               in go
                    rest
                    (Map.insert dest name fileOwner)
                    seenDirs
                    (updatedOp : otherOps)
                    (ContentMerged dest baseName name : warningsAcc)
        _ ->
          -- No existing file op for this dest; treat as a new file op
          handleFileOp name (WriteFileOp dest newContent Template) dest rest fileOwner seenDirs opsAcc warningsAcc

    handleFileOp name op dest rest fileOwner seenDirs opsAcc warningsAcc =
      case Map.lookup dest fileOwner of
        Just prevName ->
          -- Check for structured merge: both ops are WriteFileOp with Structured strategy
          case (findWriteOp dest opsAcc, op) of
            (Just (WriteFileOp _ existingContent Structured, otherOps), WriteFileOp _ newContent Structured) ->
              case mergeStructuredContent dest existingContent newContent of
                Right merged ->
                  let updatedOp = WriteFileOp dest merged Structured
                   in go
                        rest
                        (Map.insert dest name fileOwner)
                        seenDirs
                        (updatedOp : otherOps)
                        (ContentMerged dest prevName name : warningsAcc)
                Left _ ->
                  -- On merge failure, fall back to last-writer-wins
                  let opsAcc' = op : filter (\old -> destOfOp old /= Just dest) opsAcc
                   in go
                        rest
                        (Map.insert dest name fileOwner)
                        seenDirs
                        opsAcc'
                        (FileOverwritten dest prevName name : warningsAcc)
            _ ->
              -- Default: last-writer-wins
              let opsAcc' = op : filter (\old -> destOfOp old /= Just dest) opsAcc
               in go
                    rest
                    (Map.insert dest name fileOwner)
                    seenDirs
                    opsAcc'
                    (FileOverwritten dest prevName name : warningsAcc)
        Nothing ->
          go
            rest
            (Map.insert dest name fileOwner)
            seenDirs
            (op : opsAcc)
            warningsAcc

-- | Find and extract a WriteFileOp targeting a given destination from the ops accumulator.
-- Returns the matching op and the remaining ops (with it removed).
findWriteOp :: FilePath -> [Operation] -> Maybe (Operation, [Operation])
findWriteOp _ [] = Nothing
findWriteOp dest (op@(WriteFileOp d _ _) : rest)
  | d == dest = Just (op, rest)
findWriteOp dest (op : rest) =
  case findWriteOp dest rest of
    Just (found, remaining) -> Just (found, op : remaining)
    Nothing -> Nothing

-- | Extract the destination path from a file-producing operation.
destOfOp :: Operation -> Maybe FilePath
destOfOp (WriteFileOp d _ _) = Just d
destOfOp (CopyFileOp _ d) = Just d
destOfOp (PatchFileOp d _ _ _ _) = Just d
destOfOp _ = Nothing

-- | Merge two serialized structured files (JSON or YAML) by deep-merging
-- their contents. The file extension determines the parse/serialize format.
-- Right-biased: overlapping scalar keys take the overlay's value; nested
-- objects are merged recursively.
mergeStructuredContent :: FilePath -> Text -> Text -> Either Text Text
mergeStructuredContent dest base overlay = do
  baseVal <- parseStructured dest base
  overlayVal <- parseStructured dest overlay
  let merged = deepMergeJSON baseVal overlayVal
  serializeStructured dest merged

-- | Parse serialized content based on file extension.
parseStructured :: FilePath -> Text -> Either Text Aeson.Value
parseStructured dest content =
  case takeExtension dest of
    ".json" ->
      case Aeson.eitherDecodeStrict' (TE.encodeUtf8 content) of
        Left err -> Left ("Failed to parse JSON in " <> T.pack dest <> ": " <> T.pack err)
        Right val -> Right val
    ".yaml" -> parseYaml dest content
    ".yml" -> parseYaml dest content
    ext -> Left ("Structured merge: unsupported format '" <> T.pack ext <> "'")
  where
    parseYaml d c =
      case Yaml.decodeEither' (TE.encodeUtf8 c) of
        Left err -> Left ("Failed to parse YAML in " <> T.pack d <> ": " <> T.pack (show err))
        Right val -> Right val

-- | Serialize a JSON value based on file extension.
serializeStructured :: FilePath -> Aeson.Value -> Either Text Text
serializeStructured dest value =
  case takeExtension dest of
    ".json" -> Right (TL.toStrict (TLE.decodeUtf8 (AesonPretty.encodePretty value)) <> "\n")
    ".yaml" -> Right (TE.decodeUtf8 (Yaml.encode value))
    ".yml" -> Right (TE.decodeUtf8 (Yaml.encode value))
    ext -> Left ("Structured merge: unsupported format '" <> T.pack ext <> "'")

-- | Deep-merge two JSON values. For objects, keys are merged recursively.
-- For all other types, the right (overlay) value wins.
deepMergeJSON :: Aeson.Value -> Aeson.Value -> Aeson.Value
deepMergeJSON (Aeson.Object base) (Aeson.Object overlay) =
  Aeson.Object (KM.unionWith deepMergeJSON base overlay)
deepMergeJSON _ overlay = overlay

-- | Partition a list of Either into errors and successes.
partitionResults :: [Either e a] -> ([e], [a])
partitionResults = foldr step ([], [])
  where
    step (Left e) (errs, oks) = (e : errs, oks)
    step (Right a) (errs, oks) = (errs, a : oks)
