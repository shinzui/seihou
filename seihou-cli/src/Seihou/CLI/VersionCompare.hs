module Seihou.CLI.VersionCompare
  ( OutdatedStatus (..),
    OutdatedEntry (..),
    CheckStats (..),
    compareVersions,
  )
where

import Data.Aeson (ToJSON (..), object, (.=))
import Data.Text (Text)
import Seihou.Core.Version (parseVersion)

-- | Status of a module with respect to available updates.
data OutdatedStatus
  = UpToDate
  | OutdatedSt
  | Unversioned
  | Unreachable
  deriving stock (Eq, Show)

-- | A single entry in the outdated report. Shared between the
-- @seihou outdated@ command (which formats them as a table) and
-- @seihou status@ (which folds them into per-row annotations).
data OutdatedEntry = OutdatedEntry
  { moduleName :: Text,
    installedVersion :: Maybe Text,
    availableVersion :: Maybe Text,
    status :: OutdatedStatus
  }
  deriving stock (Eq, Show)

instance ToJSON OutdatedEntry where
  toJSON e =
    object
      [ "module" .= e.moduleName,
        "installed" .= e.installedVersion,
        "available" .= e.availableVersion,
        "status" .= statusText e.status
      ]
    where
      statusText UpToDate = "up to date" :: Text
      statusText OutdatedSt = "outdated"
      statusText Unversioned = "unversioned"
      statusText Unreachable = "unreachable"

-- | Summary statistics for an update check.
data CheckStats = CheckStats
  { checkedCount :: Int,
    skippedNoOrigin :: Int
  }
  deriving stock (Eq, Show)

-- | Compare installed and available version strings.
compareVersions :: Maybe Text -> Maybe Text -> OutdatedStatus
compareVersions (Just instText) (Just availText) =
  case (parseVersion instText, parseVersion availText) of
    (Just instV, Just availV)
      | instV < availV -> OutdatedSt
      | otherwise -> UpToDate
    _ -> Unversioned -- unparseable version treated as unversioned
compareVersions _ _ = Unversioned
