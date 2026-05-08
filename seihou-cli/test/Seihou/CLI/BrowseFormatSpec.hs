module Seihou.CLI.BrowseFormatSpec (tests) where

import Data.Text (Text, pack)
import Seihou.CLI.BrowseFormat (formatBrowseRegistry, formatBrowseSingleModule)
import Seihou.Core.Registry (Registry (..), RegistryEntry (..))
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
      blueprints = []
    }

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

  describe "formatBrowseRegistry" $ do
    it "formats multi-module registry" $ do
      let entries =
            [ mkEntry "haskell-base" "modules/haskell-base" (Just "Base Haskell project") ["haskell"],
              mkEntry "nix-flake" "modules/nix-flake" (Just "Nix flake setup") ["nix", "devops"]
            ]
          registry = mkRegistry "my-templates" (Just "A collection of project templates") entries
          result = formatBrowseRegistry "https://github.com/user/templates" registry entries Nothing
      result
        `shouldBe` "my-templates\n\
                   \A collection of project templates\n\
                   \\n\
                   \Available modules:\n\
                   \\n\
                   \  haskell-base   Base Haskell project  [haskell]\n\
                   \  nix-flake      Nix flake setup  [nix, devops]\n\
                   \\n\
                   \2 modules available. Install with:\n\
                   \  seihou install https://github.com/user/templates --module <name>\n\
                   \  seihou install https://github.com/user/templates --all\n"

    it "formats registry with no description" $ do
      let entries = [mkEntry "only-mod" "modules/only-mod" (Just "The only module") []]
          registry = mkRegistry "simple-repo" Nothing entries
          result = formatBrowseRegistry "https://github.com/user/repo" registry entries Nothing
      result
        `shouldBe` "simple-repo\n\
                   \\n\
                   \Available modules:\n\
                   \\n\
                   \  only-mod   The only module\n\
                   \\n\
                   \1 module available. Install with:\n\
                   \  seihou install https://github.com/user/repo --module <name>\n\
                   \  seihou install https://github.com/user/repo --all\n"

    it "formats empty registry" $ do
      let registry = mkRegistry "empty-repo" (Just "Nothing here") []
          result = formatBrowseRegistry "source" registry [] Nothing
      result
        `shouldBe` "empty-repo\n\
                   \Nothing here\n\
                   \\n\
                   \No modules in registry.\n"

    it "formats tag filter with no matches" $ do
      let registry = mkRegistry "my-templates" Nothing []
          result = formatBrowseRegistry "source" registry [] (Just "rust")
      result
        `shouldBe` "my-templates\n\
                   \\n\
                   \No modules matching tag 'rust'.\n"

    it "formats filtered results by tag" $ do
      let allEntries =
            [ mkEntry "haskell-base" "modules/haskell-base" (Just "Haskell setup") ["haskell"],
              mkEntry "nix-flake" "modules/nix-flake" (Just "Nix flake") ["nix"]
            ]
          filtered = [head allEntries] -- only the haskell one
          registry = mkRegistry "templates" Nothing allEntries
          result = formatBrowseRegistry "source" registry filtered (Just "haskell")
      result
        `shouldBe` "templates\n\
                   \\n\
                   \Available modules:\n\
                   \\n\
                   \  haskell-base   Haskell setup  [haskell]\n\
                   \\n\
                   \1 module available. Install with:\n\
                   \  seihou install source --module <name>\n\
                   \  seihou install source --all\n"

    it "aligns columns when names have different lengths" $ do
      let entries =
            [ mkEntry "a" "modules/a" (Just "Short name") [],
              mkEntry "very-long-module-name" "modules/vlmn" (Just "Long name") []
            ]
          registry = mkRegistry "repo" Nothing entries
          result = formatBrowseRegistry "source" registry entries Nothing
      -- The short name should be padded to match the longest
      result
        `shouldBe` "repo\n\
                   \\n\
                   \Available modules:\n\
                   \\n\
                   \  a                       Short name\n\
                   \  very-long-module-name   Long name\n\
                   \\n\
                   \2 modules available. Install with:\n\
                   \  seihou install source --module <name>\n\
                   \  seihou install source --all\n"
