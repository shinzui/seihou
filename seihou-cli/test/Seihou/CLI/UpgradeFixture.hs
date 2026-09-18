-- | Fixtures shared by the @seihou agent upgrade@ specs: the two-application
-- shared-path project of "Seihou.CLI.UpdateSpec", given portable origins.
--
-- 'prepareSharedPathFixture' records each module's origin as the path of a
-- local git repository, which the upgrade diagnosis rightly reports as a
-- machine-local origin. A project that is otherwise healthy needs remote
-- URLs, so 'preparePortableFixture' rewrites them to @https@ URLs and
-- 'portableEnvironment' has git map those URLs back onto the local
-- repositories, the technique "Seihou.CLI.RepairOriginsE2ESpec" uses.
module Seihou.CLI.UpgradeFixture
  ( preparePortableFixture,
    portableEnvironment,
    alphaUrl,
    betaUrl,
    snapshotTree,
  )
where

import Control.Lens ((^.))
import Control.Monad (forM)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.ManifestRepairOrigins (overManifestOrigins)
import Seihou.CLI.UpdateSpec (CoOwnerWriteMode (..), SharedPathFixture (..), prepareSharedPathFixture)
import Seihou.Core.Types (ArtifactOrigin (..))
import Seihou.Manifest.Types (manifestFromJSON, manifestToJSON)
import System.Directory (doesDirectoryExist, doesFileExist, listDirectory)
import System.FilePath ((</>))

alphaUrl :: Text
alphaUrl = "https://example.invalid/alpha.git"

betaUrl :: Text
betaUrl = "https://example.invalid/beta.git"

-- | 'prepareSharedPathFixture' with every recorded and installed origin
-- rewritten from a local path to 'alphaUrl' or 'betaUrl'.
preparePortableFixture :: CoOwnerWriteMode -> FilePath -> IO SharedPathFixture
preparePortableFixture mode root = do
  fixture <- prepareSharedPathFixture mode root
  bytes <- LBS.readFile (fixture ^. #manifestPath)
  manifest <- either fail pure (manifestFromJSON bytes)
  let portable = \case
        RemoteOrigin _ "alpha" repo -> RemoteOrigin alphaUrl "alpha" repo
        RemoteOrigin _ "beta" repo -> RemoteOrigin betaUrl "beta" repo
        other -> other
  LBS.writeFile (fixture ^. #manifestPath) (manifestToJSON (overManifestOrigins portable manifest))
  let installed = fixture ^. #xdgHome </> "seihou" </> "installed"
  rewriteOrigin (installed </> "alpha" </> ".seihou-origin.json") (root </> "remote" </> "alpha") alphaUrl
  rewriteOrigin (fixture ^. #betaInstalledPath </> ".seihou-origin.json") (root </> "remote" </> "beta") betaUrl
  pure fixture
  where
    rewriteOrigin file localPath url = do
      body <- TIO.readFile file
      TIO.writeFile file (T.replace (T.pack localPath) url body)

-- | @XDG_CONFIG_HOME@ for the fixture, and git configuration mapping both
-- portable URLs onto the fixture's local repositories.
portableEnvironment :: FilePath -> SharedPathFixture -> [(String, String)]
portableEnvironment root fixture =
  [ ("XDG_CONFIG_HOME", fixture ^. #xdgHome),
    ("GIT_CONFIG_COUNT", "2"),
    ("GIT_CONFIG_KEY_0", "url." <> (root </> "remote" </> "alpha") <> ".insteadOf"),
    ("GIT_CONFIG_VALUE_0", T.unpack alphaUrl),
    ("GIT_CONFIG_KEY_1", "url." <> (root </> "remote" </> "beta") <> ".insteadOf"),
    ("GIT_CONFIG_VALUE_1", T.unpack betaUrl)
  ]

-- | Every file under a directory, with its bytes, keyed by path.
snapshotTree :: FilePath -> IO (Map.Map FilePath BS.ByteString)
snapshotTree top = do
  exists <- doesDirectoryExist top
  if not exists then pure Map.empty else Map.fromList <$> walk top
  where
    walk directory = do
      names <- listDirectory directory
      concat
        <$> forM
          names
          ( \name -> do
              let path = directory </> name
              isDirectory <- doesDirectoryExist path
              if isDirectory
                then walk path
                else do
                  isFile <- doesFileExist path
                  if isFile then (\bytes -> [(path, bytes)]) <$> BS.readFile path else pure []
          )
