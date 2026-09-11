module Seihou.CLI.AgentCompletionSpec (tests) where

import Baikai qualified
import Baikai.Model qualified as BaikaiModel
import Baikai.Response qualified as BaikaiResponse
import Baikai.Trace.Sink (TraceSink, silent)
import Control.Exception (throwIO)
import Control.Lens ((^.))
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString.Lazy.Char8 qualified as BL8
import Data.Generics.Labels ()
import Data.Text qualified as Text
import Data.Time (UTCTime)
import Data.Vector qualified as V
import Seihou.CLI.AgentCompletion
import Seihou.CLI.AgentTrace (traceSinkFor)
import System.Directory (doesFileExist)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec
import Test.Tasty (TestTree)
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.CLI.AgentCompletion" $ do
  describe "provider text helpers" $ do
    it "parses known providers case-insensitively" $ do
      providerFromText "claude-cli" `shouldBe` Right AgentProviderClaudeCli
      providerFromText "CODEX-CLI" `shouldBe` Right AgentProviderCodexCli
      providerFromText " anthropic " `shouldBe` Right AgentProviderAnthropic
      providerFromText "openai" `shouldBe` Right AgentProviderOpenAI

    it "renders providers to canonical config text" $ do
      providerToText AgentProviderClaudeCli `shouldBe` "claude-cli"
      providerToText AgentProviderCodexCli `shouldBe` "codex-cli"
      providerToText AgentProviderAnthropic `shouldBe` "anthropic"
      providerToText AgentProviderOpenAI `shouldBe` "openai"

    it "returns a useful error for unknown providers" $
      providerFromText "llama" `shouldSatisfy` \case
        Left err ->
          "claude-cli" `Text.isInfixOf` err
            && "codex-cli" `Text.isInfixOf` err
            && "anthropic" `Text.isInfixOf` err
            && "openai" `Text.isInfixOf` err
        Right _ -> False

  describe "trace setting text helpers" $ do
    it "parses every accepted setting case-insensitively" $ do
      traceFromText "off" `shouldBe` Right TraceOff
      traceFromText "FILE" `shouldBe` Right TraceFile
      traceFromText "  stdout  " `shouldBe` Right TraceStdout
      traceFromText "StdErr" `shouldBe` Right TraceStderr

    it "names every accepted setting in the failure message" $
      traceFromText "syslog" `shouldSatisfy` \case
        Left err ->
          "off" `Text.isInfixOf` err
            && "file" `Text.isInfixOf` err
            && "stdout" `Text.isInfixOf` err
            && "stderr" `Text.isInfixOf` err
        Right _ -> False

    it "round-trips through traceToText" $
      traverse (traceFromText . traceToText) [TraceOff, TraceFile, TraceStdout, TraceStderr]
        `shouldBe` Right [TraceOff, TraceFile, TraceStdout, TraceStderr]

  describe "model construction" $ do
    it "defaults to the Claude CLI provider with no explicit model" $
      defaultAgentModelConfig
        `shouldBe` AgentModelConfig
          { provider = AgentProviderClaudeCli,
            model = Nothing,
            effort = Nothing,
            trace = TraceOff,
            tracePath = Nothing
          }

    it "builds a Claude CLI model using the CLI API tag" $ do
      let model =
            buildBaikaiModel
              AgentModelConfig
                { provider = AgentProviderClaudeCli,
                  model = Just "sonnet",
                  effort = Nothing,
                  trace = TraceOff,
                  tracePath = Nothing
                }
      BaikaiModel.api model `shouldBe` Baikai.AnthropicMessagesCli
      BaikaiModel.provider model `shouldBe` "anthropic"
      BaikaiModel.modelId model `shouldBe` "sonnet"

    it "builds a Codex CLI model using the CLI API tag" $ do
      let model =
            buildBaikaiModel
              AgentModelConfig
                { provider = AgentProviderCodexCli,
                  model = Just "gpt-5",
                  effort = Nothing,
                  trace = TraceOff,
                  tracePath = Nothing
                }
      BaikaiModel.api model `shouldBe` Baikai.OpenAICompletionsCli
      BaikaiModel.provider model `shouldBe` "openai"
      BaikaiModel.modelId model `shouldBe` "gpt-5"

  describe "buildAgentCompletionRequest" $ do
    it "preserves rendered prompts and resolved model configuration" $ do
      let config =
            AgentModelConfig
              { provider = AgentProviderCodexCli,
                model = Just "gpt-5",
                effort = Nothing,
                trace = TraceOff,
                tracePath = Nothing
              }
          req = buildAgentCompletionRequest config "system" (Just "user")
      -- AgentCompletionRequest has no Eq: it carries a TraceSink, which wraps a
      -- streamly fold. Compare the inspectable fields instead.
      (req ^. #systemPrompt) `shouldBe` "system"
      (req ^. #initialPrompt) `shouldBe` Just "user"
      (req ^. #modelConfig) `shouldBe` config

  -- These drive the real Baikai.Trace.withTrace path against a stub provider
  -- registered under the anthropic-messages tag. They exist because withTrace
  -- reports provider failures as an error-shaped Response rather than by
  -- throwing, the way completeRequest did: without the responseError branch in
  -- runAgentCompletionWith, every one of these failures would be reported as
  -- "Provider returned no assistant text." and the real message would be lost.
  describe "runAgentCompletionWith" $ do
    it "returns the assistant text of a successful call" $ do
      result <- runStub (const (pure (okResponse "hello from the stub"))) Nothing
      result `shouldBe` Right "hello from the stub"

    -- The regression test for the whole swap. Delete the responseError branch
    -- in runAgentCompletionWith and this fails with the empty-text message.
    it "reports the provider's message when the response is error-shaped" $ do
      result <- runStub (\m -> pure (failedResponse m "invalid x-api-key")) Nothing
      result `shouldSatisfy` \case
        Left err -> "invalid x-api-key" `Text.isInfixOf` err
        Right _ -> False

    it "does not mistake a provider error for missing assistant text" $ do
      result <- runStub (\m -> pure (failedResponse m "model not found")) Nothing
      result `shouldSatisfy` \case
        Left err -> not ("Provider returned no assistant text." `Text.isInfixOf` err)
        Right _ -> False

    -- ...and the empty-text guard must still fire for a genuinely empty
    -- success, rather than being shadowed by the new branch.
    it "still reports a successful but empty response as missing text" $ do
      result <- runStub (const (pure (okResponse ""))) Nothing
      result `shouldBe` Left "Provider returned no assistant text."

    it "reports a thrown provider exception, which withTrace still propagates" $ do
      result <- runStub (const (throwIO (Baikai.providerError "connection reset"))) Nothing
      result `shouldSatisfy` \case
        Left err -> "connection reset" `Text.isInfixOf` err
        Right _ -> False

    it "writes a correlated start/finish pair to a file sink" $
      withSystemTempDirectory "seihou-completion-trace" $ \root -> do
        let path = root </> "trace.jsonl"
        sink <- traceSinkFor TraceFile (Just path)
        _ <- runStub (const (pure (okResponse "traced"))) (Just sink)
        events <- traceEvents path
        map fst events `shouldBe` ["call_started", "call_finished"]
        case map snd events of
          [a, b] -> a `shouldBe` b
          other -> expectationFailure ("expected two events, got " <> show (length other))

    it "writes a start/fail pair when the call fails" $
      withSystemTempDirectory "seihou-completion-trace-fail" $ \root -> do
        let path = root </> "trace.jsonl"
        sink <- traceSinkFor TraceFile (Just path)
        _ <- runStub (\m -> pure (failedResponse m "rate limited")) (Just sink)
        events <- traceEvents path
        map fst events `shouldBe` ["call_started", "call_failed"]

    it "writes nothing when tracing is off" $
      withSystemTempDirectory "seihou-completion-trace-off" $ \root -> do
        let path = root </> "trace.jsonl"
        _ <- runStub (const (pure (okResponse "untraced"))) Nothing
        doesFileExist path `shouldReturn` False

  describe "responseText" $ do
    it "extracts and joins assistant text blocks only" $ do
      let resp =
            BaikaiResponse.emptyResponse
              { BaikaiResponse.message =
                  Baikai.AssistantPayload
                    { Baikai.content =
                        V.fromList
                          [ Baikai.AssistantText (Baikai.TextContent "hello"),
                            Baikai.AssistantThinking Baikai.emptyThinkingContent,
                            Baikai.AssistantText (Baikai.TextContent "world")
                          ],
                      Baikai.usage = Baikai.zeroUsage,
                      Baikai.stopReason = Baikai.Stop,
                      Baikai.errorMessage = Nothing,
                      Baikai.timestamp = Just (read "2026-05-23 00:00:00 UTC" :: UTCTime)
                    }
              }
      responseText resp `shouldBe` "hello\nworld"

-- | Run a completion against a stub provider that returns whatever the given
-- action produces, optionally reporting to a trace sink.
--
-- The stub registers under the @anthropic-messages@ tag, which is what
-- 'buildBaikaiModel' selects for 'AgentProviderAnthropic'. It supplies both
-- provider fields the way the real CLI providers do — a direct @complete@ and
-- a @stream@ lifted from it — because 'Baikai.Trace.withTrace' dispatches
-- through @stream@, not @complete@.
--
-- Registration mutates Baikai's process-global registry. That is safe here
-- because the test binary is not built with @-threaded@, so tasty runs these
-- sequentially; a stub is always registered immediately before the call that
-- uses it.
runStub ::
  (Baikai.Model -> IO BaikaiResponse.Response) ->
  Maybe TraceSink ->
  IO (Either Text.Text Text.Text)
runStub respond sink =
  runAgentCompletionWith registerStub request
  where
    registerStub =
      Baikai.registerApiProvider
        ( Baikai.apiProviderWith
            Baikai.AnthropicMessages
            (Baikai.liftCompleteToStream (\m _ _ -> respond m))
            (\m _ _ -> respond m)
        )
    request =
      buildAgentCompletionRequestWith
        (maybe silent id sink)
        AgentModelConfig
          { provider = AgentProviderAnthropic,
            model = Just "stub-model",
            effort = Nothing,
            trace = maybe TraceOff (const TraceFile) sink,
            tracePath = Nothing
          }
        "system"
        (Just "user")

-- | A successful response carrying one assistant text block.
okResponse :: Text.Text -> BaikaiResponse.Response
okResponse body =
  BaikaiResponse.emptyResponse
    { BaikaiResponse.message =
        Baikai.AssistantPayload
          { Baikai.content = V.singleton (Baikai.AssistantText (Baikai.TextContent body)),
            Baikai.usage = Baikai.zeroUsage,
            Baikai.stopReason = Baikai.Stop,
            Baikai.errorMessage = Nothing,
            Baikai.timestamp = Just epoch
          }
    }

-- | An error-shaped response, the way a conforming provider reports an in-band
-- failure: @stopReason = ErrorReason@ plus the provider's message.
failedResponse :: Baikai.Model -> Text.Text -> BaikaiResponse.Response
failedResponse m message =
  BaikaiResponse.errorResponse m epoch 12 (Baikai.providerError message)

epoch :: UTCTime
epoch = read "2026-07-27 00:00:00 UTC"

-- | The @(kind, eventId)@ of every event in a JSONL trace file, in order.
traceEvents :: FilePath -> IO [(String, String)]
traceEvents path = do
  contents <- BL8.readFile path
  pure
    [ (Text.unpack kind, Text.unpack eventId)
    | line <- BL8.lines contents,
      not (BL8.null line),
      Just (Aeson.Object o) <- [Aeson.decode line],
      Just (Aeson.String kind) <- [KeyMap.lookup (Key.fromString "kind") o],
      Just (Aeson.String eventId) <- [KeyMap.lookup (Key.fromString "eventId") o]
    ]
