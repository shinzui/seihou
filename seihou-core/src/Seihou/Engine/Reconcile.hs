module Seihou.Engine.Reconcile
  ( DesiredFileOwner (..),
    DesiredFile (..),
    ReconciliationReason (..),
    ObservedFile (..),
    PlannedFileState (..),
    ResolvedFileConflict (..),
    FileReconciliation (..),
    ReconciliationPlan (..),
    ReconciliationError (..),
    FileConflictChoice (..),
    OrphanChoice (..),
    ReconciliationSummary (..),
    planReconciliation,
    planReconciliationWith,
    resolveFileConflict,
    resolveEditedOrphan,
    reconciliationSummary,
    reconciliationMutationPaths,
    unresolvedPaths,
  )
where

import Control.Monad (foldM)
import Data.Foldable (traverse_)
import Data.List (foldl')
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as T
import Seihou.Core.Path (validateProjectRelativePath)
import Seihou.Core.Types hiding (KeepCurrent)
import Seihou.Effect.BaselineStore (BaselineError, BaselineStore, readBaseline)
import Seihou.Effect.Filesystem (Filesystem, doesFileExist, readFileText)
import Seihou.Engine.Section (applyTextPatch)
import Seihou.Engine.ThreeWayMerge (MergeOutcome (..), threeWayMerge)
import Seihou.Manifest.Hash (hashContent)
import Seihou.Prelude
import System.FilePath (takeDirectory)

-- | Ownership supplied by the update orchestrator for one desired path.
-- The application set is path-specific: a batch may update several
-- applications without every application contributing to every path.
data DesiredFileOwner = DesiredFileOwner
  { moduleName :: ModuleName,
    applicationIds :: Set ApplicationId
  }
  deriving stock (Eq, Show)

-- | The final generated side after all operations for a path are replayed.
data DesiredFile = DesiredFile
  { path :: FilePath,
    generatedContent :: Text,
    moduleName :: ModuleName,
    strategy :: Strategy,
    applicationIds :: Set ApplicationId
  }
  deriving stock (Eq, Show)

data ReconciliationReason
  = MissingTrustedBaseline
  | CurrentFileMissing
  | MergeDriverUnavailable Text
  | OverlappingEdits
  deriving stock (Eq, Show)

-- | The disk snapshot used while planning. Applying verifies every snapshot
-- before the first mutation, so a resolution cannot overwrite later edits.
data ObservedFile = ObservedFile
  { existed :: Bool,
    contentHash :: Maybe SHA256
  }
  deriving stock (Eq, Show)

-- | The exact generated ancestor and applied bytes a resolved action will
-- publish. @writeToDisk@ is false for paths already containing those bytes.
-- @recordedHash@ may intentionally remain the prior applied hash for a
-- user-only edit that generation did not change.
data PlannedFileState = PlannedFileState
  { generatedBaseline :: Text,
    appliedContent :: Text,
    recordedHash :: SHA256,
    writeToDisk :: Bool
  }
  deriving stock (Eq, Show)

data ResolvedFileConflict = ResolvedFileConflict
  { choice :: FileConflictChoice,
    state :: PlannedFileState
  }
  deriving stock (Eq, Show)

data FileReconciliation
  = FileCreate DesiredFile PlannedFileState ObservedFile
  | FileUpdate DesiredFile PlannedFileState ObservedFile (Maybe FileRecord)
  | FileAutoMerge DesiredFile PlannedFileState ObservedFile (Maybe FileRecord)
  | FileUnchanged DesiredFile PlannedFileState ObservedFile (Maybe FileRecord)
  | FileConflict
      DesiredFile
      Text
      Text
      ReconciliationReason
      ObservedFile
      (Maybe FileRecord)
      (Maybe ResolvedFileConflict)
  | FileDeleteSafe FilePath FileRecord ObservedFile
  | FileOrphanEdited FilePath FileRecord Text ObservedFile (Maybe OrphanChoice)
  | FileReleaseSharedOwnership FilePath FileRecord ObservedFile
  | FileAlreadyAbsent FilePath FileRecord ObservedFile
  deriving stock (Eq, Show)

data ReconciliationPlan = ReconciliationPlan
  { applicationIds :: Set ApplicationId,
    files :: Map FilePath FileReconciliation,
    requiredDirectories :: Set FilePath
  }
  deriving stock (Eq, Show)

data ReconciliationError
  = InvalidReconciliationPath FilePath Text
  | MissingDesiredOwner FilePath
  | DesiredOwnerOutsideSelection FilePath (Set ApplicationId)
  | SharedPathRequiresApplications FilePath (Set ApplicationId)
  | CopySourceUnavailable FilePath
  | PatchMaterializationFailed FilePath PatchOp ModuleName Text
  | ReconciliationPathNotFound FilePath
  | NotAFileConflict FilePath
  | NotAnEditedOrphan FilePath
  | UpdateAborted FilePath
  deriving stock (Eq, Show)

data FileConflictChoice
  = AcceptGenerated
  | KeepCurrent
  | WriteConflictMarkers
  | AbortUpdate
  deriving stock (Eq, Show)

data OrphanChoice
  = DeleteEditedOrphan
  | RetainTrackedOrphan
  | DetachAndKeepOrphan
  | AbortOrphanUpdate
  deriving stock (Eq, Show)

data ReconciliationSummary = ReconciliationSummary
  { creates :: Int,
    updates :: Int,
    merged :: Int,
    unchanged :: Int,
    conflicts :: Int,
    safeDeletes :: Int,
    editedOrphans :: Int,
    sharedOwnership :: Int
  }
  deriving stock (Eq, Show)

-- | Production planner using the repository filesystem and baseline effects,
-- with EP-65's Git-backed merge driver for dual edits.
planReconciliation ::
  (Filesystem :> es, BaselineStore :> es, IOE :> es) =>
  FilePath ->
  Manifest ->
  Set ApplicationId ->
  [Operation] ->
  Map FilePath DesiredFileOwner ->
  Eff es (Either ReconciliationError ReconciliationPlan)
planReconciliation projectRoot manifest selected operations ownerMap =
  planReconciliationWith
    readProjectFile
    readCopySource
    readBaseline
    (\base current generated -> liftIO (threeWayMerge base current generated))
    manifest
    selected
    operations
    ownerMap
  where
    readProjectFile relativePath = do
      let fullPath = projectRoot </> relativePath
      exists <- doesFileExist fullPath
      if exists then Just <$> readFileText fullPath else pure Nothing
    readCopySource sourcePath = do
      exists <- doesFileExist sourcePath
      if exists
        then Right <$> readFileText sourcePath
        else pure (Left (CopySourceUnavailable sourcePath))

-- | Backend-parametric planner. Tests use maps for disk, copy-source, and
-- baseline reads while production supplies effects. The function is read-only.
planReconciliationWith ::
  (Monad m) =>
  (FilePath -> m (Maybe Text)) ->
  (FilePath -> m (Either ReconciliationError Text)) ->
  (BaselineRef -> m (Either BaselineError Text)) ->
  (Text -> Text -> Text -> m MergeOutcome) ->
  Manifest ->
  Set ApplicationId ->
  [Operation] ->
  Map FilePath DesiredFileOwner ->
  m (Either ReconciliationError ReconciliationPlan)
planReconciliationWith readDisk readCopy readStoredBaseline mergeContents manifest selected operations ownerMap =
  case validateInputs selected operations ownerMap manifest of
    Left err -> pure (Left err)
    Right (grouped, directories) -> do
      desiredResult <-
        traverse
          (materializeOne readDisk readCopy readStoredBaseline ownerMap manifest)
          grouped
      case sequence desiredResult of
        Left err -> pure (Left err)
        Right desiredContexts -> do
          classified <- traverse (classifyDesired mergeContents) desiredContexts
          orphaned <- classifyOrphans readDisk manifest selected (Map.keysSet grouped)
          pure $ do
            desiredFilesWithPaths <- sequence classified
            orphanFiles <- orphaned
            let desiredFiles = Map.map snd desiredFilesWithPaths
                allFiles = Map.union desiredFiles orphanFiles
                parentDirectories =
                  Set.fromList
                    [ parent
                    | path <- Map.keys grouped,
                      let parent = takeDirectory path,
                      parent /= "."
                    ]
            Right
              ReconciliationPlan
                { applicationIds = selected,
                  files = allFiles,
                  requiredDirectories = Set.union directories parentDirectories
                }

data DesiredContext = DesiredContext
  { desired :: DesiredFile,
    current :: Maybe Text,
    baseline :: Maybe Text,
    priorRecord :: Maybe FileRecord,
    observed :: ObservedFile,
    missingTrustedBaseline :: Bool
  }

validateInputs ::
  Set ApplicationId ->
  [Operation] ->
  Map FilePath DesiredFileOwner ->
  Manifest ->
  Either ReconciliationError (Map FilePath [Operation], Set FilePath)
validateInputs selected operations ownerMap manifest = do
  let grouped = groupFileOperations operations
      directories = Set.fromList [path | CreateDirOp path <- operations]
  traverse_ validateManagedPath (Map.keys grouped)
  traverse_ validateManagedPath (Set.toList directories)
  traverse_ (validateOwner selected ownerMap manifest) (Map.keys grouped)
  pure (grouped, directories)

validateOwner ::
  Set ApplicationId ->
  Map FilePath DesiredFileOwner ->
  Manifest ->
  FilePath ->
  Either ReconciliationError ()
validateOwner selected ownerMap manifest path = case Map.lookup path ownerMap of
  Nothing -> Left (MissingDesiredOwner path)
  Just owner
    | not (owner.applicationIds `Set.isSubsetOf` selected) ->
        Left (DesiredOwnerOutsideSelection path (owner.applicationIds Set.\\ selected))
    | otherwise -> case Map.lookup path manifest.files of
        Nothing -> Right ()
        Just record ->
          let unselectedOwners = record.applicationIds Set.\\ selected
           in if Set.null unselectedOwners
                then Right ()
                else Left (SharedPathRequiresApplications path record.applicationIds)

validateManagedPath :: FilePath -> Either ReconciliationError ()
validateManagedPath rawPath = case validateProjectRelativePath (T.pack rawPath) of
  Left err -> Left (InvalidReconciliationPath rawPath err)
  Right safePath
    | safePath /= rawPath ->
        Left (InvalidReconciliationPath rawPath "path must not contain surrounding whitespace")
    | safePath == "." ->
        Left (InvalidReconciliationPath rawPath "path must name a project file or directory")
    | targetsControlPath safePath ->
        Left (InvalidReconciliationPath rawPath "path targets Seihou or Git control data")
    | otherwise -> Right ()

targetsControlPath :: FilePath -> Bool
targetsControlPath path = case pathSegments path of
  firstSegment : _ -> firstSegment == ".seihou" || firstSegment == ".git"
  [] -> False

pathSegments :: FilePath -> [Text]
pathSegments = filter (not . T.null) . T.split (\character -> character == '/' || character == '\\') . T.pack

groupFileOperations :: [Operation] -> Map FilePath [Operation]
groupFileOperations = foldl' addOperation Map.empty
  where
    addOperation grouped operation = case operationDestination operation of
      Nothing -> grouped
      Just path -> Map.insertWith (flip (++)) path [operation] grouped

operationDestination :: Operation -> Maybe FilePath
operationDestination (WriteFileOp path _ _) = Just path
operationDestination (CopyFileOp _ path) = Just path
operationDestination (PatchFileOp path _ _ _ _) = Just path
operationDestination _ = Nothing

materializeOne ::
  (Monad m) =>
  (FilePath -> m (Maybe Text)) ->
  (FilePath -> m (Either ReconciliationError Text)) ->
  (BaselineRef -> m (Either BaselineError Text)) ->
  Map FilePath DesiredFileOwner ->
  Manifest ->
  [Operation] ->
  m (Either ReconciliationError DesiredContext)
materializeOne readDisk readCopy readStoredBaseline ownerMap manifest pathOperations = do
  let path = operationPath pathOperations
      prior = Map.lookup path manifest.files
      owner = ownerMap Map.! path
      containsReplacement = any isReplacement pathOperations
  current <- readDisk path
  trust <- case prior of
    Nothing ->
      pure
        ( Trusted
            (if containsReplacement then "" else maybe "" id current)
            False
        )
    Just record -> trustedBaseline readStoredBaseline record current
  let initial = case trust of
        Trusted content _ -> content
        Untrusted
          | prior == Nothing && not containsReplacement -> maybe "" id current
          | otherwise -> ""
  generatedResult <-
    foldM
      ( \result operation -> case result of
          Left err -> pure (Left err)
          Right existing -> applyGenerationOperation readCopy path existing operation
      )
      (Right initial)
      pathOperations
  pure $ do
    generated <- generatedResult
    let (trusted, missing, _synthetic) = case trust of
          Trusted content synthetic -> (Just content, False, synthetic)
          Untrusted -> (Nothing, prior /= Nothing, False)
        finalStrategy = operationStrategy (last pathOperations)
        desired =
          DesiredFile
            { path = path,
              generatedContent = generated,
              moduleName = owner.moduleName,
              strategy = finalStrategy,
              applicationIds = owner.applicationIds
            }
    Right
      DesiredContext
        { desired = desired,
          current = current,
          baseline = trusted,
          priorRecord = prior,
          observed = observe current,
          missingTrustedBaseline = missing
        }
  where
    operationPath (operation : _) = case operationDestination operation of
      Just path -> path
      Nothing -> error "materializeOne received a non-file operation"
    operationPath [] = error "materializeOne received an empty operation group"

data BaselineTrust = Trusted Text Bool | Untrusted

trustedBaseline ::
  (Monad m) =>
  (BaselineRef -> m (Either BaselineError Text)) ->
  FileRecord ->
  Maybe Text ->
  m BaselineTrust
trustedBaseline readStored record current = case record.baseline of
  Just ref -> do
    result <- readStored ref
    pure (either (const Untrusted) (\content -> Trusted content False) result)
  Nothing ->
    pure $ case current of
      Just content | hashContent content == record.hash -> Trusted content True
      _ -> Untrusted

applyGenerationOperation ::
  (Monad m) =>
  (FilePath -> m (Either ReconciliationError Text)) ->
  FilePath ->
  Text ->
  Operation ->
  m (Either ReconciliationError Text)
applyGenerationOperation _ _ _ (WriteFileOp _ content _) = pure (Right content)
applyGenerationOperation readCopy _ _ (CopyFileOp source _) = readCopy source
applyGenerationOperation _ path existing (PatchFileOp _ content patch _strategy moduleName) =
  pure $
    first
      (PatchMaterializationFailed path patch moduleName)
      (applyTextPatch patch moduleName "#" existing content)
applyGenerationOperation _ _ existing _ = pure (Right existing)

isReplacement :: Operation -> Bool
isReplacement WriteFileOp {} = True
isReplacement CopyFileOp {} = True
isReplacement _ = False

operationStrategy :: Operation -> Strategy
operationStrategy (WriteFileOp _ _ strategy) = strategy
operationStrategy CopyFileOp {} = Copy
operationStrategy (PatchFileOp _ _ _ strategy _) = strategy
operationStrategy _ = Template

classifyDesired ::
  (Monad m) =>
  (Text -> Text -> Text -> m MergeOutcome) ->
  DesiredContext ->
  m (Either ReconciliationError (FilePath, FileReconciliation))
classifyDesired mergeContents context = case context.current of
  Nothing -> pure $ Right (path, classifyMissing)
  Just current
    | context.missingTrustedBaseline ->
        pure $ Right (path, unresolved current current MissingTrustedBaseline)
    | otherwise -> case context.baseline of
        Nothing -> pure $ Right (path, unresolved current current MissingTrustedBaseline)
        Just baseline -> classifyPresent baseline current
  where
    desired = context.desired
    path = desired.path
    generated = desired.generatedContent
    prior = context.priorRecord
    observed = context.observed

    classifyMissing = case prior of
      Nothing -> FileCreate desired (automaticState generated True) observed
      Just _ -> unresolved "" "" CurrentFileMissing

    classifyPresent baseline current
      | current == baseline && generated == baseline =
          pure (Right (path, FileUnchanged desired (unchangedState generated current) observed prior))
      | current == baseline =
          pure (Right (path, FileUpdate desired (automaticState generated True) observed prior))
      | generated == baseline =
          let priorHash = maybe (hashContent current) (.hash) prior
              state = PlannedFileState generated current priorHash False
           in pure (Right (path, FileUnchanged desired state observed prior))
      | current == generated =
          pure (Right (path, FileUnchanged desired (unchangedState generated current) observed prior))
      | otherwise = do
          outcome <- mergeContents baseline current generated
          pure $ Right (path, fromMerge current outcome)

    fromMerge _ (MergeClean merged) =
      FileAutoMerge
        desired
        (PlannedFileState generated merged (hashContent merged) (context.current /= Just merged))
        observed
        prior
    fromMerge current (MergeConflicted markers) = unresolved current markers OverlappingEdits
    fromMerge current (MergeUnavailable message) =
      unresolved current current (MergeDriverUnavailable message)

    unresolved current markers reason =
      FileConflict desired current markers reason observed prior Nothing

    automaticState content write = PlannedFileState content content (hashContent content) write
    unchangedState baseline current = PlannedFileState baseline current (hashContent current) False

classifyOrphans ::
  (Monad m) =>
  (FilePath -> m (Maybe Text)) ->
  Manifest ->
  Set ApplicationId ->
  Set FilePath ->
  m (Either ReconciliationError (Map FilePath FileReconciliation))
classifyOrphans readDisk manifest selected desiredPaths = do
  entries <- traverse classify candidates
  pure (Right (Map.fromList entries))
  where
    candidates =
      [ (path, record)
      | (path, record) <- Map.toList manifest.files,
        Set.null (Set.intersection selected record.applicationIds) == False,
        Set.notMember path desiredPaths
      ]
    classify (path, record) = do
      current <- readDisk path
      let observed = observe current
          remainingOwners = record.applicationIds Set.\\ selected
          action
            | not (Set.null remainingOwners) = FileReleaseSharedOwnership path record observed
            | otherwise = case current of
                Nothing -> FileAlreadyAbsent path record observed
                Just content
                  | hashContent content == record.hash -> FileDeleteSafe path record observed
                  | otherwise -> FileOrphanEdited path record content observed Nothing
      pure (path, action)

observe :: Maybe Text -> ObservedFile
observe current = ObservedFile (maybe False (const True) current) (hashContent <$> current)

resolveFileConflict ::
  FilePath ->
  FileConflictChoice ->
  ReconciliationPlan ->
  Either ReconciliationError ReconciliationPlan
resolveFileConflict path choice plan = case Map.lookup path plan.files of
  Nothing -> Left (ReconciliationPathNotFound path)
  Just (FileConflict _ _ _ _ _ _ _) | choice == AbortUpdate -> Left (UpdateAborted path)
  Just (FileConflict desired current markers reason observed prior _) ->
    let applied = case choice of
          AcceptGenerated -> desired.generatedContent
          KeepCurrent -> current
          WriteConflictMarkers -> markers
          AbortUpdate -> current
        state =
          PlannedFileState
            { generatedBaseline = desired.generatedContent,
              appliedContent = applied,
              recordedHash = hashContent applied,
              writeToDisk = applied /= current || not observed.existed
            }
        resolved = FileConflict desired current markers reason observed prior (Just (ResolvedFileConflict choice state))
     in Right (replacePlanFiles plan (Map.insert path resolved plan.files))
  Just _ -> Left (NotAFileConflict path)

resolveEditedOrphan ::
  FilePath ->
  OrphanChoice ->
  ReconciliationPlan ->
  Either ReconciliationError ReconciliationPlan
resolveEditedOrphan path choice plan = case Map.lookup path plan.files of
  Nothing -> Left (ReconciliationPathNotFound path)
  Just (FileOrphanEdited _ _ _ _ _) | choice == AbortOrphanUpdate -> Left (UpdateAborted path)
  Just (FileOrphanEdited orphanPath record content observed _) ->
    Right $
      replacePlanFiles
        plan
        ( Map.insert
            path
            (FileOrphanEdited orphanPath record content observed (Just choice))
            plan.files
        )
  Just _ -> Left (NotAnEditedOrphan path)

reconciliationSummary :: ReconciliationPlan -> ReconciliationSummary
reconciliationSummary = foldl' count emptySummary . Map.elems . (.files)
  where
    emptySummary = ReconciliationSummary 0 0 0 0 0 0 0 0
    count summary reconciliation = case reconciliation of
      FileCreate _ _ _ -> addCreate summary
      FileUpdate _ _ _ _ -> addUpdate summary
      FileAutoMerge _ _ _ _ -> addMerge summary
      FileUnchanged _ _ _ _ -> addUnchanged summary
      FileConflict _ _ _ _ _ _ Nothing -> addConflict summary
      FileConflict _ _ _ _ _ _ (Just resolved) -> case resolved.choice of
        AcceptGenerated -> addUpdate summary
        KeepCurrent -> addMerge summary
        WriteConflictMarkers -> addMerge summary
        AbortUpdate -> addConflict summary
      FileDeleteSafe _ _ _ -> addSafeDelete summary
      FileOrphanEdited _ _ _ _ _ -> addEditedOrphan summary
      FileReleaseSharedOwnership _ _ _ -> addSharedOwnership summary
      FileAlreadyAbsent _ _ _ -> addUnchanged summary

    addCreate (ReconciliationSummary a b c d e f g h) = ReconciliationSummary (a + 1) b c d e f g h
    addUpdate (ReconciliationSummary a b c d e f g h) = ReconciliationSummary a (b + 1) c d e f g h
    addMerge (ReconciliationSummary a b c d e f g h) = ReconciliationSummary a b (c + 1) d e f g h
    addUnchanged (ReconciliationSummary a b c d e f g h) = ReconciliationSummary a b c (d + 1) e f g h
    addConflict (ReconciliationSummary a b c d e f g h) = ReconciliationSummary a b c d (e + 1) f g h
    addSafeDelete (ReconciliationSummary a b c d e f g h) = ReconciliationSummary a b c d e (f + 1) g h
    addEditedOrphan (ReconciliationSummary a b c d e f g h) = ReconciliationSummary a b c d e f (g + 1) h
    addSharedOwnership (ReconciliationSummary a b c d e f g h) = ReconciliationSummary a b c d e f g (h + 1)

replacePlanFiles :: ReconciliationPlan -> Map FilePath FileReconciliation -> ReconciliationPlan
replacePlanFiles plan newFiles =
  ReconciliationPlan
    { applicationIds = plan.applicationIds,
      files = newFiles,
      requiredDirectories = plan.requiredDirectories
    }

reconciliationMutationPaths :: ReconciliationPlan -> Set FilePath
reconciliationMutationPaths = Map.keysSet . (.files)

unresolvedPaths :: ReconciliationPlan -> Set FilePath
unresolvedPaths plan = Map.keysSet (Map.filter unresolved plan.files)
  where
    unresolved (FileConflict _ _ _ _ _ _ Nothing) = True
    unresolved (FileOrphanEdited _ _ _ _ Nothing) = True
    unresolved _ = False
