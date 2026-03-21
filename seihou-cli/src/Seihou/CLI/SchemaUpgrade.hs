module Seihou.CLI.SchemaUpgrade
  ( handleSchemaUpgrade,
  )
where

import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.Commands (SchemaUpgradeOpts (..))
import Seihou.CLI.SchemaVersion (schemaHash, schemaUrl)
import Seihou.CLI.Style (dim, green, yellow)
import Seihou.Core.Module (DiscoveredModule (..), defaultSearchPaths, discoverAllModules)
import Seihou.Core.SchemaUpgrade
import Seihou.Prelude
import System.Directory (doesFileExist, getCurrentDirectory)
import System.Exit (exitFailure)

handleSchemaUpgrade :: SchemaUpgradeOpts -> IO ()
handleSchemaUpgrade opts
  | opts.schemaUpgradeAll = do
      searchPaths <- defaultSearchPaths
      modules <- discoverAllModules searchPaths
      let paths = [dir </> "module.dhall" | DiscoveredModule {discoveredDir = dir} <- modules]
      results <- mapM (processModule opts.schemaUpgradeDryRun) paths
      printSummary results
  | otherwise = do
      moduleDir <- case opts.schemaUpgradePath of
        Just p -> pure p
        Nothing -> getCurrentDirectory
      let dhallFile = moduleDir </> "module.dhall"
      exists <- doesFileExist dhallFile
      if not exists
        then do
          TIO.putStrLn $ "Error: " <> T.pack dhallFile <> " not found."
          exitFailure
        else do
          results <- sequence [processModule opts.schemaUpgradeDryRun dhallFile]
          printSummary results

data ProcessResult
  = UpToDate FilePath
  | Fixed FilePath [UpgradeIssue]
  | WouldFix FilePath [UpgradeIssue]
  | ProcessError FilePath Text

processModule :: Bool -> FilePath -> IO ProcessResult
processModule dryRun path = do
  exists <- doesFileExist path
  if not exists
    then pure (ProcessError path "file not found")
    else do
      content <- TIO.readFile path
      case upgradeModuleText schemaUrl schemaHash content of
        AlreadyCurrent -> pure (UpToDate path)
        Upgraded newContent issues
          | dryRun -> do
              printDryRun path issues
              pure (WouldFix path issues)
          | otherwise -> do
              TIO.writeFile path newContent
              printFixed path issues
              pure (Fixed path issues)

printDryRun :: FilePath -> [UpgradeIssue] -> IO ()
printDryRun path issues = do
  TIO.putStrLn $ yellow "[dry run] " <> T.pack path
  mapM_ (\i -> TIO.putStrLn $ "  Would fix: " <> issueMessage i) issues

printFixed :: FilePath -> [UpgradeIssue] -> IO ()
printFixed path issues = do
  let count = length issues
      label = if count == 1 then " issue" else " issues"
  TIO.putStrLn $ green "  ✓ " <> T.pack path <> " — " <> T.pack (show count) <> label <> " fixed"
  mapM_ (\i -> TIO.putStrLn $ "    + " <> issueMessage i) issues

printSummary :: [ProcessResult] -> IO ()
printSummary results = do
  let total = length results
      fixed = length [() | Fixed {} <- results]
      wouldFix = length [() | WouldFix {} <- results]
      upToDate = length [() | UpToDate {} <- results]
      errors = length [() | ProcessError {} <- results]
  TIO.putStrLn ""
  if fixed > 0
    then TIO.putStrLn $ green (T.pack (show fixed) <> " upgraded") <> dim (", " <> T.pack (show upToDate) <> " already current, " <> T.pack (show total) <> " total")
    else
      if wouldFix > 0
        then TIO.putStrLn $ yellow (T.pack (show wouldFix) <> " would be upgraded") <> dim (", " <> T.pack (show upToDate) <> " already current, " <> T.pack (show total) <> " total")
        else TIO.putStrLn $ green "All modules up to date." <> dim (" (" <> T.pack (show total) <> " checked)")
  if errors > 0
    then do
      TIO.putStrLn $ T.pack (show errors) <> " errors:"
      mapM_ (\case ProcessError p msg -> TIO.putStrLn $ "  " <> T.pack p <> ": " <> msg; _ -> pure ()) results
    else pure ()
