module Seihou.CLI.StatusRender
  ( formatStatus,
    ModuleAdvice (..),
  )
where

import Data.List (intersperse, nub)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust, listToMaybe, mapMaybe)
import Data.Set qualified as Set
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
    AppliedComposition (..),
    AppliedInstanceState (..),
    AppliedModule (..),
    AppliedRecipe (..),
    AppliedTarget (..),
    Manifest (..),
    ModuleName (..),
    ParentVars (..),
    RecipeName (..),
    TrackedFile (..),
    TrackedFileStatus (..),
    VarName (..),
  )
import Seihou.Core.Version (renderVersion)

-- | What action an applied module or recorded application recommends.
-- Pending migrations and ordinary version drift both route through the
-- project-aware update workflow.
data ModuleAdvice
  = AdviceNone
  | AdviceProjectUpdate Text (Maybe MigrationPlan)
  | AdviceProjectUpdateAll
  deriving stock (Eq, Show)

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
    adviceList = projectAdviceList manifest entryMap pendingMap

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
      | otherwise = renderRows Set.empty manifest.modules
    renderRows _ [] = []
    renderRows seen (am : rest) =
      let name = am.name.unModuleName
          annotation = lookupEntry mEntries entryMap am
          headerLine = formatModuleLine color annotation am
          hintLines
            | Set.member name seen = []
            | null manifest.applications = formatAdvice color (rowProjectAdvice entryMap pendingMap am)
            | otherwise = maybe [] (formatPendingDetail color) (Map.lookup name pendingMap)
       in headerLine : hintLines <> renderRows (Set.insert name seen) rest

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
  case nub [c | Just c <- map adviceCommand advices] of
    [] -> []
    cmds -> ["", "Recommended actions:"] ++ map ("  " <>) cmds

adviceCommand :: ModuleAdvice -> Maybe Text
adviceCommand AdviceNone = Nothing
adviceCommand (AdviceProjectUpdate target _) = Just ("seihou update " <> target)
adviceCommand AdviceProjectUpdateAll = Just "seihou update"

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
formatAdvice color (AdviceProjectUpdate target Nothing) =
  ["    " <> applyColor color yellow ("Run: seihou update " <> target)]
formatAdvice color (AdviceProjectUpdate target (Just plan)) =
  ["    " <> applyColor color yellow (projectPlanSummary target plan)]
formatAdvice color AdviceProjectUpdateAll =
  ["    " <> applyColor color yellow "Run: seihou update"]

projectPlanSummary :: Text -> MigrationPlan -> Text
projectPlanSummary target plan =
  "Pending migration: "
    <> renderVersion plan.planFrom
    <> " -> "
    <> renderVersion plan.planTo
    <> " ("
    <> T.pack (show (length plan.planSteps))
    <> " step(s)). Run: seihou update "
    <> target

formatPendingDetail :: Bool -> MigrationPlan -> [Text]
formatPendingDetail color plan =
  [ "    "
      <> applyColor
        color
        yellow
        ( "Pending migration: "
            <> renderVersion plan.planFrom
            <> " -> "
            <> renderVersion plan.planTo
            <> " ("
            <> T.pack (show (length plan.planSteps))
            <> " step(s))"
        )
  ]

rowProjectAdvice ::
  Map Text OutdatedEntry ->
  Map Text MigrationPlan ->
  AppliedModule ->
  ModuleAdvice
rowProjectAdvice entryMap pendingMap applied =
  if actionable
    then AdviceProjectUpdate name pending
    else AdviceNone
  where
    name = applied.name.unModuleName
    pending = Map.lookup name pendingMap
    outdated = maybe False ((== OutdatedSt) . (.status)) (Map.lookup name entryMap)
    actionable = outdated || isJust pending

projectAdviceList ::
  Manifest ->
  Map Text OutdatedEntry ->
  Map Text MigrationPlan ->
  [ModuleAdvice]
projectAdviceList manifest entryMap pendingMap
  | null manifest.applications =
      map (rowProjectAdvice entryMap pendingMap) (deduplicateModules manifest.modules)
  | otherwise =
      let applicationAdvice = mapMaybe adviceForApplication manifest.applications
       in applicationAdvice <> [AdviceProjectUpdateAll | length applicationAdvice > 1]
  where
    adviceForApplication application =
      let names = map (.name.unModuleName) application.instances
          pending = listToMaybe (mapMaybe (`Map.lookup` pendingMap) names)
          outdated = any (maybe False ((== OutdatedSt) . (.status)) . (`Map.lookup` entryMap)) names
       in if outdated || isJust pending
            then Just (AdviceProjectUpdate (targetText application.target) pending)
            else Nothing

deduplicateModules :: [AppliedModule] -> [AppliedModule]
deduplicateModules = Map.elems . Map.fromList . map (\applied -> (applied.name.unModuleName, applied))

targetText :: AppliedTarget -> Text
targetText (AppliedModuleTarget name) = name.unModuleName
targetText (AppliedRecipeTarget name) = name.unRecipeName

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
