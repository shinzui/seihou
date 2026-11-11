-- | Adopting a judgement through @seihou run NAME@.
--
-- Adoption previews what changes, then publishes in an order that never
-- leaves a partial active policy: the hook first (a hook with no active
-- judgement checks nothing and passes), then the manifest, which stages the
-- lossless judgement-state schema step together with the new record.
--
-- Transmission is consent, not a default. Adoption requires a configured
-- review route and an explicit data policy: from @judgement.dataPolicy@ (or
-- @SEIHOU_JUDGEMENT_DATA_POLICY@), or from an interactive confirmation the
-- caller collects. Noninteractive adoption without one fails with the exact
-- commands to run and activates nothing.
module Seihou.CLI.Judgement.Adopt
  ( AdoptionPlan (..),
    AdoptionInputs (..),
    gatherAdoptionInputs,
    planAdoption,
    renderAdoptionPlan,
    applyAdoption,
    dataPolicyFromText,
  )
where

import Control.Exception (SomeException, displayException, try)
import Data.Foldable (toList)
import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text qualified as T
import Data.Time (getCurrentTime)
import Seihou.CLI.AgentCompletion (providerToText)
import Seihou.CLI.Judgement.Config (judgementModelConfigKey, judgementProviderConfigKey, resolveJudgementRoute)
import Seihou.CLI.Judgement.Evidence (gitBytes)
import Seihou.CLI.Judgement.Hooks
import Seihou.CLI.Judgement.Runtime (JudgementRoute)
import Seihou.CLI.Judgement.Scanner (findScanner)
import Seihou.CLI.ManifestCapabilityUpgrade (prepareJudgementState)
import Seihou.CLI.Shared (formatConfigError)
import Seihou.Core.Judgement
import Seihou.Core.Types (ActiveJudgement (..), ArtifactOrigin (..), JudgementSource (..), Manifest)
import Seihou.Effect.ConfigReader (readGlobalConfig, readLocalConfig)
import Seihou.Effect.ConfigReaderInterp (runConfigReader)
import Seihou.Effect.FilesystemInterp (runFilesystem)
import Seihou.Effect.ManifestStore (readManifest, writeManifest)
import Seihou.Effect.ManifestStoreInterp (runManifestStore)
import Seihou.Manifest.Judgement (definitionDigest)
import Seihou.Manifest.Types (emptyManifest)
import Seihou.Prelude
import System.Environment (lookupEnv)

dataPolicyFromText :: Text -> Either Text DataPolicy
dataPolicyFromText t = case T.strip t of
  "approved-remote" -> Right ApprovedRemote
  "local-only" -> Right LocalOnly
  other -> Left ("unknown judgement data policy '" <> other <> "'; expected approved-remote or local-only")

-- | What the local machine supplies to an adoption.
data AdoptionInputs = AdoptionInputs
  { route :: !(Maybe JudgementRoute),
    -- | The data policy stated in configuration, if any.
    configuredPolicy :: !(Maybe DataPolicy),
    scanner :: !(Maybe FilePath)
  }
  deriving stock (Eq, Show, Generic)

gatherAdoptionInputs :: IO (Either Text AdoptionInputs)
gatherAdoptionInputs = do
  routeResult <- resolveJudgementRoute
  envPolicy <- fmap T.pack <$> lookupEnv "SEIHOU_JUDGEMENT_DATA_POLICY"
  (localResult, globalResult) <- runEff $ runConfigReader $ (,) <$> readLocalConfig <*> readGlobalConfig
  sc <- findScanner
  pure $ do
    r <- routeResult
    local <- first formatConfigError localResult
    global <- first formatConfigError globalResult
    let raw = case envPolicy of
          Just v | not (T.null (T.strip v)) -> Just v
          _ -> Map.lookup "judgement.dataPolicy" local `orElse` Map.lookup "judgement.dataPolicy" global
    policy <- traverse dataPolicyFromText raw
    pure (AdoptionInputs r policy sc)
  where
    orElse (Just a) _ = Just a
    orElse Nothing b = b

data AdoptionPlan = AdoptionPlan
  { root :: !FilePath,
    active :: !ActiveJudgement,
    -- | The record this replaces, when the judgement is already active.
    previous :: !(Maybe ActiveJudgement),
    hook :: !HookPlan,
    routeLabel :: !Text,
    scanner :: !FilePath
  }
  deriving stock (Eq, Show, Generic)

