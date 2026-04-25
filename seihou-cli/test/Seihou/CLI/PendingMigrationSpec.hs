module Seihou.CLI.PendingMigrationSpec (tests) where

import Data.Text (Text)
import Data.Time (UTCTime, defaultTimeLocale, parseTimeOrError)
import Seihou.CLI.Migrate (pendingChainFor)
import Seihou.Core.Migration
  ( Migration (..),
    MigrationChain (..),
    MigrationOp (..),
  )
import Seihou.Core.Types
  ( AppliedModule (..),
    Module (..),
    ModuleName (..),
    emptyParentVars,
  )
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.CLI.PendingMigration" spec

fixedTime :: UTCTime
fixedTime =
  parseTimeOrError
    True
    defaultTimeLocale
    "%Y-%m-%dT%H:%M:%SZ"
    "2026-04-01T10:00:00Z"

mkApplied :: Maybe Text -> AppliedModule
mkApplied mver =
  AppliedModule
    { name = ModuleName "demo",
      parentVars = emptyParentVars,
      source = "/installed/demo",
      moduleVersion = mver,
      appliedAt = fixedTime,
      removal = Nothing
    }

mkInstalled :: Maybe Text -> [Migration] -> Module
mkInstalled v migs =
  Module
    { name = ModuleName "demo",
      version = v,
      description = Nothing,
      vars = [],
      exports = [],
      prompts = [],
      steps = [],
      commands = [],
      dependencies = [],
      removal = Nothing,
      migrations = migs
    }

spec :: Spec
spec = do
  describe "pendingChainFor" $ do
    it "returns Nothing when manifest has no recorded version" $ do
      let am = mkApplied Nothing
          installed = mkInstalled (Just "2.0.0") [Migration "1.0.0" "2.0.0" []]
      pendingChainFor am installed `shouldBe` Nothing

    it "returns Nothing when installed has no version" $ do
      let am = mkApplied (Just "1.0.0")
          installed = mkInstalled Nothing []
      pendingChainFor am installed `shouldBe` Nothing

    it "returns Nothing when versions match (no chain)" $ do
      let am = mkApplied (Just "1.0.0")
          installed = mkInstalled (Just "1.0.0") []
      pendingChainFor am installed `shouldBe` Nothing

    it "returns Just chain when manifest is behind installed" $ do
      let mig = Migration "1.0.0" "2.0.0" [DeleteFile "Setup.hs"]
          am = mkApplied (Just "1.0.0")
          installed = mkInstalled (Just "2.0.0") [mig]
      case pendingChainFor am installed of
        Just chain -> chain.chainSteps `shouldBe` [mig]
        Nothing -> expectationFailure "expected Just chain"

    it "returns Nothing when no migration covers the gap" $ do
      let am = mkApplied (Just "1.0.0")
          installed = mkInstalled (Just "2.0.0") []
      pendingChainFor am installed `shouldBe` Nothing

    it "returns Nothing for downgrade (manifest > installed)" $ do
      let am = mkApplied (Just "2.0.0")
          installed = mkInstalled (Just "1.0.0") []
      pendingChainFor am installed `shouldBe` Nothing
