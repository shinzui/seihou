module Seihou.CLI.UpdateSpec (tests) where

import Control.Exception (bracket)
import Data.ByteString.Lazy qualified as LBS
import Data.Map.Strict qualified as Map
import Data.Maybe (listToMaybe)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Time (UTCTime (..), fromGregorian)
import Seihou.CLI.CommandExecution (CommandPolicy (..))
import Seihou.CLI.Update (PromptPolicy (..), UpdateRequest (..), UpdateSelection (..), applyProjectUpdate, withProjectUpdate)
import Seihou.CLI.Update.Migrations (StagedMigrations (..), planAndStageMigrations)
import Seihou.CLI.Update.Selection
import Seihou.CLI.Update.Source
import Seihou.CLI.Update.Types
import Seihou.Composition.Instance (ModuleInstance (..))
import Seihou.Core.Application (mkApplicationId)
import Seihou.Core.Migration (Migration (..), MigrationOp (..))
import Seihou.Core.Types
import Seihou.Manifest.Hash (hashContent)
import Seihou.Manifest.Types (emptyManifest, manifestFromJSON, manifestToJSON)
import System.Directory (createDirectoryIfMissing, doesFileExist, withCurrentDirectory)
import System.Environment (lookupEnv, setEnv, unsetEnv)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (callProcess)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.CLI.Update" spec

