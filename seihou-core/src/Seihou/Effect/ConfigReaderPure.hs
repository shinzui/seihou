module Seihou.Effect.ConfigReaderPure
  ( runConfigReaderPure,
  )
where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Effectful
import Effectful.Dispatch.Dynamic
import Seihou.Effect.ConfigReader (ConfigReader (..))

-- | Pure interpreter for the ConfigReader effect.
--
-- Takes three scripted config maps:
--
--   * @localConfig@: the local project config (.seihou\/config.dhall)
--   * @namespaceConfigs@: a map from namespace names to their configs
--   * @globalConfig@: the global config (~\/.config\/seihou\/config.dhall)
--
-- This allows tests to provide exact config values without touching the filesystem.
runConfigReaderPure ::
  Map Text Text ->
  Map Text (Map Text Text) ->
  Map Text Text ->
  Eff (ConfigReader : es) a ->
  Eff es a
runConfigReaderPure localConfig namespaceConfigs globalConfig = interpret $ \_ -> \case
  ReadGlobalConfig -> pure globalConfig
  ReadLocalConfig -> pure localConfig
  ReadNamespaceConfig ns -> pure (Map.findWithDefault Map.empty ns namespaceConfigs)
