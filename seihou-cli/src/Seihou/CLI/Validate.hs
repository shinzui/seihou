module Seihou.CLI.Validate
  ( handleValidateModule,
  )
where

import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.Commands (ValidateOpts (..))
import Seihou.CLI.Shared (logIO)
import Seihou.CLI.Style (renderReportColor, useColor)
import Seihou.Core.Types
import Seihou.Dhall.Eval (evalModuleFromFile)
import Seihou.Effect.Logger (logError)
import Seihou.Engine.Validate (ValidateReport (..), buildReport, reportHasErrors)
import Seihou.Prelude
import System.Directory (doesFileExist, getCurrentDirectory)
import System.Exit (ExitCode (..), exitFailure, exitWith)

handleValidateModule :: ValidateOpts -> IO ()
handleValidateModule vopts = do
  -- Determine module path
  moduleDir <- case vopts.validatePath of
    Just p -> pure p
    Nothing -> getCurrentDirectory

  let dhallFile = moduleDir </> "module.dhall"

  -- Check that module.dhall exists
  exists <- doesFileExist dhallFile
  if not exists
    then do
      logIO LogNormal (logError $ T.pack dhallFile <> " not found.")
      exitWith (ExitFailure 4)
    else pure ()

  -- Evaluate Dhall
  decoded <- evalModuleFromFile dhallFile
  colorEnabled <- useColor

  case decoded of
    Left err -> do
      -- Dhall failed: build a report with reportDhallOk = False
      let dummyModule =
            Module
              { name = ModuleName "<unknown>",
                description = Nothing,
                vars = [],
                exports = [],
                prompts = [],
                steps = [],
                commands = [],
                dependencies = []
              }
          report =
            ValidateReport
              { reportModule = dummyModule,
                reportPath = moduleDir,
                reportDhallOk = False,
                reportDhallError = Just (T.pack (show err)),
                reportChecks = []
              }
      TIO.putStr (renderReportColor colorEnabled report)
      exitFailure
    Right modul -> do
      -- Build the structured report
      report <- buildReport vopts.validateLint moduleDir modul
      TIO.putStr (renderReportColor colorEnabled report)
      if reportHasErrors report
        then exitFailure
        else pure ()
