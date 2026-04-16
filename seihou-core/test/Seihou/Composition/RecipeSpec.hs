module Seihou.Composition.RecipeSpec (tests) where

import Data.Map.Strict qualified as Map
import Seihou.Composition.Recipe (expandRecipe)
import Seihou.Core.Types
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Composition.Recipe" spec

spec :: Spec
spec = do
  describe "expandRecipe" $ do
    it "returns correct primary and additional module names" $ do
      let recipe =
            Recipe
              { name = "combo",
                version = Just "1.0.0",
                description = Nothing,
                modules =
                  [ simpleDep "mod-a",
                    simpleDep "mod-b",
                    simpleDep "mod-c"
                  ],
                vars = [],
                prompts = []
              }
          (primary, additional, _, _, _) = expandRecipe recipe
      primary `shouldBe` ModuleName "mod-a"
      additional `shouldBe` [ModuleName "mod-b", ModuleName "mod-c"]

    it "collects variable overrides from module entries" $ do
      let recipe =
            Recipe
              { name = "pinned",
                version = Nothing,
                description = Nothing,
                modules =
                  [ Dependency (ModuleName "base") (Map.singleton "project.name" "my-app"),
                    Dependency (ModuleName "nix") (Map.singleton "nix.system" "aarch64-darwin")
                  ],
                vars = [],
                prompts = []
              }
          (_, _, overrides, _, _) = expandRecipe recipe
      Map.lookup (VarName "project.name") overrides `shouldBe` Just "my-app"
      Map.lookup (VarName "nix.system") overrides `shouldBe` Just "aarch64-darwin"

    it "passes through recipe-level vars and prompts" $ do
      let recipeVar =
            VarDecl
              { name = "project.name",
                type_ = VTText,
                default_ = Nothing,
                description = Just "Project name",
                required = True,
                validation = Nothing
              }
          recipePrompt =
            Prompt
              { var = "project.name",
                text = "Enter name:",
                condition = Nothing,
                choices = Nothing
              }
          recipe =
            Recipe
              { name = "prompted",
                version = Nothing,
                description = Nothing,
                modules = [simpleDep "base"],
                vars = [recipeVar],
                prompts = [recipePrompt]
              }
          (_, _, _, vars, prompts) = expandRecipe recipe
      length vars `shouldBe` 1
      (head vars).name `shouldBe` VarName "project.name"
      length prompts `shouldBe` 1
      (head prompts).var `shouldBe` VarName "project.name"

    it "handles a single-module recipe (alias)" $ do
      let recipe =
            Recipe
              { name = "alias",
                version = Nothing,
                description = Nothing,
                modules = [simpleDep "the-module"],
                vars = [],
                prompts = []
              }
          (primary, additional, overrides, _, _) = expandRecipe recipe
      primary `shouldBe` ModuleName "the-module"
      additional `shouldBe` []
      Map.null overrides `shouldBe` True
