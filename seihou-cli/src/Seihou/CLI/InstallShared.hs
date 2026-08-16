module Seihou.CLI.InstallShared
  ( -- * Origin metadata
    OriginInfo (..),
    OriginMeta (..),
    readOriginInfo,

    -- * Install collisions
    InstallCollision (..),
    InstallOutcome (..),
    classifyInstallCollision,
    formatInstallRefusal,
    formatInstallOverride,
    summarizeInstallRefusal,

    -- * Install primitives
    installModuleDir,
    installModuleDirInto,
    installedRoot,
    cloneRepo,
    copyDirectoryRecursive,
  )
where

import Control.Monad (when)
import Data.Aeson (ToJSON (..), object, (.=))
import Data.Aeson.Encode.Pretty (encodePretty)
import Data.ByteString.Lazy qualified as LBS
import Data.Generics.Labels ()
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Time (getCurrentTime)
import Data.Time.Format.ISO8601 (iso8601Show)
import Seihou.Core.ArtifactIdentity (normalizeOriginUrl)
import Seihou.Core.ArtifactOriginDetect (OriginInfo (..), readOriginInfo)
import Seihou.Prelude
import System.Directory
  ( XdgDirectory (..),
    copyFile,
    createDirectoryIfMissing,
    doesDirectoryExist,
    getXdgDirectory,
    listDirectory,
    removeDirectoryRecursive,
  )
import System.Exit (ExitCode (..))
import System.Process (readProcessWithExitCode)

-- ----------------------------------------------------------------------------
-- Origin metadata
-- ----------------------------------------------------------------------------

-- The read side ('OriginInfo', 'readOriginInfo') lives in
-- "Seihou.Core.ArtifactOriginDetect" because @seihou-core@ needs it to
-- classify an artifact directory into a portable manifest origin and cannot
-- depend on @seihou-cli-internal@. It is re-exported here so existing
-- importers are unaffected. The write side below stays in the CLI, which is
-- the only place that installs anything.

-- | Write side of @.seihou-origin.json@. Captures everything 'seihou
-- install' / 'seihou upgrade' want to record at install time, including
-- the timestamp.
data OriginMeta = OriginMeta
  { sourceUrl :: !Text,
    repoName :: !(Maybe Text),
    installedAt :: !Text,
    version :: !(Maybe Text),
    tags :: ![Text]
  }
  deriving stock (Generic)

