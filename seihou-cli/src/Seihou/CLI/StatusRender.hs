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
import Seihou.Core.Migration (MigrationPlan (..))
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
import Seihou.Core.Version (renderVersion)

-- | What action a single applied-module row recommends.
--
-- Order of precedence: a pending migration always wins over a bare
-- "outdated" annotation, because @seihou migrate@ (after EP-2) is
-- self-contained and one command suffices to bring the project to the
-- new version. An outdated row with no detected pending plan falls
-- back to @seihou upgrade@.
data ModuleAdvice
  = -- | Nothing pending; do not emit a hint.
    AdviceNone
  | -- | Module is outdated and no pending migration was detected. The
    -- renderer prints @"Run: seihou upgrade <name>"@.
    AdviceUpgradeOnly Text
  | -- | A pending migration was detected. The carried 'MigrationPlan'
    -- describes the version range and the in-window migrations that
    -- would run; 'planSteps' may be empty (a pure version bump) or
    -- non-empty. The renderer prints a one-line summary and
    -- @"Run: seihou migrate <name>"@.
    AdvicePendingMigration Text MigrationPlan
  deriving stock (Eq, Show)

-- | Decide which advice to emit for a single applied module. Any
-- detected pending plan wins over a bare outdated annotation because
-- @seihou migrate@ (after EP-2) is self-contained.
moduleAdvice ::
  AppliedModule ->
  Maybe OutdatedStatus ->
  Maybe MigrationPlan ->
  ModuleAdvice
moduleAdvice am mStatus mPlan = case mPlan of
  Just plan -> AdvicePendingMigration am.name.unModuleName plan
  Nothing -> case mStatus of
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
-- under the module name.
formatAdvice :: Bool -> ModuleAdvice -> [Text]
formatAdvice _ AdviceNone = []
formatAdvice color (AdviceUpgradeOnly name) =
  ["    " <> applyColor color yellow ("Run: seihou upgrade " <> name)]
formatAdvice color (AdvicePendingMigration name plan) =
  ["    " <> applyColor color yellow (planSummary name plan)]

-- | Format the "Pending migration: from -> to (N step(s)). Run:
-- seihou migrate <name>" line for a pending-migration advice row.
planSummary :: Text -> MigrationPlan -> Text
planSummary name plan =
  "Pending migration: "
    <> renderVersion plan.planFrom
    <> " -> "
    <> renderVersion plan.planTo
    <> " ("
    <> T.pack (show (length plan.planSteps))
    <> " step(s)). Run: seihou migrate "
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
