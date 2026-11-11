-- | The domain of judgements: author-defined yes/no checks over captured
-- evidence, and the deterministic project policy that turns model-reported
-- evidence into a decision.
--
-- A judgement is a list of checks. Each check is one question about the
-- evidence, with a declared concern direction (whether a yes or a no answer is
-- the concern), its own enforcement, and its own threshold band for the
-- generative review and, separately, for an optional judgment-only gate.
--
-- Every probability in this module is the probability of the /concern/,
-- already converted from the model's probability of yes by
-- 'concernProbability'. A higher number is always worse, whichever answer the
-- concern is, so the policy functions never consult the concern direction.
--
-- Nothing in this module refers to secrets or security: the secret scan is one
-- member of the closed set of deterministic checks, and scanner results reach
-- the policy only as deterministic findings.
--
-- This module is pure and knows nothing about Shikumi, provider transports or
-- Git. The runtime adapter in seihou-cli converts provider replies into the
-- observation types below; 'decideCheck' and 'decideJudgement' then decide.
module Seihou.Core.Judgement
  ( -- * Definitions
    JudgementDefinition (..),
    JudgementCheck (..),
    Answer (..),
    Enforcement (..),
    Thresholds (..),
    Severity (..),
    FindingCategory (..),
    EvidenceDeclaration (..),
    EvidenceScopeKind (..),
    CoverageLimits (..),
    DeterministicCheck (..),
    defaultCoverageLimits,
    defaultEvidenceDeclaration,
    renderAnswer,
    renderEnforcement,
    renderSeverity,
    renderDeterministicCheck,
    renderScopeKind,

    -- * Validation
    JudgementError (..),
    judgementError,
    validateDefinition,
    validateThresholds,

    -- * Policy
    DataPolicy (..),
    renderDataPolicy,
    JudgementPolicy (..),
    CheckPolicy (..),
    defaultPolicy,
    checkPolicyFor,

    -- * Probabilities
    concernProbability,
    validProbability,
    renderProbability,

    -- * Observations
    Location (..),
    Finding (..),
    DeterministicFinding (..),
    ReviewObservation (..),
    GateObservation (..),
    ChunkObservation (..),
    CheckObservation (..),
    Coverage (..),
    JudgementObservation (..),

    -- * Output validation
    EvidenceIndex (..),
    RawFinding (..),
    RawReview (..),
    validateReview,
    findingBlocks,

    -- * Decisions
    CheckStatus (..),
    renderCheckStatus,
    DecidedBy (..),
    DecisionReason (..),
    renderDecisionReason,
    ChunkDecision (..),
    CheckDecision (..),
    JudgementStatus (..),
    renderJudgementStatus,
    JudgementDecision (..),
    decideChunk,
    decideCheck,
    decideJudgement,
    statusSeverity,
  )
where

import Control.Monad (forM_, unless, when)
import Data.Foldable (toList)
import Data.Generics.Labels ()
import Data.List (sortOn)
import Data.List.NonEmpty (NonEmpty)
import Data.List.NonEmpty qualified as NE
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Ord (Down (..))
import Data.Text qualified as T
import Seihou.Prelude

-- ---------------------------------------------------------------------------
-- Definitions

-- | Which answer to a check's question is the concern.
data Answer = Yes | No
  deriving stock (Eq, Ord, Show, Bounded, Enum, Generic)

renderAnswer :: Answer -> Text
renderAnswer Yes = "yes"
renderAnswer No = "no"

-- | Whether a check's outcome can prevent the gated action.
data Enforcement = Enforced | Advisory
  deriving stock (Eq, Ord, Show, Bounded, Enum, Generic)

renderEnforcement :: Enforcement -> Text
renderEnforcement Enforced = "enforced"
renderEnforcement Advisory = "advisory"

-- | A threshold band over the probability of the concern. At or above
-- 'blockAt' the check blocks; at or below 'passAt' it may pass; in between it
-- needs human review. Equal values remove the needs-review band.
data Thresholds = Thresholds
  { blockAt :: !Double,
    passAt :: !Double
  }
  deriving stock (Eq, Show, Generic)

