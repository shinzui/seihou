module Seihou.CLI.Run
  ( handleRun,
  )
where

import Control.Monad (when)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Set qualified as Set
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Time (UTCTime)
import Data.Time.Clock (getCurrentTime)
import Seihou.CLI.Commands (RunOpts (..))
import Seihou.CLI.Shared (deriveNamespace, formatVarError, logIO, toVarNameMap, unwrapConfig)
import Seihou.CLI.Style (bold, dim, formatPlanViewColor, green, magenta, red, useColor, yellow)
import Seihou.Composition.Plan (compileComposedPlan)
import Seihou.Composition.Resolve (loadComposition, resolveWithPrompts)
import Seihou.Core.Context (resolveContext)
import Seihou.Core.Module (defaultSearchPaths)
import Seihou.Core.Types
import Seihou.Core.Variable (diagnoseResolution)
import Seihou.Effect.ConfigReader (readContextConfig, readGlobalConfig, readLocalConfig, readNamespaceConfig)
import Seihou.Effect.ConfigReaderInterp (runConfigReader)
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
import Seihou.Manifest.Types (emptyManifest)
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

  -- 1. Load all modules in the composition (primary + additional + transitive deps)
  searchPaths <- defaultSearchPaths
  compositionResult <- loadComposition searchPaths modName additional
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
      mapM_ (\(m, _) -> logInfo $ "  " <> m.name.unModuleName) modulesInOrder

  -- 2. Resolve variables with export visibility and interactive prompts
  envPairs <- getEnvironment
  let cliOverrides = Map.fromList [(VarName k, v) | (k, v) <- runOpts.runVars]
      envVars = Map.fromList [(T.pack k, T.pack v) | (k, v) <- envPairs]
      namespace = fromMaybe (deriveNamespace modName) runOpts.runNamespace
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
  resolved <- case resolveResult of
    Left errs -> do
      logIO level $ do
        logError "Error resolving variables:"
        mapM_ (logError . ("  " <>) . formatVarError) errs
      exitFailure
    Right r -> pure r

  -- 2b. Emit diagnostics for unused config keys
  let allDecls = concatMap ((.vars) . fst) modulesInOrder
      allResolved = Map.unions [vs | vs <- Map.elems resolved]
      (unusedKeys, _) = diagnoseResolution allResolved allDecls localMap nsMap ctxMap globalMap
  when (not (null unusedKeys)) $
    logIO level $
      logWarn $
        "Config keys not matching any declared variable: "
          <> T.intercalate ", " (map (.unVarName) unusedKeys)

  -- 3. Compile composed plan (all modules merged)
  let triples =
        [ (m, dir, Map.map (.value) (resolved Map.! m.name))
        | (m, dir) <- modulesInOrder
        ]
  planResult <- compileComposedPlan triples
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
        [(dest, content, modName) | WriteFileOp dest content _ <- opsFiltered]
          ++ [(dest, content, mName) | PatchFileOp dest content _ _ mName <- opsFiltered]

  (manifest, diff) <- runEff $ runFilesystem $ runManifestStore manifestPath $ do
    -- Ensure .seihou/ directory exists
    createDirectoryIfMissing True (takeDirectory manifestPath)

    -- Load existing manifest (or empty)
    existingResult <- readManifest
    existing <- case existingResult of
      Left err -> liftIO $ do
        logIO level (logError $ "Error reading manifest: " <> err)
        exitFailure
      Right m -> pure m
    let m = fromMaybe (emptyManifest now) existing
    d <- computeDiff m planned
    pure (m, d)

  colorEnabled <- useColor

  let modNames = map ((.name) . fst) modulesInOrder
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
                recs <- executePlan "" opsForExec modName now

                -- Build updated manifest with all composed modules
                let orphanedPaths = map (.path) diff.orphaned
                    cleanedFiles = foldr Map.delete manifest.files orphanedPaths
                    allModuleEntries = updateAllModules manifest.modules modulesInOrder now
                    allResolvedVals =
                      Map.unions
                        [Map.map (.value) vs | vs <- Map.elems resolved]
                    newManifest =
                      manifest
                        { genAt = now,
                          modules = allModuleEntries,
                          vars = Map.map varValueToText allResolvedVals,
                          files = Map.unions [recs, keepRecords, cleanedFiles]
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

              -- Execute commands after file generation
              let commandOps = [(cmd, wd) | RunCommandOp cmd wd <- opsForExec]
              mapM_ (executeCommand level) commandOps

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

-- | Update manifest's applied modules list with all composed modules.
updateAllModules :: [AppliedModule] -> [(Module, FilePath)] -> UTCTime -> [AppliedModule]
updateAllModules existing modulesInOrder now =
  let composedNames = map ((.name) . fst) modulesInOrder
      filtered = filter (\am -> am.name `notElem` composedNames) existing
      new =
        [ AppliedModule
            { name = m.name,
              source = dir,
              appliedAt = now
            }
        | (m, dir) <- modulesInOrder
        ]
   in filtered ++ new
