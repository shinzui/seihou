module Seihou.Effect.BaselineStoreSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as T
import Effectful
import Seihou.Core.Types (BaselineRef (..), SHA256 (..))
import Seihou.Effect.BaselineStore
import Seihou.Effect.BaselineStoreInterp (runBaselineStore)
import Seihou.Effect.BaselineStorePure (runBaselineStorePure)
import Seihou.Effect.Filesystem (writeFileText)
import Seihou.Effect.FilesystemInterp (runFilesystem)
import Seihou.Effect.FilesystemPure (PureFS (..), emptyFS, runFilesystemPure)
import Seihou.Manifest.Hash (baselineRefForContent, hashContent)
import System.Directory qualified as Directory
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Effect.BaselineStore" spec

spec :: Spec
spec = do
  describe "pure interpreter" $ do
    it "deduplicates identical content and round-trips it" $ do
      let ((ref1, ref2, result), store) = runPureEff $ runBaselineStorePure Map.empty $ do
            first <- putBaseline "generated text"
            second <- putBaseline "generated text"
            stored <- readBaseline first
            pure (first, second, stored)
      ref1 `shouldBe` ref2
      result `shouldBe` Right "generated text"
      Map.size store `shouldBe` 1

    it "reports missing and corrupt content" $ do
      let missingRef = baselineRefForContent "missing"
          corruptRef = baselineRefForContent "expected"
          initial = Map.singleton corruptRef "tampered"
          ((missing, corrupt), _) = runPureEff $ runBaselineStorePure initial $ do
            missingResult <- readBaseline missingRef
            corruptResult <- readBaseline corruptRef
            pure (missingResult, corruptResult)
      missing `shouldBe` Left (BaselineMissing missingRef)
      corrupt `shouldBe` Left (BaselineCorrupt corruptRef (hashContent "tampered"))

    it "prunes only valid unreferenced entries" $ do
      let kept = baselineRefForContent "kept"
          removed = baselineRefForContent "removed"
          corrupt = baselineRefForContent "expected"
          initial = Map.fromList [(kept, "kept"), (removed, "removed"), (corrupt, "tampered")]
          (pruned, store) = runPureEff $ runBaselineStorePure initial (pruneBaselines (Set.singleton kept))
      pruned `shouldBe` [removed]
      Map.keysSet store `shouldBe` Set.fromList [kept, corrupt]

  describe "filesystem interpreter" $ do
    it "writes atomically, detects tampering, cleans temp files, and prunes safely" $ do
      let baselineDir = ".seihou/baselines"
          kept = baselineRefForContent "kept"
          removed = baselineRefForContent "removed"
          keptPath = baselineDir </> refName kept
          removedPath = baselineDir </> refName removed
          staleTemp = keptPath <> ".tmp"
          unrelated = baselineDir </> "README"
          action = do
            writeFileText staleTemp "partial"
            keptRef <- putBaseline "kept"
            removedRef <- putBaseline "removed"
            writeFileText unrelated "leave me"
            beforeTamper <- readBaseline keptRef
            writeFileText keptPath "tampered"
            afterTamper <- readBaseline keptRef
            writeFileText keptPath "kept"
            pruned <- pruneBaselines (Set.singleton keptRef)
            pure (removedRef, beforeTamper, afterTamper, pruned)
          ((removedRef, beforeTamper, afterTamper, pruned), fs) =
            runPureEff $ runFilesystemPure emptyFS $ runBaselineStore baselineDir action
      removedRef `shouldBe` removed
      beforeTamper `shouldBe` Right "kept"
      afterTamper `shouldBe` Left (BaselineCorrupt kept (hashContent "tampered"))
      pruned `shouldBe` [removed]
      Map.lookup keptPath fs.files `shouldBe` Just "kept"
      Map.member removedPath fs.files `shouldBe` False
      Map.lookup unrelated fs.files `shouldBe` Just "leave me"
      Map.member staleTemp fs.files `shouldBe` False

    it "round-trips on a real filesystem with one deduplicated blob" $ do
      withSystemTempDirectory "seihou-baselines" $ \tmpDir -> do
        let baselineDir = tmpDir </> ".seihou" </> "baselines"
        (ref1, ref2, result) <-
          runEff $ runFilesystem $ runBaselineStore baselineDir $ do
            first <- putBaseline "real content"
            second <- putBaseline "real content"
            stored <- readBaseline first
            pure (first, second, stored)
        entries <- Directory.listDirectory baselineDir
        ref1 `shouldBe` ref2
        result `shouldBe` Right "real content"
        entries `shouldBe` [refName ref1]

refName :: BaselineRef -> FilePath
refName (BaselineRef (SHA256 value)) = T.unpack value
