module Seihou.Core.BlueprintSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Seihou.Core.Blueprint (checkBlueprintMigrations, validateBlueprintWith)
import Seihou.Core.Migration (BlueprintMigration (..))
import Seihou.Core.Module (discoverRunnable)
import Seihou.Core.Types
import Seihou.Dhall.Eval (evalBlueprintFromFile)
import System.Directory (createDirectoryIfMissing, getCurrentDirectory)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Core.Blueprint" spec

fixtureDir :: FilePath
fixtureDir = "test/fixtures"

hasError :: T.Text -> [T.Text] -> Bool
hasError needle = any (T.isInfixOf needle)

-- | A well-formed blueprint used as the seed for negative-case tests.
goodBlueprint :: Blueprint
goodBlueprint =
  Blueprint
    "valid-bp"
    (Just "0.1.0")
    (Just "A valid blueprint")
    "Scaffold something for the user."
    [ VarDecl
        { name = "project.name",
          type_ = VTText,
          default_ = Nothing,
          description = Nothing,
          required = True,
          validation = Nothing
        }
    ]
    []
    []
    []
    Nothing
    []
    []

-- | Helpers to update individual 'Blueprint' fields without ambiguous
-- record updates. Several @Blueprint@ fields collide by name with
-- @Module@, @Recipe@, and @Manifest@; positional construction sidesteps
-- the ambiguity once and for all.
withBlueprintName :: ModuleName -> Blueprint -> Blueprint
withBlueprintName n b =
  Blueprint n b.version b.description b.prompt b.vars b.prompts b.baseModules b.files b.allowedTools b.tags b.migrations

withBlueprintVersion :: Maybe T.Text -> Blueprint -> Blueprint
withBlueprintVersion v b =
  Blueprint b.name v b.description b.prompt b.vars b.prompts b.baseModules b.files b.allowedTools b.tags b.migrations

withBlueprintPrompt :: T.Text -> Blueprint -> Blueprint
withBlueprintPrompt p b =
  Blueprint b.name b.version b.description p b.vars b.prompts b.baseModules b.files b.allowedTools b.tags b.migrations

withBlueprintVars :: [VarDecl] -> Blueprint -> Blueprint
withBlueprintVars vs b =
  Blueprint b.name b.version b.description b.prompt vs b.prompts b.baseModules b.files b.allowedTools b.tags b.migrations

withBlueprintPrompts :: [Prompt] -> Blueprint -> Blueprint
withBlueprintPrompts ps b =
  Blueprint b.name b.version b.description b.prompt b.vars ps b.baseModules b.files b.allowedTools b.tags b.migrations

withBlueprintBaseModules :: [Dependency] -> Blueprint -> Blueprint
withBlueprintBaseModules ds b =
  Blueprint b.name b.version b.description b.prompt b.vars b.prompts ds b.files b.allowedTools b.tags b.migrations

withBlueprintFiles :: [BlueprintFile] -> Blueprint -> Blueprint
withBlueprintFiles fs b =
  Blueprint b.name b.version b.description b.prompt b.vars b.prompts b.baseModules fs b.allowedTools b.tags b.migrations

withBlueprintAllowedTools :: Maybe [T.Text] -> Blueprint -> Blueprint
withBlueprintAllowedTools at b =
  Blueprint b.name b.version b.description b.prompt b.vars b.prompts b.baseModules b.files at b.tags b.migrations

withBlueprintTags :: [T.Text] -> Blueprint -> Blueprint
withBlueprintTags ts b =
  Blueprint b.name b.version b.description b.prompt b.vars b.prompts b.baseModules b.files b.allowedTools ts b.migrations

withBlueprintMigrations :: [BlueprintMigration] -> Blueprint -> Blueprint
withBlueprintMigrations migrations b =
  Blueprint b.name b.version b.description b.prompt b.vars b.prompts b.baseModules b.files b.allowedTools b.tags migrations

