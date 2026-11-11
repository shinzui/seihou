-- | The initiative's headline claim, driven end to end through the real
-- binary: two developers can share @.seihou\/manifest.json@ safely.
--
-- Four mechanisms have to hold together for that to be true — the manifest
-- records portable origins, every command resolves them locally, seihou
-- refuses to generate from an artifact older than the manifest records, and a
-- manifest written by an older seihou can be converted. Each has its own unit
-- tests. This spec is what stops them from drifting apart.
module Seihou.CLI.SharedManifestE2ESpec (tests) where

import Control.Lens ((^.))
import Data.ByteString.Lazy qualified as LBS
import Data.Generics.Labels ()
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.TwoDeveloperFixture
  ( TwoDeveloperFixture (..),
    gitCommitAll,
    gitStatus,
    installModuleVersion,
    installModuleVersionFrom,
    moduleSourceUrl,
    prepareTwoDeveloperFixture,
    resetWorkingTree,
    runSeihouAs,
    seihouBinary,
  )
import System.Directory (doesFileExist, removeDirectoryRecursive)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "shared manifest across developers" spec

spec :: Spec
spec = do
  it "records a portable manifest and refuses a stale developer" $
    withGeneratedProject "seihou-shared-refuse" $ \binary fixture -> do
      manifest <- TIO.readFile (fixture ^. #manifestPath)
      manifest `shouldSatisfy` T.isInfixOf "\"kind\":\"remote\""
      manifest `shouldSatisfy` T.isInfixOf moduleSourceUrl
      manifest `shouldNotSatisfy` T.isInfixOf (T.pack (fixture ^. #homeA))
      manifest `shouldNotSatisfy` T.isInfixOf (T.pack (fixture ^. #homeB))

      (code, out, err) <- runSeihouAs binary fixture (fixture ^. #homeB) ["run", "demo"]
      code `shouldSatisfy` (/= ExitSuccess)
      let reported = out <> err
      reported `shouldSatisfy` T.isInfixOf "2.0.0"
      reported `shouldSatisfy` T.isInfixOf "1.4.0"
      reported `shouldSatisfy` T.isInfixOf "seihou upgrade"

      -- The assertion that matters: an exit code proves the command reported
      -- failure, only an unchanged working tree proves it did not write first.
      gitStatus fixture `shouldReturn` ""

  it "proceeds under --allow-downgrade and says so" $
    withGeneratedProject "seihou-shared-allow" $ \binary fixture -> do
      (code, out, err) <-
        runSeihouAs binary fixture (fixture ^. #homeB) ["run", "demo", "--allow-downgrade"]
      expectSuccess "developer B's deliberate downgrade" code out err

      -- A deliberate downgrade must still be visible; silently honouring the
      -- flag would hide exactly the change the guard exists to make legible.
      let reported = out <> err
      reported `shouldSatisfy` T.isInfixOf "2.0.0"
      reported `shouldSatisfy` T.isInfixOf "1.4.0"

      manifest <- TIO.readFile (fixture ^. #manifestPath)
      manifest `shouldSatisfy` T.isInfixOf "\"version\":\"1.4.0\""
      TIO.readFile (fixture ^. #projectFile) `shouldReturnSatisfy` T.isInfixOf "demo 1.4.0"

  it "succeeds once the stale developer upgrades locally" $
    withGeneratedProject "seihou-shared-upgrade" $ \binary fixture -> do
      resetWorkingTree fixture
      installModuleVersion (fixture ^. #homeB) (fixture ^. #moduleName) "2.0.0"

      generated <- TIO.readFile (fixture ^. #projectFile)
      (code, out, err) <- runSeihouAs binary fixture (fixture ^. #homeB) ["run", "demo"]
      expectSuccess "developer B's run after upgrading" code out err

      -- Regenerating from the same version with the same inputs produces the
      -- same bytes, so the generated file is untouched. The manifest is
      -- rewritten regardless, because every run stamps a fresh 'generatedAt'
      -- and 'appliedAt' — that is the only path git reports.
      status <- gitStatus fixture
      map T.strip (T.lines status) `shouldBe` ["M .seihou/manifest.json"]
      TIO.readFile (fixture ^. #projectFile) `shouldReturn` generated
      manifest <- TIO.readFile (fixture ^. #manifestPath)
      manifest `shouldSatisfy` T.isInfixOf "\"version\":\"2.0.0\""

  it "rejects, upgrades, and then accepts a legacy manifest" $
    withGeneratedProject "seihou-shared-legacy" $ \binary fixture -> do
      TIO.writeFile (fixture ^. #manifestPath) legacyManifest
      gitCommitAll fixture "test: commit a manifest from an older seihou"

      (statusCode, statusOut, statusErr) <- runSeihouAs binary fixture (fixture ^. #homeB) ["status"]
      statusCode `shouldSatisfy` (/= ExitSuccess)
      let rejected = statusOut <> statusErr
      rejected `shouldSatisfy` T.isInfixOf "schema version 5"
      rejected `shouldSatisfy` T.isInfixOf "seihou manifest upgrade"

      before <- LBS.readFile (fixture ^. #manifestPath)
      (dryCode, dryOut, dryErr) <-
        runSeihouAs binary fixture (fixture ^. #homeB) ["manifest", "upgrade", "--dry-run"]
      expectSuccess "the dry-run upgrade" dryCode dryOut dryErr
      dryOut `shouldSatisfy` T.isInfixOf foreignPath
      dryOut `shouldSatisfy` T.isInfixOf ("remote " <> moduleSourceUrl)
      LBS.readFile (fixture ^. #manifestPath) `shouldReturn` before

      (upgradeCode, upgradeOut, upgradeErr) <-
        runSeihouAs binary fixture (fixture ^. #homeB) ["manifest", "upgrade"]
      expectSuccess "the upgrade" upgradeCode upgradeOut upgradeErr
      manifest <- TIO.readFile (fixture ^. #manifestPath)
      manifest `shouldSatisfy` T.isInfixOf "\"kind\":\"remote\""
      manifest `shouldNotSatisfy` T.isInfixOf "someone-else"

      (afterCode, afterOut, afterErr) <- runSeihouAs binary fixture (fixture ^. #homeB) ["status"]
      expectSuccess "status after the upgrade" afterCode afterOut afterErr

  describe "equivalent public GitHub transport spellings" $ do
    it "status accepts an SSH-recorded manifest against an HTTPS install without writing" $
      withTransportProject "seihou-shared-ssh-https" githubSsh githubHttps $ \binary fixture -> do
        out <- statusWithoutWrites binary fixture
        out `shouldNotSatisfy` T.isInfixOf "Artifacts that differ"
        out `shouldNotSatisfy` T.isInfixOf "this project records"

    it "status accepts an HTTPS-recorded manifest against an SSH install without writing" $
      withTransportProject "seihou-shared-https-ssh" githubHttps githubSsh $ \binary fixture -> do
        out <- statusWithoutWrites binary fixture
        out `shouldNotSatisfy` T.isInfixOf "Artifacts that differ"

    it "status still reports a genuinely different repository" $
      withTransportProject "seihou-shared-other-repo" githubSsh "https://github.com/shinzui/other-modules.git" $ \binary fixture -> do
        out <- statusWithoutWrites binary fixture
        out `shouldSatisfy` T.isInfixOf "Artifacts that differ"
        out `shouldSatisfy` T.isInfixOf "this project records"
        out `shouldSatisfy` T.isInfixOf "other-modules"

    it "status still reports a different owner" $
      withTransportProject "seihou-shared-other-owner" githubSsh "https://github.com/someone/seihou-modules.git" $ \binary fixture -> do
        out <- statusWithoutWrites binary fixture
        out `shouldSatisfy` T.isInfixOf "this project records"

    it "status keeps the missing-producer notice when nothing is installed" $
      withTransportProject "seihou-shared-empty-cache" githubSsh githubHttps $ \binary fixture -> do
        removeDirectoryRecursive (fixture ^. #homeB </> "seihou" </> "installed" </> "demo")
        out <- statusWithoutWrites binary fixture
        out `shouldSatisfy` T.isInfixOf "Remote producer cache: 1 not cached locally"
        out `shouldNotSatisfy` T.isInfixOf "Artifacts that differ"

    it "run still refuses an older version from an equivalent spelling" $
      withSystemTempDirectory "seihou-shared-ssh-stale" $ \root -> do
        fixture <- prepareTwoDeveloperFixture root "2.0.0" "1.4.0"
        installModuleVersionFrom githubSsh (fixture ^. #homeA) "demo" "2.0.0"
        installModuleVersionFrom githubHttps (fixture ^. #homeB) "demo" "1.4.0"
        binary <- seihouBinary
        (code, out, err) <- runSeihouAs binary fixture (fixture ^. #homeA) ["run", "demo"]
        expectSuccess "developer A's run" code out err
        gitCommitAll fixture "feat: apply demo 2.0.0 over SSH"
        (staleCode, staleOut, staleErr) <- runSeihouAs binary fixture (fixture ^. #homeB) ["run", "demo"]
        staleCode `shouldSatisfy` (/= ExitSuccess)
        (staleOut <> staleErr) `shouldSatisfy` T.isInfixOf "1.4.0"
        gitStatus fixture `shouldReturn` ""

githubSsh :: Text
githubSsh = "git@github.com:shinzui/seihou-modules.git"

githubHttps :: Text
githubHttps = "https://github.com/shinzui/seihou-modules.git"

-- | Models existing state rather than repairing it: developer A installed
-- @demo@ 2.0.0 recording @recordedUrl@ and generated the project with it;
-- developer B has the same version installed recording @installedUrl@.
withTransportProject :: String -> Text -> Text -> (FilePath -> TwoDeveloperFixture -> IO ()) -> IO ()
withTransportProject label recordedUrl installedUrl action =
  withSystemTempDirectory label $ \root -> do
    fixture <- prepareTwoDeveloperFixture root "2.0.0" "2.0.0"
    installModuleVersionFrom recordedUrl (fixture ^. #homeA) "demo" "2.0.0"
    installModuleVersionFrom installedUrl (fixture ^. #homeB) "demo" "2.0.0"
    binary <- seihouBinary
    (code, out, err) <- runSeihouAs binary fixture (fixture ^. #homeA) ["run", "demo"]
    expectSuccess "developer A's run" code out err
    manifest <- TIO.readFile (fixture ^. #manifestPath)
    manifest `shouldSatisfy` T.isInfixOf recordedUrl
    gitCommitAll fixture "feat: apply demo 2.0.0"
    action binary fixture

-- | Run developer B's ordinary @seihou status@ twice and prove it wrote
-- nothing: the project is clean and the manifest and installed metadata keep
-- their bytes. Returns the first run's combined output.
statusWithoutWrites :: FilePath -> TwoDeveloperFixture -> IO Text
statusWithoutWrites binary fixture = do
  let originFile = fixture ^. #homeB </> "seihou" </> "installed" </> "demo" </> ".seihou-origin.json"
  manifestBefore <- LBS.readFile (fixture ^. #manifestPath)
  originBefore <- readIfPresent originFile
  (code, out, err) <- runSeihouAs binary fixture (fixture ^. #homeB) ["status"]
  expectSuccess "developer B's status" code out err
  (againCode, againOut, againErr) <- runSeihouAs binary fixture (fixture ^. #homeB) ["status"]
  expectSuccess "developer B's repeated status" againCode againOut againErr
  againOut `shouldBe` out
  gitStatus fixture `shouldReturn` ""
  LBS.readFile (fixture ^. #manifestPath) `shouldReturn` manifestBefore
  readIfPresent originFile `shouldReturn` originBefore
  pure (out <> err)
  where
    readIfPresent path = do
      present <- doesFileExist path
      if present then Just <$> LBS.readFile path else pure Nothing

-- | Developer A, on 2.0.0, generates the project and commits. Developer B has
-- 1.4.0 installed. Every scenario starts here.
withGeneratedProject :: String -> (FilePath -> TwoDeveloperFixture -> IO ()) -> IO ()
withGeneratedProject label action =
  withSystemTempDirectory label $ \root -> do
    fixture <- prepareTwoDeveloperFixture root "2.0.0" "1.4.0"
    binary <- seihouBinary
    (code, out, err) <- runSeihouAs binary fixture (fixture ^. #homeA) ["run", "demo"]
    expectSuccess "developer A's run" code out err
    gitCommitAll fixture "feat: apply demo 2.0.0"
    action binary fixture

-- | The absolute path a third machine — neither developer's — recorded, the
-- kind of value a schema-5 manifest is full of.
foreignPath :: Text
foreignPath = "/Users/someone-else/.config/seihou/installed/demo"

-- | A manifest as a released seihou wrote them: schema 5, with the module's
-- source recorded as somebody else's absolute path.
--
-- It records 1.4.0, which is what developer B has installed, so the upgrade's
-- own guard is satisfied and the scenario exercises the conversion rather than
-- the refusal.
legacyManifest :: Text
legacyManifest =
  T.concat
    [ "{\"version\":5",
      ",\"generatedAt\":\"2026-07-01T12:00:00Z\"",
      ",\"modules\":[{\"name\":\"demo\",\"source\":\"",
      foreignPath,
      "\",\"version\":\"1.4.0\",\"appliedAt\":\"2026-07-01T12:00:00Z\"}]",
      ",\"variables\":{},\"files\":{},\"applications\":[],\"blueprintMigrations\":[]}"
    ]

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

shouldReturnSatisfy :: IO Text -> (Text -> Bool) -> Expectation
shouldReturnSatisfy action predicate = action >>= (`shouldSatisfy` predicate)
