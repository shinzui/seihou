module Seihou.CLI.CommitMessageSpec (tests) where

import Data.Text qualified as T
import Seihou.CLI.CommitMessage (generateCommitMessage)
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
