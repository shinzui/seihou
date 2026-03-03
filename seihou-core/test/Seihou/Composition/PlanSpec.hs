module Seihou.Composition.PlanSpec (tests) where

import Data.Text qualified as T
import Seihou.Composition.Plan
import Seihou.Core.Types
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Composition.Plan" spec

spec :: Spec
spec = do
  describe "mergeOperations" $ do
    it "preserves all operations when no files overlap" $ do
      let aOps = [CreateDirOp "src", WriteFileOp "src/A.hs" "module A" Template]
          bOps = [CreateDirOp "lib", WriteFileOp "lib/B.hs" "module B" Template]
          (ops, warnings) = mergeOperations [("mod-a", aOps), ("mod-b", bOps)]
      length ops `shouldBe` 4
      warnings `shouldBe` []

    it "last-writer-wins when two modules write same file" $ do
      let aOps = [WriteFileOp "README.md" "from A" Template]
          bOps = [WriteFileOp "README.md" "from B" Template]
          (ops, warnings) = mergeOperations [("mod-a", aOps), ("mod-b", bOps)]
      -- Only B's version should remain
      length (filter isWriteOp ops) `shouldBe` 1
      case filter isWriteOp ops of
        [WriteFileOp _ content _] -> content `shouldBe` "from B"
        _ -> expectationFailure "Expected exactly one WriteFileOp"
      -- Warning should indicate A was overwritten by B
      length warnings `shouldBe` 1
      case warnings of
        [FileOverwritten path overwritten overwriter] -> do
          path `shouldBe` "README.md"
          overwritten `shouldBe` "mod-a"
          overwriter `shouldBe` "mod-b"
        _ -> expectationFailure "Expected one FileOverwritten warning"

    it "deduplicates CreateDirOp silently" $ do
      let aOps = [CreateDirOp "src"]
          bOps = [CreateDirOp "src"]
          (ops, warnings) = mergeOperations [("mod-a", aOps), ("mod-b", bOps)]
      length ops `shouldBe` 1
      warnings `shouldBe` []

    it "keeps all RunCommandOp operations" $ do
      let aOps = [RunCommandOp "echo hello" Nothing]
          bOps = [RunCommandOp "echo world" Nothing]
          (ops, warnings) = mergeOperations [("mod-a", aOps), ("mod-b", bOps)]
      length ops `shouldBe` 2
      warnings `shouldBe` []

    it "handles CopyFileOp overlapping with WriteFileOp" $ do
      let aOps = [WriteFileOp "config.yaml" "generated" Template]
          bOps = [CopyFileOp "files/config.yaml" "config.yaml"]
          (ops, warnings) = mergeOperations [("mod-a", aOps), ("mod-b", bOps)]
      length warnings `shouldBe` 1
      -- B's CopyFileOp should be the winner
      case filter (\op -> destOfOp' op == Just "config.yaml") ops of
        [CopyFileOp {}] -> pure ()
        other -> expectationFailure $ "Expected CopyFileOp, got: " ++ show other

    it "handles three modules with cascading overwrites" $ do
      let aOps = [WriteFileOp "README.md" "from A" Template]
          bOps = [WriteFileOp "README.md" "from B" Template]
          cOps = [WriteFileOp "README.md" "from C" Template]
          (ops, warnings) = mergeOperations [("a", aOps), ("b", bOps), ("c", cOps)]
      -- Only C's version should remain
      case filter isWriteOp ops of
        [WriteFileOp _ content _] -> content `shouldBe` "from C"
        _ -> expectationFailure "Expected exactly one WriteFileOp"
      -- Two warnings: A overwritten by B, B overwritten by C
      length warnings `shouldBe` 2

    it "handles empty module operations" $ do
      let (ops, warnings) = mergeOperations [("a", []), ("b", [])]
      ops `shouldBe` []
      warnings `shouldBe` []

  describe "mergeOperations (text patching)" $ do
    it "PatchFileOp AppendFile merges with existing WriteFileOp" $ do
      let aOps = [WriteFileOp "README.md" "# Title\n" Template]
          bOps = [PatchFileOp "README.md" "extra line\n" AppendFile Template "mod-b"]
          (ops, warnings) = mergeOperations [("mod-a", aOps), ("mod-b", bOps)]
      -- Should be a single merged WriteFileOp
      case filter isWriteOp ops of
        [WriteFileOp _ content _] -> do
          T.isInfixOf "# Title" content `shouldBe` True
          T.isInfixOf "extra line" content `shouldBe` True
        other -> expectationFailure $ "Expected one WriteFileOp, got: " ++ show other
      -- Should produce ContentMerged warning, not FileOverwritten
      case filter isContentMerged warnings of
        [ContentMerged path base contributor] -> do
          path `shouldBe` "README.md"
          base `shouldBe` "mod-a"
          contributor `shouldBe` "mod-b"
        other -> expectationFailure $ "Expected one ContentMerged, got: " ++ show other

    it "PatchFileOp AppendSection adds section markers and merges" $ do
      let aOps = [WriteFileOp "README.md" "# Title\n" Template]
          bOps = [PatchFileOp "README.md" "section content\n" AppendSection Template "mod-b"]
          (ops, _) = mergeOperations [("mod-a", aOps), ("mod-b", bOps)]
      case filter isWriteOp ops of
        [WriteFileOp _ content _] -> do
          T.isInfixOf "# Title" content `shouldBe` True
          T.isInfixOf "seihou:mod-b" content `shouldBe` True
          T.isInfixOf "section content" content `shouldBe` True
        other -> expectationFailure $ "Expected one WriteFileOp, got: " ++ show other

    it "PatchFileOp PrependFile prepends content" $ do
      let aOps = [WriteFileOp "README.md" "# Title\n" Template]
          bOps = [PatchFileOp "README.md" "header\n" PrependFile Template "mod-b"]
          (ops, _) = mergeOperations [("mod-a", aOps), ("mod-b", bOps)]
      case filter isWriteOp ops of
        [WriteFileOp _ content _] -> do
          -- header should appear before Title
          let headerIdx = T.length (fst (T.breakOn "header" content))
              titleIdx = T.length (fst (T.breakOn "# Title" content))
          (headerIdx < titleIdx) `shouldBe` True
        other -> expectationFailure $ "Expected one WriteFileOp, got: " ++ show other

    it "PatchFileOp targeting nonexistent file creates new file" $ do
      let bOps = [PatchFileOp "new.txt" "content\n" AppendFile Template "mod-b"]
          (ops, _) = mergeOperations [("mod-b", bOps)]
      -- PatchFileOp with no existing target becomes a WriteFileOp
      length (filter isWriteOp ops) `shouldBe` 1

    it "multiple patches from different modules accumulate" $ do
      let aOps = [WriteFileOp "README.md" "# Title\n" Template]
          bOps = [PatchFileOp "README.md" "from B\n" AppendSection Template "mod-b"]
          cOps = [PatchFileOp "README.md" "from C\n" AppendSection Template "mod-c"]
          (ops, warnings) = mergeOperations [("mod-a", aOps), ("mod-b", bOps), ("mod-c", cOps)]
      case filter isWriteOp ops of
        [WriteFileOp _ content _] -> do
          T.isInfixOf "# Title" content `shouldBe` True
          T.isInfixOf "from B" content `shouldBe` True
          T.isInfixOf "from C" content `shouldBe` True
          T.isInfixOf "seihou:mod-b" content `shouldBe` True
          T.isInfixOf "seihou:mod-c" content `shouldBe` True
        other -> expectationFailure $ "Expected one WriteFileOp, got: " ++ show other
      -- Two ContentMerged warnings (one for B, one for C)
      length (filter isContentMerged warnings) `shouldBe` 2

    it "ContentMerged warning is generated for patch merge" $ do
      let aOps = [WriteFileOp "f.txt" "base\n" Template]
          bOps = [PatchFileOp "f.txt" "added\n" AppendFile Template "mod-b"]
          (_, warnings) = mergeOperations [("mod-a", aOps), ("mod-b", bOps)]
      any isContentMerged warnings `shouldBe` True
      any isFileOverwritten warnings `shouldBe` False

  describe "mergeOperations (structured merge)" $ do
    it "two Structured WriteFileOps for same JSON dest get deep-merged" $ do
      let aOps = [WriteFileOp "config.json" "{\"name\": \"foo\"}\n" Structured]
          bOps = [WriteFileOp "config.json" "{\"extra\": true}\n" Structured]
          (ops, warnings) = mergeOperations [("mod-a", aOps), ("mod-b", bOps)]
      case filter isWriteOp ops of
        [WriteFileOp _ content _] -> do
          T.isInfixOf "name" content `shouldBe` True
          T.isInfixOf "foo" content `shouldBe` True
          T.isInfixOf "extra" content `shouldBe` True
        other -> expectationFailure $ "Expected one WriteFileOp, got: " ++ show other
      any isContentMerged warnings `shouldBe` True
      any isFileOverwritten warnings `shouldBe` False

    it "disjoint JSON keys are combined" $ do
      let aOps = [WriteFileOp "out.json" "{\"a\": 1}\n" Structured]
          bOps = [WriteFileOp "out.json" "{\"b\": 2}\n" Structured]
          (ops, _) = mergeOperations [("mod-a", aOps), ("mod-b", bOps)]
      case filter isWriteOp ops of
        [WriteFileOp _ content _] -> do
          T.isInfixOf "\"a\"" content `shouldBe` True
          T.isInfixOf "\"b\"" content `shouldBe` True
        other -> expectationFailure $ "Expected one WriteFileOp, got: " ++ show other

    it "overlapping scalar keys use right-biased merge" $ do
      let aOps = [WriteFileOp "out.json" "{\"x\": 1}\n" Structured]
          bOps = [WriteFileOp "out.json" "{\"x\": 2}\n" Structured]
          (ops, _) = mergeOperations [("mod-a", aOps), ("mod-b", bOps)]
      case filter isWriteOp ops of
        [WriteFileOp _ content _] ->
          -- Right-biased: B's value wins
          T.isInfixOf "2" content `shouldBe` True
        other -> expectationFailure $ "Expected one WriteFileOp, got: " ++ show other

    it "nested objects are merged recursively" $ do
      let aOps = [WriteFileOp "out.json" "{\"obj\": {\"a\": 1}}\n" Structured]
          bOps = [WriteFileOp "out.json" "{\"obj\": {\"b\": 2}}\n" Structured]
          (ops, _) = mergeOperations [("mod-a", aOps), ("mod-b", bOps)]
      case filter isWriteOp ops of
        [WriteFileOp _ content _] -> do
          T.isInfixOf "\"a\"" content `shouldBe` True
          T.isInfixOf "\"b\"" content `shouldBe` True
        other -> expectationFailure $ "Expected one WriteFileOp, got: " ++ show other

    it "non-Structured WriteFileOps still use last-writer-wins" $ do
      let aOps = [WriteFileOp "README.md" "from A" Template]
          bOps = [WriteFileOp "README.md" "from B" Template]
          (_, warnings) = mergeOperations [("mod-a", aOps), ("mod-b", bOps)]
      any isFileOverwritten warnings `shouldBe` True
      any isContentMerged warnings `shouldBe` False

    it "YAML structured merge works" $ do
      let aOps = [WriteFileOp "config.yaml" "name: foo\n" Structured]
          bOps = [WriteFileOp "config.yaml" "extra: true\n" Structured]
          (ops, warnings) = mergeOperations [("mod-a", aOps), ("mod-b", bOps)]
      case filter isWriteOp ops of
        [WriteFileOp _ content _] -> do
          T.isInfixOf "name" content `shouldBe` True
          T.isInfixOf "extra" content `shouldBe` True
        other -> expectationFailure $ "Expected one WriteFileOp, got: " ++ show other
      any isContentMerged warnings `shouldBe` True

-- Helpers

isWriteOp :: Operation -> Bool
isWriteOp (WriteFileOp {}) = True
isWriteOp _ = False

destOfOp' :: Operation -> Maybe FilePath
destOfOp' (WriteFileOp d _ _) = Just d
destOfOp' (CopyFileOp _ d) = Just d
destOfOp' (PatchFileOp d _ _ _ _) = Just d
destOfOp' _ = Nothing

isContentMerged :: CompositionWarning -> Bool
isContentMerged (ContentMerged {}) = True
isContentMerged _ = False

isFileOverwritten :: CompositionWarning -> Bool
isFileOverwritten (FileOverwritten {}) = True
isFileOverwritten _ = False
