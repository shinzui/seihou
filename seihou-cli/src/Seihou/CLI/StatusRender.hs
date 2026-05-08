module Seihou.CLI.StatusRender
  ( formatStatus,
    ModuleAdvice (..),
    moduleAdvice,
  )
where

import Data.List (intersperse)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time.Format (defaultTimeLocale, formatTime)
import Seihou.CLI.Style (dim, green, red, yellow)
import Seihou.CLI.VersionCompare
  ( OutdatedEntry (..),
    OutdatedStatus (..),
  )
import Seihou.Core.Migration (MigrationChain (..), MigrationPlan (..))
import Seihou.Core.Types
  ( AppliedBlueprint (..),
    AppliedModule (..),
    AppliedRecipe (..),
    Manifest (..),
    ModuleName (..),
    ParentVars (..),
    RecipeName (..),
    TrackedFile (..),
    TrackedFileStatus (..),
    VarName (..),
  )
import Seihou.Core.Version (Version, renderVersion)

-- | What action a single applied-module row recommends.
--
-- Order of precedence: a pending migration always wins over a bare
-- "outdated" annotation, because @seihou migrate@ (after EP-2) is
-- self-contained and one command suffices to bring the project to the
-- new version. An outdated row with no declared migration falls back
-- to @seihou upgrade@.
data ModuleAdvice
  = -- | Nothing pending; do not emit a hint.
    AdviceNone
  | -- | Module is outdated and no chain is declared. The renderer
    -- prints @"Run: seihou upgrade <name>"@.
    AdviceUpgradeOnly Text
  | -- | A pending migration was detected and the declared chain
    -- reaches the latest remote version exactly. The renderer prints a
    -- chain summary and @"Run: seihou migrate <name>"@. This variant
    -- subsumes the outdated case because the migration command also
    -- fetches the new module version (after EP-2's self-contained
    -- migrate landed).
    AdvicePendingMigration Text MigrationChain
  | -- | A pending migration whose declared chain reaches an
    -- intermediate version but not the latest remote version. The
    -- renderer prints the chain summary, a @"Run: seihou migrate
    -- <name>"@ hint, and a "no migration declared from <stuckAt>;
    -- remote is at <target>" advisory. The migrate command will apply
    -- the prefix and refresh the manifest; the next status will
    -- report blocked or up-to-date depending on whether the author
    -- ships a continuation migration.
    AdvicePartialMigration Text MigrationPlan
  | -- | No migration starts at the manifest version, so the planner
    -- can build no chain. Carries the module name and the
    -- @(stuckAt, target)@ pair. The renderer prints a "Blocked: …"
    -- row that names @seihou migrate <name> --bump-only@ as the
    -- recovery path; the Recommended actions tail lists the same
    -- command for copy-paste.
    AdviceBlockedMigration Text Version Version
  | -- | The module's manifest version trails its installed copy's
    -- version, but the module declared no migrations at all
    -- (@migrations = []@). The renderer prints a softened "Pending:
    -- … (no migrations declared)" advisory and the Recommended
    -- actions tail lists @"seihou upgrade <name> && seihou run"@
    -- (not @[blocked]@, because nothing is actually blocking).
    AdviceBenignUpgrade Text Version Version
  deriving stock (Eq, Show)

-- | Decide which advice to emit for a single applied module.
--
-- Maps the four 'MigrationPlan' shapes onto distinct advice variants:
--
--   * No plan + outdated → 'AdviceUpgradeOnly'.
--   * Full chain (steps non-empty, no unreachable tail) →
--     'AdvicePendingMigration'.
--   * Partial chain (steps non-empty, unreachable tail) →
--     'AdvicePartialMigration'.
--   * Blocked (steps empty, unreachable tail) →
--     'AdviceBlockedMigration'.
--
-- A pending plan always wins over a bare outdated annotation because
-- @seihou migrate@ (after EP-2) is self-contained: one command brings
-- the project to the new version. For blocked plans we still emit
-- 'AdviceBlockedMigration' rather than fall back to an upgrade hint
-- because @seihou upgrade@ alone does not solve the problem; the
-- recovery is @seihou migrate <name> --bump-only@ (per-module) or
-- @seihou run --bump-blocked@ (one-command, all blocked at once).
moduleAdvice ::
  AppliedModule ->
  Maybe OutdatedStatus ->
  Maybe MigrationPlan ->
  ModuleAdvice
