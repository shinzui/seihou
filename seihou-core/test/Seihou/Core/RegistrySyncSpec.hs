module Seihou.Core.RegistrySyncSpec (tests) where

import Data.Maybe (isJust, mapMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Seihou.Core.Registry
  ( EntryKind (..),
    Registry (..),
    RegistryEntry (..),
    SyncDiff (..),
    SyncReport (..),
    SyncStatus (..),
    computeRegistrySync,
    formatDriftWarning,
  )
import Seihou.Core.Types (ModuleName (..))
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Core.RegistrySync" spec

spec :: Spec
spec = describe "computeRegistrySync" $ do
  it "classifies SyncMissing when registry version is Nothing and disk has a version" $ do
    let entry = mkEntry "alpha" Nothing
        reg = mkReg [entry] []
        report = computeRegistrySync reg [(ModuleEntry, ModuleName "alpha", Just "1.0.0")]
    map (.diffStatus) report.syncDiffs `shouldBe` [SyncMissing]
    map (.diffNew) report.syncDiffs `shouldBe` [Just "1.0.0"]
    (head report.syncUpdated.modules).version `shouldBe` Just "1.0.0"

  it "classifies SyncStale when registry and disk versions differ" $ do
    let entry = mkEntry "alpha" (Just "0.1.0")
        reg = mkReg [entry] []
        report = computeRegistrySync reg [(ModuleEntry, ModuleName "alpha", Just "1.0.0")]
    map (.diffStatus) report.syncDiffs `shouldBe` [SyncStale "1.0.0"]
    map (.diffOld) report.syncDiffs `shouldBe` [Just "0.1.0"]
    map (.diffNew) report.syncDiffs `shouldBe` [Just "1.0.0"]
    (head report.syncUpdated.modules).version `shouldBe` Just "1.0.0"

  it "classifies SyncInSync when registry and disk versions match" $ do
    let entry = mkEntry "alpha" (Just "1.0.0")
        reg = mkReg [entry] []
        report = computeRegistrySync reg [(ModuleEntry, ModuleName "alpha", Just "1.0.0")]
    map (.diffStatus) report.syncDiffs `shouldBe` [SyncInSync]
    (head report.syncUpdated.modules).version `shouldBe` Just "1.0.0"

  it "classifies SyncInSync when registry and disk are both Nothing" $ do
    let entry = mkEntry "alpha" Nothing
        reg = mkReg [entry] []
        report = computeRegistrySync reg [(ModuleEntry, ModuleName "alpha", Nothing)]
    map (.diffStatus) report.syncDiffs `shouldBe` [SyncInSync]
    (head report.syncUpdated.modules).version `shouldBe` Nothing

  it "classifies SyncOrphan when the entry has no lookup (module.dhall absent/unreadable)" $ do
    let entry = mkEntry "alpha" (Just "1.0.0")
        reg = mkReg [entry] []
        report = computeRegistrySync reg []
    map (.diffStatus) report.syncDiffs `shouldBe` [SyncOrphan]
    -- Orphan: version left as-is
    (head report.syncUpdated.modules).version `shouldBe` Just "1.0.0"

  it "preserves registry order in the diff output" $ do
    let reg =
          ( mkReg
              [ mkEntry "alpha" Nothing,
                mkEntry "beta" (Just "0.1.0"),
                mkEntry "gamma" (Just "2.0.0")
              ]
              [mkEntry "lib-one" Nothing]
          )
            { prompts = [mkEntry "review" Nothing]
            }
        lookups =
          [ (ModuleEntry, ModuleName "alpha", Just "1.0.0"),
            (ModuleEntry, ModuleName "beta", Just "0.2.0"),
            (ModuleEntry, ModuleName "gamma", Just "2.0.0"),
            (RecipeEntry, ModuleName "lib-one", Just "0.3.0"),
            (PromptEntry, ModuleName "review", Just "0.4.0")
          ]
        report = computeRegistrySync reg lookups
    map (.diffName) report.syncDiffs
      `shouldBe` [ ModuleName "alpha",
                   ModuleName "beta",
                   ModuleName "gamma",
                   ModuleName "lib-one",
                   ModuleName "review"
                 ]
    map (.diffKind) report.syncDiffs
      `shouldBe` [ModuleEntry, ModuleEntry, ModuleEntry, RecipeEntry, PromptEntry]
    map (.diffStatus) report.syncDiffs
      `shouldBe` [SyncMissing, SyncStale "0.2.0", SyncInSync, SyncMissing, SyncMissing]

  it "returns an empty report for an empty registry" $ do
    let reg = mkReg [] []
        report = computeRegistrySync reg []
    report.syncDiffs `shouldBe` []
    report.syncUpdated `shouldBe` reg

  it "distinguishes module and recipe entries with the same name in lookups" $ do
    -- Module and recipe namespaces share a validation check,
    -- but the sync lookup must distinguish them by kind.
    let reg =
          mkReg
            [mkEntry "alpha" Nothing]
            [mkEntry "beta" Nothing]
        lookups =
          [ (ModuleEntry, ModuleName "alpha", Just "1.0.0"),
            (RecipeEntry, ModuleName "beta", Just "2.0.0")
          ]
        report = computeRegistrySync reg lookups
    map (.diffNew) report.syncDiffs `shouldBe` [Just "1.0.0", Just "2.0.0"]

  describe "formatDriftWarning" $ do
    it "produces a warning for a stale entry" $ do
      let reg = mkReg [mkEntry "alpha" (Just "0.1.0")] []
          lookups = [(ModuleEntry, ModuleName "alpha", Just "1.0.0")]
          report = computeRegistrySync reg lookups
          warnings = mapMaybe formatDriftWarning report.syncDiffs
      length warnings `shouldBe` 1
      isJust (formatDriftWarning (head report.syncDiffs)) `shouldBe` True

    it "produces no warnings when all entries are in sync" $ do
      let reg = mkReg [mkEntry "alpha" (Just "1.0.0")] []
          lookups = [(ModuleEntry, ModuleName "alpha", Just "1.0.0")]
          report = computeRegistrySync reg lookups
          warnings = mapMaybe formatDriftWarning report.syncDiffs
      warnings `shouldBe` []

    it "produces no warnings for orphan entries (handled by validateRegistry)" $ do
      let reg = mkReg [mkEntry "alpha" (Just "1.0.0")] []
          report = computeRegistrySync reg []
          warnings = mapMaybe formatDriftWarning report.syncDiffs
      warnings `shouldBe` []

    it "mentions prompt.dhall in stale prompt warnings" $ do
      let reg = (mkReg [] []) {prompts = [mkEntry "review" (Just "0.1.0")]}
          lookups = [(PromptEntry, ModuleName "review", Just "0.2.0")]
          report = computeRegistrySync reg lookups
          warnings = mapMaybe formatDriftWarning report.syncDiffs
      warnings
        `shouldBe` [ "prompt 'review' registry version 0.1.0 differs from prompt.dhall version 0.2.0 — run `seihou registry sync-versions`"
                   ]

mkEntry :: Text -> Maybe Text -> RegistryEntry
mkEntry n v =
  RegistryEntry
    { name = ModuleName n,
      version = v,
      path = "modules/" <> T.unpack n,
      description = Nothing,
      tags = []
    }

mkReg :: [RegistryEntry] -> [RegistryEntry] -> Registry
mkReg mods recs =
  Registry
    { repoName = "Test",
      repoDescription = Nothing,
      modules = mods,
      recipes = recs,
      blueprints = [],
      prompts = []
    }
