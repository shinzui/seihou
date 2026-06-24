module Seihou.CLI.Kit
  ( KitCommand (..),
    kitCommandParser,
    seihouKitConfig,
    runKit,
  )
where

import Baikai.Interactive (InteractiveProvider (..))
import Baikai.Kit.Command qualified as Kit
import Baikai.Kit.Config (KitConfig (..), KitScope (..))
import Options.Applicative (Parser)
import Seihou.Prelude

data KitCommand
  = KitList
  | KitInstall !Text !KitScope
  | KitUpdate !(Maybe Text)
  | KitUninstall !Text !KitScope
  | KitStatus
  deriving stock (Eq, Show)

kitCommandParser :: Parser KitCommand
kitCommandParser = fromShared <$> Kit.kitCommandParser

seihouKitConfig :: KitConfig
seihouKitConfig =
  KitConfig
    { toolName = "seihou",
      repoUrl = "https://github.com/shinzui/seihou-kit.git",
      providers = [InteractiveClaude, InteractiveCodex]
    }

runKit :: KitCommand -> IO ()
runKit = Kit.runKit seihouKitConfig . toShared

fromShared :: Kit.KitCommand -> KitCommand
fromShared = \case
  Kit.KitList -> KitList
  Kit.KitInstall name scope -> KitInstall name scope
  Kit.KitUpdate name -> KitUpdate name
  Kit.KitUninstall name scope -> KitUninstall name scope
  Kit.KitStatus -> KitStatus

toShared :: KitCommand -> Kit.KitCommand
toShared = \case
  KitList -> Kit.KitList
  KitInstall name scope -> Kit.KitInstall name scope
  KitUpdate name -> Kit.KitUpdate name
  KitUninstall name scope -> Kit.KitUninstall name scope
  KitStatus -> Kit.KitStatus
