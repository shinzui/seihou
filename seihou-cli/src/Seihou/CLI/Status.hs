module Seihou.CLI.Status
  ( handleStatus,
  )
where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Time.Format (defaultTimeLocale, formatTime)
import Effectful
import Seihou.CLI.Shared (logIO)
import Seihou.CLI.Style (dim, green, red, useColor, yellow)
import Seihou.Core.Status (computeTrackedFileStatuses)
import Seihou.Core.Types
import Seihou.Effect.FilesystemInterp (runFilesystem)
import Seihou.Effect.Logger (logError)
import Seihou.Effect.ManifestStore (readManifest)
import Seihou.Effect.ManifestStoreInterp (runManifestStore)
import System.Exit (exitFailure)
import System.FilePath ((</>))

handleStatus :: IO ()
handleStatus = do
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
    Right (Just (manifest, tracked)) ->
      renderStatus colorEnabled manifest tracked

-- | Render the full status output.
renderStatus :: Bool -> Manifest -> [TrackedFile] -> IO ()
renderStatus color manifest tracked = do
  TIO.putStrLn "Seihou Status:"
  TIO.putStrLn ""

  -- Applied modules
  TIO.putStrLn "Applied modules:"
  if null (manifestModules manifest)
    then TIO.putStrLn "  (none)"
    else mapM_ (printModule color) (manifestModules manifest)
  TIO.putStrLn ""

  -- Tracked files
  let fileCount = length tracked
  TIO.putStrLn $ "Tracked files: " <> T.pack (show fileCount)
  if null tracked
    then TIO.putStrLn "  (none)"
    else do
      let maxPathLen = maximum (map (length . trackedPath) tracked)
          maxModLen = maximum (map (T.length . unModuleName . trackedModule) tracked)
      mapM_ (printTrackedFile color maxPathLen maxModLen) tracked
  TIO.putStrLn ""

  -- Variables
  let varCount = Map.size (manifestVars manifest)
  TIO.putStrLn $ "Variables: " <> T.pack (show varCount) <> " resolved"

-- | Print a single applied module line.
printModule :: Bool -> AppliedModule -> IO ()
printModule _color am =
  TIO.putStrLn $
    "  "
      <> unModuleName (appliedName am)
      <> "    (applied "
      <> T.pack (formatTime defaultTimeLocale "%Y-%m-%d" (appliedAt am))
      <> ")"

-- | Print a single tracked file line with status.
printTrackedFile :: Bool -> Int -> Int -> TrackedFile -> IO ()
printTrackedFile color maxPathLen maxModLen tf = do
  let path = T.pack (trackedPath tf)
      modName = unModuleName (trackedModule tf)
      paddedPath = path <> T.replicate (maxPathLen - T.length path + 3) " "
      paddedMod = modName <> T.replicate (maxModLen - T.length modName + 3) " "
      label = statusLabel (trackedStatus tf)
      colorLabel = if color then statusColor (trackedStatus tf) label else label
  TIO.putStrLn $ "  " <> paddedPath <> paddedMod <> colorLabel

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
