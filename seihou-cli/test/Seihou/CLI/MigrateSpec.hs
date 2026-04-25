module Seihou.CLI.MigrateSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Time (UTCTime, defaultTimeLocale, parseTimeOrError)
import Seihou.CLI.Migrate
  ( MigrateError (..),
    MigrateOpts (..),
    MigrateResult (..),
    runMigrate,
  )
import Seihou.Core.Types
  ( AppliedModule (..),
    FileRecord (..),
    Manifest (..),
    ModuleName (..),
    Strategy (..),
    emptyParentVars,
  )
import Seihou.Manifest.Hash (hashContent)
import Seihou.Manifest.Types (emptyManifest)
import System.Directory (createDirectoryIfMissing, doesFileExist, withCurrentDirectory)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.CLI.Migrate" spec

-- ----------------------------------------------------------------------------
-- Fixture helpers
-- ----------------------------------------------------------------------------

modName :: ModuleName
modName = ModuleName "demo"

fixedTime :: UTCTime
fixedTime =
  parseTimeOrError
    True
    defaultTimeLocale
    "%Y-%m-%dT%H:%M:%SZ"
    "2026-04-01T10:00:00Z"

-- | Write a minimal but parseable @module.dhall@ for an installed
-- fixture module. The @migrations@ field is supplied as a Dhall literal
-- so we exercise the full eval-and-decode path through the CLI handler.
writeInstalledModule :: FilePath -> Text -> Text -> IO ()
writeInstalledModule dir version migrationsLit = do
  createDirectoryIfMissing True dir
  TIO.writeFile (dir </> "module.dhall") body
  where
    body =
      T.unlines
        [ "{ name = \"demo\"",
          ", version = Some \"" <> version <> "\"",
          ", description = None Text",
          ", vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }",
          ", exports = [] : List { var : Text, alias : Optional Text }",
          ", prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }",
          ", steps = [] : List { strategy : Text, src : Text, dest : Text, when : Optional Text, patch : Optional Text }",
          ", commands = [] : List { run : Text, workDir : Optional Text, when : Optional Text }",
          ", dependencies = [] : List { module : Text, vars : List { name : Text, value : Text } }",
          ", removal = None { steps : List { action : Text, dest : Text, src : Optional Text }, commands : List { run : Text, workDir : Optional Text, when : Optional Text } }",
          ", migrations = " <> migrationsLit,
          "}"
        ]

-- | A migrations Dhall literal that moves @app/Main.hs@ to
-- @src/Main.hs@ between 1.0.0 and 2.0.0.
moveAppToSrcLit :: Text
moveAppToSrcLit =
  T.unlines
    [ "[ { from = \"1.0.0\"",
      "  , to = \"2.0.0\"",
      "  , ops =",
      "      [ (< MoveFile : { src : Text, dest : Text } | MoveDir : { src : Text, dest : Text } | DeleteFile : { path : Text } | DeleteDir : { path : Text } | RunCommand : { run : Text, workDir : Optional Text } >).MoveFile { src = \"app/Main.hs\", dest = \"src/Main.hs\" }",
      "      ]",
      "  }",
      "]"
    ]

-- | Empty migrations literal (no-op migration list).
emptyMigrationsLit :: Text
emptyMigrationsLit =
  "[] : List { from : Text, to : Text, ops : List < MoveFile : { src : Text, dest : Text } | MoveDir : { src : Text, dest : Text } | DeleteFile : { path : Text } | DeleteDir : { path : Text } | RunCommand : { run : Text, workDir : Optional Text } > }"

-- | Build a manifest with one applied module recording @from@ as the
-- current version, and one tracked file with the given content.
mkManifest :: Text -> FilePath -> [(FilePath, Text)] -> Manifest
mkManifest version installedDir entries =
  (emptyManifest fixedTime)
    { modules =
        [ AppliedModule
            { name = modName,
              parentVars = emptyParentVars,
              source = installedDir,
              moduleVersion = Just version,
              appliedAt = fixedTime,
              removal = Nothing
            }
        ],
      files =
        Map.fromList
          [ ( path,
              FileRecord
                { hash = hashContent content,
                  moduleName = modName,
                  strategy = Template,
                  generatedAt = fixedTime
                }
            )
          | (path, content) <- entries
          ]
    }

