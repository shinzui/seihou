module Seihou.Core.PathSpec (tests) where

import Control.Monad (forM_)
import Data.Maybe (isJust)
import Data.Text qualified as T
import Seihou.Core.Path
import Seihou.Prelude
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

isControl :: ProjectPathClass -> Bool
isControl (ControlPath _) = True
isControl _ = False

tests :: IO TestTree
tests = testSpec "project path classification" $ do
  describe "classifyProjectPath" $ do
    it "treats paths outside .seihou and .git as ordinary" $
      forM_ ["README.md", "docs/.seihou-notes", "src/.seihou/x", "seihou/manifest.json"] $ \path ->
        classifyProjectPath path `shouldBe` OrdinaryProjectPath

    it "treats everything under .git as Git control data" $
      forM_ [".git", ".git/config", ".GIT/HEAD", "./.git/index"] $ \path ->
        classifyProjectPath path `shouldBe` ControlPath "path targets Git control data"

    it "treats Seihou's reserved entries as control data, in any case and either separator"
      $ forM_
        [ ".seihou/manifest.json",
          ".seihou/manifest.json.tmp",
          ".seihou/Manifest.JSON",
          ".SEIHOU/manifest.json",
          ".seihou/baselines/abc",
          ".seihou/transactions/x/journal.json",
          ".seihou/transactions-quarantine/x",
          ".seihou/modules/demo/module.dhall",
          ".seihou/context",
          ".seihou/config.dhall",
          ".seihou/trace.jsonl",
          ".seihou/.migrate-signal",
          ".seihou\\baselines\\abc",
          ".seihou//baselines/abc",
          ".seihou/./manifest.json"
        ]
      $ \path -> classifyProjectPath path `shouldSatisfy` isControl

    it "names the reserved entry as the path spells it" $
      classifyProjectPath ".SEIHOU/Manifest.JSON"
        `shouldBe` ControlPath "path targets Seihou's own state at .SEIHOU/Manifest.JSON"

    it "reports other .seihou entries as module state areas" $ do
      classifyProjectPath ".seihou/docs-mori-bootstrap/bootstrap-docs.py"
        `shouldBe` ModuleStatePath "docs-mori-bootstrap" True
      classifyProjectPath ".seihou/gcp-kube-env.conf" `shouldBe` ModuleStatePath "gcp-kube-env.conf" False
      classifyProjectPath ".seihou/demo/" `shouldBe` ModuleStatePath "demo" False

    it "recognises the .seihou directory itself" $
      forM_ [".seihou", ".SEIHOU", ".seihou/", "./.seihou"] $ \path ->
        classifyProjectPath path `shouldBe` SeihouRootDirectory

    it "keeps the reserved list to names that are not valid module names, except legacy entries" $
      -- Legacy entries predate the rule; new entries must not look like module names.
      filter (T.all (\c -> (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-')) reservedSeihouEntries
        `shouldBe` ["baselines", "transactions", "transactions-quarantine", "modules", "context"]

  describe "control predicates" $ do
    it "refuses the .seihou directory as a file but allows it as a directory" $ do
      isControlFileTarget ".seihou" `shouldBe` True
      isControlDirectory ".seihou" `shouldBe` False

    it "refuses control data as both files and directories" $
      forM_ [".git", ".seihou/baselines", ".seihou/manifest.json"] $ \path -> do
        isControlFileTarget path `shouldBe` True
        isControlDirectory path `shouldBe` True

    it "allows ordinary and module-state paths" $
      forM_ ["src/x", ".seihou/demo", ".seihou/demo/helper.txt"] $ \path -> do
        isControlFileTarget path `shouldBe` False
        isControlDirectory path `shouldBe` False
        controlPathReason FileTarget path `shouldBe` Nothing

  describe "ownStateDirectoryViolation" $ do
    let violation = ownStateDirectoryViolation "demo"

    it "accepts ordinary paths and files inside the module's own directory" $
      forM_ [".seihou/demo/a/b.txt", ".seihou/demo/helper.txt", "src/x"] $ \path ->
        violation FileTarget path `shouldBe` Nothing

    it "refuses other .seihou file targets, naming the allowed directory" $ do
      forM_ [".seihou/demo", ".seihou", ".seihou/other/x", ".Seihou/demo/x", ".seihou/Demo/x", ".seihou/demo.conf"] $ \path ->
        violation FileTarget path `shouldSatisfy` isJust
      violation FileTarget ".seihou/other/x"
        `shouldBe` Just ".seihou/other/x is outside this module's state directory; a module may write under .seihou/ only inside .seihou/demo/"

    it "refuses Seihou's own state with the control reason" $
      violation FileTarget ".seihou/manifest.json"
        `shouldBe` Just "path targets Seihou's own state at .seihou/manifest.json"

    it "gives a module named after a reserved entry no state directory" $
      ownStateDirectoryViolation "modules" FileTarget ".seihou/modules/x"
        `shouldBe` Just "path targets Seihou's own state at .seihou/modules"

    it "accepts the .seihou directory and the module's own directory as directory operands" $ do
      violation DirectoryOperand ".seihou" `shouldBe` Nothing
      violation DirectoryOperand ".seihou/demo" `shouldBe` Nothing
      violation DirectoryOperand ".seihou/demo/sub" `shouldBe` Nothing

    it "refuses other directories under .seihou" $ do
      violation DirectoryOperand ".seihou/other" `shouldSatisfy` isJust
      violation DirectoryOperand ".seihou/baselines" `shouldSatisfy` isJust
