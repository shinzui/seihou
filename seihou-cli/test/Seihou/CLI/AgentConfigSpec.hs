module Seihou.CLI.AgentConfigSpec (tests) where

import Baikai.ThinkingLevel (ThinkingLevel (..))
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Seihou.CLI.AgentCompletion
import Seihou.CLI.AgentConfig
import Seihou.Core.Types (AgentLaunch (..))
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.CLI.AgentConfig" spec

spec :: Spec
spec = do
  describe "resolveAgentModelConfig" $ do
    it "uses CLI flags before environment variables" $
      resolveAgentModelConfig
        (baseInputs {cliProvider = Just "codex-cli", cliModel = Just "gpt-5", envProvider = Just "anthropic", envModel = Just "claude-sonnet-4-6"})
        `shouldBe` Right (cfg AgentProviderCodexCli (Just "gpt-5"))

    it "uses environment variables before local config" $
      resolveAgentModelConfig
        (baseInputs {envProvider = Just "openai", envModel = Just "gpt-4o", localConfig = config "anthropic" "claude-sonnet-4-6"})
        `shouldBe` Right (cfg AgentProviderOpenAI (Just "gpt-4o"))

    it "uses local config before global config" $
      resolveAgentModelConfig
        (baseInputs {localConfig = config "anthropic" "claude-opus-4-1", globalConfig = config "openai" "gpt-4o-mini"})
        `shouldBe` Right (cfg AgentProviderAnthropic (Just "claude-opus-4-1"))

    it "pins the deterministic claude-cli default model when nothing is set" $
      resolveAgentModelConfig baseInputs
        `shouldBe` Right (cfg AgentProviderClaudeCli (Just "claude-opus-4-8"))

    it "pins the deterministic codex-cli default model when only the provider is set" $
      resolveAgentModelConfig (baseInputs {cliProvider = Just "codex-cli"})
        `shouldBe` Right (cfg AgentProviderCodexCli (Just "gpt-5.6-terra"))

    it "returns provider diagnostics for invalid provider text" $
      resolveAgentModelConfig (baseInputs {cliProvider = Just "llama"}) `shouldSatisfy` \case
        Left err ->
          "Unknown agent provider" `Text.isInfixOf` err
            && "claude-cli" `Text.isInfixOf` err
            && "codex-cli" `Text.isInfixOf` err
        Right _ -> False

    it "allows a model-only override while keeping the default provider" $
      resolveAgentModelConfig (baseInputs {cliModel = Just "sonnet"})
        `shouldBe` Right (cfg AgentProviderClaudeCli (Just "sonnet"))

    it "ignores blank higher-precedence values" $
      resolveAgentModelConfig
        (baseInputs {cliProvider = Just "  ", envProvider = Just "codex-cli", cliModel = Just "", envModel = Just "gpt-5"})
        `shouldBe` Right (cfg AgentProviderCodexCli (Just "gpt-5"))

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

    it "falls back to the pinned CLI default model with built-in provenance" $ do
      providerOf AgentCmdRun baseInputs `shouldBe` Right (AgentProviderClaudeCli, SourceBuiltinDefault)
      modelOf AgentCmdRun baseInputs `shouldBe` Right (Just "claude-opus-4-8", SourceBuiltinDefault)

    it "keeps claude-cli and codex-cli deterministic: model is never Nothing" $ do
      -- With nothing configured, every command resolves to a concrete model for
      -- both local CLI providers, so seihou always passes an explicit --model.
      modelOf AgentCmdAssist baseInputs `shouldBe` Right (Just "claude-opus-4-8", SourceBuiltinDefault)
      modelOf AgentCmdAssist (baseInputs {cliProvider = Just "codex-cli", cliProviderFromSubcommand = True})
        `shouldBe` Right (Just "gpt-5.6-terra", SourceBuiltinDefault)

    it "keeps environment variables above per-command config" $ do
      let inputs =
            baseInputs
              { envModel = Just "gpt-5",
                localConfig = Map.fromList [(agentCommandModelConfigKey AgentCmdRun, "claude-opus-4-8")]
              }
      modelOf AgentCmdRun inputs `shouldBe` Right (Just "gpt-5", SourceEnv)

    it "resolves migrate from its own per-command keys" $ do
      let inputs =
            baseInputs
              { localConfig =
                  Map.fromList
                    [ (agentCommandProviderConfigKey AgentCmdMigrate, "openai"),
                      (agentCommandModelConfigKey AgentCmdMigrate, "gpt-5-mini"),
                      (agentCommandModelConfigKey AgentCmdRun, "claude-opus-4-8")
                    ]
              }
      providerOf AgentCmdMigrate inputs `shouldBe` Right (AgentProviderOpenAI, SourceLocalCommand)
      modelOf AgentCmdMigrate inputs `shouldBe` Right (Just "gpt-5-mini", SourceLocalCommand)
      modelOf AgentCmdRun inputs `shouldBe` Right (Just "claude-opus-4-8", SourceLocalCommand)

  describe "resolveAgentModelConfigFor (reasoning effort)" $ do
    it "defaults to unset effort when nothing is configured" $
      effortOf AgentCmdRun baseInputs `shouldBe` Right (Nothing, SourceBuiltinDefault)

    it "prefers a per-command effort over the shared default in the same scope" $ do
      let inputs =
            baseInputs
              { localConfig =
                  Map.fromList
                    [ (agentEffortConfigKey, "medium"),
                      (agentCommandEffortConfigKey AgentCmdRun, "max")
                    ]
              }
      effortOf AgentCmdRun inputs `shouldBe` Right (Just ThinkingMax, SourceLocalCommand)
      effortOf AgentCmdAssist inputs `shouldBe` Right (Just ThinkingMedium, SourceLocalDefault)

    it "lets a local default effort override a global per-command effort" $ do
      let inputs =
            baseInputs
              { localConfig = Map.fromList [(agentEffortConfigKey, "low")],
                globalConfig = Map.fromList [(agentCommandEffortConfigKey AgentCmdRun, "max")]
              }
      effortOf AgentCmdRun inputs `shouldBe` Right (Just ThinkingLow, SourceLocalDefault)

    it "keeps the effort environment variable above config" $ do
      let inputs =
            baseInputs
              { envEffort = Just "high",
                localConfig = Map.fromList [(agentCommandEffortConfigKey AgentCmdRun, "minimal")]
              }
      effortOf AgentCmdRun inputs `shouldBe` Right (Just ThinkingHigh, SourceEnv)

    it "prefers the subcommand effort flag over everything" $
      effortOf
        AgentCmdRun
        (baseInputs {cliEffort = Just "xhigh", cliEffortFromSubcommand = True, envEffort = Just "low"})
        `shouldBe` Right (Just ThinkingXHigh, SourceCliSubcommand)

    it "parses effort case-insensitively" $
      effortOf AgentCmdRun (baseInputs {cliEffort = Just "  MAX  "}) `shouldBe` Right (Just ThinkingMax, SourceCliParent)

    it "returns a diagnostic for an invalid effort value" $
      resolveAgentModelConfigFor AgentCmdRun (baseInputs {cliEffort = Just "ultra"}) `shouldSatisfy` \case
        Left err -> "Unknown reasoning effort" `Text.isInfixOf` err && "xhigh" `Text.isInfixOf` err
        Right _ -> False

  describe "resolveAgentModelConfigFor (call tracing)" $ do
    it "defaults to tracing off when nothing is configured" $
      traceOf AgentCmdRun baseInputs `shouldBe` Right (TraceOff, SourceBuiltinDefault)

    it "prefers a per-command trace over the shared default in the same scope" $ do
      let inputs =
            baseInputs
              { localConfig =
                  Map.fromList
                    [ (agentTraceConfigKey, "stderr"),
                      (agentCommandTraceConfigKey AgentCmdRun, "file")
                    ]
              }
      traceOf AgentCmdRun inputs `shouldBe` Right (TraceFile, SourceLocalCommand)
      traceOf AgentCmdAssist inputs `shouldBe` Right (TraceStderr, SourceLocalDefault)

    it "lets a local default trace override a global per-command trace" $ do
      let inputs =
            baseInputs
              { localConfig = Map.fromList [(agentTraceConfigKey, "stdout")],
                globalConfig = Map.fromList [(agentCommandTraceConfigKey AgentCmdRun, "file")]
              }
      traceOf AgentCmdRun inputs `shouldBe` Right (TraceStdout, SourceLocalDefault)

    it "lets a global per-command trace beat a global default" $ do
      let inputs =
            baseInputs
              { globalConfig =
                  Map.fromList
                    [ (agentTraceConfigKey, "stdout"),
                      (agentCommandTraceConfigKey AgentCmdRun, "file")
                    ]
              }
      traceOf AgentCmdRun inputs `shouldBe` Right (TraceFile, SourceGlobalCommand)

    it "keeps the trace environment variable above config" $ do
      let inputs =
            baseInputs
              { envTrace = Just "stderr",
                localConfig = Map.fromList [(agentCommandTraceConfigKey AgentCmdRun, "file")]
              }
      traceOf AgentCmdRun inputs `shouldBe` Right (TraceStderr, SourceEnv)

    it "keeps a declared trace above config but below the environment" $ do
      let declared = baseInputs {declaredTrace = Just "file"}
      traceOf AgentCmdRun (declared {localConfig = Map.fromList [(agentTraceConfigKey, "stdout")]})
        `shouldBe` Right (TraceFile, SourceArtifactDeclaration)
      traceOf AgentCmdRun (declared {envTrace = Just "stderr"})
        `shouldBe` Right (TraceStderr, SourceEnv)

    it "prefers the subcommand trace flag over everything" $
      traceOf
        AgentCmdRun
        (baseInputs {cliTrace = Just "off", cliTraceFromSubcommand = True, envTrace = Just "file"})
        `shouldBe` Right (TraceOff, SourceCliSubcommand)

    it "attributes a parent `seihou agent` trace flag to that tier" $
      traceOf AgentCmdRun (baseInputs {cliTrace = Just "file", cliTraceFromSubcommand = False})
        `shouldBe` Right (TraceFile, SourceCliParent)

    it "parses trace settings case-insensitively" $
      traceOf AgentCmdRun (baseInputs {cliTrace = Just "  STDERR  "})
        `shouldBe` Right (TraceStderr, SourceCliParent)

    it "skips a blank trace value in favor of the next tier" $
      traceOf
        AgentCmdRun
        (baseInputs {cliTrace = Just "   ", localConfig = Map.fromList [(agentTraceConfigKey, "file")]})
        `shouldBe` Right (TraceFile, SourceLocalDefault)

    it "returns a diagnostic naming every accepted trace setting" $
      resolveAgentModelConfigFor AgentCmdRun (baseInputs {cliTrace = Just "syslog"}) `shouldSatisfy` \case
        Left err ->
          "Unknown trace setting" `Text.isInfixOf` err
            && "off" `Text.isInfixOf` err
            && "file" `Text.isInfixOf` err
            && "stdout" `Text.isInfixOf` err
            && "stderr" `Text.isInfixOf` err
        Right _ -> False

  describe "resolveTracePath" $ do
    it "is unset when no agent.tracePath is configured" $
      resolveTracePath baseInputs `shouldBe` Nothing

    it "reads the local key before the global key" $
      resolveTracePath
        baseInputs
          { localConfig = Map.fromList [(agentTracePathConfigKey, "/tmp/local.jsonl")],
            globalConfig = Map.fromList [(agentTracePathConfigKey, "/tmp/global.jsonl")]
          }
        `shouldBe` Just "/tmp/local.jsonl"

    it "falls back to the global key" $
      resolveTracePath baseInputs {globalConfig = Map.fromList [(agentTracePathConfigKey, "/tmp/global.jsonl")]}
        `shouldBe` Just "/tmp/global.jsonl"

    it "treats a blank local path as absent" $
      resolveTracePath
        baseInputs
          { localConfig = Map.fromList [(agentTracePathConfigKey, "   ")],
            globalConfig = Map.fromList [(agentTracePathConfigKey, "/tmp/global.jsonl")]
          }
        `shouldBe` Just "/tmp/global.jsonl"

  describe "artifact-declared launch settings" $ do
    it "beats a per-command local config key" $ do
      let inputs =
            declaring
              (decl Nothing (Just "claude-sonnet-5") Nothing)
              baseInputs
                { localConfig = Map.fromList [(agentCommandModelConfigKey AgentCmdRun, "claude-haiku-4-5")]
                }
      modelOf AgentCmdRun inputs `shouldBe` Right (Just "claude-sonnet-5", SourceArtifactDeclaration)

    it "beats both local and global default keys" $ do
      let inputs =
            declaring
              (decl (Just "openai") Nothing (Just "high"))
              baseInputs
                { localConfig = Map.fromList [(agentProviderConfigKey, "anthropic")],
                  globalConfig = Map.fromList [(agentEffortConfigKey, "low")]
                }
      providerOf AgentCmdRun inputs `shouldBe` Right (AgentProviderOpenAI, SourceArtifactDeclaration)
      effortOf AgentCmdRun inputs `shouldBe` Right (Just ThinkingHigh, SourceArtifactDeclaration)

    it "loses to a subcommand flag" $ do
      let inputs =
            declaring
              (decl Nothing (Just "claude-sonnet-5") Nothing)
              baseInputs {cliModel = Just "claude-opus-4-8", cliModelFromSubcommand = True}
      modelOf AgentCmdRun inputs `shouldBe` Right (Just "claude-opus-4-8", SourceCliSubcommand)

    it "loses to a parent `seihou agent` flag" $ do
      let inputs =
            declaring
              (decl Nothing (Just "claude-sonnet-5") Nothing)
              baseInputs {cliModel = Just "claude-opus-4-8", cliModelFromSubcommand = False}
      modelOf AgentCmdRun inputs `shouldBe` Right (Just "claude-opus-4-8", SourceCliParent)

    it "loses to an environment variable" $ do
      let inputs = declaring (decl Nothing (Just "claude-sonnet-5") (Just "max")) baseInputs {envEffort = Just "low"}
      effortOf AgentCmdRun inputs `shouldBe` Right (Just ThinkingLow, SourceEnv)
      -- ...but only for the field the environment names.
      modelOf AgentCmdRun inputs `shouldBe` Right (Just "claude-sonnet-5", SourceArtifactDeclaration)

    it "skips a blank declared value in favor of the next tier" $ do
      let inputs =
            declaring
              (decl Nothing (Just "   ") Nothing)
              baseInputs {localConfig = Map.fromList [(agentModelConfigKey, "claude-haiku-4-5")]}
      modelOf AgentCmdRun inputs `shouldBe` Right (Just "claude-haiku-4-5", SourceLocalDefault)

    -- Guards the applyProviderDefaultModel interaction: a declaration that only
    -- changes the provider must pick up that provider's pinned default model,
    -- not the previous provider's.
    it "picks up the declared provider's pinned default model" $ do
      let inputs = declaring (decl (Just "codex-cli") Nothing Nothing) baseInputs
      providerOf AgentCmdRun inputs `shouldBe` Right (AgentProviderCodexCli, SourceArtifactDeclaration)
      modelOf AgentCmdRun inputs `shouldBe` Right (Just "gpt-5.6-terra", SourceBuiltinDefault)

    it "returns a diagnostic naming the accepted providers for a bad declared provider" $
      resolveAgentModelConfigFor AgentCmdRun (declaring (decl (Just "llama") Nothing Nothing) baseInputs)
        `shouldSatisfy` \case
          Left err ->
            "Unknown agent provider" `Text.isInfixOf` err
              && "claude-cli" `Text.isInfixOf` err
              && "openai" `Text.isInfixOf` err
          Right _ -> False

    it "returns a diagnostic for a bad declared effort" $
      resolveAgentModelConfigFor AgentCmdRun (declaring (decl Nothing Nothing (Just "ultra")) baseInputs)
        `shouldSatisfy` \case
          Left err -> "Unknown reasoning effort" `Text.isInfixOf` err
          Right _ -> False

    it "labels blueprint-run and migrate declarations as blueprint sources" $ do
      agentConfigSourceLabel AgentCmdRun ModelField SourceArtifactDeclaration `shouldBe` "blueprint: launch.model"
      agentConfigSourceLabel AgentCmdMigrate EffortField SourceArtifactDeclaration `shouldBe` "blueprint: launch.effort"
      agentConfigSourceLabel AgentCmdRun ProviderField SourceArtifactDeclaration `shouldBe` "blueprint: launch.provider"

    it "labels a prompt-run declaration as a prompt source" $
      agentConfigSourceLabel AgentCmdPromptRun ModelField SourceArtifactDeclaration `shouldBe` "prompt: launch.model"

  describe "agentLaunchDeclaration" $ do
    it "treats a missing launch record as declaring nothing" $
      agentLaunchDeclaration Nothing `shouldBe` noAgentLaunchDeclaration

    it "projects the three resolvable fields and drops the reserved mode" $
      agentLaunchDeclaration
        (Just AgentLaunch {provider = Just "codex-cli", model = Just "gpt-5", effort = Just "max", mode = Just "ignored"})
        `shouldBe` AgentLaunchDeclaration
          { provider = Just "codex-cli",
            model = Just "gpt-5",
            effort = Just "max"
          }

  describe "validateAgentLaunchDeclaration" $ do
    it "accepts a declaration that states nothing" $
      validateAgentLaunchDeclaration noAgentLaunchDeclaration `shouldBe` []

    it "accepts valid provider and effort values" $
      validateAgentLaunchDeclaration (decl (Just "codex-cli") (Just "anything-goes") (Just "max")) `shouldBe` []

    it "reports an unknown provider under its key" $
      validateAgentLaunchDeclaration (decl (Just "llama") Nothing Nothing) `shouldSatisfy` \case
        [err] -> "launch.provider: " `Text.isPrefixOf` err && "Unknown agent provider" `Text.isInfixOf` err
        _ -> False

    it "reports an unknown effort under its key" $
      validateAgentLaunchDeclaration (decl Nothing Nothing (Just "ultra")) `shouldSatisfy` \case
        [err] -> "launch.effort: " `Text.isPrefixOf` err && "Unknown reasoning effort" `Text.isInfixOf` err
        _ -> False

    it "reports both invalid values at once" $
      length (validateAgentLaunchDeclaration (decl (Just "llama") Nothing (Just "ultra"))) `shouldBe` 2

    it "does not check the model, which is free-form" $
      validateAgentLaunchDeclaration (decl Nothing (Just "some-private-model-id") Nothing) `shouldBe` []

  describe "formatResolvedAgentProvenance" $ do
    it "names each field's value and source" $ do
      let pending = PendingAgentConfig AgentCmdRun baseInputs
      fmap formatResolvedAgentProvenance (resolvePendingAgentConfig pending (decl Nothing (Just "claude-sonnet-5") (Just "max")))
        `shouldBe` Right
          "provider claude-cli [built-in default], model claude-sonnet-5 [blueprint: launch.model], effort max [blueprint: launch.effort], trace off [built-in default]"

    it "reports an unset effort rather than omitting it" $ do
      let pending = PendingAgentConfig AgentCmdPromptRun baseInputs
      fmap formatResolvedAgentProvenance (resolvePendingAgentConfig pending noAgentLaunchDeclaration)
        `shouldBe` Right
          "provider claude-cli [built-in default], model claude-opus-4-8 [built-in default], effort <unset> [built-in default], trace off [built-in default]"

  describe "resolvePendingAgentConfig" $ do
    it "projects down to the config the launch layer consumes" $ do
      let pending = PendingAgentConfig AgentCmdRun baseInputs
      fmap resolvedAgentModelConfig (resolvePendingAgentConfig pending (decl (Just "codex-cli") Nothing (Just "high")))
        `shouldBe` Right
          AgentModelConfig
            { provider = AgentProviderCodexCli,
              model = Just "gpt-5.6-terra",
              effort = Just ThinkingHigh,
              trace = TraceOff,
              tracePath = Nothing
            }

