module Seihou.Effect.ConsolePure
  ( runConsolePure,
    runConsolePureNonInteractive,
    ConsoleState (..),
    emptyConsoleState,
  )
where

import Data.Generics.Labels ()
import Effectful.State.Static.Local (State, get, modify, runState)
import Seihou.Effect.Console (Console (..))
import Seihou.Prelude
import Prelude hiding (getLine)

-- | State for the pure Console interpreter.
data ConsoleState = ConsoleState
  { inputs :: ![Text],
    outputs :: ![Text],
    errors :: ![Text]
  }
  deriving stock (Eq, Generic, Show)

-- | Empty console state with no inputs or outputs.
emptyConsoleState :: ConsoleState
emptyConsoleState = ConsoleState [] [] []

-- | Pure interpreter for the Console effect (interactive mode).
-- Takes a list of scripted input lines. IsInteractive returns True.
runConsolePure :: [Text] -> Eff (Console : es) a -> Eff es (a, ConsoleState)
runConsolePure inputs = reinterpret (runState (ConsoleState inputs [] [])) handler
  where
    handler :: (State ConsoleState :> es') => EffectHandler Console es'
    handler _ = \case
      PutText msg -> modify @ConsoleState (\s -> s {outputs = s ^. #outputs ++ [msg]})
      PutError msg -> modify @ConsoleState (\s -> s {errors = s ^. #errors ++ [msg]})
      GetLine -> popInput
      Confirm _prompt -> (`elem` ["y", "yes"]) <$> popInput
      IsInteractive -> pure True

    popInput :: (State ConsoleState :> es') => Eff es' Text
    popInput = do
      s <- get @ConsoleState
      case s ^. #inputs of
        [] -> pure ""
        (x : xs) -> do
          modify @ConsoleState (\st -> st {inputs = xs})
          pure x

-- | Pure interpreter for non-interactive mode. IsInteractive returns False.
runConsolePureNonInteractive :: Eff (Console : es) a -> Eff es (a, ConsoleState)
runConsolePureNonInteractive = reinterpret (runState emptyConsoleState) handler
  where
    handler :: (State ConsoleState :> es') => EffectHandler Console es'
    handler _ = \case
      PutText msg -> modify @ConsoleState (\s -> s {outputs = s ^. #outputs ++ [msg]})
      PutError msg -> modify @ConsoleState (\s -> s {errors = s ^. #errors ++ [msg]})
      GetLine -> pure ""
      Confirm _prompt -> pure False
      IsInteractive -> pure False
