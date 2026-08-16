module Seihou.CLI.AgentMigrateE2ESpec (tests) where

import Control.Lens (to, (^.))
import Data.ByteString.Lazy qualified as LBS
import Data.Generics.Labels ()
import Data.Maybe (fromMaybe)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.SeihouBinary (seihouBinary)
import Seihou.Core.Types
  ( AppliedBlueprintMigration (..),
    Manifest (..),
    MigrationOutcome (..),
    ModuleName (..),
  )
import Seihou.Manifest.Types (manifestFromJSON)
import System.Directory
  ( createDirectoryIfMissing,
    doesFileExist,
    executable,
    getPermissions,
    removeDirectoryRecursive,
    setPermissions,
  )
import System.Environment (getEnvironment)
import System.Exit (ExitCode (..))
import System.FilePath (searchPathSeparator, takeDirectory, (</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (CreateProcess (..), proc, readCreateProcessWithExitCode)
import Test.Hspec
import Test.Tasty (TestTree)
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Agent migrate end-to-end" $ do
  it "exposes non-interactive blueprint runs in help" $ do
    binary <- seihouBinary
    (exitCode, output, _) <- runProcessText binary ["agent", "run", "--help"] Nothing Nothing
    exitCode `shouldBe` ExitSuccess
    output `shouldSatisfy` T.isInfixOf "--batch"
    output `shouldSatisfy` T.isInfixOf "stdin is not a terminal"

  it "automatically uses the batch CLI provider when stdin is not a terminal" $
    withSystemTempDirectory "seihou-agent-run-batch" $ \root -> do
      binary <- seihouBinary
      let blueprintDir = root </> ".seihou" </> "modules" </> "batch-blueprint"
          blueprintPath = blueprintDir </> "blueprint.dhall"
          referencePath = blueprintDir </> "files" </> "reference.md"
          manifestPath = root </> ".seihou" </> "manifest.json"
          xdgHome = root </> "xdg"
          fakeBin = root </> "bin"
          fakeClaude = fakeBin </> "claude"
          launchLog = root </> "agent-launch.args"
          workspaceFile = root </> "batch-ran.txt"
      createDirectoryIfMissing True blueprintDir
      createDirectoryIfMissing True (takeDirectory referencePath)
      createDirectoryIfMissing True xdgHome
      createDirectoryIfMissing True fakeBin
      TIO.writeFile blueprintPath batchBlueprintDhall
      TIO.writeFile referencePath "batch reference"
      TIO.writeFile
        fakeClaude
        "#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$SEIHOU_FAKE_AGENT_LOG\"\nprintf 'edited\\n' > \"$SEIHOU_FAKE_WORKSPACE_FILE\"\nprintf '%s\\n' '{\"result\":\"batch complete\",\"is_error\":false,\"session_id\":\"fake\"}'\n"
      permissions <- getPermissions fakeClaude
      -- Permissions comes from `directory` and has no Generic instance, so it
      -- has no #executable label. Record update syntax is the only option.
      setPermissions fakeClaude (permissions {executable = True})

      inherited <- getEnvironment
      let inheritedPath = fromMaybe "" (lookup "PATH" inherited)
          overriddenNames =
            [ "PATH",
              "XDG_CONFIG_HOME",
              "SEIHOU_AGENT_PROVIDER",
              "SEIHOU_AGENT_MODEL",
              "SEIHOU_CONTEXT",
              "SEIHOU_FAKE_AGENT_LOG",
              "SEIHOU_FAKE_WORKSPACE_FILE"
            ]
          environment =
            ("PATH", fakeBin <> [searchPathSeparator] <> inheritedPath)
              : ("XDG_CONFIG_HOME", xdgHome)
              : ("SEIHOU_AGENT_PROVIDER", "claude-cli")
              : ("SEIHOU_FAKE_AGENT_LOG", launchLog)
              : ("SEIHOU_FAKE_WORKSPACE_FILE", workspaceFile)
              : filter (\(key, _) -> key `notElem` overriddenNames) inherited

      (exitCode, output, errorOutput) <-
        runProcessText binary ["agent", "run", "batch-blueprint"] (Just root) (Just environment)
      case exitCode of
        ExitSuccess -> pure ()
        ExitFailure code ->
          expectationFailure $
            "batch run exited "
              <> show code
              <> "\nstdout:\n"
              <> T.unpack output
              <> "\nstderr:\n"
              <> T.unpack errorOutput
      output `shouldSatisfy` T.isInfixOf "batch complete"
      doesFileExist workspaceFile `shouldReturn` True
      doesFileExist manifestPath `shouldReturn` True
      launchArgs <- T.lines <$> TIO.readFile launchLog
      launchArgs `shouldSatisfy` elem "-p"
      launchArgs `shouldSatisfy` elem "--allowedTools"
      launchArgs `shouldSatisfy` elem "--add-dir"
      launchArgs `shouldSatisfy` elem (T.pack (blueprintDir </> "files"))

  -- The two cases below are the end-to-end proof that a blueprint's own launch
  -- declaration reaches the spawned agent process, rather than only reaching
  -- seihou's internal accounting. They read back the argv the fake `claude`
  -- script was called with.
  it "applies a blueprint-declared model and effort to the launched agent" $
    withDeclaredLaunchBlueprint $ \root blueprintName runDeclared -> do
      (exitCode, output, errorOutput, launchArgs) <- runDeclared []
      expectSuccess "declared launch run" exitCode output errorOutput
      output `shouldSatisfy` T.isInfixOf "declared complete"
      launchArgs `shouldSatisfy` elem "--model"
      launchArgs `shouldSatisfy` elem "claude-sonnet-5"
      launchArgs `shouldSatisfy` elem "--effort"
      launchArgs `shouldSatisfy` elem "max"
      -- Sanity: nothing in the environment or config supplied these; they came
      -- from the blueprint, whose directory is under this temp root.
      root `shouldSatisfy` (not . null)
      blueprintName `shouldBe` "declared-launch"

  it "lets a --model flag override the blueprint declaration" $
    withDeclaredLaunchBlueprint $ \_ _ runDeclared -> do
      (exitCode, output, errorOutput, launchArgs) <- runDeclared ["--model", "claude-opus-4-8"]
      expectSuccess "flag override run" exitCode output errorOutput
      launchArgs `shouldSatisfy` elem "claude-opus-4-8"
      launchArgs `shouldNotSatisfy` elem "claude-sonnet-5"
      -- Only the field the flag names moves; effort still comes from the
      -- blueprint.
      launchArgs `shouldSatisfy` elem "--effort"
      launchArgs `shouldSatisfy` elem "max"

  it "exposes an optional version window and the rerun option in help" $ do
    binary <- seihouBinary
    (exitCode, output, _) <- runProcessText binary ["agent", "migrate", "--help"] Nothing Nothing
    exitCode `shouldBe` ExitSuccess
    output `shouldSatisfy` T.isInfixOf "Usage: seihou agent migrate BLUEPRINT [--from VERSION] [--to VERSION] [PROMPT]"
    output `shouldSatisfy` T.isInfixOf "--rerun"
    output `shouldNotSatisfy` T.isInfixOf "--no-baseline"
    output `shouldNotSatisfy` T.isInfixOf "--force"

  it "renders gap-tolerant pending prompts in order without writing a receipt" $
    withSystemTempDirectory "seihou-agent-migrate-debug" $ \root -> do
      binary <- seihouBinary
      let blueprintDir = root </> ".seihou" </> "modules" </> "payments"
          blueprintPath = blueprintDir </> "blueprint.dhall"
          manifestPath = root </> ".seihou" </> "manifest.json"
          xdgHome = root </> "xdg"
      createDirectoryIfMissing True blueprintDir
      createDirectoryIfMissing True xdgHome
      TIO.writeFile blueprintPath migrationBlueprintDhall
      inherited <- getEnvironment
      let overriddenNames = ["XDG_CONFIG_HOME", "SEIHOU_AGENT_PROVIDER", "SEIHOU_AGENT_MODEL", "SEIHOU_CONTEXT"]
          environment =
            ("XDG_CONFIG_HOME", xdgHome)
              : ("SEIHOU_AGENT_PROVIDER", "claude-cli")
              : filter (\(key, _) -> key `notElem` overriddenNames) inherited
      (exitCode, output, errorOutput) <-
        runProcessText
          binary
          [ "agent",
            "--debug",
            "migrate",
            "payments",
            "--from",
            "1.0.0",
            "--to",
            "3.0.0",
            "--var",
            "library.name=baikai"
          ]
          (Just root)
          (Just environment)
      case exitCode of
        ExitSuccess -> pure ()
        ExitFailure code ->
          expectationFailure $
            "debug migration exited "
              <> show code
              <> "\nstdout:\n"
              <> T.unpack output
              <> "\nstderr:\n"
              <> T.unpack errorOutput
      output `shouldSatisfy` T.isInfixOf "Blueprint migrations for payments: 1.0.0 -> 3.0.0"
      output `shouldSatisfy` T.isInfixOf "===== [1/2] payments 1.0.0 -> 2.0.0 ====="
      output `shouldSatisfy` T.isInfixOf "===== [2/2] payments 2.5.0 -> 3.0.0 ====="
      output `shouldSatisfy` T.isInfixOf "Shared upgrade guidance for baikai."
      output `shouldSatisfy` T.isInfixOf "Replace baikai legacy calls."
      let (_, afterFirst) = T.breakOn "1.0.0 -> 2.0.0" output
          (_, afterSecond) = T.breakOn "2.5.0 -> 3.0.0" afterFirst
      afterFirst `shouldNotBe` ""
      afterSecond `shouldNotBe` ""
      doesFileExist manifestPath `shouldReturn` False

  it "records successful edges and skips them on the next invocation" $
    withSystemTempDirectory "seihou-agent-migrate-receipts" $ \root -> do
      binary <- seihouBinary
      let blueprintDir = root </> ".seihou" </> "modules" </> "payments"
          blueprintPath = blueprintDir </> "blueprint.dhall"
          manifestPath = root </> ".seihou" </> "manifest.json"
          xdgHome = root </> "xdg"
          fakeBin = root </> "bin"
          fakeClaude = fakeBin </> "claude"
          launchLog = root </> "agent-launches.log"
      createDirectoryIfMissing True blueprintDir
      createDirectoryIfMissing True xdgHome
      createDirectoryIfMissing True fakeBin
      TIO.writeFile blueprintPath migrationBlueprintDhall
      TIO.writeFile fakeClaude "#!/bin/sh\nprintf 'called\\n' >> \"$SEIHOU_FAKE_AGENT_LOG\"\nexit 0\n"
      permissions <- getPermissions fakeClaude
      -- Permissions comes from `directory` and has no Generic instance, so it
      -- has no #executable label. Record update syntax is the only option.
      setPermissions fakeClaude (permissions {executable = True})

      inherited <- getEnvironment
      let inheritedPath = fromMaybe "" (lookup "PATH" inherited)
          overriddenNames = ["PATH", "XDG_CONFIG_HOME", "SEIHOU_AGENT_PROVIDER", "SEIHOU_AGENT_MODEL", "SEIHOU_CONTEXT", "SEIHOU_FAKE_AGENT_LOG"]
          environment =
            ("PATH", fakeBin <> [searchPathSeparator] <> inheritedPath)
              : ("XDG_CONFIG_HOME", xdgHome)
              : ("SEIHOU_AGENT_PROVIDER", "claude-cli")
              : ("SEIHOU_FAKE_AGENT_LOG", launchLog)
              : filter (\(key, _) -> key `notElem` overriddenNames) inherited
          args =
            [ "agent",
              "migrate",
              "payments",
              "--from",
              "1.0.0",
              "--to",
              "3.0.0",
              "--var",
              "library.name=baikai"
            ]

      (firstExit, _, firstError) <- runProcessText binary args (Just root) (Just environment)
      case firstExit of
        ExitSuccess -> pure ()
        ExitFailure code -> expectationFailure ("migration exited " <> show code <> "\nstderr:\n" <> T.unpack firstError)
      T.lines <$> TIO.readFile launchLog `shouldReturn` ["called", "called"]
      beforeResume <- LBS.readFile manifestPath
      manifest <-
        case manifestFromJSON beforeResume of
          Left err -> expectationFailure err >> fail "unreachable"
          Right decoded -> pure decoded
      map (\receipt -> (receipt ^. #fromVersion, receipt ^. #toVersion)) (manifest ^. #blueprintMigrations)
        `shouldBe` [("1.0.0", "2.0.0"), ("2.5.0", "3.0.0")]

      (resumeExit, resumeOutput, resumeError) <- runProcessText binary args (Just root) (Just environment)
      case resumeExit of
        ExitSuccess -> pure ()
        ExitFailure code -> expectationFailure ("resume exited " <> show code <> "\nstderr:\n" <> T.unpack resumeError)
      resumeOutput `shouldSatisfy` T.isInfixOf "already have receipts"
      T.lines <$> TIO.readFile launchLog `shouldReturn` ["called", "called"]
      LBS.readFile manifestPath `shouldReturn` beforeResume

  -- The IR-1 scenario end to end: an edge whose precondition is unmet writes
  -- the signal file, the chain continues past it, and the edge runs again once
  -- the signal is no longer written -- without --rerun, which is the whole
  -- point. Before this outcome existed the first edge was skipped forever.
  it "continues past a not-applicable edge and replans it on the next invocation" $
    withSystemTempDirectory "seihou-agent-migrate-not-applicable" $ \root -> do
      binary <- seihouBinary
      let blueprintDir = root </> ".seihou" </> "modules" </> "payments"
          blueprintPath = blueprintDir </> "blueprint.dhall"
          manifestPath = root </> ".seihou" </> "manifest.json"
          signalPath = root </> ".seihou" </> ".migrate-signal"
          xdgHome = root </> "xdg"
          fakeBin = root </> "bin"
          fakeClaude = fakeBin </> "claude"
          launchLog = root </> "agent-launches.log"
          reason = "no docs/adr directory in this project"
      createDirectoryIfMissing True blueprintDir
      createDirectoryIfMissing True xdgHome
      createDirectoryIfMissing True fakeBin
      TIO.writeFile blueprintPath migrationBlueprintDhall
      -- Signals inapplicability on its very first launch only, so the same
      -- edge applies for real when it is replanned.
      TIO.writeFile
        fakeClaude
        "#!/bin/sh\nprintf 'called\\n' >> \"$SEIHOU_FAKE_AGENT_LOG\"\nif [ \"$(wc -l < \"$SEIHOU_FAKE_AGENT_LOG\" | tr -d ' ')\" = \"1\" ]; then\n  printf '%s\\n' \"$SEIHOU_FAKE_SIGNAL_REASON\" > \"$SEIHOU_FAKE_SIGNAL_FILE\"\nfi\nexit 0\n"
      permissions <- getPermissions fakeClaude
      -- Permissions comes from `directory` and has no Generic instance, so it
      -- has no #executable label. Record update syntax is the only option.
      setPermissions fakeClaude (permissions {executable = True})

      inherited <- getEnvironment
      let inheritedPath = fromMaybe "" (lookup "PATH" inherited)
          overriddenNames =
            [ "PATH",
              "XDG_CONFIG_HOME",
              "SEIHOU_AGENT_PROVIDER",
              "SEIHOU_AGENT_MODEL",
              "SEIHOU_CONTEXT",
              "SEIHOU_FAKE_AGENT_LOG",
              "SEIHOU_FAKE_SIGNAL_FILE",
              "SEIHOU_FAKE_SIGNAL_REASON"
            ]
          environment =
            ("PATH", fakeBin <> [searchPathSeparator] <> inheritedPath)
              : ("XDG_CONFIG_HOME", xdgHome)
              : ("SEIHOU_AGENT_PROVIDER", "claude-cli")
              : ("SEIHOU_FAKE_AGENT_LOG", launchLog)
              : ("SEIHOU_FAKE_SIGNAL_FILE", signalPath)
              : ("SEIHOU_FAKE_SIGNAL_REASON", T.unpack reason)
              : filter (\(key, _) -> key `notElem` overriddenNames) inherited
          args =
            [ "agent",
              "migrate",
              "payments",
              "--from",
              "1.0.0",
              "--to",
              "3.0.0",
              "--var",
              "library.name=baikai"
            ]

      (firstExit, firstOutput, firstError) <- runProcessText binary args (Just root) (Just environment)
      expectSuccess "not-applicable migration" firstExit firstOutput firstError
      firstOutput `shouldSatisfy` T.isInfixOf ("not applicable: " <> reason)
      firstOutput `shouldSatisfy` T.isInfixOf "Completed 2 blueprint migration(s) for 'payments' (1 not applicable)."
      -- Both edges launched: an inapplicable edge does not halt the chain.
      T.lines <$> TIO.readFile launchLog `shouldReturn` ["called", "called"]
      -- The signal is transient state, consumed by the run that read it.
      doesFileExist signalPath `shouldReturn` False

      afterFirst <- readReceipts manifestPath
      afterFirst
        `shouldBe` [ ("1.0.0", "2.0.0", MigrationNotApplicable reason),
                     ("2.5.0", "3.0.0", MigrationApplied)
                   ]

      -- No --rerun. The not-applicable edge is pending again; the applied one
      -- is not.
      (resumeExit, resumeOutput, resumeError) <- runProcessText binary args (Just root) (Just environment)
      expectSuccess "replanned migration" resumeExit resumeOutput resumeError
      resumeOutput `shouldSatisfy` T.isInfixOf "Running blueprint migration 1/1: payments 1.0.0 -> 2.0.0"
      resumeOutput `shouldNotSatisfy` T.isInfixOf "2.5.0 -> 3.0.0"
      resumeOutput `shouldNotSatisfy` T.isInfixOf "not applicable"
      T.lines <$> TIO.readFile launchLog `shouldReturn` ["called", "called", "called"]

      -- The replanned edge replaces its own receipt rather than adding one.
      afterResume <- readReceipts manifestPath
      afterResume
        `shouldBe` [ ("1.0.0", "2.0.0", MigrationApplied),
                     ("2.5.0", "3.0.0", MigrationApplied)
                   ]

      (settledExit, settledOutput, settledError) <- runProcessText binary args (Just root) (Just environment)
      expectSuccess "settled migration" settledExit settledOutput settledError
      settledOutput `shouldSatisfy` T.isInfixOf "already have receipts"
      T.lines <$> TIO.readFile launchLog `shouldReturn` ["called", "called", "called"]

  -- The cohort story end to end. A keiro edge entails a kiroku edge; one
  -- command plans both, in order, each carrying its own blueprint's reference
  -- files. --debug is the ideal surface: it exercises discovery, expansion, and
  -- per-blueprint preparation while contacting no provider and writing nothing.
  it "expands an entailed edge into the chain with its own blueprint's context" $
    withCohortProject $ \root run -> do
      (exitCode, output, errorOutput) <-
        run ["agent", "--debug", "migrate", "keiro-upgrade", "--from", "2.4.0", "--to", "3.0.0"]
      expectSuccess "cohort debug migration" exitCode output errorOutput
      output `shouldSatisfy` T.isInfixOf "Blueprint migrations for keiro-upgrade: 2.4.0 -> 3.0.0"
      output
        `shouldSatisfy` T.isInfixOf
          "===== [1/2] kiroku-upgrade 1.9.0 -> 2.0.0 (entailed by keiro-upgrade 2.4.0 -> 3.0.0) ====="
      output `shouldSatisfy` T.isInfixOf "===== [2/2] keiro-upgrade 2.4.0 -> 3.0.0 ====="

      -- The entailed edge comes first, which is the ordering rule.
      let (beforeKiroku, fromKiroku) = T.breakOn "kiroku-upgrade 1.9.0 -> 2.0.0" output
          (_, fromKeiro) = T.breakOn "===== [2/2]" fromKiroku
      beforeKiroku `shouldSatisfy` (not . T.isInfixOf "===== [2/2]")
      fromKeiro `shouldNotBe` ""

      -- Each step got its own blueprint's shared prompt, edge prompt, and
      -- reference-file listing. The marker files are the proof that `files/`
      -- was read from the owning blueprint's directory, not the invoked one's.
      let kirokuStep = T.take (T.length fromKiroku - T.length fromKeiro) fromKiroku
      kirokuStep `shouldSatisfy` T.isInfixOf "Shared kiroku guidance."
      kirokuStep `shouldSatisfy` T.isInfixOf "Drop the removed kiroku API."
      kirokuStep `shouldSatisfy` T.isInfixOf "kiroku-marker.md"
      kirokuStep `shouldNotSatisfy` T.isInfixOf "keiro-marker.md"
      kirokuStep
        `shouldSatisfy` T.isInfixOf "It is required by keiro-upgrade 2.4.0 -> 3.0.0"
      fromKeiro `shouldSatisfy` T.isInfixOf "Shared keiro guidance."
      fromKeiro `shouldSatisfy` T.isInfixOf "keiro-marker.md"
      fromKeiro `shouldNotSatisfy` T.isInfixOf "kiroku-marker.md"

      doesFileExist (root </> ".seihou" </> "manifest.json") `shouldReturn` False

  -- The decisive property. A project that crossed the shared kiroku edge by
  -- running keiro-upgrade does not cross it again by running kiroku-upgrade,
  -- because the receipt was written under kiroku-upgrade's own identity.
  it "crosses a shared cohort edge once regardless of entry point" $
    withCohortProject $ \root run -> do
      (exitCode, output, errorOutput) <-
        run ["agent", "migrate", "keiro-upgrade", "--from", "2.4.0", "--to", "3.0.0"]
      expectSuccess "cohort migration" exitCode output errorOutput
      output `shouldSatisfy` T.isInfixOf "Running blueprint migration 1/2: kiroku-upgrade 1.9.0 -> 2.0.0"
      output `shouldSatisfy` T.isInfixOf "Running blueprint migration 2/2: keiro-upgrade 2.4.0 -> 3.0.0"

      -- The kiroku receipt is filed under kiroku-upgrade, not keiro-upgrade.
      bytes <- LBS.readFile (root </> ".seihou" </> "manifest.json")
      manifest <- case manifestFromJSON bytes of
        Left err -> expectationFailure err >> fail "unreachable"
        Right decoded -> pure decoded
      [ (receipt ^. #name . #unModuleName, receipt ^. #fromVersion, receipt ^. #toVersion)
        | receipt <- manifest ^. #blueprintMigrations
        ]
        `shouldBe` [ ("kiroku-upgrade", "1.9.0", "2.0.0"),
                     ("keiro-upgrade", "2.4.0", "3.0.0")
                   ]

      -- Running the entailed blueprint directly finds that receipt.
      (kirokuExit, kirokuOutput, kirokuError) <-
        run ["agent", "migrate", "kiroku-upgrade", "--from", "1.9.0", "--to", "2.0.0"]
      expectSuccess "direct kiroku migration" kirokuExit kirokuOutput kirokuError
      kirokuOutput `shouldSatisfy` T.isInfixOf "already have receipts"

  -- Skipping an uninstalled cohort member would leave a half-migrated project
  -- with no signal, because the consumer never named that library.
  it "refuses when an entailed blueprint is not installed" $
    withCohortProject $ \root run -> do
      removeDirectoryRecursive (root </> ".seihou" </> "modules" </> "kiroku-upgrade")
      (exitCode, output, errorOutput) <-
        run ["agent", "--debug", "migrate", "keiro-upgrade", "--from", "2.4.0", "--to", "3.0.0"]
      exitCode `shouldSatisfy` (/= ExitSuccess)
      let streams = output <> errorOutput
      streams
        `shouldSatisfy` T.isInfixOf
          "'keiro-upgrade' edge 2.4.0 -> 3.0.0 entails blueprint 'kiroku-upgrade', which is not installed"
      streams `shouldSatisfy` T.isInfixOf "seihou install <url> --module kiroku-upgrade"

  -- Entailment names one exact edge; the likeliest authoring mistake is an
  -- off-by-one in a version string, so the real list is printed.
  it "refuses when the entailed blueprint declares no such edge, listing what it does" $
    withCohortProject $ \root run -> do
      TIO.writeFile
        (root </> ".seihou" </> "modules" </> "kiroku-upgrade" </> "blueprint.dhall")
        (kirokuBlueprintDhall "1.8.0")
      (exitCode, output, errorOutput) <-
        run ["agent", "--debug", "migrate", "keiro-upgrade", "--from", "2.4.0", "--to", "3.0.0"]
      exitCode `shouldSatisfy` (/= ExitSuccess)
      let streams = output <> errorOutput
      streams
        `shouldSatisfy` T.isInfixOf
          "'keiro-upgrade' edge 2.4.0 -> 3.0.0 entails edge 1.9.0 -> 2.0.0 of 'kiroku-upgrade', which declares no such edge"
      streams `shouldSatisfy` T.isInfixOf "Declared edges of 'kiroku-upgrade': 1.8.0 -> 2.0.0"

  -- A consumer of the entailed library alone is untouched by the existence of
  -- the blueprint that entails it.
  it "leaves a direct consumer of the entailed blueprint alone" $
    withCohortProject $ \_ run -> do
      (exitCode, output, errorOutput) <-
        run ["agent", "--debug", "migrate", "kiroku-upgrade", "--from", "1.9.0", "--to", "2.0.0"]
      expectSuccess "direct kiroku debug migration" exitCode output errorOutput
      output `shouldSatisfy` T.isInfixOf "===== [1/1] kiroku-upgrade 1.9.0 -> 2.0.0 ====="
      output `shouldNotSatisfy` T.isInfixOf "keiro"

  -- The point of the whole plan: the command a user types is `seihou agent
  -- migrate my-library`, and it does the right thing. The probe reads a file
  -- so the test can move the "installed version" around, exactly as bumping a
  -- lockfile would.
  it "infers --to from the probe and --from from the receipt ledger" $
    withProbeProject $ \root run -> do
      TIO.writeFile (root </> ".library-version") "2.0.0\n"

      -- First run: --from is typed because nothing has been recorded yet, and
      -- --to comes from the probe. Only the inferred end is reported.
      (firstExit, firstOutput, firstError) <-
        run ["agent", "migrate", "probe-upgrade", "--from", "1.0.0"]
      expectSuccess "probe-inferred target" firstExit firstOutput firstError
      firstOutput `shouldSatisfy` T.isInfixOf "Version window: 1.0.0 -> 2.0.0"
      firstOutput `shouldSatisfy` T.isInfixOf "--to   2.0.0  [probe: cat .library-version]"
      firstOutput `shouldNotSatisfy` T.isInfixOf "--from 1.0.0"
      firstOutput `shouldSatisfy` T.isInfixOf "Running blueprint migration 1/1: probe-upgrade 1.0.0 -> 2.0.0"

      -- Bump the dependency and run with no flags at all. The window starts
      -- where the last run finished and ends where the project now points.
      TIO.writeFile (root </> ".library-version") "3.0.0\n"
      (secondExit, secondOutput, secondError) <-
        run ["agent", "--debug", "migrate", "probe-upgrade"]
      expectSuccess "fully inferred window" secondExit secondOutput secondError
      secondOutput `shouldSatisfy` T.isInfixOf "Version window: 2.0.0 -> 3.0.0"
      secondOutput
        `shouldSatisfy` T.isInfixOf "--from 2.0.0  [receipt: probe-upgrade 1.0.0 -> 2.0.0, applied "
      secondOutput `shouldSatisfy` T.isInfixOf "--to   3.0.0  [probe: cat .library-version]"
      secondOutput `shouldSatisfy` T.isInfixOf "===== [1/1] probe-upgrade 2.0.0 -> 3.0.0 ====="

  -- Explicit flags win over both sources, and a run that names them keeps
  -- printing exactly what it printed before this feature existed.
  it "lets explicit flags override the probe and the ledger silently" $
    withProbeProject $ \root run -> do
      TIO.writeFile (root </> ".library-version") "2.0.0\n"
      (exitCode, output, errorOutput) <-
        run ["agent", "--debug", "migrate", "probe-upgrade", "--from", "1.0.0", "--to", "3.0.0"]
      expectSuccess "explicit window" exitCode output errorOutput
      output `shouldNotSatisfy` T.isInfixOf "Version window:"
      output `shouldSatisfy` T.isInfixOf "===== [1/2] probe-upgrade 1.0.0 -> 2.0.0 ====="
      output `shouldSatisfy` T.isInfixOf "===== [2/2] probe-upgrade 2.0.0 -> 3.0.0 ====="

      -- --verbose is where a user who typed both flags can still see them
      -- accounted for.
      (verboseExit, verboseOutput, verboseError) <-
        run ["agent", "--debug", "migrate", "probe-upgrade", "--from", "1.0.0", "--to", "3.0.0", "--verbose"]
      expectSuccess "explicit window, verbose" verboseExit verboseOutput verboseError
      verboseOutput `shouldSatisfy` T.isInfixOf "--from 1.0.0  [flag]"
      verboseOutput `shouldSatisfy` T.isInfixOf "--to   3.0.0  [flag]"

  -- A broken probe is the author's mistake and the consumer's problem, so it
  -- degrades to requiring --to rather than failing a command the user can
  -- still complete by hand.
  it "degrades to requiring --to when the probe fails" $
    withProbeProject $ \_ run -> do
      (exitCode, output, errorOutput) <-
        run ["agent", "--debug", "migrate", "probe-upgrade", "--from", "1.0.0"]
      exitCode `shouldSatisfy` (/= ExitSuccess)
      let streams = output <> errorOutput
      streams `shouldSatisfy` T.isInfixOf "version probe failed"
      streams `shouldSatisfy` T.isInfixOf "probe:  cat .library-version"
      streams `shouldSatisfy` T.isInfixOf "No such file"
      streams `shouldSatisfy` T.isInfixOf "Cannot determine the target version for 'probe-upgrade'."
      streams `shouldSatisfy` T.isInfixOf "Pass --to VERSION"

      -- The escape hatch works despite the broken probe.
      (withFlag, flagOutput, flagError) <-
        run ["agent", "--debug", "migrate", "probe-upgrade", "--from", "1.0.0", "--to", "2.0.0"]
      expectSuccess "explicit target despite broken probe" withFlag flagOutput flagError
      flagOutput `shouldSatisfy` T.isInfixOf "===== [1/1] probe-upgrade 1.0.0 -> 2.0.0 ====="

  -- The first-run case, which will be the commonest failure by far. It has to
  -- read as an explanation of what seihou cannot know.
  it "explains a missing start version when nothing has been recorded" $
    withProbeProject $ \root run -> do
      TIO.writeFile (root </> ".library-version") "3.0.0\n"
      (exitCode, output, errorOutput) <- run ["agent", "--debug", "migrate", "probe-upgrade"]
      exitCode `shouldSatisfy` (/= ExitSuccess)
      let streams = output <> errorOutput
      streams `shouldSatisfy` T.isInfixOf "Cannot determine the starting version for 'probe-upgrade'."
      streams `shouldSatisfy` T.isInfixOf "no recorded migration for that blueprint"
      streams `shouldSatisfy` T.isInfixOf "Pass --from VERSION."

  -- Blueprints published before versionProbe existed must be unaffected: both
  -- flags still work, and omitting --to gives the actionable refusal rather
  -- than a decoding failure.
  it "leaves a blueprint without a probe working exactly as before" $
    withSystemTempDirectory "seihou-agent-migrate-noprobe" $ \root -> do
      binary <- seihouBinary
      let blueprintDir = root </> ".seihou" </> "modules" </> "payments"
          xdgHome = root </> "xdg"
      createDirectoryIfMissing True blueprintDir
      createDirectoryIfMissing True xdgHome
      TIO.writeFile (blueprintDir </> "blueprint.dhall") migrationBlueprintDhall
      inherited <- getEnvironment
      let overriddenNames = ["XDG_CONFIG_HOME", "SEIHOU_AGENT_PROVIDER", "SEIHOU_AGENT_MODEL", "SEIHOU_CONTEXT"]
          environment =
            ("XDG_CONFIG_HOME", xdgHome)
              : ("SEIHOU_AGENT_PROVIDER", "claude-cli")
              : filter (\(key, _) -> key `notElem` overriddenNames) inherited
          run args = runProcessText binary args (Just root) (Just environment)

      (exitCode, output, errorOutput) <-
        run ["agent", "--debug", "migrate", "payments", "--from", "1.0.0", "--to", "3.0.0", "--var", "library.name=baikai"]
      expectSuccess "probe-less blueprint" exitCode output errorOutput
      output `shouldSatisfy` T.isInfixOf "Blueprint migrations for payments: 1.0.0 -> 3.0.0"
      output `shouldNotSatisfy` T.isInfixOf "Version window:"

      (bareExit, bareOutput, bareError) <-
        run ["agent", "--debug", "migrate", "payments", "--from", "1.0.0", "--var", "library.name=baikai"]
      bareExit `shouldSatisfy` (/= ExitSuccess)
      (bareOutput <> bareError) `shouldSatisfy` T.isInfixOf "Cannot determine the target version for 'payments'."

-- | A scratch project holding one blueprint whose version probe reads
-- @.library-version@ from the project root, plus a fake @claude@ that always
-- succeeds. The probe file is deliberately absent until a test writes it, so
-- the broken-probe case needs no extra setup.
withProbeProject ::
  (FilePath -> ([String] -> IO (ExitCode, T.Text, T.Text)) -> IO a) ->
  IO a
withProbeProject action =
  withSystemTempDirectory "seihou-agent-migrate-probe" $ \root -> do
    binary <- seihouBinary
    let blueprintDir = root </> ".seihou" </> "modules" </> "probe-upgrade"
        xdgHome = root </> "xdg"
        fakeBin = root </> "bin"
        fakeClaude = fakeBin </> "claude"
    createDirectoryIfMissing True blueprintDir
    createDirectoryIfMissing True xdgHome
    createDirectoryIfMissing True fakeBin
    TIO.writeFile (blueprintDir </> "blueprint.dhall") probeBlueprintDhall
    TIO.writeFile fakeClaude "#!/bin/sh\nexit 0\n"
    permissions <- getPermissions fakeClaude
    -- Permissions comes from `directory` and has no Generic instance, so it
    -- has no #executable label. Record update syntax is the only option.
    setPermissions fakeClaude (permissions {executable = True})

    inherited <- getEnvironment
    let inheritedPath = fromMaybe "" (lookup "PATH" inherited)
        overriddenNames =
          [ "PATH",
            "XDG_CONFIG_HOME",
            "SEIHOU_AGENT_PROVIDER",
            "SEIHOU_AGENT_MODEL",
            "SEIHOU_AGENT_EFFORT",
            "SEIHOU_CONTEXT"
          ]
        environment =
          ("PATH", fakeBin <> [searchPathSeparator] <> inheritedPath)
            : ("XDG_CONFIG_HOME", xdgHome)
            : ("SEIHOU_AGENT_PROVIDER", "claude-cli")
            : filter (\(key, _) -> key `notElem` overriddenNames) inherited
        run args = runProcessText binary args (Just root) (Just environment)
    action root run

-- | A blueprint declaring two consecutive edges and a file-backed version
-- probe, so a test can move the "installed version" the way bumping a
-- lockfile would.
probeBlueprintDhall :: T.Text
probeBlueprintDhall =
  T.unlines
    [ "{ name = \"probe-upgrade\"",
      ", version = Some \"3.0.0\"",
      ", description = Some \"probe fixture\"",
      ", prompt = \"Shared probe guidance.\"",
      ", vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }",
      ", prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }",
      ", baseModules = [] : List { module : Text, vars : List { name : Text, value : Text } }",
      ", files = [] : List { src : Text, description : Optional Text }",
      ", allowedTools = None (List Text)",
      ", tags = [] : List Text",
      ", migrations =",
      "  [ { from = \"1.0.0\", to = \"2.0.0\", prompt = \"First probe edge.\" }",
      "  , { from = \"2.0.0\", to = \"3.0.0\", prompt = \"Second probe edge.\" }",
      "  ]",
      ", versionProbe = Some \"cat .library-version\"",
      "}"
    ]

-- | A scratch project with both cohort blueprints installed, a fake @claude@
-- first on @PATH@ that always succeeds, and a scrubbed environment. The
-- callback receives the project root and a runner for @seihou@ arguments.
withCohortProject ::
  (FilePath -> ([String] -> IO (ExitCode, T.Text, T.Text)) -> IO a) ->
  IO a
withCohortProject action =
  withSystemTempDirectory "seihou-agent-migrate-cohort" $ \root -> do
    binary <- seihouBinary
    let modulesDir = root </> ".seihou" </> "modules"
        kirokuDir = modulesDir </> "kiroku-upgrade"
        keiroDir = modulesDir </> "keiro-upgrade"
        xdgHome = root </> "xdg"
        fakeBin = root </> "bin"
        fakeClaude = fakeBin </> "claude"
    createDirectoryIfMissing True (kirokuDir </> "files")
    createDirectoryIfMissing True (keiroDir </> "files")
    createDirectoryIfMissing True xdgHome
    createDirectoryIfMissing True fakeBin
    TIO.writeFile (kirokuDir </> "blueprint.dhall") (kirokuBlueprintDhall "1.9.0")
    TIO.writeFile (keiroDir </> "blueprint.dhall") keiroBlueprintDhall
    -- Distinctive markers, so each rendered step's reference-file listing
    -- proves which blueprint's files/ directory it was built from.
    TIO.writeFile (kirokuDir </> "files" </> "kiroku-marker.md") "kiroku reference"
    TIO.writeFile (keiroDir </> "files" </> "keiro-marker.md") "keiro reference"
    TIO.writeFile fakeClaude "#!/bin/sh\nexit 0\n"
    permissions <- getPermissions fakeClaude
    -- Permissions comes from `directory` and has no Generic instance, so it
    -- has no #executable label. Record update syntax is the only option.
    setPermissions fakeClaude (permissions {executable = True})

    inherited <- getEnvironment
    let inheritedPath = fromMaybe "" (lookup "PATH" inherited)
        overriddenNames =
          [ "PATH",
            "XDG_CONFIG_HOME",
            "SEIHOU_AGENT_PROVIDER",
            "SEIHOU_AGENT_MODEL",
            "SEIHOU_AGENT_EFFORT",
            "SEIHOU_CONTEXT"
          ]
        environment =
          ("PATH", fakeBin <> [searchPathSeparator] <> inheritedPath)
            : ("XDG_CONFIG_HOME", xdgHome)
            : ("SEIHOU_AGENT_PROVIDER", "claude-cli")
            : filter (\(key, _) -> key `notElem` overriddenNames) inherited
        run args = runProcessText binary args (Just root) (Just environment)
    action root run

-- | The entailed blueprint. Its edge's start version is a parameter so a test
-- can move it and make the declaring blueprint's reference dangle.
kirokuBlueprintDhall :: T.Text -> T.Text
kirokuBlueprintDhall edgeFrom =
  T.unlines
    [ "{ name = \"kiroku-upgrade\"",
      ", version = Some \"2.0.0\"",
      ", description = Some \"kiroku upgrade\"",
      ", prompt = \"Shared kiroku guidance.\"",
      ", vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }",
      ", prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }",
      ", baseModules = [] : List { module : Text, vars : List { name : Text, value : Text } }",
      ", files = [ { src = \"kiroku-marker.md\", description = Some \"kiroku reference\" } ]",
      ", allowedTools = None (List Text)",
      ", tags = [] : List Text",
      ", migrations =",
      "  [ { from = \"" <> edgeFrom <> "\"",
      "    , to = \"2.0.0\"",
      "    , prompt = \"Drop the removed kiroku API.\"",
      "    , entails = [] : List { blueprint : Text, from : Text, to : Text }",
      "    }",
      "  ]",
      "}"
    ]

-- | The declaring blueprint, whose only edge entails kiroku's.
keiroBlueprintDhall :: T.Text
keiroBlueprintDhall =
  T.unlines
    [ "{ name = \"keiro-upgrade\"",
      ", version = Some \"3.0.0\"",
      ", description = Some \"keiro upgrade\"",
      ", prompt = \"Shared keiro guidance.\"",
      ", vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }",
      ", prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }",
      ", baseModules = [] : List { module : Text, vars : List { name : Text, value : Text } }",
      ", files = [ { src = \"keiro-marker.md\", description = Some \"keiro reference\" } ]",
      ", allowedTools = None (List Text)",
      ", tags = [] : List Text",
      ", migrations =",
      "  [ { from = \"2.4.0\"",
      "    , to = \"3.0.0\"",
      "    , prompt = \"Adopt the new keiro wrapper.\"",
      "    , entails =",
      "      [ { blueprint = \"kiroku-upgrade\", from = \"1.9.0\", to = \"2.0.0\" } ]",
      "    }",
      "  ]",
      "}"
    ]

-- | The recorded edge windows and outcomes, in ledger order.
readReceipts :: FilePath -> IO [(T.Text, T.Text, MigrationOutcome)]
readReceipts manifestPath = do
  bytes <- LBS.readFile manifestPath
  case manifestFromJSON bytes of
    Left err -> expectationFailure err >> fail "unreachable"
    Right manifest ->
      pure
        [ (receipt ^. #fromVersion, receipt ^. #toVersion, receipt ^. #outcome)
        | receipt <- manifest ^. #blueprintMigrations
        ]

runProcessText ::
  FilePath ->
  [String] ->
  Maybe FilePath ->
  Maybe [(String, String)] ->
  IO (ExitCode, T.Text, T.Text)
runProcessText binary args workingDirectory environment = do
  let command = (proc binary args) {cwd = workingDirectory, env = environment}
  (exitCode, stdoutText, stderrText) <- readCreateProcessWithExitCode command ""
  pure (exitCode, T.pack stdoutText, T.pack stderrText)

-- | Fail with the captured streams when a run that was expected to succeed
-- did not.
expectSuccess :: String -> ExitCode -> T.Text -> T.Text -> Expectation
expectSuccess label exitCode output errorOutput = case exitCode of
  ExitSuccess -> pure ()
  ExitFailure code ->
    expectationFailure $
      label
        <> " exited "
        <> show code
        <> "\nstdout:\n"
        <> T.unpack output
        <> "\nstderr:\n"
        <> T.unpack errorOutput

-- | Stand up a scratch project holding a blueprint that declares a model and
-- an effort, with a fake @claude@ first on @PATH@ that records its argv, an
-- empty @XDG_CONFIG_HOME@ so no real user config leaks in, and every
-- @SEIHOU_AGENT_*@ variable scrubbed from the inherited environment. Nothing
-- outside the blueprint supplies a model or effort, so whatever reaches the
-- recorded argv came from the declaration.
--
-- The callback receives the project root, the blueprint's name, and a runner
-- that takes extra @seihou agent run@ arguments and returns the exit code, the
-- two output streams, and the recorded argv lines.
withDeclaredLaunchBlueprint ::
  (FilePath -> T.Text -> ([String] -> IO (ExitCode, T.Text, T.Text, [T.Text])) -> IO a) ->
  IO a
withDeclaredLaunchBlueprint action =
  withSystemTempDirectory "seihou-agent-run-declared-launch" $ \root -> do
    binary <- seihouBinary
    let blueprintDir = root </> ".seihou" </> "modules" </> "declared-launch"
        blueprintPath = blueprintDir </> "blueprint.dhall"
        xdgHome = root </> "xdg"
        fakeBin = root </> "bin"
        fakeClaude = fakeBin </> "claude"
        launchLog = root </> "agent-launch.args"
    createDirectoryIfMissing True blueprintDir
    createDirectoryIfMissing True xdgHome
    createDirectoryIfMissing True fakeBin
    TIO.writeFile blueprintPath declaredLaunchBlueprintDhall
    -- The batch path parses the JSON line, so the fake must keep printing it.
    TIO.writeFile
      fakeClaude
      "#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$SEIHOU_FAKE_AGENT_LOG\"\nprintf '%s\\n' '{\"result\":\"declared complete\",\"is_error\":false,\"session_id\":\"fake\"}'\n"
    permissions <- getPermissions fakeClaude
    -- Permissions comes from `directory` and has no Generic instance, so it
    -- has no #executable label. Record update syntax is the only option.
    setPermissions fakeClaude (permissions {executable = True})

    inherited <- getEnvironment
    let inheritedPath = fromMaybe "" (lookup "PATH" inherited)
        overriddenNames =
          [ "PATH",
            "XDG_CONFIG_HOME",
            "SEIHOU_AGENT_PROVIDER",
            "SEIHOU_AGENT_MODEL",
            "SEIHOU_AGENT_EFFORT",
            "SEIHOU_CONTEXT",
            "SEIHOU_FAKE_AGENT_LOG"
          ]
        environment =
          ("PATH", fakeBin <> [searchPathSeparator] <> inheritedPath)
            : ("XDG_CONFIG_HOME", xdgHome)
            : ("SEIHOU_FAKE_AGENT_LOG", launchLog)
            : filter (\(key, _) -> key `notElem` overriddenNames) inherited
        runDeclared extraArgs = do
          (exitCode, output, errorOutput) <-
            runProcessText
              binary
              (["agent", "run", "declared-launch"] <> extraArgs)
              (Just root)
              (Just environment)
          launchArgs <-
            doesFileExist launchLog >>= \case
              True -> T.lines <$> TIO.readFile launchLog
              False -> pure []
          pure (exitCode, output, errorOutput, launchArgs)
    action root "declared-launch" runDeclared

-- | A blueprint that declares a model and a reasoning effort but no provider,
-- so the provider still comes from the built-in default.
declaredLaunchBlueprintDhall :: T.Text
declaredLaunchBlueprintDhall =
  T.unlines
    [ "{ name = \"declared-launch\"",
      ", version = Some \"1.0.0\"",
      ", description = Some \"Blueprint declaring its own launch settings\"",
      ", prompt = \"Think hard about this repository.\"",
      ", vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }",
      ", prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }",
      ", baseModules = [] : List { module : Text, vars : List { name : Text, value : Text } }",
      ", files = [] : List { src : Text, description : Optional Text }",
      ", allowedTools = None (List Text)",
      ", tags = [] : List Text",
      ", migrations = [] : List { from : Text, to : Text, prompt : Text }",
      ", launch = Some",
      "    { provider = None Text",
      "    , model = Some \"claude-sonnet-5\"",
      "    , effort = Some \"max\"",
      "    , mode = None Text",
      "    }",
      "}"
    ]

migrationBlueprintDhall :: T.Text
migrationBlueprintDhall =
  T.unlines
    [ "{ name = \"payments\"",
      ", version = Some \"4.2.0\"",
      ", description = Some \"Payments library upgrade\"",
      ", prompt = \"Shared upgrade guidance for {{library.name}}.\"",
      ", vars =",
      "  [ { name = \"library.name\"",
      "    , type = \"text\"",
      "    , default = None Text",
      "    , description = None Text",
      "    , required = True",
      "    , validation = None Text",
      "    }",
      "  ]",
      ", prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }",
      ", baseModules = [] : List { module : Text, vars : List { name : Text, value : Text } }",
      ", files = [] : List { src : Text, description : Optional Text }",
      ", allowedTools = None (List Text)",
      ", tags = [] : List Text",
      ", migrations =",
      "  [ { from = \"2.5.0\", to = \"3.0.0\", prompt = \"Finish the baikai upgrade.\" }",
      "  , { from = \"1.0.0\", to = \"2.0.0\", prompt = \"Replace {{library.name}} legacy calls.\" }",
      "  ]",
      "}"
    ]

batchBlueprintDhall :: T.Text
batchBlueprintDhall =
  T.unlines
    [ "{ name = \"batch-blueprint\"",
      ", version = Some \"1.0.0\"",
      ", description = Some \"Batch blueprint fixture\"",
      ", prompt = \"Use the mounted reference and update the workspace.\"",
      ", vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }",
      ", prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }",
      ", baseModules = [] : List { module : Text, vars : List { name : Text, value : Text } }",
      ", files = [ { src = \"reference.md\", description = Some \"Batch reference\" } ]",
      ", allowedTools = Some [ \"Read\", \"Write\" ]",
      ", tags = [ \"test\" ]",
      ", migrations = [] : List { from : Text, to : Text, prompt : Text }",
      "}"
    ]
