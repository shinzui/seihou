module Seihou.Effect.ManifestStore
  ( ManifestStore (..),
    readManifest,
    writeManifest,
  )
where

import Seihou.Core.Types (Manifest)
import Seihou.Prelude

data ManifestStore :: Effect where
  ReadManifest :: ManifestStore m (Either Text (Maybe Manifest))
  WriteManifest :: Manifest -> ManifestStore m ()

type instance DispatchOf ManifestStore = Dynamic

readManifest :: (ManifestStore :> es) => Eff es (Either Text (Maybe Manifest))
readManifest = send ReadManifest

writeManifest :: (ManifestStore :> es) => Manifest -> Eff es ()
writeManifest m = send (WriteManifest m)
