module Seihou.CLI.Run
  ( handleRun,
  )
where

import Control.Monad (when)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Time (UTCTime)
import Data.Time.Clock (getCurrentTime)
import Effectful
import Seihou.CLI.Commands (RunOpts (..))
import Seihou.Composition.Plan (compileComposedPlan)
import Seihou.Composition.Resolve (loadComposition, resolveWithPrompts)
import Seihou.Core.Module (defaultSearchPaths)
import Seihou.Core.Types
import Seihou.Effect.ConsoleInterp (runConsole)
import Seihou.Effect.Filesystem (createDirectoryIfMissing)
import Seihou.Effect.FilesystemInterp (runFilesystem)
import Seihou.Effect.ManifestStore (readManifest, writeManifest)
import Seihou.Effect.ManifestStoreInterp (runManifestStore)
import Seihou.Engine.Diff (computeDiff)
import Seihou.Engine.Execute (dryRunPlan, executePlan)
import Seihou.Manifest.Types (emptyManifest)
import System.Environment (getEnvironment)
import System.Exit (exitFailure)
import System.FilePath (takeDirectory, (</>))

handleRun :: RunOpts -> IO ()
handleRun runOpts = do
  let modName = runModule runOpts
      additional = runAdditional runOpts

  -- 1. Load all modules in the composition (primary + additional + transitive deps)
  searchPaths <- defaultSearchPaths
  compositionResult <- loadComposition searchPaths modName additional
  modulesInOrder <- case compositionResult of
    Left (ModuleNotFound name searched) -> do
      TIO.putStrLn $ "Module '" <> unModuleName name <> "' not found."
      TIO.putStrLn "Searched in:"
      mapM_ (\p -> TIO.putStrLn $ "  " <> T.pack p) searched
      exitFailure
    Left (CircularDependency names) -> do
      TIO.putStrLn "Circular dependency detected:"
      TIO.putStrLn $ "  " <> T.intercalate " -> " (map unModuleName names)
      exitFailure
    Left err -> exitError (T.pack (show err))
    Right ms -> pure ms

  -- Report composition when multiple modules are involved
  when (length modulesInOrder > 1) $ do
    TIO.putStrLn $ "Composing " <> T.pack (show (length modulesInOrder)) <> " modules:"
    mapM_ (\(m, _) -> TIO.putStrLn $ "  " <> unModuleName (moduleName m)) modulesInOrder

  -- 2. Resolve variables with export visibility and interactive prompts
  envPairs <- getEnvironment
  let cliOverrides = Map.fromList [(VarName k, v) | (k, v) <- runVars runOpts]
      envVars = Map.fromList [(T.pack k, T.pack v) | (k, v) <- envPairs]
  resolveResult <- runEff $ runConsole $ resolveWithPrompts modulesInOrder cliOverrides envVars
  resolved <- case resolveResult of
    Left errs -> do
      TIO.putStrLn "Error resolving variables:"
      mapM_ (TIO.putStrLn . ("  " <>) . formatVarError) errs
      exitFailure
    Right r -> pure r

  -- 3. Compile composed plan (all modules merged)
  let triples =
        [ (m, dir, Map.map resolvedValue (resolved Map.! moduleName m))
        | (m, dir) <- modulesInOrder
        ]
  planResult <- compileComposedPlan triples
  (ops, warnings) <- case planResult of
    Left errs -> do
      TIO.putStrLn "Errors compiling plan:"
      mapM_ (TIO.putStrLn . ("  " <>)) errs
      exitFailure
    Right r -> pure r

  -- 4. Print composition warnings
  mapM_ printWarning warnings

  -- 5. Handle --dry-run: print plan and exit
  if runDryRun runOpts
    then do
      TIO.putStrLn "Dry run — operations that would be performed:"
      TIO.putStr (dryRunPlan ops)
    else do
      -- 6. Run the effectful pipeline
      now <- getCurrentTime
      let manifestPath = ".seihou" </> "manifest.json"
          planned = [(dest, content, modName) | WriteFileOp dest content <- ops]

      runEff $ runFilesystem $ runManifestStore manifestPath $ do
        -- Ensure .seihou/ directory exists
        createDirectoryIfMissing True (takeDirectory manifestPath)

        -- Load existing manifest (or empty)
        existing <- readManifest
        let manifest = fromMaybe (emptyManifest now) existing

        -- Compute three-state diff
        diff <- computeDiff manifest planned

        -- Handle --diff: show diff only
        if runDiff runOpts
          then liftIO $ TIO.putStr (formatDiff diff)
          else do
            -- Check for conflicts
            when (not (null (diffConflict diff)) && not (runForce runOpts)) $
              liftIO $ do
                TIO.putStrLn "Conflicts detected (use --force to overwrite):"
                mapM_ (\c -> TIO.putStrLn $ "  ! " <> T.pack (conflictPath c)) (diffConflict diff)
                exitFailure

            -- Execute the plan
            records <- executePlan "" ops modName now

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
                      manifestFiles = Map.union records cleanedFiles
                    }

            -- Save manifest
            writeManifest newManifest

            -- Report results
            liftIO $ do
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

-- Helpers

exitError :: Text -> IO a
exitError msg = do
  TIO.putStrLn $ "Error: " <> msg
  exitFailure

formatVarError :: VarError -> Text
formatVarError (MissingRequiredVar (VarName n)) = "missing required variable: " <> n
formatVarError (TypeMismatch (VarName n) _ _) = "type mismatch for variable: " <> n
formatVarError (ValidationFailed (VarName n) msg) = "validation failed for " <> n <> ": " <> msg
formatVarError (CoercionFailed (VarName n) _ raw) = "cannot coerce '" <> raw <> "' for variable: " <> n

printWarning :: CompositionWarning -> IO ()
printWarning (FileOverwritten path overwritten overwriter) =
  TIO.putStrLn $
    "Warning: "
      <> T.pack path
      <> " (from "
      <> unModuleName overwritten
      <> ") overwritten by "
      <> unModuleName overwriter

formatDiff :: DiffResult -> Text
formatDiff diff =
  T.unlines $
    concat
      [ if null (diffNew diff)
          then []
          else "New files:" : map (\f -> "  + " <> T.pack (plannedPath f)) (diffNew diff),
        if null (diffModified diff)
          then []
          else "Modified files:" : map (\f -> "  ~ " <> T.pack (modifiedPath f)) (diffModified diff),
        if null (diffUnchanged diff)
          then []
          else "Unchanged files:" : map (\f -> "  = " <> T.pack f) (diffUnchanged diff),
        if null (diffConflict diff)
          then []
          else "Conflicts:" : map (\f -> "  ! " <> T.pack (conflictPath f)) (diffConflict diff),
        if null (diffOrphaned diff)
          then []
          else "Orphaned files:" : map (\f -> "  - " <> T.pack (orphanedPath f)) (diffOrphaned diff)
      ]

varValueToText :: VarValue -> Text
varValueToText (VText t) = t
varValueToText (VBool True) = "true"
varValueToText (VBool False) = "false"
varValueToText (VInt n) = T.pack (show n)
varValueToText (VList vs) = T.intercalate "," (map varValueToText vs)

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
