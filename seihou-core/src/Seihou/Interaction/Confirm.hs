module Seihou.Interaction.Confirm
  ( confirmDefaults,
  )
where

import Control.Monad (foldM)
import Data.Map.Strict qualified as Map
import Seihou.Core.Types
import Seihou.Effect.Console (Console, isInteractive, putText)
import Seihou.Interaction.Prompt (promptForVar)
import Seihou.Prelude

-- | Walk the resolved variable map and prompt the user to confirm or
-- override each variable whose source is 'FromDefault' or 'FromParent'.
--
-- Variables whose new value matches the original are left unchanged
-- (preserving their original source). Variables whose new value differs
-- are recorded with 'FromPrompt' as their source, so the downstream
-- save-prompted flow picks them up.
--
-- A no-op in non-interactive mode, and a no-op when no variable is
-- resolved from a default.
confirmDefaults ::
  (Console :> es) =>
  [(Module, FilePath)] ->
  Map ModuleName (Map VarName ResolvedVar) ->
  Eff es (Map ModuleName (Map VarName ResolvedVar))
confirmDefaults modulesInOrder resolved = do
  interactive <- isInteractive
  if not interactive || not (anyNeedsConfirm resolved)
    then pure resolved
    else do
      putText ""
      putText "Confirm default values:"
      foldM processModule resolved modulesInOrder

-- | Whether any variable in any module is resolved from 'FromDefault'
-- or 'FromParent'.
anyNeedsConfirm :: Map ModuleName (Map VarName ResolvedVar) -> Bool
anyNeedsConfirm = any (any isDefaultOrParent) . Map.elems

isDefaultOrParent :: ResolvedVar -> Bool
isDefaultOrParent rv = case rv.source of
  FromDefault -> True
  FromParent _ -> True
  _ -> False

processModule ::
  (Console :> es) =>
  Map ModuleName (Map VarName ResolvedVar) ->
  (Module, FilePath) ->
  Eff es (Map ModuleName (Map VarName ResolvedVar))
processModule acc (m, _dir) = do
  let modResolved = Map.findWithDefault Map.empty m.name acc
  newModResolved <- foldM (processVar m acc) modResolved m.vars
  pure (Map.insert m.name newModResolved acc)

processVar ::
  (Console :> es) =>
  Module ->
  Map ModuleName (Map VarName ResolvedVar) ->
  Map VarName ResolvedVar ->
  VarDecl ->
  Eff es (Map VarName ResolvedVar)
processVar m allResolved modResolved decl =
  case Map.lookup decl.name modResolved of
    Just rv | isDefaultOrParent rv -> do
      let prompt = findOrSynthesize m decl
          currentBindings =
            Map.map (.value) (Map.unions (Map.elems allResolved))
      result <- promptForVar prompt decl currentBindings
      case result of
        Left _err -> pure modResolved
        Right newRv
          | newRv.value == rv.value -> pure modResolved
          | otherwise -> pure (Map.insert decl.name newRv modResolved)
    _ -> pure modResolved

-- | Find the authored 'Prompt' for a variable, or build a minimal one
-- from the declaration.
findOrSynthesize :: Module -> VarDecl -> Prompt
findOrSynthesize m decl =
  case filter (\p -> p.var == decl.name) m.prompts of
    (p : _) -> p
    [] ->
      Prompt
        { var = decl.name,
          text = decl.name.unVarName,
          condition = Nothing,
          choices = Nothing
        }
