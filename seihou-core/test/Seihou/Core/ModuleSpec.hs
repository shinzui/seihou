module Seihou.Core.ModuleSpec (tests) where

import Data.Text qualified as T
import Seihou.Core.Module (discoverModule, loadModule, validateModule)
import Seihou.Core.Types
import System.Directory (createDirectoryIfMissing, getCurrentDirectory)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Core.Module" spec

-- | A well-formed module for pure validation tests.
goodModule :: Module
goodModule =
  Module
    { moduleName = "test-module",
      moduleDescription = Just "A test module",
      moduleVars =
        [ VarDecl
            { varName = "project.name",
              varType = VTText,
              varDefault = Nothing,
              varDescription = Just "Project name",
              varRequired = True,
              varValidation = Nothing
            }
        ],
      moduleExports = [VarExport {exportVar = "project.name", exportAs = Nothing}],
      modulePrompts = [Prompt {promptVar = "project.name", promptText = "Name?", promptWhen = Nothing, promptChoices = Nothing}],
      moduleSteps =
        [ Step
            { stepStrategy = Template,
              stepSrc = "README.md.tpl",
              stepDest = "README.md",
              stepWhen = Nothing
            }
        ],
      moduleDependencies = []
    }

hasError :: T.Text -> [T.Text] -> Bool
hasError needle = any (T.isInfixOf needle)

