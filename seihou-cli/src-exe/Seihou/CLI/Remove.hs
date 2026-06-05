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
import Seihou.CLI.Style (bold, dim, green, useColor, yellow)
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

  -- Find the module's removal spec
  let mApplied = findAppliedModule manifest modName
  case mApplied of
    Nothing -> do
      TIO.putStrLn $ "Module '" <> modName.unModuleName <> "' is not applied in this project."
      exitFailure
    Just am -> case am.removal of
      Nothing -> do
        TIO.putStrLn $
          "Module '"
            <> modName.unModuleName
            <> "' has no removal spec. Add a 'removal' section to its module.dhall to make it removable."
        exitFailure
      Just removal -> do
        -- Build removal plan from declared steps
        planResult <- runEff $ runFilesystem $ buildRemovalOps manifest modName removal
        plan <- case planResult of
          Left (ModuleNotApplied name) -> do
            TIO.putStrLn $ "Module '" <> name.unModuleName <> "' is not applied in this project."
            exitFailure
          Left (ModuleNotRemovable name) -> do
            TIO.putStrLn $
              "Module '"
                <> name.unModuleName
                <> "' has no removal spec."
            exitFailure
          Left (RemovalUnsafePath label path reason) -> do
            TIO.putStrLn $
              "Unsafe removal "
                <> label
                <> " '"
                <> path
                <> "': "
                <> reason
            exitFailure
          Right p -> pure p

        colorEnabled <- useColor

        -- Display plan
        TIO.putStrLn $ "Removal plan for " <> modName.unModuleName <> ":"

        if null plan.ops
          then TIO.putStrLn "  (no removal operations)"
          else mapM_ (displayOp colorEnabled) plan.ops

        -- Dry run exits here
        when opts.removeDryRun $ do
          TIO.putStrLn ""
          TIO.putStrLn $ applyColor colorEnabled dim "(dry run — no changes made)"
          exitWith ExitSuccess

        -- Collect conflict files for interactive resolution
        let conflictFiles = [p | DeleteFileOp p RFConflict <- plan.ops]

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

        -- Prompt for confirmation (if there are any actionable ops)
        let actionableOps = [() | op <- plan.ops, isActionable op]
        when (not (null actionableOps)) $ do
          TIO.putStr "\n  Proceed? [y/N] "
          hFlush stdout
          response <- T.strip . T.pack <$> getLine
          when (T.toLower response /= "y") $
            exitWith (ExitFailure 3)

        -- Execute removal
        now <- getCurrentTime
        updatedManifest <- runEff $ runFilesystem $ executeRemovalOps manifest plan keepSet now

        -- Write updated manifest
        runEff $ runFilesystem $ runManifestStore manifestPath $ writeManifest updatedManifest

        -- Report
        let deleted = length [() | DeleteFileOp _ s <- plan.ops, s /= RFGone, not (Set.member "" keepSet)]
            stripped = length [() | StripSectionOp _ <- plan.ops]
            commands = length [() | RemovalCommandOp _ _ <- plan.ops]
        TIO.putStrLn $
          applyColor colorEnabled green "✓"
            <> " Removed module "
            <> applyColor colorEnabled bold modName.unModuleName
            <> "."
            <> formatCounts deleted stripped commands

-- | Display a single removal operation.
displayOp :: Bool -> RemovalOp -> IO ()
displayOp c (DeleteFileOp path RFSafe) =
  TIO.putStrLn $ "  " <> applyColor c green "Delete" <> " " <> T.pack path <> applyColor c dim " (unchanged)"
displayOp c (DeleteFileOp path RFConflict) =
  TIO.putStrLn $ "  " <> applyColor c yellow "Delete" <> " " <> T.pack path <> applyColor c yellow " (modified by user)"
displayOp c (DeleteFileOp path RFGone) =
  TIO.putStrLn $ "  " <> applyColor c dim "Skip" <> "   " <> T.pack path <> applyColor c dim " (already deleted)"
displayOp c (StripSectionOp path) =
  TIO.putStrLn $ "  " <> applyColor c green "Strip" <> "  " <> T.pack path <> applyColor c dim " (remove section)"
displayOp c (RewriteOp path _) =
  TIO.putStrLn $ "  " <> applyColor c green "Rewrite" <> " " <> T.pack path
displayOp c (RemovalCommandOp cmd _) =
  TIO.putStrLn $ "  " <> applyColor c green "Run" <> "    " <> cmd

-- | Check if a removal op does something (not just skip).
isActionable :: RemovalOp -> Bool
isActionable (DeleteFileOp _ RFGone) = False
isActionable _ = True

-- | Format a summary of counts.
formatCounts :: Int -> Int -> Int -> Text
formatCounts 0 0 0 = ""
formatCounts d s c =
  " "
    <> T.intercalate
      ", "
      ( filter
          (not . T.null)
          [ if d > 0 then T.pack (show d) <> " file" <> plural d <> " deleted" else "",
            if s > 0 then T.pack (show s) <> " section" <> plural s <> " stripped" else "",
            if c > 0 then T.pack (show c) <> " command" <> plural c <> " run" else ""
          ]
      )
    <> "."
  where
    plural n = if n /= 1 then "s" else ""

-- | Find an applied module by name in the manifest.
findAppliedModule :: Manifest -> ModuleName -> Maybe AppliedModule
findAppliedModule manifest modName =
  case filter (\am -> am.name == modName) manifest.modules of
    (am : _) -> Just am
    [] -> Nothing

-- | Ask the user about each conflicted file interactively.
resolveConflictsInteractively :: [FilePath] -> IO (Set.Set FilePath)
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
