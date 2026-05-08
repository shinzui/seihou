module Seihou.CLI.ValidateBlueprint
  ( handleValidateBlueprint,
  )
where

import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.Commands (ValidateBlueprintOpts (..))
import Seihou.CLI.Shared (logIO)
import Seihou.CLI.Style (bold, cyan, dim, green, red, useColor, yellow)
import Seihou.Core.Blueprint
  ( checkBlueprintAllowedTools,
    checkBlueprintBaseModules,
    checkBlueprintFiles,
    checkBlueprintNameFormat,
    checkBlueprintPromptNonEmpty,
    checkBlueprintPromptRefs,
    checkBlueprintTags,
    checkBlueprintUniqueVars,
    checkBlueprintVersionPresent,
  )
import Seihou.Core.Types
import Seihou.Dhall.Eval (evalBlueprintFromFile)
import Seihou.Effect.Logger (logError)
import Seihou.Engine.Validate (DiagCheck (..), DiagSeverity (..))
import Seihou.Prelude
import System.Directory (doesFileExist, getCurrentDirectory)
import System.Exit (ExitCode (..), exitFailure, exitWith)

-- | A complete validation report for a blueprint. Mirrors
-- 'Seihou.Engine.Validate.ValidateReport' but is keyed on a 'Blueprint'
-- rather than a 'Module', and reports on the rules that apply to
-- blueprints (no steps, no exports, no commands, but a non-empty prompt
-- and a 'files/' integrity check).
data BlueprintReport = BlueprintReport
  { -- | 'Nothing' when Dhall evaluation failed; otherwise the decoded record
    brBlueprint :: Maybe Blueprint,
    -- | Display name; equals the decoded blueprint's name when available
    brName :: Text,
    brPath :: FilePath,
    brDhallOk :: Bool,
    brDhallError :: Maybe Text,
    brChecks :: [DiagCheck]
  }

handleValidateBlueprint :: ValidateBlueprintOpts -> IO ()
handleValidateBlueprint vopts = do
  blueprintDir <- case vopts.validateBlueprintPath of
    Just p -> pure p
    Nothing -> getCurrentDirectory

  let dhallFile = blueprintDir </> "blueprint.dhall"

  exists <- doesFileExist dhallFile
  if not exists
    then do
      logIO LogNormal (logError $ T.pack dhallFile <> " not found.")
      exitWith (ExitFailure 4)
    else pure ()

  decoded <- evalBlueprintFromFile dhallFile
  colorEnabled <- useColor

  case decoded of
    Left err -> do
      let report =
            BlueprintReport
              { brBlueprint = Nothing,
                brName = "<unknown>",
                brPath = blueprintDir,
                brDhallOk = False,
                brDhallError = Just (T.pack (show err)),
                brChecks = []
              }
      TIO.putStr (renderBlueprintReport colorEnabled report)
      exitFailure
    Right bp -> do
      report <- buildBlueprintReport blueprintDir bp
      TIO.putStr (renderBlueprintReport colorEnabled report)
      if blueprintReportHasErrors report
        then exitFailure
        else pure ()

-- | Build a structured validation report for a decoded blueprint by
-- running each of EP-29's pure and IO check functions and labelling the
-- result. Lint warnings are not yet implemented — the @--lint@ flag is
-- accepted for parity with @validate-module@ but currently has no
-- effect; future work can extend this list.
buildBlueprintReport :: FilePath -> Blueprint -> IO BlueprintReport
buildBlueprintReport baseDir b = do
  fileErrors <- checkBlueprintFiles baseDir b
  baseErrors <- checkBlueprintBaseModules b
  let checks =
        [ DiagCheck "Blueprint name format" DiagError (checkBlueprintNameFormat b),
          DiagCheck "Blueprint version" DiagError (checkBlueprintVersionPresent b),
          DiagCheck "Prompt body non-empty" DiagError (checkBlueprintPromptNonEmpty b),
          DiagCheck "Unique variable names" DiagError (checkBlueprintUniqueVars b),
          DiagCheck "Prompt references" DiagError (checkBlueprintPromptRefs b),
          DiagCheck "Base modules" DiagError baseErrors,
          DiagCheck "Reference file existence" DiagError fileErrors,
          DiagCheck "Tags" DiagError (checkBlueprintTags b),
          DiagCheck "Allowed tools" DiagError (checkBlueprintAllowedTools b)
        ]
  pure
    BlueprintReport
      { brBlueprint = Just b,
        brName = b.name.unModuleName,
        brPath = baseDir,
        brDhallOk = True,
        brDhallError = Nothing,
        brChecks = checks
      }

blueprintReportHasErrors :: BlueprintReport -> Bool
blueprintReportHasErrors r =
  not r.brDhallOk
    || any (\c -> c.diagSeverity == DiagError && not (null c.diagDetails)) r.brChecks

renderBlueprintReport :: Bool -> BlueprintReport -> Text
renderBlueprintReport color report =
  T.unlines $
    [ "Validating blueprint at " <> T.pack report.brPath <> "...",
      ""
    ]
      ++ dhallLine
      ++ summaryLines
      ++ checkLines
      ++ [""]
      ++ [resultLine]
  where
    okMark = if color then green "\x2713" else "\x2713"
    errMark = if color then bold (red "\x2717") else "\x2717"
    warnMark = if color then yellow "\x26A0" else "\x26A0"
    nameStyle t = if color then cyan t else t
    detailStyle t = if color then dim t else t
    labelErr t = if color then red t else t
    labelWarn t = if color then yellow t else t

    dhallLine =
      if report.brDhallOk
        then ["  " <> okMark <> " blueprint.dhall evaluates successfully"]
        else
          ["  " <> errMark <> " blueprint.dhall failed to evaluate"]
            ++ case report.brDhallError of
              Just errText -> ["      " <> detailStyle errText]
              Nothing -> []

    summaryLines = case report.brBlueprint of
      Nothing -> []
      Just b ->
        [ "  " <> okMark <> " Blueprint name: " <> nameStyle b.name.unModuleName,
          "  " <> okMark <> " " <> T.pack (show (length b.vars)) <> " variables declared",
          "  " <> okMark <> " " <> T.pack (show (length b.prompts)) <> " prompts defined",
          "  " <> okMark <> " " <> T.pack (show (length b.baseModules)) <> " base modules declared",
          "  " <> okMark <> " " <> T.pack (show (length b.files)) <> " reference files declared"
        ]

    checkLines = concatMap renderCheck report.brChecks

    renderCheck c
      | null c.diagDetails =
          ["  " <> okMark <> " " <> c.diagLabel]
      | c.diagSeverity == DiagWarning =
          ("  " <> warnMark <> " " <> labelWarn c.diagLabel)
            : map (\d -> "      " <> detailStyle d) c.diagDetails
      | otherwise =
          ("  " <> errMark <> " " <> labelErr c.diagLabel)
            : map (\d -> "      " <> detailStyle d) c.diagDetails

    errorCount =
      length
        [ ()
        | c <- report.brChecks,
          c.diagSeverity == DiagError,
          not (null c.diagDetails)
        ]

    dhallFailed = not report.brDhallOk
    totalErrors = errorCount + (if dhallFailed then 1 else 0)

    resultLine
      | totalErrors > 0 =
          let msg = T.pack (show totalErrors) <> " error(s) found."
           in (if color then bold (red msg) else msg) <> " Blueprint is invalid."
      | otherwise =
          let msg = "Blueprint '" <> report.brName <> "' is valid."
           in if color then green msg else msg
