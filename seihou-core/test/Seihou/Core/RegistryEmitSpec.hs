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
                ]
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
              recipes = []
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
              recipes = []
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
              recipes = []
            }
    roundTrip reg

  it "round-trips an empty registry" $ do
    let reg =
          Registry
            { repoName = "Empty",
              repoDescription = Nothing,
              modules = [],
              recipes = []
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
