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
        other -> expectationFailure ("Expected Right (Just ...), got: " <> show other)

    -- Live-tree exec-plan failure mode (manifest=0.1.3, target=0.3.0, no
    -- migrations declared). Was Left (MigrationGap 0.1.3 0.3.0) before
    -- EP-5; now returned as a blocked plan: empty chain + unreachable
    -- tail covering the full span.
    it "returns a blocked plan (empty chain + unreachable tail) when no edge starts at installed" $ do
      let r = planMigrationChain "demo" [] (mkV "0.1.3") (mkV "0.3.0")
      case r of
        Right (Just plan) -> do
          plan.planChain.chainSteps `shouldBe` []
          plan.planChain.chainFrom `shouldBe` mkV "0.1.3"
          plan.planChain.chainTo `shouldBe` mkV "0.1.3"
          plan.planUnreachable `shouldBe` Just (mkV "0.1.3", mkV "0.3.0")
        other -> expectationFailure ("Expected Right (Just ...), got: " <> show other)

    -- M1 pin: today the planner output cannot distinguish
    -- "migrations = []" from "migrations = [someEdge]" where
    -- someEdge does not start at the installed version. Both produce
    -- the same MigrationPlan shape (empty chain + unreachable tail
    -- spanning the full gap). After the next milestone this changes:
    -- planMigrationsDeclared lets consumers tell the two cases apart.
    it "today returns the same shape for migrations=[] and migrations=[someEdge-that-doesnt-reach]" $ do
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
        other -> expectationFailure ("Expected Right (Just ...), got: " <> show other)

    it "treats version equality with trailing zeros consistently" $ do
      -- `mkV "1.0"` and `mkV "1.0.0"` compare equal; planner should treat
      -- them as no-op.
      let r = planMigrationChain "demo" [] (mkV "1.0") (mkV "1.0.0")
      r `shouldBe` Right Nothing

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

mkV :: Text -> Version
mkV t = case parseVersion t of
  Just ver -> ver
  Nothing -> error ("MigrationSpec.mkV: bad version literal " <> show t)
