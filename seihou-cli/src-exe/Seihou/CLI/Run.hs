module Seihou.CLI.Run
  ( handleRun,
  )
where

import Control.Monad (foldM, unless, when)
import Data.List (partition)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust)
import Data.Set qualified as Set
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Time (UTCTime)
import Data.Time.Clock (getCurrentTime)
import Seihou.CLI.Commands (RunOpts (..))
import Seihou.CLI.CommitMessage (generateCommitMessage)
import Seihou.CLI.Git (gitAdd, gitCheckIgnore, gitCommit, gitDiffCached, isGitRepo)
import Seihou.CLI.Migrate
  ( MigrateError (..),
    MigrateOpts (..),
    MigrateResult (..),
    runMigrate,
  )
import Seihou.CLI.PendingMigrations
  ( detectPendingMigrations,
    formatRefusalMessage,
    isBenignUpgrade,
    isBlockedMigration,
  )
import Seihou.CLI.SavePrompted (collectPromptedValues, offerSavePrompted)
import Seihou.CLI.Shared (deriveNamespace, formatBlueprintRefusal, formatVarError, logIO, toVarNameMap, unwrapConfig)
import Seihou.CLI.Style (bold, dim, formatPlanViewColor, green, magenta, red, useColor, yellow)
import Seihou.Composition.Instance (ModuleInstance (..), qualifiedName)
import Seihou.Composition.Plan (compileComposedPlan)
import Seihou.Composition.Recipe (expandRecipe)
import Seihou.Composition.Resolve (loadComposition, resolveWithPrompts)
import Seihou.Core.Context (resolveContext)
import Seihou.Core.Migration (MigrationChain (..), MigrationPlan (..))
import Seihou.Core.Module (defaultSearchPaths, discoverRunnable)
import Seihou.Core.Types
import Seihou.Core.Variable (diagnoseResolution)
import Seihou.Core.Version (renderVersion)
import Seihou.Effect.ConfigReader (readContextConfig, readGlobalConfig, readLocalConfig, readNamespaceConfig)
import Seihou.Effect.ConfigReaderInterp (runConfigReader)
import Seihou.Effect.ConfigWriterInterp (runConfigWriter)
import Seihou.Effect.ConsoleInterp (runConsole)
import Seihou.Effect.Filesystem (createDirectoryIfMissing)
import Seihou.Effect.FilesystemInterp (runFilesystem)
import Seihou.Effect.FzfInterp (runFzfIO)
import Seihou.Effect.Logger (logDebug, logError, logInfo, logWarn)
import Seihou.Effect.ManifestStore (readManifest, writeManifest)
import Seihou.Effect.ManifestStoreInterp (runManifestStore)
import Seihou.Effect.Process (runProcess)
import Seihou.Effect.ProcessInterp (runProcessIO)
import Seihou.Engine.Conflict (resolveConflicts)
import Seihou.Engine.Diff (computeDiff)
import Seihou.Engine.Execute (executePlan)
import Seihou.Engine.Preview (buildPreview)
import Seihou.Fzf (FzfResult (..), detectFzfConfig, isFzfUsable)
import Seihou.Fzf.Selector (selectModule)
import Seihou.Interaction.Confirm (confirmDefaults)
import Seihou.Manifest.Types (currentManifestVersion, emptyManifest)
import Seihou.Prelude
import System.Environment (getEnvironment)
import System.Exit (ExitCode (..), exitFailure, exitWith)
import System.FilePath (takeDirectory)
import System.IO (hFlush, hIsTerminalDevice, stdin, stdout)

