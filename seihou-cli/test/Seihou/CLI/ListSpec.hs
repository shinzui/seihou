module Seihou.CLI.ListSpec (tests) where

import Data.Text qualified as T
import Seihou.CLI.List (Entry (..), ListFilter (..), applyFilters, formatListOutput)
import Seihou.Core.Module (DiscoveredModule (..), ModuleSource (..))
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
              removal = Nothing
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

-- | Helper to build an Entry for filter tests.
mkEntry :: T.Text -> Maybe T.Text -> [T.Text] -> Entry
mkEntry name repo tags =
  Entry
    { entryName = name,
      entryDesc = "desc",
      entrySource = "installed",
      entryIsError = False,
      entryRepoName = repo,
      entryTags = tags
    }

noFilter :: ListFilter
noFilter = ListFilter Nothing Nothing

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
      T.isInfixOf "Available modules and recipes:" result `shouldBe` True

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
      let opts = ListFilter (Just "repo-x") Nothing
          result = applyFilters opts entries
      length result `shouldBe` 2
      map (.entryName) result `shouldBe` ["mod-a", "mod-b"]

    it "filters by tag" $ do
      let opts = ListFilter Nothing (Just "haskell")
          result = applyFilters opts entries
      length result `shouldBe` 2
      map (.entryName) result `shouldBe` ["mod-a", "mod-c"]

    it "combines repo and tag filters with AND" $ do
      let opts = ListFilter (Just "repo-x") (Just "haskell")
          result = applyFilters opts entries
      length result `shouldBe` 1
      map (.entryName) result `shouldBe` ["mod-a"]

    it "returns empty list when repo filter matches nothing" $ do
      let opts = ListFilter (Just "nonexistent") Nothing
          result = applyFilters opts entries
      result `shouldBe` []

    it "returns empty list when tag filter matches nothing" $ do
      let opts = ListFilter Nothing (Just "ruby")
          result = applyFilters opts entries
      result `shouldBe` []

    it "excludes modules without origin metadata when repo filter is active" $ do
      let opts = ListFilter (Just "repo-x") Nothing
          result = applyFilters opts entries
      all (\e -> e.entryRepoName == Just "repo-x") result `shouldBe` True
