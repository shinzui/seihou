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
--
-- A locally configured judgment-only gate route (@judgement.gateProvider@
-- and @judgement.gateModel@) is a second hosted destination. The preview
-- names it beside the review route, the same consent covers both, and the
-- recorded policy then permits a gate. Without a gate route the policy does
-- not permit one, and @seihou judgement configure NAME --gate-model MODEL@
-- adds it later as a previewed policy change.
module Seihou.CLI.Judgement.Adopt
  ( AdoptionPlan (..),
    AdoptionInputs (..),
    gatherAdoptionInputs,
    planAdoption,
    renderAdoptionPlan,
    applyAdoption,
    dataPolicyFromText,
    retireHookIfUnused,
    judgementHookState,
    removeDirectAdoption,
  )
where

import Control.Exception (SomeException, displayException, try)
import Data.Foldable (toList)
import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust)
import Data.Text qualified as T
import Data.Time (getCurrentTime)
import Seihou.CLI.AgentCompletion (providerToText)
import Seihou.CLI.Judgement.Config (judgementModelConfigKey, judgementProviderConfigKey, resolveGateRoute, resolveJudgementRoute)
import Seihou.CLI.Judgement.Evidence (gitBytes)
import Seihou.CLI.Judgement.Hooks
import Seihou.CLI.Judgement.Runtime (GateRoute, JudgementRoute, gateProviderName)
import Seihou.CLI.Judgement.Scanner (findScanner)
import Seihou.CLI.ManifestCapabilityUpgrade (prepareJudgementState)
import Seihou.CLI.Shared (formatConfigError)
import Seihou.Core.Judgement
import Seihou.Core.JudgementState (AdoptionChange (..), adoptWithOwner, retireOwner)
import Seihou.Core.Types (ActiveJudgement (..), ArtifactOrigin (..), JudgementOwner (..), JudgementSource (..), Manifest)
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
    scanner :: !(Maybe FilePath),
    -- | The optional judgment-only gate route.
    gateRoute :: !(Maybe GateRoute)
  }
  deriving stock (Eq, Show, Generic)

gatherAdoptionInputs :: IO (Either Text AdoptionInputs)
gatherAdoptionInputs = do
  routeResult <- resolveJudgementRoute
  gateResult <- resolveGateRoute
  envPolicy <- fmap T.pack <$> lookupEnv "SEIHOU_JUDGEMENT_DATA_POLICY"
  (localResult, globalResult) <- runEff $ runConfigReader $ (,) <$> readLocalConfig <*> readGlobalConfig
  sc <- findScanner
  pure $ do
    r <- routeResult
    g <- gateResult
    local <- first formatConfigError localResult
    global <- first formatConfigError globalResult
    let raw = case envPolicy of
          Just v | not (T.null (T.strip v)) -> Just v
          _ -> Map.lookup "judgement.dataPolicy" local `orElse` Map.lookup "judgement.dataPolicy" global
    policy <- traverse dataPolicyFromText raw
    pure (AdoptionInputs r policy sc g)
  where
    orElse (Just a) _ = Just a
    orElse Nothing b = b

data AdoptionPlan = AdoptionPlan
  { root :: !FilePath,
    active :: !ActiveJudgement,
    -- | Who this adoption adds as an owner.
    owner :: !JudgementOwner,
    -- | What adoption changes in the recorded judgements.
    change :: !AdoptionChange,
    hook :: !HookPlan,
    routeLabel :: !Text,
    -- | The gate route, when the recorded policy permits one.
    gateLabel :: !(Maybe Text),
    scanner :: !FilePath
  }
  deriving stock (Eq, Show, Generic)