handleRun :: RunOpts -> IO ()
handleRun runOpts = do
  let additional = runOpts.runAdditional
      level = if runOpts.runVerbose then LogVerbose else LogNormal

  -- 0. Resolve module name (from argument or fzf picker)
  modName <- case runOpts.runModule of
    Just name -> pure name
    Nothing -> do
      fzfCfg <- detectFzfConfig
      if isFzfUsable fzfCfg
        then do
          result <- runEff $ runFzfIO fzfCfg $ selectModule
          case result of
            FzfSelected name -> pure name
            FzfCancelled -> exitWith ExitSuccess
            FzfNoMatch -> do
              logIO level (logError "No modules found.")
              exitFailure
            FzfError err -> do
              logIO level (logError $ "fzf error: " <> err)
              exitFailure
        else do
          logIO level (logError "MODULE argument is required when fzf is not available.")
          exitFailure

  -- 0b. Recipe detection: check if the name resolves to a recipe or a module
  searchPaths <- defaultSearchPaths
  (primaryName, allAdditional, recipeOverrides, recipeInfo) <- do
    runnableResult <- discoverRunnable searchPaths modName
    case runnableResult of
      Right (RunnableRecipe recipe _recipeDir) -> do
        let (primary, recipeAdditional, overrides, _recipeVars, _recipePrompts) = expandRecipe recipe
        logIO level $
          logInfo $
            "Recipe '" <> recipe.name.unRecipeName <> "' expanding to " <> T.pack (show (length recipe.modules)) <> " modules"
        pure (primary, recipeAdditional ++ additional, overrides, Just (recipe.name, recipe.version))
      Right (RunnableModule _ _) ->
        pure (modName, additional, Map.empty, Nothing)
      Right (RunnableBlueprint _b _blueprintDir) -> do
        -- Use the user-typed name (modName) rather than the blueprint's
        -- declared name. Discovery resolves by directory name; the
        -- suggested 'seihou agent run NAME' must match what the user
        -- can re-type to find the same artifact.
        logIO level $ logError (formatBlueprintRefusal modName)
        exitFailure
      Left _ ->
        -- Discovery failed — let loadComposition handle the error with its detailed message
        pure (modName, additional, Map.empty, Nothing)

  -- 1. Load all modules in the composition (primary + additional + transitive deps)
  compositionResult <- loadComposition searchPaths primaryName allAdditional
  modulesInOrder <- case compositionResult of
    Left (ModuleNotFound name searched) -> do
      logIO level $ do
        logError $ "Module '" <> name.unModuleName <> "' not found."
        logError "Searched in:"
        mapM_ (\p -> logError $ "  " <> T.pack p) searched
      exitFailure
    Left (CircularDependency names) -> do
      logIO level $ do
        logError "Circular dependency detected:"
        logError $ "  " <> T.intercalate " -> " (map (.unModuleName) names)
      exitFailure
    Left err -> exitError level (T.pack (show err))
    Right ms -> pure ms

  -- Report composition when multiple modules are involved
  when (length modulesInOrder > 1) $
    logIO level $ do
      logInfo $ "Composing " <> T.pack (show (length modulesInOrder)) <> " modules:"
      mapM_ (\(_, m, _) -> logInfo $ "  " <> m.name.unModuleName) modulesInOrder

  -- 2. Resolve variables with export visibility and interactive prompts
  envPairs <- getEnvironment
  -- Merge recipe overrides with CLI overrides (CLI wins on conflict)
  let cliOverrides = Map.union (Map.fromList [(VarName k, v) | (k, v) <- runOpts.runVars]) recipeOverrides
      envVars = Map.fromList [(T.pack k, T.pack v) | (k, v) <- envPairs]
      namespace = fromMaybe (deriveNamespace primaryName) runOpts.runNamespace
  context <- resolveContext runOpts.runContext envVars
  let contextName = fromMaybe "" context
  (resolveResult, localMap, nsMap, ctxMap, globalMap) <- runEff $ runConfigReader $ runConsole $ do
    localCfg <- readLocalConfig >>= unwrapConfig level
    namespaceCfg <- readNamespaceConfig namespace >>= unwrapConfig level
    contextCfg <- readContextConfig contextName >>= unwrapConfig level
    globalCfg <- readGlobalConfig >>= unwrapConfig level
    let lm = toVarNameMap localCfg
        nm = toVarNameMap namespaceCfg
        cm = toVarNameMap contextCfg
        gm = toVarNameMap globalCfg
    r <- resolveWithPrompts modulesInOrder cliOverrides envVars namespace contextName lm nm cm gm
    pure (r, lm, nm, cm, gm)
  resolvedInitial <- case resolveResult of
    Left errs -> do
      logIO level $ do
        logError "Error resolving variables:"
        mapM_ (logError . ("  " <>) . formatVarError) errs
      exitFailure
    Right r -> pure r

  -- 2a. Optionally confirm default-sourced values.
  resolved <-
    if runOpts.runConfirmDefaults
      then runEff $ runConsole $ confirmDefaults modulesInOrder resolvedInitial
      else pure resolvedInitial

  -- 2b. Emit diagnostics for unused config keys
  let allDecls = concatMap (\(_, m, _) -> m.vars) modulesInOrder
      allResolved = Map.unions [vs | vs <- Map.elems resolved]
      (unusedKeys, _) = diagnoseResolution allResolved allDecls localMap nsMap ctxMap globalMap
  when (not (null unusedKeys)) $
    logIO level $
      logWarn $
        "Config keys not matching any declared variable: "
          <> T.intercalate ", " (map (.unVarName) unusedKeys)

  -- 3. Compile composed plan (all modules merged)
  let quads =
        [ (inst, m, dir, Map.map (.value) (resolved Map.! inst))
        | (inst, m, dir) <- modulesInOrder
        ]
  planResult <- compileComposedPlan quads
  (ops, warnings, ownerMap) <- case planResult of
    Left errs -> do
      logIO level $ do
        logError "Errors compiling plan:"
        mapM_ (logError . ("  " <>)) errs
      exitFailure
    Right r -> pure r

  -- 4. Filter out command ops if --no-commands
  let opsFiltered =
        if runOpts.runNoCommands
          then filter (not . isCommandOp) ops
          else ops

  -- 5. Print composition warnings
  mapM_ (printWarning level) warnings

  -- 6. Compute diff (shared by dry-run, --diff, and execution paths)
  now <- getCurrentTime
  let manifestPath = ".seihou" </> "manifest.json"
      planned =
        [(dest, content, modName, Nothing) | WriteFileOp dest content _ <- opsFiltered]
          ++ [(dest, content, mName, Just pOp) | PatchFileOp dest content pOp _ mName <- opsFiltered]

  -- 6a. Read the manifest before computing the diff so the pre-flight
  -- migration check can run against it (and, with --with-migrations, so
  -- 'runMigrate' can rewrite it before the diff is taken).
  existingRes <- runEff $ runFilesystem $ runManifestStore manifestPath $ do
    createDirectoryIfMissing True (takeDirectory manifestPath)
    readManifest
  initialManifest <- case existingRes of
    Left err -> do
      logIO level (logError $ "Error reading manifest: " <> err)
      exitFailure
    Right m -> pure (fromMaybe (emptyManifest now) m)

  -- 6b. Pre-flight pending-migration check. We only consider modules in
  -- the current composition: a pending chain on an unrelated module
  -- must not block this run.
  let composedModuleNames =
        Set.fromList [m.name | (_, m, _) <- modulesInOrder]
  pendings <-
    detectPendingMigrations initialManifest (Just composedModuleNames)
  manifest <-
    handlePendingMigrations level runOpts manifestPath initialManifest pendings

  -- 6c. Compute the diff against the (possibly post-migration) manifest.
  diff <- runEff $ runFilesystem $ runManifestStore manifestPath $ do
    -- Diff needs every name that could own a manifest file. Each
    -- instance owns its qualified name; the bare module name is still
    -- matched to cover manifest entries written before the schema bump.
    let composedNames =
          Set.fromList $
            concatMap (\(inst, _, _) -> [inst.instanceModule, qualifiedName inst]) modulesInOrder
    computeDiff manifest composedNames planned

  colorEnabled <- useColor

  let modNames = map (\(_, m, _) -> m.name) modulesInOrder
      allVarValues =
        Map.unions
          [Map.map (.value) vs | vs <- Map.elems resolved]
      preview = buildPreview opsFiltered (Just diff) ownerMap

  -- 6. Handle --dry-run: show plan view and exit
  if runOpts.runDryRun
    then
      TIO.putStr (formatPlanViewColor colorEnabled modNames allVarValues preview diff)
    else
      if runOpts.runDiff
        then TIO.putStr (formatDiff colorEnabled diff ownerMap)
        else do
          -- Show plan view
          TIO.putStr (formatPlanViewColor colorEnabled modNames allVarValues preview diff)

          -- Prompt for confirmation (skip if --force or non-interactive)
          interactive <- hIsTerminalDevice stdin
          when (interactive && not runOpts.runForce) $ do
            TIO.putStr "\n  Proceed? [Y/n] "
            hFlush stdout
            response <- T.strip . T.pack <$> getLine
            when (response /= "" && T.toLower response /= "y") $
              exitWith (ExitFailure 3)

          -- Resolve conflicts interactively (or abort)
          resolutions <-
            runEff $
              runConsole $
                resolveConflicts runOpts.runForce diff.conflicts
          case resolutions of
            Nothing -> do
              TIO.putStrLn "Conflicts detected (use --force to overwrite):"
              mapM_ (\c -> TIO.putStrLn $ "  ! " <> T.pack c.path) diff.conflicts
              exitFailure
            Just conflictResolved -> do
              -- Partition resolutions: accept (overwrite), keep (update manifest only), skip (ignore)
              let keepRecords =
                    Map.fromList
                      [ ( c.path,
                          case Map.lookup c.path manifest.files of
                            Just existing ->
                              existing {hash = c.diskHash, generatedAt = now}
                            Nothing ->
                              FileRecord
                                { hash = c.diskHash,
                                  moduleName = c.moduleName,
                                  strategy = Template,
                                  generatedAt = now
                                }
                        )
                      | (c, KeepCurrent) <- conflictResolved
                      ]
                  skipPaths = [c.path | (c, Skip) <- conflictResolved]
                  excludePaths = Set.fromList (Map.keys keepRecords ++ skipPaths)
                  opsForExec = filter (not . opTargetsPath excludePaths) opsFiltered

              -- Execute the plan (excluding kept/skipped files)
              runEff $ runFilesystem $ runManifestStore manifestPath $ do
                recs <- executePlan "" opsForExec ownerMap modName now

                -- Build updated manifest with all composed modules
                let orphanedPaths = map (.path) diff.orphaned
                    cleanedFiles = foldr Map.delete manifest.files orphanedPaths
                    allModuleEntries = updateAllModules manifest.modules modulesInOrder now
                    allResolvedVals =
                      Map.unions
                        [Map.map (.value) vs | vs <- Map.elems resolved]
                    appliedRecipe = case recipeInfo of
                      Just (rName, rVersion) ->
                        Just AppliedRecipe {name = rName, recipeVersion = rVersion, appliedAt = now}
                      Nothing -> manifest.recipe
                    newManifest =
                      Manifest
                        { version = currentManifestVersion,
                          genAt = now,
                          modules = allModuleEntries,
                          vars = Map.union (Map.map varValueToText allResolvedVals) manifest.vars,
                          files = Map.unions [recs, keepRecords, cleanedFiles],
                          recipe = appliedRecipe,
                          blueprint = manifest.blueprint
                        }

                -- Save manifest
                writeManifest newManifest

              -- Report results
              let nNew = length diff.new
                  nMod = length diff.modified
                  nUnch = length diff.unchanged
              TIO.putStrLn $
                T.pack (show nNew)
                  <> " new, "
                  <> T.pack (show nMod)
                  <> " modified, "
                  <> T.pack (show nUnch)
                  <> " unchanged."

              -- Commit generated files if --commit or --commit-message
              when (runOpts.runCommit || isJust runOpts.runCommitMessage) $ do
                let filesToStage =
                      map (.path) diff.new
                        ++ map (.path) diff.modified
                        ++ [manifestPath]
                inGit <- runEff $ runProcessIO $ isGitRepo
                if inGit
                  then do
                    ignored <- runEff $ runProcessIO $ gitCheckIgnore filesToStage
                    let filteredFiles = filter (`notElem` ignored) filesToStage
                    if null filteredFiles
                      then logIO level (logDebug "--commit: all generated files are git-ignored, skipping commit.")
                      else do
                        (addExit, _, addErr) <- runEff $ runProcessIO $ gitAdd filteredFiles
                        case addExit of
                          ExitFailure _ -> logIO level (logWarn $ "git add failed: " <> addErr)
                          ExitSuccess -> do
                            commitMsg <- case runOpts.runCommitMessage of
                              Just msg -> pure msg
                              Nothing -> do
                                diffText <- runEff $ runProcessIO $ gitDiffCached
                                generateCommitMessage modNames diffText
                            (commitExit, _, commitErr) <- runEff $ runProcessIO $ gitCommit commitMsg
                            case commitExit of
                              ExitSuccess -> logIO level (logInfo "Committed generated files to git.")
                              ExitFailure _ -> logIO level (logWarn $ "git commit failed: " <> commitErr)
                  else
                    logIO level (logDebug "--commit: not inside a git repository, skipping.")

              -- Execute commands after file generation
              let commandOps = [(cmd, wd) | RunCommandOp cmd wd <- opsForExec]
              mapM_ (executeCommand level) commandOps

              -- Offer to save prompted values to local config
              let prompted = collectPromptedValues resolved localMap
              when (not (null prompted)) $
                runEff $
                  runConfigWriter $
                    runConsole $
                      offerSavePrompted runOpts.runSavePrompted interactive prompted

