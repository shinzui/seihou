module Seihou.Engine.Validate
  ( DiagSeverity (..),
    DiagCheck (..),
    ValidateReport (..),
    buildReport,
    renderReportPlain,
    reportHasErrors,
  )
where

import Data.Maybe (isNothing, mapMaybe)
import Data.Set qualified as Set
import Data.Text qualified as T
import Seihou.Core.Module
  ( checkCommandSafety,
    checkDependencyNames,
    checkDestVarRefs,
    checkExportRefs,
    checkFileExistence,
    checkNameFormat,
    checkPromptRefs,
    checkSafeDestinations,
    checkUniqueVars,
    extractPlaceholders,
  )
import Seihou.Core.Types
import Seihou.Prelude

-- | Severity of a diagnostic check result.
data DiagSeverity
  = DiagError
  | DiagWarning
  deriving stock (Eq, Show)

-- | A single diagnostic check with its result.
data DiagCheck = DiagCheck
  { diagLabel :: Text,
    diagSeverity :: DiagSeverity,
    diagDetails :: [Text]
  }
  deriving stock (Eq, Show)

-- | A complete validation report for a module.
data ValidateReport = ValidateReport
  { reportModule :: Module,
    reportPath :: FilePath,
    reportDhallOk :: Bool,
    reportDhallError :: Maybe Text,
    reportChecks :: [DiagCheck]
  }
  deriving stock (Eq, Show)

-- | Build a structured validation report. When the first argument is True,
-- lint warnings are included after the core checks.
buildReport :: Bool -> FilePath -> Module -> IO ValidateReport
buildReport lint baseDir m = do
  fileErrors <- checkFileExistence baseDir m
  let coreChecks =
        [ DiagCheck "Module name format" DiagError (checkNameFormat m),
          DiagCheck "Unique variable names" DiagError (checkUniqueVars m),
          DiagCheck "Prompt references" DiagError (checkPromptRefs m),
          DiagCheck "Export references" DiagError (checkExportRefs m),
          DiagCheck "Source file existence" DiagError fileErrors,
          DiagCheck "Dependency names" DiagError (checkDependencyNames m),
          DiagCheck "Safe step destinations" DiagError (checkSafeDestinations m),
          DiagCheck "Destination variable references" DiagError (checkDestVarRefs m),
          DiagCheck "Command safety" DiagError (checkCommandSafety m)
        ]
      lintChecks =
        if lint
          then
            [ DiagCheck "Unused variables" DiagWarning (lintUnusedVars m),
              DiagCheck "Required variables without prompts" DiagWarning (lintRequiredWithoutPrompt m),
              DiagCheck "Duplicate step destinations" DiagWarning (lintDuplicateDestinations m),
              DiagCheck "Empty choice lists" DiagWarning (lintEmptyChoices m),
              DiagCheck "Missing variable descriptions" DiagWarning (lintMissingDescriptions m)
            ]
          else []
  pure
    ValidateReport
      { reportModule = m,
        reportPath = baseDir,
        reportDhallOk = True,
        reportDhallError = Nothing,
        reportChecks = coreChecks ++ lintChecks
      }

-- | Whether the report contains any errors (DiagError with non-empty details).
reportHasErrors :: ValidateReport -> Bool
reportHasErrors report =
  not report.reportDhallOk
    || any (\c -> c.diagSeverity == DiagError && not (null c.diagDetails)) report.reportChecks

