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
          m.name `shouldBe` ModuleName "haskell-base"
          m.description `shouldBe` Just "A Haskell project template"
          length (m.vars) `shouldBe` 3
          length (m.prompts) `shouldBe` 1
          length (m.steps) `shouldBe` 5
          length (m.exports) `shouldBe` 1
          m.dependencies `shouldBe` []

    it "decodes variable declarations correctly" $ do
      result <- evalModuleFromFile (fixtureDir </> "haskell-base" </> "module.dhall")
      case result of
        Left err -> expectationFailure ("Expected Right, got Left: " <> show err)
        Right m -> do
          let (projectName : projectVersion : _) = m.vars
          projectName.name `shouldBe` VarName "project.name"
          projectName.type_ `shouldBe` VTText
          projectName.default_ `shouldBe` Nothing
          projectName.required `shouldBe` True
          projectName.validation `shouldBe` Just (ValPattern "[a-z][a-z0-9-]*")

          projectVersion.name `shouldBe` VarName "project.version"
          projectVersion.default_ `shouldBe` Just (VText "0.1.0.0")
          projectVersion.required `shouldBe` False

    it "decodes steps with correct strategy" $ do
      result <- evalModuleFromFile (fixtureDir </> "haskell-base" </> "module.dhall")
      case result of
        Left err -> expectationFailure ("Expected Right, got Left: " <> show err)
        Right m -> do
          let (readme : libStep : licenseStep : _) = m.steps
          readme.strategy `shouldBe` Template
          readme.src `shouldBe` "README.md.tpl"
          readme.dest `shouldBe` "README.md"
          readme.condition `shouldBe` Nothing
          readme.patch `shouldBe` Nothing

          libStep.strategy `shouldBe` Template
          libStep.src `shouldBe` "src/Lib.hs.tpl"
          libStep.dest `shouldBe` "src/Lib.hs"
          libStep.patch `shouldBe` Nothing

          licenseStep.strategy `shouldBe` Copy
          licenseStep.src `shouldBe` "LICENSE"
          licenseStep.dest `shouldBe` "LICENSE"
          licenseStep.condition `shouldBe` Just (ExprIsSet "license")
          licenseStep.patch `shouldBe` Nothing

    it "decodes exports correctly" $ do
      result <- evalModuleFromFile (fixtureDir </> "haskell-base" </> "module.dhall")
      case result of
        Left err -> expectationFailure ("Expected Right, got Left: " <> show err)
        Right m -> do
          let (export1 : _) = m.exports
          export1.var `shouldBe` VarName "project.name"
          export1.alias `shouldBe` Nothing

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
          let (prompt1 : _) = m.prompts
          prompt1.var `shouldBe` VarName "project.name"
          prompt1.text `shouldBe` "What is the project name?"
          prompt1.condition `shouldBe` Nothing
          prompt1.choices `shouldBe` Nothing

    it "decodes step with patch = Some \"append-file\"" $ do
      withSystemTempDirectory "seihou-eval-test" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "files")
        writeFile (tmpDir </> "files" </> "section.tpl") "section content"
        let dhall =
              "{ name = \"patch-test\"\n\
              \, version = None Text\n\
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
              \, commands = [] : List { run : Text, workDir : Optional Text, when : Optional Text }\n\
              \, dependencies = [] : List Text\n\
              \, removable = False\n\
              \}"
        writeFile (tmpDir </> "module.dhall") dhall
        result <- evalModuleFromFile (tmpDir </> "module.dhall")
        case result of
          Left err -> expectationFailure ("Expected Right, got Left: " <> show err)
          Right m -> do
            let (s1 : s2 : s3 : _) = m.steps
            s1.patch `shouldBe` Just AppendFile
            s2.patch `shouldBe` Just PrependFile
            s3.patch `shouldBe` Just AppendSection

    it "returns Left for unknown patch operation (not a crash)" $ do
      withSystemTempDirectory "seihou-eval-test" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "files")
        writeFile (tmpDir </> "files" </> "section.tpl") "content"
        let dhall =
              "{ name = \"bad-patch\"\n\
              \, version = None Text\n\
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
              \, commands = [] : List { run : Text, workDir : Optional Text, when : Optional Text }\n\
              \, dependencies = [] : List Text\n\
              \, removable = False\n\
              \}"
        writeFile (tmpDir </> "module.dhall") dhall
        result <- evalModuleFromFile (tmpDir </> "module.dhall")
        case result of
          Left (DhallEvalError _ msg) ->
            T.isInfixOf "invalid-op" msg `shouldBe` True
          Left other -> expectationFailure ("Expected DhallEvalError, got: " <> show other)
          Right _ -> expectationFailure "Expected Left for bad patch operation"

  describe "dependencyDecoder" $ do
    let emptyModuleWithDeps depsStr =
          "{ name = \"test-mod\"\n\
          \, version = None Text\n\
          \, description = None Text\n\
          \, vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }\n\
          \, exports = [] : List { var : Text, alias : Optional Text }\n\
          \, prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }\n\
          \, steps = [] : List { strategy : Text, src : Text, dest : Text, when : Optional Text, patch : Optional Text }\n\
          \, commands = [] : List { run : Text, workDir : Optional Text, when : Optional Text }\n\
          \, dependencies = "
            ++ depsStr
            ++ "\n\
               \, removable = False\n\
               \}"

    it "decodes a bare string dependency" $ do
      withSystemTempDirectory "seihou-eval-test" $ \tmpDir -> do
        writeFile (tmpDir </> "module.dhall") (emptyModuleWithDeps "[\"base\"]")
        result <- evalModuleFromFile (tmpDir </> "module.dhall")
        case result of
          Left err -> expectationFailure ("Expected Right, got Left: " <> show err)
          Right m -> do
            length m.dependencies `shouldBe` 1
            let dep = head m.dependencies
            dep.depModule `shouldBe` ModuleName "base"
            Map.null dep.depVars `shouldBe` True

    it "decodes a parameterized record dependency" $ do
      withSystemTempDirectory "seihou-eval-test" $ \tmpDir -> do
        writeFile (tmpDir </> "module.dhall") (emptyModuleWithDeps "[{ module = \"base\", vars = [{ name = \"x\", value = \"y\" }] }]")
        result <- evalModuleFromFile (tmpDir </> "module.dhall")
        case result of
          Left err -> expectationFailure ("Expected Right, got Left: " <> show err)
          Right m -> do
            length m.dependencies `shouldBe` 1
            let dep = head m.dependencies
            dep.depModule `shouldBe` ModuleName "base"
            Map.lookup (VarName "x") dep.depVars `shouldBe` Just "y"

    it "decodes a parameterized dependency with empty vars" $ do
      withSystemTempDirectory "seihou-eval-test" $ \tmpDir -> do
        writeFile (tmpDir </> "module.dhall") (emptyModuleWithDeps "[{ module = \"base\", vars = [] : List { name : Text, value : Text } }]")
        result <- evalModuleFromFile (tmpDir </> "module.dhall")
        case result of
          Left err -> expectationFailure ("Expected Right, got Left: " <> show err)
          Right m -> do
            length m.dependencies `shouldBe` 1
            let dep = head m.dependencies
            dep.depModule `shouldBe` ModuleName "base"
            Map.null dep.depVars `shouldBe` True

    it "decodes a module.dhall with parameterized dependencies" $ do
      withSystemTempDirectory "seihou-eval-test" $ \tmpDir -> do
        writeFile (tmpDir </> "module.dhall") (emptyModuleWithDeps "[{ module = \"child-mod\", vars = [{ name = \"skill.name\", value = \"exec-plan\" }] }]")
        result <- evalModuleFromFile (tmpDir </> "module.dhall")
        case result of
          Left err -> expectationFailure ("Expected Right, got Left: " <> show err)
          Right m -> do
            length m.dependencies `shouldBe` 1
            let dep = head m.dependencies
            dep.depModule `shouldBe` ModuleName "child-mod"
            Map.lookup (VarName "skill.name") dep.depVars `shouldBe` Just "exec-plan"
