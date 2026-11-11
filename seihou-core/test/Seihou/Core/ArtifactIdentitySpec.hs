module Seihou.Core.ArtifactIdentitySpec (tests) where

import Control.Monad (forM_)
import Data.Text (Text)
import Data.Text qualified as T
import Seihou.Core.ArtifactIdentity (isMachineLocalOriginUrl, normalizeOriginUrl, repositoryOriginKey, sameArtifactIdentity, sameRepositoryOrigin)
import Seihou.Core.Types (ArtifactOrigin (..))
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
spec = do
  describe "isMachineLocalOriginUrl" $ do
    forM_ machineLocal $ \url ->
      it ("treats " <> T.unpack url <> " as machine-local") $
        isMachineLocalOriginUrl url `shouldBe` True
    forM_ remote $ \url ->
      it ("treats " <> T.unpack url <> " as reachable from other machines") $
        isMachineLocalOriginUrl url `shouldBe` False

  describe "normalizeOriginUrl" $ do
    it "keeps the cosmetic .git and trailing-slash spellings together" $
      map normalizeOriginUrl ["https://host/repo", "https://host/repo.git", "https://host/repo/", " https://host/repo.git/ "]
        `shouldBe` replicate 4 "https://host/repo"
    it "does not equate transports, so connection-specific keys stay specific" $
      normalizeOriginUrl "git@github.com:shinzui/seihou-modules.git" `shouldNotBe` normalizeOriginUrl "https://github.com/shinzui/seihou-modules"
    it "does not erase a separate .git path component" $
      normalizeOriginUrl "https://host/owner/repo/.git" `shouldNotBe` normalizeOriginUrl "https://host/owner/repo"

  describe "sameRepositoryOrigin" $ do
    forM_ equivalenceClasses $ \(label, members) ->
      describe label $
        forM_ [(a, b) | a <- members, b <- members] $ \(a, b) ->
          it (T.unpack a <> " ~ " <> T.unpack b) $ sameRepositoryOrigin a b `shouldBe` True

    forM_ distinctPairs $ \(a, b) ->
      it (T.unpack a <> " differs from " <> T.unpack b) $ do
        sameRepositoryOrigin a b `shouldBe` False
        sameRepositoryOrigin b a `shouldBe` False

    it "keeps every class apart from every other class" $
      and
        [ not (sameRepositoryOrigin a b)
        | (i, (_, left)) <- indexed,
          (j, (_, right)) <- indexed,
          i /= j,
          a <- left,
          b <- right
        ]
        `shouldBe` True

    it "is reflexive, symmetric and transitive over every sample" $ do
      let samples = concatMap snd equivalenceClasses <> concatMap (\(a, b) -> [a, b]) distinctPairs
      all (\a -> sameRepositoryOrigin a a) samples `shouldBe` True
      and [sameRepositoryOrigin a b == sameRepositoryOrigin b a | a <- samples, b <- samples] `shouldBe` True
      and
        [ sameRepositoryOrigin a c
        | a <- samples,
          b <- samples,
          sameRepositoryOrigin a b,
          c <- samples,
          sameRepositoryOrigin b c
        ]
        `shouldBe` True

    it "never lets malformed or hostile input become the recognised GitHub repository" $
      forM_ (concatMap (\(a, b) -> [a, b]) distinctPairs) $ \candidate ->
        if candidate `elem` reportedClass
          then pure ()
          else repositoryOriginKey candidate `shouldNotBe` repositoryOriginKey reportedHttps

  describe "sameArtifactIdentity" $ do
    it "treats the reported SSH and HTTPS records of one module as one artifact" $
      sameArtifactIdentity
        (RemoteOrigin "git@github.com:shinzui/seihou-modules.git" "git-init" Nothing)
        (RemoteOrigin reportedHttps "git-init" (Just "seihou-modules"))
        `shouldBe` True
    it "still requires the artifact name to agree" $
      sameArtifactIdentity
        (RemoteOrigin "git@github.com:shinzui/seihou-modules.git" "git-init" Nothing)
        (RemoteOrigin reportedHttps "haskell-base" Nothing)
        `shouldBe` False
    it "keeps project and local origins unchanged" $ do
      sameArtifactIdentity (ProjectOrigin "./.seihou/modules/a/") (ProjectOrigin ".seihou/modules/a") `shouldBe` True
      sameArtifactIdentity (LocalOrigin "a") (LocalOrigin "a") `shouldBe` True
      sameArtifactIdentity (LocalOrigin "a") (RemoteOrigin "a" "a" Nothing) `shouldBe` False
  where
    indexed = zip [0 :: Int ..] equivalenceClasses

