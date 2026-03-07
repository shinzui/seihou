module Seihou.Core.Context
  ( resolveContext,
    validateContextName,
  )
where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.Prelude
import System.Directory (XdgDirectory (..), doesFileExist, getCurrentDirectory, getXdgDirectory)

-- | Resolve the active context name from multiple sources in precedence order:
--
-- 1. CLI flag (@--context@)
-- 2. @SEIHOU_CONTEXT@ environment variable
-- 3. Project file @.seihou\/context@ (plain text, single line)
-- 4. Global default @~\/.config\/seihou\/default-context@ (plain text, single line)
--
-- Returns 'Nothing' if no context is active.
resolveContext ::
  Maybe Text ->
  Map Text Text ->
  IO (Maybe Text)
resolveContext cliFlag envVars =
  case cliFlag of
    Just ctx
      | not (T.null (T.strip ctx)) -> pure (Just (T.strip ctx))
    _ ->
      case Map.lookup "SEIHOU_CONTEXT" envVars of
        Just ctx
          | not (T.null (T.strip ctx)) -> pure (Just (T.strip ctx))
        _ -> do
          projectCtx <- readProjectContext
          case projectCtx of
            Just ctx -> pure (Just ctx)
            Nothing -> readGlobalDefaultContext

-- | Validate a context name. Returns 'Nothing' if valid, 'Just errorMsg' if invalid.
validateContextName :: Text -> Maybe Text
validateContextName ctx
  | T.null ctx = Just "context name cannot be empty"
  | ".." `T.isInfixOf` ctx = Just "context name must not contain '..'"
  | "/" `T.isInfixOf` ctx = Just "context name must not contain '/'"
  | otherwise = Nothing

-- Internal helpers

readProjectContext :: IO (Maybe Text)
readProjectContext = do
  cwd <- getCurrentDirectory
  let path = cwd </> ".seihou" </> "context"
  exists <- doesFileExist path
  if exists
    then do
      content <- T.strip <$> TIO.readFile path
      pure $
        if T.null content
          then Nothing
          else Just content
    else pure Nothing

readGlobalDefaultContext :: IO (Maybe Text)
readGlobalDefaultContext = do
  base <- getXdgDirectory XdgConfig "seihou"
  let path = base </> "default-context"
  exists <- doesFileExist path
  if exists
    then do
      content <- T.strip <$> TIO.readFile path
      pure $
        if T.null content
          then Nothing
          else Just content
    else pure Nothing
