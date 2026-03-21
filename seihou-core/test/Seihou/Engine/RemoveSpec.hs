module Seihou.Engine.RemoveSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Time (UTCTime, defaultTimeLocale, parseTimeOrError)
import Effectful
import Seihou.Core.Types
import Seihou.Effect.FilesystemPure (PureFS (..), emptyFS, runFilesystemPure)
import Seihou.Engine.Remove
import Seihou.Manifest.Hash (hashContent)
import Seihou.Manifest.Types (emptyManifest)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Engine.Remove" spec

fixedTime :: UTCTime
fixedTime = parseTimeOrError True defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ" "2026-03-01T10:30:00Z"

removeTime :: UTCTime
removeTime = parseTimeOrError True defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ" "2026-03-02T09:00:00Z"

modName :: ModuleName
modName = ModuleName "test-module"

otherMod :: ModuleName
otherMod = ModuleName "other-module"

-- | Helper: create a manifest with one applied module and some files.
mkManifest :: Bool -> [(FilePath, Text)] -> Manifest
mkManifest isRemovable fileContents =
  (emptyManifest fixedTime)
    { modules =
        [ AppliedModule
            { name = modName,
              source = "/path/to/test-module",
              appliedAt = fixedTime,
              removal = if isRemovable then Just (Removal [] []) else Nothing
            }
        ],
      files =
        Map.fromList
          [ ( path,
              FileRecord
                { hash = hashContent content,
                  moduleName = modName,
                  strategy = Template,
                  generatedAt = fixedTime
                }
            )
          | (path, content) <- fileContents
          ]
    }

-- | Helper: create a PureFS with files.
mkFS :: [(FilePath, Text)] -> PureFS
mkFS fileContents = PureFS (Map.fromList fileContents) Set.empty

-- | Run computeRemovalPlan in the pure filesystem.
runPlan :: PureFS -> Manifest -> ModuleName -> Either RemovalError RemovalPlan
runPlan fs manifest name =
  fst $ runPureEff $ runFilesystemPure fs $ computeRemovalPlan manifest name

-- | Run executeRemoval in the pure filesystem.
runExec :: PureFS -> Manifest -> RemovalPlan -> Set.Set FilePath -> (Manifest, PureFS)
runExec fs manifest plan keepSet =
  let (result, finalFS) =
        runPureEff $
          runFilesystemPure fs $
            executeRemoval manifest plan keepSet removeTime
   in (result, finalFS)

