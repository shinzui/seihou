module Seihou.CLI.AgentConfigShow
  ( handleAgentConfigShow,
    formatResolvedAgentConfig,
  )
where

import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.AgentCompletion (effortToText, providerToText)
import Seihou.CLI.AgentConfig
  ( AgentField (..),
    ResolvedAgentField (..),
    ResolvedCommandConfig (..),
    agentCommandLabel,
    agentConfigSourceLabel,
    loadResolvedAgentConfig,
  )
import Seihou.Prelude
import System.Exit (exitFailure)

-- | @seihou agent config@: read the real environment and config, resolve the
-- provider, model, and reasoning effort for every agent command, and print a
-- table labelling the source that supplied each value, followed by the
-- precedence legend.
handleAgentConfigShow :: IO ()
handleAgentConfigShow = do
  result <- loadResolvedAgentConfig
  case result of
    Left err -> do
      TIO.putStrLn $ "Error: " <> err
      exitFailure
    Right resolved -> TIO.putStr (formatResolvedAgentConfig resolved)

-- | Render the resolved per-command configuration as the displayed block. Pure,
-- so it is unit-testable without touching the filesystem.
formatResolvedAgentConfig :: [ResolvedCommandConfig] -> Text
formatResolvedAgentConfig resolved =
  T.unlines $
    [ "Resolved agent provider, model, and effort per command",
      "(highest-precedence source wins; see precedence list below)",
      ""
    ]
      <> concatMap renderCommand resolved
      <> ["", precedenceLegend]
  where
    labelWidth = maximum (0 : map (\rcc -> T.length (agentCommandLabel rcc.rccCommand)) resolved)
    valueWidth = maximum (0 : concatMap commandValueWidths resolved)

    commandValueWidths rcc =
      [ T.length (providerValue rcc),
        T.length (modelValue rcc),
        T.length (effortValue rcc)
      ]

    providerValue rcc = providerToText rcc.rccProvider.resolvedValue
    modelValue rcc = maybe "(default)" id rcc.rccModel.resolvedValue
    effortValue rcc = maybe "(default)" effortToText rcc.rccEffort.resolvedValue

    renderCommand rcc =
      let cmd = rcc.rccCommand
          label = agentCommandLabel cmd
       in [ row
              (padRight labelWidth label)
              "provider"
              (providerValue rcc)
              (agentConfigSourceLabel cmd ProviderField rcc.rccProvider.resolvedSource),
            row
              (padRight labelWidth "")
              "model   "
              (modelValue rcc)
              (agentConfigSourceLabel cmd ModelField rcc.rccModel.resolvedSource),
            row
              (padRight labelWidth "")
              "effort  "
              (effortValue rcc)
              (agentConfigSourceLabel cmd EffortField rcc.rccEffort.resolvedSource)
          ]

    row label field value sourceLabel =
      "  "
        <> label
        <> "  "
        <> field
        <> "  "
        <> padRight valueWidth value
        <> "  ["
        <> sourceLabel
        <> "]"

padRight :: Int -> Text -> Text
padRight width value = value <> T.replicate (max 0 (width - T.length value)) " "

precedenceLegend :: Text
precedenceLegend =
  T.intercalate
    "\n"
    [ "Precedence, highest first:",
      "  1. --provider / --model / --effort flag on the subcommand",
      "  2. --provider / --model / --effort flag on `seihou agent`",
      "  3. SEIHOU_AGENT_PROVIDER / SEIHOU_AGENT_MODEL / SEIHOU_AGENT_EFFORT environment variables",
      "  4. local  .seihou/config.dhall          agent.<command>.{provider,model,effort}",
      "  5. local  .seihou/config.dhall          agent.{provider,model,effort}",
      "  6. global ~/.config/seihou/config.dhall  agent.<command>.{provider,model,effort}",
      "  7. global ~/.config/seihou/config.dhall  agent.{provider,model,effort}",
      "  8. built-in default: provider claude-cli; model pinned per provider",
      "     (claude-cli -> claude-opus-4-8, codex-cli -> gpt-5.6-terra); effort unset",
      "     (the CLI/provider chooses its own reasoning effort)"
    ]
