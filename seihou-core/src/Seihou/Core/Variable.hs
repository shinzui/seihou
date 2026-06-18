module Seihou.Core.Variable
  ( resolveVariables,
    coerceValue,
    coerceDefault,
    validateVarValue,
    formatExplain,
    formatDeclarations,
    envVarName,
    diagnoseResolution,
  )
where

import Data.Char (toUpper)
import Data.Map.Strict qualified as Map
import Data.Maybe (catMaybes)
import Data.Set qualified as Set
import Data.Text qualified as T
import Seihou.Core.Types
import Seihou.Prelude

-- | Derive the environment variable name for a given variable.
-- @VarName "project.name"@ becomes @"SEIHOU_VAR_PROJECT_NAME"@.
envVarName :: VarName -> Text
envVarName (VarName name) =
  "SEIHOU_VAR_" <> T.map (\c -> if c == '.' then '_' else toUpper c) name

-- | Attempt to coerce a text value to the declared variable type.
coerceValue :: VarName -> VarType -> Text -> Either VarError VarValue
coerceValue name VTText t = Right (VText t)
coerceValue name VTBool t =
  case T.toLower (T.strip t) of
    "true" -> Right (VBool True)
    "yes" -> Right (VBool True)
    "1" -> Right (VBool True)
    "false" -> Right (VBool False)
    "no" -> Right (VBool False)
    "0" -> Right (VBool False)
    _ -> Left (CoercionFailed name VTBool t)
coerceValue name VTInt t =
  case reads (T.unpack (T.strip t)) of
    [(n, "")] -> Right (VInt n)
    _ -> Left (CoercionFailed name VTInt t)
coerceValue name (VTList VTText) t =
  Right (VList (map (VText . T.strip) (T.splitOn "," t)))
coerceValue name (VTList elemTy) t =
  Left (CoercionFailed name (VTList elemTy) t)
coerceValue name (VTChoice options) t
  | T.strip t `elem` options = Right (VText (T.strip t))
  | otherwise = Left (CoercionFailed name (VTChoice options) t)

-- | Coerce a module *default* value to its declared type.
--
-- Defaults are decoded from Dhall as raw 'VText'; this routes them through the
-- same 'coerceValue' contract as every other resolution source so a defaulted
-- variable reaches evaluation with the correct runtime type (e.g. a @bool@
-- default of @"true"@ becomes 'VBool' 'True', not 'VText' @"true"@).
--
-- A value that is already typed (e.g. a default synthesized during
-- composition) passes through unchanged. An unconstrained choice
-- (@VTChoice []@ — the only form the Dhall decoder currently produces, since
-- options are not yet carried in the type string) keeps its text value, as
-- there are no options to validate membership against.
coerceDefault :: VarName -> VarType -> VarValue -> Either VarError VarValue
coerceDefault _ (VTChoice []) (VText raw) = Right (VText raw)
coerceDefault name ty (VText raw) = coerceValue name ty raw
coerceDefault _ _ v = Right v

-- | Validate a resolved value against its declaration's validation constraint.
validateVarValue :: VarDecl -> VarValue -> Either VarError ()
validateVarValue decl val =
  case decl.validation of
    Nothing -> Right ()
    Just v -> checkValidation decl.name v val

checkValidation :: VarName -> Validation -> VarValue -> Either VarError ()
checkValidation name (ValPattern pat) (VText t) =
  if simplePatternMatch pat t
    then Right ()
    else Left (ValidationFailed name ("value does not match pattern: " <> pat))
checkValidation name (ValPattern _) _ =
  Left (ValidationFailed name "pattern validation requires a text value")
checkValidation name (ValRange lo hi) (VInt n)
  | n >= lo && n <= hi = Right ()
  | otherwise =
      Left
        ( ValidationFailed
            name
            ( "value "
                <> T.pack (show n)
                <> " is not in range ["
                <> T.pack (show lo)
                <> ", "
                <> T.pack (show hi)
                <> "]"
            )
        )
checkValidation name (ValRange _ _) _ =
  Left (ValidationFailed name "range validation requires an integer value")
checkValidation name (ValMinLength n) (VText t)
  | T.length t >= n = Right ()
  | otherwise =
      Left
        ( ValidationFailed
            name
            ("value must be at least " <> T.pack (show n) <> " characters")
        )
checkValidation name (ValMinLength _) _ =
  Left (ValidationFailed name "min-length validation requires a text value")
checkValidation name (ValMaxLength n) (VText t)
  | T.length t <= n = Right ()
  | otherwise =
      Left
        ( ValidationFailed
            name
            ("value must be at most " <> T.pack (show n) <> " characters")
        )
checkValidation name (ValMaxLength _) _ =
  Left (ValidationFailed name "max-length validation requires a text value")

