module Main (main) where

import Seihou.CLI.BrowseFormatSpec qualified as BrowseFormatSpec
import Seihou.CLI.DiffSpec qualified as DiffSpec
import Seihou.CLI.InitSpec qualified as InitSpec
import Seihou.CLI.ListSpec qualified as ListSpec
import Seihou.CLI.SavePromptedSpec qualified as SavePromptedSpec
import Seihou.CLI.UpgradeSpec qualified as UpgradeSpec
import Seihou.FzfSpec qualified as FzfSpec
import Test.Tasty

main :: IO ()
main = do
  tests <-
    sequence
      [ BrowseFormatSpec.tests,
        DiffSpec.tests,
        InitSpec.tests,
        ListSpec.tests,
        SavePromptedSpec.tests,
        UpgradeSpec.tests,
        FzfSpec.tests
      ]
  defaultMain (testGroup "seihou-cli" tests)
