-- | Turn an artifact origin recorded in the manifest into a directory on
-- this machine.
--
-- @.seihou\/manifest.json@ is checked into version control and records no
-- absolute path (see
-- docs\/adr\/0001-manifest-is-a-checked-in-machine-independent-artifact.md),
-- so every command that needs an artifact's bytes has to ask this question
-- first. This module is the single place that answers it, and the single
-- place that phrases the answer when it is "not here".
module Seihou.Core.ArtifactRef
  ( ArtifactRefError (..),
    resolveArtifactOrigin,
    renderArtifactRefError,
  )
where

import Data.Generics.Labels ()
import Data.Text qualified as T
import Seihou.Core.Types (ArtifactOrigin (..))
import Seihou.Prelude
import System.Directory (doesFileExist)
import System.FilePath (joinPath)

-- | Why an origin recorded in the manifest could not be turned into a
-- directory on this machine.
data ArtifactRefError
  = -- | Nothing named by the origin exists in any search path. Carries the
    -- origin and the exact directories that were probed, in order.
    ArtifactNotFoundLocally !ArtifactOrigin ![FilePath]
  | -- | A 'ProjectOrigin' pointed at a path inside the project that does
    -- not exist. Carries the origin and the absolute path that was tried.
    ProjectArtifactMissing !ArtifactOrigin !FilePath
  deriving stock (Eq, Show, Generic)

-- | Turn a recorded origin into the absolute directory on this machine
-- that holds the artifact's definition file.
--
-- @projectRoot@ is the absolute directory containing @.seihou@.
-- @searchPaths@ is normally 'Seihou.Core.Module.defaultSearchPaths'; it is
-- a parameter so tests can supply temporary directories.
-- @definitionFile@ is the file that must be present for a directory to
-- count as the artifact — @"module.dhall"@ for modules,
-- @"recipe.dhall"@ for recipes, @"blueprint.dhall"@ for blueprints.
--
-- A 'ProjectOrigin' resolves against the project root and nowhere else. If
-- the recorded directory is absent the repository is incomplete, and
-- quietly substituting a globally installed artifact of the same name would
-- be exactly the invisible substitution the portable manifest exists to
-- prevent.
--
-- A 'RemoteOrigin' or 'LocalOrigin' resolves by name through @searchPaths@
-- in the ordinary discovery order, so a developer who deliberately shadows
-- an installed module with a project-local copy keeps that shadowing.
-- Whether what was found actually matches the recorded origin is a separate
-- question, answered by
-- docs\/plans\/78-refuse-accidental-module-downgrades-and-origin-mismatches.md.
resolveArtifactOrigin ::
  FilePath ->
  [FilePath] ->
  FilePath ->
  ArtifactOrigin ->
  IO (Either ArtifactRefError FilePath)
resolveArtifactOrigin projectRoot searchPaths definitionFile origin = case origin of
  ProjectOrigin relative -> do
    let candidate = projectRoot </> fromPortablePath relative
    present <- hasDefinition candidate
    pure $
      if present
        then Right candidate
        else Left (ProjectArtifactMissing origin candidate)
  RemoteOrigin _ artifact _ -> searchByName artifact
  LocalOrigin artifact -> searchByName artifact
  where
    searchByName artifact = do
      let candidates = [dir </> T.unpack artifact | dir <- searchPaths]
      found <- firstPresent candidates
      pure (maybe (Left (ArtifactNotFoundLocally origin candidates)) Right found)

    firstPresent [] = pure Nothing
    firstPresent (candidate : rest) = do
      present <- hasDefinition candidate
      if present then pure (Just candidate) else firstPresent rest

    hasDefinition directory = doesFileExist (directory </> definitionFile)

-- | The manifest stores project-relative paths with forward slashes so a
-- manifest written on Windows matches one written on POSIX. Turn one back
-- into a native path.
fromPortablePath :: FilePath -> FilePath
fromPortablePath = joinPath . filter (not . null) . splitOnSlash
  where
    splitOnSlash path = case break (== '/') path of
      (segment, []) -> [segment]
      (segment, _ : rest) -> segment : splitOnSlash rest

-- | Render a resolution failure as the multi-line message the user sees.
--
-- Callers prepend their own one-line context ("cannot plan a migration",
-- "cannot regenerate"); the body below is identical everywhere so a reader
-- who has seen it once recognises it.
renderArtifactRefError :: ArtifactRefError -> Text
renderArtifactRefError (ProjectArtifactMissing origin candidate) =
  T.intercalate
    "\n"
    [ "Artifact '" <> artifactOriginLabel origin <> "' is recorded in .seihou/manifest.json",
      "as living inside this project, but the directory is missing.",
      "",
      "  Expected at: " <> T.pack candidate,
      "",
      "This directory should be committed alongside the manifest. Restore it",
      "from version control, or re-run the module that creates it."
    ]
renderArtifactRefError (ArtifactNotFoundLocally origin candidates) =
  T.intercalate "\n" (header <> [""] <> recordedOrigin <> searched <> [""] <> remedy)
  where
    label = artifactOriginLabel origin

    header =
      [ "Artifact '" <> label <> "' is recorded in .seihou/manifest.json but is not",
        "installed on this machine."
      ]

    recordedOrigin = case origin of
      RemoteOrigin url _ _ -> ["  Recorded origin: " <> url, ""]
      _ -> []

    searched = "  Searched:" : ["    " <> T.pack candidate | candidate <- candidates]

    remedy = case origin of
      RemoteOrigin url _ _ ->
        [ "  Install it with:",
          "    seihou install " <> url
        ]
      _ ->
        [ "  This artifact has no recorded upstream, so seihou cannot fetch it.",
          "  Place a copy in one of the directories above."
        ]

-- | The name to show a user for an origin.
artifactOriginLabel :: ArtifactOrigin -> Text
artifactOriginLabel (RemoteOrigin _ artifact _) = artifact
artifactOriginLabel (LocalOrigin artifact) = artifact
artifactOriginLabel (ProjectOrigin relative) = T.pack relative
