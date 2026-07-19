module Seihou.Engine.ThreeWayMerge
  ( MergeOutcome (..),
    threeWayMerge,
    threeWayMergeWithGit,
  )
where

import Control.Exception (IOException, displayException, try)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.Prelude
import System.Exit (ExitCode (..))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (readProcessWithExitCode)

-- | The result of reconciling a previous generated ancestor, the user's
-- current file, and newly generated content. No outcome writes to the project.
data MergeOutcome
  = MergeClean Text
  | MergeConflicted Text
  | MergeUnavailable Text
  deriving stock (Eq, Show)

-- | Merge generated content in argument order: previous generated baseline,
-- current disk content, then new generated content.
threeWayMerge :: Text -> Text -> Text -> IO MergeOutcome
threeWayMerge = threeWayMergeWithGit "git"

-- | Testable driver variant. Production callers should use 'threeWayMerge';
-- supplying the executable keeps missing-driver behavior directly testable.
threeWayMergeWithGit :: FilePath -> Text -> Text -> Text -> IO MergeOutcome
threeWayMergeWithGit gitExecutable baseline current newGenerated
  | any (T.any (== '\NUL')) [baseline, current, newGenerated] =
      pure (MergeUnavailable "binary content containing NUL cannot be merged")
  | current == baseline = pure (MergeClean newGenerated)
  | newGenerated == baseline = pure (MergeClean current)
  | current == newGenerated = pure (MergeClean current)
  | otherwise = do
      result <-
        try @IOException $
          withSystemTempDirectory "seihou-three-way-merge" $ \tmpDir -> do
            let currentPath = tmpDir </> "CURRENT"
                baselinePath = tmpDir </> "BASE"
                newPath = tmpDir </> "NEW"
            TIO.writeFile currentPath current
            TIO.writeFile baselinePath baseline
            TIO.writeFile newPath newGenerated
            readProcessWithExitCode
              gitExecutable
              [ "merge-file",
                "--stdout",
                "--diff3",
                "-L",
                "current",
                "-L",
                "generated-base",
                "-L",
                "new-generated",
                currentPath,
                baselinePath,
                newPath
              ]
              ""
      pure $ case result of
        Left err -> MergeUnavailable ("git merge-file unavailable: " <> T.pack (displayException err))
        Right (ExitSuccess, stdout, _) -> MergeClean (T.pack stdout)
        Right (ExitFailure _, stdout, stderr)
          | hasCompleteConflictMarkers merged -> MergeConflicted merged
          | otherwise ->
              MergeUnavailable
                ( "git merge-file failed without a usable conflict result"
                    <> conciseStderr stderr
                )
          where
            merged = T.pack stdout

hasCompleteConflictMarkers :: Text -> Bool
hasCompleteConflictMarkers output =
  all
    (\marker -> any (marker `T.isPrefixOf`) (T.lines output))
    [ "<<<<<<< current",
      "||||||| generated-base",
      "=======",
      ">>>>>>> new-generated"
    ]

conciseStderr :: String -> Text
conciseStderr stderr = case T.strip (T.pack stderr) of
  "" -> ""
  message -> ": " <> T.take 240 message
