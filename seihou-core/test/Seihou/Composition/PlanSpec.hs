module Seihou.Composition.PlanSpec (tests) where

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

-- Helpers

isWriteOp :: Operation -> Bool
isWriteOp (WriteFileOp {}) = True
isWriteOp _ = False

destOfOp' :: Operation -> Maybe FilePath
destOfOp' (WriteFileOp d _ _) = Just d
destOfOp' (CopyFileOp _ d) = Just d
destOfOp' _ = Nothing
