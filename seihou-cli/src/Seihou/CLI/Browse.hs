module Seihou.CLI.Browse
  ( handleBrowse,
  )
where

import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.Commands (BrowseOpts (..))
import Seihou.CLI.Shared (logIO)
import Seihou.Core.Install (parseModuleName)
import Seihou.Core.Module (validateModule)
import Seihou.Core.Registry (Registry (..), RegistryEntry (..), RepoContents (..), discoverRepoContents)
import Seihou.Core.Types
import Seihou.Dhall.Eval (evalModuleFromFile, evalRegistryFromFile)
import Seihou.Effect.Logger (logError)
import Seihou.Prelude
import System.Exit (ExitCode (..), exitFailure)
import System.IO.Temp (withSystemTempDirectory)
import System.Process (readProcessWithExitCode)

handleBrowse :: BrowseOpts -> IO ()
handleBrowse bopts = do
  let source = bopts.browseSource

  withSystemTempDirectory "seihou-browse" $ \tmpDir -> do
    let repoName = parseModuleName source
        cloneDir = tmpDir </> repoName

    -- Shallow clone
    (exitCode, _stdout, stderr) <- readProcessWithExitCode "git" ["clone", "--depth", "1", T.unpack source, cloneDir] ""
    case exitCode of
      ExitFailure _ -> do
        logIO LogNormal $ do
          logError $ "git clone failed for '" <> source <> "'."
          logError $ "  " <> T.pack stderr
        exitFailure
      ExitSuccess -> pure ()

    contents <- discoverRepoContents evalRegistryFromFile cloneDir
    case contents of
      EmptyRepo -> do
        logIO LogNormal (logError "repository contains neither seihou-registry.dhall nor module.dhall.")
        exitFailure
      SingleModule rootDir -> do
        let dhallFile = rootDir </> "module.dhall"
        decoded <- evalModuleFromFile dhallFile
        case decoded of
          Left err -> do
            logIO LogNormal (logError $ "failed to load module: " <> T.pack (show err))
            exitFailure
          Right m -> do
            TIO.putStrLn $ m.name.unModuleName
            case m.description of
              Just desc -> TIO.putStrLn $ "  " <> desc
              Nothing -> pure ()
            TIO.putStrLn ""
            TIO.putStrLn "Single-module repository. Install with:"
            TIO.putStrLn $ "  seihou install " <> source
      MultiModule registry -> do
        let filtered = case bopts.browseTag of
              Nothing -> registry.modules
              Just tag -> filter (\e -> tag `elem` e.tags) registry.modules

        TIO.putStrLn $ registry.repoName
        case registry.repoDescription of
          Just desc -> TIO.putStrLn desc
          Nothing -> pure ()
        TIO.putStrLn ""

        if null filtered
          then TIO.putStrLn $
            case bopts.browseTag of
              Just tag -> "No modules matching tag '" <> tag <> "'."
              Nothing -> "No modules in registry."
          else do
            TIO.putStrLn "Available modules:"
            TIO.putStrLn ""
            let maxNameLen = maximum (map (T.length . (.name.unModuleName)) filtered)
            mapM_ (printEntry maxNameLen) filtered
            TIO.putStrLn ""
            let n = length filtered
                noun = if n == 1 then "module" else "modules"
            TIO.putStrLn $ T.pack (show n) <> " " <> noun <> " available. Install with:"
            TIO.putStrLn $ "  seihou install " <> source <> " --module <name>"
            TIO.putStrLn $ "  seihou install " <> source <> " --all"

printEntry :: Int -> RegistryEntry -> IO ()
printEntry maxNameLen entry = do
  let name = entry.name.unModuleName
      padding = T.replicate (maxNameLen - T.length name + 3) " "
      desc = maybe "" id entry.description
      tagsText =
        if null entry.tags
          then ""
          else "  [" <> T.intercalate ", " entry.tags <> "]"
  TIO.putStrLn $ "  " <> name <> padding <> desc <> tagsText
