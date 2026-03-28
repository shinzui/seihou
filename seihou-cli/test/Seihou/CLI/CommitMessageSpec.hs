module Seihou.CLI.CommitMessageSpec (tests) where

import Data.Text qualified as T
import Seihou.CLI.CommitMessage (generateCommitMessage, stripCodeFence)
import Seihou.Core.Types (ModuleName (..))
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.CLI.CommitMessage" spec

spec :: Spec
spec = do
  describe "generateCommitMessage" $ do
    it "returns a non-empty message for a single module" $ do
      msg <- generateCommitMessage [ModuleName "haskell-base"] "diff content"
      T.null msg `shouldBe` False

    it "returns a non-empty message for multiple modules" $ do
      msg <- generateCommitMessage [ModuleName "base", ModuleName "extras"] "diff content"
      T.null msg `shouldBe` False

    it "returns a non-empty message with empty diff" $ do
      msg <- generateCommitMessage [ModuleName "haskell-base"] ""
      T.null msg `shouldBe` False

  describe "stripCodeFence" $ do
    it "strips triple-backtick fencing" $ do
      stripCodeFence "```\nfeat: apply module\n```" `shouldBe` "feat: apply module"

    it "strips fencing with language tag" $ do
      stripCodeFence "```text\nfeat: apply module\n```" `shouldBe` "feat: apply module"

    it "leaves unfenced text unchanged" $ do
      stripCodeFence "feat: apply module" `shouldBe` "feat: apply module"

    it "leaves text with backticks in the middle unchanged" $ do
      let input = "feat: use ```code``` in template"
      stripCodeFence input `shouldBe` input

    it "handles empty input" $ do
      stripCodeFence "" `shouldBe` ""

    it "preserves multiline commit messages inside fences" $ do
      stripCodeFence "```\nfeat: apply modules\n\nApply base and extras.\n```"
        `shouldBe` "feat: apply modules\n\nApply base and extras."