-- | Simple pattern matching for variable validation.
-- For M2, this checks whether the text matches the character class pattern
-- @[a-z][a-z0-9-]*@ style patterns. A full regex library can be added later.
simplePatternMatch :: Text -> Text -> Bool
simplePatternMatch pat t
  | pat == "[a-z][a-z0-9-]*" =
      case T.uncons t of
        Just (c, rest) ->
          isLowerAlpha c && T.all (\x -> isLowerAlpha x || isDigit x || x == '-') rest
        Nothing -> False
  | otherwise = True -- unknown patterns pass by default
  where
    isLowerAlpha c = c >= 'a' && c <= 'z'
    isDigit c = c >= '0' && c <= '9'

-- | Resolve all variables for a module given CLI overrides, environment variables,
-- four config file layers, and parent-supplied variable bindings.
--
-- Precedence chain (highest to lowest):
-- 1. CLI overrides (@--var@ flags)
-- 2. Environment variables (@SEIHOU_VAR_@ prefix)
-- 3. Local project config (@.seihou\/config.dhall@)
-- 4. Namespace config (@~\/.config\/seihou\/namespaces\/\<ns\>\/config.dhall@)
-- 5. Context config (@~\/.config\/seihou\/contexts\/\<ctx\>\/config.dhall@)
-- 6. Global config (@~\/.config\/seihou\/config.dhall@)
-- 7. Parent-supplied vars (from parameterized dependencies)
-- 8. Module defaults
resolveVariables ::
  [VarDecl] ->
  Map VarName Text -> -- CLI overrides
  Map Text Text -> -- Environment variables
  Text -> -- Namespace name (used in provenance tagging)
  Text -> -- Context name (used in provenance tagging)
  Map VarName Text -> -- Local config
  Map VarName Text -> -- Namespace config
  Map VarName Text -> -- Context config
  Map VarName Text -> -- Global config
  Map VarName (Text, ModuleName) -> -- Parent-supplied vars
  Either [VarError] (Map VarName ResolvedVar)
resolveVariables decls cliOverrides envVars namespace context localConfig nsConfig ctxConfig globalConfig parentVars =
  case partitionResults (map resolveOne decls) of
    ([], resolved) -> Right (Map.fromList (catMaybes resolved))
    (errs, _) -> Left errs
  where
    resolveOne :: VarDecl -> Either VarError (Maybe (VarName, ResolvedVar))
    resolveOne decl =
      let name = decl.name
          ty = decl.type_
       in case lookupCLI name ty of
            Just result -> fmap Just (result >>= validateAndWrap decl)
            Nothing -> case lookupEnv name ty of
              Just result -> fmap Just (result >>= validateAndWrap decl)
              Nothing -> case lookupConfig name ty localConfig FromLocalConfig of
                Just result -> fmap Just (result >>= validateAndWrap decl)
                Nothing -> case lookupConfig name ty nsConfig (FromNamespaceConfig namespace) of
                  Just result -> fmap Just (result >>= validateAndWrap decl)
                  Nothing -> case lookupConfig name ty ctxConfig (FromContextConfig context) of
                    Just result -> fmap Just (result >>= validateAndWrap decl)
                    Nothing -> case lookupConfig name ty globalConfig FromGlobalConfig of
                      Just result -> fmap Just (result >>= validateAndWrap decl)
                      Nothing -> case lookupParent name ty of
                        Just result -> fmap Just (result >>= validateAndWrap decl)
                        Nothing -> case decl.default_ of
                          Just defVal ->
                            case coerceDefault name ty defVal of
                              Left err -> Left err
                              Right val -> fmap Just (validateAndWrap decl (val, FromDefault))
                          Nothing
                            | decl.required -> Left (MissingRequiredVar name)
                            | otherwise -> Right Nothing

    lookupParent :: VarName -> VarType -> Maybe (Either VarError (VarValue, VarSource))
    lookupParent name ty =
      case Map.lookup name parentVars of
        Nothing -> Nothing
        Just (rawText, parentName) ->
          Just $ case coerceValue name ty rawText of
            Left err -> Left err
            Right val -> Right (val, FromParent parentName)

    lookupCLI :: VarName -> VarType -> Maybe (Either VarError (VarValue, VarSource))
    lookupCLI name ty =
      case Map.lookup name cliOverrides of
        Nothing -> Nothing
        Just rawText ->
          Just $ case coerceValue name ty rawText of
            Left err -> Left err
            Right val -> Right (val, FromCLI)

    lookupEnv :: VarName -> VarType -> Maybe (Either VarError (VarValue, VarSource))
    lookupEnv name ty =
      let envKey = envVarName name
       in case Map.lookup envKey envVars of
            Nothing -> Nothing
            Just rawText ->
              Just $ case coerceValue name ty rawText of
                Left err -> Left err
                Right val -> Right (val, FromEnv envKey)

    lookupConfig :: VarName -> VarType -> Map VarName Text -> VarSource -> Maybe (Either VarError (VarValue, VarSource))
    lookupConfig name ty configMap source =
      case Map.lookup name configMap of
        Nothing -> Nothing
        Just rawText ->
          Just $ case coerceValue name ty rawText of
            Left err -> Left err
            Right val -> Right (val, source)

    validateAndWrap :: VarDecl -> (VarValue, VarSource) -> Either VarError (VarName, ResolvedVar)
    validateAndWrap decl (val, source) =
      case validateVarValue decl val of
        Left err -> Left err
        Right () ->
          Right
            ( decl.name,
              ResolvedVar
                { value = val,
                  source = source,
                  decl = decl
                }
            )