instance ToJSON OriginMeta where
  toJSON m =
    object
      [ "sourceUrl" .= (m ^. #sourceUrl),
        "repoName" .= (m ^. #repoName),
        "installedAt" .= (m ^. #installedAt),
        "version" .= (m ^. #version),
        "tags" .= (m ^. #tags)
      ]

-- ----------------------------------------------------------------------------
-- Install collisions
-- ----------------------------------------------------------------------------

-- | What the install cache already holds at the name being installed into.
--
-- The cache at @~\/.config\/seihou\/installed\/@ is keyed by the artifact's
-- bare name across every repository the user has ever installed from, and it
-- is machine-global: every project on the machine resolves artifact names
-- through it. Replacing an entry is therefore either the most routine thing
-- seihou does — reinstalling the same artifact to pick up a new version — or
-- one of the most destructive, and the two are told apart only by the
-- provenance recorded in @.seihou-origin.json@ beside the installed copy.
data InstallCollision
  = -- | Nothing is installed under this name.
    NoExistingInstall
  | -- | An artifact from the same source URL is installed. This is the
    -- ordinary upgrade path. Carries the recorded version, if any.
    SameSource !(Maybe Text)
  | -- | An artifact from a different source URL is installed. Carries the
    -- recorded source URL.
    DifferentSource !Text
  | -- | Something is installed but carries no readable provenance, so seihou
    -- cannot tell whether replacing it is safe.
    UnknownSource
  deriving stock (Eq, Show, Generic)

-- | Whether an install ran or was refused.
--
-- 'installModuleDir' returns this rather than throwing because it has ten
-- call sites across four commands and each wants to react differently: a
-- single-artifact install exits, a registry batch collects and reports at the
-- end, and the three commands that reinstall from an artifact's own recorded
-- origin treat a refusal as evidence that the cache and that record disagree.
data InstallOutcome
  = InstallPerformed
  | InstallRefused !InstallCollision
  deriving stock (Eq, Show, Generic)

-- | Classify what is already installed at @installDir@ against the source URL
-- an install is about to write there.
--
-- URLs are compared through 'normalizeOriginUrl', so a user who typed
-- @https:\/\/host\/repo.git@ last week and @https:\/\/host\/repo@ today is not
-- told they have a different artifact. That is the same normalisation the
-- manifest guard and the migration receipt ledger use; sharing it is what
-- keeps a refusal here consistent with a mismatch reported there.
classifyInstallCollision :: FilePath -> Text -> IO InstallCollision
classifyInstallCollision installDir incomingUrl = do
  exists <- doesDirectoryExist installDir
  if not exists
    then pure NoExistingInstall
    else do
      recorded <- readOriginInfo installDir
      pure $ case recorded of
        Nothing -> UnknownSource
        Just info
          | normalizeOriginUrl (info ^. #sourceUrl) == normalizeOriginUrl incomingUrl ->
              SameSource (info ^. #version)
          | otherwise -> DifferentSource (info ^. #sourceUrl)

-- | The refusal message, in the shape
-- 'Seihou.CLI.ManifestGuard.formatGuardRefusal' established, so one class of
-- problem reads with one vocabulary. Pure, so it can be tested without a
-- filesystem.
formatInstallRefusal :: String -> Text -> InstallCollision -> Text
formatInstallRefusal name incomingUrl = \case
  DifferentSource recordedUrl ->
    T.intercalate
      "\n"
      [ "✗ Refusing to install '" <> T.pack name <> "': a different artifact",
        "  is already installed under that name.",
        "",
        "  Installed on this machine:  " <> recordedUrl,
        "  Incoming:                   " <> incomingUrl,
        "",
        "  These are different artifacts that happen to share a name. Installing",
        "  would replace the first for every project on this machine.",
        "",
        "  To replace it anyway, re-run with --force."
      ]
  UnknownSource ->
    T.intercalate
      "\n"
      [ "✗ Refusing to install '" <> T.pack name <> "': something is already",
        "  installed under that name and records no provenance.",
        "",
        "  Installed on this machine:  (no .seihou-origin.json)",
        "  Incoming:                   " <> incomingUrl,
        "",
        "  Seihou cannot tell whether these are the same artifact, and replacing",
        "  it would affect every project on this machine that resolved the name.",
        "",
        "  To replace it anyway, re-run with --force."
      ]
  NoExistingInstall -> ""
  SameSource _ -> ""

-- | A one-line reason, for callers that report inside a table or a per-entry
-- status rather than as a standalone block — the shape
-- 'Seihou.CLI.ManifestGuard.summarizeCheck' uses for the same reason.
summarizeInstallRefusal :: Text -> InstallCollision -> Text
summarizeInstallRefusal incomingUrl = \case
  DifferentSource recordedUrl ->
    "refused: the installed copy records " <> recordedUrl <> ", not " <> incomingUrl
  UnknownSource ->
    "refused: the installed copy records no provenance, so it cannot be matched against "
      <> incomingUrl
  NoExistingInstall -> ""
  SameSource _ -> ""

-- | The same news printed when @--force@ was passed. A deliberate override
-- should still be visible in the terminal, exactly as
-- 'Seihou.CLI.ManifestGuard.formatGuardOverride' keeps @--allow-downgrade@
-- visible; silently honouring the flag would hide the change this refusal
-- exists to make legible.
formatInstallOverride :: String -> Text -> InstallCollision -> Text
formatInstallOverride name incomingUrl = \case
  DifferentSource recordedUrl ->
    T.intercalate
      "\n"
      [ "! Replacing '" <> T.pack name <> "' with an artifact from a different",
        "  source (--force).",
        "",
        "  Was installed from:  " <> recordedUrl,
        "  Now installed from:  " <> incomingUrl
      ]
  UnknownSource ->
    T.intercalate
      "\n"
      [ "! Replacing '" <> T.pack name <> "', which records no provenance, with",
        "  " <> incomingUrl <> " (--force)."
      ]
  NoExistingInstall -> ""
  SameSource _ -> ""

-- ----------------------------------------------------------------------------
-- Install primitives
-- ----------------------------------------------------------------------------

-- | The machine-global install cache, @~\/.config\/seihou\/installed@.
installedRoot :: IO FilePath
installedRoot = do
  xdgConfig <- getXdgDirectory XdgConfig "seihou"
  pure (xdgConfig </> "installed")

-- | Copy an artifact directory to @~\/.config\/seihou\/installed\/<name>@ and
-- write its origin metadata. The source directory must already contain the
-- artifact's files; this function does not clone or fetch.
--
-- An existing installation from the same source URL is replaced without
-- comment — that is the ordinary upgrade path, and the calling command
-- already reports what it installed. One from a different source, or one with
-- no readable provenance, is refused with 'InstallRefused' and the cache is
-- left byte-identical, unless @force@ is 'True', in which case the override is
-- printed and the install proceeds.
installModuleDir :: Bool -> FilePath -> String -> Text -> Maybe Text -> Maybe Text -> [Text] -> IO InstallOutcome
installModuleDir force moduleDir name source registryName moduleVersion moduleTags = do
  root <- installedRoot
  installModuleDirInto root force moduleDir name source registryName moduleVersion moduleTags

-- | 'installModuleDir' against an explicit cache root.
--
-- Every command wants the XDG-derived root, so they call 'installModuleDir'.
-- This variant exists so tests can install into a temporary directory without
-- redirecting @XDG_CONFIG_HOME@, which is process-global and therefore unsafe
-- to mutate in a test suite that runs specs concurrently.
installModuleDirInto ::
  FilePath -> Bool -> FilePath -> String -> Text -> Maybe Text -> Maybe Text -> [Text] -> IO InstallOutcome
installModuleDirInto root force moduleDir name source registryName moduleVersion moduleTags = do
  let installDir = root </> name

  collision <- classifyInstallCollision installDir source
  let blocked = case collision of
        DifferentSource _ -> True
        UnknownSource -> True
        NoExistingInstall -> False
        SameSource _ -> False

  if blocked && not force
    then pure (InstallRefused collision)
    else do
      -- Nothing is removed until the collision has been accepted, so a
      -- refusal leaves the cache exactly as it was.
      when blocked $
        TIO.putStrLn (formatInstallOverride name source collision)

      exists <- doesDirectoryExist installDir
      when exists $ removeDirectoryRecursive installDir

      createDirectoryIfMissing True installDir
      copyDirectoryRecursive moduleDir installDir

      now <- getCurrentTime
      let origin = OriginMeta source registryName (T.pack (iso8601Show now)) moduleVersion moduleTags
      LBS.writeFile (installDir </> ".seihou-origin.json") (encodePretty origin)
      pure InstallPerformed

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
