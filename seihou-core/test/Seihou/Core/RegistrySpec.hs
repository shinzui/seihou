module Seihou.Core.RegistrySpec (tests) where

import Data.List (isInfixOf)
import Data.Text (Text)
import Seihou.Core.Registry
  ( EntryKind (..),
    Registry (..),
    RegistryEntry (..),
    RegistryValidationIssue (..),
    RegistryValidationReport (..),
    RepoContents (..),
    SyncDiff (..),
    SyncReport (..),
    SyncStatus (..),
    computeRegistrySync,
    discoverRepoContents,
    validateRegistry,
    validateRegistryFull,
  )
import Seihou.Core.Types
import Seihou.Dhall.Eval (evalRegistryFromFile)
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Core.Registry" spec

spec :: Spec
spec = do
  describe "evalRegistryFromFile" $ do
    it "decodes a valid registry with two modules" $ do
      withSystemTempDirectory "seihou-registry-test" $ \tmpDir -> do
        let dhall =
              "{ repoName = \"Haskell Templates\"\n\
              \, repoDescription = Some \"A collection of Haskell project templates\"\n\
              \, modules =\n\
              \  [ { name = \"haskell-base\"\n\
              \    , version = None Text\n\
              \    , path = \"modules/haskell-base\"\n\
              \    , description = Some \"Minimal Haskell project with cabal\"\n\
              \    , tags = [ \"haskell\", \"starter\" ]\n\
              \    }\n\
              \  , { name = \"nix-flake\"\n\
              \    , version = None Text\n\
              \    , path = \"modules/nix-flake\"\n\
              \    , description = Some \"Nix flake overlay\"\n\
              \    , tags = [ \"nix\" ]\n\
              \    }\n\
              \  ]\n\
              \}"
        writeFile (tmpDir </> "seihou-registry.dhall") dhall
        result <- evalRegistryFromFile (tmpDir </> "seihou-registry.dhall")
        case result of
          Left err -> expectationFailure ("Expected Right, got Left: " <> show err)
          Right reg -> do
            reg.repoName `shouldBe` "Haskell Templates"
            reg.repoDescription `shouldBe` Just "A collection of Haskell project templates"
            length reg.modules `shouldBe` 2
            let (e1 : e2 : _) = reg.modules
            e1.name `shouldBe` ModuleName "haskell-base"
            e1.path `shouldBe` "modules/haskell-base"
            e1.description `shouldBe` Just "Minimal Haskell project with cabal"
            e1.tags `shouldBe` ["haskell", "starter"]
            e2.name `shouldBe` ModuleName "nix-flake"
            e2.tags `shouldBe` ["nix"]

    it "decodes a registry with an empty module list" $ do
      withSystemTempDirectory "seihou-registry-test" $ \tmpDir -> do
        let dhall =
              "{ repoName = \"Empty Collection\"\n\
              \, repoDescription = None Text\n\
              \, modules = [] : List { name : Text, version : Optional Text, path : Text, description : Optional Text, tags : List Text }\n\
              \}"
        writeFile (tmpDir </> "seihou-registry.dhall") dhall
        result <- evalRegistryFromFile (tmpDir </> "seihou-registry.dhall")
        case result of
          Left err -> expectationFailure ("Expected Right, got Left: " <> show err)
          Right reg -> do
            reg.repoName `shouldBe` "Empty Collection"
            reg.repoDescription `shouldBe` Nothing
            reg.modules `shouldBe` []

    it "decodes a registry with no description" $ do
      withSystemTempDirectory "seihou-registry-test" $ \tmpDir -> do
        let dhall =
              "{ repoName = \"Minimal\"\n\
              \, repoDescription = None Text\n\
              \, modules =\n\
              \  [ { name = \"one\"\n\
              \    , version = None Text\n\
              \    , path = \"one\"\n\
              \    , description = None Text\n\
              \    , tags = [] : List Text\n\
              \    }\n\
              \  ]\n\
              \}"
        writeFile (tmpDir </> "seihou-registry.dhall") dhall
        result <- evalRegistryFromFile (tmpDir </> "seihou-registry.dhall")
        case result of
          Left err -> expectationFailure ("Expected Right, got Left: " <> show err)
          Right reg -> do
            reg.repoDescription `shouldBe` Nothing
            let (e1 : _) = reg.modules
            e1.description `shouldBe` Nothing
            e1.tags `shouldBe` []

    it "returns RegistryEvalError for malformed registry (missing required field)" $ do
      withSystemTempDirectory "seihou-registry-test" $ \tmpDir -> do
        let dhall =
              "{ repoName = \"Bad\"\n\
              \, modules = [] : List { name : Text, version : Optional Text, path : Text, description : Optional Text, tags : List Text }\n\
              \}"
        writeFile (tmpDir </> "seihou-registry.dhall") dhall
        result <- evalRegistryFromFile (tmpDir </> "seihou-registry.dhall")
        case result of
          Left (RegistryEvalError _ _) -> pure ()
          Left other -> expectationFailure ("Expected RegistryEvalError, got: " <> show other)
          Right _ -> expectationFailure "Expected Left for malformed registry"

    it "returns RegistryEvalError for nonexistent file" $ do
      result <- evalRegistryFromFile "/nonexistent/path/seihou-registry.dhall"
      case result of
        Left (RegistryEvalError _ _) -> pure ()
        Left other -> expectationFailure ("Expected RegistryEvalError, got: " <> show other)
        Right _ -> expectationFailure "Expected Left for nonexistent file"

  describe "discoverRepoContents" $ do
    it "returns MultiModule when seihou-registry.dhall exists" $ do
      withSystemTempDirectory "seihou-discover-test" $ \tmpDir -> do
        writeRegistryFile tmpDir
        result <- discoverRepoContents evalRegistryFromFile tmpDir
        case result of
          MultiModule reg -> reg.repoName `shouldBe` "Test Registry"
          other -> expectationFailure ("Expected MultiModule, got: " <> show other)

    it "returns SingleModule when only module.dhall exists" $ do
      withSystemTempDirectory "seihou-discover-test" $ \tmpDir -> do
        writeMinimalModuleDhall (tmpDir </> "module.dhall")
        result <- discoverRepoContents evalRegistryFromFile tmpDir
        case result of
          SingleModule p -> p `shouldBe` tmpDir
          other -> expectationFailure ("Expected SingleModule, got: " <> show other)

    it "returns MultiModule when both registry and module.dhall exist" $ do
      withSystemTempDirectory "seihou-discover-test" $ \tmpDir -> do
        writeRegistryFile tmpDir
        writeMinimalModuleDhall (tmpDir </> "module.dhall")
        result <- discoverRepoContents evalRegistryFromFile tmpDir
        case result of
          MultiModule reg -> reg.repoName `shouldBe` "Test Registry"
          other -> expectationFailure ("Expected MultiModule (registry takes precedence), got: " <> show other)

    it "returns EmptyRepo when neither file exists" $ do
      withSystemTempDirectory "seihou-discover-test" $ \tmpDir -> do
        result <- discoverRepoContents evalRegistryFromFile tmpDir
        case result of
          EmptyRepo -> pure ()
          other -> expectationFailure ("Expected EmptyRepo, got: " <> show other)

    it "falls back to SingleModule when registry is malformed and module.dhall exists" $ do
      withSystemTempDirectory "seihou-discover-test" $ \tmpDir -> do
        writeFile (tmpDir </> "seihou-registry.dhall") "{ broken = True }"
        writeMinimalModuleDhall (tmpDir </> "module.dhall")
        result <- discoverRepoContents evalRegistryFromFile tmpDir
        case result of
          SingleModule _ -> pure ()
          other -> expectationFailure ("Expected SingleModule fallback, got: " <> show other)

  describe "validateRegistry" $ do
    it "returns no errors for a valid registry" $ do
      withSystemTempDirectory "seihou-validate-reg" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "mod-a")
        writeMinimalModuleDhall (tmpDir </> "mod-a" </> "module.dhall")
        let reg =
              Registry
                { repoName = "Test",
                  repoDescription = Nothing,
                  modules = [RegistryEntry (ModuleName "mod-a") Nothing "mod-a" Nothing []],
                  recipes = [],
                  blueprints = []
                }
        errs <- validateRegistry tmpDir reg
        errs `shouldBe` []

    it "reports invalid module name" $ do
      withSystemTempDirectory "seihou-validate-reg" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "Bad_Name")
        writeMinimalModuleDhall (tmpDir </> "Bad_Name" </> "module.dhall")
        let reg =
              Registry
                { repoName = "Test",
                  repoDescription = Nothing,
                  modules = [RegistryEntry (ModuleName "Bad_Name") Nothing "Bad_Name" Nothing []],
                  recipes = [],
                  blueprints = []
                }
        errs <- validateRegistry tmpDir reg
        length errs `shouldSatisfy` (> 0)
        any ("must match" `isInfixOf`) (map show errs) `shouldBe` True

    it "reports missing module.dhall at entry path" $ do
      withSystemTempDirectory "seihou-validate-reg" $ \tmpDir -> do
        let reg =
              Registry
                { repoName = "Test",
                  repoDescription = Nothing,
                  modules = [RegistryEntry (ModuleName "missing") Nothing "nonexistent" Nothing []],
                  recipes = [],
                  blueprints = []
                }
        errs <- validateRegistry tmpDir reg
        length errs `shouldSatisfy` (> 0)
        any ("missing module.dhall" `isInfixOf`) (map show errs) `shouldBe` True

    it "reports unsafe path with .." $ do
      withSystemTempDirectory "seihou-validate-reg" $ \tmpDir -> do
        let reg =
              Registry
                { repoName = "Test",
                  repoDescription = Nothing,
                  modules = [RegistryEntry (ModuleName "bad-path") Nothing "../escape" Nothing []],
                  recipes = [],
                  blueprints = []
                }
        errs <- validateRegistry tmpDir reg
        any ("must not contain" `isInfixOf`) (map show errs) `shouldBe` True

  describe "validateRegistryFull" $ do
    it "returns no issues for a fully clean registry" $ do
      withSystemTempDirectory "seihou-validate-full" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "mod-a")
        writeMinimalModuleDhall (tmpDir </> "mod-a" </> "module.dhall")
        let reg =
              Registry
                { repoName = "Test",
                  repoDescription = Nothing,
                  modules = [RegistryEntry (ModuleName "mod-a") (Just "1.0.0") "mod-a" Nothing []],
                  recipes = [],
                  blueprints = []
                }
            lookups = [(ModuleEntry, ModuleName "mod-a", Just "1.0.0")]
        report <- validateRegistryFull tmpDir reg lookups
        report.reportIssues `shouldBe` []
        report.reportModuleCount `shouldBe` 1
        report.reportRecipeCount `shouldBe` 0
        report.reportBlueprintCount `shouldBe` 0

    it "flags a SyncMissing entry as a single VersionMismatch" $ do
      withSystemTempDirectory "seihou-validate-full" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "mod-a")
        writeMinimalModuleDhall (tmpDir </> "mod-a" </> "module.dhall")
        let reg =
              Registry
                { repoName = "Test",
                  repoDescription = Nothing,
                  modules = [RegistryEntry (ModuleName "mod-a") Nothing "mod-a" Nothing []],
                  recipes = [],
                  blueprints = []
                }
            lookups = [(ModuleEntry, ModuleName "mod-a", Just "1.0.0")]
        report <- validateRegistryFull tmpDir reg lookups
        case report.reportIssues of
          [VersionMismatch d] -> d.diffStatus `shouldBe` SyncMissing
          other -> expectationFailure ("expected one VersionMismatch SyncMissing, got: " <> show other)

    it "flags a SyncStale entry as a single VersionMismatch carrying the new version" $ do
      withSystemTempDirectory "seihou-validate-full" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "mod-a")
        writeMinimalModuleDhall (tmpDir </> "mod-a" </> "module.dhall")
        let reg =
              Registry
                { repoName = "Test",
                  repoDescription = Nothing,
                  modules = [RegistryEntry (ModuleName "mod-a") (Just "1.0.0") "mod-a" Nothing []],
                  recipes = [],
                  blueprints = []
                }
            lookups = [(ModuleEntry, ModuleName "mod-a", Just "2.0.0")]
        report <- validateRegistryFull tmpDir reg lookups
        case report.reportIssues of
          [VersionMismatch d] -> d.diffStatus `shouldBe` SyncStale "2.0.0"
          other -> expectationFailure ("expected one VersionMismatch SyncStale, got: " <> show other)

    it "flags an invalid module name as a StructuralError" $ do
      withSystemTempDirectory "seihou-validate-full" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "Bad_Name")
        writeMinimalModuleDhall (tmpDir </> "Bad_Name" </> "module.dhall")
        let reg =
              Registry
                { repoName = "Test",
                  repoDescription = Nothing,
                  modules = [RegistryEntry (ModuleName "Bad_Name") Nothing "Bad_Name" Nothing []],
                  recipes = [],
                  blueprints = []
                }
            lookups = [(ModuleEntry, ModuleName "Bad_Name", Nothing)]
        report <- validateRegistryFull tmpDir reg lookups
        let structurals = [msg | StructuralError msg <- report.reportIssues]
        any ("must match" `isInfixOf`) (map show structurals) `shouldBe` True

    it "flags an unsafe path with .. as a StructuralError" $ do
      withSystemTempDirectory "seihou-validate-full" $ \tmpDir -> do
        let reg =
              Registry
                { repoName = "Test",
                  repoDescription = Nothing,
                  modules = [RegistryEntry (ModuleName "escape") Nothing "../escape" Nothing []],
                  recipes = [],
                  blueprints = []
                }
        report <- validateRegistryFull tmpDir reg []
        let structurals = [msg | StructuralError msg <- report.reportIssues]
        any ("must not contain" `isInfixOf`) (map show structurals) `shouldBe` True

    it "lists structural issues before version issues when both are present" $ do
      withSystemTempDirectory "seihou-validate-full" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "good")
        writeMinimalModuleDhall (tmpDir </> "good" </> "module.dhall")
        createDirectoryIfMissing True (tmpDir </> "stale")
        writeMinimalModuleDhall (tmpDir </> "stale" </> "module.dhall")
        let reg =
              Registry
                { repoName = "Test",
                  repoDescription = Nothing,
                  modules =
                    [ RegistryEntry (ModuleName "good") (Just "1.0.0") "good" Nothing [],
                      RegistryEntry (ModuleName "missing-mod") Nothing "no-such-dir" Nothing [],
                      RegistryEntry (ModuleName "stale") (Just "1.0.0") "stale" Nothing []
                    ],
                  recipes = [],
                  blueprints = []
                }
            lookups =
              [ (ModuleEntry, ModuleName "good", Just "1.0.0"),
                (ModuleEntry, ModuleName "stale", Just "2.0.0")
              ]
        report <- validateRegistryFull tmpDir reg lookups
        length report.reportIssues `shouldBe` 2
        case report.reportIssues of
          [StructuralError msg, VersionMismatch d] -> do
            ("missing module.dhall" `isInfixOf` show msg) `shouldBe` True
            d.diffStatus `shouldBe` SyncStale "2.0.0"
          other ->
            expectationFailure
              ("expected [StructuralError, VersionMismatch], got: " <> show other)

  describe "blueprints in registries" $ do
    it "decodes a registry with all three entry kinds" $ do
      withSystemTempDirectory "seihou-registry-bp" $ \tmpDir -> do
        let dhall =
              "{ repoName = \"Three Kinds\"\n\
              \, repoDescription = None Text\n\
              \, modules =\n\
              \  [ { name = \"mod-one\"\n\
              \    , version = None Text\n\
              \    , path = \"modules/mod-one\"\n\
              \    , description = None Text\n\
              \    , tags = [] : List Text\n\
              \    }\n\
              \  ]\n\
              \, recipes =\n\
              \  [ { name = \"rec-one\"\n\
              \    , version = None Text\n\
              \    , path = \"recipes/rec-one\"\n\
              \    , description = None Text\n\
              \    , tags = [] : List Text\n\
              \    }\n\
              \  ]\n\
              \, blueprints =\n\
              \  [ { name = \"bp-one\"\n\
              \    , version = Some \"0.1.0\"\n\
              \    , path = \"blueprints/bp-one\"\n\
              \    , description = Some \"A blueprint\"\n\
              \    , tags = [ \"agent\" ]\n\
              \    }\n\
              \  ]\n\
              \}"
        writeFile (tmpDir </> "seihou-registry.dhall") dhall
        result <- evalRegistryFromFile (tmpDir </> "seihou-registry.dhall")
        case result of
          Left err -> expectationFailure ("Expected Right, got Left: " <> show err)
          Right reg -> do
            length reg.modules `shouldBe` 1
            length reg.recipes `shouldBe` 1
            length reg.blueprints `shouldBe` 1
            let (bp : _) = reg.blueprints
            bp.name `shouldBe` ModuleName "bp-one"
            bp.version `shouldBe` Just "0.1.0"
            bp.tags `shouldBe` ["agent"]

    it "decodes a pre-EP-33 registry (no blueprints field) with blueprints = []" $ do
      withSystemTempDirectory "seihou-registry-bp-compat" $ \tmpDir -> do
        let dhall =
              "{ repoName = \"Old Registry\"\n\
              \, repoDescription = None Text\n\
              \, modules =\n\
              \  [ { name = \"mod-a\"\n\
              \    , version = None Text\n\
              \    , path = \"mod-a\"\n\
              \    , description = None Text\n\
              \    , tags = [] : List Text\n\
              \    }\n\
              \  ]\n\
              \}"
        writeFile (tmpDir </> "seihou-registry.dhall") dhall
        result <- evalRegistryFromFile (tmpDir </> "seihou-registry.dhall")
        case result of
          Left err -> expectationFailure ("Expected Right, got Left: " <> show err)
          Right reg -> do
            reg.recipes `shouldBe` []
            reg.blueprints `shouldBe` []

    it "rejects an invalid blueprint name" $ do
      withSystemTempDirectory "seihou-validate-bp" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "Bad_Bp")
        writeMinimalBlueprintDhall (tmpDir </> "Bad_Bp" </> "blueprint.dhall")
        let reg =
              Registry
                { repoName = "Test",
                  repoDescription = Nothing,
                  modules = [],
                  recipes = [],
                  blueprints = [RegistryEntry (ModuleName "Bad_Bp") Nothing "Bad_Bp" Nothing []]
                }
        errs <- validateRegistry tmpDir reg
        any ("blueprint name must match" `isInfixOf`) (map show errs) `shouldBe` True

    it "reports a missing blueprint.dhall at the entry path" $ do
      withSystemTempDirectory "seihou-validate-bp-missing" $ \tmpDir -> do
        let reg =
              Registry
                { repoName = "Test",
                  repoDescription = Nothing,
                  modules = [],
                  recipes = [],
                  blueprints = [RegistryEntry (ModuleName "ghost") Nothing "ghost" Nothing []]
                }
        errs <- validateRegistry tmpDir reg
        any ("missing blueprint.dhall" `isInfixOf`) (map show errs) `shouldBe` True

    it "rejects an unsafe blueprint path with .." $ do
      withSystemTempDirectory "seihou-validate-bp-path" $ \tmpDir -> do
        let reg =
              Registry
                { repoName = "Test",
                  repoDescription = Nothing,
                  modules = [],
                  recipes = [],
                  blueprints = [RegistryEntry (ModuleName "escape") Nothing "../escape" Nothing []]
                }
        errs <- validateRegistry tmpDir reg
        any ("blueprint path must not contain" `isInfixOf`) (map show errs) `shouldBe` True

    it "detects module-blueprint and recipe-blueprint cross-kind name collisions" $ do
      withSystemTempDirectory "seihou-collision-bp" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "shared-mod")
        writeMinimalModuleDhall (tmpDir </> "shared-mod" </> "module.dhall")
        createDirectoryIfMissing True (tmpDir </> "shared-rec")
        writeMinimalRecipeDhall (tmpDir </> "shared-rec" </> "recipe.dhall")
        createDirectoryIfMissing True (tmpDir </> "shared-bp1")
        writeMinimalBlueprintDhall (tmpDir </> "shared-bp1" </> "blueprint.dhall")
        createDirectoryIfMissing True (tmpDir </> "shared-bp2")
        writeMinimalBlueprintDhall (tmpDir </> "shared-bp2" </> "blueprint.dhall")
        let reg =
              Registry
                { repoName = "Test",
                  repoDescription = Nothing,
                  modules = [RegistryEntry (ModuleName "duped") Nothing "shared-mod" Nothing []],
                  recipes = [RegistryEntry (ModuleName "other") Nothing "shared-rec" Nothing []],
                  blueprints =
                    [ RegistryEntry (ModuleName "duped") Nothing "shared-bp1" Nothing [],
                      RegistryEntry (ModuleName "other") Nothing "shared-bp2" Nothing []
                    ]
                }
        errs <- validateRegistry tmpDir reg
        any ("appears as both a module and a blueprint" `isInfixOf`) (map show errs)
          `shouldBe` True
        any ("appears as both a recipe and a blueprint" `isInfixOf`) (map show errs)
          `shouldBe` True

    it "detects a three-way name collision (module, recipe, and blueprint)" $ do
      withSystemTempDirectory "seihou-collision-three" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "trip-m")
        writeMinimalModuleDhall (tmpDir </> "trip-m" </> "module.dhall")
        createDirectoryIfMissing True (tmpDir </> "trip-r")
        writeMinimalRecipeDhall (tmpDir </> "trip-r" </> "recipe.dhall")
        createDirectoryIfMissing True (tmpDir </> "trip-b")
        writeMinimalBlueprintDhall (tmpDir </> "trip-b" </> "blueprint.dhall")
        let reg =
              Registry
                { repoName = "Test",
                  repoDescription = Nothing,
                  modules = [RegistryEntry (ModuleName "tripled") Nothing "trip-m" Nothing []],
                  recipes = [RegistryEntry (ModuleName "tripled") Nothing "trip-r" Nothing []],
                  blueprints = [RegistryEntry (ModuleName "tripled") Nothing "trip-b" Nothing []]
                }
        errs <- validateRegistry tmpDir reg
        let messages = map show errs
        any ("appears as both a module and a recipe" `isInfixOf`) messages `shouldBe` True
        any ("appears as both a module and a blueprint" `isInfixOf`) messages `shouldBe` True
        any ("appears as both a recipe and a blueprint" `isInfixOf`) messages `shouldBe` True

    it "computeRegistrySync classifies blueprint entries with diffKind = BlueprintEntry" $ do
      let reg =
            Registry
              { repoName = "Test",
                repoDescription = Nothing,
                modules = [],
                recipes = [],
                blueprints =
                  [ RegistryEntry (ModuleName "bp-stale") (Just "0.1.0") "blueprints/bp-stale" Nothing []
                  ]
              }
          lookups = [(BlueprintEntry, ModuleName "bp-stale", Just "0.2.0")]
          SyncReport diffs (Registry _ _ _ _ bpsAfter) = computeRegistrySync reg lookups
          kinds = [diff_ | SyncDiff {diffKind = diff_} <- diffs]
          statuses = [s | SyncDiff {diffStatus = s} <- diffs]
      kinds `shouldBe` [BlueprintEntry]
      statuses `shouldBe` [SyncStale "0.2.0"]
      let updatedVersion = case bpsAfter of
            (RegistryEntry _ v _ _ _ : _) -> v
            _ -> Nothing
      updatedVersion `shouldBe` Just ("0.2.0" :: Text)

    it "validateRegistryFull populates reportBlueprintCount" $ do
      withSystemTempDirectory "seihou-validate-bp-count" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "bp-a")
        writeMinimalBlueprintDhall (tmpDir </> "bp-a" </> "blueprint.dhall")
        createDirectoryIfMissing True (tmpDir </> "bp-b")
        writeMinimalBlueprintDhall (tmpDir </> "bp-b" </> "blueprint.dhall")
        let reg =
              Registry
                { repoName = "Test",
                  repoDescription = Nothing,
                  modules = [],
                  recipes = [],
                  blueprints =
                    [ RegistryEntry (ModuleName "bp-a") (Just "1.0.0") "bp-a" Nothing [],
                      RegistryEntry (ModuleName "bp-b") (Just "1.0.0") "bp-b" Nothing []
                    ]
                }
            lookups =
              [ (BlueprintEntry, ModuleName "bp-a", Just "1.0.0"),
                (BlueprintEntry, ModuleName "bp-b", Just "1.0.0")
              ]
        report <- validateRegistryFull tmpDir reg lookups
        report.reportBlueprintCount `shouldBe` 2
        report.reportIssues `shouldBe` []

  describe "discoverRepoContents and blueprints" $ do
    it "returns SingleBlueprint when only blueprint.dhall is present" $ do
      withSystemTempDirectory "seihou-discover-bp" $ \tmpDir -> do
        writeMinimalBlueprintDhall (tmpDir </> "blueprint.dhall")
        result <- discoverRepoContents evalRegistryFromFile tmpDir
        case result of
          SingleBlueprint p -> p `shouldBe` tmpDir
          other -> expectationFailure ("Expected SingleBlueprint, got: " <> show other)

    it "prefers SingleModule over SingleBlueprint when both are present" $ do
      withSystemTempDirectory "seihou-discover-bp-mod" $ \tmpDir -> do
        writeMinimalModuleDhall (tmpDir </> "module.dhall")
        writeMinimalBlueprintDhall (tmpDir </> "blueprint.dhall")
        result <- discoverRepoContents evalRegistryFromFile tmpDir
        case result of
          SingleModule _ -> pure ()
          other -> expectationFailure ("Expected SingleModule (module beats blueprint), got: " <> show other)

    it "prefers SingleRecipe over SingleBlueprint when both are present" $ do
      withSystemTempDirectory "seihou-discover-bp-rec" $ \tmpDir -> do
        writeMinimalRecipeDhall (tmpDir </> "recipe.dhall")
        writeMinimalBlueprintDhall (tmpDir </> "blueprint.dhall")
        result <- discoverRepoContents evalRegistryFromFile tmpDir
        case result of
          SingleRecipe _ -> pure ()
          other -> expectationFailure ("Expected SingleRecipe (recipe beats blueprint), got: " <> show other)

    it "prefers MultiModule over SingleBlueprint when both registry and blueprint exist" $ do
      withSystemTempDirectory "seihou-discover-reg-bp" $ \tmpDir -> do
        writeRegistryFile tmpDir
        writeMinimalBlueprintDhall (tmpDir </> "blueprint.dhall")
        result <- discoverRepoContents evalRegistryFromFile tmpDir
        case result of
          MultiModule _ -> pure ()
          other -> expectationFailure ("Expected MultiModule (registry beats blueprint), got: " <> show other)

