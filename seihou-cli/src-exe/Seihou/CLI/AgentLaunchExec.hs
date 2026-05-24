module Seihou.CLI.AgentLaunchExec
  ( launchConfiguredAgent,
    launchConfiguredAgentWith,
  )
where

import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.AgentCompletion (AgentModelConfig (..), AgentProvider (..))
import Seihou.CLI.AgentLaunch (agentDirsForSession)
import Seihou.Prelude
import System.Directory (findExecutable, getCurrentDirectory)
import System.Exit (ExitCode (..), exitFailure)
import System.Process (rawSystem)

launchConfiguredAgent :: AgentModelConfig -> [String] -> Bool -> Text -> Maybe Text -> IO ExitCode
launchConfiguredAgent modelConfig tools debug systemPrompt initialPrompt = do
  addDirs <- agentDirsForSession
  launchConfiguredAgentWith addDirs modelConfig tools debug systemPrompt initialPrompt

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
      let args =
            ["--system-prompt", T.unpack systemPrompt]
              <> maybe [] (\m -> ["--model", T.unpack m]) model
              <> concatMap (\d -> ["--add-dir", d]) addDirs
              <> concatMap (\t -> ["--allowedTools", t]) tools
              <> maybe [] (\p -> [T.unpack p]) initialPrompt
      rawSystem "claude" args

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
      let args =
            maybe [] (\m -> ["--model", T.unpack m]) model
              <> ["--ask-for-approval", "on-request"]
              <> ["--sandbox", "workspace-write"]
              <> ["--cd", cwd]
              <> concatMap (\d -> ["--add-dir", d]) addDirs
              <> [T.unpack (codexInitialPrompt systemPrompt initialPrompt)]
      rawSystem "codex" args

codexInitialPrompt :: Text -> Maybe Text -> Text
codexInitialPrompt systemPrompt initialPrompt =
  T.strip $
    T.unlines $
      [systemPrompt]
        <> maybe [] (\p -> ["", "## Initial user request", p]) initialPrompt

unsupportedInteractiveProvider :: Text -> IO ExitCode
unsupportedInteractiveProvider providerName = do
  TIO.putStrLn $
    "Error: provider '"
      <> providerName
      <> "' is an API provider and cannot start an interactive local agent session."
  TIO.putStrLn "Use --provider claude-cli or --provider codex-cli for interactive agent sessions."
  exitFailure
