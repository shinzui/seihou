module Seihou.CLI.StatusSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (UTCTime, defaultTimeLocale, parseTimeOrError)
import Seihou.CLI.StatusRender (formatStatus)
import Seihou.CLI.VersionCompare
  ( OutdatedEntry (..),
    OutdatedStatus (..),
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
    ModuleName (..),
    emptyParentVars,
  )
import Seihou.Core.Version qualified
import Seihou.Manifest.Types (emptyManifest)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.CLI.StatusRender" spec

fixedTime :: UTCTime
fixedTime =
  parseTimeOrError
    True
    defaultTimeLocale
    "%Y-%m-%dT%H:%M:%SZ"
    "2026-04-15T10:00:00Z"

mkApplied :: Text -> Maybe Text -> AppliedModule
mkApplied name mver =
  AppliedModule
    { name = ModuleName name,
      parentVars = emptyParentVars,
      source = "/installed/" <> T.unpack name,
      moduleVersion = mver,
      appliedAt = fixedTime,
      removal = Nothing
    }

mkManifest :: [AppliedModule] -> Manifest
mkManifest mods =
  (emptyManifest fixedTime)
    { modules = mods,
      files = Map.empty
    }

mkChain :: Text -> Text -> Text -> Int -> MigrationChain
mkChain modName from to nSteps =
  MigrationChain
    { migrationModule = modName,
      chainFrom = parseV from,
      chainTo = parseV to,
      chainSteps = replicate nSteps (Migration from to [DeleteFile "x"])
    }

-- | Wrap a fully-reachable chain into a 'MigrationPlan' for formatStatus.
-- Defaults @planMigrationsDeclared@ to True since a non-empty chain
-- implies the module declared at least one migration.
fullPlan :: MigrationChain -> MigrationPlan
fullPlan chain =
  MigrationPlan
    { planChain = chain,
      planUnreachable = Nothing,
      planMigrationsDeclared = True,
      planTailExhausted = True
    }

parseV :: Text -> Seihou.Core.Version.Version
parseV t = case Seihou.Core.Version.parseVersion t of
  Just v -> v
  Nothing -> error ("test fixture: unparseable version " <> T.unpack t)

mkEntry :: Text -> Maybe Text -> Maybe Text -> OutdatedStatus -> OutdatedEntry
mkEntry name inst avail status =
  OutdatedEntry
    { moduleName = name,
      installedVersion = inst,
      availableVersion = avail,
      status = status
    }

