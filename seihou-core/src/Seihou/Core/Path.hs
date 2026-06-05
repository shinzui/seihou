module Seihou.Core.Path
  ( validateProjectRelativePath,
  )
where

import Data.Text qualified as T
import Seihou.Prelude
import System.FilePath qualified as FilePath
import System.FilePath.Windows qualified as WindowsPath

-- | Validate that a path stays within a project root when later appended to it.
-- The path must be non-empty, relative on POSIX and Windows, and must not
-- contain a parent-directory segment.
validateProjectRelativePath :: Text -> Either Text FilePath
validateProjectRelativePath rawPath
  | T.null path = Left "path must not be empty"
  | FilePath.isAbsolute pathString || WindowsPath.isAbsolute pathString =
      Left ("path must be relative: " <> path)
  | any (== "..") (pathSegments path) =
      Left ("path must not contain '..' segment: " <> path)
  | otherwise = Right pathString
  where
    path = T.strip rawPath
    pathString = T.unpack path

pathSegments :: Text -> [Text]
pathSegments =
  filter (not . T.null)
    . T.split (\c -> c == '/' || c == '\\')
