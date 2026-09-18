module Seihou.CLI.Update.Selection
  ( MatchedApplications (..),
    SelectionPolicy (..),
    ClosureOutcome (..),
    matchApplications,
    enforceOwnershipClosure,
    applicationsWithIds,
    applicationRef,
    targetName,
    availableTargets,
  )
where

import Control.Monad (foldM)
import Data.Generics.Labels ()
import Data.List (find)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Seihou.CLI.Update.Types
import Seihou.Core.Types
import Seihou.Prelude

-- | Which recorded applications a request names, before the ownership
-- closure is consulted.
data MatchedApplications
  = -- | Every recorded application, in manifest order. Selecting all of them
    --   satisfies every closure by construction.
    MatchedAll [AppliedComposition]
  | -- | The ids a named selection matched. The closure has not been
    --   enforced yet, so this is not yet what will be updated.
    MatchedNamed (Set ApplicationId)
  | -- | A manifest with no recorded applications, seeded from one target.
    MatchedLegacy Text
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

-- | The result of enforcing the ownership closure on a named selection.
data ClosureOutcome
  = -- | The selection, possibly expanded, is safe to update, with a warning
    --   for every application the expansion added.
    ClosureSatisfied (Set ApplicationId) [UpdateWarning]
  | -- | No known closure requirement is violated, but these paths intersect
    --   the selection, leave an owner out, and record 'SharedWriteUnknown'.
    --   Their modes must be certified before the closure can be decided;
    --   selecting more applications would not supply them. The selection and
    --   warnings are those reached so far.
    ClosureNeedsEvidence (Set ApplicationId) [UpdateWarning] [FilePath]
  deriving stock (Eq, Show)

