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
  not (reportDhallOk report)
    || any (\c -> diagSeverity c == DiagError && not (null (diagDetails c))) (reportChecks report)

-- | Render the report as plain text (no ANSI codes).
renderReportPlain :: ValidateReport -> Text
renderReportPlain report =
  T.unlines $
    [ "Validating module at " <> T.pack (reportPath report) <> "...",
      ""
    ]
      ++ dhallLine
      ++ summaryLines
      ++ checkLines
      ++ [""]
      ++ [resultLine]
  where
    m = reportModule report

    dhallLine =
      if reportDhallOk report
        then ["  \x2713 module.dhall evaluates successfully"]
        else
          ["  \x2717 module.dhall failed to evaluate"]
            ++ case reportDhallError report of
              Just errText -> ["      " <> errText]
              Nothing -> []

    summaryLines =
      if reportDhallOk report
        then
          [ "  \x2713 Module name: " <> unModuleName (moduleName m),
            "  \x2713 " <> T.pack (show (length (moduleVars m))) <> " variables declared",
            "  \x2713 " <> T.pack (show (length (modulePrompts m))) <> " prompts defined",
            "  \x2713 " <> T.pack (show (length (moduleSteps m))) <> " steps defined"
          ]
        else []

    checkLines = concatMap renderCheck (reportChecks report)

    renderCheck c
      | null (diagDetails c) =
          ["  \x2713 " <> diagLabel c]
      | diagSeverity c == DiagWarning =
          ("  \x26A0 " <> diagLabel c) : map (\d -> "      " <> d) (diagDetails c)
      | otherwise =
          ("  \x2717 " <> diagLabel c) : map (\d -> "      " <> d) (diagDetails c)

    errorCount =
      length
        [ ()
        | c <- reportChecks report,
          diagSeverity c == DiagError,
          not (null (diagDetails c))
        ]

    dhallFailed = not (reportDhallOk report)

    totalErrors = errorCount + (if dhallFailed then 1 else 0)

    resultLine
      | totalErrors > 0 =
          T.pack (show totalErrors) <> " error(s) found. Module is invalid."
      | otherwise =
          "Module '" <> unModuleName (moduleName m) <> "' is valid."

-- Lint checks

-- | Variables declared but never referenced in step destinations, exports, or prompts.
lintUnusedVars :: Module -> [Text]
lintUnusedVars m =
  let destRefs =
        Set.fromList $
          concatMap (extractPlaceholders . stepDest) (moduleSteps m)
      exportRefs =
        Set.fromList $
          map (unVarName . exportVar) (moduleExports m)
      promptRefs =
        Set.fromList $
          map (unVarName . promptVar) (modulePrompts m)
      allRefs = Set.unions [destRefs, exportRefs, promptRefs]
   in mapMaybe
        ( \v ->
            let name = unVarName (varName v)
             in if Set.member name allRefs
                  then Nothing
                  else Just ("variable '" <> name <> "' is declared but never referenced")
        )
        (moduleVars m)

-- | Required variables that have no corresponding prompt.
lintRequiredWithoutPrompt :: Module -> [Text]
lintRequiredWithoutPrompt m =
  let promptedVars = Set.fromList $ map (unVarName . promptVar) (modulePrompts m)
   in mapMaybe
        ( \v ->
            let name = unVarName (varName v)
             in if varRequired v && not (Set.member name promptedVars)
                  then Just ("required variable '" <> name <> "' has no prompt")
                  else Nothing
        )
        (moduleVars m)

-- | Steps that write to the same destination (excluding patch ops).
lintDuplicateDestinations :: Module -> [Text]
lintDuplicateDestinations m =
  let nonPatchDests = [stepDest s | s <- moduleSteps m, isNothing (stepPatch s)]
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
    ( \v -> case varType v of
        VTChoice [] -> Just ("variable '" <> unVarName (varName v) <> "' has an empty choice list")
        _ -> Nothing
    )
    (moduleVars m)

-- | Variables without a description.
lintMissingDescriptions :: Module -> [Text]
lintMissingDescriptions m =
  mapMaybe
    ( \v ->
        if isNothing (varDescription v)
          then Just ("variable '" <> unVarName (varName v) <> "' has no description")
          else Nothing
    )
    (moduleVars m)
