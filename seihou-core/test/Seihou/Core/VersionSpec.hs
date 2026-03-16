module Seihou.Core.VersionSpec (tests) where

import Seihou.Core.Version (Version (..), parseVersion, renderVersion)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Core.Version" spec

spec :: Spec
spec = do
  describe "parseVersion" $ do
    it "parses a three-segment version" $ do
      parseVersion "1.0.0" `shouldBe` Just (Version [1, 0, 0])

    it "parses a two-segment version" $ do
      parseVersion "1.2" `shouldBe` Just (Version [1, 2])

    it "parses a four-segment version" $ do
      parseVersion "1.2.3.4" `shouldBe` Just (Version [1, 2, 3, 4])

    it "parses a single-segment version" $ do
      parseVersion "5" `shouldBe` Just (Version [5])

    it "returns Nothing for empty string" $ do
      parseVersion "" `shouldBe` Nothing

    it "returns Nothing for non-numeric input" $ do
      parseVersion "abc" `shouldBe` Nothing

    it "returns Nothing for mixed input" $ do
      parseVersion "1.2.abc" `shouldBe` Nothing

    it "returns Nothing for negative segments" $ do
      parseVersion "1.-2.3" `shouldBe` Nothing

  describe "Eq instance" $ do
    it "considers equal versions with trailing zeros" $ do
      Version [1, 2, 0] == Version [1, 2] `shouldBe` True

    it "considers 1.0.0 equal to 1" $ do
      Version [1, 0, 0] == Version [1] `shouldBe` True

    it "distinguishes different versions" $ do
      Version [1, 2] == Version [1, 3] `shouldBe` False

  describe "Ord instance" $ do
    it "orders 1.2 < 1.10 (numeric, not lexicographic)" $ do
      Version [1, 2] < Version [1, 10] `shouldBe` True

    it "orders 2.0 > 1.99.99" $ do
      Version [2, 0] > Version [1, 99, 99] `shouldBe` True

    it "orders equal versions as EQ" $ do
      compare (Version [1, 2, 0]) (Version [1, 2]) `shouldBe` EQ

    it "orders 0.1 < 1.0" $ do
      Version [0, 1] < Version [1, 0] `shouldBe` True

  describe "renderVersion" $ do
    it "renders a three-segment version" $ do
      renderVersion (Version [1, 2, 3]) `shouldBe` "1.2.3"

    it "renders a single-segment version" $ do
      renderVersion (Version [5]) `shouldBe` "5"

    it "roundtrips with parseVersion" $ do
      let v = Version [1, 2, 3]
      parseVersion (renderVersion v) `shouldBe` Just v
