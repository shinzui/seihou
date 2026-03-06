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
import Seihou.Core.Module (defaultSearchPaths)
import Seihou.Core.Types
import Seihou.Core.Variable (diagnoseResolution)
import Seihou.Effect.ConfigReader (readGlobalConfig, readLocalConfig, readNamespaceConfig)
import Seihou.Effect.ConfigReaderInterp (runConfigReader)
import Seihou.Effect.ConsoleInterp (runConsole)
import Seihou.Effect.Filesystem (createDirectoryIfMissing)
import Seihou.Effect.FilesystemInterp (runFilesystem)
import Seihou.Effect.Logger (logDebug, logError, logInfo, logWarn)
import Seihou.Effect.ManifestStore (readManifest, writeManifest)
import Seihou.Effect.ManifestStoreInterp (runManifestStore)
import Seihou.Effect.Process (runProcess)
import Seihou.Effect.ProcessInterp (runProcessIO)
import Seihou.Engine.Conflict (resolveConflicts)
import Seihou.Engine.Diff (computeDiff)
import Seihou.Engine.Execute (executePlan)
import Seihou.Engine.Preview (buildPreview)
import Seihou.Manifest.Types (emptyManifest)
import Seihou.Prelude
import System.Environment (getEnvironment)
import System.Exit (ExitCode (..), exitFailure, exitWith)
import System.FilePath (takeDirectory)
import System.IO (hFlush, hIsTerminalDevice, stdin, stdout)

