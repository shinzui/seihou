module Seihou.CLI.Shared
  ( formatVarError,
    formatConfigError,
    deriveNamespace,
    toVarNameMap,
  )
where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Seihou.Core.Types

-- | Format a 'VarError' for display in CLI output.
formatVarError :: VarError -> Text
formatVarError (MissingRequiredVar (VarName n)) = "missing required variable: " <> n
formatVarError (TypeMismatch (VarName n) _ _) = "type mismatch for variable: " <> n
formatVarError (ValidationFailed (VarName n) msg) = "validation failed for " <> n <> ": " <> msg
formatVarError (CoercionFailed (VarName n) _ raw) = "cannot coerce '" <> raw <> "' for variable: " <> n

-- | Format a 'ConfigError' for display in CLI output.
formatConfigError :: ConfigError -> Text
formatConfigError (ConfigParseError path msg) = T.pack path <> ": " <> msg
formatConfigError (InvalidNamespace ns reason) = "invalid namespace '" <> ns <> "': " <> reason

-- | Derive the namespace from a module name by taking the prefix before the first hyphen.
-- For example, @ModuleName "haskell-base"@ yields @"haskell"@.
-- Modules without a hyphen yield an empty text (no namespace).
deriveNamespace :: ModuleName -> Text
deriveNamespace (ModuleName name) =
  let (prefix, _) = T.breakOn "-" name
   in if prefix == name then "" else prefix

-- | Convert a @Map Text Text@ (with text keys like @"project.name"@) to a @Map VarName Text@.
toVarNameMap :: Map.Map Text Text -> Map.Map VarName Text
toVarNameMap = Map.mapKeys VarName
