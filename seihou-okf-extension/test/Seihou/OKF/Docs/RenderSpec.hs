module Seihou.OKF.Docs.RenderSpec (tests) where

import Data.List (sort)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Okf.Bundle qualified as Okf
import Okf.ConceptId qualified as Okf
import Okf.Validation (BundleValidationError (..))
import Seihou.Core.Types
import Seihou.OKF.Docs.Model
import Seihou.OKF.Docs.Render
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.OKF.Docs.Render" spec

spec :: Spec
spec = do
  describe "renderDocBundle" $ do
    it "emits one concept per entry with the documented id scheme" $ do
      let Right (concepts, problems) = renderDocBundle wellFormedModel
      problems `shouldBe` []
      sort (Okf.renderConceptId . Okf.conceptIdOf <$> concepts)
        `shouldBe` [ "blueprints/app-blueprint",
                     "modules/app",
                     "modules/base",
                     "prompts/review",
                     "recipes/app-recipe"
                   ]

    it "renders frontmatter fields and resource pointers" $ do
      concept <- requireConcept "modules/base" wellFormedModel
      let rendered = Okf.serializeConcept concept
      rendered `shouldSatisfy` T.isInfixOf "type: SeihouModule"
      rendered `shouldSatisfy` T.isInfixOf "title: base"
      rendered `shouldSatisfy` T.isInfixOf "resource: seihou://fixture/modules/base"
      rendered `shouldSatisfy` T.isInfixOf "version: 1.0.0"

    it "renders resolvable cross-links to composed modules" $ do
      concept <- requireConcept "recipes/app-recipe" wellFormedModel
      let rendered = Okf.serializeConcept concept
      rendered `shouldSatisfy` T.isInfixOf "](/modules/base.md)"
      rendered `shouldSatisfy` T.isInfixOf "](/modules/app.md)"

    it "validates clean for a well-formed model" $ do
      let Right (_, problems) = renderDocBundle wellFormedModel
      problems `shouldBe` []

    it "reports a DanglingReference for an unresolved module ref" $ do
      let Right (_, problems) = renderDocBundle danglingModel
      problems `shouldSatisfy` any isDanglingReference

    it "reports invalid generated concept IDs as render errors" $ do
      renderDocBundle invalidIdModel
        `shouldBe` Left [InvalidDocConceptId DocModuleKind "-bad" "InvalidConceptIdSegment \"-bad\""]

requireConcept :: T.Text -> DocModel -> IO Okf.Concept
requireConcept rawId model =
  case renderDocBundle model of
    Left errs -> expectationFailure ("Expected render success, got " <> show errs) >> error "unreachable"
    Right (concepts, _) ->
      case Okf.parseConceptId rawId of
        Left err -> expectationFailure ("Bad test concept id: " <> show err) >> error "unreachable"
        Right conceptId ->
          case filter (\concept -> Okf.conceptIdOf concept == conceptId) concepts of
            [concept] -> pure concept
            other -> expectationFailure ("Expected one concept, got " <> show (length other)) >> error "unreachable"

isDanglingReference :: BundleValidationError -> Bool
isDanglingReference DanglingReference {} = True
isDanglingReference _ = False

wellFormedModel :: DocModel
wellFormedModel =
  DocModel
    { docRepoName = "fixture",
      docRepoDescription = Just "Fixture",
      docEntries =
        [ moduleEntry "base" [] "modules/base",
          moduleEntry "app" [ModuleRef "base" True] "modules/app",
          recipeEntry,
          blueprintEntry,
          promptEntry
        ]
    }

danglingModel :: DocModel
danglingModel =
  DocModel
    { docRepoName = "fixture",
      docRepoDescription = Nothing,
      docEntries =
        [ moduleEntry "app" [ModuleRef "missing" False] "modules/app"
        ]
    }

invalidIdModel :: DocModel
invalidIdModel =
  DocModel
    { docRepoName = "fixture",
      docRepoDescription = Nothing,
      docEntries =
        [ moduleEntry "-bad" [] "modules/bad"
        ]
    }

moduleEntry :: T.Text -> [ModuleRef] -> FilePath -> DocEntry
moduleEntry name refs path =
  DocEntry
    { entryName = name,
      entryKind = DocModuleKind,
      entryVersion = Just "1.0.0",
      entryDescription = Just (name <> " module"),
      entryTags = ["module"],
      entryPath = path,
      entryArtifact = DocModuleArtifact (moduleArtifact name refs),
      entryModuleRefs = refs
    }

moduleArtifact :: T.Text -> [ModuleRef] -> Module
moduleArtifact name refs =
  Module
    { name = ModuleName name,
      version = Just "1.0.0",
      description = Just (name <> " module"),
      vars = [],
      exports = [],
      prompts = [],
      steps = [],
      commands = [],
      dependencies = [Dependency (ModuleName ref.refName) Map.empty | ref <- refs],
      removal = Nothing,
      migrations = []
    }

recipeEntry :: DocEntry
recipeEntry =
  DocEntry
    { entryName = "app-recipe",
      entryKind = DocRecipeKind,
      entryVersion = Just "0.1.0",
      entryDescription = Just "Recipe",
      entryTags = ["recipe"],
      entryPath = "recipes/app-recipe",
      entryArtifact =
        DocRecipeArtifact
          Recipe
            { name = RecipeName "app-recipe",
              version = Just "0.1.0",
              description = Just "Recipe",
              modules = [simpleDep "base", simpleDep "app"],
              vars = [],
              prompts = []
            },
      entryModuleRefs = [ModuleRef "base" True, ModuleRef "app" True]
    }

blueprintEntry :: DocEntry
blueprintEntry =
  DocEntry
    { entryName = "app-blueprint",
      entryKind = DocBlueprintKind,
      entryVersion = Just "0.1.0",
      entryDescription = Just "Blueprint",
      entryTags = ["blueprint"],
      entryPath = "blueprints/app-blueprint",
      entryArtifact =
        DocBlueprintArtifact
          Blueprint
            { name = ModuleName "app-blueprint",
              version = Just "0.1.0",
              description = Just "Blueprint",
              prompt = "Build the app",
              vars = [],
              prompts = [],
              baseModules = [simpleDep "base"],
              files = [],
              allowedTools = Nothing,
              tags = ["blueprint"],
              migrations = []
            },
      entryModuleRefs = [ModuleRef "base" True]
    }

promptEntry :: DocEntry
promptEntry =
  DocEntry
    { entryName = "review",
      entryKind = DocPromptKind,
      entryVersion = Just "0.1.0",
      entryDescription = Just "Review prompt",
      entryTags = ["prompt"],
      entryPath = "prompts/review",
      entryArtifact =
        DocPromptArtifact
          AgentPrompt
            { name = ModuleName "review",
              version = Just "0.1.0",
              description = Just "Review prompt",
              prompt = "Review the change",
              vars = [],
              prompts = [],
              commandVars = [],
              files = [],
              allowedTools = Nothing,
              tags = ["prompt"],
              launch = Nothing
            },
      entryModuleRefs = []
    }
