module Main (main) where

import Seihou.CLI.DiffSpec qualified as DiffSpec
import Seihou.CLI.InitSpec qualified as InitSpec
import Test.Tasty

main :: IO ()
main = do
  tests <-
    sequence
      [ DiffSpec.tests,
        InitSpec.tests
      ]
  defaultMain (testGroup "seihou-cli" tests)
