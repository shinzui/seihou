module Seihou.Effect.FzfInterp
  ( runFzfIO,
    runFzfPure,
  )
where

import Seihou.Effect.Fzf (Fzf (..))
import Seihou.Fzf (FzfConfig, FzfResult (..), isFzfUsable)
import Seihou.Fzf qualified as Fzf
import Seihou.Prelude

-- | Run fzf effects using a real fzf subprocess.
runFzfIO :: (IOE :> es) => FzfConfig -> Eff (Fzf : es) a -> Eff es a
runFzfIO cfg = interpret $ \_ -> \case
  SelectOne opts candidates -> liftIO $ Fzf.runFzf cfg opts candidates
  IsFzfAvailable -> pure (isFzfUsable cfg)

-- | Pure interpreter for testing. Always selects the candidate at the given
-- index, or returns 'FzfNoMatch' if the index is out of bounds.
runFzfPure :: Int -> Eff (Fzf : es) a -> Eff es a
runFzfPure idx = interpret $ \_ -> \case
  SelectOne _ candidates ->
    pure $
      if idx >= 0 && idx < length candidates
        then FzfSelected (candidates !! idx).candidateValue
        else FzfNoMatch
  IsFzfAvailable -> pure True
