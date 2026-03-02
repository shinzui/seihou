module Seihou.Engine.TemplateSpec (tests) where

import Data.Map.Strict qualified as Map
import Seihou.Core.Types
import Seihou.Engine.Template
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Engine.Template" spec

spec :: Spec
spec = do
  describe "valueToText" $ do
    it "converts VText" $ do
      valueToText (VText "hello") `shouldBe` "hello"

    it "converts VBool True" $ do
      valueToText (VBool True) `shouldBe` "true"

    it "converts VBool False" $ do
      valueToText (VBool False) `shouldBe` "false"

    it "converts VInt" $ do
      valueToText (VInt 42) `shouldBe` "42"

    it "converts VList" $ do
      valueToText (VList [VText "a", VText "b", VText "c"]) `shouldBe` "a,b,c"

  describe "renderTemplate" $ do
    it "substitutes a simple placeholder" $ do
      let vars = Map.fromList [("name", VText "world")]
      renderTemplate "Hello, {{name}}!" vars `shouldBe` Right "Hello, world!"

    it "substitutes multiple placeholders on one line" $ do
      let vars = Map.fromList [("first", VText "Jane"), ("last", VText "Doe")]
      renderTemplate "Name: {{first}} {{last}}" vars
        `shouldBe` Right "Name: Jane Doe"

    it "substitutes placeholders across multiple lines" $ do
      let vars = Map.fromList [("project.name", VText "my-app"), ("project.version", VText "0.1.0.0")]
      renderTemplate "# {{project.name}}\nVersion: {{project.version}}" vars
        `shouldBe` Right "# my-app\nVersion: 0.1.0.0"

    it "handles the README fixture pattern" $ do
      let vars = Map.fromList [("project.name", VText "my-app"), ("project.version", VText "0.1.0.0")]
      renderTemplate "# {{project.name}}\n\nVersion: {{project.version}}\n" vars
        `shouldBe` Right "# my-app\n\nVersion: 0.1.0.0\n"

    it "passes through text with no placeholders" $ do
      let vars = Map.empty
      renderTemplate "No placeholders here." vars
        `shouldBe` Right "No placeholders here."

    it "handles empty template" $ do
      let vars = Map.empty
      renderTemplate "" vars `shouldBe` Right ""

    it "handles escape sequence" $ do
      let vars = Map.empty
      renderTemplate "Use \\{{var}} for placeholders" vars
        `shouldBe` Right "Use {{var}} for placeholders"

    it "handles escape sequence with real placeholder" $ do
      let vars = Map.fromList [("name", VText "world")]
      renderTemplate "Literal \\{{not.a.var}} and {{name}}" vars
        `shouldBe` Right "Literal {{not.a.var}} and world"

    it "coerces VBool to text in placeholder" $ do
      let vars = Map.fromList [("enabled", VBool True)]
      renderTemplate "Enabled: {{enabled}}" vars
        `shouldBe` Right "Enabled: true"

    it "coerces VInt to text in placeholder" $ do
      let vars = Map.fromList [("count", VInt 42)]
      renderTemplate "Count: {{count}}" vars
        `shouldBe` Right "Count: 42"

    it "coerces VList to text in placeholder" $ do
      let vars = Map.fromList [("items", VList [VText "a", VText "b"])]
      renderTemplate "Items: {{items}}" vars
        `shouldBe` Right "Items: a,b"

    it "reports unresolved placeholder with correct line number" $ do
      let vars = Map.empty
      case renderTemplate "line one\n{{missing}}\nline three" vars of
        Left errs -> do
          length errs `shouldBe` 1
          case errs of
            (UnresolvedPlaceholder name lineNum : _) -> do
              name `shouldBe` "missing"
              lineNum `shouldBe` 2
            other -> expectationFailure ("Unexpected error: " <> show other)
        Right _ -> expectationFailure "Expected Left"

    it "reports multiple unresolved placeholders" $ do
      let vars = Map.empty
      case renderTemplate "{{a}}\n{{b}}" vars of
        Left errs -> length errs `shouldBe` 2
        Right _ -> expectationFailure "Expected Left"

    it "strips whitespace around placeholder name" $ do
      let vars = Map.fromList [("name", VText "world")]
      renderTemplate "{{ name }}" vars `shouldBe` Right "world"

  describe "renderDestPath" $ do
    it "expands placeholder in destination path" $ do
      let vars = Map.fromList [("project.name", VText "my-app")]
      renderDestPath "{{project.name}}.cabal" vars
        `shouldBe` Right "my-app.cabal"

    it "handles path with subdirectory and placeholder" $ do
      let vars = Map.fromList [("project.name", VText "my-app")]
      renderDestPath "src/{{project.name}}/Main.hs" vars
        `shouldBe` Right "src/my-app/Main.hs"

    it "passes through path with no placeholders" $ do
      let vars = Map.empty
      renderDestPath "src/Lib.hs" vars `shouldBe` Right "src/Lib.hs"