defaultOpts :: MigrateOpts
defaultOpts =
  MigrateOpts
    { migrateModule = modName,
      migrateTo = Nothing,
      migrateDryRun = False,
      migrateForce = False,
      migrateJson = False,
      migrateVerbose = False
    }

-- ----------------------------------------------------------------------------
-- Spec
-- ----------------------------------------------------------------------------

spec :: Spec
spec = do
  describe "runMigrate" $ do
    it "errors when the module isn't applied" $
      withSystemTempDirectory "seihou-migrate-cli" $ \dir -> do
        let installed = dir </> "installed-demo"
        writeInstalledModule installed "2.0.0" emptyMigrationsLit
        let manifest = (emptyManifest fixedTime) {modules = []}
        result <-
          withCurrentDirectory dir $
            runMigrate defaultOpts manifest installed
        case result of
          Left (MigrateModuleNotApplied n) -> n `shouldBe` modName
          other -> expectationFailure ("expected MigrateModuleNotApplied, got: " <> show other)

    it "errors when the manifest has no recorded version for the module" $
      withSystemTempDirectory "seihou-migrate-cli" $ \dir -> do
        let installed = dir </> "installed-demo"
        writeInstalledModule installed "2.0.0" emptyMigrationsLit
        let manifest =
              (emptyManifest fixedTime)
                { modules =
                    [ AppliedModule
                        { name = modName,
                          parentVars = emptyParentVars,
                          source = installed,
                          moduleVersion = Nothing,
                          appliedAt = fixedTime,
                          removal = Nothing
                        }
                    ]
                }
        result <-
          withCurrentDirectory dir $
            runMigrate defaultOpts manifest installed
        case result of
          Left (MigrateNoRecordedVersion n) -> n `shouldBe` modName
          other -> expectationFailure ("expected MigrateNoRecordedVersion, got: " <> show other)

    it "returns MigrateNoOp when manifest version equals installed version" $
      withSystemTempDirectory "seihou-migrate-cli" $ \dir -> do
        let installed = dir </> "installed-demo"
        writeInstalledModule installed "1.0.0" emptyMigrationsLit
        let manifest = mkManifest "1.0.0" installed []
        result <-
          withCurrentDirectory dir $
            runMigrate defaultOpts manifest installed
        case result of
          Right (MigrateNoOp _) -> pure ()
          other -> expectationFailure ("expected MigrateNoOp, got: " <> show other)

    it "returns a dry-run plan without touching disk" $
      withSystemTempDirectory "seihou-migrate-cli" $ \dir -> do
        let installed = dir </> "installed-demo"
        writeInstalledModule installed "2.0.0" moveAppToSrcLit
        createDirectoryIfMissing True (dir </> "app")
        TIO.writeFile (dir </> "app" </> "Main.hs") "module Main where"
        let manifest = mkManifest "1.0.0" installed [("app/Main.hs", "module Main where")]
            opts = defaultOpts {migrateDryRun = True}
        result <-
          withCurrentDirectory dir $
            runMigrate opts manifest installed
        case result of
          Right (MigrateDryRunOK _plan) -> do
            -- Disk untouched
            doesFileExist (dir </> "app" </> "Main.hs") `shouldReturn` True
            doesFileExist (dir </> "src" </> "Main.hs") `shouldReturn` False
          other -> expectationFailure ("expected MigrateDryRunOK, got: " <> show other)

    it "executes the plan and returns the rewritten manifest" $
      withSystemTempDirectory "seihou-migrate-cli" $ \dir -> do
        let installed = dir </> "installed-demo"
        writeInstalledModule installed "2.0.0" moveAppToSrcLit
        createDirectoryIfMissing True (dir </> "app")
        TIO.writeFile (dir </> "app" </> "Main.hs") "module Main where"
        let manifest = mkManifest "1.0.0" installed [("app/Main.hs", "module Main where")]
        result <-
          withCurrentDirectory dir $
            runMigrate defaultOpts manifest installed
        case result of
          Right (MigrateApplied _plan manifest') -> do
            Map.member "src/Main.hs" manifest'.files `shouldBe` True
            Map.member "app/Main.hs" manifest'.files `shouldBe` False
            (head manifest'.modules).moduleVersion `shouldBe` Just "2.0.0"
            doesFileExist (dir </> "src" </> "Main.hs") `shouldReturn` True
            doesFileExist (dir </> "app" </> "Main.hs") `shouldReturn` False
          other -> expectationFailure ("expected MigrateApplied, got: " <> show other)

    it "refuses to execute without --force when a tracked file has been modified" $
      withSystemTempDirectory "seihou-migrate-cli" $ \dir -> do
        let installed = dir </> "installed-demo"
        writeInstalledModule installed "2.0.0" moveAppToSrcLit
        createDirectoryIfMissing True (dir </> "app")
        -- Manifest hash recorded for "original"; user edits the file.
        TIO.writeFile (dir </> "app" </> "Main.hs") "user-edited"
        let manifest = mkManifest "1.0.0" installed [("app/Main.hs", "original")]
        result <-
          withCurrentDirectory dir $
            runMigrate defaultOpts manifest installed
        case result of
          Left (MigrateExecFailed _) -> do
            -- Disk unchanged: src not yet created.
            doesFileExist (dir </> "src" </> "Main.hs") `shouldReturn` False
          other -> expectationFailure ("expected MigrateExecFailed, got: " <> show other)

    it "executes through a conflict when --force is set" $
      withSystemTempDirectory "seihou-migrate-cli" $ \dir -> do
        let installed = dir </> "installed-demo"
        writeInstalledModule installed "2.0.0" moveAppToSrcLit
        createDirectoryIfMissing True (dir </> "app")
        TIO.writeFile (dir </> "app" </> "Main.hs") "user-edited"
        let manifest = mkManifest "1.0.0" installed [("app/Main.hs", "original")]
            opts = defaultOpts {migrateForce = True}
        result <-
          withCurrentDirectory dir $
            runMigrate opts manifest installed
        case result of
          Right (MigrateApplied _ manifest') -> do
            doesFileExist (dir </> "src" </> "Main.hs") `shouldReturn` True
            doesFileExist (dir </> "app" </> "Main.hs") `shouldReturn` False
            Map.member "src/Main.hs" manifest'.files `shouldBe` True
          other -> expectationFailure ("expected MigrateApplied, got: " <> show other)

    it "respects --to to stop at an intermediate version" $
      withSystemTempDirectory "seihou-migrate-cli" $ \dir -> do
        -- Two migrations: 1.0.0 → 1.5.0, 1.5.0 → 2.0.0. Test that --to
        -- 1.5.0 stops one step in.
        let installed = dir </> "installed-demo"
            twoStepLit =
              T.unlines
                [ "[ { from = \"1.0.0\"",
                  "  , to = \"1.5.0\"",
                  "  , ops =",
                  "      [ (< MoveFile : { src : Text, dest : Text } | MoveDir : { src : Text, dest : Text } | DeleteFile : { path : Text } | DeleteDir : { path : Text } | RunCommand : { run : Text, workDir : Optional Text } >).MoveFile { src = \"a.txt\", dest = \"b.txt\" }",
                  "      ]",
                  "  }",
                  ", { from = \"1.5.0\"",
                  "  , to = \"2.0.0\"",
                  "  , ops =",
                  "      [ (< MoveFile : { src : Text, dest : Text } | MoveDir : { src : Text, dest : Text } | DeleteFile : { path : Text } | DeleteDir : { path : Text } | RunCommand : { run : Text, workDir : Optional Text } >).MoveFile { src = \"b.txt\", dest = \"c.txt\" }",
                  "      ]",
                  "  }",
                  "]"
                ]
        writeInstalledModule installed "2.0.0" twoStepLit
        TIO.writeFile (dir </> "a.txt") "x"
        let manifest = mkManifest "1.0.0" installed [("a.txt", "x")]
            opts = defaultOpts {migrateTo = Just "1.5.0"}
        result <-
          withCurrentDirectory dir $
            runMigrate opts manifest installed
        case result of
          Right (MigrateApplied _ manifest') -> do
            -- After 1.0.0 → 1.5.0, the file is at b.txt, not c.txt.
            Map.member "b.txt" manifest'.files `shouldBe` True
            Map.member "c.txt" manifest'.files `shouldBe` False
            (head manifest'.modules).moduleVersion `shouldBe` Just "1.5.0"
            doesFileExist (dir </> "b.txt") `shouldReturn` True
            doesFileExist (dir </> "c.txt") `shouldReturn` False
          other -> expectationFailure ("expected MigrateApplied, got: " <> show other)
