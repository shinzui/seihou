module Seihou.CLI.RebindingSpec (tests) where

import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Time (UTCTime (..), fromGregorian)
import Seihou.CLI.Update.Rebinding
import Seihou.CLI.Update.Types
import Seihou.Composition.Instance (ModuleInstance (..))
import Seihou.Core.Types
import Seihou.Prelude
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

bindings = ParentVars . Map.fromList

state vars values = AppliedInstanceState "child" (bindings vars) (LocalOrigin "child") (Just "1.0.0") (Map.fromList values) Nothing

instanceId vars = ModuleInstance "child" (bindings vars)

align states candidates = alignPriorInstances (AppliedComposition (ApplicationId "app") (AppliedModuleTarget "parent") (LocalOrigin "parent") (Just "1.0.0") [] Nothing Nothing states Map.empty [] Nothing Nothing (UTCTime (fromGregorian 2026 11 11) 0)) (map instanceId candidates)

saved result vars = Map.findWithDefault Map.empty (instanceId vars) (carriedSavedValues result)

tests :: IO TestTree
tests = testSpec "rebinding alignment" $ do
  it "keeps exact matches and their values unchanged" $ do
    let result = align [state [] [("extra", "saved")]] [[]]
    Map.size (result ^. #priors) `shouldBe` 1
    result ^. #rebindings `shouldBe` []
    result ^. #unpaired `shouldBe` []
    saved result [] `shouldBe` Map.singleton "extra" "saved"
  it "carries project inputs but lets an added binding win" $ do
    let result = align [state [] [("project.name", "demo"), ("opt", "custom"), ("extra", "none")]] [[("extra", "x")]]
    length (result ^. #rebindings) `shouldBe` 1
    saved result [("extra", "x")] `shouldBe` Map.fromList [("project.name", "demo"), ("opt", "custom")]
  it "drops replaced and removed bound values while preserving project overrides" $ do
    let old value = state [("extra", "x")] [("extra", value), ("opt", "custom")]
    saved (align [old "x"] [[("extra", "y")]]) [("extra", "y")] `shouldBe` Map.singleton "opt" "custom"
    saved (align [old "x"] [[]]) [] `shouldBe` Map.singleton "opt" "custom"
    saved (align [old "override"] [[]]) [] `shouldBe` Map.fromList [("extra", "override"), ("opt", "custom")]
  it "preserves distinct exact invocations" $ do
    let result = align [state [("slot", "a")] [("opt", "one")], state [("slot", "b")] [("opt", "two")]] [[("slot", "b")], [("slot", "a")]]
    result ^. #rebindings `shouldBe` []
    saved result [("slot", "a")] `shouldBe` Map.singleton "opt" "one"
    saved result [("slot", "b")] `shouldBe` Map.singleton "opt" "two"
  it "pairs one leftover invocation after exact matches" $ do
    let result = align [state [("slot", "a")] [], state [("slot", "b")] [("opt", "two")]] [[("slot", "a")], [("slot", "b"), ("extra", "1")]]
    Map.size (result ^. #priors) `shouldBe` 2
    length (result ^. #rebindings) `shouldBe` 1
    saved result [("slot", "b"), ("extra", "1")] `shouldBe` Map.singleton "opt" "two"
  it "refuses every nonunique unmatched pairing deterministically" $ do
    let old = [state [("slot", "b")] [], state [("slot", "a")] []]
        candidates = [[("slot", "d")], [("slot", "c")]]
    mapM_
      ( \(os, cs) -> do
          let result = align os cs
          result ^. #priors `shouldBe` Map.empty
          result ^. #rebindings `shouldBe` []
          length (result ^. #unpaired) `shouldBe` 1
      )
      [(old, candidates), (take 1 old, candidates), (old, take 1 candidates)]
    map (^. #recorded) (align old candidates ^. #unpaired) `shouldBe` [[bindings [("slot", "a")], bindings [("slot", "b")]]]
  it "does not pair purely new or removed invocations" $ do
    align [] [[]] ^. #priors `shouldBe` Map.empty
    align [state [] []] [] ^. #unpaired `shouldBe` []
