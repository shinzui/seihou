module Seihou.CLI.Shared
  ( formatVarError,
    formatConfigError,
    formatBlueprintRefusal,
    deriveNamespace,
    toVarNameMap,
    logIO,
    unwrapConfig,
    shortenHome,
  )
where

import Data.List (isPrefixOf)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Seihou.Core.Types
import Seihou.Effect.Logger (Logger, logError)
import Seihou.Effect.LoggerInterp (runLoggerIO)
import Seihou.Prelude
import System.Directory (getHomeDirectory)
import System.Exit (exitFailure)

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

-- | The canonical message text emitted when @seihou run NAME@ resolves
-- to a blueprint. Returned as a single multi-line string so the run
-- handler can pass it to a single 'logError' call (the logger
-- prefixes each invocation with @[error] @, so emitting the body in
-- one call keeps the prefix off the continuation lines). Kept here in
-- @Seihou.CLI.Shared@ — rather than inlined in @Seihou.CLI.Run@ —
-- specifically so the message can be unit-tested without invoking the
-- full run handler.
formatBlueprintRefusal :: ModuleName -> Text
formatBlueprintRefusal name =
  T.intercalate
    "\n"
    [ "'" <> name.unModuleName <> "' is a blueprint, not a module or recipe.",
      "Blueprints must be run interactively via:",
      "  seihou agent run " <> name.unModuleName
    ]

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

-- | Run a one-shot Logger action in plain IO, using the given verbosity level.
logIO :: LogLevel -> Eff '[Logger, IOE] () -> IO ()
logIO level action = runEff $ runLoggerIO level action

-- | Abbreviate the user's home directory as @~\/@ for display.
shortenHome :: FilePath -> IO Text
shortenHome path = do
  home <- getHomeDirectory
  pure $
    if home `isPrefixOf` path
      then "~/" <> T.pack (drop (length home + 1) path)
      else T.pack path

-- | Unwrap an 'Either ConfigError' in an effectful context, logging an error
-- and exiting on 'Left'.
unwrapConfig :: (IOE :> es) => LogLevel -> Either ConfigError a -> Eff es a
unwrapConfig _ (Right a) = pure a
unwrapConfig level (Left err) = liftIO $ do
  logIO level (logError $ "Error reading config: " <> formatConfigError err)
  exitFailure
