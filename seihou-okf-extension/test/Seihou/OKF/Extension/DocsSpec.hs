module Seihou.OKF.Extension.DocsSpec (tests) where

import Control.Lens ((&), (.~), (?~))
import Data.Generics.Labels ()
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Okf.Bundle qualified as Okf
import Okf.Index qualified as Okf
import Okf.Validation qualified as Okf
import Seihou.OKF.Docs.Render (builtinProfileDescriptor)
import Seihou.OKF.Extension.Docs
import System.Directory (createDirectoryIfMissing, doesFileExist, doesPathExist)
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
        result <- runDocs (docsOpts registryDir outDir False)
        result `shouldBe` Right ("Wrote 3 concepts to " <> T.pack outDir)
        doesFileExist (outDir </> "modules" </> "base.md") `shouldReturn` True
        doesFileExist (outDir </> "recipes" </> "base-recipe.md") `shouldReturn` True
        doesFileExist (outDir </> "index.md") `shouldReturn` True
        rootIndex <- TIO.readFile (outDir </> "index.md")
        rootIndex `shouldSatisfy` T.isInfixOf "okf_version: \"0.2\""
        doesFileExist (outDir </> "modules" </> "index.md") `shouldReturn` True
        doesFileExist (outDir </> "recipes" </> "index.md") `shouldReturn` True
        doesFileExist (outDir </> "registry" </> "fixture-registry.md") `shouldReturn` True
        doesFileExist (outDir </> "profile.dhall") `shouldReturn` True
        writtenProfile <- TIO.readFile (outDir </> "profile.dhall")
        writtenProfile `shouldBe` builtinProfileDescriptor
        walked <- Okf.walkBundle outDir
        case walked of
          Left err -> expectationFailure ("Expected walkBundle success, got " <> show err)
          Right concepts ->
            Okf.validateBundle
              Okf.PermissiveConformance
              Okf.VersionUndeclared
              (Okf.bundleInventoryOfConcepts concepts)
              concepts
              `shouldBe` []

    it "refuses to overwrite a non-empty output directory without force" $ do
      withSystemTempDirectory "seihou-okf-docs-force" $ \tmpDir -> do
        let registryDir = tmpDir </> "registry"
            outDir = tmpDir </> "out"
        writeFixtureRegistry registryDir
        first <- runDocs (docsOpts registryDir outDir False)
        first `shouldBe` Right ("Wrote 3 concepts to " <> T.pack outDir)
        second <- runDocs (docsOpts registryDir outDir False)
        second `shouldBe` Left ("output directory is not empty: " <> T.pack outDir <> "; pass --force to overwrite")
        forced <- runDocs (docsOpts registryDir outDir True)
        forced `shouldBe` Right ("Wrote 3 concepts to " <> T.pack outDir)

    it "refuses to write a bundle that violates the house profile" $ do
      withSystemTempDirectory "seihou-okf-docs-profile" $ \tmpDir -> do
        let registryDir = tmpDir </> "registry"
            outDir = tmpDir </> "out"
            profilePath = tmpDir </> "demanding.dhall"
        writeFixtureRegistry registryDir
        TIO.writeFile profilePath demandingProfile
        result <-
          runDocs (docsOpts registryDir outDir False & #profile ?~ profilePath)
        case result of
          Right summary -> expectationFailure ("Expected a profile violation, got " <> show summary)
          -- Specifically a violation, not an unreadable or uncompilable
          -- descriptor, which would also mention the house profile.
          Left err -> err `shouldSatisfy` T.isInfixOf "house profile: modules/base: missing required field stale_after"
        -- Nothing at all reached disk: the check runs before the output
        -- directory is even prepared.
        doesPathExist outDir `shouldReturn` False

    it "skips profile enforcement with --no-profile" $ do
      withSystemTempDirectory "seihou-okf-docs-no-profile" $ \tmpDir -> do
        let registryDir = tmpDir </> "registry"
            outDir = tmpDir </> "out"
            profilePath = tmpDir </> "demanding.dhall"
        writeFixtureRegistry registryDir
        TIO.writeFile profilePath demandingProfile
        result <-
          runDocs
            ( docsOpts registryDir outDir False
                & #profile ?~ profilePath
                & #noProfile .~ True
            )
        result `shouldBe` Right ("Wrote 3 concepts to " <> T.pack outDir)

    it "derives its demanding fixture profile from the real descriptor" $ do
      demandingProfile `shouldNotBe` builtinProfileDescriptor

    it "reports a missing registry file" $ do
      withSystemTempDirectory "seihou-okf-docs-missing" $ \tmpDir -> do
        let registryDir = tmpDir </> "missing"
        result <- runDocs (docsOpts registryDir (tmpDir </> "out") False)
        result `shouldBe` Left ("registry file not found: " <> T.pack (registryDir </> "seihou-registry.dhall"))

-- | The default option set for a fixture run: strict validation, no generation
-- date, so the written bundle is byte-stable across runs.
docsOpts :: FilePath -> FilePath -> Bool -> DocsOpts
docsOpts registryDir outDir force =
  DocsOpts
    { dir = registryDir,
      out = outDir,
      force = force,
      generatedAt = Nothing,
      permissive = False,
      profile = Nothing,
      noProfile = False
    }

-- | The house profile, plus one required frontmatter key the generator never
-- emits, so that enforcement has something real to reject. Derived from the
-- real descriptor rather than hand-written, so it stays a valid profile.
--
-- 'demandingProfileIsDifferent' guards the substitution: if the descriptor is
-- reworded so the anchor no longer matches, that test fails loudly rather than
-- these two silently checking nothing.
demandingProfile :: T.Text
demandingProfile =
  T.replace
    demandingProfileAnchor
    ("[ scalar \"stale_after\" \"A key this generator never emits.\"\n              , scalar \"type\"")
    builtinProfileDescriptor

demandingProfileAnchor :: T.Text
demandingProfileAnchor = "[ scalar \"type\""

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
