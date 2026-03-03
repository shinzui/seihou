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
              stepWhen = Nothing,
              stepPatch = Nothing
            }
        ],
      moduleCommands = [],
      moduleDependencies = []
    }

-- | A module with multiple validation errors.
badModule :: Module
badModule =
  Module
    { moduleName = "BadName",
      moduleDescription = Nothing,
      moduleVars =
        [ VarDecl "x" VTText Nothing Nothing True Nothing,
          VarDecl "x" VTBool Nothing Nothing False Nothing
        ],
      moduleExports = [VarExport {exportVar = "nonexistent", exportAs = Nothing}],
      modulePrompts = [Prompt {promptVar = "undeclared", promptText = "?", promptWhen = Nothing, promptChoices = Nothing}],
      moduleSteps = [Step Template "missing.tpl" "/absolute/path" Nothing Nothing],
      moduleCommands = [],
      moduleDependencies = []
    }

-- | Helper: check if any DiagCheck has the given label and non-empty details.
hasFailedCheck :: T.Text -> [DiagCheck] -> Bool
hasFailedCheck label = any (\c -> diagLabel c == label && not (null (diagDetails c)))

-- | Helper: check if any DiagCheck has the given label and empty details (pass).
hasPassedCheck :: T.Text -> [DiagCheck] -> Bool
hasPassedCheck label = any (\c -> diagLabel c == label && null (diagDetails c))

-- | Helper: count checks with non-empty details of a given severity.
countFailures :: DiagSeverity -> [DiagCheck] -> Int
countFailures sev = length . filter (\c -> diagSeverity c == sev && not (null (diagDetails c)))

