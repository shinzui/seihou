-- | Pure selection/rendering and callback-driven execution for ordered
-- agent-guided blueprint migrations.
module Seihou.CLI.BlueprintMigration
  ( BlueprintMigrationLaunchFailure (..),
    BlueprintMigrationLaunchResult (..),
    BlueprintMigrationRunResult (..),
    renderBlueprintMigrationInstruction,
    renderBlueprintMigrationSystemPrompt,
    formatBlueprintMigrationDebugOutput,
    formatMigrationStepLabel,
    pendingBlueprintMigrations,
    parseNotApplicableSignal,
    unstatedNotApplicableReason,
    runBlueprintMigrationsWith,
  )
where

import Data.Char (isAlphaNum, isSpace)
import Data.Generics.Labels ()
import Data.Maybe (fromMaybe, listToMaybe, mapMaybe)
import Data.Text qualified as T
import Seihou.CLI.AgentLaunch
  ( AgentContext (..),
    formatAvailableModules,
    formatLocalModules,
    formatManifestState,
    formatModuleDhallState,
    formatSeihouProjectState,
    substitute,
  )
import Seihou.CLI.BlueprintExecution
  ( PreparedBlueprintExecution (..),
    renderBlueprintText,
  )
import Seihou.Core.ArtifactIdentity (sameArtifactIdentity)
import Seihou.Core.Migration
  ( BlueprintMigration (..),
    BlueprintMigrationPlan (..),
    BlueprintMigrationStep (..),
    EntailmentSite (..),
  )
import Seihou.Core.Types
  ( AppliedBlueprintMigration (..),
    ArtifactOrigin (..),
    Blueprint (..),
    MigrationOutcome (..),
    ModuleName (..),
    ResolvedVar,
    VarName,
  )
import Seihou.Prelude
import System.Exit (ExitCode)

-- | Provider failures retain either a real interactive process exit or API
-- error text rather than collapsing both paths into an artificial exit code.
data BlueprintMigrationLaunchFailure
  = BlueprintMigrationProcessFailure ExitCode
  | BlueprintMigrationProviderFailure Text
  deriving stock (Eq, Show)

-- | What one edge's provider interaction produced, when it produced anything
-- at all. A launch that never returned is a 'BlueprintMigrationLaunchFailure'
-- instead; these two constructors are both non-failures, and the chain
-- continues past either of them.
data BlueprintMigrationLaunchResult
  = BlueprintMigrationSessionReturned
  | BlueprintMigrationSessionNotApplicable !Text
  deriving stock (Eq, Show)

-- | Terminal outcome for one pending migration chain.
--
-- 'BlueprintMigrationComplete' carries each edge together with what it
-- produced, so the caller can report how many edges did real work and how many
-- reported themselves inapplicable without re-reading the manifest.
data BlueprintMigrationRunResult
  = BlueprintMigrationNoWork
  | BlueprintMigrationComplete [(BlueprintMigrationStep, MigrationOutcome)]
  | BlueprintMigrationLaunchFailed BlueprintMigrationStep BlueprintMigrationLaunchFailure
  | BlueprintMigrationRecordFailed BlueprintMigrationStep Text
  deriving stock (Eq, Show)

-- | Render the edge-specific instruction with the same resolved variables as
-- the blueprint's shared prompt.
renderBlueprintMigrationInstruction ::
  Map VarName ResolvedVar ->
  BlueprintMigration ->
  Text
