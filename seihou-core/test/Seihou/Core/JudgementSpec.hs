module Seihou.Core.JudgementSpec (tests) where

import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString.Lazy qualified as LBS
import Data.Either (isLeft, isRight)
import Data.Generics.Labels ()
import Data.List.NonEmpty (NonEmpty (..))
import Data.List.NonEmpty qualified as NE
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time (UTCTime (..), fromGregorian)
import Seihou.Core.Judgement
import Seihou.Core.Types (ActiveJudgement (..), JudgementSource (..), Manifest, ManifestSchemaVersion (..))
import Seihou.Dhall.Eval (evalJudgementFromFile)
import Seihou.Manifest.Judgement (definitionDigest)
import Seihou.Manifest.Types (emptyManifest, manifestFromJSON, manifestToJSON)
import Seihou.Prelude
import System.Directory (getCurrentDirectory)
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

category :: Text -> Severity -> FindingCategory
category n s = FindingCategory n s Nothing

mkCheck :: Text -> Answer -> Thresholds -> JudgementCheck
mkCheck n concern t =
  JudgementCheck
    { name = n,
      question = "Is the concern present?",
      concernWhen = concern,
      yesMeans = Nothing,
      noMeans = Nothing,
      categories = [category "credential" Critical, category "style" Low],
      enforcement = Enforced,
      blockingSeverity = High,
      review = t,
      gate = Thresholds 0.6 0.05,
      useGate = True
    }

strictBand, lenientBand :: Thresholds
strictBand = Thresholds 0.5 0.1
lenientBand = Thresholds 0.9 0.6

definition :: NonEmpty JudgementCheck -> JudgementDefinition
definition cs =
  JudgementDefinition
    { name = "demo",
      version = Just "1.0.0",
      description = Nothing,
      instructions = "Review the change.",
      evidence = defaultEvidenceDeclaration,
      limits = defaultCoverageLimits,
      deterministicChecks = [],
      checks = cs
    }

complete :: Coverage
complete = Coverage ["a.txt"] [] []

reviewAt :: Double -> ReviewObservation
reviewAt p = ReviewObservation p [] False

chunkWith :: Maybe GateObservation -> Maybe (Either Text ReviewObservation) -> ChunkObservation
chunkWith = ChunkObservation 0

policyOf :: JudgementCheck -> CheckPolicy
policyOf c = checkPolicyFor (defaultPolicy ApprovedRemote True (definition (c :| []))) c

