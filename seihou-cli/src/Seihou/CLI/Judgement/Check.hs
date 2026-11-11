-- | @seihou check@: run the project's active judgements over the staged
-- changes and report a decision.
--
-- A check is read-only. It reads the recorded definition snapshots and
-- policy from the manifest, captures the staged index, and never stages,
-- unstages, writes the manifest or changes hook setup. A dry run makes no
-- model request and never claims approval.
--
-- The services a check uses are passed in, so tests drive the same path with
-- a stub backend and production builds them from local configuration.
module Seihou.CLI.Judgement.Check
  ( CheckRequest (..),
    CheckServices (..),
    CheckOutcome (..),
    BackendChoice (..),
    runCheck,
    productionServices,
    loadActiveJudgements,
    loadPolicyAt,
    parseRange,
  )
where

import Control.Monad (forM)
import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy qualified as LBS
import Data.Foldable (toList)
import Data.Generics.Labels ()
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Seihou.CLI.AgentCompletion (providerToText)
import Seihou.CLI.Judgement.Config (resolveJudgementRoute)
import Seihou.CLI.Judgement.Evidence
import Seihou.CLI.Judgement.Execute
import Seihou.CLI.Judgement.Report
import Seihou.CLI.Judgement.Runtime (JudgementBackend, RouteObservation, isRemoteRoute, productionRunner, shikumiBackend)
import Seihou.CLI.Judgement.Scanner (findScanner)
import Seihou.Core.Judgement
import Seihou.Core.Types (ActiveJudgement)
import Seihou.Effect.FilesystemInterp (runFilesystem)
import Seihou.Effect.ManifestStore (readManifest)
import Seihou.Effect.ManifestStoreInterp (runManifestStore)
import Seihou.Manifest.Types (manifestFromJSON)
import Seihou.Prelude

data CheckRequest = CheckRequest
  { -- | One active judgement to run for diagnosis; 'Nothing' runs them all.
    judgement :: !(Maybe Text),
    -- | @BASE..HEAD@ instead of the staged changes.
    range :: !(Maybe (Text, Text)),
    dryRun :: !Bool,
    json :: !Bool
  }
  deriving stock (Eq, Show, Generic)

-- | The review route chosen for one judgement.
data BackendChoice = BackendChoice
  { backend :: !(Maybe JudgementBackend),
    -- | Whether the route sends material to a hosted service.
    remote :: !Bool,
    -- | How the route is named in reports, e.g. @claude-cli claude-sonnet-5-5@.
    label :: !(Maybe Text)
  }
  deriving stock (Generic)

data CheckServices = CheckServices
  { git :: !GitRunner,
    scanner :: !(Maybe FilePath),
    -- | Resolve the route for a definition. 'Left' is a configuration error.
    backendFor :: !(JudgementDefinition -> IO (Either Text BackendChoice))
  }
  deriving stock (Generic)

data CheckOutcome = CheckOutcome
  { exitCode :: !Int,
    output :: !Text
  }
  deriving stock (Eq, Show, Generic)

