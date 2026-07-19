module Seihou.Core.ApplicationSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (UTCTime, defaultTimeLocale, parseTimeOrError)
import Seihou.Composition.Instance (ModuleInstance (..))
import Seihou.Core.Application
import Seihou.Core.Types
import Seihou.Manifest.Hash (hashContent)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Core.Application" spec

fixedTime :: UTCTime
fixedTime = parseTimeOrError True defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ" "2026-07-19T10:30:00Z"

moduleTarget :: AppliedTarget
moduleTarget = AppliedModuleTarget (ModuleName "master-plan")

mkModule :: ModuleName -> Maybe Text -> Module
mkModule name version =
  Module
    { name = name,
      version = version,
      description = Nothing,
      vars = [],
      exports = [],
      prompts = [],
      steps = [],
      commands = [],
      dependencies = [],
      removal = Nothing,
      migrations = []
    }

mkResolved :: VarName -> VarValue -> ResolvedVar
mkResolved name value =
  ResolvedVar
    { value = value,
      source = FromDefault,
      decl =
        VarDecl
          { name = name,
            type_ = VTText,
            default_ = Nothing,
            description = Nothing,
            required = False,
            validation = Nothing
          }
    }

mkComposition :: AppliedTarget -> [ModuleName] -> AppliedComposition
mkComposition target additional =
  AppliedComposition
    { applicationId = mkApplicationId target additional,
      target = target,
      targetSource = "/modules/root",
      targetVersion = Just "1.0.0",
      additionalModules = additional,
      namespace = Just "root",
      context = Nothing,
      instances = [],
      commandReceipts = Map.empty,
      appliedAt = fixedTime
    }

spec :: Spec
spec = do
  describe "mkApplicationId" $ do
    it "is deterministic and uses the full SHA-256 digest" $ do
      let first = mkApplicationId moduleTarget [ModuleName "docs"]
          second = mkApplicationId moduleTarget [ModuleName "docs"]
      first `shouldBe` second
      T.length first.unApplicationId `shouldBe` 64

    it "changes when additional-root order changes" $ do
      let first = mkApplicationId moduleTarget [ModuleName "a", ModuleName "b"]
          second = mkApplicationId moduleTarget [ModuleName "b", ModuleName "a"]
      first `shouldNotBe` second

    it "distinguishes a module target from a recipe target with the same name" $ do
      mkApplicationId (AppliedModuleTarget "shared") []
        `shouldNotBe` mkApplicationId (AppliedRecipeTarget "shared") []

  describe "buildAppliedComposition" $ do
    it "keeps separately-scoped values for two instances of the same module" $ do
      let moduleName = ModuleName "link-skill"
          pv1 = ParentVars (Map.singleton (VarName "skill.name") "exec-plan")
          pv2 = ParentVars (Map.singleton (VarName "skill.name") "master-plan")
          inst1 = ModuleInstance moduleName pv1
          inst2 = ModuleInstance moduleName pv2
          modul = mkModule moduleName (Just "0.7.0")
          modulesInOrder = [(inst1, modul, "/modules/link-skill"), (inst2, modul, "/modules/link-skill")]
          resolved =
            Map.fromList
              [ (inst1, Map.singleton (VarName "skill.name") (mkResolved "skill.name" (VText "exec-plan"))),
                (inst2, Map.singleton (VarName "skill.name") (mkResolved "skill.name" (VText "master-plan")))
              ]
          composition =
            buildAppliedComposition moduleTarget "/modules/master-plan" (Just "0.7.0") [] (Just "docs") Nothing modulesInOrder resolved fixedTime
      map (.parentVars) composition.instances `shouldBe` [pv1, pv2]
      map (.resolvedVars) composition.instances
        `shouldBe` [Map.singleton "skill.name" "exec-plan", Map.singleton "skill.name" "master-plan"]

    it "keeps identity independent of versions, source paths, and resolved values" $ do
      let inst = ModuleInstance "dep" emptyParentVars
          first =
            buildAppliedComposition
              moduleTarget
              "/old/root"
              (Just "1.0.0")
              ["extra"]
              Nothing
              Nothing
              [(inst, mkModule "dep" (Just "1.0.0"), "/old/dep")]
              (Map.singleton inst (Map.singleton "value" (mkResolved "value" (VText "old"))))
              fixedTime
          second =
            buildAppliedComposition
              moduleTarget
              "/new/root"
              (Just "2.0.0")
              ["extra"]
              Nothing
              Nothing
              [(inst, mkModule "dep" (Just "2.0.0"), "/new/dep")]
              (Map.singleton inst (Map.singleton "value" (mkResolved "value" (VText "new"))))
              fixedTime
      first.applicationId `shouldBe` second.applicationId

    it "preserves the original module or recipe target" $ do
      let moduleComposition = buildAppliedComposition moduleTarget "/module" Nothing [] Nothing Nothing [] Map.empty fixedTime
          recipeTarget = AppliedRecipeTarget "service"
          recipeComposition = buildAppliedComposition recipeTarget "/recipe" (Just "2") [] Nothing Nothing [] Map.empty fixedTime
      moduleComposition.target `shouldBe` moduleTarget
      recipeComposition.target `shouldBe` recipeTarget

  describe "replaceAppliedComposition" $ do
    it "replaces in place and appends new applications" $ do
      let first = mkComposition moduleTarget []
          second = mkComposition (AppliedModuleTarget "other") []
          replacement = first {targetVersion = Just "2.0.0"}
          third = mkComposition (AppliedRecipeTarget "third") []
      replaceAppliedComposition replacement [first, second] `shouldBe` [replacement, second]
      replaceAppliedComposition third [first, second] `shouldBe` [first, second, third]

  describe "attachApplication" $ do
    it "unions prior and current ownership and preserves the generated baseline" $ do
      let priorId = ApplicationId "prior"
          currentId = ApplicationId "current"
          prior = FileRecord (hashContent "old") "module" Template fixedTime Nothing (Set.singleton priorId)
          current = FileRecord (hashContent "new") "module" Template fixedTime (Just (BaselineRef (hashContent "generated"))) Set.empty
          attached = attachApplication currentId (Just prior) current
      attached.applicationIds `shouldBe` Set.fromList [priorId, currentId]
      attached.baseline `shouldBe` Just (BaselineRef (hashContent "generated"))
