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
import Data.Maybe (isJust)
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
    MigrationPlan (..),
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
    migrateNoFetch :: Bool,
    -- | Skip planning entirely. Read the installed copy's declared
    -- version and write it as the manifest's recorded version, exiting
    -- with a no-op-style outcome. Independent of @migrateNoFetch@:
    -- when both are set, no fetch happens *and* no planning happens.
    -- Mutually exclusive with @migrateTo@: passing both is rejected
    -- with @MigrateConflictingFlags@ before any work is done.
    --
    -- Use case: a project pinned at an older version of a module that
    -- has since reorganized its template paths but cannot reach those
    -- new paths via declared migrations. The user can manually
    -- acknowledge "I know the unreachable tail is safe for my
    -- project" and bring the manifest's version field forward without
    -- running any ops.
    migrateBumpOnly :: Bool
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
  | -- | Two mutually exclusive flags were passed together. The
    -- carried 'Text' is the message describing the conflict.
    MigrateConflictingFlags Text
  deriving stock (Eq, Show, Generic)

-- | Outcome of a successful @runMigrate@ call.
--
-- The variant tells the renderer what to print and the caller (run,
-- upgrade) which manifest to write back. Partial and blocked outcomes
-- exist because EP-5 softened the planner contract: when the declared
-- migration list does not reach the target exactly, the planner returns
-- a partial plan plus an unreachable tail rather than failing. The
-- migrate command then either applies the longest reachable prefix
-- (without @--to@) or surfaces the gap as a hard error (with @--to@).
data MigrateResult
  = -- | Manifest was already at the target version; nothing to do.
    MigrateNoOp Version
  | -- | A full-chain plan was computed but not executed (dry-run).
    MigrateDryRunOK ExecutedMigrationPlan
  | -- | A partial-chain plan was computed but not executed (dry-run).
    -- The two 'Version's are @(stuckAt, target)@ — the highest version
    -- the chain reaches and the target it could not get to.
    MigrateDryRunOKPartial ExecutedMigrationPlan Version Version
  | -- | The full-chain plan was applied; the post-execution manifest is
    -- returned.
    MigrateApplied ExecutedMigrationPlan Manifest
  | -- | A partial-chain plan was applied (longest reachable prefix).
    -- The two 'Version's are @(stuckAt, target)@: the highest version
    -- the chain landed on (== @manifest.moduleVersion@ after the apply,
    -- == @plan.planChain.chainTo@) and the target the chain still cannot
    -- reach. The renderer prints both the chain summary and a "no
    -- migration declared from <stuckAt>; remote is at <target>"
    -- advisory.
    MigrateAppliedPartial ExecutedMigrationPlan Manifest Version Version
  | -- | No migration starts at the manifest's current version, so no
    -- step can be applied. The two 'Version's are @(stuckAt, target)@
    -- — i.e. the manifest's current version and the target. Distinct
    -- from 'MigratePlanFailed' because @seihou migrate@ (without
    -- @--to@) treats this as a non-fatal outcome the renderer surfaces
    -- as an actionable advisory; with @--to TARGET@, the same situation
    -- is converted to 'MigratePlanFailed' (MigrationGap …) for the
    -- strict-target contract.
    MigrateBlocked Version Version
  | -- | The module's manifest version trails its installed copy's
    -- version, but the module declares no migrations at all
    -- (@migrations = []@). The two 'Version's are @(manifest, target)@.
    -- The renderer prints a softened advisory pointing at
    -- "seihou upgrade && seihou run"; the exit code is zero (no work
    -- was done; no manifest change). Distinct from 'MigrateBlocked'
    -- (migrations declared but none reach the manifest version, which
    -- is a real block).
    MigrateBenignUpgrade Version Version
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
    Right (MigrateDryRunOKPartial plan stuck target) -> do
      if opts.migrateJson
        then LBS.putStr (encodePretty (planToJsonWithTail plan (Just (stuck, target))))
        else do
          renderPlan colorEnabled plan
          TIO.putStrLn ""
          TIO.putStrLn $
            applyColor colorEnabled yellow $
              "Note: no migration declared from "
                <> renderVersion stuck
                <> "; remote is at "
                <> renderVersion target
                <> "."
          TIO.putStrLn $ applyColor colorEnabled dim "(dry run — no changes made)"
      exitSuccess
    Right (MigrateApplied plan manifest')
      -- --bump-only path: dispatchPlan never produces an empty plan
      -- via MigrateApplied, but the bump-only path does. Render the
      -- distinct "Bumped" line so the user knows no ops ran.
      | null plan.planChain.chainSteps,
        not opts.migrateJson -> do
          runEff $
            runFilesystem $
              runManifestStore manifestPath $
                writeManifest manifest'
          let toV = plan.planChain.chainTo
          TIO.putStrLn $
            applyColor colorEnabled green "✓"
              <> " Bumped "
              <> applyColor colorEnabled bold modName.unModuleName
              <> " "
              <> renderVersion fromV
              <> " → "
              <> renderVersion toV
              <> " (no migration ops)."
      | null plan.planChain.chainSteps -> do
          -- bump-only JSON path: emit the same shape as a regular
          -- applied plan. Empty steps + empty operations make the
          -- bump-only nature visible to consumers.
          runEff $
            runFilesystem $
              runManifestStore manifestPath $
                writeManifest manifest'
          LBS.putStr (encodePretty (planToJson plan))
      | otherwise -> do
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
    Right (MigrateAppliedPartial plan manifest' stuck target) -> do
      if opts.migrateJson
        then LBS.putStr (encodePretty (planToJsonWithTail plan (Just (stuck, target))))
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
        TIO.putStrLn $
          applyColor colorEnabled yellow $
            "Note: no migration declared from "
              <> renderVersion stuck
              <> "; remote is at "
              <> renderVersion target
              <> "."
    Right (MigrateBlocked stuck target) -> do
      if opts.migrateJson
        then
          LBS.putStr
            ( encodePretty
                ( object
                    [ "module" .= modName.unModuleName,
                      "blocked" .= True,
                      "stuckAt" .= renderVersion stuck,
                      "target" .= renderVersion target
                    ]
                )
            )
        else
          TIO.putStrLn $
            applyColor colorEnabled yellow $
              "Blocked: no migration declared from "
                <> renderVersion stuck
                <> "; remote is at "
                <> renderVersion target
                <> ". The module author must ship one before this project can move forward."
      exitSuccess
    Right (MigrateBenignUpgrade from to) -> do
      if opts.migrateJson
        then
          LBS.putStr
            ( encodePretty
                ( object
                    [ "module" .= modName.unModuleName,
                      "benign" .= True,
                      "from" .= renderVersion from,
                      "to" .= renderVersion to
                    ]
                )
            )
        else
          TIO.putStrLn $
            applyColor colorEnabled yellow $
              "Note: "
                <> modName.unModuleName
                <> " has no migrations declared ("
                <> renderVersion from
                <> " -> "
                <> renderVersion to
                <> "). This is a benign version bump; run 'seihou upgrade "
                <> modName.unModuleName
                <> " && seihou run' to refresh templates and bring the manifest up to date."
      exitSuccess

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
  | opts.migrateBumpOnly = runBumpOnly opts manifest installedDir
  | opts.migrateNoFetch = runMigrateLocal opts manifest installedDir
  | otherwise = runMigrateWithFetch opts manifest installedDir

-- | The @--bump-only@ escape hatch. Reads the installed copy's
-- @module.dhall@ for its declared version and writes that as the
-- manifest's recorded @moduleVersion@ without consulting the
-- planner. Returns 'MigrateApplied' with an empty
-- 'ExecutedMigrationPlan' so the renderer prints the bump-only
-- summary line.
--
-- The fetch step is shared with the planning path: by default
-- @--bump-only@ also fetches so the bump targets the latest remote
-- version, not a possibly stale local cache. @--no-fetch@ skips the
-- fetch and reads the local installed copy directly.
--
-- @--bump-only@ is mutually exclusive with @--to TARGET@. The
-- contradiction is rejected with 'MigrateConflictingFlags' before
-- any IO so the error is the very first thing the caller sees.
runBumpOnly ::
  MigrateOpts ->
  Manifest ->
  FilePath ->
  IO (Either MigrateError MigrateResult)
runBumpOnly opts manifest installedDir
  | isJust opts.migrateTo =
      pure
        ( Left
            ( MigrateConflictingFlags
                "--bump-only and --to are mutually exclusive; --bump-only always targets the installed copy's declared version."
            )
        )
  | opts.migrateNoFetch = bumpFromLocal opts manifest installedDir
  | otherwise = bumpFromFetch opts manifest installedDir

-- | Read the installed copy's @module.dhall@ in @sourceDir@ and
-- write its declared version into the manifest. If the installed
-- copy has no version, emit a no-op outcome (consistent with the
-- planner's "nothing to do" semantics).
bumpFromLocal ::
  MigrateOpts ->
  Manifest ->
  FilePath ->
  IO (Either MigrateError MigrateResult)
bumpFromLocal opts manifest sourceDir = do
  let modName = opts.migrateModule
  case findApplied manifest modName of
    Nothing -> pure (Left (MigrateModuleNotApplied modName))
    Just applied -> do
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
            Right sourceModule -> case sourceModule.version of
              Nothing -> case applied.moduleVersion >>= parseVersion of
                Just v -> pure (Right (MigrateNoOp v))
                Nothing -> pure (Left (MigrateInstalledModuleHasNoVersion modName sourceDhall))
              Just toText -> case parseVersion toText of
                Nothing -> pure (Left (MigrateUnparseableInstalledVersion toText))
                Just toV -> do
                  let manifest' = replaceModuleVersion manifest modName toText
                      chain =
                        MigrationChain
                          { migrationModule = modName.unModuleName,
                            chainFrom = toV,
                            chainTo = toV,
                            chainSteps = []
                          }
                      executed =
                        ExecutedMigrationPlan
                          { planModule = modName,
                            planChain = chain,
                            planOps = []
                          }
                  pure (Right (MigrateApplied executed manifest'))

-- | Fetch the source repo, locate the module dir, and bump from
-- there. Soft-fail to the local path if the fetch cannot be
-- completed (missing origin metadata, clone failure, module not in
-- remote) — same fallback policy as 'runMigrateWithFetch'.
bumpFromFetch ::
  MigrateOpts ->
  Manifest ->
  FilePath ->
  IO (Either MigrateError MigrateResult)
bumpFromFetch opts manifest installedDir = do
  origin <- readOriginInfo installedDir
  case origin of
    Nothing -> do
      note opts $
        "  no origin metadata at "
          <> T.pack (installedDir </> ".seihou-origin.json")
          <> "; using locally installed copy."
      bumpFromLocal opts manifest installedDir
    Just o -> withSystemTempDirectory "seihou-migrate-fetch" $ \tmp -> do
      let cloneDir = tmp </> "clone"
      note opts ("  Fetching " <> o.sourceUrl <> "...")
      cloneRes <- cloneRepo o.sourceUrl cloneDir
      case cloneRes of
        Left err -> do
          note opts ("  fetch failed: " <> err <> "; using locally installed copy.")
          bumpFromLocal opts manifest installedDir
        Right () -> do
          contents <- discoverRepoContents evalRegistryFromFile cloneDir
          case findRemoteModuleDir cloneDir contents opts.migrateModule of
            Nothing -> do
              note opts $
                "  module '"
                  <> opts.migrateModule.unModuleName
                  <> "' not present in remote; using locally installed copy."
              bumpFromLocal opts manifest installedDir
            Just (moduleDir, tags) -> do
              result <- bumpFromLocal opts manifest moduleDir
              case result of
                Right (MigrateApplied _ _) ->
                  refreshInstalledFromClone moduleDir installedDir o tags
                _ -> pure ()
              pure result

-- | Replace the @moduleVersion@ field on the matching applied module
-- entry. Other entries are kept untouched.
replaceModuleVersion :: Manifest -> ModuleName -> Text -> Manifest
replaceModuleVersion manifest name newVer =
  manifest {modules = map go manifest.modules}
  where
    go am
      | am.name == name = am {moduleVersion = Just newVer}
      | otherwise = am

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
                        Right (Just plan) ->
                          dispatchPlan opts manifest plan

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
              -- commands see the new version locally. Both full and
              -- partial applies update the disk; blocked / dry-run /
              -- no-op outcomes leave the disk untouched.
              case result of
                Right (MigrateApplied _ _)
                  | not opts.migrateDryRun ->
                      refreshInstalledFromClone moduleDir installedDir o tags
                Right (MigrateAppliedPartial _ _ _ _)
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
  Maybe MigrationPlan
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
    -- Surface every divergence: full, partial, and blocked. The
    -- 'MigrationPlan' value tells consumers which shape they're
    -- looking at. Hard planner errors (downgrade, overshoot, duplicate
    -- edge, unparseable version) and Right Nothing (already at
    -- target) collapse to Nothing — there is no actionable pending
    -- chain to report.
    Right (Just plan) -> Just plan
    _ -> Nothing

-- ----------------------------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------------------------

-- | Decide what to do with a non-trivial 'MigrationPlan' returned by
-- the planner. Pure-IO: classifies the chain, optionally executes it,
-- and packs the outcome into a 'MigrateResult' variant the renderer
-- knows how to print.
--
-- The four cases:
--
--   * Full chain (@chainSteps@ non-empty, no unreachable tail) —
--     existing behavior: 'MigrateDryRunOK' or 'MigrateApplied'.
--   * Partial chain with @--to TARGET@ — strict-target contract
--     refuses the partial fulfillment, surfaced as
--     'MigratePlanFailed' ('MigrationGap' …).
--   * Partial chain without @--to@ — apply the longest reachable
--     prefix and emit 'MigrateDryRunOKPartial' or
--     'MigrateAppliedPartial' so the renderer can print both the
--     chain summary and the unreachable-tail advisory.
--   * Blocked (@chainSteps@ empty) with @--to TARGET@ — strict-target
--     refusal as above.
--   * Blocked without @--to@ — 'MigrateBlocked'; nothing to apply.
dispatchPlan ::
  MigrateOpts ->
  Manifest ->
  MigrationPlan ->
  IO (Either MigrateError MigrateResult)
dispatchPlan opts manifest plan
  -- Blocked / benign case: no edge starts at the manifest version.
  -- The two are split by planMigrationsDeclared: True (declared but
  -- unreachable) keeps the EP-5 blocked semantics; False (no
  -- migrations declared) surfaces as a benign upgrade so the renderer
  -- can soften the message. --to TARGET stays strict in both
  -- sub-cases because the user named a specific version they did not
  -- get; the new --bump-only escape hatch (M6) is the way to bypass
  -- planning when that is what the user actually wants.
  | null plan.planChain.chainSteps = case plan.planUnreachable of
      Just (stuck, target)
        | hasExplicitTo opts ->
            pure (Left (MigratePlanFailed (MigrationGap stuck target)))
        | not plan.planMigrationsDeclared ->
            pure (Right (MigrateBenignUpgrade stuck target))
        | otherwise ->
            pure (Right (MigrateBlocked stuck target))
      Nothing ->
        -- Defensive: planner shouldn't return an empty chain with no
        -- unreachable tail, but if it ever does, that means installed
        -- == target and walk produced nothing — treat as no-op.
        pure (Right (MigrateNoOp plan.planChain.chainTo))
  -- Partial chain: chain has steps but doesn't reach target.
  | Just (stuck, target) <- plan.planUnreachable =
      if hasExplicitTo opts
        then pure (Left (MigratePlanFailed (MigrationGap stuck target)))
        else applyChain opts manifest plan.planChain (Just (stuck, target))
  -- Full chain: chain reaches target exactly.
  | otherwise = applyChain opts manifest plan.planChain Nothing

-- | Whether the user passed @--to TARGET@ explicitly. The strict-target
-- contract requires every consumer of a partial/blocked plan to refuse
-- when the user named a specific version they did not get.
hasExplicitTo :: MigrateOpts -> Bool
hasExplicitTo opts = case opts.migrateTo of
  Just _ -> True
  Nothing -> False

-- | Classify the chain, optionally execute it, and return the
-- appropriate 'MigrateResult' variant. The @mUnreachable@ argument
-- distinguishes full-chain from partial-chain outcomes.
applyChain ::
  MigrateOpts ->
  Manifest ->
  MigrationChain ->
  -- | 'Nothing' for full chains; @Just (stuck, target)@ for partial.
  Maybe (Version, Version) ->
  IO (Either MigrateError MigrateResult)
applyChain opts manifest chain mUnreachable = do
  executedPlan <-
    runEff $
      runFilesystem $
        classifyMigration manifest chain
  if opts.migrateDryRun
    then case mUnreachable of
      Nothing -> pure (Right (MigrateDryRunOK executedPlan))
      Just (stuck, target) ->
        pure (Right (MigrateDryRunOKPartial executedPlan stuck target))
    else do
      now <- getCurrentTime
      execRes <-
        runEff $
          runFilesystem $
            runProcessIO $
              executeMigration opts.migrateForce executedPlan manifest now
      case execRes of
        Left err -> pure (Left (MigrateExecFailed err))
        Right manifest' -> case mUnreachable of
          Nothing -> pure (Right (MigrateApplied executedPlan manifest'))
          Just (stuck, target) ->
            pure (Right (MigrateAppliedPartial executedPlan manifest' stuck target))

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
planToJson plan = planToJsonWithTail plan Nothing

-- | JSON encoding of an executed plan, with an optional unreachable
-- tail describing the partial-chain advisory.
planToJsonWithTail ::
  ExecutedMigrationPlan -> Maybe (Version, Version) -> Aeson.Value
planToJsonWithTail plan mTail =
  object $
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
      ++ case mTail of
        Just (stuck, target) ->
          [ "unreachable"
              .= object
                [ "stuckAt" .= renderVersion stuck,
                  "target" .= renderVersion target
                ]
          ]
        Nothing -> []

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
renderError (MigrateConflictingFlags msg) = msg

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
