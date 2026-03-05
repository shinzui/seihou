module Seihou.CLI.Shared
  ( formatVarError,
    formatConfigError,
    deriveNamespace,
    toVarNameMap,
    logIO,
    unwrapConfig,
    shortenHome,
  )
where

import Data.List (isPrefixOf)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Effectful
import Seihou.Core.Types
import Seihou.Effect.Logger (Logger, logError)
import Seihou.Effect.LoggerInterp (runLoggerIO)
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
