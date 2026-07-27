module Seihou.CLI.ValidateBlueprint
  ( handleValidateBlueprint,
  )
where

import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.AgentConfig (agentLaunchDeclaration, validateAgentLaunchDeclaration)
import Seihou.CLI.Commands (ValidateBlueprintOpts (..))
import Seihou.CLI.Shared (logIO)
import Seihou.CLI.Style (bold, cyan, dim, green, red, useColor, yellow)
import Seihou.Core.Blueprint
  ( checkBlueprintAllowedTools,
    checkBlueprintBaseModules,
    checkBlueprintFiles,
    checkBlueprintLaunch,
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
    blueprint :: !(Maybe Blueprint),
    -- | Display name; equals the decoded blueprint's name when available
    name :: !Text,
    path :: !FilePath,
    dhallOk :: !Bool,
    dhallError :: !(Maybe Text),
    checks :: ![DiagCheck]
  }
  deriving stock (Generic)

handleValidateBlueprint :: ValidateBlueprintOpts -> IO ()
handleValidateBlueprint vopts = do
  blueprintDir <- case vopts.path of
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
              { blueprint = Nothing,
                name = "<unknown>",
                path = blueprintDir,
                dhallOk = False,
                dhallError = Just (T.pack (show err)),
                checks = []
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
          DiagCheck "Allowed tools" DiagError (checkBlueprintAllowedTools b),
          -- Two layers: the core rule rejects blanks, and the CLI parses the
          -- declared provider and effort against the vocabularies it owns.
          DiagCheck
            "Launch settings"
            DiagError
            ( checkBlueprintLaunch b
                <> validateAgentLaunchDeclaration (agentLaunchDeclaration b.launch)
            )
        ]
  pure
    BlueprintReport
      { blueprint = Just b,
        name = b.name.unModuleName,
        path = baseDir,
        dhallOk = True,
        dhallError = Nothing,
        checks = checks
      }

blueprintReportHasErrors :: BlueprintReport -> Bool
blueprintReportHasErrors r =
  not r.dhallOk
    || any (\c -> c.severity == DiagError && not (null c.details)) r.checks

renderBlueprintReport :: Bool -> BlueprintReport -> Text
renderBlueprintReport color report =
  T.unlines $
    [ "Validating blueprint at " <> T.pack report.path <> "...",
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
      if report.dhallOk
        then ["  " <> okMark <> " blueprint.dhall evaluates successfully"]
        else
          ["  " <> errMark <> " blueprint.dhall failed to evaluate"]
            ++ case report.dhallError of
              Just errText -> ["      " <> detailStyle errText]
              Nothing -> []

    summaryLines = case report.blueprint of
      Nothing -> []
      Just b ->
        [ "  " <> okMark <> " Blueprint name: " <> nameStyle b.name.unModuleName,
          "  " <> okMark <> " " <> T.pack (show (length b.vars)) <> " variables declared",
          "  " <> okMark <> " " <> T.pack (show (length b.prompts)) <> " prompts defined",
          "  " <> okMark <> " " <> T.pack (show (length b.baseModules)) <> " base modules declared",
          "  " <> okMark <> " " <> T.pack (show (length b.files)) <> " reference files declared"
        ]

    checkLines = concatMap renderCheck report.checks

    renderCheck c
      | null c.details =
          ["  " <> okMark <> " " <> c.label]
      | c.severity == DiagWarning =
          ("  " <> warnMark <> " " <> labelWarn c.label)
            : map (\d -> "      " <> detailStyle d) c.details
      | otherwise =
          ("  " <> errMark <> " " <> labelErr c.label)
            : map (\d -> "      " <> detailStyle d) c.details

    errorCount =
      length
        [ ()
        | c <- report.checks,
          c.severity == DiagError,
          not (null c.details)
        ]

    dhallFailed = not report.dhallOk
    totalErrors = errorCount + (if dhallFailed then 1 else 0)

    resultLine
      | totalErrors > 0 =
          let msg = T.pack (show totalErrors) <> " error(s) found."
           in (if color then bold (red msg) else msg) <> " Blueprint is invalid."
      | otherwise =
          let msg = "Blueprint '" <> report.name <> "' is valid."
           in if color then green msg else msg