handleRun :: RunOpts -> IO ()
handleRun runOpts = do
  let modName = runModule runOpts
      additional = runAdditional runOpts
      level = if runVerbose runOpts then LogVerbose else LogNormal

  -- 1. Load all modules in the composition (primary + additional + transitive deps)
  searchPaths <- defaultSearchPaths
  compositionResult <- loadComposition searchPaths modName additional
  modulesInOrder <- case compositionResult of
    Left (ModuleNotFound name searched) -> do
      logIO level $ do
        logError $ "Module '" <> unModuleName name <> "' not found."
        logError "Searched in:"
        mapM_ (\p -> logError $ "  " <> T.pack p) searched
      exitFailure
    Left (CircularDependency names) -> do
      logIO level $ do
        logError "Circular dependency detected:"
        logError $ "  " <> T.intercalate " -> " (map unModuleName names)
      exitFailure
    Left err -> exitError level (T.pack (show err))
    Right ms -> pure ms

  -- Report composition when multiple modules are involved
  when (length modulesInOrder > 1) $
    logIO level $ do
      logInfo $ "Composing " <> T.pack (show (length modulesInOrder)) <> " modules:"
      mapM_ (\(m, _) -> logInfo $ "  " <> unModuleName (moduleName m)) modulesInOrder

  -- 2. Resolve variables with export visibility and interactive prompts
  envPairs <- getEnvironment
  let cliOverrides = Map.fromList [(VarName k, v) | (k, v) <- runVars runOpts]
      envVars = Map.fromList [(T.pack k, T.pack v) | (k, v) <- envPairs]
      namespace = fromMaybe (deriveNamespace modName) (runNamespace runOpts)
  (resolveResult, localMap, nsMap, globalMap) <- runEff $ runConfigReader $ runConsole $ do
    localCfg <- readLocalConfig >>= unwrapConfig level
    namespaceCfg <- readNamespaceConfig namespace >>= unwrapConfig level
    globalCfg <- readGlobalConfig >>= unwrapConfig level
    let lm = toVarNameMap localCfg
        nm = toVarNameMap namespaceCfg
        gm = toVarNameMap globalCfg
    r <- resolveWithPrompts modulesInOrder cliOverrides envVars namespace lm nm gm
    pure (r, lm, nm, gm)
  resolved <- case resolveResult of
    Left errs -> do
      logIO level $ do
        logError "Error resolving variables:"
        mapM_ (logError . ("  " <>) . formatVarError) errs
      exitFailure
    Right r -> pure r

  -- 2b. Emit diagnostics for unused config keys
  let allDecls = concatMap (moduleVars . fst) modulesInOrder
      allResolved = Map.unions [vs | vs <- Map.elems resolved]
      (unusedKeys, _) = diagnoseResolution allResolved allDecls localMap nsMap globalMap
  when (not (null unusedKeys)) $
    logIO level $
      logWarn $
        "Config keys not matching any declared variable: "
          <> T.intercalate ", " (map unVarName unusedKeys)

  -- 3. Compile composed plan (all modules merged)
  let triples =
        [ (m, dir, Map.map resolvedValue (resolved Map.! moduleName m))
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
        if runNoCommands runOpts
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

  let moduleNames = map (moduleName . fst) modulesInOrder
      allVarValues =
        Map.unions
          [Map.map resolvedValue vs | vs <- Map.elems resolved]
      preview = buildPreview opsFiltered (Just diff) ownerMap

  -- 6. Handle --dry-run: show plan view and exit
  if runDryRun runOpts
    then
      TIO.putStr (formatPlanViewColor colorEnabled moduleNames allVarValues preview diff)
    else
      if runDiff runOpts
        then TIO.putStr (formatDiff colorEnabled diff ownerMap)
        else do
          -- Show plan view
          TIO.putStr (formatPlanViewColor colorEnabled moduleNames allVarValues preview diff)

          -- Prompt for confirmation (skip if --force or non-interactive)
          interactive <- hIsTerminalDevice stdin
          when (interactive && not (runForce runOpts)) $ do
            TIO.putStr "\n  Proceed? [Y/n] "
            hFlush stdout
            response <- T.strip . T.pack <$> getLine
            when (response /= "" && T.toLower response /= "y") $
              exitWith (ExitFailure 3)

          -- Resolve conflicts interactively (or abort)
          resolutions <-
            runEff $
              runConsole $
                resolveConflicts (runForce runOpts) (diffConflict diff)
          case resolutions of
            Nothing -> do
              TIO.putStrLn "Conflicts detected (use --force to overwrite):"
              mapM_ (\c -> TIO.putStrLn $ "  ! " <> T.pack (conflictPath c)) (diffConflict diff)
              exitFailure
            Just conflictResolved -> do
              -- Partition resolutions: accept (overwrite), keep (update manifest only), skip (ignore)
              let keepRecords =
                    Map.fromList
                      [ ( conflictPath c,
                          case Map.lookup (conflictPath c) (manifestFiles manifest) of
                            Just existing ->
                              existing {fileHash = conflictDisk c, fileGeneratedAt = now}
                            Nothing ->
                              FileRecord
                                { fileHash = conflictDisk c,
                                  fileModule = conflictModule c,
                                  fileStrategy = Template,
                                  fileGeneratedAt = now
                                }
                        )
                      | (c, KeepCurrent) <- conflictResolved
                      ]
                  skipPaths = [conflictPath c | (c, Skip) <- conflictResolved]
                  excludePaths = Set.fromList (Map.keys keepRecords ++ skipPaths)
                  opsForExec = filter (not . opTargetsPath excludePaths) opsFiltered

              -- Execute the plan (excluding kept/skipped files)
              runEff $ runFilesystem $ runManifestStore manifestPath $ do
                recs <- executePlan "" opsForExec modName now

                -- Build updated manifest with all composed modules
                let orphanedPaths = map orphanedPath (diffOrphaned diff)
                    cleanedFiles = foldr Map.delete (manifestFiles manifest) orphanedPaths
                    allModuleEntries = updateAllModules (manifestModules manifest) modulesInOrder now
                    allResolvedVals =
                      Map.unions
                        [Map.map resolvedValue vs | vs <- Map.elems resolved]
                    newManifest =
                      manifest
                        { manifestGenAt = now,
                          manifestModules = allModuleEntries,
                          manifestVars = Map.map varValueToText allResolvedVals,
                          manifestFiles = Map.unions [recs, keepRecords, cleanedFiles]
                        }

                -- Save manifest
                writeManifest newManifest

              -- Report results
              let nNew = length (diffNew diff)
                  nMod = length (diffModified diff)
                  nUnch = length (diffUnchanged diff)
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
      <> unModuleName overwritten
      <> ") overwritten by "
      <> unModuleName overwriter
printWarning level (ContentMerged path base contributor) =
  logIO level . logWarn $
    "Merged: "
      <> T.pack path
      <> " (base from "
      <> unModuleName base
      <> ", patched by "
      <> unModuleName contributor
      <> ")"

formatDiff :: Bool -> DiffResult -> Map.Map FilePath ModuleName -> Text
formatDiff color diff ownerMap' =
  T.unlines $
    concat
      [ if null (diffNew diff)
          then []
          else "New files:" : map (\f -> "  " <> colorWrap green "[new]" <> "  " <> colorWrap green (T.pack (plannedPath f)) <> modSuffix (plannedPath f)) (diffNew diff),
        if null (diffModified diff)
          then []
          else "Modified files:" : map (\f -> "  " <> colorWrap yellow "[modified]" <> "  " <> colorWrap yellow (T.pack (modifiedPath f)) <> modSuffix (modifiedPath f)) (diffModified diff),
        if null (diffUnchanged diff)
          then []
          else "Unchanged files:" : map (\f -> "  " <> colorWrap dim "[unchanged]" <> "  " <> colorWrap dim (T.pack f)) (diffUnchanged diff),
        if null (diffConflict diff)
          then []
          else "Conflicts:" : map (\f -> "  " <> colorWrap (bold . red) "[conflict]" <> "  " <> colorWrap (bold . red) (T.pack (conflictPath f)) <> modSuffix (conflictPath f)) (diffConflict diff),
        if null (diffOrphaned diff)
          then []
          else "Orphaned files:" : map (\f -> "  " <> colorWrap magenta "[orphaned]" <> "  " <> colorWrap magenta (T.pack (orphanedPath f))) (diffOrphaned diff)
      ]
  where
    colorWrap fn t = if color then fn t else t
    modSuffix path = case Map.lookup path ownerMap' of
      Just mn -> "  " <> colorWrap dim ("(" <> unModuleName mn <> ")")
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
  let composedNames = map (moduleName . fst) modulesInOrder
      filtered = filter (\am -> appliedName am `notElem` composedNames) existing
      new =
        [ AppliedModule
            { appliedName = moduleName m,
              appliedSource = dir,
              appliedAt = now
            }
        | (m, dir) <- modulesInOrder
        ]
   in filtered ++ new