reportedHttps :: Text
reportedHttps = "https://github.com/shinzui/seihou-modules.git"

reportedClass :: [Text]
reportedClass = maybe [] id (lookup "public GitHub transports of one repository" equivalenceClasses)

-- | Each list is one repository; every member must equal every other member
-- and no member of any other list.
equivalenceClasses :: [(String, [Text])]
equivalenceClasses =
  [ ( "public GitHub transports of one repository",
      [ "git@github.com:shinzui/seihou-modules.git",
        reportedHttps,
        "https://github.com/shinzui/seihou-modules",
        "https://github.com/shinzui/seihou-modules/",
        "https://github.com/shinzui/seihou-modules.git/",
        "  https://github.com/shinzui/seihou-modules  ",
        "HTTPS://GitHub.COM/shinzui/seihou-modules",
        "https://github.com:443/shinzui/seihou-modules",
        "https://token@github.com/shinzui/seihou-modules.git",
        "ssh://git@github.com/shinzui/seihou-modules.git",
        "ssh://git@github.com:22/shinzui/seihou-modules",
        "ssh://git@ssh.github.com:443/shinzui/seihou-modules.git",
        "git@GitHub.com:shinzui/seihou-modules/"
      ]
    ),
    ( "a generic HTTPS repository with cosmetic spellings",
      [ "https://git.example/team/repo",
        "https://git.example/team/repo.git",
        "https://GIT.example:443/team/repo/"
      ]
    ),
    ( "a generic SSH URL with an explicit default port",
      [ "ssh://alice@git.example/srv/repo.git",
        "ssh://alice@git.example:22/srv/repo"
      ]
    ),
    ( "a generic relative scp path",
      ["alice@git.example:repo.git", "alice@GIT.EXAMPLE:repo/"]
    ),
    ( "a git-protocol URL with its default port",
      ["git://git.example/repo.git", "git://git.example:9418/repo"]
    ),
    ( "a bracketed IPv6 authority",
      ["ssh://git@[2001:db8::1]:2222/repo.git", "ssh://git@[2001:DB8::1]:2222/repo"]
    ),
    ( "an opaque local path",
      ["/srv/repos/modules", "/srv/repos/modules.git/"]
    )
  ]

