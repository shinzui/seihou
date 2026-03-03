module Seihou.CLI.Validate
  ( handleValidateModule,
  )
where

import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.Commands (ValidateOpts (..))
import Seihou.CLI.Style (renderReportColor, useColor)
import Seihou.Core.Types
import Seihou.Dhall.Eval (evalModuleFromFile)
import Seihou.Engine.Validate (ValidateReport (..), buildReport, reportHasErrors)
import System.Directory (doesFileExist, getCurrentDirectory)
import System.Exit (exitFailure)
import System.FilePath ((</>))

handleValidateModule :: ValidateOpts -> IO ()
handleValidateModule vopts = do
  -- Determine module path
  moduleDir <- case validatePath vopts of
    Just p -> pure p
    Nothing -> getCurrentDirectory

  let dhallFile = moduleDir </> "module.dhall"

  -- Check that module.dhall exists
  exists <- doesFileExist dhallFile
  if not exists
    then do
      TIO.putStrLn $ "Error: " <> T.pack dhallFile <> " not found."
      exitFailure
    else pure ()

  -- Evaluate Dhall
  decoded <- evalModuleFromFile dhallFile
  colorEnabled <- useColor

  case decoded of
    Left _err -> do
      -- Dhall failed: build a report with reportDhallOk = False
      let dummyModule =
            Module
              { moduleName = ModuleName "<unknown>",
                moduleDescription = Nothing,
                moduleVars = [],
                moduleExports = [],
                modulePrompts = [],
                moduleSteps = [],
                moduleCommands = [],
                moduleDependencies = []
              }
          report =
            ValidateReport
              { reportModule = dummyModule,
                reportPath = moduleDir,
                reportDhallOk = False,
                reportChecks = []
              }
      TIO.putStr (renderReportColor colorEnabled report)
      exitFailure
    Right modul -> do
      -- Build the structured report
      report <- buildReport (validateLint vopts) moduleDir modul
      TIO.putStr (renderReportColor colorEnabled report)
      if reportHasErrors report
        then exitFailure
        else pure ()
