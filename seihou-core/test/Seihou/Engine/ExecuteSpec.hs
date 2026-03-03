module Seihou.Engine.ExecuteSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Time (UTCTime, defaultTimeLocale, parseTimeOrError)
import Effectful
import Seihou.Core.Types
import Seihou.Effect.Filesystem (doesDirectoryExist, doesFileExist, readFileText)
import Seihou.Effect.FilesystemPure (PureFS (..), emptyFS, runFilesystemPure)
import Seihou.Engine.Execute (dryRunPlan, executePlan)
import Seihou.Manifest.Hash (hashContent)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Engine.Execute" spec

fixedTime :: UTCTime
fixedTime = parseTimeOrError True defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ" "2026-03-01T10:30:00Z"

modName :: ModuleName
modName = ModuleName "test-module"

-- | Run execution in pure filesystem and return results + final FS state.
runExec :: [Operation] -> ((Map.Map FilePath FileRecord, PureFS), PureFS)
runExec ops =
  runPureEff $
    runFilesystemPure emptyFS $ do
      records <- executePlan "/project" ops modName fixedTime
      fs <- pure () -- just to get the final state via the tuple
      pure (records, emptyFS) -- placeholder; actual FS state is in the outer tuple

-- | More useful helper: run and return records + the pure FS state.
runExecFS :: PureFS -> [Operation] -> (Map.Map FilePath FileRecord, PureFS)
runExecFS initial ops =
  runPureEff $
    runFilesystemPure initial $
      executePlan "/project" ops modName fixedTime

