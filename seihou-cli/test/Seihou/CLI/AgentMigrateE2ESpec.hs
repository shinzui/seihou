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
      output `shouldSatisfy` T.isInfixOf "===== Blueprint migration 1/2: 1.0.0 -> 2.0.0 ====="
      output `shouldSatisfy` T.isInfixOf "===== Blueprint migration 2/2: 2.5.0 -> 3.0.0 ====="
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
