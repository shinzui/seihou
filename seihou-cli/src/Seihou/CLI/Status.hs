module Seihou.CLI.Status
  ( handleStatus,
  )
where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Effectful
import Seihou.CLI.Shared (logIO)
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

  result <- runEff $ runFilesystem $ runManifestStore manifestPath readManifest

  case result of
    Left err -> do
      logIO LogNormal (logError $ "Error reading manifest: " <> err)
      exitFailure
    Right Nothing ->
      TIO.putStrLn "No manifest found. Run 'seihou run <module>' first."
    Right (Just manifest) -> do
      TIO.putStrLn $ "Seihou manifest (v" <> T.pack (show (manifestVersion manifest)) <> ")"
      TIO.putStrLn $ "Generated at: " <> T.pack (show (manifestGenAt manifest))
      TIO.putStrLn ""

      -- Modules
      TIO.putStrLn "Modules:"
      if null (manifestModules manifest)
        then TIO.putStrLn "  (none)"
        else mapM_ printModule (manifestModules manifest)
      TIO.putStrLn ""

      -- Variables
      let vars = manifestVars manifest
      TIO.putStrLn $ "Variables: " <> T.pack (show (Map.size vars))
      mapM_ (\(k, v) -> TIO.putStrLn $ "  " <> unVarName k <> " = " <> v) (Map.toAscList vars)
      TIO.putStrLn ""

      -- Files
      let files = manifestFiles manifest
      TIO.putStrLn $ "Files: " <> T.pack (show (Map.size files))
      mapM_ (\(path, _) -> TIO.putStrLn $ "  " <> T.pack path) (Map.toAscList files)
  where
    printModule am =
      TIO.putStrLn $
        "  "
          <> unModuleName (appliedName am)
          <> " (from "
          <> T.pack (appliedSource am)
          <> ")"
