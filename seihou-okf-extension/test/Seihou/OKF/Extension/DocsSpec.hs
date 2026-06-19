module Seihou.OKF.Extension.DocsSpec (tests) where

import Data.Text qualified as T
import Okf.Bundle qualified as Okf
import Okf.Validation qualified as Okf
import Seihou.OKF.Extension.Docs
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.OKF.Extension.Docs" spec

spec :: Spec
spec = do
  describe "runDocs" $ do
    it "writes and validates an OKF bundle for a registry" $ do
      withSystemTempDirectory "seihou-okf-docs" $ \tmpDir -> do
        let registryDir = tmpDir </> "registry"
            outDir = tmpDir </> "out"
        writeFixtureRegistry registryDir
        result <- runDocs DocsOpts {docsDir = registryDir, docsOut = outDir, docsForce = False}
        result `shouldBe` Right ("Wrote 2 concepts to " <> T.pack outDir)
        doesFileExist (outDir </> "modules" </> "base.md") `shouldReturn` True
        doesFileExist (outDir </> "recipes" </> "base-recipe.md") `shouldReturn` True
        walked <- Okf.walkBundle outDir
        case walked of
          Left err -> expectationFailure ("Expected walkBundle success, got " <> show err)
          Right concepts -> Okf.validateBundle Okf.PermissiveConformance concepts `shouldBe` []

    it "refuses to overwrite a non-empty output directory without force" $ do
      withSystemTempDirectory "seihou-okf-docs-force" $ \tmpDir -> do
        let registryDir = tmpDir </> "registry"
            outDir = tmpDir </> "out"
        writeFixtureRegistry registryDir
        first <- runDocs DocsOpts {docsDir = registryDir, docsOut = outDir, docsForce = False}
        first `shouldBe` Right ("Wrote 2 concepts to " <> T.pack outDir)
        second <- runDocs DocsOpts {docsDir = registryDir, docsOut = outDir, docsForce = False}
        second `shouldBe` Left ("output directory is not empty: " <> T.pack outDir <> "; pass --force to overwrite")
        forced <- runDocs DocsOpts {docsDir = registryDir, docsOut = outDir, docsForce = True}
        forced `shouldBe` Right ("Wrote 2 concepts to " <> T.pack outDir)

    it "reports a missing registry file" $ do
      withSystemTempDirectory "seihou-okf-docs-missing" $ \tmpDir -> do
        let registryDir = tmpDir </> "missing"
        result <- runDocs DocsOpts {docsDir = registryDir, docsOut = tmpDir </> "out", docsForce = False}
        result `shouldBe` Left ("registry file not found: " <> T.pack (registryDir </> "seihou-registry.dhall"))

writeFixtureRegistry :: FilePath -> IO ()
writeFixtureRegistry registryDir = do
  createDirectoryIfMissing True (registryDir </> "modules" </> "base")
  createDirectoryIfMissing True (registryDir </> "recipes" </> "base-recipe")
  writeFile (registryDir </> "seihou-registry.dhall") registryDhall
  writeFile (registryDir </> "modules" </> "base" </> "module.dhall") moduleDhall
  writeFile (registryDir </> "recipes" </> "base-recipe" </> "recipe.dhall") recipeDhall

registryDhall :: String
registryDhall =
  "{ repoName = \"fixture-registry\"\n\
  \, repoDescription = Some \"Fixture registry\"\n\
  \, modules = [ { name = \"base\", version = Some \"1.0.0\", path = \"modules/base\", description = Some \"Base module\", tags = [ \"haskell\" ] } ]\n\
  \, recipes = [ { name = \"base-recipe\", version = Some \"0.1.0\", path = \"recipes/base-recipe\", description = Some \"Recipe\", tags = [ \"recipe\" ] } ]\n\
  \, blueprints = [] : List { name : Text, version : Optional Text, path : Text, description : Optional Text, tags : List Text }\n\
  \, prompts = [] : List { name : Text, version : Optional Text, path : Text, description : Optional Text, tags : List Text }\n\
  \}"

moduleDhall :: String
moduleDhall =
  "{ name = \"base\"\n\
  \, version = Some \"1.0.0\"\n\
  \, description = Some \"Base module\"\n\
  \, vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }\n\
  \, exports = [] : List { var : Text, alias : Optional Text }\n\
  \, prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }\n\
  \, steps = [] : List { strategy : Text, src : Text, dest : Text, when : Optional Text, patch : Optional Text }\n\
  \, commands = [] : List { run : Text, workDir : Optional Text, when : Optional Text }\n\
  \, dependencies = [] : List Text\n\
  \}"

recipeDhall :: String
recipeDhall =
  "{ name = \"base-recipe\"\n\
  \, version = Some \"0.1.0\"\n\
  \, description = Some \"Recipe\"\n\
  \, modules = [ \"base\" ]\n\
  \, vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }\n\
  \, prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }\n\
  \}"
