module Seihou.OKF.Extension.DocsSpec (tests) where

import Control.Lens ((&), (.~), (?~), (^.))
import Control.Monad (forM)
import Data.Aeson (Value (..))
import Data.Generics.Labels ()
import Data.List (sort)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Dhall qualified
import Okf.Bundle qualified as Okf
import Okf.ConceptId qualified as Okf
import Okf.Index qualified as Okf
import Okf.Profile qualified as Profile
import Okf.Validation qualified as Okf
import Seihou.OKF.Docs.ModelSpec (writeCurrentFixtureRegistry)
import Seihou.OKF.Docs.Render (DocBundleError (..), builtinProfileDescriptor)
import Seihou.OKF.Extension.Docs
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, doesFileExist, doesPathExist, listDirectory)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.OKF.Extension.Docs" spec

spec :: Spec
spec = do
  describe "OKF 0.13 diagnostics" $ do
    it "names the field and violated constraint in every new profile diagnostic" $ do
      Right conceptId <- pure (Okf.parseConceptId "modules/base")
      let field = Profile.FieldPath (Profile.FieldName "generated" :| [Profile.FieldName "at"])
          other = Profile.FieldPath (Profile.FieldName "reviewed" :| [])
          selector = Profile.ValueSelector "sources" (Just "id")
          cases =
            [ (Profile.ConstraintPresenceMissing conceptId field Nothing, "constraint requires field generated.at"),
              (Profile.ConstraintAlternativeMissing conceptId [field, other] Nothing, "constraint requires one of generated.at, reviewed"),
              (Profile.TimestampOrderViolation conceptId field other, "generated.at must precede reviewed"),
              (Profile.TextOperandMismatch conceptId field (Number 7), "must hold text for this constraint, but holds 7"),
              (Profile.ValueFormatMismatch conceptId field Profile.FiniteDecimal (String "0.5"), "must be finite-decimal"),
              (Profile.MembershipValueMissing conceptId field "missing" selector, "absent from sources[].id"),
              (Profile.DuplicateSelectedValue conceptId field "duplicate" other, "repeats duplicate from reviewed"),
              (Profile.NestedFieldNotInProfile conceptId field, "nested field generated.at is not one this profile declares")
            ]
      mapM_ (\(problem, expected) -> renderDocBundleError (DocBundleProfileViolation problem) `shouldSatisfy` T.isInfixOf expected) cases
      renderDocBundleError (DocBundleProfileInvalid (Profile.InvalidConceptConstraint Nothing Nothing selector "undeclared source" :| []))
        `shouldSatisfy` T.isInfixOf "invalid constraint sources[].id: undeclared source"

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
              Okf.StrictAuthoring
              (Okf.VersionDeclared Okf.supportedOkfVersion)
              (Okf.bundleInventoryOfConcepts concepts)
              concepts
              `shouldBe` []

    it "generates complete current declarations without executing commands and regenerates identical bytes" $
      withSystemTempDirectory "seihou-current-docs" $ \tmpDir -> do
        let registryDir = tmpDir </> "registry"
            outDir = tmpDir </> "out"
        createDirectoryIfMissing True registryDir
        writeCurrentFixtureRegistry registryDir
        runDocs (docsOpts registryDir outDir False) `shouldReturn` Right ("Wrote 9 concepts to " <> T.pack outDir)
        first <- snapshot outDir
        runDocs (docsOpts registryDir outDir True) `shouldReturn` Right ("Wrote 9 concepts to " <> T.pack outDir)
        snapshot outDir `shouldReturn` first
        runDocs (docsOpts registryDir outDir True & #profile ?~ (outDir </> "profile.dhall"))
          `shouldReturn` Right ("Wrote 9 concepts to " <> T.pack outDir)
        snapshot outDir `shouldReturn` first
        doesPathExist (registryDir </> "SHOULD-NOT-EXIST") `shouldReturn` False
        let page name = TIO.readFile (outDir </> name)
        app <- page "modules/app.md"
        mapM_
          (\text -> app `shouldSatisfy` T.isInfixOf text)
          [ "Managed:",
            "Seed: created once",
            "Checkout: portable symlink",
            "seihou sync",
            "repeatable checkout setup",
            "from `https://example.invalid/modules.git`",
            "`` exact|`literal` ``",
            "every matching logical line",
            "[docs-review](/judgements/docs-review.md)",
            "when `IsSet project.name`",
            "from `https://example.invalid/reviews.git`"
          ]
        app `shouldNotSatisfy` T.isInfixOf "](/modules/base.md)"
        recipe <- page "recipes/app-recipe.md"
        recipe `shouldSatisfy` T.isInfixOf "[base](/modules/base.md)"
        recipe `shouldNotSatisfy` T.isInfixOf "[app-recipe](/recipes/app-recipe.md)"
        recipe `shouldSatisfy` T.isInfixOf "inherited declarations are not expanded"
        recipe `shouldSatisfy` T.isInfixOf "(JSON string)"
        blueprint <- page "blueprints/app-blueprint.md"
        blueprint `shouldNotSatisfy` T.isInfixOf "](/modules/base.md)"
        blueprint `shouldSatisfy` T.isInfixOf "No additional tools declared (explicit empty allowlist)"
        blueprint `shouldSatisfy` T.isInfixOf "mode: `reserved` (reserved; ignored)"
        blueprint `shouldSatisfy` T.isInfixOf "````text\nFirst line\n```text\nsecond | line\n````"
        judgement <- page "judgements/docs-review.md"
        mapM_
          (\text -> judgement `shouldSatisfy` T.isInfixOf text)
          [ "Yes means: `Documentation is stale`",
            "No means: `Documentation matches`",
            "Category explanation",
            "useGate = false (disabled)",
            "passAt = 0.05, blockAt = 0.9",
            "maxFileBytes: 262144",
            "maxChunkBytes: 49152",
            "maxChunks: 16",
            "maxAttempts: 3",
            "timeoutSeconds: 120",
            "maxFindings: 20",
            "not calibrated risk estimates"
          ]
        validateWritten outDir

    it "preserves every existing output file on invalid input and rejecting profiles even with force" $
      withSystemTempDirectory "seihou-docs-preservation" $ \tmpDir -> do
        let registryDir = tmpDir </> "registry"
            outDir = tmpDir </> "out"
            profilePath = tmpDir </> "reject.dhall"
        writeFixtureRegistry registryDir
        runDocs (docsOpts registryDir outDir False) `shouldReturn` Right ("Wrote 3 concepts to " <> T.pack outDir)
        originalOutput <- snapshot outDir
        TIO.writeFile profilePath demandingProfile
        rejected <- runDocs (docsOpts registryDir outDir True & #profile ?~ profilePath)
        rejected `shouldSatisfy` either (T.isInfixOf "missing required field stale_after") (const False)
        snapshot outDir `shouldReturn` originalOutput
        TIO.writeFile (registryDir </> "modules/base/module.dhall") "{ invalid"
        invalid <- runDocs (docsOpts registryDir outDir True)
        invalid `shouldSatisfy` either (T.isInfixOf "failed to load registry entry base") (const False)
        snapshot outDir `shouldReturn` originalOutput

    it "accepts an older custom descriptor through OKF's compatibility decoder" $
      withSystemTempDirectory "seihou-old-profile" $ \tmpDir -> do
        let registryDir = tmpDir </> "registry"
            outDir = tmpDir </> "out"
            profilePath = tmpDir </> "legacy.dhall"
        writeFixtureRegistry registryDir
        TIO.writeFile profilePath "{name=\"legacy\",okfVersion=\"0.1\",allowUnknownTypes=True,idField=None Text,frontmatter={required=[] : List Text,recommended=[] : List Text},types=[] : List {type : Text,pathPattern : Optional Text,resourceScheme : Optional Text,requireSchemaSection : Bool,schemaColumns : List Text,idPrefix : Optional Text}}"
        runDocs (docsOpts registryDir outDir False & #profile ?~ profilePath)
          `shouldReturn` Right ("Wrote 3 concepts to " <> T.pack outDir)

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

snapshot :: FilePath -> IO [(FilePath, T.Text)]
snapshot root = do
  names <- sort <$> listDirectory root
  fmap concat $ forM names $ \name -> do
    let path = root </> name
    directory <- doesDirectoryExist path
    if directory
      then map (\(relative, bytes) -> (name </> relative, bytes)) <$> snapshot path
      else do
        bytes <- TIO.readFile path
        pure [(name, bytes)]

validateWritten :: FilePath -> IO ()
validateWritten outDir = do
  Right concepts <- Okf.walkBundle outDir
  Okf.validateBundle
    Okf.StrictAuthoring
    (Okf.VersionDeclared Okf.supportedOkfVersion)
    (Okf.bundleInventoryOfConcepts concepts)
    concepts
    `shouldBe` []
  profileSpec <- Dhall.inputFile Dhall.auto (outDir </> "profile.dhall") :: IO Profile.ProfileSpec
  -- A current descriptor must use the current decoder, not depend on a frozen
  -- fallback. Its new nested policy/constraint fields survive decoding.
  profileSpec ^. #okfVersion `shouldBe` "0.2"
  Right compiled <- pure (Profile.compileProfile profileSpec)
  Profile.validateProfile Okf.StrictAuthoring compiled concepts `shouldBe` []

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
