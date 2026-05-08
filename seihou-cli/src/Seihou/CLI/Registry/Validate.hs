module Seihou.CLI.Registry.Validate
  ( ValidateRegistryOpts (..),
    ValidateOutcome (..),
    runValidate,
    handleValidate,
    renderValidationReport,
  )
where

import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import GHC.Generics (Generic)
import Seihou.CLI.Registry.Sync (resolveOnDiskVersions)
import Seihou.Core.Registry
  ( RegistryValidationIssue (..),
    RegistryValidationReport (..),
    RepoContents (..),
    discoverRepoContents,
    formatValidationIssue,
    reportHasIssues,
    validateRegistryFull,
  )
import Seihou.Dhall.Eval (evalRegistryFromFile)
import Seihou.Prelude
import System.Directory (doesDirectoryExist)
import System.Exit (ExitCode (..), exitWith)
import System.IO (hPutStrLn, stderr)

-- | Flags parsed for the @seihou registry validate@ subcommand.
data ValidateRegistryOpts = ValidateRegistryOpts
  { validateRegistryDir :: Maybe FilePath
  }
  deriving stock (Eq, Show, Generic)

-- | Terminal outcome of a validate run, decoupled from IO concerns like
-- printing and 'exitWith' so tests can assert without capturing stdout.
data ValidateOutcome
  = -- | Report ran. Caller decides exit code from 'reportHasIssues'.
    ValidateOk RegistryValidationReport
  | -- | Could not even start (no registry at target dir, etc.).
    ValidateFailed Text
  deriving stock (Eq, Show, Generic)

-- | Testable core of @seihou registry validate@. Locates the registry,
-- resolves each entry's on-disk version, and produces the unified report.
runValidate :: ValidateRegistryOpts -> IO ValidateOutcome
runValidate opts = do
  let target = maybe "." id opts.validateRegistryDir
  dirExists <- doesDirectoryExist target
  if not dirExists
    then pure (ValidateFailed ("target directory does not exist: " <> T.pack target))
    else do
      contents <- discoverRepoContents evalRegistryFromFile target
      case contents of
        MultiModule reg -> do
          lookups <- resolveOnDiskVersions target reg
          report <- validateRegistryFull target reg lookups
          pure (ValidateOk report)
        _ ->
          pure
            ( ValidateFailed
                "registry validate requires a seihou-registry.dhall at the target directory"
            )

-- | Handler wired into the CLI command dispatcher. Drives 'runValidate',
-- prints the report, and exits 0 or 1 based on 'reportHasIssues'.
handleValidate :: ValidateRegistryOpts -> IO ()
handleValidate opts = do
  outcome <- runValidate opts
  case outcome of
    ValidateFailed msg -> do
      hPutStrLn stderr ("error: " <> T.unpack msg)
      exitWith (ExitFailure 1)
    ValidateOk report -> do
      TIO.putStr (renderValidationReport report)
      if reportHasIssues report
        then exitWith (ExitFailure 1)
        else exitWith ExitSuccess

-- | Format the report for stdout. Mirrors the wording shown in the ExecPlan
-- example: an "OK" one-liner on success, an "errors:" list with a summary
-- line on failure.
renderValidationReport :: RegistryValidationReport -> Text
renderValidationReport r
  | null r.reportIssues =
      T.unlines
        [ "OK: "
            <> T.pack (show r.reportModuleCount)
            <> " "
            <> pluralize r.reportModuleCount "module" "modules"
            <> ", "
            <> T.pack (show r.reportRecipeCount)
            <> " "
            <> pluralize r.reportRecipeCount "recipe" "recipes"
            <> ", "
            <> T.pack (show r.reportBlueprintCount)
            <> " "
            <> pluralize r.reportBlueprintCount "blueprint" "blueprints"
            <> ", all versions in sync."
        ]
  | otherwise =
      T.unlines $
        ["errors:"]
          <> map (("  " <>) . formatValidationIssue) r.reportIssues
          <> [""]
          <> [summary r]

summary :: RegistryValidationReport -> Text
summary r =
  let n = length r.reportIssues
      hasVersionDrift = any isVersionMismatch r.reportIssues
      base = T.pack (show n) <> " " <> pluralize n "error" "errors"
      tail_ =
        if hasVersionDrift
          then ". Run `seihou registry sync-versions` to fix version drift."
          else "."
   in base <> tail_
  where
    isVersionMismatch (VersionMismatch _) = True
    isVersionMismatch _ = False

pluralize :: Int -> Text -> Text -> Text
pluralize 1 s _ = s
pluralize _ _ p = p
