-- | @seihou judgement configure NAME@: choose the review route and data
-- policy, and change an active judgement's per-check enforcement and
-- thresholds.
--
-- The route (provider and model) is local configuration. The data policy is
-- read from configuration at adoption and, once the judgement is active, is
-- part of its recorded policy. Enforcement and thresholds are project
-- policy and change only an active judgement, through a previewed, atomic
-- manifest write. No credential is stored anywhere by this command.
module Seihou.CLI.Judgement.Configure
  ( ConfigureRequest (..),
    CheckOverride (..),
    ConfigurePlan (..),
    planConfigure,
    renderConfigurePlan,
    applyConfigure,
  )
where

import Control.Exception (SomeException, displayException, try)
import Control.Monad (forM_, when)
import Data.Foldable (toList)
import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust)
import Data.Text qualified as T
import Seihou.CLI.AgentCompletion (providerFromText)
import Seihou.CLI.Judgement.Config (judgementModelConfigKey, judgementProviderConfigKey)
import Seihou.Core.Judgement
import Seihou.Core.Types (ActiveJudgement, ConfigScope (..), Manifest)
import Seihou.Effect.ConfigWriter (writeConfigValue)
import Seihou.Effect.ConfigWriterInterp (runConfigWriter)
import Seihou.Effect.FilesystemInterp (runFilesystem)
import Seihou.Effect.ManifestStore (readManifest, writeManifest)
import Seihou.Effect.ManifestStoreInterp (runManifestStore)
import Seihou.Prelude

data CheckOverride = CheckOverride
  { enforcement :: !(Maybe Enforcement),
    blockAt :: !(Maybe Double),
    passAt :: !(Maybe Double),
    gateBlockAt :: !(Maybe Double),
    gatePassAt :: !(Maybe Double)
  }
  deriving stock (Eq, Show, Generic)

data ConfigureRequest = ConfigureRequest
  { name :: !Text,
    provider :: !(Maybe Text),
    model :: !(Maybe Text),
    dataPolicy :: !(Maybe DataPolicy),
    gateProvider :: !(Maybe Text),
    gateModel :: !(Maybe Text),
    noGate :: !Bool,
    -- | The check the overrides apply to; 'Nothing' means every check, which
    -- only @--enforcement@ may target.
    check :: !(Maybe Text),
    overrides :: !CheckOverride,
    global :: !Bool,
    dryRun :: !Bool
  }
  deriving stock (Eq, Show, Generic)

data ConfigurePlan = ConfigurePlan
  { configWrites :: ![(Text, Text)],
    scope :: !ConfigScope,
    -- | The active judgement before and after, when policy changes.
    policyChange :: !(Maybe (ActiveJudgement, ActiveJudgement)),
    manifest :: !(Maybe Manifest)
  }
  deriving stock (Show, Generic)

manifestPath :: FilePath -> FilePath
manifestPath root = root </> ".seihou" </> "manifest.json"

