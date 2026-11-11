-- | @seihou validate-judgement@: every problem with a judgement artifact,
-- named, before any provider call.
--
-- A target is a directory holding @judgement.dhall@ (and optionally
-- @examples.json@), a path to that file, or a judgement name found through
-- the ordinary search paths. Validation decodes the definition, checks it
-- structurally, checks the examples against it, and, when the scanner is
-- available, scans every example's contents so a real credential is caught
-- before evaluation could send it anywhere.
module Seihou.CLI.Judgement.Validate
  ( JudgementValidation (..),
    resolveJudgementTarget,
    discoverJudgementNames,
    activeJudgementNames,
    validateJudgementDir,
    loadExamples,
    renderValidation,
    exampleEvidence,
  )
where

import Control.Monad (filterM, forM)
import Data.ByteString.Lazy qualified as LBS
import Data.Containers.ListUtils (nubOrd)
import Data.Generics.Labels ()
import Data.List (isPrefixOf)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Seihou.CLI.Judgement.Evidence (EvidenceFile (..), FileChange (..))
import Seihou.CLI.Judgement.Scanner (findScanner, flaggedPaths, scanCaptured)
import Seihou.Core.Judgement
import Seihou.Core.JudgementExamples
import Seihou.Core.Module (defaultSearchPaths)
import Seihou.Core.Types (ModuleLoadError (..))
import Seihou.Dhall.Eval (evalJudgementFromFile)
import Seihou.Effect.FilesystemInterp (runFilesystem)
import Seihou.Effect.ManifestStore (readManifest)
import Seihou.Effect.ManifestStoreInterp (runManifestStore)
import Seihou.Prelude
import System.Directory (doesDirectoryExist, doesFileExist, listDirectory)
import System.FilePath (takeDirectory, takeFileName)

data JudgementValidation = JudgementValidation
  { dir :: !FilePath,
    definition :: !(Maybe JudgementDefinition),
    examples :: !(Maybe JudgementExamples),
    errors :: ![JudgementError],
    -- | Advisory notes that do not fail validation.
    notes :: ![Text]
  }
  deriving stock (Eq, Show, Generic)

-- | A path to a directory or @judgement.dhall@, or a name to discover.
resolveJudgementTarget :: Maybe Text -> IO (Either Text FilePath)
resolveJudgementTarget = \case
  Nothing -> pure (Right ".")
  Just t -> do
    let p = T.unpack t
    isDir <- doesDirectoryExist p
    isFile <- doesFileExist p
    case () of
      _
        | isDir -> pure (Right p)
        | isFile && takeFileName p == "judgement.dhall" -> pure (Right (takeDirectory p))
        | otherwise -> do
            roots <- defaultSearchPaths
            found <- filterM (\r -> doesFileExist (r </> p </> "judgement.dhall")) roots
            pure $ case found of
              (r : _) -> Right (r </> p)
              [] -> Left ("No judgement '" <> t <> "' was found as a path or in " <> T.intercalate ", " (map T.pack roots))
  where
    filterM f = foldr (\x acc -> f x >>= \keep -> (if keep then (x :) else id) <$> acc) (pure [])

