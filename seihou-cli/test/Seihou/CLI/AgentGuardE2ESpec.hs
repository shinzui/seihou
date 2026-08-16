-- | The agent path refuses a stale or substituted artifact, driven end to end
-- through the real binary.
--
-- @seihou run@ has refused since
-- docs\/adr\/0003-a-stale-or-substituted-artifact-is-a-hard-error.md was
-- accepted; @seihou agent run@ and @seihou agent migrate@ did not, even though
-- the first applies a blueprint's baseline modules to the working directory
-- and rewrites the manifest, and the second writes receipts that suppress
-- future runs of the edges they name. This spec is what stops that gap from
-- reopening.
--
-- Every case asserts the decisive property rather than the exit code alone:
-- an exit code proves the command reported failure, only an unchanged working
-- tree proves it did not write first.
module Seihou.CLI.AgentGuardE2ESpec (tests) where

import Control.Lens ((^.))
import Data.ByteString.Lazy qualified as LBS
import Data.Generics.Labels ()
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import GHC.Generics (Generic)
import Seihou.CLI.SeihouBinary (seihouBinary)
import Seihou.CLI.TwoDeveloperFixture (installModuleVersion, moduleSourceUrl)
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
import System.Process (CreateProcess (..), callProcess, proc, readCreateProcessWithExitCode, readProcess)
import Test.Hspec
import Test.Tasty (TestTree)
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "agent path artifact guard" spec

