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

  describe "renderCommand" $ do
    it "substitutes variables in a command string" $ do
      let vars = Map.fromList [("project.name", VText "my-app")]
      renderCommand "echo {{project.name}}" vars
        `shouldBe` Right "echo my-app"

    it "substitutes multiple placeholders" $ do
      let vars = Map.fromList [("name", VText "app"), ("ver", VText "1.0")]
      renderCommand "echo {{name}}-{{ver}}" vars
        `shouldBe` Right "echo app-1.0"

    it "handles escape sequence" $ do
      let vars = Map.empty
      renderCommand "echo \\{{literal}}" vars
        `shouldBe` Right "echo {{literal}}"

    it "reports unresolved placeholder" $ do
      let vars = Map.empty
      case renderCommand "echo {{missing}}" vars of
        Left errs -> length errs `shouldBe` 1
        Right _ -> expectationFailure "Expected Left"

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

  describe "renderTemplateText" $ do
    it "behaves like renderTemplate on templates with no blocks" $ do
      let vars = Map.fromList [("project.name", VText "my-app")]
          tpl = "# {{project.name}}\nVersion: 0.1.0.0\n"
      renderTemplateText tpl vars
        `shouldBe` renderTemplate tpl vars

    it "selects the then-branch when the if expression is true" $ do
      let vars = Map.fromList [("x", VBool True)]
      renderTemplateText "{{#if Eq x true}}A{{/if}}" vars
        `shouldBe` Right "A"

    it "excludes the then-branch when the if expression is false" $ do
      let vars = Map.fromList [("x", VBool False)]
      renderTemplateText "{{#if Eq x true}}A{{/if}}" vars
        `shouldBe` Right ""

    it "selects the then-branch of an if/else when the variable is set" $ do
      let vars = Map.fromList [("foo", VText "bar")]
      renderTemplateText "{{#if IsSet foo}}yes{{#else}}no{{/if}}" vars
        `shouldBe` Right "yes"

    it "selects the else-branch of an if/else when the variable is unset" $ do
      let vars = Map.empty
      renderTemplateText "{{#if IsSet foo}}yes{{#else}}no{{/if}}" vars
        `shouldBe` Right "no"

    it "handles two-level nesting with both branches taken" $ do
      let vars = Map.fromList [("a", VBool True), ("b", VBool True)]
      renderTemplateText
        "{{#if Eq a true}}outer{{#if Eq b true}}inner{{/if}}outer2{{/if}}"
        vars
        `shouldBe` Right "outerinnerouter2"

    it "handles three-level nesting" $ do
      let vars = Map.fromList [("a", VBool True), ("b", VBool True), ("c", VBool True)]
      renderTemplateText
        "{{#if Eq a true}}{{#if Eq b true}}{{#if Eq c true}}deep{{/if}}{{/if}}{{/if}}"
        vars
        `shouldBe` Right "deep"

    it "reports UnterminatedIf with the opener's source line" $ do
      let tpl = "line one\nline two\n{{#if Eq x true}}never closed\nline four\n"
          vars = Map.fromList [("x", VBool True)]
      case renderTemplateText tpl vars of
        Right _ -> expectationFailure "expected UnterminatedIf"
        Left [UnterminatedIf lineNum] -> lineNum `shouldBe` 3
        Left other -> expectationFailure ("expected [UnterminatedIf 3], got " <> show other)

    it "reports orphan {{/if}} at top level" $ do
      let tpl = "a\nb\n{{/if}}\n"
          vars = Map.empty
      case renderTemplateText tpl vars of
        Right _ -> expectationFailure "expected OrphanBlockToken"
        Left [OrphanBlockToken tok lineNum] -> do
          tok `shouldBe` "{{/if}}"
          lineNum `shouldBe` 3
        Left other ->
          expectationFailure ("expected [OrphanBlockToken \"{{/if}}\" 3], got " <> show other)

    it "reports orphan {{#else}} at top level" $ do
      let tpl = "a\n{{#else}}\n"
          vars = Map.empty
      case renderTemplateText tpl vars of
        Right _ -> expectationFailure "expected OrphanBlockToken"
        Left [OrphanBlockToken tok lineNum] -> do
          tok `shouldBe` "{{#else}}"
          lineNum `shouldBe` 2
        Left other ->
          expectationFailure ("expected [OrphanBlockToken \"{{#else}}\" 2], got " <> show other)

    it "reports MalformedIfExpression with the opener line and parser error" $ do
      let tpl = "ok\n{{#if &&garbage}}body{{/if}}"
          vars = Map.empty
      case renderTemplateText tpl vars of
        Right _ -> expectationFailure "expected MalformedIfExpression"
        Left [MalformedIfExpression rawExpr lineNum _parserErr] -> do
          rawExpr `shouldBe` "&&garbage"
          lineNum `shouldBe` 2
        Left other ->
          expectationFailure ("expected [MalformedIfExpression …], got " <> show other)

    it "substitutes {{var}} inside the taken branch and surfaces unresolved errors" $ do
      let vars = Map.fromList [("gate", VBool True)]
      case renderTemplateText "{{#if Eq gate true}}hello {{name}}{{/if}}" vars of
        Right _ -> expectationFailure "expected UnresolvedPlaceholder in taken branch"
        Left [UnresolvedPlaceholder (VarName nm) _] -> nm `shouldBe` "name"
        Left other -> expectationFailure ("unexpected errors: " <> show other)

    it "discards untaken branches so their {{var}} errors do not surface" $ do
      let vars = Map.fromList [("gate", VBool False)]
      renderTemplateText "before {{#if Eq gate true}}hello {{missing}}{{/if}}after" vars
        `shouldBe` Right "before after"

    it "evaluates && combinator: both true takes the branch" $ do
      let vars = Map.fromList [("a", VBool True), ("b", VBool True)]
      renderTemplateText "{{#if Eq a true && Eq b true}}Y{{#else}}N{{/if}}" vars
        `shouldBe` Right "Y"

    it "evaluates && combinator: one false drops the branch" $ do
      let vars = Map.fromList [("a", VBool True), ("b", VBool False)]
      renderTemplateText "{{#if Eq a true && Eq b true}}Y{{#else}}N{{/if}}" vars
        `shouldBe` Right "N"

    it "evaluates || combinator: either true takes the branch" $ do
      let vars = Map.fromList [("a", VBool False), ("b", VBool True)]
      renderTemplateText "{{#if Eq a true || Eq b true}}Y{{#else}}N{{/if}}" vars
        `shouldBe` Right "Y"

    it "evaluates ! combinator: negation flips the branch" $ do
      let vars = Map.fromList [("a", VBool False)]
      renderTemplateText "{{#if !Eq a true}}Y{{#else}}N{{/if}}" vars
        `shouldBe` Right "Y"

    it "evaluates a parenthesised expression honouring precedence" $ do
      -- (A || B) && !C — with A=false, B=true, C=false → (true) && true = true
      let vars =
            Map.fromList
              [ ("a", VBool False),
                ("b", VBool True),
                ("c", VBool False)
              ]
      renderTemplateText
        "{{#if (Eq a true || Eq b true) && !Eq c true}}Y{{#else}}N{{/if}}"
        vars
        `shouldBe` Right "Y"

    it "matches outer {{#else}} past a nested {{#else}} inside the then-branch" $ do
      -- The outer if's else is "e"; the inner if (B) has its own else "b2".
      -- splitBranches must skip the inner {{#else}} (it's at depth 1) and
      -- only mark the outer {{#else}} (at depth 0).
      let mkVars a b =
            Map.fromList [("a", VBool a), ("b", VBool b)]
      renderTemplateText
        "{{#if Eq a true}}a1{{#if Eq b true}}b1{{#else}}b2{{/if}}a2{{#else}}e{{/if}}"
        (mkVars True True)
        `shouldBe` Right "a1b1a2"
      renderTemplateText
        "{{#if Eq a true}}a1{{#if Eq b true}}b1{{#else}}b2{{/if}}a2{{#else}}e{{/if}}"
        (mkVars True False)
        `shouldBe` Right "a1b2a2"
      renderTemplateText
        "{{#if Eq a true}}a1{{#if Eq b true}}b1{{#else}}b2{{/if}}a2{{#else}}e{{/if}}"
        (mkVars False True)
        `shouldBe` Right "e"

    it "surfaces an UnterminatedIf from a nested block inside the taken branch" $ do
      -- Outer if takes the then-branch; the inner {{#if B}} has no closing
      -- token before the outer {{/if}}, so splitBranches consumes the outer
      -- {{/if}} as the inner's match and reports the outer opener as
      -- unterminated. The precise error is UnterminatedIf; line is the
      -- opener that actually ran out of closers.
      let vars = Map.fromList [("a", VBool True), ("b", VBool True)]
          tpl = "{{#if Eq a true}}outer{{#if Eq b true}}inner{{/if}}"
      case renderTemplateText tpl vars of
        Right r -> expectationFailure ("expected UnterminatedIf, got " <> show r)
        Left [UnterminatedIf _] -> pure ()
        Left other ->
          expectationFailure ("expected [UnterminatedIf _], got " <> show other)

    it "reports UnterminatedIf on the opener line for a long preamble" $ do
      -- Preamble of ten lines; opener on line 11; no {{/if}} at all.
      let preamble = mconcat (replicate 10 "line\n")
          tpl = preamble <> "{{#if Eq x true}}body\nmore body\n"
          vars = Map.fromList [("x", VBool True)]
      case renderTemplateText tpl vars of
        Right _ -> expectationFailure "expected UnterminatedIf"
        Left [UnterminatedIf lineNum] -> lineNum `shouldBe` 11
        Left other -> expectationFailure ("expected [UnterminatedIf 11], got " <> show other)

    it "handles an empty then-branch" $ do
      let vars = Map.fromList [("x", VBool True)]
      renderTemplateText "a{{#if Eq x true}}{{/if}}b" vars
        `shouldBe` Right "ab"

    it "handles an if/else with both branches empty" $ do
      let vars = Map.fromList [("x", VBool False)]
      renderTemplateText "a{{#if Eq x true}}{{#else}}{{/if}}b" vars
        `shouldBe` Right "ab"

    it "handles multiple top-level blocks back-to-back" $ do
      let vars = Map.fromList [("a", VBool True), ("b", VBool False)]
      renderTemplateText
        "{{#if Eq a true}}A{{/if}}-{{#if Eq b true}}B{{/if}}-{{#if Eq a true}}A2{{/if}}"
        vars
        `shouldBe` Right "A--A2"

    it "interleaves {{var}} and {{#if}} on the same line" $ do
      let vars =
            Map.fromList
              [ ("flag", VBool True),
                ("name", VText "world")
              ]
      renderTemplateText
        "pre {{name}} {{#if Eq flag true}}mid-{{name}}-mid{{/if}} post"
        vars
        `shouldBe` Right "pre world mid-world-mid post"
