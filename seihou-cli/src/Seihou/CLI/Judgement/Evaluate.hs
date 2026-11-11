-- | @seihou judgement eval NAME@: run a judgement's labelled examples
-- through the same program a commit uses and report how it decides them.
--
-- Each example becomes an in-memory snapshot and goes through
-- 'runJudgement', so the transmission safeguard, data policy and limits
-- apply exactly as they do to a commit. Each case's observation is kept, so
-- the threshold sweep re-decides every case under other threshold pairs
-- without further model calls. Evaluation proposes nothing and writes
-- nothing. Offline mode runs only the corpus checks and the deterministic
-- scanner; it says so and never reports model accuracy.
module Seihou.CLI.Judgement.Evaluate
  ( EvalCase (..),
    EvalReport (..),
    CheckTally (..),
    GateTally (..),
    evaluateExamples,
    gateTally,
    evaluateOffline,
    tally,
    sweep,
    renderEvalReport,
  )
where

import Control.Monad (forM)
import Data.Foldable (toList)
import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text qualified as T
import Data.Time.Clock (diffUTCTime, getCurrentTime)
import Seihou.CLI.Judgement.Evidence (Snapshot (..))
import Seihou.CLI.Judgement.Execute
import Seihou.CLI.Judgement.Runtime (JudgementBackend)
import Seihou.CLI.Judgement.Scanner (scanCaptured)
import Seihou.CLI.Judgement.Validate (exampleEvidence)
import Seihou.Core.Judgement
import Seihou.Core.JudgementExamples
import Seihou.Prelude

data EvalCase = EvalCase
  { example :: !JudgementExample,
    observation :: !JudgementObservation,
    decision :: !JudgementDecision,
    seconds :: !Double
  }
  deriving stock (Eq, Show, Generic)

data CheckTally = CheckTally
  { correct :: !Int,
    missedUnsafe :: !Int,
    falseBlocks :: !Int,
    undecided :: !Int,
    errors :: !Int,
    scored :: !Int
  }
  deriving stock (Eq, Show, Generic)

-- | How the judgment-only gate did on one check. A gate is qualified only
-- when it clears no unsafe case; the benign cases it escalates are its cost.
data GateTally = GateTally
  { unsafeCleared :: !Int,
    unsafeEscalated :: !Int,
    benignCleared :: !Int,
    benignEscalated :: !Int,
    gateFailures :: !Int
  }
  deriving stock (Eq, Show, Generic)

data EvalReport = EvalReport
  { judgement :: !JudgementDefinition,
    policy :: !JudgementPolicy,
    route :: !Text,
    cases :: ![EvalCase]
  }
  deriving stock (Eq, Show, Generic)

