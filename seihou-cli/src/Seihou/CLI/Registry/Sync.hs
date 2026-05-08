module Seihou.CLI.Registry.Sync
  ( SyncVersionsOpts (..),
    SyncAction (..),
    SyncOutcome (..),
    runSync,
    handleSyncVersions,
    renderSyncReport,
    checkRegistryVersionDrift,
    resolveOnDiskVersions,
  )
where

import Data.Maybe (mapMaybe)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import GHC.Generics (Generic)
import Seihou.Core.Registry
  ( EntryKind (..),
    Registry (..),
    RegistryEntry (..),
    RepoContents (..),
    SyncDiff (..),
    SyncReport (..),
    SyncStatus (..),
    computeRegistrySync,
    discoverRepoContents,
    formatDriftWarning,
    renderRegistryDhall,
  )
import Seihou.Core.Types (Blueprint, Module, ModuleName (..), Recipe)
import Seihou.Core.Types qualified as Types
import Seihou.Dhall.Eval
  ( evalBlueprintFromFile,
    evalModuleFromFile,
    evalRecipeFromFile,
    evalRegistryFromFile,
  )
import Seihou.Prelude
import System.Directory (doesDirectoryExist)
import System.Exit (ExitCode (..), exitWith)
import System.FilePath ((</>))
import System.IO (hPutStrLn, stderr)

-- | Flags parsed for the @seihou registry sync-versions@ subcommand.
data SyncVersionsOpts = SyncVersionsOpts
  { syncVersionsDir :: Maybe FilePath,
    syncVersionsDryRun :: Bool,
    syncVersionsCheck :: Bool
  }
  deriving stock (Eq, Show, Generic)

-- | What the sync pass did with the registry file.
data SyncAction
  = -- | Registry file rewritten on disk.
    Wrote
  | -- | @--dry-run@: diff computed, file left untouched.
    WouldWrite
  | -- | @--check@: diff computed, file left untouched, exit code reflects drift.
    Checked
  deriving stock (Eq, Show, Generic)

-- | Terminal outcome of a sync run, decoupled from IO concerns like printing
-- and 'exitWith' so tests can assert without capturing stdout.
data SyncOutcome
  = -- | Registry loaded, diff computed, action applied.
    SyncSuccess SyncReport SyncAction
  | -- | Target invalid (directory missing, no registry file, etc.); carries a
    -- human-readable error.
    SyncFailure Text
  deriving stock (Eq, Show, Generic)

-- | Testable core of @seihou registry sync-versions@. Locates the registry,
-- reads each entry's on-disk version, computes the diff, writes the file
-- when appropriate, and returns a structured outcome.
runSync :: SyncVersionsOpts -> IO SyncOutcome
runSync opts = do
  let targetDir = maybe "." id opts.syncVersionsDir
  dirExists <- doesDirectoryExist targetDir
  if not dirExists
    then pure (SyncFailure ("target directory does not exist: " <> T.pack targetDir))
    else do
      contents <- discoverRepoContents evalRegistryFromFile targetDir
      case contents of
        MultiModule reg -> do
          lookups <- resolveOnDiskVersions targetDir reg
          let report = computeRegistrySync reg lookups
          let checkMode = opts.syncVersionsCheck
              dryRun = opts.syncVersionsDryRun && not checkMode
              writeMode = not checkMode && not dryRun
          action <-
            if writeMode
              then do
                let rendered = renderRegistryDhall report.syncUpdated
                TIO.writeFile (targetDir </> "seihou-registry.dhall") rendered
                pure Wrote
              else
                if checkMode
                  then pure Checked
                  else pure WouldWrite
          pure (SyncSuccess report action)
        _ ->
          pure
            ( SyncFailure
                "registry sync-versions requires a seihou-registry.dhall at the target directory"
            )

-- | Read each registry entry's @module.dhall@ or @recipe.dhall@ and pair it
-- with the entry's @(kind, name)@. Entries whose file fails to evaluate are
-- omitted from the returned list, which causes 'computeRegistrySync' to
-- classify them as 'SyncOrphan'.
resolveOnDiskVersions ::
  FilePath ->
  Registry ->
  IO [(EntryKind, ModuleName, Maybe Text)]
resolveOnDiskVersions repoRoot reg = do
  modulePairs <- mapM (loadModule repoRoot) reg.modules
  recipePairs <- mapM (loadRecipe repoRoot) reg.recipes
  blueprintPairs <- mapM (loadBlueprint repoRoot) reg.blueprints
  pure (concat modulePairs <> concat recipePairs <> concat blueprintPairs)
  where
    loadModule :: FilePath -> RegistryEntry -> IO [(EntryKind, ModuleName, Maybe Text)]
    loadModule root entry = do
      let path = root </> entry.path </> "module.dhall"
      decoded <- evalModuleFromFile path
      case decoded of
        Right m -> pure [(ModuleEntry, entry.name, moduleVersion m)]
        Left _ -> pure []
    loadRecipe :: FilePath -> RegistryEntry -> IO [(EntryKind, ModuleName, Maybe Text)]
    loadRecipe root entry = do
      let path = root </> entry.path </> "recipe.dhall"
      decoded <- evalRecipeFromFile path
      case decoded of
        Right r -> pure [(RecipeEntry, entry.name, recipeVersion r)]
        Left _ -> pure []
    loadBlueprint :: FilePath -> RegistryEntry -> IO [(EntryKind, ModuleName, Maybe Text)]
    loadBlueprint root entry = do
      let path = root </> entry.path </> "blueprint.dhall"
      decoded <- evalBlueprintFromFile path
      case decoded of
        Right b -> pure [(BlueprintEntry, entry.name, blueprintVersion b)]
        Left _ -> pure []

