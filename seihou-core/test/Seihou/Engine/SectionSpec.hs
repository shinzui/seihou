module Seihou.Engine.SectionSpec (tests) where

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