spec :: Spec
spec = do
  describe "buildReport" $ do
    it "produces all-pass checks for a valid module" $ do
      withSystemTempDirectory "seihou-validate" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "files")
        writeFile (tmpDir </> "files" </> "README.md.tpl") "stub"
        report <- buildReport False tmpDir goodModule
        reportDhallOk report `shouldBe` True
        reportHasErrors report `shouldBe` False
        countFailures DiagError (reportChecks report) `shouldBe` 0

    it "detects module name format errors" $ do
      withSystemTempDirectory "seihou-validate" $ \tmpDir -> do
        report <- buildReport False tmpDir badModule
        hasFailedCheck "Module name format" (reportChecks report) `shouldBe` True

    it "detects duplicate variable names" $ do
      withSystemTempDirectory "seihou-validate" $ \tmpDir -> do
        report <- buildReport False tmpDir badModule
        hasFailedCheck "Unique variable names" (reportChecks report) `shouldBe` True

    it "detects export referencing undeclared variable" $ do
      withSystemTempDirectory "seihou-validate" $ \tmpDir -> do
        report <- buildReport False tmpDir badModule
        hasFailedCheck "Export references" (reportChecks report) `shouldBe` True

    it "detects prompt referencing undeclared variable" $ do
      withSystemTempDirectory "seihou-validate" $ \tmpDir -> do
        report <- buildReport False tmpDir badModule
        hasFailedCheck "Prompt references" (reportChecks report) `shouldBe` True

    it "detects missing source files" $ do
      withSystemTempDirectory "seihou-validate" $ \tmpDir -> do
        report <- buildReport False tmpDir badModule
        hasFailedCheck "Source file existence" (reportChecks report) `shouldBe` True

    it "detects unsafe step destinations" $ do
      withSystemTempDirectory "seihou-validate" $ \tmpDir -> do
        report <- buildReport False tmpDir badModule
        hasFailedCheck "Safe step destinations" (reportChecks report) `shouldBe` True

    it "reports multiple errors at once" $ do
      withSystemTempDirectory "seihou-validate" $ \tmpDir -> do
        report <- buildReport False tmpDir badModule
        reportHasErrors report `shouldBe` True
        countFailures DiagError (reportChecks report) `shouldSatisfy` (>= 5)

    it "does not include lint checks when lint is False" $ do
      withSystemTempDirectory "seihou-validate" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "files")
        writeFile (tmpDir </> "files" </> "README.md.tpl") "stub"
        report <- buildReport False tmpDir goodModule
        let hasWarning = any (\c -> diagSeverity c == DiagWarning) (reportChecks report)
        hasWarning `shouldBe` False

    it "includes lint checks when lint is True" $ do
      withSystemTempDirectory "seihou-validate" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "files")
        writeFile (tmpDir </> "files" </> "README.md.tpl") "stub"
        report <- buildReport True tmpDir goodModule
        let hasWarning = any (\c -> diagSeverity c == DiagWarning) (reportChecks report)
        hasWarning `shouldBe` True

  describe "lint checks" $ do
    it "detects unused variables" $ do
      withSystemTempDirectory "seihou-validate" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "files")
        writeFile (tmpDir </> "files" </> "README.md.tpl") "stub"
        let m =
              goodModule
                { moduleVars =
                    [ VarDecl "project.name" VTText Nothing (Just "Name") True Nothing,
                      VarDecl "unused.var" VTText Nothing (Just "Unused") False Nothing
                    ]
                }
        report <- buildReport True tmpDir m
        hasFailedCheck "Unused variables" (reportChecks report) `shouldBe` True
        let details = concatMap diagDetails $ filter (\c -> diagLabel c == "Unused variables") (reportChecks report)
        any (T.isInfixOf "unused.var") details `shouldBe` True

    it "does not flag used variables as unused" $ do
      withSystemTempDirectory "seihou-validate" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "files")
        writeFile (tmpDir </> "files" </> "README.md.tpl") "stub"
        report <- buildReport True tmpDir goodModule
        hasFailedCheck "Unused variables" (reportChecks report) `shouldBe` False

    it "detects required variables without prompts" $ do
      withSystemTempDirectory "seihou-validate" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "files")
        writeFile (tmpDir </> "files" </> "README.md.tpl") "stub"
        let m =
              goodModule
                { moduleVars =
                    [VarDecl "project.name" VTText Nothing (Just "Name") True Nothing],
                  modulePrompts = []
                }
        report <- buildReport True tmpDir m
        hasFailedCheck "Required variables without prompts" (reportChecks report) `shouldBe` True

    it "does not flag required variables that have prompts" $ do
      withSystemTempDirectory "seihou-validate" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "files")
        writeFile (tmpDir </> "files" </> "README.md.tpl") "stub"
        report <- buildReport True tmpDir goodModule
        hasFailedCheck "Required variables without prompts" (reportChecks report) `shouldBe` False

    it "detects duplicate step destinations" $ do
      withSystemTempDirectory "seihou-validate" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "files")
        writeFile (tmpDir </> "files" </> "a.tpl") "stub"
        writeFile (tmpDir </> "files" </> "b.tpl") "stub"
        let m =
              goodModule
                { moduleSteps =
                    [ Step Template "a.tpl" "out.txt" Nothing Nothing,
                      Step Template "b.tpl" "out.txt" Nothing Nothing
                    ]
                }
        report <- buildReport True tmpDir m
        hasFailedCheck "Duplicate step destinations" (reportChecks report) `shouldBe` True

    it "does not flag patch ops as duplicate destinations" $ do
      withSystemTempDirectory "seihou-validate" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "files")
        writeFile (tmpDir </> "files" </> "a.tpl") "stub"
        writeFile (tmpDir </> "files" </> "b.tpl") "stub"
        let m =
              goodModule
                { moduleSteps =
                    [ Step Template "a.tpl" "out.txt" Nothing Nothing,
                      Step Template "b.tpl" "out.txt" Nothing (Just AppendFile)
                    ]
                }
        report <- buildReport True tmpDir m
        hasFailedCheck "Duplicate step destinations" (reportChecks report) `shouldBe` False

    it "detects empty choice lists" $ do
      withSystemTempDirectory "seihou-validate" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "files")
        writeFile (tmpDir </> "files" </> "README.md.tpl") "stub"
        let m =
              goodModule
                { moduleVars =
                    [VarDecl "pick" (VTChoice []) Nothing (Just "Pick") True Nothing]
                }
        report <- buildReport True tmpDir m
        hasFailedCheck "Empty choice lists" (reportChecks report) `shouldBe` True

    it "detects missing variable descriptions" $ do
      withSystemTempDirectory "seihou-validate" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "files")
        writeFile (tmpDir </> "files" </> "README.md.tpl") "stub"
        let m =
              goodModule
                { moduleVars =
                    [VarDecl "project.name" VTText Nothing Nothing True Nothing]
                }
        report <- buildReport True tmpDir m
        hasFailedCheck "Missing variable descriptions" (reportChecks report) `shouldBe` True

    it "does not flag variables with descriptions" $ do
      withSystemTempDirectory "seihou-validate" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "files")
        writeFile (tmpDir </> "files" </> "README.md.tpl") "stub"
        report <- buildReport True tmpDir goodModule
        hasFailedCheck "Missing variable descriptions" (reportChecks report) `shouldBe` False

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
              goodModule
                { moduleVars =
                    [ VarDecl "project.name" VTText Nothing (Just "Name") True Nothing,
                      VarDecl "unused" VTText Nothing (Just "Unused") False Nothing
                    ]
                }
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
              goodModule
                { moduleVars =
                    [ VarDecl "project.name" VTText Nothing (Just "Name") True Nothing,
                      VarDecl "unused" VTText Nothing (Just "Unused") False Nothing
                    ]
                }
        report <- buildReport True tmpDir m
        reportHasErrors report `shouldBe` False

    it "returns True when Dhall failed" $ do
      let report =
            ValidateReport
              { reportModule = goodModule,
                reportPath = "/some/path",
                reportDhallOk = False,
                reportChecks = []
              }
      reportHasErrors report `shouldBe` True

  describe "command safety" $ do
    it "passes for valid commands" $ do
      withSystemTempDirectory "seihou-validate" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "files")
        writeFile (tmpDir </> "files" </> "README.md.tpl") "stub"
        let m = goodModule {moduleCommands = [Command "echo hello" Nothing Nothing]}
        report <- buildReport False tmpDir m
        hasPassedCheck "Command safety" (reportChecks report) `shouldBe` True

    it "fails for empty command text" $ do
      withSystemTempDirectory "seihou-validate" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "files")
        writeFile (tmpDir </> "files" </> "README.md.tpl") "stub"
        let m = goodModule {moduleCommands = [Command "  " Nothing Nothing]}
        report <- buildReport False tmpDir m
        hasFailedCheck "Command safety" (reportChecks report) `shouldBe` True

    it "fails for absolute workDir" $ do
      withSystemTempDirectory "seihou-validate" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "files")
        writeFile (tmpDir </> "files" </> "README.md.tpl") "stub"
        let m = goodModule {moduleCommands = [Command "echo hi" (Just "/usr/local") Nothing]}
        report <- buildReport False tmpDir m
        hasFailedCheck "Command safety" (reportChecks report) `shouldBe` True

    it "fails for workDir containing .." $ do
      withSystemTempDirectory "seihou-validate" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "files")
        writeFile (tmpDir </> "files" </> "README.md.tpl") "stub"
        let m = goodModule {moduleCommands = [Command "echo hi" (Just "../escape") Nothing]}
        report <- buildReport False tmpDir m
        hasFailedCheck "Command safety" (reportChecks report) `shouldBe` True
