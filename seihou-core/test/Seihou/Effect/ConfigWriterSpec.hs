module Seihou.Effect.ConfigWriterSpec (tests) where

import Data.Map.Strict qualified as Map
import Effectful
import Seihou.Core.Types (ConfigScope (..))
import Seihou.Effect.ConfigWriter (ConfigWriter, deleteConfigValue, listConfigValues, writeConfigValue)
import Seihou.Effect.ConfigWriterPure (ConfigWriterState (..), emptyConfigWriterState, runConfigWriterPure)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Effect.ConfigWriter" spec

run :: ConfigWriterState -> Eff '[ConfigWriter] a -> (a, ConfigWriterState)
run st action = runPureEff $ runConfigWriterPure st action

spec :: Spec
spec = do
  describe "writeConfigValue + listConfigValues" $ do
    it "writes a value and lists it back" $ do
      let (result, _) = run emptyConfigWriterState $ do
            writeConfigValue ScopeLocal "project.name" "my-app"
            listConfigValues ScopeLocal
      result `shouldBe` Right (Map.fromList [("project.name", "my-app")])

    it "overwrites an existing value" $ do
      let initial = emptyConfigWriterState {cwLocal = Map.fromList [("key", "old")]}
          (result, _) = run initial $ do
            writeConfigValue ScopeLocal "key" "new"
            listConfigValues ScopeLocal
      result `shouldBe` Right (Map.fromList [("key", "new")])

    it "preserves other keys when writing" $ do
      let initial = emptyConfigWriterState {cwLocal = Map.fromList [("existing", "keep")]}
          (result, _) = run initial $ do
            writeConfigValue ScopeLocal "new-key" "added"
            listConfigValues ScopeLocal
      result `shouldBe` Right (Map.fromList [("existing", "keep"), ("new-key", "added")])

    it "writes to global scope independently of local" $ do
      let (resultLocal, _) = run emptyConfigWriterState $ do
            writeConfigValue ScopeGlobal "license" "MIT"
            listConfigValues ScopeLocal
          (resultGlobal, _) = run emptyConfigWriterState $ do
            writeConfigValue ScopeGlobal "license" "MIT"
            listConfigValues ScopeGlobal
      resultLocal `shouldBe` Right Map.empty
      resultGlobal `shouldBe` Right (Map.fromList [("license", "MIT")])

    it "writes to namespace scope" $ do
      let (result, _) = run emptyConfigWriterState $ do
            writeConfigValue (ScopeNamespace "haskell") "haskell.ghc" "9.12.2"
            listConfigValues (ScopeNamespace "haskell")
      result `shouldBe` Right (Map.fromList [("haskell.ghc", "9.12.2")])

    it "keeps namespace scopes independent" $ do
      let (r1, _) = run emptyConfigWriterState $ do
            writeConfigValue (ScopeNamespace "haskell") "key" "h-val"
            writeConfigValue (ScopeNamespace "nix") "key" "n-val"
            listConfigValues (ScopeNamespace "haskell")
          (r2, _) = run emptyConfigWriterState $ do
            writeConfigValue (ScopeNamespace "haskell") "key" "h-val"
            writeConfigValue (ScopeNamespace "nix") "key" "n-val"
            listConfigValues (ScopeNamespace "nix")
      r1 `shouldBe` Right (Map.fromList [("key", "h-val")])
      r2 `shouldBe` Right (Map.fromList [("key", "n-val")])

  describe "deleteConfigValue" $ do
    it "removes an existing value" $ do
      let initial = emptyConfigWriterState {cwLocal = Map.fromList [("key", "val")]}
          (result, _) = run initial $ do
            deleteConfigValue ScopeLocal "key"
            listConfigValues ScopeLocal
      result `shouldBe` Right Map.empty

    it "is a no-op for nonexistent key" $ do
      let initial = emptyConfigWriterState {cwLocal = Map.fromList [("keep", "me")]}
          (result, _) = run initial $ do
            deleteConfigValue ScopeLocal "nonexistent"
            listConfigValues ScopeLocal
      result `shouldBe` Right (Map.fromList [("keep", "me")])

    it "deletes from global scope" $ do
      let initial = emptyConfigWriterState {cwGlobal = Map.fromList [("license", "MIT")]}
          (result, _) = run initial $ do
            deleteConfigValue ScopeGlobal "license"
            listConfigValues ScopeGlobal
      result `shouldBe` Right Map.empty

  describe "state inspection" $ do
    it "returns final state with all changes" $ do
      let (_, finalState) = run emptyConfigWriterState $ do
            writeConfigValue ScopeLocal "local.key" "l"
            writeConfigValue ScopeGlobal "global.key" "g"
            writeConfigValue (ScopeNamespace "ns") "ns.key" "n"
      finalState.cwLocal `shouldBe` Map.fromList [("local.key", "l")]
      finalState.cwGlobal `shouldBe` Map.fromList [("global.key", "g")]
      Map.lookup "ns" (finalState.cwNamespaces) `shouldBe` Just (Map.fromList [("ns.key", "n")])
