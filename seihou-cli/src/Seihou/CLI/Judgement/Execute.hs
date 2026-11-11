-- | Run one judgement over one captured snapshot.
--
-- The order is fixed and is the security contract: select evidence by the
-- definition's path filters; scan the selected bytes and every outgoing
-- instruction locally; record deterministic findings for definitions that
-- declare the scan; refuse to transmit anything the scanner flagged; apply
-- the project data policy; and only then send chunks, first to the gate when
-- one is permitted and then, for checks the gate did not clear, to the review.
-- The result is an observation; 'decideJudgement' turns it into a decision.
module Seihou.CLI.Judgement.Execute
  ( JudgementExecution (..),
    runJudgement,
  )
where

import Control.Monad (forM)
import Data.Foldable (toList)
import Data.Generics.Labels ()
import Data.Maybe (isJust)
import Data.Text qualified as T
import Seihou.CLI.Judgement.Evidence
import Seihou.CLI.Judgement.Runtime (ChunkRequest (..), JudgementBackend)
import Seihou.CLI.Judgement.Scanner
import Seihou.Core.Judgement
import Seihou.Prelude

data JudgementExecution = JudgementExecution
  { policy :: !JudgementPolicy,
    -- | 'Nothing' when no permitted route is configured.
    backend :: !(Maybe JudgementBackend),
    -- | Whether the configured route sends material to a hosted service.
    remote :: !Bool,
    -- | The located scanner executable, if any.
    scanner :: !(Maybe FilePath)
  }
  deriving stock (Generic)

runJudgement :: JudgementExecution -> JudgementDefinition -> Snapshot -> IO JudgementObservation
runJudgement exec def snap = do
  let (selected, excluded, uncoveredSel) = selectForDefinition def snap
      limits = def ^. #limits
      checks = toList (def ^. #checks)
      declaresScan = SecretScan `elem` def ^. #deterministicChecks
      needsScan = declaresScan || exec ^. #remote
      instructionTexts = [("check '" <> c ^. #name <> "' instructions", def ^. #instructions <> "\n" <> c ^. #question <> "\n" <> foldMap id (c ^. #yesMeans) <> "\n" <> foldMap id (c ^. #noMeans)) | c <- checks]
      noChanges = null selected && null uncoveredSel
  if noChanges
    then pure (JudgementObservation (Coverage [] excluded []) [] [] [] True)
    else do
      scanned <-
        if not needsScan
          then pure (Right (ScanResult [] []))
          else case exec ^. #scanner of
            Nothing -> pure (Left "the secret scanner (gitleaks) was not found; install it or set SEIHOU_GITLEAKS")
            Just exe -> scanCaptured exe selected instructionTexts
      case scanned of
        Left err ->
          -- No scan, no transmission: every check ends as an error.
          pure (JudgementObservation (Coverage [] excluded uncoveredSel) [] [err] [CheckObservation (c ^. #name) [] ["not reviewed: " <> err] | c <- checks] False)
        Right scan -> do
          let deterministic = if declaresScan then scan ^. #findings else []
              flagged = flaggedPaths scan
              transmissible = filter ((`notElem` flagged) . (^. #path)) selected
              (chunks, overflow) = chunkEvidence limits transmissible
              coverage = Coverage (map (^. #path) transmissible) excluded (uncoveredSel <> overflow)
              index = evidenceIndex transmissible
              policy = exec ^. #policy
              gateOn = policy ^. #gatePermitted
              baseErrors c =
                [ "'" <> T.pack p <> "' was not sent: the transmission safeguard flagged it, and this judgement does not declare the secret scan"
                | not declaresScan,
                  p <- flagged
                ]
                  <> [ "the " <> name <> " were flagged by the transmission safeguard and were not sent"
                     | name <- scan ^. #flaggedTexts,
                       name == "check '" <> c ^. #name <> "' instructions"
                     ]
                  <> [ "the project data policy is local-only and the configured route sends material to a hosted service"
                     | exec ^. #remote && policy ^. #dataPolicy == LocalOnly
                     ]
                  <> ["no review route is configured; set one with seihou config set judgement.provider PROVIDER and seihou config set judgement.model MODEL" | not (isJust (exec ^. #backend))]
          observations <- forM checks $ \c -> do
            let errs = baseErrors c
                cpol = checkPolicyFor policy c
            if not (null deterministic)
              then pure (CheckObservation (c ^. #name) [] ["not reviewed: a deterministic finding stopped further transmission"])
              else
                if not (null errs)
                  then pure (CheckObservation (c ^. #name) [] errs)
                  else case exec ^. #backend of
                    Nothing -> pure (CheckObservation (c ^. #name) [] ["no permitted review route is configured"])
                    Just be -> do
                      cs <- forM chunks $ \ch -> do
                        let req = ChunkRequest (ch ^. #index) (ch ^. #text)
                            gateFn = if gateOn && cpol ^. #useGate then be ^. #gate else Nothing
                        gateObs <- forM gateFn $ \g -> either GateFailed GateAnswered <$> g def c req
                        let cleared = case gateObs of
                              Just (GateAnswered p) -> validProbability p && p <= cpol ^. #gate . #passAt
                              _ -> False
                        reviewObs <-
                          if cleared
                            then pure Nothing
                            else do
                              r <- (be ^. #review) def c req
                              pure (Just (r >>= validateReview limits c index))
                        pure (ChunkObservation (ch ^. #index) gateObs reviewObs)
                      pure (CheckObservation (c ^. #name) cs [])
          pure (JudgementObservation coverage deterministic [] observations False)
