module Seihou.Engine.MigrateSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Time (UTCTime, defaultTimeLocale, parseTimeOrError)
import Effectful
import Seihou.Core.Migration
  ( Migration (..),
    MigrationOp (..),
    MigrationPlan (..),
  )
import Seihou.Core.Types
import Seihou.Core.Version (Version, parseVersion)
import Seihou.Effect.FilesystemPure (PureFS (..), runFilesystemPure)
import Seihou.Effect.ProcessPure (runProcessPure)
import Seihou.Engine.Migrate
  ( ExecutedMigrationPlan (..),
    MigrationExecError (..),
    MigrationFileStatus (..),
    MigrationOpInstance (..),
    classifyMigration,
    executeMigration,
  )
import Seihou.Manifest.Hash (hashContent)
import Seihou.Manifest.Types (emptyManifest)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Engine.Migrate" spec

-- ----------------------------------------------------------------------------
-- Fixtures and helpers
-- ----------------------------------------------------------------------------

fixedTime :: UTCTime
fixedTime = parseTimeOrError True defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ" "2026-04-01T10:00:00Z"

migrateTime :: UTCTime
migrateTime = parseTimeOrError True defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ" "2026-04-25T11:00:00Z"

modName :: ModuleName
modName = ModuleName "demo"

mkV :: Text -> Version
mkV t = case parseVersion t of
  Just v -> v
  Nothing -> error ("MigrateSpec.mkV: bad version " <> show t)

