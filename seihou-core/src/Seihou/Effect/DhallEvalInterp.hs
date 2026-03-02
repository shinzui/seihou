module Seihou.Effect.DhallEvalInterp
  ( runDhallEval,
    runDhallEvalPure,
  )
where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Effectful
import Effectful.Dispatch.Dynamic
import Seihou.Core.Types (Module, ModuleLoadError (..))
import Seihou.Dhall.Eval (evalModuleFromFile)
import Seihou.Effect.DhallEval (DhallEval (..))

-- | Real interpreter that evaluates Dhall files from disk.
runDhallEval :: (IOE :> es) => Eff (DhallEval : es) a -> Eff es a
runDhallEval = interpret $ \_ -> \case
  EvalModuleFile path -> do
    result <- liftIO (evalModuleFromFile path)
    case result of
      Right m -> pure m
      Left err -> error ("DhallEval failed: " <> show err)

-- | Pure test interpreter that looks up modules from an in-memory map.
-- The map keys are file paths; if a path is not found, an error is raised.
runDhallEvalPure :: Map FilePath Module -> Eff (DhallEval : es) a -> Eff es a
runDhallEvalPure modules = interpret $ \_ -> \case
  EvalModuleFile path ->
    case Map.lookup path modules of
      Just m -> pure m
      Nothing -> error ("runDhallEvalPure: no module at path: " <> path)
