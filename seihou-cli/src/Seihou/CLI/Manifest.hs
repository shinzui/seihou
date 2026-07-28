module Seihou.CLI.Manifest
  ( ManifestCommand (..),
    handleManifest,
  )
where

import Seihou.CLI.ManifestUpgrade (ManifestUpgradeOpts, handleManifestUpgrade)
import Seihou.Prelude

-- | Subcommand selector for the @seihou manifest@ group. Reserves space for
-- future operations on @.seihou\/manifest.json@ — inspection, repair — without
-- another CLI restructuring pass.
data ManifestCommand
  = ManifestUpgrade ManifestUpgradeOpts
  deriving stock (Eq, Show, Generic)

-- | Dispatch the selected @manifest@ subcommand to its handler.
handleManifest :: ManifestCommand -> IO ()
handleManifest (ManifestUpgrade opts) = handleManifestUpgrade opts
