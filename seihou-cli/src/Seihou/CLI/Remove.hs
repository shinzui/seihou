module Seihou.CLI.Remove
  ( handleRemove,
  )
where

import Control.Monad (foldM, when)
import Data.Set qualified as Set
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Time.Clock (getCurrentTime)
import Seihou.CLI.Commands (RemoveOpts (..))
import Seihou.CLI.Style (bold, dim, green, red, useColor, yellow)
import Seihou.Core.Types
import Seihou.Effect.FilesystemInterp (runFilesystem)
import Seihou.Effect.ManifestStore (readManifest, writeManifest)
import Seihou.Effect.ManifestStoreInterp (runManifestStore)
import Seihou.Engine.Remove
import Seihou.Prelude
import System.Exit (ExitCode (..), exitFailure, exitWith)
import System.IO (hFlush, hIsTerminalDevice, stdin, stdout)

handleRemove :: RemoveOpts -> IO ()
handleRemove opts = do
  let manifestPath = ".seihou" </> "manifest.json"
      modName = opts.removeModule

  -- Read the manifest
  manifestResult <- runEff $ runFilesystem $ runManifestStore manifestPath readManifest
  manifest <- case manifestResult of
    Left err -> do
      TIO.putStrLn $ "Error reading manifest: " <> err
      exitFailure
    Right Nothing -> do
      TIO.putStrLn "No Seihou manifest found. Nothing to remove."
      exitFailure
    Right (Just m) -> pure m

  -- Compute removal plan
  planResult <- runEff $ runFilesystem $ computeRemovalPlan manifest modName
  plan <- case planResult of
    Left (ModuleNotApplied name) -> do
      TIO.putStrLn $ "Module '" <> name.unModuleName <> "' is not applied in this project."
      exitFailure
    Left (ModuleNotRemovable name) -> do
      TIO.putStrLn $
        "Module '"
          <> name.unModuleName
          <> "' has no removal spec. Add a 'removal' section to its module.dhall to make it removable."
      exitFailure
    Right p -> pure p

  colorEnabled <- useColor

  -- Display plan
  let safeFiles = [p | RemovalSafe p <- plan.files]
      conflictFiles = [p | RemovalConflict p <- plan.files]
      goneFiles = [p | RemovalGone p <- plan.files]

  TIO.putStrLn $ "Removal plan for " <> modName.unModuleName <> ":"

  when (not (null safeFiles)) $ do
    mapM_ (\p -> TIO.putStrLn $ "  " <> applyColor colorEnabled green "Delete" <> " " <> T.pack p <> applyColor colorEnabled dim " (unchanged)") safeFiles

  when (not (null conflictFiles)) $ do
    mapM_ (\p -> TIO.putStrLn $ "  " <> applyColor colorEnabled yellow "Delete" <> " " <> T.pack p <> applyColor colorEnabled yellow " (modified by user)") conflictFiles

  when (not (null goneFiles)) $ do
    mapM_ (\p -> TIO.putStrLn $ "  " <> applyColor colorEnabled dim "Skip" <> "   " <> T.pack p <> applyColor colorEnabled dim " (already deleted)") goneFiles

  when (null safeFiles && null conflictFiles && null goneFiles) $ do
    TIO.putStrLn "  (no files to remove)"

  -- Dry run exits here
  when opts.removeDryRun $ exitWith ExitSuccess

  -- Resolve conflicts
  keepSet <-
    if null conflictFiles || opts.removeForce
      then pure Set.empty
      else do
        isInteractive <- hIsTerminalDevice stdin
        if not isInteractive
          then do
            TIO.putStrLn "Conflicted files found. Use --force to delete them non-interactively."
            exitFailure
          else resolveConflictsInteractively conflictFiles

  -- Prompt for confirmation
  when (not (null safeFiles) || (not (null conflictFiles) && (opts.removeForce || Set.size keepSet < length conflictFiles))) $ do
    TIO.putStr "\n  Proceed? [y/N] "
    hFlush stdout
    response <- T.strip . T.pack <$> getLine
    when (T.toLower response /= "y") $
      exitWith (ExitFailure 3)

  -- Execute removal
  now <- getCurrentTime
  updatedManifest <- runEff $ runFilesystem $ executeRemoval manifest plan keepSet now

  -- Write updated manifest
  runEff $ runFilesystem $ runManifestStore manifestPath $ writeManifest updatedManifest

  -- Report
  let deleted = length safeFiles + length conflictFiles - Set.size keepSet
  TIO.putStrLn $
    applyColor colorEnabled green "✓"
      <> " Removed module "
      <> applyColor colorEnabled bold modName.unModuleName
      <> ". Deleted "
      <> T.pack (show deleted)
      <> " file"
      <> (if deleted /= 1 then "s" else "")
      <> "."

-- | Ask the user about each conflicted file interactively.
resolveConflictsInteractively :: [FilePath] -> IO (Set FilePath)
resolveConflictsInteractively paths = do
  TIO.putStrLn "\nThe following files have been modified since generation:"
  foldM askOne Set.empty paths
  where
    askOne keepSet path = do
      TIO.putStr $ "  " <> T.pack path <> " — keep or delete? [k/d] "
      hFlush stdout
      response <- T.strip . T.toLower . T.pack <$> getLine
      if response == "k" || response == "keep"
        then pure (Set.insert path keepSet)
        else pure keepSet

-- | Apply a color function if colors are enabled.
applyColor :: Bool -> (Text -> Text) -> Text -> Text
applyColor True f t = f t
applyColor False _ t = t