-- Helpers

exitError :: LogLevel -> Text -> IO a
exitError level msg = do
  logIO level (logError $ "Error: " <> msg)
  exitFailure

printWarning :: LogLevel -> CompositionWarning -> IO ()
printWarning level (FileOverwritten path overwritten overwriter) =
  logIO level . logWarn $
    "Warning: "
      <> T.pack path
      <> " (from "
      <> overwritten.unModuleName
      <> ") overwritten by "
      <> overwriter.unModuleName
printWarning level (ContentMerged path base contributor) =
  logIO level . logWarn $
    "Merged: "
      <> T.pack path
      <> " (base from "
      <> base.unModuleName
      <> ", patched by "
      <> contributor.unModuleName
      <> ")"

formatDiff :: Bool -> DiffResult -> Map.Map FilePath ModuleName -> Text
formatDiff color diff ownerMap' =
  T.unlines $
    concat
      [ if null diff.new
          then []
          else "New files:" : map (\f -> "  " <> colorWrap green "[new]" <> "  " <> colorWrap green (T.pack f.path) <> modSuffix f.path) diff.new,
        if null diff.modified
          then []
          else "Modified files:" : map (\f -> "  " <> colorWrap yellow "[modified]" <> "  " <> colorWrap yellow (T.pack f.path) <> modSuffix f.path) diff.modified,
        if null diff.unchanged
          then []
          else "Unchanged files:" : map (\f -> "  " <> colorWrap dim "[unchanged]" <> "  " <> colorWrap dim (T.pack f)) diff.unchanged,
        if null diff.conflicts
          then []
          else "Conflicts:" : map (\f -> "  " <> colorWrap (bold . red) "[conflict]" <> "  " <> colorWrap (bold . red) (T.pack f.path) <> modSuffix f.path) diff.conflicts,
        if null diff.orphaned
          then []
          else "Orphaned files:" : map (\f -> "  " <> colorWrap magenta "[orphaned]" <> "  " <> colorWrap magenta (T.pack f.path)) diff.orphaned
      ]
  where
    colorWrap fn t = if color then fn t else t
    modSuffix path = case Map.lookup path ownerMap' of
      Just mn -> "  " <> colorWrap dim ("(" <> mn.unModuleName <> ")")
      Nothing -> ""

