module Seihou.Dhall.ConfigSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.Dhall.Config (escapeDhallText, evalConfigFile, evalConfigFileIfExists, serializeConfig)
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

  describe "serializeConfig" $ do
    it "serializes an empty map to {=}" $ do
      serializeConfig Map.empty `shouldBe` "{=}\n"

    it "serializes a single entry" $ do
      let m = Map.fromList [("license", "MIT")]
          result = serializeConfig m
      result `shouldSatisfy` T.isInfixOf "`license`"
      result `shouldSatisfy` T.isInfixOf "\"MIT\""

    it "serializes multiple entries in sorted order" $ do
      let m = Map.fromList [("z-key", "last"), ("a-key", "first")]
          result = serializeConfig m
          aPos = T.findIndex (== 'a') result
          zPos = T.findIndex (== 'z') result
      -- a-key should appear before z-key (sorted)
      case (aPos, zPos) of
        (Just a, Just z) -> a `shouldSatisfy` (< z)
        _ -> expectationFailure "Expected both keys in output"

    it "round-trips through evalConfigFile" $ do
      withSystemTempDirectory "seihou-config-test" $ \tmpDir -> do
        let original = Map.fromList [("project.name", "my-app"), ("license", "MIT")]
            path = tmpDir </> "config.dhall"
        TIO.writeFile path (serializeConfig original)
        result <- evalConfigFile path
        result `shouldBe` original

    it "round-trips dotted keys" $ do
      withSystemTempDirectory "seihou-config-test" $ \tmpDir -> do
        let original = Map.fromList [("haskell.ghc", "9.12.2"), ("project.name", "test")]
            path = tmpDir </> "config.dhall"
        TIO.writeFile path (serializeConfig original)
        result <- evalConfigFile path
        result `shouldBe` original

    it "round-trips values with special characters" $ do
      withSystemTempDirectory "seihou-config-test" $ \tmpDir -> do
        let original = Map.fromList [("path", "C:\\Users\\me"), ("quote", "say \"hello\"")]
            path = tmpDir </> "config.dhall"
        TIO.writeFile path (serializeConfig original)
        result <- evalConfigFile path
        result `shouldBe` original

  describe "escapeDhallText" $ do
    it "passes through plain text unchanged" $ do
      escapeDhallText "hello world" `shouldBe` "hello world"

    it "escapes backslashes" $ do
      escapeDhallText "a\\b" `shouldBe` "a\\\\b"

    it "escapes double-quotes" $ do
      escapeDhallText "say \"hi\"" `shouldBe` "say \\\"hi\\\""
