module Seihou.CLI.ListSpec (tests) where

import Control.Lens ((&), (.~), (^.))
import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Seihou.CLI.List (DescriptionMode (..), Entry (..), ListFilter (..), applyFilters, formatListOutput, formatListOutputEntries, runnableToEntryWithOrigin)
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
    { result =
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
      source = src,
      dir = "/fake/" ++ name
    }

-- | A broken discovered module for testing.
brokenModule :: String -> ModuleSource -> DiscoveredModule
brokenModule name src =
  DiscoveredModule
    { result = Left (DhallEvalError (ModuleName (T.pack name)) "parse error"),
      source = src,
      dir = "/fake/" ++ name
    }

-- | Helper to build an Entry for filter tests.  Defaults the kind to a module.
mkEntry :: T.Text -> Maybe T.Text -> [T.Text] -> Entry
mkEntry = mkEntryK KindModule

-- | Helper to build an Entry with an explicit kind for kind-filter tests.
mkEntryK :: RunnableKind -> T.Text -> Maybe T.Text -> [T.Text] -> Entry
mkEntryK kind name repo tags =
  Entry
    { name = name,
      desc = "desc",
      source = "installed",
      isError = False,
      repoName = repo,
      tags = tags,
      kind = kind
    }

noFilter :: ListFilter
noFilter = ListFilter Nothing Nothing []

