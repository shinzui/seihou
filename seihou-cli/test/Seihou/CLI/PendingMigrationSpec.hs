module Seihou.CLI.PendingMigrationSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Time (UTCTime, defaultTimeLocale, parseTimeOrError)
import Seihou.CLI.Migrate (pendingChainFor)
import Seihou.CLI.PendingMigrations
  ( detectPendingMigrations,
    formatRefusalMessage,
  )
import Seihou.Core.Migration
  ( Migration (..),
    MigrationOp (..),
    MigrationPlan (..),
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

    it "returns Just plan with full chain when manifest is behind installed" $ do
      let mig = Migration "1.0.0" "2.0.0" [DeleteFile "Setup.hs"]
          am = mkApplied (Just "1.0.0")
          installed = mkInstalled (Just "2.0.0") [mig]
      case pendingChainFor am installed of
        Just plan -> do
          plan.planSteps `shouldBe` [mig]
          plan.planTo `shouldBe` parseV "2.0.0"
        Nothing -> expectationFailure "expected Just plan"

    it "returns Nothing for downgrade (manifest > installed)" $ do
      let am = mkApplied (Just "2.0.0")
          installed = mkInstalled (Just "1.0.0") []
      pendingChainFor am installed `shouldBe` Nothing

    it "returns a partial-cover plan when the chain reaches some intermediate version" $ do
      -- master-plan live-tree fixture: manifest=0.1.0, installed=0.3.0,
      -- edges=[0.1.0 -> 0.2.0]. Under the gap-tolerant walker the plan
      -- always carries the supplied target as planTo, regardless of
      -- whether the steps reach it.
      let am = mkApplied (Just "0.1.0")
          mig = Migration "0.1.0" "0.2.0" [DeleteFile "x"]
          installed = mkInstalled (Just "0.3.0") [mig]
      case pendingChainFor am installed of
        Just plan -> do
          plan.planSteps `shouldBe` [mig]
          plan.planFrom `shouldBe` parseV "0.1.0"
          plan.planTo `shouldBe` parseV "0.3.0"
        Nothing -> expectationFailure "expected Just plan with partial cover"

    it "returns an empty-steps plan when no edge starts at the manifest version" $ do
      let am = mkApplied (Just "0.1.3")
          installed = mkInstalled (Just "0.3.0") []
      case pendingChainFor am installed of
        Just plan -> do
          plan.planSteps `shouldBe` []
          plan.planFrom `shouldBe` parseV "0.1.3"
          plan.planTo `shouldBe` parseV "0.3.0"
        Nothing -> expectationFailure "expected Just plan with empty steps"

    it "[] vs [orphanEdge] both yield empty-steps plans (window walker)" $ do
      -- Under the gap-tolerant walker an orphan edge entirely outside
      -- the [installed, target] window contributes nothing — same plan
      -- shape as no migrations declared at all.
      let am = mkApplied (Just "0.2.0")
          emptyInstalled = mkInstalled (Just "0.3.0") []
          orphanInstalled =
            mkInstalled (Just "0.3.0") [Migration "0.5.0" "0.6.0" []]
      case (pendingChainFor am emptyInstalled, pendingChainFor am orphanInstalled) of
        (Just pEmpty, Just pOrphan) -> do
          pEmpty.planSteps `shouldBe` []
          pOrphan.planSteps `shouldBe` []
          pEmpty.planFrom `shouldBe` pOrphan.planFrom
          pEmpty.planTo `shouldBe` pOrphan.planTo
        other ->
          expectationFailure
            ("expected two Just plans, got: " <> show other)

  describe "detectPendingMigrations" $ do
    it "with Nothing filter, surfaces every applied module's pending plan" $
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
    it "lists each module's plan summary and the actionable next step" $ do
      let plan =
            MigrationPlan
              { planModule = "demo",
                planFrom = parseV "1.0.0",
                planTo = parseV "2.0.0",
                planSteps =
                  [Migration "1.0.0" "2.0.0" [DeleteFile "Setup.hs"]]
              }
          msg = formatRefusalMessage [(ModuleName "demo", plan)]
      msg `shouldSatisfy` T.isInfixOf "Pending migrations detected:"
      msg `shouldSatisfy` T.isInfixOf "demo: 1.0.0 -> 2.0.0 (1 step(s))"
      msg `shouldSatisfy` T.isInfixOf "--with-migrations"
      msg `shouldSatisfy` T.isInfixOf "seihou migrate <module>"

    it "reports a 0-step pure version-bump entry without doomed vocabulary" $ do
      let plan =
            MigrationPlan
              { planModule = "demo",
                planFrom = parseV "0.2.0",
                planTo = parseV "0.3.0",
                planSteps = []
              }
          msg = formatRefusalMessage [(ModuleName "demo", plan)]
      msg `shouldSatisfy` T.isInfixOf "demo: 0.2.0 -> 0.3.0 (0 step(s))"
      msg `shouldNotSatisfy` T.isInfixOf "Blocked"
      msg `shouldNotSatisfy` T.isInfixOf "--bump-only"
      msg `shouldNotSatisfy` T.isInfixOf "--bump-blocked"

parseV :: Text -> Seihou.Core.Version.Version
parseV t = case Seihou.Core.Version.parseVersion t of
  Just v -> v
  Nothing -> error ("test fixture: unparseable version " <> T.unpack t)
