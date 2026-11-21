-- | A blueprint's baseline runs its modules' commands, driven end to end
-- through the real binary.
--
-- A blueprint baseline is the module composition @seihou agent run@ applies
-- before the provider starts. Through 0.16.0.2 it generated the modules'
-- files and silently dropped their commands (BUG-4,
-- docs/bug-reports/a-blueprint-baseline-silently-skips-its-modules-commands.md).
-- These cases pin the fixed behavior: the commands run after the files, in
-- composition order, before the provider launches, with the receipt
-- publication and withdrawal contract of
-- docs/adr/0023-command-receipts-are-published-before-the-command-phase-runs.md,
-- and with everything the phase prints kept off standard output.
--
-- See docs/plans/125-run-blueprint-baseline-commands-before-launching-the-agent.md.
module Seihou.CLI.BaselineCommandE2ESpec (tests) where

import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.CommandReceiptE2ESpec (commitCommand, committedManifest, demoReceipts, initCommand)
import Seihou.CLI.SeedRunE2ESpec (prepare, readManifest)
import Seihou.Core.Types
import Seihou.Prelude
import System.Directory qualified as D
import System.Environment (getEnvironment)
import System.Exit (ExitCode (..))
import System.FilePath (searchPathSeparator)
import System.IO.Temp (withSystemTempDirectory)
import System.Process (CreateProcess (..), proc, readCreateProcessWithExitCode)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "blueprint baseline commands" spec

