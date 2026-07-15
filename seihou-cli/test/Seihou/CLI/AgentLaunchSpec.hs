module Seihou.CLI.AgentLaunchSpec (tests) where

import Data.Text qualified as T
import Seihou.CLI.AgentLaunch
  ( AgentContext (..),
    BaselineStatus (..),
    formatAvailableModules,
    formatBaselineStatus,
    formatBlueprintIdentity,
    formatLocalModules,
    formatManifestState,
    formatModuleDhallState,
    formatReferenceFiles,
    formatReferenceFilesDir,
    formatSeihouProjectState,
    substitute,
  )
import Seihou.Core.Types
  ( Blueprint (..),
    BlueprintFile (..),
    ModuleName (..),
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

  describe "formatBaselineStatus" $ do
    it "names --no-baseline as the reason when skipped" $
      formatBaselineStatus BaselineSkipped
        `shouldBe` "(no baseline applied — `--no-baseline` was passed)"
    it "calls out an empty baseModules list" $
      formatBaselineStatus BaselineEmpty
        `shouldBe` "(this blueprint declares no base modules)"
    it "renders an applied versioned module as a bullet" $
      formatBaselineStatus (BaselineApplied [(ModuleName "foo", Just "1.0.0")])
        `shouldBe` "  - foo (v1.0.0)"
    it "renders an applied unversioned module as a bullet" $
      formatBaselineStatus (BaselineApplied [(ModuleName "foo", Nothing)])
        `shouldBe` "  - foo (unversioned)"

  describe "formatReferenceFiles" $ do
    it "states '(no reference files)' when empty" $
      formatReferenceFiles [] `shouldBe` "(no reference files)"
    it "renders an entry with a description as 'path — description'" $
      formatReferenceFiles [BlueprintFile {src = "x.txt", description = Just "an example"}]
        `shouldBe` "  - x.txt — an example"
    it "renders an entry without a description as just the path" $
      formatReferenceFiles [BlueprintFile {src = "y.txt", description = Nothing}]
        `shouldBe` "  - y.txt"

  describe "formatReferenceFilesDir" $ do
    it "renders the mounted path with read-directly guidance" $ do
      let rendered = formatReferenceFilesDir (Just "/tmp/bp/files")
      rendered `shouldSatisfy` T.isInfixOf "/tmp/bp/files"
      rendered `shouldSatisfy` T.isInfixOf "open them directly"
    it "renders the ask-the-user fallback when no directory is mounted" $ do
      let rendered = formatReferenceFilesDir Nothing
      rendered `shouldSatisfy` T.isInfixOf "ask the user"
      rendered `shouldSatisfy` (not . T.isInfixOf "readable at")

  describe "formatBlueprintIdentity" $ do
    let mk v d =
          Blueprint
            { name = ModuleName "bp",
              version = v,
              description = d,
              prompt = "",
              vars = [],
              prompts = [],
              baseModules = [],
              files = [],
              allowedTools = Nothing,
              tags = []
            }
    it "renders name, version, description as a three-line block" $
      formatBlueprintIdentity (mk (Just "0.1") (Just "a thing"))
        `shouldBe` "Name: bp\nVersion: 0.1\nDescription: a thing"
    it "names '(unspecified)' when version is missing" $
      formatBlueprintIdentity (mk Nothing (Just "a thing"))
        `shouldBe` "Name: bp\nVersion: (unspecified)\nDescription: a thing"
    it "names '(no description)' when description is missing" $
      formatBlueprintIdentity (mk (Just "0.1") Nothing)
        `shouldBe` "Name: bp\nVersion: 0.1\nDescription: (no description)"
