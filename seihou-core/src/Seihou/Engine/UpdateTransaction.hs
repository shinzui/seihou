module Seihou.Engine.UpdateTransaction
  ( UpdateTransaction (..),
    TransactionError (..),
    beginUpdateTransaction,
    applyReconciliation,
    applyReconciliationWithHook,
    rollbackUpdateTransaction,
    completeUpdateTransaction,
    recoverIncompleteTransactions,
  )
where

import Control.Exception (SomeException, bracketOnError, displayException, onException, try)
import Control.Monad (foldM, forM, forM_, unless, when)
import Data.Aeson (FromJSON (..), ToJSON (..), (.:), (.:?), (.=))
import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy qualified as LBS
import Data.Foldable (traverse_)
import Data.List (sortOn)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Time (UTCTime, getCurrentTime)
import Seihou.Core.Path (validateProjectRelativePath)
import Seihou.Core.Types
import Seihou.Effect.BaselineStore (putBaseline)
import Seihou.Effect.BaselineStoreInterp (runBaselineStore)
import Seihou.Effect.FilesystemInterp (runFilesystem)
import Seihou.Engine.Reconcile
import Seihou.Manifest.Hash (hashContent)
import Seihou.Manifest.Types (manifestFromJSON)
import Seihou.Prelude
import System.Directory qualified as Directory
import System.FilePath (splitDirectories, takeDirectory, takeFileName)
import System.IO (hClose, hSetEncoding, utf8)
import System.IO.Temp (createTempDirectory, openTempFile)

data UpdateTransaction = UpdateTransaction
  { projectRoot :: FilePath,
    transactionDirectory :: FilePath,
    targets :: Set FilePath
  }
  deriving stock (Eq, Show)

data TransactionError
  = InvalidTransactionPath FilePath Text
  | TransactionStartFailed Text
  | TransactionJournalMalformed FilePath Text
  | TransactionUnjournaledPaths (Set FilePath)
  | TransactionUnresolvedPaths (Set FilePath)
  | TransactionStalePlan FilePath ObservedFile ObservedFile
  | TransactionApplyFailed Text (Maybe Text)
  | TransactionRollbackFailed Text
  | TransactionCompletionFailed Text
  deriving stock (Eq, Show)

data JournalEntry = JournalEntry
  { targetPath :: FilePath,
    backupFile :: Maybe FilePath
  }
  deriving stock (Eq, Show)

data JournalMetadata = JournalMetadata
  { journalVersion :: Int,
    createdAt :: UTCTime,
    entries :: [JournalEntry],
    newDirectories :: [FilePath],
    expectedManifest :: Maybe Manifest
  }
  deriving stock (Eq, Show)

instance ToJSON JournalEntry where
  toJSON entry =
    Aeson.object
      [ "path" .= entry.targetPath,
        "backup" .= entry.backupFile
      ]

instance FromJSON JournalEntry where
  parseJSON = Aeson.withObject "JournalEntry" $ \object ->
    JournalEntry <$> object .: "path" <*> object .:? "backup"

instance ToJSON JournalMetadata where
  toJSON metadata =
    Aeson.object
      [ "version" .= metadata.journalVersion,
        "createdAt" .= metadata.createdAt,
        "entries" .= metadata.entries,
        "newDirectories" .= metadata.newDirectories,
        "expectedManifest" .= metadata.expectedManifest
      ]

instance FromJSON JournalMetadata where
  parseJSON = Aeson.withObject "JournalMetadata" $ \object -> do
    version <- object .: "version"
    unless (version == 1) (fail "unsupported transaction journal version")
    JournalMetadata
      <$> pure version
      <*> object .: "createdAt"
      <*> object .: "entries"
      <*> object .: "newDirectories"
      <*> object .:? "expectedManifest"

