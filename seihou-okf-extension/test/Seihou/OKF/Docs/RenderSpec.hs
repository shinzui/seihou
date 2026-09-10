module Seihou.OKF.Docs.RenderSpec (tests) where

import Control.Lens ((&), (?~), (^.))
import Data.Generics.Labels ()
import Data.List (sort)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Okf.Bundle qualified as Okf
import Okf.ConceptId qualified as Okf
import Okf.Validation (BundleValidationError (..), ValidationProfile (..))
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
      (concepts, problems) <- renderOrFail testOptions wellFormedModel
      problems `shouldBe` []
      sort (Okf.renderConceptId . Okf.conceptIdOf <$> concepts)
        `shouldBe` [ "blueprints/app-blueprint",
                     "modules/app",
                     "modules/base",
                     "prompts/review",
                     "recipes/app-recipe"
                   ]

    it "renders frontmatter fields and resource pointers" $ do
      concept <- requireConcept "modules/base" testOptions wellFormedModel
      let rendered = Okf.serializeConcept concept
      rendered `shouldSatisfy` T.isInfixOf "type: SeihouModule"
      rendered `shouldSatisfy` T.isInfixOf "title: base"
      rendered `shouldSatisfy` T.isInfixOf "resource: seihou://fixture/modules/base"
      rendered `shouldSatisfy` T.isInfixOf "version: 1.0.0"

    it "renders resolvable cross-links to composed modules" $ do
      concept <- requireConcept "recipes/app-recipe" testOptions wellFormedModel
      let rendered = Okf.serializeConcept concept
      rendered `shouldSatisfy` T.isInfixOf "](/modules/base.md)"
      rendered `shouldSatisfy` T.isInfixOf "](/modules/app.md)"

    it "validates clean for a well-formed model" $ do
      (_, problems) <- renderOrFail testOptions wellFormedModel
      problems `shouldBe` []

    it "reports a DanglingReference for an unresolved module ref" $ do
      (_, problems) <- renderOrFail testOptions danglingModel
      problems `shouldSatisfy` any isDanglingReference

    it "reports invalid generated concept IDs as render errors" $ do
      renderDocBundle testOptions invalidIdModel
        `shouldBe` Left [InvalidDocConceptId DocModuleKind "-bad" "InvalidConceptIdSegment \"-bad\""]

    it "stamps a generated.by producer actor on every concept" $ do
      (concepts, _) <- renderOrFail testOptions wellFormedModel
      let rendered = Okf.serializeConcept <$> concepts
      rendered `shouldSatisfy` all (T.isInfixOf "by: seihou-okf-extension/9.9.9")

    it "omits generated.at unless the operator supplies one" $ do
      concept <- requireConcept "modules/base" testOptions wellFormedModel
      Okf.serializeConcept concept `shouldNotSatisfy` T.isInfixOf "at:"

    it "records --generated-at verbatim in generated.at" $ do
      let dated = testOptions & #generatedAt ?~ "2026-09-10"
      concept <- requireConcept "modules/base" dated wellFormedModel
      Okf.serializeConcept concept `shouldSatisfy` T.isInfixOf "at: 2026-09-10"

    it "marks every concept stable" $ do
      concept <- requireConcept "modules/base" testOptions wellFormedModel
      Okf.serializeConcept concept `shouldSatisfy` T.isInfixOf "status: stable"

    it "validates clean under StrictAuthoring when nothing supplies a description" $ do
      (_, problems) <- renderOrFail testOptions undescribedModel
      problems `shouldBe` []

    it "falls back to the artifact description when the registry entry has none" $ do
      concept <- requireConcept "modules/base" testOptions registrySilentModel
      Okf.serializeConcept concept
        `shouldSatisfy` T.isInfixOf "description: the artifact describes itself"

    it "synthesizes a description when neither the registry nor the artifact has one" $ do
      concept <- requireConcept "modules/base" testOptions undescribedModel
      Okf.serializeConcept concept
        `shouldSatisfy` T.isInfixOf "Seihou module `base` published by the `fixture` registry."

-- | A fixed producer version, so assertions on the stamped actor do not change
-- every time the package version is bumped.
testOptions :: RenderOptions
testOptions =
  RenderOptions
    { producerVersion = "9.9.9",
      generatedAt = Nothing,
      validationProfile = StrictAuthoring
    }

