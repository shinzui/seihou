-- | Refreshing installed blueprints and prompts from the source each one
-- records in its @.seihou-origin.json@.
--
-- A blueprint is installed together with its @baseModules@ (its install
-- closure), after validation and import normalization. Refreshing it
-- therefore restages that whole closure exactly as @seihou install@ would,
-- compares the staged bytes with the installed ones by content hash, and
-- publishes only what changed. Publication honours ADR 0006: a cache entry in
-- the closure whose provenance names a different source, or none, is refused
-- and the cache is left untouched.
module Seihou.CLI.InstalledRunnables
  ( RefreshOptions (..),
    selectInstalledRunnables,
    installKey,
    matchesRequest,
    refreshInstalledRunnables,
    checkInstalledRunnablesForUpdates,
  )
where

import Control.Exception (SomeException, displayException, try)
import Control.Monad (forM, when)
import Data.Generics.Labels ()
import Data.List (find)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.InstallClosure (ClosureArtifact (..), publishStagedClosure, readContents, stageClosuresInto)
import Seihou.CLI.InstallShared (InstallCollision (..), OriginInfo (..), classifyInstallCollision, cloneRepo, readOriginInfo, summarizeInstallRefusal)
import Seihou.CLI.RemoteVersion (fetchTrueRunnableVersion)
import Seihou.CLI.Update.Source (hashArtifactDirectory)
import Seihou.CLI.UpgradeReport (UpgradeEntry (..), UpgradeStatus (..))
import Seihou.CLI.VersionCompare (OutdatedEntry (..), OutdatedStatus (..), compareVersions)
import Seihou.Core.ArtifactIdentity (normalizeOriginUrl)
import Seihou.Core.Install (parseModuleName)
import Seihou.Core.Module (DiscoveredRunnable (..), ModuleSource (..), RunnableKind (..))
import Seihou.Core.Registry (Registry (..), RegistryEntry (..), RepoContents (..))
import Seihou.Core.Types (ModuleName (..))
import Seihou.Prelude
import System.Directory (doesDirectoryExist)
import System.FilePath (takeFileName)
import System.IO.Temp (withSystemTempDirectory)

data RefreshOptions = RefreshOptions
  { dryRun :: !Bool,
    skipUnversioned :: !Bool
  }
  deriving stock (Eq, Show, Generic)

