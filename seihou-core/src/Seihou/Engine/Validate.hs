module Seihou.Engine.Validate
  ( DiagSeverity (..),
    DiagCheck (..),
    ValidateReport (..),
    buildReport,
    renderReportPlain,
    reportHasErrors,
  )
where

import Data.Map.Strict qualified as Map
import Data.Maybe (isNothing, mapMaybe)
import Data.Set qualified as Set
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.Core.Expr (exprRefs, parseExpr)
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
    checkVersionPresent,
    extractPlaceholders,
  )
import Seihou.Core.Types
import Seihou.Engine.Template (extractIfExprs)
import Seihou.Prelude
import System.Directory (doesFileExist)

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
  -- The conditional lint reads template file contents, so it runs in IO and
  -- only when --lint is requested.
  (undeclaredRefs, typeMismatches) <-
    if lint then lintConditionals baseDir m else pure ([], [])
  let coreChecks =
        [ DiagCheck "Module name format" DiagError (checkNameFormat m),
          DiagCheck "Module version declared" DiagError (checkVersionPresent m),
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
            [ -- Conditional findings are genuine correctness bugs (the class
              -- that silently dropped guarded output), so they gate exit
              -- status as DiagError, while remaining gated behind --lint.
              DiagCheck "Conditional variable references" DiagError undeclaredRefs,
              DiagCheck "Conditional comparison types" DiagError typeMismatches,
              DiagCheck "Unused variables" DiagWarning (lintUnusedVars m),
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

-- Conditional-expression lint (when clauses + template {{#if}} conditionals)

-- | A finding about a conditional expression, tagged by kind so 'buildReport'
-- can render undeclared-reference and type-mismatch findings under separate
-- check labels.
data CondFinding
  = CondUndeclared Text
  | CondTypeMismatch Text

-- | Lint every conditional expression in the module: step, command, and prompt
-- @when@ clauses (already parsed to 'Expr') plus @{{#if …}}@ conditionals in
-- text-bearing template files. Returns @(undeclaredReferences, typeMismatches)@.
--
-- Each referenced variable is checked against the module's declarations: a
-- reference to an undeclared variable, or an @Eq@ comparison whose literal type
-- cannot match the variable's declared type (e.g. a @bool@ variable compared
-- against the quoted string @"true"@), becomes a finding.
lintConditionals :: FilePath -> Module -> IO ([Text], [Text])
lintConditionals baseDir m = do
  templateExprs <- collectTemplateExprs baseDir m
  let declaredTypes = Map.fromList [(d.name, d.type_) | d <- m.vars]
      stepExprs =
        [("step '" <> s.dest <> "' when clause", c) | s <- m.steps, Just c <- [s.condition]]
      commandExprs =
        [("command when clause", c) | c0 <- m.commands, Just c <- [c0.condition]]
      promptExprs =
        [ ("prompt for '" <> p.var.unVarName <> "' when clause", c)
        | p <- m.prompts,
          Just c <- [p.condition]
        ]
      allExprs = stepExprs ++ commandExprs ++ promptExprs ++ templateExprs
      findings = concatMap (uncurry (lintExpr declaredTypes)) allExprs
  pure
    ( [t | CondUndeclared t <- findings],
      [t | CondTypeMismatch t <- findings]
    )

-- | Read text-bearing template files (@Template@ / @DhallText@ strategies) and
-- extract their @{{#if …}}@ conditionals, parsed to 'Expr'. Files that do not
-- exist are skipped (their absence is already reported by the core
-- source-file-existence check); expressions that fail to parse are skipped here
-- (they surface at render time, outside this lint's scope).
collectTemplateExprs :: FilePath -> Module -> IO [(Text, Expr)]
collectTemplateExprs baseDir m =
  concat <$> mapM readStep textBearingSteps
  where
    textBearingSteps = filter (isTextBearing . (.strategy)) m.steps

    isTextBearing Template = True
    isTextBearing DhallText = True
    isTextBearing _ = False

    readStep s = do
      let path = baseDir </> "files" </> s.src
      exists <- doesFileExist path
      if not exists
        then pure []
        else do
          contents <- TIO.readFile path
          let label = "template '" <> T.pack s.src <> "' {{#if}} condition"
          pure [(label, expr) | raw <- extractIfExprs contents, Right expr <- [parseExpr raw]]

-- | Lint a single expression from the given source against the declared types.
lintExpr :: Map.Map VarName VarType -> Text -> Expr -> [CondFinding]
lintExpr declaredTypes srcLabel expr =
  concatMap checkRef (exprRefs expr)
  where
    checkRef (name, mLit) =
      case Map.lookup name declaredTypes of
        Nothing ->
          [CondUndeclared (srcLabel <> " references undeclared variable: " <> name.unVarName)]
        Just ty -> case mLit of
          Just lit
            | not (literalMatchesType ty lit) ->
                [CondTypeMismatch (describeMismatch srcLabel name ty lit)]
          _ -> []

-- | Whether an @Eq@ literal's constructor can match a value of the declared
-- type. Bool→'VBool', int→'VInt', text→'VText', choice→'VText' (choice values
-- resolve to text), list→'VList'.
literalMatchesType :: VarType -> VarValue -> Bool
literalMatchesType VTBool (VBool _) = True
literalMatchesType VTInt (VInt _) = True
literalMatchesType VTText (VText _) = True
literalMatchesType (VTChoice _) (VText _) = True
literalMatchesType (VTList _) (VList _) = True
literalMatchesType _ _ = False

-- | Build a human-readable message for a type-inconsistent @Eq@ comparison,
-- with an actionable hint where one applies (the original bug: a @bool@
-- variable compared against the quoted string @"true"@ instead of the
-- bareword @true@).
describeMismatch :: Text -> VarName -> VarType -> VarValue -> Text
describeMismatch srcLabel name ty lit =
  srcLabel
    <> " compares variable '"
    <> name.unVarName
    <> "' (declared type "
    <> renderVarType ty
    <> ") against "
    <> describeLiteral lit
    <> "; the comparison can never match."
    <> mismatchHint ty lit

-- | A short hint steering the author to the correct literal form.
mismatchHint :: VarType -> VarValue -> Text
mismatchHint VTBool (VText t)
  | T.toLower (T.strip t) `elem` ["true", "false"] =
      " Use the bareword " <> T.toLower (T.strip t) <> " instead of the quoted \"" <> t <> "\"."
mismatchHint VTInt (VText t) = " Use the unquoted number " <> t <> " instead of the quoted \"" <> t <> "\"."
mismatchHint VTText (VBool b) =
  " Use the quoted string \"" <> (if b then "true" else "false") <> "\" instead of the bareword."
mismatchHint _ _ = ""

-- | Render an @Eq@ literal for a diagnostic message.
describeLiteral :: VarValue -> Text
describeLiteral (VText t) = "string literal \"" <> t <> "\""
describeLiteral (VBool b) = "bareword " <> (if b then "true" else "false")
describeLiteral (VInt n) = "integer literal " <> T.pack (show n)
describeLiteral (VList _) = "a list literal"

-- | A short rendering of a declared variable type for diagnostic messages.
renderVarType :: VarType -> Text
renderVarType VTText = "text"
renderVarType VTBool = "bool"
renderVarType VTInt = "int"
renderVarType (VTList ty) = "list " <> renderVarType ty
renderVarType (VTChoice _) = "choice"
