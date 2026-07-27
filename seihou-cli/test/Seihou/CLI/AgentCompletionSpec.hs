module Seihou.CLI.AgentCompletionSpec (tests) where

import Baikai qualified
import Baikai.Model qualified as BaikaiModel
import Baikai.Response qualified as BaikaiResponse
import Data.Text qualified as Text
import Data.Time (UTCTime)
import Data.Vector qualified as V
import Seihou.CLI.AgentCompletion
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
          { agentProvider = AgentProviderClaudeCli,
            agentModel = Nothing,
            agentEffort = Nothing,
            agentTrace = TraceOff,
            agentTracePath = Nothing
          }

    it "builds a Claude CLI model using the CLI API tag" $ do
      let model =
            buildBaikaiModel
              AgentModelConfig
                { agentProvider = AgentProviderClaudeCli,
                  agentModel = Just "sonnet",
                  agentEffort = Nothing
                }
      BaikaiModel.api model `shouldBe` Baikai.AnthropicMessagesCli
      BaikaiModel.provider model `shouldBe` "anthropic"
      BaikaiModel.modelId model `shouldBe` "sonnet"

    it "builds a Codex CLI model using the CLI API tag" $ do
      let model =
            buildBaikaiModel
              AgentModelConfig
                { agentProvider = AgentProviderCodexCli,
                  agentModel = Just "gpt-5",
                  agentEffort = Nothing
                }
      BaikaiModel.api model `shouldBe` Baikai.OpenAICompletionsCli
      BaikaiModel.provider model `shouldBe` "openai"
      BaikaiModel.modelId model `shouldBe` "gpt-5"

  describe "buildAgentCompletionRequest" $ do
    it "preserves rendered prompts and resolved model configuration" $ do
      let config =
            AgentModelConfig
              { agentProvider = AgentProviderCodexCli,
                agentModel = Just "gpt-5",
                agentEffort = Nothing,
                agentTrace = TraceOff,
                agentTracePath = Nothing
              }
      buildAgentCompletionRequest config "system" (Just "user")
        `shouldBe` AgentCompletionRequest
          { completionSystemPrompt = "system",
            completionInitialPrompt = Just "user",
            completionModelConfig = config
          }

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
