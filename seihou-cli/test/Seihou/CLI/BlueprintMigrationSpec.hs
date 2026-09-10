module Seihou.CLI.BlueprintMigrationSpec (tests) where

import Control.Lens (to, (^.))
import Data.Generics.Labels ()
import Data.IORef
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (UTCTime)
import Effectful (runPureEff)
import Seihou.CLI.AgentLaunch (AgentContext (..))
import Seihou.CLI.BlueprintExecution (PreparedBlueprintExecution (..))
import Seihou.CLI.BlueprintMigration
import Seihou.Core.Migration
import Seihou.Core.Types
import Seihou.Core.Version (Version, parseVersion)
import Seihou.Effect.ProcessPure (ProcessMock (..), runProcessPure)
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
      pendingBlueprintMigrations False owners [] migrationPlan
        `shouldBe` [ownedStep "payments" early, ownedStep "payments" late]

    it "resumes by filtering only an already-recorded exact edge" $ do
      let migrationPlan = plan [first, second]
          receipts =
            [ receipt blueprintOrigin blueprintName "1.0.0" "2.0.0",
              receipt blueprintOrigin "another-blueprint" "2.0.0" "3.0.0"
            ]
      pendingBlueprintMigrations False owners receipts migrationPlan
        `shouldBe` [second]

    it "keeps recorded edges when rerun is requested" $ do
      let migrationPlan = plan [first, second]
          receipts = [receipt blueprintOrigin blueprintName "1.0.0" "2.0.0"]
      pendingBlueprintMigrations True owners receipts migrationPlan
        `shouldBe` [first, second]

    -- The behaviour the origin field exists for. Two repositories can publish
    -- a blueprint under the same name; their identically-numbered edges are
    -- different work, and the first one's receipt must not silently suppress
    -- the second one's edge.
    it "does not let another repository's receipt suppress an identical edge" $ do
      let migrationPlan = plan [first, second]
          receipts = [receipt otherRepoOrigin blueprintName "1.0.0" "2.0.0"]
      pendingBlueprintMigrations False owners receipts migrationPlan
        `shouldBe` [first, second]

    it "does drop the edge when the receipt is from the same repository" $ do
      let migrationPlan = plan [first, second]
          receipts = [receipt blueprintOrigin blueprintName "1.0.0" "2.0.0"]
      pendingBlueprintMigrations False owners receipts migrationPlan
        `shouldBe` [second]

    -- Two spellings of one git URL are one repository. A developer who
    -- installed with the '.git' suffix must not see their recorded edges
    -- reappear because someone else typed it without.
    it "treats a trailing .git as the same origin" $ do
      let migrationPlan = plan [first, second]
          receipts =
            [receipt (RemoteOrigin "https://github.com/acme/one.git" "payments" Nothing) blueprintName "1.0.0" "2.0.0"]
      pendingBlueprintMigrations False owners receipts migrationPlan
        `shouldBe` [second]

    -- Receipts written before origins were recorded decode as LocalOrigin.
    -- They match each other, and they match nothing installed from a URL.
    it "matches a legacy receipt only against an equally unprovenanced blueprint" $ do
      let migrationPlan = plan [first, second]
          receipts = [receipt (LocalOrigin "payments") blueprintName "1.0.0" "2.0.0"]
          unprovenancedOwners =
            ownersFrom [("payments", (blueprintName, LocalOrigin "payments"))]
      pendingBlueprintMigrations False unprovenancedOwners receipts migrationPlan
        `shouldBe` [second]
      pendingBlueprintMigrations False owners receipts migrationPlan
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
      pendingBlueprintMigrations False owners receipts migrationPlan
        `shouldBe` [first, second]

    -- The same edge, the same origin, the same window: only the outcome
    -- differs, and only the applied one suppresses.
    it "suppresses the edge once the same edge is recorded as applied" $ do
      let migrationPlan = plan [first, second]
          skipped = notApplicableReceipt blueprintOrigin blueprintName "1.0.0" "2.0.0" "no adr bundle"
          applied = receipt blueprintOrigin blueprintName "1.0.0" "2.0.0"
      pendingBlueprintMigrations False owners [skipped] migrationPlan
        `shouldBe` [first, second]
      pendingBlueprintMigrations False owners [applied] migrationPlan
        `shouldBe` [second]

    -- The regression fence around fan-out's central claim. A plan whose steps
    -- belong to two blueprints is filtered per step against the receipts of
    -- that step's own owner.
    it "drops an entailed step when the entailed blueprint recorded that edge" $ do
      let migrationPlan = plan [entailedStep, first]
          receipts = [receipt entailedOrigin entailedName "1.9.0" "2.0.0"]
      pendingBlueprintMigrations False cohortOwners receipts migrationPlan
        `shouldBe` [first]

    -- The mirror, and the whole reason the receipt is written under the owner:
    -- a receipt filed under the invoking blueprint for the same window says
    -- nothing about the entailed blueprint's edge, and must not drop it.
    it "does not drop an entailed step because the invoking blueprint recorded that window" $ do
      let migrationPlan = plan [entailedStep, first]
          receipts = [receipt blueprintOrigin blueprintName "1.9.0" "2.0.0"]
      pendingBlueprintMigrations False cohortOwners receipts migrationPlan
        `shouldBe` [entailedStep, first]

    -- Discovery resolves every owner before a plan reaches this function, so
    -- an unresolvable owner is an internal inconsistency. Claiming the step
    -- was already applied would silently skip real work; the honest answer is
    -- that nothing is known about it.
    it "treats a step whose owner cannot be resolved as not previously applied" $ do
      let migrationPlan = plan [entailedStep]
          receipts = [receipt entailedOrigin entailedName "1.9.0" "2.0.0"]
      pendingBlueprintMigrations False owners receipts migrationPlan
        `shouldBe` [entailedStep]

  describe "formatMigrationStepLabel" $ do
    it "names the owning blueprint and the edge" $
      formatMigrationStepLabel first `shouldBe` "payments 1.0.0 -> 2.0.0"

    it "names what pulled in an entailed step" $
      formatMigrationStepLabel entailedStep
        `shouldBe` "kiroku-upgrade 1.9.0 -> 2.0.0 (entailed by keiro-upgrade 2.4.0 -> 3.0.0)"

  describe "formatMarkAppliedNotice" $ do
    it "names every step it is about to record, with the owning blueprint" $
      formatMarkAppliedNotice [first, second]
        `shouldBe` T.unlines
          [ "Marking 2 blueprint migration(s) as already applied, without running them:",
            "  payments 1.0.0 -> 2.0.0",
            "  payments 2.0.0 -> 3.0.0"
          ]

    -- Proves the notice goes through 'formatMigrationStepLabel' rather than a
    -- second label derivation: someone marking a cohort window must see that
    -- an edge of a blueprint they never named is about to get a receipt, and
    -- what pulled it in.
    it "labels an entailed step with what entailed it" $
      formatMarkAppliedNotice [entailedStep]
        `shouldSatisfy` T.isInfixOf
          "  kiroku-upgrade 1.9.0 -> 2.0.0 (entailed by keiro-upgrade 2.4.0 -> 3.0.0)\n"

    it "counts the steps it lists" $
      formatMarkAppliedNotice [first, second, entailedStep]
        `shouldSatisfy` T.isPrefixOf "Marking 3 blueprint migration(s) "

  describe "formatMarkAppliedSummary" $ do
    -- The second sentence is the whole point of the line: it is what makes a
    -- mistaken marking obvious the moment it happens.
    it "says plainly that nothing ran and nothing changed" $
      formatMarkAppliedSummary 2
        `shouldBe` "Recorded 2 receipt(s). No agent session was started and no file was changed."

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
      let edge = ownedStep "payments" (migrationWithPrompt "1.0.0" "2.0.0" "Upgrade {{library.name}} now.")
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

    -- An entailed step is being run on a library the user never named, so the
    -- framing has to say why it is happening at all.
    it "explains an entailed step, and says nothing for a directly selected one" $ do
      let render step =
            renderBlueprintMigrationSystemPrompt
              "{{migration_entailed_by}}"
              "/tmp/project/.seihou/.migrate-signal"
              sampleContext
              samplePrepared
              1
              1
              step
      render entailedStep
        `shouldBe` "This edge was not requested directly. It is required by keiro-upgrade 2.4.0 -> 3.0.0, which the user is migrating."
      render first `shouldBe` ""

    it "delimits debug prompts in pending order without any execution callback" $ do
      let output =
            formatBlueprintMigrationDebugOutput
              (\position total step -> "prompt " <> tshow position <> "/" <> tshow total <> " " <> step ^. #edge . #from)
              [first, second]
      output `shouldSatisfy` T.isInfixOf "===== [1/2] payments 1.0.0 -> 2.0.0 ====="
      output `shouldSatisfy` T.isInfixOf "===== [2/2] payments 2.0.0 -> 3.0.0 ====="
      T.breakOn "2.0.0 -> 3.0.0" output `shouldSatisfy` (not . T.null . snd)

    -- A chain that spans blueprints is unreadable if every header looks the
    -- same; the owner is the only way to tell whose prompt follows.
    it "labels a debug header with the owning blueprint and what entailed it" $ do
      let output =
            formatBlueprintMigrationDebugOutput
              (\_ _ _ -> "prompt body")
              [entailedStep, first]
      output
        `shouldSatisfy` T.isInfixOf
          "===== [1/2] kiroku-upgrade 1.9.0 -> 2.0.0 (entailed by keiro-upgrade 2.4.0 -> 3.0.0) ====="
      output `shouldSatisfy` T.isInfixOf "===== [2/2] payments 1.0.0 -> 2.0.0 ====="

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
      let launch position total step = do
            modifyIORef' calls (<> ["launch " <> tshow position <> "/" <> tshow total <> " " <> step ^. #edge . #from])
            pure (Right BlueprintMigrationSessionReturned)
          record step _ = do
            modifyIORef' calls (<> ["record " <> step ^. #edge . #from])
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
      let launch _ _ step = do
            modifyIORef' calls (<> ["launch " <> step ^. #edge . #from])
            pure . Right $
              if step == first
                then BlueprintMigrationSessionNotApplicable "no docs/adr directory"
                else BlueprintMigrationSessionReturned
          record step outcome = do
            modifyIORef' calls (<> ["record " <> step ^. #edge . #from])
            modifyIORef' outcomes (<> [(step ^. #edge . #from, outcome)])
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
      let third = ownedStep "payments" (migration "3.0.0" "4.0.0")
          migrationPlan =
            BlueprintMigrationPlan
              { name = "payments",
                from = version "1.0.0",
                to = version "4.0.0",
                steps = [first, second, third]
              }
          launch _ _ step = do
            modifyIORef' calls (<> ["launch " <> step ^. #edge . #from])
            pure $
              if step == second
                then Left (BlueprintMigrationProcessFailure (ExitFailure 17))
                else Right BlueprintMigrationSessionReturned
          record step _ = do
            modifyIORef' calls (<> ["record " <> step ^. #edge . #from])
            modifyIORef' recorded (<> [receipt blueprintOrigin blueprintName (step ^. #edge . #from) (step ^. #edge . #to)])
            pure (Right ())
      result <- runBlueprintMigrationsWith launch record [first, second, third]
      result
        `shouldBe` BlueprintMigrationLaunchFailed second (BlueprintMigrationProcessFailure (ExitFailure 17))
      readIORef calls
        `shouldReturn` ["launch 1.0.0", "record 1.0.0", "launch 2.0.0"]

      savedReceipts <- readIORef recorded
      let resumed = pendingBlueprintMigrations False owners savedReceipts migrationPlan
      resumed `shouldBe` [second, third]

      resumedResult <-
        runBlueprintMigrationsWith
          (\_ _ step -> modifyIORef' calls (<> ["resume " <> step ^. #edge . #from]) >> pure (Right BlueprintMigrationSessionReturned))
          record
          resumed
      resumedResult `shouldBe` BlueprintMigrationComplete [(second, MigrationApplied), (third, MigrationApplied)]
      readIORef recorded
        `shouldReturn` map
          (\step -> receipt blueprintOrigin blueprintName (step ^. #edge . #from) (step ^. #edge . #to))
          [first, second, third]

    it "stops before the next launch when receipt recording fails" $ do
      calls <- newIORef ([] :: [Text])
      let launch _ _ step = modifyIORef' calls (<> ["launch " <> step ^. #edge . #from]) >> pure (Right BlueprintMigrationSessionReturned)
          record step _ = modifyIORef' calls (<> ["record " <> step ^. #edge . #from]) >> pure (Left "disk full")
      result <- runBlueprintMigrationsWith launch record [first, second]
      result `shouldBe` BlueprintMigrationRecordFailed first "disk full"
      readIORef calls `shouldReturn` ["launch 1.0.0", "record 1.0.0"]

  describe "highestMigratedVersion" $ do
    it "returns Nothing when nothing has been recorded" $
      highestMigratedVersion blueprintOrigin blueprintName [] `shouldBe` Nothing

    it "returns the highest recorded target with the receipt that says so" $ do
      let earlier = receipt blueprintOrigin blueprintName "1.0.0" "2.0.0"
          later = receipt blueprintOrigin blueprintName "2.0.0" "2.5.0"
      highestMigratedVersion blueprintOrigin blueprintName [later, earlier]
        `shouldBe` Just (version "2.5.0", later)

    it "ignores receipts belonging to another blueprint name" $
      highestMigratedVersion
        blueprintOrigin
        blueprintName
        [receipt blueprintOrigin "another-blueprint" "1.0.0" "9.0.0"]
        `shouldBe` Nothing

    -- The reason origin is part of the identity: another repository's
    -- same-named blueprint records a different project history, and starting
    -- this project's window from it would skip every edge below its target.
    it "ignores a same-named receipt from another repository" $
      highestMigratedVersion
        blueprintOrigin
        blueprintName
        [receipt otherRepoOrigin blueprintName "1.0.0" "9.0.0"]
        `shouldBe` Nothing

    it "treats two spellings of one git URL as the same repository" $ do
      let dotGit = receipt (RemoteOrigin "https://github.com/acme/one.git" "payments" Nothing) blueprintName "1.0.0" "2.0.0"
      highestMigratedVersion blueprintOrigin blueprintName [dotGit]
        `shouldBe` Just (version "2.0.0", dotGit)

    -- One malformed entry written by an earlier run must not make the
    -- command unusable.
    it "skips an unparseable recorded version rather than failing" $ do
      let usable = receipt blueprintOrigin blueprintName "1.0.0" "2.0.0"
          broken = receipt blueprintOrigin blueprintName "2.0.0" "not-a-version"
      highestMigratedVersion blueprintOrigin blueprintName [broken, usable]
        `shouldBe` Just (version "2.0.0", usable)

    -- The subtlest correctness point in the feature. A not-applicable receipt
    -- says seihou considered an edge and this project did not need it, which
    -- is not progress. Its target is deliberately the highest here, so an
    -- implementation that counted it would visibly pick it and then skip the
    -- 2.0.0 -> 3.0.0 edge forever.
    it "does not count a not-applicable receipt as progress" $ do
      let applied = receipt blueprintOrigin blueprintName "1.0.0" "2.0.0"
          skipped = notApplicableReceipt blueprintOrigin blueprintName "2.0.0" "3.0.0" "no bundle adopted"
      highestMigratedVersion blueprintOrigin blueprintName [applied, skipped]
        `shouldBe` Just (version "2.0.0", applied)

  describe "resolveMigrationWindow" $ do
    it "takes an explicit flag over the probe and the receipts, at each end" $ do
      resolveMigrationWindow (Just (version "1.0.0")) (Just (version "4.0.0")) probeResult recordedResult
        `shouldBe` Right
          ResolvedWindow
            { fromVersion = version "1.0.0",
              fromSource = VersionFromFlag,
              toVersion = version "4.0.0",
              toSource = VersionFromFlag
            }

    -- The two ends resolve independently: either may be typed while the
    -- other is inferred.
    it "infers only the end that was not given" $ do
      resolveMigrationWindow (Just (version "1.0.0")) Nothing probeResult recordedResult
        `shouldBe` Right
          ResolvedWindow
            { fromVersion = version "1.0.0",
              fromSource = VersionFromFlag,
              toVersion = version "3.0.0",
              toSource = VersionFromProbe "cat .library-version"
            }
      resolveMigrationWindow Nothing (Just (version "4.0.0")) probeResult recordedResult
        `shouldBe` Right
          ResolvedWindow
            { fromVersion = version "2.0.0",
              fromSource = VersionFromReceipt recordedReceipt,
              toVersion = version "4.0.0",
              toSource = VersionFromFlag
            }

    -- The probe reads how far the dependency was bumped, so it is the
    -- target; the ledger records how far the source was carried, so it is the
    -- start. Reversing them would report nothing to do for every project that
    -- bumped its lockfile first, which is the workflow this exists for.
    it "takes --to from the probe and --from from the receipt" $
      resolveMigrationWindow Nothing Nothing probeResult recordedResult
        `shouldBe` Right
          ResolvedWindow
            { fromVersion = version "2.0.0",
              fromSource = VersionFromReceipt recordedReceipt,
              toVersion = version "3.0.0",
              toSource = VersionFromProbe "cat .library-version"
            }

    it "reports a missing target when there is no --to and no probe" $
      resolveMigrationWindow Nothing Nothing Nothing recordedResult
        `shouldBe` Left NoTargetVersion

    it "reports a missing start when there is no --from and no receipt" $
      resolveMigrationWindow Nothing Nothing probeResult Nothing
        `shouldBe` Left NoStartVersion

  describe "readVersionProbeOutput" $ do
    it "reads a version printed on its own" $
      readVersionProbeOutput "3.0.0\n" `shouldBe` ProbeVersion (version "3.0.0")

    -- A probe like `nix eval` prints progress before its answer, and
    -- requiring authors to silence every tool's chatter would make probes
    -- fragile.
    it "reads the last non-empty line, past progress output" $
      readVersionProbeOutput "evaluating derivation\nbuilding...\n\n3.0.0\n\n"
        `shouldBe` ProbeVersion (version "3.0.0")

    it "reports unparseable output with the raw text" $ do
      readVersionProbeOutput "v3.0.0\n" `shouldBe` ProbeOutputUnparseable "v3.0.0\n"
      readVersionProbeOutput "" `shouldBe` ProbeOutputUnparseable ""

  describe "runVersionProbe" $ do
    it "returns the version a successful probe printed" $
      runProbe (ExitSuccess, "3.0.0\n", "") `shouldBe` ProbeVersion (version "3.0.0")

    it "returns the version after progress lines" $
      runProbe (ExitSuccess, "evaluating\n3.0.0\n", "warning: ignoring config\n")
        `shouldBe` ProbeVersion (version "3.0.0")

    -- Neither failure aborts the command: the caller reports them and falls
    -- through to requiring --to, because the user did not write the probe and
    -- still has an explicit flag.
    it "carries a nonzero exit and its stderr back to the caller" $
      runProbe (ExitFailure 1, "", "cat: .library-version: No such file\n")
        `shouldBe` ProbeExitedNonZero 1 "cat: .library-version: No such file\n"

    it "reports output that is not a version" $
      runProbe (ExitSuccess, "nothing useful\n", "")
        `shouldBe` ProbeOutputUnparseable "nothing useful\n"

    it "falls through when the probe command does not exist at all" $
      runPureEff (runProcessPure [] (runVersionProbe "no-such-tool" "/tmp/project"))
        `shouldBe` ProbeExitedNonZero 127 "command not found: sh"

  describe "formatResolvedWindow" $ do
    -- Existing invocations that name both versions keep printing exactly what
    -- they printed before; the user does not need to be told what they typed.
    it "says nothing when both ends were typed and verbose was not asked for" $
      formatResolvedWindow False (windowWith VersionFromFlag VersionFromFlag) `shouldBe` []

    it "names both sources under verbose" $
      formatResolvedWindow True (windowWith VersionFromFlag VersionFromFlag)
        `shouldBe` [ "Version window: 2.0.0 -> 3.0.0",
                     "  --from 2.0.0  [flag]",
                     "  --to   3.0.0  [flag]"
                   ]

    -- An inferred window that is silently wrong runs the wrong agent sessions
    -- against the user's source, so an inferred end always reports itself.
    it "reports an inferred end at normal verbosity, and only that end" $
      formatResolvedWindow False (windowWith VersionFromFlag (VersionFromProbe "cat .library-version"))
        `shouldBe` [ "Version window: 2.0.0 -> 3.0.0",
                     "  --to   3.0.0  [probe: cat .library-version]"
                   ]

    it "names the blueprint, the edge, and the date a receipt-derived start came from" $
      formatResolvedWindow False (windowWith (VersionFromReceipt recordedReceipt) (VersionFromProbe "cat .library-version"))
        `shouldBe` [ "Version window: 2.0.0 -> 3.0.0",
                     "  --from 2.0.0  [receipt: payments 1.0.0 -> 2.0.0, applied 2026-07-20]",
                     "  --to   3.0.0  [probe: cat .library-version]"
                   ]

  describe "formatProbeFailure" $ do
    it "says nothing about a probe that produced a version" $
      formatProbeFailure "cat .library-version" (ProbeVersion (version "3.0.0")) `shouldBe` Nothing

    it "shows the command, the exit code, and the stderr" $ do
      let rendered = formatProbeFailure "cat .library-version" (ProbeExitedNonZero 1 "No such file\n")
      rendered `shouldSatisfy` maybe False (T.isInfixOf "probe:  cat .library-version")
      rendered `shouldSatisfy` maybe False (T.isInfixOf "exit:   1")
      rendered `shouldSatisfy` maybe False (T.isInfixOf "stderr: No such file")

    it "shows what an unparseable probe printed" $
      formatProbeFailure "cat .library-version" (ProbeOutputUnparseable "v3.0.0\n")
        `shouldSatisfy` maybe False (T.isInfixOf "output: v3.0.0")

  describe "formatWindowResolutionError" $ do
    it "names --to and the author's remedy for a missing target" $ do
      let rendered = formatWindowResolutionError blueprintName NoTargetVersion
      rendered `shouldSatisfy` T.isInfixOf "Cannot determine the target version for 'payments'."
      rendered `shouldSatisfy` T.isInfixOf "Pass --to VERSION"
      rendered `shouldSatisfy` T.isInfixOf "versionProbe"

    -- The first-run case, which will be much the commoner of the two. It
    -- should read as an explanation of what seihou does not know, not as a
    -- complaint about what the user failed to type.
    it "explains rather than complains about a missing start" $ do
      let rendered = formatWindowResolutionError blueprintName NoStartVersion
      rendered `shouldSatisfy` T.isInfixOf "no recorded migration for that blueprint"
      rendered `shouldSatisfy` T.isInfixOf "Pass --from VERSION."

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

-- | A second cohort member, published by a third repository, whose edge is
-- reached only through entailment.
entailedName :: ModuleName
entailedName = "kiroku-upgrade"

entailedOrigin :: ArtifactOrigin
entailedOrigin = RemoteOrigin "https://github.com/acme/kiroku" "kiroku-upgrade" Nothing

-- | Owner identities for a run that loaded only the invoked blueprint.
owners :: Text -> Maybe (ModuleName, ArtifactOrigin)
owners = ownersFrom [("payments", (blueprintName, blueprintOrigin))]

-- | Owner identities for a run that also loaded the entailed blueprint.
cohortOwners :: Text -> Maybe (ModuleName, ArtifactOrigin)
cohortOwners =
  ownersFrom
    [ ("payments", (blueprintName, blueprintOrigin)),
      ("kiroku-upgrade", (entailedName, entailedOrigin))
    ]

ownersFrom :: [(Text, (ModuleName, ArtifactOrigin))] -> Text -> Maybe (ModuleName, ArtifactOrigin)
ownersFrom table name = lookup name table

first :: BlueprintMigrationStep
first = ownedStep "payments" (migration "1.0.0" "2.0.0")

second :: BlueprintMigrationStep
second = ownedStep "payments" (migration "2.0.0" "3.0.0")

-- | An edge of another blueprint, pulled in by an edge of the invoked one.
entailedStep :: BlueprintMigrationStep
entailedStep =
  BlueprintMigrationStep
    { owner = "kiroku-upgrade",
      edge = migration "1.9.0" "2.0.0",
      entailedBy = Just (EntailmentSite "keiro-upgrade" "2.4.0" "3.0.0")
    }

ownedStep :: Text -> BlueprintMigration -> BlueprintMigrationStep
ownedStep owner edge =
  BlueprintMigrationStep {owner = owner, edge = edge, entailedBy = Nothing}

migration :: Text -> Text -> BlueprintMigration
migration fromVersion toVersion =
  migrationWithPrompt fromVersion toVersion ("Migrate from " <> fromVersion <> " to " <> toVersion)

migrationWithPrompt :: Text -> Text -> Text -> BlueprintMigration
migrationWithPrompt fromVersion toVersion instructions =
  BlueprintMigration
    { from = fromVersion,
      to = toVersion,
      prompt = instructions,
      entails = []
    }

plan :: [BlueprintMigrationStep] -> BlueprintMigrationPlan
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

-- | The receipt an inferred @--from@ is read out of.
recordedReceipt :: AppliedBlueprintMigration
recordedReceipt = receipt blueprintOrigin blueprintName "1.0.0" "2.0.0"

-- | What 'highestMigratedVersion' would hand the resolver for that receipt.
recordedResult :: Maybe (Version, AppliedBlueprintMigration)
recordedResult = Just (version "2.0.0", recordedReceipt)

-- | What a successful probe would hand the resolver.
probeResult :: Maybe (Version, Text)
probeResult = Just (version "3.0.0", "cat .library-version")

-- | A resolved window whose values are fixed so a test can vary only where
-- each end came from.
windowWith :: VersionSource -> VersionSource -> ResolvedWindow
windowWith startSource targetSource =
  ResolvedWindow
    { fromVersion = version "2.0.0",
      fromSource = startSource,
      toVersion = version "3.0.0",
      toSource = targetSource
    }

-- | Run one probe against a mocked @sh -c@ result.
runProbe :: (ExitCode, Text, Text) -> VersionProbeResult
runProbe result =
  runPureEff $
    runProcessPure
      [ProcessMock {command = "sh", args = ["-c", probeCommand], result = result}]
      (runVersionProbe probeCommand "/tmp/project")
  where
    probeCommand = "cat .library-version"

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
            migrations = [first ^. #edge, second ^. #edge],
            launch = Nothing,
            versionProbe = Nothing
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
