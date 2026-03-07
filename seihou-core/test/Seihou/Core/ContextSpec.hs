module Seihou.Core.ContextSpec (tests) where

import Data.Map.Strict qualified as Map
import Seihou.Core.Context
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Core.Context" spec

spec :: Spec
spec = do
  describe "resolveContext" $ do
    it "returns CLI flag when provided" $ do
      result <- resolveContext (Just "work") Map.empty
      result `shouldBe` Just "work"

    it "strips whitespace from CLI flag" $ do
      result <- resolveContext (Just "  work  ") Map.empty
      result `shouldBe` Just "work"

    it "ignores empty CLI flag and falls through" $ do
      result <- resolveContext (Just "") Map.empty
      result `shouldBe` Nothing

    it "returns SEIHOU_CONTEXT env var when CLI flag is absent" $ do
      let envVars = Map.singleton "SEIHOU_CONTEXT" "personal"
      result <- resolveContext Nothing envVars
      result `shouldBe` Just "personal"

    it "CLI flag takes precedence over env var" $ do
      let envVars = Map.singleton "SEIHOU_CONTEXT" "personal"
      result <- resolveContext (Just "work") envVars
      result `shouldBe` Just "work"

    it "ignores empty SEIHOU_CONTEXT env var" $ do
      let envVars = Map.singleton "SEIHOU_CONTEXT" ""
      result <- resolveContext Nothing envVars
      result `shouldBe` Nothing

    it "returns Nothing when no source provides a context" $ do
      result <- resolveContext Nothing Map.empty
      result `shouldBe` Nothing

  describe "validateContextName" $ do
    it "accepts a normal context name" $ do
      validateContextName "work" `shouldBe` Nothing

    it "accepts a hyphenated context name" $ do
      validateContextName "my-work" `shouldBe` Nothing

    it "rejects empty context name" $ do
      validateContextName "" `shouldSatisfy` (/= Nothing)

    it "rejects context name containing '..'" $ do
      validateContextName "foo..bar" `shouldSatisfy` (/= Nothing)

    it "rejects context name containing '/'" $ do
      validateContextName "foo/bar" `shouldSatisfy` (/= Nothing)
