-- | Pure selection/rendering and callback-driven execution for ordered
-- agent-guided blueprint migrations.
module Seihou.CLI.BlueprintMigration
  ( BlueprintMigrationLaunchFailure (..),
    BlueprintMigrationRunResult (..),
    renderBlueprintMigrationInstruction,
    renderBlueprintMigrationSystemPrompt,
    formatBlueprintMigrationDebugOutput,
    pendingBlueprintMigrations,
    runBlueprintMigrationsWith,
  )
where

import Data.Maybe (fromMaybe)
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
import Seihou.Core.Migration
  ( BlueprintMigration (..),
    BlueprintMigrationPlan (..),
  )
import Seihou.Core.Types
  ( AppliedBlueprintMigration (..),
    Blueprint (..),
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

-- | Terminal outcome for one pending migration chain.
data BlueprintMigrationRunResult
  = BlueprintMigrationNoWork
  | BlueprintMigrationComplete [BlueprintMigration]
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
  renderBlueprintText resolved migration.prompt

-- | Fill the migration-specific embedded template. The template itself stays
-- in the executable target because @Data.FileEmbed@ traps it there; accepting
-- it as an argument keeps all rendering policy pure and unit-testable here.
renderBlueprintMigrationSystemPrompt ::
  Text ->
  AgentContext ->
  PreparedBlueprintExecution ->
  Int ->
  Int ->
  BlueprintMigration ->
  Text
renderBlueprintMigrationSystemPrompt template ctx prepared position total migration =
  let blueprint = prepared.preparedBlueprint
      renderedInstruction =
        renderBlueprintMigrationInstruction prepared.preparedResolvedVariables migration
   in substitute
        [ ("cwd", ctx.cwd),
          ("seihou_project_state", formatSeihouProjectState ctx),
          ("manifest_state", formatManifestState ctx),
          ("module_dhall_state", formatModuleDhallState ctx),
          ("local_modules", formatLocalModules ctx),
          ("available_modules", formatAvailableModules ctx),
          ("blueprint_name", blueprint.name.unModuleName),
          ("blueprint_version", fromMaybe "(unspecified)" blueprint.version),
          ("blueprint_description", fromMaybe "(no description)" blueprint.description),
          ("migration_from", migration.from),
          ("migration_to", migration.to),
          ("migration_position", T.pack (show position)),
          ("migration_total", T.pack (show total)),
          ("reference_files", prepared.preparedReferenceFiles),
          ("reference_files_dir", prepared.preparedReferenceFilesAccess),
          ("shared_prompt", prepared.preparedSharedPrompt),
          ("migration_prompt", renderedInstruction)
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
            <> migration.from
            <> " -> "
            <> migration.to
            <> " =====",
          render position total migration
        ]
    | (position, migration) <- zip [1 ..] migrations
    ]
  where
    total = length migrations

-- | Remove exact-edge receipts while retaining planner order. Artifact
-- versions and timestamps are intentionally not part of the completion key.
pendingBlueprintMigrations ::
  Bool ->
  ModuleName ->
  [AppliedBlueprintMigration] ->
  BlueprintMigrationPlan ->
  [BlueprintMigration]
pendingBlueprintMigrations rerun blueprintName receipts plan
  | rerun = plan.blueprintPlanSteps
  | otherwise = filter (not . alreadyApplied) plan.blueprintPlanSteps
  where
    alreadyApplied migration =
      any
        ( \receipt ->
            receipt.name == blueprintName
              && receipt.fromVersion == migration.from
              && receipt.toVersion == migration.to
        )
        receipts

-- | Launch and record one pending edge at a time. A receipt is requested only
-- after its launch succeeds, and either callback failure stops the chain before
-- the next launch.
runBlueprintMigrationsWith ::
  (Int -> Int -> BlueprintMigration -> IO (Either BlueprintMigrationLaunchFailure ())) ->
  (BlueprintMigration -> IO (Either Text ())) ->
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
        Right () -> do
          recordResult <- record migration
          case recordResult of
            Left err -> pure (BlueprintMigrationRecordFailed migration err)
            Right () -> go (migration : completed) rest