-- | Build a manifest with the given files (path, content) all owned by
-- the demo module. The manifest hash is the SHA256 of the content, so
-- safe-vs-conflict can be exercised by mutating the on-disk content.
mkManifest :: [(FilePath, Text)] -> Manifest
mkManifest entries =
  (emptyManifest fixedTime)
    { modules =
        [ AppliedModule
            { name = modName,
              parentVars = emptyParentVars,
              source = "/installed/demo",
              moduleVersion = Just "1.0.0",
              appliedAt = fixedTime,
              removal = Nothing
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
          | (path, content) <- entries
          ]
    }

-- | Build an in-memory filesystem from (path, content) pairs.
mkFS :: [(FilePath, Text)] -> PureFS
mkFS entries = PureFS (Map.fromList entries) Set.empty

-- | Single-step plan wrapping the supplied ops.
chain1 :: Text -> Text -> [MigrationOp] -> MigrationPlan
chain1 fromV toV ops =
  MigrationPlan
    { planModule = "demo",
      planFrom = mkV fromV,
      planTo = mkV toV,
      planSteps = [Migration {from = fromV, to = toV, ops}]
    }

runClassify :: PureFS -> Manifest -> MigrationPlan -> ExecutedMigrationPlan
runClassify fs manifest c =
  fst $
    runPureEff $
      runFilesystemPure fs $
        classifyMigration manifest c

runExecute ::
  PureFS ->
  Manifest ->
  ExecutedMigrationPlan ->
  Bool ->
  (Either MigrationExecError Manifest, PureFS)
runExecute fs manifest plan force =
  runPureEff $
    runFilesystemPure fs $
      runProcessPure [] $
        executeMigration force plan manifest migrateTime

-- ----------------------------------------------------------------------------
-- Spec
-- ----------------------------------------------------------------------------

spec :: Spec
spec = do
  describe "classifyMigration" $ do
    it "marks a move-file safe when disk hash matches manifest" $ do
      let manifest = mkManifest [("app/Main.hs", "module Main where")]
          fs = mkFS [("app/Main.hs", "module Main where")]
          c = chain1 "1.0.0" "2.0.0" [MoveFile "app/Main.hs" "src/Main.hs"]
          plan = runClassify fs manifest c
      plan.planOps `shouldBe` [MoveFileInst "app/Main.hs" "src/Main.hs" MFSafe]

    it "marks a move-file as conflict when disk content differs" $ do
      let manifest = mkManifest [("app/Main.hs", "original")]
          fs = mkFS [("app/Main.hs", "user-edited")]
          c = chain1 "1.0.0" "2.0.0" [MoveFile "app/Main.hs" "src/Main.hs"]
          plan = runClassify fs manifest c
      plan.planOps `shouldBe` [MoveFileInst "app/Main.hs" "src/Main.hs" MFConflict]

    it "marks a delete-file as gone when the file is absent" $ do
      let manifest = mkManifest [("Setup.hs", "boring")]
          fs = mkFS [] -- file already deleted on disk
          c = chain1 "1.0.0" "2.0.0" [DeleteFile "Setup.hs"]
          plan = runClassify fs manifest c
      plan.planOps `shouldBe` [DeleteFileInst "Setup.hs" MFGone]

  describe "executeMigration" $ do
    it "renames a single safe file and rewrites the manifest" $ do
      let manifest = mkManifest [("app/Main.hs", "x")]
          fs = mkFS [("app/Main.hs", "x")]
          c = chain1 "1.0.0" "2.0.0" [MoveFile "app/Main.hs" "src/Main.hs"]
          plan = runClassify fs manifest c
          (result, fs') = runExecute fs manifest plan False
      case result of
        Right m -> do
          Map.member "src/Main.hs" m.files `shouldBe` True
          Map.member "app/Main.hs" m.files `shouldBe` False
          (head m.modules).moduleVersion `shouldBe` Just "2.0.0"
        Left err -> expectationFailure ("expected Right, got: " <> show err)
      Map.member "src/Main.hs" fs'.files `shouldBe` True
      Map.member "app/Main.hs" fs'.files `shouldBe` False

    it "refuses on conflict without --force and leaves disk untouched" $ do
      let manifest = mkManifest [("app/Main.hs", "original")]
          fs = mkFS [("app/Main.hs", "user-edited")]
          c = chain1 "1.0.0" "2.0.0" [MoveFile "app/Main.hs" "src/Main.hs"]
          plan = runClassify fs manifest c
          (result, fs') = runExecute fs manifest plan False
      result `shouldBe` Left (MigrationConflict ["app/Main.hs"])
      -- Disk untouched: original src still there, dest absent.
      Map.member "app/Main.hs" fs'.files `shouldBe` True
      Map.member "src/Main.hs" fs'.files `shouldBe` False

    it "executes through a conflict when force is set" $ do
      let manifest = mkManifest [("app/Main.hs", "original")]
          fs = mkFS [("app/Main.hs", "user-edited")]
          c = chain1 "1.0.0" "2.0.0" [MoveFile "app/Main.hs" "src/Main.hs"]
          plan = runClassify fs manifest c
          (result, fs') = runExecute fs manifest plan True
      case result of
        Right m -> do
          Map.member "src/Main.hs" m.files `shouldBe` True
          Map.member "app/Main.hs" m.files `shouldBe` False
        Left err -> expectationFailure ("expected Right, got: " <> show err)
      -- The user-edited content rode along: the move is a key rename in
      -- the pure FS, so the bytes follow the rename.
      Map.lookup "src/Main.hs" fs'.files `shouldBe` Just "user-edited"

    it "moves a directory, rewriting all contained manifest entries" $ do
      let manifest =
            mkManifest
              [ ("app/Main.hs", "main"),
                ("app/Lib.hs", "lib")
              ]
          fs =
            mkFS
              [ ("app/Main.hs", "main"),
                ("app/Lib.hs", "lib")
              ]
          c = chain1 "1.0.0" "2.0.0" [MoveDir "app" "src"]
          plan = runClassify fs manifest c
          (result, fs') = runExecute fs manifest plan False
      case result of
        Right m -> do
          Map.keys m.files `shouldMatchList` ["src/Main.hs", "src/Lib.hs"]
        Left err -> expectationFailure ("expected Right, got: " <> show err)
      Map.keys fs'.files `shouldMatchList` ["src/Main.hs", "src/Lib.hs"]

    it "is a no-op for a delete-file whose target is already gone" $ do
      let manifest = mkManifest [("Setup.hs", "boring")]
          fs = mkFS [] -- absent on disk
          c = chain1 "1.0.0" "2.0.0" [DeleteFile "Setup.hs"]
          plan = runClassify fs manifest c
          (result, fs') = runExecute fs manifest plan False
      case result of
        Right m -> Map.member "Setup.hs" m.files `shouldBe` False
        Left err -> expectationFailure ("expected Right, got: " <> show err)
      Map.null fs'.files `shouldBe` True

    it "deletes a directory and drops every manifest entry under it" $ do
      let manifest =
            mkManifest
              [ ("legacy/a.hs", "a"),
                ("legacy/sub/b.hs", "b"),
                ("keep.hs", "k")
              ]
          fs =
            mkFS
              [ ("legacy/a.hs", "a"),
                ("legacy/sub/b.hs", "b"),
                ("keep.hs", "k")
              ]
          c = chain1 "1.0.0" "2.0.0" [DeleteDir "legacy"]
          plan = runClassify fs manifest c
          (result, fs') = runExecute fs manifest plan False
      case result of
        Right m -> Map.keys m.files `shouldBe` ["keep.hs"]
        Left err -> expectationFailure ("expected Right, got: " <> show err)
      Map.keys fs'.files `shouldBe` ["keep.hs"]

    it "applies a chain of two migrations in declaration order" $ do
      -- 1.0.0 → 2.0.0: move app → src
      -- 2.0.0 → 3.0.0: delete src/Main.hs
      let manifest = mkManifest [("app/Main.hs", "x")]
          fs = mkFS [("app/Main.hs", "x")]
          chain =
            MigrationPlan
              { planModule = "demo",
                planFrom = mkV "1.0.0",
                planTo = mkV "3.0.0",
                planSteps =
                  [ Migration "1.0.0" "2.0.0" [MoveDir "app" "src"],
                    Migration "2.0.0" "3.0.0" [DeleteFile "src/Main.hs"]
                  ]
              }
          plan = runClassify fs manifest chain
          (result, fs') = runExecute fs manifest plan False
      case result of
        Right m -> do
          Map.null m.files `shouldBe` True
          (head m.modules).moduleVersion `shouldBe` Just "3.0.0"
        Left err -> expectationFailure ("expected Right, got: " <> show err)
      Map.null fs'.files `shouldBe` True
