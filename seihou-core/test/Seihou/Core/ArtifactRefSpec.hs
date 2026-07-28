module Seihou.Core.ArtifactRefSpec (tests) where

import Control.Lens ((^.))
import Data.Generics.Labels ()
import Data.Text qualified as T
import GHC.Generics (Generic)
import Seihou.Core.ArtifactRef
import Seihou.Core.Types
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Core.ArtifactRef" spec

-- | A project root plus the three search paths seihou discovers through, in
-- the same order as 'Seihou.Core.Module.defaultSearchPaths': the project's
-- own modules, the developer's personal modules, and the install cache.
data Roots = Roots
  { projectRoot :: !FilePath,
    projectModules :: !FilePath,
    userModules :: !FilePath,
    installed :: !FilePath
  }
  deriving stock (Generic)

searchPathsOf :: Roots -> [FilePath]
searchPathsOf roots = [roots ^. #projectModules, roots ^. #userModules, roots ^. #installed]

withRoots :: (Roots -> IO a) -> IO a
withRoots body =
  withSystemTempDirectory "seihou-artifact-ref" $ \tmpDir -> do
    let roots =
          Roots
            { projectRoot = tmpDir </> "project",
              projectModules = tmpDir </> "project" </> ".seihou" </> "modules",
              userModules = tmpDir </> "home" </> "seihou" </> "modules",
              installed = tmpDir </> "home" </> "seihou" </> "installed"
            }
    mapM_ (createDirectoryIfMissing True) ((roots ^. #projectRoot) : searchPathsOf roots)
    body roots

-- | Create @<parent>/<name>/module.dhall@ and return the module directory.
plantModule :: FilePath -> String -> IO FilePath
plantModule parent name = do
  let directory = parent </> name
  createDirectoryIfMissing True directory
  writeFile (directory </> "module.dhall") "{- fixture -}"
  pure directory

resolve :: Roots -> ArtifactOrigin -> IO (Either ArtifactRefError FilePath)
resolve roots = resolveArtifactOrigin ((roots ^. #projectRoot)) (searchPathsOf roots) "module.dhall"

remoteOrigin :: ArtifactOrigin
remoteOrigin = RemoteOrigin "https://github.com/shinzui/seihou-modules.git" "haskell-base" (Just "seihou-modules")

spec :: Spec
spec = do
  describe "resolveArtifactOrigin" $ do
    it "finds a remote-origin artifact in the install cache" $ do
      withRoots $ \roots -> do
        expected <- plantModule ((roots ^. #installed)) "haskell-base"
        resolve roots remoteOrigin `shouldReturn` Right expected

    it "lets a project-local copy shadow the installed one" $ do
      withRoots $ \roots -> do
        shadow <- plantModule ((roots ^. #projectModules)) "haskell-base"
        _ <- plantModule ((roots ^. #installed)) "haskell-base"
        resolve roots remoteOrigin `shouldReturn` Right shadow

    it "finds a local-origin artifact in the personal module directory" $ do
      withRoots $ \roots -> do
        expected <- plantModule ((roots ^. #userModules)) "scratch"
        resolve roots (LocalOrigin "scratch") `shouldReturn` Right expected

    it "reports every probed directory in order when nothing matches" $ do
      withRoots $ \roots -> do
        result <- resolve roots remoteOrigin
        result
          `shouldBe` Left
            ( ArtifactNotFoundLocally
                remoteOrigin
                [ (roots ^. #projectModules) </> "haskell-base",
                  (roots ^. #userModules) </> "haskell-base",
                  (roots ^. #installed) </> "haskell-base"
                ]
            )

    it "ignores a directory that has no definition file" $ do
      withRoots $ \roots -> do
        createDirectoryIfMissing True ((roots ^. #projectModules) </> "haskell-base")
        expected <- plantModule ((roots ^. #installed)) "haskell-base"
        resolve roots remoteOrigin `shouldReturn` Right expected

    it "resolves a project origin against the project root" $ do
      withRoots $ \roots -> do
        expected <- plantModule ((roots ^. #projectModules)) "docs"
        resolve roots (ProjectOrigin ".seihou/modules/docs") `shouldReturn` Right expected

    it "refuses to substitute an installed artifact for a missing project one" $ do
      withRoots $ \roots -> do
        _ <- plantModule ((roots ^. #installed)) "docs"
        result <- resolve roots (ProjectOrigin ".seihou/modules/docs")
        result
          `shouldBe` Left
            ( ProjectArtifactMissing
                (ProjectOrigin ".seihou/modules/docs")
                ((roots ^. #projectRoot) </> ".seihou" </> "modules" </> "docs")
            )

  describe "renderArtifactRefError" $ do
    it "names the recorded URL, every probed directory, and the install remedy" $ do
      withRoots $ \roots -> do
        Left err <- resolve roots remoteOrigin
        let message = renderArtifactRefError err
        message `shouldSatisfy` T.isInfixOf "haskell-base"
        message `shouldSatisfy` T.isInfixOf "https://github.com/shinzui/seihou-modules.git"
        message `shouldSatisfy` T.isInfixOf "seihou install https://github.com/shinzui/seihou-modules.git"
        mapM_
          (\directory -> message `shouldSatisfy` T.isInfixOf (T.pack directory))
          [ (roots ^. #projectModules) </> "haskell-base",
            (roots ^. #userModules) </> "haskell-base",
            (roots ^. #installed) </> "haskell-base"
          ]

    it "says a local-origin artifact has no upstream to fetch from" $ do
      withRoots $ \roots -> do
        Left err <- resolve roots (LocalOrigin "scratch")
        let message = renderArtifactRefError err
        message `shouldSatisfy` T.isInfixOf "no recorded upstream"
        message `shouldSatisfy` not . T.isInfixOf "seihou install"

    it "says a missing project artifact should have been committed" $ do
      withRoots $ \roots -> do
        Left err <- resolve roots (ProjectOrigin ".seihou/modules/docs")
        let message = renderArtifactRefError err
        message `shouldSatisfy` T.isInfixOf ".seihou/modules/docs"
        message `shouldSatisfy` T.isInfixOf "committed"
