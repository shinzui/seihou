{-# LANGUAGE TemplateHaskell #-}

module Seihou.CLI.Assist
  ( handleAssist,
  )
where

import Data.FileEmbed (embedFile)
import Data.Text.Encoding qualified as TE
import Seihou.CLI.AgentLaunch
import Seihou.CLI.Commands (AssistOpts (..))
import Seihou.Prelude

-- | The prompt template, embedded at compile time from data/assist-prompt.md.
promptTemplate :: Text
promptTemplate = TE.decodeUtf8 $(embedFile "data/assist-prompt.md")

handleAssist :: Bool -> AssistOpts -> IO ()
handleAssist debug assistOpts = do
  ctx <- gatherAgentContext
  let systemPrompt = renderPrompt ctx
  launchAgent debug systemPrompt assistOpts.assistPrompt

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