beginUpdateTransaction :: FilePath -> Set FilePath -> IO (Either TransactionError UpdateTransaction)
beginUpdateTransaction projectRoot targets = case traverse validateTransactionPath (Set.toAscList targets) of
  Left err -> pure (Left err)
  Right safeTargets -> do
    result <- try @SomeException $ do
      let transactionsRoot = projectRoot </> ".seihou" </> "transactions"
      Directory.createDirectoryIfMissing True transactionsRoot
      transactionDirectory <- createTempDirectory transactionsRoot "update-"
      let transaction = UpdateTransaction projectRoot transactionDirectory (Set.fromList safeTargets)
      initializeJournal transaction safeTargets `onException` cleanupDirectory transactionDirectory
      pure transaction
    pure $ first (TransactionStartFailed . exceptionText) result

initializeJournal :: UpdateTransaction -> [FilePath] -> IO ()
initializeJournal transaction safeTargets = do
  let backupDirectory = transaction.transactionDirectory </> "backups"
  Directory.createDirectoryIfMissing True backupDirectory
  entries <- forM (zip [0 :: Int ..] safeTargets) $ \(index, relativePath) -> do
    let fullPath = transaction.projectRoot </> relativePath
        backupName = show index <> ".txt"
        backupPath = backupDirectory </> backupName
    exists <- Directory.doesFileExist fullPath
    if exists
      then do
        TIO.readFile fullPath >>= TIO.writeFile backupPath
        pure (JournalEntry relativePath (Just backupName))
      else pure (JournalEntry relativePath Nothing)
  missingDirectories <- missingParentDirectories transaction.projectRoot safeTargets
  now <- getCurrentTime
  writeJournal
    transaction.transactionDirectory
    JournalMetadata
      { journalVersion = 1,
        createdAt = now,
        entries = entries,
        newDirectories = missingDirectories,
        expectedManifest = Nothing
      }

missingParentDirectories :: FilePath -> [FilePath] -> IO [FilePath]
missingParentDirectories projectRoot paths = do
  let candidates =
        Set.toAscList . Set.fromList . concatMap relativeParents $ paths
  missing <- filterMIO (fmap not . Directory.doesDirectoryExist . (projectRoot </>)) candidates
  pure (sortOn pathDepth missing)

relativeParents :: FilePath -> [FilePath]
relativeParents path =
  filter (/= ".") (takeWhile (/= ".") (iterate takeDirectory (takeDirectory path)))

applyReconciliation ::
  UpdateTransaction ->
  ReconciliationPlan ->
  Manifest ->
  IO (Either TransactionError Manifest)
applyReconciliation = applyReconciliationWithHook (const (pure ()))

-- | Hooked variant for deterministic failure-injection tests. The hook runs
-- after each successful disk write or deletion and receives a one-based count.
applyReconciliationWithHook ::
  (Int -> IO ()) ->
  UpdateTransaction ->
  ReconciliationPlan ->
  Manifest ->
  IO (Either TransactionError Manifest)
applyReconciliationWithHook afterMutation transaction plan manifest = do
  preflight <- transactionPreflight transaction plan
  case preflight of
    Left err -> failAndRollback transaction err
    Right () -> do
      prepared <- try @SomeException (prepareCandidateManifest transaction plan manifest)
      case prepared of
        Left err -> failAndRollback transaction (TransactionApplyFailed (exceptionText err) Nothing)
        Right candidate -> do
          journalResult <- updateJournalForPlan transaction plan candidate
          case journalResult of
            Left err -> failAndRollback transaction err
            Right () -> do
              mutationResult <- try @SomeException (applyMutations afterMutation transaction plan)
              case mutationResult of
                Left err ->
                  failAndRollback transaction (TransactionApplyFailed (exceptionText err) Nothing)
                Right () -> pure (Right candidate)

transactionPreflight :: UpdateTransaction -> ReconciliationPlan -> IO (Either TransactionError ())
transactionPreflight transaction plan = case traverse validateTransactionPath (Set.toAscList plan.requiredDirectories) of
  Left err -> pure (Left err)
  Right _
    | not (Set.null unjournaled) -> pure (Left (TransactionUnjournaledPaths unjournaled))
    | not (Set.null unresolved) -> pure (Left (TransactionUnresolvedPaths unresolved))
    | otherwise -> verifyObservedFiles transaction plan
  where
    unjournaled = Map.keysSet plan.files Set.\\ transaction.targets
    unresolved = unresolvedPaths plan

