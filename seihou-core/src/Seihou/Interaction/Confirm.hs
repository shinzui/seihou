module Seihou.Interaction.Confirm
  ( confirmDefaults,
  )
where

import Control.Monad (foldM)
import Data.Map.Strict qualified as Map
import Seihou.Composition.Instance (ModuleInstance (..))
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
--
-- Operates per 'ModuleInstance': two invocations of the same module
-- are confirmed independently, so the user can approve different
-- defaults for each.
confirmDefaults ::
  (Console :> es) =>
  [(ModuleInstance, Module, FilePath)] ->
  Map ModuleInstance (Map VarName ResolvedVar) ->
  Eff es (Map ModuleInstance (Map VarName ResolvedVar))
confirmDefaults modulesInOrder resolved = do
  interactive <- isInteractive
  if not interactive || not (anyNeedsConfirm resolved)
    then pure resolved
    else do
      putText ""
      putText "Confirm default values:"
      foldM processInstance resolved modulesInOrder

anyNeedsConfirm :: Map ModuleInstance (Map VarName ResolvedVar) -> Bool
anyNeedsConfirm = any (any isDefaultOrParent) . Map.elems

isDefaultOrParent :: ResolvedVar -> Bool
isDefaultOrParent rv = case rv.source of
  FromDefault -> True
  FromParent _ -> True
  _ -> False

processInstance ::
  (Console :> es) =>
  Map ModuleInstance (Map VarName ResolvedVar) ->
  (ModuleInstance, Module, FilePath) ->
  Eff es (Map ModuleInstance (Map VarName ResolvedVar))
processInstance acc (inst, m, _dir) = do
  let modResolved = Map.findWithDefault Map.empty inst acc
  newModResolved <- foldM (processVar m acc) modResolved m.vars
  pure (Map.insert inst newModResolved acc)

processVar ::
  (Console :> es) =>
  Module ->
  Map ModuleInstance (Map VarName ResolvedVar) ->
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
