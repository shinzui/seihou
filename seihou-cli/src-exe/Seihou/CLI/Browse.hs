module Seihou.CLI.Browse
  ( handleBrowse,
  )
where

import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.BrowseFormat (formatBrowseRegistry, formatBrowseSingleBlueprint, formatBrowseSingleModule, formatBrowseSinglePrompt)
import Seihou.CLI.Commands (BrowseOpts (..))
import Seihou.CLI.Registry.Sync (checkRegistryVersionDrift)
import Seihou.CLI.Shared (logIO)
import Seihou.Core.Install (parseModuleName)
import Seihou.Core.Registry (EntryKind (..), Registry (..), RegistryEntry (..), RepoContents (..), discoverRepoContents)
import Seihou.Core.Types
import Seihou.Dhall.Eval (evalAgentPromptFromFile, evalBlueprintFromFile, evalModuleFromFile, evalRecipeFromFile, evalRegistryFromFile)
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
      SingleBlueprint rootDir -> do
        let dhallFile = rootDir </> "blueprint.dhall"
        decoded <- evalBlueprintFromFile dhallFile
        case decoded of
          Left err -> do
            logIO LogNormal (logError $ "failed to load blueprint: " <> T.pack (show err))
            exitFailure
          Right b -> do
            let bpName = case b of Blueprint nm _ _ _ _ _ _ _ _ _ -> nm
                bpDesc = case b of Blueprint _ _ d _ _ _ _ _ _ _ -> d
            TIO.putStr $ formatBrowseSingleBlueprint source bpName.unModuleName bpDesc
      SinglePrompt rootDir -> do
        let dhallFile = rootDir </> "prompt.dhall"
        decoded <- evalAgentPromptFromFile dhallFile
        case decoded of
          Left err -> do
            logIO LogNormal (logError $ "failed to load prompt: " <> T.pack (show err))
            exitFailure
          Right p ->
            TIO.putStr $ formatBrowseSinglePrompt source p.name.unModuleName p.description
      MultiModule registry -> do
        driftWarnings <- checkRegistryVersionDrift cloneDir registry
        logIO LogNormal (mapM_ logWarn driftWarnings)
        let matchTag e = case bopts.browseTag of
              Nothing -> True
              Just tag -> tag `elem` e.tags
            tagged =
              [(ModuleEntry, e) | e <- registry.modules, matchTag e]
                ++ [(RecipeEntry, e) | e <- registry.recipes, matchTag e]
                ++ [(BlueprintEntry, e) | e <- registry.blueprints, matchTag e]
                ++ [(PromptEntry, e) | e <- registry.prompts, matchTag e]
        TIO.putStr $ formatBrowseRegistry source registry tagged bopts.browseTag
