-- | The one vocabulary the CLI uses to name a recorded application or an
-- applied module instance to a person.
--
-- An application id is a SHA-256 digest; nobody recognises it. What people
-- recognise is the target they ran and, for a repeated module, the parent
-- variables that told the instances apart, which @seihou status@ already
-- prints as @link-skill [skill.name=exec-plan]@. Status and update both render
-- through this module so the two can never drift apart.
--
-- Everything here is pure: it never resolves an artifact, inspects a path on
-- this machine, or renders a resolved variable value. Parent variables are
-- identity context the manifest records verbatim, not user secrets.
module Seihou.CLI.ApplicationDisplay
  ( applicationLabel,
    appliedModuleLabel,
    appliedTargetName,
    parentVarsText,
    moduleNameText,
  )
where

import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Seihou.CLI.Update.Types (ApplicationRef (..))
import Seihou.Core.Types
  ( ApplicationId (..),
    AppliedModule (..),
    AppliedTarget (..),
    ModuleName (..),
    ParentVars (..),
    RecipeName (..),
    VarName (..),
  )
import Seihou.Prelude

-- | How a recorded application is named: its target, the root instance's
-- parent variables, and any additional modules applied with it.
--
-- An application id is derived from exactly the target and the additional
-- modules, so two recorded applications never share a label. A file record
-- can still name an owner the manifest does not record as an application;
-- only then is a short prefix of the digest shown, because nothing else
-- identifies it.
--
-- For example, @exec-plan [skill.name=exec-plan]@ or
-- @nix-haskell-flake (with direnv)@.
applicationLabel :: ApplicationRef -> Text
applicationLabel ref = case ref ^. #target of
  Nothing -> "unrecorded application " <> T.take 12 (ref ^. #applicationId . #unApplicationId)
  Just target ->
    appliedTargetName target
      <> maybe "" (" " <>) (parentVarsText (ref ^. #parentVars))
      <> additional (ref ^. #additionalModules)
  where
    additional [] = ""
    additional modules = " (with " <> T.intercalate ", " (map moduleNameText modules) <> ")"

-- | How @seihou status@ names an applied module instance:
-- @name [key=value, ...]@.
appliedModuleLabel :: AppliedModule -> Text
appliedModuleLabel applied =
  moduleNameText (applied ^. #name)
    <> maybe "" (" " <>) (parentVarsText (applied ^. #parentVars))

-- | The name a user types to select a recorded target.
appliedTargetName :: AppliedTarget -> Text
appliedTargetName (AppliedModuleTarget name) = moduleNameText name
appliedTargetName (AppliedRecipeTarget name) = name ^. #unRecipeName

-- | Parent variables as sorted @[key=value, ...]@, or 'Nothing' when there
-- are none, so callers can style the bracket separately.
parentVarsText :: ParentVars -> Maybe Text
parentVarsText (ParentVars vars)
  | Map.null vars = Nothing
  | otherwise =
      Just
        ( "["
            <> T.intercalate ", " [name ^. #unVarName <> "=" <> value | (name, value) <- Map.toAscList vars]
            <> "]"
        )

moduleNameText :: ModuleName -> Text
moduleNameText name = name ^. #unModuleName
