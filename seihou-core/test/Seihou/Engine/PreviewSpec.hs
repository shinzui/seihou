module Seihou.Engine.PreviewSpec (tests) where

import Data.Map.Strict qualified as Map
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
          result = buildPreview ops Nothing Map.empty
      length result `shouldBe` 3
      previewStatus (result !! 0) `shouldBe` FsNew
      previewStatus (result !! 1) `shouldBe` FsNew
      previewStatus (result !! 2) `shouldBe` FsNew

    it "classifies a new file as FsNew" $ do
      let ops = [WriteFileOp "README.md" "# Hello" Template]
          diff = emptyDiff {diffNew = [PlannedFile "README.md" modName "# Hello"]}
          result = buildPreview ops (Just diff) Map.empty
      length result `shouldBe` 1
      previewStatus (head result) `shouldBe` FsNew

    it "classifies a modified file as FsModified" $ do
      let ops = [WriteFileOp "README.md" "# Updated" Template]
          diff = emptyDiff {diffModified = [ModifiedFile "README.md" modName (SHA256 "old") "# Updated"]}
          result = buildPreview ops (Just diff) Map.empty
      length result `shouldBe` 1
      previewStatus (head result) `shouldBe` FsModified

    it "classifies an unchanged file as FsUnchanged" $ do
      let ops = [WriteFileOp "README.md" "# Same" Template]
          diff = emptyDiff {diffUnchanged = ["README.md"]}
          result = buildPreview ops (Just diff) Map.empty
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
          result = buildPreview ops (Just diff) Map.empty
      length result `shouldBe` 1
      previewStatus (head result) `shouldBe` FsConflict

    it "classifies an orphaned file as FsOrphaned" $ do
      let ops = [WriteFileOp "other.txt" "content" Template]
          diff =
            emptyDiff
              { diffNew = [PlannedFile "other.txt" modName "content"],
                diffOrphaned = [OrphanedFile "old.txt" modName]
              }
          result = buildPreview ops (Just diff) Map.empty
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
          result = buildPreview ops (Just diff) Map.empty
      -- Only the file preview, orphan is suppressed because path matches an operation
      length result `shouldBe` 1
      case head result of
        FilePreview {} -> pure ()
        _ -> expectationFailure "Expected FilePreview"

    it "produces DirPreview for CreateDirOp" $ do
      let ops = [CreateDirOp "src"]
          result = buildPreview ops Nothing Map.empty
      length result `shouldBe` 1
      case head result of
        DirPreview path -> path `shouldBe` "src"
        _ -> expectationFailure "Expected DirPreview"

    it "produces CommandPreview for RunCommandOp" $ do
      let ops = [RunCommandOp "cabal build" Nothing]
          result = buildPreview ops Nothing Map.empty
      length result `shouldBe` 1
      case head result of
        CommandPreview cmd -> cmd `shouldBe` "cabal build"
        _ -> expectationFailure "Expected CommandPreview"

    it "maps PatchFileOp to FilePreview with patch annotation" $ do
      let ops = [PatchFileOp "README.md" "extra content" AppendSection Template modName]
          result = buildPreview ops Nothing Map.empty
      length result `shouldBe` 1
      case head result of
        FilePreview status path annotation mMod -> do
          status `shouldBe` FsNew
          path `shouldBe` "README.md"
          annotation `shouldBe` "patch"
          mMod `shouldBe` Just modName
        _ -> expectationFailure "Expected FilePreview"

    it "maps CopyFileOp to FilePreview with copy annotation" $ do
      let ops = [CopyFileOp "templates/LICENSE" "LICENSE"]
          result = buildPreview ops Nothing Map.empty
      length result `shouldBe` 1
      case head result of
        FilePreview _ path annotation _ -> do
          path `shouldBe` "LICENSE"
          annotation `shouldBe` "copy"
        _ -> expectationFailure "Expected FilePreview"

    it "includes correct strategy annotation for WriteFileOp" $ do
      let ops =
            [ WriteFileOp "a.txt" "" Copy,
              WriteFileOp "b.txt" "" Template,
              WriteFileOp "c.txt" "" DhallText,
              WriteFileOp "d.txt" "" Structured
            ]
          result = buildPreview ops Nothing Map.empty
      map previewAnnotation (filter isFilePreview result)
        `shouldBe` ["copy", "template", "dhall-text", "structured"]

  describe "renderPreviewPlain" $ do
    it "renders empty list as 'No operations' message" $ do
      renderPreviewPlain [] `shouldBe` "No operations to perform.\n"

    it "renders FilePreview lines with status tags" $ do
      let lines' =
            [ FilePreview FsNew "README.md" "template" Nothing,
              FilePreview FsModified "src/Lib.hs" "template" Nothing,
              FilePreview FsUnchanged "LICENSE" "copy" Nothing,
              FilePreview FsConflict "config.yml" "structured" Nothing,
              FilePreview FsOrphaned "old.txt" "template" Nothing
            ]
          rendered = renderPreviewPlain lines'
          renderedLines = T.lines rendered
      length renderedLines `shouldBe` 5
      (renderedLines !! 0) `shouldBe` "    [new]  README.md   (template)"
      (renderedLines !! 1) `shouldBe` "    [modified]  src/Lib.hs  (template)"
      (renderedLines !! 2) `shouldBe` "    [unchanged]  LICENSE     (copy)"
      (renderedLines !! 3) `shouldBe` "    [conflict]  config.yml  (structured)"
      (renderedLines !! 4) `shouldBe` "    [orphaned]  old.txt     (template)"

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
      (renderedLines !! 2) `shouldBe` "    [orphaned]  gone.txt  (orphaned from test-module)"

  describe "formatPlanView" $ do
    it "includes header with module names" $ do
      let preview = [FilePreview FsNew "README.md" "template" (Just modName)]
          diff = emptyDiff {diffNew = [PlannedFile "README.md" modName "# Hello"]}
          rendered = formatPlanView [modName] Map.empty preview diff
      T.isInfixOf "Generation Plan (test-module):" rendered `shouldBe` True

    it "includes header with multiple module names joined by +" $ do
      let preview = []
          diff = emptyDiff
          rendered = formatPlanView [modName, modName2] Map.empty preview diff
      T.isInfixOf "Generation Plan (test-module + other-module):" rendered `shouldBe` True

    it "includes Variables section when variables are present" $ do
      let vars = Map.fromList [(VarName "project.name", VText "hello")]
          preview = []
          diff = emptyDiff
          rendered = formatPlanView [modName] vars preview diff
      T.isInfixOf "Variables:" rendered `shouldBe` True
      T.isInfixOf "project.name" rendered `shouldBe` True
      T.isInfixOf "\"hello\"" rendered `shouldBe` True

    it "omits Variables section when no variables" $ do
      let rendered = formatPlanView [modName] Map.empty [] emptyDiff
      T.isInfixOf "Variables:" rendered `shouldBe` False

    it "includes summary with file and conflict counts" $ do
      let diff =
            emptyDiff
              { diffNew = [PlannedFile "a.txt" modName ""],
                diffModified = [ModifiedFile "b.txt" modName (SHA256 "old") "new"]
              }
          rendered = formatPlanView [modName] Map.empty [] diff
      T.isInfixOf "2 files to write, 0 conflicts" rendered `shouldBe` True

-- | Helper to test if a PreviewLine is a FilePreview.
isFilePreview :: PreviewLine -> Bool
isFilePreview (FilePreview {}) = True
isFilePreview _ = False
