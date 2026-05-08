module Seihou.Fzf.Selector.Module
  ( formatModuleCandidate,
    formatRunnableCandidate,
    defaultModuleOpts,
    selectModule,
  )
where

import Data.Maybe (mapMaybe)
import Data.Text qualified as T
import Seihou.Core.Module (DiscoveredModule (..), DiscoveredRunnable (..), ModuleSource (..), RunnableKind (..), defaultSearchPaths, discoverAllModules, discoverAllRunnables)
import Seihou.Core.Types
import Seihou.Effect.Fzf (Fzf, selectOne)
import Seihou.Fzf (Candidate (..), FzfOpts, FzfResult, withAnsi, withHeight, withNoSort, withPrompt)
import Seihou.Prelude

-- | Format a discovered module as an fzf candidate.
-- Returns 'Nothing' for modules that failed to load.
formatModuleCandidate :: DiscoveredModule -> Maybe (Candidate ModuleName)
formatModuleCandidate dm = case dm.discoveredResult of
  Left _ -> Nothing
  Right m ->
    let nameText = m.name.unModuleName
        descText = maybe "" (\d -> "  " <> d) m.description
        sourceTag = case dm.discoveredSource of
          SourceProject -> "[project]"
          SourceUser -> "[user]"
          SourceInstalled -> "[installed]"
        display = nameText <> descText <> "  " <> sourceTag
     in Just Candidate {candidateDisplay = display, candidateValue = m.name}

-- | Format a discovered runnable (module or recipe) as an fzf candidate.
-- Returns 'Nothing' for items that failed to load.
formatRunnableCandidate :: DiscoveredRunnable -> Maybe (Candidate ModuleName)
formatRunnableCandidate dr
  | dr.drIsError = Nothing
  | otherwise =
      let nameText = dr.drName
          descText = maybe "" (\d -> "  " <> d) dr.drDescription
          kindTag = case dr.drKind of
            KindModule -> ""
            KindRecipe -> " [recipe]"
            KindBlueprint -> " [blueprint]"
          sourceTag = case dr.drSource of
            SourceProject -> "[project]"
            SourceUser -> "[user]"
            SourceInstalled -> "[installed]"
          display = nameText <> descText <> kindTag <> "  " <> sourceTag
       in Just Candidate {candidateDisplay = display, candidateValue = ModuleName nameText}

-- | Default fzf options for module selection.
defaultModuleOpts :: FzfOpts
defaultModuleOpts = withPrompt "module> " <> withHeight "40%" <> withAnsi <> withNoSort

-- | Discover all available modules and recipes and present them in an fzf picker.
selectModule :: (Fzf :> es, IOE :> es) => Eff es (FzfResult ModuleName)
selectModule = do
  searchPaths <- liftIO defaultSearchPaths
  discovered <- liftIO (discoverAllRunnables searchPaths)
  let candidates = mapMaybe formatRunnableCandidate discovered
  selectOne defaultModuleOpts candidates
