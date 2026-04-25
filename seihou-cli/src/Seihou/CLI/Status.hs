module Seihou.CLI.Status
  ( handleStatus,
  )
where

import Control.Exception (SomeException, try)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Time.Format (defaultTimeLocale, formatTime)
import Seihou.CLI.Commands (StatusOpts (..))
import Seihou.CLI.Migrate (pendingChainFor)
import Seihou.CLI.Outdated
  ( OutdatedEntry (..),
    checkInstalledModulesForUpdates,
  )
import Seihou.CLI.Shared (logIO)
import Seihou.CLI.Style (dim, green, red, useColor, yellow)
import Seihou.CLI.VersionCompare (OutdatedStatus (..))
import Seihou.Core.Migration (MigrationChain (..))
import Seihou.Core.Module (defaultSearchPaths, discoverAllModules)
import Seihou.Core.Status (computeTrackedFileStatuses)
import Seihou.Core.Types
import Seihou.Core.Version (renderVersion)
import Seihou.Dhall.Eval (evalModuleFromFile)
import Seihou.Effect.FilesystemInterp (runFilesystem)
import Seihou.Effect.Logger (logError)
import Seihou.Effect.ManifestStore (readManifest)
import Seihou.Effect.ManifestStoreInterp (runManifestStore)
import Seihou.Prelude
import System.Directory (doesFileExist)
import System.Exit (exitFailure)
import System.IO (hPutStrLn, stderr)

handleStatus :: StatusOpts -> IO ()
handleStatus opts = do
  let manifestPath = ".seihou" </> "manifest.json"

  -- Run both manifest read and file status computation in the same effect block.
  result <- runEff $ runFilesystem $ runManifestStore manifestPath $ do
    mResult <- readManifest
    case mResult of
      Left err -> pure (Left err)
      Right Nothing -> pure (Right Nothing)
      Right (Just manifest) -> do
        tracked <- computeTrackedFileStatuses manifest
        pure (Right (Just (manifest, tracked)))

  colorEnabled <- useColor

  case result of
    Left err -> do
      logIO LogNormal (logError $ "Error reading manifest: " <> err)
      exitFailure
    Right Nothing ->
      TIO.putStrLn "No Seihou manifest found. Run 'seihou run <module>' to generate a project."
    Right (Just (manifest, tracked)) -> do
      mEntries <-
        if opts.statusCheckUpdates && not (null manifest.modules)
          then fetchUpdateEntries
          else pure Nothing
      pendings <- detectPendingMigrations manifest
      renderStatus colorEnabled manifest tracked mEntries pendings

-- | Run the update check, catching any IO failure so status still renders.
fetchUpdateEntries :: IO (Maybe [OutdatedEntry])
fetchUpdateEntries = do
  outcome <- try $ do
    searchPaths <- defaultSearchPaths
    modules <- discoverAllModules searchPaths
    checkInstalledModulesForUpdates modules
  case outcome of
    Left (e :: SomeException) -> do
      hPutStrLn stderr $
        "warning: update check failed: " <> show e
      pure Nothing
    Right (entries, _stats) -> pure (Just entries)

-- | Detect pending migrations across all applied modules. Each entry
-- carries the module name and the chain length / target version so the
-- renderer can produce a one-line summary. IO failures (missing
-- module.dhall, eval errors) are silently skipped — pending-migration
-- reporting is best-effort.
detectPendingMigrations :: Manifest -> IO [(ModuleName, MigrationChain)]
detectPendingMigrations manifest =
  fmap
    (\xs -> [(name, c) | (name, Just c) <- xs])
    (mapM check manifest.modules)
  where
    check am = do
      let dhallFile = am.source </> "module.dhall"
      exists <- doesFileExist dhallFile
      if not exists
        then pure (am.name, Nothing)
        else do
          r <- evalModuleFromFile dhallFile
          case r of
            Left _ -> pure (am.name, Nothing)
            Right installed -> pure (am.name, pendingChainFor am installed)

-- | Render the full status output.
renderStatus ::
  Bool ->
  Manifest ->
  [TrackedFile] ->
  Maybe [OutdatedEntry] ->
  [(ModuleName, MigrationChain)] ->
  IO ()
renderStatus color manifest tracked mEntries pendings = do
  TIO.putStrLn "Seihou Status:"
  TIO.putStrLn ""

  let entryMap = case mEntries of
        Just es -> Map.fromList [(e.moduleName, e) | e <- es]
        Nothing -> Map.empty
      pendingMap =
        Map.fromList
          [ (name.unModuleName, chain) | (name, chain) <- pendings
          ]

  -- Recipe provenance
  case manifest.recipe of
    Just ar -> do
      TIO.putStrLn $
        "Recipe: "
          <> ar.name.unRecipeName
          <> maybe "" (\v -> " v" <> v) ar.recipeVersion
      TIO.putStrLn ""
    Nothing -> pure ()

  -- Applied modules
  TIO.putStrLn "Applied modules:"
  if null manifest.modules
    then TIO.putStrLn "  (none)"
    else
      mapM_
        ( \am -> do
            printModule
              color
              (lookupEntry mEntries entryMap am)
              am
            case Map.lookup am.name.unModuleName pendingMap of
              Just chain -> printPendingMigration color am chain
              Nothing -> pure ()
        )
        manifest.modules
  TIO.putStrLn ""

  -- Tracked files
  let fileCount = length tracked
  TIO.putStrLn $ "Tracked files: " <> T.pack (show fileCount)
  if null tracked
    then TIO.putStrLn "  (none)"
    else do
      let maxPathLen = maximum (map (length . (.path)) tracked)
          maxModLen = maximum (map (T.length . displayModuleName . (.moduleName)) tracked)
      mapM_ (printTrackedFile color maxPathLen maxModLen) tracked
  TIO.putStrLn ""

  -- Variables
  let varCount = Map.size manifest.vars
  TIO.putStrLn $ "Variables: " <> T.pack (show varCount) <> " resolved"

  -- Update-check summary line, only when the flag was set.
  case mEntries of
    Nothing -> pure ()
    Just entries -> do
      let total = length entries
          outdated = length (filter (\e -> e.status == OutdatedSt) entries)
      TIO.putStrLn ""
      TIO.putStrLn $
        T.pack (show total)
          <> " module(s) checked, "
          <> T.pack (show outdated)
          <> " outdated."

