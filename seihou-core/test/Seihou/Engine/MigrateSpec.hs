module Seihou.Engine.MigrateSpec (tests) where

import Control.Lens (to, (&), (.~), (^.))
import Data.Generics.Labels ()
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
    removeExactLine,
    validateSeedMigration,
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
    & #modules .~ [AppliedModule {name = modName, parentVars = emptyParentVars, origin = LocalOrigin "demo", moduleVersion = Just "1.0.0", appliedAt = fixedTime, removal = Nothing}]
    & #files .~ Map.fromList [(path, FileRecord {hash = hashContent content, moduleName = modName, strategy = Template, generatedAt = fixedTime, baseline = Nothing, applicationIds = mempty, sharedWriteMode = SharedWriteUnknown}) | (path, content) <- entries]

-- | Build an in-memory filesystem from (path, content) pairs.
mkFS :: [(FilePath, Text)] -> PureFS
mkFS entries = PureFS (Map.fromList entries) Set.empty Map.empty

-- | Single-step plan wrapping the supplied ops.
chain1 :: Text -> Text -> [MigrationOp] -> MigrationPlan
chain1 fromV toV ops =
  MigrationPlan
    { module_ = "demo",
      from = mkV fromV,
      to = mkV toV,
      steps = [Migration {from = fromV, to = toV, ops}]
    }

runClassifyResult :: PureFS -> Manifest -> MigrationPlan -> Either MigrationExecError ExecutedMigrationPlan
runClassifyResult fs manifest c =
  fst $
    runPureEff $
      runFilesystemPure fs $
        classifyMigration manifest c

