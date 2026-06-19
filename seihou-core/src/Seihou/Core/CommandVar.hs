module Seihou.Core.CommandVar
  ( resolveCommandVars,
    planCommandVars,
    commandVarDecl,
  )
where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Seihou.Core.Expr (evalExpr)
import Seihou.Core.Path (validateProjectRelativePath)
import Seihou.Core.Types
import Seihou.Core.Variable (coerceValue, validateVarValue)
import Seihou.Effect.Process (Process, runProcess)
import Seihou.Prelude
import System.Exit (ExitCode (..))

-- | Select command variables that should run. Already-resolved variables keep
-- their existing value; command variables only fill gaps.
planCommandVars :: [CommandVar] -> Map VarName ResolvedVar -> Map VarName VarValue -> [CommandVar]
planCommandVars commandVars existing bindings =
  filter shouldRun commandVars
  where
    conditionBindings = resolvedValues existing <> bindings

    shouldRun cv =
      not (Map.member cv.name existing)
        && maybe True (evalExpr conditionBindings) cv.condition

-- | Return the matching declaration for a command variable, or synthesize a
-- text declaration for prompt-only dynamic context such as @git.branch@.
commandVarDecl :: [VarDecl] -> CommandVar -> VarDecl
commandVarDecl decls cv =
  case filter (\decl -> decl.name == cv.name) decls of
    decl : _ -> decl
    [] ->
      VarDecl
        { name = cv.name,
          type_ = VTText,
          default_ = Nothing,
          description = Nothing,
          required = False,
          validation = Nothing
        }

-- | Resolve command-derived variables through the process effect.
--
-- Existing resolved values have higher precedence and are never overwritten.
-- Command results are accumulated in order so later @when@ expressions can
-- depend on earlier command-derived values.
resolveCommandVars ::
  (Process :> es) =>
  [VarDecl] ->
  [CommandVar] ->
  Map VarName ResolvedVar ->
  Eff es (Either [VarError] (Map VarName ResolvedVar))
resolveCommandVars decls commandVars existing = do
  (errs, resolved) <- go [] existing (resolvedValues existing) commandVars
  pure $
    if null errs
      then Right resolved
      else Left errs
  where
    go errs resolved _bindings [] = pure (reverse errs, resolved)
    go errs resolved bindings (cv : rest)
      | Map.member cv.name resolved = go errs resolved bindings rest
      | maybe False (not . evalExpr bindings) cv.condition = go errs resolved bindings rest
      | otherwise = do
          result <- resolveOne bindings cv
          case result of
            Left err -> go (err : errs) resolved bindings rest
            Right rv ->
              let resolved' = Map.insert cv.name rv resolved
                  bindings' = Map.insert cv.name rv.value bindings
               in go errs resolved' bindings' rest

    resolveOne _bindings cv = do
      let decl = commandVarDecl decls cv
      case validateWorkDir cv of
        Left err -> pure (Left err)
        Right workDir -> do
          (exitCode, stdoutText, stderrText) <- runProcess "sh" ["-c", cv.run] workDir
          pure $ case exitCode of
            ExitSuccess -> coerceCommandOutput decl cv stdoutText
            ExitFailure code ->
              Left $
                ValidationFailed
                  cv.name
                  ( "command failed with exit code "
                      <> T.pack (show code)
                      <> ": "
                      <> summarizeDiagnostic stderrText
                  )

    validateWorkDir :: CommandVar -> Either VarError (Maybe FilePath)
    validateWorkDir cv@CommandVar {workDir = Nothing} = Right Nothing
    validateWorkDir cv@CommandVar {workDir = Just wd} =
      case validateProjectRelativePath wd of
        Left err -> Left (ValidationFailed cv.name ("command variable workDir " <> err))
        Right _ -> Right (Just (T.unpack wd))

coerceCommandOutput :: VarDecl -> CommandVar -> Text -> Either VarError ResolvedVar
coerceCommandOutput decl cv stdoutText = do
  let output =
        if cv.trim
          then T.strip stdoutText
          else stdoutText
  case cv.maxBytes of
    Just n
      | fromIntegral (T.length output) > n ->
          Left (ValidationFailed cv.name ("command output exceeds maxBytes " <> T.pack (show n)))
    _ -> do
      value <- coerceValue decl.name decl.type_ output
      validateVarValue decl value
      Right
        ResolvedVar
          { value = value,
            source = FromCommand cv.run,
            decl = decl
          }

resolvedValues :: Map VarName ResolvedVar -> Map VarName VarValue
resolvedValues = Map.map (.value)

summarizeDiagnostic :: Text -> Text
summarizeDiagnostic t =
  let stripped = T.strip t
   in if T.null stripped
        then "no stderr"
        else T.take 200 stripped
