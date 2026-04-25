module Seihou.Engine.PlanSpec (tests) where

import Data.Aeson qualified as Aeson
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.Encoding qualified as T
import Data.Yaml qualified as Yaml
import Seihou.Core.Module (loadModule)
import Seihou.Core.Types
import Seihou.Engine.Plan
import System.Directory (createDirectoryIfMissing, getCurrentDirectory)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Engine.Plan" spec

-- | Helper to create a temp fixture with files in a @files/@ subdirectory.
withFixture :: [(FilePath, String)] -> (FilePath -> IO a) -> IO a
withFixture files action = do
  withSystemTempDirectory "seihou-plan-test" $ \tmpDir -> do
    mapM_ (createFile tmpDir) files
    action tmpDir
  where
    createFile base (path, content) = do
      let full = base </> "files" </> path
          dir = takeDir full
      createDirectoryIfMissing True dir
      writeFile full content

    takeDir = reverse . dropWhile (/= '/') . reverse

spec :: Spec
spec = do
  describe "parentDirs" $ do
    it "returns empty for a file in the root" $ do
      parentDirs "README.md" `shouldBe` []

    it "returns one directory for a file one level deep" $ do
      parentDirs "src/Lib.hs" `shouldBe` ["src"]

    it "returns two directories for a file two levels deep" $ do
      parentDirs "a/b/c.txt" `shouldBe` ["a", "a/b"]

    it "returns three directories for a file three levels deep" $ do
      parentDirs "a/b/c/d.txt" `shouldBe` ["a", "a/b", "a/b/c"]

  describe "compilePlan" $ do
    it "compiles a Copy step" $ do
      withFixture [("data.txt", "raw content")] $ \baseDir -> do
        let modul =
              Module
                { name = "test",
                  version = Nothing,
                  description = Nothing,
                  vars = [],
                  exports = [],
                  prompts = [],
                  steps = [Step Copy "data.txt" "data.txt" Nothing Nothing],
                  commands = [],
                  dependencies = [],
                  removal = Nothing,
                  migrations = []
                }
            vars = Map.empty
        result <- compilePlan baseDir modul vars
        case result of
          Right ops -> ops `shouldBe` [WriteFileOp "data.txt" "raw content" Copy]
          Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "compiles a Template step with rendering" $ do
      withFixture [("hello.tpl", "Hello, {{name}}!")] $ \baseDir -> do
        let modul =
              Module
                { name = "test",
                  version = Nothing,
                  description = Nothing,
                  vars = [],
                  exports = [],
                  prompts = [],
                  steps = [Step Template "hello.tpl" "hello.txt" Nothing Nothing],
                  commands = [],
                  dependencies = [],
                  removal = Nothing,
                  migrations = []
                }
            vars = Map.fromList [("name", VText "world")]
        result <- compilePlan baseDir modul vars
        case result of
          Right ops -> ops `shouldBe` [WriteFileOp "hello.txt" "Hello, world!" Template]
          Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "skips step when condition is false" $ do
      withFixture [("data.txt", "content")] $ \baseDir -> do
        let modul =
              Module
                { name = "test",
                  version = Nothing,
                  description = Nothing,
                  vars = [],
                  exports = [],
                  prompts = [],
                  steps = [Step Copy "data.txt" "data.txt" (Just (ExprLit False)) Nothing],
                  commands = [],
                  dependencies = [],
                  removal = Nothing,
                  migrations = []
                }
            vars = Map.empty
        result <- compilePlan baseDir modul vars
        case result of
          Right ops -> ops `shouldBe` []
          Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "includes step when condition is true" $ do
      withFixture [("data.txt", "content")] $ \baseDir -> do
        let modul =
              Module
                { name = "test",
                  version = Nothing,
                  description = Nothing,
                  vars = [],
                  exports = [],
                  prompts = [],
                  steps = [Step Copy "data.txt" "data.txt" (Just (ExprLit True)) Nothing],
                  commands = [],
                  dependencies = [],
                  removal = Nothing,
                  migrations = []
                }
            vars = Map.empty
        result <- compilePlan baseDir modul vars
        case result of
          Right ops -> ops `shouldBe` [WriteFileOp "data.txt" "content" Copy]
          Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "evaluates IsSet condition correctly" $ do
      withFixture [("LICENSE", "MIT License")] $ \baseDir -> do
        let modul =
              Module
                { name = "test",
                  version = Nothing,
                  description = Nothing,
                  vars = [],
                  exports = [],
                  prompts = [],
                  steps = [Step Copy "LICENSE" "LICENSE" (Just (ExprIsSet "license")) Nothing],
                  commands = [],
                  dependencies = [],
                  removal = Nothing,
                  migrations = []
                }
        -- Variable IS set
        let vars1 = Map.fromList [("license", VText "MIT")]
        result1 <- compilePlan baseDir modul vars1
        case result1 of
          Right ops -> ops `shouldBe` [WriteFileOp "LICENSE" "MIT License" Copy]
          Left errs -> expectationFailure ("Expected Right, got: " <> show errs)
        -- Variable is NOT set
        let vars2 = Map.empty
        result2 <- compilePlan baseDir modul vars2
        case result2 of
          Right ops -> ops `shouldBe` []
          Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "expands destination path with placeholders" $ do
      withFixture [("pkg.cabal.tpl", "name: {{name}}\n")] $ \baseDir -> do
        let modul =
              Module
                { name = "test",
                  version = Nothing,
                  description = Nothing,
                  vars = [],
                  exports = [],
                  prompts = [],
                  steps = [Step Template "pkg.cabal.tpl" "{{name}}.cabal" Nothing Nothing],
                  commands = [],
                  dependencies = [],
                  removal = Nothing,
                  migrations = []
                }
            vars = Map.fromList [("name", VText "my-app")]
        result <- compilePlan baseDir modul vars
        case result of
          Right ops -> ops `shouldBe` [WriteFileOp "my-app.cabal" "name: my-app\n" Template]
          Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "creates parent directories" $ do
      withFixture [("Lib.hs.tpl", "module Lib where\n")] $ \baseDir -> do
        let modul =
              Module
                { name = "test",
                  version = Nothing,
                  description = Nothing,
                  vars = [],
                  exports = [],
                  prompts = [],
                  steps = [Step Template "Lib.hs.tpl" "src/Lib.hs" Nothing Nothing],
                  commands = [],
                  dependencies = [],
                  removal = Nothing,
                  migrations = []
                }
            vars = Map.empty
        result <- compilePlan baseDir modul vars
        case result of
          Right ops ->
            ops `shouldBe` [CreateDirOp "src", WriteFileOp "src/Lib.hs" "module Lib where\n" Template]
          Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "deduplicates parent directory operations" $ do
      withFixture [("A.hs.tpl", "module A\n"), ("B.hs.tpl", "module B\n")] $ \baseDir -> do
        let modul =
              Module
                { name = "test",
                  version = Nothing,
                  description = Nothing,
                  vars = [],
                  exports = [],
                  prompts = [],
                  steps =
                    [ Step Template "A.hs.tpl" "src/A.hs" Nothing Nothing,
                      Step Template "B.hs.tpl" "src/B.hs" Nothing Nothing
                    ],
                  commands = [],
                  dependencies = [],
                  removal = Nothing,
                  migrations = []
                }
            vars = Map.empty
        result <- compilePlan baseDir modul vars
        case result of
          Right ops ->
            ops
              `shouldBe` [ CreateDirOp "src",
                           WriteFileOp "src/A.hs" "module A\n" Template,
                           WriteFileOp "src/B.hs" "module B\n" Template
                         ]
          Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "propagates template error for unresolved placeholder" $ do
      withFixture [("hello.tpl", "Hello, {{missing}}!")] $ \baseDir -> do
        let modul =
              Module
                { name = "test",
                  version = Nothing,
                  description = Nothing,
                  vars = [],
                  exports = [],
                  prompts = [],
                  steps = [Step Template "hello.tpl" "hello.txt" Nothing Nothing],
                  commands = [],
                  dependencies = [],
                  removal = Nothing,
                  migrations = []
                }
            vars = Map.empty
        result <- compilePlan baseDir modul vars
        case result of
          Left errs -> do
            length errs `shouldBe` 1
            T.isInfixOf "missing" (errs !! 0) `shouldBe` True
          Right _ -> expectationFailure "Expected Left"

    it "compiles a DhallText step" $ do
      withFixture [("greeting.dhall", "\"Hello, {{name}}!\"")] $ \baseDir -> do
        let modul =
              Module
                { name = "test",
                  version = Nothing,
                  description = Nothing,
                  vars = [],
                  exports = [],
                  prompts = [],
                  steps = [Step DhallText "greeting.dhall" "greeting.txt" Nothing Nothing],
                  commands = [],
                  dependencies = [],
                  removal = Nothing,
                  migrations = []
                }
            vars = Map.fromList [("name", VText "world")]
        result <- compilePlan baseDir modul vars
        case result of
          Right ops -> ops `shouldBe` [WriteFileOp "greeting.txt" "Hello, world!" DhallText]
          Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "compiles a DhallText step with Dhall string interpolation" $ do
      let dhallContent =
            "let name = \"{{project.name}}\"\n\
            \let version = \"{{project.version}}\"\n\
            \in \"name: ${name}\\nversion: ${version}\\n\""
      withFixture [("pkg.dhall", T.unpack dhallContent)] $ \baseDir -> do
        let modul =
              Module
                { name = "test",
                  version = Nothing,
                  description = Nothing,
                  vars = [],
                  exports = [],
                  prompts = [],
                  steps = [Step DhallText "pkg.dhall" "pkg.txt" Nothing Nothing],
                  commands = [],
                  dependencies = [],
                  removal = Nothing,
                  migrations = []
                }
            vars = Map.fromList [("project.name", VText "my-app"), ("project.version", VText "0.1.0.0")]
        result <- compilePlan baseDir modul vars
        case result of
          Right ops -> ops `shouldBe` [WriteFileOp "pkg.txt" "name: my-app\nversion: 0.1.0.0\n" DhallText]
          Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "reports error for invalid Dhall in DhallText step" $ do
      withFixture [("bad.dhall", "this is not valid dhall {")] $ \baseDir -> do
        let modul =
              Module
                { name = "test",
                  version = Nothing,
                  description = Nothing,
                  vars = [],
                  exports = [],
                  prompts = [],
                  steps = [Step DhallText "bad.dhall" "out.txt" Nothing Nothing],
                  commands = [],
                  dependencies = [],
                  removal = Nothing,
                  migrations = []
                }
            vars = Map.empty
        result <- compilePlan baseDir modul vars
        case result of
          Left errs -> do
            length errs `shouldSatisfy` (>= 1)
            T.isInfixOf "Dhall" (errs !! 0) `shouldBe` True
          Right _ -> expectationFailure "Expected Left"

    it "compiles a Structured step to JSON" $ do
      withFixture [("data.json.gen", "{ name = \"{{name}}\", version = \"1.0.0\" }\n")] $ \baseDir -> do
        let modul =
              Module
                { name = "test",
                  version = Nothing,
                  description = Nothing,
                  vars = [],
                  exports = [],
                  prompts = [],
                  steps = [Step Structured "data.json.gen" "data.json" Nothing Nothing],
                  commands = [],
                  dependencies = [],
                  removal = Nothing,
                  migrations = []
                }
            vars = Map.fromList [("name", VText "my-app")]
        result <- compilePlan baseDir modul vars
        case result of
          Right ops -> do
            length ops `shouldBe` 1
            let (WriteFileOp dest content strat) = ops !! 0
            dest `shouldBe` "data.json"
            strat `shouldBe` Structured
            -- Parse the JSON to verify it's valid
            case Aeson.eitherDecodeStrict (T.encodeUtf8 content) of
              Left err -> expectationFailure ("Invalid JSON: " <> err)
              Right (val :: Aeson.Value) -> do
                val `shouldBe` Aeson.object [("name", Aeson.String "my-app"), ("version", Aeson.String "1.0.0")]
          Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "compiles a Structured step to YAML" $ do
      withFixture [("config.yaml.gen", "{ name = \"{{name}}\", debug = False }\n")] $ \baseDir -> do
        let modul =
              Module
                { name = "test",
                  version = Nothing,
                  description = Nothing,
                  vars = [],
                  exports = [],
                  prompts = [],
                  steps = [Step Structured "config.yaml.gen" "config.yaml" Nothing Nothing],
                  commands = [],
                  dependencies = [],
                  removal = Nothing,
                  migrations = []
                }
            vars = Map.fromList [("name", VText "my-app")]
        result <- compilePlan baseDir modul vars
        case result of
          Right ops -> do
            length ops `shouldBe` 1
            let (WriteFileOp dest content strat) = ops !! 0
            dest `shouldBe` "config.yaml"
            strat `shouldBe` Structured
            -- Parse the YAML to verify it's valid
            case Yaml.decodeEither' (T.encodeUtf8 content) of
              Left err -> expectationFailure ("Invalid YAML: " <> show err)
              Right (val :: Aeson.Value) -> do
                val `shouldBe` Aeson.object [("debug", Aeson.Bool False), ("name", Aeson.String "my-app")]
          Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "reports error for Structured step with unconvertible Dhall expression" $ do
      -- A lambda cannot be converted to JSON
      withFixture [("bad.gen", "\\(x : Text) -> x\n")] $ \baseDir -> do
        let modul =
              Module
                { name = "test",
                  version = Nothing,
                  description = Nothing,
                  vars = [],
                  exports = [],
                  prompts = [],
                  steps = [Step Structured "bad.gen" "out.json" Nothing Nothing],
                  commands = [],
                  dependencies = [],
                  removal = Nothing,
                  migrations = []
                }
            vars = Map.empty
        result <- compilePlan baseDir modul vars
        case result of
          Left errs -> do
            length errs `shouldSatisfy` (>= 1)
            T.isInfixOf "Cannot convert" (errs !! 0) `shouldBe` True
          Right _ -> expectationFailure "Expected Left"

    it "reports error for unknown output format in Structured step" $ do
      withFixture [("data.gen", "{ name = \"test\" }\n")] $ \baseDir -> do
        let modul =
              Module
                { name = "test",
                  version = Nothing,
                  description = Nothing,
                  vars = [],
                  exports = [],
                  prompts = [],
                  steps = [Step Structured "data.gen" "output.txt" Nothing Nothing],
                  commands = [],
                  dependencies = [],
                  removal = Nothing,
                  migrations = []
                }
            vars = Map.empty
        result <- compilePlan baseDir modul vars
        case result of
          Left errs -> do
            length errs `shouldSatisfy` (>= 1)
            T.isInfixOf "unsupported output format" (errs !! 0) `shouldBe` True
          Right _ -> expectationFailure "Expected Left"

    it "compiles haskell-base fixture end-to-end" $ do
      cwd <- getCurrentDirectory
      let fixtures = cwd </> "test" </> "fixtures"
      result <- loadModule [fixtures] "haskell-base"
      case result of
        Left err -> expectationFailure ("Failed to load module: " <> show err)
        Right modul -> do
          let vars =
                Map.fromList
                  [ ("project.name", VText "my-app"),
                    ("project.version", VText "0.1.0.0"),
                    ("license", VText "MIT")
                  ]
          planResult <- compilePlan (fixtures </> "haskell-base") modul vars
          case planResult of
            Left errs -> expectationFailure ("Expected Right, got: " <> show errs)
            Right ops -> do
              -- Should have operations for README, src/Lib.hs, LICENSE, my-app.cabal, and cabal.project
              let writeOps = [op | op@(WriteFileOp _ _ _) <- ops]
                  dirOps = [op | op@(CreateDirOp _) <- ops]
              length writeOps `shouldBe` 5
              -- README.md with rendered content
              (writeOps !! 0).dest `shouldBe` "README.md"
              T.isInfixOf "my-app" ((writeOps !! 0).content) `shouldBe` True
              -- src/Lib.hs
              (writeOps !! 1).dest `shouldBe` "src/Lib.hs"
              -- LICENSE (copy)
              (writeOps !! 2).dest `shouldBe` "LICENSE"
              -- my-app.cabal (dest expanded from {{project.name}}.cabal)
              (writeOps !! 3).dest `shouldBe` "my-app.cabal"
              T.isInfixOf "my-app" ((writeOps !! 3).content) `shouldBe` True
              -- cabal.project (DhallText)
              (writeOps !! 4).dest `shouldBe` "cabal.project"
              T.isInfixOf "my-app" ((writeOps !! 4).content) `shouldBe` True
              -- Should have CreateDirOp for src/
              dirOps `shouldSatisfy` any (\op -> op.path == "src")
              -- Should have RunCommandOp for the command
              let cmdOps = [op | op@(RunCommandOp _ _) <- ops]
              length cmdOps `shouldBe` 1
              (cmdOps !! 0).command `shouldBe` "echo 'Project generated'"

    it "compiles a Template step with patch = AppendFile to PatchFileOp" $ do
      withFixture [("section.tpl", "appended content")] $ \baseDir -> do
        let modul =
              Module
                { name = "patch-mod",
                  version = Nothing,
                  description = Nothing,
                  vars = [],
                  exports = [],
                  prompts = [],
                  steps = [Step Template "section.tpl" "README.md" Nothing (Just AppendFile)],
                  commands = [],
                  dependencies = [],
                  removal = Nothing,
                  migrations = []
                }
            vars = Map.empty
        result <- compilePlan baseDir modul vars
        case result of
          Right ops ->
            ops `shouldBe` [PatchFileOp "README.md" "appended content" AppendFile Template "patch-mod"]
          Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "compiles a Template step with patch = AppendSection to PatchFileOp" $ do
      withFixture [("section.tpl", "section {{name}}")] $ \baseDir -> do
        let modul =
              Module
                { name = "section-mod",
                  version = Nothing,
                  description = Nothing,
                  vars = [],
                  exports = [],
                  prompts = [],
                  steps = [Step Template "section.tpl" "README.md" Nothing (Just AppendSection)],
                  commands = [],
                  dependencies = [],
                  removal = Nothing,
                  migrations = []
                }
            vars = Map.fromList [("name", VText "test")]
        result <- compilePlan baseDir modul vars
        case result of
          Right ops ->
            ops `shouldBe` [PatchFileOp "README.md" "section test" AppendSection Template "section-mod"]
          Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "compiles a Template step containing {{#if}} and selects the then-branch" $ do
      let tpl = "prefix\n{{#if Eq flag true}}hot\n{{/if}}suffix\n"
      withFixture [("conditional.tpl", tpl)] $ \baseDir -> do
        let modul =
              Module
                { name = "cond-mod",
                  version = Nothing,
                  description = Nothing,
                  vars = [],
                  exports = [],
                  prompts = [],
                  steps = [Step Template "conditional.tpl" "out.txt" Nothing Nothing],
                  commands = [],
                  dependencies = [],
                  removal = Nothing,
                  migrations = []
                }
            vars = Map.fromList [("flag", VBool True)]
        result <- compilePlan baseDir modul vars
        case result of
          Right ops ->
            ops `shouldBe` [WriteFileOp "out.txt" "prefix\nhot\nsuffix\n" Template]
          Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "compiles a Template step containing {{#if}} and drops the untaken branch" $ do
      let tpl = "prefix\n{{#if Eq flag true}}hot\n{{/if}}suffix\n"
      withFixture [("conditional.tpl", tpl)] $ \baseDir -> do
        let modul =
              Module
                { name = "cond-mod",
                  version = Nothing,
                  description = Nothing,
                  vars = [],
                  exports = [],
                  prompts = [],
                  steps = [Step Template "conditional.tpl" "out.txt" Nothing Nothing],
                  commands = [],
                  dependencies = [],
                  removal = Nothing,
                  migrations = []
                }
            vars = Map.fromList [("flag", VBool False)]
        result <- compilePlan baseDir modul vars
        case result of
          Right ops ->
            ops `shouldBe` [WriteFileOp "out.txt" "prefix\nsuffix\n" Template]
          Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "compiles a Template patch step whose body uses {{#if}}" $ do
      let tpl = "base{{#if Eq flag true}} extra{{/if}}\n"
      withFixture [("patch.tpl", tpl)] $ \baseDir -> do
        let modul =
              Module
                { name = "patch-cond-mod",
                  version = Nothing,
                  description = Nothing,
                  vars = [],
                  exports = [],
                  prompts = [],
                  steps = [Step Template "patch.tpl" "README.md" Nothing (Just AppendFile)],
                  commands = [],
                  dependencies = [],
                  removal = Nothing,
                  migrations = []
                }
            vars = Map.fromList [("flag", VBool True)]
        result <- compilePlan baseDir modul vars
        case result of
          Right ops ->
            ops
              `shouldBe` [PatchFileOp "README.md" "base extra\n" AppendFile Template "patch-cond-mod"]
          Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "compiles a Copy step with patch = PrependFile to PatchFileOp" $ do
      withFixture [("header.txt", "header line\n")] $ \baseDir -> do
        let modul =
              Module
                { name = "header-mod",
                  version = Nothing,
                  description = Nothing,
                  vars = [],
                  exports = [],
                  prompts = [],
                  steps = [Step Copy "header.txt" "out.txt" Nothing (Just PrependFile)],
                  commands = [],
                  dependencies = [],
                  removal = Nothing,
                  migrations = []
                }
            vars = Map.empty
        result <- compilePlan baseDir modul vars
        case result of
          Right ops ->
            ops `shouldBe` [PatchFileOp "out.txt" "header line\n" PrependFile Copy "header-mod"]
          Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "rejects Structured strategy with patch operation" $ do
      withFixture [("data.gen", "{ name = \"test\" }\n")] $ \baseDir -> do
        let modul =
              Module
                { name = "test",
                  version = Nothing,
                  description = Nothing,
                  vars = [],
                  exports = [],
                  prompts = [],
                  steps = [Step Structured "data.gen" "data.json" Nothing (Just AppendFile)],
                  commands = [],
                  dependencies = [],
                  removal = Nothing,
                  migrations = []
                }
            vars = Map.empty
        result <- compilePlan baseDir modul vars
        case result of
          Left errs -> do
            length errs `shouldSatisfy` (>= 1)
            T.isInfixOf "Structured" (errs !! 0) `shouldBe` True
          Right _ -> expectationFailure "Expected Left"

    it "compiles unconditional command to RunCommandOp" $ do
      withFixture [("data.txt", "content")] $ \baseDir -> do
        let modul =
              Module
                { name = "test",
                  version = Nothing,
                  description = Nothing,
                  vars = [],
                  exports = [],
                  prompts = [],
                  steps = [Step Copy "data.txt" "data.txt" Nothing Nothing],
                  commands = [Command "echo hello" Nothing Nothing],
                  dependencies = [],
                  removal = Nothing,
                  migrations = []
                }
            vars = Map.empty
        result <- compilePlan baseDir modul vars
        case result of
          Right ops -> do
            let cmdOps = [op | op@(RunCommandOp _ _) <- ops]
            length cmdOps `shouldBe` 1
            (cmdOps !! 0).command `shouldBe` "echo hello"
            (cmdOps !! 0).workDir `shouldBe` Nothing
          Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "skips command when condition is false" $ do
      withFixture [("data.txt", "content")] $ \baseDir -> do
        let modul =
              Module
                { name = "test",
                  version = Nothing,
                  description = Nothing,
                  vars = [],
                  exports = [],
                  prompts = [],
                  steps = [Step Copy "data.txt" "data.txt" Nothing Nothing],
                  commands = [Command "echo skip" Nothing (Just (ExprLit False))],
                  dependencies = [],
                  removal = Nothing,
                  migrations = []
                }
            vars = Map.empty
        result <- compilePlan baseDir modul vars
        case result of
          Right ops -> do
            let cmdOps = [op | op@(RunCommandOp _ _) <- ops]
            length cmdOps `shouldBe` 0
          Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "includes command when condition is true" $ do
      withFixture [("data.txt", "content")] $ \baseDir -> do
        let modul =
              Module
                { name = "test",
                  version = Nothing,
                  description = Nothing,
                  vars = [],
                  exports = [],
                  prompts = [],
                  steps = [Step Copy "data.txt" "data.txt" Nothing Nothing],
                  commands = [Command "echo yes" Nothing (Just (ExprIsSet "name"))],
                  dependencies = [],
                  removal = Nothing,
                  migrations = []
                }
            vars = Map.fromList [("name", VText "test")]
        result <- compilePlan baseDir modul vars
        case result of
          Right ops -> do
            let cmdOps = [op | op@(RunCommandOp _ _) <- ops]
            length cmdOps `shouldBe` 1
          Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "places commands after file operations in compiled plan" $ do
      withFixture [("data.txt", "content")] $ \baseDir -> do
        let modul =
              Module
                { name = "test",
                  version = Nothing,
                  description = Nothing,
                  vars = [],
                  exports = [],
                  prompts = [],
                  steps = [Step Copy "data.txt" "data.txt" Nothing Nothing],
                  commands = [Command "echo post" Nothing Nothing],
                  dependencies = [],
                  removal = Nothing,
                  migrations = []
                }
            vars = Map.empty
        result <- compilePlan baseDir modul vars
        case result of
          Right ops -> do
            let isFileOp (WriteFileOp {}) = True
                isFileOp (CreateDirOp {}) = True
                isFileOp (CopyFileOp {}) = True
                isFileOp (PatchFileOp {}) = True
                isFileOp _ = False
                isCmdOp (RunCommandOp {}) = True
                isCmdOp _ = False
                fileOps = filter isFileOp ops
                cmdOps = filter isCmdOp ops
            -- Commands should come after all file ops
            ops `shouldBe` (fileOps ++ cmdOps)
          Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "compiles command with workDir" $ do
      withFixture [("data.txt", "content")] $ \baseDir -> do
        let modul =
              Module
                { name = "test",
                  version = Nothing,
                  description = Nothing,
                  vars = [],
                  exports = [],
                  prompts = [],
                  steps = [Step Copy "data.txt" "data.txt" Nothing Nothing],
                  commands = [Command "npm install" (Just "subdir") Nothing],
                  dependencies = [],
                  removal = Nothing,
                  migrations = []
                }
            vars = Map.empty
        result <- compilePlan baseDir modul vars
        case result of
          Right ops -> do
            let cmdOps = [op | op@(RunCommandOp _ _) <- ops]
            length cmdOps `shouldBe` 1
            (cmdOps !! 0).workDir `shouldBe` Just "subdir"
          Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "interpolates {{var}} in command run field" $ do
      withFixture [("data.txt", "content")] $ \baseDir -> do
        let modul =
              Module
                { name = "test",
                  version = Nothing,
                  description = Nothing,
                  vars = [],
                  exports = [],
                  prompts = [],
                  steps = [Step Copy "data.txt" "data.txt" Nothing Nothing],
                  commands = [Command "echo {{name}}" Nothing Nothing],
                  dependencies = [],
                  removal = Nothing,
                  migrations = []
                }
            vars = Map.fromList [("name", VText "my-app")]
        result <- compilePlan baseDir modul vars
        case result of
          Right ops -> do
            let cmdOps = [op | op@(RunCommandOp _ _) <- ops]
            length cmdOps `shouldBe` 1
            (cmdOps !! 0).command `shouldBe` "echo my-app"
          Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "interpolates {{var}} in command workDir field" $ do
      withFixture [("data.txt", "content")] $ \baseDir -> do
        let modul =
              Module
                { name = "test",
                  version = Nothing,
                  description = Nothing,
                  vars = [],
                  exports = [],
                  prompts = [],
                  steps = [Step Copy "data.txt" "data.txt" Nothing Nothing],
                  commands = [Command "cabal build" (Just "{{name}}") Nothing],
                  dependencies = [],
                  removal = Nothing,
                  migrations = []
                }
            vars = Map.fromList [("name", VText "my-app")]
        result <- compilePlan baseDir modul vars
        case result of
          Right ops -> do
            let cmdOps = [op | op@(RunCommandOp _ _) <- ops]
            length cmdOps `shouldBe` 1
            (cmdOps !! 0).workDir `shouldBe` Just "my-app"
          Left errs -> expectationFailure ("Expected Right, got: " <> show errs)

    it "fails compilation when command has unresolved placeholder" $ do
      withFixture [("data.txt", "content")] $ \baseDir -> do
        let modul =
              Module
                { name = "test",
                  version = Nothing,
                  description = Nothing,
                  vars = [],
                  exports = [],
                  prompts = [],
                  steps = [Step Copy "data.txt" "data.txt" Nothing Nothing],
                  commands = [Command "echo {{missing}}" Nothing Nothing],
                  dependencies = [],
                  removal = Nothing,
                  migrations = []
                }
            vars = Map.empty
        result <- compilePlan baseDir modul vars
        case result of
          Left errs -> do
            length errs `shouldSatisfy` (>= 1)
            T.isInfixOf "missing" (errs !! 0) `shouldBe` True
          Right _ -> expectationFailure "Expected Left"