spec :: Spec
spec = do
  describe "computeRemovalPlan" $ do
    it "returns ModuleNotApplied when module is not in manifest" $ do
      let manifest = emptyManifest fixedTime
          result = runPlan emptyFS manifest modName
      result `shouldBe` Left (ModuleNotApplied modName)

    it "returns ModuleNotRemovable when removable is False" $ do
      let manifest = mkManifest False [("README.md", "hello")]
          fs = mkFS [("README.md", "hello")]
          result = runPlan fs manifest modName
      result `shouldBe` Left (ModuleNotRemovable modName)

    it "classifies unchanged files as RemovalSafe" $ do
      let manifest = mkManifest True [("README.md", "hello")]
          fs = mkFS [("README.md", "hello")]
          result = runPlan fs manifest modName
      case result of
        Left err -> expectationFailure ("unexpected error: " <> show err)
        Right plan -> plan.files `shouldBe` [RemovalSafe "README.md"]

    it "classifies user-modified files as RemovalConflict" $ do
      let manifest = mkManifest True [("README.md", "original")]
          fs = mkFS [("README.md", "user changed this")]
          result = runPlan fs manifest modName
      case result of
        Left err -> expectationFailure ("unexpected error: " <> show err)
        Right plan -> plan.files `shouldBe` [RemovalConflict "README.md"]

    it "classifies deleted files as RemovalGone" $ do
      let manifest = mkManifest True [("README.md", "hello")]
          result = runPlan emptyFS manifest modName
      case result of
        Left err -> expectationFailure ("unexpected error: " <> show err)
        Right plan -> plan.files `shouldBe` [RemovalGone "README.md"]

    it "handles mix of safe, conflict, and gone files" $ do
      let manifest = mkManifest True [("a.txt", "aaa"), ("b.txt", "bbb"), ("c.txt", "ccc")]
          fs = mkFS [("a.txt", "aaa"), ("b.txt", "modified")]
          result = runPlan fs manifest modName
      case result of
        Left err -> expectationFailure ("unexpected error: " <> show err)
        Right plan -> do
          length plan.files `shouldBe` 3
          RemovalSafe "a.txt" `elem` plan.files `shouldBe` True
          RemovalConflict "b.txt" `elem` plan.files `shouldBe` True
          RemovalGone "c.txt" `elem` plan.files `shouldBe` True

  describe "executeRemoval" $ do
    it "deletes safe files from the filesystem" $ do
      let manifest = mkManifest True [("README.md", "hello")]
          fs = mkFS [("README.md", "hello")]
          plan = RemovalPlan {targetModule = modName, files = [RemovalSafe "README.md"]}
          (_, finalFS) = runExec fs manifest plan Set.empty
      Map.member "README.md" finalFS.files `shouldBe` False

    it "preserves files in the keep-set" $ do
      let manifest = mkManifest True [("a.txt", "aaa")]
          fs = mkFS [("a.txt", "modified")]
          plan = RemovalPlan {targetModule = modName, files = [RemovalConflict "a.txt"]}
          keepSet = Set.singleton "a.txt"
          (_, finalFS) = runExec fs manifest plan keepSet
      Map.member "a.txt" finalFS.files `shouldBe` True

    it "removes the module from manifest.modules" $ do
      let manifest = mkManifest True [("README.md", "hello")]
          fs = mkFS [("README.md", "hello")]
          plan = RemovalPlan {targetModule = modName, files = [RemovalSafe "README.md"]}
          (updated, _) = runExec fs manifest plan Set.empty
      updated.modules `shouldBe` []

    it "removes module's files from manifest.files" $ do
      let manifest = mkManifest True [("a.txt", "aaa"), ("b.txt", "bbb")]
          fs = mkFS [("a.txt", "aaa"), ("b.txt", "bbb")]
          plan = RemovalPlan {targetModule = modName, files = [RemovalSafe "a.txt", RemovalSafe "b.txt"]}
          (updated, _) = runExec fs manifest plan Set.empty
      Map.null updated.files `shouldBe` True

    it "preserves files from other modules in manifest" $ do
      let base = mkManifest True [("mine.txt", "mine")]
          otherRec = FileRecord (hashContent "other") otherMod Template fixedTime
          manifest =
            Manifest
              { version = base.version,
                genAt = base.genAt,
                modules = base.modules,
                vars = base.vars,
                files = Map.insert "other.txt" otherRec base.files
              }
          fs = mkFS [("mine.txt", "mine"), ("other.txt", "other")]
          plan = RemovalPlan {targetModule = modName, files = [RemovalSafe "mine.txt"]}
          (updated, _) = runExec fs manifest plan Set.empty
      Map.member "other.txt" updated.files `shouldBe` True
      Map.member "mine.txt" updated.files `shouldBe` False

    it "updates genAt timestamp in manifest" $ do
      let manifest = mkManifest True [("a.txt", "aaa")]
          fs = mkFS [("a.txt", "aaa")]
          plan = RemovalPlan {targetModule = modName, files = [RemovalSafe "a.txt"]}
          (updated, _) = runExec fs manifest plan Set.empty
      updated.genAt `shouldBe` removeTime

    it "full round-trip: manifest returns to clean state after removal" $ do
      let manifest = mkManifest True [("a.txt", "aaa"), ("b.txt", "bbb")]
          fs = mkFS [("a.txt", "aaa"), ("b.txt", "bbb")]
          plan = RemovalPlan {targetModule = modName, files = [RemovalSafe "a.txt", RemovalSafe "b.txt"]}
          (updated, finalFS) = runExec fs manifest plan Set.empty
      updated.modules `shouldBe` []
      Map.null updated.files `shouldBe` True
      Map.member "a.txt" finalFS.files `shouldBe` False
      Map.member "b.txt" finalFS.files `shouldBe` False
