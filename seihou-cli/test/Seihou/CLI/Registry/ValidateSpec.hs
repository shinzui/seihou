{-# LANGUAGE OverloadedStrings #-}

module Seihou.CLI.Registry.ValidateSpec (tests) where

import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.Registry.Validate
  ( ValidateOutcome (..),
    ValidateRegistryOpts (..),
    renderValidationReport,
    runValidate,
  )
import Seihou.Core.Registry
  ( RegistryValidationIssue (..),
    RegistryValidationReport (..),
    SyncDiff (..),
    SyncStatus (..),
  )
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.CLI.Registry.Validate" spec

spec :: Spec
spec = do
  describe "runValidate" $ do
    it "succeeds with no issues for a clean registry" $ do
      withCleanFixture $ \dir -> do
        outcome <- runValidate (ValidateRegistryOpts (Just dir))
        case outcome of
          ValidateOk r -> do
            r.reportIssues `shouldBe` []
            r.reportModuleCount `shouldBe` 2
            r.reportRecipeCount `shouldBe` 0
          other -> expectationFailure ("expected ValidateOk, got " <> show other)

    it "flags both stale and missing version entries" $ do
      withDriftedFixture $ \dir -> do
        outcome <- runValidate (ValidateRegistryOpts (Just dir))
        case outcome of
          ValidateOk r -> do
            let statuses =
                  [ d.diffStatus
                  | VersionMismatch d <- r.reportIssues
                  ]
            statuses `shouldBe` [SyncMissing, SyncStale "2.0.0"]
          other -> expectationFailure ("unexpected outcome: " <> show other)

    it "flags structural issues alongside version issues" $ do
      withMissingFileFixture $ \dir -> do
        outcome <- runValidate (ValidateRegistryOpts (Just dir))
        case outcome of
          ValidateOk r -> do
            let structurals =
                  [ msg
                  | StructuralError msg <- r.reportIssues
                  ]
            any ("missing module.dhall" `T.isInfixOf`) structurals
              `shouldBe` True
          other -> expectationFailure ("unexpected outcome: " <> show other)

    it "fails when there is no registry at the target directory" $ do
      withSystemTempDirectory "seihou-validate-empty" $ \dir -> do
        outcome <- runValidate (ValidateRegistryOpts (Just dir))
        case outcome of
          ValidateFailed _ -> pure ()
          ValidateOk _ ->
            expectationFailure "expected ValidateFailed for empty directory"

    it "flags blueprint version drift with the blueprints. prefix" $ do
      withDriftedBlueprintFixture $ \dir -> do
        outcome <- runValidate (ValidateRegistryOpts (Just dir))
        case outcome of
          ValidateOk r -> do
            let rendered = renderValidationReport r
            T.isInfixOf "blueprints.payments-service:" rendered `shouldBe` True
          other -> expectationFailure ("unexpected outcome: " <> show other)

    it "renders the success summary with module, recipe, and blueprint counts" $ do
      withCleanBlueprintFixture $ \dir -> do
        outcome <- runValidate (ValidateRegistryOpts (Just dir))
        case outcome of
          ValidateOk r -> do
            let rendered = renderValidationReport r
            T.isInfixOf "1 module" rendered `shouldBe` True
            T.isInfixOf "0 recipes" rendered `shouldBe` True
            T.isInfixOf "1 blueprint" rendered `shouldBe` True
            T.isInfixOf "all versions in sync" rendered `shouldBe` True
          other -> expectationFailure ("unexpected outcome: " <> show other)

-- | Two modules at version 1.0.0, registry lists both at version 1.0.0.
withCleanFixture :: (FilePath -> IO ()) -> IO ()
withCleanFixture action = withSystemTempDirectory "seihou-validate-clean" $ \dir -> do
  createDirectoryIfMissing True (dir </> "modules" </> "alpha")
  createDirectoryIfMissing True (dir </> "modules" </> "beta")
  writeModuleDhall (dir </> "modules" </> "alpha" </> "module.dhall") "alpha" "1.0.0"
  writeModuleDhall (dir </> "modules" </> "beta" </> "module.dhall") "beta" "1.0.0"
  TIO.writeFile (dir </> "seihou-registry.dhall") (registryDhall "alpha" (Just "1.0.0") "beta" (Just "1.0.0"))
  action dir

-- | Two modules on disk at 2.0.0; registry lists alpha unversioned and
-- beta stuck at 1.0.0 — produces SyncMissing then SyncStale "2.0.0".
withDriftedFixture :: (FilePath -> IO ()) -> IO ()
withDriftedFixture action = withSystemTempDirectory "seihou-validate-drift" $ \dir -> do
  createDirectoryIfMissing True (dir </> "modules" </> "alpha")
  createDirectoryIfMissing True (dir </> "modules" </> "beta")
  writeModuleDhall (dir </> "modules" </> "alpha" </> "module.dhall") "alpha" "2.0.0"
  writeModuleDhall (dir </> "modules" </> "beta" </> "module.dhall") "beta" "2.0.0"
  TIO.writeFile (dir </> "seihou-registry.dhall") (registryDhall "alpha" Nothing "beta" (Just "1.0.0"))
  action dir

-- | One real module + one entry whose path points at a directory with no
-- module.dhall. Produces a "missing module.dhall" structural error.
withMissingFileFixture :: (FilePath -> IO ()) -> IO ()
withMissingFileFixture action = withSystemTempDirectory "seihou-validate-missing" $ \dir -> do
  createDirectoryIfMissing True (dir </> "modules" </> "alpha")
  writeModuleDhall (dir </> "modules" </> "alpha" </> "module.dhall") "alpha" "1.0.0"
  TIO.writeFile (dir </> "seihou-registry.dhall") (registryDhall "alpha" (Just "1.0.0") "ghost" Nothing)
  action dir

-- | One module + one drifted blueprint. Module's registry version
-- matches its on-disk version (no module drift); the blueprint's
-- registry version is "0.1.0" while its on-disk version is "0.2.0".
withDriftedBlueprintFixture :: (FilePath -> IO ()) -> IO ()
withDriftedBlueprintFixture action = withSystemTempDirectory "seihou-validate-bp-drift" $ \dir -> do
  createDirectoryIfMissing True (dir </> "modules" </> "alpha")
  writeModuleDhall (dir </> "modules" </> "alpha" </> "module.dhall") "alpha" "1.0.0"
  createDirectoryIfMissing True (dir </> "blueprints" </> "payments-service")
  writeBlueprintDhall (dir </> "blueprints" </> "payments-service" </> "blueprint.dhall") "payments-service" "0.2.0"
  TIO.writeFile
    (dir </> "seihou-registry.dhall")
    (mixedRegistry "alpha" (Just "1.0.0") "payments-service" (Just "0.1.0"))
  action dir

-- | One module + one blueprint, all versions matching on disk and in
-- the registry.
withCleanBlueprintFixture :: (FilePath -> IO ()) -> IO ()
withCleanBlueprintFixture action = withSystemTempDirectory "seihou-validate-bp-clean" $ \dir -> do
  createDirectoryIfMissing True (dir </> "modules" </> "alpha")
  writeModuleDhall (dir </> "modules" </> "alpha" </> "module.dhall") "alpha" "1.0.0"
  createDirectoryIfMissing True (dir </> "blueprints" </> "payments-service")
  writeBlueprintDhall (dir </> "blueprints" </> "payments-service" </> "blueprint.dhall") "payments-service" "0.1.0"
  TIO.writeFile
    (dir </> "seihou-registry.dhall")
    (mixedRegistry "alpha" (Just "1.0.0") "payments-service" (Just "0.1.0"))
  action dir

writeBlueprintDhall :: FilePath -> Text -> Text -> IO ()
writeBlueprintDhall path name ver =
  TIO.writeFile
    path
    ( T.unlines
        [ "{ name = \"" <> name <> "\"",
          ", version = Some \"" <> ver <> "\"",
          ", description = None Text",
          ", prompt = \"hi\"",
          ", vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }",
          ", prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }",
          ", baseModules = [] : List { module : Text, vars : List { name : Text, value : Text } }",
          ", files = [] : List { src : Text, description : Optional Text }",
          ", allowedTools = None (List Text)",
          ", tags = [] : List Text",
          "}"
        ]
    )

mixedRegistry :: Text -> Maybe Text -> Text -> Maybe Text -> Text
mixedRegistry modName modVer bpName bpVer =
  T.unlines
    [ "{ repoName = \"Mixed\"",
      ", repoDescription = None Text",
      ", modules =",
      "  [ { name = \"" <> modName <> "\"",
      "    , version = " <> optVersion modVer,
      "    , path = \"modules/" <> modName <> "\"",
      "    , description = None Text",
      "    , tags = [] : List Text",
      "    }",
      "  ]",
      ", blueprints =",
      "  [ { name = \"" <> bpName <> "\"",
      "    , version = " <> optVersion bpVer,
      "    , path = \"blueprints/" <> bpName <> "\"",
      "    , description = None Text",
      "    , tags = [] : List Text",
      "    }",
      "  ]",
      "}"
    ]

writeModuleDhall :: FilePath -> Text -> Text -> IO ()
writeModuleDhall path name ver =
  TIO.writeFile
    path
    ( T.unlines
        [ "{ name = \"" <> name <> "\"",
          ", version = Some \"" <> ver <> "\"",
          ", description = None Text",
          ", vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }",
          ", exports = [] : List { var : Text, alias : Optional Text }",
          ", prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }",
          ", steps = [] : List { strategy : Text, src : Text, dest : Text, when : Optional Text, patch : Optional Text }",
          ", commands = [] : List { run : Text, workDir : Optional Text, when : Optional Text }",
          ", dependencies = [] : List Text",
          ", removal = None { steps : List { action : Text, dest : Text, src : Optional Text }, commands : List { run : Text, workDir : Optional Text, when : Optional Text } }",
          "}"
        ]
    )

registryDhall :: Text -> Maybe Text -> Text -> Maybe Text -> Text
registryDhall n1 v1 n2 v2 =
  T.unlines
    [ "{ repoName = \"Test\"",
      ", repoDescription = None Text",
      ", modules =",
      "  [ { name = \"" <> n1 <> "\"",
      "    , version = " <> optVersion v1,
      "    , path = \"modules/" <> n1 <> "\"",
      "    , description = None Text",
      "    , tags = [] : List Text",
      "    }",
      "  , { name = \"" <> n2 <> "\"",
      "    , version = " <> optVersion v2,
      "    , path = \"modules/" <> n2 <> "\"",
      "    , description = None Text",
      "    , tags = [] : List Text",
      "    }",
      "  ]",
      "}"
    ]

optVersion :: Maybe Text -> Text
optVersion Nothing = "None Text"
optVersion (Just v) = "Some \"" <> v <> "\""