-- | Installed blueprints and prompts, each paired with its recorded origin.
-- Entries whose descriptor fails to load are kept: a broken installed copy is
-- exactly what a refresh can repair.
selectInstalledRunnables :: [DiscoveredRunnable] -> IO [(DiscoveredRunnable, Maybe OriginInfo)]
selectInstalledRunnables runnables =
  forM [r | r <- runnables, r ^. #source == SourceInstalled, isRefreshable (r ^. #kind)] $ \r -> do
    origin <- readOriginInfo (r ^. #dir)
    pure (r, origin)
  where
    isRefreshable KindBlueprint = True
    isRefreshable KindPrompt = True
    isRefreshable _ = False

-- | The install-cache key: the entry's directory name under @installed/@.
-- It usually equals the descriptor's name but is not guaranteed to.
installKey :: DiscoveredRunnable -> Text
installKey r = T.pack (takeFileName (r ^. #dir))

-- | A requested name selects an entry by its descriptor name or its key.
matchesRequest :: Text -> DiscoveredRunnable -> Bool
matchesRequest requested r = requested == r ^. #name || requested == installKey r

-- | Refresh each selected root's closure from its recorded source. Returns the
-- report rows (deduplicated by name, first wins) and the names of every
-- artifact in every staged closure, so a caller can keep another refresh path
-- from touching the same entries twice. Prints nothing.
refreshInstalledRunnables :: RefreshOptions -> FilePath -> [(DiscoveredRunnable, OriginInfo)] -> IO ([UpgradeEntry], [Text])
refreshInstalledRunnables opts cache inputs = do
  let groups = Map.elems (Map.fromListWith (flip (<>)) [(normalizeOriginUrl (origin ^. #sourceUrl), [(r, origin)]) | (r, origin) <- inputs])
  results <- forM groups (refreshGroup opts cache)
  let rows = concatMap fst results
      names = concatMap snd results
  pure (dedupeByName rows, Set.toList (Set.fromList names))

-- | Every member of a group shares one source URL, so one clone serves all.
refreshGroup :: RefreshOptions -> FilePath -> [(DiscoveredRunnable, OriginInfo)] -> IO ([UpgradeEntry], [Text])
refreshGroup _ _ [] = pure ([], [])
refreshGroup opts cache members@((_, firstOrigin) : _) =
  withSystemTempDirectory "seihou-runnable-upgrade" $ \tmp -> do
    let url = firstOrigin ^. #sourceUrl
        cloneDir = tmp </> "clone"
    cloned <- cloneRepo url cloneDir
    case cloned of
      Left _ -> pure ([UpgradeEntry (installKey r) (origin ^. #version) Nothing SourceUnreachable | (r, origin) <- members], [])
      Right () -> do
        contents <- try @SomeException (readContents cloneDir)
        case contents of
          Left err ->
            let reason = "could not read the registry in " <> url <> ": " <> T.pack (displayException err)
             in pure ([failedRow r origin reason | (r, origin) <- members], [])
          Right repo -> do
            results <- forM (zip [0 :: Int ..] members) $ \(index, member) ->
              refreshMember opts cache (tmp </> ("staging-" <> show index)) cloneDir url repo member
            pure (concatMap fst results, concatMap snd results)

refreshMember :: RefreshOptions -> FilePath -> FilePath -> FilePath -> Text -> RepoContents -> (DiscoveredRunnable, OriginInfo) -> IO ([UpgradeEntry], [Text])
refreshMember opts cache staging cloneDir url repo (r, origin) =
  case locateArtifact cloneDir repo (r ^. #kind) (installKey r) of
    Nothing -> pure ([failedRow r origin (kindLabel (r ^. #kind) <> " '" <> installKey r <> "' not found in " <> url)], [])
    Just artifactDir -> do
      -- The staging cache is empty, so staging itself can never refuse; the
      -- ADR 0006 check happens against the real cache at publication.
      staged <- stageClosuresInto False staging False [(cloneDir, url, [(installKey r, artifactDir)])]
      case staged of
        Left reason -> pure ([failedRow r origin reason], [])
        Right artifacts -> do
          rows <- compareAndPublish opts cache artifacts
          pure (rows, map (^. #name) artifacts)

-- | Decide each staged artifact's status as recipe upgrades do, keep a
-- skipped closure together, and publish the changed artifacts atomically.
compareAndPublish :: RefreshOptions -> FilePath -> [ClosureArtifact] -> IO [UpgradeEntry]
compareAndPublish opts cache artifacts = do
  compared <- forM artifacts $ \artifact -> do
    let path = cache </> T.unpack (artifact ^. #name)
    old <- readOriginInfo path
    present <- doesDirectoryExist path
    oldHash <- if present then Just <$> hashArtifactDirectory path else pure Nothing
    newHash <- hashArtifactDirectory (artifact ^. #directory)
    let changed = oldHash /= Just newHash
        skipped = opts ^. #skipUnversioned && (artifact ^. #version == Nothing || maybe False ((== Nothing) . (^. #version)) old)
        status
          | changed && skipped = Skipped
          | changed = Upgraded
          | otherwise = AlreadyUpToDate
    pure (UpgradeEntry (artifact ^. #name) (old >>= (^. #version)) (artifact ^. #version) status, artifact)
  let blocked = any ((== Skipped) . (^. #upgradeStatus) . fst) compared
      settled = [(if blocked && entry ^. #upgradeStatus == Upgraded then entry & #upgradeStatus .~ Skipped else entry, artifact) | (entry, artifact) <- compared]
      changes = [artifact | (entry, artifact) <- settled, entry ^. #upgradeStatus == Upgraded]
  -- Classify first so each refused row carries its own one-line reason. The
  -- closure is published all or nothing, so one refusal holds back the rest.
  collisions <- forM changes $ \artifact -> do
    collision <- classifyInstallCollision (cache </> T.unpack (artifact ^. #name)) (artifact ^. #sourceUrl)
    pure (artifact ^. #name, summarize artifact collision)
  let refusals = Map.fromList [(name, reason) | (name, Just reason) <- collisions]
      entries = map fst settled
  if not (Map.null refusals)
    then pure [refuse refusals entry | entry <- entries]
    else
      if opts ^. #dryRun || null changes
        then pure entries
        else do
          published <- publishStagedClosure cache changes
          pure $ case published of
            Right () -> entries
            Left reason -> [if entry ^. #upgradeStatus == Upgraded then entry & #upgradeStatus .~ UpgradeFailed reason else entry | entry <- entries]
  where
    summarize artifact = \case
      collision@(DifferentSource _) -> Just (summarizeInstallRefusal (artifact ^. #sourceUrl) collision)
      UnknownSource -> Just (summarizeInstallRefusal (artifact ^. #sourceUrl) UnknownSource)
      _ -> Nothing
    refuse refusals entry
      | entry ^. #upgradeStatus /= Upgraded = entry
      | Just reason <- Map.lookup (entry ^. #moduleName) refusals = entry & #upgradeStatus .~ UpgradeFailed reason
      | otherwise =
          entry
            & #upgradeStatus
            .~ UpgradeFailed ("not published: " <> T.intercalate ", " (Map.keys refusals) <> " in the same closure was refused")

-- | Compare each installed blueprint's or prompt's recorded version with the
-- version its source's descriptor declares. Reads the source only and never
-- stages, so unlike 'refreshInstalledRunnables' it compares declared versions,
-- not content. Clones once per source URL; prints @Cloning@ progress lines when
-- asked. A failed clone is 'Unreachable'; a lookup error collapses to an
-- unknown available version, shown as unversioned.
checkInstalledRunnablesForUpdates :: Bool -> [(DiscoveredRunnable, OriginInfo)] -> IO [OutdatedEntry]
checkInstalledRunnablesForUpdates progress inputs = do
  let groups = Map.elems (Map.fromListWith (flip (<>)) [(normalizeOriginUrl (origin ^. #sourceUrl), [(r, origin)]) | (r, origin) <- inputs])
  concat <$> forM groups checkGroup
  where
    checkGroup [] = pure []
    checkGroup members@((_, firstOrigin) : _) = do
      let url = firstOrigin ^. #sourceUrl
      when progress $ TIO.putStrLn ("  Cloning " <> T.pack (parseModuleName url) <> "...")
      withSystemTempDirectory "seihou-runnable-outdated" $ \tmp -> do
        let cloneDir = tmp </> "clone"
        cloned <- cloneRepo url cloneDir
        forM members $ \(r, origin) -> case cloned of
          Left _ -> pure (OutdatedEntry (installKey r) (origin ^. #version) Nothing Unreachable)
          Right () -> do
            available <- either (const Nothing) id <$> fetchTrueRunnableVersion cloneDir (r ^. #kind) (installKey r)
            pure (OutdatedEntry (installKey r) (origin ^. #version) available (compareVersions (origin ^. #version) available))

-- | Find a blueprint or prompt in a cloned source, by the key it is installed
-- under.
locateArtifact :: FilePath -> RepoContents -> RunnableKind -> Text -> Maybe FilePath
locateArtifact cloneDir contents kind key = case (contents, kind) of
  (MultiModule registry, KindBlueprint) -> byName (registry ^. #blueprints)
  (MultiModule registry, KindPrompt) -> byName (registry ^. #prompts)
  (SingleBlueprint root, KindBlueprint) -> Just root
  (SinglePrompt root, KindPrompt) -> Just root
  _ -> Nothing
  where
    byName = fmap (\entry -> cloneDir </> entry ^. #path) . find (\entry -> entry ^. #name . #unModuleName == key)

kindLabel :: RunnableKind -> Text
kindLabel = \case
  KindBlueprint -> "blueprint"
  KindPrompt -> "prompt"
  KindRecipe -> "recipe"
  KindModule -> "module"

failedRow :: DiscoveredRunnable -> OriginInfo -> Text -> UpgradeEntry
failedRow r origin reason = UpgradeEntry (installKey r) (origin ^. #version) Nothing (UpgradeFailed reason)

dedupeByName :: [UpgradeEntry] -> [UpgradeEntry]
dedupeByName = go Set.empty
  where
    go _ [] = []
    go seen (entry : rest)
      | Set.member (entry ^. #moduleName) seen = go seen rest
      | otherwise = entry : go (Set.insert (entry ^. #moduleName) seen) rest
