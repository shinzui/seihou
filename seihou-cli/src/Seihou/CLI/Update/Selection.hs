module Seihou.CLI.Update.Selection
  ( SelectedApplications (..),
    SelectionPolicy (..),
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

-- | What to do when a named selection does not satisfy the ownership closure.
data SelectionPolicy
  = -- | Refuse, and tell the user which owners are missing. The default: a
    --   named selection is never broadened without being asked.
    RequireNamedOwners
  | -- | Add the applications the closure requires, reporting each one. Chosen
    --   by @seihou update <target> --include-shared-owners@.
    IncludeSharedOwners
  deriving stock (Eq, Show)

-- | Select applications in manifest order. Bare module names select every
-- recorded application containing that module instance; target names take
-- precedence for each requested name.
--
-- Returns the warnings the selection produced, which under
-- 'IncludeSharedOwners' name every application the expansion added and the
-- path it was added for.
selectApplications ::
  SelectionPolicy ->
  UpdateSelection ->
  Manifest ->
  Either UpdateError (SelectedApplications, [UpdateWarning])
selectApplications policy selection manifest = case selection of
  AllRecordedApplications
    | null (manifest ^. #applications) -> Left NoRecordedApplications
    | otherwise -> Right (RecordedSelection (manifest ^. #applications), [])
  NamedUpdateTargets names
    -- A manifest with no recorded applications has no ownership to close
    -- over, so the policy cannot apply.
    | null (manifest ^. #applications) -> case nubOrd names of
        [name] -> Right (LegacySelection name, [])
        _ -> Left LegacyUpdateRequiresOneTarget
    | otherwise -> do
        namedIds <- foldM selectName Set.empty (nubOrd names)
        let (selectedIds, warnings) = case policy of
              RequireNamedOwners -> (namedIds, [])
              IncludeSharedOwners -> expandToSharedOwners manifest namedIds
            selected = filter ((`Set.member` selectedIds) . (^. #applicationId)) (manifest ^. #applications)
        ensureOwnershipClosure manifest selectedIds
        Right (RecordedSelection selected, warnings)
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

-- | Grow the selection until it satisfies the ownership closure.
--
-- For every managed path that is /not/ additive-only and whose owners
-- intersect the selection, add all of that path's owners. This has to iterate
-- to a fixed point rather than run once: an application pulled in through one
-- path may co-own a different path with a third application, which then has
-- to come along too.
--
-- Additive-only paths are skipped, because they no longer require the
-- closure; expanding for them would update applications the user did not ask
-- for and did not need.
expandToSharedOwners :: Manifest -> Set ApplicationId -> (Set ApplicationId, [UpdateWarning])
expandToSharedOwners manifest = go []
  where
    go warnings selected =
      case [ (path, owner)
           | (path, record) <- Map.toAscList (manifest ^. #files),
             not (record ^. #additiveOnly),
             not (Set.null (Set.intersection selected (record ^. #applicationIds))),
             owner <- Set.toAscList ((record ^. #applicationIds) Set.\\ selected)
           ] of
        [] -> (selected, reverse warnings)
        additions ->
          go
            ([SelectionExpandedForSharedPath path owner | (path, owner) <- additions] <> warnings)
            (Set.union selected (Set.fromList (map snd additions)))

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
