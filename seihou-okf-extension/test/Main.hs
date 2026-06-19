module Main (main) where

import Data.Text qualified as T
import Seihou.OKF.Docs.ModelSpec qualified as ModelSpec
import Seihou.OKF.Docs.RenderSpec qualified as RenderSpec
import Seihou.OKF.Extension (okfSmoke)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

main :: IO ()
main = do
  smokeTests <- testSpec "Seihou.OKF.Extension" spec
  modelTests <- ModelSpec.tests
  renderTests <- RenderSpec.tests
  defaultMain (testGroup "seihou-okf-extension" [smokeTests, modelTests, renderTests])

spec :: Spec
spec = do
  describe "okfSmoke" $ do
    it "serializes an OKF document through okf-core" $ do
      okfSmoke `shouldSatisfy` T.isInfixOf "# smoke"
