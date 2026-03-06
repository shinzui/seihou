module Seihou.Effect.DhallEval
  ( DhallEval (..),
    evalModuleFile,
  )
where

import Seihou.Core.Types (Module, ModuleLoadError)
import Seihou.Prelude

data DhallEval :: Effect where
  EvalModuleFile :: FilePath -> DhallEval m (Either ModuleLoadError Module)

type instance DispatchOf DhallEval = Dynamic

evalModuleFile :: (DhallEval :> es) => FilePath -> Eff es (Either ModuleLoadError Module)
evalModuleFile path = send (EvalModuleFile path)
