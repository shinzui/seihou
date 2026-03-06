module Seihou.Interaction.PromptSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Effectful
import Seihou.Composition.Resolve (resolveWithPrompts)
import Seihou.Core.Types
import Seihou.Effect.ConsolePure
import Seihou.Interaction.Prompt (promptForVar, runPrompts)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Interaction.Prompt" spec

-- | Helper to create a minimal module.
mkModule :: ModuleName -> [ModuleName] -> [VarDecl] -> [VarExport] -> [Prompt] -> Module
mkModule name deps vars exports prompts =
  Module
    { name = name,
      description = Nothing,
      vars = vars,
      exports = exports,
      prompts = prompts,
      steps = [],
      commands = [],
      dependencies = deps
    }

-- | Helper to create a text variable declaration.
mkTextVar :: VarName -> Maybe VarValue -> Bool -> VarDecl
mkTextVar name defVal required =
  VarDecl
    { name = name,
      type_ = VTText,
      default_ = defVal,
      description = Nothing,
      required = required,
      validation = Nothing
    }

-- | Helper to create a bool variable declaration.
mkBoolVar :: VarName -> Maybe VarValue -> Bool -> VarDecl
mkBoolVar name defVal required =
  VarDecl
    { name = name,
      type_ = VTBool,
      default_ = defVal,
      description = Nothing,
      required = required,
      validation = Nothing
    }

-- | Helper to create a simple prompt for a variable.
mkPrompt :: VarName -> Text -> Prompt
mkPrompt var text =
  Prompt
    { var = var,
      text = text,
      condition = Nothing,
      choices = Nothing
    }

-- | Helper to create a prompt with choices.
mkChoicePrompt :: VarName -> Text -> [Text] -> Prompt
mkChoicePrompt var text choices =
  Prompt
    { var = var,
      text = text,
      condition = Nothing,
      choices = Just choices
    }

-- | Helper to create a prompt with a when condition.
mkConditionalPrompt :: VarName -> Text -> Expr -> Prompt
mkConditionalPrompt var text expr =
  Prompt
    { var = var,
      text = text,
      condition = Just expr,
      choices = Nothing
    }

-- | Helper to create an export without alias.
mkExport :: VarName -> VarExport
mkExport name = VarExport {var = name, alias = Nothing}

