module Seihou.Core.RecipeSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Seihou.Core.Recipe (validateRecipe)
import Seihou.Core.Types
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Core.Recipe" spec

hasError :: T.Text -> [T.Text] -> Bool
hasError needle = any (T.isInfixOf needle)

spec :: Spec
spec = do
  describe "validateRecipe" $ do
    it "passes a valid recipe" $ do
      let recipe =
            Recipe
              { name = "valid-recipe",
                version = Just "1.0.0",
                description = Just "A valid recipe",
                modules = [simpleDep "mod-a", simpleDep "mod-b"],
                vars = [],
                prompts = []
              }
      validateRecipe recipe `shouldBe` Right recipe

    it "rejects an empty modules list" $ do
      let recipe =
            Recipe
              { name = "empty-recipe",
                version = Nothing,
                description = Nothing,
                modules = [],
                vars = [],
                prompts = []
              }
      case validateRecipe recipe of
        Left errs -> hasError "at least one module" errs `shouldBe` True
        Right _ -> expectationFailure "Expected validation failure"

    it "rejects an invalid recipe name" $ do
      let recipe =
            Recipe
              { name = "BadName",
                version = Nothing,
                description = Nothing,
                modules = [simpleDep "mod-a"],
                vars = [],
                prompts = []
              }
      case validateRecipe recipe of
        Left errs -> hasError "recipe name must match" errs `shouldBe` True
        Right _ -> expectationFailure "Expected validation failure"

    it "rejects duplicate module names" $ do
      let recipe =
            Recipe
              { name = "dup-recipe",
                version = Nothing,
                description = Nothing,
                modules = [simpleDep "mod-a", simpleDep "mod-b", simpleDep "mod-a"],
                vars = [],
                prompts = []
              }
      case validateRecipe recipe of
        Left errs -> hasError "duplicate module" errs `shouldBe` True
        Right _ -> expectationFailure "Expected validation failure"

    it "rejects invalid variable binding name" $ do
      let recipe =
            Recipe
              { name = "bad-var-recipe",
                version = Nothing,
                description = Nothing,
                modules =
                  [ Dependency (ModuleName "mod-a") (Map.singleton (VarName "INVALID") "val")
                  ],
                vars = [],
                prompts = []
              }
      case validateRecipe recipe of
        Left errs -> hasError "invalid var binding name" errs `shouldBe` True
        Right _ -> expectationFailure "Expected validation failure"

    it "accepts valid variable binding names with dots" $ do
      let recipe =
            Recipe
              { name = "dotted-vars",
                version = Nothing,
                description = Nothing,
                modules =
                  [ Dependency (ModuleName "mod-a") (Map.singleton (VarName "nix.system") "aarch64-darwin")
                  ],
                vars = [],
                prompts = []
              }
      validateRecipe recipe `shouldBe` Right recipe

    it "collects multiple errors at once" $ do
      let recipe =
            Recipe
              { name = "BadName",
                version = Nothing,
                description = Nothing,
                modules = [],
                vars = [],
                prompts = []
              }
      case validateRecipe recipe of
        Left errs -> length errs `shouldSatisfy` (>= 2)
        Right _ -> expectationFailure "Expected validation failure"
