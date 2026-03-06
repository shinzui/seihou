module Seihou.Interaction.Prompt
  ( runPrompts,
    promptForVar,
  )
where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Seihou.Core.Expr (evalExpr)
import Seihou.Core.Types
import Seihou.Core.Variable (coerceValue, validateVarValue)
import Seihou.Effect.Console (Console, getLine, putText)
import Seihou.Prelude
import Prelude hiding (getLine)

-- | Run prompts for unresolved variables.
--
-- For each prompt whose variable is in the unresolved set:
-- 1. Evaluate the prompt's @condition@ against current bindings.
-- 2. If the condition is false, skip.
-- 3. Display the prompt text and read input (or show choice menu).
-- 4. Coerce and validate the input.
-- 5. On failure, retry up to 3 times.
--
-- Returns a map of newly resolved variables with 'FromPrompt' source.
runPrompts ::
  (Console :> es) =>
  [Prompt] ->
  [VarDecl] ->
  Map VarName VarValue ->
  Eff es (Map VarName ResolvedVar)
runPrompts prompts unresolvedDecls currentBindings =
  go prompts Map.empty
  where
    declMap = Map.fromList [(d.name, d) | d <- unresolvedDecls]

    go :: (Console :> es) => [Prompt] -> Map VarName ResolvedVar -> Eff es (Map VarName ResolvedVar)
    go [] acc = pure acc
    go (p : ps) acc = do
      let vn = p.var
      -- Skip if variable is not in the unresolved set
      case Map.lookup vn declMap of
        Nothing -> go ps acc
        Just decl -> do
          -- Skip if already resolved by an earlier prompt
          if Map.member vn acc
            then go ps acc
            else do
              -- Evaluate when condition
              let allBindings = Map.union (Map.map (.value) acc) currentBindings
              if shouldPrompt p allBindings
                then do
                  result <- promptForVar p decl allBindings
                  case result of
                    Left _err -> go ps acc
                    Right rv -> go ps (Map.insert vn rv acc)
                else go ps acc

-- | Check if a prompt should be displayed based on its @when@ condition.
shouldPrompt :: Prompt -> Map VarName VarValue -> Bool
shouldPrompt p bindings =
  case p.condition of
    Nothing -> True
    Just expr -> evalExpr bindings expr

-- | Prompt for a single variable value.
-- Displays the prompt text, reads input, coerces to the declared type,
-- and validates. Retries up to 3 times on failure.
promptForVar ::
  (Console :> es) =>
  Prompt ->
  VarDecl ->
  Map VarName VarValue ->
  Eff es (Either VarError ResolvedVar)
promptForVar prompt decl _bindings =
  case prompt.choices of
    Just choices -> promptWithChoices prompt decl choices
    Nothing -> promptFreeText prompt decl 3

-- | Prompt with free text input. Retries up to @maxRetries@ times.
promptFreeText ::
  (Console :> es) =>
  Prompt ->
  VarDecl ->
  Int ->
  Eff es (Either VarError ResolvedVar)
promptFreeText prompt decl retriesLeft = do
  putText prompt.text
  raw <- getLine
  if T.null (T.strip raw)
    then
      if retriesLeft > 1
        then do
          putText "Value cannot be empty. Please try again."
          promptFreeText prompt decl (retriesLeft - 1)
        else pure (Left (MissingRequiredVar decl.name))
    else case coerceAndValidate decl raw of
      Left err ->
        if retriesLeft > 1
          then do
            putText ("Invalid input: " <> formatCoercionError err <> ". Please try again.")
            promptFreeText prompt decl (retriesLeft - 1)
          else pure (Left err)
      Right rv -> pure (Right rv)

-- | Prompt with a numbered choice menu.
promptWithChoices ::
  (Console :> es) =>
  Prompt ->
  VarDecl ->
  [Text] ->
  Eff es (Either VarError ResolvedVar)
promptWithChoices prompt decl choices = do
  putText prompt.text
  mapM_ (\(i, c) -> putText ("  " <> T.pack (show i) <> ") " <> c)) (zip [1 :: Int ..] choices)
  putText "Enter selection number:"
  raw <- getLine
  case reads (T.unpack (T.strip raw)) of
    [(n, "")]
      | n >= 1 && n <= length choices ->
          let chosen = choices !! (n - 1)
           in case coerceAndValidate decl chosen of
                Left err -> pure (Left err)
                Right rv -> pure (Right rv)
    _ -> do
      putText ("Please enter a number between 1 and " <> T.pack (show (length choices)) <> ".")
      -- Retry once
      raw2 <- getLine
      case reads (T.unpack (T.strip raw2)) of
        [(n, "")]
          | n >= 1 && n <= length choices ->
              let chosen = choices !! (n - 1)
               in case coerceAndValidate decl chosen of
                    Left err -> pure (Left err)
                    Right rv -> pure (Right rv)
        _ -> pure (Left (MissingRequiredVar decl.name))

-- | Coerce raw text to the variable's type and validate.
coerceAndValidate :: VarDecl -> Text -> Either VarError ResolvedVar
coerceAndValidate decl raw = do
  val <- coerceValue decl.name decl.type_ raw
  validateVarValue decl val
  pure
    ResolvedVar
      { value = val,
        source = FromPrompt,
        decl = decl
      }

-- | Format a VarError for display during retry prompts.
formatCoercionError :: VarError -> Text
formatCoercionError (CoercionFailed _ ty raw) =
  "cannot convert '" <> raw <> "' to " <> showType ty
formatCoercionError (ValidationFailed _ msg) = msg
formatCoercionError (MissingRequiredVar (VarName n)) = "missing value for " <> n
formatCoercionError (TypeMismatch (VarName n) _ _) = "type mismatch for " <> n

showType :: VarType -> Text
showType VTText = "text"
showType VTBool = "bool"
showType VTInt = "int"
showType (VTList _) = "list"
showType (VTChoice _) = "choice"
