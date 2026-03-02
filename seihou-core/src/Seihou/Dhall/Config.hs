module Seihou.Dhall.Config
  ( evalConfigFile,
    evalConfigFileIfExists,
  )
where

import Control.Exception (SomeException, try)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Dhall (input, strictText)
import Dhall.Marshal.Decode (Decoder, field, list, record)
import System.Directory (doesFileExist)

-- | Evaluate a Dhall config file to a @Map Text Text@.
--
-- Config files are plain Dhall records of text values, e.g.:
--
-- >  { license = "MIT", `project.name` = "my-app" }
--
-- This function reads the file, wraps the content with @toMap@ to convert
-- the record to a list of key-value entries, then decodes via the Dhall
-- library.
evalConfigFile :: FilePath -> IO (Map Text Text)
evalConfigFile path = do
  content <- TIO.readFile path
  let trimmed = T.strip content
  -- An empty record {=} needs a type annotation for toMap.
  if trimmed == "{=}" || trimmed == "{ = }" || T.null trimmed
    then pure Map.empty
    else do
      let wrapped = "toMap (" <> content <> ")"
      input configMapDecoder wrapped

-- | Like 'evalConfigFile', but returns an empty map if the file does not exist.
-- Dhall parse/evaluation errors still propagate as 'Left'.
evalConfigFileIfExists :: FilePath -> IO (Either Text (Map Text Text))
evalConfigFileIfExists path = do
  exists <- doesFileExist path
  if exists
    then do
      result <- try (evalConfigFile path)
      case result of
        Left (e :: SomeException) ->
          pure (Left ("Error reading config " <> T.pack path <> ": " <> T.pack (show e)))
        Right m -> pure (Right m)
    else pure (Right Map.empty)

-- | Decoder for a list of @{ mapKey : Text, mapValue : Text }@ entries,
-- which is what @toMap { k = "v" }@ produces.
configMapDecoder :: Decoder (Map Text Text)
configMapDecoder = fmap Map.fromList (list entryDecoder)
  where
    entryDecoder :: Decoder (Text, Text)
    entryDecoder = record ((,) <$> field "mapKey" strictText <*> field "mapValue" strictText)
