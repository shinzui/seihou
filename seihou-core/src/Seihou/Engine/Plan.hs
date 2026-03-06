module Seihou.Engine.Plan
  ( compilePlan,
    parentDirs,
  )
where

import Control.Exception (IOException, SomeException, catch, try)
import Data.Aeson qualified as Aeson
import Data.Aeson.Encode.Pretty qualified as AesonPretty
import Data.Set qualified as Set
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Data.Text.Lazy qualified as TL
import Data.Text.Lazy.Encoding qualified as TLE
import Data.Void (Void)
import Data.Yaml qualified as Yaml
import Dhall qualified
import Dhall.Core qualified as DhallCore
import Dhall.Src (Src)
import Seihou.Core.Expr (evalExpr)
import Seihou.Core.Types
import Seihou.Engine.DhallJSON (dhallExprToJSON)
import Seihou.Engine.Template (renderDestPath, renderTemplate)
import Seihou.Prelude
import System.FilePath (takeDirectory, takeExtension)

-- | Compile a module's steps into a list of filesystem operations.
-- Evaluates @when@ conditions, dispatches by strategy, reads source files,
-- renders templates, and expands destination paths.
compilePlan ::
  FilePath -> -- Module base directory (containing @files/@)
  Module ->
  Map VarName VarValue -> -- Resolved variable values
  IO (Either [Text] [Operation])
compilePlan baseDir modul vars = do
  let modName = modul.name
  results <- mapM (compileStep baseDir modName vars) modul.steps
  let (allErrors, allOps) = partitionResults results
  if null allErrors
    then Right <$> pure (deduplicateDirs (concat allOps) ++ compileCommands vars modul.commands)
    else pure (Left (concat allErrors))

-- | Compile commands into 'RunCommandOp' operations.
-- Commands whose @when@ condition evaluates to False are skipped.
compileCommands :: Map VarName VarValue -> [Command] -> [Operation]
compileCommands vars = concatMap compileCommand
  where
    compileCommand cmd =
      let shouldRun = case cmd.condition of
            Nothing -> True
            Just expr -> evalExpr vars expr
       in if shouldRun
            then [RunCommandOp cmd.run (fmap T.unpack cmd.workDir)]
            else []

-- | Compile a single step into operations (or skip it).
-- If the step has a patch operation, it produces a 'PatchFileOp'; otherwise
-- dispatches by strategy to produce a 'WriteFileOp'.
compileStep ::
  FilePath ->
  ModuleName ->
  Map VarName VarValue ->
  Step ->
  IO (Either [Text] [Operation])
compileStep baseDir modName vars step = do
  -- Evaluate the when condition
  let shouldRun = case step.condition of
        Nothing -> True
        Just expr -> evalExpr vars expr
  if not shouldRun
    then pure (Right [])
    else case step.patch of
      Just _ -> compilePatchStep baseDir vars modName step
      Nothing -> case step.strategy of
        Copy -> compileCopyStep baseDir vars step
        Template -> compileTemplateStep baseDir vars step
        DhallText -> compileDhallTextStep baseDir vars step
        Structured -> compileStructuredStep baseDir vars step

-- | Compile a Copy step: read the source file and write it to the destination.
compileCopyStep ::
  FilePath ->
  Map VarName VarValue ->
  Step ->
  IO (Either [Text] [Operation])
compileCopyStep baseDir vars step = do
  let srcPath = baseDir </> "files" </> step.src
  result <- tryReadFile srcPath
  case result of
    Left err -> pure (Left [err])
    Right content ->
      case renderDestPath step.dest vars of
        Left placeholderErrors ->
          pure (Left (map formatPlaceholderError placeholderErrors))
        Right dest -> do
          let destStr = T.unpack dest
              dirOps = map (CreateDirOp . T.unpack) (parentDirs dest)
          pure (Right (dirOps ++ [WriteFileOp destStr content Copy]))

-- | Compile a Template step: read, render placeholders, write.
compileTemplateStep ::
  FilePath ->
  Map VarName VarValue ->
  Step ->
  IO (Either [Text] [Operation])
compileTemplateStep baseDir vars step = do
  let srcPath = baseDir </> "files" </> step.src
  result <- tryReadFile srcPath
  case result of
    Left err -> pure (Left [err])
    Right content ->
      case renderTemplate content vars of
        Left placeholderErrors ->
          pure (Left (map formatPlaceholderError placeholderErrors))
        Right rendered ->
          case renderDestPath step.dest vars of
            Left placeholderErrors ->
              pure (Left (map formatPlaceholderError placeholderErrors))
            Right dest -> do
              let destStr = T.unpack dest
                  dirOps = map (CreateDirOp . T.unpack) (parentDirs dest)
              pure (Right (dirOps ++ [WriteFileOp destStr rendered Template]))

-- | Compile a DhallText step: read source, substitute placeholders, evaluate as Dhall.
compileDhallTextStep ::
  FilePath ->
  Map VarName VarValue ->
  Step ->
  IO (Either [Text] [Operation])
