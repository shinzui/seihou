module Seihou.CLI.ListSpec (tests) where

import Data.Text qualified as T
import Seihou.CLI.List (formatListOutput)
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
            { moduleName = ModuleName (T.pack name),
              moduleDescription = Just (T.pack desc),
              moduleVars = [],
              moduleExports = [],
              modulePrompts = [],
              moduleSteps = [],
              moduleCommands = [],
              moduleDependencies = []
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
      T.isInfixOf "Available modules:" result `shouldBe` True

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
