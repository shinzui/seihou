module Seihou.Engine.Migrate
  ( -- * Engine types
    MigrationFileStatus (..),
    MigrationOpInstance (..),
    ExecutedMigrationPlan (..),
    MigrationExecError (..),

    -- * Engine entry points
    classifyMigration,
    executeMigration,
  )
where

import Data.List (nub, sortBy)
import Data.Map.Strict qualified as Map
import Data.Ord (Down (..))
import Data.Text qualified as T
import Data.Time (UTCTime)
import GHC.Generics (Generic)
import Seihou.Core.Migration
  ( Migration (..),
    MigrationOp (..),
    MigrationPlan (..),
  )
import Seihou.Core.Path (validateProjectRelativePath)
import Seihou.Core.Types
  ( AppliedModule (..),
    FileRecord (..),
    Manifest (..),
    ModuleName (..),
  )
import Seihou.Core.Version (renderVersion)
import Seihou.Effect.Filesystem
  ( Filesystem,
    createDirectoryIfMissing,
    doesFileExist,
    readFileText,
    removeDirectoryIfEmpty,
    removeDirectoryRecursive,
    removeFile,
    renamePath,
  )
import Seihou.Effect.Process (Process, runProcess)
import Seihou.Manifest.Hash (hashContent)
import Seihou.Prelude
import System.Exit (ExitCode (..))
import System.FilePath (takeDirectory)

-- ----------------------------------------------------------------------------
-- Types
-- ----------------------------------------------------------------------------

-- | Per-file safety classification, mirroring 'Seihou.Engine.Remove'.
--
--   * 'MFSafe'     — disk hash matches the manifest's recorded hash; safe
--     to move or delete without losing user edits.
--   * 'MFConflict' — disk hash differs from the manifest's recorded hash;
--     the user has modified the file since generation and the engine
--     refuses to clobber it unless the caller passes @force = True@.
--   * 'MFGone'     — file is absent on disk. The op is a no-op (target
--     of a delete already gone, source of a move already gone).
data MigrationFileStatus = MFSafe | MFConflict | MFGone
  deriving stock (Eq, Show, Generic)

-- | A 'MigrationOp' lifted to a concrete, classified instance ready to
-- execute or render. Move/delete *file* ops carry the file's status (so
-- the CLI can render conflicts up front); directory and command ops do
-- not — directories imply many files, and a command's effect is opaque.
data MigrationOpInstance
  = MoveFileInst FilePath FilePath MigrationFileStatus
  | MoveDirInst FilePath FilePath
  | DeleteFileInst FilePath MigrationFileStatus
  | DeleteDirInst FilePath
  | RunCommandInst Text (Maybe FilePath)
  deriving stock (Eq, Show, Generic)

-- | The complete plan that 'classifyMigration' returns: the planner's
-- 'MigrationPlan' it was built from, and the linearized list of
-- concrete op instances in execution order.
data ExecutedMigrationPlan = ExecutedMigrationPlan
  { planModule :: ModuleName,
    planSource :: MigrationPlan,
    planOps :: [MigrationOpInstance]
  }
  deriving stock (Eq, Show, Generic)

-- | Reasons the engine refuses to execute. 'MigrationConflict' carries
-- every disk path whose hash diverged from the manifest, so the CLI can
-- list them and tell the user what to inspect.
data MigrationExecError
  = MigrationConflict [FilePath]
  | MigrationCommandFailed Text Int
  | MigrationUnsafePath Text FilePath Text
  deriving stock (Eq, Show, Generic)

-- ----------------------------------------------------------------------------
-- classifyMigration
-- ----------------------------------------------------------------------------

-- | Walk a 'MigrationPlan' and produce a fully classified
-- 'ExecutedMigrationPlan'. The classification reads files from the
-- filesystem (for hash comparisons against the manifest) but does not
-- modify anything.
classifyMigration ::
  (Filesystem :> es) =>
  Manifest ->
  MigrationPlan ->
  Eff es (Either MigrationExecError ExecutedMigrationPlan)
classifyMigration manifest plan = do
  opsResult <- traverse (classifyOp manifest) (concatMap (.ops) plan.planSteps)
  pure $ do
    ops <- sequence opsResult
    Right
      ExecutedMigrationPlan
        { planModule = ModuleName plan.planModule,
          planSource = plan,
          planOps = ops
        }

-- | Classify a single 'MigrationOp' against the manifest and disk.
classifyOp ::
  (Filesystem :> es) =>
  Manifest ->
  MigrationOp ->
  Eff es (Either MigrationExecError MigrationOpInstance)
