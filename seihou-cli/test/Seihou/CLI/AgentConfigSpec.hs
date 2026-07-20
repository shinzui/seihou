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

  describe "resolveAgentModelConfigFor (per-command)" $ do
    it "prefers a per-command model over the default in the same scope" $ do
      let inputs =
            baseInputs
              { localConfig =
                  Map.fromList
                    [ (agentModelConfigKey, "claude-sonnet-5"),
                      (agentCommandModelConfigKey AgentCmdRun, "claude-opus-4-8")
                    ]
              }
      modelOf AgentCmdRun inputs `shouldBe` Right (Just "claude-opus-4-8", SourceLocalCommand)
      modelOf AgentCmdAssist inputs `shouldBe` Right (Just "claude-sonnet-5", SourceLocalDefault)

    it "lets a local default override a global per-command key (project over global)" $ do
      let inputs =
            baseInputs
              { localConfig = Map.fromList [(agentModelConfigKey, "claude-sonnet-5")],
                globalConfig = Map.fromList [(agentCommandModelConfigKey AgentCmdRun, "gpt-5")]
              }
      modelOf AgentCmdRun inputs `shouldBe` Right (Just "claude-sonnet-5", SourceLocalDefault)

    it "prefers a global per-command key over the global default" $ do
      let inputs =
            baseInputs
              { globalConfig =
                  Map.fromList
                    [ (agentProviderConfigKey, "anthropic"),
                      (agentCommandProviderConfigKey AgentCmdAssist, "openai")
                    ]
              }
      providerOf AgentCmdAssist inputs `shouldBe` Right (AgentProviderOpenAI, SourceGlobalCommand)
      providerOf AgentCmdSetup inputs `shouldBe` Right (AgentProviderAnthropic, SourceGlobalDefault)

    it "labels a subcommand CLI flag distinctly from a parent flag" $ do
      providerOf AgentCmdAssist (baseInputs {cliProvider = Just "codex-cli", cliProviderFromSubcommand = True})
        `shouldBe` Right (AgentProviderCodexCli, SourceCliSubcommand)
      providerOf AgentCmdAssist (baseInputs {cliProvider = Just "codex-cli", cliProviderFromSubcommand = False})
        `shouldBe` Right (AgentProviderCodexCli, SourceCliParent)

    it "falls back to the built-in default with built-in provenance" $ do
      providerOf AgentCmdRun baseInputs `shouldBe` Right (AgentProviderClaudeCli, SourceBuiltinDefault)
      modelOf AgentCmdRun baseInputs `shouldBe` Right (Nothing, SourceBuiltinDefault)

    it "keeps environment variables above per-command config" $ do
      let inputs =
            baseInputs
              { envModel = Just "gpt-5",
                localConfig = Map.fromList [(agentCommandModelConfigKey AgentCmdRun, "claude-opus-4-8")]
              }
      modelOf AgentCmdRun inputs `shouldBe` Right (Just "gpt-5", SourceEnv)

providerOf :: AgentCommandName -> AgentConfigInputs -> Either Text (AgentProvider, AgentConfigSource)
providerOf c inputs =
  (\(p, _) -> (p.resolvedValue, p.resolvedSource)) <$> resolveAgentModelConfigFor c inputs

modelOf :: AgentCommandName -> AgentConfigInputs -> Either Text (Maybe Text, AgentConfigSource)
modelOf c inputs =
  (\(_, m) -> (m.resolvedValue, m.resolvedSource)) <$> resolveAgentModelConfigFor c inputs

baseInputs :: AgentConfigInputs
baseInputs = baseAgentConfigInputs

config :: Text -> Text -> Map.Map Text Text
config provider model =
  Map.fromList
    [ (agentProviderConfigKey, provider),
      (agentModelConfigKey, model)
    ]
