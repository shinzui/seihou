module Seihou.Engine.ValidateSpec (tests) where

import Data.Text qualified as T
import Seihou.Core.Types
import Seihou.Engine.Validate
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Engine.Validate" spec

-- | A well-formed module for validation tests.
goodModule :: Module
goodModule =
  Module
    { name = "test-module",
      version = Nothing,
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
      removable = False
    }

-- | A module with multiple validation errors.
badModule :: Module
badModule =
  Module
    { name = "BadName",
      version = Nothing,
      description = Nothing,
      vars =
        [ VarDecl "x" VTText Nothing Nothing True Nothing,
          VarDecl "x" VTBool Nothing Nothing False Nothing
        ],
      exports = [VarExport {var = "nonexistent", alias = Nothing}],
      prompts = [Prompt {var = "undeclared", text = "?", condition = Nothing, choices = Nothing}],
      steps = [Step Template "missing.tpl" "/absolute/path" Nothing Nothing],
      commands = [],
      dependencies = [],
      removable = False
    }

-- | Helper to update Module fields without ambiguity.
withVars :: [VarDecl] -> Module -> Module
withVars v m = Module m.name m.version m.description v m.exports m.prompts m.steps m.commands m.dependencies m.removable

withSteps :: [Step] -> Module -> Module
withSteps s m = Module m.name m.version m.description m.vars m.exports m.prompts s m.commands m.dependencies m.removable

withPrompts :: [Prompt] -> Module -> Module
withPrompts p m = Module m.name m.version m.description m.vars m.exports p m.steps m.commands m.dependencies m.removable

withCommands :: [Command] -> Module -> Module
withCommands c m = Module m.name m.version m.description m.vars m.exports m.prompts m.steps c m.dependencies m.removable

withVarsAndPrompts :: [VarDecl] -> [Prompt] -> Module -> Module
withVarsAndPrompts v p m = Module m.name m.version m.description v m.exports p m.steps m.commands m.dependencies m.removable

-- | Helper: check if any DiagCheck has the given label and non-empty details.
hasFailedCheck :: T.Text -> [DiagCheck] -> Bool
hasFailedCheck label = any (\c -> c.diagLabel == label && not (null (c.diagDetails)))

-- | Helper: check if any DiagCheck has the given label and empty details (pass).
hasPassedCheck :: T.Text -> [DiagCheck] -> Bool
hasPassedCheck label = any (\c -> c.diagLabel == label && null (c.diagDetails))

-- | Helper: count checks with non-empty details of a given severity.
countFailures :: DiagSeverity -> [DiagCheck] -> Int
countFailures sev = length . filter (\c -> c.diagSeverity == sev && not (null (c.diagDetails)))

