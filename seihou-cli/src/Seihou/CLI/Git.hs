module Seihou.CLI.Git
  ( isGitRepo,
    gitAdd,
    gitCommit,
    gitDiffCached,
  )
where

import Data.Text qualified as T
import Seihou.Effect.Process (Process, runProcess)
import Seihou.Prelude
import System.Exit (ExitCode (..))

-- | Check if the current directory is inside a git work tree.
isGitRepo :: (Process :> es) => Eff es Bool
isGitRepo = do
  (exitCode, _, _) <- runProcess "git" ["rev-parse", "--is-inside-work-tree"] Nothing
  pure (exitCode == ExitSuccess)

-- | Stage specific files.
gitAdd :: (Process :> es) => [FilePath] -> Eff es (ExitCode, Text, Text)
gitAdd paths =
  runProcess "git" ("add" : map T.pack paths) Nothing

-- | Create a commit with the given message.
gitCommit :: (Process :> es) => Text -> Eff es (ExitCode, Text, Text)
gitCommit msg =
  runProcess "git" ["commit", "-m", msg] Nothing

-- | Get the diff of staged changes for feeding to the commit message generator.
-- Returns a stat summary followed by the full diff (truncated to ~4000 chars).
gitDiffCached :: (Process :> es) => Eff es Text
gitDiffCached = do
  (_, stat, _) <- runProcess "git" ["diff", "--cached", "--stat"] Nothing
  (_, fullDiff, _) <- runProcess "git" ["diff", "--cached"] Nothing
  let truncatedDiff = T.take 4000 fullDiff
      suffix = if T.length fullDiff > 4000 then "\n... (diff truncated)" else ""
  pure (stat <> "\n" <> truncatedDiff <> suffix)
