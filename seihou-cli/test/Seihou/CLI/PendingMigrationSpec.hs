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
    isBenignUpgrade,
  )
import Seihou.Core.Migration
  ( Migration (..),
    MigrationChain (..),
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

    it "returns Just plan with full chain when manifest is behind installed" $ do
      let mig = Migration "1.0.0" "2.0.0" [DeleteFile "Setup.hs"]
          am = mkApplied (Just "1.0.0")
          installed = mkInstalled (Just "2.0.0") [mig]
      case pendingChainFor am installed of
        Just plan -> do
          plan.planUnreachable `shouldBe` Nothing
          plan.planChain.chainSteps `shouldBe` [mig]
        Nothing -> expectationFailure "expected Just plan"

    it "returns Nothing for downgrade (manifest > installed)" $ do
      let am = mkApplied (Just "2.0.0")
          installed = mkInstalled (Just "1.0.0") []
      pendingChainFor am installed `shouldBe` Nothing

    -- EP-5: partial chain returns a plan with the unreachable tail
    -- in-band rather than collapsing to Nothing. This is the master-plan
    -- live-tree fixture (manifest=0.1.0, installed=0.3.0,
    -- edges=[0.1.0 -> 0.2.0]).
    it "returns a partial plan when the chain reaches some intermediate version" $ do
      let am = mkApplied (Just "0.1.0")
          mig = Migration "0.1.0" "0.2.0" [DeleteFile "x"]
          installed = mkInstalled (Just "0.3.0") [mig]
      case pendingChainFor am installed of
        Just plan -> do
          plan.planChain.chainSteps `shouldBe` [mig]
          plan.planUnreachable `shouldSatisfy` \mt -> case mt of
            Just (s, t) ->
              Seihou.Core.Version.renderVersion s == "0.2.0"
                && Seihou.Core.Version.renderVersion t == "0.3.0"
            Nothing -> False
        Nothing -> expectationFailure "expected Just plan with partial chain"

    -- EP-5: blocked plan returns an empty chain plus the unreachable
    -- tail covering the full span. Live-tree exec-plan fixture
    -- (manifest=0.1.3, installed=0.3.0, no migrations declared).
    it "returns a blocked plan when no edge starts at the manifest version" $ do
      let am = mkApplied (Just "0.1.3")
          installed = mkInstalled (Just "0.3.0") []
      case pendingChainFor am installed of
        Just plan -> do
          plan.planChain.chainSteps `shouldBe` []
          plan.planUnreachable `shouldSatisfy` \mt -> case mt of
            Just (s, t) ->
              Seihou.Core.Version.renderVersion s == "0.1.3"
                && Seihou.Core.Version.renderVersion t == "0.3.0"
            Nothing -> False
        Nothing -> expectationFailure "expected Just plan with blocked chain"

    -- M1 pin, flipped in M3: pendingChainFor still surfaces both
    -- cases (the chain-level shape is identical), but
    -- planMigrationsDeclared now lets consumers distinguish them.
    it "distinguishes [] vs [orphanEdge] via planMigrationsDeclared" $ do
      let am = mkApplied (Just "0.2.0")
          emptyInstalled = mkInstalled (Just "0.3.0") []
          orphanInstalled =
            mkInstalled (Just "0.3.0") [Migration "0.5.0" "0.6.0" []]
      case (pendingChainFor am emptyInstalled, pendingChainFor am orphanInstalled) of
        (Just pEmpty, Just pOrphan) -> do
          pEmpty.planChain.chainSteps `shouldBe` []
          pOrphan.planChain.chainSteps `shouldBe` []
          pEmpty.planChain.chainFrom `shouldBe` pOrphan.planChain.chainFrom
          pEmpty.planChain.chainTo `shouldBe` pOrphan.planChain.chainTo
          pEmpty.planUnreachable `shouldBe` pOrphan.planUnreachable
          pEmpty.planMigrationsDeclared `shouldBe` False
          pOrphan.planMigrationsDeclared `shouldBe` True
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
      let plan =
            MigrationPlan
              { planChain =
                  MigrationChain
                    { migrationModule = "demo",
                      chainFrom = parseV "1.0.0",
                      chainTo = parseV "2.0.0",
                      chainSteps =
                        [Migration "1.0.0" "2.0.0" [DeleteFile "Setup.hs"]]
                    },
                planUnreachable = Nothing,
                planMigrationsDeclared = True
              }
          msg = formatRefusalMessage [(ModuleName "demo", plan)]
      msg `shouldSatisfy` T.isInfixOf "Pending migrations detected:"
      msg `shouldSatisfy` T.isInfixOf "demo: 1.0.0 -> 2.0.0 (1 step(s))"
      msg `shouldSatisfy` T.isInfixOf "--with-migrations"
      msg `shouldSatisfy` T.isInfixOf "seihou migrate <module>"

    -- EP-5: partial-chain rows include the unreachable-tail advisory
    -- so the user knows the chain doesn't reach the latest remote
    -- version even after they apply it.
    it "annotates a partial-chain entry with the unreachable tail" $ do
      let plan =
            MigrationPlan
              { planChain =
                  MigrationChain
                    { migrationModule = "demo",
                      chainFrom = parseV "0.1.0",
                      chainTo = parseV "0.2.0",
                      chainSteps = [Migration "0.1.0" "0.2.0" []]
                    },
                planUnreachable = Just (parseV "0.2.0", parseV "0.3.0"),
                planMigrationsDeclared = True
              }
          msg = formatRefusalMessage [(ModuleName "demo", plan)]
      msg `shouldSatisfy` T.isInfixOf "demo: 0.1.0 -> 0.2.0"
      msg `shouldSatisfy` T.isInfixOf "no migration declared from 0.2.0"
      msg `shouldSatisfy` T.isInfixOf "remote is at 0.3.0"

    -- EP-5: blocked rows print a Blocked: prefix and skip the chain
    -- summary (there are no steps to summarize). After M3 the
    -- "Blocked:" wording only fires when planMigrationsDeclared is
    -- True (the author shipped at least one migration but the chain
    -- doesn't reach the manifest version).
    it "prints a Blocked entry when the plan has no reachable steps and migrations were declared" $ do
      let plan =
            MigrationPlan
              { planChain =
                  MigrationChain
                    { migrationModule = "demo",
                      chainFrom = parseV "0.1.3",
                      chainTo = parseV "0.1.3",
                      chainSteps = []
                    },
                planUnreachable = Just (parseV "0.1.3", parseV "0.3.0"),
                planMigrationsDeclared = True
              }
          msg = formatRefusalMessage [(ModuleName "demo", plan)]
      msg `shouldSatisfy` T.isInfixOf "demo: Blocked: no migration declared from 0.1.3"
      msg `shouldSatisfy` T.isInfixOf "remote is at 0.3.0"

    -- EP-7 / M2: when the input contains a blocked entry, the trailer
    -- names --bump-only (per-module) and --bump-blocked (one-command)
    -- as the recoveries. The legacy "pass --with-migrations" sentence
    -- is reserved for runnable (full / partial) entries.
    it "blocked-only trailer names --bump-only and --bump-blocked" $ do
      let plan =
            MigrationPlan
              { planChain =
                  MigrationChain
                    { migrationModule = "demo",
                      chainFrom = parseV "0.1.3",
                      chainTo = parseV "0.1.3",
                      chainSteps = []
                    },
                planUnreachable = Just (parseV "0.1.3", parseV "0.3.0"),
                planMigrationsDeclared = True
              }
          msg = formatRefusalMessage [(ModuleName "demo", plan)]
      msg `shouldSatisfy` T.isInfixOf "seihou migrate <module> --bump-only"
      msg `shouldSatisfy` T.isInfixOf "seihou run --bump-blocked"
      msg `shouldNotSatisfy` T.isInfixOf "pass --with-migrations"

    -- EP-7 / M2: a mixed input (one blocked + one runnable) gets both
    -- the bump-only / bump-blocked recovery and the --with-migrations
    -- recovery, joined.
    it "mixed trailer names both blocked recoveries and --with-migrations" $ do
      let blocked =
            MigrationPlan
              { planChain =
                  MigrationChain
                    { migrationModule = "blocked-mod",
                      chainFrom = parseV "0.1.3",
                      chainTo = parseV "0.1.3",
                      chainSteps = []
                    },
                planUnreachable = Just (parseV "0.1.3", parseV "0.3.0"),
                planMigrationsDeclared = True
              }
          runnable =
            MigrationPlan
              { planChain =
                  MigrationChain
                    { migrationModule = "runnable-mod",
                      chainFrom = parseV "1.0.0",
                      chainTo = parseV "2.0.0",
                      chainSteps = [Migration "1.0.0" "2.0.0" [DeleteFile "x"]]
                    },
                planUnreachable = Nothing,
                planMigrationsDeclared = True
              }
          msg =
            formatRefusalMessage
              [ (ModuleName "blocked-mod", blocked),
                (ModuleName "runnable-mod", runnable)
              ]
      msg `shouldSatisfy` T.isInfixOf "--bump-only"
      msg `shouldSatisfy` T.isInfixOf "--bump-blocked"
      msg `shouldSatisfy` T.isInfixOf "--with-migrations"

    -- M3: a benign upgrade entry (planMigrationsDeclared = False)
    -- routes through the softened branch in formatRefusalMessage.
    -- M5 strips benign entries from the input before calling this
    -- formatter, so this is the defensive fallback. The renderer
    -- must not say "Blocked:" for a benign case.
    it "softens benign entries when planMigrationsDeclared is False" $ do
      let plan =
            MigrationPlan
              { planChain =
                  MigrationChain
                    { migrationModule = "demo",
                      chainFrom = parseV "0.2.0",
                      chainTo = parseV "0.2.0",
                      chainSteps = []
                    },
                planUnreachable = Just (parseV "0.2.0", parseV "0.3.0"),
                planMigrationsDeclared = False
              }
          msg = formatRefusalMessage [(ModuleName "demo", plan)]
      msg `shouldSatisfy` T.isInfixOf "no migrations declared"
      msg `shouldSatisfy` T.isInfixOf "0.2.0 -> 0.3.0"
      msg `shouldNotSatisfy` T.isInfixOf "Blocked:"

  describe "isBenignUpgrade" $ do
    -- M5: the run pre-flight uses this predicate to partition pending
    -- entries into benign (no destructive op; let the run flow's
    -- updateAllModules catch the manifest up) vs blocking (refuse,
    -- summarize in dry-run, or apply in --with-migrations mode).
    let mkPlan :: [Migration] -> Bool -> MigrationPlan
        mkPlan steps declared =
          MigrationPlan
            { planChain =
                MigrationChain
                  { migrationModule = "demo",
                    chainFrom = parseV "0.2.0",
                    chainTo = parseV "0.2.0",
                    chainSteps = steps
                  },
              planUnreachable = Just (parseV "0.2.0", parseV "0.3.0"),
              planMigrationsDeclared = declared
            }

    it "is True for an empty chain with planMigrationsDeclared = False" $
      isBenignUpgrade (mkPlan [] False) `shouldBe` True

    it "is False for an empty chain with planMigrationsDeclared = True (real block)" $
      isBenignUpgrade (mkPlan [] True) `shouldBe` False

    it "is False for a non-empty chain regardless of declared bit" $ do
      let stepped = [Migration "0.2.0" "0.3.0" []]
      isBenignUpgrade (mkPlan stepped True) `shouldBe` False
      -- Defensive: the planner cannot produce stepped + declared=False,
      -- but the predicate must still say "not benign" because work
      -- needs doing.
      isBenignUpgrade (mkPlan stepped False) `shouldBe` False

parseV :: Text -> Seihou.Core.Version.Version
parseV t = case Seihou.Core.Version.parseVersion t of
  Just v -> v
  Nothing -> error ("test fixture: unparseable version " <> T.unpack t)
