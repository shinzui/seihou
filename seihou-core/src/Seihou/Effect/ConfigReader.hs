module Seihou.Effect.ConfigReader
  ( ConfigReader (..),
    readGlobalConfig,
    readLocalConfig,
    readNamespaceConfig,
  )
where

import Data.Map.Strict (Map)
import Data.Text (Text)
import Effectful
import Effectful.Dispatch.Dynamic
import Seihou.Core.Types (ConfigError)

data ConfigReader :: Effect where
  ReadGlobalConfig :: ConfigReader m (Either ConfigError (Map Text Text))
  ReadLocalConfig :: ConfigReader m (Either ConfigError (Map Text Text))
  ReadNamespaceConfig :: Text -> ConfigReader m (Either ConfigError (Map Text Text))

type instance DispatchOf ConfigReader = Dynamic

readGlobalConfig :: (ConfigReader :> es) => Eff es (Either ConfigError (Map Text Text))
readGlobalConfig = send ReadGlobalConfig

readLocalConfig :: (ConfigReader :> es) => Eff es (Either ConfigError (Map Text Text))
readLocalConfig = send ReadLocalConfig

readNamespaceConfig :: (ConfigReader :> es) => Text -> Eff es (Either ConfigError (Map Text Text))
readNamespaceConfig ns = send (ReadNamespaceConfig ns)
