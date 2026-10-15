module Seihou.CLI.Kit
  ( KitCommand (..),
    kitCommandParser,
    seihouKitConfig,
    runKit,
  )
where

import Baikai.Kit.Command (KitCommand (..))
import Baikai.Kit.Command qualified as Kit
import Options.Applicative (Parser)
import Seihou.CLI.KitConfig (seihouKitConfig)
import Seihou.Prelude

kitCommandParser :: Parser KitCommand
kitCommandParser = Kit.kitCommandParser seihouKitConfig

runKit :: KitCommand -> IO ()
runKit = Kit.runKit seihouKitConfig