-- | Render a model, failing the example rather than pattern-matching partially.
renderOrFail :: RenderOptions -> DocModel -> IO ([Okf.Concept], [BundleValidationError])
renderOrFail opts model =
  case renderDocBundle opts model of
    Left errs -> expectationFailure ("Expected render success, got " <> show errs) >> error "unreachable"
    Right rendered -> pure rendered

requireConcept :: T.Text -> RenderOptions -> DocModel -> IO Okf.Concept
requireConcept rawId opts model = do
  (concepts, _) <- renderOrFail opts model
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
    { repoName = "fixture",
      repoDescription = Just "Fixture",
      entries =
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
    { repoName = "fixture",
      repoDescription = Nothing,
      entries =
        [ moduleEntry "app" [ModuleRef "missing" False] "modules/app"
        ]
    }

-- | Neither the registry entry nor the module says anything about itself, which
-- is what StrictAuthoring would otherwise reject.
undescribedModel :: DocModel
undescribedModel =
  DocModel
    { repoName = "fixture",
      repoDescription = Nothing,
      entries = [silentEntry Nothing]
    }

-- | The registry entry is silent but the artifact describes itself.
registrySilentModel :: DocModel
registrySilentModel =
  DocModel
    { repoName = "fixture",
      repoDescription = Nothing,
      entries = [silentEntry (Just "the artifact describes itself")]
    }

silentEntry :: Maybe T.Text -> DocEntry
silentEntry artifactDescription =
  DocEntry
    { name = "base",
      kind = DocModuleKind,
      version = Nothing,
      description = Nothing,
      tags = [],
      path = "modules/base",
      artifact = DocModuleArtifact (silentModuleArtifact artifactDescription),
      moduleRefs = []
    }

silentModuleArtifact :: Maybe T.Text -> Module
silentModuleArtifact description =
  Module
    { name = ModuleName "base",
      version = Nothing,
      description = description,
      vars = [],
      exports = [],
      prompts = [],
      steps = [],
      commands = [],
      dependencies = [],
      removal = Nothing,
      migrations = []
    }

invalidIdModel :: DocModel
invalidIdModel =
  DocModel
    { repoName = "fixture",
      repoDescription = Nothing,
      entries =
        [ moduleEntry "-bad" [] "modules/bad"
        ]
    }

moduleEntry :: T.Text -> [ModuleRef] -> FilePath -> DocEntry
moduleEntry name refs path =
  DocEntry
    { name = name,
      kind = DocModuleKind,
      version = Just "1.0.0",
      description = Just (name <> " module"),
      tags = ["module"],
      path = path,
      artifact = DocModuleArtifact (moduleArtifact name refs),
      moduleRefs = refs
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
      dependencies = [Dependency (ModuleName (ref ^. #name)) Map.empty | ref <- refs],
      removal = Nothing,
      migrations = []
    }

recipeEntry :: DocEntry
recipeEntry =
  DocEntry
    { name = "app-recipe",
      kind = DocRecipeKind,
      version = Just "0.1.0",
      description = Just "Recipe",
      tags = ["recipe"],
      path = "recipes/app-recipe",
      artifact =
        DocRecipeArtifact
          Recipe
            { name = RecipeName "app-recipe",
              version = Just "0.1.0",
              description = Just "Recipe",
              modules = [simpleDep "base", simpleDep "app"],
              vars = [],
              prompts = []
            },
      moduleRefs = [ModuleRef "base" True, ModuleRef "app" True]
    }

blueprintEntry :: DocEntry
blueprintEntry =
  DocEntry
    { name = "app-blueprint",
      kind = DocBlueprintKind,
      version = Just "0.1.0",
      description = Just "Blueprint",
      tags = ["blueprint"],
      path = "blueprints/app-blueprint",
      artifact =
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
              migrations = [],
              launch = Nothing,
              versionProbe = Nothing
            },
      moduleRefs = [ModuleRef "base" True]
    }

promptEntry :: DocEntry
promptEntry =
  DocEntry
    { name = "review",
      kind = DocPromptKind,
      version = Just "0.1.0",
      description = Just "Review prompt",
      tags = ["prompt"],
      path = "prompts/review",
      artifact =
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
              launch = Nothing,
              guidance = []
            },
      moduleRefs = []
    }
