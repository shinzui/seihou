module Seihou.CLI.Status
  ( handleStatus,
  )
where

import Control.Exception (SomeException, try)
import Data.Text.IO qualified as TIO
import Seihou.CLI.Commands (StatusOpts (..))
import Seihou.CLI.Outdated (checkInstalledModulesForUpdates)
import Seihou.CLI.PendingMigrations (detectPendingMigrations)
import Seihou.CLI.Shared (logIO)
import Seihou.CLI.StatusRender (formatStatus)
import Seihou.CLI.Style (useColor)
import Seihou.CLI.VersionCompare (OutdatedEntry (..))
import Seihou.Core.Module (defaultSearchPaths, discoverAllModules)
import Seihou.Core.Status (computeTrackedFileStatuses)
import Seihou.Core.Types
import Seihou.Effect.FilesystemInterp (runFilesystem)
import Seihou.Effect.Logger (logError)
import Seihou.Effect.ManifestStore (readManifest)
import Seihou.Effect.ManifestStoreInterp (runManifestStore)
import Seihou.Prelude
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
      pendings <- detectPendingMigrations manifest Nothing
      TIO.putStr (formatStatus colorEnabled manifest tracked mEntries pendings)

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