-- | Services built from this checkout and the local judgement route.
productionServices :: FilePath -> IO CheckServices
productionServices root = do
  sc <- findScanner
  pure
    CheckServices
      { git = gitBytes root,
        scanner = sc,
        backendFor = \def ->
          resolveJudgementRoute >>= \case
            Left err -> pure (Left err)
            Right Nothing -> pure (Right (BackendChoice Nothing False Nothing))
            Right (Just route) -> do
              (runner, observed) <- productionRunner (def ^. #limits) route
              pure
                ( Right
                    ( BackendChoice
                        (Just (shikumiBackend runner Nothing observed))
                        (isRemoteRoute route)
                        (Just (providerToText (route ^. #provider) <> " " <> route ^. #model))
                    )
                )
      }

-- | Read the active judgements from @.seihou/manifest.json@ under a project
-- root without changing anything. A missing manifest, or one older than
-- judgement state, has no active judgements.
loadActiveJudgements :: FilePath -> IO (Either Text [ActiveJudgement])
loadActiveJudgements root =
  runEff (runFilesystem (runManifestStore (root </> ".seihou" </> "manifest.json") readManifest)) <&> \case
    Left err -> Left ("Cannot read .seihou/manifest.json: " <> err)
    Right Nothing -> Right []
    Right (Just m) -> Right (m ^. #judgements)

-- | Read the active judgements recorded at a trusted ref, from Git objects
-- only: nothing is checked out, and the working tree's manifest, which the
-- change under test may have weakened, is not consulted.
loadPolicyAt :: GitRunner -> Text -> IO (Either Text [ActiveJudgement])
loadPolicyAt git ref =
  git ["rev-parse", "--verify", "--quiet", T.unpack ref <> "^{commit}"] >>= \case
    Left _ -> pure (Left ("The policy ref '" <> ref <> "' does not name a commit in this clone; fetch it first."))
    Right raw -> do
      let commit = T.unpack (T.strip (TE.decodeUtf8 raw))
      git ["cat-file", "-e", commit <> ":.seihou/manifest.json"] >>= \case
        Left _ -> pure (Left ("No trusted policy exists at " <> ref <> ": it has no .seihou/manifest.json. First adoption needs an explicit review of the proposed policy, not a check against it."))
        Right _ ->
          git ["cat-file", "blob", commit <> ":.seihou/manifest.json"] <&> \case
            Left err -> Left err
            Right bytes -> case manifestFromJSON (LBS.fromStrict bytes) of
              Left err -> Left ("The manifest at " <> ref <> " cannot be read: " <> T.pack err)
              Right m -> Right (m ^. #judgements)

-- | Parse @BASE..HEAD@.
parseRange :: Text -> Either Text (Text, Text)
parseRange t = case T.splitOn ".." t of
  [b, h] | not (T.null b), not (T.null h), not ("." `T.isPrefixOf` h) -> Right (b, h)
  _ -> Left ("'" <> t <> "' is not a range; write BASE..HEAD, for example origin/main..HEAD")

failure :: Bool -> Text -> CheckOutcome
failure asJson msg
  | asJson = CheckOutcome 1 (encodeJson (Aeson.object ["version" Aeson..= reportVersion, "status" Aeson..= ("error" :: Text), "exitCode" Aeson..= (1 :: Int), "error" Aeson..= msg, "judgements" Aeson..= ([] :: [Aeson.Value])]))
  | otherwise = CheckOutcome 1 (msg <> "\n")

encodeJson :: Aeson.Value -> Text
encodeJson = (<> "\n") . TE.decodeUtf8 . LBS.toStrict . Aeson.encode

runCheck :: CheckServices -> [ActiveJudgement] -> CheckRequest -> IO CheckOutcome
runCheck services active req = case selected of
  Left msg -> pure (failure (req ^. #json) msg)
  Right [] ->
    pure $
      if req ^. #json
        then CheckOutcome 0 (encodeJson (renderJson []))
        else CheckOutcome 0 "No judgements are active in this project; nothing was checked.\n"
  Right candidates ->
    capture >>= \case
      Left err -> pure (failure (req ^. #json) ("Cannot read the " <> scopeLabel <> ": " <> err))
      Right snap
        | null judgements -> pure (CheckOutcome 0 (T.unlines notApplicable <> "Nothing was checked.\n"))
        | req ^. #dryRun -> (\o -> o & #output %~ (T.unlines notApplicable <>)) <$> dryRunReport judgements snap
        | otherwise -> (\o -> if req ^. #json then o else o & #output %~ (T.unlines notApplicable <>)) <$> runAll judgements snap
    where
      wanted = maybe StagedChangesScope (const CommitRangeScope) (req ^. #range)
      declares j = wanted `elem` (j ^. #definition . #evidence . #scopes)
      judgements = filter declares candidates
      notApplicable = [j ^. #definition . #name <> ": not checked; it does not declare " <> renderScopeKind wanted <> " evidence" | j <- candidates, not (declares j)]
  where
    capture = case req ^. #range of
      Nothing -> captureStaged defaultCoverageLimits (services ^. #git)
      Just (b, h) -> captureRange defaultCoverageLimits (services ^. #git) b h
    scopeLabel = case req ^. #range of
      Nothing -> "staged changes"
      Just (b, h) -> "commits " <> b <> ".." <> h
    selected = case req ^. #judgement of
      Nothing -> Right active
      Just n -> case [j | j <- active, j ^. #definition . #name == n] of
        [] -> Left ("Judgement '" <> n <> "' is not active in this project; adopt it with seihou run " <> n)
        js -> Right js

    runAll judgements snap = do
      results <- forM judgements $ \j -> do
        let def = j ^. #definition
        (services ^. #backendFor) def >>= \case
          Left err -> pure (Left (def ^. #name <> ": " <> err))
          Right choice -> do
            let exec = JudgementExecution (j ^. #policy) (choice ^. #backend) (choice ^. #remote) (services ^. #scanner)
            obs <- runJudgement exec def snap
            routeSeen <- maybe (pure []) (^. #observed) (choice ^. #backend)
            pure (Right (def, decideJudgement def (j ^. #policy) obs, choice ^. #label, routeSeen))
      case sequence results of
        Left err -> pure (failure (req ^. #json) err)
        Right decided -> do
          let overall = combinedStatus [d ^. #status | (_, d, _, _) <- decided]
              code = exitCodeFor overall
          pure $
            if req ^. #json
              then CheckOutcome code (encodeJson (renderJson [(def, d) | (def, d, _, _) <- decided]))
              else CheckOutcome code (T.concat [renderHumanFor scopeLabel def d <> routeLines lbl seen | (def, d, lbl, seen) <- decided])

    routeLines :: Maybe Text -> [RouteObservation] -> Text
    routeLines lbl seen = case (lbl, seen) of
      (Nothing, _) -> ""
      (Just l, []) -> "Route: " <> l <> " (no request was sent)\n"
      (Just l, obs) ->
        "Route: " <> l <> "; observed " <> T.intercalate ", " (dedupe [o ^. #observedModel | o <- obs]) <> " over " <> T.pack (show (length obs)) <> " request(s)\n"

    dedupe = foldr (\x acc -> if x `elem` acc then acc else x : acc) []

    dryRunReport judgements snap = do
      sections <- forM judgements $ \j -> do
        let def = j ^. #definition
            (sel, excluded, uncovered) = selectForDefinition def snap
            (chunks, overflow) = chunkEvidence (def ^. #limits) sel
        choice <- (services ^. #backendFor) def
        let route = case choice of
              Left err -> "not usable: " <> err
              Right c -> maybe "none configured" id (c ^. #label)
        pure $
          T.unlines $
            [ def ^. #name <> " " <> maybe "" id (def ^. #version) <> "  (" <> T.take 12 (j ^. #digest . #unSHA256) <> ")",
              "  data policy: " <> renderDataPolicy (j ^. #policy . #dataPolicy) <> "; route: " <> route,
              "  scanner: " <> maybe "not found" T.pack (services ^. #scanner),
              "  scope: " <> scopeLabel <> "; " <> T.pack (show (length sel)) <> " file(s) selected in " <> T.pack (show (length chunks)) <> " chunk(s), " <> T.pack (show (length excluded)) <> " excluded"
            ]
              <> ["  would not review: " <> T.pack p <> " (" <> why <> ")" | (p, why) <- uncovered <> overflow]
              <> [ "  check " <> c ^. #name <> ": " <> renderEnforcement (cp ^. #enforcement) <> ", pass at " <> num (cp ^. #review . #passAt) <> ", block at " <> num (cp ^. #review . #blockAt)
                 | c <- toList (def ^. #checks),
                   let cp = checkPolicyFor (j ^. #policy) c
                 ]
      pure (CheckOutcome 0 (T.concat sections <> "Dry run: no model request was made and nothing was approved.\n"))

    num = T.pack . show
