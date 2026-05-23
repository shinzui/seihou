module Seihou.CLI.AgentConfig
  ( AgentConfigInputs (..),
    agentProviderConfigKey,
    agentModelConfigKey,
    agentProviderEnvVar,
    agentModelEnvVar,
    resolveAgentModelConfig,
    loadAgentModelConfig,
  )
where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Seihou.CLI.AgentCompletion
  ( AgentModelConfig (..),
    defaultAgentModelConfig,
    providerFromText,
  )
import Seihou.CLI.Shared (formatConfigError)
import Seihou.Effect.ConfigReader (readGlobalConfig, readLocalConfig)
import Seihou.Effect.ConfigReaderInterp (runConfigReader)
import Seihou.Prelude
import System.Environment (lookupEnv)

data AgentConfigInputs = AgentConfigInputs
  { cliProvider :: Maybe Text,
    cliModel :: Maybe Text,
    envProvider :: Maybe Text,
    envModel :: Maybe Text,
    localConfig :: Map Text Text,
    globalConfig :: Map Text Text
  }
  deriving stock (Eq, Show)

agentProviderConfigKey :: Text
agentProviderConfigKey = "agent.provider"

agentModelConfigKey :: Text
agentModelConfigKey = "agent.model"

agentProviderEnvVar :: String
agentProviderEnvVar = "SEIHOU_AGENT_PROVIDER"

agentModelEnvVar :: String
agentModelEnvVar = "SEIHOU_AGENT_MODEL"

resolveAgentModelConfig :: AgentConfigInputs -> Either Text AgentModelConfig
resolveAgentModelConfig inputs = do
  provider <-
    maybe
      (Right defaultAgentModelConfig.agentProvider)
      providerFromText
      (firstNonBlank [inputs.cliProvider, inputs.envProvider, configValue inputs.localConfig agentProviderConfigKey, configValue inputs.globalConfig agentProviderConfigKey])
  pure
    AgentModelConfig
      { agentProvider = provider,
        agentModel = firstNonBlank [inputs.cliModel, inputs.envModel, configValue inputs.localConfig agentModelConfigKey, configValue inputs.globalConfig agentModelConfigKey]
      }

loadAgentModelConfig :: Maybe Text -> Maybe Text -> IO (Either Text AgentModelConfig)
loadAgentModelConfig cliProvider cliModel = do
  envProvider <- fmap T.pack <$> lookupEnv agentProviderEnvVar
  envModel <- fmap T.pack <$> lookupEnv agentModelEnvVar
  (localResult, globalResult) <- runEff $ runConfigReader $ do
    local <- readLocalConfig
    global <- readGlobalConfig
    pure (local, global)
  pure $ do
    local <- first formatConfigError localResult
    global <- first formatConfigError globalResult
    resolveAgentModelConfig
      AgentConfigInputs
        { cliProvider = cliProvider,
          cliModel = cliModel,
          envProvider = envProvider,
          envModel = envModel,
          localConfig = local,
          globalConfig = global
        }

configValue :: Map Text Text -> Text -> Maybe Text
configValue config key = Map.lookup key config

firstNonBlank :: [Maybe Text] -> Maybe Text
firstNonBlank =
  foldr
    ( \candidate acc ->
        case T.strip <$> candidate of
          Just "" -> acc
          Just value -> Just value
          Nothing -> acc
    )
    Nothing
