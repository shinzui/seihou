module Seihou.Composition.InstanceSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Seihou.Composition.Instance
import Seihou.Core.Types
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Composition.Instance" spec

spec :: Spec
spec = do
  describe "qualifiedName" $ do
    it "returns the plain module name when no parent bindings are present" $ do
      qualifiedName (primaryInstance "claude-skill-link")
        `shouldBe` ModuleName "claude-skill-link"

    it "appends a stable hash suffix when parent bindings are present" $ do
      let inst = mkInstance "claude-skill-link" (ParentVars (Map.singleton "skill.name" "exec-plan"))
          qn = qualifiedName inst
      T.isPrefixOf "claude-skill-link#" (qn.unModuleName) `shouldBe` True
      T.length (qn.unModuleName) `shouldBe` T.length "claude-skill-link#" + 8

    it "produces a distinct qualified name for each distinct binding" $ do
      let a = mkInstance "claude-skill-link" (ParentVars (Map.singleton "skill.name" "exec-plan"))
          b = mkInstance "claude-skill-link" (ParentVars (Map.singleton "skill.name" "master-plan"))
      qualifiedName a `shouldNotBe` qualifiedName b

    it "is stable across equal but differently constructed binding maps" $ do
      let vs1 = Map.fromList [("a", "1"), ("b", "2")]
          vs2 = Map.fromList [("b", "2"), ("a", "1")]
          ia = mkInstance "m" (ParentVars vs1)
          ib = mkInstance "m" (ParentVars vs2)
      qualifiedName ia `shouldBe` qualifiedName ib

  describe "stableHash" $ do
    it "returns 8 hex characters for any binding set" $ do
      let h = stableHash (ParentVars (Map.singleton "x" "1"))
      T.length h `shouldBe` 8

    it "ignores construction order" $ do
      stableHash (ParentVars (Map.fromList [("a", "1"), ("b", "2")]))
        `shouldBe` stableHash (ParentVars (Map.fromList [("b", "2"), ("a", "1")]))

    it "differs when binding values differ" $ do
      stableHash (ParentVars (Map.singleton "skill.name" "exec-plan"))
        `shouldNotBe` stableHash (ParentVars (Map.singleton "skill.name" "master-plan"))

  describe "ParentVars Eq/Ord" $ do
    it "two ParentVars with identical maps compare equal" $ do
      let a = ParentVars (Map.fromList [("a", "1"), ("b", "2")])
          b = ParentVars (Map.fromList [("b", "2"), ("a", "1")])
      a `shouldBe` b
