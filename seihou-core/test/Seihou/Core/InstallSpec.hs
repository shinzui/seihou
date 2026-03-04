module Seihou.Core.InstallSpec (tests) where

import Seihou.Core.Install (parseModuleName)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Core.Install" spec

spec :: Spec
spec = do
  describe "parseModuleName" $ do
    it "extracts repo name from HTTPS URL with .git suffix" $
      parseModuleName "https://github.com/user/my-module.git" `shouldBe` "my-module"

    it "extracts repo name from HTTPS URL without .git suffix" $
      parseModuleName "https://github.com/user/my-module" `shouldBe` "my-module"

    it "returns a bare name unchanged" $
      parseModuleName "my-local-module" `shouldBe` "my-local-module"

    it "extracts repo name from SSH-style URL" $
      -- SSH URLs use : before user, so splitOn "/" takes "user:repo" or similar.
      -- The current implementation splits on "/" so "git@github.com:user/repo.git"
      -- splits to ["git@github.com:user", "repo.git"] and last segment is "repo".
      parseModuleName "git@github.com:user/repo.git" `shouldBe` "repo"

    it "handles URL with trailing slash" $
      -- Trailing slash produces an empty last segment; last returns ""
      parseModuleName "https://github.com/user/my-module/" `shouldBe` ""
