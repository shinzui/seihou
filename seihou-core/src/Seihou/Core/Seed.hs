module Seihou.Core.Seed
  ( seedApplicationIds,
    mergeSeedRecord,
    dropSeedOwners,
    seedClaimsFor,
    replaceSelectedSeedClaims,
    SeedOwnershipError (..),
    renderSeedOwnershipError,
    ManifestInvariantError (..),
    renderManifestInvariantError,
    validateManifestInvariants,
  )
where

import Control.Monad (forM_, unless, when)
import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as T
import Seihou.Composition.Instance (ModuleInstance (..), qualifiedName)
import Seihou.Core.Checkout (pathsOverlap)
import Seihou.Core.Path (validateCanonicalProjectPath)
import Seihou.Core.Types
import Seihou.Prelude

seedApplicationIds :: SeedRecord -> Set ApplicationId
seedApplicationIds record = case record ^. #ownership of
  LegacySeedOwners apps -> apps
  KnownSeedOwners owners -> Map.keysSet owners

data SeedOwnershipError
  = SeedOwnershipUnresolved FilePath (Set ApplicationId)
  | SeedClaimsOutsideSelection FilePath (Set ApplicationId)
  deriving stock (Eq, Show, Generic)

renderSeedOwnershipError :: SeedOwnershipError -> Text
renderSeedOwnershipError = \case
  SeedOwnershipUnresolved path apps ->
    "seed '"
      <> T.pack path
      <> "' needs exact recorded module evidence for applications "
      <> T.intercalate ", " (map (^. #unApplicationId) (Set.toAscList apps))
      <> "; restore access to their recorded releases and retry the command"
  SeedClaimsOutsideSelection path _ -> "seed claims for '" <> T.pack path <> "' include an unselected application"

-- | Union claims, retaining the original supplier, outcome and time. Callers
-- validate the combined manifest after attaching its recorded applications.
mergeSeedRecord :: FilePath -> SeedRecord -> Manifest -> Either SeedOwnershipError Manifest
mergeSeedRecord path receipt manifest = do
  combined <- case Map.lookup path (manifest ^. #seeds) of
    Nothing -> Right receipt
    Just old -> do
      owners <- case (old ^. #ownership, receipt ^. #ownership) of
        (KnownSeedOwners a, KnownSeedOwners b) -> Right (KnownSeedOwners (Map.unionWith Set.union a b))
        (LegacySeedOwners a, LegacySeedOwners b) -> Right (LegacySeedOwners (a <> b))
        _ -> Left (SeedOwnershipUnresolved path (seedApplicationIds old <> seedApplicationIds receipt))
      Right (old & #ownership .~ owners)
  pure (manifest & #seeds %~ Map.insert path combined)

dropSeedOwners :: Map ApplicationId (Set ModuleName) -> FilePath -> Manifest -> Either SeedOwnershipError Manifest
dropSeedOwners departing path manifest = case Map.lookup path (manifest ^. #seeds) of
  Nothing -> Right manifest
  Just receipt -> do
    retained <- case receipt ^. #ownership of
      LegacySeedOwners apps
        | Set.null (apps `Set.intersection` Map.keysSet departing) -> Right (Just receipt)
        | otherwise -> Left (SeedOwnershipUnresolved path apps)
      KnownSeedOwners owners ->
        let rest = Map.mapMaybeWithKey (\app names -> nonempty (names `Set.difference` Map.findWithDefault Set.empty app departing)) owners
         in Right (if Map.null rest then Nothing else Just (receipt & #ownership .~ KnownSeedOwners rest))
    pure (manifest & #seeds %~ Map.update (const retained) path)

seedClaimsFor :: ApplicationId -> ModuleName -> Manifest -> Either SeedOwnershipError (Map FilePath SeedRecord)
seedClaimsFor app name manifest = Map.traverseMaybeWithKey select (manifest ^. #seeds)
  where
    select path receipt = case receipt ^. #ownership of
      LegacySeedOwners apps
        | Set.member app apps -> Left (SeedOwnershipUnresolved path apps)
        | otherwise -> Right Nothing
      KnownSeedOwners owners -> Right (if Set.member name (Map.findWithDefault Set.empty app owners) then Just receipt else Nothing)

-- | Replace the complete claim set of selected applications in one pass.
-- A surviving receipt keeps its original settlement even when every old
-- selected claim was replaced. Unknown unselected claims are preserved.
replaceSelectedSeedClaims :: Set ApplicationId -> Map FilePath SeedRecord -> Manifest -> Either SeedOwnershipError Manifest
replaceSelectedSeedClaims selected incoming manifest = do
  forM_ (Map.toAscList incoming) $ \(path, receipt) -> do
    unless (seedApplicationIds receipt `Set.isSubsetOf` selected) $
      Left (SeedClaimsOutsideSelection path (seedApplicationIds receipt Set.\\ selected))
    case receipt ^. #ownership of
      LegacySeedOwners apps -> Left (SeedOwnershipUnresolved path apps)
      KnownSeedOwners _ -> Right ()
  records <- Map.traverseMaybeWithKey replace (Map.union (manifest ^. #seeds) incoming)
  pure (manifest & #seeds .~ records)
  where
    replace path _ = case Map.lookup path (manifest ^. #seeds) of
      Nothing -> Right (Map.lookup path incoming)
      Just old -> case old ^. #ownership of
        LegacySeedOwners apps
          | not (Set.null (apps `Set.intersection` selected)) || Map.member path incoming -> Left (SeedOwnershipUnresolved path apps)
          | otherwise -> Right (Just old)
        KnownSeedOwners owners ->
          let proposed = case (^. #ownership) <$> Map.lookup path incoming of
                Just (KnownSeedOwners claims) -> claims
                _ -> Map.empty
              rest = Map.unionWith Set.union (Map.withoutKeys owners selected) proposed
           in Right (if Map.null rest then Nothing else Just (old & #ownership .~ KnownSeedOwners rest))

nonempty :: Set a -> Maybe (Set a)
nonempty names = if Set.null names then Nothing else Just names

data ManifestInvariantError
  = PathBothManagedAndSeeded FilePath
  | InvalidSeedPath FilePath Text
  | SeedPathOverlap FilePath FilePath
  | InvalidSeedOwners FilePath Text
  deriving stock (Eq, Show, Generic)

renderManifestInvariantError :: ManifestInvariantError -> Text
renderManifestInvariantError = \case
  PathBothManagedAndSeeded path -> "path " <> T.pack path <> " is recorded both as a tracked file and as a seed"
  InvalidSeedPath path reason -> "seed '" <> T.pack path <> "': " <> reason
  SeedPathOverlap path other -> "seed '" <> T.pack path <> "' overlaps output '" <> T.pack other <> "'"
  InvalidSeedOwners path reason -> "seed '" <> T.pack path <> "' " <> reason

validateManifestInvariants :: Manifest -> Either ManifestInvariantError ()
validateManifestInvariants manifest = do
  forM_ (Map.keys (Map.intersection (manifest ^. #files) (manifest ^. #seeds))) $ \path -> Left (PathBothManagedAndSeeded path)
  forM_ (Map.toAscList (manifest ^. #seeds)) $ \(path, receipt) -> case receipt ^. #ownership of
    -- Preserve historical receipts without pretending they contain exact facts.
    LegacySeedOwners _ -> Right ()
    KnownSeedOwners owners -> do
      first (InvalidSeedPath path) (validateCanonicalProjectPath (T.pack path))
      when (Map.null owners) $ bad path "has no owners"
      forM_ (Map.toAscList owners) $ \(appId, names) -> do
        when (Set.null names) $ bad path "has an empty instance owner set"
        case filter ((== appId) . (^. #applicationId)) (manifest ^. #applications) of
          [app] -> unless (names `Set.isSubsetOf` Set.fromList [qualifiedName (ModuleInstance (state ^. #name) (state ^. #parentVars)) | state <- app ^. #instances]) $ bad path "names an instance outside its owning application"
          _ -> bad path "names an unknown or duplicate application owner"
      forM_ (Map.keys (manifest ^. #files) <> Map.keys (manifest ^. #checkoutOutputs) <> filter (/= path) (Map.keys (manifest ^. #seeds))) $ \other ->
        when (pathsOverlap path other) $ Left (SeedPathOverlap path other)
  where
    bad path = Left . InvalidSeedOwners path
