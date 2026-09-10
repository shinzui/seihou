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
    formatMarkAppliedNotice,
    formatMarkAppliedSummary,
    pendingBlueprintMigrations,
    parseNotApplicableSignal,
    unstatedNotApplicableReason,
    runBlueprintMigrationsWith,

    -- * Inferring the version window
    VersionSource (..),
    ResolvedWindow (..),
    WindowResolutionError (..),
    VersionProbeResult (..),
    highestMigratedVersion,
    resolveMigrationWindow,
    readVersionProbeOutput,
    runVersionProbe,
    formatResolvedWindow,
    formatProbeFailure,
    formatWindowResolutionError,
  )
where

import Data.Char (isAlphaNum, isSpace)
import Data.Generics.Labels ()
import Data.List (sortOn)
import Data.Maybe (fromMaybe, listToMaybe, mapMaybe)
import Data.Ord (Down (..))
import Data.Text qualified as T
import Data.Time.Format (defaultTimeLocale, formatTime)
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
import Seihou.Core.Version (Version, parseVersion, renderVersion)
import Seihou.Effect.Process (Process, runProcess)
import Seihou.Prelude
import System.Exit (ExitCode (..))

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

-- | Announce the steps a @--mark-applied@ run is about to record.
--
-- Every step is named with 'formatMigrationStepLabel', the one function every
-- user-facing step label goes through, so a marked chain reads the same as a
-- run one and an entailed step still says what pulled it in.
--
-- \"without running them\" is in the first line rather than only in the
-- summary because this is the sentence a user sees before the receipts are
-- written. Marking asserts something rather than observing it, and someone
-- who reached for the flag by mistake needs the mistake visible here.
formatMarkAppliedNotice :: [BlueprintMigrationStep] -> Text
formatMarkAppliedNotice steps =
  T.unlines $
    "Marking "
      <> T.pack (show (length steps))
      <> " blueprint migration(s) as already applied, without running them:"
      : ["  " <> formatMigrationStepLabel step | step <- steps]

-- | Confirm what a @--mark-applied@ run recorded, once the receipts are in.
--
-- The second sentence is doing real work. A receipt written this way is an
-- ordinary applied receipt, indistinguishable from one an agent earned, so a
-- user who marked a migration they have not actually performed has to notice
-- immediately — and @--rerun@ is the remedy.
formatMarkAppliedSummary :: Int -> Text
formatMarkAppliedSummary recorded =
  "Recorded "
    <> T.pack (show recorded)
    <> " receipt(s). No agent session was started and no file was changed."

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

-- ---------------------------------------------------------------------------
-- Inferring the version window
-- ---------------------------------------------------------------------------

-- | Where one end of the migration version window came from. Carried so the
-- command can tell the user what it inferred and why, which matters more here
-- than usual: an inferred window silently off by one release would run the
-- wrong edges against their source.
data VersionSource
  = VersionFromFlag
  | -- | The blueprint's declared probe command, which printed this version.
    VersionFromProbe !Text
  | -- | The receipt this end was read from. The whole record is carried
    -- rather than only its edge window, because the reported line names the
    -- blueprint and the date the edge was applied, and a user checking an
    -- inferred start needs to recognise the run it came from.
    VersionFromReceipt !AppliedBlueprintMigration
  deriving stock (Eq, Show, Generic)

-- | Both ends of the window, each with the reason it holds that value.
data ResolvedWindow = ResolvedWindow
  { fromVersion :: !Version,
    fromSource :: !VersionSource,
    toVersion :: !Version,
    toSource :: !VersionSource
  }
  deriving stock (Eq, Show, Generic)

-- | Why a window could not be resolved. Both cases are recoverable by passing
-- the flag the message names, so neither is reported as a defect.
data WindowResolutionError
  = -- | No @--to@ was given, and no probe supplied one.
    NoTargetVersion
  | -- | No @--from@ was given, and this project has no applied receipt for
    -- this blueprint to start from.
    NoStartVersion
  deriving stock (Eq, Show, Generic)

-- | What running a blueprint's declared version probe produced.
--
-- Only 'ProbeVersion' contributes to the window. The other two are reported to
-- the user and then treated as "no probe result": a probe is the blueprint
-- author's convenience, and a broken one must degrade to requiring @--to@
-- rather than failing a command the user can still complete by hand.
data VersionProbeResult
  = ProbeVersion !Version
  | -- | Exit code and captured stderr.
    ProbeExitedNonZero !Int !Text
  | -- | The probe succeeded but printed something that is not a dotted
    -- numeric version. Carries the raw stdout.
    ProbeOutputUnparseable !Text
  deriving stock (Eq, Show, Generic)

