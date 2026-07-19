module Seihou.CLI.Update.Recovery
  ( prepareServiceBackups,
    setServiceExpectedManifest,
    restoreServiceBackups,
    recoverServiceBackups,
  )
where

import Control.Exception (SomeException, displayException, try)
import Control.Monad (forM, forM_, unless, when)
import Data.Aeson (FromJSON (..), ToJSON (..), (.:), (.:?), (.=))
import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy qualified as LBS
import Data.List (isPrefixOf, sortOn)
import Data.Maybe (catMaybes, isJust)
import Data.Ord (Down (..))
import Data.Set qualified as Set
import Data.Text qualified as T
import Seihou.CLI.Update.Types
import Seihou.Core.Path (validateProjectRelativePath)
import Seihou.Core.Types
import Seihou.Engine.Migrate (ExecutedMigrationPlan (..), MigrationOpInstance (..))
import Seihou.Engine.UpdateTransaction (UpdateTransaction (..))
import Seihou.Manifest.Types (manifestFromJSON)
import Seihou.Prelude
import System.Directory qualified as Directory
import System.FilePath (splitDirectories, takeDirectory, takeFileName)

data BackupScope = ProjectDirectory | InstalledArtifact
  deriving stock (Eq, Show)

data ServiceBackup = ServiceBackup
  { scope :: BackupScope,
    target :: FilePath,
    backupName :: Maybe FilePath
  }
  deriving stock (Eq, Show)

data ServiceJournal = ServiceJournal
  { version :: Int,
    installedRoot :: FilePath,
    entries :: [ServiceBackup],
    expectedManifest :: Maybe Manifest
  }
  deriving stock (Eq, Show)

instance ToJSON BackupScope where
  toJSON ProjectDirectory = Aeson.String "project-directory"
  toJSON InstalledArtifact = Aeson.String "installed-artifact"

instance FromJSON BackupScope where
  parseJSON = Aeson.withText "BackupScope" $ \case
    "project-directory" -> pure ProjectDirectory
    "installed-artifact" -> pure InstalledArtifact
    other -> fail ("unknown backup scope: " <> T.unpack other)

instance ToJSON ServiceBackup where
  toJSON entry =
    Aeson.object
      [ "scope" .= entry.scope,
        "target" .= entry.target,
        "backup" .= entry.backupName
      ]

instance FromJSON ServiceBackup where
  parseJSON = Aeson.withObject "ServiceBackup" $ \object ->
    ServiceBackup <$> object .: "scope" <*> object .: "target" <*> object .:? "backup"

instance ToJSON ServiceJournal where
  toJSON journal =
    Aeson.object
      [ "version" .= journal.version,
        "installedRoot" .= journal.installedRoot,
        "entries" .= journal.entries,
        "expectedManifest" .= journal.expectedManifest
      ]

instance FromJSON ServiceJournal where
  parseJSON = Aeson.withObject "ServiceJournal" $ \object -> do
    version <- object .: "version"
    unless (version == (1 :: Int)) (fail "unsupported service journal version")
    ServiceJournal
      <$> pure version
      <*> object .: "installedRoot"
      <*> object .: "entries"
      <*> object .:? "expectedManifest"

-- | Persist byte-for-byte backups for whole migration directories and shared
-- cache destinations inside EP-66's transaction directory. The companion
-- recovery pass runs before EP-66 recovery and uses the same manifest commit
-- boundary.
prepareServiceBackups ::
  UpdateTransaction ->
  FilePath ->
  [PlannedUpdateMigration] ->
  [CandidateArtifact] ->
  IO (Either UpdateError ())
prepareServiceBackups transaction installedRoot migrations artifacts = do
  let projectDirectories = normalizeDirectories (concatMap migrationDirectories migrations)
      installedNames =
        Set.toAscList . Set.fromList $
          [ T.unpack artifact.name
          | artifact <- artifacts,
            isJust artifact.sourceUrl
          ]
      requests =
        map (ProjectDirectory,) projectDirectories
          <> map (InstalledArtifact,) installedNames
      backupRoot = transaction.transactionDirectory </> "service-backups"
  result <- try @SomeException $ do
    Directory.createDirectoryIfMissing True backupRoot
    entries <- forM (zip [0 :: Int ..] requests) $ \(index, (scope, target)) -> do
      fullTarget <- resolveTarget transaction.projectRoot installedRoot scope target
      exists <- Directory.doesDirectoryExist fullTarget
      if exists
        then do
          let backupName = show index
              backupPath = backupRoot </> backupName
          copyDirectoryBytes fullTarget backupPath
          pure ServiceBackup {scope, target, backupName = Just backupName}
        else pure ServiceBackup {scope, target, backupName = Nothing}
    writeServiceJournal
      transaction.transactionDirectory
      ServiceJournal
        { version = 1,
          installedRoot,
          entries,
          expectedManifest = Nothing
        }
  pure $ first (UpdateCachePublicationFailed . T.pack . displayException) result

setServiceExpectedManifest :: UpdateTransaction -> Manifest -> IO (Either UpdateError ())
setServiceExpectedManifest transaction expected = do
  current <- readServiceJournal transaction.transactionDirectory
  case current of
    Left err -> pure (Left err)
    Right Nothing -> pure (Right ())
    Right (Just journal) -> do
      result <-
        try @SomeException $
          writeServiceJournal
            transaction.transactionDirectory
            journal {expectedManifest = Just expected}
      pure $ first (UpdateManifestWriteFailed . T.pack . displayException) result

restoreServiceBackups :: UpdateTransaction -> IO (Either UpdateError ())
restoreServiceBackups transaction = do
  current <- readServiceJournal transaction.transactionDirectory
  case current of
    Left err -> pure (Left err)
    Right Nothing -> pure (Right ())
    Right (Just journal) -> restoreJournal transaction.projectRoot transaction.transactionDirectory journal

