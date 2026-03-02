module Seihou.Effect.ConsolePure
  ( runConsolePure,
    runConsolePureNonInteractive,
    ConsoleState (..),
    emptyConsoleState,
  )
where

import Data.Text (Text)
import Effectful
import Effectful.Dispatch.Dynamic
import Effectful.State.Static.Local (State, get, modify, runState)
import Seihou.Effect.Console (Console (..))
import Prelude hiding (getLine)

-- | State for the pure Console interpreter.
data ConsoleState = ConsoleState
  { consoleInputs :: [Text],
    consoleOutputs :: [Text],
    consoleErrors :: [Text]
  }
  deriving stock (Eq, Show)

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
      PutText msg -> modify (\s -> s {consoleOutputs = consoleOutputs s ++ [msg]})
      PutError msg -> modify (\s -> s {consoleErrors = consoleErrors s ++ [msg]})
      GetLine -> do
        s <- get
        case consoleInputs s of
          [] -> pure ""
          (x : xs) -> do
            modify (\st -> st {consoleInputs = xs})
            pure x
      Confirm _prompt -> do
        s <- get
        case consoleInputs s of
          [] -> pure False
          (x : xs) -> do
            modify (\st -> st {consoleInputs = xs})
            pure (x `elem` ["y", "yes"])
      IsInteractive -> pure True

-- | Pure interpreter for non-interactive mode. IsInteractive returns False.
runConsolePureNonInteractive :: Eff (Console : es) a -> Eff es (a, ConsoleState)
runConsolePureNonInteractive = reinterpret (runState emptyConsoleState) handler
  where
    handler :: (State ConsoleState :> es') => EffectHandler Console es'
    handler _ = \case
      PutText msg -> modify (\s -> s {consoleOutputs = consoleOutputs s ++ [msg]})
      PutError msg -> modify (\s -> s {consoleErrors = consoleErrors s ++ [msg]})
      GetLine -> pure ""
      Confirm _prompt -> pure False
      IsInteractive -> pure False
