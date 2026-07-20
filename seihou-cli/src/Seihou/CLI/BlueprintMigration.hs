-- | Pure selection/rendering and callback-driven execution for ordered
-- agent-guided blueprint migrations.
module Seihou.CLI.BlueprintMigration
  ( BlueprintMigrationLaunchFailure (..),
    BlueprintMigrationRunResult (..),
    renderBlueprintMigrationInstruction,
    pendingBlueprintMigrations,
    runBlueprintMigrationsWith,
  )
where

import Seihou.CLI.BlueprintExecution (renderBlueprintText)
import Seihou.Core.Migration
  ( BlueprintMigration (..),
    BlueprintMigrationPlan (..),
  )
import Seihou.Core.Types
  ( AppliedBlueprintMigration (..),
    ModuleName,
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
