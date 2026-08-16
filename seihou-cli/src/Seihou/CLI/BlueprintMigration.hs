-- | Pure selection/rendering and callback-driven execution for ordered
-- agent-guided blueprint migrations.
module Seihou.CLI.BlueprintMigration
  ( BlueprintMigrationLaunchFailure (..),
    BlueprintMigrationLaunchResult (..),
    BlueprintMigrationRunResult (..),
    renderBlueprintMigrationInstruction,
    renderBlueprintMigrationSystemPrompt,
    formatBlueprintMigrationDebugOutput,
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
  | BlueprintMigrationComplete [(BlueprintMigration, MigrationOutcome)]
  | BlueprintMigrationLaunchFailed BlueprintMigration BlueprintMigrationLaunchFailure
  | BlueprintMigrationRecordFailed BlueprintMigration Text
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
renderBlueprintMigrationSystemPrompt ::
  Text ->
  -- | absolute path the agent writes to when this edge does not apply
  FilePath ->
  AgentContext ->
  PreparedBlueprintExecution ->
  Int ->
  Int ->
  BlueprintMigration ->
  Text
renderBlueprintMigrationSystemPrompt template signalPath ctx prepared position total migration =
  let blueprint = (prepared ^. #blueprint)
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
formatBlueprintMigrationDebugOutput ::
  (Int -> Int -> BlueprintMigration -> Text) ->
  [BlueprintMigration] ->
  Text
formatBlueprintMigrationDebugOutput render migrations =
  T.intercalate
    "\n\n"
    [ T.unlines
        [ "===== ["
            <> T.pack (show position)
            <> "/"
            <> T.pack (show total)
            <> "] "
            <> migration ^. #from
            <> " -> "
            <> migration ^. #to
            <> " =====",
          render position total migration
        ]
    | (position, migration) <- zip [1 ..] migrations
    ]
  where
    total = length migrations

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
  ArtifactOrigin ->
  ModuleName ->
  [AppliedBlueprintMigration] ->
  BlueprintMigrationPlan ->
  [BlueprintMigration]
pendingBlueprintMigrations rerun blueprintOrigin blueprintName receipts plan
  | rerun = plan ^. #steps
  | otherwise = filter (not . alreadyApplied) (plan ^. #steps)
  where
    alreadyApplied migration =
      any
        ( \receipt ->
            receipt ^. #outcome == MigrationApplied
              && sameArtifactIdentity (receipt ^. #origin) blueprintOrigin
              && receipt ^. #name == blueprintName
              && receipt ^. #fromVersion == migration ^. #from
              && receipt ^. #toVersion == migration ^. #to
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
  (Int -> Int -> BlueprintMigration -> IO (Either BlueprintMigrationLaunchFailure BlueprintMigrationLaunchResult)) ->
  (BlueprintMigration -> MigrationOutcome -> IO (Either Text ())) ->
  [BlueprintMigration] ->
  IO BlueprintMigrationRunResult
runBlueprintMigrationsWith _launch _record [] = pure BlueprintMigrationNoWork
runBlueprintMigrationsWith launch record migrations =
  go [] (zip [1 ..] migrations)
  where
    total = length migrations

    go completed [] = pure (BlueprintMigrationComplete (reverse completed))
    go completed ((position, migration) : rest) = do
      launchResult <- launch position total migration
      case launchResult of
        Left failure -> pure (BlueprintMigrationLaunchFailed migration failure)
        Right sessionResult -> do
          let outcome = case sessionResult of
                BlueprintMigrationSessionReturned -> MigrationApplied
                BlueprintMigrationSessionNotApplicable reason -> MigrationNotApplicable reason
          recordResult <- record migration outcome
          case recordResult of
            Left err -> pure (BlueprintMigrationRecordFailed migration err)
            Right () -> go ((migration, outcome) : completed) rest

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