spec :: Spec
spec = do
  describe "evalBlueprintFromFile (sample fixture)" $ do
    it "decodes the sample-blueprint fixture" $ do
      result <- evalBlueprintFromFile (fixtureDir </> "sample-blueprint" </> "blueprint.dhall")
      case result of
        Left err -> expectationFailure ("Expected Right, got Left: " <> show err)
        Right b -> do
          b.name `shouldBe` ModuleName "sample-blueprint"
          b.version `shouldBe` Just "0.1.0"
          b.description `shouldBe` Just "Fixture blueprint for EP-29 tests"
          T.isInfixOf "{{project.name}}" b.prompt `shouldBe` True
          length b.vars `shouldBe` 2
          b.tags `shouldBe` ["demo"]
          b.baseModules `shouldBe` []
          length b.files `shouldBe` 1
          b.migrations `shouldBe` []

    it "decodes declared blueprint migrations in declaration order" $ do
      withSystemTempDirectory "seihou-blueprint-migration-decode" $ \tmpDir -> do
        let path = tmpDir </> "blueprint.dhall"
        writeFile path (sampleBlueprintWithMigrationsDhall "migration-bp")
        result <- evalBlueprintFromFile path
        case result of
          Right b ->
            b.migrations
              `shouldBe` [ BlueprintMigration "1.0.0" "2.0.0" "first edge",
                           BlueprintMigration "2.5.0" "3.0.0" "second edge"
                         ]
          Left err -> expectationFailure ("Expected migrations to decode, got: " <> show err)

  describe "validateBlueprintWith (sample fixture)" $ do
    it "accepts the sample-blueprint fixture" $ do
      cwd <- getCurrentDirectory
      let baseDir = cwd </> "test" </> "fixtures" </> "sample-blueprint"
      Right b <- evalBlueprintFromFile (baseDir </> "blueprint.dhall")
      result <- validateBlueprintWith [] baseDir b
      case result of
        Right b' -> b'.name `shouldBe` "sample-blueprint"
        Left err -> expectationFailure ("Expected Right, got: " <> show err)

  describe "validateBlueprintWith (rule-by-rule)" $ do
    it "rejects an invalid blueprint name" $ do
      withSystemTempDirectory "seihou-test" $ \tmpDir -> do
        let bad = withBlueprintName "Bad_Name" goodBlueprint
        result <- validateBlueprintWith [] tmpDir bad
        case result of
          Left (ValidationError _ errs) ->
            hasError "blueprint name must match" errs `shouldBe` True
          other -> expectationFailure ("Expected ValidationError, got: " <> show other)

    it "rejects an empty version string" $ do
      withSystemTempDirectory "seihou-test" $ \tmpDir -> do
        let bad = withBlueprintVersion (Just "  ") goodBlueprint
        result <- validateBlueprintWith [] tmpDir bad
        case result of
          Left (ValidationError _ errs) ->
            hasError "version, if specified, must not be empty" errs `shouldBe` True
          other -> expectationFailure ("Expected ValidationError, got: " <> show other)

    it "accepts a missing version" $ do
      withSystemTempDirectory "seihou-test" $ \tmpDir -> do
        let bp = withBlueprintVersion Nothing goodBlueprint
        result <- validateBlueprintWith [] tmpDir bp
        case result of
          Right _ -> pure ()
          Left err -> expectationFailure ("Expected Right, got: " <> show err)

    it "rejects an empty prompt" $ do
      withSystemTempDirectory "seihou-test" $ \tmpDir -> do
        let bad = withBlueprintPrompt "   \n  " goodBlueprint
        result <- validateBlueprintWith [] tmpDir bad
        case result of
          Left (ValidationError _ errs) ->
            hasError "prompt must not be empty" errs `shouldBe` True
          other -> expectationFailure ("Expected ValidationError, got: " <> show other)

    it "rejects duplicate variable names" $ do
      withSystemTempDirectory "seihou-test" $ \tmpDir -> do
        let dup =
              VarDecl
                { name = "project.name",
                  type_ = VTBool,
                  default_ = Nothing,
                  description = Nothing,
                  required = False,
                  validation = Nothing
                }
            bad = withBlueprintVars (goodBlueprint.vars ++ [dup]) goodBlueprint
        result <- validateBlueprintWith [] tmpDir bad
        case result of
          Left (ValidationError _ errs) ->
            hasError "duplicate variable name" errs `shouldBe` True
          other -> expectationFailure ("Expected ValidationError, got: " <> show other)

    it "rejects a prompt referencing an undeclared variable" $ do
      withSystemTempDirectory "seihou-test" $ \tmpDir -> do
        let bad =
              withBlueprintPrompts
                [Prompt {var = "undeclared", text = "?", condition = Nothing, choices = Nothing}]
                goodBlueprint
        result <- validateBlueprintWith [] tmpDir bad
        case result of
          Left (ValidationError _ errs) ->
            hasError "prompt references undeclared" errs `shouldBe` True
          other -> expectationFailure ("Expected ValidationError, got: " <> show other)

    it "rejects an empty tag" $ do
      withSystemTempDirectory "seihou-test" $ \tmpDir -> do
        let bad = withBlueprintTags ["ok", "  "] goodBlueprint
        result <- validateBlueprintWith [] tmpDir bad
        case result of
          Left (ValidationError _ errs) ->
            hasError "tag must not be empty" errs `shouldBe` True
          other -> expectationFailure ("Expected ValidationError, got: " <> show other)

    it "rejects an empty allowedTools entry" $ do
      withSystemTempDirectory "seihou-test" $ \tmpDir -> do
        let bad = withBlueprintAllowedTools (Just ["Read", ""]) goodBlueprint
        result <- validateBlueprintWith [] tmpDir bad
        case result of
          Left (ValidationError _ errs) ->
            hasError "allowedTools entry must not be empty" errs `shouldBe` True
          other -> expectationFailure ("Expected ValidationError, got: " <> show other)

    it "rejects an empty migration prompt" $ do
      let bad = withBlueprintMigrations [BlueprintMigration "1.0.0" "2.0.0" "  "] goodBlueprint
      checkBlueprintMigrations bad `shouldSatisfy` hasError "prompt must not be empty"

    it "rejects malformed migration versions" $ do
      let bad = withBlueprintMigrations [BlueprintMigration "release-1" "next" "change"] goodBlueprint
          errors = checkBlueprintMigrations bad
      errors `shouldSatisfy` hasError "from version is not dotted numeric"
      errors `shouldSatisfy` hasError "to version is not dotted numeric"

    it "rejects migration edges that do not advance" $ do
      let equalEdge = withBlueprintMigrations [BlueprintMigration "2.0.0" "2.0.0" "change"] goodBlueprint
          reverseEdge = withBlueprintMigrations [BlueprintMigration "3.0.0" "2.0.0" "change"] goodBlueprint
      checkBlueprintMigrations equalEdge `shouldSatisfy` hasError "must advance versions"
      checkBlueprintMigrations reverseEdge `shouldSatisfy` hasError "must advance versions"

    it "rejects duplicate migration starts" $ do
      let bad =
            withBlueprintMigrations
              [ BlueprintMigration "1.0.0" "2.0.0" "first",
                BlueprintMigration "1.0.0" "3.0.0" "second"
              ]
              goodBlueprint
      checkBlueprintMigrations bad `shouldSatisfy` hasError "duplicate blueprint migration from version"

    it "rejects a missing referenced file" $ do
      withSystemTempDirectory "seihou-test" $ \tmpDir -> do
        let bad =
              withBlueprintFiles
                [BlueprintFile {src = "missing.md", description = Nothing}]
                goodBlueprint
        result <- validateBlueprintWith [] tmpDir bad
        case result of
          Left (ValidationError _ errs) ->
            hasError "blueprint file not found" errs `shouldBe` True
          other -> expectationFailure ("Expected ValidationError, got: " <> show other)

    it "accepts a referenced file when present on disk" $ do
      withSystemTempDirectory "seihou-test" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "files")
        writeFile (tmpDir </> "files" </> "snippet.md") "stub"
        let bp =
              withBlueprintFiles
                [BlueprintFile {src = "snippet.md", description = Nothing}]
                goodBlueprint
        result <- validateBlueprintWith [] tmpDir bp
        case result of
          Right _ -> pure ()
          Left err -> expectationFailure ("Expected Right, got: " <> show err)

    it "rejects a baseModule that does not resolve" $ do
      withSystemTempDirectory "seihou-test" $ \tmpDir -> do
        let bad =
              withBlueprintBaseModules
                [Dependency {depModule = "nope-not-here", depVars = Map.empty}]
                goodBlueprint
        result <- validateBlueprintWith [tmpDir] tmpDir bad
        case result of
          Left (ValidationError _ errs) ->
            hasError "not found in any search path" errs `shouldBe` True
          other -> expectationFailure ("Expected ValidationError, got: " <> show other)

    it "rejects a baseModule that resolves to another blueprint" $ do
      withSystemTempDirectory "seihou-test" $ \tmpDir -> do
        let nestedDir = tmpDir </> "nested-bp"
        createDirectoryIfMissing True nestedDir
        writeFile (nestedDir </> "blueprint.dhall") (sampleBlueprintDhall "nested-bp")
        let bad =
              withBlueprintBaseModules
                [Dependency {depModule = "nested-bp", depVars = Map.empty}]
                goodBlueprint
        result <- validateBlueprintWith [tmpDir] tmpDir bad
        case result of
          Left (ValidationError _ errs) ->
            hasError "resolves to a blueprint" errs `shouldBe` True
          other -> expectationFailure ("Expected ValidationError, got: " <> show other)

  describe "discoverRunnable for blueprints" $ do
    it "finds a blueprint when only blueprint.dhall is present" $ do
      withSystemTempDirectory "seihou-test" $ \tmpDir -> do
        let bpDir = tmpDir </> "only-bp"
        createDirectoryIfMissing True bpDir
        writeFile (bpDir </> "blueprint.dhall") (sampleBlueprintDhall "only-bp")
        result <- discoverRunnable [tmpDir] "only-bp"
        case result of
          Right (RunnableBlueprint b dir) -> do
            b.name `shouldBe` "only-bp"
            dir `shouldBe` bpDir
          other -> expectationFailure ("Expected RunnableBlueprint, got: " <> show other)

    it "prefers module.dhall over blueprint.dhall in the same directory" $ do
      withSystemTempDirectory "seihou-test" $ \tmpDir -> do
        let entryDir = tmpDir </> "ambiguous"
        createDirectoryIfMissing True entryDir
        writeFile (entryDir </> "module.dhall") minimalModuleDhall
        writeFile (entryDir </> "blueprint.dhall") (sampleBlueprintDhall "ambiguous")
        result <- discoverRunnable [tmpDir] "ambiguous"
        case result of
          Right (RunnableModule _ _) -> pure ()
          other -> expectationFailure ("Expected RunnableModule (module wins over blueprint), got: " <> show other)