-- | Decide every change, or name what is wrong. Nothing is written.
planConfigure :: FilePath -> ConfigureRequest -> IO (Either Text ConfigurePlan)
planConfigure root req = do
  existing <- runEff (runFilesystem (runManifestStore (manifestPath root) readManifest))
  pure $ do
    m <- either (Left . ("Cannot read .seihou/manifest.json: " <>)) Right existing
    when (isJust (req ^. #gateProvider) || isJust (req ^. #gateModel)) $
      Left "No judgment-only provider is available in this build of seihou, so a gate cannot be configured; the generative review decides every check."
    forM_ (req ^. #provider) $ \p -> () <$ providerFromText p
    let o = req ^. #overrides
        thresholdFlags = any isJust [o ^. #blockAt, o ^. #passAt, o ^. #gateBlockAt, o ^. #gatePassAt]
    when (thresholdFlags && not (isJust (req ^. #check))) $
      Left "Threshold flags apply to one check; name it with --check CHECK."
    let writes =
          [(judgementProviderConfigKey, p) | Just p <- [req ^. #provider]]
            <> [(judgementModelConfigKey, md) | Just md <- [req ^. #model]]
            <> [("judgement.dataPolicy", renderDataPolicy dp) | Just dp <- [req ^. #dataPolicy]]
        wantsPolicy = thresholdFlags || isJust (o ^. #enforcement) || isJust (req ^. #dataPolicy) || req ^. #noGate
        active = [j | j <- maybe [] (^. #judgements) m, j ^. #definition . #name == req ^. #name]
    change <- case (active, wantsPolicy) of
      (_, False) -> Right Nothing
      ([], True)
        | thresholdFlags || isJust (o ^. #enforcement) ->
            Left ("Judgement '" <> req ^. #name <> "' is not active, so it has no project policy to change; adopt it with seihou run " <> req ^. #name <> " first.")
        | otherwise -> Right Nothing
      (j : _, True) -> do
        let def = j ^. #definition
            names = map (^. #name) (toList (def ^. #checks))
        targets <- case req ^. #check of
          Nothing -> Right names
          Just c
            | c `elem` names -> Right [c]
            | otherwise -> Left ("Judgement '" <> req ^. #name <> "' has no check '" <> c <> "'; its checks are " <> T.intercalate ", " names)
        let adjust cp =
              cp
                & #enforcement
                %~ (\e -> fromMaybe e (o ^. #enforcement))
                & #review
                . #blockAt
                %~ (\v -> fromMaybe v (o ^. #blockAt))
                & #review
                . #passAt
                %~ (\v -> fromMaybe v (o ^. #passAt))
                & #gate
                . #blockAt
                %~ (\v -> fromMaybe v (o ^. #gateBlockAt))
                & #gate
                . #passAt
                %~ (\v -> fromMaybe v (o ^. #gatePassAt))
            newPolicy =
              (j ^. #policy)
                & #checks
                %~ (\cs -> foldr (Map.adjust adjust) cs targets)
                & #dataPolicy
                %~ (\dp -> fromMaybe dp (req ^. #dataPolicy))
                & #gatePermitted
                %~ (\g -> g && not (req ^. #noGate))
        forM_ targets $ \c -> forM_ (Map.lookup c (newPolicy ^. #checks)) $ \cp -> do
          first (^. #message) (validateThresholds ("check '" <> c <> "' review") (cp ^. #review))
          first (^. #message) (validateThresholds ("check '" <> c <> "' gate") (cp ^. #gate))
        when (newPolicy ^. #dataPolicy == LocalOnly) $
          Left "Every review route in this release sends material to a hosted service, so a local-only data policy would make this judgement fail on every commit."
        Right (Just (j, j & #policy .~ newPolicy))
    when (null writes && not (isJust change)) $
      Left "Nothing to change: give --provider, --model, --data-policy, --enforcement or --check with threshold flags."
    pure (ConfigurePlan writes (if req ^. #global then ScopeGlobal else ScopeLocal) change m)

renderConfigurePlan :: ConfigurePlan -> Text
renderConfigurePlan p =
  T.unlines $
    ["  config " <> scopeText <> ": " <> k <> " = " <> v | (k, v) <- p ^. #configWrites]
      <> maybe [] policyLines (p ^. #policyChange)
  where
    scopeText = case p ^. #scope of
      ScopeGlobal -> "global"
      _ -> "local"
    policyLines (old, new) =
      [ "  policy " <> renderDataPolicy (old ^. #policy . #dataPolicy) <> " -> " <> renderDataPolicy (new ^. #policy . #dataPolicy)
      | old ^. #policy . #dataPolicy /= new ^. #policy . #dataPolicy
      ]
        <> [ "  check " <> c <> ": " <> describe a <> " -> " <> describe b
           | (c, b) <- Map.toList (new ^. #policy . #checks),
             Just a <- [Map.lookup c (old ^. #policy . #checks)],
             a /= b
           ]
    describe cp =
      renderEnforcement (cp ^. #enforcement)
        <> ", pass "
        <> renderProbability (cp ^. #review . #passAt)
        <> " block "
        <> renderProbability (cp ^. #review . #blockAt)
        <> ", gate pass "
        <> renderProbability (cp ^. #gate . #passAt)
        <> " block "
        <> renderProbability (cp ^. #gate . #blockAt)

-- | Write configuration, then the manifest policy, each atomically.
applyConfigure :: FilePath -> ConfigurePlan -> IO (Either Text ())
applyConfigure root p = do
  wrote <- try (runEff (runConfigWriter (mapM_ (uncurry (writeConfigValue (p ^. #scope))) (p ^. #configWrites))))
  case wrote of
    Left (e :: SomeException) -> pure (Left ("Cannot write configuration: " <> T.pack (displayException e)))
    Right () -> case (p ^. #policyChange, p ^. #manifest) of
      (Just (_, new), Just m) -> do
        let updated = m & #judgements %~ map (\j -> if j ^. #definition . #name == new ^. #definition . #name then new else j)
        try (runEff (runFilesystem (runManifestStore (manifestPath root) (writeManifest updated)))) <&> \case
          Left (e :: SomeException) -> Left ("Cannot write .seihou/manifest.json: " <> T.pack (displayException e))
          Right () -> Right ()
      _ -> pure (Right ())
