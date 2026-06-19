module Seihou.CLI.BrowseFormatSpec (tests) where

import Data.Text (Text, pack)
import Seihou.CLI.BrowseFormat (formatBrowseRegistry, formatBrowseSingleBlueprint, formatBrowseSingleModule, formatBrowseSinglePrompt)
import Seihou.Core.Registry (EntryKind (..), Registry (..), RegistryEntry (..))
import Seihou.Core.Types (ModuleName (..))
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.CLI.BrowseFormat" spec

mkEntry :: String -> String -> Maybe String -> [String] -> RegistryEntry
mkEntry n p desc ts =
  RegistryEntry
    { name = ModuleName (pack n),
      version = Nothing,
      path = p,
      description = fmap pack desc,
      tags = map pack ts
    }

mkRegistry :: String -> Maybe String -> [RegistryEntry] -> Registry
mkRegistry n desc ms =
  Registry
    { repoName = pack n,
      repoDescription = fmap pack desc,
      modules = ms,
      recipes = [],
      blueprints = [],
      prompts = []
    }

asModules :: [RegistryEntry] -> [(EntryKind, RegistryEntry)]
asModules = map ((,) ModuleEntry)

spec :: Spec
spec = do
  describe "formatBrowseSingleModule" $ do
    it "formats single module with description" $ do
      let result = formatBrowseSingleModule "https://github.com/user/repo" "haskell-base" (Just "Base Haskell setup")
      result
        `shouldBe` "haskell-base\n\
                   \  Base Haskell setup\n\
                   \\n\
                   \Single-module repository. Install with:\n\
                   \  seihou install https://github.com/user/repo\n"

    it "formats single module without description" $ do
      let result = formatBrowseSingleModule "https://github.com/user/repo" "minimal" Nothing
      result
        `shouldBe` "minimal\n\
                   \\n\
                   \Single-module repository. Install with:\n\
                   \  seihou install https://github.com/user/repo\n"

  describe "formatBrowseSingleBlueprint" $ do
    it "formats single blueprint with description" $ do
      let result = formatBrowseSingleBlueprint "https://github.com/user/bp" "payments-service" (Just "Agent-driven payments scaffold")
      result
        `shouldBe` "payments-service\n\
                   \  Agent-driven payments scaffold\n\
                   \\n\
                   \Single-blueprint repository. Install with:\n\
                   \  seihou install https://github.com/user/bp\n"

    it "formats single blueprint without description" $ do
      let result = formatBrowseSingleBlueprint "https://github.com/user/bp" "minimal-bp" Nothing
      result
        `shouldBe` "minimal-bp\n\
                   \\n\
                   \Single-blueprint repository. Install with:\n\
                   \  seihou install https://github.com/user/bp\n"

  describe "formatBrowseSinglePrompt" $ do
    it "formats single prompt with description" $ do
      let result = formatBrowseSinglePrompt "https://github.com/user/prompt" "review-changes" (Just "Review the current diff")
      result
        `shouldBe` "review-changes\n\
                   \  Review the current diff\n\
                   \\n\
                   \Single-prompt repository. Install with:\n\
                   \  seihou install https://github.com/user/prompt\n"

    it "formats single prompt without description" $ do
      let result = formatBrowseSinglePrompt "https://github.com/user/prompt" "quick-note" Nothing
      result
        `shouldBe` "quick-note\n\
                   \\n\
                   \Single-prompt repository. Install with:\n\
                   \  seihou install https://github.com/user/prompt\n"

  describe "formatBrowseRegistry" $ do
    it "formats multi-module registry with kind labels" $ do
      let entries =
            [ mkEntry "haskell-base" "modules/haskell-base" (Just "Base Haskell project") ["haskell"],
              mkEntry "nix-flake" "modules/nix-flake" (Just "Nix flake setup") ["nix", "devops"]
            ]
          registry = mkRegistry "my-templates" (Just "A collection of project templates") entries
          result = formatBrowseRegistry "https://github.com/user/templates" registry (asModules entries) Nothing
      result
        `shouldBe` "my-templates\n\
                   \A collection of project templates\n\
                   \\n\
                   \Available entries:\n\
                   \\n\
                   \  [module]     haskell-base   Base Haskell project  [haskell]\n\
                   \  [module]     nix-flake      Nix flake setup  [nix, devops]\n\
                   \\n\
                   \2 entries available. Install with:\n\
                   \  seihou install https://github.com/user/templates --module <name>\n\
                   \  seihou install https://github.com/user/templates --all\n"

    it "formats registry with no description" $ do
      let entries = [mkEntry "only-mod" "modules/only-mod" (Just "The only module") []]
          registry = mkRegistry "simple-repo" Nothing entries
          result = formatBrowseRegistry "https://github.com/user/repo" registry (asModules entries) Nothing
      result
        `shouldBe` "simple-repo\n\
                   \\n\
                   \Available entries:\n\
                   \\n\
                   \  [module]     only-mod   The only module\n\
                   \\n\
                   \1 entry available. Install with:\n\
                   \  seihou install https://github.com/user/repo --module <name>\n\
                   \  seihou install https://github.com/user/repo --all\n"

    it "formats empty registry" $ do
      let registry = mkRegistry "empty-repo" (Just "Nothing here") []
          result = formatBrowseRegistry "source" registry [] Nothing
      result
        `shouldBe` "empty-repo\n\
                   \Nothing here\n\
                   \\n\
                   \No entries in registry.\n"

    it "formats tag filter with no matches" $ do
      let registry = mkRegistry "my-templates" Nothing []
          result = formatBrowseRegistry "source" registry [] (Just "rust")
      result
        `shouldBe` "my-templates\n\
                   \\n\
                   \No entries matching tag 'rust'.\n"

    it "formats filtered results by tag" $ do
      let allMods =
            [ mkEntry "haskell-base" "modules/haskell-base" (Just "Haskell setup") ["haskell"],
              mkEntry "nix-flake" "modules/nix-flake" (Just "Nix flake") ["nix"]
            ]
          filtered = [head allMods] -- only the haskell one
          registry = mkRegistry "templates" Nothing allMods
          result = formatBrowseRegistry "source" registry (asModules filtered) (Just "haskell")
      result
        `shouldBe` "templates\n\
                   \\n\
                   \Available entries:\n\
                   \\n\
                   \  [module]     haskell-base   Haskell setup  [haskell]\n\
                   \\n\
                   \1 entry available. Install with:\n\
                   \  seihou install source --module <name>\n\
                   \  seihou install source --all\n"

    it "aligns columns when names have different lengths" $ do
      let entries =
            [ mkEntry "a" "modules/a" (Just "Short name") [],
              mkEntry "very-long-module-name" "modules/vlmn" (Just "Long name") []
            ]
          registry = mkRegistry "repo" Nothing entries
          result = formatBrowseRegistry "source" registry (asModules entries) Nothing
      -- The short name should be padded to match the longest
      result
        `shouldBe` "repo\n\
                   \\n\
                   \Available entries:\n\
                   \\n\
                   \  [module]     a                       Short name\n\
                   \  [module]     very-long-module-name   Long name\n\
                   \\n\
                   \2 entries available. Install with:\n\
                   \  seihou install source --module <name>\n\
                   \  seihou install source --all\n"

    it "formats a mixed-kind registry with module, recipe, blueprint, and prompt labels" $ do
      let modEntry = mkEntry "haskell-base" "modules/haskell-base" (Just "Module entry") ["haskell"]
          recEntry = mkEntry "lib-recipe" "recipes/lib-recipe" (Just "Recipe entry") []
          bpEntry = mkEntry "payments-service" "blueprints/payments-service" (Just "Blueprint entry") []
          promptEntry = mkEntry "review-changes" "prompts/review-changes" (Just "Prompt entry") ["review"]
          mixed =
            [ (ModuleEntry, modEntry),
              (RecipeEntry, recEntry),
              (BlueprintEntry, bpEntry),
              (PromptEntry, promptEntry)
            ]
          registry = mkRegistry "mixed-repo" Nothing [modEntry]
          result = formatBrowseRegistry "source" registry mixed Nothing
      result
        `shouldBe` "mixed-repo\n\
                   \\n\
                   \Available entries:\n\
                   \\n\
                   \  [module]     haskell-base       Module entry  [haskell]\n\
                   \  [recipe]     lib-recipe         Recipe entry\n\
                   \  [blueprint]  payments-service   Blueprint entry\n\
                   \  [prompt]     review-changes     Prompt entry  [review]\n\
                   \\n\
                   \4 entries available. Install with:\n\
                   \  seihou install source --module <name>\n\
                   \  seihou install source --all\n"
