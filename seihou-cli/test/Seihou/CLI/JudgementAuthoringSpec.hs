module Seihou.CLI.JudgementAuthoringSpec (tests) where

import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Either (isLeft)
import Data.Generics.Labels ()
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Time (UTCTime (..), fromGregorian)
import Seihou.CLI.Judgement.Configure
import Seihou.CLI.Judgement.Evaluate
import Seihou.CLI.Judgement.Runtime (JudgementBackend (..))
import Seihou.CLI.Judgement.Scanner (findScanner)
import Seihou.CLI.Judgement.Validate
import Seihou.Core.Judgement
import Seihou.Core.JudgementExamples
import Seihou.Core.Scaffold (judgementDhall, judgementExamplesJson)
import Seihou.Core.Types (ActiveJudgement (..), JudgementSource (..))
import Seihou.Effect.FilesystemInterp (runFilesystem)
import Seihou.Effect.ManifestStore (writeManifest)
import Seihou.Effect.ManifestStoreInterp (runManifestStore)
import Seihou.Manifest.Judgement (definitionDigest)
import Seihou.Manifest.Types (emptyManifest, manifestFromJSON)
import Seihou.Prelude
import System.Directory (createDirectoryIfMissing, getCurrentDirectory)
import System.FilePath (takeDirectory)
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

check :: Text -> Answer -> Enforcement -> Thresholds -> JudgementCheck
check n concern enf t = JudgementCheck n "Is the concern present?" concern Nothing Nothing [FindingCategory "concern" High Nothing] enf High t (Thresholds 0.9 0.05) True

def2 :: JudgementDefinition
def2 =
  JudgementDefinition "demo" (Just "1.0.0") Nothing "Review." (EvidenceDeclaration [StagedChangesScope] [] []) defaultCoverageLimits [] (check "a" Yes Enforced (Thresholds 0.5 0.1) :| [check "b" No Advisory (Thresholds 0.8 0.4)])

labelled :: Text -> [(Text, ExpectedStatus)] -> JudgementExample
labelled i expects = JudgementExample i Nothing [ExampleFile "notes.txt" ("case " <> i <> "\n")] (Map.fromList expects) []

writeDir :: FilePath -> Text -> Text -> IO ()
writeDir dir dhall examples = do
  createDirectoryIfMissing True dir
  TIO.writeFile (dir </> "judgement.dhall") dhall
  TIO.writeFile (dir </> "examples.json") examples