-- | Classification for an applied module's update status.
data UpdateAnnotation
  = -- | No update check was run at all.
    NoCheck
  | -- | Check ran but this module has no origin metadata.
    NoOrigin
  | -- | The module was checked and produced an entry.
    Entry OutdatedEntry

lookupEntry ::
  Maybe [OutdatedEntry] ->
  Map.Map Text OutdatedEntry ->
  AppliedModule ->
  UpdateAnnotation
lookupEntry Nothing _ _ = NoCheck
lookupEntry (Just _) m am =
  case Map.lookup am.name.unModuleName m of
    Just e -> Entry e
    Nothing -> NoOrigin

-- | Print a single applied module line, optionally with an update annotation.
-- When the applied module carries non-empty parent bindings, append them
-- inline so two invocations of the same module are distinguishable to a
-- reader of `seihou status`.
printModule :: Bool -> UpdateAnnotation -> AppliedModule -> IO ()
printModule color annotation am =
  let verText = case am.moduleVersion of
        Just v -> "  " <> (if color then green ("v" <> v) else "v" <> v)
        Nothing -> ""
      appliedText =
        "    (applied "
          <> T.pack (formatTime defaultTimeLocale "%Y-%m-%d" am.appliedAt)
          <> ")"
      parentVarsText =
        let m = am.parentVars.unParentVars
         in if Map.null m
              then ""
              else
                let pairs =
                      T.intercalate
                        ", "
                        [ vn.unVarName <> "=" <> v
                        | (vn, v) <- Map.toAscList m
                        ]
                    rendered = " [" <> pairs <> "]"
                 in if color then dim rendered else rendered
      updateText = case annotation of
        NoCheck -> ""
        NoOrigin -> "  " <> (if color then dim "(no origin)" else "(no origin)")
        Entry e -> "  " <> renderEntry color e
   in TIO.putStrLn $
        "  "
          <> am.name.unModuleName
          <> parentVarsText
          <> verText
          <> appliedText
          <> updateText

-- | Print the "Pending migrations" sub-line under a module that has a
-- chain available. Indented two spaces past the module line so it
-- visually nests.
printPendingMigration :: Bool -> AppliedModule -> MigrationChain -> IO ()
printPendingMigration color _am chain = do
  let n = length chain.chainSteps
      label =
        T.pack (show n)
          <> " migration(s) pending: "
          <> renderVersion chain.chainFrom
          <> " → "
          <> renderVersion chain.chainTo
  TIO.putStrLn $
    "    "
      <> (if color then yellow ("Pending migrations: " <> label) else "Pending migrations: " <> label)

-- | Render the status portion of an OutdatedEntry as a colored segment.
renderEntry :: Bool -> OutdatedEntry -> Text
renderEntry color e = case e.status of
  UpToDate ->
    if color then dim "up to date" else "up to date"
  OutdatedSt ->
    let avail = maybe "?" id e.availableVersion
        txt = "outdated -> v" <> avail
     in if color then red txt else txt
  Unversioned ->
    if color then dim "unversioned" else "unversioned"
  Unreachable ->
    if color then yellow "unreachable" else "unreachable"

-- | Print a single tracked file line with status.
--
-- File-record module names may carry a @#<hash>@ disambiguator when the
-- owning instance has parent bindings (see 'qualifiedName'). That suffix
-- is an internal key, not something a reader should see; strip it for
-- display so tracked files show the bare module name.
printTrackedFile :: Bool -> Int -> Int -> TrackedFile -> IO ()
printTrackedFile color maxPathLen maxModLen tf = do
  let path = T.pack tf.path
      modName = displayModuleName tf.moduleName
      paddedPath = path <> T.replicate (maxPathLen - T.length path + 3) " "
      paddedMod = modName <> T.replicate (maxModLen - T.length modName + 3) " "
      label = statusLabel tf.status
      colorLabel = if color then statusColor tf.status label else label
  TIO.putStrLn $ "  " <> paddedPath <> paddedMod <> colorLabel

-- | Strip the internal @#<hash>@ disambiguator from a module name for
-- display in user-facing surfaces.
displayModuleName :: ModuleName -> Text
displayModuleName (ModuleName n) = T.takeWhile (/= '#') n

-- | Human-readable label for a file status.
statusLabel :: TrackedFileStatus -> Text
statusLabel TfsUnchanged = "unchanged"
statusLabel TfsModified = "modified by user"
statusLabel TfsDeleted = "deleted by user"

-- | Apply color to a status label.
statusColor :: TrackedFileStatus -> Text -> Text
statusColor TfsUnchanged = dim
statusColor TfsModified = yellow
statusColor TfsDeleted = red
