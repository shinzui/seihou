-- | Locating the @seihou@ executable the end-to-end tests shell out to.
--
-- The test suite declares @build-tool-depends: seihou-cli:seihou@, and cabal
-- used to satisfy that by symlinking the executable next to the test binary at
-- @\<test-build-dir\>\/..\/seihou\/seihou@. Cabal 3.16 no longer creates that
-- symlink, so every end-to-end spec that assumed it went looking for a path
-- that does not exist. We probe the layouts cabal actually produces and report
-- every directory searched when none of them holds the binary, rather than
-- surfacing a bare @posix_spawnp: does not exist@ from deep inside a spec.
--
-- Deliberately absent: a @PATH@ lookup. Falling back to whatever @seihou@ the
-- developer has installed would silently test a different build than the one
-- under test, which is worse than failing.
module Seihou.CLI.SeihouBinary
  ( seihouBinary,
  )
where

import Control.Monad (filterM)
import Data.List (intercalate)
import System.Directory (doesFileExist)
import System.Environment (getExecutablePath)
import System.FilePath (takeDirectory, (</>))

-- | The @seihou@ executable built alongside this test suite.
seihouBinary :: IO FilePath
seihouBinary = do
  candidates <- seihouBinaryCandidates
  found <- filterM doesFileExist candidates
  case found of
    (binary : _) -> pure binary
    [] ->
      fail $
        "Could not find the seihou executable built alongside this test suite.\n"
          <> "Searched:\n"
          <> intercalate "\n" (map ("  " <>) candidates)
          <> "\nBuild it with 'cabal build seihou-cli:seihou' and rerun."

-- | The places cabal has been observed to put the executable, most specific
-- first: the @build-tool-depends@ symlink beside the test binary, then the
-- executable component's own build directory under the same package.
seihouBinaryCandidates :: IO [FilePath]
seihouBinaryCandidates = do
  testBinary <- getExecutablePath
  -- @\<pkg\>/t/seihou-cli-test/build@
  let testBuildDir = takeDirectory (takeDirectory testBinary)
      -- @\<pkg\>@, three levels above @build@
      packageDir = takeDirectory (takeDirectory (takeDirectory testBuildDir))
  pure
    [ testBuildDir </> "seihou" </> "seihou",
      packageDir </> "x" </> "seihou" </> "build" </> "seihou" </> "seihou"
    ]