-- | Partition a list of Either into errors and successes.
partitionResults :: [Either e a] -> ([e], [a])
partitionResults = foldr go ([], [])
  where
    go (Left e) (errs, oks) = (e : errs, oks)
    go (Right a) (errs, oks) = (errs, a : oks)

-- | Format a human-readable provenance report for @--explain@ output.
-- Uses bracket notation for sources and column-aligned output with 2-space indent.
formatExplain :: Map VarName ResolvedVar -> Text
formatExplain resolved =
  T.unlines (map formatOne entries)
  where
    entries = Map.toAscList resolved

    -- Calculate column widths for alignment
    maxNameLen = maximum (0 : map (\(VarName n, _) -> T.length n) entries)
    maxValueLen = maximum (0 : map (\(_, rv) -> T.length (showValue rv.value)) entries)

    formatOne :: (VarName, ResolvedVar) -> Text
    formatOne (VarName n, rv) =
      let valText = showValue rv.value
          namePad = T.replicate (maxNameLen - T.length n) " "
          valPad = T.replicate (maxValueLen - T.length valText) " "
       in "  " <> n <> namePad <> " = " <> valText <> valPad <> "  " <> showSource rv.source

    showValue :: VarValue -> Text
    showValue (VText t) = "\"" <> t <> "\""
    showValue (VBool True) = "true"
    showValue (VBool False) = "false"
    showValue (VInt n) = T.pack (show n)
    showValue (VList vs) = "[" <> T.intercalate ", " (map showValue vs) <> "]"

    showSource :: VarSource -> Text
    showSource FromCLI = "[--var]"
    showSource (FromEnv envKey) = "[env " <> envKey <> "]"
    showSource FromLocalConfig = "[local config]"
    showSource (FromNamespaceConfig ns) = "[namespace: " <> ns <> "]"
    showSource (FromContextConfig ctx) = "[context: " <> ctx <> "]"
    showSource FromGlobalConfig = "[global config]"
    showSource (FromParent mn) = "[parent: " <> mn.unModuleName <> "]"
    showSource FromDefault = "[default]"
    showSource FromPrompt = "[prompt]"

-- | Format variable declarations for default mode output.
-- Produces aligned output with @=@ signs and 2-space indent.
formatDeclarations :: [VarDecl] -> Text
formatDeclarations decls =
  T.unlines (map formatOne decls)
  where
    maxNameLen = maximum (0 : map (\d -> T.length d.name.unVarName) decls)

    formatOne :: VarDecl -> Text
    formatOne d =
      let VarName n = d.name
          namePad = T.replicate (maxNameLen - T.length n) " "
          valText = case d.default_ of
            Nothing
              | d.required -> "(required, no default)"
              | otherwise -> "(optional, no default)"
            Just v -> showDeclValue v
       in "  " <> n <> namePad <> " = " <> valText

    showDeclValue :: VarValue -> Text
    showDeclValue (VText t) = "\"" <> t <> "\""
    showDeclValue (VBool True) = "true"
    showDeclValue (VBool False) = "false"
    showDeclValue (VInt n) = T.pack (show n)
    showDeclValue (VList vs) = "[" <> T.intercalate ", " (map showDeclValue vs) <> "]"

-- | Diagnose mismatches between config values and variable declarations.
--
-- Returns two lists:
-- 1. Unused config keys: keys present in any config layer that don't match
--    any declared variable name across the composition.
-- 2. Unresolved optional variables: declared non-required variables that
--    have no resolved value.
diagnoseResolution ::
  Map VarName ResolvedVar ->
  [VarDecl] ->
  Map VarName Text ->
  Map VarName Text ->
  Map VarName Text ->
  Map VarName Text ->
  ([VarName], [VarName])
diagnoseResolution resolved decls localConfig nsConfig ctxConfig globalConfig =
  (unusedConfigKeys, unresolvedOptional)
  where
    declaredNames = Set.fromList (map (.name) decls)
    allConfigKeys =
      Set.fromList $
        Map.keys localConfig ++ Map.keys nsConfig ++ Map.keys ctxConfig ++ Map.keys globalConfig
    unusedConfigKeys =
      Set.toAscList (allConfigKeys `Set.difference` declaredNames)
    unresolvedOptional =
      [ d.name
      | d <- decls,
        not d.required,
        not (Map.member d.name resolved)
      ]
