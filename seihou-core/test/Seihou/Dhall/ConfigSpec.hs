module Seihou.Dhall.ConfigSpec (tests) where

import Data.Map.Strict qualified as Map
import Seihou.Dhall.Config (evalConfigFile, evalConfigFileIfExists)
import System.Directory (getCurrentDirectory)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Dhall.Config" spec

spec :: Spec
spec = do
  describe "evalConfigFile" $ do
    it "evaluates a simple Dhall config to Map Text Text" $ do
      withSystemTempDirectory "seihou-config-test" $ \tmpDir -> do
        let path = tmpDir </> "config.dhall"
        writeFile path "{ license = \"MIT\", `project.name` = \"my-app\" }"
        result <- evalConfigFile path
        Map.lookup "license" result `shouldBe` Just "MIT"
        Map.lookup "project.name" result `shouldBe` Just "my-app"

    it "evaluates an empty record" $ do
      withSystemTempDirectory "seihou-config-test" $ \tmpDir -> do
        let path = tmpDir </> "config.dhall"
        writeFile path "{=}"
        result <- evalConfigFile path
        Map.null result `shouldBe` True

  describe "evalConfigFileIfExists" $ do
    it "returns empty map for nonexistent file" $ do
      result <- evalConfigFileIfExists "/nonexistent/path/config.dhall"
      result `shouldBe` Right Map.empty

    it "returns Right map for valid config file" $ do
      withSystemTempDirectory "seihou-config-test" $ \tmpDir -> do
        let path = tmpDir </> "config.dhall"
        writeFile path "{ license = \"BSD3\" }"
        result <- evalConfigFileIfExists path
        case result of
          Left err -> expectationFailure ("Expected Right, got Left: " <> show err)
          Right m -> Map.lookup "license" m `shouldBe` Just "BSD3"

    it "returns Left for invalid Dhall" $ do
      withSystemTempDirectory "seihou-config-test" $ \tmpDir -> do
        let path = tmpDir </> "config.dhall"
        writeFile path "this is not valid dhall @@##"
        result <- evalConfigFileIfExists path
        case result of
          Left _ -> pure ()
          Right _ -> expectationFailure "Expected Left for invalid Dhall"