-- | The highest version this project has already migrated this blueprint to,
-- with the receipt that says so.
--
-- Only receipts belonging to this blueprint identity are considered — name and
-- origin both, per docs\/adr\/0002-artifact-identity-is-origin-url-plus-name.md
-- and compared with 'sameArtifactIdentity' rather than structural equality,
-- because a same-named blueprint from another repository records a different
-- project history and two spellings of one git URL record the same one.
--
-- The identity to pass is that of the blueprint whose /own/ edges are being
-- windowed. For @seihou agent migrate@ that is the invoked blueprint, because
-- the window is expressed in the invoked library's version space; an entailed
-- blueprint's steps are windowed by the edge that entails them, not by a
-- window of their own.
--
-- Two exclusions are deliberate:
--
--   * A receipt whose @toVersion@ does not parse is skipped rather than
--     failing the command. Receipts are data written by earlier runs, and one
--     malformed entry must not make the command unusable.
--
--   * A 'MigrationNotApplicable' receipt does not count. It records that
--     seihou considered an edge and this project did not need it, which says
--     nothing about how far the source has been carried. Counting it would
--     start the window above edges that were never applied and skip them
--     permanently.
highestMigratedVersion ::
  ArtifactOrigin ->
  ModuleName ->
  [AppliedBlueprintMigration] ->
  Maybe (Version, AppliedBlueprintMigration)
