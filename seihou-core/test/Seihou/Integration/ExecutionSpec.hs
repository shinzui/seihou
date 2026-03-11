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
resolvedValues = Map.map (.value)

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
      case resolveVariables (modul.vars) cli env "" "" Map.empty Map.empty Map.empty Map.empty Map.empty of
        Left errs -> error ("Failed to resolve: " <> show errs)
        Right resolved -> do
          planResult <- compilePlan (fixtures </> "haskell-base") modul (resolvedValues resolved)
          case planResult of
            Left errs -> error ("Plan failed: " <> show errs)
            Right ops -> pure (modul, ops)

-- | Helper to create a manifest with file records (avoids ambiguous record update).
manifestWithFiles :: UTCTime -> Map.Map FilePath FileRecord -> Manifest
manifestWithFiles t recs =
  let base = emptyManifest t
   in Manifest
        { version = base.version,
          genAt = base.genAt,
          modules = base.modules,
          vars = base.vars,
          files = recs
        }

-- | Extract planned files from operations for computeDiff.
extractPlanned :: ModuleName -> [Operation] -> [(FilePath, Text, ModuleName)]
extractPlanned modName' ops =
  [(dest, content, modName') | WriteFileOp dest content _ <- ops]
    ++ [(dest, content, mName) | PatchFileOp dest content _ _ mName <- ops]

spec :: Spec
spec = do
  describe "full execution pipeline" $ do
    it "first run creates files and builds file records" $ do
      (modul, ops) <- compileFixturePlan [("project.name", "my-app")]
      let modName = modul.name
          (records, fs) =
            runPureEff $
              runFilesystemPure emptyFS $
                executePlan "" ops modName fixedTime
      -- Verify files were created in the filesystem
      Map.member "README.md" (fs.files) `shouldBe` True
      Map.member "my-app.cabal" (fs.files) `shouldBe` True
      Map.member "src/Lib.hs" (fs.files) `shouldBe` True
      Map.member "LICENSE" (fs.files) `shouldBe` True
      Map.member "cabal.project" (fs.files) `shouldBe` True
      -- Verify FileRecords for manifest
      Map.member "README.md" records `shouldBe` True
      Map.member "my-app.cabal" records `shouldBe` True
      Map.member "src/Lib.hs" records `shouldBe` True
      -- Verify content
      Map.lookup "README.md" (fs.files) `shouldBe` Just "# my-app\n\nVersion: 0.1.0.0\n"

    it "re-run with same plan shows all unchanged" $ do
      (modul, ops) <- compileFixturePlan [("project.name", "my-app")]
      let modName = modul.name
          planned = extractPlanned modName ops
          -- First run: execute to get filesystem state and records
          (records, fs) =
            runPureEff $
              runFilesystemPure emptyFS $
                executePlan "" ops modName fixedTime
          -- Build manifest from first run
          manifest = manifestWithFiles fixedTime records
          -- Re-run: compute diff against same plan and same FS
          (diff, _) =
            runPureEff $
              runFilesystemPure fs $
                computeDiff manifest planned
      -- All files should be unchanged
      length (diff.new) `shouldBe` 0
      length (diff.modified) `shouldBe` 0
      length (diff.conflicts) `shouldBe` 0
      length (diff.orphaned) `shouldBe` 0
      length (diff.unchanged) `shouldBe` 5

    it "re-run with changed variable shows modified, new, and orphaned" $ do
      (modul, ops1) <- compileFixturePlan [("project.name", "my-app")]
      let modName = modul.name
          -- First run
          (records, fs) =
            runPureEff $
              runFilesystemPure emptyFS $
                executePlan "" ops1 modName fixedTime
          manifest = manifestWithFiles fixedTime records
      -- Compile with changed variable
      (_, ops2) <- compileFixturePlan [("project.name", "other-app")]
      let planned2 = extractPlanned modName ops2
          (diff, _) =
            runPureEff $
              runFilesystemPure fs $
                computeDiff manifest planned2
      -- README.md and cabal.project have different content → Modified
      length (diff.modified) `shouldBe` 2
      -- src/Lib.hs and LICENSE have same content → Unchanged
      length (diff.unchanged) `shouldBe` 2
      -- my-app.cabal not in new plan → Orphaned
      length (diff.orphaned) `shouldBe` 1
      (head diff.orphaned).path `shouldBe` "my-app.cabal"
      -- other-app.cabal is new → New
      length (diff.new) `shouldBe` 1
      (head diff.new).path `shouldBe` "other-app.cabal"
      -- No conflicts
      length (diff.conflicts) `shouldBe` 0

    it "dryRunPlan lists all operations without execution" $ do
      (_, ops) <- compileFixturePlan [("project.name", "my-app")]
      let text = dryRunPlan ops
      T.isInfixOf "README.md" text `shouldBe` True
      T.isInfixOf "my-app.cabal" text `shouldBe` True
      T.isInfixOf "cabal.project" text `shouldBe` True

    it "force mode: re-execute after user edit overwrites the file" $ do
      (modul, ops) <- compileFixturePlan [("project.name", "my-app")]
      let modName = modul.name
          planned = extractPlanned modName ops
          -- First run
          (records, fs1) =
            runPureEff $
              runFilesystemPure emptyFS $
                executePlan "" ops modName fixedTime
          manifest = manifestWithFiles fixedTime records
          -- Simulate user editing README.md
          fs2 = PureFS (Map.insert "README.md" "user edit" fs1.files) fs1.dirs
          -- Compute diff → should detect conflict
          (diff, _) =
            runPureEff $
              runFilesystemPure fs2 $
                computeDiff manifest planned
      -- README.md is a conflict (user edited, plan unchanged)
      length (diff.conflicts) `shouldBe` 1
      (head diff.conflicts).path `shouldBe` "README.md"
      -- Force: re-execute (overwrites user changes)
      let (_, fs3) =
            runPureEff $
              runFilesystemPure fs2 $
                executePlan "" ops modName fixedTime
      -- Verify README.md was overwritten with plan content
      Map.lookup "README.md" fs3.files `shouldBe` Just "# my-app\n\nVersion: 0.1.0.0\n"

    it "records correct strategy per file in FileRecords" $ do
      (modul, ops) <- compileFixturePlan [("project.name", "my-app")]
      let modName = modul.name
          (records, _) =
            runPureEff $
              runFilesystemPure emptyFS $
                executePlan "" ops modName fixedTime
      -- README.md → Template
      (records Map.! "README.md").strategy `shouldBe` Template
      -- src/Lib.hs → Template
      (records Map.! "src/Lib.hs").strategy `shouldBe` Template
      -- LICENSE → Copy
      (records Map.! "LICENSE").strategy `shouldBe` Copy
      -- my-app.cabal → Template
      (records Map.! "my-app.cabal").strategy `shouldBe` Template
      -- cabal.project → DhallText
      (records Map.! "cabal.project").strategy `shouldBe` DhallText
