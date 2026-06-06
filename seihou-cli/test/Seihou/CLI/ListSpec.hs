module Seihou.CLI.ListSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Seihou.CLI.List (Entry (..), ListFilter (..), applyFilters, formatListOutput, runnableToEntryWithOrigin)
import Seihou.Core.Module (DiscoveredModule (..), DiscoveredRunnable (..), ModuleSource (..), RunnableKind (..))
import Seihou.Core.Types
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.CLI.List" spec

-- | A valid discovered module for testing.
validModule :: String -> String -> ModuleSource -> DiscoveredModule
validModule name desc src =
  DiscoveredModule
    { discoveredResult =
        Right
          Module
            { name = ModuleName (T.pack name),
              version = Nothing,
              description = Just (T.pack desc),
              vars = [],
              exports = [],
              prompts = [],
              steps = [],
              commands = [],
              dependencies = [],
              removal = Nothing,
              migrations = []
            },
      discoveredSource = src,
      discoveredDir = "/fake/" ++ name
    }

-- | A broken discovered module for testing.
brokenModule :: String -> ModuleSource -> DiscoveredModule
brokenModule name src =
  DiscoveredModule
    { discoveredResult = Left (DhallEvalError (ModuleName (T.pack name)) "parse error"),
      discoveredSource = src,
      discoveredDir = "/fake/" ++ name
    }

-- | Helper to build an Entry for filter tests.  Defaults the kind to a module.
mkEntry :: T.Text -> Maybe T.Text -> [T.Text] -> Entry
mkEntry = mkEntryK KindModule

-- | Helper to build an Entry with an explicit kind for kind-filter tests.
mkEntryK :: RunnableKind -> T.Text -> Maybe T.Text -> [T.Text] -> Entry
mkEntryK kind name repo tags =
  Entry
    { entryName = name,
      entryDesc = "desc",
      entrySource = "installed",
      entryIsError = False,
      entryRepoName = repo,
      entryTags = tags,
      entryKind = kind
    }

noFilter :: ListFilter
noFilter = ListFilter Nothing Nothing []

