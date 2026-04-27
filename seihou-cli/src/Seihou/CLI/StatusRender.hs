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
  ( AppliedModule (..),
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
-- new version. An outdated row with no declared migration falls back
-- to @seihou upgrade@.
data ModuleAdvice
  = -- | Nothing pending; do not emit a hint.
    AdviceNone
  | -- | Module is outdated and no chain is declared. The renderer
    -- prints @"Run: seihou upgrade <name>"@.
    AdviceUpgradeOnly Text
  | -- | A pending migration was detected. The renderer prints both a
    -- chain summary and @"Run: seihou migrate <name>"@. This variant
    -- subsumes the outdated case because the migration command also
    -- fetches the new module version (after EP-2's self-contained
    -- migrate landed).
    AdvicePendingMigration Text MigrationChain
  deriving stock (Eq, Show)

-- | Decide which advice to emit for a single applied module.
--
-- M3 widens the signature from 'Maybe MigrationChain' to 'Maybe
-- MigrationPlan' so partial and blocked plans flow through. The
-- renderer still treats partial/blocked plans the same as full chains
-- here (printing the chain summary and a migrate hint); M4 will split
-- them into dedicated advice variants with the unreachable-tail
-- advisory.
moduleAdvice ::
  AppliedModule ->
  Maybe OutdatedStatus ->
  Maybe MigrationPlan ->
  ModuleAdvice
moduleAdvice am mStatus mPlan =
  case mPlan of
    Just plan
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
formatAdvice color (AdvicePendingMigration name chain) =
  let chainSummary =
        "Pending migration: "
          <> renderVersion chain.chainFrom
          <> " -> "
          <> renderVersion chain.chainTo
          <> " ("
          <> T.pack (show (length chain.chainSteps))
          <> " operation(s)). Run: seihou migrate "
          <> name
   in ["    " <> applyColor color yellow chainSummary]

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