spec :: Spec
spec = do
  describe "application selection" $ do
    it "selects every application containing a requested bare module" $ do
      let first = application (AppliedModuleTarget "one") [instanceState "shared" "/one/shared"]
          second = application (AppliedRecipeTarget "stack") [instanceState "shared" "/two/shared"]
          manifest :: Manifest
          manifest = manifestForApplications [first, second] Map.empty
      selectApplications (NamedUpdateTargets ["shared"]) manifest
        `shouldBe` Right (RecordedSelection [first, second])

    it "rejects a partial selection that shares an owned path" $ do
      let first = application (AppliedModuleTarget "one") [instanceState "one" "/one"]
          second = application (AppliedModuleTarget "two") [instanceState "two" "/two"]
          owners = Set.fromList [first.applicationId, second.applicationId]
          record = FileRecord (hashContent "old") "one" Template testTime Nothing owners
          manifest :: Manifest
          manifest = manifestForApplications [first, second] (Map.singleton "shared.txt" record)
      selectApplications (NamedUpdateTargets ["one"]) manifest
        `shouldBe` Left (SharedPathRequiresApplications "shared.txt" (Set.singleton first.applicationId) (Set.singleton second.applicationId))

    it "requires one explicit target to seed a legacy manifest" $ do
      selectApplications AllRecordedApplications (emptyManifest testTime) `shouldBe` Left NoRecordedApplications
      selectApplications (NamedUpdateTargets ["one", "two"]) (emptyManifest testTime)
        `shouldBe` Left LegacyUpdateRequiresOneTarget

  describe "candidate source staging" $ do
    it "keeps local artifacts as an explicit candidate-first fallback" $
      withSystemTempDirectory "seihou-update-source" $ \root -> do
        let moduleDirectory = root </> "current" </> "demo"
            sessionDirectory = root </> "session"
            applied = application (AppliedModuleTarget "demo") [instanceState "demo" moduleDirectory]
        createDirectoryIfMissing True moduleDirectory
        TIO.writeFile (moduleDirectory </> "module.dhall") (moduleDhall "demo" "1.0.0")
        result <- stageCandidateSources sessionDirectory [applied {targetSource = moduleDirectory}]
        case result of
          Left err -> expectationFailure (show err)
          Right (catalog, warnings) -> do
            warnings `shouldContain` [LocalArtifactHasNoRemote "demo"]
            let candidate = catalog.artifacts Map.! (CandidateModule, "demo")
            candidate.originalDirectory `shouldBe` moduleDirectory
            candidate.sourceUrl `shouldBe` Nothing
            doesFileExist (catalog.searchRoot </> "demo" </> "module.dhall") `shouldReturn` True

    it "clones one registry origin once for a recipe and all of its modules" $
      withSystemTempDirectory "seihou-update-registry-source" $ \root -> do
        let remote = root </> "remote"
            installed = root </> "installed"
            moduleOne = installed </> "one"
            moduleTwo = installed </> "two"
            recipeDirectory = installed </> "stack"
            sessionDirectory = root </> "session"
            sourceUrl = T.pack remote
            applied =
              (application (AppliedRecipeTarget "stack") [instanceState "one" moduleOne, instanceState "two" moduleTwo])
                { targetSource = recipeDirectory,
                  additionalModules = []
                }
        createDirectoryIfMissing True (remote </> "modules" </> "one")
        createDirectoryIfMissing True (remote </> "modules" </> "two")
        createDirectoryIfMissing True (remote </> "recipes" </> "stack")
        TIO.writeFile (remote </> "modules" </> "one" </> "module.dhall") (moduleDhall "one" "2.0.0")
        TIO.writeFile (remote </> "modules" </> "two" </> "module.dhall") (moduleDhall "two" "2.0.0")
        TIO.writeFile (remote </> "recipes" </> "stack" </> "recipe.dhall") (recipeDhall "stack" "2.0.0" ["one", "two"])
        TIO.writeFile (remote </> "seihou-registry.dhall") registryDhall
        callProcess "git" ["-C", remote, "init", "-q"]
        callProcess "git" ["-C", remote, "add", "."]
        callProcess "git" ["-C", remote, "-c", "user.name=Seihou Test", "-c", "user.email=test@example.com", "commit", "-qm", "registry"]
        mapM_ (writeOrigin sourceUrl) [moduleOne, moduleTwo, recipeDirectory]
        result <- stageCandidateSources sessionDirectory [applied]
        case result of
          Left err -> expectationFailure (show err)
          Right (catalog, _) -> do
            Map.size catalog.clonedOrigins `shouldBe` 1
            Map.keysSet catalog.artifacts
              `shouldBe` Set.fromList [(CandidateModule, "one"), (CandidateModule, "two"), (CandidateRecipe, "stack")]

    it "returns a structured clone error before touching the project" $
      withSystemTempDirectory "seihou-update-clone-error" $ \root -> do
        let moduleDirectory = root </> "installed" </> "demo"
            missingRemote = T.pack (root </> "missing-remote")
            applied = (application (AppliedModuleTarget "demo") [instanceState "demo" moduleDirectory]) {targetSource = moduleDirectory}
        writeOrigin missingRemote moduleDirectory
        result <- stageCandidateSources (root </> "session") [applied]
        result `shouldSatisfy` \case
          Left (CandidateCloneFailed url message) -> url == missingRemote && "git clone failed" `T.isInfixOf` message
          _ -> False

  describe "staged update service" $ do
    it "reuses accepted inputs, keeps dry-run read-only, and publishes one coherent update" $
      withSystemTempDirectory "seihou-update-e2e" $ \root -> do
        fixture <- prepareUpdateFixture root
        withSavedEnv "XDG_CONFIG_HOME" (Just fixture.xdgHome) $
          withCurrentDirectory fixture.projectRoot $ do
            beforeManifest <- LBS.readFile fixture.manifestPath
            beforeProject <- TIO.readFile fixture.projectFile
            beforeInstalled <- TIO.readFile (fixture.installedModule </> "module.dhall")
            let dryRequest = updateRequest True
            dryResult <- withProjectUpdate dryRequest $ \case
              Left err -> pure (Left err)
              Right plan -> applyProjectUpdate plan
            case dryResult of
              Left err -> expectationFailure (show err)
              Right _ -> pure ()
            LBS.readFile fixture.manifestPath `shouldReturn` beforeManifest
            TIO.readFile fixture.projectFile `shouldReturn` beforeProject
            TIO.readFile (fixture.installedModule </> "module.dhall") `shouldReturn` beforeInstalled

            applied <- withProjectUpdate (updateRequest False) $ \case
              Left err -> pure (Left err)
              Right plan -> applyProjectUpdate plan
            case applied of
              Left err -> expectationFailure (show err)
              Right result -> do
                result.versions `shouldSatisfy` any (\change -> change.name == "demo" && change.fromVersion == Just "1.0.0" && change.toVersion == Just "2.0.0")
                result.updatedApplications `shouldBe` [fixture.applicationId]
            TIO.readFile fixture.projectFile `shouldReturn` "hello accepted\nv2\n"
            installedBytes <- TIO.readFile (fixture.installedModule </> "module.dhall")
            installedBytes `shouldSatisfy` T.isInfixOf "Some \"2.0.0\""
            decoded <- manifestFromJSON <$> LBS.readFile fixture.manifestPath
            case decoded of
              Left err -> expectationFailure err
              Right manifest -> case manifest.applications of
                updated : _ -> case updated.instances of
                  instanceState : _ -> do
                    instanceState.resolvedVars `shouldBe` Map.singleton "project.name" "accepted"
                    instanceState.moduleVersion `shouldBe` Just "2.0.0"
                  [] -> expectationFailure "updated application has no instances"
                [] -> expectationFailure "updated manifest has no applications"

            afterFirstApply <- LBS.readFile fixture.manifestPath
            noOp <- withProjectUpdate (updateRequest False) $ \case
              Left err -> pure (Left err)
              Right plan -> applyProjectUpdate plan
            case noOp of
              Left err -> expectationFailure (show err)
              Right result -> result.updatedApplications `shouldBe` []
            LBS.readFile fixture.manifestPath `shouldReturn` afterFirstApply

    it "rejects a plan when its manifest snapshot changes" $
      withSystemTempDirectory "seihou-update-stale" $ \root -> do
        fixture <- prepareUpdateFixture root
        withSavedEnv "XDG_CONFIG_HOME" (Just fixture.xdgHome) $
          withCurrentDirectory fixture.projectRoot $ do
            result <- withProjectUpdate (updateRequest False) $ \case
              Left err -> pure (Left err)
              Right plan -> do
                TIO.appendFile fixture.manifestPath "\n"
                applyProjectUpdate plan
            result `shouldSatisfy` \case
              Left (UpdatePlanStale paths) -> Set.member (".seihou" </> "manifest.json") paths
              _ -> False

    it "re-expands a candidate recipe and removes dependencies dropped by it" $
      withSystemTempDirectory "seihou-update-recipe" $ \root -> do
        fixture <- prepareRecipeUpdateFixture root
        withSavedEnv "XDG_CONFIG_HOME" (Just fixture.recipeXdgHome) $
          withCurrentDirectory fixture.recipeProjectRoot $ do
            result <- withProjectUpdate (updateRequest False) $ \case
              Left err -> pure (Left err)
              Right plan -> applyProjectUpdate plan
            case result of
              Left err -> expectationFailure (show err)
              Right updateResult -> updateResult.updatedApplications `shouldBe` [fixture.recipeApplicationId]
            decoded <- manifestFromJSON <$> LBS.readFile fixture.recipeManifestPath
            case decoded of
              Left err -> expectationFailure err
              Right manifest -> case manifest.applications of
                [updated] -> do
                  updated.applicationId `shouldBe` fixture.recipeApplicationId
                  updated.targetVersion `shouldBe` Just "2.0.0"
                  updated.additionalModules `shouldBe` []
                  Set.fromList (map (.name) updated.instances) `shouldBe` Set.fromList ["one", "new"]
                  Set.fromList (map (.name) manifest.modules) `shouldBe` Set.fromList ["one", "new"]
                other -> expectationFailure ("expected one updated recipe application, got " <> show other)
            doesFileExist (fixture.recipeXdgHome </> "seihou" </> "installed" </> "new" </> "module.dhall") `shouldReturn` True

    it "refuses an unresolved three-way conflict without mutating durable state" $
      withSystemTempDirectory "seihou-update-conflict" $ \root -> do
        fixture <- prepareUpdateFixture root
        TIO.writeFile (fixture.remote </> "files" </> "README.tmpl") "candidate {{project.name}}\nv2\n"
        callProcess "git" ["-C", fixture.remote, "add", "files/README.tmpl"]
        callProcess "git" ["-C", fixture.remote, "-c", "user.name=Seihou Test", "-c", "user.email=test@example.com", "commit", "-qm", "conflicting template"]
        withSavedEnv "XDG_CONFIG_HOME" (Just fixture.xdgHome) $
          withCurrentDirectory fixture.projectRoot $ do
            TIO.writeFile fixture.projectFile "user accepted\nv1\n"
            beforeManifest <- LBS.readFile fixture.manifestPath
            beforeInstalled <- LBS.readFile (fixture.installedModule </> "module.dhall")
            result <- withProjectUpdate (updateRequest False) $ \case
              Left err -> pure (Left err)
              Right plan -> applyProjectUpdate plan
            result `shouldSatisfy` \case
              Left (UpdateHasUnresolvedPaths paths) -> Set.member "README.md" paths
              _ -> False
            LBS.readFile fixture.manifestPath `shouldReturn` beforeManifest
            TIO.readFile fixture.projectFile `shouldReturn` "user accepted\nv1\n"
            LBS.readFile (fixture.installedModule </> "module.dhall") `shouldReturn` beforeInstalled

    it "seeds one explicit legacy target and records it only after success" $
      withSystemTempDirectory "seihou-update-legacy" $ \root -> do
        fixture <- prepareUpdateFixture root
        decoded <- manifestFromJSON <$> LBS.readFile fixture.manifestPath
        legacy <- case decoded of
          Left err -> expectationFailure err >> pure (emptyManifest testTime)
          Right manifest -> pure (withoutApplications manifest)
        LBS.writeFile fixture.manifestPath (manifestToJSON legacy)
        let request = (updateRequest False) {selection = NamedUpdateTargets ["demo"]}
        withSavedEnv "XDG_CONFIG_HOME" (Just fixture.xdgHome) $
          withCurrentDirectory fixture.projectRoot $ do
            result <- withProjectUpdate request $ \case
              Left err -> pure (Left err)
              Right plan -> applyProjectUpdate plan
            case result of
              Left err -> expectationFailure (show err)
              Right updateResult -> updateResult.updatedApplications `shouldBe` [fixture.applicationId]
            updated <- manifestFromJSON <$> LBS.readFile fixture.manifestPath
            case updated of
              Left err -> expectationFailure err
              Right manifest -> case manifest.applications of
                [applicationState] -> case applicationState.instances of
                  [moduleState] -> moduleState.resolvedVars `shouldBe` Map.singleton "project.name" "accepted"
                  other -> expectationFailure ("expected one legacy module instance, got " <> show other)
                other -> expectationFailure ("expected one seeded application, got " <> show other)

    it "rolls managed project and cache state back when a candidate command fails" $
      withSystemTempDirectory "seihou-update-command-failure" $ \root -> do
        fixture <- prepareUpdateFixture root
        let modulePath = fixture.remote </> "module.dhall"
        body <- TIO.readFile modulePath
        TIO.writeFile
          modulePath
          ( T.replace
              ", commands = [] : List { run : Text, workDir : Optional Text, when : Optional Text }"
              ", commands = [{ run = \"exit 7\", workDir = None Text, when = None Text }]"
              body
          )
        callProcess "git" ["-C", fixture.remote, "add", "module.dhall"]
        callProcess "git" ["-C", fixture.remote, "-c", "user.name=Seihou Test", "-c", "user.email=test@example.com", "commit", "-qm", "failing command"]
        withSavedEnv "XDG_CONFIG_HOME" (Just fixture.xdgHome) $
          withCurrentDirectory fixture.projectRoot $ do
            beforeManifest <- LBS.readFile fixture.manifestPath
            beforeProject <- TIO.readFile fixture.projectFile
            beforeInstalled <- LBS.readFile (fixture.installedModule </> "module.dhall")
            result <- withProjectUpdate (updateRequest False) $ \case
              Left err -> pure (Left err)
              Right plan -> applyProjectUpdate plan
            result `shouldSatisfy` \case
              Left UpdateCommandFailed {} -> True
              _ -> False
            LBS.readFile fixture.manifestPath `shouldReturn` beforeManifest
            TIO.readFile fixture.projectFile `shouldReturn` beforeProject
            LBS.readFile (fixture.installedModule </> "module.dhall") `shouldReturn` beforeInstalled

    it "rolls managed state back when installed-cache publication fails" $
      withSystemTempDirectory "seihou-update-cache-failure" $ \root -> do
        fixture <- prepareUpdateFixture root
        withSavedEnv "XDG_CONFIG_HOME" (Just fixture.xdgHome) $
          withCurrentDirectory fixture.projectRoot $ do
            beforeManifest <- LBS.readFile fixture.manifestPath
            beforeProject <- TIO.readFile fixture.projectFile
            beforeInstalled <- LBS.readFile (fixture.installedModule </> "module.dhall")
            result <- withProjectUpdate (updateRequest False) $ \case
              Left err -> pure (Left err)
              Right plan -> applyProjectUpdate (breakCandidatePublication plan)
            result `shouldSatisfy` \case
              Left UpdateCachePublicationFailed {} -> True
              _ -> False
            LBS.readFile fixture.manifestPath `shouldReturn` beforeManifest
            TIO.readFile fixture.projectFile `shouldReturn` beforeProject
            LBS.readFile (fixture.installedModule </> "module.dhall") `shouldReturn` beforeInstalled

  describe "migration staging" $ do
    it "preserves parameterized instances while planning their shared transition once" $
      withSystemTempDirectory "seihou-update-shared-migration" $ \projectRoot -> do
        let parentOne = ParentVars (Map.singleton "tenant" "one")
            parentTwo = ParentVars (Map.singleton "tenant" "two")
            instanceOne = ModuleInstance "shared" parentOne
            instanceTwo = ModuleInstance "shared" parentTwo
            stateFor parent = AppliedInstanceState "shared" parent "/installed/shared" (Just "1.0.0") Map.empty
            previous = application (AppliedModuleTarget "shared") [stateFor parentOne, stateFor parentTwo]
            candidate =
              Module
                { name = "shared",
                  version = Just "2.0.0",
                  description = Nothing,
                  vars = [],
                  exports = [],
                  prompts = [],
                  steps = [],
                  commands = [],
                  dependencies = [],
                  removal = Nothing,
                  migrations = [Migration "1.0.0" "2.0.0" [RunCommand "true" Nothing]]
                }
            appliedModules =
              [ AppliedModule "shared" parentOne "/installed/shared" (Just "1.0.0") testTime Nothing,
                AppliedModule "shared" parentTwo "/installed/shared" (Just "1.0.0") testTime Nothing
              ]
            base = emptyManifest testTime
            manifest =
              Manifest
                { version = base.version,
                  genAt = base.genAt,
                  modules = appliedModules,
                  vars = Map.empty,
                  files = Map.empty,
                  applications = [previous],
                  recipe = Nothing,
                  blueprint = Nothing
                }
            catalog = CandidateCatalog (projectRoot </> "search") Map.empty Map.empty
            candidates = [(instanceOne, candidate, "/candidate/shared"), (instanceTwo, candidate, "/candidate/shared")]
        staged <- planAndStageMigrations projectRoot manifest catalog [(Just previous, candidates)]
        case staged of
          Left err -> expectationFailure (show err)
          Right migrationStage -> do
            length migrationStage.plans `shouldBe` 1
            migrationStage.plans `shouldSatisfy` all (.containsCommands)
            migrationStage.warnings `shouldBe` [MigrationCommandNotSimulated "shared" "true"]
            map (.moduleVersion) migrationStage.manifest.modules `shouldBe` [Just "2.0.0", Just "2.0.0"]

