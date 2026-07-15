module Seihou.CLI.AgentModels
  ( availableAgentModels,
    providersForModel,
    filterAgentModels,
    formatAgentModels,
  )
where

import Baikai.Model (Model)
import Baikai.Model qualified as BaikaiModel
import Baikai.Models.Generated qualified as Models
import Data.List (sortOn)
import Data.Text (Text)
import Data.Text qualified as Text
import Seihou.CLI.AgentCompletion
  ( AgentProvider (..),
    providerToText,
  )

availableAgentModels :: [Model]
availableAgentModels =
  [ Models.anthropic_claude_fable_5,
    Models.anthropic_claude_haiku_4_5,
    Models.anthropic_claude_opus_4_5,
    Models.anthropic_claude_opus_4_6,
    Models.anthropic_claude_opus_4_7,
    Models.anthropic_claude_opus_4_8,
    Models.anthropic_claude_sonnet_4_5,
    Models.anthropic_claude_sonnet_4_6,
    Models.anthropic_claude_sonnet_5,
    Models.openai_gpt_4_1,
    Models.openai_gpt_4_1_mini,
    Models.openai_gpt_4_1_nano,
    Models.openai_gpt_4o,
    Models.openai_gpt_4o_mini,
    Models.openai_gpt_5,
    Models.openai_gpt_5_1,
    Models.openai_gpt_5_2,
    Models.openai_gpt_5_4,
    Models.openai_gpt_5_4_mini,
    Models.openai_gpt_5_4_nano,
    Models.openai_gpt_5_5,
    Models.openai_gpt_5_6,
    Models.openai_gpt_5_6_luna,
    Models.openai_gpt_5_6_sol,
    Models.openai_gpt_5_6_terra,
    Models.openai_gpt_5_mini,
    Models.openai_gpt_5_nano,
    Models.openai_o1,
    Models.openai_o3,
    Models.openai_o3_mini,
    Models.openai_o4_mini
  ]

providersForModel :: Model -> [AgentProvider]
providersForModel model =
  case BaikaiModel.provider model of
    "anthropic" -> [AgentProviderAnthropic, AgentProviderClaudeCli]
    "openai" -> [AgentProviderOpenAI, AgentProviderCodexCli]
    _ -> []

filterAgentModels :: Maybe AgentProvider -> [Model] -> [Model]
filterAgentModels Nothing = id
filterAgentModels (Just provider) =
  filter (elem provider . providersForModel)

formatAgentModels :: Maybe AgentProvider -> [Model] -> Text
formatAgentModels providerFilter models =
  Text.unlines $
    [ "Available agent models:",
      "",
      formatRow modelWidth nameWidth "MODEL" "NAME" "PROVIDERS"
    ]
      <> map formatModel sortedModels
      <> [ "",
           Text.pack (show (length sortedModels)) <> " models found.",
           "Provider-specific aliases and custom model IDs remain accepted by --model."
         ]
  where
    sortedModels =
      sortOn
        (\model -> (BaikaiModel.provider model, BaikaiModel.modelId model))
        (filterAgentModels providerFilter models)
    modelWidth = maximum (Text.length "MODEL" : map (Text.length . BaikaiModel.modelId) sortedModels)
    nameWidth = maximum (Text.length "NAME" : map (Text.length . BaikaiModel.name) sortedModels)
    formatModel model =
      formatRow
        modelWidth
        nameWidth
        (BaikaiModel.modelId model)
        (BaikaiModel.name model)
        (Text.intercalate ", " (map providerToText (providersForModel model)))

formatRow :: Int -> Int -> Text -> Text -> Text -> Text
formatRow modelWidth nameWidth model name providers =
  padRight modelWidth model
    <> "  "
    <> padRight nameWidth name
    <> "  "
    <> providers

padRight :: Int -> Text -> Text
padRight width value = value <> Text.replicate (width - Text.length value) " "