spec :: Spec
spec = do
  describe "runPrompts" $ do
    it "fills a required text variable with FromPrompt source" $ do
      let decl = mkTextVar "project.name" Nothing True
          prompt = mkPrompt "project.name" "What is the project name?"
          bindings = Map.empty
      (result, st) <-
        runEff $
          runConsolePure ["my-app"] $
            runPrompts [prompt] [decl] bindings
      Map.member "project.name" result `shouldBe` True
      let rv = result Map.! "project.name"
      rv.value `shouldBe` VText "my-app"
      rv.source `shouldBe` FromPrompt
      -- The prompt text should have been output
      st.consoleOutputs `shouldSatisfy` any (== "What is the project name?")

    it "fills a prompt with choices via selection number" $ do
      let decl = mkTextVar "license" Nothing True
          prompt = mkChoicePrompt "license" "Choose a license:" ["MIT", "Apache-2.0", "BSD-3-Clause"]
          bindings = Map.empty
      (result, _st) <-
        runEff $
          runConsolePure ["2"] $
            runPrompts [prompt] [decl] bindings
      Map.member "license" result `shouldBe` True
      (result Map.! "license").value `shouldBe` VText "Apache-2.0"
      (result Map.! "license").source `shouldBe` FromPrompt

    it "skips a prompt whose when condition evaluates to False" $ do
      let decl = mkTextVar "extra.flag" Nothing True
          -- Condition: IsSet license — but license is not in bindings
          prompt = mkConditionalPrompt "extra.flag" "Extra flag?" (ExprIsSet "license")
          bindings = Map.empty
      (result, st) <-
        runEff $
          runConsolePure ["some-value"] $
            runPrompts [prompt] [decl] bindings
      -- Prompt was skipped, so the variable is not resolved
      Map.member "extra.flag" result `shouldBe` False
      -- No prompt text was output
      st.consoleOutputs `shouldSatisfy` all (/= "Extra flag?")

    it "shows a prompt whose when condition evaluates to True" $ do
      let decl = mkTextVar "extra.flag" Nothing True
          -- Condition: IsSet license — license IS in bindings
          prompt = mkConditionalPrompt "extra.flag" "Extra flag?" (ExprIsSet "license")
          bindings = Map.singleton "license" (VText "MIT")
      (result, _st) <-
        runEff $
          runConsolePure ["some-value"] $
            runPrompts [prompt] [decl] bindings
      Map.member "extra.flag" result `shouldBe` True
      (result Map.! "extra.flag").value `shouldBe` VText "some-value"

    it "skips a prompt for a variable not in the unresolved set" $ do
      let decl = mkTextVar "project.name" Nothing True
          -- Prompt references a different variable
          prompt = mkPrompt "other.var" "Other?"
          bindings = Map.empty
      (result, st) <-
        runEff $
          runConsolePure ["anything"] $
            runPrompts [prompt] [decl] bindings
      Map.null result `shouldBe` True
      st.consoleOutputs `shouldSatisfy` all (/= "Other?")

  describe "default value display" $ do
    it "shows default value in prompt text and accepts Enter" $ do
      let decl = mkTextVar "project.version" (Just (VText "0.1.0.0")) True
          prompt = mkPrompt "project.version" "Project version"
      (result, st) <-
        runEff $
          runConsolePure [""] $
            promptForVar prompt decl Map.empty
      case result of
        Left err -> expectationFailure $ "Expected Right, got: " ++ show err
        Right rv -> do
          rv.value `shouldBe` VText "0.1.0.0"
          rv.source `shouldBe` FromPrompt
      -- Prompt text should include the default in brackets
      st.consoleOutputs `shouldSatisfy` any (== "Project version [0.1.0.0]:")

    it "accepts user input over default when provided" $ do
      let decl = mkTextVar "project.version" (Just (VText "0.1.0.0")) True
          prompt = mkPrompt "project.version" "Project version"
      (result, st) <-
        runEff $
          runConsolePure ["1.0.0"] $
            promptForVar prompt decl Map.empty
      case result of
        Left err -> expectationFailure $ "Expected Right, got: " ++ show err
        Right rv ->
          rv.value `shouldBe` VText "1.0.0"
      st.consoleOutputs `shouldSatisfy` any (== "Project version [0.1.0.0]:")

    it "shows [skip] for optional variable without default" $ do
      let decl = mkTextVar "license" Nothing False
          prompt = mkPrompt "license" "License"
      (_result, st) <-
        runEff $
          runConsolePure [""] $
            promptForVar prompt decl Map.empty
      st.consoleOutputs `shouldSatisfy` any (== "License [skip]:")

    it "shows bool default as yes/no" $ do
      let decl = mkBoolVar "enable.ci" (Just (VBool True)) False
          prompt = mkPrompt "enable.ci" "Enable CI?"
      (result, st) <-
        runEff $
          runConsolePure [""] $
            promptForVar prompt decl Map.empty
      case result of
        Left err -> expectationFailure $ "Expected Right, got: " ++ show err
        Right rv ->
          rv.value `shouldBe` VBool True
      st.consoleOutputs `shouldSatisfy` any (== "Enable CI? [yes]:")

  describe "promptForVar" $ do
    it "coerces boolean input correctly" $ do
      let decl = mkBoolVar "use.ci" Nothing True
          prompt = mkPrompt "use.ci" "Enable CI?"
      (result, _st) <-
        runEff $
          runConsolePure ["yes"] $
            promptForVar prompt decl Map.empty
      case result of
        Left err -> expectationFailure $ "Expected Right, got: " ++ show err
        Right rv -> do
          rv.value `shouldBe` VBool True
          rv.source `shouldBe` FromPrompt

    it "coerces 'no' to False for boolean variable" $ do
      let decl = mkBoolVar "use.ci" Nothing True
          prompt = mkPrompt "use.ci" "Enable CI?"
      (result, _st) <-
        runEff $
          runConsolePure ["no"] $
            promptForVar prompt decl Map.empty
      case result of
        Left err -> expectationFailure $ "Expected Right, got: " ++ show err
        Right rv ->
          rv.value `shouldBe` VBool False

    it "retries on empty input then succeeds" $ do
      let decl = mkTextVar "project.name" Nothing True
          prompt = mkPrompt "project.name" "Project name?"
      (result, st) <-
        runEff $
          runConsolePure ["", "my-app"] $
            promptForVar prompt decl Map.empty
      case result of
        Left err -> expectationFailure $ "Expected Right, got: " ++ show err
        Right rv ->
          rv.value `shouldBe` VText "my-app"
      -- Should have output a retry message
      st.consoleOutputs `shouldSatisfy` any (== "Value cannot be empty. Please try again.")

    it "fails after exhausting retries on empty input" $ do
      let decl = mkTextVar "project.name" Nothing True
          prompt = mkPrompt "project.name" "Project name?"
      (result, _st) <-
        runEff $
          runConsolePure ["", "", ""] $
            promptForVar prompt decl Map.empty
      case result of
        Left (MissingRequiredVar _) -> pure ()
        Left err -> expectationFailure $ "Expected MissingRequiredVar, got: " ++ show err
        Right _ -> expectationFailure "Expected Left, got Right"

  describe "resolveWithPrompts" $ do
    it "prompts for missing required variables in interactive mode" $ do
      let m =
            mkModule
              "base"
              []
              [mkTextVar "project.name" Nothing True]
              []
              [mkPrompt "project.name" "What is the project name?"]
          modules = [(m, "/fake/base")]
      (result, st) <-
        runEff $
          runConsolePure ["my-app"] $
            resolveWithPrompts modules Map.empty Map.empty "" Map.empty Map.empty Map.empty
      case result of
        Left errs -> expectationFailure $ "Expected Right, got: " ++ show errs
        Right resolved -> do
          let baseVars = resolved Map.! "base"
          (baseVars Map.! "project.name").value `shouldBe` VText "my-app"
          (baseVars Map.! "project.name").source `shouldBe` FromPrompt
      st.consoleOutputs `shouldSatisfy` any (== "What is the project name?")

    it "does not prompt when all variables are provided via CLI" $ do
      let m =
            mkModule
              "base"
              []
              [mkTextVar "project.name" Nothing True]
              []
              [mkPrompt "project.name" "What is the project name?"]
          modules = [(m, "/fake/base")]
          cliOverrides = Map.singleton "project.name" "from-cli"
      (result, st) <-
        runEff $
          runConsolePure [] $
            resolveWithPrompts modules cliOverrides Map.empty "" Map.empty Map.empty Map.empty
      case result of
        Left errs -> expectationFailure $ "Expected Right, got: " ++ show errs
        Right resolved -> do
          let baseVars = resolved Map.! "base"
          (baseVars Map.! "project.name").value `shouldBe` VText "from-cli"
          (baseVars Map.! "project.name").source `shouldBe` FromCLI
      -- No prompts should have been displayed
      st.consoleOutputs `shouldSatisfy` all (/= "What is the project name?")

    it "skips prompts and errors in non-interactive mode" $ do
      let m =
            mkModule
              "base"
              []
              [mkTextVar "project.name" Nothing True]
              []
              [mkPrompt "project.name" "What is the project name?"]
          modules = [(m, "/fake/base")]
      (result, st) <-
        runEff $
          runConsolePureNonInteractive $
            resolveWithPrompts modules Map.empty Map.empty "" Map.empty Map.empty Map.empty
      case result of
        Left errs -> case errs of
          [MissingRequiredVar name] -> name `shouldBe` "project.name"
          [other] -> expectationFailure $ "Expected MissingRequiredVar, got: " ++ show other
          _ -> expectationFailure $ "Expected exactly 1 error, got: " ++ show (length errs)
        Right _ -> expectationFailure "Expected Left (errors), got Right"
      -- No prompts should have been displayed
      st.consoleOutputs `shouldSatisfy` all (/= "What is the project name?")

    it "flows prompted value from first module to second via exports" $ do
      let base =
            mkModule
              "base"
              []
              [mkTextVar "project.name" Nothing True]
              [mkExport "project.name"]
              [mkPrompt "project.name" "What is the project name?"]
          app =
            mkModule
              "app"
              ["base"]
              [mkTextVar "project.name" Nothing True]
              []
              []
          modules = [(base, "/fake/base"), (app, "/fake/app")]
      (result, st) <-
        runEff $
          runConsolePure ["my-app"] $
            resolveWithPrompts modules Map.empty Map.empty "" Map.empty Map.empty Map.empty
      case result of
        Left errs -> expectationFailure $ "Expected Right, got: " ++ show errs
        Right resolved -> do
          -- Base module was prompted
          let baseVars = resolved Map.! "base"
          (baseVars Map.! "project.name").value `shouldBe` VText "my-app"
          (baseVars Map.! "project.name").source `shouldBe` FromPrompt
          -- App module received the value via export (no additional prompt needed)
          let appVars = resolved Map.! "app"
          (appVars Map.! "project.name").value `shouldBe` VText "my-app"
      -- Only one prompt should have fired (for base), not two
      let promptOutputs = filter (== "What is the project name?") (st.consoleOutputs)
      length promptOutputs `shouldBe` 1
