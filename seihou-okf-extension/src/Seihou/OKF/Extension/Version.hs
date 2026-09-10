-- | The extension's own version, read from Cabal rather than a hand-maintained
-- literal, so the provenance actor stamped on every generated concept cannot
-- drift from the package that produced it.
module Seihou.OKF.Extension.Version
  ( extensionVersion,
    producerActorName,
  )
where

import Data.Text (Text)
import Data.Text qualified as T
import Data.Version (showVersion)
import Paths_seihou_okf_extension qualified as Paths

-- | The extension's package version, e.g. @"0.7.0.0"@.
extensionVersion :: Text
extensionVersion = T.pack (showVersion Paths.version)

-- | The producer half of the OKF @generated.by@ actor. The version half is
-- 'extensionVersion'; together okf renders them as
-- @seihou-okf-extension\/\<version\>@.
producerActorName :: Text
producerActorName = "seihou-okf-extension"
