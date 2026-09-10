module Seihou.OKF.Docs.RenderSpec (tests) where

import Control.Lens ((&), (?~), (^.))
import Data.Generics.Labels ()
import Data.List (sort)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Okf.Bundle qualified as Okf
import Okf.ConceptId qualified as Okf
import Okf.Validation (BundleValidationError (..), ValidationProfile (..))
import Seihou.Core.Migration
  ( BlueprintMigration (..),
    EntailedEdge (..),
    Migration (..),
    MigrationOp (..),
  )
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
    it "emits one concept per entry, plus the registry overview, with the documented id scheme" $ do
      (concepts, problems) <- renderOrFail testOptions wellFormedModel
      problems `shouldBe` []
      sort (Okf.renderConceptId . Okf.conceptIdOf <$> concepts)
        `shouldBe` [ "blueprints/app-blueprint",
                     "modules/app",
                     "modules/base",
                     "prompts/review",
                     "recipes/app-recipe",
                     "registry/fixture"
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

  describe "artifact features" $ do
    it "renders a variable declaration in full" $ do
      body <- requireBody "modules/rich" testOptions richModel
      body `shouldSatisfy` T.isInfixOf "- `project.name` — text, required, matching `[a-z]+`. The project name"
      body `shouldSatisfy` T.isInfixOf "- `license` — one of `MIT`, `BSD-3`, optional, default `MIT`"
      body `shouldSatisfy` T.isInfixOf "- `retries` — integer, optional, between 0 and 5"

    it "renders an export alias" $ do
      body <- requireBody "modules/rich" testOptions richModel
      body `shouldSatisfy` T.isInfixOf "- `project.name` as `app.name`"

    it "renders interactive prompts with choices and conditions" $ do
      body <- requireBody "modules/rich" testOptions richModel
      body `shouldSatisfy` T.isInfixOf "## Prompts"
      body
        `shouldSatisfy` T.isInfixOf
          "- `license` — Which license? (choices: `MIT`, `BSD-3`) — when `IsSet project.name`"

    it "renders generation steps with strategy, patch operation and condition" $ do
      body <- requireBody "modules/rich" testOptions richModel
      body `shouldSatisfy` T.isInfixOf "## Generation steps"
      body `shouldSatisfy` T.isInfixOf "- `Template` `flake.nix.tpl` → `flake.nix`"
      body
        `shouldSatisfy` T.isInfixOf
          "- `Copy` `gitignore.tpl` → `.gitignore` (appends one line to a file another module owns, if absent) — when `Eq license \"MIT\"`"

    it "renders commands with working directory and condition" $ do
      body <- requireBody "modules/rich" testOptions richModel
      body `shouldSatisfy` T.isInfixOf "## Commands"
      body `shouldSatisfy` T.isInfixOf "- `cabal build` in `app` — when `IsSet license`"

    it "renders the removal procedure" $ do
      body <- requireBody "modules/rich" testOptions richModel
      body `shouldSatisfy` T.isInfixOf "## Removal"
      body `shouldSatisfy` T.isInfixOf "- delete `flake.nix`"
      body `shouldSatisfy` T.isInfixOf "- strip this module's section from `.gitignore`"
      body `shouldSatisfy` T.isInfixOf "Then runs:"
      body `shouldSatisfy` T.isInfixOf "- `rm -rf dist-newstyle`"

    it "renders each module migration edge with its operations" $ do
      body <- requireBody "modules/rich" testOptions richModel
      body `shouldSatisfy` T.isInfixOf "## Migrations"
      body `shouldSatisfy` T.isInfixOf "### 0.1.0 → 0.2.0"
      body `shouldSatisfy` T.isInfixOf "- move `old.nix` → `new.nix`"
      body `shouldSatisfy` T.isInfixOf "### 0.2.0 → 0.3.0"
      body `shouldSatisfy` T.isInfixOf "- delete directory `legacy`"
      body `shouldSatisfy` T.isInfixOf "- run `just fmt` in `."

    it "omits sections the module declares nothing for" $ do
      body <- requireBody "modules/base" testOptions wellFormedModel
      body `shouldNotSatisfy` T.isInfixOf "## Migrations"
      body `shouldNotSatisfy` T.isInfixOf "## Removal"
      body `shouldNotSatisfy` T.isInfixOf "## Generation steps"

    it "shows the variable bindings a recipe supplies along each edge" $ do
      body <- requireBody "recipes/rich-recipe" testOptions richModel
      body `shouldSatisfy` T.isInfixOf "(with `license` = `MIT`, `project.name` = `demo`)"

    it "links an entailed edge whose blueprint is in the same registry" $ do
      body <- requireBody "blueprints/rich-blueprint" testOptions richModel
      body `shouldSatisfy` T.isInfixOf "Entails:"
      body `shouldSatisfy` T.isInfixOf "- [other-blueprint](/blueprints/other-blueprint.md) `1.9.0` → `2.0.0`"

    it "labels an entailed edge whose blueprint is outside the registry" $ do
      body <- requireBody "blueprints/rich-blueprint" testOptions richModel
      body `shouldSatisfy` T.isInfixOf "- `kiroku` `1.9.0` → `2.0.0` (declared outside this registry)"

    it "does not turn an out-of-registry entailed edge into a dangling reference" $ do
      (_, problems) <- renderOrFail testOptions richModel
      problems `shouldBe` []

    it "renders blueprint launch preferences and says what overrides them" $ do
      body <- requireBody "blueprints/rich-blueprint" testOptions richModel
      body `shouldSatisfy` T.isInfixOf "## Agent launch"
      body `shouldSatisfy` T.isInfixOf "- provider: `claude`"
      body `shouldSatisfy` T.isInfixOf "- model: `opus`"
      body `shouldSatisfy` T.isInfixOf "- effort: `high`"
      body `shouldSatisfy` T.isInfixOf "SEIHOU_AGENT_*"

    it "renders the version probe command and why it exists" $ do
      body <- requireBody "blueprints/rich-blueprint" testOptions richModel
      body `shouldSatisfy` T.isInfixOf "## Version probe"
      body `shouldSatisfy` T.isInfixOf "```bash\ncabal get-version\n```"
      body `shouldSatisfy` T.isInfixOf "reads no package-manager format"

    it "renders the blueprint tool allowlist" $ do
      body <- requireBody "blueprints/rich-blueprint" testOptions richModel
      body `shouldSatisfy` T.isInfixOf "## Tools"
      body `shouldSatisfy` T.isInfixOf "- `Bash`"

    it "keeps the whole agent prompt, not just its first paragraph" $ do
      body <- requireBody "blueprints/rich-blueprint" testOptions richModel
      body `shouldSatisfy` T.isInfixOf "Upgrade the project."
      body `shouldSatisfy` T.isInfixOf "```text\nUpgrade the project.\n\nBe careful.\n```"

    it "renders command-derived variables" $ do
      body <- requireBody "prompts/rich-prompt" testOptions richModel
      body `shouldSatisfy` T.isInfixOf "## Command variables"
      body
        `shouldSatisfy` T.isInfixOf
          "- `head.sha` — runs `git rev-parse HEAD` in `.`, trimmed, capped at 64 bytes — when `IsSet license`"

    it "renders conditional guidance blocks" $ do
      body <- requireBody "prompts/rich-prompt" testOptions richModel
      body `shouldSatisfy` T.isInfixOf "## Guidance"
      body `shouldSatisfy` T.isInfixOf "### Formatting"
      body `shouldSatisfy` T.isInfixOf "Run the formatter before finishing."
      body `shouldSatisfy` T.isInfixOf "Applies when `Eq license \"MIT\"`."

  describe "registry overview concept" $ do
    it "emits one concept describing the registry itself" $ do
      (concepts, _) <- renderOrFail testOptions wellFormedModel
      sort (Okf.renderConceptId . Okf.conceptIdOf <$> concepts)
        `shouldSatisfy` elem "registry/fixture"

    it "links every artifact from the registry concept, grouped by kind" $ do
      body <- requireBody "registry/fixture" testOptions wellFormedModel
      body `shouldSatisfy` T.isInfixOf "## Modules"
      body `shouldSatisfy` T.isInfixOf "](/modules/base.md)"
      body `shouldSatisfy` T.isInfixOf "## Recipes"
      body `shouldSatisfy` T.isInfixOf "](/recipes/app-recipe.md)"
      body `shouldSatisfy` T.isInfixOf "## Blueprints"
      body `shouldSatisfy` T.isInfixOf "](/blueprints/app-blueprint.md)"
      body `shouldSatisfy` T.isInfixOf "## Prompts"
      body `shouldSatisfy` T.isInfixOf "](/prompts/review.md)"

    it "omits a kind section the registry publishes nothing for" $ do
      body <- requireBody "registry/fixture" testOptions danglingModel
      body `shouldNotSatisfy` T.isInfixOf "## Recipes"

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

-- | The rendered Markdown body of one concept, which is where every section
-- assertion above looks.
requireBody :: T.Text -> RenderOptions -> DocModel -> IO T.Text
requireBody rawId opts model = Okf.serializeConcept <$> requireConcept rawId opts model

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
      moduleRefs = [],
      entailedRefs = []
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
      moduleRefs = refs,
      entailedRefs = []
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
      moduleRefs = [ModuleRef "base" True, ModuleRef "app" True],
      entailedRefs = []
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
      moduleRefs = [ModuleRef "base" True],
      entailedRefs = []
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
      moduleRefs = [],
      entailedRefs = []
    }

