module Seihou.Core.RegistrySpec (tests) where

import Data.List (isInfixOf)
import Seihou.Core.Registry
  ( EntryKind (..),
    Registry (..),
    RegistryEntry (..),
    RegistryValidationIssue (..),
    RegistryValidationReport (..),
    RepoContents (..),
    SyncDiff (..),
    SyncStatus (..),
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
                  recipes = []
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
                  recipes = []
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
                  recipes = []
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
                  recipes = []
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
                  recipes = []
                }
            lookups = [(ModuleEntry, ModuleName "mod-a", Just "1.0.0")]
        report <- validateRegistryFull tmpDir reg lookups
        report.reportIssues `shouldBe` []
        report.reportModuleCount `shouldBe` 1
        report.reportRecipeCount `shouldBe` 0

    it "flags a SyncMissing entry as a single VersionMismatch" $ do
      withSystemTempDirectory "seihou-validate-full" $ \tmpDir -> do
        createDirectoryIfMissing True (tmpDir </> "mod-a")
        writeMinimalModuleDhall (tmpDir </> "mod-a" </> "module.dhall")
        let reg =
              Registry
                { repoName = "Test",
                  repoDescription = Nothing,
                  modules = [RegistryEntry (ModuleName "mod-a") Nothing "mod-a" Nothing []],
                  recipes = []
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
                  recipes = []
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
                  recipes = []
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
                  recipes = []
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
                  recipes = []
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
