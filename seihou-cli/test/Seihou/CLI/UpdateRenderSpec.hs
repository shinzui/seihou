module Seihou.CLI.UpdateRenderSpec (tests) where

import Data.List (isInfixOf)
import Data.Set qualified as Set
import Data.Text qualified as T
import Seihou.CLI.Update (UpdateError (..), UpdateWarning (..))
import Seihou.CLI.Update.Render
  ( encodeUpdateOutput,
    errorOutput,
    planOutput,
    renderUpdateHuman,
  )
import Seihou.CLI.UpdateFixture (conflictPlan, planWithWarnings)
import Seihou.Core.Types (ApplicationId (..))
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

  it "renders an expanded selection as prose, not a shown constructor" $ do
    let warning = SelectionExpandedForSharedPath ".gitignore" (ApplicationId "master-plan")
        rendered = renderUpdateHuman False (planOutput (planWithWarnings [warning]))
    rendered
      `shouldSatisfy` T.isInfixOf "Warning:     also updating master-plan because it co-owns .gitignore"
    rendered `shouldNotSatisfy` T.isInfixOf "SelectionExpandedForSharedPath"

  it "names --include-shared-owners in the shared-path refusal" $ do
    let err =
          SharedPathRequiresApplications
            ".gitignore"
            (Set.singleton (ApplicationId "nix-haskell-flake"))
            (Set.singleton (ApplicationId "master-plan"))
        rendered = renderUpdateHuman False (errorOutput err)
    rendered `shouldSatisfy` T.isInfixOf "Update failed [shared_path_requires_applications]"
    rendered `shouldSatisfy` T.isInfixOf "--include-shared-owners"
    -- The user also needs to know why the exemption did not apply.
    rendered `shouldSatisfy` T.isInfixOf "not recorded as written only by additive patches"