-- | Restore or accept every service journal before the core transaction
-- recovery pass. A durable matching manifest means cache/directory publication
-- committed; every other state restores the byte backups.
recoverServiceBackups :: FilePath -> IO [Either UpdateError ()]
recoverServiceBackups projectRoot = do
  let transactionsRoot = projectRoot </> ".seihou" </> "transactions"
  exists <- Directory.doesDirectoryExist transactionsRoot
  if not exists
    then pure []
    else do
      names <- Directory.listDirectory transactionsRoot
      fmap catMaybes . forM names $ \name -> do
        let transactionDirectory = transactionsRoot </> name
        isDirectory <- Directory.doesDirectoryExist transactionDirectory
        if not isDirectory
          then pure Nothing
          else do
            current <- readServiceJournal transactionDirectory
            case current of
              Left err -> pure (Just (Left err))
              Right Nothing -> pure Nothing
              Right (Just journal) -> do
                committed <- manifestMatches projectRoot journal.expectedManifest
                if committed
                  then pure (Just (Right ()))
                  else Just <$> restoreJournal projectRoot transactionDirectory journal

restoreJournal :: FilePath -> FilePath -> ServiceJournal -> IO (Either UpdateError ())
restoreJournal projectRoot transactionDirectory journal = do
  result <- try @SomeException $
    forM_ (sortOn (Down . pathDepth . (.target)) journal.entries) $ \entry -> do
      fullTarget <- resolveTarget projectRoot journal.installedRoot entry.scope entry.target
      targetExists <- Directory.doesPathExist fullTarget
      when targetExists (Directory.removePathForcibly fullTarget)
      case entry.backupName of
        Nothing -> pure ()
        Just backupName -> do
          validateBackupName backupName
          copyDirectoryBytes (transactionDirectory </> "service-backups" </> backupName) fullTarget
  pure $ first (UpdateCachePublicationFailed . T.pack . displayException) result

resolveTarget :: FilePath -> FilePath -> BackupScope -> FilePath -> IO FilePath
resolveTarget projectRoot _ ProjectDirectory target =
  case validateProjectRelativePath (T.pack target) of
    Left reason -> ioError (userError ("unsafe project backup path: " <> T.unpack reason))
    Right safe
      | safe == "." || targetsControlPath safe -> ioError (userError "unsafe project backup target")
      | otherwise -> pure (projectRoot </> safe)
resolveTarget _ installedRoot InstalledArtifact target
  | takeFileName target == target && target /= "." && target /= ".." = pure (installedRoot </> target)
  | otherwise = ioError (userError "unsafe installed artifact backup target")

validateBackupName :: FilePath -> IO ()
validateBackupName name
  | takeFileName name == name && name /= "." && name /= ".." = pure ()
  | otherwise = ioError (userError "unsafe service backup name")

targetsControlPath :: FilePath -> Bool
targetsControlPath path = case splitDirectories path of
  first : _ -> first == ".seihou" || first == ".git"
  [] -> False

migrationDirectories :: PlannedUpdateMigration -> [FilePath]
migrationDirectories migration = concatMap directories migration.stagedPlan.planOps
  where
    directories (MoveDirInst source destination) = [source, destination]
    directories (DeleteDirInst path) = [path]
    directories _ = []

normalizeDirectories :: [FilePath] -> [FilePath]
normalizeDirectories paths = filter notCovered sorted
  where
    sorted = sortOn pathDepth (Set.toAscList (Set.fromList paths))
    notCovered path = not (any (isParentOf path) sorted)
    isParentOf child parent =
      parent /= child
        && splitDirectories parent `isPrefixOf` splitDirectories child

pathDepth :: FilePath -> Int
pathDepth = length . splitDirectories

copyDirectoryBytes :: FilePath -> FilePath -> IO ()
copyDirectoryBytes source destination = do
  Directory.createDirectoryIfMissing True destination
  names <- Directory.listDirectory source
  forM_ names $ \name -> do
    let sourcePath = source </> name
        destinationPath = destination </> name
    isDirectory <- Directory.doesDirectoryExist sourcePath
    if isDirectory
      then copyDirectoryBytes sourcePath destinationPath
      else Directory.copyFile sourcePath destinationPath

writeServiceJournal :: FilePath -> ServiceJournal -> IO ()
writeServiceJournal transactionDirectory journal = do
  let path = serviceJournalPath transactionDirectory
      temporaryPath = path <> ".tmp"
  LBS.writeFile temporaryPath (Aeson.encode journal)
  Directory.renamePath temporaryPath path

readServiceJournal :: FilePath -> IO (Either UpdateError (Maybe ServiceJournal))
readServiceJournal transactionDirectory = do
  let path = serviceJournalPath transactionDirectory
  exists <- Directory.doesFileExist path
  if not exists
    then pure (Right Nothing)
    else do
      result <- try @SomeException (LBS.readFile path)
      pure $ case result of
        Left err -> Left (UpdateCachePublicationFailed (T.pack (displayException err)))
        Right bytes -> first (UpdateCachePublicationFailed . T.pack) (Just <$> Aeson.eitherDecode bytes)

serviceJournalPath :: FilePath -> FilePath
serviceJournalPath transactionDirectory = transactionDirectory </> "service-journal.json"

manifestMatches :: FilePath -> Maybe Manifest -> IO Bool
manifestMatches _ Nothing = pure False
manifestMatches projectRoot (Just expected) = do
  let path = projectRoot </> ".seihou" </> "manifest.json"
  exists <- Directory.doesFileExist path
  if not exists
    then pure False
    else do
      bytes <- LBS.readFile path
      pure (manifestFromJSON bytes == Right expected)