-- | Run every example; 'Nothing' as the backend makes every check an error,
-- which the report then shows as runtime failures.
evaluateExamples :: Maybe JudgementBackend -> Bool -> Maybe FilePath -> Text -> JudgementDefinition -> JudgementPolicy -> JudgementExamples -> IO EvalReport
evaluateExamples be remote sc routeLabel def pol ex = do
  cases <- forM (ex ^. #examples) $ \e -> do
    let snap = Snapshot StagedChangesScope ("example:" <> e ^. #id) (map unprefix (exampleEvidence e)) []
        unprefix f = f & #path .~ dropPrefix (T.unpack (e ^. #id)) (f ^. #path)
    start <- getCurrentTime
    obs <- runJudgement (JudgementExecution pol be remote sc) def snap
    end <- getCurrentTime
    pure (EvalCase e obs (decideJudgement def pol obs) (realToFrac (diffUTCTime end start)))
  pure (EvalReport def pol routeLabel cases)
  where
    dropPrefix pfx p = case splitAt (length pfx + 1) p of
      (h, rest) | h == pfx <> "/" -> rest
      _ -> p

-- | Corpus and scanner only. Returns, per example, the deterministic
-- findings the secret scan produced, when the definition declares it.
evaluateOffline :: Maybe FilePath -> JudgementDefinition -> JudgementExamples -> IO (Either Text [(Text, Int)])
evaluateOffline sc def ex
  | SecretScan `notElem` (def ^. #deterministicChecks) = pure (Right [(e ^. #id, 0) | e <- ex ^. #examples])
  | otherwise = case sc of
      Nothing -> pure (Left "this judgement declares the secret scan, and gitleaks was not found")
      Just exe -> fmap sequence . forM (ex ^. #examples) $ \e ->
        scanCaptured exe (exampleEvidence e) [] <&> fmap (\r -> (e ^. #id, length (r ^. #findings)))

-- | A deterministic finding blocks the whole judgement before any check is
-- reviewed, so it counts as a block for every check.
actualStatus :: JudgementDecision -> Text -> Maybe CheckStatus
actualStatus d name
  | not (null (d ^. #deterministic)) = Just CheckBlocked
  | otherwise = case [c ^. #status | c <- d ^. #checks, c ^. #check == name] of
      (s : _) -> Just s
      [] -> Nothing

-- | Score one check across every case that states an expectation for it.
tally :: [(JudgementExample, JudgementDecision)] -> Text -> CheckTally
tally rows name = foldr add (CheckTally 0 0 0 0 0 0) scoredRows
  where
    scoredRows = [(want, actualStatus d name) | (e, d) <- rows, Just want <- [Map.lookup name (e ^. #expect)]]
    add (want, got) t =
      let t' = t & #scored %~ (+ 1)
       in case (want, got) of
            (ExpectBlocked, Just CheckPassed) -> t' & #missedUnsafe %~ (+ 1)
            (ExpectPassed, Just CheckBlocked) -> t' & #falseBlocks %~ (+ 1)
            (ExpectPassed, Just CheckPassed) -> t' & #correct %~ (+ 1)
            (ExpectBlocked, Just CheckBlocked) -> t' & #correct %~ (+ 1)
            (ExpectNeedsReview, Just CheckNeedsReview) -> t' & #correct %~ (+ 1)
            (_, Just CheckNeedsReview) -> t' & #undecided %~ (+ 1)
            (_, Just CheckFailed) -> t' & #errors %~ (+ 1)
            (ExpectNeedsReview, Just _) -> t' & #undecided %~ (+ 1)
            _ -> t' & #errors %~ (+ 1)

-- | The gate's record on one check, or 'Nothing' when the gate never ran for
-- it. A case counts as cleared when the gate decided every chunk.
gateTally :: [EvalCase] -> Text -> Maybe GateTally
gateTally cases name
  | null gated = Nothing
  | otherwise = Just (foldr add (GateTally 0 0 0 0 0) gated)
  where
    gated =
      [ (want, cleared, failed)
      | c <- cases,
        null (c ^. #decision . #deterministic),
        Just want <- [Map.lookup name (c ^. #example . #expect)],
        d <- [x | x <- c ^. #decision . #checks, x ^. #check == name],
        o <- [x | x <- c ^. #observation . #checks, x ^. #check == name],
        let gates = [g | ch <- o ^. #chunks, Just g <- [ch ^. #gate]],
        not (null gates),
        let cleared = not (null (d ^. #chunks)) && all ((== DecidedByGate) . (^. #decidedBy)) (d ^. #chunks)
            failed = length [() | GateFailed _ <- gates]
      ]
    add (want, cleared, failed) t =
      let t' = t & #gateFailures %~ (+ failed)
       in case (want, cleared) of
            (ExpectPassed, True) -> t' & #benignCleared %~ (+ 1)
            (ExpectPassed, False) -> t' & #benignEscalated %~ (+ 1)
            (_, True) -> t' & #unsafeCleared %~ (+ 1)
            (_, False) -> t' & #unsafeEscalated %~ (+ 1)

-- | How one check's tally would change under other review thresholds,
-- re-deciding the retained observations. Only valid pairs are swept.
sweep :: EvalReport -> Text -> [(Thresholds, CheckTally)]
sweep report name =
  [ (t, tally [(c ^. #example, decideJudgement def (pol t) (c ^. #observation)) | c <- report ^. #cases] name)
  | blockAt <- [0.5, 0.6, 0.7, 0.8, 0.9],
    passAt <- [0.05, 0.1, 0.2, 0.3, 0.4, 0.5],
    passAt <= blockAt,
    let t = Thresholds blockAt passAt
  ]
  where
    def = report ^. #judgement
    pol t = (report ^. #policy) & #checks %~ Map.adjust (#review .~ t) name

renderEvalReport :: EvalReport -> Text
renderEvalReport r =
  T.unlines $
    [ "Evaluation of '" <> def ^. #name <> "' " <> fromMaybe "(unversioned)" (def ^. #version) <> " on " <> T.pack (show (length (r ^. #cases))) <> " example(s)",
      "Route: " <> r ^. #route <> ". Probabilities are model-reported and these counts apply to this route only.",
      "Mean latency per example: " <> secs (if null (r ^. #cases) then 0 else sum (map (^. #seconds) (r ^. #cases)) / fromIntegral (length (r ^. #cases)))
    ]
      <> concatMap perCase (r ^. #cases)
      <> concatMap perCheck (toList (def ^. #checks))
  where
    def = r ^. #judgement
    rows = [(c ^. #example, c ^. #decision) | c <- r ^. #cases]
    secs x = T.pack (show (fromIntegral (round (x * 10) :: Int) / (10 :: Double))) <> "s"
    perCase c
      | not (null (c ^. #decision . #deterministic)) =
          ["  " <> c ^. #example . #id <> ": " <> renderJudgementStatus (c ^. #decision . #status) <> " by the secret scan before any request (counts as blocked for every check)"]
      | otherwise = perReviewed c
    perReviewed c =
      ("  " <> c ^. #example . #id <> ": " <> renderJudgementStatus (c ^. #decision . #status))
        : [ "    "
              <> d ^. #check
              <> " "
              <> renderCheckStatus (d ^. #status)
              <> maybe "" (\p -> " at " <> renderProbability p) (d ^. #reviewConcern)
              <> maybe "" (\p -> "; gate " <> renderProbability p <> (if d ^. #reviewConcern == Nothing then ", cleared by the gate" else "")) (d ^. #gateConcern)
              <> maybe "" (\want -> " (expected " <> renderExpectedStatus want <> ")") (Map.lookup (d ^. #check) (c ^. #example . #expect))
          | d <- c ^. #decision . #checks
          ]
    perCheck chk =
      let name = chk ^. #name
          t = tally rows name
          cp = checkPolicyFor (r ^. #policy) chk
       in [ "Check " <> name <> " at pass " <> renderProbability (cp ^. #review . #passAt) <> " / block " <> renderProbability (cp ^. #review . #blockAt) <> ": " <> line t
          ]
            <> maybe [] (gateLines cp) (gateTally (r ^. #cases) name)
            <> [ "  threshold sweep (no further model calls):"
               ]
            <> [ "    pass " <> renderProbability (th ^. #passAt) <> " block " <> renderProbability (th ^. #blockAt) <> ": " <> line s
               | (th, s) <- sweep r name
               ]
    gateLines cp g =
      [ "  gate at pass "
          <> renderProbability (cp ^. #gate . #passAt)
          <> " / block "
          <> renderProbability (cp ^. #gate . #blockAt)
          <> ": cleared "
          <> T.pack (show (g ^. #unsafeCleared))
          <> " unsafe and "
          <> T.pack (show (g ^. #benignCleared))
          <> " benign; escalated "
          <> T.pack (show (g ^. #benignEscalated))
          <> " benign and "
          <> T.pack (show (g ^. #unsafeEscalated))
          <> " unsafe; "
          <> T.pack (show (g ^. #gateFailures))
          <> " gate failure(s)"
          <> (if g ^. #unsafeCleared > 0 then ". NOT QUALIFIED: the gate cleared an unsafe case" else "")
      ]
    line t =
      T.pack (show (t ^. #correct))
        <> "/"
        <> T.pack (show (t ^. #scored))
        <> " correct, "
        <> T.pack (show (t ^. #missedUnsafe))
        <> " missed unsafe, "
        <> T.pack (show (t ^. #falseBlocks))
        <> " false blocks, "
        <> T.pack (show (t ^. #undecided))
        <> " undecided, "
        <> T.pack (show (t ^. #errors))
        <> " errors"
