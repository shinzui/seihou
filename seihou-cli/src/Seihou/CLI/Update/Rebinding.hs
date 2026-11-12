-- | Match invocation history before resolving candidate inputs. Exact identities
-- win; only a unique remaining pair may carry history across changed bindings.
module Seihou.CLI.Update.Rebinding (alignPriorInstances, carriedSavedValues) where

import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Seihou.CLI.Update.Types
import Seihou.Composition.Instance (ModuleInstance (..))
import Seihou.Composition.Resolve (SavedInstanceValues)
import Seihou.Core.Types
import Seihou.Prelude

alignPriorInstances :: AppliedComposition -> [ModuleInstance] -> PriorAlignment
alignPriorInstances previous candidates = foldl' align (PriorAlignment exact [] []) names
  where
    recorded = Map.fromList [(ModuleInstance (s ^. #name) (s ^. #parentVars), s) | s <- previous ^. #instances]
    candidateSet = Set.fromList candidates
    exact = Map.restrictKeys recorded candidateSet
    old = Map.withoutKeys recorded candidateSet
    new = candidateSet `Set.difference` Map.keysSet recorded
    names = Set.toAscList (Set.map (^. #module_) new)
    align result name =
      case (filter ((== name) . (^. #module_)) (Set.toAscList new), filter ((== name) . (^. #module_) . fst) (Map.toAscList old)) of
        ([candidate], [(priorId, prior)]) ->
          result
            & #priors
            %~ Map.insert candidate prior
            & #rebindings
            %~ (<> [InstanceRebinding (previous ^. #applicationId) name (priorId ^. #parentVars) (candidate ^. #parentVars)])
        (cs@(_ : _), os@(_ : _)) ->
          result & #unpaired %~ (<> [UnpairedInstances (previous ^. #applicationId) name (map ((^. #parentVars) . fst) os) (map (^. #parentVars) cs)])
        _ -> result

carriedSavedValues :: PriorAlignment -> SavedInstanceValues
carriedSavedValues alignment = Map.mapWithKey carry (alignment ^. #priors)
  where
    carry candidate prior
      | candidate ^. #parentVars == prior ^. #parentVars = prior ^. #resolvedVars
      | otherwise =
          let ParentVars old = prior ^. #parentVars
              ParentVars new = candidate ^. #parentVars
           in Map.filterWithKey (\key value -> Map.notMember key new && Map.lookup key old /= Just value) (prior ^. #resolvedVars)