-- | Declared severity of a finding category, least severe first.
data Severity = Info | Low | Medium | High | Critical
  deriving stock (Eq, Ord, Show, Bounded, Enum, Generic)

renderSeverity :: Severity -> Text
renderSeverity = \case
  Info -> "info"
  Low -> "low"
  Medium -> "medium"
  High -> "high"
  Critical -> "critical"

-- | A category a check's findings may use. The model names the category; the
-- severity is the author's, never the model's.
data FindingCategory = FindingCategory
  { name :: !Text,
    severity :: !Severity,
    description :: !(Maybe Text)
  }
  deriving stock (Eq, Show, Generic)

-- | The closed, versioned set of evidence scopes in this delivery.
data EvidenceScopeKind = StagedChangesScope | CommitRangeScope
  deriving stock (Eq, Ord, Show, Bounded, Enum, Generic)

renderScopeKind :: EvidenceScopeKind -> Text
renderScopeKind StagedChangesScope = "staged-changes"
renderScopeKind CommitRangeScope = "commit-range"

-- | Which evidence a judgement may inspect. Path patterns are Git-style
-- globs relative to the project root; an empty include list means every path.
data EvidenceDeclaration = EvidenceDeclaration
  { scopes :: ![EvidenceScopeKind],
    include :: ![Text],
    exclude :: ![Text]
  }
  deriving stock (Eq, Show, Generic)

defaultEvidenceDeclaration :: EvidenceDeclaration
defaultEvidenceDeclaration = EvidenceDeclaration [StagedChangesScope, CommitRangeScope] [] []

-- | Declared bounds on one review. Exceeding a bound never truncates
-- silently: the uncovered files are reported and the check cannot pass.
data CoverageLimits = CoverageLimits
  { maxFileBytes :: !Int,
    maxChunkBytes :: !Int,
    maxChunks :: !Int,
    maxAttempts :: !Int,
    timeoutSeconds :: !Int,
    maxFindings :: !Int
  }
  deriving stock (Eq, Show, Generic)

defaultCoverageLimits :: CoverageLimits
defaultCoverageLimits =
  CoverageLimits
    { maxFileBytes = 262144,
      maxChunkBytes = 49152,
      maxChunks = 16,
      maxAttempts = 3,
      timeoutSeconds = 120,
      maxFindings = 20
    }

-- | The closed, versioned set of deterministic checks.
data DeterministicCheck = SecretScan
  deriving stock (Eq, Ord, Show, Bounded, Enum, Generic)

renderDeterministicCheck :: DeterministicCheck -> Text
renderDeterministicCheck SecretScan = "secret-scan"

-- | One author-written yes/no question.
data JudgementCheck = JudgementCheck
  { name :: !Text,
    question :: !Text,
    concernWhen :: !Answer,
    yesMeans :: !(Maybe Text),
    noMeans :: !(Maybe Text),
    categories :: ![FindingCategory],
    enforcement :: !Enforcement,
    -- | Findings whose category severity is at or above this block.
    blockingSeverity :: !Severity,
    review :: !Thresholds,
    gate :: !Thresholds,
    useGate :: !Bool
  }
  deriving stock (Eq, Show, Generic)

data JudgementDefinition = JudgementDefinition
  { name :: !Text,
    version :: !(Maybe Text),
    description :: !(Maybe Text),
    instructions :: !Text,
    evidence :: !EvidenceDeclaration,
    limits :: !CoverageLimits,
    deterministicChecks :: ![DeterministicCheck],
    checks :: !(NonEmpty JudgementCheck)
  }
  deriving stock (Eq, Show, Generic)

-- ---------------------------------------------------------------------------
-- Validation

-- | A stable machine code and an actionable explanation naming the artifact
-- part as an author writes it.
data JudgementError = JudgementError {code :: !Text, message :: !Text}
  deriving stock (Eq, Show, Generic)

judgementError :: Text -> Text -> JudgementError
judgementError = JudgementError

