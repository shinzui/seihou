module Seihou.CLI.MigrateSpec (tests) where

import Control.Exception (bracket_)
import Data.Aeson (encode, object, (.=))
import Data.ByteString.Lazy qualified as LBS
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Time (UTCTime, defaultTimeLocale, parseTimeOrError)
import Effectful (runEff)
import Seihou.CLI.Migrate
  ( MigrateError (..),
    MigrateOpts (..),
    MigrateResult (..),
    commitMigratedFiles,
    runMigrate,
  )
import Seihou.Core.Migration (MigrationPlan (..))
import Seihou.Core.Types
  ( AppliedModule (..),
    FileRecord (..),
    Manifest (..),
    ModuleName (..),
    Strategy (..),
    emptyParentVars,
  )
import Seihou.Core.Version (renderVersion)
import Seihou.Effect.FilesystemInterp (runFilesystem)
import Seihou.Effect.ManifestStore (writeManifest)
import Seihou.Effect.ManifestStoreInterp (runManifestStore)
import Seihou.Engine.Migrate (ExecutedMigrationPlan (..))
import Seihou.Manifest.Hash (hashContent)
import Seihou.Manifest.Types (emptyManifest)
import System.Directory (createDirectoryIfMissing, doesFileExist, withCurrentDirectory)
import System.Environment (lookupEnv, setEnv, unsetEnv)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (readProcessWithExitCode)
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

moveOldToNewLit :: Text
moveOldToNewLit =
  T.unlines
    [ "[ { from = \"1.0.0\"",
      "  , to = \"2.0.0\"",
      "  , ops =",
      "      [ (< MoveFile : { src : Text, dest : Text } | MoveDir : { src : Text, dest : Text } | DeleteFile : { path : Text } | DeleteDir : { path : Text } | RunCommand : { run : Text, workDir : Optional Text } >).MoveFile { src = \"old.txt\", dest = \"new.txt\" }",
      "      ]",
      "  }",
      "]"
    ]

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

emptyMigrationsLit :: Text
emptyMigrationsLit =
  "[] : List { from : Text, to : Text, ops : List < MoveFile : { src : Text, dest : Text } | MoveDir : { src : Text, dest : Text } | DeleteFile : { path : Text } | DeleteDir : { path : Text } | RunCommand : { run : Text, workDir : Optional Text } > }"

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
      migrateVerbose = False,
      migrateNoFetch = True,
      migrateCommit = False,
      migrateCommitMessage = Nothing
    }

-- ----------------------------------------------------------------------------
-- Fetch-path fixture
-- ----------------------------------------------------------------------------

data FetchFixture = FetchFixture
  { modName :: Text,
    remoteDir :: FilePath,
    installedDir :: FilePath,
    projectDir :: FilePath
  }

withFetchFixture :: Text -> Text -> Text -> (FetchFixture -> IO ()) -> IO ()
withFetchFixture installedVer remoteVer migrationsLit action =
  withSystemTempDirectory "seihou-migrate-fetch" $ \tmp -> do
    let xdgHome = tmp </> "xdg"
        remoteDir = tmp </> "remote"
        projectDir = tmp </> "project"
        nameStr = "demo"
        installedDir = xdgHome </> "seihou" </> "installed" </> nameStr
        fix =
          FetchFixture
            { modName = T.pack nameStr,
              remoteDir = remoteDir,
              installedDir = installedDir,
              projectDir = projectDir
            }

    createDirectoryIfMissing True remoteDir
    createDirectoryIfMissing True projectDir
    createDirectoryIfMissing True installedDir

    writeInstalledModule remoteDir remoteVer migrationsLit
    initRemoteRepo remoteDir

    writeInstalledModule installedDir installedVer emptyMigrationsLit
    writeOriginJson installedDir (T.pack remoteDir)

    withSavedEnv "XDG_CONFIG_HOME" (Just xdgHome) $
      withSavedEnv "GIT_ALLOW_PROTOCOL" (Just "file") $
        action fix

