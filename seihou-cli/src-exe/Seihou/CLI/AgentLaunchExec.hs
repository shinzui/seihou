module Seihou.CLI.AgentLaunchExec
  ( launchConfiguredAgent,
    launchConfiguredAgentAddingDirs,
    launchConfiguredAgentWith,
  )
where

import Baikai.Interactive
  ( CodexApprovalPolicy (CodexApprovalOnRequest),
    CodexSandboxMode (CodexWorkspaceWrite),
    InteractiveLaunchResult (..),
    InteractiveSafety (ClaudeAllowedTools, CodexSandbox),
    extraDirs,
    interactiveLaunchRequest,
    modelId,
    safety,
    systemPrompt,
    workingDir,
  )
import Baikai.Kit.Session qualified as KitSession
import Baikai.Provider.Claude.Interactive
  ( defaultClaudeInteractiveConfig,
    launchClaudeInteractive,
  )
import Baikai.Provider.OpenAI.Interactive
  ( defaultCodexInteractiveConfig,
    launchCodexInteractive,
  )
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.AgentCompletion (AgentModelConfig (..), AgentProvider (..))
import Seihou.CLI.Kit (seihouKitConfig)
import Seihou.Prelude
import System.Directory (findExecutable, getCurrentDirectory)
import System.Exit (ExitCode (..), exitFailure)

launchConfiguredAgent :: AgentModelConfig -> [String] -> Bool -> Text -> Maybe Text -> IO ExitCode
launchConfiguredAgent = launchConfiguredAgentAddingDirs []

launchConfiguredAgentAddingDirs :: [FilePath] -> AgentModelConfig -> [String] -> Bool -> Text -> Maybe Text -> IO ExitCode
launchConfiguredAgentAddingDirs extraDirs modelConfig tools debug systemPrompt initialPrompt = do
  sessionDirs <- KitSession.agentDirsForSession seihouKitConfig
  launchConfiguredAgentWith (sessionDirs <> extraDirs) modelConfig tools debug systemPrompt initialPrompt

launchConfiguredAgentWith :: [FilePath] -> AgentModelConfig -> [String] -> Bool -> Text -> Maybe Text -> IO ExitCode
launchConfiguredAgentWith addDirs modelConfig tools debug systemPrompt initialPrompt
  | debug = do
      TIO.putStr systemPrompt
      pure ExitSuccess
  | otherwise =
      case modelConfig.agentProvider of
        AgentProviderClaudeCli ->
          launchClaude addDirs tools modelConfig.agentModel systemPrompt initialPrompt
        AgentProviderCodexCli ->
          launchCodex addDirs modelConfig.agentModel systemPrompt initialPrompt
        AgentProviderAnthropic ->
          unsupportedInteractiveProvider "anthropic"
        AgentProviderOpenAI ->
          unsupportedInteractiveProvider "openai"

launchClaude :: [FilePath] -> [String] -> Maybe Text -> Text -> Maybe Text -> IO ExitCode
launchClaude addDirs tools model systemPrompt initialPrompt = do
  claudePath <- findExecutable "claude"
  case claudePath of
    Nothing -> do
      TIO.putStrLn "Error: 'claude' CLI (Claude Code) not found on PATH."
      TIO.putStrLn "Install it from: https://docs.anthropic.com/en/docs/claude-code"
      exitFailure
    Just _ -> do
      cwd <- getCurrentDirectory
      InteractiveLaunchResult {exitCode} <-
        launchClaudeInteractive
          defaultClaudeInteractiveConfig
          (interactiveLaunchRequest (promptOrEmpty initialPrompt))
            { systemPrompt = Just systemPrompt,
              modelId = model,
              workingDir = Just cwd,
              extraDirs = addDirs,
              safety = ClaudeAllowedTools (map T.pack tools)
            }
      pure exitCode

launchCodex :: [FilePath] -> Maybe Text -> Text -> Maybe Text -> IO ExitCode
launchCodex addDirs model systemPrompt initialPrompt = do
  codexPath <- findExecutable "codex"
  case codexPath of
    Nothing -> do
      TIO.putStrLn "Error: 'codex' CLI not found on PATH."
      TIO.putStrLn "Install and authenticate Codex CLI, then retry."
      exitFailure
    Just _ -> do
      cwd <- getCurrentDirectory
      InteractiveLaunchResult {exitCode} <-
        launchCodexInteractive
          defaultCodexInteractiveConfig
          (interactiveLaunchRequest (promptOrEmpty initialPrompt))
            { systemPrompt = Just systemPrompt,
              modelId = model,
              workingDir = Just cwd,
              extraDirs = addDirs,
              safety = CodexSandbox CodexWorkspaceWrite CodexApprovalOnRequest
            }
      pure exitCode

promptOrEmpty :: Maybe Text -> Text
promptOrEmpty = maybe "" id

unsupportedInteractiveProvider :: Text -> IO ExitCode
unsupportedInteractiveProvider providerName = do
  TIO.putStrLn $
    "Error: provider '"
      <> providerName
      <> "' is an API provider and cannot start an interactive local agent session."
  TIO.putStrLn "Use --provider claude-cli or --provider codex-cli for interactive agent sessions."
  exitFailure
