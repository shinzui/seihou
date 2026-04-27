module Seihou.CLI.PendingMigrationSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Time (UTCTime, defaultTimeLocale, parseTimeOrError)
import Seihou.CLI.Migrate (pendingChainFor)
import Seihou.CLI.PendingMigrations (detectPendingMigrations, formatRefusalMessage)
import Seihou.Core.Migration
  ( Migration (..),
    MigrationChain (..),
    MigrationOp (..),
  )
import Seihou.Core.Types
  ( AppliedModule (..),
    Manifest (..),
    Module (..),
    ModuleName (..),
    emptyParentVars,
  )
import Seihou.Core.Version qualified
import Seihou.Manifest.Types (emptyManifest)
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.CLI.PendingMigration" spec

fixedTime :: UTCTime
fixedTime =
  parseTimeOrError
    True
    defaultTimeLocale
    "%Y-%m-%dT%H:%M:%SZ"
    "2026-04-01T10:00:00Z"

mkApplied :: Maybe Text -> AppliedModule
mkApplied mver =
  AppliedModule
    { name = ModuleName "demo",
      parentVars = emptyParentVars,
      source = "/installed/demo",
      moduleVersion = mver,
      appliedAt = fixedTime,
      removal = Nothing
    }

mkInstalled :: Maybe Text -> [Migration] -> Module
mkInstalled v migs =
  Module
    { name = ModuleName "demo",
      version = v,
      description = Nothing,
      vars = [],
      exports = [],
      prompts = [],
      steps = [],
      commands = [],
      dependencies = [],
      removal = Nothing,
      migrations = migs
    }