-- | A registry whose artifacts declare every feature the renderer now covers,
-- including the four -- entailment, launch preferences, a version probe, and
-- command-derived variables -- that no real registry on this machine exercises.
richModel :: DocModel
richModel =
  DocModel
    { repoName = "fixture",
      repoDescription = Just "Fixture",
      entries = [richModuleEntry, richRecipeEntry, richBlueprintEntry, otherBlueprintEntry, richPromptEntry]
    }

richModuleEntry :: DocEntry
richModuleEntry =
  DocEntry
    { name = "rich",
      kind = DocModuleKind,
      version = Just "0.3.0",
      description = Just "A module that declares everything",
      tags = ["module"],
      path = "modules/rich",
      artifact = DocModuleArtifact richModule,
      moduleRefs = [],
      entailedRefs = []
    }

richModule :: Module
richModule =
  Module
    { name = ModuleName "rich",
      version = Just "0.3.0",
      description = Just "A module that declares everything",
      vars =
        [ VarDecl
            { name = "project.name",
              type_ = VTText,
              default_ = Nothing,
              description = Just "The project name",
              required = True,
              validation = Just (ValPattern "[a-z]+")
            },
          VarDecl
            { name = "license",
              type_ = VTChoice ["MIT", "BSD-3"],
              default_ = Just (VText "MIT"),
              description = Nothing,
              required = False,
              validation = Nothing
            },
          VarDecl
            { name = "retries",
              type_ = VTInt,
              default_ = Nothing,
              description = Nothing,
              required = False,
              validation = Just (ValRange 0 5)
            }
        ],
      exports = [VarExport {var = "project.name", alias = Just "app.name"}],
      prompts =
        [ Prompt
            { var = "license",
              text = "Which license?",
              condition = Just (ExprIsSet "project.name"),
              choices = Just ["MIT", "BSD-3"]
            }
        ],
      steps =
        [ Step
            { strategy = Template,
              src = "flake.nix.tpl",
              dest = "flake.nix",
              condition = Nothing,
              patch = Nothing
            },
          Step
            { strategy = Copy,
              src = "gitignore.tpl",
              dest = ".gitignore",
              condition = Just (ExprEq "license" (VText "MIT")),
              patch = Just AppendLineIfAbsent
            }
        ],
      commands =
        [ Command
            { run = "cabal build",
              workDir = Just "app",
              condition = Just (ExprIsSet "license")
            }
        ],
      dependencies = [],
      removal =
        Just
          Removal
            { steps =
                [ RemovalStep {action = RemoveFileAction, dest = "flake.nix", src = Nothing},
                  RemovalStep {action = RemoveSectionAction, dest = ".gitignore", src = Nothing}
                ],
              commands =
                [Command {run = "rm -rf dist-newstyle", workDir = Nothing, condition = Nothing}]
            },
      migrations =
        [ Migration
            { from = "0.1.0",
              to = "0.2.0",
              ops = [MoveFile {src = "old.nix", dest = "new.nix"}]
            },
          Migration
            { from = "0.2.0",
              to = "0.3.0",
              ops =
                [ DeleteDir {path = "legacy"},
                  RunCommand {run = "just fmt", workDir = Just "."}
                ]
            }
        ]
    }

