module Seihou.CLI.AgentModelsSpec (tests) where

import Baikai.Model (Model)
import Baikai.Model qualified as BaikaiModel
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Seihou.CLI.AgentCompletion (AgentProvider (..))
import Seihou.CLI.AgentModels
import Test.Hspec
import Test.Tasty (TestTree)
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.CLI.AgentModels" $ do
  describe "availableAgentModels" $ do
    it "contains 31 unique Anthropic and OpenAI model IDs" $ do
      let ids = modelIds availableAgentModels
      length ids `shouldBe` 31
      Set.size (Set.fromList ids) `shouldBe` 31
      Set.fromList (map BaikaiModel.provider availableAgentModels)
        `shouldBe` Set.fromList ["anthropic", "openai"]

    it "contains the newest Claude and GPT-5.6 models" $
      modelIds availableAgentModels
        `shouldSatisfy` \ids ->
          all
            (`elem` ids)
            ["claude-sonnet-5", "gpt-5.6", "gpt-5.6-luna", "gpt-5.6-sol", "gpt-5.6-terra"]

  describe "filterAgentModels" $ do
    it "maps the Anthropic API and Claude CLI providers to the same 9 models" $ do
      let anthropicIds = filteredIds AgentProviderAnthropic
          claudeCliIds = filteredIds AgentProviderClaudeCli
      anthropicIds `shouldBe` claudeCliIds
      length anthropicIds `shouldBe` 9

    it "maps the OpenAI API and Codex CLI providers to the same 22 models" $ do
      let openAIIds = filteredIds AgentProviderOpenAI
          codexCliIds = filteredIds AgentProviderCodexCli
      openAIIds `shouldBe` codexCliIds
      length openAIIds `shouldBe` 22

  describe "formatAgentModels" $ do
    it "renders model names, compatible providers, count, and alias guidance" $ do
      let output = formatAgentModels Nothing availableAgentModels
      output `shouldSatisfy` Text.isInfixOf "MODEL"
      output `shouldSatisfy` Text.isInfixOf "Claude Sonnet 5"
      output `shouldSatisfy` Text.isInfixOf "anthropic, claude-cli"
      output `shouldSatisfy` Text.isInfixOf "GPT-5.6 Terra"
      output `shouldSatisfy` Text.isInfixOf "openai, codex-cli"
      output `shouldSatisfy` Text.isInfixOf "31 models found."
      output `shouldSatisfy` Text.isInfixOf "aliases and custom model IDs remain accepted"

    it "reports the filtered model count" $ do
      formatAgentModels (Just AgentProviderAnthropic) availableAgentModels
        `shouldSatisfy` Text.isInfixOf "9 models found."
      formatAgentModels (Just AgentProviderCodexCli) availableAgentModels
        `shouldSatisfy` Text.isInfixOf "22 models found."

modelIds :: [Model] -> [Text]
modelIds = map BaikaiModel.modelId

filteredIds :: AgentProvider -> [Text]
filteredIds provider =
  modelIds (filterAgentModels (Just provider) availableAgentModels)
