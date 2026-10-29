module Seihou.Core.RecipeSpec (tests) where

import Control.Lens ((&), (.~))
import Data.Generics.Labels ()
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
    it "accepts camelCase bindings without recipe declarations or installed members" $ do
      let recipe = interactiveRecipe & #modules .~ [Dependency "unavailable" (Map.fromList [("git.githubOwner", "tan"), ("git.createGithub", "true"), ("git.githubVisibility", "private")]) Nothing]
      validateRecipe recipe `shouldBe` Right recipe

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
                  [ Dependency (ModuleName "mod-a") (Map.singleton (VarName "INVALID") "val") Nothing
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
                  [ Dependency (ModuleName "mod-a") (Map.singleton (VarName "nix.system") "aarch64-darwin") Nothing
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

    it "rejects malformed patterns without resolving absent optional inputs or members" $ do
      let recipe = interactiveRecipe & #vars .~ [VarDecl "owner" VTText Nothing Nothing False (Just (ValPattern "["))] & #prompts .~ []
      case validateRecipe recipe of
        Left errs -> hasError "invalid pattern" errs `shouldBe` True
        Right _ -> expectationFailure "Expected descriptor-local pattern failure"

    it "accepts unanswered required declarations and nested conditions" $ do
      validateRecipe interactiveRecipe `shouldBe` Right interactiveRecipe

    it "reports duplicate declarations, prompt targets and all nested references together" $ do
      let recipe =
            Recipe
              "interactive"
              Nothing
              Nothing
              [simpleDep "unavailable"]
              [requiredVar "enabled", requiredVar "enabled"]
              [Prompt "missing-target" "Question" (Just (ExprAnd (ExprIsSet "unknown-a") (ExprNot (ExprOr (ExprLit True) (ExprEq "unknown-b" (VBool False)))))) Nothing]
      case validateRecipe recipe of
        Left errs -> do
          length errs `shouldBe` 4
          mapM_
            (\needle -> hasError needle errs `shouldBe` True)
            ["vars: duplicate", "missing-target", "unknown-a", "unknown-b"]
        Right _ -> expectationFailure "Expected all four descriptor errors"

requiredVar :: VarName -> VarDecl
requiredVar name = VarDecl name VTBool Nothing Nothing True Nothing

interactiveRecipe :: Recipe
interactiveRecipe =
  Recipe
    "interactive"
    Nothing
    Nothing
    [Dependency "unavailable" (Map.singleton "member.only" "literal ${unchanged}") Nothing]
    [requiredVar "enabled", requiredVar "owner"]
    [Prompt "owner" "Owner?" (Just (ExprAnd (ExprEq "enabled" (VBool True)) (ExprNot (ExprOr (ExprIsSet "owner") (ExprLit False))))) Nothing]
