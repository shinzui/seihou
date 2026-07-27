module Seihou.Composition.Graph
  ( CompositionGraph (..),
    buildGraph,
    topoSort,
  )
where

import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Seihou.Composition.Instance (ModuleInstance (..), mkInstance)
import Seihou.Core.Types
import Seihou.Prelude

-- | A directed acyclic graph of module instances.
--
-- Edges point from a 'ModuleInstance' to the instances of its direct
-- dependencies: two invocations of the same module with different
-- 'ParentVars' have independent edges, so the topological sort
-- produces one node per distinct invocation.
data CompositionGraph = CompositionGraph
  { modules :: !(Map ModuleInstance Module),
    edges :: !(Map ModuleInstance [ModuleInstance])
  }
  deriving stock (Eq, Generic, Show)

-- | Build a composition graph from a list of module instances.
--
-- Each module's dependencies are resolved to the corresponding
-- 'ModuleInstance' present in the input. A dependency edge with
-- @vars@ selects the instance created with those exact bindings;
-- a bare dependency (no @vars@) selects the 'emptyParentVars'
-- instance. If the instance set does not contain the child the edge
-- points to, the edge is silently dropped — the loader is
-- responsible for ensuring every referenced child is loaded first.
buildGraph :: [(ModuleInstance, Module)] -> CompositionGraph
buildGraph entries =
  let present = Set.fromList (map fst entries)
      edgesFor m =
        -- Dedupe edges: if a parent lists the same @(module_, vars)@
        -- twice, the two edges resolve to the same child instance and
        -- must count as one for the topological sort's in-degree.
        Set.toAscList . Set.fromList $
          [ child
          | dep <- m ^. #dependencies,
            let child = mkInstance (dep ^. #module_) (parentVarsFromDep dep),
            Set.member child present
          ]
   in CompositionGraph
        { modules = Map.fromList entries,
          edges = Map.fromList [(inst, edgesFor m) | (inst, m) <- entries]
        }

-- | Topological sort using Kahn's algorithm, operating on
-- 'ModuleInstance' nodes.
--
-- Returns instances in execution order (dependencies first) or a
-- 'CircularDependency' error if a cycle exists. The error payload
-- lists bare module names because that is what callers expect
-- today; the set can include duplicates when two instances of the
-- same module both sit in a cycle.
topoSort :: CompositionGraph -> Either ModuleLoadError [ModuleInstance]
topoSort graph = kahn initialReady initialInDegree [] allNodes
  where
    allNodes :: Set ModuleInstance
    allNodes = Map.keysSet (graph ^. #edges)

    initialInDegree :: Map ModuleInstance Int
    initialInDegree =
      Map.fromList
        [ (n, length [d | d <- Map.findWithDefault [] n (graph ^. #edges), Set.member d allNodes])
        | n <- Set.toList allNodes
        ]

    initialReady :: [ModuleInstance]
    initialReady =
      [ n
      | (n, deg) <- Map.toList initialInDegree,
        deg == 0
      ]

    kahn :: [ModuleInstance] -> Map ModuleInstance Int -> [ModuleInstance] -> Set ModuleInstance -> Either ModuleLoadError [ModuleInstance]
    kahn [] _ result remaining
      | Set.null remaining = Right (reverse result)
      | otherwise =
          Left (CircularDependency (map (^. #module_) (Set.toList remaining)))
    kahn (node : rest) inDeg result remaining =
      let remaining' = Set.delete node remaining
          (newReady, inDeg') = foldl (decrementDep node) ([], inDeg) (Set.toList remaining')
       in kahn (rest ++ newReady) inDeg' (node : result) remaining'

    decrementDep :: ModuleInstance -> ([ModuleInstance], Map ModuleInstance Int) -> ModuleInstance -> ([ModuleInstance], Map ModuleInstance Int)
    decrementDep processed (ready, inDeg) candidate =
      let deps = Map.findWithDefault [] candidate (graph ^. #edges)
       in if processed `elem` deps
            then
              let newDeg = Map.findWithDefault 0 candidate inDeg - 1
                  inDeg' = Map.insert candidate newDeg inDeg
               in if newDeg == 0
                    then (candidate : ready, inDeg')
                    else (ready, inDeg')
            else (ready, inDeg)