verifyObservedFiles :: UpdateTransaction -> ReconciliationPlan -> IO (Either TransactionError ())
verifyObservedFiles transaction plan = go (Map.toAscList plan.files)
  where
    go [] = pure (Right ())
    go ((path, reconciliation) : rest) = do
      current <- observeDiskFile (transaction.projectRoot </> path)
      let planned = reconciliationObservation reconciliation
      if current == planned
        then go rest
        else pure (Left (TransactionStalePlan path planned current))

reconciliationObservation :: FileReconciliation -> ObservedFile
reconciliationObservation reconciliation = case reconciliation of
  FileCreate _ _ observed -> observed
  FileUpdate _ _ observed _ -> observed
  FileAutoMerge _ _ observed _ -> observed
  FileUnchanged _ _ observed _ -> observed
  FileConflict _ _ _ _ observed _ _ -> observed
  FileDeleteSafe _ _ observed -> observed
  FileOrphanEdited _ _ _ observed _ -> observed
  FileReleaseSharedOwnership _ _ observed -> observed
  FileAlreadyAbsent _ _ observed -> observed

observeDiskFile :: FilePath -> IO ObservedFile
observeDiskFile path = do
  exists <- Directory.doesFileExist path
  if exists
    then do
      content <- TIO.readFile path
      pure (ObservedFile True (Just (hashContent content)))
    else pure (ObservedFile False Nothing)

prepareCandidateManifest :: UpdateTransaction -> ReconciliationPlan -> Manifest -> IO Manifest
prepareCandidateManifest transaction plan manifest = do
  nextFiles <- foldM applyManifestAction manifest.files (Map.toAscList plan.files)
  pure (replaceManifestFiles manifest nextFiles)
  where
    applyManifestAction files (path, reconciliation) = case desiredState reconciliation of
      Just (desired, state) -> do
        baseline <- writeBaselineBlob transaction.projectRoot state.generatedBaseline
        let record =
              FileRecord
                { hash = state.recordedHash,
                  moduleName = desired.moduleName,
                  strategy = desired.strategy,
                  generatedAt = manifest.genAt,
                  baseline = Just baseline,
                  applicationIds = desired.applicationIds
                }
        pure (Map.insert path record files)
      Nothing -> pure (applyOrphanManifestAction plan.applicationIds reconciliation files)

desiredState :: FileReconciliation -> Maybe (DesiredFile, PlannedFileState)
desiredState reconciliation = case reconciliation of
  FileCreate desired state _ -> Just (desired, state)
  FileUpdate desired state _ _ -> Just (desired, state)
  FileAutoMerge desired state _ _ -> Just (desired, state)
  FileUnchanged desired state _ _ -> Just (desired, state)
  FileConflict desired _ _ _ _ _ (Just resolution) -> Just (desired, resolution.state)
  _ -> Nothing

applyOrphanManifestAction ::
  Set ApplicationId ->
  FileReconciliation ->
  Map FilePath FileRecord ->
  Map FilePath FileRecord
applyOrphanManifestAction selected reconciliation files = case reconciliation of
  FileDeleteSafe path _ _ -> Map.delete path files
  FileAlreadyAbsent path _ _ -> Map.delete path files
  FileReleaseSharedOwnership path record _ ->
    let remaining = record.applicationIds Set.\\ selected
     in if Set.null remaining
          then Map.delete path files
          else Map.insert path (replaceRecordApplications record remaining) files
  FileOrphanEdited path _ _ _ (Just DeleteEditedOrphan) -> Map.delete path files
  FileOrphanEdited _ _ _ _ (Just RetainTrackedOrphan) -> files
  FileOrphanEdited path record _ _ (Just DetachAndKeepOrphan) ->
    let remaining = record.applicationIds Set.\\ selected
     in if Set.null remaining
          then Map.delete path files
          else Map.insert path (replaceRecordApplications record remaining) files
  _ -> files

replaceRecordApplications :: FileRecord -> Set ApplicationId -> FileRecord
replaceRecordApplications record owners =
  FileRecord
    { hash = record.hash,
      moduleName = record.moduleName,
      strategy = record.strategy,
      generatedAt = record.generatedAt,
      baseline = record.baseline,
      applicationIds = owners
    }

