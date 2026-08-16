module Seihou.CLI.Status
  ( handleStatus,
  )
where

import Control.Exception (SomeException, try)
import Data.Generics.Labels ()
import Data.Maybe (maybeToList)
import Data.Text.IO qualified as TIO
import Seihou.CLI.Commands (StatusOpts (..))
import Seihou.CLI.ManifestGuard (ArtifactCheck, checkAppliedArtifacts, checkAppliedBlueprint)
import Seihou.CLI.Outdated (checkInstalledModulesForUpdates)
import Seihou.CLI.PendingMigrations (detectPendingMigrations)
import Seihou.CLI.Shared (logIO)
import Seihou.CLI.StatusRender (formatArtifactChecks, formatStatus)
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
import System.Directory (getCurrentDirectory)
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
        if opts ^. #statusCheckUpdates && not (null (manifest ^. #modules))
          then fetchUpdateEntries
          else pure Nothing
      pendings <- detectPendingMigrations manifest Nothing
      TIO.putStr (formatStatus colorEnabled manifest tracked mEntries pendings)
      -- Report, never fail: a stale or mismatched module makes 'seihou run'
      -- refuse, and this is where a developer finds out before that happens.
      -- Any IO failure while checking is swallowed for the same reason.
      guardChecks <- fetchArtifactChecks manifest
      TIO.putStr (formatArtifactChecks colorEnabled guardChecks)

-- | Compare every recorded artifact against this machine, catching any IO
-- failure so status still renders. An empty list means "nothing to report",
-- which is also what a failed check yields — @seihou status@ must not turn a
-- reporting problem into an exit code.
--
-- The recorded blueprint is checked alongside the recorded modules. A stale
-- or substituted blueprint makes @seihou agent run@ and @seihou agent
-- migrate@ refuse, so this is where a developer finds out before that
-- happens — the same reason the module checks are here.
fetchArtifactChecks :: Manifest -> IO [ArtifactCheck]
fetchArtifactChecks manifest = do
  outcome <- try $ do
    projectRoot <- getCurrentDirectory
    searchPaths <- defaultSearchPaths
    moduleChecks <- checkAppliedArtifacts projectRoot searchPaths manifest
    blueprintCheck <- checkAppliedBlueprint projectRoot searchPaths manifest
    pure (moduleChecks <> maybeToList blueprintCheck)
  case outcome of
    Left (e :: SomeException) -> do
      hPutStrLn stderr ("warning: artifact check failed: " <> show e)
      pure []
    Right checks -> pure checks

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