spec :: Spec
spec = do
  describe "executePlan" $ do
    it "writes a file via WriteFileOp" $ do
      let ops = [WriteFileOp "hello.txt" "hello world" Template]
          (records, fs) = runExecFS emptyFS ops
      Map.member "hello.txt" records `shouldBe` True
      Map.lookup "/project/hello.txt" (pureFiles fs) `shouldBe` Just "hello world"

    it "creates a directory via CreateDirOp" $ do
      let ops = [CreateDirOp "src"]
          ((exists, _), _) =
            runPureEff $
              runFilesystemPure emptyFS $ do
                _ <- executePlan "/project" ops modName fixedTime
                e <- doesDirectoryExist "/project/src"
                pure (e, ())
      exists `shouldBe` True

    it "produces FileRecord with correct hash" $ do
      let content = "test content"
          ops = [WriteFileOp "test.txt" content Template]
          (records, _) = runExecFS emptyFS ops
          record = records Map.! "test.txt"
      fileHash record `shouldBe` hashContent content

    it "produces FileRecord with correct module name" $ do
      let ops = [WriteFileOp "test.txt" "data" Template]
          (records, _) = runExecFS emptyFS ops
          record = records Map.! "test.txt"
      fileModule record `shouldBe` modName

    it "produces FileRecord with correct timestamp" $ do
      let ops = [WriteFileOp "test.txt" "data" Template]
          (records, _) = runExecFS emptyFS ops
          record = records Map.! "test.txt"
      fileGeneratedAt record `shouldBe` fixedTime

    it "handles multiple operations" $ do
      let ops =
            [ CreateDirOp "src",
              WriteFileOp "README.md" "# Hello" Template,
              WriteFileOp "src/Main.hs" "module Main where" Template
            ]
          (records, fs) = runExecFS emptyFS ops
      Map.size records `shouldBe` 2
      Map.lookup "/project/README.md" (pureFiles fs) `shouldBe` Just "# Hello"
      Map.lookup "/project/src/Main.hs" (pureFiles fs) `shouldBe` Just "module Main where"

    it "skips RunCommandOp" $ do
      let ops = [RunCommandOp "echo hello" Nothing]
          (records, _) = runExecFS emptyFS ops
      Map.size records `shouldBe` 0

    it "handles CopyFileOp by reading source and writing dest" $ do
      let initial = PureFS (Map.singleton "/source/file.txt" "copied content") mempty
          ops = [CopyFileOp "/source/file.txt" "dest.txt"]
          (records, fs) = runExecFS initial ops
      Map.member "dest.txt" records `shouldBe` True
      Map.lookup "/project/dest.txt" (pureFiles fs) `shouldBe` Just "copied content"

    it "records Template strategy in FileRecord" $ do
      let ops = [WriteFileOp "test.txt" "content" Template]
          (records, _) = runExecFS emptyFS ops
          record = records Map.! "test.txt"
      fileStrategy record `shouldBe` Template

    it "records Copy strategy in FileRecord" $ do
      let ops = [WriteFileOp "test.txt" "content" Copy]
          (records, _) = runExecFS emptyFS ops
          record = records Map.! "test.txt"
      fileStrategy record `shouldBe` Copy

    it "records DhallText strategy in FileRecord" $ do
      let ops = [WriteFileOp "test.txt" "content" DhallText]
          (records, _) = runExecFS emptyFS ops
          record = records Map.! "test.txt"
      fileStrategy record `shouldBe` DhallText

    it "records Structured strategy in FileRecord" $ do
      let ops = [WriteFileOp "test.json" "{}" Structured]
          (records, _) = runExecFS emptyFS ops
          record = records Map.! "test.json"
      fileStrategy record `shouldBe` Structured

    it "executes PatchFileOp AppendFile on existing file" $ do
      let initial = PureFS (Map.singleton "/project/README.md" "# Title\n") mempty
          ops = [PatchFileOp "README.md" "extra line\n" AppendFile Template modName]
          (records, fs) = runExecFS initial ops
      Map.member "README.md" records `shouldBe` True
      let content = pureFiles fs Map.! "/project/README.md"
      T.isInfixOf "# Title" content `shouldBe` True
      T.isInfixOf "extra line" content `shouldBe` True

    it "executes PatchFileOp PrependFile on existing file" $ do
      let initial = PureFS (Map.singleton "/project/README.md" "# Title\n") mempty
          ops = [PatchFileOp "README.md" "header\n" PrependFile Template modName]
          (records, fs) = runExecFS initial ops
      Map.member "README.md" records `shouldBe` True
      let content = pureFiles fs Map.! "/project/README.md"
      T.isInfixOf "header" content `shouldBe` True
      T.isInfixOf "# Title" content `shouldBe` True

    it "executes PatchFileOp AppendSection with section markers" $ do
      let initial = PureFS (Map.singleton "/project/README.md" "# Title\n") mempty
          ops = [PatchFileOp "README.md" "section content\n" AppendSection Template modName]
          (records, fs) = runExecFS initial ops
      Map.member "README.md" records `shouldBe` True
      let content = pureFiles fs Map.! "/project/README.md"
      T.isInfixOf "# Title" content `shouldBe` True
      T.isInfixOf "seihou:test-module" content `shouldBe` True
      T.isInfixOf "section content" content `shouldBe` True

    it "executes PatchFileOp on nonexistent file (creates from empty)" $ do
      let ops = [PatchFileOp "new.txt" "new content\n" AppendFile Template modName]
          (records, fs) = runExecFS emptyFS ops
      Map.member "new.txt" records `shouldBe` True
      let content = pureFiles fs Map.! "/project/new.txt"
      T.isInfixOf "new content" content `shouldBe` True

  describe "dryRunPlan" $ do
    it "formats WriteFileOp" $ do
      let result = dryRunPlan [WriteFileOp "README.md" "content" Template]
      T.isInfixOf "write" result `shouldBe` True
      T.isInfixOf "README.md" result `shouldBe` True

    it "formats CreateDirOp" $ do
      let result = dryRunPlan [CreateDirOp "src"]
      T.isInfixOf "mkdir" result `shouldBe` True
      T.isInfixOf "src" result `shouldBe` True

    it "formats CopyFileOp" $ do
      let result = dryRunPlan [CopyFileOp "src.txt" "dest.txt"]
      T.isInfixOf "copy" result `shouldBe` True

    it "formats RunCommandOp" $ do
      let result = dryRunPlan [RunCommandOp "echo hello" Nothing]
      T.isInfixOf "run" result `shouldBe` True

    it "returns message for empty plan" $ do
      let result = dryRunPlan []
      T.isInfixOf "No operations" result `shouldBe` True

    it "formats PatchFileOp" $ do
      let result = dryRunPlan [PatchFileOp "README.md" "content" AppendSection Template (ModuleName "nix-flake")]
      T.isInfixOf "patch" result `shouldBe` True
      T.isInfixOf "README.md" result `shouldBe` True
      T.isInfixOf "nix-flake" result `shouldBe` True

    it "does not include file content" $ do
      let result = dryRunPlan [WriteFileOp "secret.txt" "super secret" Template]
      T.isInfixOf "super secret" result `shouldBe` False