renderBlueprintMigrationInstruction resolved migration =
  renderBlueprintText resolved (migration ^. #prompt)

-- | Fill the migration-specific embedded template. The template itself stays
-- in the executable target because @Data.FileEmbed@ traps it there; accepting
-- it as an argument keeps all rendering policy pure and unit-testable here.
-- The not-applicable signal path is passed in for the same reason: the caller
-- knows the project root, and this stays a function of its arguments.
--
-- @prepared@ must be the execution context of the step's /owning/ blueprint,
-- not of the blueprint named on the command line. Under entailment those
-- differ, and the agent is told the owner's identity and handed the owner's
-- reference files, because it is doing the owner's migration.
renderBlueprintMigrationSystemPrompt ::
  Text ->
  -- | absolute path the agent writes to when this edge does not apply
  FilePath ->
  AgentContext ->
  -- | the /owning/ blueprint's prepared execution
  PreparedBlueprintExecution ->
  Int ->
  Int ->
  BlueprintMigrationStep ->
  Text
renderBlueprintMigrationSystemPrompt template signalPath ctx prepared position total step =
  let blueprint = (prepared ^. #blueprint)
      migration = (step ^. #edge)
      renderedInstruction =
        renderBlueprintMigrationInstruction (prepared ^. #resolvedVariables) migration
   in substitute
        [ ("cwd", ctx ^. #cwd),
          ("seihou_project_state", formatSeihouProjectState ctx),
          ("manifest_state", formatManifestState ctx),
          ("module_dhall_state", formatModuleDhallState ctx),
          ("local_modules", formatLocalModules ctx),
          ("available_modules", formatAvailableModules ctx),
          ("blueprint_name", blueprint ^. #name . #unModuleName),
          ("blueprint_version", fromMaybe "(unspecified)" (blueprint ^. #version)),
          ("blueprint_description", fromMaybe "(no description)" (blueprint ^. #description)),
          ("migration_from", migration ^. #from),
          ("migration_to", migration ^. #to),
          ("migration_position", T.pack (show position)),
          ("migration_total", T.pack (show total)),
          ("migration_entailed_by", formatEntailedBy step),
          ("reference_files", prepared ^. #referenceFiles),
          ("reference_files_dir", prepared ^. #referenceFilesAccess),
          ("shared_prompt", prepared ^. #sharedPrompt),
          ("migration_prompt", renderedInstruction),
          ("not_applicable_signal_path", T.pack signalPath)
        ]
        template

-- | Clearly delimit every pending prompt for parent debug mode. This pure
-- function cannot launch a provider or receive a recorder, which makes the
-- migration debug path structurally read-only.
--
-- Each header names the step's owning blueprint, because a chain may span
-- several: a reader inspecting a cohort migration has no other way to tell
-- which blueprint's prompt they are looking at.
formatBlueprintMigrationDebugOutput ::
  (Int -> Int -> BlueprintMigrationStep -> Text) ->
  [BlueprintMigrationStep] ->
  Text
formatBlueprintMigrationDebugOutput render steps =
  T.intercalate
    "\n\n"
    [ T.unlines
        [ "===== ["
            <> T.pack (show position)
            <> "/"
            <> T.pack (show total)
            <> "] "
            <> formatMigrationStepLabel step
            <> " =====",
          render position total step
        ]
    | (position, step) <- zip [1 ..] steps
    ]
  where
    total = length steps

-- | Name one step the way every user-facing surface names it: the owning
-- blueprint, its edge window, and — when the step was reached through
-- entailment rather than named on the command line — what pulled it in.
--
-- One definition rather than three, because the launch announcement, the
-- debug headers, and the failure messages must agree; a chain that spans
-- blueprints is confusing enough without three spellings of the same step.
formatMigrationStepLabel :: BlueprintMigrationStep -> Text
formatMigrationStepLabel step =
  step ^. #owner
    <> " "
    <> step ^. #edge . #from
    <> " -> "
    <> step ^. #edge . #to
    <> maybe "" (\site -> " (entailed by " <> renderSite site <> ")") (step ^. #entailedBy)

-- | The sentence the framing prompt uses to explain to an agent why it is
-- migrating a library the user did not name. Empty for a directly selected
-- edge, which needs no explanation.
formatEntailedBy :: BlueprintMigrationStep -> Text
formatEntailedBy step = case step ^. #entailedBy of
  Nothing -> ""
  Just site ->
    "This edge was not requested directly. It is required by "
      <> renderSite site
      <> ", which the user is migrating."

renderSite :: EntailmentSite -> Text
renderSite site =
  site ^. #blueprint <> " " <> site ^. #from <> " -> " <> site ^. #to

-- | Remove applied exact-edge receipts while retaining planner order.
--
-- Exact-edge identity is the origin and name of the blueprint that owns the
-- edge together with its @from@ and @to@ versions. Artifact versions and
-- timestamps are intentionally not part of the completion key: an edge is the
-- same edge regardless of which release of the blueprint declared it. Origin
-- is part of it, because two blueprints published by different repositories
-- that share a name and an edge window are not the same edge, and dropping a
-- second repository's edge because the first one's is recorded would be a
-- silent skip of work that never ran.
--
-- The identity used for a step is the /owning/ blueprint's, resolved through
-- @lookupOwner@, not the identity of the blueprint the user invoked. Under
-- entailment a single plan contains steps owned by several blueprints, and
-- this is the mechanism that makes a shared cohort edge the same edge from
-- either entry point: a project that crossed kiroku's edge by running
-- @keiro-upgrade@ has a receipt under @kiroku-upgrade@'s identity, so running
-- @kiroku-upgrade@ directly finds that receipt and crosses nothing twice.
--
-- @lookupOwner@ returning 'Nothing' cannot happen in production: cohort
-- discovery resolves every owner before a plan reaches this function. It is
-- treated as "not previously applied" rather than as a crash, because the
-- honest failure for an unresolvable owner is the discovery error the caller
-- already raises, not a receipt lookup that silently claims completion.
--
-- The receipt's outcome is also part of the decision, though not of the
-- edge's identity. Only a 'MigrationApplied' receipt suppresses its edge. A
-- 'MigrationNotApplicable' one records that the edge was evaluated and found
-- inapplicable to this project, which says nothing about whether it applies
-- now — the precondition it reported unmet may since have been met, and that
-- is the ordinary case, because satisfying it is usually what the edge told
-- the user to do.
--
-- Receipts written before origins were recorded decode as
-- @'LocalOrigin' name@, which matches other such receipts and matches nothing
-- installed from a git URL. A project upgrading across that change therefore
-- sees its previously-recorded edges become pending once; that is honest,
-- because seihou cannot prove the recorded edge and the planned one came from
-- the same repository.
pendingBlueprintMigrations ::
  Bool ->
  -- | the recorded identity of a step's owning blueprint, by name
  (Text -> Maybe (ModuleName, ArtifactOrigin)) ->
  [AppliedBlueprintMigration] ->
  BlueprintMigrationPlan ->
  [BlueprintMigrationStep]
pendingBlueprintMigrations rerun lookupOwner receipts plan
  | rerun = plan ^. #steps
  | otherwise = filter (not . alreadyApplied) (plan ^. #steps)
  where
    alreadyApplied step = case lookupOwner (step ^. #owner) of
      Nothing -> False
      Just (ownerName, ownerOrigin) ->
        any
          ( \receipt ->
              receipt ^. #outcome == MigrationApplied
                && sameArtifactIdentity (receipt ^. #origin) ownerOrigin
                && receipt ^. #name == ownerName
                && receipt ^. #fromVersion == step ^. #edge . #from
                && receipt ^. #toVersion == step ^. #edge . #to
          )
          receipts

-- | Launch and record one pending edge at a time. A receipt is requested only
-- after its launch returns, and either callback failure stops the chain before
-- the next launch.
--
-- An edge that reports itself not applicable is not a failure and does not
-- stop the chain: its receipt is written with that outcome and the next edge
-- launches, exactly as after an applied one.
runBlueprintMigrationsWith ::
  (Int -> Int -> BlueprintMigrationStep -> IO (Either BlueprintMigrationLaunchFailure BlueprintMigrationLaunchResult)) ->
  (BlueprintMigrationStep -> MigrationOutcome -> IO (Either Text ())) ->
  [BlueprintMigrationStep] ->
  IO BlueprintMigrationRunResult
runBlueprintMigrationsWith _launch _record [] = pure BlueprintMigrationNoWork
runBlueprintMigrationsWith launch record steps =
  go [] (zip [1 ..] steps)
  where
    total = length steps

    go completed [] = pure (BlueprintMigrationComplete (reverse completed))
    go completed ((position, step) : rest) = do
      launchResult <- launch position total step
      case launchResult of
        Left failure -> pure (BlueprintMigrationLaunchFailed step failure)
        Right sessionResult -> do
          let outcome = case sessionResult of
                BlueprintMigrationSessionReturned -> MigrationApplied
                BlueprintMigrationSessionNotApplicable reason -> MigrationNotApplicable reason
          recordResult <- record step outcome
          case recordResult of
            Left err -> pure (BlueprintMigrationRecordFailed step err)
            Right () -> go ((step, outcome) : completed) rest

-- | Extract a not-applicable signal from an API provider's assistant text.
--
-- Recognises a line of the form @SEIHOU: not-applicable \<reason\>@ among the
-- last few non-empty lines, tolerating the surrounding whitespace, backticks
-- and emphasis a model is liable to add. The marker itself is matched
-- strictly: the line must begin with it, so prose that merely discusses
-- applicability is not a signal. A false positive here silently skips real
-- work, which is worse than missing a signal an agent could have written to
-- the signal file instead.
parseNotApplicableSignal :: Text -> Maybe Text
parseNotApplicableSignal assistantText =
  listToMaybe (mapMaybe signalOnLine candidateLines)
  where
    candidateLines =
      take signalScanDepth $
        reverse $
          filter (not . T.null) $
            map T.strip (T.lines assistantText)

    signalOnLine line = do
      afterMarker <- T.stripPrefix "SEIHOU:" (stripDecoration line)
      afterToken <- T.stripPrefix "not-applicable" (stripDecoration afterMarker)
      -- The token must end a word: 'not-applicable-ish' is not the marker.
      if maybe False continuesTheToken (fst <$> T.uncons afterToken)
        then Nothing
        else Just (readReason afterToken)

    continuesTheToken c = isAlphaNum c || c == '-'

    readReason =
      orPlaceholder
        . stripDecoration
        . T.dropWhile (\c -> isSpace c || c `elem` (":-–—" :: String))
        . stripDecoration

    orPlaceholder reason
      | T.null reason = unstatedNotApplicableReason
      | otherwise = reason

    stripDecoration = T.dropAround (\c -> isSpace c || c `elem` ("*_`" :: String))

-- | How many trailing non-empty lines of an assistant reply to search for the
-- marker. A model that signals usually does so last, but often follows with a
-- closing sentence or two.
signalScanDepth :: Int
signalScanDepth = 5

-- | What to record when an edge signals inapplicability without saying why.
-- The signal is a deliberate act either way, so it is honoured; the reason is
-- what suffers.
unstatedNotApplicableReason :: Text
unstatedNotApplicableReason = "(no reason given)"
