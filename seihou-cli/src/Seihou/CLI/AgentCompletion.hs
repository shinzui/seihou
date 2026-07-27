{-# LANGUAGE DerivingStrategies #-}

module Seihou.CLI.AgentCompletion
  ( AgentProvider (..),
    AgentModelConfig (..),
    AgentCompletionRequest (..),
    TraceSetting (..),
    defaultAgentModelConfig,
    defaultModelForProvider,
    providerFromText,
    providerToText,
    effortFromText,
    effortToText,
    traceFromText,
    traceToText,
    buildAgentCompletionRequest,
    buildBaikaiModel,
    runAgentCompletion,
    runAgentCompletionWithCliAccess,
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
import System.Directory (getCurrentDirectory)

data AgentProvider
  = AgentProviderClaudeCli
  | AgentProviderCodexCli
  | AgentProviderAnthropic
  | AgentProviderOpenAI
  deriving stock (Eq, Show)

-- | Where trace events for a model call should go.
--
-- Baikai emits a small stream of 'Baikai.Trace.Event.TraceEvent' values per
-- call — one when the call starts, one when it finishes or fails — carrying
-- the provider, model, elapsed milliseconds, token counts, and dollar cost.
-- This closed vocabulary names the four destinations Seihou exposes, rather
-- than exposing Baikai's composable @TraceSink@ surface (a streamly fold),
-- which no config string could express.
data TraceSetting
  = -- | Emit nothing. The default, and byte-for-byte the historical behavior.
    TraceOff
  | -- | Append one JSON object per line to the resolved trace file.
    TraceFile
  | -- | Print one human-readable line per event to stdout.
    TraceStdout
  | -- | Print one human-readable line per event to stderr.
    TraceStderr
  deriving stock (Eq, Show)

data AgentModelConfig = AgentModelConfig
  { agentProvider :: AgentProvider,
    agentModel :: Maybe Text,
    -- | Reasoning effort. 'Nothing' leaves the provider/CLI default alone.
    agentEffort :: Maybe ThinkingLevel,
    -- | Where call traces go. 'TraceOff' emits nothing.
    agentTrace :: TraceSetting,
    -- | The configured @agent.tracePath@, when set. 'Nothing' means the
    -- built-in default path is used by the file sink.
    agentTracePath :: Maybe FilePath
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
      agentEffort = Nothing,
      agentTrace = TraceOff,
      agentTracePath = Nothing
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

-- | Parse a trace-destination name (case-insensitive) into a 'TraceSetting'.
traceFromText :: Text -> Either Text TraceSetting
traceFromText raw =
  case Text.toLower (Text.strip raw) of
    "off" -> Right TraceOff
    "file" -> Right TraceFile
    "stdout" -> Right TraceStdout
    "stderr" -> Right TraceStderr
    other ->
      Left $
        "Unknown trace setting '"
          <> other
          <> "'. Expected one of: off, file, stdout, stderr."

-- | Render a 'TraceSetting' to its canonical name.
traceToText :: TraceSetting -> Text
traceToText TraceOff = "off"
traceToText TraceFile = "file"
traceToText TraceStdout = "stdout"
traceToText TraceStderr = "stderr"

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
runAgentCompletion = runAgentCompletionWith registerAgentProviders

-- | Run a completion while granting local CLI providers access to the current
-- workspace and mounted blueprint references. API providers ignore this local
-- access configuration. This is the non-interactive counterpart to the
-- interactive launcher used by normal @seihou agent run@ sessions.
runAgentCompletionWithCliAccess :: [FilePath] -> [String] -> AgentCompletionRequest -> IO (Either Text Text)
runAgentCompletionWithCliAccess extraDirs tools =
  runAgentCompletionWith (registerAgentProvidersWithCliAccess extraDirs tools)

runAgentCompletionWith :: IO () -> AgentCompletionRequest -> IO (Either Text Text)
runAgentCompletionWith registerProviders req = do
  registerProviders
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

registerAgentProvidersWithCliAccess :: [FilePath] -> [String] -> IO ()
registerAgentProvidersWithCliAccess extraDirs tools = do
  cwd <- getCurrentDirectory
  Baikai.registerApiProvider $
    ClaudeCli.claudeCliProvider
      ClaudeCli.defaultClaudeCliConfig
        { ClaudeCli.workingDir = Just cwd,
          ClaudeCli.extraArgs = claudeAccessArgs extraDirs tools
        }
  Baikai.registerApiProvider $
    CodexCli.codexCliProvider
      CodexCli.defaultCodexCliConfig
        { CodexCli.workingDir = Just cwd,
          CodexCli.extraArgs = codexAccessArgs extraDirs
        }
  ClaudeApi.register
  OpenAIApi.register

claudeAccessArgs :: [FilePath] -> [String] -> [Text]
claudeAccessArgs extraDirs tools =
  ( if null tools
      then []
      else ["--allowedTools", Text.intercalate "," (map Text.pack tools)]
  )
    <> concatMap (\dir -> ["--add-dir", Text.pack dir]) extraDirs

codexAccessArgs :: [FilePath] -> [Text]
codexAccessArgs extraDirs =
  ["--sandbox", "workspace-write"]
    <> concatMap (\dir -> ["--add-dir", Text.pack dir]) extraDirs