validProbability :: Double -> Bool
validProbability p = not (isNaN p || isInfinite p) && p >= 0 && p <= 1

validateThresholds :: Text -> Thresholds -> Either JudgementError ()
validateThresholds what t = do
  forM_ [("blockAt", t ^. #blockAt), ("passAt", t ^. #passAt)] $ \(label, p) ->
    unless (validProbability p) $
      Left (judgementError "judgement_threshold_out_of_range" (what <> " " <> label <> " must be between 0 and 1, got " <> T.pack (show p)))
  when (t ^. #passAt > t ^. #blockAt) $
    Left
      ( judgementError
          "judgement_threshold_inverted"
          (what <> " passAt (" <> T.pack (show (t ^. #passAt)) <> ") must not exceed blockAt (" <> T.pack (show (t ^. #blockAt)) <> ")")
      )

-- | Structural validation of a definition. Free of discovery, configuration
-- and prompts, so it can run on a descriptor alone.
validateDefinition :: JudgementDefinition -> Either JudgementError ()
validateDefinition def = do
  let jname = def ^. #name
  validName "judgement" jname
  when (T.null (T.strip (def ^. #instructions)) && all (T.null . T.strip . (^. #question)) (def ^. #checks)) $
    Left (judgementError "judgement_empty" ("judgement '" <> jname <> "' has no instructions and no check questions"))
  when (null (def ^. #evidence . #scopes)) $
    Left (judgementError "judgement_no_scope" ("judgement '" <> jname <> "' declares no evidence scope"))
  forM_ ((def ^. #evidence . #include) <> (def ^. #evidence . #exclude)) $ \pat ->
    when (T.null pat || "/" `T.isPrefixOf` pat || ".." `elem` T.splitOn "/" pat) $
      Left (judgementError "judgement_bad_path_pattern" ("judgement '" <> jname <> "' path pattern '" <> pat <> "' must be a non-empty project-relative pattern without '..'"))
  validateLimits jname (def ^. #limits)
  let names = map (^. #name) (toList (def ^. #checks))
  forM_ (duplicates names) $ \dup ->
    Left (judgementError "judgement_duplicate_check" ("judgement '" <> jname <> "' declares check '" <> dup <> "' more than once"))
  forM_ (def ^. #checks) $ \check -> do
    let cname = check ^. #name
        what = "check '" <> cname <> "' of judgement '" <> jname <> "'"
    validName "check" cname
    when (T.null (T.strip (check ^. #question))) $
      Left (judgementError "judgement_empty_question" (what <> " has an empty question"))
    validateThresholds (what <> " review") (check ^. #review)
    validateThresholds (what <> " gate") (check ^. #gate)
    let cats = map (^. #name) (check ^. #categories)
    forM_ cats (validName "finding category")
    forM_ (duplicates cats) $ \dup ->
      Left (judgementError "judgement_duplicate_category" (what <> " declares finding category '" <> dup <> "' more than once"))
  where
    validName kind n =
      unless (not (T.null n) && T.all (\c -> c `elem` ['a' .. 'z'] || c `elem` ['0' .. '9'] || c == '-') n && T.head n /= '-') $
        Left (judgementError "judgement_bad_name" (kind <> " name '" <> n <> "' must be lowercase letters, digits and hyphens, starting with a letter or digit"))

validateLimits :: Text -> CoverageLimits -> Either JudgementError ()
validateLimits jname l =
  forM_
    [ ("maxFileBytes", l ^. #maxFileBytes),
      ("maxChunkBytes", l ^. #maxChunkBytes),
      ("maxChunks", l ^. #maxChunks),
      ("maxAttempts", l ^. #maxAttempts),
      ("timeoutSeconds", l ^. #timeoutSeconds),
      ("maxFindings", l ^. #maxFindings)
    ]
    $ \(label, v) ->
      when (v <= 0) $
        Left (judgementError "judgement_bad_limit" ("judgement '" <> jname <> "' limit " <> label <> " must be positive, got " <> T.pack (show v)))

duplicates :: [Text] -> [Text]
duplicates xs = Map.keys (Map.filter (> (1 :: Int)) (Map.fromListWith (+) [(x, 1) | x <- xs]))

-- ---------------------------------------------------------------------------
-- Policy

-- | Where review material may be sent. 'LocalOnly' never permits a hosted
-- destination, even through a locally running executable.
data DataPolicy = LocalOnly | ApprovedRemote
  deriving stock (Eq, Ord, Show, Bounded, Enum, Generic)

renderDataPolicy :: DataPolicy -> Text
renderDataPolicy LocalOnly = "local-only"
renderDataPolicy ApprovedRemote = "approved-remote"

-- | The effective, project-owned policy for one check.
data CheckPolicy = CheckPolicy
  { enforcement :: !Enforcement,
    blockingSeverity :: !Severity,
    review :: !Thresholds,
    gate :: !Thresholds,
    useGate :: !Bool
  }
  deriving stock (Eq, Show, Generic)

data JudgementPolicy = JudgementPolicy
  { dataPolicy :: !DataPolicy,
    gatePermitted :: !Bool,
    checks :: !(Map Text CheckPolicy)
  }
  deriving stock (Eq, Show, Generic)

-- | The policy a definition's authored defaults imply.
defaultPolicy :: DataPolicy -> Bool -> JudgementDefinition -> JudgementPolicy
defaultPolicy dp gatePerm def =
  JudgementPolicy
    { dataPolicy = dp,
      gatePermitted = gatePerm,
      checks = Map.fromList [(c ^. #name, fromCheck c) | c <- toList (def ^. #checks)]
    }
  where
    fromCheck c =
      CheckPolicy
        { enforcement = c ^. #enforcement,
          blockingSeverity = c ^. #blockingSeverity,
          review = c ^. #review,
          gate = c ^. #gate,
          useGate = c ^. #useGate
        }

-- | The recorded policy for a check, falling back to its authored defaults.
checkPolicyFor :: JudgementPolicy -> JudgementCheck -> CheckPolicy
checkPolicyFor policy c =
  fromMaybe
    (CheckPolicy (c ^. #enforcement) (c ^. #blockingSeverity) (c ^. #review) (c ^. #gate) (c ^. #useGate))
    (Map.lookup (c ^. #name) (policy ^. #checks))

-- ---------------------------------------------------------------------------
-- Probabilities

-- | Convert a model's probability of yes into the probability of the
-- concern. This is the only place the concern direction is consulted.
concernProbability :: Answer -> Double -> Double
concernProbability Yes p = p
concernProbability No p = 1 - p

-- ---------------------------------------------------------------------------
-- Observations

-- | A validated location inside captured evidence. Lines are 1-based and
-- refer to the post-change content.
data Location = Location
  { path :: !FilePath,
    line :: !(Maybe Int)
  }
  deriving stock (Eq, Ord, Show, Generic)

data Finding = Finding
  { category :: !Text,
    severity :: !Severity,
    location :: !Location,
    explanation :: !Text
  }
  deriving stock (Eq, Show, Generic)

-- | A finding from a deterministic check. It always blocks.
data DeterministicFinding = DeterministicFinding
  { check :: !DeterministicCheck,
    rule :: !Text,
    location :: !Location
  }
  deriving stock (Eq, Show, Generic)

-- | A validated generative review reply for one chunk.
data ReviewObservation = ReviewObservation
  { concern :: !Double,
    findings :: ![Finding],
    requestedHumanReview :: !Bool
  }
  deriving stock (Eq, Show, Generic)

-- | What the judgment-only gate reported for one chunk.
data GateObservation
  = GateAnswered !Double
  | GateFailed !Text
  deriving stock (Eq, Show, Generic)

-- | Everything observed for one check over one evidence chunk.
data ChunkObservation = ChunkObservation
  { chunk :: !Int,
    gate :: !(Maybe GateObservation),
    -- | 'Nothing' when no review ran (cleared by the gate, or never sent).
    review :: !(Maybe (Either Text ReviewObservation))
  }
  deriving stock (Eq, Show, Generic)

-- | Seihou's own coverage measurement, never the model's.
data Coverage = Coverage
  { reviewedFiles :: ![FilePath],
    excludedFiles :: ![FilePath],
    uncoveredFiles :: ![(FilePath, Text)]
  }
  deriving stock (Eq, Show, Generic)

data CheckObservation = CheckObservation
  { check :: !Text,
    chunks :: ![ChunkObservation],
    -- | Errors that prevented review of this check, such as material the
    -- transmission safeguard refused to send.
    errors :: ![Text]
  }
  deriving stock (Eq, Show, Generic)

data JudgementObservation = JudgementObservation
  { coverage :: !Coverage,
    deterministic :: ![DeterministicFinding],
    deterministicErrors :: ![Text],
    checks :: ![CheckObservation],
    noChanges :: !Bool
  }
  deriving stock (Eq, Show, Generic)

-- ---------------------------------------------------------------------------
-- Output validation

-- | The files a reply may cite, with their post-change line counts.
newtype EvidenceIndex = EvidenceIndex {files :: Map FilePath Int}
  deriving stock (Eq, Show, Generic)

-- | A decoded but not yet validated finding from the runtime adapter.
data RawFinding = RawFinding
  { category :: !Text,
    path :: !Text,
    line :: !(Maybe Int),
    explanation :: !Text
  }
  deriving stock (Eq, Show, Generic)

-- | A decoded but not yet validated review, with the probability already
-- converted to the probability of the concern.
data RawReview = RawReview
  { concern :: !Double,
    findings :: ![RawFinding],
    requestedHumanReview :: !Bool
  }
  deriving stock (Eq, Show, Generic)

-- | Enforce the domain after decoding: declared categories, locations inside
-- the captured evidence, bounded output and a probability in range. The
-- model reports evidence; it never chooses a category's severity.
validateReview :: CoverageLimits -> JudgementCheck -> EvidenceIndex -> RawReview -> Either Text ReviewObservation
validateReview limits check index raw = do
  unless (validProbability (raw ^. #concern)) $
    Left ("the reply's probability " <> renderProbability (raw ^. #concern) <> " is outside 0 to 1")
  when (length (raw ^. #findings) > limits ^. #maxFindings) $
    Left ("the reply has " <> T.pack (show (length (raw ^. #findings))) <> " findings, more than the limit of " <> T.pack (show (limits ^. #maxFindings)))
  let declared = Map.fromList [(c ^. #name, c ^. #severity) | c <- check ^. #categories]
  found <- traverse (validateFinding declared) (raw ^. #findings)
  pure (ReviewObservation (raw ^. #concern) found (raw ^. #requestedHumanReview))
  where
    validateFinding declared f = do
      sev <- case Map.lookup (f ^. #category) declared of
        Just s -> Right s
        Nothing -> Left ("the reply uses finding category '" <> bounded 64 (f ^. #category) <> "', which check '" <> check ^. #name <> "' does not declare")
      let p = T.unpack (f ^. #path)
      lineCount <- case Map.lookup p (index ^. #files) of
        Just n -> Right n
        Nothing -> Left ("the reply cites '" <> bounded 200 (f ^. #path) <> "', which is not in the reviewed evidence")
      forM_ (f ^. #line) $ \l ->
        when (l < 1 || l > max 1 lineCount) $
          Left ("the reply cites line " <> T.pack (show l) <> " of '" <> T.pack p <> "', which has " <> T.pack (show lineCount) <> " lines")
      pure (Finding (f ^. #category) sev (Location p (f ^. #line)) (bounded 500 (f ^. #explanation)))

bounded :: Int -> Text -> Text
bounded n t
  | T.length t <= n = t
  | otherwise = T.take n t <> "…"

findingBlocks :: CheckPolicy -> Finding -> Bool
findingBlocks policy f = f ^. #severity >= policy ^. #blockingSeverity

-- ---------------------------------------------------------------------------
-- Decisions

data CheckStatus = CheckPassed | CheckBlocked | CheckNeedsReview | CheckFailed | CheckNoChanges
  deriving stock (Eq, Ord, Show, Bounded, Enum, Generic)

renderCheckStatus :: CheckStatus -> Text
renderCheckStatus = \case
  CheckPassed -> "passed"
  CheckBlocked -> "blocked"
  CheckNeedsReview -> "needs review"
  CheckFailed -> "error"
  CheckNoChanges -> "no changes"

-- | Ranking used to combine outcomes: block above needs-review above error
-- above pass above no-changes.
statusSeverity :: CheckStatus -> Int
statusSeverity = \case
  CheckBlocked -> 4
  CheckNeedsReview -> 3
  CheckFailed -> 2
  CheckPassed -> 1
  CheckNoChanges -> 0

-- | Which route decided a chunk.
data DecidedBy = DecidedByGate | DecidedByReview | DecidedByNone
  deriving stock (Eq, Ord, Show, Generic)

-- | Why a check reached its status. Rendered for humans; the constructors
-- are stable for JSON reports.
data DecisionReason
  = BlockingFinding !Finding
  | ConcernAtOrAboveBlock !Double !Double
  | ConcernInBand !Double !Thresholds
  | ConcernAtOrBelowPass !Double !Double
  | ModelRequestedReview
  | GateCleared !Double !Double
  | GateEscalated !Double !Double
  | GateDisagreed !Double !Double
  | GateUnavailable !Text
  | ReviewMissing
  | ReviewError !Text
  | CheckError !Text
  deriving stock (Eq, Show, Generic)

renderDecisionReason :: DecisionReason -> Text
renderDecisionReason = \case
  BlockingFinding f -> "blocking " <> renderSeverity (f ^. #severity) <> " finding '" <> f ^. #category <> "' at " <> renderLoc (f ^. #location)
  ConcernAtOrAboveBlock p t -> "model-reported probability " <> fmt p <> " is at or above block threshold " <> fmt t <> "; the review gave no location"
  ConcernInBand p t -> "model-reported probability " <> fmt p <> " is between pass at " <> fmt (t ^. #passAt) <> " and block at " <> fmt (t ^. #blockAt)
  ConcernAtOrBelowPass p t -> "model-reported probability " <> fmt p <> " is at or below pass threshold " <> fmt t
  ModelRequestedReview -> "the model requested human review"
  GateCleared p t -> "cleared by gate, probability " <> fmt p <> " at or below " <> fmt t
  GateEscalated p t -> "gate probability " <> fmt p <> " above gate pass threshold " <> fmt t <> "; escalated to review"
  GateDisagreed p t -> "gate probability " <> fmt p <> " reached gate block threshold " <> fmt t <> "; the review cannot pass this check"
  GateUnavailable why -> "gate unavailable (" <> why <> "); escalated to review"
  ReviewMissing -> "escalated, but no review result was produced"
  ReviewError why -> "review failed: " <> why
  CheckError why -> why
  where
    renderLoc l = T.pack (l ^. #path) <> maybe "" (\n -> ":" <> T.pack (show n)) (l ^. #line)

fmt :: Double -> Text
fmt = renderProbability

-- | A probability as a reader expects it, with two decimals: @0.02@, not
-- @2.0e-2@. Values outside 0 to 1 are rendered the same way so a diagnostic
-- can name them.
renderProbability :: Double -> Text
renderProbability p
  | isNaN p || isInfinite p = T.pack (show p)
  | otherwise =
      let hundredths = round (abs p * 100) :: Integer
          (whole, frac) = hundredths `divMod` 100
       in (if p < 0 && hundredths /= 0 then "-" else "") <> T.pack (show whole) <> "." <> (if frac < 10 then "0" else "") <> T.pack (show frac)

data ChunkDecision = ChunkDecision
  { chunk :: !Int,
    status :: !CheckStatus,
    decidedBy :: !DecidedBy,
    gateConcern :: !(Maybe Double),
    reviewConcern :: !(Maybe Double),
    findings :: ![Finding],
    reasons :: ![DecisionReason]
  }
  deriving stock (Eq, Show, Generic)

data CheckDecision = CheckDecision
  { check :: !Text,
    status :: !CheckStatus,
    enforcement :: !Enforcement,
    policy :: !CheckPolicy,
    chunks :: ![ChunkDecision],
    -- | The governing (highest) concern probabilities over all chunks.
    gateConcern :: !(Maybe Double),
    reviewConcern :: !(Maybe Double),
    findings :: ![Finding],
    reasons :: ![DecisionReason]
  }
  deriving stock (Eq, Show, Generic)

-- | Apply one check's policy to one chunk's observation.
--
-- * The gate clears a chunk at or below its pass threshold; no review is
--   needed. A higher gate probability escalates, and a gate probability at or
--   above its block threshold forbids the review from passing the chunk.
-- * A gate failure escalates visibly; it is neither an error nor a clearance.
-- * In the review, a blocking finding blocks; a probability at or above the
--   block threshold blocks even without a location; a probability above the
--   pass threshold, or a request for human review, needs review; only a
--   probability at or below the pass threshold passes.
decideChunk :: Bool -> CheckPolicy -> ChunkObservation -> ChunkDecision
decideChunk gateActive policy obs =
  case (if gateActive && policy ^. #useGate then obs ^. #gate else Nothing) of
    Just (GateAnswered g)
      | g <= gatePass && validProbability g ->
          ChunkDecision (obs ^. #chunk) CheckPassed DecidedByGate (Just g) Nothing [] [GateCleared g gatePass]
      | validProbability g ->
          let escalation = GateEscalated g gatePass
              disagree = g >= gateBlock
              d = fromReview (Just g) [escalation]
           in if disagree && d ^. #status == CheckPassed
                then d & #status .~ CheckNeedsReview & #reasons %~ (<> [GateDisagreed g gateBlock])
                else d
      | otherwise ->
          fromReview Nothing [GateUnavailable ("probability " <> renderProbability g <> " is outside 0 to 1")]
    Just (GateFailed why) -> fromReview Nothing [GateUnavailable why]
    Nothing -> fromReview Nothing []
  where
    gatePass = policy ^. #gate . #passAt
    gateBlock = policy ^. #gate . #blockAt
    reviewT = policy ^. #review
    fromReview gateP prior = case obs ^. #review of
      Nothing -> ChunkDecision (obs ^. #chunk) CheckFailed DecidedByNone gateP Nothing [] (prior <> [ReviewMissing])
      Just (Left why) -> ChunkDecision (obs ^. #chunk) CheckFailed DecidedByReview gateP Nothing [] (prior <> [ReviewError why])
      Just (Right r) ->
        let p = r ^. #concern
            blocking = filter (findingBlocks policy) (r ^. #findings)
            (status, reasons)
              | not (validProbability p) = (CheckFailed, [ReviewError ("probability " <> renderProbability p <> " is outside 0 to 1")])
              | not (null blocking) = (CheckBlocked, map BlockingFinding blocking)
              | p >= reviewT ^. #blockAt = (CheckBlocked, [ConcernAtOrAboveBlock p (reviewT ^. #blockAt)])
              | p > reviewT ^. #passAt = (CheckNeedsReview, [ConcernInBand p reviewT] <> [ModelRequestedReview | r ^. #requestedHumanReview])
              | r ^. #requestedHumanReview = (CheckNeedsReview, [ModelRequestedReview])
              | otherwise = (CheckPassed, [ConcernAtOrBelowPass p (reviewT ^. #passAt)])
         in ChunkDecision (obs ^. #chunk) status DecidedByReview gateP (Just p) (r ^. #findings) (prior <> reasons)

-- | Combine a check's chunks. The most severe chunk governs, and the highest
-- probability over all chunks is reported. A check with no chunks and no
-- errors had nothing in scope.
decideCheck :: Bool -> Coverage -> CheckPolicy -> CheckObservation -> CheckDecision
decideCheck gateActive coverage policy obs =
  CheckDecision
    { check = obs ^. #check,
      status = finalStatus,
      enforcement = policy ^. #enforcement,
      policy = policy,
      chunks = decided,
      gateConcern = maximumMaybe (mapMaybe (^. #gateConcern) decided),
      reviewConcern = maximumMaybe (mapMaybe (^. #reviewConcern) decided),
      findings = concatMap (^. #findings) decided,
      reasons = map CheckError (obs ^. #errors) <> uncoveredReasons <> concatMap (^. #reasons) decided
    }
  where
    decided = map (decideChunk gateActive policy) (obs ^. #chunks)
    uncovered = coverage ^. #uncoveredFiles
    uncoveredReasons = [CheckError ("'" <> T.pack p <> "' was not reviewed: " <> why) | (p, why) <- uncovered]
    chunkStatus = case sortOn (Down . statusSeverity) (map (^. #status) decided) of
      (s : _) -> s
      [] -> CheckNoChanges
    finalStatus
      | not (null (obs ^. #errors)) = worst [chunkStatus, CheckFailed]
      | not (null uncovered) = worst [chunkStatus, CheckFailed]
      | otherwise = chunkStatus
    worst = NE.head . NE.sortWith (Down . statusSeverity) . NE.fromList

maximumMaybe :: [Double] -> Maybe Double
maximumMaybe [] = Nothing
maximumMaybe xs = Just (maximum xs)

data JudgementStatus = Passed | Blocked | NeedsReview | Failed | NoChanges
  deriving stock (Eq, Ord, Show, Bounded, Enum, Generic)

renderJudgementStatus :: JudgementStatus -> Text
renderJudgementStatus = \case
  Passed -> "PASSED"
  Blocked -> "BLOCKED"
  NeedsReview -> "NEEDS REVIEW"
  Failed -> "ERROR"
  NoChanges -> "NO CHANGES"

data JudgementDecision = JudgementDecision
  { judgement :: !Text,
    status :: !JudgementStatus,
    deterministic :: ![DeterministicFinding],
    deterministicErrors :: ![Text],
    checks :: ![CheckDecision],
    coverage :: !Coverage
  }
  deriving stock (Eq, Show, Generic)

-- | Combine a judgement's checks under its policy. A deterministic finding
-- blocks regardless of any probability. Among enforced checks the most
-- severe outcome governs: block, then needs-review, then error. Advisory
-- checks are reported with their real status and never affect the result.
-- Empty evidence is 'NoChanges', an explicit no-op rather than a review.
decideJudgement :: JudgementDefinition -> JudgementPolicy -> JudgementObservation -> JudgementDecision
decideJudgement def policy obs =
  JudgementDecision
    { judgement = def ^. #name,
      status = overall,
      deterministic = obs ^. #deterministic,
      deterministicErrors = obs ^. #deterministicErrors,
      checks = decisions,
      coverage = obs ^. #coverage
    }
  where
    gateActive = policy ^. #gatePermitted
    observed = Map.fromList [(o ^. #check, o) | o <- obs ^. #checks]
    decisions =
      [ decideCheck gateActive (obs ^. #coverage) (checkPolicyFor policy c) (Map.findWithDefault (missing c) (c ^. #name) observed)
      | c <- toList (def ^. #checks)
      ]
    missing c
      | obs ^. #noChanges = CheckObservation (c ^. #name) [] []
      | otherwise = CheckObservation (c ^. #name) [] ["check '" <> c ^. #name <> "' produced no observation"]
    enforced = [d ^. #status | d <- decisions, d ^. #enforcement == Enforced]
    overall
      | not (null (obs ^. #deterministic)) = Blocked
      | CheckBlocked `elem` enforced = Blocked
      | CheckNeedsReview `elem` enforced = NeedsReview
      | CheckFailed `elem` enforced || not (null (obs ^. #deterministicErrors)) = Failed
      | obs ^. #noChanges = NoChanges
      | all (== CheckNoChanges) enforced && not (null enforced) = NoChanges
      | otherwise = Passed
