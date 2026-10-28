module Seihou.CLI.CommandExecution
  ( CommandPolicy (..),
    CommandDisposition (..),
    PlannedCommand (..),
    CommandPlan (..),
    CommandPlanSummary (..),
    CommandExecutionError (..),
    planCommands,
    planCheckoutCommands,
    summarizeCommandPlan,
    executeCommandPlan,
    executeCommandPlanWithOutput,
    expectedCommandReceipts,
    withReceiptWithdrawal,
    finalizeCommandReceipts,
    CommandOutcome (..),
    CommandOutcomeStatus (..),
    executeCommandOutcomes,
    commandOutcomesFailed,
    checkCheckoutWorkDir,
  )
where

import Control.Exception (IOException, SomeException, displayException, onException, try)
import Control.Monad (forM, forM_, void, when)
import Data.Generics.Labels ()
import Data.List (find)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Text qualified as T
import Data.Time (UTCTime)
import Effectful.Exception qualified as E
import Seihou.Core.CommandFingerprint (checkoutCommandOperation, fingerprintCommand, isCheckoutCommand)
import Seihou.Core.Path (validateCanonicalProjectPath)
import Seihou.Core.Types
import Seihou.Effect.Process (Process, runProcess)
import Seihou.Prelude
import System.Directory qualified as Directory
import System.Exit (ExitCode (..))
import System.FilePath qualified as Path

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
  { operation :: !Operation,
    fingerprint :: !CommandFingerprint,
    disposition :: !CommandDisposition
  }
  deriving stock (Eq, Generic, Show)

-- | An ordered command phase. Declaration/composition order is also execution
-- order.
newtype CommandPlan = CommandPlan
  { commands :: [PlannedCommand]
  }
  deriving stock (Eq, Generic, Show)

-- | Counts suitable for human or machine-readable previews.
data CommandPlanSummary = CommandPlanSummary
  { willRun :: !Int,
    skippedUnchanged :: !Int,
    skippedDisabled :: !Int
  }
  deriving stock (Eq, Generic, Show)

-- | A failed shell command and its captured process result.
data CommandExecutionError = CommandExecutionError
  { command :: !PlannedCommand,
    exitCode :: !Int,
    stdout :: !Text,
    stderr :: !Text
  }
  deriving stock (Eq, Generic, Show)

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
              | not (isCheckoutCommand operation), Map.member fingerprint priorReceipts -> CommandSkippedUnchanged
              | otherwise -> CommandWillRun
            DisableCommands -> CommandSkippedDisabled
      pure PlannedCommand {operation, fingerprint, disposition}

-- | Resolved checkout instructions always run on explicit sync. This boundary
-- accepts neither a receipt map nor an application command policy. Conversion
-- produces only RunCommandOp, for which fingerprintCommand always returns Just.
planCheckoutCommands :: [CheckoutCommand] -> CommandPlan
planCheckoutCommands declarations = CommandPlan (mapMaybe planned declarations)
  where
    planned declaration = do
      let operation = checkoutCommandOperation declaration
      fingerprint <- fingerprintCommand operation
      pure (PlannedCommand operation fingerprint CommandWillRun)

