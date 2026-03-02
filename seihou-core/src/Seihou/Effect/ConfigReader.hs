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

data ConfigReader :: Effect where
  ReadGlobalConfig :: ConfigReader m (Map Text Text)
  ReadLocalConfig :: ConfigReader m (Map Text Text)
  ReadNamespaceConfig :: Text -> ConfigReader m (Map Text Text)

type instance DispatchOf ConfigReader = Dynamic

readGlobalConfig :: (ConfigReader :> es) => Eff es (Map Text Text)
readGlobalConfig = send ReadGlobalConfig

readLocalConfig :: (ConfigReader :> es) => Eff es (Map Text Text)
readLocalConfig = send ReadLocalConfig

readNamespaceConfig :: (ConfigReader :> es) => Text -> Eff es (Map Text Text)
readNamespaceConfig ns = send (ReadNamespaceConfig ns)
