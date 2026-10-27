module Seihou.Effect.ManifestStore
  ( ManifestStore (..),
    readManifest,
    writeManifest,
  )
where

import Control.Exception (throw)
import Data.Text qualified as T
import Seihou.Core.Types (Manifest)
import Seihou.Manifest.Types (manifestEncodingLoss)
import Seihou.Prelude

data ManifestStore :: Effect where
  ReadManifest :: ManifestStore m (Either Text (Maybe Manifest))
  WriteManifest :: Manifest -> ManifestStore m ()

type instance DispatchOf ManifestStore = Dynamic

readManifest :: (ManifestStore :> es) => Eff es (Either Text (Maybe Manifest))
readManifest = send ReadManifest

writeManifest :: (ManifestStore :> es) => Manifest -> Eff es ()
writeManifest m = case manifestEncodingLoss m of
  [] -> send (WriteManifest m)
  problems -> throw (userError (T.unpack ("refusing to write invalid manifest: " <> T.intercalate "; " problems)))