replaceManifestFiles :: Manifest -> Map FilePath FileRecord -> Manifest
replaceManifestFiles manifest nextFiles =
  Manifest
    { version = manifest.version,
      genAt = manifest.genAt,
      modules = manifest.modules,
      vars = manifest.vars,
      files = nextFiles,
      applications = manifest.applications,
      recipe = manifest.recipe,
      blueprint = manifest.blueprint
    }

writeBaselineBlob :: FilePath -> Text -> IO BaselineRef
writeBaselineBlob projectRoot content = do
  let baselineDirectory = projectRoot </> ".seihou" </> "baselines"
  runEff $ runFilesystem $ runBaselineStore baselineDirectory (putBaseline content)

updateJournalForPlan :: UpdateTransaction -> ReconciliationPlan -> Manifest -> IO (Either TransactionError ())
updateJournalForPlan transaction plan candidate = do
  metadataResult <- readJournal transaction.transactionDirectory
  case metadataResult of
    Left err -> pure (Left err)
    Right metadata -> do
      missingDirectories <-
        filterMIO
          (fmap not . Directory.doesDirectoryExist . (transaction.projectRoot </>))
          ( Set.toAscList . Set.fromList $
              concatMap
                (\path -> path : relativeParents path)
                (Set.toAscList plan.requiredDirectories)
          )
      let updated = setExpectedManifestAndDirectories metadata missingDirectories candidate
      result <- try @SomeException $ writeJournal transaction.transactionDirectory updated
      pure $ first (\err -> TransactionApplyFailed (exceptionText err) Nothing) result

setExpectedManifestAndDirectories :: JournalMetadata -> [FilePath] -> Manifest -> JournalMetadata
setExpectedManifestAndDirectories metadata additionalDirectories candidate =
  JournalMetadata
    { journalVersion = metadata.journalVersion,
      createdAt = metadata.createdAt,
      entries = metadata.entries,
      newDirectories =
        sortOn pathDepth . Set.toList $
          Set.fromList (metadata.newDirectories <> additionalDirectories),
      expectedManifest = Just candidate
    }

applyMutations :: (Int -> IO ()) -> UpdateTransaction -> ReconciliationPlan -> IO ()
applyMutations afterMutation transaction plan = do
  forM_ (Set.toAscList plan.requiredDirectories) $ \relativePath ->
    Directory.createDirectoryIfMissing True (transaction.projectRoot </> relativePath)
  _ <- foldM applyOne (0 :: Int) (Map.toAscList plan.files)
  pure ()
  where
    applyOne count (path, reconciliation) = case mutationFor reconciliation of
      NoMutation -> pure count
      WriteMutation content -> do
        atomicWriteText (transaction.projectRoot </> path) content
        let next = count + 1
        afterMutation next
        pure next
      DeleteMutation -> do
        let fullPath = transaction.projectRoot </> path
        exists <- Directory.doesFileExist fullPath
        when exists (Directory.removeFile fullPath)
        let next = count + 1
        afterMutation next
        pure next

data FileMutation = NoMutation | WriteMutation Text | DeleteMutation

mutationFor :: FileReconciliation -> FileMutation
mutationFor reconciliation = case desiredState reconciliation of
  Just (_, state)
    | state.writeToDisk -> WriteMutation state.appliedContent
    | otherwise -> NoMutation
  Nothing -> case reconciliation of
    FileDeleteSafe _ _ _ -> DeleteMutation
    FileOrphanEdited _ _ _ _ (Just DeleteEditedOrphan) -> DeleteMutation
    _ -> NoMutation

rollbackUpdateTransaction :: UpdateTransaction -> IO (Either TransactionError ())
rollbackUpdateTransaction transaction = do
  metadataResult <- readJournal transaction.transactionDirectory
  case metadataResult of
    Left err -> pure (Left err)
    Right metadata -> do
      result <- try @SomeException $ do
        forM_ metadata.entries (restoreEntry transaction)
        removeNewDirectories transaction.projectRoot metadata.newDirectories
        cleanupDirectory transaction.transactionDirectory
      pure $ first (TransactionRollbackFailed . exceptionText) result

