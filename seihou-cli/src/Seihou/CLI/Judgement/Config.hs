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
--
-- The optional gate route resolves the same way from
-- @SEIHOU_JUDGEMENT_GATE_PROVIDER@ / @SEIHOU_JUDGEMENT_GATE_MODEL@ and
-- @judgement.gateProvider@ / @judgement.gateModel@. The gate must be a model
-- Baikai's catalogue marks judgment-only, and such a model is refused as the
-- review route, because it cannot return located findings.
module Seihou.CLI.Judgement.Config
  ( judgementProviderConfigKey,
    judgementModelConfigKey,
    judgementGateProviderConfigKey,
    judgementGateModelConfigKey,
    judgementProviderEnvVar,
    judgementModelEnvVar,
    judgementGateProviderEnvVar,
    judgementGateModelEnvVar,
    resolveJudgementRoute,
    resolveJudgementRouteFrom,
    resolveGateRoute,
    resolveGateRouteFrom,
    validateReviewProvider,
    validateGateRoute,
  )
where

import Control.Applicative ((<|>))
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Seihou.CLI.AgentCompletion (providerFromText)
import Seihou.CLI.Judgement.Runtime (GateRoute (..), JudgementRoute (..), gateProviderName, isJudgmentOnlyModelId)
import Seihou.CLI.Shared (formatConfigError)
import Seihou.Effect.ConfigReader (readGlobalConfig, readLocalConfig)
import Seihou.Effect.ConfigReaderInterp (runConfigReader)
import Seihou.Prelude
import System.Environment (lookupEnv)

judgementProviderConfigKey, judgementModelConfigKey :: Text
judgementProviderConfigKey = "judgement.provider"
judgementModelConfigKey = "judgement.model"

judgementGateProviderConfigKey, judgementGateModelConfigKey :: Text
judgementGateProviderConfigKey = "judgement.gateProvider"
judgementGateModelConfigKey = "judgement.gateModel"

judgementProviderEnvVar, judgementModelEnvVar, judgementGateProviderEnvVar, judgementGateModelEnvVar :: String
judgementProviderEnvVar = "SEIHOU_JUDGEMENT_PROVIDER"
judgementModelEnvVar = "SEIHOU_JUDGEMENT_MODEL"
judgementGateProviderEnvVar = "SEIHOU_JUDGEMENT_GATE_PROVIDER"
judgementGateModelEnvVar = "SEIHOU_JUDGEMENT_GATE_MODEL"

judgmentOnlyAsReview :: Text -> Text
judgmentOnlyAsReview what =
  what
    <> " is judgment-only: it answers closed questions but cannot return located findings, so it cannot be the review route. \
       \Configure it as the gate instead, with seihou config set "
    <> judgementGateProviderConfigKey
    <> " "
    <> gateProviderName
    <> " and seihou config set "
    <> judgementGateModelConfigKey
    <> " MODEL."

-- | Refuse a provider or model that cannot be the review route.
validateReviewProvider :: Text -> Maybe Text -> Either Text ()
validateReviewProvider p m
  | T.toLower (T.strip p) == gateProviderName = Left (judgmentOnlyAsReview ("The provider '" <> gateProviderName <> "'"))
  | Just md <- m, isJudgmentOnlyModelId (T.strip md) = Left (judgmentOnlyAsReview ("The model '" <> T.strip md <> "'"))
  | otherwise = () <$ providerFromText p

-- | Check a gate provider and model against the catalogue.
validateGateRoute :: Text -> Text -> Either Text GateRoute
validateGateRoute p m
  | T.toLower (T.strip p) /= gateProviderName =
      Left
        ( "The gate must be a judgment-only model, and '"
            <> T.strip p
            <> "' is not a judgment-only provider; the only one in this build is "
            <> gateProviderName
            <> ". A generative model belongs in judgement.provider."
        )
  | not (isJudgmentOnlyModelId (T.strip m)) =
      Left ("'" <> T.strip m <> "' is not a judgment-only model in Baikai's catalogue, so it cannot be the gate; for " <> gateProviderName <> " use jev-latest or jev-preview.")
  | otherwise = Right (GateRoute (T.strip m))

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
      validateReviewProvider p (Just m)
      provider <- providerFromText p
      pure (Just (JudgementRoute provider m))
  where
    pick = pickSetting local global

pickSetting :: Map Text Text -> Map Text Text -> Maybe Text -> Text -> Maybe Text
pickSetting local global env key = nonEmpty env <|> nonEmpty (Map.lookup key local) <|> nonEmpty (Map.lookup key global)
  where
    nonEmpty = (>>= \t -> if T.null (T.strip t) then Nothing else Just (T.strip t))

-- | Resolve the gate route from explicit sources. 'Right Nothing' means no
-- gate is configured, which is the normal case.
resolveGateRouteFrom :: (Maybe Text, Maybe Text) -> Map Text Text -> Map Text Text -> Either Text (Maybe GateRoute)
resolveGateRouteFrom (envProvider, envModel) local global =
  case (pick envProvider judgementGateProviderConfigKey, pick envModel judgementGateModelConfigKey) of
    (Nothing, Nothing) -> Right Nothing
    (Nothing, Just _) -> Left ("judgement.gateModel is set but judgement.gateProvider is not; set it with seihou config set " <> judgementGateProviderConfigKey <> " " <> gateProviderName)
    (Just _, Nothing) -> Left ("judgement.gateProvider is set but judgement.gateModel is not; set it with seihou config set " <> judgementGateModelConfigKey <> " MODEL")
    (Just p, Just m) -> Just <$> validateGateRoute p m
  where
    pick = pickSetting local global

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

-- | Resolve the gate route from this process's environment and configuration.
resolveGateRoute :: IO (Either Text (Maybe GateRoute))
resolveGateRoute = do
  envProvider <- fmap T.pack <$> lookupEnv judgementGateProviderEnvVar
  envModel <- fmap T.pack <$> lookupEnv judgementGateModelEnvVar
  (localResult, globalResult) <- runEff $ runConfigReader $ (,) <$> readLocalConfig <*> readGlobalConfig
  pure $ do
    local <- first formatConfigError localResult
    global <- first formatConfigError globalResult
    resolveGateRouteFrom (envProvider, envModel) local global
