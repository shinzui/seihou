module Seihou.Integration.ExecutionSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (UTCTime, defaultTimeLocale, parseTimeOrError)
import Effectful
import Seihou.Core.Module (loadModule)
import Seihou.Core.Types
import Seihou.Core.Variable (resolveVariables)
import Seihou.Effect.FilesystemPure (PureFS (..), emptyFS, runFilesystemPure)
import Seihou.Engine.Diff (computeDiff)
import Seihou.Engine.Execute (dryRunPlan, executePlan)
import Seihou.Engine.Plan (compilePlan)
import Seihou.Manifest.Types (emptyManifest)
import System.Directory (getCurrentDirectory)
import System.FilePath ((</>))
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Integration.Execution" spec

fixedTime :: UTCTime
fixedTime = parseTimeOrError True defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ" "2026-03-01T10:30:00Z"

fixtureDir :: IO FilePath
fixtureDir = do
  cwd <- getCurrentDirectory
  pure (cwd </> "test" </> "fixtures")

-- | Helper to extract the resolved variable values map.
resolvedValues :: Map.Map VarName ResolvedVar -> Map.Map VarName VarValue
resolvedValues = Map.map resolvedValue

-- | Load haskell-base fixture, resolve vars, compile plan.
compileFixturePlan :: [(Text, Text)] -> IO (Module, [Operation])
compileFixturePlan vars = do
  fixtures <- fixtureDir
  result <- loadModule [fixtures] "haskell-base"
  case result of
    Left err -> error ("Failed to load module: " <> show err)
    Right modul -> do
      let cli = Map.fromList [(VarName k, v) | (k, v) <- vars]
          env = Map.empty
      case resolveVariables (moduleVars modul) cli env Map.empty Map.empty Map.empty of
        Left errs -> error ("Failed to resolve: " <> show errs)
        Right resolved -> do
          planResult <- compilePlan (fixtures </> "haskell-base") modul (resolvedValues resolved)
          case planResult of
            Left errs -> error ("Plan failed: " <> show errs)
            Right ops -> pure (modul, ops)

-- | Extract planned files from operations for computeDiff.
extractPlanned :: ModuleName -> [Operation] -> [(FilePath, Text, ModuleName)]
extractPlanned modName ops = [(dest, content, modName) | WriteFileOp dest content _ <- ops]

