module Seihou.Effect.BaselineStorePure
  ( runBaselineStorePure,
  )
where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Effectful.State.Static.Local (State, get, modify, runState)
import Seihou.Core.Types (BaselineRef (..))
import Seihou.Effect.BaselineStore (BaselineError (..), BaselineStore (..))
import Seihou.Manifest.Hash (baselineRefForContent, hashContent)
import Seihou.Prelude

-- | Run the baseline store entirely in memory. The map is intentionally
-- exposed in the result so tests can inspect deduplication and pruning.
runBaselineStorePure ::
  Map BaselineRef Text ->
  Eff (BaselineStore : es) a ->
  Eff es (a, Map BaselineRef Text)
runBaselineStorePure initial = reinterpret (runState initial) handler
  where
    handler :: (State (Map BaselineRef Text) :> es') => EffectHandler BaselineStore es'
    handler _ = \case
      PutBaseline content -> do
        let ref = baselineRefForContent content
        modify @(Map BaselineRef Text) (Map.insert ref content)
        pure ref
      ReadBaseline ref -> do
        store <- get @(Map BaselineRef Text)
        pure $ case Map.lookup ref store of
          Nothing -> Left (BaselineMissing ref)
          Just content ->
            let actual = hashContent content
             in if actual == ref.unBaselineRef
                  then Right content
                  else Left (BaselineCorrupt ref actual)
      PruneBaselines referenced -> do
        store <- get @(Map BaselineRef Text)
        let removable =
              Map.keysSet $
                Map.filterWithKey
                  (\ref content -> Set.notMember ref referenced && hashContent content == ref.unBaselineRef)
                  store
        modify @(Map BaselineRef Text) (`Map.withoutKeys` removable)
        pure (Set.toAscList removable)
