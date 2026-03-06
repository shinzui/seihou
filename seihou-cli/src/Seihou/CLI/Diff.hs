module Seihou.CLI.Diff
  ( handleDiff,
    formatDiffOutput,
  )
where

import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.Shared (logIO)
import Seihou.CLI.Style (dim, red, useColor, yellow)
import Seihou.Core.Status (computeTrackedFileStatuses)
import Seihou.Core.Types
import Seihou.Effect.FilesystemInterp (runFilesystem)
import Seihou.Effect.Logger (logError)
import Seihou.Effect.ManifestStore (readManifest)
import Seihou.Effect.ManifestStoreInterp (runManifestStore)
import Seihou.Prelude
import System.Exit (exitFailure)

handleDiff :: IO ()
handleDiff = do
  let manifestPath = ".seihou" </> "manifest.json"

  result <- runEff $ runFilesystem $ runManifestStore manifestPath $ do
    mResult <- readManifest
    case mResult of
      Left err -> pure (Left err)
      Right Nothing -> pure (Right Nothing)
      Right (Just manifest) -> do
        tracked <- computeTrackedFileStatuses manifest
        pure (Right (Just tracked))

  colorEnabled <- useColor

  case result of
    Left err -> do
      logIO LogNormal (logError $ "Error reading manifest: " <> err)
      exitFailure
    Right Nothing ->
      TIO.putStrLn "No Seihou manifest found. Run 'seihou run <module>' to generate a project."
    Right (Just tracked) ->
      TIO.putStr (formatDiffOutput colorEnabled tracked)

formatDiffOutput :: Bool -> [TrackedFile] -> Text
formatDiffOutput color tracked =
  let modified = filter (\t -> trackedStatus t == TfsModified) tracked
      deleted = filter (\t -> trackedStatus t == TfsDeleted) tracked
      unchanged = filter (\t -> trackedStatus t == TfsUnchanged) tracked
      nMod = length modified
      nDel = length deleted
      nUnch = length unchanged
      changed = modified ++ deleted
   in if null changed
        then "No changes since last generation.\n"
        else
          let maxPathLen = maximum (map (length . trackedPath) changed)
              header = "Seihou Diff:\n"
              fileLines = map (formatLine color maxPathLen) changed
              summary =
                "  "
                  <> T.pack (show nUnch)
                  <> " unchanged, "
                  <> T.pack (show nMod)
                  <> " modified, "
                  <> T.pack (show nDel)
                  <> " deleted\n"
           in header <> "\n" <> T.unlines fileLines <> "\n" <> summary

formatLine :: Bool -> Int -> TrackedFile -> Text
formatLine color maxPathLen tf =
  let (label, colorFn) = case trackedStatus tf of
        TfsModified -> ("modified", yellow)
        TfsDeleted -> ("deleted ", red)
        TfsUnchanged -> ("unchanged", dim)
      path = T.pack (trackedPath tf)
      modName = unModuleName (trackedModule tf)
      paddedLabel = if color then colorFn label else label
      paddedPath = path <> T.replicate (maxPathLen - T.length path + 3) " "
      modAttr = if color then dim ("(" <> modName <> ")") else "(" <> modName <> ")"
   in "  " <> paddedLabel <> "   " <> paddedPath <> modAttr