-- Helper: write a minimal valid seihou-registry.dhall
writeRegistryFile :: FilePath -> IO ()
writeRegistryFile dir = do
  let dhall =
        "{ repoName = \"Test Registry\"\n\
        \, repoDescription = Some \"A test registry\"\n\
        \, modules =\n\
        \  [ { name = \"mod-a\"\n\
        \    , version = None Text\n\
        \    , path = \"mod-a\"\n\
        \    , description = Some \"Module A\"\n\
        \    , tags = [ \"test\" ]\n\
        \    }\n\
        \  ]\n\
        \}"
  writeFile (dir </> "seihou-registry.dhall") dhall

-- Helper: write a minimal valid module.dhall
writeMinimalModuleDhall :: FilePath -> IO ()
writeMinimalModuleDhall path = do
  let dhall =
        "{ name = \"minimal\"\n\
        \, version = None Text\n\
        \, description = None Text\n\
        \, vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }\n\
        \, exports = [] : List { var : Text, alias : Optional Text }\n\
        \, prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }\n\
        \, steps = [] : List { strategy : Text, src : Text, dest : Text, when : Optional Text, patch : Optional Text }\n\
        \, commands = [] : List { run : Text, workDir : Optional Text, when : Optional Text }\n\
        \, dependencies = [] : List Text\n\
        \, removal = None { steps : List { action : Text, dest : Text, src : Optional Text }, commands : List { run : Text, workDir : Optional Text, when : Optional Text } }\n\
        \}"
  writeFile path dhall

-- Helper: write a minimal valid recipe.dhall
writeMinimalRecipeDhall :: FilePath -> IO ()
writeMinimalRecipeDhall path = do
  let dhall =
        "{ name = \"minimal\"\n\
        \, version = None Text\n\
        \, description = None Text\n\
        \, modules = [] : List Text\n\
        \, vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }\n\
        \, prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }\n\
        \}"
  writeFile path dhall

-- Helper: write a minimal valid blueprint.dhall
writeMinimalBlueprintDhall :: FilePath -> IO ()
writeMinimalBlueprintDhall path = do
  let dhall =
        "{ name = \"minimal-bp\"\n\
        \, version = Some \"0.1.0\"\n\
        \, description = None Text\n\
        \, prompt = \"hello\"\n\
        \, vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }\n\
        \, prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }\n\
        \, baseModules = [] : List { module : Text, vars : List { name : Text, value : Text } }\n\
        \, files = [] : List { src : Text, description : Optional Text }\n\
        \, allowedTools = None (List Text)\n\
        \, tags = [] : List Text\n\
        \}"
  writeFile path dhall