highestMigratedVersion origin name receipts =
  listToMaybe (sortOn (Down . fst) (mapMaybe reached receipts))
  where
    reached receipt
      | receipt ^. #outcome /= MigrationApplied = Nothing
      | not (sameArtifactIdentity (receipt ^. #origin) origin) = Nothing
      | receipt ^. #name /= name = Nothing
      | otherwise = (,receipt) <$> parseVersion (receipt ^. #toVersion)

-- | Decide each end of the window from what the user supplied and what seihou
-- could infer.
--
-- Precedence is per end and independent: an explicit flag always wins, and
-- either end may be inferred while the other is typed.
--
-- The two ends deliberately draw on different sources. @--to@ takes the probe,
-- which reads how far the /dependency/ has been bumped in this project;
-- @--from@ takes the receipt ledger, which records how far the /source/ has
-- been migrated. Swapping them would break the workflow this exists for: the
-- normal sequence is to bump the dependency and then migrate the source up to
-- it, so at the moment the command runs the lockfile already names the target.
--
-- Running the probe is the caller's job, and its result arrives here already
-- parsed. That keeps this pure, and lets the caller skip the subprocess
-- entirely when @--to@ was given.
resolveMigrationWindow ::
  -- | @--from@, already parsed
  Maybe Version ->
  -- | @--to@, already parsed
  Maybe Version ->
  -- | the probe's version and the command that produced it
  Maybe (Version, Text) ->
  -- | the highest applied receipt, from 'highestMigratedVersion'
  Maybe (Version, AppliedBlueprintMigration) ->
  Either WindowResolutionError ResolvedWindow
resolveMigrationWindow fromFlag toFlag probed recorded = do
  (target, targetSource) <- case (toFlag, probed) of
    (Just version, _) -> Right (version, VersionFromFlag)
    (Nothing, Just (version, command)) -> Right (version, VersionFromProbe command)
    (Nothing, Nothing) -> Left NoTargetVersion
  (start, startSource) <- case (fromFlag, recorded) of
    (Just version, _) -> Right (version, VersionFromFlag)
    (Nothing, Just (version, receipt)) -> Right (version, VersionFromReceipt receipt)
    (Nothing, Nothing) -> Left NoStartVersion
  pure
    ResolvedWindow
      { fromVersion = start,
        fromSource = startSource,
        toVersion = target,
        toSource = targetSource
      }

-- | Read a probe's captured stdout as a version.
--
-- The rule is the /last non-empty line/, trimmed, rather than the whole of
-- stdout: a probe like @nix eval@ prints progress before its answer, and
-- requiring authors to silence every tool's chatter would make probes
-- fragile. Authors need to know this rule, so it is documented in
-- docs\/user\/blueprints.md as well as here.
readVersionProbeOutput :: Text -> VersionProbeResult
readVersionProbeOutput raw =
  case lastNonEmptyLine of
    Just line | Just version <- parseVersion line -> ProbeVersion version
    _ -> ProbeOutputUnparseable raw
  where
    lastNonEmptyLine =
      listToMaybe (reverse (filter (not . T.null) (map T.strip (T.lines raw))))

-- | Run a blueprint's declared version probe in the project directory.
--
-- Executed through @sh -c@, exactly as a module's @RunCommand@ operation and a
-- command-derived variable are, so an author writes the same kind of shell
-- string everywhere. This function has no timeout of its own; the caller
-- bounds it, because a bound belongs where the real clock is.
runVersionProbe ::
  (Process :> es) =>
  -- | the declared command
  Text ->
  -- | the project directory to run it in
  FilePath ->
  Eff es VersionProbeResult
runVersionProbe command projectRoot = do
  (exitCode, stdoutText, stderrText) <- runProcess "sh" ["-c", command] (Just projectRoot)
  pure $ case exitCode of
    ExitSuccess -> readVersionProbeOutput stdoutText
    ExitFailure code -> ProbeExitedNonZero code stderrText

-- | Report the resolved window and where each end came from.
--
-- Returns no lines at all when the user typed both flags and did not ask for
-- verbose output: they already know what they typed, and existing invocations
-- should keep printing exactly what they printed before. An /inferred/ end is
-- always reported, verbose or not — a window silently off by one release runs
-- the wrong agent sessions against the user's source, which is worth two lines.
formatResolvedWindow :: Bool -> ResolvedWindow -> [Text]
formatResolvedWindow verbose window
  | null provenance = []
  | otherwise = header : provenance
  where
    header =
      "Version window: "
        <> renderVersion (window ^. #fromVersion)
        <> " -> "
        <> renderVersion (window ^. #toVersion)

    provenance =
      end "--from" (window ^. #fromVersion) (window ^. #fromSource)
        <> end "--to  " (window ^. #toVersion) (window ^. #toSource)

    end flag version source =
      [ "  " <> flag <> " " <> renderVersion version <> "  " <> renderSource source
      | verbose || source /= VersionFromFlag
      ]

    renderSource = \case
      VersionFromFlag -> "[flag]"
      VersionFromProbe command -> "[probe: " <> command <> "]"
      VersionFromReceipt receipt ->
        "[receipt: "
          <> receipt ^. #name . #unModuleName
          <> " "
          <> receipt ^. #fromVersion
          <> " -> "
          <> receipt ^. #toVersion
          <> ", applied "
          <> T.pack (formatTime defaultTimeLocale "%Y-%m-%d" (receipt ^. #appliedAt))
          <> "]"

-- | Explain a probe that did not produce a version.
--
-- The blueprint's author wrote the command and the consumer is the one holding
-- the failure, so the message shows enough to forward upstream — and says
-- plainly that the run can continue with an explicit flag.
formatProbeFailure :: Text -> VersionProbeResult -> Maybe Text
formatProbeFailure command = \case
  ProbeVersion _ -> Nothing
  ProbeExitedNonZero code stderrText ->
    Just $
      "The blueprint's version probe failed, so --to could not be inferred.\n"
        <> "  probe:  "
        <> command
        <> "\n  exit:   "
        <> T.pack (show code)
        <> diagnostic "stderr" stderrText
  ProbeOutputUnparseable raw ->
    Just $
      "The blueprint's version probe printed no dotted numeric version, so --to could not be inferred.\n"
        <> "  probe:  "
        <> command
        <> diagnostic "output" raw
  where
    -- Both labels are six characters, so one space after the colon lines
    -- their values up under `probe:` and `exit:` above them.
    diagnostic label text
      | T.null trimmed = ""
      | otherwise = "\n  " <> label <> ": " <> T.replace "\n" "\n          " trimmed
      where
        trimmed = T.strip text

-- | Turn an unresolvable window into the sentence the user has to act on.
--
-- The missing-start case is the first-run case and will be much the commoner
-- of the two, so it explains rather than complains: seihou has no record of
-- this project's migration history, which is a fact about the project and not
-- a mistake by the person typing.
formatWindowResolutionError :: ModuleName -> WindowResolutionError -> Text
formatWindowResolutionError blueprintName = \case
  NoTargetVersion ->
    "Cannot determine the target version for '"
      <> name
      <> "'.\n\n"
      <> "  Pass --to VERSION, or ask the blueprint's author to declare a versionProbe\n"
      <> "  so seihou can read the version this project depends on."
  NoStartVersion ->
    "Cannot determine the starting version for '"
      <> name
      <> "'.\n\n"
      <> "  This project has no recorded migration for that blueprint, so seihou does\n"
      <> "  not know how far its source has already been migrated.\n\n"
      <> "  Pass --from VERSION."
  where
    name = blueprintName ^. #unModuleName