moduleAdvice am mStatus mPlan =
  case mPlan of
    Just plan
      | null plan.planChain.chainSteps,
        not plan.planMigrationsDeclared,
        Just (stuck, target) <- plan.planUnreachable ->
          AdviceBenignUpgrade am.name.unModuleName stuck target
      | null plan.planChain.chainSteps,
        Just (stuck, target) <- plan.planUnreachable ->
          AdviceBlockedMigration am.name.unModuleName stuck target
      | not (null plan.planChain.chainSteps),
        Just _ <- plan.planUnreachable ->
          AdvicePartialMigration am.name.unModuleName plan
      | not (null plan.planChain.chainSteps) ->
          AdvicePendingMigration am.name.unModuleName plan.planChain
    _ -> case mStatus of
      Just OutdatedSt -> AdviceUpgradeOnly am.name.unModuleName
      _ -> AdviceNone

-- | Render the full @seihou status@ output as a single 'Text' value.
--
-- @color@ controls ANSI styling; pass 'False' for plain text (used by
-- the test suite).
formatStatus ::
  Bool ->
  Manifest ->
  [TrackedFile] ->
  Maybe [OutdatedEntry] ->
  [(ModuleName, MigrationPlan)] ->
  Text
formatStatus color manifest tracked mEntries pendings =
  T.unlines $
    ["Seihou Status:", ""]
      ++ recipeSection manifest
      ++ blueprintSection manifest
      ++ appliedSection color manifest mEntries pendings
      ++ trackedSection color tracked
      ++ varsSection manifest
      ++ updateSummarySection mEntries
      ++ recommendedActionsSection adviceList
  where
    entryMap = case mEntries of
      Just es -> Map.fromList [(e.moduleName, e) | e <- es]
      Nothing -> Map.empty
    pendingMap =
      Map.fromList [(name.unModuleName, plan) | (name, plan) <- pendings]
    adviceList = map (rowAdvice entryMap pendingMap) manifest.modules

-- | Build a 'ModuleAdvice' for one applied module from the lookup maps.
rowAdvice ::
  Map Text OutdatedEntry ->
  Map Text MigrationPlan ->
  AppliedModule ->
  ModuleAdvice
rowAdvice entryMap pendingMap am =
  let name = am.name.unModuleName
      mStatus = (.status) <$> Map.lookup name entryMap
      mPlan = Map.lookup name pendingMap
   in moduleAdvice am mStatus mPlan

-- ---------------------------------------------------------------------------
-- Section renderers
-- ---------------------------------------------------------------------------

recipeSection :: Manifest -> [Text]
recipeSection manifest = case manifest.recipe of
  Nothing -> []
  Just ar ->
    [ "Recipe: "
        <> ar.name.unRecipeName
        <> maybe "" (\v -> " v" <> v) ar.recipeVersion,
      ""
    ]

-- | Render the "Blueprint:" provenance block when 'Manifest.blueprint'
-- is populated. Empty otherwise.
--
-- Header line: name, optional @vX.Y.Z@, and the applied timestamp.
-- Baseline line: comma-separated baseline module names, or one of the
-- two empty-baseline placeholders.
-- Prompt line: present only when the user passed a positional prompt.
blueprintSection :: Manifest -> [Text]
blueprintSection manifest = case manifest.blueprint of
  Nothing -> []
  Just ab ->
    let header =
          "Blueprint: "
            <> ab.name.unModuleName
            <> maybe "" (\v -> " v" <> v) ab.blueprintVersion
            <> " (applied "
            <> T.pack (formatTime defaultTimeLocale "%Y-%m-%d %H:%M UTC" ab.appliedAt)
            <> ")"
        baselineLine = "  Baseline: " <> renderBaseline ab
        promptLines = case ab.userPrompt of
          Nothing -> []
          Just p -> ["  Prompt: \"" <> p <> "\""]
     in [header, baselineLine] ++ promptLines ++ [""]

-- | Render the baseline body for the blueprint section. Three cases:
-- @--no-baseline@ was passed, the blueprint declared no baseline at
-- all, or one or more baseline modules were applied.
renderBaseline :: AppliedBlueprint -> Text
renderBaseline ab
  | ab.noBaseline = "(none -- --no-baseline)"
  | null ab.baselineModules = "(none declared)"
  | otherwise =
      T.intercalate ", " (map (.unModuleName) ab.baselineModules)

appliedSection ::
  Bool ->
  Manifest ->
  Maybe [OutdatedEntry] ->
  [(ModuleName, MigrationPlan)] ->
  [Text]