-- | Count each command disposition without changing command order.
summarizeCommandPlan :: CommandPlan -> CommandPlanSummary
summarizeCommandPlan commandPlan =
  foldl' count emptySummary (commandPlan ^. #commands)
  where
    emptySummary = CommandPlanSummary {willRun = 0, skippedUnchanged = 0, skippedDisabled = 0}
    count summary planned = case planned ^. #disposition of
      CommandWillRun -> (summary & #willRun %~ (+ 1))
      CommandSkippedUnchanged -> (summary & #skippedUnchanged %~ (+ 1))
      CommandSkippedDisabled -> summary & #skippedDisabled %~ (+ 1)

-- | Execute runnable commands sequentially with @sh -c@. Stop at the first
-- failure. The caller receives receipts only if the entire phase succeeds.
executeCommandPlan ::
  (Process :> es, IOE :> es) =>
  UTCTime ->
  CommandPlan ->
  Eff es (Either CommandExecutionError [CommandReceipt])
executeCommandPlan completedAt commandPlan = go [] (commandPlan ^. #commands)
  where
    go = executeCommands completedAt (\_ _ _ -> pure ())

-- | Execute a command plan while exposing successful captured output to an
-- effectful callback. The executable uses this to preserve its historical
-- stdout behavior; library callers that only need receipts use
-- 'executeCommandPlan'.
executeCommandPlanWithOutput ::
  (Process :> es, IOE :> es) =>
  UTCTime ->
  (PlannedCommand -> Text -> Text -> Eff es ()) ->
  CommandPlan ->
  Eff es (Either CommandExecutionError [CommandReceipt])
executeCommandPlanWithOutput completedAt onSuccess commandPlan =
  executeCommands completedAt onSuccess [] (commandPlan ^. #commands)

-- | Transient outcomes are never persisted as checkout completion history.
data CommandOutcomeStatus = CommandSucceeded | CommandFailed | CommandSkipped | CommandNotRun
  deriving stock (Eq, Show, Generic)

data CommandOutcome = CommandOutcome
  { command :: !PlannedCommand,
    status :: !CommandOutcomeStatus,
    exitCode :: !(Maybe Int),
    stdout :: !Text,
    stderr :: !Text
  }
  deriving stock (Eq, Show, Generic)

commandOutcomesFailed :: [CommandOutcome] -> Bool
commandOutcomesFailed = any ((== CommandFailed) . (^. #status))

-- | Check every component without following symlinks. Repeated immediately
-- before checkout invocations because a preceding shell may change the path.
checkCheckoutWorkDir :: FilePath -> Maybe FilePath -> IO (Either Text ())
checkCheckoutWorkDir root workDir = do
  let path = fromMaybe "." workDir
  case if path == "." then Right () else validateCanonicalProjectPath (T.pack path) of
    Left reason -> pure (Left reason)
    Right () -> do
      result <- try @IOException $ do
        let parts = if path == "." then [] else Path.splitDirectories path
            paths = scanl (Path.</>) root parts
        safe <-
          and
            <$> forM
              paths
              ( \part -> do
                  link <- Directory.pathIsSymbolicLink part
                  directory <- Directory.doesDirectoryExist part
                  pure (not link && directory)
              )
        pure $ if safe then Right () else Left ("checkout command workDir must be an existing real directory with real ancestors: " <> T.pack path)
      pure $ either (Left . T.pack . displayException) id result

-- | One shared shell executor. Capture the completed prefix and unrun tail,
-- including launch errors; callers choose receipt publication separately.
executeCommandOutcomes :: (Process :> es, IOE :> es) => CommandPlan -> Eff es [CommandOutcome]
executeCommandOutcomes commandPlan = go False (commandPlan ^. #commands)
  where
    go _ [] = pure []
    go failed (planned : remaining)
      | failed = (emptyOutcome planned CommandNotRun :) <$> go True remaining
      | planned ^. #disposition /= CommandWillRun = (emptyOutcome planned CommandSkipped :) <$> go False remaining
      | otherwise = case planned ^. #operation of
          operation@RunCommandOp {command, workDir} -> do
            ready <-
              if isCheckoutCommand operation
                then liftIO (Directory.getCurrentDirectory >>= (\root -> checkCheckoutWorkDir root workDir))
                else pure (Right ())
            outcome <- case ready of
              Left reason -> pure ((emptyOutcome planned CommandFailed) & #stderr .~ reason)
              Right () -> do
                launched <- E.try @IOException (runProcess "sh" ["-c", command] workDir)
                pure $ case launched of
                  Left err -> (emptyOutcome planned CommandFailed) & #stderr .~ T.pack (displayException err)
                  Right (processExit, stdout, stderr) -> CommandOutcome planned (if processExit == ExitSuccess then CommandSucceeded else CommandFailed) (Just (case processExit of ExitSuccess -> 0; ExitFailure code -> code)) stdout stderr
            (outcome :) <$> go (outcome ^. #status == CommandFailed) remaining
          _ -> (emptyOutcome planned CommandSkipped :) <$> go False remaining
    emptyOutcome command status = CommandOutcome command status Nothing "" ""

executeCommands ::
  (Process :> es, IOE :> es) =>
  UTCTime ->
  (PlannedCommand -> Text -> Text -> Eff es ()) ->
  [CommandReceipt] ->
  [PlannedCommand] ->
  Eff es (Either CommandExecutionError [CommandReceipt])
executeCommands completedAt onSuccess completed commands = do
  outcomes <- executeCommandOutcomes (CommandPlan commands)
  forM_ outcomes $ \outcome -> when (outcome ^. #status == CommandSucceeded) (onSuccess (outcome ^. #command) (outcome ^. #stdout) (outcome ^. #stderr))
  pure $ case find ((== CommandFailed) . (^. #status)) outcomes of
    Just failed -> Left (CommandExecutionError (failed ^. #command) (fromMaybe 127 (failed ^. #exitCode)) (failed ^. #stdout) (failed ^. #stderr))
    Nothing -> Right (reverse completed <> mapMaybe receipt outcomes)
  where
    receipt outcome
      | outcome ^. #status /= CommandSucceeded = Nothing
      | otherwise = plannedReceipt completedAt (outcome ^. #command)

-- | The receipts 'executeCommandPlan' returns when every runnable command in
-- the plan succeeds, stamped with @completedAt@. Known before the first
-- command runs, because fingerprints and the stamp do not depend on execution.
expectedCommandReceipts :: UTCTime -> CommandPlan -> [CommandReceipt]
expectedCommandReceipts completedAt commandPlan =
  mapMaybe expected (commandPlan ^. #commands)
  where
    expected planned
      | planned ^. #disposition /= CommandWillRun = Nothing
      | otherwise = plannedReceipt completedAt planned

-- | The receipt a successful run of one planned command earns. Checkout
-- commands and non-command operations never earn one.
plannedReceipt :: UTCTime -> PlannedCommand -> Maybe CommandReceipt
plannedReceipt completedAt planned
  | isCheckoutCommand (planned ^. #operation) = Nothing
  | otherwise = case planned ^. #operation of
      RunCommandOp {moduleName, command, workDir} -> Just (CommandReceipt (planned ^. #fingerprint) moduleName command workDir completedAt)
      _ -> Nothing

-- | Run a command phase whose receipts were published in advance. If the
-- phase returns a failure or throws, run the withdrawal action first, then
-- return the failure or rethrow. The withdrawal runs at most once, and an
-- exception it throws is discarded so it never masks the phase's own outcome;
-- callers that want to report a failed withdrawal do so inside the action.
withReceiptWithdrawal ::
  IO () ->
  IO (Either CommandExecutionError a) ->
  IO (Either CommandExecutionError a)
withReceiptWithdrawal withdraw phase = do
  result <- phase `onException` withdrawQuietly
  case result of
    Left _ -> withdrawQuietly
    Right _ -> pure ()
  pure result
  where
    withdrawQuietly = void (try @SomeException withdraw)

-- | Produce the accepted receipt map for the plan's current declaration set.
-- Removed commands are dropped. Fresh successes replace old receipts;
-- unchanged or explicitly disabled declarations retain a matching old receipt.
finalizeCommandReceipts ::
  CommandPlan ->
  [CommandReceipt] ->
  Map CommandFingerprint CommandReceipt ->
  Map CommandFingerprint CommandReceipt
finalizeCommandReceipts commandPlan completed priorReceipts =
  Map.fromList (mapMaybe receiptFor (commandPlan ^. #commands))
  where
    completedByFingerprint = Map.fromList [(receipt ^. #fingerprint, receipt) | receipt <- completed]

    receiptFor planned
      | isCheckoutCommand (planned ^. #operation) = Nothing
      | otherwise = case Map.lookup (planned ^. #fingerprint) completedByFingerprint of
          Just receipt -> Just (planned ^. #fingerprint, receipt)
          Nothing -> case planned ^. #disposition of
            CommandWillRun -> Nothing
            CommandSkippedUnchanged -> retainPrior planned
            CommandSkippedDisabled -> retainPrior planned

    retainPrior planned =
      (planned ^. #fingerprint,) <$> Map.lookup (planned ^. #fingerprint) priorReceipts
