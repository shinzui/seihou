module Seihou.CLI.Migrate
  ( -- * Options
    MigrateOpts (..),

    -- * Handlers
    handleMigrate,
    runMigrate,
    MigrateError (..),
    MigrateResult (..),

    -- * Helpers for upgrade/status integration
    pendingChainFor,
  )
where

import Data.Aeson (ToJSON, object, (.=))
import Data.Aeson qualified as Aeson
import Data.Aeson.Encode.Pretty (encodePretty)
import Data.ByteString.Lazy.Char8 qualified as LBS
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Time.Clock (getCurrentTime)
import Effectful (runEff)
import GHC.Generics (Generic)
import Seihou.CLI.InstallShared
  ( OriginInfo (..),
    cloneRepo,
    installModuleDir,
    readOriginInfo,
  )
import Seihou.CLI.Style (bold, dim, green, red, useColor, yellow)
import Seihou.Core.Migration
  ( Migration (..),
    MigrationChain (..),
    MigrationOp (..),
    MigrationPlanError (..),
    planMigrationChain,
  )
import Seihou.Core.Registry
  ( Registry (..),
    RegistryEntry (..),
    RepoContents (..),
    discoverRepoContents,
  )
import Seihou.Core.Types
  ( AppliedModule (..),
    Manifest (..),
    Module (..),
    ModuleName (..),
  )
import Seihou.Core.Version (Version, parseVersion, renderVersion)
import Seihou.Dhall.Eval (evalModuleFromFile, evalRegistryFromFile)
import Seihou.Effect.FilesystemInterp (runFilesystem)
import Seihou.Effect.ManifestStore (readManifest, writeManifest)
import Seihou.Effect.ManifestStoreInterp (runManifestStore)
import Seihou.Effect.ProcessInterp (runProcessIO)
import Seihou.Engine.Migrate
  ( ExecutedMigrationPlan (..),
    MigrationExecError (..),
    MigrationFileStatus (..),
    MigrationOpInstance (..),
    classifyMigration,
    executeMigration,
  )
import Seihou.Prelude
import System.Directory (doesFileExist)
import System.Exit (exitFailure, exitSuccess)
import System.FilePath (takeFileName, (</>))
import System.IO.Temp (withSystemTempDirectory)

-- ----------------------------------------------------------------------------
-- Options
-- ----------------------------------------------------------------------------

-- | Options for @seihou migrate@: applies module-declared migrations to
-- the current project's working tree and manifest.
data MigrateOpts = MigrateOpts
  { migrateModule :: ModuleName,
    -- | Override the target version. Defaults to the installed
    -- module's current version (i.e. "migrate up to where the
    -- installed copy is now").
    migrateTo :: Maybe Text,
    migrateDryRun :: Bool,
    -- | Proceed even when the plan touches files the user has edited
    -- since they were generated. Mirrors @seihou remove --force@.
    migrateForce :: Bool,
    migrateJson :: Bool,
    migrateVerbose :: Bool,
    -- | Skip the default fetch-and-refresh step that clones the module's
    -- source repo and refreshes @~/.config/seihou/installed/<name>/@
    -- before planning the chain. When 'True', the command performs no
    -- network IO and uses only the locally installed copy as the source
    -- of truth. Default: 'False' (fetch is the new default after EP-2;
    -- before EP-2 the only behavior was local-only).
    migrateNoFetch :: Bool
  }
  deriving stock (Eq, Show, Generic)

-- ----------------------------------------------------------------------------
-- Errors and results
-- ----------------------------------------------------------------------------

-- | Reasons the @seihou migrate@ handler exits non-zero. Each variant
-- carries a human-readable message that the IO shell prints and uses
-- as its error message.
data MigrateError
  = MigrateNoManifest FilePath
  | MigrateModuleNotApplied ModuleName
  | MigrateNoRecordedVersion ModuleName
  | MigrateInstalledModuleEvalFailed FilePath Text
  | MigrateInstalledModuleHasNoVersion ModuleName FilePath
  | MigrateUnparseableInstalledVersion Text
  | MigrateUnparseableTargetVersion Text
  | MigrateUnparseableManifestVersion Text
  | MigratePlanFailed MigrationPlanError
  | MigrateExecFailed MigrationExecError
  deriving stock (Eq, Show, Generic)

