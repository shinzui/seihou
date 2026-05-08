{-# LANGUAGE TemplateHaskell #-}

module Seihou.CLI.Setup
  ( handleSetup,
  )
where

import Data.FileEmbed (embedFile)
import Data.Text.Encoding qualified as TE
import Seihou.CLI.AgentLaunch
  ( AgentContext (..),
    agentDirsForSession,
    formatAvailableModules,
    formatLocalModules,
    formatManifestState,
    formatModuleDhallState,
    formatSeihouProjectState,
    gatherAgentContext,
    setupAllowedTools,
    substitute,
  )
import Seihou.CLI.AgentLaunchExec (launchAgentWith)
import Seihou.CLI.Commands (SetupOpts (..))
import Seihou.Prelude
import System.Exit (exitWith)

-- | The prompt template, embedded at compile time from data/setup-prompt.md.
promptTemplate :: Text
promptTemplate = TE.decodeUtf8 $(embedFile "data/setup-prompt.md")

handleSetup :: Bool -> SetupOpts -> IO ()
handleSetup debug setupOpts = do
  ctx <- gatherAgentContext
  addDirs <- agentDirsForSession
  let systemPrompt = renderPrompt ctx
  exitCode <-
    launchAgentWith addDirs setupAllowedTools debug systemPrompt setupOpts.setupPrompt
  exitWith exitCode

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