varValueToText :: VarValue -> Text
varValueToText (VText t) = t
varValueToText (VBool True) = "true"
varValueToText (VBool False) = "false"
varValueToText (VInt n) = T.pack (show n)
varValueToText (VList vs) = T.intercalate "," (map varValueToText vs)

-- | Whether an operation is a command (RunCommandOp).
isCommandOp :: Operation -> Bool
isCommandOp (RunCommandOp _ _) = True
isCommandOp _ = False

-- | Check whether an operation targets a file in the given path set.
opTargetsPath :: Set.Set FilePath -> Operation -> Bool
opTargetsPath paths (WriteFileOp dest _ _) = Set.member dest paths
opTargetsPath paths (PatchFileOp dest _ _ _ _) = Set.member dest paths
opTargetsPath _ _ = False

-- | Execute a shell command via @sh -c@, printing output and halting on failure.
executeCommand :: LogLevel -> (Text, Maybe FilePath) -> IO ()
executeCommand level (cmd, workDir) = do
  logIO level (logDebug $ "  run  " <> cmd)
  (exitCode, cmdOut, cmdErr) <- runEff $ runProcessIO $ runProcess "sh" ["-c", cmd] workDir
  when (not (T.null cmdOut)) $ TIO.putStr cmdOut
  case exitCode of
    ExitSuccess -> pure ()
    ExitFailure code -> do
      when (not (T.null cmdErr)) $ TIO.putStr cmdErr
      logIO level (logError $ "Command failed (exit " <> T.pack (show code) <> "): " <> cmd)
      exitFailure

