module Seihou.Effect.DhallEvalInterp
  ( runDhallEval,
    runDhallEvalPure,
  )
where

import Data.Map.Strict qualified as Map
import Seihou.Core.Types (Module, ModuleLoadError (..))
import Seihou.Dhall.Eval (evalModuleFromFile)
import Seihou.Effect.DhallEval (DhallEval (..))
import Seihou.Prelude

-- | Real interpreter that evaluates Dhall files from disk.
runDhallEval :: (IOE :> es) => Eff (DhallEval : es) a -> Eff es a
runDhallEval = interpret $ \_ -> \case
  EvalModuleFile path -> liftIO (evalModuleFromFile path)

-- | Pure test interpreter that looks up modules from an in-memory map.
-- The map keys are file paths; if a path is not found, an error is raised.
runDhallEvalPure :: Map FilePath Module -> Eff (DhallEval : es) a -> Eff es a
runDhallEvalPure modules = interpret $ \_ -> \case
  EvalModuleFile path ->
    case Map.lookup path modules of
      Just m -> pure (Right m)
      Nothing -> error ("runDhallEvalPure: no module at path: " <> path)
