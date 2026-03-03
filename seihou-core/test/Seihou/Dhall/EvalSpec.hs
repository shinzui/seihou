module Seihou.Dhall.EvalSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Seihou.Core.Types
import Seihou.Dhall.Eval (evalDhallExpr, evalModuleFromFile)
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Dhall.Eval" spec

fixtureDir :: FilePath
fixtureDir = "test/fixtures"

spec :: Spec
spec = do
  describe "evalDhallExpr (spike)" $ do
    it "decodes a simple Dhall record with name and version" $ do
      result <- evalDhallExpr "{ name = \"my-project\", version = \"0.1.0\" }"
      Map.lookup "name" result `shouldBe` Just "my-project"
      Map.lookup "version" result `shouldBe` Just "0.1.0"

  describe "evalModuleFromFile" $ do
    it "decodes the haskell-base fixture module" $ do
      result <- evalModuleFromFile (fixtureDir </> "haskell-base" </> "module.dhall")
      case result of
        Left err -> expectationFailure ("Expected Right, got Left: " <> show err)
        Right m -> do
          moduleName m `shouldBe` ModuleName "haskell-base"
          moduleDescription m `shouldBe` Just "A Haskell project template"
          length (moduleVars m) `shouldBe` 3
          length (modulePrompts m) `shouldBe` 1
          length (moduleSteps m) `shouldBe` 5
          length (moduleExports m) `shouldBe` 1
          moduleDependencies m `shouldBe` []

    it "decodes variable declarations correctly" $ do
      result <- evalModuleFromFile (fixtureDir </> "haskell-base" </> "module.dhall")
      case result of
        Left err -> expectationFailure ("Expected Right, got Left: " <> show err)
        Right m -> do
          let (projectName : projectVersion : _) = moduleVars m
          varName projectName `shouldBe` VarName "project.name"
          varType projectName `shouldBe` VTText
          varDefault projectName `shouldBe` Nothing
          varRequired projectName `shouldBe` True
          varValidation projectName `shouldBe` Just (ValPattern "[a-z][a-z0-9-]*")

          varName projectVersion `shouldBe` VarName "project.version"
          varDefault projectVersion `shouldBe` Just (VText "0.1.0.0")
          varRequired projectVersion `shouldBe` False

    it "decodes steps with correct strategy" $ do
      result <- evalModuleFromFile (fixtureDir </> "haskell-base" </> "module.dhall")
      case result of
        Left err -> expectationFailure ("Expected Right, got Left: " <> show err)
        Right m -> do
          let (readme : libStep : licenseStep : _) = moduleSteps m
          stepStrategy readme `shouldBe` Template
          stepSrc readme `shouldBe` "README.md.tpl"
          stepDest readme `shouldBe` "README.md"
          stepWhen readme `shouldBe` Nothing
          stepPatch readme `shouldBe` Nothing

          stepStrategy libStep `shouldBe` Template
          stepSrc libStep `shouldBe` "src/Lib.hs.tpl"
          stepDest libStep `shouldBe` "src/Lib.hs"
          stepPatch libStep `shouldBe` Nothing

          stepStrategy licenseStep `shouldBe` Copy
          stepSrc licenseStep `shouldBe` "LICENSE"
          stepDest licenseStep `shouldBe` "LICENSE"
          stepWhen licenseStep `shouldBe` Just (ExprIsSet "license")
          stepPatch licenseStep `shouldBe` Nothing

    it "decodes exports correctly" $ do
      result <- evalModuleFromFile (fixtureDir </> "haskell-base" </> "module.dhall")
      case result of
        Left err -> expectationFailure ("Expected Right, got Left: " <> show err)
        Right m -> do
          let (export1 : _) = moduleExports m
          exportVar export1 `shouldBe` VarName "project.name"
          exportAs export1 `shouldBe` Nothing

    it "returns DhallEvalError for nonexistent file" $ do
      result <- evalModuleFromFile "/nonexistent/path/module.dhall"
      case result of
        Left (DhallEvalError _ _) -> pure ()
        Left other -> expectationFailure ("Expected DhallEvalError, got: " <> show other)
        Right _ -> expectationFailure "Expected Left, got Right"

    it "returns Left for unknown var type (not a crash)" $ do
      result <- evalModuleFromFile (fixtureDir </> "bad-vartype" </> "module.dhall")
      case result of
        Left (DhallEvalError _ msg) ->
          T.isInfixOf "strng" msg `shouldBe` True
        Left other -> expectationFailure ("Expected DhallEvalError, got: " <> show other)
        Right _ -> expectationFailure "Expected Left for bad var type"

    it "returns Left for unknown strategy (not a crash)" $ do
      result <- evalModuleFromFile (fixtureDir </> "bad-strategy" </> "module.dhall")
      case result of
        Left (DhallEvalError _ msg) ->
          T.isInfixOf "coppy" msg `shouldBe` True
        Left other -> expectationFailure ("Expected DhallEvalError, got: " <> show other)
        Right _ -> expectationFailure "Expected Left for bad strategy"

    it "decodes prompts correctly" $ do
      result <- evalModuleFromFile (fixtureDir </> "haskell-base" </> "module.dhall")
      case result of
        Left err -> expectationFailure ("Expected Right, got Left: " <> show err)
        Right m -> do
          let (prompt1 : _) = modulePrompts m
          promptVar prompt1 `shouldBe` VarName "project.name"
          promptText prompt1 `shouldBe` "What is the project name?"
          promptWhen prompt1 `shouldBe` Nothing
          promptChoices prompt1 `shouldBe` Nothing

    it "decodes step with patch = Some \"append-file\"" $ do
      withSystemTempDirectory "seihou-eval-test" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "files")
        writeFile (tmpDir </> "files" </> "section.tpl") "section content"
        let dhall =
              "{ name = \"patch-test\"\n\
              \, description = None Text\n\
              \, vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }\n\
              \, exports = [] : List { var : Text, alias : Optional Text }\n\
              \, prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }\n\
              \, steps =\n\
              \  [ { strategy = \"template\"\n\
              \    , src = \"section.tpl\"\n\
              \    , dest = \"README.md\"\n\
              \    , when = None Text\n\
              \    , patch = Some \"append-file\"\n\
              \    }\n\
              \  , { strategy = \"template\"\n\
              \    , src = \"section.tpl\"\n\
              \    , dest = \"README.md\"\n\
              \    , when = None Text\n\
              \    , patch = Some \"prepend-file\"\n\
              \    }\n\
              \  , { strategy = \"template\"\n\
              \    , src = \"section.tpl\"\n\
              \    , dest = \"README.md\"\n\
              \    , when = None Text\n\
              \    , patch = Some \"append-section\"\n\
              \    }\n\
              \  ]\n\
              \, dependencies = [] : List Text\n\
              \}"
        writeFile (tmpDir </> "module.dhall") dhall
        result <- evalModuleFromFile (tmpDir </> "module.dhall")
        case result of
          Left err -> expectationFailure ("Expected Right, got Left: " <> show err)
          Right m -> do
            let (s1 : s2 : s3 : _) = moduleSteps m
            stepPatch s1 `shouldBe` Just AppendFile
            stepPatch s2 `shouldBe` Just PrependFile
            stepPatch s3 `shouldBe` Just AppendSection

    it "returns Left for unknown patch operation (not a crash)" $ do
      withSystemTempDirectory "seihou-eval-test" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "files")
        writeFile (tmpDir </> "files" </> "section.tpl") "content"
        let dhall =
              "{ name = \"bad-patch\"\n\
              \, description = None Text\n\
              \, vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }\n\
              \, exports = [] : List { var : Text, alias : Optional Text }\n\
              \, prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }\n\
              \, steps =\n\
              \  [ { strategy = \"template\"\n\
              \    , src = \"section.tpl\"\n\
              \    , dest = \"README.md\"\n\
              \    , when = None Text\n\
              \    , patch = Some \"invalid-op\"\n\
              \    }\n\
              \  ]\n\
              \, dependencies = [] : List Text\n\
              \}"
        writeFile (tmpDir </> "module.dhall") dhall
        result <- evalModuleFromFile (tmpDir </> "module.dhall")
        case result of
          Left (DhallEvalError _ msg) ->
            T.isInfixOf "invalid-op" msg `shouldBe` True
          Left other -> expectationFailure ("Expected DhallEvalError, got: " <> show other)
          Right _ -> expectationFailure "Expected Left for bad patch operation"
