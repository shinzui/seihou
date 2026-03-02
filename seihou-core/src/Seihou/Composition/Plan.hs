module Seihou.Composition.Plan
  ( compileComposedPlan,
    mergeOperations,
  )
where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Seihou.Core.Types
import Seihou.Engine.Plan (compilePlan)

-- | Compile plans for all modules in execution order and merge into a
-- single operation list. File conflicts are resolved by last-writer-wins
-- with 'CompositionWarning' entries for overwritten files.
compileComposedPlan ::
  [(Module, FilePath, Map VarName VarValue)] ->
  IO (Either [Text] ([Operation], [CompositionWarning]))
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
  ([Operation], [CompositionWarning])
mergeOperations moduleOps =
  let tagged = [(name, op) | (name, ops) <- moduleOps, op <- ops]
      (result, warnings) = go tagged Map.empty Set.empty [] []
   in (reverse result, warnings)
  where
    go [] _ _ opsAcc warningsAcc = (opsAcc, warningsAcc)
    go ((name, op) : rest) fileOwner seenDirs opsAcc warningsAcc =
      case op of
        CreateDirOp p
          | Set.member p seenDirs -> go rest fileOwner seenDirs opsAcc warningsAcc
          | otherwise -> go rest fileOwner (Set.insert p seenDirs) (op : opsAcc) warningsAcc
        WriteFileOp dest _ ->
          handleFileOp name op dest rest fileOwner seenDirs opsAcc warningsAcc
        CopyFileOp _ dest ->
          handleFileOp name op dest rest fileOwner seenDirs opsAcc warningsAcc
        RunCommandOp {} ->
          go rest fileOwner seenDirs (op : opsAcc) warningsAcc

    handleFileOp name op dest rest fileOwner seenDirs opsAcc warningsAcc =
      case Map.lookup dest fileOwner of
        Just prevName ->
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

-- | Extract the destination path from a file-producing operation.
destOfOp :: Operation -> Maybe FilePath
destOfOp (WriteFileOp d _) = Just d
destOfOp (CopyFileOp _ d) = Just d
destOfOp _ = Nothing

-- | Partition a list of Either into errors and successes.
partitionResults :: [Either e a] -> ([e], [a])
partitionResults = foldr step ([], [])
  where
    step (Left e) (errs, oks) = (e : errs, oks)
    step (Right a) (errs, oks) = (errs, a : oks)
