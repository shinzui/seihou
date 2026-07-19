module Seihou.Engine.ReconcileSpec (tests) where

import Data.Functor.Identity (Identity (..))
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Time (UTCTime, defaultTimeLocale, parseTimeOrError)
import Seihou.Core.Types hiding (KeepCurrent)
import Seihou.Effect.BaselineStore (BaselineError (..))
import Seihou.Engine.Reconcile
import Seihou.Engine.ThreeWayMerge (MergeOutcome (..))
import Seihou.Manifest.Hash (baselineRefForContent, hashContent)
import Seihou.Manifest.Types (emptyManifest)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Engine.Reconcile" spec

spec :: Spec
spec = do
  describe "materialization" $ do
    it "folds four ordered patches into one desired file" $ do
      let operations =
            [ patch "one" "mod-a",
              patch "two" "mod-b",
              patch "two" "mod-c",
              patch "three" "mod-d"
            ]
          result = planWith (Map.singleton ".gitignore" "root\n") Map.empty Map.empty empty [appA] operations (owners ".gitignore" [appA]) cleanMerge
      case result of
        Right reconciliation -> do
          Map.size reconciliation.files `shouldBe` 1
          case reconciliation.files Map.! ".gitignore" of
            FileUpdate desired _ _ _ -> desired.generatedContent `shouldBe` "root\none\ntwo\nthree\n"
            other -> expectationFailure ("expected one update, got " <> show other)
        Left err -> expectationFailure (show err)

    it "replays a patch after a complete write" $ do
      let operations =
            [ WriteFileOp "README.md" "generated\n" Template,
              PatchFileOp "README.md" "added\n" AppendFile Template "mod-b"
            ]
          result = planWith Map.empty Map.empty Map.empty empty [appA] operations (owners "README.md" [appA]) cleanMerge
      case result of
        Right reconciliation -> case reconciliation.files Map.! "README.md" of
          FileCreate desired _ _ -> desired.generatedContent `shouldBe` "generated\nadded\n"
          other -> expectationFailure ("expected create, got " <> show other)
        Left err -> expectationFailure (show err)

    it "materializes copy operations through the supplied source reader" $ do
      let operations = [CopyFileOp "/staged/template" "copied.txt"]
          result =
            planWith
              Map.empty
              (Map.singleton "/staged/template" "copied\n")
              Map.empty
              empty
              [appA]
              operations
              (owners "copied.txt" [appA])
              cleanMerge
      case result of
        Right reconciliation -> case reconciliation.files Map.! "copied.txt" of
          FileCreate desired _ _ -> do
            desired.generatedContent `shouldBe` "copied\n"
            desired.strategy `shouldBe` Copy
          other -> expectationFailure ("expected create, got " <> show other)
        Left err -> expectationFailure (show err)

  describe "baseline trust and application scoping" $ do
    it "adopts a legacy disk baseline only when its recorded hash matches" $ do
      let manifest = withFile "legacy.txt" (record "legacy\n" Nothing [appA]) empty
          result =
            planWith
              (Map.singleton "legacy.txt" "legacy\n")
              Map.empty
              Map.empty
              manifest
              [appA]
              [WriteFileOp "legacy.txt" "new\n" Template]
              (owners "legacy.txt" [appA])
              cleanMerge
      case result of
        Right reconciliation -> case reconciliation.files Map.! "legacy.txt" of
          FileUpdate _ _ _ _ -> pure ()
          other -> expectationFailure ("expected trusted update, got " <> show other)
        Left err -> expectationFailure (show err)

    it "refuses to guess a legacy baseline after a user edit" $ do
      let manifest = withFile "legacy.txt" (record "legacy\n" Nothing [appA]) empty
          result =
            planWith
              (Map.singleton "legacy.txt" "user edit\n")
              Map.empty
              Map.empty
              manifest
              [appA]
              [WriteFileOp "legacy.txt" "new\n" Template]
              (owners "legacy.txt" [appA])
              cleanMerge
      case result of
        Right reconciliation -> case reconciliation.files Map.! "legacy.txt" of
          FileConflict _ current _ MissingTrustedBaseline _ _ Nothing -> current `shouldBe` "user edit\n"
          other -> expectationFailure ("expected conservative conflict, got " <> show other)
        Left err -> expectationFailure (show err)

    it "reports every owner when a targeted update regenerates a shared path" $ do
      let manifest = withFile "shared.txt" (record "old\n" Nothing [appA, appB]) empty
          result =
            planWith
              (Map.singleton "shared.txt" "old\n")
              Map.empty
              Map.empty
              manifest
              [appA]
              [WriteFileOp "shared.txt" "new\n" Template]
              (owners "shared.txt" [appA])
              cleanMerge
      result `shouldBe` Left (SharedPathRequiresApplications "shared.txt" (Set.fromList [appA, appB]))

    it "rejects control paths before reading or planning" $ do
      let result =
            planWith
              Map.empty
              Map.empty
              Map.empty
              empty
              [appA]
              [WriteFileOp ".seihou/manifest.json" "bad" Template]
              (owners ".seihou/manifest.json" [appA])
              cleanMerge
      result `shouldSatisfy` isInvalidPath

  describe "classification and resolution" $ do
    it "preserves a user-only edit without advancing its applied hash" $ do
      let base = "base\n"
          ref = baselineRefForContent base
          oldRecord = record base (Just ref) [appA]
          manifest = withFile "file.txt" oldRecord empty
          result =
            planWith
              (Map.singleton "file.txt" "user\n")
              Map.empty
              (Map.singleton ref base)
              manifest
              [appA]
              [WriteFileOp "file.txt" base Template]
              (owners "file.txt" [appA])
              cleanMerge
      case result of
        Right reconciliation -> case reconciliation.files Map.! "file.txt" of
          FileUnchanged _ state _ _ -> do
            state.appliedContent `shouldBe` "user\n"
            state.recordedHash `shouldBe` oldRecord.hash
            state.writeToDisk `shouldBe` False
          other -> expectationFailure ("expected unchanged user edit, got " <> show other)
        Left err -> expectationFailure (show err)

    it "classifies a clean dual edit as one automatic merge" $ do
      let base = "base\n"
          ref = baselineRefForContent base
          manifest = withFile "file.txt" (record base (Just ref) [appA]) empty
          result =
            planWith
              (Map.singleton "file.txt" "user\n")
              Map.empty
              (Map.singleton ref base)
              manifest
              [appA]
              [WriteFileOp "file.txt" "generated\n" Template]
              (owners "file.txt" [appA])
              (\_ _ _ -> MergeClean "user and generated\n")
      case result of
        Right reconciliation -> do
          case reconciliation.files Map.! "file.txt" of
            FileAutoMerge _ state _ _ -> state.appliedContent `shouldBe` "user and generated\n"
            other -> expectationFailure ("expected automatic merge, got " <> show other)
          reconciliationSummary reconciliation `shouldBe` ReconciliationSummary 0 0 1 0 0 0 0 0
        Left err -> expectationFailure (show err)

    it "keeps overlapping edits unresolved until an explicit choice" $ do
      let base = "base\n"
          ref = baselineRefForContent base
          markers = "<<<<<<< current\nuser\n=======\ngenerated\n>>>>>>> new-generated\n"
          manifest = withFile "file.txt" (record base (Just ref) [appA]) empty
          planned =
            planWith
              (Map.singleton "file.txt" "user\n")
              Map.empty
              (Map.singleton ref base)
              manifest
              [appA]
              [WriteFileOp "file.txt" "generated\n" Template]
              (owners "file.txt" [appA])
              (\_ _ _ -> MergeConflicted markers)
      case planned of
        Left err -> expectationFailure (show err)
        Right reconciliation -> do
          unresolvedPaths reconciliation `shouldBe` Set.singleton "file.txt"
          let resolved = resolveFileConflict "file.txt" KeepCurrent reconciliation
          case resolved of
            Left err -> expectationFailure (show err)
            Right finalPlan -> case finalPlan.files Map.! "file.txt" of
              FileConflict _ _ _ _ _ _ (Just resolution) -> do
                resolution.state.generatedBaseline `shouldBe` "generated\n"
                resolution.state.appliedContent `shouldBe` "user\n"
                unresolvedPaths finalPlan `shouldBe` Set.empty
              other -> expectationFailure ("expected resolved conflict, got " <> show other)

  describe "orphan handling" $ do
    it "distinguishes safe deletion, edited retention, and shared release" $ do
      let manifest =
            withFile "safe.txt" (record "safe\n" Nothing [appA]) $
              withFile "edited.txt" (record "before\n" Nothing [appA]) $
                withFile "shared.txt" (record "shared\n" Nothing [appA, appB]) empty
          disk =
            Map.fromList
              [ ("safe.txt", "safe\n"),
                ("edited.txt", "user\n"),
                ("shared.txt", "shared\n")
              ]
          result = planWith disk Map.empty Map.empty manifest [appA] [] Map.empty cleanMerge
      case result of
        Left err -> expectationFailure (show err)
        Right reconciliation -> do
          reconciliation.files Map.! "safe.txt" `shouldSatisfy` isSafeDelete
          reconciliation.files Map.! "edited.txt" `shouldSatisfy` isEditedOrphan
          reconciliation.files Map.! "shared.txt" `shouldSatisfy` isSharedRelease
          unresolvedPaths reconciliation `shouldBe` Set.singleton "edited.txt"
          case resolveEditedOrphan "edited.txt" RetainTrackedOrphan reconciliation of
            Left err -> expectationFailure (show err)
            Right resolved -> unresolvedPaths resolved `shouldBe` Set.empty

