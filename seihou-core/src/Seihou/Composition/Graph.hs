module Seihou.Composition.Graph
  ( CompositionGraph (..),
    buildGraph,
    topoSort,
  )
where

import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Seihou.Core.Types
import Seihou.Prelude

-- | A directed acyclic graph of modules where edges point from a module
-- to its dependencies.
data CompositionGraph = CompositionGraph
  { cgModules :: Map ModuleName Module,
    cgEdges :: Map ModuleName [ModuleName]
  }
  deriving stock (Eq, Show)

-- | Build a composition graph from a list of modules.
-- Each module's dependencies become edges in the graph.
buildGraph :: [Module] -> CompositionGraph
buildGraph modules =
  CompositionGraph
    { cgModules = Map.fromList [(moduleName m, m) | m <- modules],
      cgEdges = Map.fromList [(moduleName m, moduleDependencies m) | m <- modules]
    }

-- | Topological sort using Kahn's algorithm.
-- Returns module names in execution order (dependencies first)
-- or a 'CircularDependency' error if a cycle exists.
topoSort :: CompositionGraph -> Either ModuleLoadError [ModuleName]
topoSort graph = kahn initialReady initialInDegree [] allNodes
  where
    allNodes :: Set ModuleName
    allNodes = Map.keysSet (cgEdges graph)

    -- In-degree for the reversed graph: for each module, count how
    -- many of its declared dependencies are present in the graph.
    -- Modules with 0 dependencies are ready first (leaf dependencies).
    -- When a module is processed, we decrement in-degree of all
    -- modules that depend on it.
    initialInDegree :: Map ModuleName Int
    initialInDegree =
      Map.fromList
        [ (n, length [d | d <- Map.findWithDefault [] n (cgEdges graph), Set.member d allNodes])
        | n <- Set.toList allNodes
        ]

    initialReady :: [ModuleName]
    initialReady =
      [ n
      | (n, deg) <- Map.toList initialInDegree,
        deg == 0
      ]

    -- Kahn's algorithm: process nodes with zero in-degree,
    -- reduce in-degree of their reverse-dependents, repeat.
    kahn :: [ModuleName] -> Map ModuleName Int -> [ModuleName] -> Set ModuleName -> Either ModuleLoadError [ModuleName]
    kahn [] inDeg result remaining
      | Set.null remaining = Right (reverse result)
      | otherwise = Left (CircularDependency (Set.toList remaining))
    kahn (node : rest) inDeg result remaining =
      let remaining' = Set.delete node remaining
          -- Find all nodes that depend on this node (reverse edges).
          -- For each module whose dependency list contains 'node',
          -- decrease its in-degree.
          (newReady, inDeg') = foldl (decrementDep node) ([], inDeg) (Set.toList remaining')
       in kahn (rest ++ newReady) inDeg' (node : result) remaining'

    decrementDep :: ModuleName -> ([ModuleName], Map ModuleName Int) -> ModuleName -> ([ModuleName], Map ModuleName Int)
    decrementDep processed (ready, inDeg) candidate =
      let deps = Map.findWithDefault [] candidate (cgEdges graph)
       in if processed `elem` deps
            then
              let newDeg = Map.findWithDefault 0 candidate inDeg - 1
                  inDeg' = Map.insert candidate newDeg inDeg
               in if newDeg == 0
                    then (candidate : ready, inDeg')
                    else (ready, inDeg')
            else (ready, inDeg)
