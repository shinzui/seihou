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
  )
where

import Data.Generics.Labels ()
import Data.List (nub)
import Data.Set qualified as Set
import Data.Text qualified as T
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
