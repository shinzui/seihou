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
    MigrationOp (..),
    MigrationPlan (..),
  )
import Seihou.Core.Types
  ( ApplicationId (..),
    AppliedBlueprint (..),
    AppliedComposition (..),
    AppliedInstanceState (..),
    AppliedModule (..),
    AppliedTarget (..),
    Manifest (..),
    ModuleName (..),
    RecipeName (..),
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

mkApplication :: Text -> [Text] -> AppliedComposition
mkApplication target modules =
  AppliedComposition
    { applicationId = ApplicationId ("app-" <> target),
      target = AppliedRecipeTarget (RecipeName target),
      targetSource = "/installed/" <> T.unpack target,
      targetVersion = Just "1.0.0",
      additionalModules = [],
      namespace = Nothing,
      context = Nothing,
      instances = map mkInstance modules,
      commandReceipts = Map.empty,
      appliedAt = fixedTime
    }
  where
    mkInstance name =
      AppliedInstanceState
        { name = ModuleName name,
          parentVars = emptyParentVars,
          source = "/installed/" <> T.unpack name,
          moduleVersion = Just "1.0.0",
          resolvedVars = Map.empty
        }

-- | Build a 'MigrationPlan' fixture for use with formatStatus.
mkPlan :: Text -> Text -> Text -> Int -> MigrationPlan
mkPlan modName from to nSteps =
  MigrationPlan
    { planModule = modName,
      planFrom = parseV from,
      planTo = parseV to,
      planSteps = replicate nSteps (Migration from to [DeleteFile "x"])
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

mkBlueprint ::
  Text ->
  Maybe Text ->
  [Text] ->
  Bool ->
  Maybe Text ->
  AppliedBlueprint
mkBlueprint name mver baselines noBL prompt =
  AppliedBlueprint
    { name = ModuleName name,
      blueprintVersion = mver,
      appliedAt = fixedTime,
      baselineModules = map ModuleName baselines,
      noBaseline = noBL,
      userPrompt = prompt,
      agentSessionId = Nothing
    }

withManifestBlueprint :: Maybe AppliedBlueprint -> Manifest -> Manifest
withManifestBlueprint mb m = m {blueprint = mb}

spec :: Spec
spec = describe "formatStatus" $ do
  describe "blueprint provenance" $ do
    it "renders a populated blueprint with version, two baselines, and prompt" $ do
      let manifest =
            withManifestBlueprint
              ( Just $
                  mkBlueprint
                    "payments-service"
                    (Just "0.3.1")
                    ["nix-flake", "haskell-base"]
                    False
                    (Just "set this up for a payments microservice")
              )
              (mkManifest [])
          out = formatStatus False manifest [] Nothing []
      out `shouldSatisfy` T.isInfixOf "Blueprint: payments-service v0.3.1 (applied"
      out `shouldSatisfy` T.isInfixOf "  Baseline: nix-flake, haskell-base"
      out `shouldSatisfy` T.isInfixOf "  Prompt: \"set this up for a payments microservice\""

    it "renders --no-baseline as the dedicated placeholder" $ do
      let manifest =
            withManifestBlueprint
              ( Just $
                  mkBlueprint "lone-blueprint" Nothing [] True Nothing
              )
              (mkManifest [])
          out = formatStatus False manifest [] Nothing []
      out `shouldSatisfy` T.isInfixOf "Blueprint: lone-blueprint (applied"
      out `shouldSatisfy` T.isInfixOf "  Baseline: (none -- --no-baseline)"
      out `shouldNotSatisfy` T.isInfixOf "  Prompt:"

    it "omits the Prompt line when no positional prompt was supplied" $ do
      let manifest =
            withManifestBlueprint
              ( Just $
                  mkBlueprint
                    "payments-service"
                    (Just "0.3.1")
                    ["nix-flake"]
                    False
                    Nothing
              )
              (mkManifest [])
          out = formatStatus False manifest [] Nothing []
      out `shouldSatisfy` T.isInfixOf "Blueprint: payments-service v0.3.1 (applied"
      out `shouldSatisfy` T.isInfixOf "  Baseline: nix-flake"
      out `shouldNotSatisfy` T.isInfixOf "  Prompt:"

    it "omits the entire blueprint section when manifest.blueprint is Nothing" $ do
      let manifest = withManifestBlueprint Nothing (mkManifest [])
          out = formatStatus False manifest [] Nothing []
      out `shouldNotSatisfy` T.isInfixOf "Blueprint: "
      out `shouldNotSatisfy` T.isInfixOf "  Baseline:"

    it "renders an empty-baseline (no --no-baseline) blueprint with the (none declared) placeholder" $ do
      let manifest =
            withManifestBlueprint
              (Just $ mkBlueprint "pure-prompt" Nothing [] False Nothing)
              (mkManifest [])
          out = formatStatus False manifest [] Nothing []
      out `shouldSatisfy` T.isInfixOf "Blueprint: pure-prompt (applied"
      out `shouldSatisfy` T.isInfixOf "  Baseline: (none declared)"

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

  it "outdated only recommends the project-aware update workflow" $ do
    let am = mkApplied "demo" (Just "0.1.0")
        manifest = mkManifest [am]
        entries = Just [mkEntry "demo" (Just "0.1.0") (Just "0.3.0") OutdatedSt]
        out = formatStatus False manifest [] entries []
    out `shouldSatisfy` T.isInfixOf "outdated: 0.3.0 available"
    out `shouldSatisfy` T.isInfixOf "Run: seihou update demo"
    out `shouldSatisfy` T.isInfixOf "Recommended actions:"
    out `shouldSatisfy` T.isInfixOf "  seihou update demo"
    out `shouldNotSatisfy` T.isInfixOf "Pending migration"

  it "pending migration keeps detail and recommends update" $ do
    let am = mkApplied "demo" (Just "1.0.0")
        manifest = mkManifest [am]
        plan = mkPlan "demo" "1.0.0" "2.0.0" 1
        out = formatStatus False manifest [] Nothing [(ModuleName "demo", plan)]
    out `shouldSatisfy` T.isInfixOf "Pending migration: 1.0.0 -> 2.0.0 (1 step(s))"
    out `shouldSatisfy` T.isInfixOf "Run: seihou update demo"
    out `shouldSatisfy` T.isInfixOf "Recommended actions:"
    out `shouldSatisfy` T.isInfixOf "  seihou update demo"
    out `shouldNotSatisfy` T.isInfixOf "seihou upgrade"

  it "outdated plus pending migration produces one update hint" $ do
    let am = mkApplied "demo" (Just "0.1.0")
        manifest = mkManifest [am]
        plan = mkPlan "demo" "0.1.0" "0.3.0" 6
        entries = Just [mkEntry "demo" (Just "0.1.0") (Just "0.3.0") OutdatedSt]
        out = formatStatus False manifest [] entries [(ModuleName "demo", plan)]
    out `shouldSatisfy` T.isInfixOf "outdated: 0.3.0 available"
    out `shouldSatisfy` T.isInfixOf "Pending migration: 0.1.0 -> 0.3.0 (6 step(s))"
    out `shouldSatisfy` T.isInfixOf "Run: seihou update demo"
    out `shouldNotSatisfy` T.isInfixOf "seihou upgrade demo"
    out `shouldSatisfy` T.isInfixOf "Recommended actions:"
    out `shouldSatisfy` T.isInfixOf "  seihou update demo"

  -- Master-plan live-tree fixture: manifest=0.1.0, installed=0.3.0,
  -- declared [0.1.0 → 0.2.0]. The chain reaches 0.2 via ops; the
  -- supplied target is 0.3, so planTo = 0.3. Status surfaces the
  -- single in-window step and points at `seihou update demo` as the
  -- remediation.
  it "partial-cover plan: chain reaches an intermediate version, target is the user's installed copy" $ do
    let am = mkApplied "demo" (Just "0.1.0")
        manifest = mkManifest [am]
        plan = mkPlan "demo" "0.1.0" "0.3.0" 1
        out = formatStatus False manifest [] Nothing [(ModuleName "demo", plan)]
    out `shouldSatisfy` T.isInfixOf "Pending migration: 0.1.0 -> 0.3.0 (1 step(s))"
    out `shouldSatisfy` T.isInfixOf "Run: seihou update demo"
    out `shouldSatisfy` T.isInfixOf "Recommended actions:"
    out `shouldSatisfy` T.isInfixOf "  seihou update demo"
    -- Doomed vocabulary is gone from status output.
    out `shouldNotSatisfy` T.isInfixOf "Blocked"
    out `shouldNotSatisfy` T.isInfixOf "no migration declared from"
    out `shouldNotSatisfy` T.isInfixOf "bump through"

  -- A module that has a version gap but no in-window declared
  -- migration still surfaces a pending advisory; the row reports
  -- 0 step(s) so the user knows `seihou migrate` will only advance
  -- the manifest.
  it "renders empty-steps plan with a 0-step pending row" $ do
    let am = mkApplied "demo" (Just "0.2.0")
        manifest = mkManifest [am]
        plan =
          MigrationPlan
            { planModule = "demo",
              planFrom = parseV "0.2.0",
              planTo = parseV "0.3.0",
              planSteps = []
            }
        out = formatStatus False manifest [] Nothing [(ModuleName "demo", plan)]
    out `shouldSatisfy` T.isInfixOf "Pending migration: 0.2.0 -> 0.3.0 (0 step(s))"
    out `shouldSatisfy` T.isInfixOf "Run: seihou update demo"
    out `shouldSatisfy` T.isInfixOf "Recommended actions:"
    out `shouldSatisfy` T.isInfixOf "  seihou update demo"
    -- The doomed vocabulary stays out of the rendered status.
    out `shouldNotSatisfy` T.isInfixOf "Blocked"
    out `shouldNotSatisfy` T.isInfixOf "--bump-only"
    out `shouldNotSatisfy` T.isInfixOf "[blocked]"

  it "deduplicates repeated instances into one recipe application action" $ do
    let duplicate = mkApplied "demo" (Just "1.0.0")
        manifest =
          (mkManifest [duplicate, duplicate])
            { applications = [mkApplication "stack" ["demo", "demo"]]
            }
        plan = mkPlan "demo" "1.0.0" "2.0.0" 1
        out = formatStatus False manifest [] Nothing [(ModuleName "demo", plan)]
        recommendationLines = filter (== "  seihou update stack") (T.lines out)
    recommendationLines `shouldBe` ["  seihou update stack"]
    T.count "seihou update stack" out `shouldBe` 1
    out `shouldNotSatisfy` T.isInfixOf "  seihou migrate demo"

  it "recommends each affected application plus the whole-project update" $ do
    let shared = mkApplied "shared" (Just "1.0.0")
        manifest =
          (mkManifest [shared])
            { applications =
                [ mkApplication "stack-one" ["shared"],
                  mkApplication "stack-two" ["shared"]
                ]
            }
        plan = mkPlan "shared" "1.0.0" "2.0.0" 1
        out = formatStatus False manifest [] Nothing [(ModuleName "shared", plan)]
        recommendationLines = dropWhile (/= "Recommended actions:") (T.lines out)
    recommendationLines
      `shouldBe` [ "Recommended actions:",
                   "  seihou update stack-one",
                   "  seihou update stack-two",
                   "  seihou update"
                 ]

  it "deduplicates legacy instances by bare module name" $ do
    let duplicate = mkApplied "demo" (Just "1.0.0")
        manifest = mkManifest [duplicate, duplicate]
        plan = mkPlan "demo" "1.0.0" "2.0.0" 1
        out = formatStatus False manifest [] Nothing [(ModuleName "demo", plan)]
    T.count "seihou update demo" out `shouldBe` 2
