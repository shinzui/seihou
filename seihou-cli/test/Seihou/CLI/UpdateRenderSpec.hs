{-# LANGUAGE LambdaCase #-}

module Seihou.CLI.UpdateRenderSpec (tests) where

import Control.Lens ((&), (.~), (^.))
import Data.Char (isHexDigit)
import Data.Generics.Labels ()
import Data.List (isInfixOf)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as T
import Seihou.CLI.ApplicationDisplay (applicationLabel)
import Seihou.CLI.ManifestCapabilityUpgrade (CertificationGap (..), EvidenceSource (..))
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
    ParentVars (..),
    RecipeName (..),
    SharedWriteMode (..),
    VarName (..),
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

  describe "application labels" $ do
    it "names an application by its target and parent variables, never its digest" $
      applicationLabel skillRef `shouldBe` "exec-plan [skill.name=exec-plan]"

    it "sorts parent variables and names additional modules" $ do
      let ref =
            ApplicationRef
              (ApplicationId (T.replicate 64 "b"))
              (Just (AppliedRecipeTarget (RecipeName "haskell-service")))
              (ParentVars (Map.fromList [(VarName "z", "2"), (VarName "a", "1")]))
              [ModuleName "direnv", ModuleName "just"]
      applicationLabel ref `shouldBe` "haskell-service [a=1, z=2] (with direnv, just)"

    it "shows only a short digest prefix for an owner the manifest does not record" $ do
      let label = applicationLabel (ApplicationRef (ApplicationId (T.replicate 64 "c")) Nothing emptyParentVars [])
      label `shouldBe` "unrecorded application cccccccccccc"
      label `shouldNotSatisfy` leaksInternals

  describe "warnings" $ do
    it "covers every constructor" $
      all coveredWarning everyWarning `shouldBe` True

    it "renders every constructor as prose in both human and JSON output" $
      mapM_
        ( \warning -> do
            let human = renderUpdateHuman False (planOutput (planWithWarnings [warning]))
                json = T.pack (show (encodeUpdateOutput (planOutput (planWithWarnings [warning]))))
            human `shouldNotSatisfy` leaksInternals
            json `shouldNotSatisfy` T.isInfixOf "ModuleName {"
            json `shouldNotSatisfy` T.isInfixOf "CrossApplicationLastWriter"
        )
        everyWarning

    it "explains a cross-application last writer as attribution, not a content change" $ do
      let rendered =
            renderUpdateHuman
              False
              (planOutput (planWithWarnings [CrossApplicationLastWriter "ADR.md" (ModuleName "exec-plan") (ModuleName "link-skill")]))
      rendered
        `shouldSatisfy` T.isInfixOf
          "ADR.md receives content from both exec-plan and link-skill; link-skill is recorded as its last writer"
      rendered `shouldSatisfy` T.isInfixOf "not a content change"

    it "labels an expanded owner with its parent variables" $
      renderUpdateHuman False (planOutput (planWithWarnings [SelectionExpandedForSharedPath ".gitignore" skillRef]))
        `shouldSatisfy` T.isInfixOf "also updating exec-plan [skill.name=exec-plan] because it co-owns .gitignore"

  describe "closure and evidence errors" $ do
    it "lists selected and required owners by label and offers a concrete selection" $ do
      let err =
            SharedPathRequiresApplications
              ".gitignore"
              (Set.singleton (moduleRef "nix-haskell-flake"))
              (Set.singleton skillRef)
          rendered = renderUpdateHuman False (errorOutput err)
      rendered `shouldSatisfy` T.isInfixOf "Selected: nix-haskell-flake"
      rendered `shouldSatisfy` T.isInfixOf "Also required: exec-plan [skill.name=exec-plan]"
      rendered `shouldSatisfy` T.isInfixOf "(seihou update exec-plan nix-haskell-flake)"
      rendered `shouldSatisfy` T.isInfixOf "--include-shared-owners to update their full applications"
      rendered `shouldNotSatisfy` leaksInternals
      rendered `shouldNotSatisfy` T.isInfixOf "no targets"

    it "leads the evidence error with the repair and never offers expansion" $ do
      let err =
            SharedWriteEvidenceUnavailable
              ".gitignore"
              [(skillRef, OwnerEvidenceUnavailable (skillRef ^. #applicationId) "module exec-plan 1.2.0 is not installed here")]
          rendered = renderUpdateHuman False (errorOutput err)
      rendered `shouldSatisfy` T.isPrefixOf "Update failed [shared_write_evidence_unavailable]: Install the recorded version"
      rendered `shouldSatisfy` T.isInfixOf "exec-plan [skill.name=exec-plan]: module exec-plan 1.2.0 is not installed here"
      rendered `shouldSatisfy` T.isInfixOf "does not update it"
      rendered `shouldNotSatisfy` T.isInfixOf "--include-shared-owners"
      rendered `shouldNotSatisfy` leaksInternals

    it "leads the legacy-schema error with the explicit upgrade command" $
      renderUpdateHuman False (errorOutput (UpdateManifestUpgradeRequired ".seihou/manifest.json" (ManifestSchemaVersion 5)))
        `shouldSatisfy` T.isPrefixOf "Update failed [manifest_upgrade_required]: Run 'seihou manifest upgrade --dry-run'"

    it "keeps the machine error codes stable in JSON" $
      mapM_
        ( \(err, code) ->
            show (encodeUpdateOutput (errorOutput err)) `shouldSatisfy` isInfixOf ("\\\"code\\\":\\\"" <> code <> "\\\"")
        )
        [ (SharedPathRequiresApplications ".gitignore" Set.empty (Set.singleton skillRef), "shared_path_requires_applications"),
          (SharedWriteEvidenceUnavailable ".gitignore" [], "shared_write_evidence_unavailable"),
          (UpdateManifestUpgradeRequired "m" (ManifestSchemaVersion 5), "manifest_upgrade_required")
        ]

  it "shows a staged manifest preparation in the human and JSON plan" $ do
    let preparation =
          ManifestPreparation
            { fromVersion = ManifestSchemaVersion 6,
              toVersion = ManifestSchemaVersion 7,
              modeChanges = Map.singleton ".gitignore" (SharedWriteUnknown, SharedWriteAdditiveOnly),
              evidenceSources = [],
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
    -- Nothing was fetched, so the output is exactly what it was before.
    json `shouldNotSatisfy` isInfixOf "evidenceSources"
    human `shouldNotSatisfy` T.isInfixOf "read from"

  it "names each fetched recorded release in the human and JSON plan" $ do
    let source =
          EvidenceSource
            { moduleName = ModuleName "nix-haskell-flake",
              version = "0.13.2",
              originUrl = "https://github.com/shinzui/seihou-modules.git",
              revision = "08191d3"
            }
        preparation =
          ManifestPreparation
            { fromVersion = ManifestSchemaVersion 7,
              toVersion = ManifestSchemaVersion 7,
              modeChanges = Map.singleton ".gitignore" (SharedWriteUnknown, SharedWriteAdditiveOnly),
              evidenceSources = [source],
              preparedManifest = planWithWarnings [] ^. #snapshot . #originalManifest
            }
        plan = planWithWarnings [] & #manifestPreparation .~ Just preparation
        human = renderUpdateHuman False (planOutput plan)
        json = show (encodeUpdateOutput (planOutput plan))
    human
      `shouldSatisfy` T.isInfixOf
        "             (nix-haskell-flake 0.13.2 read from https://github.com/shinzui/seihou-modules.git at 08191d3)"
    json `shouldSatisfy` isInfixOf "\\\"evidenceSources\\\":[{"
    json `shouldSatisfy` isInfixOf "\\\"revision\\\":\\\"08191d3\\\""
    json `shouldSatisfy` isInfixOf "\\\"module\\\":\\\"nix-haskell-flake\\\""

-- | One of every warning constructor. Adding a constructor without adding
-- it here fails the exhaustiveness test below.
everyWarning :: [UpdateWarning]
everyWarning =
  [ LocalArtifactHasNoRemote "demo",
    SameVersionContentChanged "demo",
    AmbiguousLegacyValue (VarName "project.name"),
    MissingLegacyValue (VarName "project.name"),
    MigrationCommandNotSimulated (ModuleName "demo") "cabal gen-bounds",
    CrossApplicationLastWriter "agents/skills/exec-plan/ADR.md" (ModuleName "exec-plan") (ModuleName "exec-plan#bfa0a336"),
    ArbitraryCommandSideEffectsMayRemain,
    BaselinePruneFailed "permission denied",
    RecoveryCleanupDeferred "permission denied",
    SelectionExpandedForSharedPath ".gitignore" skillRef
  ]

-- | Whether a warning is one of 'everyWarning's constructors. Written as a
-- total match so GHC's incomplete-pattern warning names a new constructor.
coveredWarning :: UpdateWarning -> Bool
coveredWarning = \case
  LocalArtifactHasNoRemote {} -> True
  SameVersionContentChanged {} -> True
  AmbiguousLegacyValue {} -> True
  MissingLegacyValue {} -> True
  MigrationCommandNotSimulated {} -> True
  CrossApplicationLastWriter {} -> True
  ArbitraryCommandSideEffectsMayRemain -> True
  BaselinePruneFailed {} -> True
  RecoveryCleanupDeferred {} -> True
  SelectionExpandedForSharedPath {} -> True

-- | Text that must never reach a person: Haskell constructor or record
-- syntax, or a whole application digest.
leaksInternals :: T.Text -> Bool
leaksInternals text =
  any
    (`T.isInfixOf` text)
    ["ApplicationId", "ModuleName {", "unModuleName", "CrossApplicationLastWriter", "SelectionExpandedForSharedPath", "fromList"]
    || any ((>= 64) . T.length) (T.split (not . isHexDigit) text)

skillRef :: ApplicationRef
skillRef =
  ApplicationRef
    (ApplicationId (T.replicate 64 "a"))
    (Just (AppliedModuleTarget (ModuleName "exec-plan")))
    (ParentVars (Map.fromList [(VarName "skill.name", "exec-plan")]))
    []

moduleRef :: T.Text -> ApplicationRef
moduleRef name = ApplicationRef (ApplicationId name) (Just (AppliedModuleTarget (ModuleName name))) emptyParentVars []
