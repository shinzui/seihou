module Seihou.Interaction.ConfirmSpec (tests) where

import Data.Map.Strict qualified as Map
import Effectful
import Seihou.Composition.Instance (primaryInstance)
import Seihou.Core.Types
import Seihou.Effect.ConsolePure
import Seihou.Interaction.Confirm (confirmDefaults)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Interaction.Confirm" spec

mkModule :: ModuleName -> [VarDecl] -> [Prompt] -> Module
mkModule name vars prompts =
  Module
    { name = name,
      version = Nothing,
      description = Nothing,
      vars = vars,
      exports = [],
      prompts = prompts,
      steps = [],
      commands = [],
      dependencies = [],
      removal = Nothing
    }

mkTextVar :: VarName -> Maybe VarValue -> VarDecl
mkTextVar name defVal =
  VarDecl
    { name = name,
      type_ = VTText,
      default_ = defVal,
      description = Nothing,
      required = True,
      validation = Nothing
    }

mkIntVar :: VarName -> Maybe VarValue -> VarDecl
mkIntVar name defVal =
  VarDecl
    { name = name,
      type_ = VTInt,
      default_ = defVal,
      description = Nothing,
      required = True,
      validation = Nothing
    }

mkResolved :: VarDecl -> VarValue -> VarSource -> ResolvedVar
mkResolved decl val src =
  ResolvedVar {value = val, source = src, decl = decl}

spec :: Spec
spec = do
  describe "confirmDefaults" $ do
    it "does nothing when the flag activates but no variables have default sources" $ do
      let decl = mkTextVar "project.name" (Just (VText "my-project"))
          m = mkModule "base" [decl] []
          resolved =
            Map.singleton
              (primaryInstance "base")
              (Map.singleton "project.name" (mkResolved decl (VText "my-app") FromCLI))
      (result, st) <-
        runEff $
          runConsolePure [] $
            confirmDefaults [(primaryInstance m.name, m, "/fake/base")] resolved
      result `shouldBe` resolved
      st.consoleOutputs `shouldSatisfy` all (/= "Confirm default values:")

    it "prompts for FromDefault variables and accepts Enter as keeping the default" $ do
      let decl = mkTextVar "project.version" (Just (VText "0.1.0.0"))
          m = mkModule "base" [decl] []
          resolved =
            Map.singleton
              (primaryInstance "base")
              (Map.singleton "project.version" (mkResolved decl (VText "0.1.0.0") FromDefault))
      (result, st) <-
        runEff $
          runConsolePure [""] $
            confirmDefaults [(primaryInstance m.name, m, "/fake/base")] resolved
      let rv = (result Map.! primaryInstance "base") Map.! "project.version"
      rv.value `shouldBe` VText "0.1.0.0"
      rv.source `shouldBe` FromDefault
      st.consoleOutputs `shouldSatisfy` any (== "Confirm default values:")
      st.consoleOutputs `shouldSatisfy` any (== "project.version [0.1.0.0]:")

    it "replaces the value and marks source as FromPrompt when user types a new value" $ do
      let decl = mkTextVar "project.version" (Just (VText "0.1.0.0"))
          m = mkModule "base" [decl] []
          resolved =
            Map.singleton
              (primaryInstance "base")
              (Map.singleton "project.version" (mkResolved decl (VText "0.1.0.0") FromDefault))
      (result, _st) <-
        runEff $
          runConsolePure ["1.0.0"] $
            confirmDefaults [(primaryInstance m.name, m, "/fake/base")] resolved
      let rv = (result Map.! primaryInstance "base") Map.! "project.version"
      rv.value `shouldBe` VText "1.0.0"
      rv.source `shouldBe` FromPrompt

    it "retries on invalid input and keeps the default on final failure" $ do
      let decl = mkIntVar "retry.count" (Just (VInt 42))
          m = mkModule "base" [decl] []
          resolved =
            Map.singleton
              (primaryInstance "base")
              (Map.singleton "retry.count" (mkResolved decl (VInt 42) FromDefault))
      (result, _st) <-
        runEff $
          runConsolePure ["not-an-int", "still-bad", "nope"] $
            confirmDefaults [(primaryInstance m.name, m, "/fake/base")] resolved
      let rv = (result Map.! primaryInstance "base") Map.! "retry.count"
      rv.value `shouldBe` VInt 42
      rv.source `shouldBe` FromDefault

    it "prompts for FromParent variables" $ do
      let decl = mkTextVar "skill.name" (Just (VText "exec-plan"))
          m = mkModule "child" [decl] []
          resolved =
            Map.singleton
              (primaryInstance "child")
              ( Map.singleton
                  "skill.name"
                  (mkResolved decl (VText "exec-plan") (FromParent "parent"))
              )
      (result, _st) <-
        runEff $
          runConsolePure ["override"] $
            confirmDefaults [(primaryInstance m.name, m, "/fake/child")] resolved
      let rv = (result Map.! primaryInstance "child") Map.! "skill.name"
      rv.value `shouldBe` VText "override"
      rv.source `shouldBe` FromPrompt

    it "is a no-op in non-interactive mode" $ do
      let decl = mkTextVar "project.version" (Just (VText "0.1.0.0"))
          m = mkModule "base" [decl] []
          resolved =
            Map.singleton
              (primaryInstance "base")
              (Map.singleton "project.version" (mkResolved decl (VText "0.1.0.0") FromDefault))
      (result, st) <-
        runEff $
          runConsolePureNonInteractive $
            confirmDefaults [(primaryInstance m.name, m, "/fake/base")] resolved
      result `shouldBe` resolved
      st.consoleOutputs `shouldBe` []

    it "uses authored Prompt text when available" $ do
      let decl = mkTextVar "license" (Just (VText "MIT"))
          prompt =
            Prompt
              { var = "license",
                text = "Choose a license",
                condition = Nothing,
                choices = Nothing
              }
          m = mkModule "base" [decl] [prompt]
          resolved =
            Map.singleton
              (primaryInstance "base")
              (Map.singleton "license" (mkResolved decl (VText "MIT") FromDefault))
      (_result, st) <-
        runEff $
          runConsolePure [""] $
            confirmDefaults [(primaryInstance m.name, m, "/fake/base")] resolved
      st.consoleOutputs `shouldSatisfy` any (== "Choose a license [MIT]:")
