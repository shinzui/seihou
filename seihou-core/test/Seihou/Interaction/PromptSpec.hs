module Seihou.Interaction.PromptSpec (tests) where

import Control.Lens ((&), (.~), (^.))
import Control.Monad (forM_)
import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Effectful
import Seihou.Composition.Instance (primaryInstance)
import Seihou.Composition.Resolve (PromptPermission (..), RecipeInputSpec (..), resolveRecipeWithPrompts, resolveWithPromptPermission, resolveWithPrompts)
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
      version = Nothing,
      description = Nothing,
      vars = vars,
      exports = exports,
      prompts = prompts,
      steps = [],
      commands = [],
      dependencies = map simpleDep deps,
      removal = Nothing,
      migrations = []
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
  describe "recipe input resolution" $ do
    let feature = mkBoolVar "feature" Nothing True
        consumer = mkModule "consumer" [] [mkBoolVar "feature" (Just (VBool False)) False] [] []
        modules = [(primaryInstance "consumer", consumer, "/fixture")]
        resolve permission spec saved cli literals local =
          resolveRecipeWithPrompts permission False spec modules saved cli literals Map.empty "" "" local Map.empty Map.empty Map.empty
        recipe = RecipeInputSpec [feature] [mkPrompt "feature" "Feature?"] Nothing
    it "requires the recipe choice before considering a consumer default" $ do
      let (result, _) = runPureEff $ runConsolePureNonInteractive $ resolve PromptsForbidden recipe Map.empty Map.empty Map.empty Map.empty
      result `shouldBe` Left [MissingRequiredVar "feature"]
    it "broadcasts explicit false and retains prompt source" $ do
      let (result, console) = runPureEff $ runConsolePure ["false"] $ resolve PromptsAllowed recipe Map.empty Map.empty Map.empty Map.empty
      case result of
        Left errs -> expectationFailure (show errs)
        Right (inputs, values) -> do
          (inputs Map.! "feature") ^. #value `shouldBe` VBool False
          (values Map.! primaryInstance "consumer" Map.! "feature") ^. #source `shouldBe` FromPrompt
      console ^. #outputs `shouldBe` ["Feature?"]
    it "keeps CLI above literals, and literals above config" $ do
      let check cli literal local = fst $ runPureEff $ runConsolePureNonInteractive $ resolve PromptsForbidden recipe Map.empty cli literal local
      case check (Map.singleton "feature" "false") (Map.singleton "feature" "true") Map.empty of
        Right (inputs, _) -> (inputs Map.! "feature") ^. #value `shouldBe` VBool False
        Left errs -> expectationFailure (show errs)
      case check Map.empty (Map.singleton "feature" "false") (Map.singleton "feature" "true") of
        Right (inputs, _) -> (inputs Map.! "feature") ^. #value `shouldBe` VBool False
        Left errs -> expectationFailure (show errs)
    it "lets optional conditions see resolved siblings despite another missing input" $ do
      let details = mkTextVar "details" Nothing False
          spec =
            RecipeInputSpec
              [feature, mkBoolVar "other" Nothing True, details]
              [mkPrompt "other" "Other?", mkConditionalPrompt "details" "Details?" (ExprEq "feature" (VBool True))]
              Nothing
          (result, console) = runPureEff $ runConsolePure ["false", "owner"] $ resolve PromptsAllowed spec Map.empty Map.empty Map.empty (Map.singleton "feature" "true")
      case result of
        Right (inputs, _) -> (inputs Map.! "details") ^. #value `shouldBe` VText "owner"
        Left errs -> expectationFailure (show errs)
      console ^. #outputs `shouldBe` ["Other?", "Details? [skip]:"]
    it "rejects exhausted invalid optional answers" $ do
      let optional = feature & #required .~ False
          spec = RecipeInputSpec [optional] [mkPrompt "feature" "Feature?"] Nothing
          (result, _) = runPureEff $ runConsolePure ["bad", "bad", "bad"] $ resolve PromptsAllowed spec Map.empty Map.empty Map.empty Map.empty
      result `shouldBe` Left [CoercionFailed "feature" VTBool "bad"]
    it "adopts historical false through recipe coercion and rejects disagreeing consumers" $ do
      let second = primaryInstance "second"
          both = modules <> [(second, consumer, "/second")]
          check saved cli =
            fst $
              runPureEff $
                runConsolePureNonInteractive $
                  resolveRecipeWithPrompts PromptsForbidden False recipe both saved cli Map.empty Map.empty "" "" Map.empty Map.empty Map.empty Map.empty
          saved a b = Map.fromList [(primaryInstance "consumer", Map.singleton "feature" a), (second, Map.singleton "feature" b)]
      case check (saved "false" "no") Map.empty of
        Right (inputs, _) -> (inputs Map.! "feature") ^. #value `shouldBe` VBool False
        Left errs -> expectationFailure (show errs)
      case check (saved "false" "true") Map.empty of
        Left [ValidationFailed "feature" _] -> pure ()
        other -> expectationFailure (show other)
      case check (saved "false" "true") (Map.singleton "feature" "true") of
        Right (inputs, _) -> (inputs Map.! "feature") ^. #value `shouldBe` VBool True
        Left errs -> expectationFailure (show errs)
    it "validates the broadcast against each consumer declaration" $ do
      let invalid = consumer & #vars .~ [mkTextVar "feature" Nothing True & #validation .~ Just (ValMinLength 10)]
          (result, _) =
            runPureEff $
              runConsolePureNonInteractive $
                resolveRecipeWithPrompts PromptsForbidden False recipe [(primaryInstance "consumer", invalid, "/fixture")] Map.empty (Map.singleton "feature" "true") Map.empty Map.empty "" "" Map.empty Map.empty Map.empty Map.empty
      case result of
        Left [ValidationFailed "feature" _] -> pure ()
        other -> expectationFailure (show other)
    it "replays recorded choices before config and skips accepted optional omissions" $ do
      let optional = mkTextVar "details" Nothing False
          spec = RecipeInputSpec [feature, optional] [mkPrompt "details" "Details?"] (Just (Map.singleton "feature" "false"))
          (result, console) = runPureEff $ runConsolePure [] $ resolve PromptsAllowed spec Map.empty Map.empty Map.empty (Map.singleton "feature" "true")
      case result of
        Right (inputs, _) -> (inputs Map.! "feature") ^. #value `shouldBe` VBool False
        Left errs -> expectationFailure (show errs)
      console ^. #outputs `shouldBe` []

  describe "owner policy" $ do
    let owner = mkTextVar "git.githubOwner" Nothing True
        policy = owner & #validation .~ Just (ValPattern "^topagentnetwork$")
        prompt = mkPrompt "git.githubOwner" "Owner?"
        check source (Left [ValidationFailed "git.githubOwner" msg]) = msg `shouldSatisfy` T.isInfixOf source
        check _ other = expectationFailure (show other)
        resolve recipeDecl memberDecl recorded cli literals global answers confirm =
          fst $
            runPureEff $
              runConsolePure answers $
                resolveRecipeWithPrompts
                  PromptsAllowed
                  confirm
                  (RecipeInputSpec [recipeDecl] [prompt] recorded)
                  [(primaryInstance "consumer", mkModule "consumer" [] [memberDecl] [] [], "/fixture")]
                  Map.empty
                  cli
                  literals
                  Map.empty
                  ""
                  ""
                  Map.empty
                  Map.empty
                  Map.empty
                  global
    forM_ [True, False] $ \recipeOwnsPolicy -> do
      let r = if recipeOwnsPolicy then policy else owner
          m = if recipeOwnsPolicy then owner else policy
      it ("rejects global input with its source; recipe policy=" <> show recipeOwnsPolicy) $
        check "global config" (resolve r m Nothing Map.empty Map.empty (Map.singleton "git.githubOwner" "personal") [] False)
      it ("revalidates history with its source; recipe policy=" <> show recipeOwnsPolicy) $
        check "application" (resolve r m (Just (Map.singleton "git.githubOwner" "personal")) Map.empty Map.empty Map.empty [] False)
      it ("rejects literals with their source; recipe policy=" <> show recipeOwnsPolicy) $
        check "literal recipe binding" (resolve r m Nothing Map.empty (Map.singleton "git.githubOwner" "personal") Map.empty [] False)
      it ("rejects prompt input with its source; recipe policy=" <> show recipeOwnsPolicy) $
        check "prompt" (resolve r m Nothing Map.empty Map.empty Map.empty ["personal", "personal", "personal"] False)
    it "accepts a valid retry after a rejected answer" $ do
      case resolve policy owner Nothing Map.empty Map.empty Map.empty ["personal", "topagentnetwork"] False of
        Right (inputs, _) -> (inputs Map.! "git.githubOwner") ^. #source `shouldBe` FromPrompt
        other -> expectationFailure (show other)
    it "validates numbered prompt choices" $ do
      let (result, _) = runPureEff $ runConsolePure ["1"] $ promptForVar (mkChoicePrompt "git.githubOwner" "Owner?" ["personal", "topagentnetwork"]) policy Map.empty
      case result of
        Left (ValidationFailed _ msg) -> msg `shouldSatisfy` T.isInfixOf "prompt"
        other -> expectationFailure (show other)
    it "validates a changed answer during confirm-defaults" $
      check "prompt" (resolve (policy & #default_ .~ Just (VText "topagentnetwork")) owner Nothing Map.empty Map.empty Map.empty ["personal", "personal", "personal"] True)
    it "validates an accepted prompt default" $ do
      let (result, _) = runPureEff $ runConsolePure [""] $ promptForVar prompt (policy & #default_ .~ Just (VText "personal")) Map.empty
      case result of
        Left (ValidationFailed _ msg) -> msg `shouldSatisfy` T.isInfixOf "prompt"
        other -> expectationFailure (show other)

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
      (rv ^. #value) `shouldBe` VText "my-app"
      (rv ^. #source) `shouldBe` FromPrompt
      -- The prompt text should have been output
      (st ^. #outputs) `shouldSatisfy` any (== "What is the project name?")

    it "fills a prompt with choices via selection number" $ do
      let decl = mkTextVar "license" Nothing True
          prompt = mkChoicePrompt "license" "Choose a license:" ["MIT", "Apache-2.0", "BSD-3-Clause"]
          bindings = Map.empty
      (result, _st) <-
        runEff $
          runConsolePure ["2"] $
            runPrompts [prompt] [decl] bindings
      Map.member "license" result `shouldBe` True
      ((result Map.! "license") ^. #value) `shouldBe` VText "Apache-2.0"
      ((result Map.! "license") ^. #source) `shouldBe` FromPrompt

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
      (st ^. #outputs) `shouldSatisfy` all (/= "Extra flag?")

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
      ((result Map.! "extra.flag") ^. #value) `shouldBe` VText "some-value"

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
      (st ^. #outputs) `shouldSatisfy` all (/= "Other?")

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
          (rv ^. #value) `shouldBe` VText "0.1.0.0"
          (rv ^. #source) `shouldBe` FromPrompt
      -- Prompt text should include the default in brackets
      (st ^. #outputs) `shouldSatisfy` any (== "Project version [0.1.0.0]:")

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
          (rv ^. #value) `shouldBe` VText "1.0.0"
      (st ^. #outputs) `shouldSatisfy` any (== "Project version [0.1.0.0]:")

    it "shows [skip] for optional variable without default" $ do
      let decl = mkTextVar "license" Nothing False
          prompt = mkPrompt "license" "License"
      (_result, st) <-
        runEff $
          runConsolePure [""] $
            promptForVar prompt decl Map.empty
      (st ^. #outputs) `shouldSatisfy` any (== "License [skip]:")

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
          (rv ^. #value) `shouldBe` VBool True
      (st ^. #outputs) `shouldSatisfy` any (== "Enable CI? [yes]:")

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
          (rv ^. #value) `shouldBe` VBool True
          (rv ^. #source) `shouldBe` FromPrompt

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
          (rv ^. #value) `shouldBe` VBool False

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
          (rv ^. #value) `shouldBe` VText "my-app"
      -- Should have output a retry message
      (st ^. #outputs) `shouldSatisfy` any (== "Value cannot be empty. Please try again.")

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
          modules = [(primaryInstance (m ^. #name), m, "/fake/base")]
      (result, st) <-
        runEff $
          runConsolePure ["my-app"] $
            resolveWithPrompts modules Map.empty Map.empty "" "" Map.empty Map.empty Map.empty Map.empty
      case result of
        Left errs -> expectationFailure $ "Expected Right, got: " ++ show errs
        Right resolved -> do
          let baseVars = resolved Map.! primaryInstance "base"
          ((baseVars Map.! "project.name") ^. #value) `shouldBe` VText "my-app"
          ((baseVars Map.! "project.name") ^. #source) `shouldBe` FromPrompt
      (st ^. #outputs) `shouldSatisfy` any (== "What is the project name?")

    it "does not prompt when all variables are provided via CLI" $ do
      let m =
            mkModule
              "base"
              []
              [mkTextVar "project.name" Nothing True]
              []
              [mkPrompt "project.name" "What is the project name?"]
          modules = [(primaryInstance (m ^. #name), m, "/fake/base")]
          cliOverrides = Map.singleton "project.name" "from-cli"
      (result, st) <-
        runEff $
          runConsolePure [] $
            resolveWithPrompts modules cliOverrides Map.empty "" "" Map.empty Map.empty Map.empty Map.empty
      case result of
        Left errs -> expectationFailure $ "Expected Right, got: " ++ show errs
        Right resolved -> do
          let baseVars = resolved Map.! primaryInstance "base"
          ((baseVars Map.! "project.name") ^. #value) `shouldBe` VText "from-cli"
          ((baseVars Map.! "project.name") ^. #source) `shouldBe` FromCLI
      -- No prompts should have been displayed
      (st ^. #outputs) `shouldSatisfy` all (/= "What is the project name?")

    it "skips prompts and errors in non-interactive mode" $ do
      let m =
            mkModule
              "base"
              []
              [mkTextVar "project.name" Nothing True]
              []
              [mkPrompt "project.name" "What is the project name?"]
          modules = [(primaryInstance (m ^. #name), m, "/fake/base")]
      (result, st) <-
        runEff $
          runConsolePureNonInteractive $
            resolveWithPrompts modules Map.empty Map.empty "" "" Map.empty Map.empty Map.empty Map.empty
      case result of
        Left errs -> case errs of
          [MissingRequiredVar name] -> name `shouldBe` "project.name"
          [other] -> expectationFailure $ "Expected MissingRequiredVar, got: " ++ show other
          _ -> expectationFailure $ "Expected exactly 1 error, got: " ++ show (length errs)
        Right _ -> expectationFailure "Expected Left (errors), got Right"
      -- No prompts should have been displayed
      (st ^. #outputs) `shouldSatisfy` all (/= "What is the project name?")

    it "forbids prompts even when the Console interpreter is interactive" $ do
      let m =
            mkModule
              "base"
              []
              [mkTextVar "project.name" Nothing True]
              []
              [mkPrompt "project.name" "What is the project name?"]
          modules = [(primaryInstance (m ^. #name), m, "/fake/base")]
      (result, st) <-
        runEff $
          runConsolePure ["must-not-be-read"] $
            resolveWithPromptPermission PromptsForbidden modules Map.empty Map.empty Map.empty "" "" Map.empty Map.empty Map.empty Map.empty
      result `shouldBe` Left [MissingRequiredVar "project.name"]
      (st ^. #inputs) `shouldBe` ["must-not-be-read"]
      (st ^. #outputs) `shouldSatisfy` all (/= "What is the project name?")

    it "prompts for optional variables after required resolution" $ do
      let m =
            mkModule
              "base"
              []
              [ mkTextVar "project.name" Nothing True,
                mkTextVar "license" Nothing False
              ]
              []
              [ mkPrompt "project.name" "What is the project name?",
                mkPrompt "license" "License"
              ]
          modules = [(primaryInstance (m ^. #name), m, "/fake/base")]
      (result, st) <-
        runEff $
          runConsolePure ["my-app", "MIT"] $
            resolveWithPrompts modules Map.empty Map.empty "" "" Map.empty Map.empty Map.empty Map.empty
      case result of
        Left errs -> expectationFailure $ "Expected Right, got: " ++ show errs
        Right resolved -> do
          let baseVars = resolved Map.! primaryInstance "base"
          ((baseVars Map.! "project.name") ^. #value) `shouldBe` VText "my-app"
          ((baseVars Map.! "project.name") ^. #source) `shouldBe` FromPrompt
          ((baseVars Map.! "license") ^. #value) `shouldBe` VText "MIT"
          ((baseVars Map.! "license") ^. #source) `shouldBe` FromPrompt
      (st ^. #outputs) `shouldSatisfy` any (== "Optional configuration:")

    it "skips optional variable when user presses Enter" $ do
      let m =
            mkModule
              "base"
              []
              [ mkTextVar "project.name" Nothing True,
                mkTextVar "license" Nothing False
              ]
              []
              [ mkPrompt "project.name" "What is the project name?",
                mkPrompt "license" "License"
              ]
          modules = [(primaryInstance (m ^. #name), m, "/fake/base")]
      (result, _st) <-
        runEff $
          runConsolePure ["my-app", ""] $
            resolveWithPrompts modules Map.empty Map.empty "" "" Map.empty Map.empty Map.empty Map.empty
      case result of
        Left errs -> expectationFailure $ "Expected Right, got: " ++ show errs
        Right resolved -> do
          let baseVars = resolved Map.! primaryInstance "base"
          Map.member "project.name" baseVars `shouldBe` True
          Map.member "license" baseVars `shouldBe` False

    it "shows Optional configuration separator for optional-only modules" $ do
      let m =
            mkModule
              "base"
              []
              [mkTextVar "license" Nothing False]
              []
              [mkPrompt "license" "License"]
          modules = [(primaryInstance (m ^. #name), m, "/fake/base")]
      (result, st) <-
        runEff $
          runConsolePure ["MIT"] $
            resolveWithPrompts modules Map.empty Map.empty "" "" Map.empty Map.empty Map.empty Map.empty
      case result of
        Left errs -> expectationFailure $ "Expected Right, got: " ++ show errs
        Right resolved -> do
          let baseVars = resolved Map.! primaryInstance "base"
          ((baseVars Map.! "license") ^. #value) `shouldBe` VText "MIT"
      (st ^. #outputs) `shouldSatisfy` any (== "Optional configuration:")

    it "does not show optional prompts in non-interactive mode" $ do
      let m =
            mkModule
              "base"
              []
              [mkTextVar "license" Nothing False]
              []
              [mkPrompt "license" "License"]
          modules = [(primaryInstance (m ^. #name), m, "/fake/base")]
      (result, st) <-
        runEff $
          runConsolePureNonInteractive $
            resolveWithPrompts modules Map.empty Map.empty "" "" Map.empty Map.empty Map.empty Map.empty
      case result of
        Left _ -> expectationFailure "Expected Right (no required vars)"
        Right resolved -> do
          let baseVars = resolved Map.! primaryInstance "base"
          Map.member "license" baseVars `shouldBe` False
      (st ^. #outputs) `shouldSatisfy` all (/= "Optional configuration:")

    it "respects when condition on optional prompts" $ do
      let m =
            mkModule
              "base"
              []
              [ mkTextVar "project.name" Nothing True,
                mkTextVar "extra" Nothing False
              ]
              []
              [ mkPrompt "project.name" "Name?",
                mkConditionalPrompt "extra" "Extra?" (ExprIsSet "nonexistent")
              ]
          modules = [(primaryInstance (m ^. #name), m, "/fake/base")]
      (result, st) <-
        runEff $
          runConsolePure ["my-app"] $
            resolveWithPrompts modules Map.empty Map.empty "" "" Map.empty Map.empty Map.empty Map.empty
      case result of
        Left errs -> expectationFailure $ "Expected Right, got: " ++ show errs
        Right resolved -> do
          let baseVars = resolved Map.! primaryInstance "base"
          Map.member "extra" baseVars `shouldBe` False
      -- The condition was false so Optional configuration header should not appear
      -- (no optional prompts actually fired)
      (st ^. #outputs) `shouldSatisfy` all (/= "Extra?")

    it "does not prompt for optional variables already resolved via config" $ do
      let m =
            mkModule
              "base"
              []
              [mkTextVar "license" Nothing False]
              []
              [mkPrompt "license" "License"]
          modules = [(primaryInstance (m ^. #name), m, "/fake/base")]
          globalConfig = Map.singleton "license" "MIT"
      (result, st) <-
        runEff $
          runConsolePure [] $
            resolveWithPrompts modules Map.empty Map.empty "" "" Map.empty Map.empty Map.empty globalConfig
      case result of
        Left errs -> expectationFailure $ "Expected Right, got: " ++ show errs
        Right resolved -> do
          let baseVars = resolved Map.! primaryInstance "base"
          ((baseVars Map.! "license") ^. #value) `shouldBe` VText "MIT"
          ((baseVars Map.! "license") ^. #source) `shouldBe` FromGlobalConfig
      (st ^. #outputs) `shouldSatisfy` all (/= "Optional configuration:")

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
          modules = [(primaryInstance (base ^. #name), base, "/fake/base"), (primaryInstance (app ^. #name), app, "/fake/app")]
      (result, st) <-
        runEff $
          runConsolePure ["my-app"] $
            resolveWithPrompts modules Map.empty Map.empty "" "" Map.empty Map.empty Map.empty Map.empty
      case result of
        Left errs -> expectationFailure $ "Expected Right, got: " ++ show errs
        Right resolved -> do
          -- Base module was prompted
          let baseVars = resolved Map.! primaryInstance "base"
          ((baseVars Map.! "project.name") ^. #value) `shouldBe` VText "my-app"
          ((baseVars Map.! "project.name") ^. #source) `shouldBe` FromPrompt
          -- App module received the value via export (no additional prompt needed)
          let appVars = resolved Map.! primaryInstance "app"
          ((appVars Map.! "project.name") ^. #value) `shouldBe` VText "my-app"
      -- Only one prompt should have fired (for base), not two
      let promptOutputs = filter (== "What is the project name?") (st ^. #outputs)
      length promptOutputs `shouldBe` 1
