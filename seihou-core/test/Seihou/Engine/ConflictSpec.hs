module Seihou.Engine.ConflictSpec (tests) where

import Data.Text qualified as T
import Effectful
import Seihou.Core.Types
import Seihou.Effect.ConsolePure (ConsoleState (..), runConsolePure, runConsolePureNonInteractive)
import Seihou.Engine.Conflict (resolveConflicts, resolveConflictsInteractive)
import Seihou.Manifest.Hash (hashContent)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Engine.Conflict" spec

-- | Helper to make a ConflictFile with realistic hashes.
mkConflict :: FilePath -> ConflictFile
mkConflict path =
  ConflictFile
    { conflictPath = path,
      conflictModule = ModuleName "test-module",
      conflictManifest = hashContent "original content",
      conflictDisk = hashContent "user edited content",
      conflictPlan = "new generated content"
    }

spec :: Spec
spec = do
  describe "resolveConflicts" $ do
    it "returns Just [] for empty conflict list" $ do
      let (result, _st) = runPureEff $ runConsolePure [] $ resolveConflicts False []
      result `shouldBe` Just []

    it "returns Just [] for empty conflict list with force" $ do
      let (result, _st) = runPureEff $ runConsolePure [] $ resolveConflicts True []
      result `shouldBe` Just []

    it "returns all AcceptNew when force is True" $ do
      let conflicts = [mkConflict "a.txt", mkConflict "b.txt", mkConflict "c.txt"]
          (result, _st) = runPureEff $ runConsolePure [] $ resolveConflicts True conflicts
      case result of
        Just resolved -> do
          length resolved `shouldBe` 3
          all (\(_, r) -> r == AcceptNew) resolved `shouldBe` True
        Nothing -> expectationFailure "Expected Just, got Nothing"

    it "returns Nothing in non-interactive mode without force" $ do
      let conflicts = [mkConflict "a.txt"]
          (result, _st) = runPureEff $ runConsolePureNonInteractive $ resolveConflicts False conflicts
      result `shouldBe` Nothing

    it "does not produce console output when force is True" $ do
      let conflicts = [mkConflict "a.txt"]
          (_result, st) = runPureEff $ runConsolePure [] $ resolveConflicts True conflicts
      consoleOutputs st `shouldBe` []

  describe "resolveConflictsInteractive" $ do
    it "resolves accept with 'a'" $ do
      let conflict = mkConflict "readme.md"
          (result, _st) = runPureEff $ runConsolePure ["a"] $ resolveConflictsInteractive [conflict]
      case result of
        Just [(_, res)] -> res `shouldBe` AcceptNew
        _ -> expectationFailure "Expected Just with one AcceptNew resolution"

    it "resolves keep with 'k'" $ do
      let conflict = mkConflict "readme.md"
          (result, _st) = runPureEff $ runConsolePure ["k"] $ resolveConflictsInteractive [conflict]
      case result of
        Just [(_, res)] -> res `shouldBe` KeepCurrent
        _ -> expectationFailure "Expected Just with one KeepCurrent resolution"

    it "resolves skip with 's'" $ do
      let conflict = mkConflict "readme.md"
          (result, _st) = runPureEff $ runConsolePure ["s"] $ resolveConflictsInteractive [conflict]
      case result of
        Just [(_, res)] -> res `shouldBe` Skip
        _ -> expectationFailure "Expected Just with one Skip resolution"

    it "returns Nothing on abort with 'A'" $ do
      let conflicts = [mkConflict "a.txt", mkConflict "b.txt"]
          (result, _st) = runPureEff $ runConsolePure ["A"] $ resolveConflictsInteractive conflicts
      result `shouldBe` Nothing

    it "re-prompts on invalid input then accepts valid input" $ do
      let conflict = mkConflict "readme.md"
          (result, st) = runPureEff $ runConsolePure ["x", "a"] $ resolveConflictsInteractive [conflict]
      case result of
        Just [(_, res)] -> res `shouldBe` AcceptNew
        _ -> expectationFailure "Expected Just with one AcceptNew resolution"
      any (T.isInfixOf "Invalid choice") (consoleOutputs st) `shouldBe` True

    it "resolves multiple files in order" $ do
      let conflicts = [mkConflict "a.txt", mkConflict "b.txt", mkConflict "c.txt"]
          (result, _st) = runPureEff $ runConsolePure ["a", "k", "s"] $ resolveConflictsInteractive conflicts
      case result of
        Just resolved -> do
          length resolved `shouldBe` 3
          map snd resolved `shouldBe` [AcceptNew, KeepCurrent, Skip]
          map (conflictPath . fst) resolved `shouldBe` ["a.txt", "b.txt", "c.txt"]
        Nothing -> expectationFailure "Expected Just, got Nothing"

    it "abort on second file stops prompting" $ do
      let conflicts = [mkConflict "a.txt", mkConflict "b.txt", mkConflict "c.txt"]
          (result, st) = runPureEff $ runConsolePure ["a", "A"] $ resolveConflictsInteractive conflicts
      result `shouldBe` Nothing
      -- Should have prompted for a.txt and b.txt, but not c.txt
      let outputs = T.unlines (consoleOutputs st)
      T.isInfixOf "a.txt" outputs `shouldBe` True
      T.isInfixOf "b.txt" outputs `shouldBe` True
      T.isInfixOf "c.txt" outputs `shouldBe` False

    it "outputs file paths in prompt messages" $ do
      let conflict = mkConflict "src/Main.hs"
          (_result, st) = runPureEff $ runConsolePure ["a"] $ resolveConflictsInteractive [conflict]
          outputs = T.unlines (consoleOutputs st)
      T.isInfixOf "src/Main.hs" outputs `shouldBe` True
      T.isInfixOf "modified since last generation" outputs `shouldBe` True

    it "accepts full word inputs" $ do
      let conflicts = [mkConflict "a.txt", mkConflict "b.txt", mkConflict "c.txt", mkConflict "d.txt"]
          (result, _st) = runPureEff $ runConsolePure ["accept", "keep", "skip", "abort"] $ resolveConflictsInteractive conflicts
      -- abort on d.txt → Nothing
      result `shouldBe` Nothing
