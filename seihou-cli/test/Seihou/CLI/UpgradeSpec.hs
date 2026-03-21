module Seihou.CLI.UpgradeSpec (tests) where

import Seihou.CLI.VersionCompare (OutdatedStatus (..), compareVersions)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.CLI.Upgrade" spec

spec :: Spec
spec = do
  describe "compareVersions" $ do
    it "returns Unversioned when both versions are Nothing" $
      compareVersions Nothing Nothing `shouldBe` Unversioned

    it "returns Unversioned when installed version is Nothing" $
      compareVersions Nothing (Just "1.0") `shouldBe` Unversioned

    it "returns Unversioned when available version is Nothing" $
      compareVersions (Just "1.0") Nothing `shouldBe` Unversioned

    it "returns OutdatedSt when available version is newer" $
      compareVersions (Just "1.0") (Just "2.0") `shouldBe` OutdatedSt

    it "returns UpToDate when installed version is newer" $
      compareVersions (Just "2.0") (Just "1.0") `shouldBe` UpToDate

    it "returns UpToDate when versions are equal" $
      compareVersions (Just "1.0") (Just "1.0") `shouldBe` UpToDate

    it "returns Unversioned when version strings are unparseable" $
      compareVersions (Just "abc") (Just "def") `shouldBe` Unversioned

    it "returns Unversioned when one version is unparseable" $
      compareVersions (Just "1.0") (Just "abc") `shouldBe` Unversioned
