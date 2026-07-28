-- | End-to-end proof that call tracing reaches a JSONL file when it is turned
-- on, and touches nothing at all when it is not.
--
-- These run the real @seihou@ binary against a fake @claude@ first on @PATH@,
-- with an empty @XDG_CONFIG_HOME@ and every @SEIHOU_AGENT_*@ variable scrubbed
-- from the inherited environment, so nothing outside the test configures
-- tracing. The unit specs cover sink construction and the completion path;
-- this covers the wiring between them, which is the part a stale binary or a
-- missed call site would silently break.
module Seihou.CLI.AgentTraceE2ESpec (tests) where

import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString.Lazy.Char8 qualified as BL8
import Data.Maybe (fromMaybe)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.SeihouBinary (seihouBinary)
import System.Directory
  ( createDirectoryIfMissing,
    doesFileExist,
    executable,
    getPermissions,
    setPermissions,
  )
import System.Environment (getEnvironment)
import System.Exit (ExitCode (..))
import System.FilePath (searchPathSeparator, (</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (CreateProcess (..), proc, readCreateProcessWithExitCode)
import Test.Hspec
import Test.Tasty (TestTree)
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Agent call tracing end-to-end" $ do
  -- The guarantee that tracing is genuinely off by default: no file, anywhere.
  it "creates no trace file when tracing is not configured" $
    withTraceProject $ \root run -> do
      (exitCode, output, errorOutput, _) <- run [] []
      expectSuccess "untraced run" exitCode output errorOutput
      output `shouldSatisfy` T.isInfixOf "traced complete"
      doesFileExist (root </> ".seihou" </> "trace.jsonl") `shouldReturn` False

  it "writes a correlated start/finish pair when SEIHOU_AGENT_TRACE=file" $
    withTraceProject $ \root run -> do
      let tracePath = root </> "trace.jsonl"
      (exitCode, output, errorOutput, _) <-
        run [("SEIHOU_AGENT_TRACE", "file"), ("SEIHOU_AGENT_TRACE_PATH_FIXTURE", tracePath)] []
      expectSuccess "traced run" exitCode output errorOutput
      events <- traceEvents tracePath
      map fst events `shouldBe` ["call_started", "call_finished"]
      case map snd events of
        [started, finished] -> started `shouldBe` finished
        other -> expectationFailure ("expected two events, got " <> show (length other))

  it "lets --trace off override a configured file trace" $
    withTraceProject $ \root run -> do
      let tracePath = root </> "trace.jsonl"
      (exitCode, output, errorOutput, _) <-
        run
          [("SEIHOU_AGENT_TRACE", "file"), ("SEIHOU_AGENT_TRACE_PATH_FIXTURE", tracePath)]
          ["--trace", "off"]
      expectSuccess "flag-disabled run" exitCode output errorOutput
      doesFileExist tracePath `shouldReturn` False

  -- Trace lines must never land in stdout, which callers pipe.
  it "sends --trace stderr to stderr, leaving stdout clean" $
    withTraceProject $ \_ run -> do
      (exitCode, output, errorOutput, _) <- run [] ["--trace", "stderr"]
      expectSuccess "stderr-traced run" exitCode output errorOutput
      errorOutput `shouldSatisfy` T.isInfixOf "START"
      output `shouldNotSatisfy` T.isInfixOf "START"
      output `shouldSatisfy` T.isInfixOf "traced complete"

  it "rejects an unknown trace setting, naming the accepted ones" $
    withTraceProject $ \_ run -> do
      (exitCode, output, errorOutput, _) <- run [] ["--trace", "syslog"]
      exitCode `shouldBe` ExitFailure 1
      (output <> errorOutput) `shouldSatisfy` T.isInfixOf "Unknown trace setting 'syslog'"
      (output <> errorOutput) `shouldSatisfy` T.isInfixOf "off, file, stdout, stderr"

-- | Stand up a scratch project with a trivial blueprint and a fake @claude@
-- that prints the batch JSON line the CLI provider expects.
--
-- The callback receives the project root and a runner taking extra environment
-- entries and extra @seihou agent run@ arguments. When the environment carries
-- @SEIHOU_AGENT_TRACE_PATH_FIXTURE@, that path is written into the project's
-- local config as @agent.tracePath@ before the run, since the path has no flag
-- or environment variable of its own by design.
withTraceProject ::
  (FilePath -> ([(String, String)] -> [String] -> IO (ExitCode, T.Text, T.Text, [T.Text])) -> IO a) ->
  IO a
withTraceProject action =
  withSystemTempDirectory "seihou-agent-trace" $ \root -> do
    binary <- seihouBinary
    let blueprintDir = root </> ".seihou" </> "modules" </> "tracer"
        blueprintPath = blueprintDir </> "blueprint.dhall"
        configPath = root </> ".seihou" </> "config.dhall"
        xdgHome = root </> "xdg"
        fakeBin = root </> "bin"
        fakeClaude = fakeBin </> "claude"
        launchLog = root </> "agent-launch.args"
    createDirectoryIfMissing True blueprintDir
    createDirectoryIfMissing True xdgHome
    createDirectoryIfMissing True fakeBin
    TIO.writeFile blueprintPath tracerBlueprintDhall
    TIO.writeFile
      fakeClaude
      "#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$SEIHOU_FAKE_AGENT_LOG\"\nprintf '%s\\n' '{\"result\":\"traced complete\",\"is_error\":false,\"session_id\":\"fake\"}'\n"
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
            "SEIHOU_AGENT_TRACE",
            "SEIHOU_CONTEXT",
            "SEIHOU_FAKE_AGENT_LOG"
          ]
        baseEnvironment =
          ("PATH", fakeBin <> [searchPathSeparator] <> inheritedPath)
            : ("XDG_CONFIG_HOME", xdgHome)
            : ("SEIHOU_FAKE_AGENT_LOG", launchLog)
            : filter (\(key, _) -> key `notElem` overriddenNames) inherited
        run extraEnv extraArgs = do
          case lookup "SEIHOU_AGENT_TRACE_PATH_FIXTURE" extraEnv of
            Nothing -> pure ()
            Just tracePath ->
              TIO.writeFile configPath (localConfigDhall (T.pack tracePath))
          (exitCode, output, errorOutput) <-
            runProcessText
              binary
              (["agent", "run", "tracer", "--batch"] <> extraArgs)
              (Just root)
              (Just (extraEnv <> baseEnvironment))
          launchArgs <-
            doesFileExist launchLog >>= \case
              True -> T.lines <$> TIO.readFile launchLog
              False -> pure []
          pure (exitCode, output, errorOutput, launchArgs)
    action root run

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

-- | The @(kind, eventId)@ of every event in a JSONL trace file, in order.
--
-- Deliberately not asserting on token counts or cost: @claude-cli@ is
-- subscription-based and reports neither, so those fields are legitimately
-- absent from this fixture's @call_finished@ event.
traceEvents :: FilePath -> IO [(String, String)]
traceEvents path = do
  contents <- BL8.readFile path
  pure
    [ (T.unpack kind, T.unpack eventId)
    | line <- BL8.lines contents,
      not (BL8.null line),
      Just (Aeson.Object o) <- [Aeson.decode line],
      Just (Aeson.String kind) <- [KeyMap.lookup (Key.fromString "kind") o],
      Just (Aeson.String eventId) <- [KeyMap.lookup (Key.fromString "eventId") o]
    ]

-- | A project-local @.seihou/config.dhall@: a plain Dhall record of text
-- values with backtick-escaped dotted keys, which is the shape
-- 'Seihou.Dhall.Config.evalConfigFile' expects.
localConfigDhall :: T.Text -> T.Text
localConfigDhall tracePath =
  "{ `agent.tracePath` = \"" <> tracePath <> "\" }\n"

tracerBlueprintDhall :: T.Text
tracerBlueprintDhall =
  T.unlines
    [ "{ name = \"tracer\"",
      ", version = Some \"1.0.0\"",
      ", description = Some \"Blueprint fixture for call tracing\"",
      ", prompt = \"Say hello.\"",
      ", vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }",
      ", prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }",
      ", baseModules = [] : List { module : Text, vars : List { name : Text, value : Text } }",
      ", files = [] : List { src : Text, description : Optional Text }",
      ", allowedTools = None (List Text)",
      ", tags = [] : List Text",
      ", migrations = [] : List { from : Text, to : Text, prompt : Text }",
      "}"
    ]
