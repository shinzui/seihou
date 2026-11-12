module Seihou.OKF.Docs.ModelSpec (tests, writeCurrentFixtureRegistry) where

import Control.Lens ((^.))
import Data.Generics.Labels ()
import Data.List (find)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.OKF.Docs.Model
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.OKF.Docs.Model" spec

spec :: Spec
spec = do
  describe "loadDocModel" $ do
    it "loads all five registry entry kinds from a fixture registry" $ do
      withFixtureRegistry $ \registryDir -> do
        model <- shouldLoad registryDir
        (model ^. #repoName) `shouldBe` "fixture-registry"
        length (entriesByKind DocModuleKind model) `shouldBe` 3
        length (entriesByKind DocRecipeKind model) `shouldBe` 1
        length (entriesByKind DocBlueprintKind model) `shouldBe` 2
        length (entriesByKind DocPromptKind model) `shouldBe` 1
        length (entriesByKind DocJudgementKind model) `shouldBe` 1

    it "keeps catalog metadata from the registry entry" $ do
      withFixtureRegistry $ \registryDir -> do
        model <- shouldLoad registryDir
        let entry = requireEntry "app" model
        (entry ^. #version) `shouldBe` Just "1.2.3"
        (entry ^. #description) `shouldBe` Just "Application module"
        (entry ^. #tags) `shouldBe` ["haskell", "app"]
        (entry ^. #path) `shouldBe` "modules/app"

    it "marks module dependencies that resolve inside the registry" $ do
      withFixtureRegistry $ \registryDir -> do
        model <- shouldLoad registryDir
        let entry = requireEntry "app" model
        (entry ^. #moduleRefs) `shouldContain` [ModuleRef "base" Nothing Map.empty True]

    it "marks module dependencies that do not resolve inside the registry" $ do
      withFixtureRegistry $ \registryDir -> do
        model <- shouldLoad registryDir
        let entry = requireEntry "dangling" model
        (entry ^. #moduleRefs) `shouldBe` [ModuleRef "missing" Nothing Map.empty False]

    it "captures recipe and blueprint module references" $ do
      withFixtureRegistry $ \registryDir -> do
        model <- shouldLoad registryDir
        let recipe = requireEntry "app-recipe" model
            blueprint = requireEntry "app-blueprint" model
        (recipe ^. #moduleRefs) `shouldMatchList` [ModuleRef "base" Nothing Map.empty True, ModuleRef "app" Nothing Map.empty True]
        (blueprint ^. #moduleRefs) `shouldBe` [ModuleRef "base" Nothing Map.empty True]

    it "retains an external base reference without fetching it or requiring installed members" $
      withFixtureRegistry $ \registryDir -> do
        let path = registryDir </> "recipes/app-recipe/recipe.dhall"
        TIO.writeFile path ("(" <> T.pack recipeDhall <> ") // {extends=Some {recipe=\"external\",source=Some \"https://example.invalid/base.git\",versionRange=Some {minimum=\"1\",before=\"2\"}}}")
        model <- shouldLoad registryDir
        case requireEntry "app-recipe" model ^. #baseRecipe of
          Nothing -> expectationFailure "missing base relationship"
          Just base -> do
            base ^. #resolved `shouldBe` False
            base ^. #reference . #source `shouldBe` Just "https://example.invalid/base.git"
            base ^. #reference . #recipe `shouldBe` "external"

    it "retains source-qualified edges and judgement references without resolving local shadows" $
      withSystemTempDirectory "seihou-current-model" $ \registryDir -> do
        writeCurrentFixtureRegistry registryDir
        model <- shouldLoad registryDir
        let app = requireEntry "app" model
            recipe = requireEntry "app-recipe" model
            blueprint = requireEntry "app-blueprint" model
        app ^. #moduleRefs `shouldBe` [ModuleRef "base" (Just "https://example.invalid/modules.git") (Map.singleton "literal" "a|`b`") False]
        map (^. #resolved) (app ^. #judgementRefs) `shouldBe` [True, False, False]
        map (^. #resolved) (recipe ^. #judgementRefs) `shouldBe` [True, False, False]
        map (^. #resolved) (recipe ^. #moduleRefs) `shouldBe` [True, False]
        map (^. #resolved) (blueprint ^. #moduleRefs) `shouldBe` [False]
        fmap (^. #resolved) (recipe ^. #baseRecipe) `shouldBe` Just False

    it "resolves an entailed edge naming a blueprint in the same registry" $ do
      withFixtureRegistry $ \registryDir -> do
        model <- shouldLoad registryDir
        let entry = requireEntry "entailing-blueprint" model
        (entry ^. #entailedRefs)
          `shouldContain` [ EntailedRef
                              { blueprint = "app-blueprint",
                                from = "1.0.0",
                                to = "2.0.0",
                                resolved = True
                              }
                          ]

    it "leaves an entailed edge naming a blueprint outside the registry unresolved" $ do
      withFixtureRegistry $ \registryDir -> do
        model <- shouldLoad registryDir
        let entry = requireEntry "entailing-blueprint" model
        (entry ^. #entailedRefs)
          `shouldContain` [ EntailedRef
                              { blueprint = "kiroku",
                                from = "1.9.0",
                                to = "2.0.0",
                                resolved = False
                              }
                          ]

    it "records no entailed edges for a blueprint that declares none" $ do
      withFixtureRegistry $ \registryDir -> do
        model <- shouldLoad registryDir
        (requireEntry "app-blueprint" model ^. #entailedRefs) `shouldBe` []

    it "records no entailed edges for kinds that cannot declare them" $ do
      withFixtureRegistry $ \registryDir -> do
        model <- shouldLoad registryDir
        (requireEntry "app" model ^. #entailedRefs) `shouldBe` []
        (requireEntry "app-recipe" model ^. #entailedRefs) `shouldBe` []
        (requireEntry "review" model ^. #entailedRefs) `shouldBe` []

    it "returns RegistryNotFound when the registry file is absent" $ do
      withSystemTempDirectory "seihou-doc-model-missing" $ \registryDir -> do
        result <- loadDocModel registryDir
        result `shouldBe` Left (RegistryNotFound (registryDir </> "seihou-registry.dhall"))

shouldLoad :: FilePath -> IO DocModel
shouldLoad registryDir = do
  result <- loadDocModel registryDir
  case result of
    Left err -> do
      expectationFailure ("Expected Right, got Left: " <> show err)
      error "unreachable"
    Right model -> pure model

entriesByKind :: DocKind -> DocModel -> [DocEntry]
entriesByKind kind model =
  filter (\entry -> entry ^. #kind == kind) (model ^. #entries)

requireEntry :: String -> DocModel -> DocEntry
requireEntry name model =
  fromMaybe (error ("missing entry " <> name)) $
    find (\entry -> entry ^. #name == T.pack name) (model ^. #entries)

withFixtureRegistry :: (FilePath -> IO a) -> IO a
withFixtureRegistry action =
  withSystemTempDirectory "seihou-doc-model" $ \registryDir -> do
    writeFixtureRegistry registryDir
    action registryDir

writeFixtureRegistry :: FilePath -> IO ()
writeFixtureRegistry registryDir = do
  writeFile (registryDir </> "seihou-registry.dhall") registryDhall
  writeModule registryDir "modules/base" "base" [] "Base module"
  writeModule registryDir "modules/app" "app" ["base"] "Application module"
  writeModule registryDir "modules/dangling" "dangling" ["missing"] "Dangling module"
  writeRecipe registryDir
  writeBlueprint registryDir
  writeEntailingBlueprint registryDir
  writePrompt registryDir
  createDirectoryIfMissing True (registryDir </> "judgements/docs-review")
  writeFile (registryDir </> "judgements/docs-review/judgement.dhall") judgementDhall

writeModule :: FilePath -> FilePath -> String -> [String] -> String -> IO ()
writeModule registryDir relDir name dependencies description = do
  createDirectoryIfMissing True (registryDir </> relDir)
  writeFile (registryDir </> relDir </> "module.dhall") (moduleDhall name dependencies description)

writeRecipe :: FilePath -> IO ()
writeRecipe registryDir = do
  let relDir = "recipes/app-recipe"
  createDirectoryIfMissing True (registryDir </> relDir)
  writeFile (registryDir </> relDir </> "recipe.dhall") recipeDhall

writeBlueprint :: FilePath -> IO ()
writeBlueprint registryDir = do
  let relDir = "blueprints/app-blueprint"
  createDirectoryIfMissing True (registryDir </> relDir)
  writeFile (registryDir </> relDir </> "blueprint.dhall") blueprintDhall

-- | A blueprint whose one migration edge entails two edges: one of a blueprint
-- listed in this registry, and one of a blueprint that is not.
writeEntailingBlueprint :: FilePath -> IO ()
writeEntailingBlueprint registryDir = do
  let relDir = "blueprints/entailing-blueprint"
  createDirectoryIfMissing True (registryDir </> relDir)
  writeFile (registryDir </> relDir </> "blueprint.dhall") entailingBlueprintDhall

writePrompt :: FilePath -> IO ()
writePrompt registryDir = do
  let relDir = "prompts/review"
  createDirectoryIfMissing True (registryDir </> relDir)
  writeFile (registryDir </> relDir </> "prompt.dhall") promptDhall

registryDhall :: String
registryDhall =
  "{ repoName = \"fixture-registry\"\n\
  \, repoDescription = Some \"Fixture registry\"\n\
  \, modules =\n\
  \  [ { name = \"base\", version = Some \"1.0.0\", path = \"modules/base\", description = Some \"Base module\", tags = [ \"haskell\" ] }\n\
  \  , { name = \"app\", version = Some \"1.2.3\", path = \"modules/app\", description = Some \"Application module\", tags = [ \"haskell\", \"app\" ] }\n\
  \  , { name = \"dangling\", version = None Text, path = \"modules/dangling\", description = Some \"Dangling module\", tags = [] : List Text }\n\
  \  ]\n\
  \, recipes = [ { name = \"app-recipe\", version = Some \"0.1.0\", path = \"recipes/app-recipe\", description = Some \"Recipe\", tags = [ \"recipe\" ] } ]\n\
  \, blueprints =\n\
  \  [ { name = \"app-blueprint\", version = Some \"0.1.0\", path = \"blueprints/app-blueprint\", description = Some \"Blueprint\", tags = [ \"blueprint\" ] }\n\
  \  , { name = \"entailing-blueprint\", version = Some \"0.1.0\", path = \"blueprints/entailing-blueprint\", description = Some \"Entailing blueprint\", tags = [] : List Text }\n\
  \  ]\n\
  \, prompts = [ { name = \"review\", version = Some \"0.1.0\", path = \"prompts/review\", description = Some \"Review prompt\", tags = [ \"prompt\" ] } ]\n\
  \, judgements = [ { name = \"docs-review\", version = Some \"1.0.0\", path = \"judgements/docs-review\", description = Some \"Docs review\", tags = [] : List Text } ]\n\
  \}"

moduleDhall :: String -> [String] -> String -> String
moduleDhall name dependencies description =
  "{ name = \""
    <> name
    <> "\"\n\
       \, version = Some \"1.0.0\"\n\
       \, description = Some \""
    <> description
    <> "\"\n\
       \, vars = [] : "
    <> varDeclListType
    <> "\n\
       \, exports = [] : "
    <> varExportListType
    <> "\n\
       \, prompts = [] : "
    <> promptListType
    <> "\n\
       \, steps = [] : "
    <> stepListType
    <> "\n\
       \, commands = [] : "
    <> commandListType
    <> "\n\
       \, dependencies = "
    <> dependencyList dependencies
    <> "\n\
       \}"

recipeDhall :: String
recipeDhall =
  "{ name = \"app-recipe\"\n\
  \, version = Some \"0.1.0\"\n\
  \, description = Some \"Recipe\"\n\
  \, modules = [ \"base\", \"app\" ]\n\
  \, vars = [] : "
    <> varDeclListType
    <> "\n\
       \, prompts = [] : "
    <> promptListType
    <> "\n\
       \}"

blueprintDhall :: String
blueprintDhall =
  "{ name = \"app-blueprint\"\n\
  \, version = Some \"0.1.0\"\n\
  \, description = Some \"Blueprint\"\n\
  \, prompt = \"Build the app\"\n\
  \, vars = [] : "
    <> varDeclListType
    <> "\n\
       \, prompts = [] : "
    <> promptListType
    <> "\n\
       \, baseModules = [ \"base\" ]\n\
       \, files = [] : "
    <> blueprintFileListType
    <> "\n\
       \, allowedTools = None (List Text)\n\
       \, tags = [ \"blueprint\" ]\n\
       \}"

entailingBlueprintDhall :: String
entailingBlueprintDhall =
  "{ name = \"entailing-blueprint\"\n\
  \, version = Some \"0.1.0\"\n\
  \, description = Some \"Entailing blueprint\"\n\
  \, prompt = \"Upgrade\"\n\
  \, vars = [] : "
    <> varDeclListType
    <> "\n\
       \, prompts = [] : "
    <> promptListType
    <> "\n\
       \, baseModules = [] : List Text\n\
       \, files = [] : "
    <> blueprintFileListType
    <> "\n\
       \, allowedTools = None (List Text)\n\
       \, tags = [] : List Text\n\
       \, migrations =\n\
       \  [ { from = \"2.4.0\"\n\
       \    , to = \"3.0.0\"\n\
       \    , prompt = \"Cross it\"\n\
       \    , entails =\n\
       \      [ { blueprint = \"app-blueprint\", from = \"1.0.0\", to = \"2.0.0\" }\n\
       \      , { blueprint = \"kiroku\", from = \"1.9.0\", to = \"2.0.0\" }\n\
       \      ]\n\
       \    }\n\
       \  ]\n\
       \}"

promptDhall :: String
promptDhall =
  "{ name = \"review\"\n\
  \, version = Some \"0.1.0\"\n\
  \, description = Some \"Review prompt\"\n\
  \, prompt = \"Review the change\"\n\
  \, vars = [] : "
    <> varDeclListType
    <> "\n\
       \, prompts = [] : "
    <> promptListType
    <> "\n\
       \, commandVars = [] : "
    <> commandVarListType
    <> "\n\
       \, files = [] : "
    <> blueprintFileListType
    <> "\n\
       \, allowedTools = None (List Text)\n\
       \, tags = [ \"prompt\" ]\n\
       \, launch = None { provider : Optional Text, mode : Optional Text, model : Optional Text }\n\
       \}"

dependencyList :: [String] -> String
dependencyList [] = "[] : List Text"
dependencyList deps = "[ " <> joinComma (map show deps) <> " ]"

joinComma :: [String] -> String
joinComma [] = ""
joinComma [x] = x
joinComma (x : xs) = x <> ", " <> joinComma xs

varDeclListType :: String
varDeclListType =
  "List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }"

varExportListType :: String
varExportListType =
  "List { var : Text, alias : Optional Text }"

promptListType :: String
promptListType =
  "List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }"

stepListType :: String
stepListType =
  "List { strategy : Text, src : Text, dest : Text, when : Optional Text, patch : Optional Text }"

commandListType :: String
commandListType =
  "List { run : Text, workDir : Optional Text, when : Optional Text }"

blueprintFileListType :: String
blueprintFileListType =
  "List { src : Text, description : Optional Text }"

commandVarListType :: String
commandVarListType =
  "List { name : Text, run : Text, workDir : Optional Text, when : Optional Text, trim : Bool, maxBytes : Optional Natural }"

-- | A judgement written out in full, without the schema package.
judgementDhall :: String
judgementDhall =
  "let Answer = < Yes | No > let Enforcement = < Enforced | Advisory > let Severity = < Info | Low | Medium | High | Critical >\n\
  \let Scope = < StagedChanges | CommitRange > let Det = < SecretScan >\n\
  \in\n\
  \{ name = \"docs-review\", version = Some \"1.0.0\", description = Some \"Docs review\", instructions = \"Review documentation.\"\n\
  \   , evidence = { scopes = [ Scope.StagedChanges ], include = [ \"docs/**\" ], exclude = [] : List Text }\n\
  \   , limits = { maxFileBytes = 262144, maxChunkBytes = 49152, maxChunks = 16, maxAttempts = 3, timeoutSeconds = 120, maxFindings = 20 }\n\
  \   , deterministicChecks = [] : List Det\n\
  \   , checks = [ { name = \"stale-docs\", question = \"Does this change leave documented behaviour out of date?\", concernWhen = Answer.Yes, yesMeans = None Text, noMeans = None Text\n\
  \              , categories = [ { name = \"stale\", severity = Severity.Medium, description = None Text } ], enforcement = Enforcement.Enforced, blockingSeverity = Severity.High\n\
  \              , blockAt = 0.7, passAt = 0.3, gateBlockAt = 0.9, gatePassAt = 0.05, useGate = True } ] }\n"

-- | Current declarations layered over the older standalone descriptors. None
-- of the command strings should execute while loading or generating docs.
writeCurrentFixtureRegistry :: FilePath -> IO ()
writeCurrentFixtureRegistry registryDir = do
  writeFixtureRegistry registryDir
  overlay "modules/app/module.dhall" "let Op = < MoveFile : { src : Text, dest : Text } | MoveDir : { src : Text, dest : Text } | DeleteFile : { path : Text } | DeleteDir : { path : Text } | RemoveLine : { path : Text, line : Text } | RunCommand : { run : Text, workDir : Optional Text } >\nlet Action = < Apply : Text | Checkout : Text >\nin { dependencies = [ { module = \"base\", source = Some \"https://example.invalid/modules.git\", vars = [ {name=\"literal\",value=\"a|`b`\"} ] } ]\n, judgements = [ { name = \"docs-review\", source = None Text, when = Some \"IsSet project.name\" }, { name = \"docs-review\", source = Some \"https://example.invalid/reviews.git\", when = None Text }, { name = \"catalogue-review\", source = None Text, when = None Text } ]\n, steps = [ {strategy=\"template\",src=\"managed.tpl\",dest=\"managed\",when=None Text,patch=None Text,lifecycle=Some \"managed\"}, {strategy=\"template\",src=\"seed.tpl\",dest=\"seed\",when=None Text,patch=None Text,lifecycle=Some \"seed\"}, {strategy=\"symlink\",src=\"files\",dest=\"linked\",when=None Text,patch=None Text,lifecycle=Some \"checkout\"} ]\n, commands = [ {action=Action.Checkout \"touch SHOULD-NOT-EXIST\",workDir=None Text,when=None Text} ]\n, migrations = [ {from=\"1\",to=\"2\",ops=[Op.RemoveLine {path=\".gitignore\",line=\"exact|`literal`\"}]} ]\n}"
  overlay "recipes/app-recipe/recipe.dhall" "{ modules = [ { module = \"base\", source = None Text, vars = [] : List {name : Text,value : Text} }, { module = \"base\", source = Some \"https://example.invalid/modules.git\", vars = [] : List {name : Text,value : Text} } ]\n, extends = Some { recipe = \"app-recipe\", source = Some \"https://example.invalid/recipes.git\", versionRange = Some {minimum=\"1\",before=\"2\"} }\n, moduleOverrides = [ { module = \"inherited\", vars = [ {name=\"literal\",value=\"a|`b`\"} ] } ]\n, promptOverrides = [ {var=\"inherited\",text=\"First line\\n```text\\nsecond | line\",when=None Text,choices=None (List Text)} ]\n, judgements = [ { name = \"docs-review\", source = None Text, when = Some \"IsSet project.name\" }, { name = \"docs-review\", source = Some \"https://example.invalid/reviews.git\", when = None Text }, { name = \"catalogue-review\", source = None Text, when = None Text } ] }"
  overlay "blueprints/app-blueprint/blueprint.dhall" "{ baseModules = [ { module = \"base\", source = Some \"https://example.invalid/modules.git\", vars = [] : List {name : Text,value : Text} } ], allowedTools=Some ([] : List Text), prompt=\"First line\\n```text\\nsecond | line\",versionProbe=Some \"touch SHOULD-NOT-EXIST\\n```\",launch=Some {provider=Some \"test\",model=Some \"model\",effort=Some \"high\",mode=Some \"reserved\"} }"
  let judgementPath = registryDir </> "judgements/docs-review/judgement.dhall"
  judgement <- TIO.readFile judgementPath
  TIO.writeFile
    judgementPath
    ( T.replace
        "yesMeans = None Text"
        "yesMeans = Some \"Documentation is stale\""
        ( T.replace
            "noMeans = None Text"
            "noMeans = Some \"Documentation matches\""
            ( T.replace
                "description = None Text"
                "description = Some \"Category explanation\""
                (T.replace "useGate = True" "useGate = False" judgement)
            )
        )
    )
  where
    overlay relative fields = do
      let path = registryDir </> relative
      old <- TIO.readFile path
      TIO.writeFile path ("(" <> old <> ") // (" <> fields <> ")")
