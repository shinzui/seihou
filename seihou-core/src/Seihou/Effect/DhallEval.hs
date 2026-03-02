module Seihou.Effect.DhallEval
  ( DhallEval (..),
    evalModuleFile,
  )
where

import Effectful
import Effectful.Dispatch.Dynamic
import Seihou.Core.Types (Module)

data DhallEval :: Effect where
  EvalModuleFile :: FilePath -> DhallEval m Module

type instance DispatchOf DhallEval = Dynamic

evalModuleFile :: (DhallEval :> es) => FilePath -> Eff es Module
evalModuleFile path = send (EvalModuleFile path)
