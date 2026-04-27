module Seihou.CLI.MigrateSpec (tests) where

import Control.Exception (bracket_)
import Data.Aeson (encode, object, (.=))
import Data.ByteString.Lazy qualified as LBS
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
import Seihou.Core.Migration (MigrationChain (..))
import Seihou.Core.Types
  ( AppliedModule (..),
    FileRecord (..),
    Manifest (..),
    ModuleName (..),
    Strategy (..),
    emptyParentVars,
  )
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

-- | A migrations Dhall literal that moves @old.txt@ to @new.txt@
-- between 1.0.0 and 2.0.0. Used by the fetch-path tests.
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
      migrateVerbose = False,
      -- Existing local-only tests pass an installed dir directly; they
      -- do not need (and must not perform) network IO.
      migrateNoFetch = True,
      migrateBumpOnly = False,
      migrateCommit = False,
      migrateCommitMessage = Nothing
    }

-- ----------------------------------------------------------------------------
-- Fetch-path fixture: a local "remote" git repo + an installed copy +
-- a project working tree, all wired up so 'runMigrate' with
-- migrateNoFetch=False clones the remote and refreshes the installed
-- copy in place.
-- ----------------------------------------------------------------------------

-- | Bundle of paths the fetch-path tests need to refer to.
data FetchFixture = FetchFixture
  { -- | Module name (matches install dir basename and module.dhall name).
    modName :: Text,
    -- | The "remote" git repo cloneRepo will fetch from.
    remoteDir :: FilePath,
    -- | XDG-derived install dir for the module.
    installedDir :: FilePath,
    -- | Project working tree (where the chain runs).
    projectDir :: FilePath
  }

-- | Set up the fetch-path fixture inside a temp directory and run the
-- action. The fixture:
--
--   * Sets @XDG_CONFIG_HOME@ to a temp dir so 'installModuleDir' writes
--     into the test-controlled tree, then restores it on exit.
--   * Sets @GIT_ALLOW_PROTOCOL=file@ so @git clone@ accepts the local
--     @file://@ URL even on git versions that lock down the file
--     transport by default (CVE-2022-39253).
--   * Initializes the @remoteDir@ as a git repo containing a single
--     @module.dhall@ at @remoteVer@ with the given migrations literal,
--     committed under a fixed test identity.
--   * Writes the installed module.dhall at @installedVer@ and a
--     @.seihou-origin.json@ pointing at the remote.
--
-- The action receives a 'FetchFixture' bundle.
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

    -- Remote: a git repo with module.dhall at remoteVer.
    writeInstalledModule remoteDir remoteVer migrationsLit
    initRemoteRepo remoteDir

    -- Installed copy: same fields but at installedVer, plus origin.json.
    writeInstalledModule installedDir installedVer emptyMigrationsLit
    writeOriginJson installedDir (T.pack remoteDir)

    withSavedEnv "XDG_CONFIG_HOME" (Just xdgHome) $
      withSavedEnv "GIT_ALLOW_PROTOCOL" (Just "file") $
        action fix

-- | Initialize a directory as a git repo with one commit. The test
-- ignores any user / system git config (pre-commit hooks, signing
-- requirements) so the commit is self-contained.
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

-- | Write a minimal @.seihou-origin.json@ pointing at the given source
-- URL. The migrate fetch path reads this file via 'readOriginInfo'.
writeOriginJson :: FilePath -> Text -> IO ()
writeOriginJson installedDir sourceUrl = do
  let payload =
        object
          [ "sourceUrl" .= sourceUrl,
            "repoName" .= (Nothing :: Maybe Text),
            "version" .= (Nothing :: Maybe Text)
          ]
  LBS.writeFile (installedDir </> ".seihou-origin.json") (encode payload)

-- | Build a manifest for the fetch-path fixture: one applied module
-- recording @version@ as its current version, @applied.source@ pointed
-- at the fixture's installedDir, and the given list of tracked files.
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

