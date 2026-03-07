module Seihou.Effect.ConfigReaderPure
  ( runConfigReaderPure,
  )
where

import Data.Map.Strict qualified as Map
import Seihou.Effect.ConfigReader (ConfigReader (..))
import Seihou.Prelude

-- | Pure interpreter for the ConfigReader effect.
--
-- Takes four scripted config maps:
--
--   * @localConfig@: the local project config (.seihou\/config.dhall)
--   * @namespaceConfigs@: a map from namespace names to their configs
--   * @contextConfigs@: a map from context names to their configs
--   * @globalConfig@: the global config (~\/.config\/seihou\/config.dhall)
--
-- This allows tests to provide exact config values without touching the filesystem.
-- All operations return 'Right' (success) since the pure interpreter has no parse errors.
runConfigReaderPure ::
  Map Text Text ->
  Map Text (Map Text Text) ->
  Map Text (Map Text Text) ->
  Map Text Text ->
  Eff (ConfigReader : es) a ->
  Eff es a
runConfigReaderPure localConfig namespaceConfigs contextConfigs globalConfig = interpret $ \_ -> \case
  ReadGlobalConfig -> pure (Right globalConfig)
  ReadLocalConfig -> pure (Right localConfig)
  ReadNamespaceConfig ns -> pure (Right (Map.findWithDefault Map.empty ns namespaceConfigs))
  ReadContextConfig ctx -> pure (Right (Map.findWithDefault Map.empty ctx contextConfigs))
