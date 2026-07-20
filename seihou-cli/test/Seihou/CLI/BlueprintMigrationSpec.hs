module Seihou.CLI.BlueprintMigrationSpec (tests) where

import Data.IORef
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (UTCTime)
import Seihou.CLI.BlueprintMigration
import Seihou.Core.Migration
import Seihou.Core.Types
import Seihou.Core.Version (Version, parseVersion)
import System.Exit (ExitCode (..))
import Test.Hspec
import Test.Tasty (TestTree)
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.CLI.BlueprintMigration" $ do
  describe "pendingBlueprintMigrations" $ do
    it "retains the planner's order across an intentional version gap" $ do
      let late = migration "2.5.0" "3.0.0"
          early = migration "1.0.0" "2.0.0"
          Right (Just migrationPlan) =
            planBlueprintMigrationChain
              "payments"
              [late, early]
              (version "1.0.0")
              (version "3.0.0")
      pendingBlueprintMigrations False blueprintName [] migrationPlan
        `shouldBe` [early, late]

    it "resumes by filtering only an already-recorded exact edge" $ do
      let migrationPlan = plan [first, second]
          receipts =
            [ receipt blueprintName "1.0.0" "2.0.0",
              receipt "another-blueprint" "2.0.0" "3.0.0"
            ]
      pendingBlueprintMigrations False blueprintName receipts migrationPlan
        `shouldBe` [second]

    it "keeps recorded edges when rerun is requested" $ do
      let migrationPlan = plan [first, second]
          receipts = [receipt blueprintName "1.0.0" "2.0.0"]
      pendingBlueprintMigrations True blueprintName receipts migrationPlan
        `shouldBe` [first, second]

  describe "renderBlueprintMigrationInstruction" $ do
    it "substitutes the variables resolved for the shared blueprint" $ do
      let declaration = VarDecl "library.name" VTText Nothing Nothing False Nothing
          resolved =
            Map.singleton
              "library.name"
              (ResolvedVar (VText "baikai") FromDefault declaration)
      renderBlueprintMigrationInstruction resolved (migrationWithPrompt "1" "2" "Upgrade {{library.name}}.")
        `shouldBe` "Upgrade baikai."

  describe "runBlueprintMigrationsWith" $ do
    it "reports no work without invoking either callback" $ do
      calls <- newIORef ([] :: [Text])
      result <-
        runBlueprintMigrationsWith
          (\_ _ _ -> modifyIORef' calls (<> ["launch"]) >> pure (Right ()))
          (\_ -> modifyIORef' calls (<> ["record"]) >> pure (Right ()))
          []
      result `shouldBe` BlueprintMigrationNoWork
      readIORef calls `shouldReturn` []

    it "launches and records every edge sequentially" $ do
      calls <- newIORef ([] :: [Text])
      let launch position total edge = do
            modifyIORef' calls (<> ["launch " <> tshow position <> "/" <> tshow total <> " " <> edge.from])
            pure (Right ())
          record edge = do
            modifyIORef' calls (<> ["record " <> edge.from])
            pure (Right ())
      result <- runBlueprintMigrationsWith launch record [first, second]
      result `shouldBe` BlueprintMigrationComplete [first, second]
      readIORef calls
        `shouldReturn` [ "launch 1/2 1.0.0",
                         "record 1.0.0",
                         "launch 2/2 2.0.0",
                         "record 2.0.0"
                       ]

    it "records only completed edges after failure and resumes at the failed edge" $ do
      calls <- newIORef ([] :: [Text])
      recorded <- newIORef ([] :: [AppliedBlueprintMigration])
      let third = migration "3.0.0" "4.0.0"
          migrationPlan =
            BlueprintMigrationPlan
              { blueprintPlanName = "payments",
                blueprintPlanFrom = version "1.0.0",
                blueprintPlanTo = version "4.0.0",
                blueprintPlanSteps = [first, second, third]
              }
          launch _ _ edge = do
            modifyIORef' calls (<> ["launch " <> edge.from])
            pure $
              if edge == second
                then Left (BlueprintMigrationProcessFailure (ExitFailure 17))
                else Right ()
          record edge = do
            modifyIORef' calls (<> ["record " <> edge.from])
            modifyIORef' recorded (<> [receipt blueprintName edge.from edge.to])
            pure (Right ())
      result <- runBlueprintMigrationsWith launch record [first, second, third]
      result
        `shouldBe` BlueprintMigrationLaunchFailed second (BlueprintMigrationProcessFailure (ExitFailure 17))
      readIORef calls
        `shouldReturn` ["launch 1.0.0", "record 1.0.0", "launch 2.0.0"]

      savedReceipts <- readIORef recorded
      let resumed = pendingBlueprintMigrations False blueprintName savedReceipts migrationPlan
      resumed `shouldBe` [second, third]

      resumedResult <-
        runBlueprintMigrationsWith
          (\_ _ edge -> modifyIORef' calls (<> ["resume " <> edge.from]) >> pure (Right ()))
          record
          resumed
      resumedResult `shouldBe` BlueprintMigrationComplete [second, third]
      readIORef recorded `shouldReturn` map (\edge -> receipt blueprintName edge.from edge.to) [first, second, third]

    it "stops before the next launch when receipt recording fails" $ do
      calls <- newIORef ([] :: [Text])
      let launch _ _ edge = modifyIORef' calls (<> ["launch " <> edge.from]) >> pure (Right ())
          record edge = modifyIORef' calls (<> ["record " <> edge.from]) >> pure (Left "disk full")
      result <- runBlueprintMigrationsWith launch record [first, second]
      result `shouldBe` BlueprintMigrationRecordFailed first "disk full"
      readIORef calls `shouldReturn` ["launch 1.0.0", "record 1.0.0"]

blueprintName :: ModuleName
blueprintName = "payments"

first :: BlueprintMigration
first = migration "1.0.0" "2.0.0"

second :: BlueprintMigration
second = migration "2.0.0" "3.0.0"

migration :: Text -> Text -> BlueprintMigration
migration fromVersion toVersion =
  migrationWithPrompt fromVersion toVersion ("Migrate from " <> fromVersion <> " to " <> toVersion)

migrationWithPrompt :: Text -> Text -> Text -> BlueprintMigration
migrationWithPrompt fromVersion toVersion instructions =
  BlueprintMigration
    { from = fromVersion,
      to = toVersion,
      prompt = instructions
    }

plan :: [BlueprintMigration] -> BlueprintMigrationPlan
plan steps =
  BlueprintMigrationPlan
    { blueprintPlanName = "payments",
      blueprintPlanFrom = version "1.0.0",
      blueprintPlanTo = version "3.0.0",
      blueprintPlanSteps = steps
    }

receipt :: ModuleName -> Text -> Text -> AppliedBlueprintMigration
receipt name fromVersion toVersion =
  AppliedBlueprintMigration
    { name,
      blueprintVersion = Just "4.2.0",
      fromVersion,
      toVersion,
      appliedAt = read "2026-07-20 12:00:00 UTC" :: UTCTime,
      agentSessionId = Nothing
    }

version :: Text -> Version
version raw =
  case parseVersion raw of
    Just parsed -> parsed
    Nothing -> error "test version should parse"

tshow :: (Show a) => a -> Text
tshow = T.pack . show
