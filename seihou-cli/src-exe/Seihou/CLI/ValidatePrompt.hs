module Seihou.CLI.ValidatePrompt
  ( handleValidatePrompt,
  )
where

import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.AgentConfig (agentLaunchDeclaration, validateAgentLaunchDeclaration)
import Seihou.CLI.Commands (ValidatePromptOpts (..))
import Seihou.CLI.Shared (logIO)
import Seihou.CLI.Style (bold, cyan, dim, green, red, useColor, yellow)
import Seihou.Core.AgentPrompt
  ( checkAgentPromptAllowedTools,
    checkAgentPromptBodyNonEmpty,
    checkAgentPromptCommandVars,
    checkAgentPromptFiles,
    checkAgentPromptGuidance,
    checkAgentPromptLaunch,
    checkAgentPromptNameFormat,
    checkAgentPromptPromptRefs,
    checkAgentPromptTags,
    checkAgentPromptUniqueVars,
    checkAgentPromptVersionPresent,
  )
import Seihou.Core.Types
import Seihou.Dhall.Eval (evalAgentPromptFromFile)
import Seihou.Effect.Logger (logError)
import Seihou.Engine.Validate (DiagCheck (..), DiagSeverity (..))
import Seihou.Prelude
import System.Directory (doesFileExist, getCurrentDirectory)
import System.Exit (ExitCode (..), exitFailure, exitWith)

data PromptReport = PromptReport
  { prompt :: !(Maybe AgentPrompt),
    name :: !Text,
    path :: !FilePath,
    dhallOk :: !Bool,
    dhallError :: !(Maybe Text),
    checks :: ![DiagCheck]
  }
  deriving stock (Generic)

handleValidatePrompt :: ValidatePromptOpts -> IO ()
handleValidatePrompt vopts = do
  promptDir <- case vopts.path of
    Just p -> pure p
    Nothing -> getCurrentDirectory

  let dhallFile = promptDir </> "prompt.dhall"

  exists <- doesFileExist dhallFile
  if not exists
    then do
      logIO LogNormal (logError $ T.pack dhallFile <> " not found.")
      exitWith (ExitFailure 4)
    else pure ()

  decoded <- evalAgentPromptFromFile dhallFile
  colorEnabled <- useColor

  case decoded of
    Left err -> do
      let report =
            PromptReport
              { prompt = Nothing,
                name = "<unknown>",
                path = promptDir,
                dhallOk = False,
                dhallError = Just (T.pack (show err)),
                checks = []
              }
      TIO.putStr (renderPromptReport colorEnabled report)
      exitFailure
    Right p -> do
      report <- buildPromptReport promptDir p
      TIO.putStr (renderPromptReport colorEnabled report)
      if promptReportHasErrors report
        then exitFailure
        else pure ()

buildPromptReport :: FilePath -> AgentPrompt -> IO PromptReport
buildPromptReport baseDir p = do
  fileErrors <- checkAgentPromptFiles baseDir p
  let checks =
        [ DiagCheck "Prompt name format" DiagError (checkAgentPromptNameFormat p),
          DiagCheck "Prompt version" DiagError (checkAgentPromptVersionPresent p),
          DiagCheck "Prompt body non-empty" DiagError (checkAgentPromptBodyNonEmpty p),
          DiagCheck "Unique variable names" DiagError (checkAgentPromptUniqueVars p),
          DiagCheck "Prompt references" DiagError (checkAgentPromptPromptRefs p),
          DiagCheck "Command variables" DiagError (checkAgentPromptCommandVars p),
          DiagCheck "Prompt guidance" DiagError (checkAgentPromptGuidance p),
          DiagCheck "Reference file existence" DiagError fileErrors,
          DiagCheck "Tags" DiagError (checkAgentPromptTags p),
          DiagCheck "Allowed tools" DiagError (checkAgentPromptAllowedTools p),
          -- Two layers: the core rule rejects blanks, and the CLI parses the
          -- declared provider and effort against the vocabularies it owns.
          DiagCheck
            "Launch settings"
            DiagError
            ( checkAgentPromptLaunch p
                <> validateAgentLaunchDeclaration (agentLaunchDeclaration p.launch)
            )
        ]
  pure
    PromptReport
      { prompt = Just p,
        name = p.name.unModuleName,
        path = baseDir,
        dhallOk = True,
        dhallError = Nothing,
        checks = checks
      }

promptReportHasErrors :: PromptReport -> Bool
promptReportHasErrors r =
  not r.dhallOk
    || any (\c -> c.severity == DiagError && not (null c.details)) r.checks

renderPromptReport :: Bool -> PromptReport -> Text
renderPromptReport color report =
  T.unlines $
    [ "Validating prompt at " <> T.pack report.path <> "...",
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
        then ["  " <> okMark <> " prompt.dhall evaluates successfully"]
        else
          ["  " <> errMark <> " prompt.dhall failed to evaluate"]
            ++ case report.dhallError of
              Just errText -> ["      " <> detailStyle errText]
              Nothing -> []

    summaryLines = case report.prompt of
      Nothing -> []
      Just p ->
        [ "  " <> okMark <> " Prompt name: " <> nameStyle p.name.unModuleName,
          "  " <> okMark <> " " <> T.pack (show (length p.vars)) <> " variables declared",
          "  " <> okMark <> " " <> T.pack (show (length p.prompts)) <> " prompts defined",
          "  " <> okMark <> " " <> T.pack (show (length p.commandVars)) <> " command variables declared",
          "  " <> okMark <> " " <> T.pack (show (length p.guidance)) <> " guidance blocks declared",
          "  " <> okMark <> " " <> T.pack (show (length p.files)) <> " reference files declared"
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
           in (if color then bold (red msg) else msg) <> " Prompt is invalid."
      | otherwise =
          let msg = "Prompt '" <> report.name <> "' is valid."
           in if color then green msg else msg
