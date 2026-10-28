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
    buildAgentCompletionRequestWith,
    buildBaikaiModel,
    runAgentCompletion,
    runAgentCompletionWithCliAccess,
    runAgentMigrationCompletionWithCliAccess,
    resolveAgentInitialPrompt,
    migrationAllowedTools,
    runAgentCompletionWith,
    responseText,
  )
where

import Baikai qualified
import Baikai.Kit.Session qualified as KitSession
import Baikai.Options qualified as BaikaiOptions
import Baikai.Provider.Claude.Api qualified as ClaudeApi
import Baikai.Provider.Claude.Cli qualified as ClaudeCli
import Baikai.Provider.OpenAI.Api qualified as OpenAIApi
import Baikai.Provider.OpenAI.Cli qualified as CodexCli
import Baikai.Response qualified as BaikaiResponse
import Baikai.ThinkingLevel (ThinkingLevel (..), renderThinkingLevel)
import Baikai.Trace qualified as BaikaiTrace
import Baikai.Trace.Sink (TraceSink, silent)
import Control.Exception (IOException, throwIO, try)
import Control.Lens ((&), (.~), (^.))
import Data.Generics.Labels ()
import Data.List (nub)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TE
import Data.Vector qualified as V
import GHC.Generics (Generic)
import Seihou.CLI.AgentMigrationProtocol (validateMigrationOutput)
import Seihou.CLI.KitConfig (seihouKitConfig)
import System.Directory (getCurrentDirectory)
import System.Exit (ExitCode (..))
import System.Process qualified as Process

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
  { provider :: !AgentProvider,
    model :: !(Maybe Text),
    -- | Reasoning effort. 'Nothing' leaves the provider/CLI default alone.
    effort :: !(Maybe ThinkingLevel),
    -- | Where call traces go. 'TraceOff' emits nothing.
    trace :: !TraceSetting,
    -- | The configured @agent.tracePath@, when set. 'Nothing' means the
    -- built-in default path is used by the file sink.
    tracePath :: !(Maybe FilePath)
  }
  deriving stock (Eq, Generic, Show)

-- | Note the absence of 'Eq' and 'Show': 'TraceSink' wraps a streamly fold,
-- which is a function and so has neither. Tests compare the inspectable fields
-- individually.
data AgentCompletionRequest = AgentCompletionRequest
  { systemPrompt :: !Text,
    initialPrompt :: !(Maybe Text),
    modelConfig :: !AgentModelConfig,
    -- | Where this call's trace events go. Baikai's 'silent' sink when tracing
    -- is off, which is the default and costs nothing.
    traceSink :: !TraceSink
  }
  deriving stock (Generic)

-- | Build a request that emits no trace events.
buildAgentCompletionRequest :: AgentModelConfig -> Text -> Maybe Text -> AgentCompletionRequest
buildAgentCompletionRequest = buildAgentCompletionRequestWith silent

-- | Build a request whose model call reports to the given sink. Construct the
-- sink with 'Seihou.CLI.AgentTrace.traceSinkFor'; build it once per command
-- rather than per call, so a command that makes several calls appends them all
-- to the same destination.
buildAgentCompletionRequestWith ::
  TraceSink ->
  AgentModelConfig ->
  Text ->
  Maybe Text ->
  AgentCompletionRequest
buildAgentCompletionRequestWith sink modelConfig systemPrompt initialPrompt =
  AgentCompletionRequest
    { systemPrompt = systemPrompt,
      initialPrompt = initialPrompt,
      modelConfig = modelConfig,
      traceSink = sink
    }