compileDhallTextStep baseDir vars step = do
  let srcPath = baseDir </> "files" </> step.src
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
              case renderDestPath step.dest vars of
                Left placeholderErrors ->
                  pure (Left (map formatPlaceholderError placeholderErrors))
                Right dest -> do
                  let destStr = T.unpack dest
                      dirOps = map (CreateDirOp . T.unpack) (parentDirs dest)
                  pure (Right (dirOps ++ [WriteFileOp destStr evaluated DhallText]))

-- | Compile a Structured step: read source, substitute placeholders, evaluate as Dhall,
-- then serialize to JSON or YAML based on the destination file extension.
compileStructuredStep ::
  FilePath ->
  Map VarName VarValue ->
  Step ->
  IO (Either [Text] [Operation])
compileStructuredStep baseDir vars step = do
  let srcPath = baseDir </> "files" </> step.src
  result <- tryReadFile srcPath
  case result of
    Left err -> pure (Left [err])
    Right content ->
      case renderTemplate content vars of
        Left placeholderErrors ->
          pure (Left (map formatPlaceholderError placeholderErrors))
        Right substituted -> do
          dhallResult <- evaluateDhallExpr substituted
          case dhallResult of
            Left err -> pure (Left [err])
            Right dhallExpr ->
              case dhallExprToJSON dhallExpr of
                Left err -> pure (Left [err])
                Right jsonValue ->
                  case renderDestPath step.dest vars of
                    Left placeholderErrors ->
                      pure (Left (map formatPlaceholderError placeholderErrors))
                    Right dest ->
                      case serializeByExtension (T.unpack dest) jsonValue of
                        Left err -> pure (Left [err])
                        Right serialized -> do
                          let destStr = T.unpack dest
                              dirOps = map (CreateDirOp . T.unpack) (parentDirs dest)
                          pure (Right (dirOps ++ [WriteFileOp destStr serialized Structured]))

-- | Compile a patch step: read source, render template, produce PatchFileOp.
-- The content rendering follows the step's strategy (Template renders placeholders,
-- Copy uses raw content, DhallText evaluates as Dhall).
compilePatchStep ::
  FilePath ->
  Map VarName VarValue ->
  ModuleName ->
  Step ->
  IO (Either [Text] [Operation])
compilePatchStep baseDir vars modName step = do
  let srcPath = baseDir </> "files" </> step.src
      patchOp' = case step.patch of
        Just p -> p
        Nothing -> error "compilePatchStep called without patch op"
  result <- tryReadFile srcPath
  case result of
    Left err -> pure (Left [err])
    Right rawContent -> do
      -- Render content based on strategy
      contentResult <- case step.strategy of
        Copy -> pure (Right rawContent)
        Template ->
          pure $ case renderTemplate rawContent vars of
            Left placeholderErrors -> Left (map formatPlaceholderError placeholderErrors)
            Right rendered -> Right rendered
        DhallText -> do
          case renderTemplate rawContent vars of
            Left placeholderErrors -> pure (Left (map formatPlaceholderError placeholderErrors))
            Right substituted -> do
              dhallResult <- renderDhallText substituted
              case dhallResult of
                Left err -> pure (Left [err])
                Right evaluated -> pure (Right evaluated)
        Structured ->
          pure (Left ["Structured strategy cannot be used with patch operations"])
      case contentResult of
        Left errs -> pure (Left errs)
        Right content ->
          case renderDestPath step.dest vars of
            Left placeholderErrors ->
              pure (Left (map formatPlaceholderError placeholderErrors))
            Right dest -> do
              let destStr = T.unpack dest
                  dirOps = map (CreateDirOp . T.unpack) (parentDirs dest)
              pure (Right (dirOps ++ [PatchFileOp destStr content patchOp' step.strategy modName]))

-- | Evaluate a Dhall expression and return the normalized AST.
evaluateDhallExpr :: Text -> IO (Either Text (DhallCore.Expr Src Void))
evaluateDhallExpr dhallSource = do
  result <- try (Dhall.inputExpr dhallSource)
  case result of
    Left (e :: SomeException) ->
      pure (Left ("Dhall evaluation failed: " <> T.pack (show e)))
    Right expr -> pure (Right expr)

-- | Serialize a JSON Value to Text based on the destination file extension.
-- .json → pretty-printed JSON; .yaml or .yml → YAML; other → error.
serializeByExtension :: FilePath -> Aeson.Value -> Either Text Text
serializeByExtension dest value =
  case takeExtension dest of
    ".json" -> Right (TL.toStrict (TLE.decodeUtf8 (AesonPretty.encodePretty value)) <> "\n")
    ".yaml" -> Right (TE.decodeUtf8 (Yaml.encode value))
    ".yml" -> Right (TE.decodeUtf8 (Yaml.encode value))
    ext -> Left ("Structured strategy: unsupported output format '" <> T.pack ext <> "' (expected .json, .yaml, or .yml)")

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
