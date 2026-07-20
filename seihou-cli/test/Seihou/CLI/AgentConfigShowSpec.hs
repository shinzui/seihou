module Seihou.CLI.AgentConfigShowSpec (tests) where

import Baikai.ThinkingLevel (ThinkingLevel (..))
import Data.Text (Text)
import Data.Text qualified as Text
import Seihou.CLI.AgentCompletion (AgentProvider (..))
import Seihou.CLI.AgentConfig
  ( AgentCommandName (..),
    AgentConfigSource (..),
    ResolvedAgentField (..),
    ResolvedCommandConfig (..),
  )
import Seihou.CLI.AgentConfigShow (formatResolvedAgentConfig)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.CLI.AgentConfigShow" spec

spec :: Spec
spec =
  describe "formatResolvedAgentConfig" $ do
    let rendered = formatResolvedAgentConfig sample
        -- A line exists containing every fragment (order-independent).
        hasLine fragments =
          any (\ln -> all (`Text.isInfixOf` ln) fragments) (Text.lines rendered)

    -- The command label is printed on the provider row; the model row's label
    -- column is blank, so model-row assertions match on value + source only
    -- (each is unique to one command in the sample).
    it "labels a per-command local model with its concrete key" $
      hasLine ["model", "claude-opus-4-8", "[local: agent.run.model]"] `shouldBe` True

    it "shows an unset model as (default) with built-in provenance" $
      hasLine ["model", "(default)", "[built-in default]"] `shouldBe` True

    it "labels a global default model with the shared key" $
      hasLine ["model", "claude-sonnet-5", "[global: agent.model]"] `shouldBe` True

    it "labels a global per-command provider with its command key on the labelled row" $
      hasLine ["assist", "provider", "codex-cli", "[global: agent.assist.provider]"] `shouldBe` True

    it "renders the migrate command and its concrete config key" $
      hasLine ["migrate", "model", "gpt-5-mini", "[local: agent.migrate.model]"] `shouldBe` True

    it "labels a per-command local effort with its concrete key" $
      hasLine ["effort", "max", "[local: agent.run.effort]"] `shouldBe` True

    it "labels a global default effort with the shared key" $
      hasLine ["effort", "high", "[global: agent.effort]"] `shouldBe` True

    it "shows an unset effort as (default) with built-in provenance" $
      hasLine ["effort", "(default)", "[built-in default]"] `shouldBe` True

    it "includes the precedence legend" $
      ("Precedence, highest first:" `Text.isInfixOf` rendered) `shouldBe` True

sample :: [ResolvedCommandConfig]
sample =
  [ ResolvedCommandConfig
      AgentCmdAssist
      (ResolvedAgentField AgentProviderCodexCli SourceGlobalCommand)
      (ResolvedAgentField Nothing SourceBuiltinDefault)
      (ResolvedAgentField (Just ThinkingHigh) SourceGlobalDefault),
    ResolvedCommandConfig
      AgentCmdBootstrap
      (ResolvedAgentField AgentProviderClaudeCli SourceBuiltinDefault)
      (ResolvedAgentField (Just "claude-sonnet-5") SourceGlobalDefault)
      (ResolvedAgentField Nothing SourceBuiltinDefault),
    ResolvedCommandConfig
      AgentCmdRun
      (ResolvedAgentField AgentProviderClaudeCli SourceBuiltinDefault)
      (ResolvedAgentField (Just "claude-opus-4-8") SourceLocalCommand)
      (ResolvedAgentField (Just ThinkingMax) SourceLocalCommand),
    ResolvedCommandConfig
      AgentCmdMigrate
      (ResolvedAgentField AgentProviderOpenAI SourceLocalCommand)
      (ResolvedAgentField (Just "gpt-5-mini") SourceLocalCommand)
      (ResolvedAgentField Nothing SourceBuiltinDefault)
  ]
