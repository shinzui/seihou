module Seihou.Core.MigrationSpec (tests) where

import Data.Text (Text)
import Seihou.Core.Migration
  ( Migration (..),
    MigrationChain (..),
    MigrationOp (..),
    MigrationPlan (..),
    MigrationPlanError (..),
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
  describe "planMigrationChain" $ do
    it "returns Nothing when installed equals target" $ do
      let r = planMigrationChain "demo" [] (mkV "1.0.0") (mkV "1.0.0")
      r `shouldBe` Right Nothing

    it "rejects a downgrade with MigrationDowngradeNotSupported" $ do
      let r = planMigrationChain "demo" [] (mkV "2.0.0") (mkV "1.0.0")
      r `shouldBe` Left (MigrationDowngradeNotSupported (mkV "2.0.0") (mkV "1.0.0"))

    it "builds a single-edge chain" $ do
      let m = Migration {from = "1.0.0", to = "2.0.0", ops = [DeleteFile {path = "a"}]}
          r = planMigrationChain "demo" [m] (mkV "1.0.0") (mkV "2.0.0")
      case r of
        Right (Just plan) -> do
          plan.planUnreachable `shouldBe` Nothing
          plan.planMigrationsDeclared `shouldBe` True
          plan.planChain.migrationModule `shouldBe` "demo"
          plan.planChain.chainFrom `shouldBe` mkV "1.0.0"
          plan.planChain.chainTo `shouldBe` mkV "2.0.0"
          plan.planChain.chainSteps `shouldBe` [m]
        other -> expectationFailure ("Expected Right (Just ...), got: " <> show other)

    it "builds a two-edge chain in order regardless of declaration order" $ do
      let m1 = Migration "1.0.0" "2.0.0" [DeleteFile "a"]
          m2 = Migration "2.0.0" "3.0.0" [DeleteFile "b"]
          r = planMigrationChain "demo" [m2, m1] (mkV "1.0.0") (mkV "3.0.0")
      case r of
        Right (Just plan) -> do
          plan.planUnreachable `shouldBe` Nothing
          plan.planMigrationsDeclared `shouldBe` True
          plan.planChain.chainSteps `shouldBe` [m1, m2]
        other -> expectationFailure ("Expected Right (Just ...), got: " <> show other)

    it "stops one step short of the target with MigrationOvershoot" $ do
      let m = Migration "1.0.0" "3.0.0" []
          r = planMigrationChain "demo" [m] (mkV "1.0.0") (mkV "2.0.0")
      r `shouldBe` Left (MigrationOvershoot (mkV "1.0.0") (mkV "3.0.0"))

    it "returns a partial chain plus an unreachable tail when the walk gets stuck mid-way" $ do
      let m1 = Migration "1.0.0" "1.5.0" [DeleteFile "a"]
          r = planMigrationChain "demo" [m1] (mkV "1.0.0") (mkV "2.0.0")
      case r of
        Right (Just plan) -> do
          plan.planChain.chainFrom `shouldBe` mkV "1.0.0"
          plan.planChain.chainTo `shouldBe` mkV "1.5.0"
          plan.planChain.chainSteps `shouldBe` [m1]
          plan.planUnreachable `shouldBe` Just (mkV "1.5.0", mkV "2.0.0")
          plan.planMigrationsDeclared `shouldBe` True
        other -> expectationFailure ("Expected Right (Just ...), got: " <> show other)

    -- Live-tree master-plan failure mode (manifest=0.1.0, target=0.3.0,
    -- declared [0.1.0 -> 0.2.0]). Was Left (MigrationGap 0.2.0 0.3.0)
    -- before EP-5; now returned in-band as a partial plan.
    it "returns a partial plan for the EP-5 master-plan fixture" $ do
      let m = Migration "0.1.0" "0.2.0" []
          r = planMigrationChain "demo" [m] (mkV "0.1.0") (mkV "0.3.0")
      case r of
        Right (Just plan) -> do
          plan.planChain.chainSteps `shouldBe` [m]
          plan.planChain.chainFrom `shouldBe` mkV "0.1.0"
          plan.planChain.chainTo `shouldBe` mkV "0.2.0"
          plan.planUnreachable `shouldBe` Just (mkV "0.2.0", mkV "0.3.0")
          plan.planMigrationsDeclared `shouldBe` True
        other -> expectationFailure ("Expected Right (Just ...), got: " <> show other)

    -- Live-tree exec-plan failure mode (manifest=0.1.3, target=0.3.0, no
    -- migrations declared). Was Left (MigrationGap 0.1.3 0.3.0) before
    -- EP-5; now returned as a blocked plan: empty chain + unreachable
    -- tail covering the full span. With M2 the empty list is also
    -- reflected in planMigrationsDeclared = False.
    it "returns a blocked plan (empty chain + unreachable tail) when no edge starts at installed" $ do
      let r = planMigrationChain "demo" [] (mkV "0.1.3") (mkV "0.3.0")
      case r of
        Right (Just plan) -> do
          plan.planChain.chainSteps `shouldBe` []
          plan.planChain.chainFrom `shouldBe` mkV "0.1.3"
          plan.planChain.chainTo `shouldBe` mkV "0.1.3"
          plan.planUnreachable `shouldBe` Just (mkV "0.1.3", mkV "0.3.0")
          plan.planMigrationsDeclared `shouldBe` False
        other -> expectationFailure ("Expected Right (Just ...), got: " <> show other)

    -- M1 pin, flipped in M2: planMigrationsDeclared now distinguishes
    -- the two cases that EP-5 collapsed. The empty list yields
    -- planMigrationsDeclared = False (benign version gap); the
    -- orphan-edge list yields True (declared but unreachable). The
    -- chain shape itself remains identical, which is what consumers
    -- (status / migrate / run) layer their dispatch on top of.
    it "distinguishes migrations=[] from migrations=[someEdge-that-doesnt-reach] via planMigrationsDeclared" $ do
      let rEmpty =
            planMigrationChain "demo" [] (mkV "0.2.0") (mkV "0.3.0")
          unreachableEdge = Migration "0.5.0" "0.6.0" []
          rOrphan =
            planMigrationChain "demo" [unreachableEdge] (mkV "0.2.0") (mkV "0.3.0")
      case (rEmpty, rOrphan) of
        (Right (Just pEmpty), Right (Just pOrphan)) -> do
          pEmpty.planChain.chainSteps `shouldBe` []
          pOrphan.planChain.chainSteps `shouldBe` []
          pEmpty.planChain.chainFrom `shouldBe` pOrphan.planChain.chainFrom
          pEmpty.planChain.chainTo `shouldBe` pOrphan.planChain.chainTo
          pEmpty.planUnreachable `shouldBe` pOrphan.planUnreachable
          pEmpty.planUnreachable `shouldBe` Just (mkV "0.2.0", mkV "0.3.0")
          pEmpty.planMigrationsDeclared `shouldBe` False
          pOrphan.planMigrationsDeclared `shouldBe` True
        other ->
          expectationFailure
            ("Expected two Right (Just …), got: " <> show other)

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
          plan.planUnreachable `shouldBe` Nothing
          plan.planChain.chainSteps `shouldBe` [live]
          plan.planMigrationsDeclared `shouldBe` True
        other -> expectationFailure ("Expected Right (Just ...), got: " <> show other)

    it "treats version equality with trailing zeros consistently" $ do
      -- `mkV "1.0"` and `mkV "1.0.0"` compare equal; planner should treat
      -- them as no-op.
      let r = planMigrationChain "demo" [] (mkV "1.0") (mkV "1.0.0")
      r `shouldBe` Right Nothing

    -- ----------------------------------------------------------------
    -- EP-28 M1: planTailExhausted
    --
    -- The planner now reports whether the unreachable tail's region
    -- declares any further migrations. Consumers (notably `seihou
    -- migrate`) split the partial-chain shape into two sub-cases:
    --
    --   * Exhausted tail — no migration in the input list has
    --     `from > stuckAt`. The author ran out of declared migrations.
    --     `seihou migrate` will treat this as a benign version-only
    --     bump and advance the manifest all the way to target.
    --   * Blocked tail — some migration has `from > stuckAt`. The
    --     author has plans in the unreachable region but they don't
    --     form a continuous chain. The user is genuinely stuck.
    -- ----------------------------------------------------------------

    it "EP-28: planTailExhausted = True for full chains" $ do
      let m = Migration "1.0.0" "2.0.0" [DeleteFile "x"]
          r = planMigrationChain "demo" [m] (mkV "1.0.0") (mkV "2.0.0")
      case r of
        Right (Just plan) -> plan.planTailExhausted `shouldBe` True
        other -> expectationFailure ("Expected Right (Just ...), got: " <> show other)

    it "EP-28: planTailExhausted = True for partial chain whose tail has no further declared edges" $ do
      -- The user's master-plan-shape fixture: migrations=[{0.1->0.2}],
      -- target=0.3. After the chain reaches 0.2, no migration has
      -- `from > 0.2`, so the tail is exhausted.
      let m = Migration "0.1.0" "0.2.0" []
          r = planMigrationChain "demo" [m] (mkV "0.1.0") (mkV "0.3.0")
      case r of
        Right (Just plan) -> do
          plan.planChain.chainSteps `shouldBe` [m]
          plan.planChain.chainTo `shouldBe` mkV "0.2.0"
          plan.planUnreachable `shouldBe` Just (mkV "0.2.0", mkV "0.3.0")
          plan.planTailExhausted `shouldBe` True
        other -> expectationFailure ("Expected Right (Just ...), got: " <> show other)

    it "EP-28: planTailExhausted = False for partial chain whose tail still has future edges" $ do
      -- The "real block past the chain" shape: migrations=[{0.1->0.2,
      -- 0.5->0.6}], target=0.6. After the chain reaches 0.2, the
      -- declared edge {0.5->0.6} starts at a version > 0.2, so the
      -- tail is *not* exhausted — the author has plans in the
      -- unreachable region but the chain doesn't span the gap.
      let early = Migration "0.1.0" "0.2.0" []
          future = Migration "0.5.0" "0.6.0" []
          r = planMigrationChain "demo" [early, future] (mkV "0.1.0") (mkV "0.6.0")
      case r of
        Right (Just plan) -> do
          plan.planChain.chainSteps `shouldBe` [early]
          plan.planChain.chainTo `shouldBe` mkV "0.2.0"
          plan.planUnreachable `shouldBe` Just (mkV "0.2.0", mkV "0.6.0")
          plan.planTailExhausted `shouldBe` False
        other -> expectationFailure ("Expected Right (Just ...), got: " <> show other)

    it "EP-28: planTailExhausted = True for benign empty migrations" $ do
      -- migrations=[], manifest=0.1, target=0.3. No declared edges
      -- anywhere → tail is trivially exhausted.
      let r = planMigrationChain "demo" [] (mkV "0.1.0") (mkV "0.3.0")
      case r of
        Right (Just plan) -> do
          plan.planMigrationsDeclared `shouldBe` False
          plan.planTailExhausted `shouldBe` True
        other -> expectationFailure ("Expected Right (Just ...), got: " <> show other)

    it "EP-28: planTailExhausted = False for orphan-edge full block" $ do
      -- Empty chain (orphan edge starts past manifest), migrations
      -- list has an edge with from > stuckAt (= manifest version).
      -- Tail is not exhausted: the author declared a future edge.
      let orphan = Migration "0.5.0" "0.6.0" []
          r = planMigrationChain "demo" [orphan] (mkV "0.1.0") (mkV "0.6.0")
      case r of
        Right (Just plan) -> do
          plan.planChain.chainSteps `shouldBe` []
          plan.planMigrationsDeclared `shouldBe` True
          plan.planTailExhausted `shouldBe` False
        other -> expectationFailure ("Expected Right (Just ...), got: " <> show other)

    it "EP-28: planTailExhausted ignores edges with from <= stuckAt" $ do
      -- A migration with `from < stuckAt` is in the past; it doesn't
      -- count as a future edge. Same chain shape as the bump-through
      -- case but with an extra stale edge that the walker overshot.
      let stale = Migration "0.0.5" "0.1.0" []
          applied = Migration "0.1.0" "0.2.0" []
          r =
            planMigrationChain
              "demo"
              [stale, applied]
              (mkV "0.1.0")
              (mkV "0.3.0")
      case r of
        Right (Just plan) -> do
          plan.planChain.chainSteps `shouldBe` [applied]
          plan.planChain.chainTo `shouldBe` mkV "0.2.0"
          plan.planTailExhausted `shouldBe` True
        other -> expectationFailure ("Expected Right (Just ...), got: " <> show other)

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

mkV :: Text -> Version
mkV t = case parseVersion t of
  Just ver -> ver
  Nothing -> error ("MigrationSpec.mkV: bad version literal " <> show t)