-- | Outcome of a successful, non-dry-run @runMigrate@ call.
data MigrateResult
  = -- | Manifest was already at the target version; nothing to do.
    MigrateNoOp Version
  | -- | A plan was computed but not executed (dry-run).
    MigrateDryRunOK ExecutedMigrationPlan
  | -- | The plan was applied; the post-execution manifest is returned.
    MigrateApplied ExecutedMigrationPlan Manifest
  deriving stock (Eq, Show, Generic)

-- ----------------------------------------------------------------------------
-- IO shell
-- ----------------------------------------------------------------------------

-- | The IO entry point dispatched from @main@. Loads the manifest,
-- delegates planning + execution to 'runMigrate' (which handles the
-- fetch-and-refresh dance unless @--no-fetch@ was passed), and renders
-- the result.
handleMigrate :: MigrateOpts -> IO ()
handleMigrate opts = do
  let manifestPath = ".seihou" </> "manifest.json"
      modName = opts.migrateModule

  manifestRes <- runEff $ runFilesystem $ runManifestStore manifestPath readManifest
  manifest <- case manifestRes of
    Left err -> die (MigrateNoManifest (T.unpack err))
    Right Nothing -> die (MigrateNoManifest manifestPath)
    Right (Just m) -> pure m

  applied <- case findApplied manifest modName of
    Nothing -> die (MigrateModuleNotApplied modName)
    Just am -> pure am

  fromV <- case applied.moduleVersion >>= parseVersion of
    Just v -> pure v
    Nothing -> case applied.moduleVersion of
      Nothing -> die (MigrateNoRecordedVersion modName)
      Just t -> die (MigrateUnparseableManifestVersion t)

  result <- runMigrate opts manifest applied.source

  colorEnabled <- useColor
  case result of
    Left err -> die err
    Right (MigrateNoOp toV) -> do
      TIO.putStrLn $
        applyColor colorEnabled green "✓"
          <> " "
          <> modName.unModuleName
          <> " is already at version "
          <> renderVersion toV
          <> "; nothing to do."
      exitSuccess
    Right (MigrateDryRunOK plan) -> do
      if opts.migrateJson
        then LBS.putStr (encodePretty (planToJson plan))
        else do
          renderPlan colorEnabled plan
          TIO.putStrLn ""
          TIO.putStrLn $ applyColor colorEnabled dim "(dry run — no changes made)"
      exitSuccess
    Right (MigrateApplied plan manifest') -> do
      if opts.migrateJson
        then LBS.putStr (encodePretty (planToJson plan))
        else renderPlan colorEnabled plan
      runEff $
        runFilesystem $
          runManifestStore manifestPath $
            writeManifest manifest'
      let toV = plan.planChain.chainTo
      unless opts.migrateJson $ do
        TIO.putStrLn ""
        TIO.putStrLn $
          applyColor colorEnabled green "✓"
            <> " Migrated "
            <> applyColor colorEnabled bold modName.unModuleName
            <> " "
            <> renderVersion fromV
            <> " → "
            <> renderVersion toV
            <> "."

-- | The non-IO core of the handler. Useful as a building block for
-- other CLI surfaces (e.g. @seihou upgrade --with-migrations@) that
-- already have a manifest and an installed-module dir in hand.
--
-- Behavior depends on @opts.migrateNoFetch@:
--
--   * @True@ — operate purely on the supplied @installedDir@. This is
--     the legacy behavior used by @seihou upgrade --with-migrations@,
--     which has already refreshed the installed copy.
--   * @False@ (default) — read @<installedDir>\/.seihou-origin.json@,
--     clone the source repository shallowly, use the clone's module
--     dir as the source of truth for planning the chain, and on a
--     successful non-dry-run application refresh @installedDir@ from
--     the clone via 'installModuleDir'. Failures (missing origin file,
--     clone failure, module not present in remote) silently fall back
--     to the local-only path.
runMigrate ::
  -- | Options
  MigrateOpts ->
  -- | Manifest in memory (already loaded)
  Manifest ->
  -- | Installed-module directory, the path that holds @module.dhall@
  FilePath ->
  IO (Either MigrateError MigrateResult)
runMigrate opts manifest installedDir
  | opts.migrateNoFetch = runMigrateLocal opts manifest installedDir
  | otherwise = runMigrateWithFetch opts manifest installedDir

-- | Plan and (optionally) execute a migration chain using @sourceDir@
-- as the source of truth for the module's @module.dhall@ and migrations
-- list. Performs no network IO.
runMigrateLocal ::
  MigrateOpts ->
  Manifest ->
  -- | Directory holding the module's @module.dhall@ — either the
  -- locally installed copy or a freshly cloned moduleDir.
  FilePath ->
  IO (Either MigrateError MigrateResult)
runMigrateLocal opts manifest sourceDir = do
  let modName = opts.migrateModule
  case findApplied manifest modName of
    Nothing -> pure (Left (MigrateModuleNotApplied modName))
    Just applied -> case applied.moduleVersion of
      Nothing -> pure (Left (MigrateNoRecordedVersion modName))
      Just fromText ->
        case parseVersion fromText of
          Nothing -> pure (Left (MigrateUnparseableManifestVersion fromText))
          Just fromV -> do
            let sourceDhall = sourceDir </> "module.dhall"
            exists <- doesFileExist sourceDhall
            if not exists
              then
                pure
                  ( Left
                      ( MigrateInstalledModuleEvalFailed
                          sourceDhall
                          "module.dhall not found at installed dir"
                      )
                  )
              else do
                r <- evalModuleFromFile sourceDhall
                case r of
                  Left err ->
                    pure
                      ( Left
                          ( MigrateInstalledModuleEvalFailed
                              sourceDhall
                              (T.pack (show err))
                          )
                      )
                  Right sourceModule -> case resolveTarget opts sourceModule modName sourceDhall of
                    Left e -> pure (Left e)
                    Right toV ->
                      case planMigrationChain
                        modName.unModuleName
                        sourceModule.migrations
                        fromV
                        toV of
                        Left e -> pure (Left (MigratePlanFailed e))
                        Right Nothing -> pure (Right (MigrateNoOp toV))
                        Right (Just chain) -> do
                          plan <-
                            runEff $
                              runFilesystem $
                                classifyMigration manifest chain
                          if opts.migrateDryRun
                            then pure (Right (MigrateDryRunOK plan))
                            else do
                              now <- getCurrentTime
                              execRes <-
                                runEff $
                                  runFilesystem $
                                    runProcessIO $
                                      executeMigration opts.migrateForce plan manifest now
                              case execRes of
                                Left err -> pure (Left (MigrateExecFailed err))
                                Right manifest' ->
                                  pure (Right (MigrateApplied plan manifest'))

-- | The fetch-and-refresh wrapper. Reads @<installedDir>\/.seihou-origin.json@,
-- clones the source repo to a temp dir, locates the module within the
-- clone, and dispatches to 'runMigrateLocal' with the cloned module
-- dir. On a successful non-dry-run apply, refreshes @installedDir@
-- from the clone so the next @seihou status@/@migrate@ call sees the
-- new version locally.
--
-- Any soft failure in the fetch path (missing origin metadata, clone
-- failure, module not in remote) emits a one-line note (unless JSON
-- output is requested, in which case the path stays silent so JSON
-- consumers aren't disturbed) and falls back to 'runMigrateLocal'
-- against the original 'installedDir'.
runMigrateWithFetch ::
  MigrateOpts ->
  Manifest ->
  FilePath ->
  IO (Either MigrateError MigrateResult)
runMigrateWithFetch opts manifest installedDir = do
  origin <- readOriginInfo installedDir
  case origin of
    Nothing -> do
      note opts $
        "  no origin metadata at "
          <> T.pack (installedDir </> ".seihou-origin.json")
          <> "; using locally installed copy."
      runMigrateLocal opts manifest installedDir
    Just o -> withSystemTempDirectory "seihou-migrate-fetch" $ \tmp -> do
      let cloneDir = tmp </> "clone"
      note opts ("  Fetching " <> o.sourceUrl <> "...")
      cloneRes <- cloneRepo o.sourceUrl cloneDir
      case cloneRes of
        Left err -> do
          note opts ("  fetch failed: " <> err <> "; using locally installed copy.")
          runMigrateLocal opts manifest installedDir
        Right () -> do
          contents <- discoverRepoContents evalRegistryFromFile cloneDir
          case findRemoteModuleDir cloneDir contents opts.migrateModule of
            Nothing -> do
              note opts $
                "  module '"
                  <> opts.migrateModule.unModuleName
                  <> "' not present in remote; using locally installed copy."
              runMigrateLocal opts manifest installedDir
            Just (moduleDir, tags) -> do
              -- Plan and execute against the clone's module dir. The
              -- chain operates on the project's working tree; the
              -- moduleDir only supplies the migrations list and the
              -- target version.
              result <- runMigrateLocal opts manifest moduleDir
              -- Refresh the installed copy on the disk so future
              -- commands see the new version locally.
              case result of
                Right (MigrateApplied _ _)
                  | not opts.migrateDryRun ->
                      refreshInstalledFromClone moduleDir installedDir o tags
                _ -> pure ()
              pure result

-- | Print a one-line note unless JSON output is requested. Using JSON
-- output requires a clean, parseable stdout.
note :: MigrateOpts -> Text -> IO ()
note opts msg = unless opts.migrateJson (TIO.putStrLn msg)

-- | Locate the module's directory inside a cloned repo and return any
-- registry-declared tags. Returns 'Nothing' for empty repos or
-- recipe-only repos, or for multi-module repos that do not list the
-- requested module.
findRemoteModuleDir ::
  FilePath ->
  RepoContents ->
  ModuleName ->
  Maybe (FilePath, [Text])
findRemoteModuleDir cloneDir contents modName = case contents of
  SingleModule rootDir -> Just (rootDir, [])
  MultiModule registry ->
    case filter (\e -> e.name == modName) registry.modules of
      (entry : _) -> Just (cloneDir </> entry.path, entry.tags)
      [] -> Nothing
  SingleRecipe _ -> Nothing
  EmptyRepo -> Nothing

-- | Refresh the on-disk installed module directory from a cloned
-- module dir. Reads the clone's @module.dhall@ for its declared
-- version, then calls 'installModuleDir' with the same name as the
-- existing installation (basename of @installedDir@) so the XDG-derived
-- destination matches the original install path.
refreshInstalledFromClone ::
  FilePath ->
  FilePath ->
  OriginInfo ->
  [Text] ->
  IO ()
refreshInstalledFromClone moduleDir installedDir origin tags = do
  let dhallFile = moduleDir </> "module.dhall"
  modulRes <- evalModuleFromFile dhallFile
  case modulRes of
    Left _ -> pure ()
    Right modul -> do
      let installedName = takeFileName installedDir
      installModuleDir
        moduleDir
        installedName
        origin.sourceUrl
        origin.repoName
        modul.version
        tags

-- ----------------------------------------------------------------------------
-- Pending-migration detection (used by status / upgrade)
-- ----------------------------------------------------------------------------

-- | Detect whether the manifest's recorded version of an applied module
-- has fallen behind the installed copy in a way that pending migrations
-- would close. Returns:
--
--   * @Nothing@ — no pending chain (versions equal, manifest version
--     unrecorded, installed-module version unrecorded, parse failure
--     anywhere in the chain, the planner reported any error, or no
--     migrations are declared).
--   * @Just chain@ — a contiguous chain that would advance the
--     project's recorded version up to (some prefix of) the installed
--     copy's version.
--
-- Parse failures and planner errors are treated as "no pending
-- migration" rather than surfaced — this is the soft-warning path for
-- @seihou status@. Hard errors land on the user when they actually
-- run @seihou migrate@.
pendingChainFor ::
  AppliedModule ->
  Module ->
  Maybe MigrationChain
pendingChainFor applied installed = do
  fromText <- applied.moduleVersion
  fromV <- parseVersion fromText
  toText <- installed.version
  toV <- parseVersion toText
  case planMigrationChain
    applied.name.unModuleName
    installed.migrations
    fromV
    toV of
    Right (Just chain) -> Just chain
    _ -> Nothing

-- ----------------------------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------------------------

resolveTarget ::
  MigrateOpts -> Module -> ModuleName -> FilePath -> Either MigrateError Version
resolveTarget opts installedModule modName installedDhall =
  case opts.migrateTo of
    Just t -> case parseVersion t of
      Just v -> Right v
      Nothing -> Left (MigrateUnparseableTargetVersion t)
    Nothing -> case installedModule.version of
      Nothing -> Left (MigrateInstalledModuleHasNoVersion modName installedDhall)
      Just t -> case parseVersion t of
        Just v -> Right v
        Nothing -> Left (MigrateUnparseableInstalledVersion t)

findApplied :: Manifest -> ModuleName -> Maybe AppliedModule
findApplied m name =
  case filter (\am -> am.name == name) m.modules of
    (am : _) -> Just am
    [] -> Nothing

-- | Render a classified plan to stdout in the human-readable format.
renderPlan :: Bool -> ExecutedMigrationPlan -> IO ()
renderPlan c plan = do
  let chain = plan.planChain
  TIO.putStrLn $
    "Migration plan: "
      <> applyColor c bold (chain.migrationModule)
      <> "  "
      <> renderVersion chain.chainFrom
      <> " → "
      <> renderVersion chain.chainTo
  mapM_ (renderStep c) chain.chainSteps
  let conflictCount =
        length
          [ () | inst <- plan.planOps, isConflict inst
          ]
      affectedCount =
        length
          [ () | inst <- plan.planOps, touchesFs inst
          ]
  TIO.putStrLn ""
  TIO.putStrLn $
    T.pack (show affectedCount)
      <> " operation(s), "
      <> T.pack (show conflictCount)
      <> " conflict(s)."
  where
    isConflict (MoveFileInst _ _ MFConflict) = True
    isConflict (DeleteFileInst _ MFConflict) = True
    isConflict _ = False

    touchesFs (RunCommandInst _ _) = True
    touchesFs _ = True

renderStep :: Bool -> Migration -> IO ()
renderStep c step = do
  TIO.putStrLn $ "  " <> step.from <> " → " <> step.to <> ":"
  mapM_ (renderOp c) step.ops

renderOp :: Bool -> MigrationOp -> IO ()
renderOp c op = case op of
  MoveFile {src, dest} ->
    TIO.putStrLn $ "    " <> applyColor c green "move-file " <> T.pack src <> " -> " <> T.pack dest
  MoveDir {src, dest} ->
    TIO.putStrLn $ "    " <> applyColor c green "move-dir  " <> T.pack src <> " -> " <> T.pack dest
  DeleteFile {path} ->
    TIO.putStrLn $ "    " <> applyColor c yellow "delete    " <> T.pack path
  DeleteDir {path} ->
    TIO.putStrLn $ "    " <> applyColor c yellow "delete-dir" <> " " <> T.pack path
  RunCommand {run, workDir} ->
    let suffix = case workDir of
          Just wd -> applyColor c dim (" (in " <> T.pack wd <> ")")
          Nothing -> ""
     in TIO.putStrLn $ "    " <> applyColor c green "run       " <> run <> suffix

-- ----------------------------------------------------------------------------
-- JSON output
-- ----------------------------------------------------------------------------

planToJson :: ExecutedMigrationPlan -> Aeson.Value
planToJson plan =
  object
    [ "module" .= plan.planModule.unModuleName,
      "from" .= renderVersion plan.planChain.chainFrom,
      "to" .= renderVersion plan.planChain.chainTo,
      "steps"
        .= [ object
               [ "from" .= step.from,
                 "to" .= step.to,
                 "ops" .= map opToJson step.ops
               ]
           | step <- plan.planChain.chainSteps
           ],
      "operations" .= map instToJson plan.planOps
    ]

opToJson :: MigrationOp -> Aeson.Value
opToJson op = case op of
  MoveFile {src, dest} ->
    object ["op" .= ("move-file" :: Text), "src" .= T.pack src, "dest" .= T.pack dest]
  MoveDir {src, dest} ->
    object ["op" .= ("move-dir" :: Text), "src" .= T.pack src, "dest" .= T.pack dest]
  DeleteFile {path} ->
    object ["op" .= ("delete-file" :: Text), "path" .= T.pack path]
  DeleteDir {path} ->
    object ["op" .= ("delete-dir" :: Text), "path" .= T.pack path]
  RunCommand {run, workDir} ->
    object ["op" .= ("run-command" :: Text), "run" .= run, "workDir" .= fmap T.pack workDir]

instToJson :: MigrationOpInstance -> Aeson.Value
instToJson inst = case inst of
  MoveFileInst src dest status ->
    object
      [ "op" .= ("move-file" :: Text),
        "src" .= T.pack src,
        "dest" .= T.pack dest,
        "status" .= statusToJson status
      ]
  MoveDirInst src dest ->
    object
      ["op" .= ("move-dir" :: Text), "src" .= T.pack src, "dest" .= T.pack dest]
  DeleteFileInst p status ->
    object
      [ "op" .= ("delete-file" :: Text),
        "path" .= T.pack p,
        "status" .= statusToJson status
      ]
  DeleteDirInst p ->
    object ["op" .= ("delete-dir" :: Text), "path" .= T.pack p]
  RunCommandInst run wd ->
    object ["op" .= ("run-command" :: Text), "run" .= run, "workDir" .= fmap T.pack wd]

statusToJson :: MigrationFileStatus -> Text
statusToJson MFSafe = "safe"
statusToJson MFConflict = "conflict"
statusToJson MFGone = "gone"

-- ----------------------------------------------------------------------------
-- Misc
-- ----------------------------------------------------------------------------

-- | Apply ANSI styling when colour is enabled.
applyColor :: Bool -> (Text -> Text) -> Text -> Text
applyColor True f = f
applyColor False _ = id

-- | Print the error and exit non-zero. The IO shell calls this; the
-- pure 'runMigrate' returns 'Left' instead.
die :: MigrateError -> IO a
die err = do
  c <- useColor
  TIO.putStrLn $ applyColor c red "Error: " <> renderError err
  exitFailure

renderError :: MigrateError -> Text
renderError (MigrateNoManifest path) =
  "no Seihou manifest at " <> T.pack path <> "; run from a project that has been initialized."
renderError (MigrateModuleNotApplied modName) =
  "module '" <> modName.unModuleName <> "' is not applied in this project."
renderError (MigrateNoRecordedVersion modName) =
  "module '"
    <> modName.unModuleName
    <> "' has no version recorded in the manifest. Re-apply the module with 'seihou run' to record one before migrating."
renderError (MigrateInstalledModuleEvalFailed path msg) =
  "could not evaluate installed module at " <> T.pack path <> ": " <> msg
renderError (MigrateInstalledModuleHasNoVersion modName path) =
  "installed module '"
    <> modName.unModuleName
    <> "' at "
    <> T.pack path
    <> " has no version field; either pass --to or add a version to its module.dhall."
renderError (MigrateUnparseableInstalledVersion v) =
  "installed module's version '" <> v <> "' is not a valid dotted version."
renderError (MigrateUnparseableTargetVersion v) =
  "--to value '" <> v <> "' is not a valid dotted version."
renderError (MigrateUnparseableManifestVersion v) =
  "manifest's recorded module version '" <> v <> "' is not a valid dotted version."
renderError (MigratePlanFailed e) = renderPlanError e
renderError (MigrateExecFailed e) = renderExecError e

renderPlanError :: MigrationPlanError -> Text
renderPlanError (MigrationVersionUnparseable t) =
  "a migration declares an unparseable version: '" <> t <> "'"
renderPlanError (MigrationGap stuck target) =
  "no migration covers the gap from "
    <> renderVersion stuck
    <> " to "
    <> renderVersion target
    <> ". The module author needs to ship a migration that starts at "
    <> renderVersion stuck
    <> "."
renderPlanError (MigrationDowngradeNotSupported installed target) =
  "downgrade not supported: installed "
    <> renderVersion installed
    <> ", requested target "
    <> renderVersion target
    <> "."
renderPlanError (MigrationDuplicateEdge fromV _) =
  "two or more migrations declare the same 'from = "
    <> renderVersion fromV
    <> "'. The chain is ambiguous; the module author needs to merge or remove the duplicate."
renderPlanError (MigrationOvershoot atV reachedV) =
  "migration from "
    <> renderVersion atV
    <> " jumps to "
    <> renderVersion reachedV
    <> ", which overshoots the requested target. Pass --to to migrate to "
    <> renderVersion reachedV
    <> " explicitly, or ship intermediate migrations."

renderExecError :: MigrationExecError -> Text
renderExecError (MigrationConflict paths) =
  "the following file(s) have been modified since they were generated:\n"
    <> T.intercalate "\n" ["  - " <> T.pack p | p <- paths]
    <> "\n\nRe-run with --force to overwrite them, or revert your edits first."
renderExecError (MigrationCommandFailed msg code) =
  "a run-command op exited with code "
    <> T.pack (show code)
    <> ":\n  "
    <> msg

-- Aeson ToJSON pass-through for ExecutedMigrationPlan: routed through
-- planToJson manually rather than deriving so we have the field shape
-- documented above.
instance ToJSON ExecutedMigrationPlan where
  toJSON = planToJson

-- Avoid an unused-import warning when 'unless' is the only Control.Monad
-- use and tests trim other helpers.
unless :: Bool -> IO () -> IO ()
unless True _ = pure ()
unless False action = action