fixedTime :: UTCTime
fixedTime = parseTimeOrError True defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ" "2026-07-19T12:00:00Z"

appA, appB :: ApplicationId
appA = ApplicationId "app-a"
appB = ApplicationId "app-b"

empty :: Manifest
empty = emptyManifest fixedTime

withFile :: FilePath -> FileRecord -> Manifest -> Manifest
withFile path fileRecord manifest =
  Manifest
    { version = manifest.version,
      genAt = manifest.genAt,
      modules = manifest.modules,
      vars = manifest.vars,
      files = Map.insert path fileRecord manifest.files,
      applications = manifest.applications,
      recipe = manifest.recipe,
      blueprint = manifest.blueprint
    }

record :: Text -> Maybe BaselineRef -> [ApplicationId] -> FileRecord
record content baseline owners' =
  FileRecord
    { hash = hashContent content,
      moduleName = "owner",
      strategy = Template,
      generatedAt = fixedTime,
      baseline = baseline,
      applicationIds = Set.fromList owners'
    }

owners :: FilePath -> [ApplicationId] -> Map.Map FilePath DesiredFileOwner
owners path ownerIds = Map.singleton path (DesiredFileOwner "owner" (Set.fromList ownerIds))

patch :: Text -> ModuleName -> Operation
patch content moduleName = PatchFileOp ".gitignore" (content <> "\n") AppendLineIfAbsent Template moduleName

