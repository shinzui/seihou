{-# LANGUAGE OverloadedStrings #-}

module Seihou.CLI.Registry.SyncSpec (tests) where

import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.Registry.Sync
  ( SyncAction (..),
    SyncOutcome (..),
    SyncVersionsOpts (..),
    renderSyncReport,
    runSync,
  )
import Seihou.Core.Registry
  ( Registry (..),
    RegistryEntry (..),
    SyncDiff (..),
    SyncReport (..),
    SyncStatus (..),
  )
import Seihou.Dhall.Eval (evalRegistryFromFile)
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.CLI.Registry.Sync" spec

spec :: Spec
spec = do
  describe "runSync" $ do
    it "rewrites the registry with each module's on-disk version" $ do
      withFixture $ \dir -> do
        outcome <-
          runSync
            SyncVersionsOpts
              { syncVersionsDir = Just dir,
                syncVersionsDryRun = False,
                syncVersionsCheck = False
              }
        case outcome of
          SyncFailure msg ->
            expectationFailure ("expected SyncSuccess, got failure: " <> T.unpack msg)
          SyncSuccess _ action -> action `shouldBe` Wrote
        reloaded <- evalRegistryFromFile (dir </> "seihou-registry.dhall")
        case reloaded of
          Left err -> expectationFailure ("failed to reload: " <> show err)
          Right reg -> do
            map (.version) reg.modules `shouldBe` [Just "2.0.0", Just "2.0.0"]

    it "leaves the file untouched under --dry-run" $ do
      withFixture $ \dir -> do
        before <- TIO.readFile (dir </> "seihou-registry.dhall")
        outcome <-
          runSync
            SyncVersionsOpts
              { syncVersionsDir = Just dir,
                syncVersionsDryRun = True,
                syncVersionsCheck = False
              }
        case outcome of
          SyncSuccess _ WouldWrite -> pure ()
          other -> expectationFailure ("expected WouldWrite, got " <> show other)
        after <- TIO.readFile (dir </> "seihou-registry.dhall")
        after `shouldBe` before

    it "leaves the file untouched and reports drift under --check" $ do
      withFixture $ \dir -> do
        before <- TIO.readFile (dir </> "seihou-registry.dhall")
        outcome <-
          runSync
            SyncVersionsOpts
              { syncVersionsDir = Just dir,
                syncVersionsDryRun = False,
                syncVersionsCheck = True
              }
        case outcome of
          SyncSuccess report Checked -> do
            -- first entry missing, second entry stale
            map (.diffStatus) report.syncDiffs
              `shouldBe` [SyncMissing, SyncStale "2.0.0"]
          other -> expectationFailure ("expected Checked, got " <> show other)
        after <- TIO.readFile (dir </> "seihou-registry.dhall")
        after `shouldBe` before

    it "fails when the target directory has no seihou-registry.dhall" $ do
      withSystemTempDirectory "seihou-sync-empty" $ \dir -> do
        outcome <-
          runSync
            SyncVersionsOpts
              { syncVersionsDir = Just dir,
                syncVersionsDryRun = False,
                syncVersionsCheck = False
              }
        case outcome of
          SyncFailure _ -> pure ()
          SyncSuccess {} -> expectationFailure "expected SyncFailure for empty directory"

    it "rewrites a blueprint entry's on-disk version into the registry" $ do
      withBlueprintFixture $ \dir -> do
        outcome <-
          runSync
            SyncVersionsOpts
              { syncVersionsDir = Just dir,
                syncVersionsDryRun = False,
                syncVersionsCheck = False
              }
        case outcome of
          SyncFailure msg -> expectationFailure ("expected success, got: " <> T.unpack msg)
          SyncSuccess _ action -> action `shouldBe` Wrote
        reloaded <- evalRegistryFromFile (dir </> "seihou-registry.dhall")
        case reloaded of
          Left err -> expectationFailure ("failed to reload: " <> show err)
          Right reg -> map (.version) reg.blueprints `shouldBe` [Just "0.2.0"]

    it "renderSyncReport prefixes blueprint rows with blueprints." $ do
      withBlueprintFixture $ \dir -> do
        outcome <-
          runSync
            SyncVersionsOpts
              { syncVersionsDir = Just dir,
                syncVersionsDryRun = True,
                syncVersionsCheck = False
              }
        case outcome of
          SyncSuccess report _ -> do
            let rendered = renderSyncReport report
            T.isInfixOf "blueprints.payments-service:" rendered `shouldBe` True
          other -> expectationFailure ("expected SyncSuccess, got " <> show other)

    it "rewrites a prompt entry's on-disk version into the registry" $ do
      withPromptFixture $ \dir -> do
        outcome <-
          runSync
            SyncVersionsOpts
              { syncVersionsDir = Just dir,
                syncVersionsDryRun = False,
                syncVersionsCheck = False
              }
        case outcome of
          SyncFailure msg -> expectationFailure ("expected success, got: " <> T.unpack msg)
          SyncSuccess _ action -> action `shouldBe` Wrote
        reloaded <- evalRegistryFromFile (dir </> "seihou-registry.dhall")
        case reloaded of
          Left err -> expectationFailure ("failed to reload: " <> show err)
          Right reg -> map (.version) reg.prompts `shouldBe` [Just "0.2.0"]

    it "renderSyncReport prefixes prompt rows with prompts." $ do
      withPromptFixture $ \dir -> do
        outcome <-
          runSync
            SyncVersionsOpts
              { syncVersionsDir = Just dir,
                syncVersionsDryRun = True,
                syncVersionsCheck = False
              }
        case outcome of
          SyncSuccess report _ -> do
            let rendered = renderSyncReport report
            T.isInfixOf "prompts.review-changes:" rendered `shouldBe` True
          other -> expectationFailure ("expected SyncSuccess, got " <> show other)

-- | Build a temp registry repo with:
--
--   * modules/alpha/module.dhall declaring version = Some "2.0.0"
--   * modules/beta/module.dhall  declaring version = Some "2.0.0"
--   * seihou-registry.dhall listing both, with the first unversioned and the
--     second stuck at an old "1.0.0"
withFixture :: (FilePath -> IO ()) -> IO ()
withFixture action = withSystemTempDirectory "seihou-sync-fixture" $ \dir -> do
  createDirectoryIfMissing True (dir </> "modules" </> "alpha")
  createDirectoryIfMissing True (dir </> "modules" </> "beta")
  writeModuleDhall (dir </> "modules" </> "alpha" </> "module.dhall") "alpha" "2.0.0"
  writeModuleDhall (dir </> "modules" </> "beta" </> "module.dhall") "beta" "2.0.0"
  TIO.writeFile (dir </> "seihou-registry.dhall") (registryDhall "alpha" Nothing "beta" (Just "1.0.0"))
  action dir

-- | Build a temp registry repo with a single blueprint entry whose
-- on-disk @blueprint.dhall@ declares @version = "0.2.0"@ but the
-- @seihou-registry.dhall@ pins @"0.1.0"@.
withBlueprintFixture :: (FilePath -> IO ()) -> IO ()
withBlueprintFixture action = withSystemTempDirectory "seihou-sync-bp" $ \dir -> do
  createDirectoryIfMissing True (dir </> "blueprints" </> "payments-service")
  writeBlueprintDhall (dir </> "blueprints" </> "payments-service" </> "blueprint.dhall") "payments-service" "0.2.0"
  TIO.writeFile (dir </> "seihou-registry.dhall") (registryWithBlueprint "payments-service" (Just "0.1.0"))
  action dir

-- | Build a temp registry repo with a single prompt entry whose on-disk
-- @prompt.dhall@ declares @version = "0.2.0"@ but the registry pins @"0.1.0"@.
withPromptFixture :: (FilePath -> IO ()) -> IO ()
withPromptFixture action = withSystemTempDirectory "seihou-sync-prompt" $ \dir -> do
  createDirectoryIfMissing True (dir </> "prompts" </> "review-changes")
  writePromptDhall (dir </> "prompts" </> "review-changes" </> "prompt.dhall") "review-changes" "0.2.0"
  TIO.writeFile (dir </> "seihou-registry.dhall") (registryWithPrompt "review-changes" (Just "0.1.0"))
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

registryWithBlueprint :: Text -> Maybe Text -> Text
registryWithBlueprint n v =
  T.unlines
    [ "{ repoName = \"Test\"",
      ", repoDescription = None Text",
      ", modules = [] : List { name : Text, version : Optional Text, path : Text, description : Optional Text, tags : List Text }",
      ", recipes = [] : List { name : Text, version : Optional Text, path : Text, description : Optional Text, tags : List Text }",
      ", blueprints =",
      "  [ { name = \"" <> n <> "\"",
      "    , version = " <> optVersion v,
      "    , path = \"blueprints/" <> n <> "\"",
      "    , description = None Text",
      "    , tags = [] : List Text",
      "    }",
      "  ]",
      "}"
    ]

writePromptDhall :: FilePath -> Text -> Text -> IO ()
writePromptDhall path name ver =
  TIO.writeFile
    path
    ( T.unlines
        [ "{ name = \"" <> name <> "\"",
          ", version = Some \"" <> ver <> "\"",
          ", description = None Text",
          ", prompt = \"Review the current changes.\"",
          ", vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }",
          ", prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }",
          ", commandVars = [] : List { name : Text, run : Text, workDir : Optional Text, when : Optional Text, trim : Bool, maxBytes : Optional Natural }",
          ", files = [] : List { src : Text, description : Optional Text }",
          ", allowedTools = None (List Text)",
          ", tags = [] : List Text",
          ", launch = None { provider : Optional Text, mode : Optional Text, model : Optional Text }",
          "}"
        ]
    )

registryWithPrompt :: Text -> Maybe Text -> Text
registryWithPrompt n v =
  T.unlines
    [ "{ repoName = \"Test\"",
      ", repoDescription = None Text",
      ", modules = [] : List { name : Text, version : Optional Text, path : Text, description : Optional Text, tags : List Text }",
      ", recipes = [] : List { name : Text, version : Optional Text, path : Text, description : Optional Text, tags : List Text }",
      ", blueprints = [] : List { name : Text, version : Optional Text, path : Text, description : Optional Text, tags : List Text }",
      ", prompts =",
      "  [ { name = \"" <> n <> "\"",
      "    , version = " <> optVersion v,
      "    , path = \"prompts/" <> n <> "\"",
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
