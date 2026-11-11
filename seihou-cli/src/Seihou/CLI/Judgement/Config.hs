-- | The local review route for judgements.
--
-- A route is a machine-local choice of provider and model, never project
-- intent: the manifest records only what a project permits (its data
-- policy), and a route can narrow that but never broaden it. Judgements have
-- their own settings; the interactive @agent.*@ configuration does not
-- silently become an unattended reviewer.
--
-- Precedence, highest first: @SEIHOU_JUDGEMENT_PROVIDER@ /
-- @SEIHOU_JUDGEMENT_MODEL@, then the project-local and global
-- @judgement.provider@ / @judgement.model@ configuration keys. A provider
-- without a model is an error: no model identifier is guessed.
module Seihou.CLI.Judgement.Config
  ( judgementProviderConfigKey,
    judgementModelConfigKey,
    judgementProviderEnvVar,
    judgementModelEnvVar,
    resolveJudgementRoute,
    resolveJudgementRouteFrom,
  )
where

import Control.Applicative ((<|>))
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Seihou.CLI.AgentCompletion (providerFromText)
import Seihou.CLI.Judgement.Runtime (JudgementRoute (..))
import Seihou.CLI.Shared (formatConfigError)
import Seihou.Effect.ConfigReader (readGlobalConfig, readLocalConfig)
import Seihou.Effect.ConfigReaderInterp (runConfigReader)
import Seihou.Prelude
import System.Environment (lookupEnv)

judgementProviderConfigKey, judgementModelConfigKey :: Text
judgementProviderConfigKey = "judgement.provider"
judgementModelConfigKey = "judgement.model"

judgementProviderEnvVar, judgementModelEnvVar :: String
judgementProviderEnvVar = "SEIHOU_JUDGEMENT_PROVIDER"
judgementModelEnvVar = "SEIHOU_JUDGEMENT_MODEL"

-- | Resolve a route from explicit sources: environment values, then local
-- and global configuration maps. 'Right Nothing' means no route is
-- configured.
resolveJudgementRouteFrom :: (Maybe Text, Maybe Text) -> Map Text Text -> Map Text Text -> Either Text (Maybe JudgementRoute)
resolveJudgementRouteFrom (envProvider, envModel) local global =
  case (pick envProvider judgementProviderConfigKey, pick envModel judgementModelConfigKey) of
    (Nothing, Nothing) -> Right Nothing
    (Nothing, Just _) -> Left ("judgement.model is set but judgement.provider is not; set it with seihou config set " <> judgementProviderConfigKey <> " PROVIDER")
    (Just _, Nothing) -> Left ("judgement.provider is set but judgement.model is not; set it with seihou config set " <> judgementModelConfigKey <> " MODEL")
    (Just p, Just m) -> do
      provider <- providerFromText p
      pure (Just (JudgementRoute provider m))
  where
    pick env key = nonEmpty env <|> nonEmpty (Map.lookup key local) <|> nonEmpty (Map.lookup key global)
    nonEmpty = (>>= \t -> if T.null (T.strip t) then Nothing else Just (T.strip t))

-- | Resolve the route from this process's environment and configuration.
resolveJudgementRoute :: IO (Either Text (Maybe JudgementRoute))
resolveJudgementRoute = do
  envProvider <- fmap T.pack <$> lookupEnv judgementProviderEnvVar
  envModel <- fmap T.pack <$> lookupEnv judgementModelEnvVar
  (localResult, globalResult) <- runEff $ runConfigReader $ (,) <$> readLocalConfig <*> readGlobalConfig
  pure $ do
    local <- first formatConfigError localResult
    global <- first formatConfigError globalResult
    resolveJudgementRouteFrom (envProvider, envModel) local global
