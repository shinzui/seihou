module Seihou.CLI.CommandExecutionSpec (tests) where

import Control.Exception (AsyncException (UserInterrupt), throwIO, try)
import Data.Generics.Labels ()
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromJust)
import Data.Time (UTCTime, defaultTimeLocale, parseTimeOrError)
import Effectful (runEff)
import Seihou.CLI.CommandExecution
import Seihou.Core.CommandFingerprint (fingerprintCommand)
import Seihou.Core.Types
import Seihou.Effect.ProcessPure (ProcessMock (..), runProcessPure)
import Seihou.Prelude
import System.Exit (ExitCode (..))
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.CLI.CommandExecution" spec

fixedTime :: UTCTime
fixedTime = parseTimeOrError True defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ" "2026-07-19T18:00:00Z"

laterTime :: UTCTime
laterTime = parseTimeOrError True defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ" "2026-07-19T19:00:00Z"

commandOp :: Text -> Maybe FilePath -> ModuleName -> Int -> Operation
commandOp command workDir moduleName occurrence =
  RunCommandOp {command, workDir, moduleName, occurrence, lifecycle = ApplicationCommand}

fingerprintOf :: Operation -> CommandFingerprint
fingerprintOf = fromJust . fingerprintCommand

receiptFor :: UTCTime -> Operation -> CommandReceipt
receiptFor completedAt operation@RunCommandOp {command, workDir, moduleName} =
  CommandReceipt
    { fingerprint = fingerprintOf operation,
      moduleName,
      command,
      workDir,
      completedAt
    }
receiptFor _ _ = error "receiptFor requires RunCommandOp"

successMock :: Text -> ProcessMock
successMock command =
  ProcessMock
    { command = "sh",
      args = ["-c", command],
      result = (ExitSuccess, "output", "")
    }

