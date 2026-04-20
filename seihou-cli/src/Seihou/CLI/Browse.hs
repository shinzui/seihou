module Seihou.CLI.Browse
  ( handleBrowse,
  )
where

import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.BrowseFormat (formatBrowseRegistry, formatBrowseSingleModule)
import Seihou.CLI.Commands (BrowseOpts (..))
import Seihou.CLI.Registry.Sync (checkRegistryVersionDrift)
import Seihou.CLI.Shared (logIO)
import Seihou.Core.Install (parseModuleName)
import Seihou.Core.Registry (Registry (..), RegistryEntry (..), RepoContents (..), discoverRepoContents)
import Seihou.Core.Types
import Seihou.Dhall.Eval (evalModuleFromFile, evalRecipeFromFile, evalRegistryFromFile)
import Seihou.Effect.Logger (logError, logWarn)
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
          Right m ->
            TIO.putStr $ formatBrowseSingleModule source m.name.unModuleName m.description
      SingleRecipe rootDir -> do
        let dhallFile = rootDir </> "recipe.dhall"
        decoded <- evalRecipeFromFile dhallFile
        case decoded of
          Left err -> do
            logIO LogNormal (logError $ "failed to load recipe: " <> T.pack (show err))
            exitFailure
          Right r ->
            TIO.putStr $ formatBrowseSingleModule source r.name.unRecipeName r.description
      MultiModule registry -> do
        driftWarnings <- checkRegistryVersionDrift cloneDir registry
        logIO LogNormal (mapM_ logWarn driftWarnings)
        let filteredMods = case bopts.browseTag of
              Nothing -> registry.modules
              Just tag -> filter (\e -> tag `elem` e.tags) registry.modules
            filteredRecs = case bopts.browseTag of
              Nothing -> registry.recipes
              Just tag -> filter (\e -> tag `elem` e.tags) registry.recipes
        TIO.putStr $ formatBrowseRegistry source registry (filteredMods ++ filteredRecs) bopts.browseTag
