module Seihou.OKF.Docs.ModelSpec (tests) where

import Data.List (find)
import Data.Maybe (fromMaybe)
import Data.Text qualified as T
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
    it "loads all four registry entry kinds from a fixture registry" $ do
      withFixtureRegistry $ \registryDir -> do
        model <- shouldLoad registryDir
        model.docRepoName `shouldBe` "fixture-registry"
        length (entriesByKind DocModuleKind model) `shouldBe` 3
        length (entriesByKind DocRecipeKind model) `shouldBe` 1
        length (entriesByKind DocBlueprintKind model) `shouldBe` 1
        length (entriesByKind DocPromptKind model) `shouldBe` 1

    it "keeps catalog metadata from the registry entry" $ do
      withFixtureRegistry $ \registryDir -> do
        model <- shouldLoad registryDir
        let entry = requireEntry "app" model
        entry.entryVersion `shouldBe` Just "1.2.3"
        entry.entryDescription `shouldBe` Just "Application module"
        entry.entryTags `shouldBe` ["haskell", "app"]
        entry.entryPath `shouldBe` "modules/app"

    it "marks module dependencies that resolve inside the registry" $ do
      withFixtureRegistry $ \registryDir -> do
        model <- shouldLoad registryDir
        let entry = requireEntry "app" model
        entry.entryModuleRefs `shouldContain` [ModuleRef "base" True]

    it "marks module dependencies that do not resolve inside the registry" $ do
      withFixtureRegistry $ \registryDir -> do
        model <- shouldLoad registryDir
        let entry = requireEntry "dangling" model
        entry.entryModuleRefs `shouldBe` [ModuleRef "missing" False]

    it "captures recipe and blueprint module references" $ do
      withFixtureRegistry $ \registryDir -> do
        model <- shouldLoad registryDir
        let recipe = requireEntry "app-recipe" model
            blueprint = requireEntry "app-blueprint" model
        recipe.entryModuleRefs `shouldMatchList` [ModuleRef "base" True, ModuleRef "app" True]
        blueprint.entryModuleRefs `shouldBe` [ModuleRef "base" True]

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
  filter (\entry -> entry.entryKind == kind) model.docEntries

requireEntry :: String -> DocModel -> DocEntry
requireEntry name model =
  fromMaybe (error ("missing entry " <> name)) $
    find (\entry -> entry.entryName == T.pack name) model.docEntries

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
  writePrompt registryDir

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
  \, blueprints = [ { name = \"app-blueprint\", version = Some \"0.1.0\", path = \"blueprints/app-blueprint\", description = Some \"Blueprint\", tags = [ \"blueprint\" ] } ]\n\
  \, prompts = [ { name = \"review\", version = Some \"0.1.0\", path = \"prompts/review\", description = Some \"Review prompt\", tags = [ \"prompt\" ] } ]\n\
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
