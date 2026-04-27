{-# LANGUAGE OverloadedStrings #-}

module Seihou.CLI.Registry.ValidateSpec (tests) where

import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.Registry.Validate
  ( ValidateOutcome (..),
    ValidateRegistryOpts (..),
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
