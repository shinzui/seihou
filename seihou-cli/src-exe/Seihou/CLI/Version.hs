{-# LANGUAGE CPP #-}
{-# LANGUAGE TemplateHaskell #-}

module Seihou.CLI.Version
  ( seihouVersion,
    seihouVersionWithGit,
    gitCommitShort,
  )
where

import Data.Text (Text, pack)
import Data.Version (showVersion)
import GitHash (GitInfo, giHash, tGitInfoCwdTry)
import Paths_seihou_cli (version)

seihouVersion :: Text
seihouVersion = pack (showVersion version)

-- | Git info embedded at compile time (Right if in git repo, Left with error message otherwise)
gitInfo :: Either String GitInfo
gitInfo = $$tGitInfoCwdTry

-- | Fallback git hash injected via CPP for Nix builds where .git is absent.
nixGitHash :: Maybe Text
#ifdef GIT_HASH
nixGitHash = Just GIT_HASH
#else
nixGitHash = Nothing
#endif

-- | Get the short git commit hash (first 7 characters).
-- Falls back to CPP-injected GIT_HASH for Nix builds.
gitCommitShort :: Maybe Text
gitCommitShort = case gitInfo of
  Right gi -> Just $ pack $ take 7 $ giHash gi
  Left _ -> nixGitHash

-- | Version string with git commit suffix (e.g. "seihou v0.1.0.0 (a1b2c3d)")
seihouVersionWithGit :: Text
seihouVersionWithGit = "seihou v" <> seihouVersion <> commitSuffix
  where
    commitSuffix = maybe "" (\c -> " (" <> c <> ")") gitCommitShort