appliedSection color manifest mEntries pendings =
  "Applied modules:"
    : moduleLines
    ++ [""]
  where
    entryMap = case mEntries of
      Just es -> Map.fromList [(e.moduleName, e) | e <- es]
      Nothing -> Map.empty
    pendingMap =
      Map.fromList [(name.unModuleName, plan) | (name, plan) <- pendings]
    moduleLines
      | null manifest.modules = ["  (none)"]
      | otherwise =
          concatMap
            ( \am ->
                let advice = rowAdvice entryMap pendingMap am
                    annotation = lookupEntry mEntries entryMap am
                    headerLine = formatModuleLine color annotation am
                    hintLines = formatAdvice color advice
                 in headerLine : hintLines
            )
            manifest.modules

trackedSection :: Bool -> [TrackedFile] -> [Text]
trackedSection color tracked =
  ("Tracked files: " <> T.pack (show (length tracked)))
    : ( if null tracked
          then ["  (none)"]
          else map (formatTrackedFile color maxPathLen maxModLen) tracked
      )
    ++ [""]
  where
    maxPathLen = maximum (map (length . (.path)) tracked)
    maxModLen = maximum (map (T.length . displayModuleName . (.moduleName)) tracked)

varsSection :: Manifest -> [Text]
varsSection manifest =
  ["Variables: " <> T.pack (show (Map.size manifest.vars)) <> " resolved"]

updateSummarySection :: Maybe [OutdatedEntry] -> [Text]
updateSummarySection Nothing = []
updateSummarySection (Just entries) =
  let total = length entries
      outdated = length (filter (\e -> e.status == OutdatedSt) entries)
   in [ "",
        T.pack (show total)
          <> " module(s) checked, "
          <> T.pack (show outdated)
          <> " outdated."
      ]

-- | Print a "Recommended actions:" block listing the exact commands a
-- user should run for each problem row. Skipped when no row had an
-- actionable problem.
recommendedActionsSection :: [ModuleAdvice] -> [Text]
recommendedActionsSection advices =
  case [c | Just c <- map adviceCommand advices] of
    [] -> []
    cmds -> ["", "Recommended actions:"] ++ map ("  " <>) cmds

adviceCommand :: ModuleAdvice -> Maybe Text
adviceCommand AdviceNone = Nothing
adviceCommand (AdviceUpgradeOnly name) = Just ("seihou upgrade " <> name)
adviceCommand (AdvicePendingMigration name _) = Just ("seihou migrate " <> name)
adviceCommand (AdvicePartialMigration name _) = Just ("seihou migrate " <> name)
adviceCommand (AdviceBlockedMigration name _stuck _target) =
  Just ("seihou migrate " <> name <> " --bump-only")
adviceCommand (AdviceBenignUpgrade name _ _) =
  Just ("seihou upgrade " <> name <> " && seihou run")

-- ---------------------------------------------------------------------------
-- Per-row formatting
-- ---------------------------------------------------------------------------

-- | Per-row update annotation source, mirroring the previous local
-- @UpdateAnnotation@ enum in @Status.hs@.
data UpdateAnnotation
  = NoCheck
  | NoOrigin
  | Entry OutdatedEntry

lookupEntry ::
  Maybe [OutdatedEntry] ->
  Map Text OutdatedEntry ->
  AppliedModule ->
  UpdateAnnotation
lookupEntry Nothing _ _ = NoCheck
lookupEntry (Just _) m am = case Map.lookup am.name.unModuleName m of
  Just e -> Entry e
  Nothing -> NoOrigin

formatModuleLine :: Bool -> UpdateAnnotation -> AppliedModule -> Text
formatModuleLine color annotation am =
  let verText = case am.moduleVersion of
        Just v -> "  " <> applyColor color green ("v" <> v)
        Nothing -> ""
      appliedText =
        "    (applied "
          <> T.pack (formatTime defaultTimeLocale "%Y-%m-%d" am.appliedAt)
          <> ")"
      parentVarsText =
        let m = am.parentVars.unParentVars
         in if Map.null m
              then ""
              else
                let pairs =
                      T.concat
                        ( intersperse
                            ", "
                            [ vn.unVarName <> "=" <> v
                            | (vn, v) <- Map.toAscList m
                            ]
                        )
                    rendered = " [" <> pairs <> "]"
                 in applyColor color dim rendered
      updateText = case annotation of
        NoCheck -> ""
        NoOrigin -> "  " <> applyColor color dim "(no origin)"
        Entry e -> "  " <> renderEntry color e
   in "  "
        <> am.name.unModuleName
        <> parentVarsText
        <> verText
        <> appliedText
        <> updateText

