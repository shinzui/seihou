-- | Labelled examples for a judgement: synthetic changes and the outcome
-- each check should reach on them.
--
-- An @examples.json@ file sits beside @judgement.dhall@. Its cases are
-- synthetic by contract: evaluation submits them to a model, and a scanner
-- pass over them runs first. Validation here is structural and needs only
-- the definition, so @validate-judgement@ can name every problem before any
-- provider call.
--
-- Format, version 1:
--
-- > { "version": 1,
-- >   "examples": [
-- >     { "id": "benign-readme",
-- >       "description": "A documentation-only change",
-- >       "files": [ { "path": "README.md", "content": "..." } ],
-- >       "expect": { "stale-docs": "passed", "has-example": "blocked" },
-- >       "findings": [ { "check": "has-example", "category": "missing-example", "path": "README.md", "line": 3 } ] } ] }
--
-- @expect@ maps check names to @passed@, @blocked@ or @needs-review@; a
-- check left out is not scored on that case. @findings@ is optional.
module Seihou.Core.JudgementExamples
  ( ExampleFile (..),
    ExpectedFinding (..),
    JudgementExample (..),
    JudgementExamples (..),
    ExpectedStatus (..),
    renderExpectedStatus,
    parseExamples,
    validateExamples,
  )
where

import Control.Monad (forM_, when)
import Data.Aeson (FromJSON (..), withObject, (.:), (.:?))
import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy qualified as LBS
import Data.Foldable (toList)
import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text qualified as T
import Seihou.Core.Judgement
import Seihou.Prelude hiding ((.=))

data ExpectedStatus = ExpectPassed | ExpectBlocked | ExpectNeedsReview
  deriving stock (Eq, Ord, Show, Bounded, Enum, Generic)

renderExpectedStatus :: ExpectedStatus -> Text
renderExpectedStatus = \case
  ExpectPassed -> "passed"
  ExpectBlocked -> "blocked"
  ExpectNeedsReview -> "needs-review"

data ExampleFile = ExampleFile {path :: !FilePath, content :: !Text}
  deriving stock (Eq, Show, Generic)

data ExpectedFinding = ExpectedFinding
  { check :: !Text,
    category :: !Text,
    path :: !FilePath,
    line :: !(Maybe Int)
  }
  deriving stock (Eq, Show, Generic)

data JudgementExample = JudgementExample
  { id :: !Text,
    description :: !(Maybe Text),
    files :: ![ExampleFile],
    expect :: !(Map Text ExpectedStatus),
    findings :: ![ExpectedFinding]
  }
  deriving stock (Eq, Show, Generic)

data JudgementExamples = JudgementExamples
  { version :: !Int,
    examples :: ![JudgementExample]
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON ExpectedStatus where
  parseJSON = Aeson.withText "ExpectedStatus" $ \t -> case [s | s <- [minBound .. maxBound], renderExpectedStatus s == t] of
    [s] -> pure s
    _ -> fail ("unknown expected status '" <> T.unpack t <> "'; expected passed, blocked or needs-review")

instance FromJSON ExampleFile where
  parseJSON = withObject "ExampleFile" $ \o -> ExampleFile <$> o .: "path" <*> o .: "content"

instance FromJSON ExpectedFinding where
  parseJSON = withObject "ExpectedFinding" $ \o -> ExpectedFinding <$> o .: "check" <*> o .: "category" <*> o .: "path" <*> o .:? "line"

instance FromJSON JudgementExample where
  parseJSON = withObject "JudgementExample" $ \o ->
    JudgementExample
      <$> o .: "id"
      <*> o .:? "description"
      <*> o .: "files"
      <*> o .: "expect"
      <*> (fromMaybe [] <$> o .:? "findings")

instance FromJSON JudgementExamples where
  parseJSON = withObject "JudgementExamples" $ \o -> JudgementExamples <$> o .: "version" <*> o .: "examples"

-- | Decode @examples.json@ bytes, naming the file in the error.
parseExamples :: FilePath -> LBS.ByteString -> Either JudgementError JudgementExamples
parseExamples file bytes = case Aeson.eitherDecode bytes of
  Left err -> Left (judgementError "judgement_examples_malformed" (T.pack file <> " is not a valid examples file: " <> T.pack err))
  Right ex
    | ex ^. #version /= 1 -> Left (judgementError "judgement_examples_version" (T.pack file <> " has version " <> T.pack (show (ex ^. #version)) <> "; this seihou reads version 1"))
    | otherwise -> Right ex

-- | Every structural problem, in file order, as named diagnostics.
validateExamples :: JudgementDefinition -> JudgementExamples -> [JudgementError]
validateExamples def ex = either pure (const []) checkIds <> concatMap one (ex ^. #examples)
  where
    checks = Map.fromList [(c ^. #name, c) | c <- toList (def ^. #checks)]
    checkIds = do
      let ids = map (^. #id) (ex ^. #examples)
      when (null ids) $ Left (judgementError "judgement_examples_empty" "the examples file has no examples")
      forM_ (Map.keys (Map.filter (> (1 :: Int)) (Map.fromListWith (+) [(i, 1) | i <- ids]))) $ \dup ->
        Left (judgementError "judgement_example_duplicate_id" ("example id '" <> dup <> "' is used more than once"))
    one e =
      let eid = "example '" <> e ^. #id <> "'"
          paths = map (^. #path) (e ^. #files)
       in [judgementError "judgement_example_bad_id" (eid <> ": ids must be non-empty") | T.null (T.strip (e ^. #id))]
            <> [judgementError "judgement_example_no_files" (eid <> " has no files") | null (e ^. #files)]
            <> [ judgementError "judgement_example_bad_path" (eid <> " file path '" <> T.pack p <> "' must be project-relative without '..'")
               | p <- paths,
                 null p || "/" `T.isPrefixOf` T.pack p || ".." `elem` T.splitOn "/" (T.pack p)
               ]
            <> [judgementError "judgement_example_unknown_check" (eid <> " expects an outcome for check '" <> c <> "', which the judgement does not declare") | c <- Map.keys (e ^. #expect), not (Map.member c checks)]
            <> [judgementError "judgement_example_no_expectation" (eid <> " expects no outcome for any check") | Map.null (e ^. #expect)]
            <> concatMap (finding eid paths) (e ^. #findings)
    finding eid paths f = case Map.lookup (f ^. #check) checks of
      Nothing -> [judgementError "judgement_example_unknown_check" (eid <> " lists a finding for check '" <> f ^. #check <> "', which the judgement does not declare")]
      Just c ->
        [ judgementError "judgement_example_unknown_category" (eid <> " lists finding category '" <> f ^. #category <> "', which check '" <> c ^. #name <> "' does not declare")
        | f ^. #category `notElem` map (^. #name) (c ^. #categories)
        ]
          <> [judgementError "judgement_example_unknown_file" (eid <> " lists a finding in '" <> T.pack (f ^. #path) <> "', which is not one of its files") | f ^. #path `notElem` paths]
          <> [judgementError "judgement_example_bad_line" (eid <> " lists a finding at line " <> T.pack (show l) <> "; lines start at 1") | Just l <- [f ^. #line], l < 1]
