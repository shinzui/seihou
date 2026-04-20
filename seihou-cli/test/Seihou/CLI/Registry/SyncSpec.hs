{-# LANGUAGE OverloadedStrings #-}

module Seihou.CLI.Registry.SyncSpec (tests) where

import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.Registry.Sync
  ( SyncAction (..),
    SyncOutcome (..),
    SyncVersionsOpts (..),
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
