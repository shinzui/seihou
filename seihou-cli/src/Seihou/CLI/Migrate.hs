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
import Seihou.CLI.Style (bold, dim, green, red, useColor, yellow)
import Seihou.Core.Migration
  ( Migration (..),
    MigrationChain (..),
    MigrationOp (..),
    MigrationPlanError (..),
    planMigrationChain,
  )
import Seihou.Core.Types
  ( AppliedModule (..),
    Manifest (..),
    Module (..),
    ModuleName (..),
  )
import Seihou.Core.Version (Version, parseVersion, renderVersion)
import Seihou.Dhall.Eval (evalModuleFromFile)
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
import System.FilePath ((</>))

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
    migrateVerbose :: Bool
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

-- | The IO entry point dispatched from @main@.
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

  fromText <- case applied.moduleVersion of
    Just v -> pure v
    Nothing -> die (MigrateNoRecordedVersion modName)
  fromV <- case parseVersion fromText of
    Just v -> pure v
    Nothing -> die (MigrateUnparseableManifestVersion fromText)

  -- Evaluate the installed module's module.dhall to get the migrations
  -- list and the current installed version.
  let installedDhall = applied.source </> "module.dhall"
  exists <- doesFileExist installedDhall
  installedModule <- case exists of
    False -> die (MigrateInstalledModuleEvalFailed installedDhall "module.dhall not found at recorded source")
    True -> do
      r <- evalModuleFromFile installedDhall
      case r of
        Right m -> pure m
        Left err -> die (MigrateInstalledModuleEvalFailed installedDhall (T.pack (show err)))

  -- Resolve target version: --to override, else installed module's version.
  toText <- case opts.migrateTo of
    Just t -> pure t
    Nothing -> case installedModule.version of
      Just v -> pure v
      Nothing -> die (MigrateInstalledModuleHasNoVersion modName installedDhall)
  toV <- case parseVersion toText of
    Just v -> pure v
    Nothing -> case opts.migrateTo of
      Just _ -> die (MigrateUnparseableTargetVersion toText)
      Nothing -> die (MigrateUnparseableInstalledVersion toText)

  -- Plan and act.
  case planMigrationChain modName.unModuleName installedModule.migrations fromV toV of
    Left e -> die (MigratePlanFailed e)
    Right Nothing -> do
      colorEnabled <- useColor
      TIO.putStrLn $
        applyColor colorEnabled green "✓"
          <> " "
          <> modName.unModuleName
          <> " is already at version "
          <> renderVersion toV
          <> "; nothing to do."
      exitSuccess
    Right (Just chain) -> do
      plan <-
        runEff $
          runFilesystem $
            classifyMigration manifest chain

      colorEnabled <- useColor
      if opts.migrateJson
        then LBS.putStr (encodePretty (planToJson plan))
        else renderPlan colorEnabled plan

      if opts.migrateDryRun
        then do
          unless opts.migrateJson $ do
            TIO.putStrLn ""
            TIO.putStrLn $ applyColor colorEnabled dim "(dry run — no changes made)"
          exitSuccess
        else do
          now <- getCurrentTime
          execRes <-
            runEff $
              runFilesystem $
                runProcessIO $
                  executeMigration opts.migrateForce plan manifest now
          case execRes of
            Left err -> die (MigrateExecFailed err)
            Right manifest' -> do
              runEff $
                runFilesystem $
                  runManifestStore manifestPath $
                    writeManifest manifest'
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
runMigrate ::
  -- | Options
  MigrateOpts ->
  -- | Manifest in memory (already loaded)
  Manifest ->
  -- | Installed-module directory, the path that holds @module.dhall@
  FilePath ->
  IO (Either MigrateError MigrateResult)
runMigrate opts manifest installedDir = do
  let modName = opts.migrateModule
  case findApplied manifest modName of
    Nothing -> pure (Left (MigrateModuleNotApplied modName))
    Just applied -> case applied.moduleVersion of
      Nothing -> pure (Left (MigrateNoRecordedVersion modName))
      Just fromText ->
        case parseVersion fromText of
          Nothing -> pure (Left (MigrateUnparseableManifestVersion fromText))
          Just fromV -> do
            let installedDhall = installedDir </> "module.dhall"
            exists <- doesFileExist installedDhall
            if not exists
              then
                pure
                  ( Left
                      ( MigrateInstalledModuleEvalFailed
                          installedDhall
                          "module.dhall not found at installed dir"
                      )
                  )
              else do
                r <- evalModuleFromFile installedDhall
                case r of
                  Left err ->
                    pure
                      ( Left
                          ( MigrateInstalledModuleEvalFailed
                              installedDhall
                              (T.pack (show err))
                          )
                      )
                  Right installedModule -> case resolveTarget opts installedModule modName installedDhall of
                    Left e -> pure (Left e)
                    Right toV ->
                      case planMigrationChain
                        modName.unModuleName
                        installedModule.migrations
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