classifyOp manifest op = case op of
  MoveFile {src, dest} ->
    case (validateMigrationPath "move-file source" src, validateMigrationPath "move-file destination" dest) of
      (Left err, _) -> pure (Left err)
      (_, Left err) -> pure (Left err)
      (Right safeSrc, Right safeDest) -> do
        status <- classifyFile manifest safeSrc
        pure (Right (MoveFileInst safeSrc safeDest status))
  MoveDir {src, dest} ->
    pure $
      case (validateMigrationPath "move-dir source" src, validateMigrationPath "move-dir destination" dest) of
        (Left err, _) -> Left err
        (_, Left err) -> Left err
        (Right safeSrc, Right safeDest) -> Right (MoveDirInst safeSrc safeDest)
  DeleteFile {path} ->
    case validateMigrationPath "delete-file path" path of
      Left err -> pure (Left err)
      Right safePath -> do
        status <- classifyFile manifest safePath
        pure (Right (DeleteFileInst safePath status))
  DeleteDir {path} ->
    pure $
      case validateMigrationPath "delete-dir path" path of
        Left err -> Left err
        Right safePath -> Right (DeleteDirInst safePath)
  RunCommand {run, workDir} ->
    pure $
      case traverse (validateMigrationPath "run-command workDir") workDir of
        Left err -> Left err
        Right safeWorkDir -> Right (RunCommandInst run safeWorkDir)

validateMigrationPath :: Text -> FilePath -> Either MigrationExecError FilePath
validateMigrationPath label path =
  case validateProjectRelativePath (T.pack path) of
    Left reason -> Left (MigrationUnsafePath label path reason)
    Right safePath -> Right safePath

-- | Compare the disk copy of a file to the manifest's recorded hash.
-- Returns 'MFGone' if the file is missing, 'MFSafe' if the manifest has
-- no record (the migration is targeting a file the engine isn't tracking
-- — treat as safe), 'MFSafe' if hashes match, 'MFConflict' otherwise.
classifyFile ::
  (Filesystem :> es) =>
  Manifest ->
  FilePath ->
  Eff es MigrationFileStatus
classifyFile manifest path = do
  exists <- doesFileExist path
  if not exists
    then pure MFGone
    else case Map.lookup path (manifest.files :: Map FilePath FileRecord) of
      Nothing -> pure MFSafe
      Just rec -> do
        content <- readFileText path
        let diskHash = hashContent content
        if diskHash == rec.hash
          then pure MFSafe
          else pure MFConflict

-- ----------------------------------------------------------------------------
-- executeMigration
-- ----------------------------------------------------------------------------

