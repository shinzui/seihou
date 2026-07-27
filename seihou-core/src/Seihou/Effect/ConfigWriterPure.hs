module Seihou.Effect.ConfigWriterPure
  ( runConfigWriterPure,
    ConfigWriterState (..),
    emptyConfigWriterState,
  )
where

import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Effectful.State.Static.Local (State, get, modify, runState)
import Seihou.Core.Types (ConfigScope (..))
import Seihou.Effect.ConfigWriter (ConfigWriter (..))
import Seihou.Prelude

-- | In-memory state for the pure ConfigWriter interpreter.
data ConfigWriterState = ConfigWriterState
  { local :: !(Map Text Text),
    namespaces :: !(Map Text (Map Text Text)),
    global :: !(Map Text Text)
  }
  deriving stock (Eq, Generic, Show)

-- | Empty initial state with no config values in any scope.
emptyConfigWriterState :: ConfigWriterState
emptyConfigWriterState =
  ConfigWriterState
    { local = Map.empty,
      namespaces = Map.empty,
      global = Map.empty
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
        modify @ConfigWriterState (writeToScope scope key val)
      DeleteConfigValue scope key ->
        modify @ConfigWriterState (deleteFromScope scope key)
      ListConfigValues scope -> do
        st <- get @ConfigWriterState
        pure (Right (readScope scope st))

writeToScope :: ConfigScope -> Text -> Text -> ConfigWriterState -> ConfigWriterState
writeToScope ScopeLocal key val st = st & #local . at key ?~ val
writeToScope (ScopeNamespace ns) key val st =
  let nsMap = Map.findWithDefault Map.empty ns (st ^. #namespaces)
      updated = Map.insert key val nsMap
   in st & #namespaces . at ns ?~ updated
writeToScope ScopeGlobal key val st = st & #global . at key ?~ val

deleteFromScope :: ConfigScope -> Text -> ConfigWriterState -> ConfigWriterState
deleteFromScope ScopeLocal key st = st & #local . at key .~ Nothing
deleteFromScope (ScopeNamespace ns) key st =
  let nsMap = Map.findWithDefault Map.empty ns (st ^. #namespaces)
      updated = Map.delete key nsMap
   in st & #namespaces . at ns ?~ updated
deleteFromScope ScopeGlobal key st = st & #global . at key .~ Nothing

readScope :: ConfigScope -> ConfigWriterState -> Map Text Text
readScope ScopeLocal st = st ^. #local
readScope (ScopeNamespace ns) st = Map.findWithDefault Map.empty ns (st ^. #namespaces)
readScope ScopeGlobal st = st ^. #global
