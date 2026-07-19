module Seihou.CLI.CommandExecution
  ( CommandPolicy (..),
    CommandDisposition (..),
    PlannedCommand (..),
    CommandPlan (..),
    CommandPlanSummary (..),
    CommandExecutionError (..),
    planCommands,
    summarizeCommandPlan,
    executeCommandPlan,
    executeCommandPlanWithOutput,
    finalizeCommandReceipts,
  )
where

import Data.Map.Strict qualified as Map
import Data.Maybe (mapMaybe)
import Data.Time (UTCTime)
import Seihou.Core.CommandFingerprint (fingerprintCommand)
import Seihou.Core.Types
import Seihou.Effect.Process (Process, runProcess)
import Seihou.Prelude
import System.Exit (ExitCode (..))

-- | Whether a command phase runs every declaration, only declarations that
-- lack a successful receipt, or no declarations.
data CommandPolicy
  = RunAllCommands
  | RunChangedCommands
  | DisableCommands
  deriving stock (Eq, Show)

-- | The action selected for one rendered command.
data CommandDisposition
  = CommandWillRun
  | CommandSkippedUnchanged
  | CommandSkippedDisabled
  deriving stock (Eq, Show)

-- | A rendered command paired with its stable identity and selected action.
data PlannedCommand = PlannedCommand
  { operation :: Operation,
    fingerprint :: CommandFingerprint,
    disposition :: CommandDisposition
  }
  deriving stock (Eq, Show)

-- | An ordered command phase. Declaration/composition order is also execution
-- order.
newtype CommandPlan = CommandPlan
  { commands :: [PlannedCommand]
  }
  deriving stock (Eq, Show)

-- | Counts suitable for human or machine-readable previews.
data CommandPlanSummary = CommandPlanSummary
  { willRun :: Int,
    skippedUnchanged :: Int,
    skippedDisabled :: Int
  }
  deriving stock (Eq, Show)

-- | A failed shell command and its captured process result.
data CommandExecutionError = CommandExecutionError
  { command :: PlannedCommand,
    exitCode :: Int,
    stdout :: Text,
    stderr :: Text
  }
  deriving stock (Eq, Show)

-- | Select command dispositions according to policy and prior successful
-- receipts. Non-command operations are ignored.
planCommands ::
  CommandPolicy ->
  Map CommandFingerprint CommandReceipt ->
  [Operation] ->
  CommandPlan
planCommands policy priorReceipts =
  CommandPlan . mapMaybe planOne
  where
    planOne operation = do
      fingerprint <- fingerprintCommand operation
      let disposition = case policy of
            RunAllCommands -> CommandWillRun
            RunChangedCommands
              | Map.member fingerprint priorReceipts -> CommandSkippedUnchanged
              | otherwise -> CommandWillRun
            DisableCommands -> CommandSkippedDisabled
      pure PlannedCommand {operation, fingerprint, disposition}

-- | Count each command disposition without changing command order.
summarizeCommandPlan :: CommandPlan -> CommandPlanSummary
summarizeCommandPlan commandPlan =
  foldl' count emptySummary commandPlan.commands
  where
    emptySummary = CommandPlanSummary {willRun = 0, skippedUnchanged = 0, skippedDisabled = 0}
    count summary planned = case planned.disposition of
      CommandWillRun -> summary {willRun = summary.willRun + 1}
      CommandSkippedUnchanged -> summary {skippedUnchanged = summary.skippedUnchanged + 1}
      CommandSkippedDisabled -> summary {skippedDisabled = summary.skippedDisabled + 1}

-- | Execute runnable commands sequentially with @sh -c@. Stop at the first
-- failure. The caller receives receipts only if the entire phase succeeds.
executeCommandPlan ::
  (Process :> es) =>
  UTCTime ->
  CommandPlan ->
  Eff es (Either CommandExecutionError [CommandReceipt])
executeCommandPlan completedAt commandPlan = go [] commandPlan.commands
  where
    go = executeCommands completedAt (\_ _ _ -> pure ())

-- | Execute a command plan while exposing successful captured output to an
-- effectful callback. The executable uses this to preserve its historical
-- stdout behavior; library callers that only need receipts use
-- 'executeCommandPlan'.
executeCommandPlanWithOutput ::
  (Process :> es) =>
  UTCTime ->
  (PlannedCommand -> Text -> Text -> Eff es ()) ->
  CommandPlan ->
  Eff es (Either CommandExecutionError [CommandReceipt])
executeCommandPlanWithOutput completedAt onSuccess commandPlan =
  executeCommands completedAt onSuccess [] commandPlan.commands

executeCommands ::
  (Process :> es) =>
  UTCTime ->
  (PlannedCommand -> Text -> Text -> Eff es ()) ->
  [CommandReceipt] ->
  [PlannedCommand] ->
  Eff es (Either CommandExecutionError [CommandReceipt])
executeCommands completedAt onSuccess = go
  where
    go completed [] = pure (Right (reverse completed))
    go completed (planned : remaining) = case planned.disposition of
      CommandSkippedUnchanged -> go completed remaining
      CommandSkippedDisabled -> go completed remaining
      CommandWillRun -> case planned.operation of
        RunCommandOp {command, workDir, moduleName} -> do
          (processExit, stdout, stderr) <- runProcess "sh" ["-c", command] workDir
          case processExit of
            ExitSuccess -> do
              onSuccess planned stdout stderr
              let receipt =
                    CommandReceipt
                      { fingerprint = planned.fingerprint,
                        moduleName,
                        command,
                        workDir,
                        completedAt
                      }
              go (receipt : completed) remaining
            ExitFailure exitCode ->
              pure
                ( Left
                    CommandExecutionError
                      { command = planned,
                        exitCode,
                        stdout,
                        stderr
                      }
                )
        _ -> go completed remaining

-- | Produce the accepted receipt map for the plan's current declaration set.
-- Removed commands are dropped. Fresh successes replace old receipts;
-- unchanged or explicitly disabled declarations retain a matching old receipt.
finalizeCommandReceipts ::
  CommandPlan ->
  [CommandReceipt] ->
  Map CommandFingerprint CommandReceipt ->
  Map CommandFingerprint CommandReceipt
finalizeCommandReceipts commandPlan completed priorReceipts =
  Map.fromList (mapMaybe receiptFor commandPlan.commands)
  where
    completedByFingerprint = Map.fromList [(receipt.fingerprint, receipt) | receipt <- completed]

    receiptFor planned =
      case Map.lookup planned.fingerprint completedByFingerprint of
        Just receipt -> Just (planned.fingerprint, receipt)
        Nothing -> case planned.disposition of
          CommandWillRun -> Nothing
          CommandSkippedUnchanged -> retainPrior planned
          CommandSkippedDisabled -> retainPrior planned

    retainPrior planned =
      (planned.fingerprint,) <$> Map.lookup planned.fingerprint priorReceipts
