module Seihou.Manifest.TypesSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Time (UTCTime, defaultTimeLocale, parseTimeOrError)
import Seihou.Core.Types
import Seihou.Manifest.Hash (hashContent)
import Seihou.Manifest.Types
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Manifest.Types" spec

-- Helper to create a fixed timestamp for testing.
fixedTime :: UTCTime
fixedTime = parseTimeOrError True defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ" "2026-03-01T10:30:00Z"

fixedTime2 :: UTCTime
fixedTime2 = parseTimeOrError True defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ" "2026-03-01T11:00:00Z"

spec :: Spec
spec = do
  describe "emptyManifest" $ do
    it "creates a manifest with version 1" $ do
      let m = emptyManifest fixedTime
      m.version `shouldBe` currentManifestVersion
      m.version `shouldBe` 1

    it "creates a manifest with no modules, vars, or files" $ do
      let m = emptyManifest fixedTime
      m.modules `shouldBe` []
      m.vars `shouldBe` Map.empty
      m.files `shouldBe` Map.empty

  describe "JSON roundtrip" $ do
    it "roundtrips an empty manifest" $ do
      let m = emptyManifest fixedTime
      manifestFromJSON (manifestToJSON m) `shouldBe` Right m

    it "roundtrips a manifest with modules" $ do
      let m =
            (emptyManifest fixedTime)
              { modules =
                  [ AppliedModule
                      { name = ModuleName "haskell-base",
                        source = "/home/user/.config/seihou/modules/haskell-base",
                        appliedAt = fixedTime,
                        removal = Nothing
                      }
                  ]
              }
      manifestFromJSON (manifestToJSON m) `shouldBe` Right m

    it "roundtrips a manifest with variables" $ do
      let base = emptyManifest fixedTime
          m =
            Manifest
              { version = base.version,
                genAt = base.genAt,
                modules = base.modules,
                vars =
                  Map.fromList
                    [ (VarName "project.name", "my-app"),
                      (VarName "license", "MIT")
                    ],
                files = base.files
              }
      manifestFromJSON (manifestToJSON m) `shouldBe` Right m

    it "roundtrips a manifest with file records" $ do
      let m =
            (emptyManifest fixedTime)
              { files =
                  Map.fromList
                    [ ( "README.md",
                        FileRecord
                          { hash = SHA256 "abc123",
                            moduleName = ModuleName "haskell-base",
                            strategy = Template,
                            generatedAt = fixedTime
                          }
                      ),
                      ( "my-app.cabal",
                        FileRecord
                          { hash = SHA256 "def456",
                            moduleName = ModuleName "haskell-base",
                            strategy = DhallText,
                            generatedAt = fixedTime
                          }
                      )
                    ]
              }
      manifestFromJSON (manifestToJSON m) `shouldBe` Right m

    it "roundtrips a full manifest" $ do
      let m =
            Manifest
              { version = 1,
                genAt = fixedTime,
                modules =
                  [ AppliedModule (ModuleName "haskell-base") "/path/to/module" fixedTime Nothing,
                    AppliedModule (ModuleName "nix-flake") "/path/to/nix" fixedTime2 Nothing
                  ],
                vars =
                  Map.fromList
                    [ (VarName "project.name", "my-app"),
                      (VarName "project.version", "0.1.0.0")
                    ],
                files =
                  Map.fromList
                    [ ( "README.md",
                        FileRecord (SHA256 "aaa") (ModuleName "haskell-base") Template fixedTime
                      ),
                      ( "LICENSE",
                        FileRecord (SHA256 "bbb") (ModuleName "haskell-base") Copy fixedTime
                      )
                    ]
              }
      manifestFromJSON (manifestToJSON m) `shouldBe` Right m

    it "roundtrips all strategy types" $ do
      let strategies = [Copy, Template, DhallText, Structured]
          makeRecord s =
            FileRecord (SHA256 "hash") (ModuleName "mod") s fixedTime
          m =
            (emptyManifest fixedTime)
              { files =
                  Map.fromList
                    (zipWith (\i s -> ("file" <> show i, makeRecord s)) [(1 :: Int) ..] strategies)
              }
      manifestFromJSON (manifestToJSON m) `shouldBe` Right m

  describe "version checking" $ do
    it "rejects manifests with version higher than current" $ do
      let base = emptyManifest fixedTime
          m = Manifest {version = 99, genAt = base.genAt, modules = base.modules, vars = base.vars, files = base.files}
          result = manifestFromJSON (manifestToJSON m)
      case result of
        Left err -> err `shouldContain` "newer version"
        Right _ -> expectationFailure "should have rejected future version"

  describe "hashContent" $ do
    it "produces a hex-encoded SHA256 digest" $ do
      let h = hashContent "hello world"
      -- SHA256 of "hello world" is a well-known value
      h.unSHA256 `shouldBe` "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9"

    it "produces different hashes for different content" $ do
      let h1 = hashContent "hello"
          h2 = hashContent "world"
      h1 `shouldNotBe` h2

    it "produces consistent hashes for the same content" $ do
      let h1 = hashContent "test content"
          h2 = hashContent "test content"
      h1 `shouldBe` h2

    it "produces a 64-character hex string" $ do
      let SHA256 hex = hashContent "anything"
      T.length hex `shouldBe` 64

    it "handles empty content" $ do
      let h = hashContent ""
      -- SHA256 of empty string is a well-known value
      h.unSHA256 `shouldBe` "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
