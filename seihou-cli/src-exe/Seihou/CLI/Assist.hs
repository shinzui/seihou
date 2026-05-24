{-# LANGUAGE TemplateHaskell #-}

module Seihou.CLI.Assist
  ( handleAssist,
  )
where

import Data.FileEmbed (embedFile)
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
    defaultAllowedTools,
    formatAvailableModules,
    formatLocalModules,
    formatManifestState,
    formatModuleDhallState,
    formatSeihouProjectState,
    gatherAgentContext,
    substitute,
  )
import Seihou.CLI.AgentLaunchExec (launchConfiguredAgent)
import Seihou.CLI.Commands (AssistOpts (..))
import Seihou.Prelude
import System.Exit (exitFailure, exitWith)

-- | The prompt template, embedded at compile time from data/assist-prompt.md.
promptTemplate :: Text
promptTemplate = TE.decodeUtf8 $(embedFile "data/assist-prompt.md")

handleAssist :: Bool -> AgentModelConfig -> AssistOpts -> IO ()
handleAssist debug modelConfig assistOpts = do
  ctx <- gatherAgentContext
  let systemPrompt = renderPrompt ctx
  runRenderedAgentPrompt debug modelConfig systemPrompt assistOpts.assistPrompt

renderPrompt :: AgentContext -> Text
renderPrompt ctx =
  substitute
    [ ("cwd", ctx.cwd),
      ("seihou_project_state", formatSeihouProjectState ctx),
      ("manifest_state", formatManifestState ctx),
      ("module_dhall_state", formatModuleDhallState ctx),
      ("local_modules", formatLocalModules ctx),
      ("available_modules", formatAvailableModules ctx)
    ]
    promptTemplate

runRenderedAgentPrompt :: Bool -> AgentModelConfig -> Text -> Maybe Text -> IO ()
runRenderedAgentPrompt debug modelConfig systemPrompt initialPrompt
  | debug = TIO.putStr systemPrompt
  | modelConfig.agentProvider == AgentProviderClaudeCli || modelConfig.agentProvider == AgentProviderCodexCli = do
      exitCode <- launchConfiguredAgent modelConfig defaultAllowedTools debug systemPrompt initialPrompt
      exitWith exitCode
  | otherwise = do
      result <- runAgentCompletion (buildAgentCompletionRequest modelConfig systemPrompt initialPrompt)
      case result of
        Right assistantText -> TIO.putStrLn assistantText
        Left err -> do
          TIO.putStrLn $ "Error: " <> err
          exitFailure
