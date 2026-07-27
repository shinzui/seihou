module Seihou.CLI.AgentConfigShow
  ( handleAgentConfigShow,
    formatResolvedAgentConfig,
  )
where

import Data.Generics.Labels ()
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.AgentCompletion (effortToText, providerToText, traceToText)
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
-- provider, model, reasoning effort, and trace destination for every agent
-- command, and print a table labelling the source that supplied each value,
-- followed by the precedence legend.
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
    [ "Resolved agent provider, model, effort, and trace per command",
      "(highest-precedence source wins; see precedence list below)",
      ""
    ]
      <> concatMap renderCommand resolved
      <> ["", precedenceLegend]
  where
    labelWidth = maximum (0 : map (\rcc -> T.length (agentCommandLabel (rcc ^. #command))) resolved)
    valueWidth = maximum (0 : concatMap commandValueWidths resolved)

    commandValueWidths rcc =
      [ T.length (providerValue rcc),
        T.length (modelValue rcc),
        T.length (effortValue rcc),
        T.length (traceValue rcc)
      ]

    providerValue rcc = providerToText (rcc ^. #provider . #value)
    modelValue rcc = maybe "(default)" id (rcc ^. #model . #value)
    effortValue rcc = maybe "(default)" effortToText (rcc ^. #effort . #value)
    traceValue rcc = traceToText (rcc ^. #trace . #value)

    renderCommand rcc =
      let cmd = (rcc ^. #command)
          label = agentCommandLabel cmd
       in [ row
              (padRight labelWidth label)
              "provider"
              (providerValue rcc)
              (agentConfigSourceLabel cmd ProviderField (rcc ^. #provider . #source)),
            row
              (padRight labelWidth "")
              "model   "
              (modelValue rcc)
              (agentConfigSourceLabel cmd ModelField (rcc ^. #model . #source)),
            row
              (padRight labelWidth "")
              "effort  "
              (effortValue rcc)
              (agentConfigSourceLabel cmd EffortField (rcc ^. #effort . #source)),
            row
              (padRight labelWidth "")
              "trace   "
              (traceValue rcc)
              (agentConfigSourceLabel cmd TraceField (rcc ^. #trace . #source))
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
      "  1. --provider / --model / --effort / --trace flag on the subcommand",
      "  2. --provider / --model / --effort / --trace flag on `seihou agent`",
      "  3. SEIHOU_AGENT_PROVIDER / SEIHOU_AGENT_MODEL / SEIHOU_AGENT_EFFORT /",
      "     SEIHOU_AGENT_TRACE environment variables",
      "  4. blueprint.dhall / prompt.dhall       launch.{provider,model,effort}",
      "  5. local  .seihou/config.dhall          agent.<command>.{provider,model,effort,trace}",
      "  6. local  .seihou/config.dhall          agent.{provider,model,effort,trace}",
      "  7. global ~/.config/seihou/config.dhall  agent.<command>.{provider,model,effort,trace}",
      "  8. global ~/.config/seihou/config.dhall  agent.{provider,model,effort,trace}",
      "  9. built-in default: provider claude-cli; model pinned per provider",
      "     (claude-cli -> claude-opus-4-8, codex-cli -> gpt-5.6-terra); effort unset",
      "     (the CLI/provider chooses its own reasoning effort); trace off",
      "",
      "Tier 4 is per-artifact: it depends on which blueprint or prompt you run, so",
      "the table above cannot show it. Run with --verbose to see the resolved",
      "settings and their sources for a specific run. `trace` has no tier-4",
      "declaration: no blueprint or prompt schema field feeds it.",
      "",
      "The trace file path is set with agent.tracePath (local, then global). It is",
      "free-form and has no flag, environment variable, or per-command variant;",
      "unset means .seihou/trace.jsonl."
    ]