spec :: Spec
spec = do
  describe "formatListOutput" $ do
    it "shows no-items message when list is empty" $ do
      let result = formatListOutput False [] ["path1", "path2"]
      T.isInfixOf "No items found." result `shouldBe` True
      T.isInfixOf "path1" result `shouldBe` True
      T.isInfixOf "path2" result `shouldBe` True

    it "opens with a kind heading carrying the count" $ do
      let mods = [validModule "test-mod" "A test module" SourceUser]
          result = formatListOutput False mods ["p1", "p2", "p3"]
      T.lines result `shouldSatisfy` (\ls -> take 2 ls == ["Modules (1)", ""])

    it "shows module name and description" $ do
      let mods = [validModule "haskell-base" "Haskell boilerplate" SourceUser]
          result = formatListOutput False mods ["p1"]
      T.isInfixOf "haskell-base" result `shouldBe` True
      T.isInfixOf "Haskell boilerplate" result `shouldBe` True

    it "puts the source on the name's line, the description indented below" $ do
      let mods = [validModule "my-mod" "desc" SourceInstalled]
          result = formatListOutput False mods ["p1"]
      T.lines result `shouldSatisfy` (\ls -> take 2 (drop 2 ls) == ["  my-mod  installed", "    desc"])

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
      map (^. #name) result `shouldBe` ["mod-a", "mod-b"]

    it "filters by tag" $ do
      let opts = ListFilter Nothing (Just "haskell") []
          result = applyFilters opts entries
      length result `shouldBe` 2
      map (^. #name) result `shouldBe` ["mod-a", "mod-c"]

    it "combines repo and tag filters with AND" $ do
      let opts = ListFilter (Just "repo-x") (Just "haskell") []
          result = applyFilters opts entries
      length result `shouldBe` 1
      map (^. #name) result `shouldBe` ["mod-a"]

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
      all (\e -> e ^. #repoName == Just "repo-x") result `shouldBe` True

  describe "applyFilters (by kind)" $ do
    let mixed =
          [ mkEntryK KindModule "mod-a" Nothing [],
            mkEntryK KindRecipe "rec-a" Nothing [],
            mkEntryK KindBlueprint "bp-a" Nothing [],
            mkEntryK KindPrompt "prompt-a" Nothing [],
            mkEntryK KindModule "mod-b" (Just "repo-x") ["haskell"]
          ]

    it "keeps all kinds when kinds is empty" $ do
      length (applyFilters (ListFilter Nothing Nothing []) mixed) `shouldBe` 5

    it "keeps only modules with --modules" $ do
      let result = applyFilters (ListFilter Nothing Nothing [KindModule]) mixed
      map (^. #name) result `shouldBe` ["mod-a", "mod-b"]

    it "keeps only recipes with --recipes" $ do
      let result = applyFilters (ListFilter Nothing Nothing [KindRecipe]) mixed
      map (^. #name) result `shouldBe` ["rec-a"]

    it "keeps only blueprints with --blueprints" $ do
      let result = applyFilters (ListFilter Nothing Nothing [KindBlueprint]) mixed
      map (^. #name) result `shouldBe` ["bp-a"]

    it "keeps only prompts with --prompts" $ do
      let result = applyFilters (ListFilter Nothing Nothing [KindPrompt]) mixed
      map (^. #name) result `shouldBe` ["prompt-a"]

    it "keeps only judgements with --judgements" $ do
      let withJudgement = mixed <> [mkEntryK KindJudgement "guard" Nothing []]
          result = applyFilters (ListFilter Nothing Nothing [KindJudgement]) withJudgement
      map (^. #name) result `shouldBe` ["guard"]

    it "unions kinds when several flags are given" $ do
      let result = applyFilters (ListFilter Nothing Nothing [KindModule, KindRecipe]) mixed
      map (^. #name) result `shouldBe` ["mod-a", "rec-a", "mod-b"]

    it "combines kind and repo with AND" $ do
      let result = applyFilters (ListFilter (Just "repo-x") Nothing [KindModule]) mixed
      map (^. #name) result `shouldBe` ["mod-b"]

    it "returns empty when kind matches nothing in the set" $ do
      let onlyRecipes = filter (\e -> e ^. #kind == KindRecipe) mixed
          result = applyFilters (ListFilter Nothing Nothing [KindBlueprint]) onlyRecipes
      result `shouldBe` []

  describe "formatListOutputEntries (count noun)" $ do
    let noFilterF = ListFilter Nothing Nothing []

    it "uses the kind noun when all shown entries share one kind" $ do
      let entries = [mkEntryK KindBlueprint "bp-a" Nothing [], mkEntryK KindBlueprint "bp-b" Nothing []]
          result = formatListOutputEntries False BoundedDescriptions entries ["p1"] noFilterF
      T.isInfixOf "2 blueprints found" result `shouldBe` True

    it "uses the singular kind noun for one entry" $ do
      let entries = [mkEntryK KindRecipe "rec-a" Nothing []]
          result = formatListOutputEntries False BoundedDescriptions entries ["p1"] noFilterF
      T.isInfixOf "1 recipe found" result `shouldBe` True

    it "uses the prompt noun when all shown entries are prompts" $ do
      let entries = [mkEntryK KindPrompt "review" Nothing [], mkEntryK KindPrompt "explain" Nothing []]
          result = formatListOutputEntries False BoundedDescriptions entries ["p1"] noFilterF
      T.isInfixOf "2 prompts found" result `shouldBe` True

    it "lists judgements under their own section with the judgement noun" $ do
      let entries = [mkEntryK KindJudgement "guard" Nothing []]
          result = formatListOutputEntries False BoundedDescriptions entries ["p1"] noFilterF
      T.isInfixOf "Judgements (1)" result `shouldBe` True
      T.isInfixOf "  guard" result `shouldBe` True
      T.isInfixOf "1 judgement found" result `shouldBe` True

    it "names judgements in the empty message when filtered to judgements" $ do
      let result = formatListOutputEntries False BoundedDescriptions [] ["p1"] (ListFilter Nothing Nothing [KindJudgement])
      T.isInfixOf "No judgements found." result `shouldBe` True
      T.isInfixOf "kind=judgement" result `shouldBe` True

    it "falls back to the neutral noun for a mix of kinds" $ do
      let entries = [mkEntryK KindModule "mod-a" Nothing [], mkEntryK KindRecipe "rec-a" Nothing []]
          result = formatListOutputEntries False BoundedDescriptions entries ["p1"] noFilterF
      T.isInfixOf "2 items found" result `shouldBe` True

    it "names the kind in the empty message when filtered to one kind" $ do
      let result = formatListOutputEntries False BoundedDescriptions [] ["p1"] (ListFilter Nothing Nothing [KindBlueprint])
      T.isInfixOf "No blueprints found." result `shouldBe` True

    it "names prompts in the empty message when filtered to prompts" $ do
      let result = formatListOutputEntries False BoundedDescriptions [] ["p1"] (ListFilter Nothing Nothing [KindPrompt])
      T.isInfixOf "No prompts found." result `shouldBe` True

    it "uses the neutral noun in the empty message with no kind filter" $ do
      let result = formatListOutputEntries False BoundedDescriptions [] ["p1"] noFilterF
      T.isInfixOf "No items found." result `shouldBe` True

  describe "runnableToEntryWithOrigin (blueprint)" $ do
    it "leaves the kind out of a blueprint's source label" $ do
      let dr =
            DiscoveredRunnable
              { name = "demo",
                description = Just "A new seihou blueprint",
                kind = KindBlueprint,
                source = SourceProject,
                dir = "/fake/demo",
                isError = False,
                error = Nothing
              }
          entry = runnableToEntryWithOrigin Map.empty dr
      (entry ^. #source) `shouldBe` "project"
      (entry ^. #name) `shouldBe` "demo"
      (entry ^. #isError) `shouldBe` False
      (entry ^. #kind) `shouldBe` KindBlueprint

  describe "runnableToEntryWithOrigin (prompt)" $ do
    it "leaves the kind out of a prompt's source label" $ do
      let dr =
            DiscoveredRunnable
              { name = "review",
                description = Just "Review current changes",
                kind = KindPrompt,
                source = SourceProject,
                dir = "/fake/review",
                isError = False,
                error = Nothing
              }
          entry = runnableToEntryWithOrigin Map.empty dr
      (entry ^. #source) `shouldBe` "project"
      (entry ^. #name) `shouldBe` "review"
      (entry ^. #isError) `shouldBe` False
      (entry ^. #kind) `shouldBe` KindPrompt

  describe "formatListOutputEntries (layout)" $ do
    it "groups by kind, sorts by name, and bounds each description to one line" $ do
      let result = formatListOutputEntries False BoundedDescriptions scrambledFixture ["p1", "p2", "p3"] noFilter
      result `shouldBe` T.unlines goldenBounded

    it "keeps every line within 76 columns however long a description is" $ do
      let long = mkEntryK KindRecipe "long-desc" Nothing [] & #desc .~ T.replicate 100 "verbose prose "
          result = formatListOutputEntries False BoundedDescriptions [long] ["p1"] noFilter
      T.lines result `shouldSatisfy` all ((<= 76) . T.length)
      T.lines result `shouldSatisfy` any (T.isSuffixOf "…")

    it "leaves no trailing spaces on any line" $ do
      let result = formatListOutputEntries False BoundedDescriptions scrambledFixture ["p1", "p2", "p3"] noFilter
      T.lines result `shouldSatisfy` all (\l -> T.stripEnd l == l)

    it "omits sections for kinds that have no entries" $ do
      let entries = [mkEntryK KindRecipe "rec-a" Nothing []]
          result = formatListOutputEntries False BoundedDescriptions entries ["p1"] (ListFilter Nothing Nothing [KindRecipe])
      T.lines result
        `shouldBe` [ "Recipes (1)",
                     "",
                     "  rec-a  installed",
                     "    desc",
                     "",
                     "1 recipe found (1 sources searched) [filtered: kind=recipe]"
                   ]

  describe "formatListOutputEntries (--full)" $ do
    it "word-wraps the whole description under a four-space indent" $ do
      let exec = filter (\e -> e ^. #name == "exec-plan") scrambledFixture
          result = formatListOutputEntries False FullDescriptions exec ["p1"] noFilter
      take 4 (drop 2 (T.lines result))
        `shouldBe` [ "  exec-plan  installed: agent-seihou v0.14.0",
                     "    Claude skill for creating, implementing, and managing execution plans",
                     "    (ExecPlans) — self-contained design documents that guide implementation",
                     "    of features and system changes."
                   ]

    it "separates entries with a blank line and keeps paragraph breaks unpadded" $ do
      let a = mkEntryK KindModule "mod-a" Nothing [] & #desc .~ "First paragraph.\n\nSecond paragraph."
          b = mkEntryK KindModule "mod-b" Nothing []
          result = formatListOutputEntries False FullDescriptions [b, a] ["p1"] noFilter
      T.lines result
        `shouldBe` [ "Modules (2)",
                     "",
                     "  mod-a  installed",
                     "    First paragraph.",
                     "",
                     "    Second paragraph.",
                     "",
                     "  mod-b  installed",
                     "    desc",
                     "",
                     "2 modules found (1 sources searched)"
                   ]

    it "shows text the bounded view would cut" $ do
      let result = formatListOutputEntries False FullDescriptions scrambledFixture ["p1"] noFilter
      T.isInfixOf "discovery directories." result `shouldBe` True
      T.isInfixOf "…" result `shouldBe` False

-- | Four entries in a scrambled order, to prove the grouping and sorting.
scrambledFixture :: [Entry]
scrambledFixture =
  [ fixtureEntry
      KindBlueprint
      "exec-plan"
      "installed: agent-seihou v0.14.0"
      "Claude skill for creating, implementing, and managing execution plans (ExecPlans) — self-contained design documents that guide implementation of features and system changes.",
    fixtureEntry
      KindModule
      "upgrade-haskell-nix2container"
      "installed: seihou-modules v0.2.0"
      "Migrate existing nix-haskell-flake service images from dockerTools to pinned nix2container, preserving configuration, runtime files, inputs and Seihou ownership",
    fixtureEntry
      KindRecipe
      "haskell-cli-app"
      "installed: seihou-modules v0.1.0"
      "Bootstrap a tested two-package Haskell CLI app (reusable core library + CLI executable) under GHC2024, with GHC 9.12.4 as the HLS-backed default and GHC 9.14.1 as a secondary build shell.",
    fixtureEntry
      KindModule
      "agent-gitignore"
      "installed: seihou-modules v0.1.0"
      "Ensure .claude/, .codex/, .agents/, and CLAUDE.local.md are in .gitignore. Shared base module for skill modules that publish into all three discovery directories."
  ]

fixtureEntry :: RunnableKind -> T.Text -> T.Text -> T.Text -> Entry
fixtureEntry kind name source desc =
  Entry
    { name = name,
      desc = desc,
      source = source,
      isError = False,
      repoName = Nothing,
      tags = [],
      kind = kind
    }

-- | The expected bounded rendering of 'scrambledFixture', exactly as the
-- ExecPlan's Validation and Acceptance section shows it.
goldenBounded :: [T.Text]
goldenBounded =
  [ "Modules (2)",
    "",
    "  agent-gitignore                installed: seihou-modules v0.1.0",
    "    Ensure .claude/, .codex/, .agents/, and CLAUDE.local.md are in .gitigno…",
    "  upgrade-haskell-nix2container  installed: seihou-modules v0.2.0",
    "    Migrate existing nix-haskell-flake service images from dockerTools to p…",
    "",
    "Recipes (1)",
    "",
    "  haskell-cli-app                installed: seihou-modules v0.1.0",
    "    Bootstrap a tested two-package Haskell CLI app (reusable core library +…",
    "",
    "Blueprints (1)",
    "",
    "  exec-plan                      installed: agent-seihou v0.14.0",
    "    Claude skill for creating, implementing, and managing execution plans (…",
    "",
    "4 items found (3 sources searched)"
  ]
