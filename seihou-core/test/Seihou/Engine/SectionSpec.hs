module Seihou.Engine.SectionSpec (tests) where

import Data.Text qualified as T
import Seihou.Core.Types
import Seihou.Engine.Section
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Engine.Section" spec

modName :: ModuleName
modName = ModuleName "nix-flake"

marker :: SectionMarker
marker = SectionMarker {sectionPrefix = "#", sectionModule = modName}

spec :: Spec
spec = do
  describe "renderSectionOpen" $ do
    it "produces correct format with # prefix" $ do
      renderSectionOpen marker `shouldBe` "# --- seihou:nix-flake ---\n"

    it "produces correct format with -- prefix" $ do
      let hsMarker = marker {sectionPrefix = "--"}
      renderSectionOpen hsMarker `shouldBe` "-- --- seihou:nix-flake ---\n"

  describe "renderSectionClose" $ do
    it "produces correct format with # prefix" $ do
      renderSectionClose marker `shouldBe` "# --- /seihou:nix-flake ---\n"

    it "produces correct format with -- prefix" $ do
      let hsMarker = marker {sectionPrefix = "--"}
      renderSectionClose hsMarker `shouldBe` "-- --- /seihou:nix-flake ---\n"

  describe "wrapInSection" $ do
    it "wraps content with open and close markers" $ do
      wrapInSection marker "extra config\n"
        `shouldBe` "# --- seihou:nix-flake ---\nextra config\n# --- /seihou:nix-flake ---\n"

    it "adds trailing newline to content if missing" $ do
      wrapInSection marker "no trailing newline"
        `shouldBe` "# --- seihou:nix-flake ---\nno trailing newline\n# --- /seihou:nix-flake ---\n"

    it "handles empty content" $ do
      wrapInSection marker ""
        `shouldBe` "# --- seihou:nix-flake ---\n# --- /seihou:nix-flake ---\n"

  describe "applyTextPatch" $ do
    it "AppendFile appends content after existing" $ do
      let result = applyTextPatch AppendFile modName "#" "line1\n" "line2\n"
      result `shouldBe` Right "line1\nline2\n"

    it "AppendFile ensures newline between existing and new" $ do
      let result = applyTextPatch AppendFile modName "#" "line1" "line2\n"
      result `shouldBe` Right "line1\nline2\n"

    it "PrependFile prepends content before existing" $ do
      let result = applyTextPatch PrependFile modName "#" "line2\n" "line1\n"
      result `shouldBe` Right "line1\nline2\n"

    it "PrependFile ensures newline between new and existing" $ do
      let result = applyTextPatch PrependFile modName "#" "line2\n" "line1"
      result `shouldBe` Right "line1\nline2\n"

    it "AppendSection appends wrapped section" $ do
      let result = applyTextPatch AppendSection modName "#" "base content\n" "extra\n"
      result
        `shouldBe` Right
          "base content\n# --- seihou:nix-flake ---\nextra\n# --- /seihou:nix-flake ---\n"

    it "AppendSection uses configured comment prefix" $ do
      let result = applyTextPatch AppendSection modName "--" "base\n" "extra\n"
      result
        `shouldBe` Right
          "base\n-- --- seihou:nix-flake ---\nextra\n-- --- /seihou:nix-flake ---\n"

    it "AppendSection works with empty existing content" $ do
      let result = applyTextPatch AppendSection modName "#" "" "new section\n"
      result
        `shouldBe` Right
          "# --- seihou:nix-flake ---\nnew section\n# --- /seihou:nix-flake ---\n"

    it "AppendFile with empty existing content" $ do
      let result = applyTextPatch AppendFile modName "#" "" "new content\n"
      result `shouldBe` Right "new content\n"

    it "PrependFile with empty existing content" $ do
      let result = applyTextPatch PrependFile modName "#" "" "new content\n"
      result `shouldBe` Right "new content\n"

  describe "removeSection" $ do
    it "removes a section between markers" $ do
      let content = "before\n# --- seihou:nix-flake ---\nmodule content\n# --- /seihou:nix-flake ---\nafter\n"
          result = removeSection modName "#" content
      result `shouldBe` "before\nafter\n"

    it "leaves content outside markers intact" $ do
      let content = "line1\nline2\n# --- seihou:nix-flake ---\nstuff\n# --- /seihou:nix-flake ---\nline3\nline4\n"
          result = removeSection modName "#" content
      result `shouldBe` "line1\nline2\nline3\nline4\n"

    it "returns content unchanged when no markers found" $ do
      let content = "no markers here\njust text\n"
          result = removeSection modName "#" content
      result `shouldBe` content

    it "only removes the target module's section" $ do
      let otherMod' = ModuleName "other-module"
          content =
            "start\n"
              <> "# --- seihou:nix-flake ---\nflake stuff\n# --- /seihou:nix-flake ---\n"
              <> "# --- seihou:other-module ---\nother stuff\n# --- /seihou:other-module ---\n"
              <> "end\n"
      -- Remove nix-flake: should keep other-module
      let result = removeSection modName "#" content
      T.isInfixOf "seihou:nix-flake" result `shouldBe` False
      T.isInfixOf "seihou:other-module" result `shouldBe` True
      -- Remove other-module: should keep nix-flake
      let result2 = removeSection otherMod' "#" content
      T.isInfixOf "seihou:nix-flake" result2 `shouldBe` True
      T.isInfixOf "seihou:other-module" result2 `shouldBe` False

    it "cleans up double blank lines after removal" $ do
      let content = "before\n\n# --- seihou:nix-flake ---\nstuff\n# --- /seihou:nix-flake ---\n\nafter\n"
          result = removeSection modName "#" content
      -- Should not have triple+ blank lines
      T.isInfixOf "\n\n\n" result `shouldBe` False

    it "handles section at beginning of file" $ do
      let content = "# --- seihou:nix-flake ---\nstuff\n# --- /seihou:nix-flake ---\nafter\n"
          result = removeSection modName "#" content
      result `shouldBe` "after\n"

    it "handles section at end of file" $ do
      let content = "before\n# --- seihou:nix-flake ---\nstuff\n# --- /seihou:nix-flake ---\n"
          result = removeSection modName "#" content
      result `shouldBe` "before\n"

    it "works with -- comment prefix" $ do
      let content = "before\n-- --- seihou:nix-flake ---\nstuff\n-- --- /seihou:nix-flake ---\nafter\n"
          result = removeSection modName "--" content
      result `shouldBe` "before\nafter\n"
