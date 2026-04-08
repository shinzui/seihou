module Seihou.CLI.InstallHistory
  ( HistoryEntry (..),
    InstallHistory (..),
    readHistory,
    readHistoryFrom,
    writeHistory,
    writeHistoryTo,
    recordUrl,
    recordUrlTo,
    maxHistoryEntries,
  )
where

import Data.Aeson (FromJSON (..), ToJSON (..), eitherDecodeStrict', object, withObject, (.:), (.=))
import Data.Aeson.Encode.Pretty (encodePretty)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Text qualified as T
import Data.Time (getCurrentTime)
import Data.Time.Format.ISO8601 (iso8601Show)
import Seihou.Prelude
import System.Directory
  ( XdgDirectory (..),
    createDirectoryIfMissing,
    doesFileExist,
    getXdgDirectory,
  )
import System.FilePath (takeDirectory)

-- | A single entry in the install URL history.
data HistoryEntry = HistoryEntry
  { url :: Text,
    lastUsed :: Text
  }
  deriving stock (Eq, Show)

instance ToJSON HistoryEntry where
  toJSON e = object ["url" .= e.url, "lastUsed" .= e.lastUsed]

instance FromJSON HistoryEntry where
  parseJSON = withObject "HistoryEntry" $ \o ->
    HistoryEntry <$> o .: "url" <*> o .: "lastUsed"

-- | The full install history.
newtype InstallHistory = InstallHistory
  { entries :: [HistoryEntry]
  }
  deriving stock (Eq, Show)

instance ToJSON InstallHistory where
  toJSON h = object ["entries" .= h.entries]

instance FromJSON InstallHistory where
  parseJSON = withObject "InstallHistory" $ \o ->
    InstallHistory <$> o .: "entries"

-- | Maximum number of history entries to retain.
maxHistoryEntries :: Int
maxHistoryEntries = 50

-- | Path to the history file: ~/.config/seihou/install-history.json
historyFilePath :: IO FilePath
historyFilePath = do
  base <- getXdgDirectory XdgConfig "seihou"
  pure (base </> "install-history.json")

-- | Read history from the XDG config path. Returns empty on missing/malformed file.
readHistory :: IO InstallHistory
readHistory = historyFilePath >>= readHistoryFrom

-- | Read history from a specific file path (for testing).
readHistoryFrom :: FilePath -> IO InstallHistory
readHistoryFrom path = do
  exists <- doesFileExist path
  if not exists
    then pure (InstallHistory [])
    else do
      bs <- BS.readFile path
      case eitherDecodeStrict' bs of
        Left _ -> pure (InstallHistory [])
        Right h -> pure h

-- | Write history to the XDG config path.
writeHistory :: InstallHistory -> IO ()
writeHistory history = historyFilePath >>= \path -> writeHistoryTo path history

-- | Write history to a specific file path (for testing).
writeHistoryTo :: FilePath -> InstallHistory -> IO ()
writeHistoryTo path history = do
  createDirectoryIfMissing True (takeDirectory path)
  LBS.writeFile path (encodePretty history)

-- | Record a URL after successful install. Deduplicates, sorts recent-first, caps at 50.
recordUrl :: Text -> IO ()
recordUrl url = historyFilePath >>= \path -> recordUrlTo path url

-- | Record a URL to a specific history file (for testing).
recordUrlTo :: FilePath -> Text -> IO ()
recordUrlTo path url = do
  now <- getCurrentTime
  history <- readHistoryFrom path
  let timestamp = T.pack (iso8601Show now)
      newEntry = HistoryEntry {url = url, lastUsed = timestamp}
      filtered = filter (\e -> e.url /= url) history.entries
      updated = take maxHistoryEntries (newEntry : filtered)
  writeHistoryTo path (InstallHistory updated)
