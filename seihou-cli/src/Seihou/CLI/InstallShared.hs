module Seihou.CLI.InstallShared
  ( -- * Origin metadata
    OriginInfo (..),
    OriginMeta (..),
    readOriginInfo,

    -- * Install primitives
    installModuleDir,
    cloneRepo,
    copyDirectoryRecursive,
  )
where

import Control.Monad (when)
import Data.Aeson (FromJSON (..), ToJSON (..), object, withObject, (.:), (.:?), (.=))
import Data.Aeson qualified as Aeson
import Data.Aeson.Encode.Pretty (encodePretty)
import Data.ByteString.Lazy qualified as LBS
import Data.Text qualified as T
import Data.Time (getCurrentTime)
import Data.Time.Format.ISO8601 (iso8601Show)
import Seihou.CLI.Shared (logIO)
import Seihou.Core.Types (LogLevel (..))
import Seihou.Effect.Logger (logWarn)
import Seihou.Prelude
import System.Directory
  ( XdgDirectory (..),
    copyFile,
    createDirectoryIfMissing,
    doesDirectoryExist,
    doesFileExist,
    getXdgDirectory,
    listDirectory,
    removeDirectoryRecursive,
  )
import System.Exit (ExitCode (..))
import System.Process (readProcessWithExitCode)

-- ----------------------------------------------------------------------------
-- Origin metadata
-- ----------------------------------------------------------------------------

-- | Read side of @.seihou-origin.json@. Tolerates files written by older
-- 'seihou install' runs that may have been missing optional fields.
data OriginInfo = OriginInfo
  { sourceUrl :: Text,
    repoName :: Maybe Text,
    version :: Maybe Text
  }
  deriving stock (Eq, Show)

instance FromJSON OriginInfo where
  parseJSON = withObject "OriginInfo" $ \v ->
    OriginInfo <$> v .: "sourceUrl" <*> v .:? "repoName" <*> v .:? "version"

-- | Read and parse @.seihou-origin.json@ at the given installed-module
-- directory. Returns 'Nothing' if the file is absent or unparseable.
readOriginInfo :: FilePath -> IO (Maybe OriginInfo)
readOriginInfo installedDir = do
  let path = installedDir </> ".seihou-origin.json"
  exists <- doesFileExist path
  if not exists
    then pure Nothing
    else do
      bs <- LBS.readFile path
      pure (Aeson.decode bs)

-- | Write side of @.seihou-origin.json@. Captures everything 'seihou
-- install' / 'seihou upgrade' want to record at install time, including
-- the timestamp.
data OriginMeta = OriginMeta
  { sourceUrl :: Text,
    repoName :: Maybe Text,
    installedAt :: Text,
    version :: Maybe Text,
    tags :: [Text]
  }

instance ToJSON OriginMeta where
  toJSON m =
    object
      [ "sourceUrl" .= m.sourceUrl,
        "repoName" .= m.repoName,
        "installedAt" .= m.installedAt,
        "version" .= m.version,
        "tags" .= m.tags
      ]

-- ----------------------------------------------------------------------------
-- Install primitives
-- ----------------------------------------------------------------------------

-- | Copy a module directory to @~/.config/seihou/installed/<name>@,
-- replacing any existing installation, and write origin metadata. The
-- source directory must already contain the module's files; this
-- function does not clone or fetch.
installModuleDir :: FilePath -> String -> Text -> Maybe Text -> Maybe Text -> [Text] -> IO ()
installModuleDir moduleDir name source registryName moduleVersion moduleTags = do
  xdgConfig <- getXdgDirectory XdgConfig "seihou"
  let installDir = xdgConfig </> "installed" </> name

  exists <- doesDirectoryExist installDir
  when exists $ do
    logIO LogNormal (logWarn $ "overwriting existing installation of '" <> T.pack name <> "'")
    removeDirectoryRecursive installDir

  createDirectoryIfMissing True installDir
  copyDirectoryRecursive moduleDir installDir

  now <- getCurrentTime
  let origin = OriginMeta source registryName (T.pack (iso8601Show now)) moduleVersion moduleTags
  LBS.writeFile (installDir </> ".seihou-origin.json") (encodePretty origin)

-- | Recursively copy a directory tree, excluding the @.git@ directory.
copyDirectoryRecursive :: FilePath -> FilePath -> IO ()
copyDirectoryRecursive src dst = do
  entries <- listDirectory src
  mapM_ (copyEntry src dst) entries
  where
    copyEntry s d entry
      | entry == ".git" = pure ()
      | otherwise = do
          let srcPath = s </> entry
              dstPath = d </> entry
          isDir <- doesDirectoryExist srcPath
          if isDir
            then do
              createDirectoryIfMissing True dstPath
              copyDirectoryRecursive srcPath dstPath
            else copyFile srcPath dstPath

-- | Clone a git repo shallowly into the target directory. Returns 'Left'
-- with a human-readable message on failure (the caller decides how to
-- recover or report). On success returns 'Right ()' with no progress
-- chatter; the caller is expected to print whatever progress message
-- fits its UX.
cloneRepo :: Text -> FilePath -> IO (Either Text ())
cloneRepo source cloneDir = do
  (exitCode, _stdout, stderr) <-
    readProcessWithExitCode "git" ["clone", "--depth", "1", T.unpack source, cloneDir] ""
  case exitCode of
    ExitFailure _ ->
      pure
        ( Left $
            "git clone failed for '" <> source <> "': " <> T.pack stderr
        )
    ExitSuccess -> pure (Right ())