-- | Render the report as plain text (no ANSI codes).
renderReportPlain :: ValidateReport -> Text
renderReportPlain report =
  T.unlines $
    [ "Validating module at " <> T.pack report.reportPath <> "...",
      ""
    ]
      ++ dhallLine
      ++ summaryLines
      ++ checkLines
      ++ [""]
      ++ [resultLine]
  where
    m = report.reportModule

    dhallLine =
      if report.reportDhallOk
        then ["  \x2713 module.dhall evaluates successfully"]
        else
          ["  \x2717 module.dhall failed to evaluate"]
            ++ case report.reportDhallError of
              Just errText -> ["      " <> errText]
              Nothing -> []

    summaryLines =
      if report.reportDhallOk
        then
          [ "  \x2713 Module name: " <> m.name.unModuleName,
            "  \x2713 " <> T.pack (show (length m.vars)) <> " variables declared",
            "  \x2713 " <> T.pack (show (length m.prompts)) <> " prompts defined",
            "  \x2713 " <> T.pack (show (length m.steps)) <> " steps defined"
          ]
        else []

    checkLines = concatMap renderCheck report.reportChecks

    renderCheck c
      | null c.diagDetails =
          ["  \x2713 " <> c.diagLabel]
      | c.diagSeverity == DiagWarning =
          ("  \x26A0 " <> c.diagLabel) : map (\d -> "      " <> d) c.diagDetails
      | otherwise =
          ("  \x2717 " <> c.diagLabel) : map (\d -> "      " <> d) c.diagDetails

    errorCount =
      length
        [ ()
        | c <- report.reportChecks,
          c.diagSeverity == DiagError,
          not (null c.diagDetails)
        ]

    dhallFailed = not report.reportDhallOk

    totalErrors = errorCount + (if dhallFailed then 1 else 0)

    resultLine
      | totalErrors > 0 =
          T.pack (show totalErrors) <> " error(s) found. Module is invalid."
      | otherwise =
          "Module '" <> m.name.unModuleName <> "' is valid."

-- Lint checks

-- | Variables declared but never referenced in step destinations, exports, or prompts.
lintUnusedVars :: Module -> [Text]
lintUnusedVars m =
  let destRefs =
        Set.fromList $
          concatMap (extractPlaceholders . (.dest)) m.steps
      exportRefs =
        Set.fromList $
          map (.var.unVarName) m.exports
      promptRefs =
        Set.fromList $
          map (.var.unVarName) m.prompts
      allRefs = Set.unions [destRefs, exportRefs, promptRefs]
   in mapMaybe
        ( \v ->
            let name' = v.name.unVarName
             in if Set.member name' allRefs
                  then Nothing
                  else Just ("variable '" <> name' <> "' is declared but never referenced")
        )
        m.vars

-- | Required variables that have no corresponding prompt.
lintRequiredWithoutPrompt :: Module -> [Text]
lintRequiredWithoutPrompt m =
  let promptedVars = Set.fromList $ map (.var.unVarName) m.prompts
   in mapMaybe
        ( \v ->
            let name' = v.name.unVarName
             in if v.required && not (Set.member name' promptedVars)
                  then Just ("required variable '" <> name' <> "' has no prompt")
                  else Nothing
        )
        m.vars

-- | Steps that write to the same destination (excluding patch ops).
lintDuplicateDestinations :: Module -> [Text]
lintDuplicateDestinations m =
  let nonPatchDests = [s.dest | s <- m.steps, isNothing s.patch]
      dupes = findDuplicates Set.empty Set.empty nonPatchDests
   in map (\d -> "multiple steps write to '" <> d <> "'") dupes

findDuplicates :: Set.Set Text -> Set.Set Text -> [Text] -> [Text]
findDuplicates _ _ [] = []
findDuplicates seen reported (x : xs)
  | Set.member x seen && not (Set.member x reported) =
      x : findDuplicates seen (Set.insert x reported) xs
  | otherwise = findDuplicates (Set.insert x seen) reported xs

-- | Choice variables with an empty option list.
lintEmptyChoices :: Module -> [Text]
lintEmptyChoices m =
  mapMaybe
    ( \v -> case v.type_ of
        VTChoice [] -> Just ("variable '" <> v.name.unVarName <> "' has an empty choice list")
        _ -> Nothing
    )
    m.vars

-- | Variables without a description.
lintMissingDescriptions :: Module -> [Text]
lintMissingDescriptions m =
  mapMaybe
    ( \v ->
        if isNothing v.description
          then Just ("variable '" <> v.name.unVarName <> "' has no description")
          else Nothing
    )
    m.vars
