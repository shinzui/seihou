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
    { hash = hashContent content,
      moduleName = modName,
      strategy = Template,
      generatedAt = fixedTime
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
            (emptyManifest fixedTime :: Manifest)
              { files = Map.singleton "README.md" (mkRecord content)
              }
          fs = PureFS (Map.singleton "README.md" content) mempty
          result = runStatus fs manifest
      length result `shouldBe` 1
      (head result).path `shouldBe` "README.md"
      (head result).moduleName `shouldBe` modName
      (head result).status `shouldBe` TfsUnchanged

    it "classifies a file with different disk content as TfsModified" $ do
      let originalContent = "# Hello"
          modifiedContent = "# Hello - edited"
          manifest =
            (emptyManifest fixedTime :: Manifest)
              { files = Map.singleton "README.md" (mkRecord originalContent)
              }
          fs = PureFS (Map.singleton "README.md" modifiedContent) mempty
          result = runStatus fs manifest
      length result `shouldBe` 1
      (head result).status `shouldBe` TfsModified

    it "classifies a file missing from disk as TfsDeleted" $ do
      let content = "# Hello"
          manifest =
            (emptyManifest fixedTime :: Manifest)
              { files = Map.singleton "README.md" (mkRecord content)
              }
          result = runStatus emptyFS manifest
      length result `shouldBe` 1
      (head result).status `shouldBe` TfsDeleted

    it "handles mixed statuses across multiple files" $ do
      let unchangedContent = "unchanged"
          modifiedOriginal = "original"
          modifiedCurrent = "edited"
          deletedContent = "deleted"
          manifest =
            (emptyManifest fixedTime :: Manifest)
              { files =
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
      (result !! 0).path `shouldBe` "a.txt"
      (result !! 0).status `shouldBe` TfsUnchanged
      (result !! 1).path `shouldBe` "b.txt"
      (result !! 1).status `shouldBe` TfsModified
      (result !! 2).path `shouldBe` "c.txt"
      (result !! 2).status `shouldBe` TfsDeleted

    it "returns empty list for empty manifest" $ do
      let manifest = emptyManifest fixedTime
          result = runStatus emptyFS manifest
      result `shouldBe` []