-- | Per-row remediation hint. Indented two characters past the row's
-- two-space indentation (i.e. four spaces total) so it visually nests
-- under the module name. Partial and blocked migrations get an extra
-- line below the chain summary describing the unreachable tail or
-- the missing edge.
formatAdvice :: Bool -> ModuleAdvice -> [Text]
formatAdvice _ AdviceNone = []
formatAdvice color (AdviceUpgradeOnly name) =
  ["    " <> applyColor color yellow ("Run: seihou upgrade " <> name)]
formatAdvice color (AdvicePendingMigration name chain) =
  ["    " <> applyColor color yellow (chainSummary name chain)]
formatAdvice color (AdvicePartialMigration name plan) =
  let summary = chainSummary name plan.planChain
      tail_ = case plan.planUnreachable of
        Just (stuck, target)
          -- EP-28: exhausted tail — `seihou migrate <name>` will run
          -- the prefix and bump the manifest all the way to target in
          -- one shot. Tell the user that's what to expect, instead of
          -- the legacy "no migration declared" advisory that implied
          -- a follow-up --bump-only was needed.
          | plan.planTailExhausted ->
              [ "    "
                  <> applyColor
                    color
                    yellow
                    ( "Note: "
                        <> renderVersion stuck
                        <> " -> "
                        <> renderVersion target
                        <> " has no declared migration; "
                        <> "'seihou migrate "
                        <> name
                        <> "' will bump through."
                    )
              ]
          | otherwise ->
              [ "    "
                  <> applyColor
                    color
                    yellow
                    ( "Note: no migration declared from "
                        <> renderVersion stuck
                        <> "; remote is at "
                        <> renderVersion target
                        <> "."
                    )
              ]
        Nothing -> []
   in ("    " <> applyColor color yellow summary) : tail_
formatAdvice color (AdviceBlockedMigration name stuck target) =
  [ "    "
      <> applyColor
        color
        red
        ( "Blocked: no migration declared from "
            <> renderVersion stuck
            <> "; remote is at "
            <> renderVersion target
            <> ". To proceed, run 'seihou migrate "
            <> name
            <> " --bump-only' to acknowledge no migration is needed, or wait for the module author to ship one."
        )
  ]
formatAdvice color (AdviceBenignUpgrade name from to) =
  [ "    "
      <> applyColor
        color
        yellow
        ( "Pending: "
            <> renderVersion from
            <> " -> "
            <> renderVersion to
            <> " (no migrations declared). Run: seihou upgrade "
            <> name
            <> " && seihou run"
        )
  ]

-- | Format the "Pending migration: from -> to (N operation(s)). Run:
-- seihou migrate <name>" line shared by full- and partial-chain
-- advices.
chainSummary :: Text -> MigrationChain -> Text
chainSummary name chain =
  "Pending migration: "
    <> renderVersion chain.chainFrom
    <> " -> "
    <> renderVersion chain.chainTo
    <> " ("
    <> T.pack (show (length chain.chainSteps))
    <> " operation(s)). Run: seihou migrate "
    <> name

renderEntry :: Bool -> OutdatedEntry -> Text
renderEntry color e = case e.status of
  UpToDate -> applyColor color dim "up to date"
  OutdatedSt ->
    let avail = maybe "?" id e.availableVersion
        txt = "outdated: " <> avail <> " available"
     in applyColor color red txt
  Unversioned -> applyColor color dim "unversioned"
  Unreachable -> applyColor color yellow "unreachable"

formatTrackedFile :: Bool -> Int -> Int -> TrackedFile -> Text
formatTrackedFile color maxPathLen maxModLen tf =
  let path = T.pack tf.path
      modName = displayModuleName tf.moduleName
      paddedPath = path <> T.replicate (maxPathLen - T.length path + 3) " "
      paddedMod = modName <> T.replicate (maxModLen - T.length modName + 3) " "
      label = statusLabel tf.status
      colored = applyColor color (statusColor tf.status) label
   in "  " <> paddedPath <> paddedMod <> colored

displayModuleName :: ModuleName -> Text
displayModuleName (ModuleName n) = T.takeWhile (/= '#') n

statusLabel :: TrackedFileStatus -> Text
statusLabel TfsUnchanged = "unchanged"
statusLabel TfsModified = "modified by user"
statusLabel TfsDeleted = "deleted by user"

statusColor :: TrackedFileStatus -> Text -> Text
statusColor TfsUnchanged = dim
statusColor TfsModified = yellow
statusColor TfsDeleted = red

applyColor :: Bool -> (Text -> Text) -> Text -> Text
applyColor True f = f
applyColor False _ = id
