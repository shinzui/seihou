module Seihou.Effect.ManifestStorePure
  ( runManifestStorePure,
  )
where

import Effectful
import Effectful.Dispatch.Dynamic
import Effectful.State.Static.Local (State, get, put, runState)
import Seihou.Core.Types (Manifest)
import Seihou.Effect.ManifestStore (ManifestStore (..))

-- | Pure in-memory interpreter for the ManifestStore effect.
-- Stores the manifest in effectful State.
runManifestStorePure ::
  Maybe Manifest ->
  Eff (ManifestStore : es) a ->
  Eff es (a, Maybe Manifest)
runManifestStorePure initial = reinterpret (runState initial) handler
  where
    handler :: (State (Maybe Manifest) :> es') => EffectHandler ManifestStore es'
    handler _ = \case
      ReadManifest -> Right <$> get
      WriteManifest manifest -> put (Just manifest)
