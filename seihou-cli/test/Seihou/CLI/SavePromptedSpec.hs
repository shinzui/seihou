module Seihou.CLI.SavePromptedSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Seihou.CLI.SavePrompted (collectPromptedValues, offerSavePrompted)
import Seihou.Composition.Instance (primaryInstance)
import Seihou.Core.Types
import Seihou.Effect.ConfigWriterPure (ConfigWriterState (..), emptyConfigWriterState, runConfigWriterPure)
import Seihou.Effect.ConsolePure (ConsoleState (..), runConsolePure)
import Seihou.Prelude (runEff)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.CLI.SavePrompted" spec

mkDecl :: Text -> VarDecl
mkDecl n =
  VarDecl
    { name = VarName n,
      type_ = VTText,
      default_ = Nothing,
      description = Nothing,
      required = True,
      validation = Nothing
    }

mkResolved :: VarSource -> Text -> VarDecl -> ResolvedVar
mkResolved src val decl =
  ResolvedVar
    { value = VText val,
      source = src,
      decl = decl
    }

spec :: Spec
spec = do
  describe "collectPromptedValues" $ do
    it "extracts variables with FromPrompt source" $ do
      let decl = mkDecl "project.name"
          resolved =
            Map.singleton (primaryInstance (ModuleName "mod1")) $
              Map.singleton (VarName "project.name") (mkResolved FromPrompt "my-app" decl)
          result = collectPromptedValues resolved Map.empty
      result `shouldBe` [(VarName "project.name", "my-app", Nothing)]

    it "ignores variables from non-prompt sources" $ do
      let decl = mkDecl "license"
          resolved =
            Map.singleton (primaryInstance (ModuleName "mod1")) $
              Map.fromList
                [ (VarName "license", mkResolved FromGlobalConfig "MIT" decl),
                  (VarName "project.name", mkResolved FromCLI "foo" (mkDecl "project.name"))
                ]
          result = collectPromptedValues resolved Map.empty
      result `shouldBe` []

    it "skips values already in local config with the same value" $ do
      let decl = mkDecl "project.name"
          resolved =
            Map.singleton (primaryInstance (ModuleName "mod1")) $
              Map.singleton (VarName "project.name") (mkResolved FromPrompt "my-app" decl)
          localConfig = Map.singleton (VarName "project.name") "my-app"
          result = collectPromptedValues resolved localConfig
      result `shouldBe` []

    it "includes values that differ from local config with existing value" $ do
      let decl = mkDecl "project.name"
          resolved =
            Map.singleton (primaryInstance (ModuleName "mod1")) $
              Map.singleton (VarName "project.name") (mkResolved FromPrompt "new-app" decl)
          localConfig = Map.singleton (VarName "project.name") "old-app"
          result = collectPromptedValues resolved localConfig
      result `shouldBe` [(VarName "project.name", "new-app", Just "old-app")]

    it "deduplicates across modules" $ do
      let decl = mkDecl "project.name"
          resolved =
            Map.fromList
              [ ( primaryInstance (ModuleName "mod1"),
                  Map.singleton (VarName "project.name") (mkResolved FromPrompt "app1" decl)
                ),
                ( primaryInstance (ModuleName "mod2"),
                  Map.singleton (VarName "project.name") (mkResolved FromPrompt "app2" decl)
                )
              ]
          result = collectPromptedValues resolved Map.empty
      length result `shouldBe` 1

    it "handles multiple prompted variables" $ do
      let resolved =
            Map.singleton (primaryInstance (ModuleName "mod1")) $
              Map.fromList
                [ (VarName "license", mkResolved FromPrompt "MIT" (mkDecl "license")),
                  (VarName "project.name", mkResolved FromPrompt "my-app" (mkDecl "project.name"))
                ]
          result = collectPromptedValues resolved Map.empty
      length result `shouldBe` 2

    it "returns empty list when no prompted values exist" $ do
      let resolved =
            Map.singleton (primaryInstance (ModuleName "mod1")) $
              Map.singleton (VarName "x") (mkResolved FromDefault "val" (mkDecl "x"))
          result = collectPromptedValues resolved Map.empty
      result `shouldBe` []

  describe "offerSavePrompted" $ do
    let entries =
          [ (VarName "project.name", "my-app", Nothing),
            (VarName "license", "MIT", Nothing)
          ]

    it "saves values when user confirms with 'y'" $ do
      (((), cwState), _consoleSt) <-
        runEff $
          runConsolePure ["y"] $
            runConfigWriterPure emptyConfigWriterState $
              offerSavePrompted Nothing True entries
      cwState.cwLocal `shouldBe` Map.fromList [("project.name", "my-app"), ("license", "MIT")]

    it "does not save when user declines with 'n'" $ do
      (((), cwState), _consoleSt) <-
        runEff $
          runConsolePure ["n"] $
            runConfigWriterPure emptyConfigWriterState $
              offerSavePrompted Nothing True entries
      cwState.cwLocal `shouldBe` Map.empty

    it "saves without asking when --save-prompted (Just True)" $ do
      (((), cwState), consoleSt) <-
        runEff $
          runConsolePure [] $
            runConfigWriterPure emptyConfigWriterState $
              offerSavePrompted (Just True) True entries
      cwState.cwLocal `shouldBe` Map.fromList [("project.name", "my-app"), ("license", "MIT")]
      -- Should not contain the confirmation prompt
      any (T.isInfixOf "Save prompted values") consoleSt.consoleOutputs `shouldBe` False

    it "skips entirely when --no-save-prompted (Just False)" $ do
      (((), cwState), consoleSt) <-
        runEff $
          runConsolePure [] $
            runConfigWriterPure emptyConfigWriterState $
              offerSavePrompted (Just False) True entries
      cwState.cwLocal `shouldBe` Map.empty
      consoleSt.consoleOutputs `shouldBe` []

    it "skips in non-interactive mode when no flag given" $ do
      (((), cwState), _consoleSt) <-
        runEff $
          runConsolePure [] $
            runConfigWriterPure emptyConfigWriterState $
              offerSavePrompted Nothing False entries
      cwState.cwLocal `shouldBe` Map.empty

    it "shows overwrite note for existing values" $ do
      let entriesWithOverwrite =
            [ (VarName "project.name", "new-app", Just "old-app")
            ]
      ((_result, _cwState), consoleSt) <-
        runEff $
          runConsolePure ["y"] $
            runConfigWriterPure emptyConfigWriterState $
              offerSavePrompted Nothing True entriesWithOverwrite
      any (T.isInfixOf "overwrites current") consoleSt.consoleOutputs `shouldBe` True

    it "does nothing when entries list is empty" $ do
      (((), cwState), consoleSt) <-
        runEff $
          runConsolePure [] $
            runConfigWriterPure emptyConfigWriterState $
              offerSavePrompted Nothing True []
      cwState.cwLocal `shouldBe` Map.empty
      consoleSt.consoleOutputs `shouldBe` []

    it "displays confirmation message after saving" $ do
      (((), _cwState), consoleSt) <-
        runEff $
          runConsolePure ["y"] $
            runConfigWriterPure emptyConfigWriterState $
              offerSavePrompted Nothing True entries
      any (T.isInfixOf "Saved 2 value(s)") consoleSt.consoleOutputs `shouldBe` True
