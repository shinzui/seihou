module Seihou.Effect.ConfigReaderSpec (tests) where

import Data.Map.Strict qualified as Map
import Effectful
import Seihou.Effect.ConfigReader (readGlobalConfig, readLocalConfig, readNamespaceConfig)
import Seihou.Effect.ConfigReaderPure (runConfigReaderPure)
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
      result `shouldBe` globalCfg

    it "ReadLocalConfig returns the scripted local map" $ do
      let localCfg = Map.fromList [("project.name", "local-app")]
          result = runPureEff $ runConfigReaderPure localCfg Map.empty Map.empty readLocalConfig
      result `shouldBe` localCfg

    it "ReadNamespaceConfig returns the scripted namespace map" $ do
      let nsCfgs = Map.fromList [("haskell", Map.fromList [("haskell.ghc", "9.12.2")])]
          result = runPureEff $ runConfigReaderPure Map.empty nsCfgs Map.empty (readNamespaceConfig "haskell")
      result `shouldBe` Map.fromList [("haskell.ghc", "9.12.2")]

    it "ReadNamespaceConfig returns empty for unknown namespace" $ do
      let nsCfgs = Map.fromList [("haskell", Map.fromList [("haskell.ghc", "9.12.2")])]
          result = runPureEff $ runConfigReaderPure Map.empty nsCfgs Map.empty (readNamespaceConfig "nix")
      result `shouldBe` Map.empty

    it "returns independent values from each config layer" $ do
      let localCfg = Map.fromList [("project.name", "local-app")]
          nsCfgs = Map.fromList [("haskell", Map.fromList [("haskell.ghc", "9.12.2")])]
          globalCfg = Map.fromList [("license", "MIT")]
          (local, ns, global) = runPureEff $ runConfigReaderPure localCfg nsCfgs globalCfg $ do
            l <- readLocalConfig
            n <- readNamespaceConfig "haskell"
            g <- readGlobalConfig
            pure (l, n, g)
      local `shouldBe` localCfg
      ns `shouldBe` Map.fromList [("haskell.ghc", "9.12.2")]
      global `shouldBe` globalCfg
