module Main (main) where

import Seihou.Core.TypesSpec qualified as TypesSpec
import Test.Tasty

main :: IO ()
main = do
  typesTests <- TypesSpec.tests
  defaultMain (testGroup "seihou-core" [typesTests])