richRecipeEntry :: DocEntry
richRecipeEntry =
  DocEntry
    { name = "rich-recipe",
      kind = DocRecipeKind,
      version = Nothing,
      description = Just "A recipe that preconfigures its modules",
      tags = [],
      path = "recipes/rich-recipe",
      artifact =
        DocRecipeArtifact
          Recipe
            { name = RecipeName "rich-recipe",
              version = Nothing,
              description = Just "A recipe that preconfigures its modules",
              modules =
                [ Dependency
                    { module_ = ModuleName "rich",
                      vars = Map.fromList [("project.name", "demo"), ("license", "MIT")]
                    }
                ],
              vars = [],
              prompts = []
            },
      moduleRefs = [ModuleRef "rich" True],
      entailedRefs = []
    }

richBlueprintEntry :: DocEntry
richBlueprintEntry =
  DocEntry
    { name = "rich-blueprint",
      kind = DocBlueprintKind,
      version = Nothing,
      description = Just "A blueprint that declares everything",
      tags = [],
      path = "blueprints/rich-blueprint",
      artifact = DocBlueprintArtifact richBlueprint,
      moduleRefs = [],
      -- One entailed edge resolves inside this registry and one does not, which
      -- is the distinction the renderer has to honour.
      entailedRefs =
        [ EntailedRef {blueprint = "other-blueprint", from = "1.9.0", to = "2.0.0", resolved = True},
          EntailedRef {blueprint = "kiroku", from = "1.9.0", to = "2.0.0", resolved = False}
        ]
    }

