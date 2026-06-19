module Seihou.CLI.ValidatePrompt
  ( handleValidatePrompt,
  )
where

import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.Commands (ValidatePromptOpts (..))
import Seihou.CLI.Shared (logIO)
import Seihou.CLI.Style (bold, cyan, dim, green, red, useColor, yellow)
import Seihou.Core.AgentPrompt
  ( checkAgentPromptAllowedTools,
    checkAgentPromptBodyNonEmpty,
    checkAgentPromptCommandVars,
    checkAgentPromptFiles,
    checkAgentPromptGuidance,
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
  { prPrompt :: Maybe AgentPrompt,
    prName :: Text,
    prPath :: FilePath,
    prDhallOk :: Bool,
    prDhallError :: Maybe Text,
    prChecks :: [DiagCheck]
  }

handleValidatePrompt :: ValidatePromptOpts -> IO ()
handleValidatePrompt vopts = do
  promptDir <- case vopts.validatePromptPath of
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
              { prPrompt = Nothing,
                prName = "<unknown>",
                prPath = promptDir,
                prDhallOk = False,
                prDhallError = Just (T.pack (show err)),
                prChecks = []
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
          DiagCheck "Allowed tools" DiagError (checkAgentPromptAllowedTools p)
        ]
  pure
    PromptReport
      { prPrompt = Just p,
        prName = p.name.unModuleName,
        prPath = baseDir,
        prDhallOk = True,
        prDhallError = Nothing,
        prChecks = checks
      }

promptReportHasErrors :: PromptReport -> Bool
promptReportHasErrors r =
  not r.prDhallOk
    || any (\c -> c.diagSeverity == DiagError && not (null c.diagDetails)) r.prChecks

renderPromptReport :: Bool -> PromptReport -> Text
renderPromptReport color report =
  T.unlines $
    [ "Validating prompt at " <> T.pack report.prPath <> "...",
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
      if report.prDhallOk
        then ["  " <> okMark <> " prompt.dhall evaluates successfully"]
        else
          ["  " <> errMark <> " prompt.dhall failed to evaluate"]
            ++ case report.prDhallError of
              Just errText -> ["      " <> detailStyle errText]
              Nothing -> []

    summaryLines = case report.prPrompt of
      Nothing -> []
      Just p ->
        [ "  " <> okMark <> " Prompt name: " <> nameStyle p.name.unModuleName,
          "  " <> okMark <> " " <> T.pack (show (length p.vars)) <> " variables declared",
          "  " <> okMark <> " " <> T.pack (show (length p.prompts)) <> " prompts defined",
          "  " <> okMark <> " " <> T.pack (show (length p.commandVars)) <> " command variables declared",
          "  " <> okMark <> " " <> T.pack (show (length p.guidance)) <> " guidance blocks declared",
          "  " <> okMark <> " " <> T.pack (show (length p.files)) <> " reference files declared"
        ]

    checkLines = concatMap renderCheck report.prChecks

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
        | c <- report.prChecks,
          c.diagSeverity == DiagError,
          not (null c.diagDetails)
        ]

    dhallFailed = not report.prDhallOk
    totalErrors = errorCount + (if dhallFailed then 1 else 0)

    resultLine
      | totalErrors > 0 =
          let msg = T.pack (show totalErrors) <> " error(s) found."
           in (if color then bold (red msg) else msg) <> " Prompt is invalid."
      | otherwise =
          let msg = "Prompt '" <> report.prName <> "' is valid."
           in if color then green msg else msg