spec :: Spec
spec = do
  describe "full execution pipeline" $ do
    it "first run creates files and builds file records" $ do
      (modul, ops) <- compileFixturePlan [("project.name", "my-app")]
      let modName = moduleName modul
          (records, fs) =
            runPureEff $
              runFilesystemPure emptyFS $
                executePlan "" ops modName fixedTime
      -- Verify files were created in the filesystem
      Map.member "README.md" (pureFiles fs) `shouldBe` True
      Map.member "my-app.cabal" (pureFiles fs) `shouldBe` True
      Map.member "src/Lib.hs" (pureFiles fs) `shouldBe` True
      Map.member "LICENSE" (pureFiles fs) `shouldBe` True
      Map.member "cabal.project" (pureFiles fs) `shouldBe` True
      -- Verify FileRecords for manifest
      Map.member "README.md" records `shouldBe` True
      Map.member "my-app.cabal" records `shouldBe` True
      Map.member "src/Lib.hs" records `shouldBe` True
      -- Verify content
      Map.lookup "README.md" (pureFiles fs) `shouldBe` Just "# my-app\n\nVersion: 0.1.0.0\n"

    it "re-run with same plan shows all unchanged" $ do
      (modul, ops) <- compileFixturePlan [("project.name", "my-app")]
      let modName = moduleName modul
          planned = extractPlanned modName ops
          -- First run: execute to get filesystem state and records
          (records, fs) =
            runPureEff $
              runFilesystemPure emptyFS $
                executePlan "" ops modName fixedTime
          -- Build manifest from first run
          manifest =
            (emptyManifest fixedTime)
              { manifestFiles = records
              }
          -- Re-run: compute diff against same plan and same FS
          (diff, _) =
            runPureEff $
              runFilesystemPure fs $
                computeDiff manifest planned
      -- All files should be unchanged
      length (diffNew diff) `shouldBe` 0
      length (diffModified diff) `shouldBe` 0
      length (diffConflict diff) `shouldBe` 0
      length (diffOrphaned diff) `shouldBe` 0
      length (diffUnchanged diff) `shouldBe` 5

    it "re-run with changed variable shows modified, new, and orphaned" $ do
      (modul, ops1) <- compileFixturePlan [("project.name", "my-app")]
      let modName = moduleName modul
          -- First run
          (records, fs) =
            runPureEff $
              runFilesystemPure emptyFS $
                executePlan "" ops1 modName fixedTime
          manifest = (emptyManifest fixedTime) {manifestFiles = records}
      -- Compile with changed variable
      (_, ops2) <- compileFixturePlan [("project.name", "other-app")]
      let planned2 = extractPlanned modName ops2
          (diff, _) =
            runPureEff $
              runFilesystemPure fs $
                computeDiff manifest planned2
      -- README.md and cabal.project have different content → Modified
      length (diffModified diff) `shouldBe` 2
      -- src/Lib.hs and LICENSE have same content → Unchanged
      length (diffUnchanged diff) `shouldBe` 2
      -- my-app.cabal not in new plan → Orphaned
      length (diffOrphaned diff) `shouldBe` 1
      orphanedPath (head (diffOrphaned diff)) `shouldBe` "my-app.cabal"
      -- other-app.cabal is new → New
      length (diffNew diff) `shouldBe` 1
      plannedPath (head (diffNew diff)) `shouldBe` "other-app.cabal"
      -- No conflicts
      length (diffConflict diff) `shouldBe` 0

    it "dryRunPlan lists all operations without execution" $ do
      (_, ops) <- compileFixturePlan [("project.name", "my-app")]
      let text = dryRunPlan ops
      T.isInfixOf "README.md" text `shouldBe` True
      T.isInfixOf "my-app.cabal" text `shouldBe` True
      T.isInfixOf "cabal.project" text `shouldBe` True

    it "force mode: re-execute after user edit overwrites the file" $ do
      (modul, ops) <- compileFixturePlan [("project.name", "my-app")]
      let modName = moduleName modul
          planned = extractPlanned modName ops
          -- First run
          (records, fs1) =
            runPureEff $
              runFilesystemPure emptyFS $
                executePlan "" ops modName fixedTime
          manifest = (emptyManifest fixedTime) {manifestFiles = records}
          -- Simulate user editing README.md
          fs2 = fs1 {pureFiles = Map.insert "README.md" "user edit" (pureFiles fs1)}
          -- Compute diff → should detect conflict
          (diff, _) =
            runPureEff $
              runFilesystemPure fs2 $
                computeDiff manifest planned
      -- README.md is a conflict (user edited, plan unchanged)
      length (diffConflict diff) `shouldBe` 1
      conflictPath (head (diffConflict diff)) `shouldBe` "README.md"
      -- Force: re-execute (overwrites user changes)
      let (_, fs3) =
            runPureEff $
              runFilesystemPure fs2 $
                executePlan "" ops modName fixedTime
      -- Verify README.md was overwritten with plan content
      Map.lookup "README.md" (pureFiles fs3) `shouldBe` Just "# my-app\n\nVersion: 0.1.0.0\n"

    it "records correct strategy per file in FileRecords" $ do
      (modul, ops) <- compileFixturePlan [("project.name", "my-app")]
      let modName = moduleName modul
          (records, _) =
            runPureEff $
              runFilesystemPure emptyFS $
                executePlan "" ops modName fixedTime
      -- README.md → Template
      fileStrategy (records Map.! "README.md") `shouldBe` Template
      -- src/Lib.hs → Template
      fileStrategy (records Map.! "src/Lib.hs") `shouldBe` Template
      -- LICENSE → Copy
      fileStrategy (records Map.! "LICENSE") `shouldBe` Copy
      -- my-app.cabal → Template
      fileStrategy (records Map.! "my-app.cabal") `shouldBe` Template
      -- cabal.project → DhallText
      fileStrategy (records Map.! "cabal.project") `shouldBe` DhallText
