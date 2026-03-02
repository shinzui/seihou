module Seihou.Effect.ManifestStore
  ( ManifestStore (..),
    readManifest,
    writeManifest,
  )
where

import Effectful
import Effectful.Dispatch.Dynamic
import Seihou.Core.Types (Manifest)

data ManifestStore :: Effect where
  ReadManifest :: ManifestStore m (Maybe Manifest)
  WriteManifest :: Manifest -> ManifestStore m ()

type instance DispatchOf ManifestStore = Dynamic

readManifest :: (ManifestStore :> es) => Eff es (Maybe Manifest)
readManifest = send ReadManifest

writeManifest :: (ManifestStore :> es) => Manifest -> Eff es ()
writeManifest m = send (WriteManifest m)