-- | Apply the pending-migration policy. Splits pending entries into
-- benign (the module declared no migrations and the version field
-- changed; nothing destructive to apply) and blocking (a real chain
-- to run, a partial chain, or a declared-but-unreachable block).
--
-- Benign entries are noted at info level and otherwise ignored: the
-- run flow's 'updateAllModules' brings the manifest's recorded
-- @moduleVersion@ up to the installed copy's version automatically.
-- Blocking entries follow the existing policy: refuse without
-- @--with-migrations@, show a chain summary in dry-run mode, or apply
-- chains in-band before the run plan is computed.
--
-- Returns the manifest the run flow should continue with — either the
-- one that was passed in (refusal aborts before this returns; dry-run
-- with-migrations leaves disk and manifest untouched) or the
-- post-migration manifest (non-dry-run with-migrations).
handlePendingMigrations ::
  LogLevel ->
  RunOpts ->
  FilePath ->
  Manifest ->
  [(ModuleName, MigrationPlan)] ->
  IO Manifest
handlePendingMigrations level runOpts manifestPath manifest pendings = do
  let (benign, blocking) = partition (isBenignUpgrade . snd) pendings
  mapM_ (logBenign level) benign
  handleBlocking level runOpts manifestPath manifest blocking

-- | Note a benign upgrade so the user knows the manifest is about
-- to roll forward without a migration. Quiet but not silent: the
-- info-level line is suppressed when @LogLevel@ filters it out.
logBenign :: LogLevel -> (ModuleName, MigrationPlan) -> IO ()
logBenign level (name, plan)
  | Just (from, to) <- plan.planUnreachable =
      logIO level $
        logInfo $
          "  Note: "
            <> name.unModuleName
            <> " has no migrations declared ("
            <> renderVersion from
            <> " -> "
            <> renderVersion to
            <> "); will refresh templates and bump manifest during this run."
  | otherwise = pure ()