spec :: Spec
spec = do
  describe "buildReport" $ do
    it "produces all-pass checks for a valid module" $ do
      withSystemTempDirectory "seihou-validate" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "files")
        writeFile (tmpDir </> "files" </> "README.md.tpl") "stub"
        report <- buildReport False tmpDir goodModule
        report.reportDhallOk `shouldBe` True
        reportHasErrors report `shouldBe` False
        countFailures DiagError report.reportChecks `shouldBe` 0

    it "detects module name format errors" $ do
      withSystemTempDirectory "seihou-validate" $ \tmpDir -> do
        report <- buildReport False tmpDir badModule
        hasFailedCheck "Module name format" report.reportChecks `shouldBe` True

    it "detects duplicate variable names" $ do
      withSystemTempDirectory "seihou-validate" $ \tmpDir -> do
        report <- buildReport False tmpDir badModule
        hasFailedCheck "Unique variable names" report.reportChecks `shouldBe` True

    it "detects export referencing undeclared variable" $ do
      withSystemTempDirectory "seihou-validate" $ \tmpDir -> do
        report <- buildReport False tmpDir badModule
        hasFailedCheck "Export references" report.reportChecks `shouldBe` True

    it "detects prompt referencing undeclared variable" $ do
      withSystemTempDirectory "seihou-validate" $ \tmpDir -> do
        report <- buildReport False tmpDir badModule
        hasFailedCheck "Prompt references" report.reportChecks `shouldBe` True

    it "detects missing source files" $ do
      withSystemTempDirectory "seihou-validate" $ \tmpDir -> do
        report <- buildReport False tmpDir badModule
        hasFailedCheck "Source file existence" report.reportChecks `shouldBe` True

    it "detects unsafe step destinations" $ do
      withSystemTempDirectory "seihou-validate" $ \tmpDir -> do
        report <- buildReport False tmpDir badModule
        hasFailedCheck "Safe step destinations" report.reportChecks `shouldBe` True

    it "reports multiple errors at once" $ do
      withSystemTempDirectory "seihou-validate" $ \tmpDir -> do
        report <- buildReport False tmpDir badModule
        reportHasErrors report `shouldBe` True
        countFailures DiagError report.reportChecks `shouldSatisfy` (>= 5)

    it "does not include lint checks when lint is False" $ do
      withSystemTempDirectory "seihou-validate" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "files")
        writeFile (tmpDir </> "files" </> "README.md.tpl") "stub"
        report <- buildReport False tmpDir goodModule
        let hasWarning = any (\c -> c.diagSeverity == DiagWarning) report.reportChecks
        hasWarning `shouldBe` False

    it "includes lint checks when lint is True" $ do
      withSystemTempDirectory "seihou-validate" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "files")
        writeFile (tmpDir </> "files" </> "README.md.tpl") "stub"
        report <- buildReport True tmpDir goodModule
        let hasWarning = any (\c -> c.diagSeverity == DiagWarning) report.reportChecks
        hasWarning `shouldBe` True

  describe "lint checks" $ do
    it "detects unused variables" $ do
      withSystemTempDirectory "seihou-validate" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "files")
        writeFile (tmpDir </> "files" </> "README.md.tpl") "stub"
        let m =
              withVars
                [ VarDecl "project.name" VTText Nothing (Just "Name") True Nothing,
                  VarDecl "unused.var" VTText Nothing (Just "Unused") False Nothing
                ]
                goodModule
        report <- buildReport True tmpDir m
        hasFailedCheck "Unused variables" report.reportChecks `shouldBe` True
        let details = concatMap (.diagDetails) $ filter (\c -> c.diagLabel == "Unused variables") report.reportChecks
        any (T.isInfixOf "unused.var") details `shouldBe` True

    it "does not flag used variables as unused" $ do
      withSystemTempDirectory "seihou-validate" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "files")
        writeFile (tmpDir </> "files" </> "README.md.tpl") "stub"
        report <- buildReport True tmpDir goodModule
        hasFailedCheck "Unused variables" report.reportChecks `shouldBe` False

    it "detects required variables without prompts" $ do
      withSystemTempDirectory "seihou-validate" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "files")
        writeFile (tmpDir </> "files" </> "README.md.tpl") "stub"
        let m =
              withVarsAndPrompts
                [VarDecl "project.name" VTText Nothing (Just "Name") True Nothing]
                []
                goodModule
        report <- buildReport True tmpDir m
        hasFailedCheck "Required variables without prompts" report.reportChecks `shouldBe` True

    it "does not flag required variables that have prompts" $ do
      withSystemTempDirectory "seihou-validate" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "files")
        writeFile (tmpDir </> "files" </> "README.md.tpl") "stub"
        report <- buildReport True tmpDir goodModule
        hasFailedCheck "Required variables without prompts" report.reportChecks `shouldBe` False

    it "detects duplicate step destinations" $ do
      withSystemTempDirectory "seihou-validate" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "files")
        writeFile (tmpDir </> "files" </> "a.tpl") "stub"
        writeFile (tmpDir </> "files" </> "b.tpl") "stub"
        let m =
              withSteps
                [ Step Template "a.tpl" "out.txt" Nothing Nothing,
                  Step Template "b.tpl" "out.txt" Nothing Nothing
                ]
                goodModule
        report <- buildReport True tmpDir m
        hasFailedCheck "Duplicate step destinations" report.reportChecks `shouldBe` True

    it "does not flag patch ops as duplicate destinations" $ do
      withSystemTempDirectory "seihou-validate" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "files")
        writeFile (tmpDir </> "files" </> "a.tpl") "stub"
        writeFile (tmpDir </> "files" </> "b.tpl") "stub"
        let m =
              withSteps
                [ Step Template "a.tpl" "out.txt" Nothing Nothing,
                  Step Template "b.tpl" "out.txt" Nothing (Just AppendFile)
                ]
                goodModule
        report <- buildReport True tmpDir m
        hasFailedCheck "Duplicate step destinations" report.reportChecks `shouldBe` False

    it "detects empty choice lists" $ do
      withSystemTempDirectory "seihou-validate" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "files")
        writeFile (tmpDir </> "files" </> "README.md.tpl") "stub"
        let m =
              withVars
                [VarDecl "pick" (VTChoice []) Nothing (Just "Pick") True Nothing]
                goodModule
        report <- buildReport True tmpDir m
        hasFailedCheck "Empty choice lists" report.reportChecks `shouldBe` True

    it "detects missing variable descriptions" $ do
      withSystemTempDirectory "seihou-validate" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "files")
        writeFile (tmpDir </> "files" </> "README.md.tpl") "stub"
        let m =
              withVars
                [VarDecl "project.name" VTText Nothing Nothing True Nothing]
                goodModule
        report <- buildReport True tmpDir m
        hasFailedCheck "Missing variable descriptions" report.reportChecks `shouldBe` True

    it "does not flag variables with descriptions" $ do
      withSystemTempDirectory "seihou-validate" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "files")
        writeFile (tmpDir </> "files" </> "README.md.tpl") "stub"
        report <- buildReport True tmpDir goodModule
        hasFailedCheck "Missing variable descriptions" report.reportChecks `shouldBe` False

  describe "renderReportPlain" $ do
    it "renders a valid module report with check marks" $ do
      withSystemTempDirectory "seihou-validate" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "files")
        writeFile (tmpDir </> "files" </> "README.md.tpl") "stub"
        report <- buildReport False tmpDir goodModule
        let rendered = renderReportPlain report
        T.isInfixOf "\x2713 module.dhall evaluates successfully" rendered `shouldBe` True
        T.isInfixOf "\x2713 Module name: test-module" rendered `shouldBe` True
        T.isInfixOf "Module 'test-module' is valid." rendered `shouldBe` True

    it "renders an invalid module report with cross marks and error count" $ do
      withSystemTempDirectory "seihou-validate" $ \tmpDir -> do
        report <- buildReport False tmpDir badModule
        let rendered = renderReportPlain report
        T.isInfixOf "\x2717 Module name format" rendered `shouldBe` True
        T.isInfixOf "error(s) found. Module is invalid." rendered `shouldBe` True

    it "renders a Dhall-failure report" $ do
      let report =
            ValidateReport
              { reportModule = goodModule,
                reportPath = "/some/path",
                reportDhallOk = False,
                reportDhallError = Just "test error message",
                reportChecks = []
              }
          rendered = renderReportPlain report
      T.isInfixOf "\x2717 module.dhall failed to evaluate" rendered `shouldBe` True
      T.isInfixOf "test error message" rendered `shouldBe` True
      T.isInfixOf "1 error(s) found. Module is invalid." rendered `shouldBe` True

    it "renders a Dhall-failure report without error details when absent" $ do
      let report =
            ValidateReport
              { reportModule = goodModule,
                reportPath = "/some/path",
                reportDhallOk = False,
                reportDhallError = Nothing,
                reportChecks = []
              }
          rendered = renderReportPlain report
      T.isInfixOf "\x2717 module.dhall failed to evaluate" rendered `shouldBe` True
      T.isInfixOf "1 error(s) found. Module is invalid." rendered `shouldBe` True

    it "renders lint warnings with warning symbol" $ do
      withSystemTempDirectory "seihou-validate" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "files")
        writeFile (tmpDir </> "files" </> "README.md.tpl") "stub"
        let m =
              withVars
                [ VarDecl "project.name" VTText Nothing (Just "Name") True Nothing,
                  VarDecl "unused" VTText Nothing (Just "Unused") False Nothing
                ]
                goodModule
        report <- buildReport True tmpDir m
        let rendered = renderReportPlain report
        T.isInfixOf "\x26A0 Unused variables" rendered `shouldBe` True

  describe "reportHasErrors" $ do
    it "returns False for a valid report" $ do
      withSystemTempDirectory "seihou-validate" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "files")
        writeFile (tmpDir </> "files" </> "README.md.tpl") "stub"
        report <- buildReport False tmpDir goodModule
        reportHasErrors report `shouldBe` False

    it "returns True for a report with errors" $ do
      withSystemTempDirectory "seihou-validate" $ \tmpDir -> do
        report <- buildReport False tmpDir badModule
        reportHasErrors report `shouldBe` True

    it "returns False when only warnings are present" $ do
      withSystemTempDirectory "seihou-validate" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "files")
        writeFile (tmpDir </> "files" </> "README.md.tpl") "stub"
        let m =
              withVars
                [ VarDecl "project.name" VTText Nothing (Just "Name") True Nothing,
                  VarDecl "unused" VTText Nothing (Just "Unused") False Nothing
                ]
                goodModule
        report <- buildReport True tmpDir m
        reportHasErrors report `shouldBe` False

    it "returns True when Dhall failed" $ do
      let report =
            ValidateReport
              { reportModule = goodModule,
                reportPath = "/some/path",
                reportDhallOk = False,
                reportDhallError = Just "some dhall error",
                reportChecks = []
              }
      reportHasErrors report `shouldBe` True

  describe "command safety" $ do
    it "passes for valid commands" $ do
      withSystemTempDirectory "seihou-validate" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "files")
        writeFile (tmpDir </> "files" </> "README.md.tpl") "stub"
        let m = withCommands [Command "echo hello" Nothing Nothing] goodModule
        report <- buildReport False tmpDir m
        hasPassedCheck "Command safety" report.reportChecks `shouldBe` True

    it "fails for empty command text" $ do
      withSystemTempDirectory "seihou-validate" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "files")
        writeFile (tmpDir </> "files" </> "README.md.tpl") "stub"
        let m = withCommands [Command "  " Nothing Nothing] goodModule
        report <- buildReport False tmpDir m
        hasFailedCheck "Command safety" report.reportChecks `shouldBe` True

    it "fails for absolute workDir" $ do
      withSystemTempDirectory "seihou-validate" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "files")
        writeFile (tmpDir </> "files" </> "README.md.tpl") "stub"
        let m = withCommands [Command "echo hi" (Just "/usr/local") Nothing] goodModule
        report <- buildReport False tmpDir m
        hasFailedCheck "Command safety" report.reportChecks `shouldBe` True

    it "fails for workDir containing .." $ do
      withSystemTempDirectory "seihou-validate" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "files")
        writeFile (tmpDir </> "files" </> "README.md.tpl") "stub"
        let m = withCommands [Command "echo hi" (Just "../escape") Nothing] goodModule
        report <- buildReport False tmpDir m
        hasFailedCheck "Command safety" report.reportChecks `shouldBe` True
