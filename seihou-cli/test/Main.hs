module Main (main) where

import Seihou.CLI.InitSpec qualified as InitSpec
import Test.Tasty

main :: IO ()
main = do
  tests <-
    sequence
      [ InitSpec.tests
      ]
  defaultMain (testGroup "seihou-cli" tests)
