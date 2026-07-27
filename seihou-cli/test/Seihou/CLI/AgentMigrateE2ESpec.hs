module Seihou.CLI.AgentMigrateE2ESpec (tests) where

import Data.ByteString.Lazy qualified as LBS
import Data.Maybe (fromMaybe)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.Core.Types (AppliedBlueprintMigration (..), Manifest (..))
import Seihou.Manifest.Types (manifestFromJSON)
import System.Directory
  ( createDirectoryIfMissing,
    doesFileExist,
    executable,
    getPermissions,
    setPermissions,
  )
import System.Environment (getEnvironment, getExecutablePath)
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

  it "exposes the required version window and rerun option in help" $ do
    binary <- seihouBinary
    (exitCode, output, _) <- runProcessText binary ["agent", "migrate", "--help"] Nothing Nothing
    exitCode `shouldBe` ExitSuccess
    output `shouldSatisfy` T.isInfixOf "Usage: seihou agent migrate BLUEPRINT --from VERSION --to VERSION [PROMPT]"
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
      output `shouldSatisfy` T.isInfixOf "===== [1/2] 1.0.0 -> 2.0.0 ====="
      output `shouldSatisfy` T.isInfixOf "===== [2/2] 2.5.0 -> 3.0.0 ====="
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
      map (\receipt -> (receipt.fromVersion, receipt.toVersion)) manifest.blueprintMigrations
        `shouldBe` [("1.0.0", "2.0.0"), ("2.5.0", "3.0.0")]

      (resumeExit, resumeOutput, resumeError) <- runProcessText binary args (Just root) (Just environment)
      case resumeExit of
        ExitSuccess -> pure ()
        ExitFailure code -> expectationFailure ("resume exited " <> show code <> "\nstderr:\n" <> T.unpack resumeError)
      resumeOutput `shouldSatisfy` T.isInfixOf "already have receipts"
      T.lines <$> TIO.readFile launchLog `shouldReturn` ["called", "called"]
      LBS.readFile manifestPath `shouldReturn` beforeResume

seihouBinary :: IO FilePath
seihouBinary = do
  testBinary <- getExecutablePath
  pure (takeDirectory (takeDirectory testBinary) </> "seihou" </> "seihou")

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