-- | Save the current value of an env var, set a new one, and restore
-- on exit. Used to redirect XDG_CONFIG_HOME and GIT_ALLOW_PROTOCOL for
-- the duration of a fetch-path test.
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

    -- ------------------------------------------------------------------
    -- Fetch-path tests (EP-2): exercise the default behavior where
    -- runMigrate clones the module's source repo, refreshes the
    -- locally installed copy, and applies the chain in one shot.
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
          Right (MigrateApplied _ manifest') -> do
            -- Project working tree updated.
            doesFileExist (fix.projectDir </> "old.txt") `shouldReturn` False
            doesFileExist (fix.projectDir </> "new.txt") `shouldReturn` True
            -- Manifest reflects the new version.
            case manifest'.modules of
              (am : _) -> am.moduleVersion `shouldBe` Just "2.0.0"
              [] -> expectationFailure "manifest has no modules"
            Map.member "new.txt" manifest'.files `shouldBe` True
            Map.member "old.txt" manifest'.files `shouldBe` False
            -- The on-disk installed copy was refreshed to the remote's
            -- version (verifiable by reading its module.dhall back).
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
        -- The installed copy still says 1.0.0; with --no-fetch, runMigrate
        -- never consults the remote so it sees manifest=1.0.0 ==
        -- installed=1.0.0 and reports NoOp. The remote at 2.0.0 is
        -- ignored.
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

    -- ------------------------------------------------------------------
    -- EP-5: partial / blocked planner outcomes
    -- ------------------------------------------------------------------

    it "applies the longest reachable prefix and surfaces the unreachable tail" $
      -- Master-plan live-tree shape: installed declares one edge
      -- 1.0.0 -> 2.0.0 but is itself at 3.0.0. Manifest at 1.0.0
      -- targets 3.0.0 implicitly. Without --to, we should apply the
      -- prefix and report the unreachable (2.0.0, 3.0.0) tail.
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
          Right (MigrateAppliedPartial _ manifest' _stuck _target) -> do
            -- Manifest bumped to the highest reached version, not the
            -- unreachable target.
            (head manifest'.modules).moduleVersion `shouldBe` Just "2.0.0"
            -- File moved as the prefix specified.
            Map.member "src/Main.hs" manifest'.files `shouldBe` True
            Map.member "app/Main.hs" manifest'.files `shouldBe` False
            doesFileExist (dir </> "src" </> "Main.hs") `shouldReturn` True
            doesFileExist (dir </> "app" </> "Main.hs") `shouldReturn` False
          other ->
            expectationFailure
              ("expected MigrateAppliedPartial, got: " <> show other)

    it "errors with MigrationGap when --to TARGET cannot be reached (partial)" $
      -- Same fixture as above, but the user explicitly asked for
      -- 3.0.0. The strict-target contract refuses partial fulfillment.
      withSystemTempDirectory "seihou-migrate-cli" $ \dir -> do
        let installed = dir </> "installed-demo"
        writeInstalledModule installed "3.0.0" moveAppToSrcLit
        createDirectoryIfMissing True (dir </> "app")
        TIO.writeFile (dir </> "app" </> "Main.hs") "x"
        let manifest = mkManifest "1.0.0" installed [("app/Main.hs", "x")]
            opts = defaultOpts {migrateTo = Just "3.0.0"}
        result <-
          withCurrentDirectory dir $
            runMigrate opts manifest installed
        case result of
          Left (MigratePlanFailed _) ->
            -- Disk untouched: prefix should not have been applied.
            doesFileExist (dir </> "src" </> "Main.hs") `shouldReturn` False
          other ->
            expectationFailure
              ("expected MigratePlanFailed (MigrationGap …), got: " <> show other)

    it "returns MigrateBenignUpgrade when the module declares no migrations and the manifest trails" $
      -- After EP-6: installed at 0.3.0 declares no migrations at all
      -- (the empty-migrations case); manifest is at 0.1.3. Without
      -- --to, the migrate command treats this as a benign version
      -- bump rather than a block, since there is no destructive op
      -- to apply and `seihou upgrade && seihou run` will catch the
      -- manifest up.
      withSystemTempDirectory "seihou-migrate-cli" $ \dir -> do
        let installed = dir </> "installed-demo"
        writeInstalledModule installed "0.3.0" emptyMigrationsLit
        let manifest = mkManifest "0.1.3" installed []
        result <-
          withCurrentDirectory dir $
            runMigrate defaultOpts manifest installed
        case result of
          Right (MigrateBenignUpgrade _from _to) -> pure ()
          other ->
            expectationFailure
              ("expected MigrateBenignUpgrade, got: " <> show other)

    it "returns MigrateBlocked when migrations are declared but none reach the manifest version" $
      -- The "real block" case after EP-6: the module *did* ship at
      -- least one migration, but no edge starts at the manifest
      -- version. The author owes a migration; --without-to we surface
      -- this as MigrateBlocked.
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
          Right (MigrateBlocked _stuck _target) -> pure ()
          other ->
            expectationFailure
              ("expected MigrateBlocked, got: " <> show other)

    it "returns MigratePlanFailed when --to TARGET asks for a blocked target" $
      withSystemTempDirectory "seihou-migrate-cli" $ \dir -> do
        let installed = dir </> "installed-demo"
        writeInstalledModule installed "0.3.0" emptyMigrationsLit
        let manifest = mkManifest "0.1.3" installed []
            opts = defaultOpts {migrateTo = Just "0.3.0"}
        result <-
          withCurrentDirectory dir $
            runMigrate opts manifest installed
        case result of
          Left (MigratePlanFailed _) -> pure ()
          other ->
            expectationFailure
              ("expected MigratePlanFailed, got: " <> show other)

    -- M1 pin, flipped in M3: empty-migrations and [orphanEdge] now
    -- diverge at the migrate-command layer. Empty migrations route
    -- through MigrateBenignUpgrade (no destructive op to apply, so
    -- the user can run upgrade && run normally); orphan-edge routes
    -- through MigrateBlocked (the author started declaring migrations
    -- but the chain doesn't reach, which is a real block).
    it "splits [] vs [orphanEdge]: MigrateBenignUpgrade vs MigrateBlocked" $
      withSystemTempDirectory "seihou-migrate-cli" $ \dir -> do
        let installedEmpty = dir </> "installed-empty"
            installedOrphan = dir </> "installed-orphan"
            -- An edge that starts at 0.5.0; manifest is at 0.1.3 so it
            -- doesn't reach.
            orphanEdgeLit =
              T.unlines
                [ "[ { from = \"0.5.0\"",
                  "  , to = \"0.6.0\"",
                  "  , ops = [] : List < MoveFile : { src : Text, dest : Text } | MoveDir : { src : Text, dest : Text } | DeleteFile : { path : Text } | DeleteDir : { path : Text } | RunCommand : { run : Text, workDir : Optional Text } >",
                  "  }",
                  "]"
                ]
        writeInstalledModule installedEmpty "0.3.0" emptyMigrationsLit
        writeInstalledModule installedOrphan "0.3.0" orphanEdgeLit
        let manifestEmpty = mkManifest "0.1.3" installedEmpty []
            manifestOrphan = mkManifest "0.1.3" installedOrphan []
        rEmpty <-
          withCurrentDirectory dir $
            runMigrate defaultOpts manifestEmpty installedEmpty
        rOrphan <-
          withCurrentDirectory dir $
            runMigrate defaultOpts {migrateModule = modName} manifestOrphan installedOrphan
        case (rEmpty, rOrphan) of
          (Right (MigrateBenignUpgrade _ _), Right (MigrateBlocked _ _)) -> pure ()
          other ->
            expectationFailure
              ( "expected (MigrateBenignUpgrade, MigrateBlocked), got: "
                  <> show other
              )

    -- ------------------------------------------------------------------
    -- M6: --bump-only escape hatch.
    -- ------------------------------------------------------------------

    it "--bump-only refreshes the manifest version to the installed copy without running ops" $
      withSystemTempDirectory "seihou-migrate-cli" $ \dir -> do
        -- Live-tree exec-plan shape: manifest at 0.1.0, installed
        -- declares no migrations at 0.3.0. Without --bump-only this
        -- would route through MigrateBenignUpgrade (M3); --bump-only
        -- forces the manifest to bump to 0.3.0 in one step.
        let installed = dir </> "installed-demo"
        writeInstalledModule installed "0.3.0" emptyMigrationsLit
        let manifest = mkManifest "0.1.0" installed []
            opts = defaultOpts {migrateBumpOnly = True}
        result <-
          withCurrentDirectory dir $
            runMigrate opts manifest installed
        case result of
          Right (MigrateApplied execPlan manifest') -> do
            -- Manifest reflects the new version.
            (head manifest'.modules).moduleVersion `shouldBe` Just "0.3.0"
            -- Empty plan: bump-only never runs ops.
            let chain :: MigrationChain
                chain = execPlan.planChain
             in null chain.chainSteps `shouldBe` True
          other ->
            expectationFailure
              ("expected MigrateApplied (bump-only), got: " <> show other)

    it "--bump-only --to TARGET errors with MigrateConflictingFlags" $
      withSystemTempDirectory "seihou-migrate-cli" $ \dir -> do
        let installed = dir </> "installed-demo"
        writeInstalledModule installed "0.3.0" emptyMigrationsLit
        let manifest = mkManifest "0.1.0" installed []
            opts =
              defaultOpts
                { migrateBumpOnly = True,
                  migrateTo = Just "0.2.0"
                }
        result <-
          withCurrentDirectory dir $
            runMigrate opts manifest installed
        case result of
          Left (MigrateConflictingFlags _) -> pure ()
          other ->
            expectationFailure
              ("expected MigrateConflictingFlags, got: " <> show other)

    it "--bump-only is idempotent: a second run targets the same version with no error" $
      withSystemTempDirectory "seihou-migrate-cli" $ \dir -> do
        let installed = dir </> "installed-demo"
        writeInstalledModule installed "0.3.0" emptyMigrationsLit
        let manifest = mkManifest "0.1.0" installed []
            opts = defaultOpts {migrateBumpOnly = True}
        first <-
          withCurrentDirectory dir $
            runMigrate opts manifest installed
        manifest1 <- case first of
          Right (MigrateApplied _ m) -> pure m
          other ->
            expectationFailure
              ("expected first MigrateApplied, got: " <> show other)
              >> error "unreachable"
        second <-
          withCurrentDirectory dir $
            runMigrate opts manifest1 installed
        case second of
          Right (MigrateApplied plan manifest2) -> do
            (head manifest2.modules).moduleVersion `shouldBe` Just "0.3.0"
            length plan.planChain.chainSteps `shouldBe` 0
          other ->
            expectationFailure
              ("expected second MigrateApplied, got: " <> show other)

    it "--bump-only bypasses a partial-chain fixture (master-plan shape)" $
      -- Manifest at 1.0.0, installed declares one edge 1.0.0 -> 2.0.0
      -- but is at 3.0.0. Without --bump-only this would route through
      -- MigrateAppliedPartial (the prefix is applied, the unreachable
      -- 2.0.0 -> 3.0.0 tail is left). --bump-only skips the chain
      -- entirely and bumps the manifest straight to 3.0.0.
      withSystemTempDirectory "seihou-migrate-cli" $ \dir -> do
        let installed = dir </> "installed-demo"
        writeInstalledModule installed "3.0.0" moveAppToSrcLit
        createDirectoryIfMissing True (dir </> "app")
        TIO.writeFile (dir </> "app" </> "Main.hs") "module Main where"
        let manifest = mkManifest "1.0.0" installed [("app/Main.hs", "module Main where")]
            opts = defaultOpts {migrateBumpOnly = True}
        result <-
          withCurrentDirectory dir $
            runMigrate opts manifest installed
        case result of
          Right (MigrateApplied plan manifest') -> do
            (head manifest'.modules).moduleVersion `shouldBe` Just "3.0.0"
            length plan.planChain.chainSteps `shouldBe` 0
            -- Disk is untouched: --bump-only never moves files.
            doesFileExist (dir </> "app" </> "Main.hs") `shouldReturn` True
            doesFileExist (dir </> "src" </> "Main.hs") `shouldReturn` False
          other ->
            expectationFailure
              ("expected MigrateApplied, got: " <> show other)

    it "dry-run on a partial chain returns MigrateDryRunOKPartial without writing disk" $
      withSystemTempDirectory "seihou-migrate-cli" $ \dir -> do
        let installed = dir </> "installed-demo"
        writeInstalledModule installed "3.0.0" moveAppToSrcLit
        createDirectoryIfMissing True (dir </> "app")
        TIO.writeFile (dir </> "app" </> "Main.hs") "x"
        let manifest = mkManifest "1.0.0" installed [("app/Main.hs", "x")]
            opts = defaultOpts {migrateDryRun = True}
        result <-
          withCurrentDirectory dir $
            runMigrate opts manifest installed
        case result of
          Right (MigrateDryRunOKPartial _ _stuck _target) -> do
            -- Disk untouched.
            doesFileExist (dir </> "app" </> "Main.hs") `shouldReturn` True
            doesFileExist (dir </> "src" </> "Main.hs") `shouldReturn` False
          other ->
            expectationFailure
              ("expected MigrateDryRunOKPartial, got: " <> show other)
