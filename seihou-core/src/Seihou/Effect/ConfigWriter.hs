module Seihou.Effect.ConfigWriter
  ( ConfigWriter (..),
    writeConfigValue,
    deleteConfigValue,
    listConfigValues,
  )
where

import Seihou.Core.Types (ConfigError, ConfigScope)
import Seihou.Prelude

data ConfigWriter :: Effect where
  WriteConfigValue :: ConfigScope -> Text -> Text -> ConfigWriter m ()
  DeleteConfigValue :: ConfigScope -> Text -> ConfigWriter m ()
  ListConfigValues :: ConfigScope -> ConfigWriter m (Either ConfigError (Map Text Text))

type instance DispatchOf ConfigWriter = Dynamic

writeConfigValue :: (ConfigWriter :> es) => ConfigScope -> Text -> Text -> Eff es ()
writeConfigValue scope key val = send (WriteConfigValue scope key val)

deleteConfigValue :: (ConfigWriter :> es) => ConfigScope -> Text -> Eff es ()
deleteConfigValue scope key = send (DeleteConfigValue scope key)

listConfigValues :: (ConfigWriter :> es) => ConfigScope -> Eff es (Either ConfigError (Map Text Text))
listConfigValues scope = send (ListConfigValues scope)