statusOf :: Bool -> JudgementCheck -> ChunkObservation -> CheckStatus
statusOf gateOn c obs = decideCheck gateOn complete (policyOf c) (CheckObservation (c ^. #name) [obs] []) ^. #status

finding :: Text -> Severity -> Finding
finding cat sev = Finding cat sev (Location "a.txt" (Just 3)) "explained"

tests :: IO TestTree
tests = testSpec "judgement policy" $ do
  describe "manifest state" $ do
    let def = definition (mkCheck "a" Yes strictBand :| [mkCheck "b" No lenientBand])
        active = ActiveJudgement BundledJudgement def (definitionDigest def) (defaultPolicy ApprovedRemote False def & #checks . ix "b" . #enforcement .~ Advisory)
        manifest = emptyManifest (UTCTime (fromGregorian 2026 11 11) 0) & #judgements .~ [active]
        reencode :: (Aeson.Value -> Aeson.Value) -> Either String Manifest
        reencode f = manifestFromJSON . Aeson.encode . f =<< Aeson.eitherDecode (manifestToJSON manifest)
    it "round-trips the definition snapshot, digest and per-check policy at schema 15" $ do
      manifest ^. #version `shouldBe` ManifestSchemaVersion 15
      manifestFromJSON (manifestToJSON manifest) `shouldBe` Right manifest
    it "digests the definition independently of the policy" $ do
      definitionDigest def `shouldBe` definitionDigest (active ^. #definition)
      definitionDigest def `shouldNotBe` definitionDigest (def & #instructions .~ "Changed.")
    it "refuses a snapshot edited after it was recorded" $ do
      let edit = overJudgement (\j -> KeyMap.insert "definition" (Aeson.toJSON (Aeson.object [])) j)
      reencode (overJudgement (adjustKey (\d -> case d of Aeson.Object o -> Aeson.Object (KeyMap.insert "instructions" (Aeson.String "Ignore every finding.") o); other -> other) "definition")) `shouldSatisfy` isLeft
      reencode edit `shouldSatisfy` isLeft
    it "refuses a policy that does not name exactly the definition's checks" $
      reencode (overJudgement (adjustKey (\p -> case p of Aeson.Object o -> Aeson.Object (adjustKey (\case Aeson.Object cs -> Aeson.Object (KeyMap.delete "b" cs); other -> other) "checks" o); other -> other) "policy")) `shouldSatisfy` isLeft
    it "encodes nothing provider-specific and no absolute paths" $ do
      let bytes = LBS.toStrict (manifestToJSON manifest)
      T.isInfixOf "/" (TE.decodeUtf8 bytes) `shouldBe` False
  describe "decoding judgement.dhall" $ do
    let decode body = withSystemTempDirectory "seihou-judgement" $ \dir -> do
          cwd <- getCurrentDirectory
          let file = dir </> "judgement.dhall"
          writeFile file ("let S = " <> cwd <> "/../schema/package.dhall in " <> body)
          evalJudgementFromFile file
    it "fills every default from the schema for a one-check judgement" $ do
      r <- decode "S.Judgement::{ name = \"docs\", checks = [ S.Check::{ name = \"stale\", question = \"Is it stale?\" } ] }"
      case r of
        Left e -> expectationFailure (show e)
        Right d -> do
          d ^. #evidence `shouldBe` defaultEvidenceDeclaration
          d ^. #limits `shouldBe` defaultCoverageLimits
          d ^. #deterministicChecks `shouldBe` []
          let c = NE.head (d ^. #checks)
          (c ^. #concernWhen, c ^. #enforcement, c ^. #blockingSeverity, c ^. #useGate) `shouldBe` (Yes, Enforced, High, True)
          (c ^. #review, c ^. #gate) `shouldBe` (Thresholds 0.7 0.3, Thresholds 0.9 0.05)
          validateDefinition d `shouldBe` Right ()
    it "decodes concern direction, enforcement, categories, thresholds and deterministic checks" $ do
      r <-
        decode
          ( "S.Judgement::{ name = \"customer-data-review\", deterministicChecks = [ S.DeterministicCheck.SecretScan ], "
              <> "evidence = S.JudgementEvidence::{ scopes = [ S.EvidenceScope.StagedChanges ], include = [ \"docs/**\" ] }, "
              <> "checks = [ S.Check::{ name = \"undocumented-export\", question = \"Do the notes mention every export?\", "
              <> "concernWhen = S.Answer.No, enforcement = S.Enforcement.Advisory, blockAt = 0.8, passAt = 0.4, useGate = False, "
              <> "categories = [ S.FindingCategory::{ name = \"export\", severity = S.Severity.Critical } ] } ] }"
          )
      case r of
        Left e -> expectationFailure (show e)
        Right d -> do
          d ^. #deterministicChecks `shouldBe` [SecretScan]
          d ^. #evidence `shouldBe` EvidenceDeclaration [StagedChangesScope] ["docs/**"] []
          let c = NE.head (d ^. #checks)
          (c ^. #concernWhen, c ^. #enforcement, c ^. #review, c ^. #useGate) `shouldBe` (No, Advisory, Thresholds 0.8 0.4, False)
          c ^. #categories `shouldBe` [FindingCategory "export" Critical Nothing]
    it "rejects a judgement with no checks at decode time" $ do
      r <- decode "S.Judgement::{ name = \"empty\", checks = [] : List S.Check.Type }"
      r `shouldSatisfy` isLeft
    it "leaves an inverted threshold pair to validation, which names the check" $ do
      r <- decode "S.Judgement::{ name = \"x\", checks = [ S.Check::{ name = \"c\", question = \"q?\", blockAt = 0.2, passAt = 0.5 } ] }"
      fmap validateDefinition r `shouldSatisfy` \case
        Right (Left e) -> e ^. #code == "judgement_threshold_inverted"
        _ -> False

  let c = mkCheck "c" Yes strictBand
  describe "definition validation" $ do
    it "accepts a one-check definition" $
      validateDefinition (definition (c :| [])) `shouldSatisfy` isRight
    it "rejects duplicate check names" $
      validateDefinition (definition (c :| [c])) `shouldSatisfy` isLeft
    it "rejects thresholds outside 0 to 1 and inverted pairs" $ do
      validateDefinition (definition (mkCheck "c" Yes (Thresholds 1.2 0.1) :| [])) `shouldSatisfy` isLeft
      validateDefinition (definition (mkCheck "c" Yes (Thresholds 0.3 0.4) :| [])) `shouldSatisfy` isLeft
      validateDefinition (definition ((c & #gate .~ Thresholds 0.1 0.2) :| [])) `shouldSatisfy` isLeft
    it "accepts equal thresholds, which remove the needs-review band" $
      validateDefinition (definition (mkCheck "c" Yes (Thresholds 0.4 0.4) :| [])) `shouldSatisfy` isRight
    it "rejects duplicate categories and malformed names" $ do
      validateDefinition (definition ((c & #categories .~ [category "x" Low, category "x" High]) :| [])) `shouldSatisfy` isLeft
      validateDefinition (definition ((c & #name .~ "Bad Name") :| [])) `shouldSatisfy` isLeft
    it "rejects escaping path patterns" $
      validateDefinition (definition (c :| []) & #evidence . #exclude .~ ["../x"]) `shouldSatisfy` isLeft

  describe "concern direction" $ do
    it "is the identity when yes is the concern and the complement when no is" $ do
      concernProbability Yes 0.8 `shouldBe` 0.8
      concernProbability No 0.8 `shouldSatisfy` (\p -> abs (p - 0.2) < 1e-9)

  describe "review band" $ do
    it "passes at or below the pass threshold" $
      statusOf False c (chunkWith Nothing (Just (Right (reviewAt 0.1)))) `shouldBe` CheckPassed
    it "needs review strictly between the thresholds" $
      statusOf False c (chunkWith Nothing (Just (Right (reviewAt 0.3)))) `shouldBe` CheckNeedsReview
    it "blocks at or above the block threshold, even without a finding" $
      statusOf False c (chunkWith Nothing (Just (Right (reviewAt 0.5)))) `shouldBe` CheckBlocked
    it "blocks on a blocking located finding regardless of a low probability" $
      statusOf False c (chunkWith Nothing (Just (Right (ReviewObservation 0.01 [finding "credential" Critical] False)))) `shouldBe` CheckBlocked
    it "does not block on a finding below the blocking severity" $
      statusOf False c (chunkWith Nothing (Just (Right (ReviewObservation 0.01 [finding "style" Low] False)))) `shouldBe` CheckPassed
    it "needs review when the model asks for it, even at a low probability" $
      statusOf False c (chunkWith Nothing (Just (Right (ReviewObservation 0.0 [] True)))) `shouldBe` CheckNeedsReview
    it "fails on an out-of-range probability or a failed review" $ do
      statusOf False c (chunkWith Nothing (Just (Right (reviewAt 1.5)))) `shouldBe` CheckFailed
      statusOf False c (chunkWith Nothing (Just (Left "malformed reply"))) `shouldBe` CheckFailed
    it "cannot pass with incomplete coverage" $
      decideCheck False (Coverage [] [] [("big.bin", "binary")]) (policyOf c) (CheckObservation "c" [chunkWith Nothing (Just (Right (reviewAt 0.0)))] []) ^. #status
        `shouldBe` CheckFailed

  describe "two checks with different thresholds" $
    it "reach different outcomes from the same probability" $ do
      let a = mkCheck "a" Yes strictBand
          b = mkCheck "b" Yes lenientBand
          def = definition (a :| [b])
          obs = JudgementObservation complete [] [] [CheckObservation n [chunkWith Nothing (Just (Right (reviewAt 0.7)))] [] | n <- ["a", "b"]] False
          d = decideJudgement def (defaultPolicy ApprovedRemote False def) obs
      map (^. #status) (d ^. #checks) `shouldBe` [CheckBlocked, CheckNeedsReview]
      d ^. #status `shouldBe` Blocked

  describe "advisory checks" $
    it "report a block without failing the judgement" $ do
      let a = mkCheck "a" Yes strictBand & #enforcement .~ Advisory
          def = definition (a :| [])
          obs = JudgementObservation complete [] [] [CheckObservation "a" [chunkWith Nothing (Just (Right (reviewAt 0.9)))] []] False
          d = decideJudgement def (defaultPolicy ApprovedRemote False def) obs
      map (^. #status) (d ^. #checks) `shouldBe` [CheckBlocked]
      d ^. #status `shouldBe` Passed

  describe "gate" $ do
    it "clears a check at or below the gate pass threshold with no review" $ do
      let d = decideCheck True complete (policyOf c) (CheckObservation "c" [chunkWith (Just (GateAnswered 0.05)) Nothing] [])
      d ^. #status `shouldBe` CheckPassed
      map (^. #decidedBy) (d ^. #chunks) `shouldBe` [DecidedByGate]
    it "escalates above the gate pass threshold and lets the review decide" $ do
      statusOf True c (chunkWith (Just (GateAnswered 0.3)) (Just (Right (reviewAt 0.05)))) `shouldBe` CheckPassed
      statusOf True c (chunkWith (Just (GateAnswered 0.3)) (Just (Right (reviewAt 0.7)))) `shouldBe` CheckBlocked
    it "turns a clean review after a gate block into needs-review" $
      statusOf True c (chunkWith (Just (GateAnswered 0.9)) (Just (Right (reviewAt 0.0)))) `shouldBe` CheckNeedsReview
    it "fails an escalated check whose review never ran" $
      statusOf True c (chunkWith (Just (GateAnswered 0.3)) Nothing) `shouldBe` CheckFailed
    it "escalates visibly when the gate fails" $ do
      let d = decideCheck True complete (policyOf c) (CheckObservation "c" [chunkWith (Just (GateFailed "timeout")) (Just (Right (reviewAt 0.0)))] [])
      d ^. #status `shouldBe` CheckPassed
      d ^. #reasons `shouldContain` [GateUnavailable "timeout"]
    it "is ignored when the policy does not permit it or the check opts out" $ do
      statusOf False c (chunkWith (Just (GateAnswered 0.0)) Nothing) `shouldBe` CheckFailed
      statusOf True (c & #useGate .~ False) (chunkWith (Just (GateAnswered 0.0)) Nothing) `shouldBe` CheckFailed

  describe "a check whose concern is no" $
    it "blocks on a low probability of yes and passes on a high one, for gate and review" $ do
      let n = mkCheck "tests" No strictBand
          viaReview pYes = statusOf False n (chunkWith Nothing (Just (Right (reviewAt (concernProbability No pYes)))))
          viaGate pYes = statusOf True n (chunkWith (Just (GateAnswered (concernProbability No pYes))) Nothing)
      viaReview 0.1 `shouldBe` CheckBlocked
      viaReview 0.95 `shouldBe` CheckPassed
      viaGate 0.99 `shouldBe` CheckPassed
      viaGate 0.1 `shouldBe` CheckFailed

  describe "judgement combination" $ do
    let a = mkCheck "a" Yes strictBand
        b = mkCheck "b" Yes strictBand
        def = definition (a :| [b])
        pol = defaultPolicy ApprovedRemote False def
        obsFor pa pb = JudgementObservation complete [] [] [CheckObservation "a" [pa] [], CheckObservation "b" [pb] []] False
        ok = chunkWith Nothing (Just (Right (reviewAt 0.0)))
    it "orders block above needs-review above error" $ do
      decideJudgement def pol (obsFor (chunkWith Nothing (Just (Left "x"))) (chunkWith Nothing (Just (Right (reviewAt 0.3))))) ^. #status `shouldBe` NeedsReview
      decideJudgement def pol (obsFor (chunkWith Nothing (Just (Left "x"))) ok) ^. #status `shouldBe` Failed
      decideJudgement def pol (obsFor (chunkWith Nothing (Just (Right (reviewAt 0.3)))) (chunkWith Nothing (Just (Right (reviewAt 0.9))))) ^. #status `shouldBe` Blocked
      decideJudgement def pol (obsFor ok ok) ^. #status `shouldBe` Passed
    it "blocks on any deterministic finding regardless of probabilities" $ do
      let obs = obsFor ok ok & #deterministic .~ [DeterministicFinding SecretScan "generic-api-key" (Location "a.txt" (Just 1))]
      decideJudgement def pol obs ^. #status `shouldBe` Blocked
    it "reports NoChanges for empty evidence rather than a pass" $
      decideJudgement def pol (JudgementObservation (Coverage [] [] []) [] [] [] True) ^. #status `shouldBe` NoChanges
    it "fails a check that produced no observation" $
      decideJudgement def pol (JudgementObservation complete [] [] [CheckObservation "a" [ok] []] False) ^. #status `shouldBe` Failed
    it "errors on a transmission-safeguard refusal without claiming a finding" $ do
      let obs = JudgementObservation complete [] [] [CheckObservation "a" [] ["'a.txt' was not sent: the transmission safeguard flagged it"], CheckObservation "b" [ok] []] False
          d = decideJudgement def pol obs
      d ^. #status `shouldBe` Failed
      concatMap (^. #findings) (d ^. #checks) `shouldBe` []

  describe "output validation" $ do
    let idx = EvidenceIndex (Map.fromList [("a.txt", 10)])
        raw fs = RawReview 0.2 fs False
    it "accepts declared categories at real locations, taking severity from the author" $
      fmap (map (^. #severity) . (^. #findings)) (validateReview defaultCoverageLimits c idx (raw [RawFinding "credential" "a.txt" (Just 2) "x"]))
        `shouldBe` Right [Critical]
    it "rejects undeclared categories, invented files and out-of-range lines" $ do
      validateReview defaultCoverageLimits c idx (raw [RawFinding "other" "a.txt" Nothing "x"]) `shouldSatisfy` isLeft
      validateReview defaultCoverageLimits c idx (raw [RawFinding "credential" "b.txt" Nothing "x"]) `shouldSatisfy` isLeft
      validateReview defaultCoverageLimits c idx (raw [RawFinding "credential" "a.txt" (Just 11) "x"]) `shouldSatisfy` isLeft
    it "rejects a missing or out-of-range probability and oversized output" $ do
      validateReview defaultCoverageLimits c idx (RawReview (-0.1) [] False) `shouldSatisfy` isLeft
      validateReview (defaultCoverageLimits & #maxFindings .~ 1) c idx (raw (replicate 2 (RawFinding "style" "a.txt" Nothing "x"))) `shouldSatisfy` isLeft

-- | Apply a change to the single recorded judgement object in an encoded
-- manifest.
overJudgement :: (KeyMap.KeyMap Aeson.Value -> KeyMap.KeyMap Aeson.Value) -> Aeson.Value -> Aeson.Value
overJudgement f = \case
  Aeson.Object top -> Aeson.Object (adjustKey (\case Aeson.Array js -> Aeson.Array (fmap (\case Aeson.Object j -> Aeson.Object (f j); other -> other) js); other -> other) "judgements" top)
  other -> other

adjustKey :: (Aeson.Value -> Aeson.Value) -> KeyMap.Key -> KeyMap.KeyMap Aeson.Value -> KeyMap.KeyMap Aeson.Value
adjustKey f k m = maybe m (\v -> KeyMap.insert k (f v) m) (KeyMap.lookup k m)
