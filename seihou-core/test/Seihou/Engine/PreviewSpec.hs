module Seihou.Engine.PreviewSpec (tests) where

import Data.Text qualified as T
import Seihou.Core.Types
import Seihou.Engine.Preview
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Engine.Preview" spec

modName :: ModuleName
modName = ModuleName "test-module"

modName2 :: ModuleName
modName2 = ModuleName "other-module"

-- | A DiffResult with all fields empty.
emptyDiff :: DiffResult
emptyDiff =
  DiffResult
    { diffNew = [],
      diffModified = [],
      diffUnchanged = [],
      diffConflict = [],
      diffOrphaned = []
    }

spec :: Spec
spec = do
  describe "buildPreview" $ do
    it "treats all file ops as FsNew when no DiffResult is provided" $ do
      let ops =
            [ WriteFileOp "README.md" "# Hello" Template,
              WriteFileOp "src/Lib.hs" "module Lib" Template,
              CopyFileOp "templates/LICENSE" "LICENSE"
            ]
          result = buildPreview ops Nothing
      length result `shouldBe` 3
      previewStatus (result !! 0) `shouldBe` FsNew
      previewStatus (result !! 1) `shouldBe` FsNew
      previewStatus (result !! 2) `shouldBe` FsNew

    it "classifies a new file as FsNew" $ do
      let ops = [WriteFileOp "README.md" "# Hello" Template]
          diff = emptyDiff {diffNew = [PlannedFile "README.md" modName "# Hello"]}
          result = buildPreview ops (Just diff)
      length result `shouldBe` 1
      previewStatus (head result) `shouldBe` FsNew

    it "classifies a modified file as FsModified" $ do
      let ops = [WriteFileOp "README.md" "# Updated" Template]
          diff = emptyDiff {diffModified = [ModifiedFile "README.md" modName (SHA256 "old") "# Updated"]}
          result = buildPreview ops (Just diff)
      length result `shouldBe` 1
      previewStatus (head result) `shouldBe` FsModified

    it "classifies an unchanged file as FsUnchanged" $ do
      let ops = [WriteFileOp "README.md" "# Same" Template]
          diff = emptyDiff {diffUnchanged = ["README.md"]}
          result = buildPreview ops (Just diff)
      length result `shouldBe` 1
      previewStatus (head result) `shouldBe` FsUnchanged

    it "classifies a conflicting file as FsConflict" $ do
      let ops = [WriteFileOp "README.md" "# New" Template]
          diff =
            emptyDiff
              { diffConflict =
                  [ ConflictFile
                      { conflictPath = "README.md",
                        conflictModule = modName,
                        conflictManifest = SHA256 "man",
                        conflictDisk = SHA256 "disk",
                        conflictPlan = "# New"
                      }
                  ]
              }
          result = buildPreview ops (Just diff)
      length result `shouldBe` 1
      previewStatus (head result) `shouldBe` FsConflict

    it "classifies an orphaned file as FsOrphaned" $ do
      let ops = [WriteFileOp "other.txt" "content" Template]
          diff =
            emptyDiff
              { diffNew = [PlannedFile "other.txt" modName "content"],
                diffOrphaned = [OrphanedFile "old.txt" modName]
              }
          result = buildPreview ops (Just diff)
      -- One file preview + one orphan preview
      length result `shouldBe` 2
      let orphan = result !! 1
      case orphan of
        OrphanPreview path mn -> do
          path `shouldBe` "old.txt"
          mn `shouldBe` modName
        _ -> expectationFailure "Expected OrphanPreview"

    it "does not include orphaned files that are produced by an operation" $ do
      let ops = [WriteFileOp "reused.txt" "content" Template]
          diff =
            emptyDiff
              { diffNew = [PlannedFile "reused.txt" modName "content"],
                diffOrphaned = [OrphanedFile "reused.txt" modName2]
              }
          result = buildPreview ops (Just diff)
      -- Only the file preview, orphan is suppressed because path matches an operation
      length result `shouldBe` 1
      case head result of
        FilePreview {} -> pure ()
        _ -> expectationFailure "Expected FilePreview"

    it "produces DirPreview for CreateDirOp" $ do
      let ops = [CreateDirOp "src"]
          result = buildPreview ops Nothing
      length result `shouldBe` 1
      case head result of
        DirPreview path -> path `shouldBe` "src"
        _ -> expectationFailure "Expected DirPreview"

    it "produces CommandPreview for RunCommandOp" $ do
      let ops = [RunCommandOp "cabal build" Nothing]
          result = buildPreview ops Nothing
      length result `shouldBe` 1
      case head result of
        CommandPreview cmd -> cmd `shouldBe` "cabal build"
        _ -> expectationFailure "Expected CommandPreview"

    it "maps PatchFileOp to FilePreview with correct verb and annotation" $ do
      let ops = [PatchFileOp "README.md" "extra content" AppendSection Template modName]
          result = buildPreview ops Nothing
      length result `shouldBe` 1
      case head result of
        FilePreview status verb path annotation -> do
          status `shouldBe` FsNew
          verb `shouldBe` "patch"
          path `shouldBe` "README.md"
          annotation `shouldBe` "(append-section from test-module)"
        _ -> expectationFailure "Expected FilePreview"

    it "maps CopyFileOp to FilePreview with copy verb" $ do
      let ops = [CopyFileOp "templates/LICENSE" "LICENSE"]
          result = buildPreview ops Nothing
      length result `shouldBe` 1
      case head result of
        FilePreview _ verb _ annotation -> do
          verb `shouldBe` "copy"
          annotation `shouldBe` "(copy)"
        _ -> expectationFailure "Expected FilePreview"

    it "includes correct strategy annotation for WriteFileOp" $ do
      let ops =
            [ WriteFileOp "a.txt" "" Copy,
              WriteFileOp "b.txt" "" Template,
              WriteFileOp "c.txt" "" DhallText,
              WriteFileOp "d.txt" "" Structured
            ]
          result = buildPreview ops Nothing
      map previewAnnotation (filter isFilePreview result)
        `shouldBe` ["(copy)", "(template)", "(dhall-text)", "(structured)"]

  describe "renderPreviewPlain" $ do
    it "renders empty list as 'No operations' message" $ do
      renderPreviewPlain [] `shouldBe` "No operations to perform.\n"

    it "renders FilePreview lines with status symbol" $ do
      let lines' =
            [ FilePreview FsNew "write" "README.md" "(template)",
              FilePreview FsModified "write" "src/Lib.hs" "(template)",
              FilePreview FsUnchanged "write" "LICENSE" "(copy)",
              FilePreview FsConflict "write" "config.yml" "(structured)",
              FilePreview FsOrphaned "write" "old.txt" "(template)"
            ]
          rendered = renderPreviewPlain lines'
          renderedLines = T.lines rendered
      length renderedLines `shouldBe` 5
      (renderedLines !! 0) `shouldBe` "  + write  README.md  (template)"
      (renderedLines !! 1) `shouldBe` "  ~ write  src/Lib.hs  (template)"
      (renderedLines !! 2) `shouldBe` "  = write  LICENSE  (copy)"
      (renderedLines !! 3) `shouldBe` "  ! write  config.yml  (structured)"
      (renderedLines !! 4) `shouldBe` "  - write  old.txt  (template)"

    it "renders DirPreview, CommandPreview, and OrphanPreview" $ do
      let lines' =
            [ DirPreview "src",
              CommandPreview "cabal build",
              OrphanPreview "gone.txt" modName
            ]
          rendered = renderPreviewPlain lines'
          renderedLines = T.lines rendered
      length renderedLines `shouldBe` 3
      (renderedLines !! 0) `shouldBe` "    mkdir  src"
      (renderedLines !! 1) `shouldBe` "    run    cabal build"
      (renderedLines !! 2) `shouldBe` "  - gone.txt  (orphaned from test-module)"

-- | Helper to test if a PreviewLine is a FilePreview.
isFilePreview :: PreviewLine -> Bool
isFilePreview (FilePreview {}) = True
isFilePreview _ = False