-- | Pairs that must never compare equal, in either direction.
distinctPairs :: [(Text, Text)]
distinctPairs =
  [ ("git@github.com:other/seihou-modules.git", reportedHttps),
    ("git@github.com:shinzui/other.git", reportedHttps),
    ("https://github.com/Shinzui/seihou-modules", reportedHttps),
    ("git@git.example:shinzui/seihou-modules.git", "https://git.example/shinzui/seihou-modules"),
    ("http://github.com/shinzui/seihou-modules", reportedHttps),
    ("git://github.com/shinzui/seihou-modules.git", reportedHttps),
    ("https://github.com.evil.example/shinzui/seihou-modules.git", reportedHttps),
    ("https://github.com@evil.example/shinzui/seihou-modules.git", reportedHttps),
    ("https://www.github.com/shinzui/seihou-modules", reportedHttps),
    ("https://github.com:8443/shinzui/seihou-modules", reportedHttps),
    ("https://github.com:/shinzui/seihou-modules", reportedHttps),
    ("https://github.com:0/shinzui/seihou-modules", reportedHttps),
    ("https://github.com:65536/shinzui/seihou-modules", reportedHttps),
    ("https://github.com:4x3/shinzui/seihou-modules", reportedHttps),
    ("ssh://github.com/shinzui/seihou-modules.git", reportedHttps),
    ("ssh://alice@github.com/shinzui/seihou-modules.git", reportedHttps),
    ("ssh://git@github.com:2222/shinzui/seihou-modules.git", reportedHttps),
    ("ssh://git@ssh.github.com/shinzui/seihou-modules.git", reportedHttps),
    ("ssh://git@ssh.github.com:22/shinzui/seihou-modules.git", reportedHttps),
    ("alice@github.com:shinzui/seihou-modules.git", reportedHttps),
    ("github.com:shinzui/seihou-modules.git", reportedHttps),
    ("git@github.com:/shinzui/seihou-modules.git", reportedHttps),
    ("git@github.com:~/shinzui/seihou-modules.git", reportedHttps),
    ("https://github.com/shinzui/seihou-modules/.git", reportedHttps),
    ("https://github.com/shinzui/seihou-modules/extra", reportedHttps),
    ("https://github.com//shinzui/seihou-modules", reportedHttps),
    ("https://github.com/shinzui//seihou-modules", reportedHttps),
    ("https://github.com/shinzui/seihou-modules?", reportedHttps),
    ("https://github.com/shinzui/seihou-modules#", reportedHttps),
    ("https://github.com/shinzui/seihou-modules?ref=main", reportedHttps),
    ("https://github.com/shinzui/seihou%2Dmodules", reportedHttps),
    ("https://github.com/shinzui/seihou modules", reportedHttps),
    ("https://github.com/shinzui/..", "https://github.com/shinzui/."),
    ("https://github.com/owner/.git", "https://github.com/owner"),
    ("https:///shinzui/seihou-modules", reportedHttps),
    ("https://github.com", reportedHttps),
    ("seihou-modules", reportedHttps),
    ("ftp://github.com/shinzui/seihou-modules", reportedHttps),
    ("file:///srv/shinzui/seihou-modules", reportedHttps),
    ("/srv/shinzui/seihou-modules", "ssh://git@github.com/srv/shinzui/seihou-modules"),
    ("C:/src/seihou-modules", "c:/src/seihou-modules.git"),
    ("https://example.com/repo?ref=topic.git", "https://example.com/repo?ref=topic"),
    ("https://example.com/repo?", "https://example.com/repo"),
    ("https://example.com/repo#", "https://example.com/repo"),
    ("https://example.com/Repo", "https://example.com/repo"),
    ("https://example.com/repo/.git", "https://example.com/repo"),
    ("https://example.com/a%2Fb", "https://example.com/a/b"),
    ("https://example.com/a/./b", "https://example.com/a/b"),
    ("https://example.com/a//b", "https://example.com/a/b"),
    ("https://example.com:8443/repo", "https://example.com/repo"),
    ("https://alice@example.com/repo", "https://example.com/repo"),
    ("ssh://alice@git.example/repo", "ssh://bob@git.example/repo"),
    ("ssh://alice@git.example/repo", "ssh://git.example/repo"),
    ("ssh://alice@git.example:2222/repo", "ssh://alice@git.example:2223/repo"),
    ("ssh://alice@git.example/repo", "https://git.example/repo"),
    ("http://example.com/repo", "https://example.com/repo"),
    ("http://example.com:443/repo", "https://example.com/repo"),
    ("alice@git.example:repo", "ssh://alice@git.example/repo"),
    ("alice@git.example:/srv/repo", "ssh://alice@git.example/srv/repo"),
    ("alice@git.example:/srv/repo", "alice@git.example:srv/repo"),
    ("alice@git.example:repo", "bob@git.example:repo"),
    ("alice@git.example:repo", "git.example:repo"),
    ("alice@git.example:repo", "https://git.example/repo"),
    ("ssh://git@[2001:db8::1]/repo", "ssh://git@[2001:db8::2]/repo"),
    ("ssh://git@[2001:db8::1/repo", "ssh://git@[2001:db8::1]/repo"),
    ("svn+ssh://git.example/repo", "ssh://git.example/repo"),
    ("unknown://github.com/shinzui/seihou-modules", reportedHttps)
  ]
