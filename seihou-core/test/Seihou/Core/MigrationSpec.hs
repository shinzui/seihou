module Seihou.Core.MigrationSpec (tests) where

import Data.Text (Text)
import Seihou.Core.Migration
  ( BlueprintMigration (..),
    BlueprintMigrationPlan (..),
    Migration (..),
    MigrationOp (..),
    MigrationPlan (..),
    MigrationPlanError (..),
    planBlueprintMigrationChain,
    planMigrationChain,
  )
import Seihou.Core.Version (Version, parseVersion)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Core.Migration" spec

spec :: Spec
spec = do
  describe "planMigrationChain (window walker)" $ do
    it "returns Nothing when installed equals target" $ do
      let r = planMigrationChain "demo" [] (mkV "1.0.0") (mkV "1.0.0")
      r `shouldBe` Right Nothing

    it "rejects a downgrade with MigrationDowngradeNotSupported" $ do
      let r = planMigrationChain "demo" [] (mkV "2.0.0") (mkV "1.0.0")
      r `shouldBe` Left (MigrationDowngradeNotSupported (mkV "2.0.0") (mkV "1.0.0"))

    it "builds a single-edge plan whose target equals the edge's `to`" $ do
      let m = Migration {from = "1.0.0", to = "2.0.0", ops = [DeleteFile {path = "a"}]}
          r = planMigrationChain "demo" [m] (mkV "1.0.0") (mkV "2.0.0")
      case r of
        Right (Just plan) -> do
          plan.planModule `shouldBe` "demo"
          plan.planFrom `shouldBe` mkV "1.0.0"
          plan.planTo `shouldBe` mkV "2.0.0"
          plan.planSteps `shouldBe` [m]
        other -> expectationFailure ("Expected Right (Just ...), got: " <> show other)

    it "builds a two-edge plan in order regardless of declaration order" $ do
      let m1 = Migration "1.0.0" "2.0.0" [DeleteFile "a"]
          m2 = Migration "2.0.0" "3.0.0" [DeleteFile "b"]
          r = planMigrationChain "demo" [m2, m1] (mkV "1.0.0") (mkV "3.0.0")
      case r of
        Right (Just plan) -> do
          plan.planSteps `shouldBe` [m1, m2]
          plan.planTo `shouldBe` mkV "3.0.0"
        other -> expectationFailure ("Expected Right (Just ...), got: " <> show other)

    -- Live-tree master-plan fixture (manifest=0.1.0, target=0.3.0,
    -- declared [0.1.0 -> 0.2.0]). The chain reaches 0.2.0 via ops; the
    -- manifest still advances to the supplied target 0.3.0.
    it "yields a partial-cover plan for the EP-5 master-plan fixture" $ do
      let m = Migration "0.1.0" "0.2.0" []
          r = planMigrationChain "demo" [m] (mkV "0.1.0") (mkV "0.3.0")
      case r of
        Right (Just plan) -> do
          plan.planSteps `shouldBe` [m]
          plan.planFrom `shouldBe` mkV "0.1.0"
          plan.planTo `shouldBe` mkV "0.3.0"
        other -> expectationFailure ("Expected Right (Just ...), got: " <> show other)

    it "yields an empty-steps plan when no declared migration falls in the window" $ do
      let r = planMigrationChain "demo" [] (mkV "0.1.3") (mkV "0.3.0")
      case r of
        Right (Just plan) -> do
          plan.planSteps `shouldBe` []
          plan.planFrom `shouldBe` mkV "0.1.3"
          plan.planTo `shouldBe` mkV "0.3.0"
        other -> expectationFailure ("Expected Right (Just ...), got: " <> show other)

    it "reports MigrationVersionUnparseable when a from string is malformed" $ do
      let m = Migration "not-a-version" "2.0.0" []
          r = planMigrationChain "demo" [m] (mkV "1.0.0") (mkV "2.0.0")
      r `shouldBe` Left (MigrationVersionUnparseable "not-a-version")

    it "reports MigrationVersionUnparseable when a to string is malformed" $ do
      let m = Migration "1.0.0" "" []
          r = planMigrationChain "demo" [m] (mkV "1.0.0") (mkV "2.0.0")
      r `shouldBe` Left (MigrationVersionUnparseable "")

    it "rejects two edges sharing the same from with MigrationDuplicateEdge" $ do
      let m1 = Migration "1.0.0" "2.0.0" []
          m2 = Migration "1.0.0" "1.5.0" []
          r = planMigrationChain "demo" [m1, m2] (mkV "1.0.0") (mkV "2.0.0")
      case r of
        Left (MigrationDuplicateEdge fromV _) -> fromV `shouldBe` mkV "1.0.0"
        other -> expectationFailure ("Expected MigrationDuplicateEdge, got: " <> show other)

    it "ignores migrations whose from precedes the installed version" $ do
      -- An old 0.5.0 → 1.0.0 migration is irrelevant when installed is 1.0.0.
      let stale = Migration "0.5.0" "1.0.0" []
          live = Migration "1.0.0" "2.0.0" [DeleteFile "x"]
          r = planMigrationChain "demo" [stale, live] (mkV "1.0.0") (mkV "2.0.0")
      case r of
        Right (Just plan) -> do
          plan.planSteps `shouldBe` [live]
          plan.planTo `shouldBe` mkV "2.0.0"
        other -> expectationFailure ("Expected Right (Just ...), got: " <> show other)

    it "treats version equality with trailing zeros consistently" $ do
      -- `mkV "1.0"` and `mkV "1.0.0"` compare equal; planner should treat
      -- them as no-op.
      let r = planMigrationChain "demo" [] (mkV "1.0") (mkV "1.0.0")
      r `shouldBe` Right Nothing

    -- ----------------------------------------------------------------
    -- New EP-35 contract pins
    -- ----------------------------------------------------------------

    it "user's two-component fixture: 0.2 / 0.6 with [{0.2→0.3}, {0.5→0.6}] yields both edges" $ do
      let early = Migration "0.2" "0.3" [DeleteFile "v2"]
          late = Migration "0.5" "0.6" [DeleteFile "v5"]
          r = planMigrationChain "foo" [early, late] (mkV "0.2") (mkV "0.6")
      case r of
        Right (Just plan) -> do
          plan.planFrom `shouldBe` mkV "0.2"
          plan.planTo `shouldBe` mkV "0.6"
          plan.planSteps `shouldBe` [early, late]
        other -> expectationFailure ("Expected Right (Just ...), got: " <> show other)

    it "skips migrations that overshoot the supplied target" $ do
      let m = Migration "0.5" "1.0" []
          r = planMigrationChain "demo" [m] (mkV "0.4") (mkV "0.6")
      case r of
        Right (Just plan) -> do
          plan.planSteps `shouldBe` []
          plan.planTo `shouldBe` mkV "0.6"
        other -> expectationFailure ("Expected Right (Just ...), got: " <> show other)

    it "skips overlapping migrations once the cursor has advanced past them" $ do
      let big = Migration "0.2" "0.5" [DeleteFile "a"]
          small = Migration "0.3" "0.4" [DeleteFile "b"]
          r = planMigrationChain "demo" [big, small] (mkV "0.2") (mkV "0.5")
      case r of
        Right (Just plan) ->
          plan.planSteps `shouldBe` [big]
        other -> expectationFailure ("Expected Right (Just ...), got: " <> show other)

    it "empty migrations list with installed != target yields empty-steps plan with target" $ do
      let r = planMigrationChain "demo" [] (mkV "0.1") (mkV "0.3")
      case r of
        Right (Just plan) -> do
          plan.planSteps `shouldBe` []
          plan.planFrom `shouldBe` mkV "0.1"
          plan.planTo `shouldBe` mkV "0.3"
        other -> expectationFailure ("Expected Right (Just ...), got: " <> show other)

    it "edges with `to == target` are picked" $ do
      let m = Migration "0.2" "0.3" [DeleteFile "x"]
          r = planMigrationChain "demo" [m] (mkV "0.2") (mkV "0.3")
      case r of
        Right (Just plan) ->
          plan.planSteps `shouldBe` [m]
        other -> expectationFailure ("Expected Right (Just ...), got: " <> show other)

  describe "planBlueprintMigrationChain" $ do
    it "orders in-window migrations while allowing intentional gaps" $ do
      let early = BlueprintMigration "1.0.0" "2.0.0" "first"
          late = BlueprintMigration "2.5.0" "3.0.0" "second"
          result = planBlueprintMigrationChain "demo" [late, early] (mkV "1.0.0") (mkV "3.0.0")
      case result of
        Right (Just plan) -> do
          plan.blueprintPlanName `shouldBe` "demo"
          plan.blueprintPlanFrom `shouldBe` mkV "1.0.0"
          plan.blueprintPlanTo `shouldBe` mkV "3.0.0"
          plan.blueprintPlanSteps `shouldBe` [early, late]
        other -> expectationFailure ("Expected ordered blueprint plan, got: " <> show other)

    it "returns Nothing for an equal version window" $ do
      planBlueprintMigrationChain "demo" [] (mkV "1.0.0") (mkV "1.0.0")
        `shouldBe` Right Nothing

    it "rejects a downgrade" $ do
      planBlueprintMigrationChain "demo" [] (mkV "3.0.0") (mkV "2.0.0")
        `shouldBe` Left (MigrationDowngradeNotSupported (mkV "3.0.0") (mkV "2.0.0"))

    it "rejects an unparseable declared version" $ do
      let migration = BlueprintMigration "release-1" "2.0.0" "change"
      planBlueprintMigrationChain "demo" [migration] (mkV "1.0.0") (mkV "2.0.0")
        `shouldBe` Left (MigrationVersionUnparseable "release-1")

    it "rejects duplicate starts" $ do
      let first = BlueprintMigration "1.0.0" "2.0.0" "first"
          second = BlueprintMigration "1.0.0" "1.5.0" "second"
          result = planBlueprintMigrationChain "demo" [first, second] (mkV "1.0.0") (mkV "2.0.0")
      case result of
        Left (MigrationDuplicateEdge fromVersion _) -> fromVersion `shouldBe` mkV "1.0.0"
        other -> expectationFailure ("Expected duplicate blueprint edge error, got: " <> show other)

    it "skips an edge that overshoots the target" $ do
      let migration = BlueprintMigration "1.0.0" "3.0.0" "too far"
          result = planBlueprintMigrationChain "demo" [migration] (mkV "1.0.0") (mkV "2.0.0")
      case result of
        Right (Just plan) -> plan.blueprintPlanSteps `shouldBe` []
        other -> expectationFailure ("Expected empty blueprint plan, got: " <> show other)

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

mkV :: Text -> Version
mkV t = case parseVersion t of
  Just ver -> ver
  Nothing -> error ("MigrationSpec.mkV: bad version literal " <> show t)
