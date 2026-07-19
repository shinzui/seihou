module Seihou.CLI.UpdateRenderSpec (tests) where

import Data.List (isInfixOf)
import Data.Text qualified as T
import Seihou.CLI.Update (UpdateError (..))
import Seihou.CLI.Update.Render
  ( encodeUpdateOutput,
    errorOutput,
    planOutput,
    renderUpdateHuman,
  )
import Seihou.CLI.UpdateFixture (conflictPlan)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.CLI.Update.Render" spec

spec :: Spec
spec = do
  it "groups a human plan and names unresolved paths" $ do
    let rendered = renderUpdateHuman False (planOutput conflictPlan)
    rendered `shouldSatisfy` T.isInfixOf "Files:"
    rendered `shouldSatisfy` T.isInfixOf "Conflict:    README.md"
    rendered `shouldSatisfy` T.isInfixOf "Commands:"

  it "emits one versioned JSON plan document" $ do
    let rendered = show (encodeUpdateOutput (planOutput conflictPlan))
    rendered `shouldSatisfy` isInfixOf "\\\"schemaVersion\\\":1"
    rendered `shouldSatisfy` isInfixOf "\\\"outcome\\\":\\\"plan\\\""
    rendered `shouldSatisfy` isInfixOf "\\\"classification\\\":\\\"conflict\\\""

  it "uses a stable machine error code" $ do
    let rendered = show (encodeUpdateOutput (errorOutput (UpdateManifestMissing ".seihou/manifest.json")))
    rendered `shouldSatisfy` isInfixOf "manifest_missing"
    renderUpdateHuman False (errorOutput (UpdateManifestMissing "manifest"))
      `shouldSatisfy` T.isInfixOf "Update failed [manifest_missing]"
