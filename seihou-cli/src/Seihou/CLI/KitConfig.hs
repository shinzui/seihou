module Seihou.CLI.KitConfig (seihouKitConfig) where

import Baikai.Interactive (InteractiveProvider (..))
import Baikai.Kit.Config (KitConfig, kitConfig)

seihouKitConfig :: KitConfig
seihouKitConfig =
  kitConfig
    "seihou"
    "https://github.com/shinzui/seihou-kit.git"
    [InteractiveClaude, InteractiveCodex]
