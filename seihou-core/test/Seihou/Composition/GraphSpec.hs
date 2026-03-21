module Seihou.Composition.GraphSpec (tests) where

import Data.Either (isLeft)
import Seihou.Composition.Graph
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

spec :: Spec
spec = do
  describe "buildGraph" $ do
    it "builds a graph from a single module with no dependencies" $ do
      let m = mkModule "base" []
          g = buildGraph [m]
      length (g.cgModules) `shouldBe` 1
      length (g.cgEdges) `shouldBe` 1

    it "builds a graph preserving dependency edges" $ do
      let a = mkModule "a" ["b", "c"]
          b = mkModule "b" []
          c = mkModule "c" []
          g = buildGraph [a, b, c]
      length (g.cgModules) `shouldBe` 3
      length (g.cgEdges) `shouldBe` 3

  describe "topoSort" $ do
    it "returns a single module with no dependencies" $ do
      let g = buildGraph [mkModule "base" []]
      topoSort g `shouldBe` Right ["base"]

    it "orders a linear chain: A -> B -> C" $ do
      let a = mkModule "a" ["b"]
          b = mkModule "b" ["c"]
          c = mkModule "c" []
          g = buildGraph [a, b, c]
      case topoSort g of
        Right order -> do
          indexOf "c" order `shouldSatisfy` (< indexOf "b" order)
          indexOf "b" order `shouldSatisfy` (< indexOf "a" order)
        Left err -> expectationFailure $ "Expected Right, got: " ++ show err

    it "handles a diamond: A -> [B,C], B -> D, C -> D" $ do
      let a = mkModule "a" ["b", "c"]
          b = mkModule "b" ["d"]
          c = mkModule "c" ["d"]
          d = mkModule "d" []
          g = buildGraph [a, b, c, d]
      case topoSort g of
        Right order -> do
          length order `shouldBe` 4
          indexOf "d" order `shouldSatisfy` (< indexOf "b" order)
          indexOf "d" order `shouldSatisfy` (< indexOf "c" order)
          indexOf "b" order `shouldSatisfy` (< indexOf "a" order)
          indexOf "c" order `shouldSatisfy` (< indexOf "a" order)
        Left err -> expectationFailure $ "Expected Right, got: " ++ show err

    it "detects a self-loop" $ do
      let a = mkModule "a" ["a"]
          g = buildGraph [a]
      topoSort g `shouldSatisfy` isLeft

    it "detects a cycle: A -> B -> C -> A" $ do
      let a = mkModule "a" ["b"]
          b = mkModule "b" ["c"]
          c = mkModule "c" ["a"]
          g = buildGraph [a, b, c]
      topoSort g `shouldSatisfy` isLeft

    it "handles disconnected components" $ do
      let a = mkModule "a" []
          b = mkModule "b" []
          c = mkModule "c" []
          g = buildGraph [a, b, c]
      case topoSort g of
        Right order -> length order `shouldBe` 3
        Left err -> expectationFailure $ "Expected Right, got: " ++ show err

    it "handles a larger graph with multiple dependencies" $ do
      let e = mkModule "e" []
          d = mkModule "d" ["e"]
          c = mkModule "c" ["e"]
          b = mkModule "b" ["c", "d"]
          a = mkModule "a" ["b"]
          g = buildGraph [a, b, c, d, e]
      case topoSort g of
        Right order -> do
          length order `shouldBe` 5
          indexOf "e" order `shouldSatisfy` (< indexOf "d" order)
          indexOf "e" order `shouldSatisfy` (< indexOf "c" order)
          indexOf "c" order `shouldSatisfy` (< indexOf "b" order)
          indexOf "d" order `shouldSatisfy` (< indexOf "b" order)
          indexOf "b" order `shouldSatisfy` (< indexOf "a" order)
        Left err -> expectationFailure $ "Expected Right, got: " ++ show err

-- | Get the index of a ModuleName in a list, or fail.
indexOf :: ModuleName -> [ModuleName] -> Int
indexOf name xs = case lookup name (zip xs [0 ..]) of
  Just i -> i
  Nothing -> error $ "Module not found in order: " ++ show name
