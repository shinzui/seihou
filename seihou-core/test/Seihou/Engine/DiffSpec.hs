module Seihou.Engine.DiffSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Time (UTCTime, defaultTimeLocale, parseTimeOrError)
import Effectful
import Seihou.Core.Types
import Seihou.Effect.FilesystemPure (PureFS (..), emptyFS, runFilesystemPure)
import Seihou.Engine.Diff (computeDiff)
import Seihou.Manifest.Hash (hashContent)
import Seihou.Manifest.Types (emptyManifest)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Engine.Diff" spec

fixedTime :: UTCTime
fixedTime = parseTimeOrError True defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ" "2026-03-01T10:30:00Z"

modName :: ModuleName
modName = ModuleName "test-module"

-- | Run diff computation in pure filesystem.
runDiff :: PureFS -> Manifest -> [(FilePath, Text, ModuleName)] -> DiffResult
runDiff fs manifest planned =
  fst $ runPureEff $ runFilesystemPure fs $ computeDiff manifest planned

-- | Helper to make a FileRecord from content.
mkRecord :: Text -> FileRecord
mkRecord content =
  FileRecord
    { fileHash = hashContent content,
      fileModule = modName,
      fileStrategy = Template,
      fileGeneratedAt = fixedTime
    }

spec :: Spec
spec = do
  describe "computeDiff" $ do
    it "classifies file in plan only (not on disk) as New" $ do
      let manifest = emptyManifest fixedTime
          planned = [("README.md", "# Hello", modName)]
          result = runDiff emptyFS manifest planned
      length (diffNew result) `shouldBe` 1
      plannedPath (head (diffNew result)) `shouldBe` "README.md"

    it "classifies file in plan + on disk (not in manifest) as Conflict" $ do
      let manifest = emptyManifest fixedTime
          planned = [("README.md", "# Hello", modName)]
          fs = PureFS (Map.singleton "README.md" "existing content") mempty
          result = runDiff fs manifest planned
      length (diffConflict result) `shouldBe` 1
      conflictPath (head (diffConflict result)) `shouldBe` "README.md"

    it "classifies file in manifest + plan + disk (unchanged) as Unchanged" $ do
      let content = "# Hello World"
          manifest =
            (emptyManifest fixedTime)
              { manifestFiles = Map.singleton "README.md" (mkRecord content)
              }
          planned = [("README.md", content, modName)]
          fs = PureFS (Map.singleton "README.md" content) mempty
          result = runDiff fs manifest planned
      length (diffUnchanged result) `shouldBe` 1
      head (diffUnchanged result) `shouldBe` "README.md"

    it "classifies file in manifest + plan + disk (plan changed) as Modified" $ do
      let oldContent = "# Hello"
          newContent = "# Hello World"
          manifest =
            (emptyManifest fixedTime)
              { manifestFiles = Map.singleton "README.md" (mkRecord oldContent)
              }
          planned = [("README.md", newContent, modName)]
          -- Disk matches manifest (user didn't touch it)
          fs = PureFS (Map.singleton "README.md" oldContent) mempty
          result = runDiff fs manifest planned
      length (diffModified result) `shouldBe` 1
      modifiedPath (head (diffModified result)) `shouldBe` "README.md"
      modifiedNewContent (head (diffModified result)) `shouldBe` newContent

    it "classifies file in manifest + plan + disk (user modified) as Conflict" $ do
      let originalContent = "# Hello"
          userContent = "# Hello - edited by user"
          planContent = "# Hello World"
          manifest =
            (emptyManifest fixedTime)
              { manifestFiles = Map.singleton "README.md" (mkRecord originalContent)
              }
          planned = [("README.md", planContent, modName)]
          -- Disk was modified by user (doesn't match manifest)
          fs = PureFS (Map.singleton "README.md" userContent) mempty
          result = runDiff fs manifest planned
      length (diffConflict result) `shouldBe` 1
      conflictPath (head (diffConflict result)) `shouldBe` "README.md"
      conflictPlan (head (diffConflict result)) `shouldBe` planContent

    it "classifies file in manifest only (on disk) as Orphaned" $ do
      let content = "orphaned content"
          manifest =
            (emptyManifest fixedTime)
              { manifestFiles = Map.singleton "old-file.txt" (mkRecord content)
              }
          planned = [] -- module no longer produces this file
          fs = PureFS (Map.singleton "old-file.txt" content) mempty
          result = runDiff fs manifest planned
      length (diffOrphaned result) `shouldBe` 1
      orphanedPath (head (diffOrphaned result)) `shouldBe` "old-file.txt"

    it "classifies file in manifest only (not on disk) as Orphaned" $ do
      let content = "deleted content"
          manifest =
            (emptyManifest fixedTime)
              { manifestFiles = Map.singleton "deleted.txt" (mkRecord content)
              }
          planned = []
          result = runDiff emptyFS manifest planned
      length (diffOrphaned result) `shouldBe` 1
      orphanedPath (head (diffOrphaned result)) `shouldBe` "deleted.txt"

    it "classifies file in manifest + plan (deleted from disk) as Modified" $ do
      let content = "recreate me"
          manifest =
            (emptyManifest fixedTime)
              { manifestFiles = Map.singleton "gone.txt" (mkRecord content)
              }
          planned = [("gone.txt", "new version", modName)]
          result = runDiff emptyFS manifest planned
      length (diffModified result) `shouldBe` 1
      modifiedPath (head (diffModified result)) `shouldBe` "gone.txt"

    it "handles mixed classifications" $ do
      let existingContent = "existing"
          manifest =
            (emptyManifest fixedTime)
              { manifestFiles =
                  Map.fromList
                    [ ("unchanged.txt", mkRecord existingContent),
                      ("orphaned.txt", mkRecord "orphan")
                    ]
              }
          planned =
            [ ("unchanged.txt", existingContent, modName),
              ("new-file.txt", "brand new", modName)
            ]
          fs =
            PureFS
              (Map.fromList [("unchanged.txt", existingContent), ("orphaned.txt", "orphan")])
              mempty
          result = runDiff fs manifest planned
      length (diffNew result) `shouldBe` 1
      length (diffUnchanged result) `shouldBe` 1
      length (diffOrphaned result) `shouldBe` 1
      length (diffModified result) `shouldBe` 0
      length (diffConflict result) `shouldBe` 0

    it "handles empty manifest and empty plan" $ do
      let manifest = emptyManifest fixedTime
          result = runDiff emptyFS manifest []
      diffNew result `shouldBe` []
      diffModified result `shouldBe` []
      diffUnchanged result `shouldBe` []
      diffConflict result `shouldBe` []
      diffOrphaned result `shouldBe` []