-- | Write a minimal but parseable @module.dhall@ for a fixture module.
-- Mirrors the helper in MigrateSpec — kept inline here so this spec
-- stays self-contained.
writeInstalledModule :: FilePath -> Text -> Text -> Text -> IO ()
writeInstalledModule dir name version migrationsLit = do
  createDirectoryIfMissing True dir
  TIO.writeFile (dir </> "module.dhall") body
  where
    body =
      T.unlines
        [ "{ name = \"" <> name <> "\"",
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
-- between 1.0.0 and 2.0.0.
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

emptyMigrationsLit :: Text
emptyMigrationsLit =
  "[] : List { from : Text, to : Text, ops : List < MoveFile : { src : Text, dest : Text } | MoveDir : { src : Text, dest : Text } | DeleteFile : { path : Text } | DeleteDir : { path : Text } | RunCommand : { run : Text, workDir : Optional Text } > }"

mkAppliedAt :: Text -> FilePath -> Maybe Text -> AppliedModule
mkAppliedAt name source mver =
  AppliedModule
    { name = ModuleName name,
      parentVars = emptyParentVars,
      source = source,
      moduleVersion = mver,
      appliedAt = fixedTime,
      removal = Nothing
    }

spec :: Spec
spec = do
  describe "pendingChainFor" $ do
    it "returns Nothing when manifest has no recorded version" $ do
      let am = mkApplied Nothing
          installed = mkInstalled (Just "2.0.0") [Migration "1.0.0" "2.0.0" []]
      pendingChainFor am installed `shouldBe` Nothing

    it "returns Nothing when installed has no version" $ do
      let am = mkApplied (Just "1.0.0")
          installed = mkInstalled Nothing []
      pendingChainFor am installed `shouldBe` Nothing

    it "returns Nothing when versions match (no chain)" $ do
      let am = mkApplied (Just "1.0.0")
          installed = mkInstalled (Just "1.0.0") []
      pendingChainFor am installed `shouldBe` Nothing

    it "returns Just chain when manifest is behind installed" $ do
      let mig = Migration "1.0.0" "2.0.0" [DeleteFile "Setup.hs"]
          am = mkApplied (Just "1.0.0")
          installed = mkInstalled (Just "2.0.0") [mig]
      case pendingChainFor am installed of
        Just chain -> chain.chainSteps `shouldBe` [mig]
        Nothing -> expectationFailure "expected Just chain"

    it "returns Nothing when no migration covers the gap" $ do
      let am = mkApplied (Just "1.0.0")
          installed = mkInstalled (Just "2.0.0") []
      pendingChainFor am installed `shouldBe` Nothing

    it "returns Nothing for downgrade (manifest > installed)" $ do
      let am = mkApplied (Just "2.0.0")
          installed = mkInstalled (Just "1.0.0") []
      pendingChainFor am installed `shouldBe` Nothing

    -- Pin the current partial-chain silence (mirrors live-tree
    -- master-plan: manifest=0.1.0, installed=0.3.0, edges=[0.1.0→0.2.0]).
    -- EP-5 will flip this to a Just plan with reachable prefix +
    -- unreachable tail.
    it "currently returns Nothing for a partial chain (pinned for EP-5)" $ do
      let am = mkApplied (Just "0.1.0")
          installed =
            mkInstalled (Just "0.3.0") [Migration "0.1.0" "0.2.0" []]
      pendingChainFor am installed `shouldBe` Nothing

    -- Pin the current no-chain-at-all silence (mirrors live-tree
    -- exec-plan: manifest=0.1.3, installed=0.3.0, no migrations).
    it "currently returns Nothing when no edge starts at the manifest version (pinned for EP-5)" $ do
      let am = mkApplied (Just "0.1.3")
          installed = mkInstalled (Just "0.3.0") []
      pendingChainFor am installed `shouldBe` Nothing

  describe "detectPendingMigrations" $ do
    it "with Nothing filter, surfaces every applied module's pending chain" $
      withSystemTempDirectory "seihou-pending-detect" $ \dir -> do
        let aDir = dir </> "demo-a"
            bDir = dir </> "demo-b"
        writeInstalledModule aDir "demo-a" "2.0.0" moveOldToNewLit
        writeInstalledModule bDir "demo-b" "2.0.0" moveOldToNewLit
        let manifest =
              (emptyManifest fixedTime)
                { modules =
                    [ mkAppliedAt "demo-a" aDir (Just "1.0.0"),
                      mkAppliedAt "demo-b" bDir (Just "1.0.0")
                    ],
                  files = Map.empty
                }
        result <- detectPendingMigrations manifest Nothing
        map fst result `shouldMatchList` [ModuleName "demo-a", ModuleName "demo-b"]

    it "with a Just filter, restricts detection to the named modules" $
      withSystemTempDirectory "seihou-pending-detect" $ \dir -> do
        let aDir = dir </> "demo-a"
            bDir = dir </> "demo-b"
        writeInstalledModule aDir "demo-a" "2.0.0" moveOldToNewLit
        writeInstalledModule bDir "demo-b" "2.0.0" moveOldToNewLit
        let manifest =
              (emptyManifest fixedTime)
                { modules =
                    [ mkAppliedAt "demo-a" aDir (Just "1.0.0"),
                      mkAppliedAt "demo-b" bDir (Just "1.0.0")
                    ],
                  files = Map.empty
                }
        result <-
          detectPendingMigrations
            manifest
            (Just (Set.singleton (ModuleName "demo-a")))
        map fst result `shouldBe` [ModuleName "demo-a"]

    it "skips modules whose installed copy has no module.dhall" $
      withSystemTempDirectory "seihou-pending-detect" $ \dir -> do
        let bogus = dir </> "missing-installed"
        let manifest =
              (emptyManifest fixedTime)
                { modules = [mkAppliedAt "demo" bogus (Just "1.0.0")],
                  files = Map.empty
                }
        result <- detectPendingMigrations manifest Nothing
        result `shouldBe` []

    it "skips modules with no pending chain (manifest already at installed version)" $
      withSystemTempDirectory "seihou-pending-detect" $ \dir -> do
        let modDir = dir </> "demo"
        writeInstalledModule modDir "demo" "1.0.0" emptyMigrationsLit
        let manifest =
              (emptyManifest fixedTime)
                { modules = [mkAppliedAt "demo" modDir (Just "1.0.0")],
                  files = Map.empty
                }
        result <- detectPendingMigrations manifest Nothing
        result `shouldBe` []

    -- This test mirrors the EP-3 milestone-5 expectation: a pending
    -- migration on a module that is *not* part of the current run
    -- composition must not block the run. We model that by setting
    -- the filter to the no-chain module's name only; the with-chain
    -- module's pending entry is ignored.
    it "with a filter selecting only no-chain modules, returns empty" $
      withSystemTempDirectory "seihou-pending-detect" $ \dir -> do
        let withChain = dir </> "with-chain"
            noChain = dir </> "no-chain"
        writeInstalledModule withChain "with-chain" "2.0.0" moveOldToNewLit
        writeInstalledModule noChain "no-chain" "1.0.0" emptyMigrationsLit
        let manifest =
              (emptyManifest fixedTime)
                { modules =
                    [ mkAppliedAt "with-chain" withChain (Just "1.0.0"),
                      mkAppliedAt "no-chain" noChain (Just "1.0.0")
                    ],
                  files = Map.empty
                }
        result <-
          detectPendingMigrations
            manifest
            (Just (Set.singleton (ModuleName "no-chain")))
        result `shouldBe` []

  describe "formatRefusalMessage" $ do
    it "lists each module's chain summary and the actionable next step" $ do
      let chain =
            MigrationChain
              { migrationModule = "demo",
                chainFrom = parseV "1.0.0",
                chainTo = parseV "2.0.0",
                chainSteps =
                  [Migration "1.0.0" "2.0.0" [DeleteFile "Setup.hs"]]
              }
          msg = formatRefusalMessage [(ModuleName "demo", chain)]
      msg `shouldSatisfy` T.isInfixOf "Pending migrations detected:"
      msg `shouldSatisfy` T.isInfixOf "demo: 1.0.0 -> 2.0.0 (1 step(s))"
      msg `shouldSatisfy` T.isInfixOf "--with-migrations"
      msg `shouldSatisfy` T.isInfixOf "seihou migrate <module>"

parseV :: Text -> Seihou.Core.Version.Version
parseV t = case Seihou.Core.Version.parseVersion t of
  Just v -> v
  Nothing -> error ("test fixture: unparseable version " <> T.unpack t)
