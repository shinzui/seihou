-- | Machine-local origins, end to end through the real binary: installing
-- from a local checkout must not put a path into the manifest, and
-- @seihou manifest repair-origins@ must fix a manifest that already has one.
module Seihou.CLI.RepairOriginsE2ESpec (tests) where

import Control.Lens ((^.))
import Data.ByteString.Lazy qualified as LBS
import Data.Generics.Labels ()
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.ManifestRepairOrigins (overManifestOrigins)
import Seihou.CLI.SeihouBinary (seihouBinary)
import Seihou.CLI.UpdateSpec (CoOwnerWriteMode (..), SharedPathFixture (..), prepareSharedPathFixture)
import Seihou.Core.Types (ArtifactOrigin (..))
import Seihou.Manifest.Types (manifestFromJSON, manifestToJSON)
import System.Directory (createDirectoryIfMissing, removeFile)
import System.Environment (getEnvironment)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (CreateProcess (..), callProcess, proc, readCreateProcessWithExitCode)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "repair machine-local origins end-to-end" spec

-- | The published remote the checkout claims. Nothing is fetched from it
-- unless a test maps it back onto the checkout with 'insteadOf'.
fakeRemote :: Text
fakeRemote = "https://example.invalid/r.git"

spec :: Spec
spec = do
  describe "seihou install <local path>" $ do
    it "records the checkout's published remote, and the manifest never sees the path" $
      withSystemTempDirectory "seihou-install-local-published" $ \root -> do
        binary <- seihouBinary
        checkout <- prepareCheckout root
        publishHead checkout
        let home = root </> "home"
            project = root </> "project"
        createDirectoryIfMissing True project

        (installCode, installOut, installErr) <- runIn binary home root [] ["install", checkout]
        expectSuccess "install" installCode installOut installErr
        installOut `shouldSatisfy` T.isInfixOf ("note: recording origin " <> fakeRemote)
        originFile <- TIO.readFile (home </> "seihou" </> "installed" </> "demo" </> ".seihou-origin.json")
        originFile `shouldSatisfy` T.isInfixOf fakeRemote
        originFile `shouldNotSatisfy` T.isInfixOf (T.pack checkout)

        (runCode, runOut, runErr) <- runIn binary home project [] ["run", "demo"]
        expectSuccess "run" runCode runOut runErr
        manifest <- TIO.readFile (project </> ".seihou" </> "manifest.json")
        manifest `shouldSatisfy` T.isInfixOf ("\"url\":\"" <> fakeRemote <> "\"")
        manifest `shouldNotSatisfy` T.isInfixOf (T.pack checkout)

        -- Installing the recorded remote afterwards is the same artifact, so
        -- it reinstalls rather than being refused as a different source.
        (againCode, againOut, againErr) <-
          runIn binary home root (insteadOf checkout) ["install", T.unpack fakeRemote]
        expectSuccess "reinstall from the remote" againCode againOut againErr
        againOut `shouldNotSatisfy` T.isInfixOf "Refusing"

    it "records an unpublished checkout's origin as unknown and warns" $
      withSystemTempDirectory "seihou-install-local-unpublished" $ \root -> do
        binary <- seihouBinary
        checkout <- prepareCheckout root
        let home = root </> "home"
            project = root </> "project"
        createDirectoryIfMissing True project

        (installCode, installOut, installErr) <- runIn binary home root [] ["install", checkout]
        expectSuccess "install" installCode installOut installErr
        installOut `shouldSatisfy` T.isInfixOf "warning: "
        installOut `shouldSatisfy` T.isInfixOf "no origin remote"

        (runCode, runOut, runErr) <- runIn binary home project [] ["run", "demo"]
        expectSuccess "run" runCode runOut runErr
        manifest <- TIO.readFile (project </> ".seihou" </> "manifest.json")
        manifest `shouldSatisfy` T.isInfixOf "\"kind\":\"local\""
        manifest `shouldNotSatisfy` T.isInfixOf (T.pack checkout)

  describe "seihou manifest repair-origins" $ do
    it "repairs the reported path origin so a targeted update certifies again" $
      withSystemTempDirectory "seihou-repair-origins" $ \root -> do
        binary <- seihouBinary
        fixture <- prepareDamagedFixture root
        let run = runIn binary (fixture ^. #xdgHome) (fixture ^. #projectRoot) (remotesFor root)

        -- The fixture is a schema-6 manifest, as in the report. The command
        -- works on the current schema and says how to get there.
        (oldCode, oldOut, _) <- run ["manifest", "repair-origins", "--dry-run"]
        oldCode `shouldBe` ExitFailure 1
        oldOut `shouldSatisfy` T.isInfixOf "seihou manifest upgrade"
        (upgradeCode, upgradeOut, upgradeErr) <- run ["manifest", "upgrade"]
        expectSuccess "manifest upgrade" upgradeCode upgradeOut upgradeErr

        -- The reported failure: certifying the shared .gitignore needs beta's
        -- recorded state, and beta's recorded origin is a path.
        (failedCode, failedOut, _) <- run ["update", "alpha", "--dry-run", "--json"]
        failedCode `shouldSatisfy` (/= ExitSuccess)
        failedOut `shouldSatisfy` T.isInfixOf "different origin than recorded"

        before <- LBS.readFile (fixture ^. #manifestPath)
        (dryCode, dryOut, dryErr) <- run ["manifest", "repair-origins", "--dry-run"]
        expectSuccess "repair-origins --dry-run" dryCode dryOut dryErr
        dryOut `shouldSatisfy` T.isInfixOf (damagedPath <> "\n  -> " <> fakeRemote)
        dryOut `shouldSatisfy` T.isInfixOf "evidence: the installed copy of beta"
        dryOut `shouldSatisfy` T.isInfixOf "--dry-run: nothing was written."
        LBS.readFile (fixture ^. #manifestPath) `shouldReturn` before

        (repairCode, repairOut, repairErr) <- run ["manifest", "repair-origins"]
        expectSuccess "repair-origins" repairCode repairOut repairErr
        manifest <- TIO.readFile (fixture ^. #manifestPath)
        manifest `shouldNotSatisfy` T.isInfixOf damagedPath
        manifest `shouldSatisfy` T.isInfixOf fakeRemote

        (updateCode, updateOut, updateErr) <- run ["update", "alpha", "--dry-run", "--json"]
        expectSuccess "update after repair" updateCode updateOut updateErr
        updateOut `shouldNotSatisfy` T.isInfixOf "different origin than recorded"

        (againCode, againOut, againErr) <- run ["manifest", "repair-origins"]
        expectSuccess "second repair" againCode againOut againErr
        againOut `shouldSatisfy` T.isInfixOf "nothing to repair"

    it "exits 1 for a path it cannot resolve and accepts --set for it" $
      withSystemTempDirectory "seihou-repair-origins-set" $ \root -> do
        binary <- seihouBinary
        fixture <- prepareDamagedFixture root
        let run = runIn binary (fixture ^. #xdgHome) (fixture ^. #projectRoot) (remotesFor root)
        (upgradeCode, upgradeOut, upgradeErr) <- run ["manifest", "upgrade"]
        expectSuccess "manifest upgrade" upgradeCode upgradeOut upgradeErr
        removeFile (fixture ^. #betaInstalledPath </> ".seihou-origin.json")

        before <- LBS.readFile (fixture ^. #manifestPath)
        (code, out, _) <- run ["manifest", "repair-origins"]
        code `shouldBe` ExitFailure 1
        out `shouldSatisfy` T.isInfixOf "no remote found"
        out `shouldSatisfy` T.isInfixOf "pass --set beta=<url>"
        LBS.readFile (fixture ^. #manifestPath) `shouldReturn` before

        (localCode, localOut, _) <- run ["manifest", "repair-origins", "--set", "beta=/elsewhere/modules"]
        localCode `shouldBe` ExitFailure 1
        localOut `shouldSatisfy` T.isInfixOf "is a path on this machine"

        (setCode, setOut, setErr) <- run ["manifest", "repair-origins", "--set", "beta=" <> T.unpack fakeRemote]
        expectSuccess "repair-origins --set" setCode setOut setErr
        setOut `shouldSatisfy` T.isInfixOf ("evidence: --set beta=" <> fakeRemote)
        TIO.readFile (fixture ^. #manifestPath) `shouldReturnSatisfy` (not . T.isInfixOf damagedPath)

-- | The path the reported project recorded as beta's origin.
damagedPath :: Text
damagedPath = "/nonexistent/seihou-modules"

-- | Alpha's origin once it is not a path: an https URL git maps back onto the
-- fixture's local remote.
alphaRemote :: Text
alphaRemote = "https://example.invalid/alpha.git"

-- | The two-application shared-path fixture, damaged the way the reported
-- project was. Beta's manifest origins name a path on some other machine,
-- while its installed copy records the real remote. Alpha is given a real
-- (mapped) remote too, so only beta needs repairing.
prepareDamagedFixture :: FilePath -> IO SharedPathFixture
prepareDamagedFixture root = do
  fixture <- prepareSharedPathFixture CoOwnerAppendsUnrecorded root
  bytes <- LBS.readFile (fixture ^. #manifestPath)
  manifest <- either fail pure (manifestFromJSON bytes)
  let damage = \case
        RemoteOrigin _ "alpha" _ -> RemoteOrigin alphaRemote "alpha" Nothing
        RemoteOrigin _ "beta" _ -> RemoteOrigin damagedPath "beta" (Just "seihou-modules")
        other -> other
  LBS.writeFile (fixture ^. #manifestPath) (manifestToJSON (overManifestOrigins damage manifest))
  let installed = fixture ^. #xdgHome </> "seihou" </> "installed"
  TIO.writeFile
    (installed </> "alpha" </> ".seihou-origin.json")
    ("{\"sourceUrl\":\"" <> alphaRemote <> "\",\"version\":\"1.0.0\"}")
  TIO.writeFile
    (fixture ^. #betaInstalledPath </> ".seihou-origin.json")
    ("{\"sourceUrl\":\"" <> fakeRemote <> "\",\"repoName\":\"seihou-modules\",\"version\":\"1.0.0\"}")
  pure fixture

-- | Map both fixture remotes' https URLs onto their local repositories.
remotesFor :: FilePath -> [(String, String)]
remotesFor root =
  [ ("GIT_CONFIG_COUNT", "2"),
    ("GIT_CONFIG_KEY_0", "url." <> (root </> "remote" </> "alpha") <> ".insteadOf"),
    ("GIT_CONFIG_VALUE_0", T.unpack alphaRemote),
    ("GIT_CONFIG_KEY_1", "url." <> (root </> "remote" </> "beta") <> ".insteadOf"),
    ("GIT_CONFIG_VALUE_1", T.unpack fakeRemote)
  ]

shouldReturnSatisfy :: IO Text -> (Text -> Bool) -> Expectation
shouldReturnSatisfy action predicate = action >>= (`shouldSatisfy` predicate)

-- | A git checkout holding the single module @demo@, with one commit.
prepareCheckout :: FilePath -> IO FilePath
prepareCheckout root = do
  let checkout = root </> "checkout" </> "demo"
  createDirectoryIfMissing True (checkout </> "files")
  TIO.writeFile (checkout </> "module.dhall") (moduleDhall "demo" "1.0.0")
  TIO.writeFile (checkout </> "files" </> "README.tmpl") "# {{project.name}}\n"
  git checkout ["init", "-q", "-b", "main"]
  git checkout ["add", "."]
  git checkout ["commit", "-qm", "init"]
  pure checkout

-- | Point the checkout's @origin@ at 'fakeRemote' and pretend HEAD was pushed.
publishHead :: FilePath -> IO ()
publishHead checkout = do
  git checkout ["remote", "add", "origin", T.unpack fakeRemote]
  git checkout ["update-ref", "refs/remotes/origin/main", "HEAD"]

git :: FilePath -> [String] -> IO ()
git dir args =
  callProcess
    "git"
    (["-C", dir, "-c", "user.name=Seihou Test", "-c", "user.email=test@example.com", "-c", "commit.gpgsign=false"] <> args)

-- | Git configuration, passed through the environment, that makes
-- 'fakeRemote' resolve to a local directory, so a command that fetches the
-- recorded remote can run without a network.
insteadOf :: FilePath -> [(String, String)]
insteadOf directory =
  [ ("GIT_CONFIG_COUNT", "1"),
    ("GIT_CONFIG_KEY_0", "url." <> directory <> ".insteadOf"),
    ("GIT_CONFIG_VALUE_0", T.unpack fakeRemote)
  ]

-- | Run the binary with @home@ as @XDG_CONFIG_HOME@, in @workDir@, with extra
-- environment variables.
runIn :: FilePath -> FilePath -> FilePath -> [(String, String)] -> [String] -> IO (ExitCode, Text, Text)
runIn binary home workDir extra args = do
  inherited <- getEnvironment
  let overridden = "XDG_CONFIG_HOME" : map fst extra
      environment =
        ("XDG_CONFIG_HOME", home) : extra <> filter ((`notElem` overridden) . fst) inherited
      command = (proc binary args) {cwd = Just workDir, env = Just environment}
  (exitCode, out, err) <- readCreateProcessWithExitCode command ""
  pure (exitCode, T.pack out, T.pack err)

expectSuccess :: String -> ExitCode -> Text -> Text -> Expectation
expectSuccess label code out err = case code of
  ExitSuccess -> pure ()
  ExitFailure n ->
    expectationFailure
      (label <> " exited " <> show n <> "\nstdout:\n" <> T.unpack out <> "\nstderr:\n" <> T.unpack err)

-- | A module with one defaulted variable and one generated file.
moduleDhall :: Text -> Text -> Text
moduleDhall name version =
  T.unlines
    [ "{ name = \"" <> name <> "\"",
      ", version = Some \"" <> version <> "\"",
      ", description = None Text",
      ", vars = [{ name = \"project.name\", type = \"text\", default = Some \"demo\", description = None Text, required = False, validation = None Text }]",
      ", exports = [] : List { var : Text, alias : Optional Text }",
      ", prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }",
      ", steps = [{ strategy = \"template\", src = \"README.tmpl\", dest = \"README.md\", when = None Text, patch = None Text }]",
      ", commands = [] : List { run : Text, workDir : Optional Text, when : Optional Text }",
      ", dependencies = [] : List Text",
      ", removal = None { steps : List { action : Text, dest : Text, src : Optional Text }, commands : List { run : Text, workDir : Optional Text, when : Optional Text } }",
      "}"
    ]