spec :: Spec
spec = describe "formatStatus" $ do
  it "all modules clean: no remediation, no Recommended actions block" $ do
    let am = mkApplied "demo" (Just "1.0.0")
        manifest = mkManifest [am]
        entries = Just [mkEntry "demo" (Just "1.0.0") (Just "1.0.0") UpToDate]
        out = formatStatus False manifest [] entries []
    out `shouldSatisfy` T.isInfixOf "demo"
    out `shouldSatisfy` T.isInfixOf "up to date"
    out `shouldNotSatisfy` T.isInfixOf "Run: seihou"
    out `shouldNotSatisfy` T.isInfixOf "Recommended actions"
    out `shouldNotSatisfy` T.isInfixOf "Pending migration"

  it "outdated only (no migration declared): per-row upgrade hint and summary entry" $ do
    let am = mkApplied "demo" (Just "0.1.0")
        manifest = mkManifest [am]
        entries = Just [mkEntry "demo" (Just "0.1.0") (Just "0.3.0") OutdatedSt]
        out = formatStatus False manifest [] entries []
    out `shouldSatisfy` T.isInfixOf "outdated: 0.3.0 available"
    out `shouldSatisfy` T.isInfixOf "Run: seihou upgrade demo"
    out `shouldSatisfy` T.isInfixOf "Recommended actions:"
    out `shouldSatisfy` T.isInfixOf "  seihou upgrade demo"
    out `shouldNotSatisfy` T.isInfixOf "Pending migration"

  it "pending migration only (versions current): per-row migrate hint and summary" $ do
    let am = mkApplied "demo" (Just "1.0.0")
        manifest = mkManifest [am]
        chain = mkChain "demo" "1.0.0" "2.0.0" 1
        out = formatStatus False manifest [] Nothing [(ModuleName "demo", fullPlan chain)]
    out `shouldSatisfy` T.isInfixOf "Pending migration: 1.0.0 -> 2.0.0 (1 operation(s))"
    out `shouldSatisfy` T.isInfixOf "Run: seihou migrate demo"
    out `shouldSatisfy` T.isInfixOf "Recommended actions:"
    out `shouldSatisfy` T.isInfixOf "  seihou migrate demo"
    out `shouldNotSatisfy` T.isInfixOf "seihou upgrade"

  it "outdated + pending migration: single migrate hint, no upgrade hint" $ do
    let am = mkApplied "demo" (Just "0.1.0")
        manifest = mkManifest [am]
        chain = mkChain "demo" "0.1.0" "0.2.0" 6
        entries = Just [mkEntry "demo" (Just "0.1.0") (Just "0.3.0") OutdatedSt]
        out = formatStatus False manifest [] entries [(ModuleName "demo", fullPlan chain)]
    out `shouldSatisfy` T.isInfixOf "outdated: 0.3.0 available"
    out `shouldSatisfy` T.isInfixOf "Pending migration: 0.1.0 -> 0.2.0 (6 operation(s))"
    out `shouldSatisfy` T.isInfixOf "Run: seihou migrate demo"
    out `shouldNotSatisfy` T.isInfixOf "seihou upgrade demo"
    out `shouldSatisfy` T.isInfixOf "Recommended actions:"
    out `shouldSatisfy` T.isInfixOf "  seihou migrate demo"

  -- EP-5 + EP-28: partial chain with a BLOCKED tail (a future edge
  -- declared past the chain's stopping point but the chain doesn't
  -- span the gap). The advisory still names the unreachable tail in
  -- the legacy "no migration declared from X; remote is at Y" wording
  -- because `seihou migrate` will only apply the prefix and stop.
  it "partial migration (blocked tail): chain summary + unreachable-tail advisory" $ do
    let am = mkApplied "master-plan" (Just "0.1.0")
        manifest = mkManifest [am]
        chain = mkChain "master-plan" "0.1.0" "0.2.0" 1
        plan =
          MigrationPlan
            { planChain = chain,
              planUnreachable = Just (parseV "0.2.0", parseV "0.3.0"),
              planMigrationsDeclared = True,
              planTailExhausted = False
            }
        out = formatStatus False manifest [] Nothing [(ModuleName "master-plan", plan)]
    out `shouldSatisfy` T.isInfixOf "Pending migration: 0.1.0 -> 0.2.0"
    out `shouldSatisfy` T.isInfixOf "Run: seihou migrate master-plan"
    out `shouldSatisfy` T.isInfixOf "Note: no migration declared from 0.2.0"
    out `shouldSatisfy` T.isInfixOf "remote is at 0.3.0"
    out `shouldSatisfy` T.isInfixOf "Recommended actions:"
    out `shouldSatisfy` T.isInfixOf "  seihou migrate master-plan"

  -- EP-28: partial chain with an EXHAUSTED tail (no migration
  -- declared past the chain's stopping point). The status row tells
  -- the user that `seihou migrate` will bump through to the target
  -- in one shot.
  it "partial migration (exhausted tail): bump-through advisory in status" $ do
    let am = mkApplied "demo" (Just "0.1.0")
        manifest = mkManifest [am]
        chain = mkChain "demo" "0.1.0" "0.2.0" 1
        plan =
          MigrationPlan
            { planChain = chain,
              planUnreachable = Just (parseV "0.2.0", parseV "0.3.0"),
              planMigrationsDeclared = True,
              planTailExhausted = True
            }
        out = formatStatus False manifest [] Nothing [(ModuleName "demo", plan)]
    out `shouldSatisfy` T.isInfixOf "Pending migration: 0.1.0 -> 0.2.0"
    -- The new advisory line names "bump through" so the user
    -- understands one command will land them at the target.
    out `shouldSatisfy` T.isInfixOf "0.2.0 -> 0.3.0 has no declared migration"
    out `shouldSatisfy` T.isInfixOf "will bump through"
    out `shouldSatisfy` T.isInfixOf "Recommended actions:"
    out `shouldSatisfy` T.isInfixOf "  seihou migrate demo"
    -- The legacy "no migration declared from 0.2.0; remote is at 0.3.0"
    -- wording is gone for exhausted-tail rows (it still appears for
    -- blocked-tail rows, tested above).
    out `shouldNotSatisfy` T.isInfixOf "Note: no migration declared from 0.2.0"

  -- EP-7 / M2: blocked rendering now names --bump-only as the recovery
  -- path both inline (in the row text) and in the Recommended actions
  -- tail block (where it replaces the old [blocked] annotation). The
  -- "module author must ship one" finality sentence is gone.
  it "blocked migration: refusal row + bump-only command in Recommended actions" $ do
    let am = mkApplied "exec-plan" (Just "0.1.3")
        manifest = mkManifest [am]
        plan =
          MigrationPlan
            { planChain =
                MigrationChain
                  { migrationModule = "exec-plan",
                    chainFrom = parseV "0.1.3",
                    chainTo = parseV "0.1.3",
                    chainSteps = []
                  },
              planUnreachable = Just (parseV "0.1.3", parseV "0.3.0"),
              planMigrationsDeclared = True,
              planTailExhausted = False
            }
        out = formatStatus False manifest [] Nothing [(ModuleName "exec-plan", plan)]
    out `shouldSatisfy` T.isInfixOf "Blocked: no migration declared from 0.1.3"
    out `shouldSatisfy` T.isInfixOf "remote is at 0.3.0"
    out `shouldSatisfy` T.isInfixOf "Recommended actions:"
    -- The actionable command appears both in the inline advisory and
    -- as a copy-pasteable line in Recommended actions.
    out `shouldSatisfy` T.isInfixOf "seihou migrate exec-plan --bump-only"
    -- The [blocked] no-action annotation and the "module author must
    -- ship one" finality sentence are gone.
    out `shouldNotSatisfy` T.isInfixOf "[blocked]"
    out `shouldNotSatisfy` T.isInfixOf "module author must ship one"

  -- M1 pin, flipped in M4: an empty-migrations module with a version
  -- gap renders as a softened "Pending: … (no migrations declared)"
  -- advisory rather than the hard "Blocked: …" wording. The
  -- Recommended actions tail lists "seihou upgrade <name> && seihou
  -- run" because that is the actual remediation — no migration is
  -- needed and the run flow's updateAllModules brings the manifest
  -- up to date.
  it "renders empty-migrations + version-gap as a benign upgrade row" $ do
    let am = mkApplied "demo" (Just "0.2.0")
        manifest = mkManifest [am]
        plan =
          MigrationPlan
            { planChain =
                MigrationChain
                  { migrationModule = "demo",
                    chainFrom = parseV "0.2.0",
                    chainTo = parseV "0.2.0",
                    chainSteps = []
                  },
              planUnreachable = Just (parseV "0.2.0", parseV "0.3.0"),
              planMigrationsDeclared = False,
              planTailExhausted = True
            }
        out = formatStatus False manifest [] Nothing [(ModuleName "demo", plan)]
    out `shouldSatisfy` T.isInfixOf "Pending: 0.2.0 -> 0.3.0 (no migrations declared)"
    out `shouldSatisfy` T.isInfixOf "Run: seihou upgrade demo && seihou run"
    out `shouldSatisfy` T.isInfixOf "Recommended actions:"
    out `shouldSatisfy` T.isInfixOf "  seihou upgrade demo && seihou run"
    -- Benign rows do NOT use the EP-5 blocked language.
    out `shouldNotSatisfy` T.isInfixOf "Blocked:"
    out `shouldNotSatisfy` T.isInfixOf "[blocked]"