richBlueprint :: Blueprint
richBlueprint =
  Blueprint
    { name = ModuleName "rich-blueprint",
      version = Nothing,
      description = Just "A blueprint that declares everything",
      prompt = "Upgrade the project.\n\nBe careful.",
      vars = [],
      prompts = [],
      baseModules = [],
      files = [],
      allowedTools = Just ["Bash", "Read"],
      tags = [],
      migrations =
        [ BlueprintMigration
            { from = "2.4.0",
              to = "3.0.0",
              prompt = "Cross the breaking change.",
              entails =
                [ EntailedEdge {blueprint = "other-blueprint", from = "1.9.0", to = "2.0.0"},
                  EntailedEdge {blueprint = "kiroku", from = "1.9.0", to = "2.0.0"}
                ]
            }
        ],
      launch =
        Just
          AgentLaunch
            { provider = Just "claude",
              model = Just "opus",
              effort = Just "high",
              mode = Nothing
            },
      versionProbe = Just "cabal get-version"
    }

-- | The blueprint the rich blueprint entails, so that one entailed edge has a
-- target inside the bundle to link to.
otherBlueprintEntry :: DocEntry
otherBlueprintEntry =
  DocEntry
    { name = "other-blueprint",
      kind = DocBlueprintKind,
      version = Nothing,
      description = Just "The entailed blueprint",
      tags = [],
      path = "blueprints/other-blueprint",
      artifact =
        DocBlueprintArtifact
          Blueprint
            { name = ModuleName "other-blueprint",
              version = Nothing,
              description = Just "The entailed blueprint",
              prompt = "Do the other thing.",
              vars = [],
              prompts = [],
              baseModules = [],
              files = [],
              allowedTools = Nothing,
              tags = [],
              migrations = [],
              launch = Nothing,
              versionProbe = Nothing
            },
      moduleRefs = [],
      entailedRefs = []
    }

richPromptEntry :: DocEntry
richPromptEntry =
  DocEntry
    { name = "rich-prompt",
      kind = DocPromptKind,
      version = Nothing,
      description = Just "A prompt that declares everything",
      tags = [],
      path = "prompts/rich-prompt",
      artifact =
        DocPromptArtifact
          AgentPrompt
            { name = ModuleName "rich-prompt",
              version = Nothing,
              description = Just "A prompt that declares everything",
              prompt = "Review the change.",
              vars = [],
              prompts = [],
              commandVars =
                [ CommandVar
                    { name = "head.sha",
                      run = "git rev-parse HEAD",
                      workDir = Just ".",
                      condition = Just (ExprIsSet "license"),
                      trim = True,
                      maxBytes = Just 64
                    }
                ],
              guidance =
                [ PromptGuidance
                    { title = "Formatting",
                      body = "Run the formatter before finishing.",
                      condition = Just (ExprEq "license" (VText "MIT"))
                    }
                ],
              files = [],
              allowedTools = Nothing,
              tags = [],
              launch = Nothing
            },
      moduleRefs = [],
      entailedRefs = []
    }