-- | Validate, resolve the policy and plan the hook. 'Left' names exactly
-- what to configure; nothing has been written.
planAdoption :: FilePath -> AdoptionInputs -> Maybe DataPolicy -> JudgementOwner -> JudgementSource -> JudgementDefinition -> IO (Either Text AdoptionPlan)
planAdoption root inputs consent owner source def = case validateDefinition def of
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
            let gatePermitted = isJust (inputs ^. #gateRoute)
                record = ActiveJudgement source def (definitionDigest def) (defaultPolicy ApprovedRemote gatePermitted def) [owner]
            (_, change) <- adoptWithOwner owner record (manifest ^. #judgements)
            pure (AdoptionPlan root record owner change hp (label r) gateText sc)
  where
    label r = providerToText (r ^. #provider) <> " " <> r ^. #model
    gateText = (\g -> gateProviderName <> " " <> g ^. #model) <$> inputs ^. #gateRoute

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
      "  gate: " <> maybe "none; the review decides every check" (<> " (judgment-only; staged file contents are also sent there, and a check it clears needs no review call)") (p ^. #gateLabel),
      "  deterministic checks: " <> if null (def ^. #deterministicChecks) then "none" else T.intercalate ", " (map renderDeterministicCheck (def ^. #deterministicChecks)),
      "  transmission safeguard: " <> T.pack (p ^. #scanner),
      "  " <> renderHookPlan (p ^. #hook)
    ]
      <> [ "  check "
             <> c ^. #name
             <> " ("
             <> renderEnforcement (c ^. #enforcement)
             <> "): concern when "
             <> renderAnswer (c ^. #concernWhen)
             <> "; pass at "
             <> num (c ^. #review . #passAt)
             <> ", block at "
             <> num (c ^. #review . #blockAt)
             <> (if isJust (p ^. #gateLabel) && c ^. #useGate then "; gate pass at " <> num (c ^. #gate . #passAt) <> ", block at " <> num (c ^. #gate . #blockAt) else "")
         | c <- toList (def ^. #checks)
         ]
  where
    def = p ^. #active . #definition
    num = renderProbability
    status = case p ^. #change of
      AdoptedNew -> "new: becomes active for every commit in this checkout"
      AdoptedUnchanged -> "already active with this definition; nothing changes and its recorded policy is kept"
      AdoptedReplacing prev -> "replaces the active definition " <> T.take 16 (prev ^. #digest . #unSHA256) <> "; its policy returns to the authored defaults"
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
            case adoptWithOwner (p ^. #owner) (p ^. #active) (prepared ^. #judgements) of
              Left err -> pure (Left err)
              Right (judgements, _) ->
                try (runEff (runFilesystem (runManifestStore (manifestPathFor (p ^. #root)) (writeManifest (prepared & #judgements .~ judgements))))) <&> \case
                  Left (err :: SomeException) -> Left ("Cannot write .seihou/manifest.json: " <> T.pack (displayException err))
                  Right () -> Right ()

-- | Retire Seihou's hook when the written manifest has no active judgement.
retireHookIfUnused :: FilePath -> Manifest -> IO [Text]
retireHookIfUnused root m
  | not (null (m ^. #judgements)) = pure []
  | otherwise = either (\e -> ["pre-commit hook: " <> e]) id <$> retireOwnedHook root (gitBytes root)

-- | @seihou remove NAME@ for a directly adopted judgement: drop the direct
-- owner, and the record when no application still references it.
removeDirectAdoption :: Text -> Manifest -> Either Text (Manifest, Text)
removeDirectAdoption name m = case [j | j <- m ^. #judgements, j ^. #definition . #name == name] of
  [] -> Left ("Judgement '" <> name <> "' is not active.")
  (j : _)
    | DirectAdoption `notElem` (j ^. #owners) ->
        Left ("Judgement '" <> name <> "' was not adopted directly; it is active because a recorded application references it. Remove that application instead.")
    | otherwise ->
        let (remaining, retired) = retireOwner DirectAdoption (m ^. #judgements)
            msg =
              if name `elem` retired
                then "Judgement '" <> name <> "' is no longer active."
                else "Judgement '" <> name <> "' stays active because a recorded application still references it."
         in Right (m & #judgements .~ remaining, msg)

-- | Check, and unless dry-running repair, the hook that active judgements
-- need. Used by @seihou sync@ (repairing) and @seihou status@ (dry-run).
-- A missing hook is reinstalled from the recorded intent; a hook another
-- manager replaced is reported, never overwritten.
judgementHookState :: FilePath -> Bool -> IO (Either Text [Text])
judgementHookState root dryRun =
  readExisting root >>= \case
    Left err -> pure (Left err)
    Right m
      | null (m ^. #judgements) -> pure (Right [])
      | otherwise ->
          planHook root (gitBytes root) >>= \case
            Left err -> pure (Left ("Judgement hook: misconfigured: " <> err))
            Right (HookAlreadyInstalled p) -> pure (Right ["Judgement hook: operational (" <> T.pack p <> ")"])
            Right plan
              | dryRun -> pure (Right ["Judgement hook: missing; seihou sync would " <> renderHookPlan plan])
              | otherwise ->
                  applyHook plan <&> \case
                    Left err -> Left ("Judgement hook: " <> err)
                    Right () -> Right ["Judgement hook: repaired; " <> renderHookPlan plan]
