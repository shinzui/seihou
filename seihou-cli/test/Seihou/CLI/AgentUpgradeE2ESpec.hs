-- | @seihou agent upgrade@ through the real binary: the brief under
-- @--debug@, the never-fail fallbacks, and @--check@ as the definition of
-- done. No provider is contacted.
module Seihou.CLI.AgentUpgradeE2ESpec (tests) where

import Control.Lens ((^.))
import Data.Char (isHexDigit)
import Data.Generics.Labels ()
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.SeihouBinary (seihouBinary)
import Seihou.CLI.UpdateSpec (CoOwnerWriteMode (..), SharedPathFixture (..))
import Seihou.CLI.UpgradeFixture (portableEnvironment, preparePortableFixture, snapshotTree)
import System.Directory (createDirectoryIfMissing, createFileLink, doesFileExist, findExecutable)
import System.Environment (getEnvironment)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (CreateProcess (..), proc, readCreateProcessWithExitCode)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "seihou agent upgrade end-to-end" spec

spec :: Spec
spec = do
  describe "seihou agent --debug upgrade" $ do
    it "prints the brief for a schema-6 project and changes nothing in it" $
      withSystemTempDirectory "seihou-agent-upgrade-debug" $ \root -> do
        fixture <- preparePortableFixture CoOwnerAppendsPredatingEvidence root
        before <- snapshotTree (fixture ^. #projectRoot)
        (code, out, err) <- runIn root fixture [] ["agent", "--debug", "upgrade", "alpha"]
        expectSuccess "agent --debug upgrade" code out err
        out `shouldSatisfy` T.isInfixOf "seihou agent upgrade alpha --check"
        out `shouldSatisfy` T.isInfixOf "## Repair playbook"
        out `shouldSatisfy` T.isInfixOf "schema 6"
        out `shouldSatisfy` T.isInfixOf ".gitignore"
        out `shouldNotSatisfy` hasDigest
        out `shouldNotSatisfy` T.isInfixOf "{{"
        err `shouldSatisfy` T.isInfixOf "Upgrade brief: "
        snapshotTree (fixture ^. #projectRoot) `shouldReturn` before

    it "writes a brief outside any project" $
      withSystemTempDirectory "seihou-agent-upgrade-empty" $ \root -> do
        let empty = root </> "empty"
        createDirectoryIfMissing True empty
        (code, out, err) <- runBare root empty [] ["agent", "--debug", "upgrade", "alpha"]
        expectSuccess "agent --debug upgrade outside a project" code out err
        out `shouldSatisfy` T.isInfixOf "There is no `.seihou/manifest.json` here"

    it "writes a brief for a manifest that is not JSON" $
      withSystemTempDirectory "seihou-agent-upgrade-corrupt" $ \root -> do
        fixture <- preparePortableFixture CoOwnerAppends root
        TIO.writeFile (fixture ^. #manifestPath) "{not json"
        (code, out, err) <- runIn root fixture [] ["agent", "--debug", "upgrade", "alpha"]
        expectSuccess "agent --debug upgrade on a corrupt manifest" code out err
        out `shouldSatisfy` T.isInfixOf "is not valid JSON"

    it "falls back to the built-in configuration when the configured provider is invalid" $
      withSystemTempDirectory "seihou-agent-upgrade-bad-provider" $ \root -> do
        fixture <- preparePortableFixture CoOwnerAppends root
        (code, out, err) <- runIn root fixture [] ["agent", "--provider", "not-a-provider", "--debug", "upgrade", "alpha"]
        expectSuccess "agent upgrade with an invalid provider" code out err
        out `shouldSatisfy` T.isInfixOf "fell back to the built-in default provider"

  describe "seihou agent upgrade without the provider's binary" $
    it "saves the brief, says how to use it, and exits 0" $
      withSystemTempDirectory "seihou-agent-upgrade-no-claude" $ \root -> do
        fixture <- preparePortableFixture CoOwnerAppends root
        binDirectory <- gitOnlyPath root
        (code, out, err) <- runIn root fixture [("PATH", binDirectory)] ["agent", "--provider", "claude-cli", "upgrade", "alpha"]
        expectSuccess "agent upgrade without claude" code out err
        out `shouldSatisfy` T.isInfixOf "Could not start the agent: claude is not on PATH"
        out `shouldSatisfy` T.isInfixOf "claude --append-system-prompt"
        case briefPath err of
          Nothing -> expectationFailure ("no brief path in stderr:\n" <> T.unpack err)
          Just path -> do
            doesFileExist path `shouldReturn` True
            TIO.readFile path >>= (`shouldSatisfy` T.isInfixOf "## Repair playbook")

  describe "seihou agent upgrade --check" $ do
    it "reports a healthy project ready" $
      withSystemTempDirectory "seihou-agent-upgrade-check-ready" $ \root -> do
        fixture <- preparePortableFixture CoOwnerAppends root
        (code, out, err) <- runIn root fixture [] ["agent", "upgrade", "alpha", "--check"]
        expectSuccess "--check" code out err
        out `shouldSatisfy` T.isSuffixOf "Upgrade readiness: ready\n"

    it "reports a schema-6 project not ready, and ready once seihou update has run" $
      withSystemTempDirectory "seihou-agent-upgrade-check-loop" $ \root -> do
        fixture <- preparePortableFixture CoOwnerAppendsPredatingEvidence root
        (code, out, err) <- runIn root fixture [] ["agent", "upgrade", "alpha", "--check"]
        expectSuccess "--check before the update" code out err
        out `shouldSatisfy` T.isInfixOf "Upgrade readiness: not ready (2 checks need attention)"
        out `shouldSatisfy` T.isInfixOf ".gitignore is shared with beta"

        (updateCode, updateOut, updateErr) <- runIn root fixture [] ["update", "alpha", "--json"]
        expectSuccess "update alpha" updateCode updateOut updateErr

        (afterCode, afterOut, afterErr) <- runIn root fixture [] ["agent", "upgrade", "alpha", "--check"]
        expectSuccess "--check after the update" afterCode afterOut afterErr
        afterOut `shouldSatisfy` T.isSuffixOf "Upgrade readiness: ready\n"

    it "exits 0 and is not ready outside a project" $
      withSystemTempDirectory "seihou-agent-upgrade-check-empty" $ \root -> do
        let empty = root </> "empty"
        createDirectoryIfMissing True empty
        (code, out, err) <- runBare root empty [] ["agent", "upgrade", "alpha", "--check"]
        expectSuccess "--check outside a project" code out err
        out `shouldSatisfy` T.isInfixOf "Upgrade readiness: not ready"

-- | Run the binary in the fixture's project with its configuration, the
-- portable-URL git mapping, and a private @XDG_STATE_HOME@.
runIn :: FilePath -> SharedPathFixture -> [(String, String)] -> [String] -> IO (ExitCode, Text, Text)
runIn root fixture extra =
  runWith (fixture ^. #projectRoot) (portableEnvironment root fixture <> extra <> [("XDG_STATE_HOME", root </> "state")])

-- | Run the binary in a directory that is no project at all.
runBare :: FilePath -> FilePath -> [(String, String)] -> [String] -> IO (ExitCode, Text, Text)
runBare root workDir extra =
  runWith workDir ([("XDG_CONFIG_HOME", root </> "xdg"), ("XDG_STATE_HOME", root </> "state")] <> extra)

runWith :: FilePath -> [(String, String)] -> [String] -> IO (ExitCode, Text, Text)
runWith workDir overrides args = do
  binary <- seihouBinary
  inherited <- getEnvironment
  let environment = overrides <> filter ((`notElem` map fst overrides) . fst) inherited
      command = (proc binary args) {cwd = Just workDir, env = Just environment}
  (exitCode, out, err) <- readCreateProcessWithExitCode command ""
  pure (exitCode, T.pack out, T.pack err)

-- | A directory holding only a link to @git@, to use as the whole @PATH@.
gitOnlyPath :: FilePath -> IO FilePath
gitOnlyPath root = do
  let directory = root </> "bin"
  createDirectoryIfMissing True directory
  found <- findExecutable "git"
  case found of
    Nothing -> fail "git is not on PATH"
    Just git -> createFileLink git (directory </> "git")
  pure directory

briefPath :: Text -> Maybe FilePath
briefPath err = case [T.strip rest | line <- T.lines err, Just rest <- [T.stripPrefix "Upgrade brief: " line]] of
  path : _ -> Just (T.unpack path)
  [] -> Nothing

-- | Whether the text contains a full SHA-256 digest (an application id).
hasDigest :: Text -> Bool
hasDigest = any ((>= 64) . T.length) . T.split (not . isHexDigit)

expectSuccess :: String -> ExitCode -> Text -> Text -> Expectation
expectSuccess label code out err = case code of
  ExitSuccess -> pure ()
  ExitFailure n ->
    expectationFailure
      (label <> " exited " <> show n <> "\nstdout:\n" <> T.unpack out <> "\nstderr:\n" <> T.unpack err)