-- | Build an 'AgentLaunchDeclaration' from the three resolvable fields.
decl :: Maybe Text -> Maybe Text -> Maybe Text -> AgentLaunchDeclaration
decl provider model effort =
  AgentLaunchDeclaration
    { provider = provider,
      model = model,
      effort = effort
    }

-- | Fold a declaration into an inputs record, the way
-- 'resolvePendingAgentConfig' does.
declaring :: AgentLaunchDeclaration -> AgentConfigInputs -> AgentConfigInputs
declaring d inputs =
  inputs
    { declaredProvider = d.provider,
      declaredModel = d.model,
      declaredEffort = d.effort
    }

providerOf :: AgentCommandName -> AgentConfigInputs -> Either Text (AgentProvider, AgentConfigSource)
providerOf c inputs =
  (\(p, _, _, _) -> (p.value, p.source)) <$> resolveAgentModelConfigFor c inputs

modelOf :: AgentCommandName -> AgentConfigInputs -> Either Text (Maybe Text, AgentConfigSource)
modelOf c inputs =
  (\(_, m, _, _) -> (m.value, m.source)) <$> resolveAgentModelConfigFor c inputs

effortOf :: AgentCommandName -> AgentConfigInputs -> Either Text (Maybe ThinkingLevel, AgentConfigSource)
effortOf c inputs =
  (\(_, _, e, _) -> (e.value, e.source)) <$> resolveAgentModelConfigFor c inputs

traceOf :: AgentCommandName -> AgentConfigInputs -> Either Text (TraceSetting, AgentConfigSource)
traceOf c inputs =
  (\(_, _, _, t) -> (t.value, t.source)) <$> resolveAgentModelConfigFor c inputs

-- | Build an expected 'AgentModelConfig' with effort unset (the flat resolver
-- never sets effort).
cfg :: AgentProvider -> Maybe Text -> AgentModelConfig
cfg provider model =
  AgentModelConfig
    { provider = provider,
      model = model,
      effort = Nothing,
      trace = TraceOff,
      tracePath = Nothing
    }

baseInputs :: AgentConfigInputs
baseInputs = baseAgentConfigInputs

config :: Text -> Text -> Map.Map Text Text
config provider model =
  Map.fromList
    [ (agentProviderConfigKey, provider),
      (agentModelConfigKey, model)
    ]
