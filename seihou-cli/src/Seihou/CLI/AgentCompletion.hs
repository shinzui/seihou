{-# LANGUAGE DerivingStrategies #-}

module Seihou.CLI.AgentCompletion
  ( AgentProvider (..),
    AgentModelConfig (..),
    AgentCompletionRequest (..),
    defaultAgentModelConfig,
    defaultModelForProvider,
    providerFromText,
    providerToText,
    effortFromText,
    effortToText,
    buildAgentCompletionRequest,
    buildBaikaiModel,
    runAgentCompletion,
    responseText,
  )
where

import Baikai qualified
import Baikai.Options qualified as BaikaiOptions
import Baikai.Provider.Claude.Api qualified as ClaudeApi
import Baikai.Provider.Claude.Cli qualified as ClaudeCli
import Baikai.Provider.OpenAI.Api qualified as OpenAIApi
import Baikai.Provider.OpenAI.Cli qualified as CodexCli
import Baikai.ThinkingLevel (ThinkingLevel (..), renderThinkingLevel)
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
    agentModel :: Maybe Text,
    -- | Reasoning effort. 'Nothing' leaves the provider/CLI default alone.
    agentEffort :: Maybe ThinkingLevel
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
      agentModel = Nothing,
      agentEffort = Nothing
    }

-- | Parse a reasoning-effort level name (case-insensitive) into a Baikai
-- 'ThinkingLevel'. Accepts the six canonical Baikai level names.
effortFromText :: Text -> Either Text ThinkingLevel
effortFromText raw =
  case Text.toLower (Text.strip raw) of
    "minimal" -> Right ThinkingMinimal
    "low" -> Right ThinkingLow
    "medium" -> Right ThinkingMedium
    "high" -> Right ThinkingHigh
    "xhigh" -> Right ThinkingXHigh
    "max" -> Right ThinkingMax
    other ->
      Left $
        "Unknown reasoning effort '"
          <> other
          <> "'. Expected one of: minimal, low, medium, high, xhigh, max."

-- | Render a 'ThinkingLevel' to its canonical name (via Baikai).
effortToText :: ThinkingLevel -> Text
effortToText = renderThinkingLevel

-- | The deterministic default model for a provider when the user has configured
-- none. The two local CLI providers pin a specific model so a @seihou agent@
-- session never inherits whatever model the ambient @claude@ or @codex@ session
-- happens to have active — that would be non-deterministic and could silently
-- run a token-hungry model another session left selected. The API providers
-- return 'Nothing' here; they already send an explicit model chosen in
-- 'buildBaikaiModel', so they are deterministic without a pinned default.
defaultModelForProvider :: AgentProvider -> Maybe Text
defaultModelForProvider AgentProviderClaudeCli = Just "claude-opus-4-8"
defaultModelForProvider AgentProviderCodexCli = Just "gpt-5.6-terra"
defaultModelForProvider AgentProviderAnthropic = Nothing
defaultModelForProvider AgentProviderOpenAI = Nothing

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
      Baikai.emptyModel
        { Baikai.modelId = maybe "claude-sonnet-4-6" id config.agentModel,
          Baikai.name = maybe "Claude Sonnet 4.6" id config.agentModel,
          Baikai.api = Baikai.AnthropicMessages,
          Baikai.provider = "anthropic",
          Baikai.baseUrl = "https://api.anthropic.com"
        }
    AgentProviderOpenAI ->
      Baikai.emptyModel
        { Baikai.modelId = maybe "gpt-4o-mini" id config.agentModel,
          Baikai.name = maybe "GPT-4o Mini" id config.agentModel,
          Baikai.api = Baikai.OpenAIChatCompletions,
          Baikai.provider = "openai",
          Baikai.baseUrl = "https://api.openai.com"
        }
  where
    baseCliModel =
      Baikai.emptyModel
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
        Baikai.emptyContext
          { Baikai.systemPrompt = Just req.completionSystemPrompt,
            Baikai.messages = initialMessages
          }
      options = Baikai.emptyOptions {BaikaiOptions.thinking = req.completionModelConfig.agentEffort}
  result <- try (Baikai.completeRequest model ctx options) :: IO (Either Baikai.BaikaiError Baikai.Response)
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
