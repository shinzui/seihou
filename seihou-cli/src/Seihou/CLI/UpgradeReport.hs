-- | The rows @seihou upgrade@ reports, shared by the executable's command
-- handler and the library code that refreshes individual artifact kinds.
module Seihou.CLI.UpgradeReport
  ( UpgradeStatus (..),
    UpgradeEntry (..),
    isFailedEntry,
    isRefusedEntry,
  )
where

import Data.Aeson (ToJSON (..), object, (.=))
import Data.Generics.Labels ()
import Seihou.Prelude

data UpgradeStatus
  = Upgraded
  | AlreadyUpToDate
  | Skipped
  | UpgradeFailed Text
  | SourceUnreachable
  deriving stock (Eq, Show)

data UpgradeEntry = UpgradeEntry
  { moduleName :: !Text,
    oldVersion :: !(Maybe Text),
    newVersion :: !(Maybe Text),
    upgradeStatus :: !UpgradeStatus
  }
  deriving stock (Eq, Generic, Show)

instance ToJSON UpgradeEntry where
  toJSON e =
    object
      [ "module" .= (e ^. #moduleName),
        "oldVersion" .= (e ^. #oldVersion),
        "newVersion" .= (e ^. #newVersion),
        "status" .= statusText (e ^. #upgradeStatus)
      ]
    where
      statusText :: UpgradeStatus -> Text
      statusText Upgraded = "upgraded"
      statusText AlreadyUpToDate = "up to date"
      statusText Skipped = "skipped"
      statusText (UpgradeFailed reason) = "failed: " <> reason
      statusText SourceUnreachable = "unreachable"

-- | A row the summary line counts as failed: a refusal or error, or a source
-- that could not be reached.
isFailedEntry :: UpgradeEntry -> Bool
isFailedEntry e = case e ^. #upgradeStatus of
  UpgradeFailed _ -> True
  SourceUnreachable -> True
  _ -> False

-- | A row that makes @seihou upgrade@ exit non-zero. An unreachable source is
-- transient and says nothing about the cache's integrity, so it is excluded.
isRefusedEntry :: UpgradeEntry -> Bool
isRefusedEntry e = case e ^. #upgradeStatus of
  UpgradeFailed _ -> True
  _ -> False