spec :: Spec
spec = do
  describe "formatListOutput" $ do
    it "shows no-modules message when list is empty" $ do
      let result = formatListOutput False [] ["path1", "path2"]
      T.isInfixOf "No modules found." result `shouldBe` True
      T.isInfixOf "path1" result `shouldBe` True
      T.isInfixOf "path2" result `shouldBe` True

    it "shows available modules header" $ do
      let mods = [validModule "test-mod" "A test module" SourceUser]
          result = formatListOutput False mods ["p1", "p2", "p3"]
      T.isInfixOf "Available modules, recipes, and blueprints:" result `shouldBe` True

    it "shows module name and description" $ do
      let mods = [validModule "haskell-base" "Haskell boilerplate" SourceUser]
          result = formatListOutput False mods ["p1"]
      T.isInfixOf "haskell-base" result `shouldBe` True
      T.isInfixOf "Haskell boilerplate" result `shouldBe` True

    it "shows source tag in parentheses" $ do
      let mods = [validModule "my-mod" "desc" SourceInstalled]
          result = formatListOutput False mods ["p1"]
      T.isInfixOf "(installed)" result `shouldBe` True

    it "shows error indicator for failed modules" $ do
      let mods = [brokenModule "broken-mod" SourceUser]
          result = formatListOutput False mods ["p1"]
      T.isInfixOf "[error:" result `shouldBe` True
      T.isInfixOf "broken-mod" result `shouldBe` True

    it "shows count summary" $ do
      let mods =
            [ validModule "mod-a" "desc a" SourceProject,
              validModule "mod-b" "desc b" SourceInstalled
            ]
          result = formatListOutput False mods ["p1", "p2", "p3"]
      T.isInfixOf "2 modules found" result `shouldBe` True
      T.isInfixOf "3 sources searched" result `shouldBe` True

    it "shows singular noun for one module" $ do
      let mods = [validModule "only-one" "desc" SourceUser]
          result = formatListOutput False mods ["p1"]
      T.isInfixOf "1 module found" result `shouldBe` True

  describe "applyFilters" $ do
    let entries =
          [ mkEntry "mod-a" (Just "repo-x") ["haskell", "cli"],
            mkEntry "mod-b" (Just "repo-x") ["python"],
            mkEntry "mod-c" (Just "repo-y") ["haskell"],
            mkEntry "mod-d" Nothing []
          ]

    it "returns all entries with no filters" $ do
      let result = applyFilters noFilter entries
      length result `shouldBe` 4

    it "filters by repo name" $ do
      let opts = ListFilter (Just "repo-x") Nothing []
          result = applyFilters opts entries
      length result `shouldBe` 2
      map (.entryName) result `shouldBe` ["mod-a", "mod-b"]

    it "filters by tag" $ do
      let opts = ListFilter Nothing (Just "haskell") []
          result = applyFilters opts entries
      length result `shouldBe` 2
      map (.entryName) result `shouldBe` ["mod-a", "mod-c"]

    it "combines repo and tag filters with AND" $ do
      let opts = ListFilter (Just "repo-x") (Just "haskell") []
          result = applyFilters opts entries
      length result `shouldBe` 1
      map (.entryName) result `shouldBe` ["mod-a"]

    it "returns empty list when repo filter matches nothing" $ do
      let opts = ListFilter (Just "nonexistent") Nothing []
          result = applyFilters opts entries
      result `shouldBe` []

    it "returns empty list when tag filter matches nothing" $ do
      let opts = ListFilter Nothing (Just "ruby") []
          result = applyFilters opts entries
      result `shouldBe` []

    it "excludes modules without origin metadata when repo filter is active" $ do
      let opts = ListFilter (Just "repo-x") Nothing []
          result = applyFilters opts entries
      all (\e -> e.entryRepoName == Just "repo-x") result `shouldBe` True

  describe "applyFilters (by kind)" $ do
    let mixed =
          [ mkEntryK KindModule "mod-a" Nothing [],
            mkEntryK KindRecipe "rec-a" Nothing [],
            mkEntryK KindBlueprint "bp-a" Nothing [],
            mkEntryK KindModule "mod-b" (Just "repo-x") ["haskell"]
          ]

    it "keeps all kinds when filterKinds is empty" $ do
      length (applyFilters (ListFilter Nothing Nothing []) mixed) `shouldBe` 4

    it "keeps only modules with --modules" $ do
      let result = applyFilters (ListFilter Nothing Nothing [KindModule]) mixed
      map (.entryName) result `shouldBe` ["mod-a", "mod-b"]

    it "keeps only recipes with --recipes" $ do
      let result = applyFilters (ListFilter Nothing Nothing [KindRecipe]) mixed
      map (.entryName) result `shouldBe` ["rec-a"]

    it "keeps only blueprints with --blueprints" $ do
      let result = applyFilters (ListFilter Nothing Nothing [KindBlueprint]) mixed
      map (.entryName) result `shouldBe` ["bp-a"]

    it "unions kinds when several flags are given" $ do
      let result = applyFilters (ListFilter Nothing Nothing [KindModule, KindRecipe]) mixed
      map (.entryName) result `shouldBe` ["mod-a", "rec-a", "mod-b"]

    it "combines kind and repo with AND" $ do
      let result = applyFilters (ListFilter (Just "repo-x") Nothing [KindModule]) mixed
      map (.entryName) result `shouldBe` ["mod-b"]

    it "returns empty when kind matches nothing in the set" $ do
      let onlyRecipes = filter (\e -> e.entryKind == KindRecipe) mixed
          result = applyFilters (ListFilter Nothing Nothing [KindBlueprint]) onlyRecipes
      result `shouldBe` []

  describe "runnableToEntryWithOrigin (blueprint)" $ do
    it "tags blueprint entries with [blueprint] in the source label" $ do
      let dr =
            DiscoveredRunnable
              { drName = "demo",
                drDescription = Just "A new seihou blueprint",
                drKind = KindBlueprint,
                drSource = SourceProject,
                drDir = "/fake/demo",
                drIsError = False,
                drError = Nothing
              }
          entry = runnableToEntryWithOrigin Map.empty dr
      entry.entrySource `shouldBe` "project [blueprint]"
      entry.entryName `shouldBe` "demo"
      entry.entryIsError `shouldBe` False
      entry.entryKind `shouldBe` KindBlueprint
