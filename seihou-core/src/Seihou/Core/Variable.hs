module Seihou.Core.Variable
  ( resolveVariables,
    coerceValue,
    validateVarValue,
    formatExplain,
    envVarName,
  )
where

import Data.Char (toUpper)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Seihou.Core.Types

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

-- | Validate a resolved value against its declaration's validation constraint.
validateVarValue :: VarDecl -> VarValue -> Either VarError ()
validateVarValue decl val =
  case varValidation decl of
    Nothing -> Right ()
    Just v -> checkValidation (varName decl) v val

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
-- and three config file layers.
--
-- Precedence chain (highest to lowest):
-- 1. CLI overrides (@--var@ flags)
-- 2. Environment variables (@SEIHOU_VAR_@ prefix)
-- 3. Local project config (@.seihou\/config.dhall@)
-- 4. Namespace config (@~\/.config\/seihou\/namespaces\/\<ns\>\/config.dhall@)
-- 5. Global config (@~\/.config\/seihou\/config.dhall@)
-- 6. Module defaults
resolveVariables ::
  [VarDecl] ->
  Map VarName Text -> -- CLI overrides
  Map Text Text -> -- Environment variables
  Text -> -- Namespace name (used in provenance tagging)
  Map VarName Text -> -- Local config
  Map VarName Text -> -- Namespace config
  Map VarName Text -> -- Global config
  Either [VarError] (Map VarName ResolvedVar)
resolveVariables decls cliOverrides envVars namespace localConfig nsConfig globalConfig =
  case partitionResults (map resolveOne decls) of
    ([], resolved) -> Right (Map.fromList resolved)
    (errs, _) -> Left errs
  where
    resolveOne :: VarDecl -> Either VarError (VarName, ResolvedVar)
    resolveOne decl =
      let name = varName decl
          ty = varType decl
       in case lookupCLI name ty of
            Just result -> result >>= validateAndWrap decl
            Nothing -> case lookupEnv name ty of
              Just result -> result >>= validateAndWrap decl
              Nothing -> case lookupConfig name ty localConfig FromLocalConfig of
                Just result -> result >>= validateAndWrap decl
                Nothing -> case lookupConfig name ty nsConfig (FromNamespaceConfig namespace) of
                  Just result -> result >>= validateAndWrap decl
                  Nothing -> case lookupConfig name ty globalConfig FromGlobalConfig of
                    Just result -> result >>= validateAndWrap decl
                    Nothing -> case varDefault decl of
                      Just defVal ->
                        validateAndWrap decl (defVal, FromDefault)
                      Nothing
                        | varRequired decl -> Left (MissingRequiredVar name)
                        | otherwise -> Left (MissingRequiredVar name)

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
            ( varName decl,
              ResolvedVar
                { resolvedValue = val,
                  resolvedSource = source,
                  resolvedDecl = decl
                }
            )

-- | Partition a list of Either into errors and successes.
partitionResults :: [Either e a] -> ([e], [a])
partitionResults = foldr go ([], [])
  where
    go (Left e) (errs, oks) = (e : errs, oks)
    go (Right a) (errs, oks) = (errs, a : oks)

-- | Format a human-readable provenance report for @--explain@ output.
formatExplain :: Map VarName ResolvedVar -> Text
formatExplain resolved =
  T.unlines (map formatOne (Map.toAscList resolved))
  where
    formatOne :: (VarName, ResolvedVar) -> Text
    formatOne (VarName name, rv) =
      name <> " = " <> showValue (resolvedValue rv) <> "  (" <> showSource (resolvedSource rv) <> ")"

    showValue :: VarValue -> Text
    showValue (VText t) = "\"" <> t <> "\""
    showValue (VBool True) = "true"
    showValue (VBool False) = "false"
    showValue (VInt n) = T.pack (show n)
    showValue (VList vs) = "[" <> T.intercalate ", " (map showValue vs) <> "]"

    showSource :: VarSource -> Text
    showSource FromCLI = "from --set flag"
    showSource (FromEnv envKey) = "from env " <> envKey
    showSource FromLocalConfig = "from local config"
    showSource (FromNamespaceConfig ns) = "from namespace " <> ns <> " config"
    showSource FromGlobalConfig = "from global config"
    showSource FromDefault = "from module default"
    showSource FromPrompt = "from interactive prompt"
