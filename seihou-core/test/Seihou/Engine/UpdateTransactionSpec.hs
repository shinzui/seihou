module Seihou.Engine.UpdateTransactionSpec (tests) where

import Control.Exception (throwIO)
import Control.Monad (unless, when)
import Data.ByteString.Lazy qualified as LBS
import Data.Foldable (traverse_)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Time (UTCTime, defaultTimeLocale, parseTimeOrError)
import Effectful (runEff)
import Seihou.Core.Types hiding (KeepCurrent)
import Seihou.Effect.BaselineStore (putBaseline)
import Seihou.Effect.BaselineStoreInterp (runBaselineStore)
import Seihou.Effect.FilesystemInterp (runFilesystem)
import Seihou.Engine.Reconcile
import Seihou.Engine.UpdateTransaction
import Seihou.Manifest.Hash (baselineRefForContent, hashContent)
import Seihou.Manifest.Types (emptyManifest, manifestToJSON)
import System.Directory (findExecutable)
import System.Directory qualified as Directory
import System.FilePath (takeDirectory, (</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Engine.UpdateTransaction" spec

spec :: Spec
spec = do
  describe "applyReconciliation" $ do
    it "writes resolved files and updates baselines, hashes, ownership, and orphans" $
      withSystemTempDirectory "seihou-update-transaction" $ \projectRoot -> do
        writeProject projectRoot "merged.txt" "user\n"
        writeProject projectRoot "safe.txt" "safe\n"
        writeProject projectRoot "edited.txt" "user orphan\n"
        writeProject projectRoot "shared.txt" "shared\n"
        let oldMerged = fileRecord "base\n" (Just (baselineRefForContent "base\n")) [appA]
            oldSafe = fileRecord "safe\n" Nothing [appA]
            oldEdited = fileRecord "before\n" Nothing [appA]
            oldShared = fileRecord "shared\n" Nothing [appA, appB]
            manifest =
              manifestWithFiles
                ( Map.fromList
                    [ ("merged.txt", oldMerged),
                      ("safe.txt", oldSafe),
                      ("edited.txt", oldEdited),
                      ("shared.txt", oldShared)
                    ]
                )
            desired = desiredFile "merged.txt" "generated\n" [appA]
            mergedState = plannedState "generated\n" "user and generated\n" True
            plan =
              ReconciliationPlan
                { applicationIds = Set.singleton appA,
                  files =
                    Map.fromList
                      [ ("merged.txt", FileAutoMerge desired mergedState (observed "user\n") (Just oldMerged)),
                        ("safe.txt", FileDeleteSafe "safe.txt" oldSafe (observed "safe\n")),
                        ( "edited.txt",
                          FileOrphanEdited
                            "edited.txt"
                            oldEdited
                            "user orphan\n"
                            (observed "user orphan\n")
                            (Just RetainTrackedOrphan)
                        ),
                        ("shared.txt", FileReleaseSharedOwnership "shared.txt" oldShared (observed "shared\n"))
                      ],
                  requiredDirectories = Set.empty
                }
        transaction <- expectRight =<< beginUpdateTransaction projectRoot (Map.keysSet plan.files)
        candidate <- expectRight =<< applyReconciliation transaction plan manifest

        readProject projectRoot "merged.txt" `shouldReturn` "user and generated\n"
        Directory.doesFileExist (projectRoot </> "safe.txt") `shouldReturn` False
        readProject projectRoot "edited.txt" `shouldReturn` "user orphan\n"
        readProject projectRoot "shared.txt" `shouldReturn` "shared\n"

        let mergedRecord = candidate.files Map.! "merged.txt"
            baseline = baselineRefForContent "generated\n"
        mergedRecord.hash `shouldBe` hashContent "user and generated\n"
        mergedRecord.baseline `shouldBe` Just baseline
        mergedRecord.applicationIds `shouldBe` Set.singleton appA
        Map.member "safe.txt" candidate.files `shouldBe` False
        candidate.files Map.! "edited.txt" `shouldBe` oldEdited
        (candidate.files Map.! "shared.txt").applicationIds `shouldBe` Set.singleton appB
        readProject projectRoot (".seihou/baselines" </> refName baseline) `shouldReturn` "generated\n"

        Directory.doesDirectoryExist transaction.transactionDirectory `shouldReturn` True
        completeUpdateTransaction transaction `shouldReturn` Right ()
        Directory.doesDirectoryExist transaction.transactionDirectory `shouldReturn` False

    it "advances the baseline but preserves disk and applied hash for KeepCurrent" $
      withSystemTempDirectory "seihou-update-keep-current" $ \projectRoot -> do
        writeProject projectRoot "file.txt" "user\n"
        let oldRecord = fileRecord "base\n" (Just (baselineRefForContent "base\n")) [appA]
            desired = desiredFile "file.txt" "generated\n" [appA]
            unresolved =
              FileConflict
                desired
                "user\n"
                "markers\n"
                OverlappingEdits
                (observed "user\n")
                (Just oldRecord)
                Nothing
            initialPlan = ReconciliationPlan (Set.singleton appA) (Map.singleton "file.txt" unresolved) Set.empty
            manifest = manifestWithFiles (Map.singleton "file.txt" oldRecord)
        resolvedPlan <- expectRight (resolveFileConflict "file.txt" KeepCurrent initialPlan)
        transaction <- expectRight =<< beginUpdateTransaction projectRoot (Set.singleton "file.txt")
        candidate <- expectRight =<< applyReconciliation transaction resolvedPlan manifest
        readProject projectRoot "file.txt" `shouldReturn` "user\n"
        let resultRecord = candidate.files Map.! "file.txt"
        resultRecord.hash `shouldBe` hashContent "user\n"
        resultRecord.baseline `shouldBe` Just (baselineRefForContent "generated\n")
        completeUpdateTransaction transaction `shouldReturn` Right ()

    it "rejects a stale plan before its first mutation" $
      withSystemTempDirectory "seihou-update-stale" $ \projectRoot -> do
        writeProject projectRoot "file.txt" "planned\n"
        let desired = desiredFile "file.txt" "new\n" [appA]
            plan =
              ReconciliationPlan
                (Set.singleton appA)
                (Map.singleton "file.txt" (FileUpdate desired (plannedState "new\n" "new\n" True) (observed "old\n") Nothing))
                Set.empty
        transaction <- expectRight =<< beginUpdateTransaction projectRoot (Set.singleton "file.txt")
        result <- applyReconciliation transaction plan (manifestWithFiles Map.empty)
        result `shouldSatisfy` isStale
        readProject projectRoot "file.txt" `shouldReturn` "planned\n"
        Directory.doesDirectoryExist transaction.transactionDirectory `shouldReturn` False

    it "deletes or detaches edited orphans only after explicit resolution" $
      withSystemTempDirectory "seihou-update-orphan-resolution" $ \projectRoot -> do
        writeProject projectRoot "delete.txt" "user delete\n"
        writeProject projectRoot "detach.txt" "user detach\n"
        let deleteRecord = fileRecord "old delete\n" Nothing [appA]
            detachRecord = fileRecord "old detach\n" Nothing [appA]
            plan =
              ReconciliationPlan
                (Set.singleton appA)
                ( Map.fromList
                    [ ( "delete.txt",
                        FileOrphanEdited
                          "delete.txt"
                          deleteRecord
                          "user delete\n"
                          (observed "user delete\n")
                          (Just DeleteEditedOrphan)
                      ),
                      ( "detach.txt",
                        FileOrphanEdited
                          "detach.txt"
                          detachRecord
                          "user detach\n"
                          (observed "user detach\n")
                          (Just DetachAndKeepOrphan)
                      )
                    ]
                )
                Set.empty
            manifest = manifestWithFiles (Map.fromList [("delete.txt", deleteRecord), ("detach.txt", detachRecord)])
        transaction <- expectRight =<< beginUpdateTransaction projectRoot (Map.keysSet plan.files)
        candidate <- expectRight =<< applyReconciliation transaction plan manifest
        Directory.doesFileExist (projectRoot </> "delete.txt") `shouldReturn` False
        readProject projectRoot "detach.txt" `shouldReturn` "user detach\n"
        candidate.files `shouldBe` Map.empty
        completeUpdateTransaction transaction `shouldReturn` Right ()

    it "refuses unresolved plans without touching disk" $
      withSystemTempDirectory "seihou-update-unresolved" $ \projectRoot -> do
        writeProject projectRoot "file.txt" "user\n"
        let desired = desiredFile "file.txt" "generated\n" [appA]
            conflict =
              FileConflict desired "user\n" "markers\n" OverlappingEdits (observed "user\n") Nothing Nothing
            plan = ReconciliationPlan (Set.singleton appA) (Map.singleton "file.txt" conflict) Set.empty
        transaction <- expectRight =<< beginUpdateTransaction projectRoot (Set.singleton "file.txt")
        result <- applyReconciliation transaction plan (manifestWithFiles Map.empty)
        result `shouldSatisfy` isUnresolved
        readProject projectRoot "file.txt" `shouldReturn` "user\n"
        Directory.doesDirectoryExist transaction.transactionDirectory `shouldReturn` False

  describe "rollback and recovery" $ do
    it "rolls every earlier mutation back after an injected failure" $
      withSystemTempDirectory "seihou-update-rollback" $ \projectRoot -> do
        writeProject projectRoot "one.txt" "old one\n"
        writeProject projectRoot "two.txt" "old two\n"
        let one = desiredFile "one.txt" "new one\n" [appA]
            two = desiredFile "two.txt" "new two\n" [appA]
            plan =
              ReconciliationPlan
                (Set.singleton appA)
                ( Map.fromList
                    [ ("one.txt", FileUpdate one (plannedState "new one\n" "new one\n" True) (observed "old one\n") Nothing),
                      ("two.txt", FileUpdate two (plannedState "new two\n" "new two\n" True) (observed "old two\n") Nothing)
                    ]
                )
                Set.empty
        transaction <- expectRight =<< beginUpdateTransaction projectRoot (Map.keysSet plan.files)
        result <-
          applyReconciliationWithHook
            (\count -> when (count == 1) (throwIO (userError "injected failure")))
            transaction
            plan
            (manifestWithFiles Map.empty)
        result `shouldSatisfy` isApplyFailure
        readProject projectRoot "one.txt" `shouldReturn` "old one\n"
        readProject projectRoot "two.txt" `shouldReturn` "old two\n"
        Directory.doesDirectoryExist transaction.transactionDirectory `shouldReturn` False

    it "restores a well-formed leftover journal on startup" $
      withSystemTempDirectory "seihou-update-recover" $ \projectRoot -> do
        writeProject projectRoot "file.txt" "old\n"
        transaction <- expectRight =<< beginUpdateTransaction projectRoot (Set.singleton "file.txt")
        writeProject projectRoot "file.txt" "interrupted\n"
        recoverIncompleteTransactions projectRoot `shouldReturn` [Right ()]
        readProject projectRoot "file.txt" `shouldReturn` "old\n"
        Directory.doesDirectoryExist transaction.transactionDirectory `shouldReturn` False

    it "recovers an applied but unpublished candidate and removes its new empty directories" $
      withSystemTempDirectory "seihou-update-unpublished" $ \projectRoot -> do
        writeProject projectRoot "file.txt" "old\n"
        let desired = desiredFile "file.txt" "new\n" [appA]
            plan =
              ReconciliationPlan
                (Set.singleton appA)
                (Map.singleton "file.txt" (FileUpdate desired (plannedState "new\n" "new\n" True) (observed "old\n") Nothing))
                (Set.singleton "empty/generated")
        transaction <- expectRight =<< beginUpdateTransaction projectRoot (Set.singleton "file.txt")
        _candidate <- expectRight =<< applyReconciliation transaction plan (manifestWithFiles Map.empty)
        readProject projectRoot "file.txt" `shouldReturn` "new\n"
        Directory.doesDirectoryExist (projectRoot </> "empty" </> "generated") `shouldReturn` True
        recoverIncompleteTransactions projectRoot `shouldReturn` [Right ()]
        readProject projectRoot "file.txt" `shouldReturn` "old\n"
        Directory.doesDirectoryExist (projectRoot </> "empty") `shouldReturn` False
        Directory.doesDirectoryExist transaction.transactionDirectory `shouldReturn` False

    it "keeps committed files when the durable manifest matches the journal" $
      withSystemTempDirectory "seihou-update-committed" $ \projectRoot -> do
        writeProject projectRoot "file.txt" "old\n"
        let desired = desiredFile "file.txt" "new\n" [appA]
            plan =
              ReconciliationPlan
                (Set.singleton appA)
                (Map.singleton "file.txt" (FileUpdate desired (plannedState "new\n" "new\n" True) (observed "old\n") Nothing))
                Set.empty
        transaction <- expectRight =<< beginUpdateTransaction projectRoot (Set.singleton "file.txt")
        candidate <- expectRight =<< applyReconciliation transaction plan (manifestWithFiles Map.empty)
        Directory.createDirectoryIfMissing True (projectRoot </> ".seihou")
        LBS.writeFile (projectRoot </> ".seihou" </> "manifest.json") (manifestToJSON candidate)
        recoverIncompleteTransactions projectRoot `shouldReturn` [Right ()]
        readProject projectRoot "file.txt" `shouldReturn` "new\n"
        Directory.doesDirectoryExist transaction.transactionDirectory `shouldReturn` False

    it "uses an orchestrator's complete final manifest as the recovery commit marker" $
      withSystemTempDirectory "seihou-update-final-marker" $ \projectRoot -> do
        writeProject projectRoot "file.txt" "old\n"
        let desired = desiredFile "file.txt" "new\n" [appA]
            plan =
              ReconciliationPlan
                (Set.singleton appA)
                (Map.singleton "file.txt" (FileUpdate desired (plannedState "new\n" "new\n" True) (observed "old\n") Nothing))
                Set.empty
        transaction <- expectRight =<< beginUpdateTransaction projectRoot (Set.singleton "file.txt")
        candidate <- expectRight =<< applyReconciliation transaction plan (manifestWithFiles Map.empty)
        let finalManifest :: Manifest
            finalManifest =
              Manifest
                { version = candidate.version,
                  genAt = candidate.genAt,
                  modules = candidate.modules,
                  vars = Map.singleton "published" "yes",
                  files = candidate.files,
                  applications = candidate.applications,
                  recipe = candidate.recipe,
                  blueprint = candidate.blueprint,
                  blueprintMigrations = candidate.blueprintMigrations
                }
        setUpdateTransactionExpectedManifest transaction finalManifest `shouldReturn` Right ()
        Directory.createDirectoryIfMissing True (projectRoot </> ".seihou")
        LBS.writeFile (projectRoot </> ".seihou" </> "manifest.json") (manifestToJSON finalManifest)
        recoverIncompleteTransactions projectRoot `shouldReturn` [Right ()]
        readProject projectRoot "file.txt" `shouldReturn` "new\n"
        Directory.doesDirectoryExist transaction.transactionDirectory `shouldReturn` False

    it "quarantines malformed journal metadata instead of deleting it" $
      withSystemTempDirectory "seihou-update-malformed" $ \projectRoot -> do
        let transactionDirectory = projectRoot </> ".seihou" </> "transactions" </> "broken"
            quarantineDirectory = projectRoot </> ".seihou" </> "transactions-quarantine" </> "broken"
        Directory.createDirectoryIfMissing True transactionDirectory
        TIO.writeFile (transactionDirectory </> "journal.json") "{ not json"
        results <- recoverIncompleteTransactions projectRoot
        results `shouldSatisfy` singleMalformed
        Directory.doesDirectoryExist transactionDirectory `shouldReturn` False
        Directory.doesDirectoryExist quarantineDirectory `shouldReturn` True

  describe "path validation" $ do
    it "rejects traversal, absolute, Git, and Seihou targets" $
      withSystemTempDirectory "seihou-update-validation" $ \projectRoot -> do
        traversal <- beginUpdateTransaction projectRoot (Set.singleton "../escape")
        absolute <- beginUpdateTransaction projectRoot (Set.singleton (projectRoot </> "escape"))
        gitPath <- beginUpdateTransaction projectRoot (Set.singleton ".git/config")
        windowsGitPath <- beginUpdateTransaction projectRoot (Set.singleton ".git\\config")
        seihouPath <- beginUpdateTransaction projectRoot (Set.singleton ".seihou/manifest.json")
        traverse_ (`shouldSatisfy` isInvalid) [traversal, absolute, gitPath, windowsGitPath, seihouPath]

  describe "disposable project fixture" $ do
    it "merges user and generated edits, deletes a safe orphan, and retains an edited orphan" $
      withGit $
        withSystemTempDirectory "seihou-update-fixture" $ \projectRoot -> do
          let baseline = "title\nshared\nfooter\n"
              current = "title\nuser\nshared\nfooter\n"
              generated = "title\nshared\nmodule\nfooter\n"
              baselineDirectory = projectRoot </> ".seihou" </> "baselines"
          writeProject projectRoot "merged.txt" current
          writeProject projectRoot "safe.txt" "safe\n"
          writeProject projectRoot "edited.txt" "user orphan\n"
          baselineRef <- runEff $ runFilesystem $ runBaselineStore baselineDirectory (putBaseline baseline)
          let mergedRecord = fileRecord baseline (Just baselineRef) [appA]
              safeRecord = fileRecord "safe\n" Nothing [appA]
              editedRecord = fileRecord "old orphan\n" Nothing [appA]
              manifest =
                manifestWithFiles
                  ( Map.fromList
                      [ ("merged.txt", mergedRecord),
                        ("safe.txt", safeRecord),
                        ("edited.txt", editedRecord)
                      ]
                  )
              operations = [WriteFileOp "merged.txt" generated Template]
              ownerMap = Map.singleton "merged.txt" (DesiredFileOwner "owner" (Set.singleton appA))
          planned <-
            runEff $
              runFilesystem $
                runBaselineStore baselineDirectory $
                  planReconciliation projectRoot manifest (Set.singleton appA) operations ownerMap
          initialPlan <- expectRight planned
          resolvedPlan <- expectRight (resolveEditedOrphan "edited.txt" RetainTrackedOrphan initialPlan)
          reconciliationSummary resolvedPlan `shouldBe` ReconciliationSummary 0 0 1 0 0 1 1 0

          transaction <- expectRight =<< beginUpdateTransaction projectRoot (reconciliationMutationPaths resolvedPlan)
          candidate <- expectRight =<< applyReconciliation transaction resolvedPlan manifest
          completeUpdateTransaction transaction `shouldReturn` Right ()

          merged <- readProject projectRoot "merged.txt"
          merged `shouldSatisfy` T.isInfixOf "user"
          merged `shouldSatisfy` T.isInfixOf "module"
          Directory.doesFileExist (projectRoot </> "safe.txt") `shouldReturn` False
          readProject projectRoot "edited.txt" `shouldReturn` "user orphan\n"
          Map.member "safe.txt" candidate.files `shouldBe` False
          Map.member "edited.txt" candidate.files `shouldBe` True
          Directory.listDirectory (projectRoot </> ".seihou" </> "transactions") `shouldReturn` []

fixedTime :: UTCTime
fixedTime = parseTimeOrError True defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ" "2026-07-19T12:00:00Z"

appA, appB :: ApplicationId
appA = ApplicationId "app-a"
appB = ApplicationId "app-b"

manifestWithFiles :: Map.Map FilePath FileRecord -> Manifest
manifestWithFiles fileRecords =
  let manifest = emptyManifest fixedTime
   in Manifest
        { version = manifest.version,
          genAt = manifest.genAt,
          modules = manifest.modules,
          vars = manifest.vars,
          files = fileRecords,
          applications = manifest.applications,
          recipe = manifest.recipe,
          blueprint = manifest.blueprint,
          blueprintMigrations = manifest.blueprintMigrations
        }

fileRecord :: Text -> Maybe BaselineRef -> [ApplicationId] -> FileRecord
fileRecord content baseline owners =
  FileRecord
    { hash = hashContent content,
      moduleName = "owner",
      strategy = Template,
      generatedAt = fixedTime,
      baseline = baseline,
      applicationIds = Set.fromList owners
    }

desiredFile :: FilePath -> Text -> [ApplicationId] -> DesiredFile
desiredFile path content owners =
  DesiredFile
    { path = path,
      generatedContent = content,
      moduleName = "owner",
      strategy = Template,
      applicationIds = Set.fromList owners
    }

plannedState :: Text -> Text -> Bool -> PlannedFileState
plannedState baseline applied shouldWrite =
  PlannedFileState
    { generatedBaseline = baseline,
      appliedContent = applied,
      recordedHash = hashContent applied,
      writeToDisk = shouldWrite
    }

observed :: Text -> ObservedFile
observed content = ObservedFile True (Just (hashContent content))

writeProject :: FilePath -> FilePath -> Text -> IO ()
writeProject projectRoot relativePath content = do
  Directory.createDirectoryIfMissing True (projectRoot </> takeDirectory relativePath)
  TIO.writeFile (projectRoot </> relativePath) content

readProject :: FilePath -> FilePath -> IO Text
readProject projectRoot relativePath = TIO.readFile (projectRoot </> relativePath)

refName :: BaselineRef -> FilePath
refName reference = T.unpack reference.unBaselineRef.unSHA256

expectRight :: (Show error) => Either error value -> IO value
expectRight (Right value) = pure value
expectRight (Left err) = expectationFailure (show err) >> fail (show err)

isStale :: Either TransactionError Manifest -> Bool
isStale (Left (TransactionStalePlan _ _ _)) = True
isStale _ = False

isApplyFailure :: Either TransactionError Manifest -> Bool
isApplyFailure (Left (TransactionApplyFailed _ _)) = True
isApplyFailure _ = False

isUnresolved :: Either TransactionError Manifest -> Bool
isUnresolved (Left (TransactionUnresolvedPaths paths)) = paths == Set.singleton "file.txt"
isUnresolved _ = False

singleMalformed :: [Either TransactionError ()] -> Bool
singleMalformed [Left (TransactionJournalMalformed _ _)] = True
singleMalformed _ = False

isInvalid :: Either TransactionError UpdateTransaction -> Bool
isInvalid (Left (InvalidTransactionPath _ _)) = True
isInvalid _ = False

withGit :: Expectation -> Expectation
withGit action = do
  available <- maybe False (const True) <$> findExecutable "git"
  unless available (pendingWith "git is not available")
  action