spec :: Spec
spec = do
  it "offers --allow-downgrade on both agent subcommands" $ do
    binary <- seihouBinary
    (runCode, runOut, _) <- runProcessText binary ["agent", "run", "--help"] Nothing Nothing
    runCode `shouldBe` ExitSuccess
    runOut `shouldSatisfy` T.isInfixOf "--allow-downgrade"
    (migrateCode, migrateOut, _) <- runProcessText binary ["agent", "migrate", "--help"] Nothing Nothing
    migrateCode `shouldBe` ExitSuccess
    migrateOut `shouldSatisfy` T.isInfixOf "--allow-downgrade"

  it "refuses agent run when the installed blueprint is older than the manifest records" $
    withStaleBlueprint $ \fixture -> do
      before <- LBS.readFile (fixture ^. #manifestPath)
      (code, out, err) <- runSeihou fixture ["agent", "run", "upgrade-helper"]
      code `shouldSatisfy` (/= ExitSuccess)
      let reported = out <> err
      reported `shouldSatisfy` T.isInfixOf "2.0.0"
      reported `shouldSatisfy` T.isInfixOf "1.0.0"
      reported `shouldSatisfy` T.isInfixOf "seihou upgrade upgrade-helper"

      -- The decisive assertions: nothing was generated, no provenance was
      -- recorded, and the provider was never contacted.
      gitStatus fixture `shouldReturn` ""
      LBS.readFile (fixture ^. #manifestPath) `shouldReturn` before
      doesFileExist (fixture ^. #launchLog) `shouldReturn` False

  it "proceeds under --allow-downgrade and prints what it overrode" $
    withStaleBlueprint $ \fixture -> do
      (code, out, err) <- runSeihou fixture ["agent", "run", "upgrade-helper", "--allow-downgrade"]
      expectSuccess "the deliberate downgrade" code out err

      -- A deliberate downgrade must still be visible; silently honouring the
      -- flag would hide exactly the change the guard exists to make legible.
      let reported = out <> err
      reported `shouldSatisfy` T.isInfixOf "Proceeding anyway (--allow-downgrade)"
      reported `shouldSatisfy` T.isInfixOf "2.0.0"
      reported `shouldSatisfy` T.isInfixOf "1.0.0"
      reported `shouldSatisfy` T.isInfixOf "agent complete"

      -- Having proceeded, it pins the project to what is installed here.
      manifest <- TIO.readFile (fixture ^. #manifestPath)
      manifest `shouldSatisfy` T.isInfixOf "\"version\":\"1.0.0\""

  it "refuses agent run when a baseline module is stale though the blueprint is current" $
    withStaleBaselineModule $ \fixture -> do
      before <- LBS.readFile (fixture ^. #manifestPath)
      (code, out, err) <- runSeihou fixture ["agent", "run", "upgrade-helper"]
      code `shouldSatisfy` (/= ExitSuccess)
      let reported = out <> err
      -- The blueprint itself is current, so the refusal must name the module.
      reported `shouldSatisfy` T.isInfixOf "'demo'"
      reported `shouldSatisfy` T.isInfixOf "2.0.0"
      reported `shouldSatisfy` T.isInfixOf "1.4.0"

      gitStatus fixture `shouldReturn` ""
      LBS.readFile (fixture ^. #manifestPath) `shouldReturn` before

  it "refuses agent migrate when the installed blueprint came from another repository" $
    withSubstitutedBlueprint $ \fixture -> do
      before <- LBS.readFile (fixture ^. #manifestPath)
      (code, out, err) <-
        runSeihou fixture ["agent", "migrate", "payments", "--from", "1.0.0", "--to", "2.0.0"]
      code `shouldSatisfy` (/= ExitSuccess)
      let reported = out <> err
      reported `shouldSatisfy` T.isInfixOf "different source"
      reported `shouldSatisfy` T.isInfixOf recordedBlueprintUrl
      reported `shouldSatisfy` T.isInfixOf substitutedBlueprintUrl

      -- The point of checking before planning: without the guard this command
      -- would have launched a provider session carrying the wrong
      -- repository's migration prompt and written a receipt for it.
      doesFileExist (fixture ^. #launchLog) `shouldReturn` False
      LBS.readFile (fixture ^. #manifestPath) `shouldReturn` before
      gitStatus fixture `shouldReturn` ""

  it "checks nothing under agent --debug migrate, which writes nothing" $
    withSubstitutedBlueprint $ \fixture -> do
      before <- LBS.readFile (fixture ^. #manifestPath)
      (code, out, err) <-
        runSeihou
          fixture
          ["agent", "--debug", "migrate", "payments", "--from", "1.0.0", "--to", "2.0.0"]
      expectSuccess "the debug migration" code out err
      out `shouldSatisfy` T.isInfixOf "Blueprint migrations for payments: 1.0.0 -> 2.0.0"

      LBS.readFile (fixture ^. #manifestPath) `shouldReturn` before
      doesFileExist (fixture ^. #launchLog) `shouldReturn` False
      gitStatus fixture `shouldReturn` ""

  it "still checks under agent --debug run, which is not a dry run" $
    withStaleBlueprint $ \fixture -> do
      before <- LBS.readFile (fixture ^. #manifestPath)
      (code, out, err) <- runSeihou fixture ["agent", "--debug", "run", "upgrade-helper"]
      code `shouldSatisfy` (/= ExitSuccess)
      (out <> err) `shouldSatisfy` T.isInfixOf "seihou upgrade upgrade-helper"

      -- Without the check this run would still have applied the baseline and
      -- rewritten the manifest to name the older blueprint: --debug skips the
      -- provider call on this path, not the writes.
      LBS.readFile (fixture ^. #manifestPath) `shouldReturn` before
      gitStatus fixture `shouldReturn` ""

-- ----------------------------------------------------------------------------
-- Scenarios
-- ----------------------------------------------------------------------------

-- | The manifest records @upgrade-helper@ at 2.0.0; 1.0.0 is installed here.
-- This is the downgrade ADR 0003 opens with, on the blueprint path.
withStaleBlueprint :: (GuardFixture -> IO ()) -> IO ()
withStaleBlueprint = withGuardFixture "seihou-agent-guard-stale" $ \fixture -> do
  installBlueprint
    fixture
    "upgrade-helper"
    recordedBlueprintUrl
    (blueprintDhall "upgrade-helper" "1.0.0" noBaseModules oneMigration)
  TIO.writeFile
    (fixture ^. #manifestPath)
    (manifestJson [] (Just (appliedBlueprintJson "upgrade-helper" recordedBlueprintUrl "2.0.0")) [])

-- | The blueprint matches what the manifest records, but a module it applies
-- as its baseline does not. Those modules generate ordinary files, and a
-- blueprint run is the one path on which they are applied without the
-- @seihou run@ guard.
withStaleBaselineModule :: (GuardFixture -> IO ()) -> IO ()
withStaleBaselineModule = withGuardFixture "seihou-agent-guard-baseline" $ \fixture -> do
  installBlueprint
    fixture
    "upgrade-helper"
    recordedBlueprintUrl
    (blueprintDhall "upgrade-helper" "2.0.0" demoBaseModule oneMigration)
  installModuleVersion (fixture ^. #home) "demo" "1.4.0"
  TIO.writeFile
    (fixture ^. #manifestPath)
    ( manifestJson
        [appliedModuleJson "demo" moduleSourceUrl "2.0.0"]
        (Just (appliedBlueprintJson "upgrade-helper" recordedBlueprintUrl "2.0.0"))
        []
    )

-- | A blueprint of the recorded name is installed, from a different
-- repository. Its edges are not this project's edges.
withSubstitutedBlueprint :: (GuardFixture -> IO ()) -> IO ()
withSubstitutedBlueprint = withGuardFixture "seihou-agent-guard-substituted" $ \fixture -> do
  installBlueprint
    fixture
    "payments"
    substitutedBlueprintUrl
    (blueprintDhall "payments" "4.2.0" noBaseModules oneMigration)
  -- Receipts only, and no applied-blueprint entry: this project has migrated
  -- the blueprint but never run it, which is the shape 'agent migrate' alone
  -- produces.
  TIO.writeFile
    (fixture ^. #manifestPath)
    (manifestJson [] Nothing [migrationReceiptJson "payments" recordedBlueprintUrl "4.2.0"])

-- ----------------------------------------------------------------------------
-- Fixture
-- ----------------------------------------------------------------------------

-- | A scratch project with its own configuration root and a fake provider.
--
-- @home@ becomes @XDG_CONFIG_HOME@, so @\<home\>\/seihou\/installed\/@ is the
-- only place artifacts are found and a test can never reach the developer's
-- own @~\/.config\/seihou\/@. @launchLog@ exists only once the fake provider
-- has actually been called, which is how a test proves nothing was launched.
data GuardFixture = GuardFixture
  { projectRoot :: !FilePath,
    manifestPath :: !FilePath,
    home :: !FilePath,
    launchLog :: !FilePath,
    binary :: !FilePath,
    environment :: ![(String, String)]
  }
  deriving stock (Eq, Show, Generic)

-- | Build the fixture, run @setup@ against it, commit everything, then run the
-- scenario. Committing after setup is what makes @git status --porcelain@ a
-- meaningful assertion: anything it reports afterwards was written by the
-- command under test.
withGuardFixture :: String -> (GuardFixture -> IO ()) -> (GuardFixture -> IO ()) -> IO ()
withGuardFixture label setup action =
  withSystemTempDirectory label $ \root -> do
    binary <- seihouBinary
    let projectRoot = root </> "project"
        home = root </> "home"
        fakeBin = root </> "bin"
        fakeClaude = fakeBin </> "claude"
        launchLog = root </> "agent-launch.args"
    createDirectoryIfMissing True (projectRoot </> ".seihou")
    createDirectoryIfMissing True home
    createDirectoryIfMissing True fakeBin

    -- The batch path parses one JSON line out of the provider's stdout, so the
    -- fake has to print one. Touching the log is what records that it ran.
    TIO.writeFile
      fakeClaude
      "#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$SEIHOU_FAKE_AGENT_LOG\"\nprintf '%s\\n' '{\"result\":\"agent complete\",\"is_error\":false,\"session_id\":\"fake\"}'\n"
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
            : ("XDG_CONFIG_HOME", home)
            : ("SEIHOU_AGENT_PROVIDER", "claude-cli")
            : ("SEIHOU_FAKE_AGENT_LOG", launchLog)
            : filter (\(key, _) -> key `notElem` overriddenNames) inherited
        fixture =
          GuardFixture
            { projectRoot = projectRoot,
              manifestPath = projectRoot </> ".seihou" </> "manifest.json",
              home = home,
              launchLog = launchLog,
              binary = binary,
              environment = environment
            }

    setup fixture

    callProcess "git" ["-C", projectRoot, "init", "-q"]
    callProcess "git" ["-C", projectRoot, "config", "user.name", "Seihou Test"]
    callProcess "git" ["-C", projectRoot, "config", "user.email", "test@example.com"]
    callProcess "git" ["-C", projectRoot, "add", "-A"]
    callProcess "git" ["-C", projectRoot, "commit", "-qm", "test: seed the guarded project"]

    action fixture

-- | Run the real binary inside the fixture's project.
runSeihou :: GuardFixture -> [String] -> IO (ExitCode, Text, Text)
runSeihou fixture args =
  runProcessText
    (fixture ^. #binary)
    args
    (Just (fixture ^. #projectRoot))
    (Just (fixture ^. #environment))

runProcessText ::
  FilePath ->
  [String] ->
  Maybe FilePath ->
  Maybe [(String, String)] ->
  IO (ExitCode, Text, Text)
runProcessText binary args workingDirectory environment = do
  let command = (proc binary args) {cwd = workingDirectory, env = environment}
  (exitCode, stdoutText, stderrText) <- readCreateProcessWithExitCode command ""
  pure (exitCode, T.pack stdoutText, T.pack stderrText)

-- | @git status --porcelain@ in the project. Empty means nothing was written.
gitStatus :: GuardFixture -> IO Text
gitStatus fixture =
  T.strip . T.pack <$> readProcess "git" ["-C", fixture ^. #projectRoot, "status", "--porcelain"] ""

expectSuccess :: String -> ExitCode -> Text -> Text -> Expectation
expectSuccess label code out err = case code of
  ExitSuccess -> pure ()
  ExitFailure status ->
    expectationFailure
      ( label
          <> " exited "
          <> show status
          <> "\nstdout:\n"
          <> T.unpack out
          <> "\nstderr:\n"
          <> T.unpack err
      )

-- ----------------------------------------------------------------------------
-- Artifacts and manifests
-- ----------------------------------------------------------------------------

-- | The repository the project's manifest says its blueprint came from.
recordedBlueprintUrl :: Text
recordedBlueprintUrl = "https://example.com/cohort-blueprints.git"

-- | A different repository publishing a blueprint of the same name. Nothing is
-- ever fetched from either; the URLs exist so the two copies are recognisably
-- different artifacts.
substitutedBlueprintUrl :: Text
substitutedBlueprintUrl = "https://example.com/somebody-elses-blueprints.git"

-- | Install a blueprint into the fixture's configuration root, as
-- @seihou install@ would: the directory, its @blueprint.dhall@, and the
-- @.seihou-origin.json@ recording where it came from.
installBlueprint :: GuardFixture -> Text -> Text -> Text -> IO ()
installBlueprint fixture name sourceUrl dhall = do
  let installed = (fixture ^. #home) </> "seihou" </> "installed" </> T.unpack name
  createDirectoryIfMissing True installed
  TIO.writeFile (installed </> "blueprint.dhall") dhall
  TIO.writeFile
    (installed </> ".seihou-origin.json")
    ( "{\"sourceUrl\":\""
        <> sourceUrl
        <> "\",\"repoName\":\"cohort\",\"installedAt\":\"2026-07-01T00:00:00Z\",\"tags\":[]}"
    )

blueprintDhall :: Text -> Text -> Text -> Text -> Text
blueprintDhall name version baseModules migrations =
  T.unlines
    [ "{ name = \"" <> name <> "\"",
      ", version = Some \"" <> version <> "\"",
      ", description = Some \"Guarded blueprint fixture\"",
      ", prompt = \"Upgrade this project.\"",
      ", vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }",
      ", prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }",
      ", baseModules = " <> baseModules,
      ", files = [] : List { src : Text, description : Optional Text }",
      ", allowedTools = None (List Text)",
      ", tags = [] : List Text",
      ", migrations = " <> migrations,
      "}"
    ]

noBaseModules :: Text
noBaseModules = "[] : List { module : Text, vars : List { name : Text, value : Text } }"

demoBaseModule :: Text
demoBaseModule = "[ { module = \"demo\", vars = [] : List { name : Text, value : Text } } ]"

oneMigration :: Text
oneMigration = "[ { from = \"1.0.0\", to = \"2.0.0\", prompt = \"Cross the cohort edge.\" } ]"

-- | A schema-6 manifest carrying exactly the records a scenario needs.
manifestJson :: [Text] -> Maybe Text -> [Text] -> Text
manifestJson modules blueprint receipts =
  T.concat
    [ "{\"version\":6",
      ",\"generatedAt\":\"2026-07-01T12:00:00Z\"",
      ",\"modules\":[",
      T.intercalate "," modules,
      "],\"variables\":{},\"files\":{},\"applications\":[]",
      maybe "" (\entry -> ",\"blueprint\":" <> entry) blueprint,
      ",\"blueprintMigrations\":[",
      T.intercalate "," receipts,
      "]}"
    ]

appliedBlueprintJson :: Text -> Text -> Text -> Text
appliedBlueprintJson name url version =
  T.concat
    [ "{\"name\":\"",
      name,
      "\",\"origin\":",
      remoteOriginJson url name,
      ",\"version\":\"",
      version,
      "\",\"appliedAt\":\"2026-07-01T12:00:00Z\"",
      ",\"baselineModules\":[],\"noBaseline\":false}"
    ]

appliedModuleJson :: Text -> Text -> Text -> Text
appliedModuleJson name url version =
  T.concat
    [ "{\"name\":\"",
      name,
      "\",\"origin\":",
      remoteOriginJson url name,
      ",\"version\":\"",
      version,
      "\",\"appliedAt\":\"2026-07-01T12:00:00Z\"}"
    ]

migrationReceiptJson :: Text -> Text -> Text -> Text
migrationReceiptJson name url version =
  T.concat
    [ "{\"name\":\"",
      name,
      "\",\"origin\":",
      remoteOriginJson url name,
      ",\"version\":\"",
      version,
      "\",\"from\":\"0.9.0\",\"to\":\"1.0.0\"",
      ",\"appliedAt\":\"2026-07-01T12:00:00Z\"}"
    ]

remoteOriginJson :: Text -> Text -> Text
remoteOriginJson url artifact =
  "{\"kind\":\"remote\",\"url\":\"" <> url <> "\",\"artifact\":\"" <> artifact <> "\"}"
