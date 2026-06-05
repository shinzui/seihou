{-# LANGUAGE DerivingStrategies #-}

module Seihou.CLI.AgentCompletion
  ( AgentProvider (..),
    AgentModelConfig (..),
    AgentCompletionRequest (..),
    defaultAgentModelConfig,
    providerFromText,
    providerToText,
    buildAgentCompletionRequest,
    buildBaikaiModel,
    runAgentCompletion,
    responseText,
  )
where

import Baikai qualified
import Baikai.Provider.Claude.Api qualified as ClaudeApi
import Baikai.Provider.Claude.Cli qualified as ClaudeCli
import Baikai.Provider.OpenAI.Api qualified as OpenAIApi
import Baikai.Provider.OpenAI.Cli qualified as CodexCli
import Control.Exception (try)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector qualified as V

data AgentProvider
  = AgentProviderClaudeCli
  | AgentProviderCodexCli
  | AgentProviderAnthropic
  | AgentProviderOpenAI
  deriving stock (Eq, Show)

data AgentModelConfig = AgentModelConfig
  { agentProvider :: AgentProvider,
    agentModel :: Maybe Text
  }
  deriving stock (Eq, Show)

data AgentCompletionRequest = AgentCompletionRequest
  { completionSystemPrompt :: Text,
    completionInitialPrompt :: Maybe Text,
    completionModelConfig :: AgentModelConfig
  }
  deriving stock (Eq, Show)

buildAgentCompletionRequest :: AgentModelConfig -> Text -> Maybe Text -> AgentCompletionRequest
buildAgentCompletionRequest modelConfig systemPrompt initialPrompt =
  AgentCompletionRequest
    { completionSystemPrompt = systemPrompt,
      completionInitialPrompt = initialPrompt,
      completionModelConfig = modelConfig
    }

defaultAgentModelConfig :: AgentModelConfig
defaultAgentModelConfig =
  AgentModelConfig
    { agentProvider = AgentProviderClaudeCli,
      agentModel = Nothing
    }

providerFromText :: Text -> Either Text AgentProvider
providerFromText raw =
  case Text.toLower (Text.strip raw) of
    "claude-cli" -> Right AgentProviderClaudeCli
    "codex-cli" -> Right AgentProviderCodexCli
    "anthropic" -> Right AgentProviderAnthropic
    "openai" -> Right AgentProviderOpenAI
    other ->
      Left $
        "Unknown agent provider '"
          <> other
          <> "'. Expected one of: claude-cli, codex-cli, anthropic, openai."

providerToText :: AgentProvider -> Text
providerToText AgentProviderClaudeCli = "claude-cli"
providerToText AgentProviderCodexCli = "codex-cli"
providerToText AgentProviderAnthropic = "anthropic"
providerToText AgentProviderOpenAI = "openai"

buildBaikaiModel :: AgentModelConfig -> Baikai.Model
buildBaikaiModel config =
  case config.agentProvider of
    AgentProviderClaudeCli ->
      baseCliModel
        { Baikai.modelId = maybe "" id config.agentModel,
          Baikai.name = maybe "Claude CLI default" id config.agentModel,
          Baikai.api = Baikai.AnthropicMessagesCli,
          Baikai.provider = "anthropic"
        }
    AgentProviderCodexCli ->
      baseCliModel
        { Baikai.modelId = maybe "" id config.agentModel,
          Baikai.name = maybe "Codex CLI default" id config.agentModel,
          Baikai.api = Baikai.OpenAICompletionsCli,
          Baikai.provider = "openai"
        }
    AgentProviderAnthropic ->
      Baikai._Model
        { Baikai.modelId = maybe "claude-sonnet-4-6" id config.agentModel,
          Baikai.name = maybe "Claude Sonnet 4.6" id config.agentModel,
          Baikai.api = Baikai.AnthropicMessages,
          Baikai.provider = "anthropic",
          Baikai.baseUrl = "https://api.anthropic.com"
        }
    AgentProviderOpenAI ->
      Baikai._Model
        { Baikai.modelId = maybe "gpt-4o-mini" id config.agentModel,
          Baikai.name = maybe "GPT-4o Mini" id config.agentModel,
          Baikai.api = Baikai.OpenAIChatCompletions,
          Baikai.provider = "openai",
          Baikai.baseUrl = "https://api.openai.com"
        }
  where
    baseCliModel =
      Baikai._Model
        { Baikai.contextWindow = 0,
          Baikai.maxOutputTokens = 0
        }

runAgentCompletion :: AgentCompletionRequest -> IO (Either Text Text)
runAgentCompletion req = do
  registerAgentProviders
  initialMessages <-
    maybe
      (pure V.empty)
      (fmap V.singleton . Baikai.userNow)
      req.completionInitialPrompt
  let model = buildBaikaiModel req.completionModelConfig
      ctx =
        Baikai._Context
          { Baikai.systemPrompt = Just req.completionSystemPrompt,
            Baikai.messages = initialMessages
          }
  result <- try (Baikai.completeRequest model ctx Baikai._Options) :: IO (Either Baikai.BaikaiError Baikai.Response)
  pure $ case result of
    Left err -> Left (Text.pack (show err))
    Right resp ->
      let body = responseText resp
       in if Text.null (Text.strip body)
            then Left "Provider returned no assistant text."
            else Right body

responseText :: Baikai.Response -> Text
responseText =
  Text.intercalate "\n"
    . V.toList
    . V.mapMaybe assistantText
    . Baikai.flattenAssistantBlocks
  where
    assistantText (Baikai.AssistantText (Baikai.TextContent t)) = Just t
    assistantText _ = Nothing

registerAgentProviders :: IO ()
registerAgentProviders = do
  ClaudeCli.register
  CodexCli.register
  ClaudeApi.register
  OpenAIApi.register
