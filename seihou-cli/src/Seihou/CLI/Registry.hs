module Seihou.CLI.Registry
  ( RegistryCommand (..),
    handleRegistry,
  )
where

import GHC.Generics (Generic)
import Seihou.CLI.Registry.Sync (SyncVersionsOpts, handleSyncVersions)
import Seihou.CLI.Registry.Validate (ValidateRegistryOpts, handleValidate)

-- | Subcommand selector for the @seihou registry@ group. Reserves space for
-- future operations (e.g. @registry add@, @registry publish@) without
-- another CLI restructuring pass.
data RegistryCommand
  = RegistrySyncVersions SyncVersionsOpts
  | RegistryValidate ValidateRegistryOpts
  deriving stock (Eq, Show, Generic)

-- | Dispatch the selected @registry@ subcommand to its handler.
handleRegistry :: RegistryCommand -> IO ()
handleRegistry (RegistrySyncVersions opts) = handleSyncVersions opts
handleRegistry (RegistryValidate opts) = handleValidate opts