-- | The evidence an example stands for, one file per example file, keyed
-- @<example id>/<path>@ so cases never collide.
exampleEvidence :: JudgementExample -> [EvidenceFile]
exampleEvidence e =
  [ EvidenceFile (T.unpack (e ^. #id) </> f ^. #path) Added "100644" Nothing Nothing (Just (TE.encodeUtf8 (f ^. #content))) Nothing Nothing
  | f <- e ^. #files
  ]

loadExamples :: FilePath -> JudgementDefinition -> IO (Either [JudgementError] (Maybe JudgementExamples))
loadExamples dir def = do
  let file = dir </> "examples.json"
  present <- doesFileExist file
  if not present
    then pure (Right Nothing)
    else do
      bytes <- LBS.readFile file
      pure $ case parseExamples "examples.json" bytes of
        Left err -> Left [err]
        Right ex -> case validateExamples def ex of
          [] -> Right (Just ex)
          errs -> Left errs

validateJudgementDir :: FilePath -> IO JudgementValidation
validateJudgementDir dir = do
  let file = dir </> "judgement.dhall"
  present <- doesFileExist file
  if not present
    then pure (JudgementValidation dir Nothing Nothing [judgementError "judgement_missing" (T.pack file <> " does not exist")] [])
    else
      evalJudgementFromFile file >>= \case
        Left err -> pure (JudgementValidation dir Nothing Nothing [judgementError "judgement_decode" (loadErrorText err)] [])
        Right def -> case validateDefinition def of
          Left err -> pure (JudgementValidation dir (Just def) Nothing [err] [])
          Right () ->
            loadExamples dir def >>= \case
              Left errs -> pure (JudgementValidation dir (Just def) Nothing errs [])
              Right Nothing -> pure (JudgementValidation dir (Just def) Nothing [] ["no examples.json; judgement eval needs labelled examples"])
              Right (Just ex) -> do
                (scanErrors, scanNotes) <- scanExamples def ex
                pure (JudgementValidation dir (Just def) (Just ex) scanErrors scanNotes)
  where
    loadErrorText = \case
      DhallEvalError _ reason -> T.take 2000 reason
      DhallDecodeError _ reason -> T.take 2000 reason
      _ -> "judgement.dhall could not be loaded"

-- | Scan the examples. A hit is an error unless the judgement declares the
-- secret scan and the example expects a block: that material is stopped by
-- the scanner before any request, so it is a valid deterministic case.
scanExamples :: JudgementDefinition -> JudgementExamples -> IO ([JudgementError], [Text])
scanExamples def ex =
  findScanner >>= \case
    Nothing -> pure ([], ["gitleaks was not found, so the examples were not scanned for credentials"])
    Just sc -> do
      let files = concatMap exampleEvidence (ex ^. #examples)
          expectsBlock e = ExpectBlocked `elem` Map.elems (e ^. #expect)
          allowed = [T.unpack (e ^. #id) | SecretScan `elem` (def ^. #deterministicChecks), e <- ex ^. #examples, expectsBlock e]
          exempt p = any (\i -> (i <> "/") `isPrefixOf` p) allowed
      scanCaptured sc files [] <&> \case
        Left err -> ([judgementError "judgement_examples_scan_failed" ("the examples could not be scanned: " <> err)], [])
        Right result ->
          ( [ judgementError "judgement_example_secret" ("'" <> T.pack p <> "' looks like a real credential to the secret scanner; examples must be synthetic, and only a block expected under the declared secret scan may contain one")
            | p <- flaggedPaths result,
              not (exempt p)
            ],
            []
          )

renderValidation :: JudgementValidation -> Text
renderValidation v =
  T.unlines $
    [ case v ^. #definition of
        Just d -> "Judgement '" <> d ^. #name <> "' " <> fromMaybe "(unversioned)" (d ^. #version) <> " at " <> T.pack (v ^. #dir)
        Nothing -> "Judgement at " <> T.pack (v ^. #dir)
    ]
      <> ["  error " <> e ^. #code <> ": " <> e ^. #message | e <- v ^. #errors]
      <> ["  note: " <> n | n <- v ^. #notes]
      <> [ if null (v ^. #errors)
             then "  valid: " <> maybe "" (\d -> T.pack (show (length (d ^. #checks))) <> " check(s)") (v ^. #definition) <> maybe "" (\e -> ", " <> T.pack (show (length (e ^. #examples))) <> " example(s)") (v ^. #examples)
             else "  invalid: " <> T.pack (show (length (v ^. #errors))) <> " problem(s)"
         ]

-- | The names of judgements in the standard search paths, for shell
-- completion: each directory holding a @judgement.dhall@. Nothing is
-- evaluated, so completion stays fast and never fails.
discoverJudgementNames :: IO [String]
discoverJudgementNames = do
  paths <- defaultSearchPaths
  found <- forM paths $ \dir -> do
    present <- doesDirectoryExist dir
    if not present
      then pure []
      else do
        entries <- listDirectory dir
        filterM (\e -> doesFileExist (dir </> e </> "judgement.dhall")) entries
  pure (nubOrd (concat found))

-- | The names of the judgements active in the project at this directory,
-- read from its manifest without changing anything.
activeJudgementNames :: FilePath -> IO [String]
activeJudgementNames root =
  runEff (runFilesystem (runManifestStore (root </> ".seihou" </> "manifest.json") readManifest)) <&> \case
    Right (Just m) -> [T.unpack (j ^. #definition . #name) | j <- m ^. #judgements]
    _ -> []