handleBlocking ::
  LogLevel ->
  RunOpts ->
  FilePath ->
  Manifest ->
  [(ModuleName, MigrationPlan)] ->
  IO Manifest
handleBlocking _ _ _ manifest [] = pure manifest
handleBlocking level runOpts manifestPath manifest pendings
  | runOpts.runBumpBlocked,
    runOpts.runDryRun = do
      let (toBump, others) = partition (isBlockedMigration . snd) pendings
      unless (null toBump) $ do
        TIO.putStrLn "Blocked modules that would be bumped (--bump-blocked + --dry-run):"
        mapM_ (TIO.putStrLn . renderBumpDryRun) toBump
        TIO.putStrLn ""
      handleBlocking level (runOpts {runBumpBlocked = False}) manifestPath manifest others
  | runOpts.runBumpBlocked = do
      let (toBump, others) = partition (isBlockedMigration . snd) pendings
      manifest' <-
        if null toBump
          then pure manifest
          else do
            logIO level (logInfo "Acknowledging blocked modules (--bump-blocked)...")
            m <- foldM (bumpOneBlocked level) manifest toBump
            runEff $
              runFilesystem $
                runManifestStore manifestPath $
                  writeManifest m
            pure m
      handleBlocking level (runOpts {runBumpBlocked = False}) manifestPath manifest' others
  | not runOpts.runWithMigrations = do
      TIO.putStr (formatRefusalMessage pendings)
      exitFailure
  | runOpts.runDryRun = do
      TIO.putStrLn "Pending migrations detected (--with-migrations + --dry-run):"
      mapM_ (TIO.putStrLn . renderPendingSummary) pendings
      TIO.putStrLn ""
      let blockedNames =
            [ name.unModuleName
            | (name, plan) <- pendings,
              null plan.planChain.chainSteps,
              isJust plan.planUnreachable
            ]
      if not (null blockedNames)
        then do
          TIO.putStrLn $
            "Note: --with-migrations would refuse the run because "
              <> T.intercalate ", " blockedNames
              <> " has no applicable migration."
          TIO.putStrLn "Resolve the block (the module author needs to ship the missing migration) before re-running."
        else do
          TIO.putStrLn "Note: the run plan below is computed against the current (pre-migration)"
          TIO.putStrLn "disk state. Re-run without --dry-run to apply migrations and regenerate."
      pure manifest
  | otherwise = do
      logIO level (logInfo "Applying pending migrations before run plan...")
      manifest' <- foldM (applyOneMigration level) manifest pendings
      runEff $
        runFilesystem $
          runManifestStore manifestPath $
            writeManifest manifest'
      pure manifest'

renderPendingSummary :: (ModuleName, MigrationPlan) -> Text
renderPendingSummary (name, plan)
  | null plan.planChain.chainSteps,
    Just (stuck, target) <- plan.planUnreachable =
      "  "
        <> name.unModuleName
        <> ": Blocked: no migration declared from "
        <> renderVersion stuck
        <> "; remote is at "
        <> renderVersion target
  | otherwise =
      let chain = plan.planChain
          (effectiveTo, tail_) = case plan.planUnreachable of
            Nothing -> (chain.chainTo, "")
            Just (stuck, target)
              -- EP-28: exhausted tail bumps through to target.
              | plan.planTailExhausted ->
                  ( target,
                    " + bump through "
                      <> renderVersion stuck
                      <> " -> "
                      <> renderVersion target
                  )
              | otherwise ->
                  ( chain.chainTo,
                    "; no migration declared from "
                      <> renderVersion stuck
                      <> ", remote is at "
                      <> renderVersion target
                  )
       in "  "
            <> name.unModuleName
            <> ": "
            <> renderVersion chain.chainFrom
            <> " -> "
            <> renderVersion effectiveTo
            <> " ("
            <> T.pack (show (length chain.chainSteps))
            <> " step(s))"
            <> tail_

-- | Apply one pending chain in-band. Reuses 'runMigrate' with
-- @migrateNoFetch=True@ since 'detectPendingMigrations' already
-- compared against the locally installed copy: there is no need to
-- clone the source repo a second time. Migration conflicts (a tracked
-- file the user has edited since generation) propagate as a hard
-- failure here; @seihou run --force@ governs the run plan's diff
-- conflicts, not migration conflicts. The fix is to run @seihou
-- migrate <module> --force@ first.
applyOneMigration ::
  LogLevel ->
  Manifest ->
  (ModuleName, MigrationPlan) ->
  IO Manifest
