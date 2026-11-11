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
    sameRepositoryOrigin,
    RepositoryOriginKey,
    repositoryOriginKey,
    normalizeOriginUrl,
    normalizeProjectPath,
    isMachineLocalOriginUrl,
  )
where

import Control.Monad (guard)
import Data.Char (isAsciiLower, isAsciiUpper, isControl, isDigit, isHexDigit, isSpace)
import Data.Maybe (fromMaybe, isJust, isNothing)
import Data.Text qualified as T
import Seihou.Core.Types (ArtifactOrigin (..))
import Seihou.Prelude

-- | Whether two recorded origins name the same artifact.
--
-- Two origins of different kinds are never the same artifact. Within a kind
-- the comparison is structural, after normalising away spellings that differ
-- without meaning anything: remote URLs are compared with
-- 'sameRepositoryOrigin', and project-relative paths ignore a @.\/@ prefix
-- and trailing slashes.
--
-- A 'LocalOrigin' carries no provenance at all, so two of them compare equal
-- exactly when they carry the same name. That is deliberately weak — it is
-- also the strongest statement available about an artifact seihou can only
-- identify by name — and it is what makes two receipts written before origins
-- were recorded still match each other.
sameArtifactIdentity :: ArtifactOrigin -> ArtifactOrigin -> Bool
sameArtifactIdentity left right = case (left, right) of
  (RemoteOrigin leftUrl leftName _, RemoteOrigin rightUrl rightName _) ->
    sameRepositoryOrigin leftUrl rightUrl
      && leftName == rightName
  (ProjectOrigin leftPath, ProjectOrigin rightPath) ->
    normalizeProjectPath leftPath == normalizeProjectPath rightPath
  (LocalOrigin leftName, LocalOrigin rightName) -> leftName == rightName
  _ -> False

-- | Reduce a git URL to a form two spellings of the same repository share,
-- lexically.
--
-- @https:\/\/host\/repo@, @https:\/\/host\/repo.git@ and
-- @https:\/\/host\/repo\/@ all reduce to one text. This is a cosmetic
-- helper for keys that must stay specific to one connection method — a
-- session clone cache, the grouping of machine-local paths during repair —
-- and it never equates two transports. Identity decisions use
-- 'sameRepositoryOrigin' or 'repositoryOriginKey' instead. Never use the
-- result as a clone URL.
normalizeOriginUrl :: Text -> Text
normalizeOriginUrl = cosmeticPath . T.strip

-- | Trailing slashes and at most one terminal @.git@ of a non-empty final
-- component, so @repo\/.git@ keeps its separate @.git@ component.
cosmeticPath :: Text -> Text
cosmeticPath path =
  let trimmed = dropTrailingSlashes path
   in case T.stripSuffix ".git" trimmed of
        Just base | not (T.null base), T.last base /= '/' -> dropTrailingSlashes base
        _ -> trimmed
  where
    dropTrailingSlashes = T.dropWhileEnd (== '/')

-- | Whether two recorded git URLs name the same repository.
--
-- This is the one repository-identity comparison seihou makes: the manifest
-- guard, install collision checks, migration receipts, repair evidence and
-- update staging all ask it. The recorded text is never rewritten; this only
-- answers the question. See 'repositoryOriginKey' for the rules.
sameRepositoryOrigin :: Text -> Text -> Bool
sameRepositoryOrigin left right = repositoryOriginKey left == repositoryOriginKey right

-- | The repository a recorded git URL identifies, as an opaque comparable
-- key. Two URLs have equal keys exactly when 'sameRepositoryOrigin' says
-- they name the same repository, so the key can index a map.
--
-- The constructors are private. Their distinct tags keep classes apart: a
-- recognised public GitHub repository, a generic scheme URL, a generic
-- scp-style address, and opaque text (local paths, @file:@, unsupported
-- schemes, and anything malformed) can never compare equal to one another.
data RepositoryOriginKey
  = -- | Owner and repository on public GitHub.
    GitHubRepository !Text !Text
  | -- | Scheme, user information, host, non-default port, path, query and
    -- fragment of a generic network URL. Absent and empty query or
    -- fragment differ.
    SchemeEndpoint !Text !(Maybe Text) !Text !(Maybe Int) !Text !(Maybe Text) !(Maybe Text)
  | -- | User, host and path of a generic scp-style address. A relative path
    -- may be relative to the user's home and is kept as written.
    ScpEndpoint !(Maybe Text) !Text !Text
  | -- | Text no supported form recognised, after cosmetic normalisation.
    OpaqueOrigin !Text
  deriving stock (Eq, Ord, Show, Generic)