-- | A minimal module Dhall body for the priority-conflict test.
minimalModuleDhall :: String
minimalModuleDhall =
  unlines
    [ "{ name = \"ambiguous\"",
      ", version = Some \"1.0.0\"",
      ", description = None Text",
      ", vars =",
      "    [] : List",
      "          { name : Text",
      "          , type : Text",
      "          , default : Optional Text",
      "          , description : Optional Text",
      "          , required : Bool",
      "          , validation : Optional Text",
      "          }",
      ", exports = [] : List { var : Text, alias : Optional Text }",
      ", prompts =",
      "    [] : List",
      "          { var : Text",
      "          , text : Text",
      "          , when : Optional Text",
      "          , choices : Optional (List Text)",
      "          }",
      ", steps =",
      "    [] : List",
      "          { strategy : Text",
      "          , src : Text",
      "          , dest : Text",
      "          , when : Optional Text",
      "          , patch : Optional Text",
      "          }",
      ", commands =",
      "    [] : List { run : Text, workDir : Optional Text, when : Optional Text }",
      ", dependencies = [] : List Text",
      "}"
    ]

-- | A minimal blueprint Dhall body parameterised by name.
sampleBlueprintDhall :: T.Text -> String
sampleBlueprintDhall n =
  unlines
    [ "{ name = \"" ++ T.unpack n ++ "\"",
      ", version = Some \"0.1.0\"",
      ", description = None Text",
      ", prompt = \"hello\"",
      ", vars =",
      "    [] : List",
      "          { name : Text",
      "          , type : Text",
      "          , default : Optional Text",
      "          , description : Optional Text",
      "          , required : Bool",
      "          , validation : Optional Text",
      "          }",
      ", prompts =",
      "    [] : List",
      "          { var : Text",
      "          , text : Text",
      "          , when : Optional Text",
      "          , choices : Optional (List Text)",
      "          }",
      ", baseModules =",
      "    [] : List { module : Text, vars : List { name : Text, value : Text } }",
      ", files =",
      "    [] : List { src : Text, description : Optional Text }",
      ", allowedTools = None (List Text)",
      ", tags = [] : List Text",
      "}"
    ]

sampleBlueprintWithMigrationsDhall :: T.Text -> String
sampleBlueprintWithMigrationsDhall n =
  unlines $
    init (lines (sampleBlueprintDhall n))
      <> [ ", migrations =",
           "    [ { from = \"1.0.0\", to = \"2.0.0\", prompt = \"first edge\" }",
           "    , { from = \"2.5.0\", to = \"3.0.0\", prompt = \"second edge\" }",
           "    ]",
           "}"
         ]
