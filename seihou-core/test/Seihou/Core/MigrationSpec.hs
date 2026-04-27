module Seihou.Core.MigrationSpec (tests) where

import Data.Text (Text)
import Seihou.Core.Migration
  ( Migration (..),
    MigrationChain (..),
    MigrationOp (..),
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
        Right (Just chain) -> do
          chain.migrationModule `shouldBe` "demo"
          chain.chainFrom `shouldBe` mkV "1.0.0"
          chain.chainTo `shouldBe` mkV "2.0.0"
          chain.chainSteps `shouldBe` [m]
        other -> expectationFailure ("Expected Right (Just ...), got: " <> show other)

    it "builds a two-edge chain in order regardless of declaration order" $ do
      let m1 = Migration "1.0.0" "2.0.0" [DeleteFile "a"]
          m2 = Migration "2.0.0" "3.0.0" [DeleteFile "b"]
          r = planMigrationChain "demo" [m2, m1] (mkV "1.0.0") (mkV "3.0.0")
      case r of
        Right (Just chain) -> chain.chainSteps `shouldBe` [m1, m2]
        other -> expectationFailure ("Expected Right (Just ...), got: " <> show other)

    it "stops one step short of the target with MigrationOvershoot" $ do
      let m = Migration "1.0.0" "3.0.0" []
          r = planMigrationChain "demo" [m] (mkV "1.0.0") (mkV "2.0.0")
      r `shouldBe` Left (MigrationOvershoot (mkV "1.0.0") (mkV "3.0.0"))

    it "reports MigrationGap when no edge starts at the current version" $ do
      let m1 = Migration "1.0.0" "1.5.0" []
          r = planMigrationChain "demo" [m1] (mkV "1.0.0") (mkV "2.0.0")
      r `shouldBe` Left (MigrationGap (mkV "1.5.0") (mkV "2.0.0"))

    -- Pin the current behavior for the EP-5 partial-chain case (mirrors
    -- the live-tree master-plan failure: manifest=0.1.0, target=0.3.0,
    -- declared [0.1.0 → 0.2.0]). EP-5 will replace the assertion with a
    -- successful partial plan once the planner contract softens.
    it "currently reports MigrationGap for a partial chain (pinned for EP-5)" $ do
      let m = Migration "0.1.0" "0.2.0" []
          r = planMigrationChain "demo" [m] (mkV "0.1.0") (mkV "0.3.0")
      r `shouldBe` Left (MigrationGap (mkV "0.2.0") (mkV "0.3.0"))

    -- Pin the current behavior for the EP-5 no-chain-at-all case
    -- (mirrors the live-tree exec-plan failure: manifest=0.1.3,
    -- target=0.3.0, no migrations declared).
    it "currently reports MigrationGap for an empty migrations list (pinned for EP-5)" $ do
      let r = planMigrationChain "demo" [] (mkV "0.1.3") (mkV "0.3.0")
      r `shouldBe` Left (MigrationGap (mkV "0.1.3") (mkV "0.3.0"))

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
        Right (Just chain) -> chain.chainSteps `shouldBe` [live]
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