data UpdateFixture = UpdateFixture
  { projectRoot :: FilePath,
    projectFile :: FilePath,
    manifestPath :: FilePath,
    xdgHome :: FilePath,
    installedModule :: FilePath,
    remote :: FilePath,
    applicationId :: ApplicationId
  }

data RecipeUpdateFixture = RecipeUpdateFixture
  { recipeProjectRoot :: FilePath,
    recipeManifestPath :: FilePath,
    recipeXdgHome :: FilePath,
    recipeApplicationId :: ApplicationId
  }

prepareUpdateFixture :: FilePath -> IO UpdateFixture
prepareUpdateFixture root = do
  let projectRoot = root </> "project"
      manifestPath = projectRoot </> ".seihou" </> "manifest.json"
      projectFile = projectRoot </> "README.md"
      remote = root </> "remote"
      xdgHome = root </> "xdg"
      installedModule = xdgHome </> "seihou" </> "installed" </> "demo"
      baselineContent = "hello accepted\nv1\n"
      baselineRef = BaselineRef (hashContent baselineContent)
      target = AppliedModuleTarget "demo"
      applicationId = mkApplicationId target []
      app =
        (application target [instanceState "demo" installedModule])
          { applicationId,
            targetSource = installedModule,
            targetVersion = Just "1.0.0",
            instances =
              [ (instanceState "demo" installedModule)
                  { resolvedVars = Map.singleton "project.name" "accepted"
                  }
              ]
          }
      appliedModule = AppliedModule "demo" emptyParentVars installedModule (Just "1.0.0") testTime Nothing
      fileRecord =
        FileRecord
          (hashContent baselineContent)
          "demo"
          Template
          testTime
          (Just baselineRef)
          (Set.singleton applicationId)
      manifest =
        (emptyManifest testTime)
          { modules = [appliedModule],
            vars = Map.singleton "project.name" "accepted",
            files = Map.singleton "README.md" fileRecord,
            applications = [app]
          }
  createDirectoryIfMissing True (installedModule </> "files")
  TIO.writeFile (installedModule </> "module.dhall") (moduleDhallWithTemplate "demo" "1.0.0" "old-default")
  TIO.writeFile (installedModule </> "files" </> "README.tmpl") "hello {{project.name}}\nv1\n"
  createDirectoryIfMissing True (remote </> "files")
  TIO.writeFile (remote </> "module.dhall") (moduleDhallWithTemplate "demo" "2.0.0" "new-default")
  TIO.writeFile (remote </> "files" </> "README.tmpl") "hello {{project.name}}\nv2\n"
  callProcess "git" ["-C", remote, "init", "-q"]
  callProcess "git" ["-C", remote, "add", "."]
  callProcess "git" ["-C", remote, "-c", "user.name=Seihou Test", "-c", "user.email=test@example.com", "commit", "-qm", "v2"]
  TIO.writeFile
    (installedModule </> ".seihou-origin.json")
    ("{\"sourceUrl\":\"" <> T.pack remote <> "\",\"version\":\"1.0.0\"}")
  createDirectoryIfMissing True (projectRoot </> ".seihou" </> "baselines")
  TIO.writeFile projectFile baselineContent
  TIO.writeFile
    (projectRoot </> ".seihou" </> "baselines" </> T.unpack baselineRef.unBaselineRef.unSHA256)
    baselineContent
  LBS.writeFile manifestPath (manifestToJSON manifest)
  pure UpdateFixture {projectRoot, projectFile, manifestPath, xdgHome, installedModule, remote, applicationId}

