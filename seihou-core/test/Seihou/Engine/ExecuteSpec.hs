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
      let ops = [WriteFileOp "hello.txt" "hello world"]
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
          ops = [WriteFileOp "test.txt" content]
          (records, _) = runExecFS emptyFS ops
          record = records Map.! "test.txt"
      fileHash record `shouldBe` hashContent content

    it "produces FileRecord with correct module name" $ do
      let ops = [WriteFileOp "test.txt" "data"]
          (records, _) = runExecFS emptyFS ops
          record = records Map.! "test.txt"
      fileModule record `shouldBe` modName

    it "produces FileRecord with correct timestamp" $ do
      let ops = [WriteFileOp "test.txt" "data"]
          (records, _) = runExecFS emptyFS ops
          record = records Map.! "test.txt"
      fileGeneratedAt record `shouldBe` fixedTime

    it "handles multiple operations" $ do
      let ops =
            [ CreateDirOp "src",
              WriteFileOp "README.md" "# Hello",
              WriteFileOp "src/Main.hs" "module Main where"
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

  describe "dryRunPlan" $ do
    it "formats WriteFileOp" $ do
      let result = dryRunPlan [WriteFileOp "README.md" "content"]
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

    it "does not include file content" $ do
      let result = dryRunPlan [WriteFileOp "secret.txt" "super secret"]
      T.isInfixOf "super secret" result `shouldBe` False
