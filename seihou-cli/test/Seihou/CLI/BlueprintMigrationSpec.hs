module Seihou.CLI.BlueprintMigrationSpec (tests) where

import Control.Lens (to, (^.))
import Data.Generics.Labels ()
import Data.IORef
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (UTCTime)
import Seihou.CLI.AgentLaunch (AgentContext (..))
import Seihou.CLI.BlueprintExecution (PreparedBlueprintExecution (..))
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
      pendingBlueprintMigrations False blueprintOrigin blueprintName [] migrationPlan
        `shouldBe` [early, late]

    it "resumes by filtering only an already-recorded exact edge" $ do
      let migrationPlan = plan [first, second]
          receipts =
            [ receipt blueprintOrigin blueprintName "1.0.0" "2.0.0",
              receipt blueprintOrigin "another-blueprint" "2.0.0" "3.0.0"
            ]
      pendingBlueprintMigrations False blueprintOrigin blueprintName receipts migrationPlan
        `shouldBe` [second]

    it "keeps recorded edges when rerun is requested" $ do
      let migrationPlan = plan [first, second]
          receipts = [receipt blueprintOrigin blueprintName "1.0.0" "2.0.0"]
      pendingBlueprintMigrations True blueprintOrigin blueprintName receipts migrationPlan
        `shouldBe` [first, second]

    -- The behaviour the origin field exists for. Two repositories can publish
    -- a blueprint under the same name; their identically-numbered edges are
    -- different work, and the first one's receipt must not silently suppress
    -- the second one's edge.
    it "does not let another repository's receipt suppress an identical edge" $ do
      let migrationPlan = plan [first, second]
          receipts = [receipt otherRepoOrigin blueprintName "1.0.0" "2.0.0"]
      pendingBlueprintMigrations False blueprintOrigin blueprintName receipts migrationPlan
        `shouldBe` [first, second]

    it "does drop the edge when the receipt is from the same repository" $ do
      let migrationPlan = plan [first, second]
          receipts = [receipt blueprintOrigin blueprintName "1.0.0" "2.0.0"]
      pendingBlueprintMigrations False blueprintOrigin blueprintName receipts migrationPlan
        `shouldBe` [second]

    -- Two spellings of one git URL are one repository. A developer who
    -- installed with the '.git' suffix must not see their recorded edges
    -- reappear because someone else typed it without.
    it "treats a trailing .git as the same origin" $ do
      let migrationPlan = plan [first, second]
          receipts =
            [receipt (RemoteOrigin "https://github.com/acme/one.git" "payments" Nothing) blueprintName "1.0.0" "2.0.0"]
      pendingBlueprintMigrations False blueprintOrigin blueprintName receipts migrationPlan
        `shouldBe` [second]

    -- Receipts written before origins were recorded decode as LocalOrigin.
    -- They match each other, and they match nothing installed from a URL.
    it "matches a legacy receipt only against an equally unprovenanced blueprint" $ do
      let migrationPlan = plan [first, second]
          receipts = [receipt (LocalOrigin "payments") blueprintName "1.0.0" "2.0.0"]
      pendingBlueprintMigrations False (LocalOrigin "payments") blueprintName receipts migrationPlan
        `shouldBe` [second]
      pendingBlueprintMigrations False blueprintOrigin blueprintName receipts migrationPlan
        `shouldBe` [first, second]

    -- The defect IR-1 filed. An edge that reported its precondition unmet
    -- recorded a receipt indistinguishable from a real upgrade, so the run
    -- that should have happened once the precondition was met never did.
    it "does not let a not-applicable receipt suppress its own edge" $ do
      let migrationPlan = plan [first, second]
          receipts =
            [ notApplicableReceipt
                blueprintOrigin
                blueprintName
                "1.0.0"
                "2.0.0"
                "the project has not adopted the bundle"
            ]
      pendingBlueprintMigrations False blueprintOrigin blueprintName receipts migrationPlan
        `shouldBe` [first, second]

    -- The same edge, the same origin, the same window: only the outcome
    -- differs, and only the applied one suppresses.
    it "suppresses the edge once the same edge is recorded as applied" $ do
      let migrationPlan = plan [first, second]
          skipped = notApplicableReceipt blueprintOrigin blueprintName "1.0.0" "2.0.0" "no adr bundle"
          applied = receipt blueprintOrigin blueprintName "1.0.0" "2.0.0"
      pendingBlueprintMigrations False blueprintOrigin blueprintName [skipped] migrationPlan
        `shouldBe` [first, second]
      pendingBlueprintMigrations False blueprintOrigin blueprintName [applied] migrationPlan
        `shouldBe` [second]

  describe "renderBlueprintMigrationInstruction" $ do
    it "substitutes the variables resolved for the shared blueprint" $ do
      let declaration = VarDecl "library.name" VTText Nothing Nothing False Nothing
          resolved =
            Map.singleton
              "library.name"
              (ResolvedVar (VText "baikai") FromDefault declaration)
      renderBlueprintMigrationInstruction resolved (migrationWithPrompt "1" "2" "Upgrade {{library.name}}.")
        `shouldBe` "Upgrade baikai."

  describe "renderBlueprintMigrationSystemPrompt" $ do
    it "renders identity, position, shared guidance, edge instructions, and reference access" $ do
      let edge = migrationWithPrompt "1.0.0" "2.0.0" "Upgrade {{library.name}} now."
          rendered =
            renderBlueprintMigrationSystemPrompt
              "{{blueprint_name}} {{blueprint_version}} | {{migration_position}}/{{migration_total}} | {{migration_from}} -> {{migration_to}} | {{shared_prompt}} | {{migration_prompt}} | {{reference_files_dir}} | {{cwd}}"
              "/tmp/project/.seihou/.migrate-signal"
              sampleContext
              samplePrepared
              1
              2
              edge
      rendered
        `shouldBe` "payments 4.2.0 | 1/2 | 1.0.0 -> 2.0.0 | Shared guidance for baikai. | Upgrade baikai now. | mounted at /tmp/payments/files | /tmp/project"

    -- The agent cannot signal inapplicability without being told where; the
    -- path is a template variable so the caller owns it, exactly as it owns
    -- the template text.
    it "substitutes the not-applicable signal path" $ do
      renderBlueprintMigrationSystemPrompt
        "write to {{not_applicable_signal_path}}"
        "/tmp/project/.seihou/.migrate-signal"
        sampleContext
        samplePrepared
        1
        1
        first
        `shouldBe` "write to /tmp/project/.seihou/.migrate-signal"

    it "delimits debug prompts in pending order without any execution callback" $ do
      let output =
            formatBlueprintMigrationDebugOutput
              (\position total edge -> "prompt " <> tshow position <> "/" <> tshow total <> " " <> edge ^. #from)
              [first, second]
      output `shouldSatisfy` T.isInfixOf "===== [1/2] 1.0.0 -> 2.0.0 ====="
      output `shouldSatisfy` T.isInfixOf "===== [2/2] 2.0.0 -> 3.0.0 ====="
      T.breakOn "2.0.0 -> 3.0.0" output `shouldSatisfy` (not . T.null . snd)

  describe "runBlueprintMigrationsWith" $ do
    it "reports no work without invoking either callback" $ do
      calls <- newIORef ([] :: [Text])
      result <-
        runBlueprintMigrationsWith
          (\_ _ _ -> modifyIORef' calls (<> ["launch"]) >> pure (Right BlueprintMigrationSessionReturned))
          (\_ _ -> modifyIORef' calls (<> ["record"]) >> pure (Right ()))
          []
      result `shouldBe` BlueprintMigrationNoWork
      readIORef calls `shouldReturn` []

    it "launches and records every edge sequentially" $ do
      calls <- newIORef ([] :: [Text])
      let launch position total edge = do
            modifyIORef' calls (<> ["launch " <> tshow position <> "/" <> tshow total <> " " <> edge ^. #from])
            pure (Right BlueprintMigrationSessionReturned)
          record edge _ = do
            modifyIORef' calls (<> ["record " <> edge ^. #from])
            pure (Right ())
      result <- runBlueprintMigrationsWith launch record [first, second]
      result `shouldBe` BlueprintMigrationComplete [(first, MigrationApplied), (second, MigrationApplied)]
      readIORef calls
        `shouldReturn` [ "launch 1/2 1.0.0",
                         "record 1.0.0",
                         "launch 2/2 2.0.0",
                         "record 2.0.0"
                       ]

    -- IR-1 rejects exiting nonzero for an inapplicable edge precisely because
    -- it "halts a multi-edge chain that should have continued past an
    -- inapplicable step". This is that requirement.
    it "records the outcome and continues past a not-applicable edge" $ do
      calls <- newIORef ([] :: [Text])
      outcomes <- newIORef ([] :: [(Text, MigrationOutcome)])
      let launch _ _ edge = do
            modifyIORef' calls (<> ["launch " <> edge ^. #from])
            pure . Right $
              if edge == first
                then BlueprintMigrationSessionNotApplicable "no docs/adr directory"
                else BlueprintMigrationSessionReturned
          record edge outcome = do
            modifyIORef' calls (<> ["record " <> edge ^. #from])
            modifyIORef' outcomes (<> [(edge ^. #from, outcome)])
            pure (Right ())
      result <- runBlueprintMigrationsWith launch record [first, second]
      result
        `shouldBe` BlueprintMigrationComplete
          [ (first, MigrationNotApplicable "no docs/adr directory"),
            (second, MigrationApplied)
          ]
      readIORef calls
        `shouldReturn` ["launch 1.0.0", "record 1.0.0", "launch 2.0.0", "record 2.0.0"]
      readIORef outcomes
        `shouldReturn` [ ("1.0.0", MigrationNotApplicable "no docs/adr directory"),
                         ("2.0.0", MigrationApplied)
                       ]

    it "records only completed edges after failure and resumes at the failed edge" $ do
      calls <- newIORef ([] :: [Text])
      recorded <- newIORef ([] :: [AppliedBlueprintMigration])
      let third = migration "3.0.0" "4.0.0"
          migrationPlan =
            BlueprintMigrationPlan
              { name = "payments",
                from = version "1.0.0",
                to = version "4.0.0",
                steps = [first, second, third]
              }
          launch _ _ edge = do
            modifyIORef' calls (<> ["launch " <> edge ^. #from])
            pure $
              if edge == second
                then Left (BlueprintMigrationProcessFailure (ExitFailure 17))
                else Right BlueprintMigrationSessionReturned
          record edge _ = do
            modifyIORef' calls (<> ["record " <> edge ^. #from])
            modifyIORef' recorded (<> [receipt blueprintOrigin blueprintName (edge ^. #from) (edge ^. #to)])
            pure (Right ())
      result <- runBlueprintMigrationsWith launch record [first, second, third]
      result
        `shouldBe` BlueprintMigrationLaunchFailed second (BlueprintMigrationProcessFailure (ExitFailure 17))
      readIORef calls
        `shouldReturn` ["launch 1.0.0", "record 1.0.0", "launch 2.0.0"]

      savedReceipts <- readIORef recorded
      let resumed = pendingBlueprintMigrations False blueprintOrigin blueprintName savedReceipts migrationPlan
      resumed `shouldBe` [second, third]

      resumedResult <-
        runBlueprintMigrationsWith
          (\_ _ edge -> modifyIORef' calls (<> ["resume " <> edge ^. #from]) >> pure (Right BlueprintMigrationSessionReturned))
          record
          resumed
      resumedResult `shouldBe` BlueprintMigrationComplete [(second, MigrationApplied), (third, MigrationApplied)]
      readIORef recorded `shouldReturn` map (\edge -> receipt blueprintOrigin blueprintName (edge ^. #from) (edge ^. #to)) [first, second, third]

    it "stops before the next launch when receipt recording fails" $ do
      calls <- newIORef ([] :: [Text])
      let launch _ _ edge = modifyIORef' calls (<> ["launch " <> edge ^. #from]) >> pure (Right BlueprintMigrationSessionReturned)
          record edge _ = modifyIORef' calls (<> ["record " <> edge ^. #from]) >> pure (Left "disk full")
      result <- runBlueprintMigrationsWith launch record [first, second]
      result `shouldBe` BlueprintMigrationRecordFailed first "disk full"
      readIORef calls `shouldReturn` ["launch 1.0.0", "record 1.0.0"]

  describe "parseNotApplicableSignal" $ do
    it "reads the plain marker line" $
      parseNotApplicableSignal "Checked the pins.\nSEIHOU: not-applicable the bundle was never adopted"
        `shouldBe` Just "the bundle was never adopted"

    it "tolerates backticks, bold, and trailing whitespace" $ do
      parseNotApplicableSignal "`SEIHOU: not-applicable no kiroku imports`"
        `shouldBe` Just "no kiroku imports"
      parseNotApplicableSignal "**SEIHOU: not-applicable no kiroku imports**"
        `shouldBe` Just "no kiroku imports"
      parseNotApplicableSignal "**SEIHOU:** not-applicable no kiroku imports"
        `shouldBe` Just "no kiroku imports"
      parseNotApplicableSignal "   SEIHOU: not-applicable no kiroku imports   \n\n"
        `shouldBe` Just "no kiroku imports"

    it "finds the marker above a closing sentence" $
      parseNotApplicableSignal
        (T.unlines ["Summary of what I checked.", "SEIHOU: not-applicable nothing to upgrade", "", "No files were changed."])
        `shouldBe` Just "nothing to upgrade"

    it "records a placeholder when the marker carries no reason" $
      parseNotApplicableSignal "SEIHOU: not-applicable" `shouldBe` Just unstatedNotApplicableReason

    -- A parser that reads a refusal out of prose silently skips real work,
    -- which is strictly worse than missing a signal the agent could also have
    -- written to the signal file.
    it "rejects prose that merely mentions the words" $ do
      parseNotApplicableSignal "This edge is not applicable to projects without an ADR bundle."
        `shouldBe` Nothing
      parseNotApplicableSignal "I considered writing SEIHOU: not-applicable but the edge does apply."
        `shouldBe` Nothing
      parseNotApplicableSignal "not-applicable" `shouldBe` Nothing
      parseNotApplicableSignal "SEIHOU: not-applicable-ish" `shouldBe` Nothing
      parseNotApplicableSignal "" `shouldBe` Nothing
      parseNotApplicableSignal "Upgraded three call sites and ran the tests." `shouldBe` Nothing

blueprintName :: ModuleName
blueprintName = "payments"

-- | The identity of the blueprint under test: installed from one repository.
blueprintOrigin :: ArtifactOrigin
blueprintOrigin = RemoteOrigin "https://github.com/acme/one" "payments" Nothing

-- | A different repository publishing a blueprint of the same name.
otherRepoOrigin :: ArtifactOrigin
otherRepoOrigin = RemoteOrigin "https://github.com/acme/two" "payments" Nothing

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
    { name = "payments",
      from = version "1.0.0",
      to = version "3.0.0",
      steps = steps
    }

receipt :: ArtifactOrigin -> ModuleName -> Text -> Text -> AppliedBlueprintMigration
receipt origin name fromVersion toVersion =
  receiptWithOutcome origin name fromVersion toVersion MigrationApplied

-- | A receipt for an edge that reported its precondition unmet.
notApplicableReceipt :: ArtifactOrigin -> ModuleName -> Text -> Text -> Text -> AppliedBlueprintMigration
notApplicableReceipt origin name fromVersion toVersion reason =
  receiptWithOutcome origin name fromVersion toVersion (MigrationNotApplicable reason)

receiptWithOutcome :: ArtifactOrigin -> ModuleName -> Text -> Text -> MigrationOutcome -> AppliedBlueprintMigration
receiptWithOutcome origin name fromVersion toVersion outcome =
  AppliedBlueprintMigration
    { name,
      origin,
      blueprintVersion = Just "4.2.0",
      fromVersion,
      toVersion,
      outcome,
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

sampleContext :: AgentContext
sampleContext =
  AgentContext
    { cwd = "/tmp/project",
      seihouInitialized = True,
      hasManifest = False,
      localModuleDhall = False,
      localModules = [],
      availableModules = []
    }

samplePrepared :: PreparedBlueprintExecution
samplePrepared =
  let declaration = VarDecl "library.name" VTText Nothing Nothing False Nothing
      resolved =
        Map.singleton
          "library.name"
          (ResolvedVar (VText "baikai") FromDefault declaration)
      blueprint =
        Blueprint
          { name = blueprintName,
            version = Just "4.2.0",
            description = Just "Payments upgrade",
            prompt = "Shared guidance for {{library.name}}.",
            vars = [declaration],
            prompts = [],
            baseModules = [],
            files = [],
            allowedTools = Nothing,
            tags = [],
            migrations = [first, second],
            launch = Nothing
          }
   in PreparedBlueprintExecution
        { blueprint = blueprint,
          blueprintDir = "/tmp/payments",
          resolvedVariables = resolved,
          mountedFilesDir = Just "/tmp/payments/files",
          referenceFiles = "  - guide.md",
          referenceFilesAccess = "mounted at /tmp/payments/files",
          sharedPrompt = "Shared guidance for baikai.",
          allowedTools = ["Read"]
        }