-- | Execute a previously classified plan. On a conflict that isn't
-- forced, returns 'Left (MigrationConflict ...)' without touching disk.
-- Otherwise runs every op in declaration order, rewrites the manifest's
-- @files@ map to reflect new paths, bumps @genAt@ to the supplied
-- timestamp, and updates the named 'AppliedModule''s @moduleVersion@ to
-- @planTo@ (the user's supplied target). When the source plan has an
-- empty 'planSteps' list, no file ops run but the manifest still
-- advances to @planTo@ — this is the "pure version bump" path.
executeMigration ::
  (Filesystem :> es, Process :> es) =>
  -- | If 'True', proceed even when files are 'MFConflict'. Mirrors the
  -- @--force@ flag on @seihou remove@.
  Bool ->
  ExecutedMigrationPlan ->
  Manifest ->
  -- | New @genAt@ timestamp to stamp on the rewritten manifest.
  UTCTime ->
  Eff es (Either MigrationExecError Manifest)
executeMigration force plan manifest now = do
  let conflicts =
        [ p
        | inst <- plan.planOps,
          (p, MFConflict) <- toFileStatus inst
        ]
  if not force && not (null conflicts)
    then pure (Left (MigrationConflict conflicts))
    else do
      result <- runOps plan.planOps manifest []
      case result of
        Left err -> pure (Left err)
        Right (man', removedDirs) -> do
          cleanupEmptyDirs removedDirs
          let bumped =
                man'
                  { genAt = now,
                    modules = map (bumpVersion plan.planModule plan.planSource) man'.modules
                  }
          pure (Right bumped)

-- | Pull (path, status) pairs out of an op for conflict detection. Only
-- file-targeted ops (MoveFile, DeleteFile) contribute; directory ops are
-- not classified per-file at this layer.
toFileStatus :: MigrationOpInstance -> [(FilePath, MigrationFileStatus)]
toFileStatus (MoveFileInst p _ s) = [(p, s)]
toFileStatus (DeleteFileInst p s) = [(p, s)]
toFileStatus _ = []

-- | Apply each op in order. Returns the updated manifest and the list
-- of paths whose parent directories may now be empty (so the caller can
-- prune them, mirroring 'Seihou.Engine.Remove').
runOps ::
  (Filesystem :> es, Process :> es) =>
  [MigrationOpInstance] ->
  Manifest ->
  -- | Accumulated removed paths (reverse order; reversed by caller as needed)
  [FilePath] ->
  Eff es (Either MigrationExecError (Manifest, [FilePath]))
runOps [] manifest acc = pure (Right (manifest, acc))
runOps (op : rest) manifest acc = case op of
  -- For move/delete, re-check disk existence at execute time. The
  -- classified status is computed before any chain ops run, so a
  -- previous step in the chain may have created or removed files
  -- since then. The classified status is still authoritative for the
  -- up-front conflict check (we never silently overwrite a
  -- user-edited file without --force), but the disk action itself
  -- must be defensive.
  MoveFileInst src dest _status -> do
    exists <- doesFileExist src
    if exists
      then do
        ensureParentDir dest
        renamePath src dest
        runOps rest (renameInManifest src dest manifest) (src : acc)
      else runOps rest (renameInManifest src dest manifest) acc
  MoveDirInst src dest -> do
    ensureParentDir dest
    renamePath src dest
    runOps rest (renameDirInManifest src dest manifest) (src : acc)
  DeleteFileInst p _status -> do
    exists <- doesFileExist p
    if exists
      then do
        removeFile p
        runOps rest (dropFromManifest p manifest) (p : acc)
      else runOps rest (dropFromManifest p manifest) acc
  DeleteDirInst p -> do
    removeDirectoryRecursive p
    runOps rest (dropDirFromManifest p manifest) (p : acc)
  RunCommandInst run mWorkDir -> do
    (code, _stdout, stderr) <- runProcess "/bin/sh" ["-c", run] mWorkDir
    case code of
      ExitSuccess -> runOps rest manifest acc
      ExitFailure n ->
        let msg = if T.null stderr then run else stderr
         in pure (Left (MigrationCommandFailed msg n))

-- ----------------------------------------------------------------------------
-- Manifest rewrites
-- ----------------------------------------------------------------------------

-- | Rewrite a single key from @src@ to @dest@ in the manifest's @files@
-- map. If the key isn't present, the manifest is returned unchanged.
renameInManifest :: FilePath -> FilePath -> Manifest -> Manifest
renameInManifest src dest manifest =
  case Map.lookup src manifest.files of
    Nothing -> manifest
    Just rec ->
      manifest
        { files = Map.insert dest rec (Map.delete src manifest.files)
        }

-- | Rewrite every @files@ key whose path is @src@ or under @src/@ to
-- replace the prefix with @dest@.
renameDirInManifest :: FilePath -> FilePath -> Manifest -> Manifest
renameDirInManifest src dest manifest =
  let prefix = src <> "/"
      rewriteKey k
        | k == src = dest
        | prefix `isPrefixOfPath` k = dest <> "/" <> drop (length prefix) k
        | otherwise = k
   in manifest {files = Map.mapKeys rewriteKey manifest.files}

-- | Drop a single file entry from the manifest.
dropFromManifest :: FilePath -> Manifest -> Manifest
dropFromManifest p manifest =
  manifest {files = Map.delete p manifest.files}

-- | Drop every file entry whose path is @path@ or under @path/@.
dropDirFromManifest :: FilePath -> Manifest -> Manifest
dropDirFromManifest path manifest =
  let prefix = path <> "/"
      keep k = k /= path && not (prefix `isPrefixOfPath` k)
   in manifest {files = Map.filterWithKey (\k _ -> keep k) manifest.files}

-- | Update the named applied module's @moduleVersion@ to the plan's
-- target. Other applied modules are untouched.
bumpVersion :: ModuleName -> MigrationPlan -> AppliedModule -> AppliedModule
bumpVersion modName plan am
  | am.name == modName =
      am {moduleVersion = Just (renderVersion plan.planTo)}
  | otherwise = am

-- ----------------------------------------------------------------------------
-- Helpers (shared with Engine.Remove patterns)
-- ----------------------------------------------------------------------------

-- | Try to remove now-empty parent directories of the given paths.
cleanupEmptyDirs :: (Filesystem :> es) => [FilePath] -> Eff es ()
cleanupEmptyDirs paths = do
  let parentDirs = nub $ concatMap allParents paths
      sorted = sortBy (\a b -> compare (Down (length a)) (Down (length b))) parentDirs
  mapM_ removeDirectoryIfEmpty sorted

allParents :: FilePath -> [FilePath]
allParents p = go (takeDirectory p)
  where
    go "." = []
    go "" = []
    go "/" = []
    go d = d : go (takeDirectory d)

-- | Ensure the parent directory of a destination path exists. Used
-- before 'renamePath' so callers don't have to author moves that
-- happen to land where the engine has already created an intermediate
-- directory. Skips the call when the parent is the project root
-- itself (@.@) — 'createDirectoryIfMissing' on @.@ is a no-op anyway.
ensureParentDir :: (Filesystem :> es) => FilePath -> Eff es ()
ensureParentDir dest =
  let parent = takeDirectory dest
   in case parent of
        "" -> pure ()
        "." -> pure ()
        d -> createDirectoryIfMissing True d

-- | Local copy of the prefix predicate used in 'Seihou.Effect.FilesystemPure'.
isPrefixOfPath :: String -> String -> Bool
isPrefixOfPath [] _ = True
isPrefixOfPath _ [] = False
isPrefixOfPath (x : xs) (y : ys) = x == y && isPrefixOfPath xs ys