tests :: IO TestTree
tests = testSpec "judgement authoring, evaluation and configuration" $ do
  describe "the scaffold" $
    it "decodes, validates, and its examples validate" $
      withSystemTempDirectory "judgement-scaffold" $ \tmp -> do
        cwd <- getCurrentDirectory
        let dir = tmp </> "customer-data-review"
        writeDir dir (judgementDhall "customer-data-review" (T.pack (takeDirectory cwd </> "schema" </> "package.dhall")) "") judgementExamplesJson
        v <- validateJudgementDir dir
        v ^. #errors `shouldBe` []
        fmap (length . (^. #examples)) (v ^. #examples) `shouldBe` Just 2

  describe "example validation" $ do
    it "names unknown checks, categories, files, duplicate ids and bad paths" $ do
      let bad =
            JudgementExamples
              1
              [ labelled "x" [("a", ExpectPassed), ("nope", ExpectBlocked)],
                (labelled "x" [("a", ExpectBlocked)]) & #findings .~ [ExpectedFinding "a" "other" "missing.txt" (Just 0)],
                (labelled "y" [("a", ExpectPassed)]) & #files .~ [ExampleFile "../escape.txt" "x"]
              ]
          codes = map (^. #code) (validateExamples def2 bad)
      codes
        `shouldBe` [ "judgement_example_duplicate_id",
                     "judgement_example_unknown_check",
                     "judgement_example_unknown_category",
                     "judgement_example_unknown_file",
                     "judgement_example_bad_line",
                     "judgement_example_bad_path"
                   ]
    it "rejects a malformed file and an unknown version by name" $ do
      fmap (const ()) (parseExamples "examples.json" "{\"version\": 1}") `shouldSatisfy` isLeft
      either (^. #code) (const "") (parseExamples "examples.json" "{\"version\": 2, \"examples\": []}") `shouldBe` "judgement_examples_version"
    it "flags a secret-bearing example before any evaluation" $ withSystemTempDirectory "judgement-secret-example" $ \tmp -> do
      sc <- findScanner
      case sc of
        Nothing -> pendingWith "gitleaks is not on PATH"
        Just _ -> do
          cwd <- getCurrentDirectory
          let dir = tmp </> "leaky"
              token = "ghp_" <> "Z8yQ3mK7pL2nV5bX9cW4rT6uJ1hG0fD8sA3e"
              examplesJson = "{\"version\":1,\"examples\":[{\"id\":\"leak\",\"files\":[{\"path\":\"a.env\",\"content\":\"token = \\\"" <> token <> "\\\"\\n\"}],\"expect\":{\"concern-present\":\"blocked\"}}]}"
          writeDir dir (judgementDhall "leaky" (T.pack (takeDirectory cwd </> "schema" </> "package.dhall")) "") examplesJson
          v <- validateJudgementDir dir
          map (^. #code) (v ^. #errors) `shouldBe` ["judgement_example_secret"]
          T.concat (map (^. #message) (v ^. #errors)) `shouldNotSatisfy` T.isInfixOf token

  describe "evaluation" $ do
    let ex = JudgementExamples 1 [labelled "safe" [("a", ExpectPassed), ("b", ExpectPassed)], labelled "unsafe" [("a", ExpectBlocked)]]
        backend calls yes =
          JudgementBackend
            { review = \_ c req -> do
                modifyIORef' calls (+ 1)
                let p = if "unsafe" `T.isInfixOf` (req ^. #evidence) then yes else 0.02
                pure (Right (RawReview (concernProbability (c ^. #concernWhen) (if c ^. #name == "b" then 0.98 else p)) [] False)),
              gate = Nothing,
              observed = pure []
            }
    it "scores each check and re-decides it across the sweep without new calls" $ do
      calls <- newIORef (0 :: Int)
      sc <- findScanner
      report <- evaluateExamples (Just (backend calls 0.55)) True sc "stub" def2 (defaultPolicy ApprovedRemote False def2) ex
      let rows = [(c ^. #example, c ^. #decision) | c <- report ^. #cases]
      tally rows "a" `shouldBe` CheckTally 2 0 0 0 0 2
      before <- readIORef calls
      -- Raising the block threshold above 0.55 leaves the unsafe case undecided.
      [s | (t, s) <- sweep report "a", t == Thresholds 0.6 0.05] `shouldBe` [CheckTally 1 0 0 1 0 2]
      readIORef calls >>= (`shouldBe` before)
      tally rows "b" `shouldBe` CheckTally 1 0 0 0 0 1
    it "reports missing review routes as errors, not passes" $ do
      sc <- findScanner
      report <- evaluateExamples Nothing True sc "none" def2 (defaultPolicy ApprovedRemote False def2) ex
      tally [(c ^. #example, c ^. #decision) | c <- report ^. #cases] "a" ^. #errors `shouldBe` 2
    it "offline mode reports only deterministic findings" $ do
      r <- evaluateOffline Nothing def2 ex
      r `shouldBe` Right [("safe", 0), ("unsafe", 0)]
      evaluateOffline Nothing (def2 & #deterministicChecks .~ [SecretScan]) ex >>= (`shouldSatisfy` isLeft)

  describe "configure" $ do
    let request = ConfigureRequest "demo" Nothing Nothing Nothing Nothing Nothing False Nothing (CheckOverride Nothing Nothing Nothing Nothing Nothing) False False
        withActive act = withSystemTempDirectory "judgement-configure" $ \root -> do
          let j = ActiveJudgement BundledJudgement def2 (definitionDigest def2) (defaultPolicy ApprovedRemote False def2)
          createDirectoryIfMissing True (root </> ".seihou")
          runEff (runFilesystem (runManifestStore (root </> ".seihou" </> "manifest.json") (writeManifest (emptyManifest (UTCTime (fromGregorian 2026 11 11) 0) & #judgements .~ [j]))))
          act root
    it "changes only the named check's thresholds and records them" $ withActive $ \root -> do
      Right plan <- planConfigure root (request & #check ?~ "a" & #overrides . #blockAt ?~ 0.6)
      renderConfigurePlan plan `shouldSatisfy` T.isInfixOf "check a: enforced, pass 0.10 block 0.50"
      applyConfigure root plan `shouldReturn` Right ()
      Right m <- manifestFromJSON . LBS.fromStrict <$> BS.readFile (root </> ".seihou" </> "manifest.json")
      [j ^? #policy . #checks . ix "a" . #review | j <- m ^. #judgements] `shouldBe` [Just (Thresholds 0.6 0.1)]
      [j ^? #policy . #checks . ix "b" . #review | j <- m ^. #judgements] `shouldBe` [Just (Thresholds 0.8 0.4)]
    it "refuses ambiguous, inverted, inactive and gate requests by name" $ withActive $ \root -> do
      planConfigure root (request & #overrides . #blockAt ?~ 0.6) >>= (`shouldSatisfy` either (T.isInfixOf "--check") (const False))
      planConfigure root (request & #check ?~ "a" & #overrides . #passAt ?~ 0.9) >>= (`shouldSatisfy` either (T.isInfixOf "must not exceed") (const False))
      planConfigure root (request & #name .~ "other" & #check ?~ "a" & #overrides . #blockAt ?~ 0.6) >>= (`shouldSatisfy` either (T.isInfixOf "seihou run other") (const False))
      planConfigure root (request & #gateProvider ?~ "typesafe") >>= (`shouldSatisfy` either (T.isInfixOf "judgment-only") (const False))
      planConfigure root (request & #check ?~ "zzz" & #overrides . #blockAt ?~ 0.6) >>= (`shouldSatisfy` either (T.isInfixOf "no check 'zzz'") (const False))
