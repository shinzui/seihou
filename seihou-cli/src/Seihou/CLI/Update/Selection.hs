module Seihou.CLI.Update.Selection
  ( SelectedApplications (..),
    selectApplications,
    targetName,
    availableTargets,
  )
where

import Control.Monad (foldM)
import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Seihou.CLI.Update.Types
import Seihou.Core.Types
import Seihou.Prelude

data SelectedApplications
  = RecordedSelection [AppliedComposition]
  | LegacySelection Text
  deriving stock (Eq, Show)

-- | Select applications in manifest order. Bare module names select every
-- recorded application containing that module instance; target names take
-- precedence for each requested name.
selectApplications :: UpdateSelection -> Manifest -> Either UpdateError SelectedApplications
selectApplications selection manifest = case selection of
  AllRecordedApplications
    | null (manifest ^. #applications) -> Left NoRecordedApplications
    | otherwise -> Right (RecordedSelection (manifest ^. #applications))
  NamedUpdateTargets names
    | null (manifest ^. #applications) -> case nubOrd names of
        [name] -> Right (LegacySelection name)
        _ -> Left LegacyUpdateRequiresOneTarget
    | otherwise -> do
        selectedIds <- foldM selectName Set.empty (nubOrd names)
        let selected = filter ((`Set.member` selectedIds) . (^. #applicationId)) (manifest ^. #applications)
        ensureOwnershipClosure manifest selectedIds
        Right (RecordedSelection selected)
  where
    selectName selected name =
      let exact = filter ((== name) . targetName) (manifest ^. #applications)
          matches =
            if null exact
              then filter (containsModule name) (manifest ^. #applications)
              else exact
       in if null matches
            then Left (UpdateTargetNotFound name (availableTargets manifest))
            else Right (foldl' (flip (Set.insert . (^. #applicationId))) selected matches)

-- | For every managed path a selected application owns, require that every
-- other owner is selected too — because regenerating a file normally means
-- rewriting all of it, which would discard an unselected owner's content.
--
-- A path whose manifest record says @additiveOnly@ is exempt: every owner
-- reaches it through an additive, non-overlapping patch, so reconciling one
-- of them provably cannot disturb another. This is the preflight, and it runs
-- before any candidate artifact is fetched, so the manifest is the only
-- evidence available here; 'Seihou.Engine.Reconcile.validateOwner' checks the
-- candidate's own operations later, once they are known.
--
-- A @False@ cannot distinguish "an owner writes the whole file" from "this
-- manifest predates the field", so the refusal message names both.
--
-- See docs/adr/0012-an-additive-co-write-is-not-a-shared-path-conflict.md.
ensureOwnershipClosure :: Manifest -> Set ApplicationId -> Either UpdateError ()
ensureOwnershipClosure manifest selected =
  case [ (path, selectedOwners, missingOwners)
       | (path, record) <- Map.toAscList (manifest ^. #files),
         not (record ^. #additiveOnly),
         let selectedOwners = Set.intersection selected (record ^. #applicationIds),
         let missingOwners = (record ^. #applicationIds) Set.\\ selected,
         not (Set.null selectedOwners),
         not (Set.null missingOwners)
       ] of
    (path, selectedOwners, missingOwners) : _ ->
      Left (SharedPathRequiresApplications path selectedOwners missingOwners)
    [] -> Right ()

targetName :: AppliedComposition -> Text
targetName application = case application ^. #target of
  AppliedModuleTarget name -> (name ^. #unModuleName)
  AppliedRecipeTarget name -> (name ^. #unRecipeName)

availableTargets :: Manifest -> [Text]
availableTargets manifest = nubOrd (map targetName (manifest ^. #applications) <> instanceNames)
  where
    instanceNames =
      [ state ^. #name . #unModuleName
      | application <- manifest ^. #applications,
        state <- application ^. #instances
      ]

containsModule :: Text -> AppliedComposition -> Bool
containsModule name = any ((== name) . (^. #name . #unModuleName)) . (^. #instances)

nubOrd :: (Ord a) => [a] -> [a]
nubOrd = go Set.empty
  where
    go _ [] = []
    go seen (value : rest)
      | Set.member value seen = go seen rest
      | otherwise = value : go (Set.insert value seen) rest