-- | Extract the @version@ field from a 'Module' by pattern match. A direct
-- record-dot access (@m.version@) fails under 'DuplicateRecordFields' +
-- 'NoFieldSelectors' in this module because 'RegistryEntry' and 'Module'
-- share the field name.
moduleVersion :: Module -> Maybe Text
moduleVersion Types.Module {Types.version = v} = v

-- | Analogous accessor for 'Recipe.version'. See 'moduleVersion'.
recipeVersion :: Recipe -> Maybe Text
recipeVersion Types.Recipe {Types.version = v} = v

-- | Analogous accessor for 'Blueprint.version'. See 'moduleVersion'.
blueprintVersion :: Blueprint -> Maybe Text
blueprintVersion Types.Blueprint {Types.version = v} = v

-- | Handler wired into the CLI command dispatcher. Drives 'runSync', prints a
-- human-readable diff, and exits with 0 or 1 as appropriate.
handleSyncVersions :: SyncVersionsOpts -> IO ()
handleSyncVersions opts = do
  outcome <- runSync opts
  case outcome of
    SyncFailure msg -> do
      hPutStrLn stderr ("error: " <> T.unpack msg)
      exitWith (ExitFailure 1)
    SyncSuccess report action -> do
      TIO.putStr (renderSyncReport report)
      case action of
        Wrote -> exitWith ExitSuccess
        WouldWrite -> exitWith ExitSuccess
        Checked ->
          if anyDrift report
            then exitWith (ExitFailure 1)
            else exitWith ExitSuccess

-- | Format the diff table and summary line for display on stdout.
-- The first entry in 'syncDiffs' appears first, preserving registry order.
renderSyncReport :: SyncReport -> Text
renderSyncReport report
  | null report.syncDiffs =
      "Registry is empty.\n"
  | otherwise =
      T.unlines $
        header
          : map ("  " <>) rows
            <> ["", summary report]
  where
    header = "Updated seihou-registry.dhall:"
    rows = map renderRow report.syncDiffs

    renderRow :: SyncDiff -> Text
    renderRow diff =
      let label = kindPrefix diff.diffKind <> diff.diffName.unModuleName <> ":"
          padded = padRight labelWidth label
          old = renderVersion diff.diffOld
          new = renderVersion diff.diffNew
          arrow = case diff.diffStatus of
            SyncInSync -> " == " <> new <> " (no change)"
            SyncOrphan -> " ?? " <> old <> " (module.dhall missing)"
            _ -> " -> " <> new
       in padded <> old <> arrow

    labelWidth = maximum (24 : map diffLabelWidth report.syncDiffs)
    diffLabelWidth d =
      T.length (kindPrefix d.diffKind <> d.diffName.unModuleName) + 2

kindPrefix :: EntryKind -> Text
kindPrefix ModuleEntry = "modules."
kindPrefix RecipeEntry = "recipes."
kindPrefix BlueprintEntry = "blueprints."

renderVersion :: Maybe Text -> Text
renderVersion Nothing = "(none)"
renderVersion (Just v) = v

padRight :: Int -> Text -> Text
padRight w t =
  let pad = max 0 (w - T.length t)
   in t <> T.replicate pad " "

summary :: SyncReport -> Text
summary report =
  let updated = length [d | d <- report.syncDiffs, changesVersion d.diffStatus]
      orphans = length [d | d <- report.syncDiffs, d.diffStatus == SyncOrphan]
      unchanged = length [d | d <- report.syncDiffs, d.diffStatus == SyncInSync]
      base =
        T.pack (show updated)
          <> " "
          <> pluralize updated "entry" "entries"
          <> " updated, "
          <> T.pack (show unchanged)
          <> " unchanged"
      suffix =
        if orphans > 0
          then ", " <> T.pack (show orphans) <> " orphan" <> (if orphans > 1 then "s" else "")
          else ""
   in base <> suffix <> "."
  where
    changesVersion SyncMissing = True
    changesVersion (SyncStale _) = True
    changesVersion _ = False
    pluralize 1 s _ = s
    pluralize _ _ p = p

anyDrift :: SyncReport -> Bool
anyDrift report =
  any
    ( \d -> case d.diffStatus of
        SyncInSync -> False
        _ -> True
    )
    report.syncDiffs

-- | Soft-warning pass: compare each registry entry's 'version' with the
-- on-disk module.dhall / recipe.dhall and return one warning per out-of-sync
-- entry. Entries whose file is missing or unparseable are treated as orphan
-- and excluded here, matching 'formatDriftWarning' (they are already flagged
-- by 'validateRegistry').
--
-- Intended to be called after 'discoverRepoContents' yields 'MultiModule' —
-- the caller has already decoded the registry and knows the repo root.
checkRegistryVersionDrift :: FilePath -> Registry -> IO [Text]
checkRegistryVersionDrift repoRoot reg = do
  lookups <- resolveOnDiskVersions repoRoot reg
  let report = computeRegistrySync reg lookups
  pure (mapMaybe formatDriftWarning report.syncDiffs)