prepareRecipeUpdateFixture :: FilePath -> IO RecipeUpdateFixture
prepareRecipeUpdateFixture root = do
  let projectRoot = root </> "project"
      manifestPath = projectRoot </> ".seihou" </> "manifest.json"
      remote = root </> "remote"
      xdgHome = root </> "xdg"
      installedRoot = xdgHome </> "seihou" </> "installed"
      installedOne = installedRoot </> "one"
      installedOld = installedRoot </> "old"
      installedRecipe = installedRoot </> "stack"
      target = AppliedRecipeTarget "stack"
      applicationId = mkApplicationId target []
      app =
        AppliedComposition
          { applicationId,
            target,
            targetSource = installedRecipe,
            targetVersion = Just "1.0.0",
            additionalModules = [],
            namespace = Just "one",
            context = Nothing,
            instances = [instanceState "old" installedOld, instanceState "one" installedOne],
            commandReceipts = Map.empty,
            appliedAt = testTime
          }
      base = emptyManifest testTime
      manifest =
        Manifest
          { version = base.version,
            genAt = base.genAt,
            modules =
              [ AppliedModule "old" emptyParentVars installedOld (Just "1.0.0") testTime Nothing,
                AppliedModule "one" emptyParentVars installedOne (Just "1.0.0") testTime Nothing
              ],
            vars = Map.empty,
            files = Map.empty,
            applications = [app],
            recipe = Just (AppliedRecipe "stack" (Just "1.0.0") testTime),
            blueprint = Nothing
          }
      sourceUrl = T.pack remote
  createDirectoryIfMissing True installedOne
  createDirectoryIfMissing True installedOld
  createDirectoryIfMissing True installedRecipe
  TIO.writeFile (installedOne </> "module.dhall") (moduleDhall "one" "1.0.0")
  TIO.writeFile (installedOld </> "module.dhall") (moduleDhall "old" "1.0.0")
  TIO.writeFile (installedRecipe </> "recipe.dhall") (recipeDhall "stack" "1.0.0" ["one", "old"])
  mapM_ (writeOrigin sourceUrl) [installedOne, installedOld, installedRecipe]
  createDirectoryIfMissing True (remote </> "modules" </> "one")
  createDirectoryIfMissing True (remote </> "modules" </> "old")
  createDirectoryIfMissing True (remote </> "modules" </> "new")
  createDirectoryIfMissing True (remote </> "recipes" </> "stack")
  TIO.writeFile (remote </> "modules" </> "one" </> "module.dhall") (moduleDhall "one" "2.0.0")
  TIO.writeFile (remote </> "modules" </> "old" </> "module.dhall") (moduleDhall "old" "1.0.0")
  TIO.writeFile (remote </> "modules" </> "new" </> "module.dhall") (moduleDhall "new" "1.0.0")
  TIO.writeFile (remote </> "recipes" </> "stack" </> "recipe.dhall") (recipeDhall "stack" "2.0.0" ["one", "new"])
  TIO.writeFile (remote </> "seihou-registry.dhall") recipeUpdateRegistryDhall
  callProcess "git" ["-C", remote, "init", "-q"]
  callProcess "git" ["-C", remote, "add", "."]
  callProcess "git" ["-C", remote, "-c", "user.name=Seihou Test", "-c", "user.email=test@example.com", "commit", "-qm", "recipe v2"]
  createDirectoryIfMissing True (projectRoot </> ".seihou")
  LBS.writeFile manifestPath (manifestToJSON manifest)
  pure
    RecipeUpdateFixture
      { recipeProjectRoot = projectRoot,
        recipeManifestPath = manifestPath,
        recipeXdgHome = xdgHome,
        recipeApplicationId = applicationId
      }

