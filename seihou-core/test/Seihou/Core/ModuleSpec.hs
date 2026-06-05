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
    { name = "test-module",
      version = Just "1.0.0",
      description = Just "A test module",
      vars =
        [ VarDecl
            { name = "project.name",
              type_ = VTText,
              default_ = Nothing,
              description = Just "Project name",
              required = True,
              validation = Nothing
            }
        ],
      exports = [VarExport {var = "project.name", alias = Nothing}],
      prompts = [Prompt {var = "project.name", text = "Name?", condition = Nothing, choices = Nothing}],
      steps =
        [ Step
            { strategy = Template,
              src = "README.md.tpl",
              dest = "README.md",
              condition = Nothing,
              patch = Nothing
            }
        ],
      commands = [],
      dependencies = [],
      removal = Nothing,
      migrations = []
    }

-- | Helpers to update Module fields without ambiguous record updates.
withModuleName :: ModuleName -> Module -> Module
withModuleName n m = Module n m.version m.description m.vars m.exports m.prompts m.steps m.commands m.dependencies m.removal m.migrations

withModuleVars :: [VarDecl] -> Module -> Module
withModuleVars v m = Module m.name m.version m.description v m.exports m.prompts m.steps m.commands m.dependencies m.removal m.migrations

withModulePrompts :: [Prompt] -> Module -> Module
withModulePrompts p m = Module m.name m.version m.description m.vars m.exports p m.steps m.commands m.dependencies m.removal m.migrations

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
          name.unModuleName `shouldBe` "no-such-module"
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
          Right m -> m.name `shouldBe` "test-module"
          Left err -> expectationFailure ("Expected Right, got: " <> show err)

    it "rejects a bad module name" $ do
      withSystemTempDirectory "seihou-test" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "files")
        writeFile (tmpDir </> "files" </> "README.md.tpl") "stub"
        let bad = withModuleName "BadName" goodModule
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
              withModuleVars
                [ VarDecl "x" VTText Nothing Nothing True Nothing,
                  VarDecl "x" VTBool Nothing Nothing False Nothing
                ]
                goodModule
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
              withModulePrompts
                [Prompt {var = "nonexistent", text = "?", condition = Nothing, choices = Nothing}]
                goodModule
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
                { exports = [VarExport {var = "nonexistent", alias = Nothing}]
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
                { steps =
                    [Step Template "README.md.tpl" "../etc/passwd" Nothing Nothing]
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
                { steps =
                    [Step Template "README.md.tpl" "/etc/passwd" Nothing Nothing]
                }
        result <- validateModule tmpDir bad
        case result of
          Left (ValidationError _ errs) ->
            hasError "must be relative" errs `shouldBe` True
          Left other -> expectationFailure ("Expected ValidationError, got: " <> show other)
          Right _ -> expectationFailure "Expected validation failure"

    it "allows dots inside destination filenames" $ do
      withSystemTempDirectory "seihou-test" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "files")
        writeFile (tmpDir </> "files" </> "README.md.tpl") "stub"
        let dotted =
              goodModule
                { steps =
                    [Step Template "README.md.tpl" "docs/README.v2.md" Nothing Nothing]
                }
        result <- validateModule tmpDir dotted
        case result of
          Right m -> m.name `shouldBe` "test-module"
          Left err -> expectationFailure ("Expected Right, got: " <> show err)

    it "rejects destination referencing undeclared variable" $ do
      withSystemTempDirectory "seihou-test" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "files")
        writeFile (tmpDir </> "files" </> "README.md.tpl") "stub"
        let bad =
              goodModule
                { steps =
                    [Step Template "README.md.tpl" "src/{{unknown}}/Main.hs" Nothing Nothing]
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
                { name = "BadName",
                  version = Nothing,
                  description = Nothing,
                  vars = [],
                  exports = [VarExport {var = "missing", alias = Nothing}],
                  prompts = [Prompt {var = "missing", text = "?", condition = Nothing, choices = Nothing}],
                  steps = [Step Template "nonexistent.tpl" "/bad/dest" Nothing Nothing],
                  commands = [],
                  dependencies = [],
                  removal = Nothing,
                  migrations = []
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
          m.name `shouldBe` "haskell-base"
          length (m.vars) `shouldBe` 3
          length (m.steps) `shouldBe` 5
        Left err -> expectationFailure ("Expected Right, got Left: " <> show err)

    it "returns ModuleNotFound for nonexistent module" $ do
      result <- loadModule ["/nonexistent"] "no-such-module"
      case result of
        Left (ModuleNotFound _ _) -> pure ()
        Left other -> expectationFailure ("Expected ModuleNotFound, got: " <> show other)
        Right _ -> expectationFailure "Expected Left, got Right"
