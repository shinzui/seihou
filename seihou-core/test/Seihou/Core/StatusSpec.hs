module Seihou.Core.StatusSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Time (UTCTime, defaultTimeLocale, parseTimeOrError)
import Effectful
import Seihou.Core.Status (computeTrackedFileStatuses)
import Seihou.Core.Types
import Seihou.Effect.FilesystemPure (PureFS (..), emptyFS, runFilesystemPure)
import Seihou.Manifest.Hash (hashContent)
import Seihou.Manifest.Types (emptyManifest)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Core.Status" spec

fixedTime :: UTCTime
fixedTime = parseTimeOrError True defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ" "2026-03-01T10:30:00Z"

modName :: ModuleName
modName = ModuleName "test-module"

mkRecord :: Text -> FileRecord
mkRecord content =
  FileRecord
    { fileHash = hashContent content,
      fileModule = modName,
      fileStrategy = Template,
      fileGeneratedAt = fixedTime
    }

runStatus :: PureFS -> Manifest -> [TrackedFile]
runStatus fs manifest =
  fst $ runPureEff $ runFilesystemPure fs $ computeTrackedFileStatuses manifest

spec :: Spec
spec = do
  describe "computeTrackedFileStatuses" $ do
    it "classifies a file matching its manifest hash as TfsUnchanged" $ do
      let content = "# Hello World"
          manifest =
            (emptyManifest fixedTime)
              { manifestFiles = Map.singleton "README.md" (mkRecord content)
              }
          fs = PureFS (Map.singleton "README.md" content) mempty
          result = runStatus fs manifest
      length result `shouldBe` 1
      trackedPath (head result) `shouldBe` "README.md"
      trackedModule (head result) `shouldBe` modName
      trackedStatus (head result) `shouldBe` TfsUnchanged

    it "classifies a file with different disk content as TfsModified" $ do
      let originalContent = "# Hello"
          modifiedContent = "# Hello - edited"
          manifest =
            (emptyManifest fixedTime)
              { manifestFiles = Map.singleton "README.md" (mkRecord originalContent)
              }
          fs = PureFS (Map.singleton "README.md" modifiedContent) mempty
          result = runStatus fs manifest
      length result `shouldBe` 1
      trackedStatus (head result) `shouldBe` TfsModified

    it "classifies a file missing from disk as TfsDeleted" $ do
      let content = "# Hello"
          manifest =
            (emptyManifest fixedTime)
              { manifestFiles = Map.singleton "README.md" (mkRecord content)
              }
          result = runStatus emptyFS manifest
      length result `shouldBe` 1
      trackedStatus (head result) `shouldBe` TfsDeleted

    it "handles mixed statuses across multiple files" $ do
      let unchangedContent = "unchanged"
          modifiedOriginal = "original"
          modifiedCurrent = "edited"
          deletedContent = "deleted"
          manifest =
            (emptyManifest fixedTime)
              { manifestFiles =
                  Map.fromList
                    [ ("a.txt", mkRecord unchangedContent),
                      ("b.txt", mkRecord modifiedOriginal),
                      ("c.txt", mkRecord deletedContent)
                    ]
              }
          fs =
            PureFS
              ( Map.fromList
                  [ ("a.txt", unchangedContent),
                    ("b.txt", modifiedCurrent)
                  ]
              )
              mempty
          result = runStatus fs manifest
      length result `shouldBe` 3
      -- Results are sorted by path
      trackedPath (result !! 0) `shouldBe` "a.txt"
      trackedStatus (result !! 0) `shouldBe` TfsUnchanged
      trackedPath (result !! 1) `shouldBe` "b.txt"
      trackedStatus (result !! 1) `shouldBe` TfsModified
      trackedPath (result !! 2) `shouldBe` "c.txt"
      trackedStatus (result !! 2) `shouldBe` TfsDeleted

    it "returns empty list for empty manifest" $ do
      let manifest = emptyManifest fixedTime
          result = runStatus emptyFS manifest
      result `shouldBe` []
