{-# LANGUAGE TemplateHaskell #-}

module Seihou.CLI.Setup
  ( handleSetup,
  )
where

import Data.FileEmbed (embedFile)
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Seihou.CLI.AgentCompletion
  ( AgentModelConfig,
    buildAgentCompletionRequest,
    runAgentCompletion,
  )
import Seihou.CLI.AgentLaunch
  ( AgentContext (..),
    formatAvailableModules,
    formatLocalModules,
    formatManifestState,
    formatModuleDhallState,
    formatSeihouProjectState,
    gatherAgentContext,
    substitute,
  )
import Seihou.CLI.Commands (SetupOpts (..))
import Seihou.Prelude
import System.Exit (exitFailure)

-- | The prompt template, embedded at compile time from data/setup-prompt.md.
promptTemplate :: Text
promptTemplate = TE.decodeUtf8 $(embedFile "data/setup-prompt.md")

handleSetup :: Bool -> AgentModelConfig -> SetupOpts -> IO ()
handleSetup debug modelConfig setupOpts = do
  ctx <- gatherAgentContext
  let systemPrompt = renderPrompt ctx
  runRenderedAgentPrompt debug modelConfig systemPrompt setupOpts.setupPrompt

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
  | otherwise = do
      result <- runAgentCompletion (buildAgentCompletionRequest modelConfig systemPrompt initialPrompt)
      case result of
        Right assistantText -> TIO.putStrLn assistantText
        Left err -> do
          TIO.putStrLn $ "Error: " <> err
          exitFailure