-- | Parse a recorded git URL into its 'RepositoryOriginKey'. Total, pure and
-- offline: no DNS, filesystem, git configuration or network.
--
-- The text is parsed before anything is normalised, so cleanup can never
-- manufacture a match. Public GitHub has one documented equivalence class:
-- @https:\/\/github.com\/OWNER\/REPO@ (port 443 allowed, user information
-- ignored), @ssh:\/\/git\@github.com\/OWNER\/REPO@ (port 22 allowed),
-- @git\@github.com:OWNER\/REPO@, and @ssh:\/\/git\@ssh.github.com:443\/OWNER\/REPO@,
-- each with an optional terminal @.git@ and trailing slashes. The path must be
-- exactly two ordinary components with no query, fragment, escape or empty
-- segment. Everything else compares conservatively: generic URLs keep their
-- scheme, user, non-default port, path, query and fragment; scp-style
-- addresses keep their user and relative path and never equal a scheme URL.
repositoryOriginKey :: Text -> RepositoryOriginKey
repositoryOriginKey raw
  | T.any (\c -> isSpace c || isControl c) url = opaque
  | isMachineLocalOriginUrl url = opaque
  | (scheme, rest) <- T.breakOn "://" url,
    not (T.null rest) =
      fromMaybe opaque (parseSchemeUrl (T.toLower scheme) (T.drop 3 rest))
  | otherwise = fromMaybe opaque (parseScp url)
  where
    url = T.strip raw
    opaque = OpaqueOrigin (normalizeOriginUrl url)

parseSchemeUrl :: Text -> Text -> Maybe RepositoryOriginKey
parseSchemeUrl scheme rest = do
  defaultPort <- lookup scheme [("https", 443), ("http", 80), ("ssh", 22), ("git", 9418)]
  let (beforeFragment, fragment) = splitDelimiter '#' rest
      (beforeQuery, query) = splitDelimiter '?' beforeFragment
      (authority, path) = T.break (== '/') beforeQuery
  (user, hostPort) <- case T.splitOn "@" authority of
    [hostPort] -> Just (Nothing, hostPort)
    [user, hostPort] -> Just (Just user, hostPort)
    _ -> Nothing
  (host, port) <- parseHostPort hostPort
  let explicitPort = if port == Just defaultPort then Nothing else port
      generic = do
        let cleaned = cosmeticPath path
        if T.null cleaned
          then Nothing
          else Just (SchemeEndpoint scheme user host explicitPort cleaned query fragment)
      github = do
        guard (isNothing query && isNothing fragment)
        guard $ case (scheme, user, host, port) of
          ("https", _, "github.com", Nothing) -> True
          ("https", _, "github.com", Just 443) -> True
          ("ssh", Just "git", "github.com", Nothing) -> True
          ("ssh", Just "git", "github.com", Just 22) -> True
          ("ssh", Just "git", "ssh.github.com", Just 443) -> True
          _ -> False
        githubPath =<< T.stripPrefix "/" path
  maybe generic Just github

-- | Split at the first delimiter, keeping an empty value distinct from an
-- absent delimiter.
splitDelimiter :: Char -> Text -> (Text, Maybe Text)
splitDelimiter delimiter text = case T.break (== delimiter) text of
  (before, after)
    | T.null after -> (before, Nothing)
    | otherwise -> (before, Just (T.drop 1 after))

-- | A lowercased DNS host or bracketed IPv6 literal, and an optional port in
-- 1..65535. An empty or out-of-range port is malformed.
parseHostPort :: Text -> Maybe (Text, Maybe Int)
parseHostPort text = do
  (host, portPart) <-
    if "[" `T.isPrefixOf` text
      then case T.breakOn "]" text of
        (_, close) | T.null close -> Nothing
        (open, close) -> do
          let literal = T.drop 1 open
          guard (not (T.null literal) && T.all (\c -> isHexDigit c || c == ':' || c == '.') literal)
          Just (T.toLower (open <> "]"), T.drop 1 close)
      else do
        let (name, portPart) = T.break (== ':') text
        guard (validDnsHost name)
        Just (T.toLower name, portPart)
  port <- case T.uncons portPart of
    Nothing -> Just Nothing
    Just (':', digits) -> Just <$> parsePort digits
    Just _ -> Nothing
  Just (host, port)

