module Seihou.Core.Path
  ( validateProjectRelativePath,
    validateCanonicalProjectPath,
    pathsHaveConflictingSpelling,
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

-- | Checkout declarations use a canonical, portable spelling and reserve metadata.
-- This deliberately strengthens rather than changes the legacy validator above.
validateCanonicalProjectPath :: Text -> Either Text ()
validateCanonicalProjectPath raw = do
  _ <- validateProjectRelativePath raw
  if T.null raw
    || raw /= T.strip raw
    || T.any (\c -> c == '\\' || c == '\0' || c == ':') raw
    || any (\part -> T.null part || part == "." || part == ".." || T.toCaseFold part `elem` [".git", ".seihou"]) (T.splitOn "/" raw)
    then Left ("path must use canonical project-relative components outside .git and .seihou: " <> raw)
    else Right ()

-- | Refuse case aliases in the portable output namespace, including conflicting
-- ancestor spellings, before any filesystem object is created.
pathsHaveConflictingSpelling :: FilePath -> FilePath -> Bool
pathsHaveConflictingSpelling a b = go (T.splitOn "/" (T.pack a)) (T.splitOn "/" (T.pack b))
  where
    go (x : xs) (y : ys)
      | x == y = go xs ys
      | otherwise = T.toCaseFold x == T.toCaseFold y
    go _ _ = False
