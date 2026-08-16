-- | When two recorded artifact origins name the same artifact.
--
-- The manifest identifies an artifact by its origin plus its name (see
-- docs\/adr\/0002-artifact-identity-is-origin-url-plus-name.md), and several
-- places have to ask whether two such identities are the same one: the
-- blueprint-migration receipt ledger in 'Seihou.Manifest.Types' when it
-- upserts a receipt, the pending-edge filter in
-- 'Seihou.CLI.BlueprintMigration' when it decides what still has to run, and
-- the pre-generation guard in 'Seihou.CLI.ManifestGuard' when it compares
-- what the manifest records against what is installed here. They must agree,
-- or a receipt could be written as a new entry while being read as a
-- duplicate, so the comparison lives in one place.
--
-- This module answers a plain yes-or-no question. The richer three-way
-- judgement that distinguishes "different artifact" from "cannot be proved
-- either way" belongs to 'Seihou.CLI.ManifestGuard.judgeArtifact' and is not
-- appropriate here: a receipt either records this exact identity or it does
-- not, with no unverifiable middle ground.
module Seihou.Core.ArtifactIdentity
  ( sameArtifactIdentity,
    normalizeOriginUrl,
    normalizeProjectPath,
  )
where

import Data.Maybe (fromMaybe)
import Data.Text qualified as T
import Seihou.Core.Types (ArtifactOrigin (..))
import Seihou.Prelude

-- | Whether two recorded origins name the same artifact.
--
-- Two origins of different kinds are never the same artifact. Within a kind
-- the comparison is structural, after normalising away spellings that differ
-- without meaning anything: a trailing @.git@ on a git URL, and a @.\/@
-- prefix or trailing slash on a project-relative path.
--
-- A 'LocalOrigin' carries no provenance at all, so two of them compare equal
-- exactly when they carry the same name. That is deliberately weak — it is
-- also the strongest statement available about an artifact seihou can only
-- identify by name — and it is what makes two receipts written before origins
-- were recorded still match each other.
sameArtifactIdentity :: ArtifactOrigin -> ArtifactOrigin -> Bool
sameArtifactIdentity left right = case (left, right) of
  (RemoteOrigin leftUrl leftName _, RemoteOrigin rightUrl rightName _) ->
    normalizeOriginUrl leftUrl == normalizeOriginUrl rightUrl
      && leftName == rightName
  (ProjectOrigin leftPath, ProjectOrigin rightPath) ->
    normalizeProjectPath leftPath == normalizeProjectPath rightPath
  (LocalOrigin leftName, LocalOrigin rightName) -> leftName == rightName
  _ -> False

-- | Reduce a git URL to a form two spellings of the same repository share.
--
-- @https:\/\/host\/repo@, @https:\/\/host\/repo.git@ and
-- @https:\/\/host\/repo\/@ all name the same repository, and a manifest
-- written by a developer who typed one of them must not read as a different
-- artifact to a developer who typed another.
normalizeOriginUrl :: Text -> Text
normalizeOriginUrl =
  dropTrailingSlashes . dropGitSuffix . dropTrailingSlashes . T.strip
  where
    dropTrailingSlashes = T.dropWhileEnd (== '/')
    dropGitSuffix url = fromMaybe url (T.stripSuffix ".git" url)

-- | Reduce a project-relative path to a comparable form. The manifest stores
-- these with forward slashes; @.\/@ prefixes and trailing slashes are noise.
normalizeProjectPath :: FilePath -> FilePath
normalizeProjectPath =
  dropWhileEnd' (== '/') . dropDotPrefix . dropWhileEnd' (== '/')
  where
    dropDotPrefix path = fromMaybe path (stripPrefix' "./" path)
    stripPrefix' prefix path =
      if take (length prefix) path == prefix
        then Just (drop (length prefix) path)
        else Nothing
    dropWhileEnd' p = reverse . dropWhile p . reverse
