module Main (main) where

import Seihou.CLI.BrowseFormatSpec qualified as BrowseFormatSpec
import Seihou.CLI.DiffSpec qualified as DiffSpec
import Seihou.CLI.InitSpec qualified as InitSpec
import Seihou.CLI.ListSpec qualified as ListSpec
import Test.Tasty

main :: IO ()
main = do
  tests <-
    sequence
      [ BrowseFormatSpec.tests,
        DiffSpec.tests,
        InitSpec.tests,
        ListSpec.tests
      ]
  defaultMain (testGroup "seihou-cli" tests)
