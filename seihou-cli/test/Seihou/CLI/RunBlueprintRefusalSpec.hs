module Seihou.CLI.RunBlueprintRefusalSpec (tests) where

import Data.Text qualified as T
import Seihou.CLI.Shared (formatBlueprintRefusal)
import Seihou.Core.Types (ModuleName (..))
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.CLI.RunBlueprintRefusal" spec

spec :: Spec
spec = do
  describe "formatBlueprintRefusal" $ do
    it "names the blueprint that was attempted" $ do
      let msg = formatBlueprintRefusal (ModuleName "my-blueprint")
      T.isInfixOf "'my-blueprint' is a blueprint" msg `shouldBe` True

    it "describes that blueprints aren't modules or recipes" $ do
      let msg = formatBlueprintRefusal (ModuleName "x")
      T.isInfixOf "not a module or recipe" msg `shouldBe` True

    it "tells the user how to invoke the blueprint via the agent runner" $ do
      let msg = formatBlueprintRefusal (ModuleName "payments-service")
      T.isInfixOf "seihou agent run payments-service" msg `shouldBe` True

    it "is rendered as a single multi-line string (one '[error]' prefix at runtime)" $ do
      -- The Logger interpreter prefixes each logError call with
      -- "[error] ". The refusal body must therefore be emitted as a
      -- single string with newlines so only the first line carries the
      -- prefix. Verify the message contains newline separators rather
      -- than being a list of independent strings.
      let msg = formatBlueprintRefusal (ModuleName "a")
          lns = T.splitOn "\n" msg
      length lns `shouldBe` 3
