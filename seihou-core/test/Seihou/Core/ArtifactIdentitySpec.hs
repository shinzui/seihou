module Seihou.Core.ArtifactIdentitySpec (tests) where

import Control.Monad (forM_)
import Data.Text (Text)
import Data.Text qualified as T
import Seihou.Core.ArtifactIdentity (isMachineLocalOriginUrl)
import Test.Hspec
import Test.Tasty
import Test.Tasty.Hspec (testSpec)

tests :: IO TestTree
tests = testSpec "Seihou.Core.ArtifactIdentity" spec

machineLocal :: [Text]
machineLocal =
  [ "/Users/alice/Keikaku/bokuno/seihou-modules",
    "  /srv/modules  ",
    "./modules",
    "../seihou-modules",
    ".",
    "..",
    "~/src/seihou-modules",
    "~",
    "file:///Users/alice/seihou-modules",
    "file:../modules",
    "C:\\src\\modules",
    "c:/src/modules"
  ]

remote :: [Text]
remote =
  [ "https://github.com/shinzui/seihou-modules.git",
    "http://example.com/mods",
    "ssh://git@github.com/shinzui/seihou-modules.git",
    "git://example.com/mods.git",
    "git@github.com:shinzui/seihou-modules.git",
    "github.com:shinzui/seihou-modules",
    "modules"
  ]

spec :: Spec
spec =
  describe "isMachineLocalOriginUrl" $ do
    forM_ machineLocal $ \url ->
      it ("treats " <> T.unpack url <> " as machine-local") $
        isMachineLocalOriginUrl url `shouldBe` True
    forM_ remote $ \url ->
      it ("treats " <> T.unpack url <> " as reachable from other machines") $
        isMachineLocalOriginUrl url `shouldBe` False
