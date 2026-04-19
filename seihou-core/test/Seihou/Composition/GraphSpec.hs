module Seihou.Composition.GraphSpec (tests) where

import Data.Either (isLeft)
import Data.Map.Strict qualified as Map
import Seihou.Composition.Graph
import Seihou.Composition.Instance (ModuleInstance (..), mkInstance, primaryInstance)
import Seihou.Core.Types
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Composition.Graph" spec

-- | Helper to create a minimal module with given name and dependencies.
mkModule :: ModuleName -> [ModuleName] -> Module
mkModule name deps =
  Module
    { name = name,
      version = Nothing,
      description = Nothing,
      vars = [],
      exports = [],
      prompts = [],
      steps = [],
      commands = [],
      dependencies = map simpleDep deps,
      removal = Nothing
    }

-- | Helper to build a graph from a list of modules, wrapping each in a
-- primary 'ModuleInstance' (no parent bindings). Works for all the
-- bare-name test scenarios below.
fromModules :: [Module] -> CompositionGraph
fromModules ms = buildGraph [(primaryInstance m.name, m) | m <- ms]

spec :: Spec
spec = do
  describe "buildGraph" $ do
    it "builds a graph from a single module with no dependencies" $ do
      let m = mkModule "base" []
          g = fromModules [m]
      length g.cgModules `shouldBe` 1
      length g.cgEdges `shouldBe` 1

    it "builds a graph preserving dependency edges" $ do
      let a = mkModule "a" ["b", "c"]
          b = mkModule "b" []
          c = mkModule "c" []
          g = fromModules [a, b, c]
      length g.cgModules `shouldBe` 3
      length g.cgEdges `shouldBe` 3

  describe "topoSort" $ do
    it "returns a single module with no dependencies" $ do
      let g = fromModules [mkModule "base" []]
      fmap (map (.instanceModule)) (topoSort g) `shouldBe` Right ["base"]

    it "orders a linear chain: A -> B -> C" $ do
      let a = mkModule "a" ["b"]
          b = mkModule "b" ["c"]
          c = mkModule "c" []
          g = fromModules [a, b, c]
      case topoSort g of
        Right order -> do
          let names = map (.instanceModule) order
          indexOf "c" names `shouldSatisfy` (< indexOf "b" names)
          indexOf "b" names `shouldSatisfy` (< indexOf "a" names)
        Left err -> expectationFailure $ "Expected Right, got: " ++ show err

    it "handles a diamond: A -> [B,C], B -> D, C -> D" $ do
      let a = mkModule "a" ["b", "c"]
          b = mkModule "b" ["d"]
          c = mkModule "c" ["d"]
          d = mkModule "d" []
          g = fromModules [a, b, c, d]
      case topoSort g of
        Right order -> do
          let names = map (.instanceModule) order
          length names `shouldBe` 4
          indexOf "d" names `shouldSatisfy` (< indexOf "b" names)
          indexOf "d" names `shouldSatisfy` (< indexOf "c" names)
          indexOf "b" names `shouldSatisfy` (< indexOf "a" names)
          indexOf "c" names `shouldSatisfy` (< indexOf "a" names)
        Left err -> expectationFailure $ "Expected Right, got: " ++ show err

    it "detects a self-loop" $ do
      let a = mkModule "a" ["a"]
          g = fromModules [a]
      topoSort g `shouldSatisfy` isLeft

    it "detects a cycle: A -> B -> C -> A" $ do
      let a = mkModule "a" ["b"]
          b = mkModule "b" ["c"]
          c = mkModule "c" ["a"]
          g = fromModules [a, b, c]
      topoSort g `shouldSatisfy` isLeft

    it "handles disconnected components" $ do
      let a = mkModule "a" []
          b = mkModule "b" []
          c = mkModule "c" []
          g = fromModules [a, b, c]
      case topoSort g of
        Right order -> length order `shouldBe` 3
        Left err -> expectationFailure $ "Expected Right, got: " ++ show err

    it "handles a larger graph with multiple dependencies" $ do
      let e = mkModule "e" []
          d = mkModule "d" ["e"]
          c = mkModule "c" ["e"]
          b = mkModule "b" ["c", "d"]
          a = mkModule "a" ["b"]
          g = fromModules [a, b, c, d, e]
      case topoSort g of
        Right order -> do
          let names = map (.instanceModule) order
          length names `shouldBe` 5
          indexOf "e" names `shouldSatisfy` (< indexOf "d" names)
          indexOf "e" names `shouldSatisfy` (< indexOf "c" names)
          indexOf "c" names `shouldSatisfy` (< indexOf "b" names)
          indexOf "d" names `shouldSatisfy` (< indexOf "b" names)
          indexOf "b" names `shouldSatisfy` (< indexOf "a" names)
        Left err -> expectationFailure $ "Expected Right, got: " ++ show err

  describe "multi-instantiation" $ do
    it "treats two dependency edges with different depVars as distinct instances" $ do
      let helper = mkModule "helper" []
          -- Parent depends on 'helper' twice with different bindings.
          parent' =
            Module
              { name = "parent",
                version = Nothing,
                description = Nothing,
                vars = [],
                exports = [],
                prompts = [],
                steps = [],
                commands = [],
                dependencies =
                  [ Dependency "helper" (Map.singleton "skill.name" "exec-plan"),
                    Dependency "helper" (Map.singleton "skill.name" "master-plan")
                  ],
                removal = Nothing
              }
          parentInst = primaryInstance "parent"
          helperA = mkInstance "helper" (ParentVars (Map.singleton "skill.name" "exec-plan"))
          helperB = mkInstance "helper" (ParentVars (Map.singleton "skill.name" "master-plan"))
          g = buildGraph [(parentInst, parent'), (helperA, helper), (helperB, helper)]
      case topoSort g of
        Right order -> do
          length order `shouldBe` 3
          helperA `elem` order `shouldBe` True
          helperB `elem` order `shouldBe` True
          parentInst `elem` order `shouldBe` True
          -- Both helper invocations must precede the parent.
          let idx x = length (takeWhile (/= x) order)
          idx helperA `shouldSatisfy` (< idx parentInst)
          idx helperB `shouldSatisfy` (< idx parentInst)
        Left err -> expectationFailure $ "Expected Right, got: " ++ show err

    it "dedupes two identical dependency edges into one instance" $ do
      let child = mkModule "child" []
          parent' =
            Module
              { name = "parent",
                version = Nothing,
                description = Nothing,
                vars = [],
                exports = [],
                prompts = [],
                steps = [],
                commands = [],
                dependencies =
                  [ Dependency "child" (Map.singleton "x" "1"),
                    Dependency "child" (Map.singleton "x" "1")
                  ],
                removal = Nothing
              }
          parentInst = primaryInstance "parent"
          childInst = mkInstance "child" (ParentVars (Map.singleton "x" "1"))
          g = buildGraph [(parentInst, parent'), (childInst, child)]
      case topoSort g of
        Right order -> length order `shouldBe` 2
        Left err -> expectationFailure $ "Expected Right, got: " ++ show err

-- | Get the index of a ModuleName in a list, or fail.
indexOf :: ModuleName -> [ModuleName] -> Int
indexOf name xs = case lookup name (zip xs [0 ..]) of
  Just i -> i
  Nothing -> error $ "Module not found in order: " ++ show name