initRemoteRepo :: FilePath -> IO ()
initRemoteRepo dir = do
  run "git" ["init", "--quiet", "--initial-branch=main", dir]
  run "git" ["-C", dir, "config", "user.email", "test@example.com"]
  run "git" ["-C", dir, "config", "user.name", "Test"]
  run "git" ["-C", dir, "config", "commit.gpgsign", "false"]
  run "git" ["-C", dir, "add", "."]
  run "git" ["-C", dir, "commit", "--quiet", "--no-verify", "-m", "fixture"]
  where
    run cmd args = do
      (code, _out, err) <- readProcessWithExitCode cmd args ""
      case code of
        ExitSuccess -> pure ()
        ExitFailure n ->
          expectationFailure
            ( cmd
                <> " "
                <> show args
                <> " exited with "
                <> show n
                <> ":\n"
                <> err
            )

initProjectRepo :: FilePath -> IO ()
initProjectRepo dir = do
  run "git" ["init", "--quiet", "--initial-branch=main", dir]
  run "git" ["-C", dir, "config", "user.email", "test@example.com"]
  run "git" ["-C", dir, "config", "user.name", "Test"]
  run "git" ["-C", dir, "config", "commit.gpgsign", "false"]
  run "git" ["-C", dir, "add", "."]
  run "git" ["-C", dir, "commit", "--quiet", "--no-verify", "-m", "baseline"]
  where
    run cmd args = do
      (code, _out, err) <- readProcessWithExitCode cmd args ""
      case code of
        ExitSuccess -> pure ()
        ExitFailure n ->
          expectationFailure
            ( cmd
                <> " "
                <> show args
                <> " exited with "
                <> show n
                <> ":\n"
                <> err
            )

writeOriginJson :: FilePath -> Text -> IO ()
writeOriginJson installedDir sourceUrl = do
  let payload =
        object
          [ "sourceUrl" .= sourceUrl,
            "repoName" .= (Nothing :: Maybe Text),
            "version" .= (Nothing :: Maybe Text)
          ]
  LBS.writeFile (installedDir </> ".seihou-origin.json") (encode payload)

mkManifestAt :: FetchFixture -> Text -> [(FilePath, Text)] -> Manifest
mkManifestAt fix version entries =
  (emptyManifest fixedTime)
    { modules =
        [ AppliedModule
            { name = ModuleName fix.modName,
              parentVars = emptyParentVars,
              source = fix.installedDir,
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
                  moduleName = ModuleName fix.modName,
                  strategy = Template,
                  generatedAt = fixedTime
                }
            )
          | (path, content) <- entries
          ]
    }

