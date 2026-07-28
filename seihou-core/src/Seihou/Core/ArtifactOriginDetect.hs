-- | Turn an absolute artifact directory into a portable 'ArtifactOrigin'.
--
-- Module discovery hands every caller an absolute directory, because
-- @Seihou.Core.Module.defaultSearchPaths@ is built from
-- 'System.Directory.getCurrentDirectory' and
-- 'System.Directory.getXdgDirectory'. Absolute paths must never reach
-- @.seihou\/manifest.json@, which is checked into version control and read
-- on other developers' machines, so every manifest write site funnels its
-- directory through 'detectArtifactOrigin' first.
--
-- The read side of @.seihou-origin.json@ lives here rather than in
-- @seihou-cli@ because this module needs it and @seihou-core@ cannot depend
-- on @seihou-cli-internal@. @Seihou.CLI.InstallShared@ re-exports it, so
-- existing importers are unaffected; the write side ('OriginMeta',
-- @installModuleDir@) stays in the CLI.
module Seihou.Core.ArtifactOriginDetect
  ( detectArtifactOrigin,
    OriginInfo (..),
    readOriginInfo,
  )
where

import Control.Exception (IOException, try)
import Data.Aeson (FromJSON (..), withObject, (.:), (.:?))
import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy qualified as LBS
import Data.Generics.Labels ()
import Data.Text qualified as T
import Seihou.Core.Types (ArtifactOrigin (..))
import Seihou.Prelude
import System.Directory (canonicalizePath, doesFileExist)
import System.FilePath (makeRelative, pathSeparator, takeFileName)

-- | Read side of @.seihou-origin.json@. Tolerates files written by older
-- 'seihou install' runs that may have been missing optional fields.
data OriginInfo = OriginInfo
  { sourceUrl :: !Text,
    repoName :: !(Maybe Text),
    version :: !(Maybe Text)
  }
  deriving stock (Eq, Generic, Show)

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

-- | Classify an absolute artifact directory into a portable origin.
--
-- @projectRoot@ is the absolute path of the project being generated into
-- (the directory holding @.seihou@). @artifactDir@ is the absolute
-- directory that holds the artifact's @module.dhall@, @recipe.dhall@,
-- @blueprint.dhall@, or @prompt.dhall@.
--
-- Classification, in order:
--
--   1. If @artifactDir@ is inside @projectRoot@, the result is a
--      'ProjectOrigin' holding the path relative to @projectRoot@ with
--      forward slashes.
--   2. Otherwise, if @artifactDir@ contains a readable
--      @.seihou-origin.json@ with a @sourceUrl@, the result is a
--      'RemoteOrigin' carrying that URL, the directory's base name, and
--      the recorded @repoName@.
--   3. Otherwise the result is a 'LocalOrigin' holding the directory's
--      base name.
detectArtifactOrigin :: FilePath -> FilePath -> IO ArtifactOrigin
detectArtifactOrigin projectRoot artifactDir = do
  root <- canonicalizeOr projectRoot
  dir <- canonicalizeOr artifactDir
  case insideProject root dir of
    Just relative -> pure (ProjectOrigin relative)
    Nothing -> do
      originInfo <- readOriginInfo dir
      let name = T.pack (takeFileName dir)
      pure $ case originInfo of
        Just info -> RemoteOrigin (info ^. #sourceUrl) name (info ^. #repoName)
        Nothing -> LocalOrigin name

-- | 'canonicalizePath' throws when an intermediate component does not
-- exist, which happens in tests and for artifacts that were removed between
-- discovery and manifest write. Fall back to the raw path in that case.
canonicalizeOr :: FilePath -> IO FilePath
canonicalizeOr path = do
  result <- try @IOException (canonicalizePath path)
  pure (either (const path) id result)

-- | The artifact directory's path relative to the project root, when it is
-- genuinely inside it.
--
-- 'makeRelative' returns its second argument unchanged when the two paths
-- share no prefix, and returns @"."@ when they are the same directory, so
-- both cases have to be rejected explicitly. A leading @".."@ cannot appear
-- (GHC's 'makeRelative' never produces one) but is rejected anyway so a
-- future implementation change cannot smuggle an escaping path into the
-- manifest.
insideProject :: FilePath -> FilePath -> Maybe FilePath
insideProject root dir
  | relative == dir = Nothing
  | relative == "." = Nothing
  | take 2 relative == ".." = Nothing
  | otherwise = Just (map toForwardSlash relative)
  where
    relative = makeRelative root dir
    toForwardSlash c = if c == pathSeparator then '/' else c