cleanMerge :: Text -> Text -> Text -> MergeOutcome
cleanMerge _ _ generated = MergeClean generated

planWith ::
  Map.Map FilePath Text ->
  Map.Map FilePath Text ->
  Map.Map BaselineRef Text ->
  Manifest ->
  [ApplicationId] ->
  [Operation] ->
  Map.Map FilePath DesiredFileOwner ->
  (Text -> Text -> Text -> MergeOutcome) ->
  Either ReconciliationError ReconciliationPlan
planWith disk copySources baselines manifest selected operations ownerMap merge =
  runIdentity $
    planReconciliationWith
      (pure . (`Map.lookup` disk))
      (\path -> pure (maybe (Left (CopySourceUnavailable path)) Right (Map.lookup path copySources)))
      (\ref -> pure (maybe (Left (BaselineMissing ref)) Right (Map.lookup ref baselines)))
      (\base current generated -> pure (merge base current generated))
      manifest
      (Set.fromList selected)
      operations
      ownerMap

isInvalidPath :: Either ReconciliationError ReconciliationPlan -> Bool
isInvalidPath (Left (InvalidReconciliationPath _ _)) = True
isInvalidPath _ = False

isSafeDelete :: FileReconciliation -> Bool
isSafeDelete (FileDeleteSafe _ _ _) = True
isSafeDelete _ = False

isEditedOrphan :: FileReconciliation -> Bool
isEditedOrphan (FileOrphanEdited _ _ _ _ _) = True
isEditedOrphan _ = False

isSharedRelease :: FileReconciliation -> Bool
isSharedRelease (FileReleaseSharedOwnership _ _ _) = True
isSharedRelease _ = False
