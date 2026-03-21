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
runDiff :: PureFS -> Manifest -> [(FilePath, Text, ModuleName, Maybe PatchOp)] -> DiffResult
runDiff fs manifest planned =
  fst $ runPureEff $ runFilesystemPure fs $ computeDiff manifest planned

-- | Helper to make a FileRecord from content.
mkRecord :: Text -> FileRecord
mkRecord content =
  FileRecord
    { hash = hashContent content,
      moduleName = modName,
      strategy = Template,
      generatedAt = fixedTime
    }

-- | Helper to create a manifest with file records (avoids ambiguous record update).
manifestWithFiles :: Map.Map FilePath FileRecord -> Manifest
manifestWithFiles recs =
  let base = emptyManifest fixedTime
   in Manifest
        { version = base.version,
          genAt = base.genAt,
          modules = base.modules,
          vars = base.vars,
          files = recs
        }

spec :: Spec
spec = do
  describe "computeDiff" $ do
    it "classifies file in plan only (not on disk) as New" $ do
      let manifest = emptyManifest fixedTime
          planned = [("README.md", "# Hello", modName, Nothing)]
          result = runDiff emptyFS manifest planned
      length (result.new) `shouldBe` 1
      (head result.new).path `shouldBe` "README.md"

    it "classifies file in plan + on disk (not in manifest) as Conflict" $ do
      let manifest = emptyManifest fixedTime
          planned = [("README.md", "# Hello", modName, Nothing)]
          fs = PureFS (Map.singleton "README.md" "existing content") mempty
          result = runDiff fs manifest planned
      length (result.conflicts) `shouldBe` 1
      (head result.conflicts).path `shouldBe` "README.md"

    it "classifies patch op on existing file (not in manifest) as New, not Conflict" $ do
      let manifest = emptyManifest fixedTime
          planned = [(".gitignore", ".claude/\n", modName, Just AppendSection)]
          fs = PureFS (Map.singleton ".gitignore" ".seihou/\n") mempty
          result = runDiff fs manifest planned
      length (result.conflicts) `shouldBe` 0
      length (result.new) `shouldBe` 1
      (head result.new).path `shouldBe` ".gitignore"

    it "classifies patch op on user-modified file (in manifest) as Modified, not Conflict" $ do
      let originalContent = "original"
          userContent = "user edited"
          patchContent = "new section"
          manifest = manifestWithFiles (Map.singleton "config.txt" (mkRecord originalContent))
          planned = [("config.txt", patchContent, modName, Just AppendSection)]
          fs = PureFS (Map.singleton "config.txt" userContent) mempty
          result = runDiff fs manifest planned
      length (result.conflicts) `shouldBe` 0
      length (result.modified) `shouldBe` 1
      (head result.modified).path `shouldBe` "config.txt"

    it "classifies file in manifest + plan + disk (unchanged) as Unchanged" $ do
      let content = "# Hello World"
          manifest = manifestWithFiles (Map.singleton "README.md" (mkRecord content))
          planned = [("README.md", content, modName, Nothing)]
          fs = PureFS (Map.singleton "README.md" content) mempty
          result = runDiff fs manifest planned
      length (result.unchanged) `shouldBe` 1
      head (result.unchanged) `shouldBe` "README.md"

    it "classifies file in manifest + plan + disk (plan changed) as Modified" $ do
      let oldContent = "# Hello"
          newContent = "# Hello World"
          manifest = manifestWithFiles (Map.singleton "README.md" (mkRecord oldContent))
          planned = [("README.md", newContent, modName, Nothing)]
          -- Disk matches manifest (user didn't touch it)
          fs = PureFS (Map.singleton "README.md" oldContent) mempty
          result = runDiff fs manifest planned
      length (result.modified) `shouldBe` 1
      (head result.modified).path `shouldBe` "README.md"
      (head result.modified).newContent `shouldBe` newContent

    it "classifies file in manifest + plan + disk (user modified) as Conflict" $ do
      let originalContent = "# Hello"
          userContent = "# Hello - edited by user"
          planContent = "# Hello World"
          manifest = manifestWithFiles (Map.singleton "README.md" (mkRecord originalContent))
          planned = [("README.md", planContent, modName, Nothing)]
          -- Disk was modified by user (doesn't match manifest)
          fs = PureFS (Map.singleton "README.md" userContent) mempty
          result = runDiff fs manifest planned
      length (result.conflicts) `shouldBe` 1
      (head result.conflicts).path `shouldBe` "README.md"
      (head result.conflicts).planContent `shouldBe` planContent

    it "classifies file in manifest only (on disk) as Orphaned" $ do
      let content = "orphaned content"
          manifest =
            (emptyManifest fixedTime :: Manifest)
              { files = Map.singleton "old-file.txt" (mkRecord content)
              }
          planned = [] :: [(FilePath, Text, ModuleName, Maybe PatchOp)] -- module no longer produces this file
          fs = PureFS (Map.singleton "old-file.txt" content) mempty
          result = runDiff fs manifest planned
      length (result.orphaned) `shouldBe` 1
      (head result.orphaned).path `shouldBe` "old-file.txt"

    it "classifies file in manifest only (not on disk) as Orphaned" $ do
      let content = "deleted content"
          manifest =
            (emptyManifest fixedTime :: Manifest)
              { files = Map.singleton "deleted.txt" (mkRecord content)
              }
          planned = [] :: [(FilePath, Text, ModuleName, Maybe PatchOp)]
          result = runDiff emptyFS manifest planned
      length (result.orphaned) `shouldBe` 1
      (head result.orphaned).path `shouldBe` "deleted.txt"

    it "classifies file in manifest + plan (deleted from disk) as Modified" $ do
      let content = "recreate me"
          manifest =
            (emptyManifest fixedTime :: Manifest)
              { files = Map.singleton "gone.txt" (mkRecord content)
              }
          planned = [("gone.txt", "new version", modName, Nothing)]
          result = runDiff emptyFS manifest planned
      length (result.modified) `shouldBe` 1
      (head result.modified).path `shouldBe` "gone.txt"

    it "handles mixed classifications" $ do
      let existingContent = "existing"
          manifest =
            (emptyManifest fixedTime :: Manifest)
              { files =
                  Map.fromList
                    [ ("unchanged.txt", mkRecord existingContent),
                      ("orphaned.txt", mkRecord "orphan")
                    ]
              }
          planned =
            [ ("unchanged.txt", existingContent, modName, Nothing),
              ("new-file.txt", "brand new", modName, Nothing)
            ]
          fs =
            PureFS
              (Map.fromList [("unchanged.txt", existingContent), ("orphaned.txt", "orphan")])
              mempty
          result = runDiff fs manifest planned
      length (result.new) `shouldBe` 1
      length (result.unchanged) `shouldBe` 1
      length (result.orphaned) `shouldBe` 1
      length (result.modified) `shouldBe` 0
      length (result.conflicts) `shouldBe` 0

    it "handles empty manifest and empty plan" $ do
      let manifest = emptyManifest fixedTime
          result = runDiff emptyFS manifest ([] :: [(FilePath, Text, ModuleName, Maybe PatchOp)])
      result.new `shouldBe` []
      result.modified `shouldBe` []
      result.unchanged `shouldBe` []
      result.conflicts `shouldBe` []
      result.orphaned `shouldBe` []