-- | Validate, resolve the policy and plan the hook. 'Left' names exactly
-- what to configure; nothing has been written.
planAdoption :: FilePath -> AdoptionInputs -> Maybe DataPolicy -> JudgementSource -> JudgementDefinition -> IO (Either Text AdoptionPlan)
planAdoption root inputs consent source def = case validateDefinition def of
  Left err -> pure (Left ("judgement '" <> def ^. #name <> "' is invalid: " <> err ^. #message))
  Right () -> case inputs ^. #route of
    Nothing ->
      pure . Left $
        T.unlines
          [ "Judgement '" <> def ^. #name <> "' needs a review route before it can be adopted. Set one, for example:",
            "  seihou config set " <> judgementProviderConfigKey <> " claude-cli",
            "  seihou config set " <> judgementModelConfigKey <> " MODEL",
            "Then run seihou run " <> def ^. #name <> " again. Nothing was activated."
          ]
    Just r -> case consent of
      Nothing ->
        pure . Left $
          T.unlines
            [ "Judgement '" <> def ^. #name <> "' sends staged file contents to " <> label r <> ", a hosted service.",
              "Record that this project permits it, then run seihou run " <> def ^. #name <> " again:",
              "  seihou config set judgement.dataPolicy approved-remote",
              "Nothing was activated."
            ]
      Just LocalOnly ->
        pure (Left ("The data policy is local-only, and every review route in this release sends material to a hosted service, so judgement '" <> def ^. #name <> "' could never pass. Nothing was activated."))
      Just ApprovedRemote -> case inputs ^. #scanner of
        Nothing ->
          pure (Left "Judgements scan every outgoing request for credentials with gitleaks, which was not found. Install gitleaks (or set SEIHOU_GITLEAKS to its path), then run again. Nothing was activated.")
        Just sc -> do
          existing <- readExisting root
          hookPlan <- planHook root (gitBytes root)
          pure $ do
            manifest <- existing
            hp <- hookPlan
            let record = ActiveJudgement source def (definitionDigest def) (defaultPolicy ApprovedRemote False def)
                prior = case [j | j <- manifest ^. #judgements, j ^. #definition . #name == def ^. #name] of
                  (j : _) -> Just j
                  [] -> Nothing
            pure (AdoptionPlan root record prior hp (label r) sc)
  where
    label r = providerToText (r ^. #provider) <> " " <> r ^. #model

readExisting :: FilePath -> IO (Either Text Manifest)
readExisting root = do
  now <- getCurrentTime
  runEff (runFilesystem (runManifestStore (manifestPathFor root) readManifest)) <&> \case
    Left err -> Left ("Cannot read .seihou/manifest.json: " <> err)
    Right m -> Right (fromMaybe (emptyManifest now) m)

manifestPathFor :: FilePath -> FilePath
manifestPathFor root = root </> ".seihou" </> "manifest.json"

renderAdoptionPlan :: AdoptionPlan -> Text
renderAdoptionPlan p =
  T.unlines $
    [ "Judgement '" <> def ^. #name <> "' " <> fromMaybe "(unversioned)" (def ^. #version) <> " from " <> sourceText (p ^. #active . #source),
      "  definition digest: " <> T.take 16 (p ^. #active . #digest . #unSHA256),
      "  " <> status,
      "  data policy: approved-remote; review route: " <> p ^. #routeLabel <> " (staged file contents are sent there)",
      "  deterministic checks: " <> if null (def ^. #deterministicChecks) then "none" else T.intercalate ", " (map renderDeterministicCheck (def ^. #deterministicChecks)),
      "  transmission safeguard: " <> T.pack (p ^. #scanner),
      "  " <> renderHookPlan (p ^. #hook)
    ]
      <> [ "  check " <> c ^. #name <> " (" <> renderEnforcement (c ^. #enforcement) <> "): concern when " <> renderAnswer (c ^. #concernWhen) <> "; pass at " <> num (c ^. #review . #passAt) <> ", block at " <> num (c ^. #review . #blockAt)
         | c <- toList (def ^. #checks)
         ]
  where
    def = p ^. #active . #definition
    num = T.pack . show
    status = case p ^. #previous of
      Nothing -> "new: becomes active for every commit in this checkout"
      Just prev
        | prev == p ^. #active -> "already active with this definition and policy; nothing changes"
        | otherwise -> "replaces the active definition " <> T.take 16 (prev ^. #digest . #unSHA256)
    sourceText = \case
      BundledJudgement -> "the catalogue built into seihou"
      ArtifactJudgement (RemoteOrigin url _ _) -> url
      ArtifactJudgement (ProjectOrigin path) -> "project:" <> T.pack path
      ArtifactJudgement (LocalOrigin name) -> name <> " (unverified local origin)"

-- | Publish: hook first, then the manifest.
applyAdoption :: AdoptionPlan -> IO (Either Text ())
applyAdoption p =
  applyHook (p ^. #hook) >>= \case
    Left err -> pure (Left (err <> ". Nothing was activated."))
    Right () ->
      readExisting (p ^. #root) >>= \case
        Left err -> pure (Left err)
        Right manifest -> case prepareJudgementState manifest of
          Left err -> pure (Left ("Cannot stage the judgement manifest schema: " <> err))
          Right prepared -> do
            let others = [j | j <- prepared ^. #judgements, j ^. #definition . #name /= p ^. #active . #definition . #name]
                updated = prepared & #judgements .~ (others <> [p ^. #active])
            try (runEff (runFilesystem (runManifestStore (manifestPathFor (p ^. #root)) (writeManifest updated)))) <&> \case
              Left (err :: SomeException) -> Left ("Cannot write .seihou/manifest.json: " <> T.pack (displayException err))
              Right () -> Right ()
