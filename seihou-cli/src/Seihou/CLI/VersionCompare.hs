module Seihou.CLI.VersionCompare
  ( OutdatedStatus (..),
    compareVersions,
  )
where

import Data.Text (Text)
import Seihou.Core.Version (parseVersion)

-- | Status of a module with respect to available updates.
data OutdatedStatus
  = UpToDate
  | OutdatedSt
  | Unversioned
  | Unreachable
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
