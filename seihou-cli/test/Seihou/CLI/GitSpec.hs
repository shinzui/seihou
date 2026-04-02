module Seihou.CLI.GitSpec (tests) where

import Seihou.CLI.Git (gitAdd, gitCheckIgnore, gitCommit, gitDiffCached, isGitRepo)
import Seihou.Effect.ProcessPure (ProcessMock (..), runProcessPure)
import Seihou.Prelude
import System.Exit (ExitCode (..))
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.CLI.Git" spec

spec :: Spec
spec = do
  describe "isGitRepo" $ do
    it "returns True when git rev-parse succeeds" $ do
      let mocks =
            [ ProcessMock
                "git"
                ["rev-parse", "--is-inside-work-tree"]
                (ExitSuccess, "true\n", "")
            ]
      result <- runEff $ runProcessPure mocks isGitRepo
      result `shouldBe` True

    it "returns False when git rev-parse fails" $ do
      let mocks =
            [ ProcessMock
                "git"
                ["rev-parse", "--is-inside-work-tree"]
                (ExitFailure 128, "", "fatal: not a git repository\n")
            ]
      result <- runEff $ runProcessPure mocks isGitRepo
      result `shouldBe` False

    it "returns False when git is not found" $ do
      result <- runEff $ runProcessPure [] isGitRepo
      result `shouldBe` False

  describe "gitAdd" $ do
    it "stages specified files" $ do
      let mocks =
            [ ProcessMock
                "git"
                ["add", "README.md", "src/Lib.hs"]
                (ExitSuccess, "", "")
            ]
      (exitCode, _, _) <- runEff $ runProcessPure mocks $ gitAdd ["README.md", "src/Lib.hs"]
      exitCode `shouldBe` ExitSuccess

    it "returns failure for nonexistent files" $ do
      let mocks =
            [ ProcessMock
                "git"
                ["add", "missing.txt"]
                (ExitFailure 128, "", "fatal: pathspec 'missing.txt' did not match any files\n")
            ]
      (exitCode, _, _) <- runEff $ runProcessPure mocks $ gitAdd ["missing.txt"]
      exitCode `shouldBe` ExitFailure 128

  describe "gitCommit" $ do
    it "creates a commit with given message" $ do
      let mocks =
            [ ProcessMock
                "git"
                ["commit", "-m", "feat: add scaffolding"]
                (ExitSuccess, "[main abc1234] feat: add scaffolding\n 2 files changed\n", "")
            ]
      (exitCode, _, _) <- runEff $ runProcessPure mocks $ gitCommit "feat: add scaffolding"
      exitCode `shouldBe` ExitSuccess

    it "returns failure when nothing to commit" $ do
      let mocks =
            [ ProcessMock
                "git"
                ["commit", "-m", "empty"]
                (ExitFailure 1, "", "nothing to commit, working tree clean\n")
            ]
      (exitCode, _, stderr) <- runEff $ runProcessPure mocks $ gitCommit "empty"
      exitCode `shouldBe` ExitFailure 1
      stderr `shouldBe` "nothing to commit, working tree clean\n"

  describe "gitCheckIgnore" $ do
    it "returns ignored files when git check-ignore succeeds" $ do
      let mocks =
            [ ProcessMock
                "git"
                ["check-ignore", "README.md", "dist/bundle.js", ".env"]
                (ExitSuccess, "dist/bundle.js\n.env\n", "")
            ]
      result <- runEff $ runProcessPure mocks $ gitCheckIgnore ["README.md", "dist/bundle.js", ".env"]
      result `shouldBe` ["dist/bundle.js", ".env"]

    it "returns empty list when no files are ignored (exit 1)" $ do
      let mocks =
            [ ProcessMock
                "git"
                ["check-ignore", "README.md", "src/Lib.hs"]
                (ExitFailure 1, "", "")
            ]
      result <- runEff $ runProcessPure mocks $ gitCheckIgnore ["README.md", "src/Lib.hs"]
      result `shouldBe` []

    it "returns empty list on error (exit 128)" $ do
      let mocks =
            [ ProcessMock
                "git"
                ["check-ignore", "README.md"]
                (ExitFailure 128, "", "fatal: not a git repository\n")
            ]
      result <- runEff $ runProcessPure mocks $ gitCheckIgnore ["README.md"]
      result `shouldBe` []

    it "returns empty list for empty input" $ do
      result <- runEff $ runProcessPure [] $ gitCheckIgnore []
      result `shouldBe` []

  describe "gitDiffCached" $ do
    it "returns stat and diff combined" $ do
      let mocks =
            [ ProcessMock
                "git"
                ["diff", "--cached", "--stat"]
                (ExitSuccess, " README.md | 1 +\n", ""),
              ProcessMock
                "git"
                ["diff", "--cached"]
                (ExitSuccess, "+hello world\n", "")
            ]
      result <- runEff $ runProcessPure mocks gitDiffCached
      result `shouldBe` " README.md | 1 +\n\n+hello world\n"
