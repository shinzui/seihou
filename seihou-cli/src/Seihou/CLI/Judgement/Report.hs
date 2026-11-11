-- | Human and JSON reports of judgement decisions, and the exit status they
-- imply.
--
-- Every probability is labelled as model-reported. Every string that can
-- carry model-generated text is bounded; matched secret text never reaches a
-- report because the scanner adapter reads only rule IDs and locations.
module Seihou.CLI.Judgement.Report
  ( reportVersion,
    exitCodeFor,
    combinedStatus,
    renderHuman,
    renderHumanFor,
    renderJson,
  )
where

import Data.Aeson (Value, object, (.=))
import Data.Generics.Labels ()
import Data.List (sortOn)
import Data.Ord (Down (..))
import Data.Text qualified as T
import Seihou.Core.Judgement
import Seihou.Prelude

-- | The version of the JSON report contract.
reportVersion :: Int
reportVersion = 1

-- | 0 for pass or explicit no changes, 10 for a policy block, 11 for needs
-- human review, 1 for runtime, configuration or coverage errors.
exitCodeFor :: JudgementStatus -> Int
exitCodeFor = \case
  Passed -> 0
  NoChanges -> 0
  Blocked -> 10
  NeedsReview -> 11
  Failed -> 1

-- | The most severe status over several judgements: block, then
-- needs-review, then error. All no-changes stays no-changes.
combinedStatus :: [JudgementStatus] -> JudgementStatus
combinedStatus ss = case sortOn (Down . rank) ss of
  (s : _) -> s
  [] -> NoChanges
  where
    rank = \case
      Blocked -> 4 :: Int
      NeedsReview -> 3
      Failed -> 2
      Passed -> 1
      NoChanges -> 0

prob :: Double -> Text
prob = renderProbability

bound :: Int -> Text -> Text
bound n t = if T.length t <= n then t else T.take n t <> "…"