restoreEntry :: UpdateTransaction -> JournalEntry -> IO ()
restoreEntry transaction entry = do
  let target = transaction.projectRoot </> entry.targetPath
  case entry.backupFile of
    Nothing -> do
      exists <- Directory.doesFileExist target
      when exists (Directory.removeFile target)
    Just backupName -> do
      let backupPath = transaction.transactionDirectory </> "backups" </> backupName
      content <- TIO.readFile backupPath
      atomicWriteText target content

removeNewDirectories :: FilePath -> [FilePath] -> IO ()
removeNewDirectories projectRoot = mapM_ removeIfEmpty . reverse . sortOn pathDepth
  where
    removeIfEmpty relativePath = do
      let fullPath = projectRoot </> relativePath
      exists <- Directory.doesDirectoryExist fullPath
      when exists $ do
        contents <- Directory.listDirectory fullPath
        when (null contents) (Directory.removeDirectory fullPath)

completeUpdateTransaction :: UpdateTransaction -> IO (Either TransactionError ())
completeUpdateTransaction transaction = do
  result <- try @SomeException (cleanupDirectory transaction.transactionDirectory)
  pure $ first (TransactionCompletionFailed . exceptionText) result

recoverIncompleteTransactions :: FilePath -> IO [Either TransactionError ()]
recoverIncompleteTransactions projectRoot = do
  let transactionsRoot = projectRoot </> ".seihou" </> "transactions"
  exists <- Directory.doesDirectoryExist transactionsRoot
  if not exists
    then pure []
    else do
      names <- Directory.listDirectory transactionsRoot
      directories <- filterMIO (Directory.doesDirectoryExist . (transactionsRoot </>)) names
      dated <- forM directories $ \name -> do
        modified <- Directory.getModificationTime (transactionsRoot </> name)
        pure (modified, name)
      forM (map snd (sortOn fst dated)) $ \name ->
        recoverOne projectRoot (transactionsRoot </> name)

recoverOne :: FilePath -> FilePath -> IO (Either TransactionError ())
recoverOne projectRoot transactionDirectory = do
  metadataResult <- readJournal transactionDirectory
  case metadataResult of
    Left err -> do
      quarantined <- quarantineTransaction projectRoot transactionDirectory
      pure $ case quarantined of
        Left quarantineError -> Left quarantineError
        Right () -> Left err
    Right metadata -> do
      committed <- manifestMatches projectRoot metadata.expectedManifest
      if committed
        then do
          result <- try @SomeException (cleanupDirectory transactionDirectory)
          pure $ first (TransactionCompletionFailed . exceptionText) result
        else
          rollbackUpdateTransaction
            UpdateTransaction
              { projectRoot = projectRoot,
                transactionDirectory = transactionDirectory,
                targets = Set.fromList (map (.targetPath) metadata.entries)
              }

manifestMatches :: FilePath -> Maybe Manifest -> IO Bool
manifestMatches _ Nothing = pure False
manifestMatches projectRoot (Just expected) = do
  let manifestPath = projectRoot </> ".seihou" </> "manifest.json"
  exists <- Directory.doesFileExist manifestPath
  if not exists
    then pure False
    else do
      bytes <- LBS.readFile manifestPath
      pure (manifestFromJSON bytes == Right expected)

quarantineTransaction :: FilePath -> FilePath -> IO (Either TransactionError ())
quarantineTransaction projectRoot transactionDirectory = do
  result <- try @SomeException $ do
    let quarantineRoot = projectRoot </> ".seihou" </> "transactions-quarantine"
        target = quarantineRoot </> takeFileName transactionDirectory
    Directory.createDirectoryIfMissing True quarantineRoot
    targetExists <- Directory.doesPathExist target
    when targetExists (ioError (userError ("quarantine target already exists: " <> target)))
    Directory.renamePath transactionDirectory target
  pure $ first (TransactionRollbackFailed . exceptionText) result

readJournal :: FilePath -> IO (Either TransactionError JournalMetadata)
readJournal transactionDirectory = do
  let path = journalPath transactionDirectory
  result <- try @SomeException (LBS.readFile path)
  pure $ case result of
    Left err -> Left (TransactionJournalMalformed path (exceptionText err))
    Right bytes -> case Aeson.eitherDecode bytes of
      Left err -> Left (TransactionJournalMalformed path (T.pack err))
      Right metadata -> first (TransactionJournalMalformed path) (validateJournal metadata)