spec :: Spec
spec = do
  describe "planCommands" $ do
    it "preserves command order and ignores non-command operations" $ do
      let first = commandOp "echo first" Nothing "app" 0
          second = commandOp "echo second" Nothing "app" 0
          plan = planCommands RunAllCommands Map.empty [first, WriteFileOp "file" "content" Template, second]
      map (^. #operation) (plan ^. #commands) `shouldBe` [first, second]
      map (^. #disposition) (plan ^. #commands) `shouldBe` [CommandWillRun, CommandWillRun]

    it "skips only fingerprints with successful prior receipts in changed-only mode" $ do
      let unchanged = commandOp "echo same" Nothing "app" 0
          changed = commandOp "echo changed" Nothing "app" 0
          prior = Map.singleton (fingerprintOf unchanged) (receiptFor fixedTime unchanged)
          plan = planCommands RunChangedCommands prior [unchanged, changed]
      map (^. #disposition) (plan ^. #commands)
        `shouldBe` [CommandSkippedUnchanged, CommandWillRun]
      summarizeCommandPlan plan
        `shouldBe` CommandPlanSummary {willRun = 1, skippedUnchanged = 1, skippedDisabled = 0}

    it "runs duplicate declarations independently because occurrences differ" $ do
      let first = commandOp "echo same" Nothing "app" 0
          second = commandOp "echo same" Nothing "app" 1
          prior = Map.singleton (fingerprintOf first) (receiptFor fixedTime first)
          plan = planCommands RunChangedCommands prior [first, second]
      map (^. #disposition) (plan ^. #commands)
        `shouldBe` [CommandSkippedUnchanged, CommandWillRun]

    it "never lets an application receipt suppress or become checkout completion" $ do
      let ordinary = commandOp "echo same" Nothing "app" 0
          checkout = RunCommandOp "echo same" Nothing "app" 0 CheckoutCommandLifecycle
          prior = Map.singleton (fingerprintOf ordinary) (receiptFor fixedTime ordinary)
          plan = planCommands RunChangedCommands prior [checkout, ordinary]
      map (^. #disposition) (plan ^. #commands) `shouldBe` [CommandWillRun, CommandSkippedUnchanged]
      finalizeCommandReceipts (planCommands DisableCommands prior [checkout]) [] prior `shouldBe` Map.empty

    it "marks every command disabled without minting receipts" $ do
      let operations = [commandOp "echo one" Nothing "app" 0, commandOp "echo two" Nothing "app" 0]
          plan = planCommands DisableCommands Map.empty operations
      map (^. #disposition) (plan ^. #commands)
        `shouldBe` [CommandSkippedDisabled, CommandSkippedDisabled]

  describe "executeCommandPlan" $ do
    it "executes runnable commands in order and returns successful receipts" $ do
      let first = commandOp "echo first" Nothing "app" 0
          second = commandOp "echo second" (Just "subdir") "app" 0
          plan = planCommands RunAllCommands Map.empty [first, second]
      result <-
        runEff $
          runProcessPure [successMock "echo first", successMock "echo second"] $
            executeCommandPlan laterTime plan
      case result of
        Right receipts -> do
          map (^. #fingerprint) receipts `shouldBe` map fingerprintOf [first, second]
          map (^. #completedAt) receipts `shouldBe` [laterTime, laterTime]
        Left err -> expectationFailure ("Expected success, got: " <> show err)

    it "does not execute skipped commands" $ do
      let operation = commandOp "echo skipped" Nothing "app" 0
          priorReceipt = receiptFor fixedTime operation
          prior = Map.singleton (priorReceipt ^. #fingerprint) priorReceipt
          plan = planCommands RunChangedCommands prior [operation]
      result <- runEff $ runProcessPure [] $ executeCommandPlan laterTime plan
      result `shouldBe` Right []

    it "returns a structured error at the first failure" $ do
      let failing = commandOp "exit 7" Nothing "app" 0
          neverReached = commandOp "echo later" Nothing "app" 0
          plan = planCommands RunAllCommands Map.empty [failing, neverReached]
          mocks =
            [ ProcessMock
                { command = "sh",
                  args = ["-c", "exit 7"],
                  result = (ExitFailure 7, "partial", "boom")
                },
              successMock "echo later"
            ]
      result <- runEff $ runProcessPure mocks $ executeCommandPlan laterTime plan
      case result of
        Left err -> do
          (err ^. #exitCode) `shouldBe` 7
          (err ^. #stdout) `shouldBe` "partial"
          (err ^. #stderr) `shouldBe` "boom"
          (err ^. #command . #operation) `shouldBe` failing
        Right receipts -> expectationFailure ("Expected failure, got receipts: " <> show receipts)

  describe "finalizeCommandReceipts" $ do
    it "keeps fresh successes and unchanged receipts while dropping removed commands" $ do
      let unchanged = commandOp "echo unchanged" Nothing "app" 0
          changed = commandOp "echo changed" Nothing "app" 0
          removed = commandOp "echo removed" Nothing "app" 0
          oldUnchanged = receiptFor fixedTime unchanged
          oldRemoved = receiptFor fixedTime removed
          newChanged = receiptFor laterTime changed
          prior =
            Map.fromList
              [ (oldUnchanged ^. #fingerprint, oldUnchanged),
                (oldRemoved ^. #fingerprint, oldRemoved)
              ]
          plan = planCommands RunChangedCommands prior [unchanged, changed]
          finalized = finalizeCommandReceipts plan [newChanged] prior
      finalized
        `shouldBe` Map.fromList
          [ (oldUnchanged ^. #fingerprint, oldUnchanged),
            (newChanged ^. #fingerprint, newChanged)
          ]

    it "retains only matching old receipts when commands are disabled" $ do
      let old = commandOp "echo old" Nothing "app" 0
          new = commandOp "echo new" Nothing "app" 0
          oldReceipt = receiptFor fixedTime old
          prior = Map.singleton (oldReceipt ^. #fingerprint) oldReceipt
          plan = planCommands DisableCommands prior [old, new]
      finalizeCommandReceipts plan [] prior
        `shouldBe` Map.singleton (oldReceipt ^. #fingerprint) oldReceipt

  describe "expectedCommandReceipts" $ do
    it "equals the receipts a fully successful execution returns" $ do
      let first = commandOp "echo first" Nothing "app" 0
          second = commandOp "echo second" (Just "subdir") "app" 0
          plan = planCommands RunAllCommands Map.empty [first, second]
      result <-
        runEff $
          runProcessPure [successMock "echo first", successMock "echo second"] $
            executeCommandPlan laterTime plan
      result `shouldBe` Right (expectedCommandReceipts laterTime plan)
      map (^. #fingerprint) (expectedCommandReceipts laterTime plan) `shouldBe` map fingerprintOf [first, second]

    it "yields no receipt for skipped, disabled, or checkout commands" $ do
      let unchanged = commandOp "echo unchanged" Nothing "app" 0
          checkout = RunCommandOp "echo checkout" Nothing "app" 0 CheckoutCommandLifecycle
          prior = Map.singleton (fingerprintOf unchanged) (receiptFor fixedTime unchanged)
      expectedCommandReceipts laterTime (planCommands RunChangedCommands prior [unchanged, checkout]) `shouldBe` []
      expectedCommandReceipts laterTime (planCommands DisableCommands Map.empty [unchanged]) `shouldBe` []

    it "finalizes to the same receipt map as a successful execution" $ do
      let unchanged = commandOp "echo unchanged" Nothing "app" 0
          changed = commandOp "echo changed" Nothing "app" 0
          removed = commandOp "echo removed" Nothing "app" 0
          prior =
            Map.fromList
              [ (fingerprintOf unchanged, receiptFor fixedTime unchanged),
                (fingerprintOf removed, receiptFor fixedTime removed)
              ]
          plan = planCommands RunChangedCommands prior [unchanged, changed]
      result <- runEff $ runProcessPure [successMock "echo changed"] $ executeCommandPlan laterTime plan
      case result of
        Right actual ->
          finalizeCommandReceipts plan (expectedCommandReceipts laterTime plan) prior
            `shouldBe` finalizeCommandReceipts plan actual prior
        Left err -> expectationFailure ("Expected success, got: " <> show err)

  describe "withReceiptWithdrawal" $ do
    let failing = commandOp "exit 7" Nothing "app" 0
        failure =
          CommandExecutionError
            { command = PlannedCommand failing (fingerprintOf failing) CommandWillRun,
              exitCode = 7,
              stdout = "",
              stderr = ""
            }

    it "does not withdraw after a successful phase" $ do
      withdrawals <- newIORef (0 :: Int)
      result <- withReceiptWithdrawal (modifyIORef' withdrawals (+ 1)) (pure (Right ()))
      result `shouldBe` Right ()
      readIORef withdrawals `shouldReturn` 0

    it "withdraws once and returns a failed phase unchanged" $ do
      withdrawals <- newIORef (0 :: Int)
      result <- withReceiptWithdrawal (modifyIORef' withdrawals (+ 1)) (pure (Left failure :: Either CommandExecutionError ()))
      result `shouldBe` Left failure
      readIORef withdrawals `shouldReturn` 1

    it "withdraws once and rethrows an interrupted phase" $ do
      withdrawals <- newIORef (0 :: Int)
      result <-
        try @AsyncException $
          withReceiptWithdrawal (modifyIORef' withdrawals (+ 1)) (throwIO UserInterrupt :: IO (Either CommandExecutionError ()))
      result `shouldBe` Left UserInterrupt
      readIORef withdrawals `shouldReturn` 1

    it "does not let a failing withdrawal mask the phase failure" $ do
      result <- withReceiptWithdrawal (ioError (userError "disk full")) (pure (Left failure :: Either CommandExecutionError ()))
      result `shouldBe` Left failure