updateRequest :: Bool -> UpdateRequest
updateRequest dryRun =
  UpdateRequest
    { selection = AllRecordedApplications,
      varOverrides = [],
      reconfigure = False,
      promptPolicy = ForbidPrompts,
      commandPolicy = RunChangedCommands,
      dryRun
    }

moduleDhallWithTemplate :: Text -> Text -> Text -> Text
moduleDhallWithTemplate name version defaultValue =
  T.unlines
    [ "{ name = \"" <> name <> "\"",
      ", version = Some \"" <> version <> "\"",
      ", description = None Text",
      ", vars = [{ name = \"project.name\", type = \"text\", default = Some \"" <> defaultValue <> "\", description = None Text, required = False, validation = None Text }]",
      ", exports = [] : List { var : Text, alias : Optional Text }",
      ", prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }",
      ", steps = [{ strategy = \"template\", src = \"README.tmpl\", dest = \"README.md\", when = None Text, patch = None Text }]",
      ", commands = [] : List { run : Text, workDir : Optional Text, when : Optional Text }",
      ", dependencies = [] : List Text",
      ", removal = None { steps : List { action : Text, dest : Text, src : Optional Text }, commands : List { run : Text, workDir : Optional Text, when : Optional Text } }",
      "}"
    ]

withSavedEnv :: String -> Maybe String -> IO a -> IO a
withSavedEnv key value action =
  bracket
    (lookupEnv key <* setValue value)
    setValue
    (const action)
  where
    setValue (Just current) = setEnv key current
    setValue Nothing = unsetEnv key

