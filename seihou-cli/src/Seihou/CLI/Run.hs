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
import Seihou.Core.Module (defaultSearchPaths, discoverModule, validateModule)
import Seihou.Core.Types
import Seihou.Core.Variable (resolveVariables)
import Seihou.Dhall.Eval (evalModuleFromFile)
import Seihou.Effect.Filesystem (createDirectoryIfMissing)
import Seihou.Effect.FilesystemInterp (runFilesystem)
import Seihou.Effect.ManifestStore (readManifest, writeManifest)
import Seihou.Effect.ManifestStoreInterp (runManifestStore)
import Seihou.Engine.Diff (computeDiff)
import Seihou.Engine.Execute (dryRunPlan, executePlan)
import Seihou.Engine.Plan (compilePlan)
import Seihou.Manifest.Types (emptyManifest)
import System.Environment (getEnvironment)
import System.Exit (exitFailure)
import System.FilePath (takeDirectory, (</>))

handleRun :: RunOpts -> IO ()
handleRun runOpts = do
  let modName = runModule runOpts

  -- 1. Discover module directory
  searchPaths <- defaultSearchPaths
  discovered <- discoverModule searchPaths modName
  moduleDir <- case discovered of
    Left (ModuleNotFound _ searched) -> do
      TIO.putStrLn $ "Module '" <> unModuleName modName <> "' not found."
      TIO.putStrLn "Searched in:"
      mapM_ (\p -> TIO.putStrLn $ "  " <> T.pack p) searched
      exitFailure
    Left err -> exitError (T.pack (show err))
    Right dir -> pure dir

  -- 2. Load and validate the module
  modul <- loadModuleFromDir moduleDir

  -- 3. Resolve variables (CLI overrides + environment)
  envPairs <- getEnvironment
  let cliOverrides = Map.fromList [(VarName k, v) | (k, v) <- runVars runOpts]
      envVars = Map.fromList [(T.pack k, T.pack v) | (k, v) <- envPairs]
  resolved <- case resolveVariables (moduleVars modul) cliOverrides envVars of
    Left errs -> do
      TIO.putStrLn "Error resolving variables:"
      mapM_ (TIO.putStrLn . ("  " <>) . formatVarError) errs
      exitFailure
    Right r -> pure r

  -- 4. Compile the plan
  let resolvedVals = Map.map resolvedValue resolved
  planResult <- compilePlan moduleDir modul resolvedVals
  ops <- case planResult of
    Left errs -> do
      TIO.putStrLn "Errors compiling plan:"
      mapM_ (TIO.putStrLn . ("  " <>)) errs
      exitFailure
    Right o -> pure o

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

            -- Build updated manifest
            let orphanedPaths = map orphanedPath (diffOrphaned diff)
                cleanedFiles = foldr Map.delete (manifestFiles manifest) orphanedPaths
                newManifest =
                  manifest
                    { manifestGenAt = now,
                      manifestModules = updateModules (manifestModules manifest) modName moduleDir now,
                      manifestVars = Map.map varValueToText resolvedVals,
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

-- | Load a module from its directory: evaluate Dhall and validate.
loadModuleFromDir :: FilePath -> IO Module
loadModuleFromDir moduleDir = do
  let dhallFile = moduleDir </> "module.dhall"
  decoded <- evalModuleFromFile dhallFile
  case decoded of
    Left err -> exitError (T.pack (show err))
    Right m -> do
      validated <- validateModule moduleDir m
      case validated of
        Left err -> exitError (T.pack (show err))
        Right valid -> pure valid

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

updateModules :: [AppliedModule] -> ModuleName -> FilePath -> UTCTime -> [AppliedModule]
updateModules existing modName moduleDir now =
  let filtered = filter (\am -> appliedName am /= modName) existing
      new = AppliedModule {appliedName = modName, appliedSource = moduleDir, appliedAt = now}
   in filtered ++ [new]