spec :: Spec
spec = do
  describe "discoverModule" $ do
    it "finds a module in the search path" $ do
      cwd <- getCurrentDirectory
      let searchPaths = [cwd </> "test" </> "fixtures"]
      result <- discoverModule searchPaths "haskell-base"
      case result of
        Right path -> path `shouldBe` (cwd </> "test" </> "fixtures" </> "haskell-base")
        Left err -> expectationFailure ("Expected Right, got Left: " <> show err)

    it "returns ModuleNotFound when module does not exist" $ do
      result <- discoverModule ["/nonexistent/path"] "no-such-module"
      case result of
        Left (ModuleNotFound name paths) -> do
          unModuleName name `shouldBe` "no-such-module"
          paths `shouldBe` ["/nonexistent/path"]
        Left other -> expectationFailure ("Expected ModuleNotFound, got: " <> show other)
        Right _ -> expectationFailure "Expected Left, got Right"

    it "searches paths in order and returns the first match" $ do
      withSystemTempDirectory "seihou-test" $ \tmpDir -> do
        let dir1 = tmpDir </> "first"
        let dir2 = tmpDir </> "second"
        createDirectoryIfMissing True (dir1 </> "my-mod")
        createDirectoryIfMissing True (dir2 </> "my-mod")
        writeFile (dir1 </> "my-mod" </> "module.dhall") "{ name = \"my-mod\" }"
        writeFile (dir2 </> "my-mod" </> "module.dhall") "{ name = \"my-mod\" }"
        result <- discoverModule [dir1, dir2] "my-mod"
        case result of
          Right path -> path `shouldBe` (dir1 </> "my-mod")
          Left err -> expectationFailure ("Expected Right, got: " <> show err)

  describe "validateModule" $ do
    it "passes a well-formed module" $ do
      withSystemTempDirectory "seihou-test" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "files")
        writeFile (tmpDir </> "files" </> "README.md.tpl") "stub"
        result <- validateModule tmpDir goodModule
        case result of
          Right m -> moduleName m `shouldBe` "test-module"
          Left err -> expectationFailure ("Expected Right, got: " <> show err)

    it "rejects a bad module name" $ do
      withSystemTempDirectory "seihou-test" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "files")
        writeFile (tmpDir </> "files" </> "README.md.tpl") "stub"
        let bad = goodModule {moduleName = "BadName"}
        result <- validateModule tmpDir bad
        case result of
          Left (ValidationError _ errs) ->
            hasError "module name must match" errs `shouldBe` True
          Left other -> expectationFailure ("Expected ValidationError, got: " <> show other)
          Right _ -> expectationFailure "Expected validation failure"

    it "rejects duplicate variable names" $ do
      withSystemTempDirectory "seihou-test" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "files")
        writeFile (tmpDir </> "files" </> "README.md.tpl") "stub"
        let dup =
              goodModule
                { moduleVars =
                    [ VarDecl "x" VTText Nothing Nothing True Nothing,
                      VarDecl "x" VTBool Nothing Nothing False Nothing
                    ]
                }
        result <- validateModule tmpDir dup
        case result of
          Left (ValidationError _ errs) ->
            hasError "duplicate variable name" errs `shouldBe` True
          Left other -> expectationFailure ("Expected ValidationError, got: " <> show other)
          Right _ -> expectationFailure "Expected validation failure"

    it "rejects prompt referencing undeclared variable" $ do
      withSystemTempDirectory "seihou-test" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "files")
        writeFile (tmpDir </> "files" </> "README.md.tpl") "stub"
        let bad =
              goodModule
                { modulePrompts =
                    [Prompt {promptVar = "nonexistent", promptText = "?", promptWhen = Nothing, promptChoices = Nothing}]
                }
        result <- validateModule tmpDir bad
        case result of
          Left (ValidationError _ errs) ->
            hasError "prompt references undeclared" errs `shouldBe` True
          Left other -> expectationFailure ("Expected ValidationError, got: " <> show other)
          Right _ -> expectationFailure "Expected validation failure"

    it "rejects missing source file" $ do
      withSystemTempDirectory "seihou-test" $ \tmpDir -> do
        result <- validateModule tmpDir goodModule
        case result of
          Left (ValidationError _ errs) ->
            hasError "step source file not found" errs `shouldBe` True
          Left other -> expectationFailure ("Expected ValidationError, got: " <> show other)
          Right _ -> expectationFailure "Expected validation failure"

    it "rejects export referencing undeclared variable" $ do
      withSystemTempDirectory "seihou-test" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "files")
        writeFile (tmpDir </> "files" </> "README.md.tpl") "stub"
        let bad =
              goodModule
                { moduleExports = [VarExport {exportVar = "nonexistent", exportAs = Nothing}]
                }
        result <- validateModule tmpDir bad
        case result of
          Left (ValidationError _ errs) ->
            hasError "export references undeclared" errs `shouldBe` True
          Left other -> expectationFailure ("Expected ValidationError, got: " <> show other)
          Right _ -> expectationFailure "Expected validation failure"

    it "rejects unsafe destination path with .." $ do
      withSystemTempDirectory "seihou-test" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "files")
        writeFile (tmpDir </> "files" </> "README.md.tpl") "stub"
        let bad =
              goodModule
                { moduleSteps =
                    [Step Template "README.md.tpl" "../etc/passwd" Nothing]
                }
        result <- validateModule tmpDir bad
        case result of
          Left (ValidationError _ errs) ->
            hasError "must not contain '..'" errs `shouldBe` True
          Left other -> expectationFailure ("Expected ValidationError, got: " <> show other)
          Right _ -> expectationFailure "Expected validation failure"

    it "rejects absolute destination path" $ do
      withSystemTempDirectory "seihou-test" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "files")
        writeFile (tmpDir </> "files" </> "README.md.tpl") "stub"
        let bad =
              goodModule
                { moduleSteps =
                    [Step Template "README.md.tpl" "/etc/passwd" Nothing]
                }
        result <- validateModule tmpDir bad
        case result of
          Left (ValidationError _ errs) ->
            hasError "must be relative" errs `shouldBe` True
          Left other -> expectationFailure ("Expected ValidationError, got: " <> show other)
          Right _ -> expectationFailure "Expected validation failure"

    it "rejects destination referencing undeclared variable" $ do
      withSystemTempDirectory "seihou-test" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "files")
        writeFile (tmpDir </> "files" </> "README.md.tpl") "stub"
        let bad =
              goodModule
                { moduleSteps =
                    [Step Template "README.md.tpl" "src/{{unknown}}/Main.hs" Nothing]
                }
        result <- validateModule tmpDir bad
        case result of
          Left (ValidationError _ errs) ->
            hasError "destination references undeclared" errs `shouldBe` True
          Left other -> expectationFailure ("Expected ValidationError, got: " <> show other)
          Right _ -> expectationFailure "Expected validation failure"

    it "collects multiple errors at once" $ do
      withSystemTempDirectory "seihou-test" $ \tmpDir -> do
        let bad =
              Module
                { moduleName = "BadName",
                  moduleDescription = Nothing,
                  moduleVars = [],
                  moduleExports = [VarExport {exportVar = "missing", exportAs = Nothing}],
                  modulePrompts = [Prompt {promptVar = "missing", promptText = "?", promptWhen = Nothing, promptChoices = Nothing}],
                  moduleSteps = [Step Template "nonexistent.tpl" "/bad/dest" Nothing],
                  moduleDependencies = []
                }
        result <- validateModule tmpDir bad
        case result of
          Left (ValidationError _ errs) ->
            length errs `shouldSatisfy` (>= 4)
          Left other -> expectationFailure ("Expected ValidationError, got: " <> show other)
          Right _ -> expectationFailure "Expected validation failure"

  describe "loadModule" $ do
    it "loads the haskell-base fixture end-to-end" $ do
      cwd <- getCurrentDirectory
      let searchPaths = [cwd </> "test" </> "fixtures"]
      result <- loadModule searchPaths "haskell-base"
      case result of
        Right m -> do
          moduleName m `shouldBe` "haskell-base"
          length (moduleVars m) `shouldBe` 2
          length (moduleSteps m) `shouldBe` 3
        Left err -> expectationFailure ("Expected Right, got Left: " <> show err)

    it "returns ModuleNotFound for nonexistent module" $ do
      result <- loadModule ["/nonexistent"] "no-such-module"
      case result of
        Left (ModuleNotFound _ _) -> pure ()
        Left other -> expectationFailure ("Expected ModuleNotFound, got: " <> show other)
        Right _ -> expectationFailure "Expected Left, got Right"
