module Seihou.Effect.Fzf
  ( Fzf (..),
    selectOne,
    isFzfAvailable,
  )
where

import Seihou.Fzf (Candidate, FzfOpts, FzfResult)
import Seihou.Prelude

data Fzf :: Effect where
  SelectOne :: FzfOpts -> [Candidate a] -> Fzf (Eff es) (FzfResult a)
  IsFzfAvailable :: Fzf (Eff es) Bool

type instance DispatchOf Fzf = Dynamic

selectOne :: (Fzf :> es) => FzfOpts -> [Candidate a] -> Eff es (FzfResult a)
selectOne opts cs = send (SelectOne opts cs)

isFzfAvailable :: (Fzf :> es) => Eff es Bool
isFzfAvailable = send IsFzfAvailable
