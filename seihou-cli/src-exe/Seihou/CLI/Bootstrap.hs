{-# LANGUAGE TemplateHaskell #-}

module Seihou.CLI.Bootstrap
  ( handleBootstrap,
  )
where

import Data.FileEmbed (embedFile)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Seihou.CLI.AgentLaunch
  ( AgentContext (..),
    agentDirsForSession,
    bootstrapAllowedTools,
    formatAvailableModules,
    formatLocalModules,
    formatManifestState,
    formatModuleDhallState,
    formatSeihouProjectState,
    gatherAgentContext,
    substitute,
  )
import Seihou.CLI.AgentLaunchExec (launchAgentWith)
import Seihou.CLI.Commands (BootstrapOpts (..))
import Seihou.Prelude
import System.Exit (exitWith)

-- | The prompt template, embedded at compile time from data/bootstrap-prompt.md.
promptTemplate :: Text
promptTemplate = TE.decodeUtf8 $(embedFile "data/bootstrap-prompt.md")

handleBootstrap :: Bool -> BootstrapOpts -> IO ()
handleBootstrap debug bootstrapOpts = do
  ctx <- gatherAgentContext
  addDirs <- agentDirsForSession
  let systemPrompt = renderPrompt ctx bootstrapOpts
  exitCode <-
    launchAgentWith addDirs bootstrapAllowedTools debug systemPrompt bootstrapOpts.bootstrapPrompt
  exitWith exitCode

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