application :: AppliedTarget -> [AppliedInstanceState] -> AppliedComposition
application target instances =
  AppliedComposition
    { applicationId = mkApplicationId target [],
      target,
      targetSource = maybe "" (.source) (listToMaybe instances),
      targetVersion = Just "1.0.0",
      additionalModules = [],
      namespace = Nothing,
      context = Nothing,
      instances,
      commandReceipts = Map.empty,
      appliedAt = testTime
    }

instanceState :: ModuleName -> FilePath -> AppliedInstanceState
instanceState name source =
  AppliedInstanceState
    { name,
      parentVars = emptyParentVars,
      source,
      moduleVersion = Just "1.0.0",
      resolvedVars = Map.empty
    }

moduleDhall :: Text -> Text -> Text
moduleDhall name version =
  T.unlines
    [ "{ name = \"" <> name <> "\"",
      ", version = Some \"" <> version <> "\"",
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

recipeDhall :: Text -> Text -> [Text] -> Text
recipeDhall name version modules =
  T.unlines
    [ "{ name = \"" <> name <> "\"",
      ", version = Some \"" <> version <> "\"",
      ", description = None Text",
      ", modules = ["
        <> T.intercalate
          ", "
          [ "{ module = \"" <> moduleName <> "\", vars = [] : List { name : Text, value : Text } }"
          | moduleName <- modules
          ]
        <> "]",
      ", vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }",
      ", prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }",
      "}"
    ]

registryDhall :: Text
registryDhall =
  T.unlines
    [ "{ repoName = \"update-test\"",
      ", repoDescription = None Text",
      ", modules =",
      "  [ { name = \"one\", version = Some \"2.0.0\", path = \"modules/one\", description = None Text, tags = [] : List Text }",
      "  , { name = \"two\", version = Some \"2.0.0\", path = \"modules/two\", description = None Text, tags = [] : List Text }",
      "  ]",
      ", recipes = [{ name = \"stack\", version = Some \"2.0.0\", path = \"recipes/stack\", description = None Text, tags = [] : List Text }]",
      ", blueprints = [] : List { name : Text, version : Optional Text, path : Text, description : Optional Text, tags : List Text }",
      ", prompts = [] : List { name : Text, version : Optional Text, path : Text, description : Optional Text, tags : List Text }",
      "}"
    ]

recipeUpdateRegistryDhall :: Text
recipeUpdateRegistryDhall =
  T.unlines
    [ "{ repoName = \"recipe-update-test\"",
      ", repoDescription = None Text",
      ", modules =",
      "  [ { name = \"one\", version = Some \"2.0.0\", path = \"modules/one\", description = None Text, tags = [] : List Text }",
      "  , { name = \"old\", version = Some \"1.0.0\", path = \"modules/old\", description = None Text, tags = [] : List Text }",
      "  , { name = \"new\", version = Some \"1.0.0\", path = \"modules/new\", description = None Text, tags = [] : List Text }",
      "  ]",
      ", recipes = [{ name = \"stack\", version = Some \"2.0.0\", path = \"recipes/stack\", description = None Text, tags = [] : List Text }]",
      ", blueprints = [] : List { name : Text, version : Optional Text, path : Text, description : Optional Text, tags : List Text }",
      ", prompts = [] : List { name : Text, version : Optional Text, path : Text, description : Optional Text, tags : List Text }",
      "}"
    ]

writeOrigin :: Text -> FilePath -> IO ()
writeOrigin sourceUrl directory = do
  createDirectoryIfMissing True directory
  TIO.writeFile (directory </> ".seihou-origin.json") ("{\"sourceUrl\":\"" <> sourceUrl <> "\"}")

manifestForApplications :: [AppliedComposition] -> Map.Map FilePath FileRecord -> Manifest
manifestForApplications applicationRecords fileRecords =
  let base = emptyManifest testTime
   in Manifest
        { version = base.version,
          genAt = base.genAt,
          modules = base.modules,
          vars = base.vars,
          files = fileRecords,
          applications = applicationRecords,
          recipe = base.recipe,
          blueprint = base.blueprint
        }

breakCandidatePublication :: UpdatePlan -> UpdatePlan
breakCandidatePublication plan =
  UpdatePlan
    { applications = plan.applications,
      versionChanges = plan.versionChanges,
      inputChanges = plan.inputChanges,
      migrations = plan.migrations,
      reconciliation = plan.reconciliation,
      commandPlan = plan.commandPlan,
      candidateArtifacts = map breakArtifact plan.candidateArtifacts,
      warnings = plan.warnings,
      request = plan.request,
      snapshot = plan.snapshot,
      plannedApplications = plan.plannedApplications
    }
  where
    breakArtifact artifact =
      CandidateArtifact
        { kind = artifact.kind,
          name = artifact.name,
          version = artifact.version,
          originalDirectory = plan.snapshot.sessionDirectory </> "missing-publication-source",
          sourceDirectory = artifact.sourceDirectory,
          sourceUrl = artifact.sourceUrl,
          repoName = artifact.repoName,
          tags = artifact.tags,
          sourceRevision = artifact.sourceRevision,
          contentHash = artifact.contentHash,
          moduleDefinition = artifact.moduleDefinition,
          recipeDefinition = artifact.recipeDefinition
        }

withoutApplications :: Manifest -> Manifest
withoutApplications manifest =
  Manifest
    { version = manifest.version,
      genAt = manifest.genAt,
      modules = manifest.modules,
      vars = manifest.vars,
      files = manifest.files,
      applications = [],
      recipe = manifest.recipe,
      blueprint = manifest.blueprint
    }

testTime :: UTCTime
testTime = UTCTime (fromGregorian 2026 7 19) 0