runClassify :: PureFS -> Manifest -> MigrationPlan -> ExecutedMigrationPlan
runClassify fs manifest c =
  case runClassifyResult fs manifest c of
    Right plan -> plan
    Left err -> error ("MigrateSpec.runClassify: unexpected error " <> show err)

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
  describe "removeExactLine" $ do
    it "preserves CRLF, LF, whitespace variants and the final unterminated line" $
      removeExactLine ".envrc" ".envrc\r\n.envrc.local\r\n .envrc\n/.envrc\n.envrc\n# comment" `shouldBe` ".envrc.local\r\n .envrc\n/.envrc\n# comment"
    it "removes duplicate matches and an unterminated match" $
      removeExactLine ".envrc" ".envrc\n.envrc" `shouldBe` ""
    it "preserves a nonmatching final carriage return" $
      removeExactLine ".envrc" ".envrc\r" `shouldBe` ".envrc\r"
    it "is idempotent" $
      removeExactLine ".envrc" (removeExactLine ".envrc" "x\n.envrc\n") `shouldBe` "x\n"

  describe "RemoveLine execution" $ do
    it "preserves unrelated edits without force and retains manifest file metadata" $ do
      let manifest = mkManifest [(".gitignore", ".envrc\noriginal\n")]
          fs = mkFS [(".gitignore", ".envrc\noriginal\nuser edit\n")]
          plan = runClassify fs manifest (chain1 "1.0.0" "2.0.0" [RemoveLine ".gitignore" ".envrc"])
          (result, finalFS) = runExecute fs manifest plan False
      Map.lookup ".gitignore" (finalFS ^. #files) `shouldBe` Just "original\nuser edit\n"
      fmap (^. #files) result `shouldBe` Right (manifest ^. #files)
    it "does not create a missing target" $ do
      let manifest = mkManifest []
          fs = mkFS []
          plan = runClassify fs manifest (chain1 "1.0.0" "2.0.0" [RemoveLine ".gitignore" ".envrc"])
          (_, finalFS) = runExecute fs manifest plan False
      finalFS `shouldBe` fs
    it "rejects a symlink target without editing its referent" $ do
      let manifest = mkManifest []
          fs = (mkFS [("real", ".envrc\n")]) & #links .~ Map.singleton ".gitignore" "real"
          plan = runClassify fs manifest (chain1 "1.0.0" "2.0.0" [RemoveLine ".gitignore" ".envrc"])
          (result, finalFS) = runExecute fs manifest plan False
      result `shouldSatisfy` either (const True) (const False)
      finalFS `shouldBe` fs
    it "rejects protected seed targets and their parent paths" $ do
      mapM_ (\path -> validateSeedMigration (Set.singleton "owned/seed") [RemoveLine path ".envrc"] `shouldSatisfy` either (const True) (const False)) ["owned/seed", "owned"]
    it "rejects unsafe paths before reading any target" $ do
      mapM_ (\path -> runClassifyResult (mkFS []) (mkManifest []) (chain1 "1.0.0" "2.0.0" [RemoveLine path ".envrc"]) `shouldSatisfy` either (const True) (const False)) ["../outside", "/absolute", ".git/config", ".seihou/manifest.json"]
    it "rejects directories and paths through symbolic-link parents" $ do
      let fs = (mkFS [("real/ignore", ".envrc\n")]) & #dirs .~ Set.singleton "directory" & #links .~ Map.singleton "linked" "real"
      mapM_
        ( \path -> do
            let plan = runClassify fs (mkManifest []) (chain1 "1.0.0" "2.0.0" [RemoveLine path ".envrc"])
                (result, finalFS) = runExecute fs (mkManifest []) plan False
            result `shouldSatisfy` either (const True) (const False)
            finalFS `shouldBe` fs
        )
        ["directory", "linked/ignore"]
    it "rejects empty and multiline removal arguments" $ do
      let manifest = mkManifest []
      mapM_ (\line -> runClassifyResult (mkFS []) manifest (chain1 "1.0.0" "2.0.0" [RemoveLine ".gitignore" line]) `shouldSatisfy` either (const True) (const False)) ["", "a\nb", "a\rb"]
  describe "classifyMigration" $ do
    it "marks a move-file safe when disk hash matches manifest" $ do
      let manifest = mkManifest [("app/Main.hs", "module Main where")]
          fs = mkFS [("app/Main.hs", "module Main where")]
          c = chain1 "1.0.0" "2.0.0" [MoveFile "app/Main.hs" "src/Main.hs"]
          plan = runClassify fs manifest c
      (plan ^. #ops) `shouldBe` [MoveFileInst "app/Main.hs" "src/Main.hs" MFSafe]

    it "marks a move-file as conflict when disk content differs" $ do
      let manifest = mkManifest [("app/Main.hs", "original")]
          fs = mkFS [("app/Main.hs", "user-edited")]
          c = chain1 "1.0.0" "2.0.0" [MoveFile "app/Main.hs" "src/Main.hs"]
          plan = runClassify fs manifest c
      (plan ^. #ops) `shouldBe` [MoveFileInst "app/Main.hs" "src/Main.hs" MFConflict]

    it "marks a delete-file as gone when the file is absent" $ do
      let manifest = mkManifest [("Setup.hs", "boring")]
          fs = mkFS [] -- file already deleted on disk
          c = chain1 "1.0.0" "2.0.0" [DeleteFile "Setup.hs"]
          plan = runClassify fs manifest c
      (plan ^. #ops) `shouldBe` [DeleteFileInst "Setup.hs" MFGone]

    it "rejects a delete-dir path with a parent directory segment" $ do
      let manifest = mkManifest []
          fs = mkFS []
          c = chain1 "1.0.0" "2.0.0" [DeleteDir "../outside"]
          result = runClassifyResult fs manifest c
      result `shouldBe` Left (MigrationUnsafePath "delete-dir path" "../outside" "path must not contain '..' segment: ../outside")

    it "rejects a move-file destination with a parent directory segment" $ do
      let manifest = mkManifest [("README.md", "hello")]
          fs = mkFS [("README.md", "hello")]
          c = chain1 "1.0.0" "2.0.0" [MoveFile "README.md" "../outside"]
          result = runClassifyResult fs manifest c
      result `shouldBe` Left (MigrationUnsafePath "move-file destination" "../outside" "path must not contain '..' segment: ../outside")

    it "rejects a migration path in Seihou's own state" $ do
      let manifest = mkManifest []
          fs = mkFS []
          c = chain1 "1.0.0" "2.0.0" [DeleteDir ".seihou/baselines"]
          result = runClassifyResult fs manifest c
      result `shouldBe` Left (MigrationUnsafePath "delete-dir path" ".seihou/baselines" "path targets Seihou's own state at .seihou/baselines")

    it "rejects a migration that deletes the .seihou directory itself" $ do
      let c = chain1 "1.0.0" "2.0.0" [DeleteDir ".seihou"]
      runClassifyResult (mkFS []) (mkManifest []) c `shouldSatisfy` either (const True) (const False)

    it "allows moving a legacy .seihou file into the module's own directory" $ do
      let manifest = mkManifest [(".seihou/gcp-kube-env.conf", "x")]
          fs = mkFS [(".seihou/gcp-kube-env.conf", "x")]
          c = chain1 "1.0.0" "2.0.0" [MoveFile ".seihou/gcp-kube-env.conf" ".seihou/gcp-kube-env/env.conf"]
          plan = runClassify fs manifest c
      (plan ^. #ops) `shouldBe` [MoveFileInst ".seihou/gcp-kube-env.conf" ".seihou/gcp-kube-env/env.conf" MFSafe]

    it "rejects a run-command workDir with a parent directory segment" $ do
      let manifest = mkManifest []
          fs = mkFS []
          c = chain1 "1.0.0" "2.0.0" [RunCommand "echo unsafe" (Just "../outside")]
          result = runClassifyResult fs manifest c
      result `shouldBe` Left (MigrationUnsafePath "run-command workDir" "../outside" "path must not contain '..' segment: ../outside")

  describe "executeMigration" $ do
    it "renames a single safe file and rewrites the manifest" $ do
      let manifest = mkManifest [("app/Main.hs", "x")]
          fs = mkFS [("app/Main.hs", "x")]
          c = chain1 "1.0.0" "2.0.0" [MoveFile "app/Main.hs" "src/Main.hs"]
          plan = runClassify fs manifest c
          (result, fs') = runExecute fs manifest plan False
      case result of
        Right m -> do
          Map.member "src/Main.hs" (m ^. #files) `shouldBe` True
          Map.member "app/Main.hs" (m ^. #files) `shouldBe` False
          ((head (m ^. #modules)) ^. #moduleVersion) `shouldBe` Just "2.0.0"
        Left err -> expectationFailure ("expected Right, got: " <> show err)
      Map.member "src/Main.hs" (fs' ^. #files) `shouldBe` True
      Map.member "app/Main.hs" (fs' ^. #files) `shouldBe` False

    it "refuses on conflict without --force and leaves disk untouched" $ do
      let manifest = mkManifest [("app/Main.hs", "original")]
          fs = mkFS [("app/Main.hs", "user-edited")]
          c = chain1 "1.0.0" "2.0.0" [MoveFile "app/Main.hs" "src/Main.hs"]
          plan = runClassify fs manifest c
          (result, fs') = runExecute fs manifest plan False
      result `shouldBe` Left (MigrationConflict ["app/Main.hs"])
      -- Disk untouched: original src still there, dest absent.
      Map.member "app/Main.hs" (fs' ^. #files) `shouldBe` True
      Map.member "src/Main.hs" (fs' ^. #files) `shouldBe` False

    it "executes through a conflict when force is set" $ do
      let manifest = mkManifest [("app/Main.hs", "original")]
          fs = mkFS [("app/Main.hs", "user-edited")]
          c = chain1 "1.0.0" "2.0.0" [MoveFile "app/Main.hs" "src/Main.hs"]
          plan = runClassify fs manifest c
          (result, fs') = runExecute fs manifest plan True
      case result of
        Right m -> do
          Map.member "src/Main.hs" (m ^. #files) `shouldBe` True
          Map.member "app/Main.hs" (m ^. #files) `shouldBe` False
        Left err -> expectationFailure ("expected Right, got: " <> show err)
      -- The user-edited content rode along: the move is a key rename in
      -- the pure FS, so the bytes follow the rename.
      Map.lookup "src/Main.hs" (fs' ^. #files) `shouldBe` Just "user-edited"

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
          Map.keys (m ^. #files) `shouldMatchList` ["src/Main.hs", "src/Lib.hs"]
        Left err -> expectationFailure ("expected Right, got: " <> show err)
      Map.keys (fs' ^. #files) `shouldMatchList` ["src/Main.hs", "src/Lib.hs"]

    it "is a no-op for a delete-file whose target is already gone" $ do
      let manifest = mkManifest [("Setup.hs", "boring")]
          fs = mkFS [] -- absent on disk
          c = chain1 "1.0.0" "2.0.0" [DeleteFile "Setup.hs"]
          plan = runClassify fs manifest c
          (result, fs') = runExecute fs manifest plan False
      case result of
        Right m -> Map.member "Setup.hs" (m ^. #files) `shouldBe` False
        Left err -> expectationFailure ("expected Right, got: " <> show err)
      Map.null (fs' ^. #files) `shouldBe` True

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
        Right m -> Map.keys (m ^. #files) `shouldBe` ["keep.hs"]
        Left err -> expectationFailure ("expected Right, got: " <> show err)
      Map.keys (fs' ^. #files) `shouldBe` ["keep.hs"]

    it "applies a chain of two migrations in declaration order" $ do
      -- 1.0.0 → 2.0.0: move app → src
      -- 2.0.0 → 3.0.0: delete src/Main.hs
      let manifest = mkManifest [("app/Main.hs", "x")]
          fs = mkFS [("app/Main.hs", "x")]
          chain =
            MigrationPlan
              { module_ = "demo",
                from = mkV "1.0.0",
                to = mkV "3.0.0",
                steps =
                  [ Migration "1.0.0" "2.0.0" [MoveDir "app" "src"],
                    Migration "2.0.0" "3.0.0" [DeleteFile "src/Main.hs"]
                  ]
              }
          plan = runClassify fs manifest chain
          (result, fs') = runExecute fs manifest plan False
      case result of
        Right m -> do
          Map.null (m ^. #files) `shouldBe` True
          ((head (m ^. #modules)) ^. #moduleVersion) `shouldBe` Just "3.0.0"
        Left err -> expectationFailure ("expected Right, got: " <> show err)
      Map.null (fs' ^. #files) `shouldBe` True
