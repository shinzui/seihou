module Seihou.Core.RegistryEmitSpec (tests) where

import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.Core.Registry (Registry (..), RegistryEntry (..), renderRegistryDhall)
import Seihou.Core.Types (ModuleName (..))
import Seihou.Dhall.Eval (evalRegistryFromFile)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Core.RegistryEmit" spec

spec :: Spec
spec = describe "renderRegistryDhall" $ do
  it "round-trips a registry with two modules and one recipe" $ do
    let reg =
          Registry
            { repoName = "Sample",
              repoDescription = Just "A sample registry",
              modules =
                [ RegistryEntry
                    { name = ModuleName "alpha",
                      version = Just "1.0.0",
                      path = "modules/alpha",
                      description = Just "Alpha module",
                      tags = ["starter", "haskell"]
                    },
                  RegistryEntry
                    { name = ModuleName "beta",
                      version = Nothing,
                      path = "modules/beta",
                      description = Nothing,
                      tags = []
                    }
                ],
              recipes =
                [ RegistryEntry
                    { name = ModuleName "library-recipe",
                      version = Just "0.1.0",
                      path = "recipes/library-recipe",
                      description = Just "Library recipe",
                      tags = ["lib"]
                    }
                ],
              blueprints = [],
              prompts = []
            }
    roundTrip reg

  it "round-trips a registry with no recipes" $ do
    let reg =
          Registry
            { repoName = "Modules Only",
              repoDescription = Nothing,
              modules =
                [ RegistryEntry
                    { name = ModuleName "solo",
                      version = Just "2.1.3",
                      path = "solo",
                      description = Nothing,
                      tags = []
                    }
                ],
              recipes = [],
              blueprints = [],
              prompts = []
            }
    roundTrip reg

  it "round-trips an entry with version = Nothing" $ do
    let reg =
          Registry
            { repoName = "Unversioned",
              repoDescription = Nothing,
              modules =
                [ RegistryEntry
                    { name = ModuleName "nover",
                      version = Nothing,
                      path = "nover",
                      description = Nothing,
                      tags = []
                    }
                ],
              recipes = [],
              blueprints = [],
              prompts = []
            }
    roundTrip reg

  it "escapes quotes and backslashes in description" $ do
    let reg =
          Registry
            { repoName = "Escape \"test\"",
              repoDescription = Just "has \"quotes\" and \\ backslashes",
              modules =
                [ RegistryEntry
                    { name = ModuleName "escaped",
                      version = Just "0.1.0",
                      path = "escaped",
                      description = Just "weird: \"quoted\" \\ and $var",
                      tags = ["has \"quote\""]
                    }
                ],
              recipes = [],
              blueprints = [],
              prompts = []
            }
    roundTrip reg

  it "round-trips an empty registry" $ do
    let reg =
          Registry
            { repoName = "Empty",
              repoDescription = Nothing,
              modules = [],
              recipes = [],
              blueprints = [],
              prompts = []
            }
    roundTrip reg

  it "round-trips a registry with all four entry kinds" $ do
    let reg =
          Registry
            { repoName = "All Four",
              repoDescription = Just "Modules, recipes, blueprints, and prompts",
              modules =
                [ RegistryEntry
                    { name = ModuleName "mod-one",
                      version = Just "1.0.0",
                      path = "modules/mod-one",
                      description = Just "Module entry",
                      tags = ["m"]
                    }
                ],
              recipes =
                [ RegistryEntry
                    { name = ModuleName "rec-one",
                      version = Just "0.2.0",
                      path = "recipes/rec-one",
                      description = Just "Recipe entry",
                      tags = ["r"]
                    }
                ],
              blueprints =
                [ RegistryEntry
                    { name = ModuleName "bp-one",
                      version = Just "0.3.0",
                      path = "blueprints/bp-one",
                      description = Just "Blueprint entry",
                      tags = ["agent", "service"]
                    },
                  RegistryEntry
                    { name = ModuleName "bp-two",
                      version = Nothing,
                      path = "blueprints/bp-two",
                      description = Nothing,
                      tags = []
                    }
                ],
              prompts =
                [ RegistryEntry
                    { name = ModuleName "prompt-one",
                      version = Just "0.4.0",
                      path = "prompts/prompt-one",
                      description = Just "Prompt entry",
                      tags = ["agent"]
                    }
                ]
            }
    roundTrip reg

roundTrip :: Registry -> Expectation
roundTrip reg =
  withSystemTempDirectory "seihou-registry-emit" $ \tmpDir -> do
    let path = tmpDir </> "seihou-registry.dhall"
    TIO.writeFile path (renderRegistryDhall reg)
    result <- evalRegistryFromFile path
    case result of
      Left err ->
        expectationFailure
          ( "expected round-trip success, got Left: "
              <> show err
              <> "\nrendered:\n"
              <> T.unpack (renderRegistryDhall reg)
          )
      Right decoded -> decoded `shouldBe` reg
