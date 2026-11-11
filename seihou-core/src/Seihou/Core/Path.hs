module Seihou.Core.Path
  ( validateProjectRelativePath,
    validateCanonicalProjectPath,
    pathsHaveConflictingSpelling,

    -- * Seihou and Git control paths
    ProjectPathClass (..),
    PathOperand (..),
    classifyProjectPath,
    reservedSeihouEntries,
    isControlFileTarget,
    isControlDirectory,
    controlPathReason,
    ownStateDirectoryViolation,
  )
where

import Data.Maybe (isJust)
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

-- | What a validated project-relative path names, for the rules that keep
-- module output away from Seihou's and Git's own data.
--
-- A module owns exactly one directory under @.seihou/@, named after itself;
-- everything on 'reservedSeihouEntries' belongs to Seihou. See
-- docs/adr/0025-a-module-owns-only-its-own-directory-under-seihou.md.
data ProjectPathClass
  = -- | An ordinary project path, outside @.seihou@ and @.git@.
    OrdinaryProjectPath
  | -- | The @.seihou@ directory itself: creatable as a directory, never a file.
    SeihouRootDirectory
  | -- | Under @.seihou/<area>@, where @<area>@ (as written) is not Seihou's own.
    -- The 'Bool' says whether the path continues below the area directory.
    ModuleStatePath !Text !Bool
  | -- | Seihou's own state or Git's; the 'Text' is the user-facing reason.
    ControlPath !Text
  deriving stock (Eq, Show, Generic)

-- | Whether a path names a file to write or a directory to create.
data PathOperand = FileTarget | DirectoryOperand
  deriving stock (Eq, Show, Generic)

-- | The entries directly under @.seihou/@ that Seihou itself owns, case-folded.
-- Every name beginning with @.@ is reserved as well. New Seihou state under
-- @.seihou/@ must be added here and must use a name that is not a valid module
-- name (one not matching @[a-z][a-z0-9-]*@), so it never collides with a
-- module's state directory.
reservedSeihouEntries :: [Text]
reservedSeihouEntries =
  [ "manifest.json",
    "manifest.json.tmp",
    "baselines",
    "transactions",
    "transactions-quarantine",
    "modules",
    "context",
    "config.dhall",
    "trace.jsonl"
  ]

-- | Classify a path that has already passed 'validateProjectRelativePath'.
-- Segments split on either separator; empty and @.@ segments are ignored, and
-- the @.seihou@, @.git@ and reserved names compare case-insensitively because
-- the default macOS volume does.
classifyProjectPath :: FilePath -> ProjectPathClass
classifyProjectPath path = case controlSegments path of
  first' : rest
    | T.toCaseFold first' == ".git" -> ControlPath "path targets Git control data"
    | T.toCaseFold first' == ".seihou" -> case rest of
        [] -> SeihouRootDirectory
        entry : below
          | isReservedSeihouEntry entry ->
              ControlPath ("path targets Seihou's own state at " <> first' <> "/" <> entry)
          | otherwise -> ModuleStatePath entry (not (null below))
  _ -> OrdinaryProjectPath

controlSegments :: FilePath -> [Text]
controlSegments = filter (/= ".") . pathSegments . T.pack

isReservedSeihouEntry :: Text -> Bool
isReservedSeihouEntry entry =
  "." `T.isPrefixOf` entry || T.toCaseFold entry `elem` reservedSeihouEntries

-- | A path no module output may write as a file: Seihou's or Git's control
-- data, or the @.seihou@ directory itself.
isControlFileTarget :: FilePath -> Bool
isControlFileTarget = isJust . controlPathReason FileTarget

-- | A directory no module output may create or replace. The @.seihou@
-- directory itself is allowed: creating it when it exists is a no-op.
isControlDirectory :: FilePath -> Bool
isControlDirectory = isJust . controlPathReason DirectoryOperand

-- | Why a path is refused as the given kind of operand, in user words, or
-- 'Nothing' when it is not control data.
controlPathReason :: PathOperand -> FilePath -> Maybe Text
controlPathReason operand path = case classifyProjectPath path of
  ControlPath reason -> Just reason
  SeihouRootDirectory
    | operand == FileTarget -> Just "path names Seihou's state directory .seihou itself"
  _ -> Nothing

-- | 'Nothing' when the module named by the first argument may write (as a file
-- target) or create (as a directory operand) the path. A module may write under
-- @.seihou/@ only inside @.seihou/<its own name>/@, spelled exactly; any
-- other answer is a message that names the directory it may use.
ownStateDirectoryViolation :: Text -> PathOperand -> FilePath -> Maybe Text
ownStateDirectoryViolation moduleName operand path = case classifyProjectPath path of
  OrdinaryProjectPath -> Nothing
  ControlPath reason -> Just reason
  SeihouRootDirectory
    | operand == DirectoryOperand -> Nothing
    | otherwise -> Just (T.pack path <> " is Seihou's state directory and cannot be written as a file")
  ModuleStatePath area below
    | ownSpelling && area == moduleName && (below || operand == DirectoryOperand) -> Nothing
    | ownSpelling && area == moduleName ->
        Just (T.pack path <> " is this module's state directory and cannot be written as a file")
    | otherwise ->
        Just
          ( T.pack path
              <> " is outside this module's state directory; a module may write under .seihou/ only inside "
              <> ownDirectory
          )
  where
    ownSpelling = take 1 (controlSegments path) == [".seihou"]
    ownDirectory = ".seihou/" <> moduleName <> "/"

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