spec :: Spec
spec = do
  it "rejects incompatible policies and malformed inputs before applying a baseline" $
    withProject [sentinelCommand] $ \project -> do
      let root = project ^. #root
          reject flags diagnostic = do
            (code, out, err) <- runSeihou project [] (["agent", "run", "proto-bp", "--batch"] <> flags)
            code `shouldBe` ExitFailure 1
            (out <> err) `shouldSatisfy` T.isInfixOf diagnostic
            D.doesFileExist (root </> "cmd.log") `shouldReturn` False
            D.doesFileExist (project ^. #launchLog) `shouldReturn` False
            D.doesFileExist (root </> ".seihou/manifest.json") `shouldReturn` False
      mapM_ (\v -> reject ["--allowed-tool", v] "--allowed-tool") [" ", "--settings", "Read,Bash"]
      mapM_ (\v -> reject ["--allowed-tool", "Read", "--provider", v] "--allowed-tool") ["openai", "anthropic", "codex-cli"]
      reject ["--settings", "missing"] "readable regular file"
      reject ["--settings", "."] "readable regular file"
      mapM_ (\v -> TIO.writeFile (root </> "policy.json") v >> reject ["--settings", "policy.json"] "JSON object") ["[]", "false", "{broken"]

  it "previews the baseline without applying commands, launching, or changing receipt bytes" $
    withProject [sentinelCommand] $ \project -> do
      let root = project ^. #root
          path = root </> ".seihou/manifest.json"
          render = do
            (out, _) <- succeed project [] ["agent", "--debug", "run", "proto-bp", "Check the preview"]
            out `shouldSatisfy` T.isInfixOf "Preview only"
            out `shouldSatisfy` T.isInfixOf "Check the preview"
            D.doesFileExist (root </> "cmd.log") `shouldReturn` False
            D.doesFileExist (project ^. #launchLog) `shouldReturn` False
      render
      D.doesFileExist path `shouldReturn` False
      _ <- succeed project [] ["run", "demo", "--no-commands"]
      TIO.appendFile path "\n  \n"
      before <- TIO.readFile path
      render
      render
      TIO.readFile path `shouldReturn` before

  it "runs the baseline's commands, as seihou run does, before the agent starts" $ do
    viaRun <- withProject [sentinelCommand] $ \project -> do
      _ <- succeed project [] ["run", "demo"]
      TIO.readFile (project ^. #root </> "cmd.log")
    viaBlueprint <- withProject [sentinelCommand] $ \project -> do
      (out, err) <- succeed project [] ["agent", "run", "proto-bp", "--batch"]
      -- The decisive assertion for BUG-4: the command saw the seed and ran.
      D.doesFileExist (project ^. #root </> "cmd.log") `shouldReturn` True
      -- Standard output carries the rendered prompt and nothing from the
      -- command phase; the progress line and the command's output go to
      -- standard error.
      out `shouldSatisfy` T.isInfixOf "baseline complete"
      out `shouldNotSatisfy` T.isInfixOf commandOutput
      out `shouldNotSatisfy` T.isInfixOf "baseline command"
      err `shouldSatisfy` T.isInfixOf "Running 1 baseline command(s)..."
      err `shouldSatisfy` T.isInfixOf commandOutput
      -- The agent is told the commands already ran.
      prompt <- TIO.readFile (project ^. #launchLog)
      prompt `shouldSatisfy` T.isInfixOf "commands already ran"
      TIO.readFile (project ^. #root </> "cmd.log")
    viaBlueprint `shouldBe` viaRun

  it "finishes the command phase before a batch provider launches" $
    withProject [sentinelCommand] $ \project -> do
      (out, err) <- succeed project [("SEIHOU_BASELINE_SENTINEL", project ^. #root </> "cmd.log")] ["agent", "run", "proto-bp", "--batch"]
      -- The stub exits 1 unless cmd.log exists, so success proves ordering.
      out `shouldSatisfy` T.isInfixOf "baseline complete"
      out `shouldNotSatisfy` T.isInfixOf commandOutput
      out `shouldNotSatisfy` T.isInfixOf "Running 1 baseline command(s)..."
      err `shouldSatisfy` T.isInfixOf "Running 1 baseline command(s)..."
      err `shouldSatisfy` T.isInfixOf commandOutput
      D.doesFileExist (project ^. #launchLog) `shouldReturn` True
      manifest <- readManifest (project ^. #root)
      map (^. #command) (demoReceipts manifest) `shouldBe` [sentinelCommand]
      fmap (^. #name) (manifest ^. #blueprint) `shouldBe` Just "proto-bp"

  it "stops at a failing command, withdraws receipts, keeps the files, and never launches" $
    withProject [firstCommand, "echo third >> cmd.log"] $ \project -> do
      let root = project ^. #root
      _ <- succeed project [] ["agent", "run", "proto-bp", "--batch"]
      earlier <- readManifest root
      D.removeFile (project ^. #launchLog)
      D.removeFile (root </> "cmd.log")
      writeDemo project (commandsField (map apply [firstCommand, "exit 7", "echo third >> cmd.log"]))
      (code, out, err) <- runSeihou project [] ["agent", "run", "proto-bp", "--batch"]
      code `shouldBe` ExitFailure 1
      TIO.readFile (root </> "cmd.log") `shouldReturn` "first\n"
      D.doesFileExist (project ^. #launchLog) `shouldReturn` False
      out `shouldNotSatisfy` T.isInfixOf "first-output"
      err `shouldSatisfy` T.isInfixOf "first-output"
      err `shouldSatisfy` T.isInfixOf "[error] Baseline command failed (exit 7): exit 7"
      err `shouldSatisfy` T.isInfixOf "  module: demo"
      err `shouldSatisfy` T.isInfixOf "  directory: ."
      err `shouldSatisfy` T.isInfixOf "The agent was not started."
      err `shouldSatisfy` T.isInfixOf "Correct the failure, then rerun: seihou agent run proto-bp"
      err `shouldSatisfy` T.isInfixOf "To start the agent without applying the baseline again: seihou agent run proto-bp --no-baseline"
      manifest <- readManifest root
      demoReceipts manifest `shouldBe` []
      D.doesFileExist (root </> "LICENSE") `shouldReturn` True
      Map.member "LICENSE" (manifest ^. #files) `shouldBe` True
      -- The earlier successful provenance survives; no new success is claimed.
      fmap (^. #appliedAt) (manifest ^. #blueprint) `shouldBe` fmap (^. #appliedAt) (earlier ^. #blueprint)
      -- The ordinary rerun recovers once the failure is corrected.
      writeDemo project (commandsField (map apply [firstCommand, "echo third >> cmd.log"]))
      (recoveredOut, _) <- succeed project [] ["agent", "run", "proto-bp", "--batch"]
      recoveredOut `shouldSatisfy` T.isInfixOf "baseline complete"
      recovered <- readManifest root
      map (^. #command) (demoReceipts recovered) `shouldMatchList` [firstCommand, "echo third >> cmd.log"]

  it "publishes receipts before a command commits the manifest, and withdraws them on failure" $ do
    withProject [initCommand, commitCommand] $ \project -> do
      let root = project ^. #root
      _ <- succeed project [] ["agent", "run", "proto-bp", "--batch"]
      (_, committed) <- committedManifest root
      map (^. #command) (demoReceipts committed) `shouldMatchList` [initCommand, commitCommand]
      -- The phase confirmed the published receipts rather than rewriting them.
      onDisk <- readManifest root
      demoReceipts onDisk `shouldBe` demoReceipts committed
    withProject [initCommand, commitCommand, "exit 7"] $ \project -> do
      let root = project ^. #root
      (code, _, err) <- runSeihou project [] ["agent", "run", "proto-bp", "--batch"]
      code `shouldBe` ExitFailure 1
      err `shouldSatisfy` T.isInfixOf "withdrawn from .seihou/manifest.json"
      err `shouldSatisfy` T.isInfixOf "commit the result of the successful rerun"
      onDisk <- readManifest root
      demoReceipts onDisk `shouldBe` []
      onDisk ^. #blueprint `shouldBe` Nothing
      -- ADR 0023's accepted residual: the snapshot the commit took over-claims.
      (_, committed) <- committedManifest root
      length (demoReceipts committed) `shouldBe` 3

  it "matches seihou run for dependencies, conditions, variables, and working directories" $ do
    let extra =
          ", vars = [S.VarDecl::{name = \"greeting\", type = \"text\", default = Some \"hello\"}, S.VarDecl::{name = \"loud\", type = \"bool\", default = Some \"false\"}]"
            <> ", dependencies = [S.Dependency::{module = \"child\", vars = [{name = \"slot\", value = \"one\"}]}]"
            <> commandsField
              [ commandOf "Apply" (", workDir = Some " <> dhallText "nested") "echo demo-{{greeting}} >> ../order.log",
                commandOf "Apply" (", when = Some " <> dhallText "Eq loud true") "echo loud >> order.log",
                commandOf "Apply" (", when = Some " <> dhallText "Eq loud false") "echo quiet >> order.log"
              ]
        observe args = withProject [] $ \project -> do
          writeChild project
          writeDemo project extra
          _ <- succeed project [] (args <> ["--var", "greeting=hi"])
          TIO.readFile (project ^. #root </> "order.log")
    viaRun <- observe ["run", "demo"]
    viaRun `shouldBe` "child-one\ndemo-hi\nquiet\n"
    viaBlueprint <- observe ["agent", "run", "proto-bp", "--batch"]
    viaBlueprint `shouldBe` viaRun

  it "repeats commands on an explicit rerun and skips files and commands under --no-baseline" $ do
    withProject [sentinelCommand] $ \project -> do
      let root = project ^. #root
      _ <- succeed project [] ["agent", "run", "proto-bp", "--batch"]
      _ <- succeed project [] ["agent", "run", "proto-bp", "--batch"]
      TIO.readFile (root </> "cmd.log") `shouldReturn` "applied\napplied\n"
      (_, err) <- succeed project [] ["agent", "run", "proto-bp", "--batch", "--no-baseline"]
      err `shouldNotSatisfy` T.isInfixOf "baseline command"
      TIO.readFile (root </> "cmd.log") `shouldReturn` "applied\napplied\n"
    withProject [sentinelCommand] $ \project -> do
      let root = project ^. #root
      _ <- succeed project [] ["agent", "run", "proto-bp", "--batch", "--no-baseline"]
      D.doesFileExist (root </> "cmd.log") `shouldReturn` False
      D.doesFileExist (root </> "LICENSE") `shouldReturn` False

  it "recovers a receipt-free baseline application and keeps receipts seihou run recorded" $ do
    -- A project BUG-4 affected: the application exists but holds no receipts.
    withProject [sentinelCommand] $ \project -> do
      let root = project ^. #root
      _ <- succeed project [] ["run", "demo", "--no-commands"]
      before <- readManifest root
      demoReceipts before `shouldBe` []
      _ <- succeed project [] ["agent", "run", "proto-bp", "--batch"]
      TIO.readFile (root </> "cmd.log") `shouldReturn` "applied\n"
      after <- readManifest root
      map (^. #command) (demoReceipts after) `shouldBe` [sentinelCommand]
    -- seihou run and the baseline share one application record.
    withProject [sentinelCommand] $ \project -> do
      let root = project ^. #root
      _ <- succeed project [] ["run", "demo"]
      _ <- succeed project [] ["agent", "run", "proto-bp", "--batch"]
      manifest <- readManifest root
      map (^. #command) (demoReceipts manifest) `shouldBe` [sentinelCommand]
      length [a | a <- manifest ^. #applications, a ^. #target == AppliedModuleTarget "demo"] `shouldBe` 1

  it "runs a checkout command once without giving it an ordinary receipt" $
    withProject [] $ \project -> do
      let root = project ^. #root
      writeDemo project (commandsField [checkout "echo checkout >> checkout.log", apply sentinelCommand])
      _ <- succeed project [] ["agent", "run", "proto-bp", "--batch"]
      TIO.readFile (root </> "checkout.log") `shouldReturn` "checkout\n"
      manifest <- readManifest root
      map (^. #command) (demoReceipts manifest) `shouldBe` [sentinelCommand]

  it "keeps command-free and empty baselines quiet" $ do
    withProject [] $ \project -> do
      (_, err) <- succeed project [] ["agent", "run", "proto-bp", "--batch"]
      err `shouldNotSatisfy` T.isInfixOf "baseline command"
      D.doesFileExist (project ^. #root </> "LICENSE") `shouldReturn` True
    withProject [sentinelCommand] $ \project -> do
      writeBlueprint project "[] : List { module : Text, vars : List { name : Text, value : Text } }"
      (_, err) <- succeed project [] ["agent", "run", "proto-bp", "--batch"]
      err `shouldNotSatisfy` T.isInfixOf "baseline command"
      D.doesFileExist (project ^. #root </> "cmd.log") `shouldReturn` False

  it "refuses a baseline conflict before running any command" $
    withProject [sentinelCommand] $ \project -> do
      let root = project ^. #root
      _ <- succeed project [] ["agent", "run", "proto-bp", "--batch"]
      TIO.writeFile (root </> "LICENSE") "edited by hand\n"
      (code, out, err) <- runSeihou project [] ["agent", "run", "proto-bp", "--batch"]
      code `shouldBe` ExitFailure 1
      (out <> err) `shouldSatisfy` T.isInfixOf "Baseline conflicts detected"
      TIO.readFile (root </> "cmd.log") `shouldReturn` "applied\n"

-- ----------------------------------------------------------------------------
-- Fixture
-- ----------------------------------------------------------------------------

data Project = Project
  { root :: !FilePath,
    binary :: !FilePath,
    launchLog :: !FilePath,
    fakeBin :: !FilePath
  }
  deriving stock (Generic)

-- | The command the first regression relies on: it fails unless the seed the
-- module generates is already on disk, and it prints to standard output so
-- the tests can see where that output lands.
sentinelCommand :: Text
sentinelCommand = "test -f nested/start.txt && echo applied >> cmd.log && echo " <> commandOutput

commandOutput :: Text
commandOutput = "command-says-hello"

firstCommand :: Text
firstCommand = "echo first >> cmd.log && echo first-output"

-- | A fresh project holding the project-local @demo@ module (one seed, one
-- managed file, the given Apply commands), a @proto-bp@ blueprint whose
-- baseline is @demo@, and a fake @claude@ that refuses to answer until the
-- baseline's sentinel exists.
withProject :: [Text] -> (Project -> IO a) -> IO a
withProject commands action =
  withSystemTempDirectory "baseline-commands" $ \tmp -> do
    root <- D.canonicalizePath tmp
    (binary, _) <- prepare root
    let project =
          Project
            { root = root,
              binary = binary,
              launchLog = root </> "agent-launch.args",
              fakeBin = root </> "bin"
            }
    TIO.writeFile (root </> ".gitignore") "/home/\n/config/\n/cache/\n/bin/\n/agent-launch.args\n"
    writeDemo project (if null commands then "" else commandsField (map apply commands))
    writeBlueprint project "[ { module = \"demo\", vars = [] : List { name : Text, value : Text } } ]"
    D.createDirectoryIfMissing True (project ^. #fakeBin)
    let fakeClaude = project ^. #fakeBin </> "claude"
    TIO.writeFile
      fakeClaude
      ( T.unlines
          [ "#!/bin/sh",
            "printf '%s\\n' \"$@\" > \"$SEIHOU_FAKE_AGENT_LOG\"",
            "if [ -n \"$SEIHOU_BASELINE_SENTINEL\" ] && [ ! -f \"$SEIHOU_BASELINE_SENTINEL\" ]; then echo 'baseline sentinel missing' >&2; exit 1; fi",
            "printf '%s\\n' '{\"result\":\"baseline complete\",\"is_error\":false,\"session_id\":\"fake\"}'"
          ]
      )
    permissions <- D.getPermissions fakeClaude
    -- Permissions has no Generic instance, so record update is the only option.
    D.setPermissions fakeClaude (permissions {D.executable = True})
    action project

writeDemo :: Project -> Text -> IO ()
writeDemo project extra =
  TIO.writeFile
    (project ^. #root </> ".seihou/modules/demo/module.dhall")
    ( "let S = ./schema/package.dhall in S.Module::{name = \"demo\", version = Some \"1.0.0\""
        <> ", steps = [S.Step::{strategy = \"copy\", src = \"starter\", dest = \"nested/start.txt\", lifecycle = Some \"seed\"}, S.Step::{strategy = \"copy\", src = \"license\", dest = \"LICENSE\"}]"
        <> extra
        <> "}"
    )

writeChild :: Project -> IO ()
writeChild project = do
  let child = project ^. #root </> ".seihou/modules/child"
  D.createDirectoryIfMissing True child
  TIO.writeFile
    (child </> "module.dhall")
    ( "let S = ../demo/schema/package.dhall in S.Module::{name = \"child\", version = Some \"1.0.0\""
        <> ", vars = [S.VarDecl::{name = \"slot\", type = \"text\", default = Some \"base\"}]"
        <> commandsField [apply "echo child-{{slot}} >> order.log"]
        <> "}"
    )

writeBlueprint :: Project -> Text -> IO ()
writeBlueprint project baseModules = do
  let dir = project ^. #root </> ".seihou/modules/proto-bp"
  D.createDirectoryIfMissing True dir
  TIO.writeFile
    (dir </> "blueprint.dhall")
    ( T.unlines
        [ "{ name = \"proto-bp\"",
          ", version = Some \"1.0.0\"",
          ", description = Some \"Baseline command fixture\"",
          ", prompt = \"Extend the baseline.\"",
          ", vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }",
          ", prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }",
          ", baseModules = " <> baseModules,
          ", files = [] : List { src : Text, description : Optional Text }",
          ", allowedTools = None (List Text)",
          ", tags = [] : List Text",
          ", migrations = [] : List { from : Text, to : Text, prompt : Text }",
          "}"
        ]
    )

commandsField :: [Text] -> Text
commandsField commands = ", commands = [" <> T.intercalate ", " commands <> "]"

apply :: Text -> Text
apply = commandOf "Apply" ""

checkout :: Text -> Text
checkout = commandOf "Checkout" ""

commandOf :: Text -> Text -> Text -> Text
commandOf action extra text = "S.Command::{action = S.Command.Action." <> action <> " " <> dhallText text <> extra <> "}"

dhallText :: Text -> Text
dhallText text = "\"" <> T.replace "\"" "\\\"" text <> "\""

-- | Run the binary in the project with isolated home, configuration, and
-- caches, the fake provider first on PATH, and no inherited agent settings.
runSeihou :: Project -> [(String, String)] -> [String] -> IO (ExitCode, Text, Text)
runSeihou project extraEnv args = do
  inherited <- getEnvironment
  let root = project ^. #root
      inheritedPath = fromMaybe "" (lookup "PATH" inherited)
      overrides =
        [ ("HOME", root </> "home"),
          ("XDG_CONFIG_HOME", root </> "config"),
          ("XDG_CACHE_HOME", root </> "cache"),
          ("PATH", project ^. #fakeBin <> [searchPathSeparator] <> inheritedPath),
          ("SEIHOU_FAKE_AGENT_LOG", project ^. #launchLog)
        ]
          <> extraEnv
      cleared = ["SEIHOU_AGENT_PROVIDER", "SEIHOU_AGENT_MODEL", "SEIHOU_AGENT_EFFORT", "SEIHOU_AGENT_TRACE", "SEIHOU_CONTEXT"]
      environment = overrides <> filter (\(key, _) -> key `notElem` (map fst overrides <> cleared)) inherited
  (code, out, err) <- readCreateProcessWithExitCode (proc (project ^. #binary) args) {cwd = Just root, env = Just environment} ""
  pure (code, T.pack out, T.pack err)

succeed :: Project -> [(String, String)] -> [String] -> IO (Text, Text)
succeed project extraEnv args = do
  (code, out, err) <- runSeihou project extraEnv args
  case code of
    ExitSuccess -> pure (out, err)
    ExitFailure n -> expectationFailure (unwords args <> " exited " <> show n <> "\nstdout:\n" <> T.unpack out <> "\nstderr:\n" <> T.unpack err) >> pure (out, err)