validateJournal :: JournalMetadata -> Either Text JournalMetadata
validateJournal metadata = do
  traverse_ (validateJournalEntry . (.targetPath)) metadata.entries
  traverse_ validateBackupName [name | JournalEntry _ (Just name) <- metadata.entries]
  traverse_ (first renderTransactionPathError . validateTransactionPath) metadata.newDirectories
  pure metadata
  where
    validateJournalEntry path = first renderTransactionPathError (validateTransactionPath path)
    validateBackupName name
      | takeFileName name == name && name /= "." && name /= ".." = Right ()
      | otherwise = Left ("invalid backup filename: " <> T.pack name)

renderTransactionPathError :: TransactionError -> Text
renderTransactionPathError (InvalidTransactionPath path reason) = T.pack path <> ": " <> reason
renderTransactionPathError other = T.pack (show other)

writeJournal :: FilePath -> JournalMetadata -> IO ()
writeJournal transactionDirectory metadata = do
  let path = journalPath transactionDirectory
      tempPath = path <> ".tmp"
  LBS.writeFile tempPath (Aeson.encode metadata)
  Directory.renamePath tempPath path

journalPath :: FilePath -> FilePath
journalPath transactionDirectory = transactionDirectory </> "journal.json"

validateTransactionPath :: FilePath -> Either TransactionError FilePath
validateTransactionPath rawPath = case validateProjectRelativePath (T.pack rawPath) of
  Left err -> Left (InvalidTransactionPath rawPath err)
  Right safePath
    | safePath /= rawPath -> Left (InvalidTransactionPath rawPath "path must not contain surrounding whitespace")
    | safePath == "." -> Left (InvalidTransactionPath rawPath "path must name a project file")
    | targetsControlPath safePath ->
        Left (InvalidTransactionPath rawPath "path targets Seihou or Git control data")
    | otherwise -> Right safePath

targetsControlPath :: FilePath -> Bool
targetsControlPath path = case pathSegments path of
  firstSegment : _ -> firstSegment == ".seihou" || firstSegment == ".git"
  [] -> False

pathSegments :: FilePath -> [Text]
pathSegments = filter (not . T.null) . T.split (\character -> character == '/' || character == '\\') . T.pack

atomicWriteText :: FilePath -> Text -> IO ()
atomicWriteText path content = do
  let parent = takeDirectory path
  Directory.createDirectoryIfMissing True parent
  bracketOnError
    (openTempFile parent (takeFileName path <> ".seihou-update-"))
    (\(tempPath, handle) -> ignoreException (hClose handle) >> removeIfExists tempPath)
    ( \(tempPath, handle) -> do
        hSetEncoding handle utf8
        TIO.hPutStr handle content
        hClose handle
        Directory.renamePath tempPath path
    )

removeIfExists :: FilePath -> IO ()
removeIfExists path = do
  exists <- Directory.doesFileExist path
  when exists (Directory.removeFile path)

ignoreException :: IO () -> IO ()
ignoreException action = do
  _ <- try @SomeException action
  pure ()

cleanupDirectory :: FilePath -> IO ()
cleanupDirectory path = do
  exists <- Directory.doesDirectoryExist path
  when exists (Directory.removeDirectoryRecursive path)

failAndRollback :: UpdateTransaction -> TransactionError -> IO (Either TransactionError a)
failAndRollback transaction originalError = do
  rollback <- rollbackUpdateTransaction transaction
  pure $ case rollback of
    Right () -> Left originalError
    Left rollbackError ->
      Left
        ( TransactionApplyFailed
            (T.pack (show originalError))
            (Just (T.pack (show rollbackError)))
        )

filterMIO :: (a -> IO Bool) -> [a] -> IO [a]
filterMIO predicate values = fmap concat $ forM values $ \value -> do
  keep <- predicate value
  pure [value | keep]

pathDepth :: FilePath -> Int
pathDepth = length . splitDirectories

exceptionText :: SomeException -> Text
exceptionText = T.pack . displayException
