module Seihou.CLI.AgentLaunchExec
  ( launchAgent,
    launchAgentWith,
  )
where

import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.AgentLaunch
  ( agentDirsForSession,
    defaultAllowedTools,
  )
import Seihou.Prelude
import System.Directory (findExecutable)
import System.Exit (ExitCode (..), exitFailure)
import System.Process (rawSystem)

-- | Launch claude with a system prompt, or print it in debug mode.
-- Returns the subprocess exit code so the caller can perform any
-- post-launch bookkeeping (e.g. recording an 'AppliedBlueprint' manifest
-- entry) before exiting.
launchAgent :: Bool -> Text -> Maybe Text -> IO ExitCode
launchAgent debug systemPrompt initialPrompt = do
  addDirs <- agentDirsForSession
  launchAgentWith addDirs defaultAllowedTools debug systemPrompt initialPrompt

-- | Launch claude with custom add-dirs and allowed tools. Returns the
-- subprocess exit code (or 'ExitSuccess' in debug mode); the caller is
-- responsible for propagating the exit status with 'exitWith' once any
-- post-launch work is done.
launchAgentWith :: [FilePath] -> [String] -> Bool -> Text -> Maybe Text -> IO ExitCode
launchAgentWith addDirs tools debug systemPrompt initialPrompt
  | debug = do
      TIO.putStr systemPrompt
      pure ExitSuccess
  | otherwise = do
      claudePath <- findExecutable "claude"
      case claudePath of
        Nothing -> do
          TIO.putStrLn "Error: 'claude' CLI (Claude Code) not found on PATH."
          TIO.putStrLn "Install it from: https://docs.anthropic.com/en/docs/claude-code"
          exitFailure
        Just _ -> do
          let args =
                ["--system-prompt", T.unpack systemPrompt]
                  <> concatMap (\d -> ["--add-dir", d]) addDirs
                  <> concatMap (\t -> ["--allowedTools", t]) tools
                  <> maybe [] (\p -> [T.unpack p]) initialPrompt
          rawSystem "claude" args