parsePort :: Text -> Maybe Int
parsePort digits = do
  guard (not (T.null digits) && T.length digits <= 5 && T.all isDigit digits)
  let value = T.foldl' (\acc c -> acc * 10 + fromEnum c - fromEnum '0') 0 digits
  guard (value >= 1 && value <= 65535)
  Just value

validDnsHost :: Text -> Bool
validDnsHost name =
  not (T.null name)
    && T.all (\c -> isAsciiLower c || isAsciiUpper c || isDigit c || c == '-' || c == '.') name
    && not ("." `T.isPrefixOf` name)
    && not (".." `T.isInfixOf` name)

-- | Git's scp-like syntax, @[user\@]host:path@, recognised only when no
-- slash precedes the first colon. Local and Windows paths were excluded
-- before this is tried.
parseScp :: Text -> Maybe RepositoryOriginKey
parseScp text = do
  let (beforeColon, afterColon) = T.break (== ':') text
  guard (not (T.null afterColon) && not ("/" `T.isInfixOf` beforeColon))
  (user, rest) <- case T.break (== '@') text of
    (candidate, at)
      | not (T.null at),
        T.all (\c -> c /= ':' && c /= '/' && c /= '[') candidate ->
          if T.null candidate then Nothing else Just (Just candidate, T.drop 1 at)
    _ -> Just (Nothing, text)
  (hostPart, path) <- splitHost rest
  (host, port) <- parseHostPort hostPart
  let cleaned = cosmeticPath path
  guard (isNothing port && not (T.null cleaned))
  -- A one-letter host with no user is a drive designator, not a server.
  guard (isJust user || T.length host > 1)
  let github = do
        guard (user == Just "git" && host == "github.com")
        githubPath path
  maybe (Just (ScpEndpoint user host cleaned)) Just github
  where
    splitHost rest
      | "[" `T.isPrefixOf` rest = case T.breakOn "]:" rest of
          (_, close) | T.null close -> Nothing
          (open, close) -> Just (open <> "]", T.drop 2 close)
      | otherwise = case T.break (== ':') rest of
          (host, colonPath) | not (T.null colonPath) -> Just (host, T.drop 1 colonPath)
          _ -> Nothing

-- | @OWNER\/REPO@ with optional trailing slashes and at most one terminal
-- @.git@, both components ordinary ASCII names. Case is preserved.
githubPath :: Text -> Maybe RepositoryOriginKey
githubPath path = case T.splitOn "/" (T.dropWhileEnd (== '/') path) of
  [owner, repoWithSuffix] -> do
    let repo = fromMaybe repoWithSuffix (T.stripSuffix ".git" repoWithSuffix)
    guard (ordinaryComponent owner && ordinaryComponent repo)
    Just (GitHubRepository owner repo)
  _ -> Nothing
  where
    ordinaryComponent component =
      not (T.null component)
        && component /= "."
        && component /= ".."
        && T.all (\c -> isAsciiLower c || isAsciiUpper c || isDigit c || c == '-' || c == '_' || c == '.') component

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

-- | Whether a recorded origin URL is a path on the machine that recorded it
-- rather than a location every developer can reach.
--
-- @seihou install@ accepts a local checkout, and before plan 98 it stored
-- that path verbatim as the installed copy's @sourceUrl@, which then reached
-- the manifest as a 'RemoteOrigin'. A path means nothing on another machine
-- (docs\/adr\/0001-manifest-is-a-checked-in-machine-independent-artifact.md)
-- and turns into a false origin mismatch on this one as soon as the artifact
-- is reinstalled from its real remote.
--
-- True for text that, once stripped, starts with @\/@, @.\/@, @..\/@, @~@
-- or @file:@, is exactly @.@ or @..@, or is a Windows drive path
-- (@C:\\@ or @C:\/@). False for URLs with a network scheme
-- (@https:\/\/@, @ssh:\/\/@, @git:\/\/@) and for scp-style
-- @user\@host:path@.
isMachineLocalOriginUrl :: Text -> Bool
isMachineLocalOriginUrl raw =
  any (`T.isPrefixOf` url) ["/", "./", "../", "~", "file:"]
    || url == "."
    || url == ".."
    || isDrivePath url
  where
    url = T.strip raw
    isDrivePath text = case T.unpack (T.take 3 text) of
      [letter, ':', sep] -> isDriveLetter letter && (sep == '\\' || sep == '/')
      _ -> False
    isDriveLetter c = isAsciiLower c || isAsciiUpper c
