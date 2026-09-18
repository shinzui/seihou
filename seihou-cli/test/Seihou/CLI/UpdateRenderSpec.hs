module Seihou.CLI.UpdateRenderSpec (tests) where

import Control.Lens ((&), (.~), (^.))
import Data.Generics.Labels ()
import Data.List (isInfixOf)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as T
import Seihou.CLI.ManifestCapabilityUpgrade (CertificationGap (..))
import Seihou.CLI.Update (UpdateError (..), UpdateWarning (..))
import Seihou.CLI.Update.Render
  ( encodeUpdateOutput,
    errorOutput,
    planOutput,
    renderUpdateHuman,
  )
import Seihou.CLI.Update.Types (ApplicationRef (..), ManifestPreparation (..))
import Seihou.CLI.UpdateFixture (conflictPlan, planWithWarnings)
import Seihou.Core.Types
  ( ApplicationId (..),
    AppliedTarget (..),
    ManifestSchemaVersion (..),
    ModuleName (..),
    SharedWriteMode (..),
    emptyParentVars,
  )
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
    let warning = SelectionExpandedForSharedPath ".gitignore" (moduleRef "master-plan")
        rendered = renderUpdateHuman False (planOutput (planWithWarnings [warning]))
    rendered
      `shouldSatisfy` T.isInfixOf "Warning:     also updating master-plan because it co-owns .gitignore"
    rendered `shouldNotSatisfy` T.isInfixOf "SelectionExpandedForSharedPath"

  it "names --include-shared-owners only for a known whole-file refusal" $ do
    let err =
          SharedPathRequiresApplications
            ".gitignore"
            (Set.singleton (moduleRef "nix-haskell-flake"))
            (Set.singleton (moduleRef "master-plan"))
        rendered = renderUpdateHuman False (errorOutput err)
    rendered `shouldSatisfy` T.isInfixOf "Update failed [shared_path_requires_applications]"
    rendered `shouldSatisfy` T.isInfixOf "--include-shared-owners"
    rendered `shouldSatisfy` T.isInfixOf "writes the whole file"
    rendered `shouldSatisfy` T.isInfixOf "master-plan"

  it "reports missing evidence without offering to broaden the selection" $ do
    let owner = moduleRef "master-plan"
        err =
          SharedWriteEvidenceUnavailable
            ".gitignore"
            [(owner, OwnerEvidenceUnavailable (ApplicationId "master-plan") "module master-plan 1.0.0 is not installed here")]
        rendered = renderUpdateHuman False (errorOutput err)
    rendered `shouldSatisfy` T.isInfixOf "Update failed [shared_write_evidence_unavailable]"
    rendered `shouldSatisfy` T.isInfixOf "master-plan: module master-plan 1.0.0 is not installed here"
    rendered `shouldNotSatisfy` T.isInfixOf "--include-shared-owners"

  it "names the explicit upgrade command for a legacy-schema manifest" $ do
    let rendered = renderUpdateHuman False (errorOutput (UpdateManifestUpgradeRequired ".seihou/manifest.json" (ManifestSchemaVersion 5)))
    rendered `shouldSatisfy` T.isInfixOf "Update failed [manifest_upgrade_required]"
    rendered `shouldSatisfy` T.isInfixOf "seihou manifest upgrade"

  it "shows a staged manifest preparation in the human and JSON plan" $ do
    let preparation =
          ManifestPreparation
            { fromVersion = ManifestSchemaVersion 6,
              toVersion = ManifestSchemaVersion 7,
              modeChanges = Map.singleton ".gitignore" (SharedWriteUnknown, SharedWriteAdditiveOnly),
              preparedManifest = planWithWarnings [] ^. #snapshot . #originalManifest
            }
        plan = planWithWarnings [] & #manifestPreparation .~ Just preparation
        human = renderUpdateHuman False (planOutput plan)
        json = show (encodeUpdateOutput (planOutput plan))
    human `shouldSatisfy` T.isInfixOf "Manifest:    schema 6 -> 7"
    human `shouldSatisfy` T.isInfixOf ".gitignore evidence unknown -> additive-only"
    json `shouldSatisfy` isInfixOf "\\\"fromSchema\\\":6"
    json `shouldSatisfy` isInfixOf "\\\"toSchema\\\":7"
    json `shouldSatisfy` isInfixOf "\\\"alreadyUpToDate\\\":false"

moduleRef :: T.Text -> ApplicationRef
moduleRef name = ApplicationRef (ApplicationId name) (Just (AppliedModuleTarget (ModuleName name))) emptyParentVars
