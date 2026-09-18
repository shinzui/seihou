-- | Machine-local origins, end to end through the real binary: installing
-- from a local checkout must not put a path into the manifest, and
-- @seihou manifest repair-origins@ must fix a manifest that already has one.
module Seihou.CLI.RepairOriginsE2ESpec (tests) where

import Control.Lens ((^.))
import Data.Generics.Labels ()
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.SeihouBinary (seihouBinary)
import System.Directory (createDirectoryIfMissing)
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
