module Main (main) where

import Seihou.Core.ExprSpec qualified as ExprSpec
import Seihou.Core.TypesSpec qualified as TypesSpec
import Seihou.Dhall.EvalSpec qualified as DhallEvalSpec
import Test.Tasty

main :: IO ()
main = do
  typesTests <- TypesSpec.tests
  exprTests <- ExprSpec.tests
  dhallEvalTests <- DhallEvalSpec.tests
  defaultMain (testGroup "seihou-core" [typesTests, exprTests, dhallEvalTests])
