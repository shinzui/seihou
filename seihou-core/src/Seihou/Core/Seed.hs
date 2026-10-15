module Seihou.Core.Seed
  ( mergeSeedRecord, dropSeedOwner, seedsOwnedByModule,
    ManifestInvariantError (..), validateManifestInvariants,
  ) where

import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Seihou.Core.Types
import Seihou.Prelude

-- | Keep the first settlement; callers must check the final manifest's invariants.
-- Never create a receipt for a managed path.
mergeSeedRecord :: FilePath -> SeedRecord -> Manifest -> Manifest
mergeSeedRecord path receipt = #seeds %~ Map.insertWith merge path receipt
  where
    merge new old = old & #applicationIds %~ Set.union (new ^. #applicationIds)

dropSeedOwner :: Set ApplicationId -> FilePath -> Manifest -> Manifest
dropSeedOwner departing path = #seeds %~ Map.update dropOwners path
  where
    dropOwners record =
      let retained = (record ^. #applicationIds) `Set.difference` departing
       in if Set.null retained then Nothing else Just (record & #applicationIds .~ retained)

seedsOwnedByModule :: ModuleName -> Manifest -> Map FilePath SeedRecord
seedsOwnedByModule name manifest = Map.filter ((== name) . (^. #moduleName)) (manifest ^. #seeds)

data ManifestInvariantError = PathBothManagedAndSeeded FilePath
  deriving stock (Eq, Show, Generic)

validateManifestInvariants :: Manifest -> Either ManifestInvariantError ()
validateManifestInvariants manifest = case Map.keys (Map.intersection (manifest ^. #files) (manifest ^. #seeds)) of
  path : _ -> Left (PathBothManagedAndSeeded path)
  [] -> Right ()