withSavedEnv :: String -> Maybe String -> IO () -> IO ()
withSavedEnv key newVal action = do
  prev <- lookupEnv key
  let setNew = case newVal of
        Just v -> setEnv key v
        Nothing -> unsetEnv key
      restore = case prev of
        Just v -> setEnv key v
        Nothing -> unsetEnv key
  bracket_ setNew restore action

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
          Right (MigrateDryRunOK _plan _from _to) -> do
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
          Right (MigrateApplied _plan manifest' fromV toV) -> do
            renderVersion fromV `shouldBe` "1.0.0"
            renderVersion toV `shouldBe` "2.0.0"
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
        TIO.writeFile (dir </> "app" </> "Main.hs") "user-edited"
        let manifest = mkManifest "1.0.0" installed [("app/Main.hs", "original")]
        result <-
          withCurrentDirectory dir $
            runMigrate defaultOpts manifest installed
        case result of
          Left (MigrateExecFailed _) ->
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
          Right (MigrateApplied _ manifest' _ _) -> do
            doesFileExist (dir </> "src" </> "Main.hs") `shouldReturn` True
            doesFileExist (dir </> "app" </> "Main.hs") `shouldReturn` False
            Map.member "src/Main.hs" manifest'.files `shouldBe` True
          other -> expectationFailure ("expected MigrateApplied, got: " <> show other)

    -- ------------------------------------------------------------------
    -- Fetch-path tests (EP-2): clone source repo, refresh installed
    -- copy, apply chain in one shot.
    -- ------------------------------------------------------------------
    it "fetches a newer remote, refreshes the installed copy, and applies the chain" $
      withFetchFixture "1.0.0" "2.0.0" moveOldToNewLit $ \fix -> do
        TIO.writeFile (fix.projectDir </> "old.txt") "x"
        let manifest = mkManifestAt fix "1.0.0" [("old.txt", "x")]
            opts = (defaultOpts {migrateNoFetch = False}) {migrateModule = ModuleName fix.modName}
        result <-
          withCurrentDirectory fix.projectDir $
            runMigrate opts manifest fix.installedDir
        case result of
          Right (MigrateApplied _ manifest' _ _) -> do
            doesFileExist (fix.projectDir </> "old.txt") `shouldReturn` False
            doesFileExist (fix.projectDir </> "new.txt") `shouldReturn` True
            case manifest'.modules of
              (am : _) -> am.moduleVersion `shouldBe` Just "2.0.0"
              [] -> expectationFailure "manifest has no modules"
            Map.member "new.txt" manifest'.files `shouldBe` True
            Map.member "old.txt" manifest'.files `shouldBe` False
            installedBody <- TIO.readFile (fix.installedDir </> "module.dhall")
            T.isInfixOf "2.0.0" installedBody `shouldBe` True
          other ->
            expectationFailure ("expected MigrateApplied, got: " <> show other)

    it "is a no-op when the remote and installed versions match" $
      withFetchFixture "1.0.0" "1.0.0" emptyMigrationsLit $ \fix -> do
        let manifest = mkManifestAt fix "1.0.0" []
            opts = (defaultOpts {migrateNoFetch = False}) {migrateModule = ModuleName fix.modName}
        result <-
          withCurrentDirectory fix.projectDir $
            runMigrate opts manifest fix.installedDir
        case result of
          Right (MigrateNoOp _) -> pure ()
          other -> expectationFailure ("expected MigrateNoOp, got: " <> show other)

    it "ignores a newer remote when --no-fetch is set" $
      withFetchFixture "1.0.0" "2.0.0" moveOldToNewLit $ \fix -> do
        let manifest = mkManifestAt fix "1.0.0" []
            opts = (defaultOpts {migrateNoFetch = True}) {migrateModule = ModuleName fix.modName}
        result <-
          withCurrentDirectory fix.projectDir $
            runMigrate opts manifest fix.installedDir
        case result of
          Right (MigrateNoOp _) -> pure ()
          other -> expectationFailure ("expected MigrateNoOp, got: " <> show other)

    it "respects --to to stop at an intermediate version" $
      withSystemTempDirectory "seihou-migrate-cli" $ \dir -> do
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
          Right (MigrateApplied _ manifest' _ toV) -> do
            renderVersion toV `shouldBe` "1.5.0"
            Map.member "b.txt" manifest'.files `shouldBe` True
            Map.member "c.txt" manifest'.files `shouldBe` False
            (head manifest'.modules).moduleVersion `shouldBe` Just "1.5.0"
            doesFileExist (dir </> "b.txt") `shouldReturn` True
            doesFileExist (dir </> "c.txt") `shouldReturn` False
          other -> expectationFailure ("expected MigrateApplied, got: " <> show other)

    -- ------------------------------------------------------------------
    -- EP-35: gap-tolerant scenarios.
    --
    -- The window walker applies any in-window declared migrations and
    -- always advances the manifest to the supplied target. There are
    -- no "blocked" / "benign" / "bump-through" outcomes — every
    -- non-trivial run yields MigrateApplied.
    -- ------------------------------------------------------------------

    it "Scenario A: applies a partial-cover plan and lands the manifest at the target" $
      -- User's reported scenario shape: manifest at 1.0.0, installed
      -- declares 3.0.0 with one edge {1.0.0 -> 2.0.0}. The walker picks
      -- the edge, the engine runs its ops, and the manifest advances
      -- to 3.0.0 (the supplied target) in one command.
      withSystemTempDirectory "seihou-migrate-cli" $ \dir -> do
        let installed = dir </> "installed-demo"
        writeInstalledModule installed "3.0.0" moveAppToSrcLit
        createDirectoryIfMissing True (dir </> "app")
        TIO.writeFile (dir </> "app" </> "Main.hs") "module Main where"
        let manifest = mkManifest "1.0.0" installed [("app/Main.hs", "module Main where")]
        result <-
          withCurrentDirectory dir $
            runMigrate defaultOpts manifest installed
        case result of
          Right (MigrateApplied _ manifest' fromV toV) -> do
            renderVersion fromV `shouldBe` "1.0.0"
            renderVersion toV `shouldBe` "3.0.0"
            (head manifest'.modules).moduleVersion `shouldBe` Just "3.0.0"
            Map.member "src/Main.hs" manifest'.files `shouldBe` True
            Map.member "app/Main.hs" manifest'.files `shouldBe` False
            doesFileExist (dir </> "src" </> "Main.hs") `shouldReturn` True
            doesFileExist (dir </> "app" </> "Main.hs") `shouldReturn` False
          other ->
            expectationFailure ("expected MigrateApplied, got: " <> show other)

    it "Scenario B: pure version bump (migrations = []) lands the manifest at the target" $
      withSystemTempDirectory "seihou-migrate-cli" $ \dir -> do
        let installed = dir </> "installed-demo"
        writeInstalledModule installed "0.3.0" emptyMigrationsLit
        let manifest = mkManifest "0.1.3" installed []
        result <-
          withCurrentDirectory dir $
            runMigrate defaultOpts manifest installed
        case result of
          Right (MigrateApplied execPlan manifest' _ toV) -> do
            renderVersion toV `shouldBe` "0.3.0"
            null execPlan.planSource.planSteps `shouldBe` True
            (head manifest'.modules).moduleVersion `shouldBe` Just "0.3.0"
          other -> expectationFailure ("expected MigrateApplied (pure bump), got: " <> show other)

    it "Scenario C: orphan-edge entirely outside the window also lands the manifest at target" $
      -- Same outcome as Scenario B from the user's perspective — the
      -- manifest advances, no ops run. The walker silently skips the
      -- out-of-window edge.
      withSystemTempDirectory "seihou-migrate-cli" $ \dir -> do
        let installed = dir </> "installed-demo"
            orphanEdgeLit =
              T.unlines
                [ "[ { from = \"0.5.0\"",
                  "  , to = \"0.6.0\"",
                  "  , ops = [] : List < MoveFile : { src : Text, dest : Text } | MoveDir : { src : Text, dest : Text } | DeleteFile : { path : Text } | DeleteDir : { path : Text } | RunCommand : { run : Text, workDir : Optional Text } >",
                  "  }",
                  "]"
                ]
        writeInstalledModule installed "0.3.0" orphanEdgeLit
        let manifest = mkManifest "0.1.3" installed []
        result <-
          withCurrentDirectory dir $
            runMigrate defaultOpts manifest installed
        case result of
          Right (MigrateApplied execPlan manifest' _ toV) -> do
            renderVersion toV `shouldBe` "0.3.0"
            null execPlan.planSource.planSteps `shouldBe` True
            (head manifest'.modules).moduleVersion `shouldBe` Just "0.3.0"
          other -> expectationFailure ("expected MigrateApplied (orphan-edge skip), got: " <> show other)

    it "User's two-component fixture: 0.2 -> 0.6 with [{0.2->0.3}, {0.5->0.6}]" $
      -- The literal example from the user's prompt: two declared
      -- migrations, two-component versions, manifest skips the gap and
      -- runs both edges in order.
      withSystemTempDirectory "seihou-migrate-cli" $ \dir -> do
        let installed = dir </> "installed-demo"
            twoEdgesLit =
              T.unlines
                [ "[ { from = \"0.2\"",
                  "  , to = \"0.3\"",
                  "  , ops =",
                  "      [ (< MoveFile : { src : Text, dest : Text } | MoveDir : { src : Text, dest : Text } | DeleteFile : { path : Text } | DeleteDir : { path : Text } | RunCommand : { run : Text, workDir : Optional Text } >).MoveFile { src = \"v2.txt\", dest = \"v3.txt\" }",
                  "      ]",
                  "  }",
                  ", { from = \"0.5\"",
                  "  , to = \"0.6\"",
                  "  , ops =",
                  "      [ (< MoveFile : { src : Text, dest : Text } | MoveDir : { src : Text, dest : Text } | DeleteFile : { path : Text } | DeleteDir : { path : Text } | RunCommand : { run : Text, workDir : Optional Text } >).MoveFile { src = \"v5.txt\", dest = \"v6.txt\" }",
                  "      ]",
                  "  }",
                  "]"
                ]
        writeInstalledModule installed "0.6" twoEdgesLit
        TIO.writeFile (dir </> "v2.txt") "at-v2"
        TIO.writeFile (dir </> "v5.txt") "at-v5"
        let manifest = mkManifest "0.2" installed [("v2.txt", "at-v2"), ("v5.txt", "at-v5")]
        result <-
          withCurrentDirectory dir $
            runMigrate defaultOpts manifest installed
        case result of
          Right (MigrateApplied execPlan manifest' _ toV) -> do
            renderVersion toV `shouldBe` "0.6"
            length execPlan.planSource.planSteps `shouldBe` 2
            (head manifest'.modules).moduleVersion `shouldBe` Just "0.6"
            doesFileExist (dir </> "v3.txt") `shouldReturn` True
            doesFileExist (dir </> "v6.txt") `shouldReturn` True
            doesFileExist (dir </> "v2.txt") `shouldReturn` False
            doesFileExist (dir </> "v5.txt") `shouldReturn` False
          other -> expectationFailure ("expected MigrateApplied (two-edge), got: " <> show other)

    -- ------------------------------------------------------------------
    -- EP-26: --commit / --commit-message auto-commit flags.
    -- ------------------------------------------------------------------

    it "--commit-message stages moved files plus the manifest into a single git commit" $
      withSystemTempDirectory "seihou-migrate-cli" $ \dir -> do
        let installed = dir </> "installed-demo"
            manifestPath = ".seihou" </> "manifest.json"
        writeInstalledModule installed "2.0.0" moveAppToSrcLit
        createDirectoryIfMissing True (dir </> "app")
        TIO.writeFile (dir </> "app" </> "Main.hs") "module Main where"
        let manifest = mkManifest "1.0.0" installed [("app/Main.hs", "module Main where")]
            opts =
              defaultOpts
                { migrateCommit = True,
                  migrateCommitMessage = Just "chore: migrate"
                }
        withCurrentDirectory dir $ do
          createDirectoryIfMissing True (dir </> ".seihou")
          runEff $
            runFilesystem $
              runManifestStore manifestPath $
                writeManifest manifest
          initProjectRepo dir
          result <- runMigrate opts manifest installed
          case result of
            Right (MigrateApplied plan manifest' _ _) -> do
              runEff $
                runFilesystem $
                  runManifestStore manifestPath $
                    writeManifest manifest'
              commitMigratedFiles opts manifestPath plan
              (subjectExit, subject, _) <-
                readProcessWithExitCode "git" ["log", "-1", "--pretty=%s"] ""
              subjectExit `shouldBe` ExitSuccess
              T.strip (T.pack subject) `shouldBe` "chore: migrate"
              (_, names, _) <-
                readProcessWithExitCode
                  "git"
                  ["log", "-1", "--name-only", "--no-renames", "--pretty="]
                  ""
              let touched = filter (not . T.null) (T.lines (T.pack names))
              touched `shouldContain` ["app/Main.hs"]
              touched `shouldContain` ["src/Main.hs"]
              touched `shouldContain` [".seihou/manifest.json"]
            other ->
              expectationFailure ("expected MigrateApplied, got: " <> show other)

    it "--commit outside a git repo is a silent no-op (apply still succeeds)" $
      withSystemTempDirectory "seihou-migrate-cli" $ \dir -> do
        let installed = dir </> "installed-demo"
            manifestPath = ".seihou" </> "manifest.json"
        writeInstalledModule installed "2.0.0" moveAppToSrcLit
        createDirectoryIfMissing True (dir </> "app")
        TIO.writeFile (dir </> "app" </> "Main.hs") "module Main where"
        let manifest = mkManifest "1.0.0" installed [("app/Main.hs", "module Main where")]
            opts = defaultOpts {migrateCommitMessage = Just "chore: migrate"}
        withCurrentDirectory dir $ do
          createDirectoryIfMissing True (dir </> ".seihou")
          result <- runMigrate opts manifest installed
          case result of
            Right (MigrateApplied plan manifest' _ _) -> do
              runEff $
                runFilesystem $
                  runManifestStore manifestPath $
                    writeManifest manifest'
              commitMigratedFiles opts manifestPath plan
              doesFileExist (dir </> "src" </> "Main.hs") `shouldReturn` True
              doesFileExist (dir </> manifestPath) `shouldReturn` True
            other ->
              expectationFailure ("expected MigrateApplied, got: " <> show other)

    it "--commit on a dry-run path returns a dry-run variant (helper is never invoked)" $
      withSystemTempDirectory "seihou-migrate-cli" $ \dir -> do
        let installed = dir </> "installed-demo"
        writeInstalledModule installed "2.0.0" moveAppToSrcLit
        createDirectoryIfMissing True (dir </> "app")
        TIO.writeFile (dir </> "app" </> "Main.hs") "module Main where"
        let manifest = mkManifest "1.0.0" installed [("app/Main.hs", "module Main where")]
            opts =
              defaultOpts
                { migrateDryRun = True,
                  migrateCommit = True,
                  migrateCommitMessage = Just "chore: migrate"
                }
        withCurrentDirectory dir $ do
          initProjectRepo dir
          result <- runMigrate opts manifest installed
          case result of
            Right (MigrateDryRunOK {}) -> pure ()
            other ->
              expectationFailure ("expected MigrateDryRunOK, got: " <> show other)
          (_, before, _) <- readProcessWithExitCode "git" ["rev-list", "--count", "HEAD"] ""
          T.strip (T.pack before) `shouldBe` "1"

    -- ------------------------------------------------------------------
    -- EP-27 / EP-35 M5: fetch-vs-local divergence fallback.
    --
    -- When the cloned remote ships fewer applicable migrations than
    -- the locally installed copy, the planner prefers the local plan.
    -- This guards against a remote that has dropped a migration the
    -- user's installed copy still declares.
    -- ------------------------------------------------------------------

    it "fetch fallback: local declares partial chain, clone has empty list -> local wins" $
      let partialLit =
            T.unlines
              [ "[ { from = \"0.1\"",
                "  , to = \"0.2\"",
                "  , ops =",
                "      [ (< MoveFile : { src : Text, dest : Text } | MoveDir : { src : Text, dest : Text } | DeleteFile : { path : Text } | DeleteDir : { path : Text } | RunCommand : { run : Text, workDir : Optional Text } >).MoveFile { src = \"old.txt\", dest = \"new.txt\" }",
                "      ]",
                "  }",
                "]"
              ]
       in withFetchFixture "0.3" "0.3" emptyMigrationsLit $ \fix -> do
            writeInstalledModule fix.installedDir "0.3" partialLit
            writeOriginJson fix.installedDir (T.pack fix.remoteDir)
            TIO.writeFile (fix.projectDir </> "old.txt") "tracked\n"
            let manifest = mkManifestAt fix "0.1" [("old.txt", "tracked\n")]
                opts = (defaultOpts {migrateNoFetch = False}) {migrateModule = ModuleName fix.modName}
            result <-
              withCurrentDirectory fix.projectDir $
                runMigrate opts manifest fix.installedDir
            case result of
              Right (MigrateApplied execPlan manifest' _ toV) -> do
                renderVersion toV `shouldBe` "0.3"
                length execPlan.planSource.planSteps `shouldBe` 1
                case manifest'.modules of
                  (am : _) -> am.moduleVersion `shouldBe` Just "0.3"
                  [] -> expectationFailure "manifest has no modules"
                doesFileExist (fix.projectDir </> "new.txt") `shouldReturn` True
                doesFileExist (fix.projectDir </> "old.txt") `shouldReturn` False
              other ->
                expectationFailure
                  ("expected MigrateApplied (local fallback), got: " <> show other)

    it "fetch fallback: clone-based plan stands when neither side declares applicable edges" $
      withFetchFixture "0.3" "0.3" emptyMigrationsLit $ \fix -> do
        let manifest = mkManifestAt fix "0.1" []
            opts = (defaultOpts {migrateNoFetch = False}) {migrateModule = ModuleName fix.modName}
        result <-
          withCurrentDirectory fix.projectDir $
            runMigrate opts manifest fix.installedDir
        case result of
          Right (MigrateApplied execPlan manifest' _ toV) -> do
            renderVersion toV `shouldBe` "0.3"
            null execPlan.planSource.planSteps `shouldBe` True
            case manifest'.modules of
              (am : _) -> am.moduleVersion `shouldBe` Just "0.3"
              [] -> expectationFailure "manifest has no modules"
          other ->
            expectationFailure ("expected MigrateApplied (no-op-style bump), got: " <> show other)