loc :: Location -> Text
loc l = T.pack (l ^. #path) <> maybe "" (\n -> ":" <> T.pack (show n)) (l ^. #line)

renderHuman :: JudgementDefinition -> JudgementDecision -> Text
renderHuman = renderHumanFor "staged changes"

-- | The human report for a named evidence scope, such as
-- @staged changes@ or @commits abc1234..def5678@.
renderHumanFor :: Text -> JudgementDefinition -> JudgementDecision -> Text
renderHumanFor scopeLabel def d =
  T.unlines $
    [ d ^. #judgement <> "  " <> renderJudgementStatus (d ^. #status),
      "Scope: " <> scopeLabel <> "; " <> coverageLine
    ]
      <> [ loc (f ^. #location) <> "  critical  " <> f ^. #rule <> " (deterministic " <> renderDeterministicCheck (f ^. #check) <> ")"
         | f <- d ^. #deterministic
         ]
      <> map ("error: " <>) (d ^. #deterministicErrors)
      <> concatMap checkLines (d ^. #checks)
      <> ["uncovered: " <> T.pack p <> " (" <> why <> ")" | (p, why) <- d ^. #coverage . #uncoveredFiles]
      <> nextStep
  where
    reviewed = length (d ^. #coverage . #reviewedFiles)
    uncovered = length (d ^. #coverage . #uncoveredFiles)
    coverageLine
      | not (null (d ^. #deterministic)) = "stopped by deterministic findings; nothing was sent for review"
      | d ^. #status == NoChanges = "nothing in scope"
      | uncovered == 0 = "complete for " <> T.pack (show reviewed) <> " changed text files"
      | otherwise = "incomplete: " <> T.pack (show uncovered) <> " files not reviewed"
    checkLines c =
      let pol = c ^. #policy
          advisory = if c ^. #enforcement == Advisory then " (advisory)" else ""
          probLine = case (c ^. #reviewConcern, c ^. #gateConcern) of
            (Just p, _) -> "  model-reported probability " <> prob p <> " (pass at " <> prob (pol ^. #review . #passAt) <> ", block at " <> prob (pol ^. #review . #blockAt) <> ")"
            (Nothing, Just g) -> "  gate probability " <> prob g <> " (gate pass at " <> prob (pol ^. #gate . #passAt) <> ")"
            _ -> ""
          direction = case [ch | ch <- toListChecks, ch ^. #name == c ^. #check, ch ^. #concernWhen == No] of
            [] -> []
            _ -> ["  probabilities are of the concern, a no answer: one minus the model's probability of yes"]
       in [c ^. #check <> "  " <> renderCheckStatus (c ^. #status) <> advisory <> probLine]
            <> direction
            <> ["  " <> loc (f ^. #location) <> "  " <> renderSeverity (f ^. #severity) <> "  " <> f ^. #category <> ": " <> bound 300 (f ^. #explanation) | f <- c ^. #findings]
            <> ["  " <> bound 300 (renderDecisionReason r) | r <- c ^. #reasons, isNotable r]
    isNotable = \case
      BlockingFinding _ -> False
      ConcernAtOrBelowPass _ _ -> False
      _ -> True
    toListChecks = foldr (:) [] (def ^. #checks)
    nextStep = case d ^. #status of
      Blocked -> ["Resolve the blocking findings in the staged content, then run seihou check."]
      NeedsReview -> ["Confirm the flagged content is acceptable or change it, then run seihou check."]
      Failed -> ["The review could not complete; fix the errors above, then run seihou check."]
      _ -> []

renderJson :: [(JudgementDefinition, JudgementDecision)] -> Value
renderJson pairs =
  object
    [ "version" .= reportVersion,
      "status" .= statusKey overall,
      "exitCode" .= exitCodeFor overall,
      "judgements" .= map one pairs
    ]
  where
    overall = combinedStatus [d ^. #status | (_, d) <- pairs]
    statusKey = \case
      Passed -> "passed" :: Text
      Blocked -> "blocked"
      NeedsReview -> "needs-review"
      Failed -> "error"
      NoChanges -> "no-changes"
    one (def, d) =
      object
        [ "name" .= (def ^. #name),
          "version" .= (def ^. #version),
          "status" .= statusKey (d ^. #status),
          "coverage"
            .= object
              [ "reviewed" .= (d ^. #coverage . #reviewedFiles),
                "excluded" .= (d ^. #coverage . #excludedFiles),
                "uncovered" .= [object ["path" .= p, "reason" .= why] | (p, why) <- d ^. #coverage . #uncoveredFiles]
              ],
          "deterministic" .= [object ["check" .= renderDeterministicCheck (f ^. #check), "rule" .= (f ^. #rule), "path" .= (f ^. #location . #path), "line" .= (f ^. #location . #line)] | f <- d ^. #deterministic],
          "errors" .= (d ^. #deterministicErrors),
          "checks" .= map check (d ^. #checks)
        ]
    check c =
      object
        [ "name" .= (c ^. #check),
          "status" .= renderCheckStatus (c ^. #status),
          "enforcement" .= renderEnforcement (c ^. #enforcement),
          "probabilitySource" .= ("model-reported" :: Text),
          "reviewConcern" .= (c ^. #reviewConcern),
          "gateConcern" .= (c ^. #gateConcern),
          "thresholds"
            .= object
              [ "review" .= object ["blockAt" .= (c ^. #policy . #review . #blockAt), "passAt" .= (c ^. #policy . #review . #passAt)],
                "gate" .= object ["blockAt" .= (c ^. #policy . #gate . #blockAt), "passAt" .= (c ^. #policy . #gate . #passAt)]
              ],
          "decidedBy" .= [route (ch ^. #decidedBy) | ch <- c ^. #chunks],
          "findings" .= [object ["category" .= (f ^. #category), "severity" .= renderSeverity (f ^. #severity), "path" .= (f ^. #location . #path), "line" .= (f ^. #location . #line), "explanation" .= bound 300 (f ^. #explanation)] | f <- c ^. #findings],
          "reasons" .= map (bound 300 . renderDecisionReason) (c ^. #reasons)
        ]
    route = \case
      DecidedByGate -> "gate" :: Text
      DecidedByReview -> "review"
      DecidedByNone -> "none"
