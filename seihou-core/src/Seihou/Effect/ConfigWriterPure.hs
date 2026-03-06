module Seihou.Effect.ConfigWriterPure
  ( runConfigWriterPure,
    ConfigWriterState (..),
    emptyConfigWriterState,
  )
where

import Data.Map.Strict qualified as Map
import Effectful.State.Static.Local (State, get, modify, runState)
import Seihou.Core.Types (ConfigScope (..))
import Seihou.Effect.ConfigWriter (ConfigWriter (..))
import Seihou.Prelude

-- | In-memory state for the pure ConfigWriter interpreter.
data ConfigWriterState = ConfigWriterState
  { cwLocal :: Map Text Text,
    cwNamespaces :: Map Text (Map Text Text),
    cwGlobal :: Map Text Text
  }
  deriving stock (Eq, Show)

-- | Empty initial state with no config values in any scope.
emptyConfigWriterState :: ConfigWriterState
emptyConfigWriterState =
  ConfigWriterState
    { cwLocal = Map.empty,
      cwNamespaces = Map.empty,
      cwGlobal = Map.empty
    }

-- | Pure interpreter for the ConfigWriter effect using in-memory state.
--
-- Returns the result along with the final state, allowing tests to
-- inspect what was written.
runConfigWriterPure :: ConfigWriterState -> Eff (ConfigWriter : es) a -> Eff es (a, ConfigWriterState)
runConfigWriterPure initial = reinterpret (runState initial) handler
  where
    handler :: (State ConfigWriterState :> es') => EffectHandler ConfigWriter es'
    handler _ = \case
      WriteConfigValue scope key val ->
        modify (writeToScope scope key val)
      DeleteConfigValue scope key ->
        modify (deleteFromScope scope key)
      ListConfigValues scope -> do
        st <- get
        pure (Right (readScope scope st))

writeToScope :: ConfigScope -> Text -> Text -> ConfigWriterState -> ConfigWriterState
writeToScope ScopeLocal key val st = st {cwLocal = Map.insert key val (cwLocal st)}
writeToScope (ScopeNamespace ns) key val st =
  let nsMap = Map.findWithDefault Map.empty ns (cwNamespaces st)
      updated = Map.insert key val nsMap
   in st {cwNamespaces = Map.insert ns updated (cwNamespaces st)}
writeToScope ScopeGlobal key val st = st {cwGlobal = Map.insert key val (cwGlobal st)}

deleteFromScope :: ConfigScope -> Text -> ConfigWriterState -> ConfigWriterState
deleteFromScope ScopeLocal key st = st {cwLocal = Map.delete key (cwLocal st)}
deleteFromScope (ScopeNamespace ns) key st =
  let nsMap = Map.findWithDefault Map.empty ns (cwNamespaces st)
      updated = Map.delete key nsMap
   in st {cwNamespaces = Map.insert ns updated (cwNamespaces st)}
deleteFromScope ScopeGlobal key st = st {cwGlobal = Map.delete key (cwGlobal st)}

readScope :: ConfigScope -> ConfigWriterState -> Map Text Text
readScope ScopeLocal st = cwLocal st
readScope (ScopeNamespace ns) st = Map.findWithDefault Map.empty ns (cwNamespaces st)
readScope ScopeGlobal st = cwGlobal st