applyOneMigration level manifest (modName, plan) =
  case findAppliedByName manifest modName of
    Nothing -> do
      logIO level $
        logError $
          "internal error: applied module '"
            <> modName.unModuleName
            <> "' missing while applying its migration"
      exitFailure
    Just am
      -- Blocked: no migration starts at the manifest version, and
      -- (since handleBlocking has already filtered out benign
      -- entries) the author shipped at least one migration that just
      -- doesn't reach. The run cannot safely auto-upgrade past the
      -- gap (writing the new template into the old layout is the
      -- original EP-3 hazard), so refuse with the same "Blocked: …"
      -- line the migrate renderer would have shown.
      | null plan.planChain.chainSteps,
        Just (stuck, target) <- plan.planUnreachable -> do
          logIO level $
            logError $
              "Migration blocked for "
                <> modName.unModuleName
                <> ": no migration declared from "
                <> renderVersion stuck
                <> "; remote is at "
                <> renderVersion target
                <> ". To proceed, run 'seihou migrate "
                <> modName.unModuleName
                <> " --bump-only' to acknowledge no migration is needed (or 'seihou run --bump-blocked' to do so for every blocked module in one step), or wait for the module author to ship one."
          exitFailure
      | otherwise -> do
          let opts =
                MigrateOpts
                  { migrateModule = modName,
                    migrateTo = Nothing,
                    migrateDryRun = False,
                    migrateForce = False,
                    migrateJson = False,
                    migrateVerbose = False,
                    migrateNoFetch = True,
                    migrateBumpOnly = False,
                    migrateCommit = False,
                    migrateCommitMessage = Nothing
                  }
          result <- runMigrate opts manifest am.source
          case result of
            Right (MigrateApplied _ manifest') -> do
              TIO.putStrLn $ "  Migrated " <> modName.unModuleName
              pure manifest'
            Right (MigrateAppliedPartial _ manifest' stuck target) -> do
              TIO.putStrLn $
                "  Migrated "
                  <> modName.unModuleName
                  <> " (partial; no migration declared from "
                  <> renderVersion stuck
                  <> ", remote is at "
                  <> renderVersion target
                  <> ")"
              pure manifest'
            Right (MigrateAppliedBumpedThrough _ manifest' stuck target) -> do
              -- EP-28: chain prefix ran AND manifest bumped through
              -- the exhausted tail. Surface both pieces so the user
              -- knows where the manifest landed.
              TIO.putStrLn $
                "  Migrated "
                  <> modName.unModuleName
                  <> " (chain prefix applied; "
                  <> renderVersion stuck
                  <> " → "
                  <> renderVersion target
                  <> " bumped through with no migration declared)"
              pure manifest'
            Right (MigrateNoOp _) -> pure manifest
            Right (MigrateDryRunOK _) -> pure manifest
            Right (MigrateDryRunOKPartial _ _ _) -> pure manifest
            Right (MigrateDryRunOKBumpedThrough _ _ _) -> pure manifest
            Right (MigrateBlocked stuck target) -> do
              -- Defensive: the planner-shape check above should make
              -- this branch unreachable, but keep a clear message in
              -- case it ever fires.
              logIO level $
                logError $
                  "Migration blocked for "
                    <> modName.unModuleName
                    <> ": no migration declared from "
                    <> renderVersion stuck
                    <> "; remote is at "
                    <> renderVersion target
                    <> ". To proceed, run 'seihou migrate "
                    <> modName.unModuleName
                    <> " --bump-only' to acknowledge no migration is needed."
              exitFailure
            Right (MigrateBenignUpgrade _ _) ->
              -- Defensive: handleBlocking partitions benign entries
              -- out before we ever get here. If a future caller forgets
              -- to filter, behave like MigrateNoOp — the run flow's
              -- updateAllModules will catch the manifest up.
              pure manifest
            Left err -> do
              logIO level $
                logError $
                  "Migration failed for "
                    <> modName.unModuleName
                    <> ": "
                    <> renderMigrateError err
              exitFailure

-- | Acknowledge a single blocked entry by writing the installed
-- copy's declared version into the manifest with no migration ops
-- applied. The work is delegated to 'runMigrate' with
-- @migrateBumpOnly = True@; this is the same code path
-- @seihou migrate <module> --bump-only@ uses.
bumpOneBlocked ::
  LogLevel ->
  Manifest ->
  (ModuleName, MigrationPlan) ->
  IO Manifest
bumpOneBlocked level manifest (modName, plan) =
  case findAppliedByName manifest modName of
    Nothing -> pure manifest
    Just am -> do
      let opts =
            MigrateOpts
              { migrateModule = modName,
                migrateTo = Nothing,
                migrateDryRun = False,
                migrateForce = False,
                migrateJson = False,
                migrateVerbose = False,
                migrateNoFetch = True,
                migrateBumpOnly = True,
                migrateCommit = False,
                migrateCommitMessage = Nothing
              }
          (fromV, toV) = bumpRange plan
      result <- runMigrate opts manifest am.source
      case result of
        Right (MigrateApplied _ manifest') -> do
          TIO.putStrLn $
            "  Bumping "
              <> modName.unModuleName
              <> " "
              <> fromV
              <> " -> "
              <> toV
              <> " (no migration declared; user-acknowledged)."
          pure manifest'
        Right other -> do
          logIO level $
            logError $
              "internal error: --bump-only for "
                <> modName.unModuleName
                <> " returned unexpected result: "
                <> T.pack (show other)
          exitFailure
        Left err -> do
          logIO level $
            logError $
              "Failed to bump "
                <> modName.unModuleName
                <> ": "
                <> renderMigrateError err
          exitFailure

-- | Pretty-print a single blocked entry for the dry-run summary.
renderBumpDryRun :: (ModuleName, MigrationPlan) -> Text
renderBumpDryRun (modName, plan) =
  let (fromV, toV) = bumpRange plan
   in "  "
        <> modName.unModuleName
        <> ": would bump "
        <> fromV
        <> " -> "
        <> toV
        <> " (no migration declared; user-acknowledged)."

-- | Extract the (from, to) version pair to display for a blocked
-- bump. Prefers the 'planUnreachable' span (which is what
-- @--bump-only@ actually moves the manifest across) and falls back
-- to the chain's bookends as a defensive default.
bumpRange :: MigrationPlan -> (Text, Text)
bumpRange plan = case plan.planUnreachable of
  Just (f, t) -> (renderVersion f, renderVersion t)
  Nothing -> (renderVersion plan.planChain.chainFrom, renderVersion plan.planChain.chainTo)

renderMigrateError :: MigrateError -> Text
renderMigrateError err = case err of
  MigrateModuleNotApplied n -> "module " <> n.unModuleName <> " not applied"
  MigrateNoRecordedVersion n -> "no version recorded for " <> n.unModuleName
  MigrateInstalledModuleEvalFailed _ msg -> msg
  MigrateInstalledModuleHasNoVersion n _ -> "no version on installed " <> n.unModuleName
  MigrateUnparseableInstalledVersion v -> "bad version " <> v
  MigrateUnparseableTargetVersion v -> "bad target version " <> v
  MigrateUnparseableManifestVersion v -> "bad manifest version " <> v
  MigratePlanFailed _ -> "plan failed"
  MigrateExecFailed _ -> "execution failed; revert your edits or run 'seihou migrate <module> --force' first"
  MigrateNoManifest _ -> "no manifest in current dir"
  MigrateConflictingFlags msg -> msg

findAppliedByName :: Manifest -> ModuleName -> Maybe AppliedModule
findAppliedByName manifest name =
  case filter (\am -> am.name == name) manifest.modules of
    (am : _) -> Just am
    [] -> Nothing

-- | Update manifest's applied modules list with all composed modules.
-- | Merge the freshly-composed module instances into the manifest's
-- applied-modules list.
--
-- Each entry keeps its bare 'ModuleName' plus the edge decoration that
-- produced it, so two instances of the same module with different
-- 'ParentVars' coexist in the manifest. Matching against existing
-- entries uses the @(name, parentVars)@ pair, so regenerating only
-- refreshes the matching instance and leaves siblings unchanged.
updateAllModules ::
  [AppliedModule] ->
  [(ModuleInstance, Module, FilePath)] ->
  UTCTime ->
  [AppliedModule]
updateAllModules existing modulesInOrder now =
  let composedKeys =
        Set.fromList
          [ (inst.instanceModule, inst.instanceParentVars)
          | (inst, _, _) <- modulesInOrder
          ]
      filtered = filter (\am -> not (Set.member (am.name, am.parentVars) composedKeys)) existing
      new =
        [ AppliedModule
            { name = inst.instanceModule,
              parentVars = inst.instanceParentVars,
              source = dir,
              moduleVersion = m.version,
              appliedAt = now,
              removal = m.removal
            }
        | (inst, m, dir) <- modulesInOrder
        ]
   in filtered ++ new