-- | Phase one: find the applications a request names, in manifest order.
-- Bare module names select every recorded application containing that
-- module instance; target names take precedence for each requested name.
--
-- This never consults shared ownership. Matching has to come first because
-- which paths' evidence matters depends on what was selected.
matchApplications :: UpdateSelection -> Manifest -> Either UpdateError MatchedApplications
matchApplications selection manifest = case selection of
  AllRecordedApplications
    | null (manifest ^. #applications) -> Left NoRecordedApplications
    | otherwise -> Right (MatchedAll (manifest ^. #applications))
  NamedUpdateTargets names
    -- A manifest with no recorded applications has no ownership to close
    -- over, so the policy cannot apply.
    | null (manifest ^. #applications) -> case nubOrd names of
        [name] -> Right (MatchedLegacy name)
        _ -> Left LegacyUpdateRequiresOneTarget
    | otherwise -> MatchedNamed <$> foldM selectName Set.empty (nubOrd names)
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

-- | Phase two: decide whether a named selection may be updated as it
-- stands.
--
-- Every managed path whose owners intersect the selection and leave an
-- owner out is judged by its recorded 'SharedWriteMode':
--
-- * 'SharedWriteAdditiveOnly' paths pass. Every owner reaches the path
--   through an additive, non-overlapping patch, so reconciling one of them
--   provably cannot disturb another.
-- * 'SharedWriteRequiresOwnershipClosure' paths refuse with
--   'SharedPathRequiresApplications', or under 'IncludeSharedOwners' pull
--   the missing owners in, iterating to a fixed point because an added
--   application may co-own another path with a third.
-- * 'SharedWriteUnknown' paths are neither: the answer has not been
--   established, so the result is 'ClosureNeedsEvidence'. Expansion is never
--   used for them, because updating whole applications does not supply a
--   missing fact.
--
-- A known refusal is reported before a request for evidence, since
-- certifying other paths could not lift it.
--
-- This is the preflight and uses only the manifest;
-- 'Seihou.Engine.Reconcile.validateOwner' checks the candidate's own
-- operations later. See
-- docs/adr/0012-an-additive-co-write-is-not-a-shared-path-conflict.md.
enforceOwnershipClosure ::
  SelectionPolicy ->
  Manifest ->
  Set ApplicationId ->
  Either UpdateError ClosureOutcome
enforceOwnershipClosure policy manifest named =
  case (closureViolations SharedWriteRequiresOwnershipClosure, closureViolations SharedWriteUnknown) of
    ((path, selectedOwners, missingOwners) : _, _) ->
      Left
        ( SharedPathRequiresApplications
            path
            (Set.map (applicationRef manifest) selectedOwners)
            (Set.map (applicationRef manifest) missingOwners)
        )
    ([], []) -> Right (ClosureSatisfied selected warnings)
    ([], unknown) -> Right (ClosureNeedsEvidence selected warnings [path | (path, _, _) <- unknown])
  where
    (selected, warnings) = case policy of
      RequireNamedOwners -> (named, [])
      IncludeSharedOwners -> expandToSharedOwners manifest named

    closureViolations mode =
      [ (path, selectedOwners, missingOwners)
      | (path, record) <- Map.toAscList (manifest ^. #files),
        record ^. #sharedWriteMode == mode,
        let selectedOwners = Set.intersection selected (record ^. #applicationIds),
        let missingOwners = (record ^. #applicationIds) Set.\\ selected,
        not (Set.null selectedOwners),
        not (Set.null missingOwners)
      ]

-- | Grow the selection until no path /known/ to require the closure leaves
-- an owner out.
--
-- For every managed path recorded 'SharedWriteRequiresOwnershipClosure'
-- whose owners intersect the selection, add all of that path's owners, to a
-- fixed point: an application pulled in through one path may co-own a
-- different path with a third application, which then has to come along too.
--
-- Additive-only paths are skipped because they do not require the closure,
-- and unknown paths because their answer is missing rather than known to
-- require it.
expandToSharedOwners :: Manifest -> Set ApplicationId -> (Set ApplicationId, [UpdateWarning])
expandToSharedOwners manifest = go []
  where
    go warnings selected =
      case [ (path, owner)
           | (path, record) <- Map.toAscList (manifest ^. #files),
             record ^. #sharedWriteMode == SharedWriteRequiresOwnershipClosure,
             not (Set.null (Set.intersection selected (record ^. #applicationIds))),
             owner <- Set.toAscList ((record ^. #applicationIds) Set.\\ selected)
           ] of
        [] -> (selected, reverse warnings)
        additions ->
          go
            ([SelectionExpandedForSharedPath path (applicationRef manifest owner) | (path, owner) <- additions] <> warnings)
            (Set.union selected (Set.fromList (map snd additions)))

-- | The recorded applications with these ids, in manifest order.
applicationsWithIds :: Manifest -> Set ApplicationId -> [AppliedComposition]
applicationsWithIds manifest ids =
  filter ((`Set.member` ids) . (^. #applicationId)) (manifest ^. #applications)

-- | A renderer-neutral reference to an application id, carrying the
-- recorded target and its root instance's parent variables when the
-- manifest records the application.
applicationRef :: Manifest -> ApplicationId -> ApplicationRef
applicationRef manifest applicationId =
  case find ((== applicationId) . (^. #applicationId)) (manifest ^. #applications) of
    Nothing -> ApplicationRef applicationId Nothing emptyParentVars []
    Just application ->
      ApplicationRef
        { applicationId,
          target = Just (application ^. #target),
          parentVars = maybe emptyParentVars (^. #parentVars) (rootInstance application),
          additionalModules = application ^. #additionalModules
        }

-- | The instance a composition was applied for: the one named after a
-- module target, or the last instance, which composition order puts after
-- its dependencies.
rootInstance :: AppliedComposition -> Maybe AppliedInstanceState
rootInstance application = case application ^. #target of
  AppliedModuleTarget name
    | Just state <- find ((== name) . (^. #name)) (reverse (application ^. #instances)) -> Just state
  _ -> lastMaybe (application ^. #instances)
  where
    lastMaybe [] = Nothing
    lastMaybe states = Just (last states)

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
