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

-- | Helper: create a manifest with a specific removal spec.
mkManifestWithRemoval :: Removal -> [(FilePath, Text)] -> Manifest
mkManifestWithRemoval removal fileContents =
  (emptyManifest fixedTime)
    { modules =
        [ AppliedModule
            { name = modName,
              source = "/path/to/test-module",
              appliedAt = fixedTime,
              removal = Just removal
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

-- | Run buildRemovalOps in the pure filesystem.
runBuildOps :: PureFS -> Manifest -> ModuleName -> Removal -> Either RemovalError ExecutedRemovalPlan
runBuildOps fs manifest name removal =
  fst $ runPureEff $ runFilesystemPure fs $ buildRemovalOps manifest name removal

-- | Run executeRemovalOps in the pure filesystem.
runExecOps :: PureFS -> Manifest -> ExecutedRemovalPlan -> Set.Set FilePath -> (Manifest, PureFS)
runExecOps fs manifest plan keepSet =
  let (result, finalFS) =
        runPureEff $
          runFilesystemPure fs $
            executeRemovalOps manifest plan keepSet removeTime
   in (result, finalFS)

spec :: Spec
spec = do
  describe "computeRemovalPlan" $ do
    it "returns ModuleNotApplied when module is not in manifest" $ do
      let manifest = emptyManifest fixedTime
          result = runPlan emptyFS manifest modName
      result `shouldBe` Left (ModuleNotApplied modName)

    it "returns ModuleNotRemovable when removal is Nothing" $ do
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

  describe "buildRemovalOps" $ do
    it "returns ModuleNotApplied when module is not in manifest" $ do
      let manifest = emptyManifest fixedTime
          removal = Removal [] []
          result = runBuildOps emptyFS manifest modName removal
      result `shouldBe` Left (ModuleNotApplied modName)

    it "builds DeleteFileOp with RFSafe for unchanged files" $ do
      let removal = Removal [RemovalStep RemoveFileAction "README.md" Nothing] []
          manifest = mkManifestWithRemoval removal [("README.md", "hello")]
          fs = mkFS [("README.md", "hello")]
          result = runBuildOps fs manifest modName removal
      case result of
        Left err -> expectationFailure ("unexpected error: " <> show err)
        Right plan -> plan.ops `shouldBe` [DeleteFileOp "README.md" RFSafe]

    it "builds DeleteFileOp with RFConflict for modified files" $ do
      let removal = Removal [RemovalStep RemoveFileAction "README.md" Nothing] []
          manifest = mkManifestWithRemoval removal [("README.md", "original")]
          fs = mkFS [("README.md", "user changed this")]
          result = runBuildOps fs manifest modName removal
      case result of
        Left err -> expectationFailure ("unexpected error: " <> show err)
        Right plan -> plan.ops `shouldBe` [DeleteFileOp "README.md" RFConflict]

    it "builds DeleteFileOp with RFGone for already-deleted files" $ do
      let removal = Removal [RemovalStep RemoveFileAction "README.md" Nothing] []
          manifest = mkManifestWithRemoval removal [("README.md", "hello")]
          result = runBuildOps emptyFS manifest modName removal
      case result of
        Left err -> expectationFailure ("unexpected error: " <> show err)
        Right plan -> plan.ops `shouldBe` [DeleteFileOp "README.md" RFGone]

    it "builds StripSectionOp for remove-section steps" $ do
      let removal = Removal [RemovalStep RemoveSectionAction ".gitignore" Nothing] []
          manifest = mkManifestWithRemoval removal [(".gitignore", "content")]
          fs = mkFS [(".gitignore", "content")]
          result = runBuildOps fs manifest modName removal
      case result of
        Left err -> expectationFailure ("unexpected error: " <> show err)
        Right plan -> plan.ops `shouldBe` [StripSectionOp ".gitignore"]

    it "builds RemovalCommandOp for removal commands" $ do
      let removal = Removal [] [Command "cabal clean" Nothing Nothing]
          manifest = mkManifestWithRemoval removal []
          result = runBuildOps emptyFS manifest modName removal
      case result of
        Left err -> expectationFailure ("unexpected error: " <> show err)
        Right plan -> plan.ops `shouldBe` [RemovalCommandOp "cabal clean" Nothing]

    it "combines steps and commands in order" $ do
      let removal =
            Removal
              [RemovalStep RemoveFileAction "a.txt" Nothing, RemovalStep RemoveSectionAction ".gitignore" Nothing]
              [Command "echo done" Nothing Nothing]
          manifest = mkManifestWithRemoval removal [("a.txt", "aaa")]
          fs = mkFS [("a.txt", "aaa"), (".gitignore", "stuff")]
          result = runBuildOps fs manifest modName removal
      case result of
        Left err -> expectationFailure ("unexpected error: " <> show err)
        Right plan -> do
          length plan.ops `shouldBe` 3
          case plan.ops of
            [DeleteFileOp _ _, StripSectionOp _, RemovalCommandOp _ _] -> pure ()
            other -> expectationFailure ("unexpected ops: " <> show other)

  describe "executeRemovalOps" $ do
    it "deletes files with DeleteFileOp" $ do
      let removal = Removal [RemovalStep RemoveFileAction "README.md" Nothing] []
          manifest = mkManifestWithRemoval removal [("README.md", "hello")]
          fs = mkFS [("README.md", "hello")]
          plan = ExecutedRemovalPlan modName [DeleteFileOp "README.md" RFSafe]
          (_, finalFS) = runExecOps fs manifest plan Set.empty
      Map.member "README.md" finalFS.files `shouldBe` False

    it "preserves files in keep-set for DeleteFileOp" $ do
      let removal = Removal [RemovalStep RemoveFileAction "a.txt" Nothing] []
          manifest = mkManifestWithRemoval removal [("a.txt", "aaa")]
          fs = mkFS [("a.txt", "modified")]
          plan = ExecutedRemovalPlan modName [DeleteFileOp "a.txt" RFConflict]
          keepSet = Set.singleton "a.txt"
          (_, finalFS) = runExecOps fs manifest plan keepSet
      Map.member "a.txt" finalFS.files `shouldBe` True

    it "skips gone files" $ do
      let manifest = mkManifest True [("a.txt", "aaa")]
          plan = ExecutedRemovalPlan modName [DeleteFileOp "a.txt" RFGone]
          (updated, _) = runExecOps emptyFS manifest plan Set.empty
      updated.modules `shouldBe` []

    it "strips section from file with StripSectionOp" $ do
      let content = "before\n# --- seihou:test-module ---\nmodule content\n# --- /seihou:test-module ---\nafter\n"
          manifest = mkManifest True [(".gitignore", content)]
          fs = mkFS [(".gitignore", content)]
          plan = ExecutedRemovalPlan modName [StripSectionOp ".gitignore"]
          (_, finalFS) = runExecOps fs manifest plan Set.empty
      case Map.lookup ".gitignore" finalFS.files of
        Nothing -> expectationFailure ".gitignore should still exist"
        Just result -> do
          result `shouldSatisfy` \t ->
            "before" `elem` lines (show t) || not ("seihou:test-module" `elem` lines (show t))

    it "leaves file unchanged when no section markers found" $ do
      let content = "no markers here\n"
          manifest = mkManifest True [("file.txt", content)]
          fs = mkFS [("file.txt", content)]
          plan = ExecutedRemovalPlan modName [StripSectionOp "file.txt"]
          (_, finalFS) = runExecOps fs manifest plan Set.empty
      Map.lookup "file.txt" finalFS.files `shouldBe` Just content

    it "removes module from manifest after all steps" $ do
      let removal = Removal [RemovalStep RemoveFileAction "a.txt" Nothing] []
          manifest = mkManifestWithRemoval removal [("a.txt", "aaa")]
          fs = mkFS [("a.txt", "aaa")]
          plan = ExecutedRemovalPlan modName [DeleteFileOp "a.txt" RFSafe]
          (updated, _) = runExecOps fs manifest plan Set.empty
      updated.modules `shouldBe` []
      Map.null updated.files `shouldBe` True

    it "preserves other modules' files in manifest" $ do
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
          plan = ExecutedRemovalPlan modName [DeleteFileOp "mine.txt" RFSafe]
          (updated, _) = runExecOps fs manifest plan Set.empty
      Map.member "other.txt" updated.files `shouldBe` True
      Map.member "mine.txt" updated.files `shouldBe` False
