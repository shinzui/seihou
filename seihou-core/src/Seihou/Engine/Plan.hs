module Seihou.Engine.Plan
  ( compilePlan,
    parentDirs,
  )
where

import Control.Exception (IOException, SomeException, catch, try)
import Data.Map.Strict (Map)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Dhall qualified
import Seihou.Core.Expr (evalExpr)
import Seihou.Core.Types
import Seihou.Engine.Template (renderDestPath, renderTemplate)
import System.FilePath (takeDirectory, (</>))

-- | Compile a module's steps into a list of filesystem operations.
-- Evaluates @when@ conditions, dispatches by strategy, reads source files,
-- renders templates, and expands destination paths.
compilePlan ::
  FilePath -> -- Module base directory (containing @files/@)
  Module ->
  Map VarName VarValue -> -- Resolved variable values
  IO (Either [Text] [Operation])
compilePlan baseDir modul vars = do
  results <- mapM (compileStep baseDir vars) (moduleSteps modul)
  let (allErrors, allOps) = partitionResults results
  if null allErrors
    then Right <$> pure (deduplicateDirs (concat allOps))
    else pure (Left (concat allErrors))

-- | Compile a single step into operations (or skip it).
compileStep ::
  FilePath ->
  Map VarName VarValue ->
  Step ->
  IO (Either [Text] [Operation])
compileStep baseDir vars step = do
  -- Evaluate the when condition
  let shouldRun = case stepWhen step of
        Nothing -> True
        Just expr -> evalExpr vars expr
  if not shouldRun
    then pure (Right [])
    else case stepStrategy step of
      Copy -> compileCopyStep baseDir vars step
      Template -> compileTemplateStep baseDir vars step
      DhallText -> compileDhallTextStep baseDir vars step
      Structured -> pure (Left ["Structured strategy not yet implemented"])

-- | Compile a Copy step: read the source file and write it to the destination.
compileCopyStep ::
  FilePath ->
  Map VarName VarValue ->
  Step ->
  IO (Either [Text] [Operation])
compileCopyStep baseDir vars step = do
  let srcPath = baseDir </> "files" </> stepSrc step
  result <- tryReadFile srcPath
  case result of
    Left err -> pure (Left [err])
    Right content ->
      case renderDestPath (stepDest step) vars of
        Left placeholderErrors ->
          pure (Left (map formatPlaceholderError placeholderErrors))
        Right dest -> do
          let destStr = T.unpack dest
              dirOps = map (CreateDirOp . T.unpack) (parentDirs dest)
          pure (Right (dirOps ++ [WriteFileOp destStr content]))

-- | Compile a Template step: read, render placeholders, write.
compileTemplateStep ::
  FilePath ->
  Map VarName VarValue ->
  Step ->
  IO (Either [Text] [Operation])
compileTemplateStep baseDir vars step = do
  let srcPath = baseDir </> "files" </> stepSrc step
  result <- tryReadFile srcPath
  case result of
    Left err -> pure (Left [err])
    Right content ->
      case renderTemplate content vars of
        Left placeholderErrors ->
          pure (Left (map formatPlaceholderError placeholderErrors))
        Right rendered ->
          case renderDestPath (stepDest step) vars of
            Left placeholderErrors ->
              pure (Left (map formatPlaceholderError placeholderErrors))
            Right dest -> do
              let destStr = T.unpack dest
                  dirOps = map (CreateDirOp . T.unpack) (parentDirs dest)
              pure (Right (dirOps ++ [WriteFileOp destStr rendered]))

-- | Compile a DhallText step: read source, substitute placeholders, evaluate as Dhall.
compileDhallTextStep ::
  FilePath ->
  Map VarName VarValue ->
  Step ->
  IO (Either [Text] [Operation])
compileDhallTextStep baseDir vars step = do
  let srcPath = baseDir </> "files" </> stepSrc step
  result <- tryReadFile srcPath
  case result of
    Left err -> pure (Left [err])
    Right content ->
      case renderTemplate content vars of
        Left placeholderErrors ->
          pure (Left (map formatPlaceholderError placeholderErrors))
        Right substituted -> do
          dhallResult <- renderDhallText substituted
          case dhallResult of
            Left err -> pure (Left [err])
            Right evaluated ->
              case renderDestPath (stepDest step) vars of
                Left placeholderErrors ->
                  pure (Left (map formatPlaceholderError placeholderErrors))
                Right dest -> do
                  let destStr = T.unpack dest
                      dirOps = map (CreateDirOp . T.unpack) (parentDirs dest)
                  pure (Right (dirOps ++ [WriteFileOp destStr evaluated]))

-- | Evaluate a Dhall expression that produces Text.
renderDhallText :: Text -> IO (Either Text Text)
renderDhallText dhallSource = do
  result <- try (Dhall.input Dhall.strictText dhallSource)
  case result of
    Left (e :: SomeException) ->
      pure (Left ("Dhall evaluation failed: " <> T.pack (show e)))
    Right t -> pure (Right t)

-- | Extract parent directories from a path.
-- @"src/Lib.hs"@ produces @["src"]@.
-- @"a/b/c.txt"@ produces @["a", "a/b"]@.
parentDirs :: Text -> [Text]
parentDirs path =
  let dir = T.pack (takeDirectory (T.unpack path))
   in if dir == "." || T.null dir
        then []
        else buildChain dir

-- | Build the chain of parent directories.
-- @"a/b"@ produces @["a", "a/b"]@.
buildChain :: Text -> [Text]
buildChain dir =
  let parts = T.splitOn "/" dir
      prefixes = drop 1 (scanl (\acc p -> acc <> "/" <> p) "" parts)
      trimmed = map (T.drop 1) prefixes -- remove leading /
   in trimmed

-- | Try to read a file, returning an error message on failure.
tryReadFile :: FilePath -> IO (Either Text Text)
tryReadFile path =
  (Right <$> TIO.readFile path) `catch` handler
  where
    handler :: IOException -> IO (Either Text Text)
    handler e = pure (Left ("failed to read file: " <> T.pack path <> ": " <> T.pack (show e)))

-- | Format a placeholder error as a human-readable text message.
formatPlaceholderError :: PlaceholderError -> Text
formatPlaceholderError (UnresolvedPlaceholder (VarName name) lineNum) =
  "unresolved placeholder '{{" <> name <> "}}' at line " <> T.pack (show lineNum)
formatPlaceholderError (MalformedPlaceholder raw lineNum) =
  "malformed placeholder '" <> raw <> "' at line " <> T.pack (show lineNum)

-- | Deduplicate CreateDirOp operations while preserving order.
deduplicateDirs :: [Operation] -> [Operation]
deduplicateDirs = go Set.empty
  where
    go _ [] = []
    go seen (op@(CreateDirOp p) : rest)
      | p `Set.member` seen = go seen rest
      | otherwise = op : go (Set.insert p seen) rest
    go seen (op : rest) = op : go seen rest

-- | Partition a list of Either into errors and successes.
partitionResults :: [Either e a] -> ([e], [a])
partitionResults = foldr step ([], [])
  where
    step (Left e) (errs, oks) = (e : errs, oks)
    step (Right a) (errs, oks) = (errs, a : oks)
