{-# LANGUAGE TemplateHaskell #-}

module Seihou.CLI.Bootstrap
  ( handleBootstrap,
  )
where

import Data.FileEmbed (embedFile)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Seihou.CLI.AgentCompletion
  ( AgentModelConfig (..),
    AgentProvider (..),
    buildAgentCompletionRequest,
    runAgentCompletion,
  )
import Seihou.CLI.AgentLaunch
  ( AgentContext (..),
    bootstrapAllowedTools,
    formatAvailableModules,
    formatLocalModules,
    formatManifestState,
    formatModuleDhallState,
    formatSeihouProjectState,
    gatherAgentContext,
    substitute,
  )
import Seihou.CLI.AgentLaunchExec (launchConfiguredAgent)
import Seihou.CLI.Commands (BootstrapOpts (..))
import Seihou.Prelude
import System.Exit (exitFailure, exitWith)

-- | The prompt template, embedded at compile time from data/bootstrap-prompt.md.
promptTemplate :: Text
promptTemplate = TE.decodeUtf8 $(embedFile "data/bootstrap-prompt.md")

handleBootstrap :: Bool -> AgentModelConfig -> BootstrapOpts -> IO ()
handleBootstrap debug modelConfig bootstrapOpts = do
  ctx <- gatherAgentContext
  let systemPrompt = renderPrompt ctx bootstrapOpts
  runRenderedAgentPrompt debug modelConfig systemPrompt bootstrapOpts.bootstrapPrompt

renderPrompt :: AgentContext -> BootstrapOpts -> Text
renderPrompt ctx bootstrapOpts =
  substitute
    [ ("cwd", ctx.cwd),
      ("seihou_project_state", formatSeihouProjectState ctx),
      ("manifest_state", formatManifestState ctx),
      ("module_dhall_state", formatModuleDhallState ctx),
      ("local_modules", formatLocalModules ctx),
      ("available_modules", formatAvailableModules ctx),
      ("bootstrap_mode", bootstrapMode bootstrapOpts)
    ]
    promptTemplate

runRenderedAgentPrompt :: Bool -> AgentModelConfig -> Text -> Maybe Text -> IO ()
runRenderedAgentPrompt debug modelConfig systemPrompt initialPrompt
  | debug = TIO.putStr systemPrompt
  | modelConfig.agentProvider == AgentProviderClaudeCli || modelConfig.agentProvider == AgentProviderCodexCli = do
      exitCode <- launchConfiguredAgent modelConfig bootstrapAllowedTools debug systemPrompt initialPrompt
      exitWith exitCode
  | otherwise = do
      result <- runAgentCompletion (buildAgentCompletionRequest modelConfig systemPrompt initialPrompt)
      case result of
        Right assistantText -> TIO.putStrLn assistantText
        Left err -> do
          TIO.putStrLn $ "Error: " <> err
          exitFailure

bootstrapMode :: BootstrapOpts -> Text
bootstrapMode opts
  | opts.bootstrapRepo =
      T.unlines
        [ "**Mode: Multi-module repository**",
          "",
          "You are bootstrapping a multi-module repository. This means:",
          "- Create a `seihou-registry.dhall` at the repository root",
          "- Organize modules under a `modules/` directory",
          "- Each module gets its own `module.dhall` and `files/` subdirectory",
          "- Modules can declare dependencies on each other",
          "- Add meaningful tags to each registry entry for discoverability",
          "",
          "Start by asking what modules the repository should contain, then create",
          "them one by one before writing the registry file."
        ]
  | otherwise =
      T.unlines
        [ "**Mode: Single module**",
          "",
          "You are bootstrapping a single Seihou module. Ask the user what kind of",
          "project they want to scaffold, then create a complete module with variables,",
          "templates, prompts, and validation."
        ]
