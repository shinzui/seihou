module Seihou.CLI.AgentConfigSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Seihou.CLI.AgentCompletion
import Seihou.CLI.AgentConfig
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.CLI.AgentConfig" spec

spec :: Spec
spec = do
  describe "resolveAgentModelConfig" $ do
    it "uses CLI flags before environment variables" $ do
      resolveAgentModelConfig
        (baseInputs {cliProvider = Just "codex-cli", cliModel = Just "gpt-5", envProvider = Just "anthropic", envModel = Just "claude-sonnet-4-6"})
        `shouldBe` Right
          AgentModelConfig
            { agentProvider = AgentProviderCodexCli,
              agentModel = Just "gpt-5"
            }

    it "uses environment variables before local config" $ do
      resolveAgentModelConfig
        (baseInputs {envProvider = Just "openai", envModel = Just "gpt-4o", localConfig = config "anthropic" "claude-sonnet-4-6"})
        `shouldBe` Right
          AgentModelConfig
            { agentProvider = AgentProviderOpenAI,
              agentModel = Just "gpt-4o"
            }

    it "uses local config before global config" $ do
      resolveAgentModelConfig
        (baseInputs {localConfig = config "anthropic" "claude-opus-4-1", globalConfig = config "openai" "gpt-4o-mini"})
        `shouldBe` Right
          AgentModelConfig
            { agentProvider = AgentProviderAnthropic,
              agentModel = Just "claude-opus-4-1"
            }

    it "falls back to the Claude CLI default" $
      resolveAgentModelConfig baseInputs `shouldBe` Right defaultAgentModelConfig

    it "returns provider diagnostics for invalid provider text" $
      resolveAgentModelConfig (baseInputs {cliProvider = Just "llama"}) `shouldSatisfy` \case
        Left err ->
          "Unknown agent provider" `Text.isInfixOf` err
            && "claude-cli" `Text.isInfixOf` err
            && "codex-cli" `Text.isInfixOf` err
        Right _ -> False

    it "allows a model-only override while keeping the default provider" $
      resolveAgentModelConfig (baseInputs {cliModel = Just "sonnet"})
        `shouldBe` Right
          AgentModelConfig
            { agentProvider = AgentProviderClaudeCli,
              agentModel = Just "sonnet"
            }

    it "ignores blank higher-precedence values" $
      resolveAgentModelConfig
        (baseInputs {cliProvider = Just "  ", envProvider = Just "codex-cli", cliModel = Just "", envModel = Just "gpt-5"})
        `shouldBe` Right
          AgentModelConfig
            { agentProvider = AgentProviderCodexCli,
              agentModel = Just "gpt-5"
            }

baseInputs :: AgentConfigInputs
baseInputs =
  AgentConfigInputs
    { cliProvider = Nothing,
      cliModel = Nothing,
      envProvider = Nothing,
      envModel = Nothing,
      localConfig = Map.empty,
      globalConfig = Map.empty
    }

config :: Text -> Text -> Map.Map Text Text
config provider model =
  Map.fromList
    [ (agentProviderConfigKey, provider),
      (agentModelConfigKey, model)
    ]
