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
    { moduleName = name,
      moduleDescription = Nothing,
      moduleVars = vars,
      moduleExports = exports,
      modulePrompts = prompts,
      moduleSteps = [],
      moduleCommands = [],
      moduleDependencies = deps
    }

-- | Helper to create a text variable declaration.
mkTextVar :: VarName -> Maybe VarValue -> Bool -> VarDecl
mkTextVar name defVal required =
  VarDecl
    { varName = name,
      varType = VTText,
      varDefault = defVal,
      varDescription = Nothing,
      varRequired = required,
      varValidation = Nothing
    }

-- | Helper to create a bool variable declaration.
mkBoolVar :: VarName -> Maybe VarValue -> Bool -> VarDecl
mkBoolVar name defVal required =
  VarDecl
    { varName = name,
      varType = VTBool,
      varDefault = defVal,
      varDescription = Nothing,
      varRequired = required,
      varValidation = Nothing
    }

-- | Helper to create a simple prompt for a variable.
mkPrompt :: VarName -> Text -> Prompt
mkPrompt var text =
  Prompt
    { promptVar = var,
      promptText = text,
      promptWhen = Nothing,
      promptChoices = Nothing
    }

-- | Helper to create a prompt with choices.
mkChoicePrompt :: VarName -> Text -> [Text] -> Prompt
mkChoicePrompt var text choices =
  Prompt
    { promptVar = var,
      promptText = text,
      promptWhen = Nothing,
      promptChoices = Just choices
    }

-- | Helper to create a prompt with a when condition.
mkConditionalPrompt :: VarName -> Text -> Expr -> Prompt
mkConditionalPrompt var text expr =
  Prompt
    { promptVar = var,
      promptText = text,
      promptWhen = Just expr,
      promptChoices = Nothing
    }

-- | Helper to create an export without alias.
mkExport :: VarName -> VarExport
mkExport name = VarExport {exportVar = name, exportAs = Nothing}

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
      resolvedValue rv `shouldBe` VText "my-app"
      resolvedSource rv `shouldBe` FromPrompt
      -- The prompt text should have been output
      consoleOutputs st `shouldSatisfy` any (== "What is the project name?")

    it "fills a prompt with choices via selection number" $ do
      let decl = mkTextVar "license" Nothing True
          prompt = mkChoicePrompt "license" "Choose a license:" ["MIT", "Apache-2.0", "BSD-3-Clause"]
          bindings = Map.empty
      (result, _st) <-
        runEff $
          runConsolePure ["2"] $
            runPrompts [prompt] [decl] bindings
      Map.member "license" result `shouldBe` True
      resolvedValue (result Map.! "license") `shouldBe` VText "Apache-2.0"
      resolvedSource (result Map.! "license") `shouldBe` FromPrompt

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
      consoleOutputs st `shouldSatisfy` all (/= "Extra flag?")

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
      resolvedValue (result Map.! "extra.flag") `shouldBe` VText "some-value"

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
      consoleOutputs st `shouldSatisfy` all (/= "Other?")

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
          resolvedValue rv `shouldBe` VBool True
          resolvedSource rv `shouldBe` FromPrompt

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
          resolvedValue rv `shouldBe` VBool False

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
          resolvedValue rv `shouldBe` VText "my-app"
      -- Should have output a retry message
      consoleOutputs st `shouldSatisfy` any (== "Value cannot be empty. Please try again.")

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
            resolveWithPrompts modules Map.empty Map.empty Map.empty Map.empty Map.empty
      case result of
        Left errs -> expectationFailure $ "Expected Right, got: " ++ show errs
        Right resolved -> do
          let baseVars = resolved Map.! "base"
          resolvedValue (baseVars Map.! "project.name") `shouldBe` VText "my-app"
          resolvedSource (baseVars Map.! "project.name") `shouldBe` FromPrompt
      consoleOutputs st `shouldSatisfy` any (== "What is the project name?")

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
            resolveWithPrompts modules cliOverrides Map.empty Map.empty Map.empty Map.empty
      case result of
        Left errs -> expectationFailure $ "Expected Right, got: " ++ show errs
        Right resolved -> do
          let baseVars = resolved Map.! "base"
          resolvedValue (baseVars Map.! "project.name") `shouldBe` VText "from-cli"
          resolvedSource (baseVars Map.! "project.name") `shouldBe` FromCLI
      -- No prompts should have been displayed
      consoleOutputs st `shouldSatisfy` all (/= "What is the project name?")

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
            resolveWithPrompts modules Map.empty Map.empty Map.empty Map.empty Map.empty
      case result of
        Left errs -> case errs of
          [MissingRequiredVar name] -> name `shouldBe` "project.name"
          [other] -> expectationFailure $ "Expected MissingRequiredVar, got: " ++ show other
          _ -> expectationFailure $ "Expected exactly 1 error, got: " ++ show (length errs)
        Right _ -> expectationFailure "Expected Left (errors), got Right"
      -- No prompts should have been displayed
      consoleOutputs st `shouldSatisfy` all (/= "What is the project name?")

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
            resolveWithPrompts modules Map.empty Map.empty Map.empty Map.empty Map.empty
      case result of
        Left errs -> expectationFailure $ "Expected Right, got: " ++ show errs
        Right resolved -> do
          -- Base module was prompted
          let baseVars = resolved Map.! "base"
          resolvedValue (baseVars Map.! "project.name") `shouldBe` VText "my-app"
          resolvedSource (baseVars Map.! "project.name") `shouldBe` FromPrompt
          -- App module received the value via export (no additional prompt needed)
          let appVars = resolved Map.! "app"
          resolvedValue (appVars Map.! "project.name") `shouldBe` VText "my-app"
      -- Only one prompt should have fired (for base), not two
      let promptOutputs = filter (== "What is the project name?") (consoleOutputs st)
      length promptOutputs `shouldBe` 1
