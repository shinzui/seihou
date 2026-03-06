module Seihou.Core.RegistrySpec (tests) where

import Seihou.Core.Registry (Registry (..), RegistryEntry (..))
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
              \    , path = \"modules/haskell-base\"\n\
              \    , description = Some \"Minimal Haskell project with cabal\"\n\
              \    , tags = [ \"haskell\", \"starter\" ]\n\
              \    }\n\
              \  , { name = \"nix-flake\"\n\
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
              \, modules = [] : List { name : Text, path : Text, description : Optional Text, tags : List Text }\n\
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
              \, modules = [] : List { name : Text, path : Text, description : Optional Text, tags : List Text }\n\
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
