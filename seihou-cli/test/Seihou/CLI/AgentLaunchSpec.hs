module Seihou.CLI.AgentLaunchSpec (tests) where

import Seihou.CLI.AgentLaunch
  ( AgentContext (..),
    formatAvailableModules,
    formatLocalModules,
    formatManifestState,
    formatModuleDhallState,
    formatSeihouProjectState,
    substitute,
  )
import Test.Hspec
import Test.Tasty (TestTree)
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.CLI.AgentLaunch" $ do
  describe "substitute" $ do
    it "replaces a single key" $
      substitute [("name", "Alice")] "Hello {{name}}"
        `shouldBe` "Hello Alice"
    it "replaces multiple keys" $
      substitute [("a", "1"), ("b", "2")] "{{a}}-{{b}}"
        `shouldBe` "1-2"
    it "leaves unknown keys untouched" $
      substitute [("a", "1")] "{{a}} and {{c}}"
        `shouldBe` "1 and {{c}}"
    it "is a no-op on a template with no placeholders" $
      substitute [("a", "1")] "no placeholders here"
        `shouldBe` "no placeholders here"

  describe "AgentContext formatters" $ do
    let baseCtx =
          AgentContext
            { cwd = "/tmp/test",
              seihouInitialized = False,
              hasManifest = False,
              localModuleDhall = False,
              localModules = [],
              availableModules = []
            }

    describe "formatSeihouProjectState" $ do
      it "names .seihou/ when initialised" $
        formatSeihouProjectState (baseCtx {seihouInitialized = True})
          `shouldBe` "Seihou project: .seihou/ directory exists (this is a seihou-managed project)"
      it "states 'No .seihou/' when not initialised" $
        formatSeihouProjectState baseCtx
          `shouldBe` "Seihou project: No .seihou/ directory (not yet a seihou project in this directory)"

    describe "formatManifestState" $ do
      it "names manifest.json when present" $
        formatManifestState (baseCtx {hasManifest = True})
          `shouldBe` "Manifest: .seihou/manifest.json exists (modules have been applied here)"
      it "reports no manifest otherwise" $
        formatManifestState baseCtx
          `shouldBe` "Manifest: No manifest (no modules applied yet)"

    describe "formatModuleDhallState" $ do
      it "names module.dhall when present in cwd" $
        formatModuleDhallState (baseCtx {localModuleDhall = True})
          `shouldBe` "Module in cwd: module.dhall found in current directory (user is authoring a module here)"
      it "is empty when module.dhall is absent" $
        formatModuleDhallState baseCtx `shouldBe` ""

    describe "formatLocalModules" $ do
      it "is empty when there are no local modules" $
        formatLocalModules baseCtx `shouldBe` ""
      it "lists local modules with bullet prefixes" $
        formatLocalModules (baseCtx {localModules = ["foo", "bar"]})
          `shouldBe` "Local modules:\n  - foo\n  - bar"

    describe "formatAvailableModules" $ do
      it "states 'None discovered' when empty" $
        formatAvailableModules baseCtx
          `shouldBe` "Available modules: None discovered"
      it "renders entries as 'name — description (source)' lines" $
        formatAvailableModules
          (baseCtx {availableModules = [("foo", "the foo module", "user")]})
          `shouldBe` "Available modules across search paths:\n  - foo — the foo module (user)"
