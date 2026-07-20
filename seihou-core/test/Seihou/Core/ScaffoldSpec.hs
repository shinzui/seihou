module Seihou.Core.ScaffoldSpec (tests) where

import Data.Text qualified as T
import Seihou.Core.AgentPrompt (validateAgentPrompt)
import Seihou.Core.Blueprint (validateBlueprint)
import Seihou.Core.Module (validateModule)
import Seihou.Core.Scaffold (blueprintDhall, exampleAgentPromptMarkdown, examplePromptMarkdown, moduleDhall, promptDhall, readmeTemplate)
import Seihou.Core.Types
import Seihou.Dhall.Eval (evalAgentPromptFromFile, evalBlueprintFromFile, evalModuleFromFile)
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, makeAbsolute)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Core.Scaffold" spec

-- | Resolve the local schema path for tests, trying both package-relative and
-- project root-relative locations (like mori's fixturePath pattern).
-- Uses an absolute path since generated Dhall is written to a temp directory.
resolveSchemaPath :: IO T.Text
resolveSchemaPath = do
  let pkgRelative = "../schema/package.dhall"
      rootRelative = "schema/package.dhall"
  pkgExists <- doesDirectoryExist "../schema"
  path <-
    if pkgExists
      then makeAbsolute pkgRelative
      else makeAbsolute rootRelative
  pure (T.pack path)

spec :: Spec
spec = do
  describe "moduleDhall" $ do
    it "generates Dhall that includes schema import" $ do
      schemaPath <- resolveSchemaPath
      let content = moduleDhall "test-mod" schemaPath ""
      T.isInfixOf "let S =" content `shouldBe` True
      T.isInfixOf "S.Module::" content `shouldBe` True

    it "generates Dhall that loads via evalModuleFromFile" $ do
      schemaPath <- resolveSchemaPath
      withSystemTempDirectory "seihou-scaffold-test" $ \tmpDir -> do
        let modDir = tmpDir </> "test-mod"
            dhallFile = modDir </> "module.dhall"
            filesDir = modDir </> "files"
        createDirectoryIfMissing True filesDir
        writeFile dhallFile (T.unpack (moduleDhall "test-mod" schemaPath ""))
        writeFile (filesDir </> "README.md.tpl") (T.unpack readmeTemplate)
        result <- evalModuleFromFile dhallFile
        case result of
          Left err -> expectationFailure $ "Failed to load generated module: " ++ show err
          Right m -> m.name `shouldBe` "test-mod"

    it "generates a module that passes validateModule" $ do
      schemaPath <- resolveSchemaPath
      withSystemTempDirectory "seihou-scaffold-test" $ \tmpDir -> do
        let modDir = tmpDir </> "test-mod"
            dhallFile = modDir </> "module.dhall"
            filesDir = modDir </> "files"
        createDirectoryIfMissing True filesDir
        writeFile dhallFile (T.unpack (moduleDhall "test-mod" schemaPath ""))
        writeFile (filesDir </> "README.md.tpl") (T.unpack readmeTemplate)
        result <- evalModuleFromFile dhallFile
        case result of
          Left err -> expectationFailure $ "Failed to load: " ++ show err
          Right m -> do
            validated <- validateModule modDir m
            case validated of
              Left err -> expectationFailure $ "Validation failed: " ++ show err
              Right _ -> pure ()

    it "generates expected module structure" $ do
      schemaPath <- resolveSchemaPath
      withSystemTempDirectory "seihou-scaffold-test" $ \tmpDir -> do
        let modDir = tmpDir </> "test-mod"
            dhallFile = modDir </> "module.dhall"
            filesDir = modDir </> "files"
        createDirectoryIfMissing True filesDir
        writeFile dhallFile (T.unpack (moduleDhall "test-mod" schemaPath ""))
        writeFile (filesDir </> "README.md.tpl") (T.unpack readmeTemplate)
        result <- evalModuleFromFile dhallFile
        case result of
          Left err -> expectationFailure $ "Failed to load: " ++ show err
          Right m -> do
            length (m.vars) `shouldBe` 1
            map (.name) m.vars `shouldBe` ["project.name"]
            length (m.steps) `shouldBe` 1
            length (m.prompts) `shouldBe` 1
            length (m.commands) `shouldBe` 0
            length (m.exports) `shouldBe` 0
            length (m.dependencies) `shouldBe` 0

  describe "readmeTemplate" $ do
    it "contains the project.name placeholder" $ do
      T.isInfixOf "{{project.name}}" readmeTemplate `shouldBe` True

  describe "blueprintDhall" $ do
    it "generates Dhall that imports the schema and uses Blueprint::" $ do
      schemaPath <- resolveSchemaPath
      let content = blueprintDhall "test-bp" schemaPath ""
      T.isInfixOf "let S =" content `shouldBe` True
      T.isInfixOf "S.Blueprint::" content `shouldBe` True
      T.isInfixOf "migrations = [] : List S.BlueprintMigration.Type" content `shouldBe` True

    it "imports prompt.md as Text rather than inlining the body" $ do
      schemaPath <- resolveSchemaPath
      let content = blueprintDhall "test-bp" schemaPath ""
      T.isInfixOf "./prompt.md as Text" content `shouldBe` True

    it "decodes via evalBlueprintFromFile when prompt.md is present" $ do
      schemaPath <- resolveSchemaPath
      withSystemTempDirectory "seihou-blueprint-scaffold-test" $ \tmpDir -> do
        let bpDir = tmpDir </> "test-bp"
            dhallFile = bpDir </> "blueprint.dhall"
            filesDir = bpDir </> "files"
        createDirectoryIfMissing True filesDir
        writeFile dhallFile (T.unpack (blueprintDhall "test-bp" schemaPath ""))
        writeFile (bpDir </> "prompt.md") (T.unpack examplePromptMarkdown)
        result <- evalBlueprintFromFile dhallFile
        case result of
          Left err -> expectationFailure $ "Failed to load generated blueprint: " ++ show err
          Right b -> b.name `shouldBe` "test-bp"

    it "produces a blueprint that passes validateBlueprint" $ do
      schemaPath <- resolveSchemaPath
      withSystemTempDirectory "seihou-blueprint-scaffold-test" $ \tmpDir -> do
        let bpDir = tmpDir </> "test-bp"
            dhallFile = bpDir </> "blueprint.dhall"
            filesDir = bpDir </> "files"
        createDirectoryIfMissing True filesDir
        writeFile dhallFile (T.unpack (blueprintDhall "test-bp" schemaPath ""))
        writeFile (bpDir </> "prompt.md") (T.unpack examplePromptMarkdown)
        result <- evalBlueprintFromFile dhallFile
        case result of
          Left err -> expectationFailure $ "Failed to load: " ++ show err
          Right b -> do
            validated <- validateBlueprint bpDir b
            case validated of
              Left err -> expectationFailure $ "Validation failed: " ++ show err
              Right _ -> pure ()

    it "produces the expected blueprint structure (1 var, 1 prompt, 0 base modules, 0 files)" $ do
      schemaPath <- resolveSchemaPath
      withSystemTempDirectory "seihou-blueprint-scaffold-test" $ \tmpDir -> do
        let bpDir = tmpDir </> "test-bp"
            dhallFile = bpDir </> "blueprint.dhall"
            filesDir = bpDir </> "files"
        createDirectoryIfMissing True filesDir
        writeFile dhallFile (T.unpack (blueprintDhall "test-bp" schemaPath ""))
        writeFile (bpDir </> "prompt.md") (T.unpack examplePromptMarkdown)
        result <- evalBlueprintFromFile dhallFile
        case result of
          Left err -> expectationFailure $ "Failed to load: " ++ show err
          Right b -> do
            length (b.vars) `shouldBe` 1
            map (.name) b.vars `shouldBe` ["project.name"]
            length (b.prompts) `shouldBe` 1
            length (b.baseModules) `shouldBe` 0
            length (b.files) `shouldBe` 0
            length (b.tags) `shouldBe` 0
            length (b.migrations) `shouldBe` 0

  describe "examplePromptMarkdown" $ do
    it "contains the {{project.name}} placeholder so authors see substitution" $ do
      T.isInfixOf "{{project.name}}" examplePromptMarkdown `shouldBe` True

    it "is non-empty after trimming (would otherwise fail prompt-non-empty validation)" $ do
      T.null (T.strip examplePromptMarkdown) `shouldBe` False

  describe "promptDhall" $ do
    it "generates self-contained Dhall with prompt-specific type aliases" $ do
      schemaPath <- resolveSchemaPath
      let content = promptDhall "review-changes" schemaPath ""
      T.isInfixOf "let Prompt =" content `shouldBe` True
      T.isInfixOf "let CommandVar =" content `shouldBe` True

    it "imports prompt.md as Text rather than inlining the body" $ do
      schemaPath <- resolveSchemaPath
      let content = promptDhall "review-changes" schemaPath ""
      T.isInfixOf "./prompt.md as Text" content `shouldBe` True

    it "decodes via evalAgentPromptFromFile when prompt.md is present" $ do
      schemaPath <- resolveSchemaPath
      withSystemTempDirectory "seihou-prompt-scaffold-test" $ \tmpDir -> do
        let promptDir = tmpDir </> "review-changes"
            dhallFile = promptDir </> "prompt.dhall"
            filesDir = promptDir </> "files"
        createDirectoryIfMissing True filesDir
        writeFile dhallFile (T.unpack (promptDhall "review-changes" schemaPath ""))
        writeFile (promptDir </> "prompt.md") (T.unpack exampleAgentPromptMarkdown)
        result <- evalAgentPromptFromFile dhallFile
        case result of
          Left err -> expectationFailure $ "Failed to load generated prompt: " ++ show err
          Right p -> p.name `shouldBe` "review-changes"

    it "produces a prompt that passes validateAgentPrompt" $ do
      schemaPath <- resolveSchemaPath
      withSystemTempDirectory "seihou-prompt-scaffold-test" $ \tmpDir -> do
        let promptDir = tmpDir </> "review-changes"
            dhallFile = promptDir </> "prompt.dhall"
            filesDir = promptDir </> "files"
        createDirectoryIfMissing True filesDir
        writeFile dhallFile (T.unpack (promptDhall "review-changes" schemaPath ""))
        writeFile (promptDir </> "prompt.md") (T.unpack exampleAgentPromptMarkdown)
        result <- evalAgentPromptFromFile dhallFile
        case result of
          Left err -> expectationFailure $ "Failed to load: " ++ show err
          Right p -> do
            validated <- validateAgentPrompt promptDir p
            case validated of
              Left err -> expectationFailure $ "Validation failed: " ++ show err
              Right _ -> pure ()

    it "produces the expected prompt structure" $ do
      schemaPath <- resolveSchemaPath
      withSystemTempDirectory "seihou-prompt-scaffold-test" $ \tmpDir -> do
        let promptDir = tmpDir </> "review-changes"
            dhallFile = promptDir </> "prompt.dhall"
            filesDir = promptDir </> "files"
        createDirectoryIfMissing True filesDir
        writeFile dhallFile (T.unpack (promptDhall "review-changes" schemaPath ""))
        writeFile (promptDir </> "prompt.md") (T.unpack exampleAgentPromptMarkdown)
        result <- evalAgentPromptFromFile dhallFile
        case result of
          Left err -> expectationFailure $ "Failed to load: " ++ show err
          Right p -> do
            length (p.vars) `shouldBe` 1
            map (.name) p.vars `shouldBe` ["project.name"]
            length (p.prompts) `shouldBe` 0
            length (p.commandVars) `shouldBe` 0
            length (p.files) `shouldBe` 0
            length (p.tags) `shouldBe` 0

  describe "exampleAgentPromptMarkdown" $ do
    it "contains the {{project.name}} placeholder so debug rendering shows substitution" $ do
      T.isInfixOf "{{project.name}}" exampleAgentPromptMarkdown `shouldBe` True

    it "is non-empty after trimming" $ do
      T.null (T.strip exampleAgentPromptMarkdown) `shouldBe` False