defaultAgentModelConfig :: AgentModelConfig
defaultAgentModelConfig =
  AgentModelConfig
    { provider = AgentProviderClaudeCli,
      model = Nothing,
      effort = Nothing,
      trace = TraceOff,
      tracePath = Nothing
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
  case config ^. #provider of
    AgentProviderClaudeCli ->
      baseCliModel
        { Baikai.modelId = maybe "" id (config ^. #model),
          Baikai.name = maybe "Claude CLI default" id (config ^. #model),
          Baikai.api = Baikai.AnthropicMessagesCli,
          Baikai.provider = "anthropic"
        }
    AgentProviderCodexCli ->
      baseCliModel
        { Baikai.modelId = maybe "" id (config ^. #model),
          Baikai.name = maybe "Codex CLI default" id (config ^. #model),
          Baikai.api = Baikai.OpenAICompletionsCli,
          Baikai.provider = "openai"
        }
    AgentProviderAnthropic ->
      Baikai.emptyModel
        { Baikai.modelId = maybe "claude-sonnet-4-6" id (config ^. #model),
          Baikai.name = maybe "Claude Sonnet 4.6" id (config ^. #model),
          Baikai.api = Baikai.AnthropicMessages,
          Baikai.provider = "anthropic",
          Baikai.baseUrl = "https://api.anthropic.com"
        }
    AgentProviderOpenAI ->
      Baikai.emptyModel
        { Baikai.modelId = maybe "gpt-4o-mini" id (config ^. #model),
          Baikai.name = maybe "GPT-4o Mini" id (config ^. #model),
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

-- | The shared implementation behind 'runAgentCompletion' and
-- 'runAgentCompletionWithCliAccess', parameterised by which providers to
-- register. Exported so tests can install a stub provider in place of a real
-- one; production callers should use one of the two wrappers.
runAgentCompletionWith :: IO () -> AgentCompletionRequest -> IO (Either Text Text)
runAgentCompletionWith = runAgentCompletionUsing (Text.pack . show)

runAgentCompletionUsing :: (Baikai.BaikaiError -> Text) -> IO () -> AgentCompletionRequest -> IO (Either Text Text)
runAgentCompletionUsing renderError registerProviders req = do
  registerProviders
  initialMessages <-
    maybe
      (pure V.empty)
      (fmap V.singleton . Baikai.userNow)
      (resolveAgentInitialPrompt (req ^. #modelConfig . #provider) (req ^. #initialPrompt))
  let model = buildBaikaiModel (req ^. #modelConfig)
      ctx =
        Baikai.emptyContext
          { Baikai.systemPrompt = Just (req ^. #systemPrompt),
            Baikai.messages = initialMessages
          }
      options = Baikai.emptyOptions {BaikaiOptions.thinking = req ^. #modelConfig . #effort}
  result <-
    try (BaikaiTrace.withTrace (req ^. #traceSink) model ctx options) ::
      IO (Either Baikai.BaikaiError Baikai.Response)
  pure $ case result of
    -- Retained deliberately. 'withTrace' does not throw for provider failures,
    -- but its doc comment states that downstream-of-the-fold exceptions still
    -- propagate — an unwritable trace path, for instance.
    Left err -> Left (renderError err)
    Right resp -> case BaikaiResponse.responseError resp of
      -- 'withTrace' surfaces a provider failure as an error-shaped Response
      -- rather than an exception, and such a response has no assistant text.
      -- Without this branch every provider error — a bad API key, a rate
      -- limit, an unknown model — would fall through to the empty-text guard
      -- below and be reported as "Provider returned no assistant text.",
      -- losing the message the user needs. Formatting matches the exception
      -- branch exactly, so the text a user sees is what it always was.
      Just err -> Left (renderError err)
      Nothing ->
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
  sessionArgs <- KitSession.codexSessionArgs seihouKitConfig
  Baikai.registerApiProvider $
    CodexCli.codexCliProvider (CodexCli.defaultCodexCliConfig & #extraArgs .~ sessionArgs)
  ClaudeApi.register
  OpenAIApi.register

registerAgentProvidersWithCliAccess :: [FilePath] -> [String] -> IO ()
registerAgentProvidersWithCliAccess extraDirs tools = do
  cwd <- getCurrentDirectory
  sessionArgs <- KitSession.codexSessionArgs seihouKitConfig
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
          CodexCli.extraArgs = codexAccessArgs extraDirs <> sessionArgs
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

-- | CLI transports need a user turn even when all instructions live in the
-- system prompt. Preserve explicit instructions and API semantics.
resolveAgentInitialPrompt :: AgentProvider -> Maybe Text -> Maybe Text
resolveAgentInitialPrompt provider prompt = case provider of
  AgentProviderClaudeCli -> cliPrompt
  AgentProviderCodexCli -> cliPrompt
  AgentProviderAnthropic -> prompt
  AgentProviderOpenAI -> prompt
  where
    cliPrompt = case prompt of
      Just value | not (Text.null (Text.strip value)) -> prompt
      _ -> Just "Follow the instructions in the system prompt."

-- | A migration must retain raw process/protocol failures until classification.
-- Register this narrow adapter behind the usual trace wrapper, so it emits to
-- the command's existing sink and ordinary completion callers remain unchanged.
runAgentMigrationCompletionWithCliAccess :: [FilePath] -> [String] -> AgentCompletionRequest -> IO (Either Text Text)
runAgentMigrationCompletionWithCliAccess dirs tools req =
  case req ^. #modelConfig . #provider of
    AgentProviderClaudeCli -> runAgentCompletionUsing (^. #message) (registerStrict Baikai.AnthropicMessagesCli) req
    AgentProviderCodexCli -> runAgentCompletionUsing (^. #message) (registerStrict Baikai.OpenAICompletionsCli) req
    _ -> runAgentCompletion req
  where
    registerStrict api = do
      cwd <- getCurrentDirectory
      sessionArgs <- KitSession.codexSessionArgs seihouKitConfig
      let complete m ctx options = do
            let (exe, args) = case req ^. #modelConfig . #provider of
                  AgentProviderClaudeCli ->
                    ClaudeCli.claudeCliCommand
                      (ClaudeCli.defaultClaudeCliConfig {ClaudeCli.extraArgs = ["--permission-mode", "acceptEdits"] <> claudeAccessArgs dirs (migrationAllowedTools tools)})
                      m
                      ctx
                      options
                  _ ->
                    CodexCli.codexCliCommand
                      (CodexCli.defaultCodexCliConfig {CodexCli.extraArgs = codexAccessArgs dirs <> sessionArgs})
                      m
                      ctx
                      options
            attempted <-
              try
                ( Process.readCreateProcessWithExitCode
                    ((Process.proc exe args) {Process.cwd = Just cwd, Process.create_group = True})
                    ""
                ) ::
                IO (Either IOException (ExitCode, String, String))
            let result = case attempted of
                  Left err -> Left ("Could not start " <> Text.pack exe <> ": " <> Text.pack (show err) <> ". Check installation and authentication, then retry.")
                  Right (code, out, err) -> case code of
                    ExitFailure n -> Left (Text.pack exe <> " exited " <> Text.pack (show n) <> ": " <> Text.take 2000 (Text.pack err <> Text.pack out) <> ". Inspect partial edits, fix the provider error, then retry.")
                    ExitSuccess -> validateMigrationOutput (req ^. #modelConfig . #provider == AgentProviderClaudeCli) (TE.encodeUtf8 (Text.pack out))
            case result of
              Left err -> throwIO (Baikai.providerError err)
              Right body ->
                pure $
                  BaikaiResponse.emptyResponse
                    { BaikaiResponse.model = m,
                      BaikaiResponse.message =
                        Baikai.AssistantPayload
                          { Baikai.content = V.singleton (Baikai.AssistantText (Baikai.TextContent body)),
                            Baikai.usage = Baikai.zeroUsage,
                            Baikai.stopReason = Baikai.Stop,
                            Baikai.errorMessage = Nothing,
                            Baikai.timestamp = Nothing
                          }
                    }
      Baikai.registerApiProvider (Baikai.apiProviderWith api (Baikai.liftCompleteToStream complete) complete)

-- | Source discovery is part of the ordinary migration workflow. Keep grants
-- specific to read-only Mori commands; registry writes are never implied.
migrationAllowedTools :: [String] -> [String]
migrationAllowedTools tools =
  nub
    ( tools
        <> [ "Bash(mori registry list)",
             "Bash(mori registry list *)",
             "Bash(mori registry search *)",
             "Bash(mori registry show *)",
             "Bash(mori registry docs *)",
             "Bash(mori registry dependents *)",
             "Bash(mori path *)",
             "Bash(head *)"
           ]
    )
