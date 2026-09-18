module Seihou.CLI.UpdateE2ESpec (tests) where

import Control.Lens ((&), (.~), (^.))
import Data.ByteString.Lazy qualified as LBS
import Data.Char (isHexDigit)
import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.SeihouBinary (seihouBinary)
import Seihou.CLI.UpdateSpec
  ( CoOwnerWriteMode (..),
    SharedPathFixture (..),
    UpdateFixture (..),
    prepareSharedPathFixture,
    prepareUpdateFixture,
  )
import Seihou.Core.Types (ManifestSchemaVersion (..), SharedWriteMode (..))
import Seihou.Manifest.Types (manifestFromJSON, manifestToJSON)
import System.Directory (doesFileExist, renameDirectory)
import System.Environment (getEnvironment)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (CreateProcess (..), callProcess, proc, readCreateProcessWithExitCode, readProcess)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Update end-to-end" spec

spec :: Spec
spec = do
  it "updates through the executable and preserves a non-overlapping user edit" $
    withSystemTempDirectory "seihou-update-executable" $ \root -> do
      fixture <- prepareUpdateFixture root
      binary <- seihouBinary
      TIO.writeFile (fixture ^. #projectFile) "hello accepted by-user\nkeep\nv1\n"
      (exitCode, stdoutText, stderrText) <- runSeihou binary fixture ["update", "demo", "--json"]
      case exitCode of
        ExitSuccess -> pure ()
        ExitFailure code -> expectationFailure ("update exited " <> show code <> "\nstdout:\n" <> T.unpack stdoutText <> "\nstderr:\n" <> T.unpack stderrText)
      stdoutText `shouldSatisfy` T.isInfixOf "\"outcome\":\"applied\""
      stdoutText `shouldSatisfy` T.isInfixOf "\"skippedUnchanged\":1"
      stdoutText `shouldNotSatisfy` T.isInfixOf "Apply?"
      stderrText `shouldNotSatisfy` T.isInfixOf "Apply?"
      TIO.readFile (fixture ^. #projectFile) `shouldReturn` "hello accepted by-user\nkeep\nv2\n"
      TIO.readFile (fixture ^. #installedModule <> "/module.dhall")
        `shouldReturnSatisfy` T.isInfixOf "Some \"2.0.0\""
      doesFileExist (fixture ^. #projectRoot <> "/command.log") `shouldReturn` False
      (statusExit, statusOut, _) <- runSeihou binary fixture ["status"]
      statusExit `shouldBe` ExitSuccess
      statusOut `shouldNotSatisfy` T.isInfixOf "seihou update demo"
      afterApply <- LBS.readFile (fixture ^. #manifestPath)
      (noOpExit, noOpOut, noOpErr) <- runSeihou binary fixture ["update", "demo", "--json"]
      noOpExit `shouldBe` ExitSuccess
      noOpOut `shouldSatisfy` T.isInfixOf "\"alreadyUpToDate\":true"
      noOpOut `shouldSatisfy` T.isInfixOf "\"outcome\":\"plan\""
      noOpErr `shouldNotSatisfy` T.isInfixOf "Apply?"
      LBS.readFile (fixture ^. #manifestPath) `shouldReturn` afterApply

  it "keeps project, manifest, and installed cache byte-identical for JSON dry-run" $
    withSystemTempDirectory "seihou-update-executable-dry" $ \root -> do
      fixture <- prepareUpdateFixture root
      binary <- seihouBinary
      beforeProject <- TIO.readFile (fixture ^. #projectFile)
      beforeManifest <- LBS.readFile (fixture ^. #manifestPath)
      beforeInstalled <- TIO.readFile (fixture ^. #installedModule <> "/module.dhall")
      (exitCode, stdoutText, _) <- runSeihou binary fixture ["update", "--dry-run", "--json"]
      exitCode `shouldBe` ExitSuccess
      stdoutText `shouldSatisfy` T.isInfixOf "\"outcome\":\"plan\""
      TIO.readFile (fixture ^. #projectFile) `shouldReturn` beforeProject
      LBS.readFile (fixture ^. #manifestPath) `shouldReturn` beforeManifest
      TIO.readFile (fixture ^. #installedModule <> "/module.dhall") `shouldReturn` beforeInstalled

  it "commits exactly the managed update paths with a requested Conventional Commit message" $
    withSystemTempDirectory "seihou-update-executable-commit" $ \root -> do
      fixture <- prepareUpdateFixture root
      binary <- seihouBinary
      callProcess "git" ["-C", fixture ^. #projectRoot, "init", "-q"]
      callProcess "git" ["-C", fixture ^. #projectRoot, "config", "user.name", "Seihou Test"]
      callProcess "git" ["-C", fixture ^. #projectRoot, "config", "user.email", "test@example.com"]
      callProcess "git" ["-C", fixture ^. #projectRoot, "add", "."]
      callProcess "git" ["-C", fixture ^. #projectRoot, "commit", "-qm", "test: record v1 fixture"]
      (exitCode, stdoutText, stderrText) <-
        runSeihou
          binary
          fixture
          ["update", "demo", "--json", "--commit-message", "chore(seihou): update demo"]
      case exitCode of
        ExitSuccess -> pure ()
        ExitFailure code -> expectationFailure ("update exited " <> show code <> "\nstdout:\n" <> T.unpack stdoutText <> "\nstderr:\n" <> T.unpack stderrText)
      subject <- T.strip . T.pack <$> readProcess "git" ["-C", fixture ^. #projectRoot, "log", "-1", "--pretty=%s"] ""
      subject `shouldBe` "chore(seihou): update demo"
      worktree <- T.strip . T.pack <$> readProcess "git" ["-C", fixture ^. #projectRoot, "status", "--porcelain"] ""
      worktree `shouldBe` ""

  it "retains an edited orphan under --force" $
    withSystemTempDirectory "seihou-update-executable-orphan" $ \root -> do
      fixture <- prepareUpdateFixture root
      binary <- seihouBinary
      let modulePath = fixture ^. #remote <> "/module.dhall"
      moduleBody <- TIO.readFile modulePath
      TIO.writeFile
        modulePath
        ( T.replace
            ", steps = [{ strategy = \"template\", src = \"README.tmpl\", dest = \"README.md\", when = None Text, patch = None Text }]"
            ", steps = [] : List { strategy : Text, src : Text, dest : Text, when : Optional Text, patch : Optional Text }"
            moduleBody
        )
      callProcess "git" ["-C", fixture ^. #remote, "add", "module.dhall"]
      callProcess "git" ["-C", fixture ^. #remote, "-c", "user.name=Seihou Test", "-c", "user.email=test@example.com", "commit", "-qm", "remove generated file"]
      TIO.writeFile (fixture ^. #projectFile) "user-owned orphan\n"
      (exitCode, stdoutText, stderrText) <- runSeihou binary fixture ["update", "demo", "--force", "--json"]
      case exitCode of
        ExitSuccess -> pure ()
        ExitFailure code -> expectationFailure ("update exited " <> show code <> "\nstdout:\n" <> T.unpack stdoutText <> "\nstderr:\n" <> T.unpack stderrText)
      stdoutText `shouldSatisfy` T.isInfixOf "\"editedOrphans\":1"
      TIO.readFile (fixture ^. #projectFile) `shouldReturn` "user-owned orphan\n"
      TIO.readFile (fixture ^. #manifestPath) `shouldReturnSatisfy` T.isInfixOf "README.md"

  it "reports an unresolved overlap before publishing project, manifest, or cache state" $
    withSystemTempDirectory "seihou-update-executable-conflict" $ \root -> do
      fixture <- prepareUpdateFixture root
      binary <- seihouBinary
      TIO.writeFile (fixture ^. #remote <> "/files/README.tmpl") "candidate {{project.name}}\nkeep\nv2\n"
      callProcess "git" ["-C", fixture ^. #remote, "add", "files/README.tmpl"]
      callProcess "git" ["-C", fixture ^. #remote, "-c", "user.name=Seihou Test", "-c", "user.email=test@example.com", "commit", "-qm", "overlap"]
      TIO.writeFile (fixture ^. #projectFile) "user accepted\nkeep\nv1\n"
      beforeManifest <- LBS.readFile (fixture ^. #manifestPath)
      beforeInstalled <- LBS.readFile (fixture ^. #installedModule <> "/module.dhall")
      (exitCode, stdoutText, _) <- runSeihou binary fixture ["update", "demo", "--json"]
      exitCode `shouldSatisfy` (/= ExitSuccess)
      stdoutText `shouldSatisfy` T.isInfixOf "\"code\":\"unresolved_conflicts\""
      TIO.readFile (fixture ^. #projectFile) `shouldReturn` "user accepted\nkeep\nv1\n"
      LBS.readFile (fixture ^. #manifestPath) `shouldReturn` beforeManifest
      LBS.readFile (fixture ^. #installedModule <> "/module.dhall") `shouldReturn` beforeInstalled
      (forceExit, forceOut, forceErr) <- runSeihou binary fixture ["update", "demo", "--force", "--json"]
      case forceExit of
        ExitSuccess -> pure ()
        ExitFailure code -> expectationFailure ("forced update exited " <> show code <> "\nstdout:\n" <> T.unpack forceOut <> "\nstderr:\n" <> T.unpack forceErr)
      forceOut `shouldSatisfy` T.isInfixOf "\"outcome\":\"applied\""
      TIO.readFile (fixture ^. #projectFile) `shouldReturn` "candidate accepted\nkeep\nv2\n"

  it "updates one owner of an additive shared path and leaves the other's lines intact" $
    withSystemTempDirectory "seihou-update-shared-additive" $ \root -> do
      fixture <- prepareSharedPathFixture CoOwnerAppends root
      binary <- seihouBinary
      (exitCode, stdoutText, stderrText) <- runSeihouShared binary fixture ["update", "alpha", "--json"]
      case exitCode of
        ExitSuccess -> pure ()
        ExitFailure code ->
          expectationFailure
            ("update exited " <> show code <> "\nstdout:\n" <> T.unpack stdoutText <> "\nstderr:\n" <> T.unpack stderrText)
      stdoutText `shouldSatisfy` T.isInfixOf "\"outcome\":\"applied\""
      -- Replaying alpha's append on top of the recorded baseline adds its new
      -- line and leaves beta's /result exactly where it was.
      TIO.readFile (fixture ^. #gitignorePath)
        `shouldReturn` "/dist-newstyle\n/result\n/alpha-v2\n"
      manifestText <- TIO.readFile (fixture ^. #manifestPath)
      -- Both owners are still recorded: a partial update must not quietly
      -- drop the co-owner it did not touch.
      manifestText `shouldSatisfy` T.isInfixOf (fixture ^. #alphaApplicationId . #unApplicationId)
      manifestText `shouldSatisfy` T.isInfixOf (fixture ^. #betaApplicationId . #unApplicationId)
      manifestText `shouldSatisfy` T.isInfixOf "\"sharedWriteMode\":\"additive-only\""

  it "still refuses a partial selection when a co-owner writes the shared path wholesale" $
    withSystemTempDirectory "seihou-update-shared-wholefile" $ \root -> do
      fixture <- prepareSharedPathFixture CoOwnerWritesWholeFile root
      binary <- seihouBinary
      beforeGitignore <- TIO.readFile (fixture ^. #gitignorePath)
      beforeManifest <- LBS.readFile (fixture ^. #manifestPath)
      (exitCode, stdoutText, _) <- runSeihouShared binary fixture ["update", "alpha", "--json"]
      exitCode `shouldSatisfy` (/= ExitSuccess)
      stdoutText `shouldSatisfy` T.isInfixOf "shared_path_requires_applications"
      TIO.readFile (fixture ^. #gitignorePath) `shouldReturn` beforeGitignore
      LBS.readFile (fixture ^. #manifestPath) `shouldReturn` beforeManifest

  it "updates the co-owner too under --include-shared-owners" $
    withSystemTempDirectory "seihou-update-shared-include" $ \root -> do
      fixture <- prepareSharedPathFixture CoOwnerWritesWholeFile root
      binary <- seihouBinary
      (exitCode, stdoutText, stderrText) <-
        runSeihouShared binary fixture ["update", "alpha", "--include-shared-owners", "--json"]
      case exitCode of
        ExitSuccess -> pure ()
        ExitFailure code ->
          expectationFailure
            ("update exited " <> show code <> "\nstdout:\n" <> T.unpack stdoutText <> "\nstderr:\n" <> T.unpack stderrText)
      stdoutText `shouldSatisfy` T.isInfixOf "\"outcome\":\"applied\""
      -- The expansion is reported, never silent.
      stdoutText `shouldSatisfy` T.isInfixOf "also updating"
      stdoutText `shouldSatisfy` T.isInfixOf "because it co-owns .gitignore"
      stdoutText `shouldSatisfy` T.isInfixOf (fixture ^. #betaApplicationId . #unApplicationId)

  it "records a missing shared-write answer when that record is the only work" $
    withSystemTempDirectory "seihou-update-shared-unrecorded" $ \root -> do
      -- Every project in the wild has a manifest that predates the evidence.
      -- A targeted update certifies the path in its own plan instead of
      -- refusing, and the certificate is real work rather than a no-op.
      fixture <- prepareSharedPathFixture CoOwnerAppendsUnrecorded root
      binary <- seihouBinary
      beforeGitignore <- TIO.readFile (fixture ^. #gitignorePath)
      beforeBeta <- LBS.readFile (fixture ^. #betaFilePath)

      (exitCode, stdoutText, stderrText) <- runSeihouShared binary fixture ["update", "alpha", "--json"]
      expectSuccess "targeted update" exitCode stdoutText stderrText
      stdoutText `shouldSatisfy` T.isInfixOf "\"outcome\":\"applied\""
      manifestText <- TIO.readFile (fixture ^. #manifestPath)
      manifestText `shouldSatisfy` T.isInfixOf "\"version\":7"
      manifestText `shouldSatisfy` T.isInfixOf "\"sharedWriteMode\":\"additive-only\""
      -- Recording an answer must not touch a single byte of the project.
      TIO.readFile (fixture ^. #gitignorePath) `shouldReturn` beforeGitignore
      LBS.readFile (fixture ^. #betaFilePath) `shouldReturn` beforeBeta

      -- Once recorded, the same request is an ordinary no-op.
      (againExit, againOut, againErr) <- runSeihouShared binary fixture ["update", "alpha", "--json"]
      expectSuccess "repeated update" againExit againOut againErr
      againOut `shouldSatisfy` T.isInfixOf "\"alreadyUpToDate\":true"

  it "records a missing shared-write answer through a whole-project update" $
    withSystemTempDirectory "seihou-update-shared-unrecorded-all" $ \root -> do
      fixture <- prepareSharedPathFixture CoOwnerAppendsUnrecorded root
      binary <- seihouBinary
      beforeGitignore <- TIO.readFile (fixture ^. #gitignorePath)
      (exitCode, stdoutText, stderrText) <- runSeihouShared binary fixture ["update", "--json"]
      expectSuccess "whole-project update" exitCode stdoutText stderrText
      stdoutText `shouldSatisfy` T.isInfixOf "\"outcome\":\"applied\""
      manifestText <- TIO.readFile (fixture ^. #manifestPath)
      manifestText `shouldSatisfy` T.isInfixOf "\"sharedWriteMode\":\"additive-only\""
      TIO.readFile (fixture ^. #gitignorePath) `shouldReturn` beforeGitignore

  it "updates one target on a schema-6 manifest without touching the co-owner's files (BUG-1)" $
    withSystemTempDirectory "seihou-update-bug-1" $ \root -> do
      fixture <- prepareSharedPathFixture CoOwnerAppendsPredatingEvidence root
      binary <- seihouBinary
      beforeManifest <- LBS.readFile (fixture ^. #manifestPath)
      beforeGitignore <- LBS.readFile (fixture ^. #gitignorePath)
      beforeBeta <- LBS.readFile (fixture ^. #betaFilePath)
      beforeBetaInstalled <- LBS.readFile (fixture ^. #betaInstalledPath </> "module.dhall")

      -- The dry run shows the schema step and the certificate, and writes
      -- nothing at all.
      (dryExit, dryOut, dryErr) <- runSeihouShared binary fixture ["update", "alpha", "--dry-run", "--json"]
      expectSuccess "dry run" dryExit dryOut dryErr
      dryOut `shouldSatisfy` T.isInfixOf "\"outcome\":\"plan\""
      dryOut `shouldSatisfy` T.isInfixOf "\"alreadyUpToDate\":false"
      dryOut `shouldSatisfy` T.isInfixOf "\"fromSchema\":6"
      dryOut `shouldSatisfy` T.isInfixOf "\"toSchema\":7"
      dryOut `shouldSatisfy` T.isInfixOf "{\"from\":\"unknown\",\"path\":\".gitignore\",\"to\":\"additive-only\"}"
      dryOut `shouldNotSatisfy` T.isInfixOf "shared_path_requires_applications"
      LBS.readFile (fixture ^. #manifestPath) `shouldReturn` beforeManifest
      LBS.readFile (fixture ^. #gitignorePath) `shouldReturn` beforeGitignore
      LBS.readFile (fixture ^. #betaFilePath) `shouldReturn` beforeBeta

      (exitCode, stdoutText, stderrText) <- runSeihouShared binary fixture ["update", "alpha", "--json"]
      expectSuccess "targeted update" exitCode stdoutText stderrText
      stdoutText `shouldSatisfy` T.isInfixOf "\"outcome\":\"applied\""
      stdoutText
        `shouldSatisfy` T.isInfixOf ("\"applications\":[\"" <> fixture ^. #alphaApplicationId . #unApplicationId <> "\"]")
      -- Alpha's new line lands next to beta's, which is left where it was.
      TIO.readFile (fixture ^. #gitignorePath) `shouldReturn` "/dist-newstyle\n/result\n/alpha-v2\n"
      -- Beta has a newer release, but nobody asked to update beta.
      LBS.readFile (fixture ^. #betaFilePath) `shouldReturn` beforeBeta
      LBS.readFile (fixture ^. #betaInstalledPath </> "module.dhall") `shouldReturn` beforeBetaInstalled
      decoded <- manifestFromJSON <$> LBS.readFile (fixture ^. #manifestPath)
      case decoded of
        Left err -> expectationFailure err
        Right manifest -> do
          (manifest ^. #version) `shouldBe` ManifestSchemaVersion 7
          case Map.lookup ".gitignore" (manifest ^. #files) of
            Nothing -> expectationFailure "the manifest lost .gitignore"
            Just record -> do
              (record ^. #sharedWriteMode) `shouldBe` SharedWriteAdditiveOnly
              (record ^. #applicationIds)
                `shouldBe` Set.fromList [fixture ^. #alphaApplicationId, fixture ^. #betaApplicationId]
          [application ^. #targetVersion | application <- manifest ^. #applications]
            `shouldBe` [Just "2.0.0", Just "1.0.0"]

      (againExit, againOut, againErr) <- runSeihouShared binary fixture ["update", "alpha", "--json"]
      expectSuccess "repeated update" againExit againOut againErr
      againOut `shouldSatisfy` T.isInfixOf "\"alreadyUpToDate\":true"

  it "explains a schema-6 targeted plan and a whole-file refusal in prose, by application name" $
    withSystemTempDirectory "seihou-update-human" $ \root -> do
      bug1 <- prepareSharedPathFixture CoOwnerAppendsPredatingEvidence (root </> "bug-1")
      binary <- seihouBinary
      (dryExit, dryOut, dryErr) <- runSeihouShared binary bug1 ["update", "alpha", "--dry-run"]
      expectSuccess "human dry run" dryExit dryOut dryErr
      dryOut `shouldSatisfy` T.isInfixOf "Manifest:    schema 6 -> 7"
      dryOut `shouldSatisfy` T.isInfixOf ".gitignore evidence unknown -> additive-only"
      (dryOut <> dryErr) `shouldNotSatisfy` leaksInternals

      wholeFile <- prepareSharedPathFixture CoOwnerWritesWholeFile (root </> "whole-file")
      (refusedExit, refusedOut, refusedErr) <- runSeihouShared binary wholeFile ["update", "alpha"]
      refusedExit `shouldSatisfy` (/= ExitSuccess)
      let refusal = refusedOut <> refusedErr
      refusal `shouldSatisfy` T.isInfixOf "Update failed [shared_path_requires_applications]"
      refusal `shouldSatisfy` T.isInfixOf "Selected: alpha. Also required: beta."
      refusal `shouldSatisfy` T.isInfixOf "seihou update alpha beta"
      refusal `shouldNotSatisfy` T.isInfixOf (wholeFile ^. #betaApplicationId . #unApplicationId)
      refusal `shouldNotSatisfy` leaksInternals

  it "reports unavailable evidence distinctly and never expands for it" $
    withSystemTempDirectory "seihou-update-evidence-unavailable" $ \root -> do
      fixture <- prepareSharedPathFixture CoOwnerAppendsPredatingEvidence root
      -- A schema-7 manifest that still records the path as unknown.
      decoded <- manifestFromJSON <$> LBS.readFile (fixture ^. #manifestPath)
      case decoded of
        Left err -> expectationFailure err
        Right manifest -> LBS.writeFile (fixture ^. #manifestPath) (manifestToJSON (manifest & #version .~ ManifestSchemaVersion 7))
      let parked = root </> "parked-beta"
      renameDirectory (fixture ^. #betaInstalledPath) parked
      binary <- seihouBinary
      beforeManifest <- LBS.readFile (fixture ^. #manifestPath)
      beforeGitignore <- LBS.readFile (fixture ^. #gitignorePath)

      (exitCode, stdoutText, _) <- runSeihouShared binary fixture ["update", "alpha", "--json"]
      exitCode `shouldSatisfy` (/= ExitSuccess)
      stdoutText `shouldSatisfy` T.isInfixOf "shared_write_evidence_unavailable"
      stdoutText `shouldSatisfy` T.isInfixOf ".gitignore"
      stdoutText `shouldSatisfy` T.isInfixOf "beta: module beta 1.0.0 is not installed here"
      stdoutText `shouldNotSatisfy` T.isInfixOf "--include-shared-owners"

      -- Selecting more applications does not supply a missing fact.
      (includeExit, includeOut, _) <- runSeihouShared binary fixture ["update", "alpha", "--include-shared-owners", "--json"]
      includeExit `shouldSatisfy` (/= ExitSuccess)
      includeOut `shouldSatisfy` T.isInfixOf "shared_write_evidence_unavailable"
      LBS.readFile (fixture ^. #manifestPath) `shouldReturn` beforeManifest
      LBS.readFile (fixture ^. #gitignorePath) `shouldReturn` beforeGitignore

      -- Installing the recorded release again is enough to proceed.
      renameDirectory parked (fixture ^. #betaInstalledPath)
      (retryExit, retryOut, retryErr) <- runSeihouShared binary fixture ["update", "alpha", "--json"]
      expectSuccess "retried update" retryExit retryOut retryErr
      retryOut `shouldSatisfy` T.isInfixOf "\"outcome\":\"applied\""

  it "lists --include-shared-owners in update --help" $ do
    binary <- seihouBinary
    (exitCode, stdoutText, _) <- runProcessText binary ["update", "--help"] Nothing Nothing
    exitCode `shouldBe` ExitSuccess
    stdoutText `shouldSatisfy` T.isInfixOf "--include-shared-owners"
    stdoutText `shouldSatisfy` T.isInfixOf "co-own a selected path"

  it "exposes update and its options through the shared Bash, Zsh, and Fish completion protocol" $ do
    binary <- seihouBinary
    (topExit, topOutput, _) <- runProcessText binary ["--bash-completion-enriched", "--bash-completion-index", "0"] Nothing Nothing
    topExit `shouldBe` ExitSuccess
    topOutput `shouldSatisfy` T.isInfixOf "update\tUpdate recorded project applications"
    (optionExit, optionOutput, _) <-
      runProcessText
        binary
        [ "--bash-completion-enriched",
          "--bash-completion-index",
          "2",
          "--bash-completion-word",
          "seihou",
          "--bash-completion-word",
          "update"
        ]
        Nothing
        Nothing
    optionExit `shouldBe` ExitSuccess
    optionOutput `shouldSatisfy` T.isInfixOf "--force\tUse generated content"
    (exclusiveExit, _, exclusiveErr) <-
      runProcessText binary ["update", "--run-all-commands", "--no-commands"] Nothing Nothing
    exclusiveExit `shouldSatisfy` (/= ExitSuccess)
    exclusiveErr `shouldSatisfy` T.isInfixOf "Invalid option"
    mapM_
      ( \shell -> do
          (shellExit, script, _) <- runProcessText binary ["completions", shell] Nothing Nothing
          shellExit `shouldBe` ExitSuccess
          script `shouldSatisfy` T.isInfixOf "bash-completion"
      )
      ["bash", "zsh", "fish"]

-- | Haskell constructor or record syntax, or a whole 64-character digest.
leaksInternals :: T.Text -> Bool
leaksInternals text =
  any (`T.isInfixOf` text) ["ModuleName {", "unModuleName", "ApplicationId", "CrossApplicationLastWriter", "fromList"]
    || any ((>= 64) . T.length) (T.split (not . isHexDigit) text)

expectSuccess :: String -> ExitCode -> T.Text -> T.Text -> Expectation
expectSuccess _ ExitSuccess _ _ = pure ()
expectSuccess label (ExitFailure code) stdoutText stderrText =
  expectationFailure
    (label <> " exited " <> show code <> "\nstdout:\n" <> T.unpack stdoutText <> "\nstderr:\n" <> T.unpack stderrText)

runSeihouShared :: FilePath -> SharedPathFixture -> [String] -> IO (ExitCode, T.Text, T.Text)
runSeihouShared binary fixture args = do
  inherited <- getEnvironment
  let environment = ("XDG_CONFIG_HOME", fixture ^. #xdgHome) : filter ((/= "XDG_CONFIG_HOME") . fst) inherited
  runProcessText binary args (Just (fixture ^. #projectRoot)) (Just environment)

runSeihou :: FilePath -> UpdateFixture -> [String] -> IO (ExitCode, T.Text, T.Text)
runSeihou binary fixture args = do
  inherited <- getEnvironment
  let environment = ("XDG_CONFIG_HOME", fixture ^. #xdgHome) : filter ((/= "XDG_CONFIG_HOME") . fst) inherited
  runProcessText binary args (Just (fixture ^. #projectRoot)) (Just environment)

runProcessText binary args workingDirectory environment = do
  let command = (proc binary args) {cwd = workingDirectory, env = environment}
  (exitCode, stdoutText, stderrText) <- readCreateProcessWithExitCode command ""
  pure (exitCode, T.pack stdoutText, T.pack stderrText)

shouldReturnSatisfy :: IO T.Text -> (T.Text -> Bool) -> Expectation
shouldReturnSatisfy action predicate = action >>= (`shouldSatisfy` predicate)
