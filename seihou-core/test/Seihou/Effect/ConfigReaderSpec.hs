module Seihou.Effect.ConfigReaderSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Effectful
import Seihou.Core.Types (ConfigError (..))
import Seihou.Dhall.Config (evalConfigFileIfExists)
import Seihou.Effect.ConfigReader (readGlobalConfig, readLocalConfig, readNamespaceConfig)
import Seihou.Effect.ConfigReaderInterp (runConfigReader)
import Seihou.Effect.ConfigReaderPure (runConfigReaderPure)
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Effect.ConfigReader" spec

spec :: Spec
spec = do
  describe "pure interpreter" $ do
    it "ReadGlobalConfig returns the scripted global map" $ do
      let globalCfg = Map.fromList [("license", "MIT"), ("author", "Test")]
          result = runPureEff $ runConfigReaderPure Map.empty Map.empty globalCfg readGlobalConfig
      result `shouldBe` Right globalCfg

    it "ReadLocalConfig returns the scripted local map" $ do
      let localCfg = Map.fromList [("project.name", "local-app")]
          result = runPureEff $ runConfigReaderPure localCfg Map.empty Map.empty readLocalConfig
      result `shouldBe` Right localCfg

    it "ReadNamespaceConfig returns the scripted namespace map" $ do
      let nsCfgs = Map.fromList [("haskell", Map.fromList [("haskell.ghc", "9.12.2")])]
          result = runPureEff $ runConfigReaderPure Map.empty nsCfgs Map.empty (readNamespaceConfig "haskell")
      result `shouldBe` Right (Map.fromList [("haskell.ghc", "9.12.2")])

    it "ReadNamespaceConfig returns empty for unknown namespace" $ do
      let nsCfgs = Map.fromList [("haskell", Map.fromList [("haskell.ghc", "9.12.2")])]
          result = runPureEff $ runConfigReaderPure Map.empty nsCfgs Map.empty (readNamespaceConfig "nix")
      result `shouldBe` Right Map.empty

    it "returns independent values from each config layer" $ do
      let localCfg = Map.fromList [("project.name", "local-app")]
          nsCfgs = Map.fromList [("haskell", Map.fromList [("haskell.ghc", "9.12.2")])]
          globalCfg = Map.fromList [("license", "MIT")]
          (local, ns, global) = runPureEff $ runConfigReaderPure localCfg nsCfgs globalCfg $ do
            l <- readLocalConfig
            n <- readNamespaceConfig "haskell"
            g <- readGlobalConfig
            pure (l, n, g)
      local `shouldBe` Right localCfg
      ns `shouldBe` Right (Map.fromList [("haskell.ghc", "9.12.2")])
      global `shouldBe` Right globalCfg

  describe "namespace validation (IO interpreter)" $ do
    it "rejects namespace containing '..'" $ do
      result <- runEff $ runConfigReader $ readNamespaceConfig "../etc"
      case result of
        Left (InvalidNamespace ns _) -> ns `shouldBe` "../etc"
        Left other -> expectationFailure ("Expected InvalidNamespace, got: " <> show other)
        Right _ -> expectationFailure "Expected Left for path traversal namespace"

    it "rejects namespace containing '/'" $ do
      result <- runEff $ runConfigReader $ readNamespaceConfig "foo/bar"
      case result of
        Left (InvalidNamespace ns _) -> ns `shouldBe` "foo/bar"
        Left other -> expectationFailure ("Expected InvalidNamespace, got: " <> show other)
        Right _ -> expectationFailure "Expected Left for namespace with slash"

    it "accepts a normal namespace" $ do
      result <- runEff $ runConfigReader $ readNamespaceConfig "haskell"
      case result of
        Left (InvalidNamespace _ _) -> expectationFailure "Did not expect InvalidNamespace for 'haskell'"
        _ -> pure () -- Right or ConfigParseError (missing file) are both OK
    it "returns Right empty for empty namespace" $ do
      result <- runEff $ runConfigReader $ readNamespaceConfig ""
      result `shouldBe` Right Map.empty

  describe "config parse error propagation" $ do
    it "evalConfigFileIfExists returns Left for malformed Dhall" $ do
      withSystemTempDirectory "seihou-test" $ \tmpDir -> do
        let path = tmpDir <> "/bad.dhall"
        writeFile path "{ this is not valid dhall"
        result <- evalConfigFileIfExists path
        case result of
          Left err -> T.isInfixOf "Error reading config" err `shouldBe` True
          Right _ -> expectationFailure "Expected Left for malformed Dhall"
