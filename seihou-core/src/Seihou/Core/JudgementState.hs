-- | Pure rules for the manifest's active judgements: adopting with an owner,
-- and retiring owners.
--
-- Agreeing owners share one record. Re-adopting an unchanged definition keeps
-- the project's recorded policy, so a policy changed with
-- @seihou judgement configure@ survives re-application. A changed definition
-- replaces the record only when no other owner holds the old one; otherwise
-- adoption is refused before anything is published.
module Seihou.Core.JudgementState
  ( AdoptionChange (..),
    adoptWithOwner,
    pruneJudgementOwners,
    retireOwner,
    policyWeakenings,
  )
where

import Data.Generics.Labels ()
import Data.List (nub)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as T
import Seihou.Core.Judgement (Enforcement (..), renderProbability)
import Seihou.Core.Types
import Seihou.Prelude

data AdoptionChange
  = AdoptedNew
  | -- | Same definition: only the owner set may have grown.
    AdoptedUnchanged
  | -- | The definition changed and replaced the recorded one.
    AdoptedReplacing !ActiveJudgement
  deriving stock (Eq, Show, Generic)

-- | Add @candidate@ for @owner@ to the active list.
adoptWithOwner :: JudgementOwner -> ActiveJudgement -> [ActiveJudgement] -> Either Text ([ActiveJudgement], AdoptionChange)
adoptWithOwner owner candidate active = case break sameName active of
  (_, []) -> Right (active <> [candidate & #owners .~ [owner]], AdoptedNew)
  (before, prior : after)
    | prior ^. #digest == candidate ^. #digest ->
        Right (before <> [prior & #owners %~ (nub . (<> [owner]))] <> after, AdoptedUnchanged)
    | any (/= owner) (prior ^. #owners) ->
        Left
          ( "Judgement '"
              <> name
              <> "' is already active with a different definition for "
              <> T.intercalate ", " (map renderOwner (filter (/= owner) (prior ^. #owners)))
              <> ". Update that owner, or remove it, before adopting this definition."
          )
    | otherwise -> Right (before <> [candidate & #owners .~ [owner]] <> after, AdoptedReplacing prior)
  where
    name = candidate ^. #definition . #name
    sameName j = j ^. #definition . #name == name

renderOwner :: JudgementOwner -> Text
renderOwner = \case
  DirectAdoption -> "a direct seihou run"
  ApplicationOwner (ApplicationId i) -> "application " <> T.take 12 i

-- | Remove one owner everywhere; returns the remaining records and the names
-- of judgements that lost their last owner.
retireOwner :: JudgementOwner -> [ActiveJudgement] -> ([ActiveJudgement], [Text])
retireOwner owner = settle . map (#owners %~ filter (/= owner))

-- | Drop application owners whose application is no longer recorded.
pruneJudgementOwners :: Manifest -> (Manifest, [Text])
pruneJudgementOwners m =
  let live = Set.fromList (map (^. #applicationId) (m ^. #applications))
      keep = \case
        ApplicationOwner a -> Set.member a live
        DirectAdoption -> True
      (remaining, retired) = settle (map (#owners %~ filter keep) (m ^. #judgements))
   in (m & #judgements .~ remaining, retired)

settle :: [ActiveJudgement] -> ([ActiveJudgement], [Text])
settle js = ([j | j <- js, not (null (j ^. #owners))], [j ^. #definition . #name | j <- js, null (j ^. #owners)])

-- | How a proposed set of active judgements is weaker than a trusted one:
-- a judgement removed, a check made advisory, or a review threshold raised.
-- Used to report a staged policy change instead of letting it pass as an
-- ordinary clean result.
policyWeakenings :: [ActiveJudgement] -> [ActiveJudgement] -> [Text]
policyWeakenings trusted proposed = concatMap one trusted
  where
    one t = case [p | p <- proposed, p ^. #definition . #name == name] of
      [] -> ["judgement '" <> name <> "' is no longer active"]
      (p : _) ->
        concat
          [ [ "check '" <> c <> "' of '" <> name <> "' is now advisory"
            | tc ^. #enforcement == Enforced,
              pc ^. #enforcement == Advisory
            ]
              <> [ "check '" <> c <> "' of '" <> name <> "' blocks at " <> renderProbability (pc ^. #review . #blockAt) <> " instead of " <> renderProbability (tc ^. #review . #blockAt)
                 | pc ^. #review . #blockAt > tc ^. #review . #blockAt
                 ]
              <> [ "check '" <> c <> "' of '" <> name <> "' passes at " <> renderProbability (pc ^. #review . #passAt) <> " instead of " <> renderProbability (tc ^. #review . #passAt)
                 | pc ^. #review . #passAt > tc ^. #review . #passAt
                 ]
          | (c, tc) <- Map.toList (t ^. #policy . #checks),
            Just pc <- [Map.lookup c (p ^. #policy . #checks)]
          ]
          <> ["check '" <> c <> "' of '" <> name <> "' was removed" | c <- Map.keys (t ^. #policy . #checks), not (Map.member c (p ^. #policy . #checks))]
      where
        name = t ^. #definition . #name
