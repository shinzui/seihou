{-# LANGUAGE DeriveAnyClass #-}

module Seihou.CLI.Kit
  ( KitCommand (..),
    KitInstallOpts (..),
    KitUpdateOpts (..),
    KitUninstallOpts (..),
    runKit,
    kitCommandParser,
  )
where

import Control.Exception (IOException, try)
import Control.Monad (forM, unless, when)
import Data.Aeson (FromJSON, eitherDecodeFileStrict')
import Data.List (isPrefixOf, isSuffixOf)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import GHC.Generics (Generic)
import Options.Applicative
import Seihou.Prelude
import System.Directory
  ( copyFile,
    createDirectoryIfMissing,
    doesDirectoryExist,
    doesFileExist,
    getCurrentDirectory,
    getHomeDirectory,
    listDirectory,
    removeDirectoryRecursive,
    removeFile,
  )
import System.Exit (ExitCode (..), exitFailure)
import System.FilePath (takeFileName, (</>))
import System.IO (hPutStrLn, stderr)
import System.Process (readProcessWithExitCode)

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

-- | Kit subcommands
data KitCommand
  = KitList
  | KitInstall !KitInstallOpts
  | KitUpdate !KitUpdateOpts
  | KitUninstall !KitUninstallOpts
  | KitStatus
  deriving stock (Eq, Show, Generic)

data KitInstallOpts = KitInstallOpts
  { kitItemName :: !Text,
    kitProjectScope :: !Bool
  }
  deriving stock (Eq, Show, Generic)

data KitUpdateOpts = KitUpdateOpts
  { kitUpdateName :: !(Maybe Text)
  }
  deriving stock (Eq, Show, Generic)

data KitUninstallOpts = KitUninstallOpts
  { kitUninstallName :: !Text,
    kitUninstallProjectScope :: !Bool
  }
  deriving stock (Eq, Show, Generic)

data KitScope
  = UserScope
  | ProjectScope
  deriving stock (Show)

--------------------------------------------------------------------------------
-- Manifest types
--------------------------------------------------------------------------------

data KitManifest = KitManifest
  { version :: !Int,
    skills :: ![SkillEntry],
    agents :: ![AgentEntry]
  }
  deriving stock (Generic, Show)
  deriving anyclass (FromJSON)

data SkillEntry = SkillEntry
  { name :: !Text,
    description :: !Text,
    path :: !Text,
    files :: ![Text]
  }
  deriving stock (Generic, Show)
  deriving anyclass (FromJSON)

data AgentEntry = AgentEntry
  { name :: !Text,
    description :: !Text,
    path :: !Text
  }
  deriving stock (Generic, Show)
  deriving anyclass (FromJSON)

-- | Resolved item from manifest
data KitItem
  = KitSkillItem !SkillEntry
  | KitAgentItem !AgentEntry

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

defaultKitRepoUrl :: String
defaultKitRepoUrl = "https://github.com/shinzui/seihou-kit.git"

--------------------------------------------------------------------------------
-- Parsers
--------------------------------------------------------------------------------

-- | Parser for kit subcommands
kitCommandParser :: Parser KitCommand
kitCommandParser =
  hsubparser
    ( command "list" (info (pure KitList) (progDesc "List available skills and subagents"))
        <> command "install" (info installParser (progDesc "Install a skill or subagent"))
        <> command "update" (info updateParser (progDesc "Update installed skills and subagents"))
        <> command "uninstall" (info uninstallParser (progDesc "Uninstall a skill or subagent"))
        <> command "status" (info (pure KitStatus) (progDesc "Show installed skills and subagents"))
    )
    <|> pure KitList -- default to list when no subcommand given

installParser :: Parser KitCommand
installParser =
  KitInstall
    <$> ( KitInstallOpts
            <$> strArgument (metavar "NAME" <> help "Name of the skill or subagent to install")
            <*> switch (long "project" <> help "Install to project scope (.seihou/agents/) instead of user scope")
        )

updateParser :: Parser KitCommand
updateParser =
  KitUpdate
    <$> ( KitUpdateOpts
            <$> optional (strArgument (metavar "NAME" <> help "Name of a specific item to update (default: all)"))
        )

uninstallParser :: Parser KitCommand
uninstallParser =
  KitUninstall
    <$> ( KitUninstallOpts
            <$> strArgument (metavar "NAME" <> help "Name of the skill or subagent to uninstall")
            <*> switch (long "project" <> help "Uninstall from project scope (.seihou/agents/) instead of user scope")
        )

--------------------------------------------------------------------------------
-- Command dispatch
--------------------------------------------------------------------------------

-- | Run a kit command
runKit :: KitCommand -> IO ()
runKit = \case
  KitList -> listAvailable
  KitInstall opts -> installItem opts.kitItemName (scopeFromBool opts.kitProjectScope)
  KitUpdate opts -> updateKit opts.kitUpdateName
  KitUninstall opts -> uninstallItem opts.kitUninstallName (scopeFromBool opts.kitUninstallProjectScope)
  KitStatus -> kitStatus

scopeFromBool :: Bool -> KitScope
scopeFromBool True = ProjectScope
scopeFromBool False = UserScope

--------------------------------------------------------------------------------
-- kit list
--------------------------------------------------------------------------------

listAvailable :: IO ()
listAvailable = do
  repoDir <- ensureKitRepo
  manifest <- loadManifest repoDir
  let sk = manifest.skills
      ag = manifest.agents
  if null sk && null ag
    then TIO.putStrLn "No items available in the kit."
    else do
      unless (null sk) $ do
        TIO.putStrLn "Skills:"
        let maxLen = maximum $ map (T.length . skillName) sk
        mapM_ (printEntry maxLen . skillNameDesc) sk
      unless (null ag) $ do
        unless (null sk) (TIO.putStrLn "")
        TIO.putStrLn "Agents:"
        let maxLen = maximum $ map (T.length . agentNameOf) ag
        mapM_ (printEntry maxLen . agentNameDesc) ag
  where
    printEntry maxLen (n, desc) =
      TIO.putStrLn $ "  " <> T.justifyLeft (maxLen + 2) ' ' n <> desc

--------------------------------------------------------------------------------
-- kit install
--------------------------------------------------------------------------------

installItem :: Text -> KitScope -> IO ()
installItem itemN scope = do
  repoDir <- ensureKitRepo
  manifest <- loadManifest repoDir
  case lookupItem itemN manifest of
    Nothing -> do
      hPutStrLn stderr $ "Error: '" <> T.unpack itemN <> "' not found in kit manifest."
      exitFailure
    Just item -> do
      doInstall repoDir item scope
      let typeLabel = case item of
            KitSkillItem {} -> "skill"
            KitAgentItem {} -> "agent" :: Text
      targetBase <- resolveTargetDir scope
      TIO.putStrLn $
        "Installed " <> typeLabel <> " '" <> itemN <> "' to " <> T.pack targetBase

doInstall :: FilePath -> KitItem -> KitScope -> IO ()
doInstall repoDir (KitSkillItem entry) scope = do
  targetBase <- resolveTargetDir scope
  let targetDir = targetBase </> ".claude" </> "skills" </> T.unpack (skillName entry)
  createDirectoryIfMissing True targetDir
  mapM_ (copySkillFile repoDir entry targetDir) entry.files
doInstall repoDir (KitAgentItem entry) scope = do
  targetBase <- resolveTargetDir scope
  let agentDir = targetBase </> ".claude" </> "agents"
      srcFile = repoDir </> T.unpack (agentPathOf entry)
      dstFile = agentDir </> takeFileName (T.unpack (agentPathOf entry))
  createDirectoryIfMissing True agentDir
  copyFile srcFile dstFile

copySkillFile :: FilePath -> SkillEntry -> FilePath -> Text -> IO ()
copySkillFile repoDir entry targetDir fileName =
  let src = repoDir </> T.unpack (skillPathOf entry) </> T.unpack fileName
      dst = targetDir </> T.unpack fileName
   in copyFile src dst

--------------------------------------------------------------------------------
-- kit update
--------------------------------------------------------------------------------

updateKit :: Maybe Text -> IO ()
updateKit mName = do
  cacheDir <- kitCacheDir
  exists <- doesDirectoryExist cacheDir
  if exists
    then do
      pullKitRepo cacheDir
      TIO.putStrLn "Kit repository updated."
    else do
      _ <- ensureKitRepo
      TIO.putStrLn "Kit repository cloned."
  manifest <- loadManifest =<< kitCacheDir
  case mName of
    Just n -> do
      reinstallIfPresent n UserScope manifest
      reinstallIfPresent n ProjectScope manifest
    Nothing ->
      reinstallAllPresent manifest

reinstallIfPresent :: Text -> KitScope -> KitManifest -> IO ()
reinstallIfPresent n scope manifest = do
  installed <- isInstalled n scope
  when installed $
    case lookupItem n manifest of
      Nothing -> pure ()
      Just item -> do
        repoDir <- kitCacheDir
        doInstall repoDir item scope
        TIO.putStrLn $ "Updated '" <> n <> "' (" <> scopeLabel scope <> ")"

reinstallAllPresent :: KitManifest -> IO ()
reinstallAllPresent manifest = do
  let allNames =
        map skillName manifest.skills
          ++ map agentNameOf manifest.agents
  repoDir <- kitCacheDir
  updated <- fmap sum $ forM allNames $ \n -> do
    userInstalled <- isInstalled n UserScope
    projectInstalled <- isInstalled n ProjectScope
    let count = (if userInstalled then 1 else 0) + (if projectInstalled then 1 else 0) :: Int
    when userInstalled $
      case lookupItem n manifest of
        Nothing -> pure ()
        Just item -> doInstall repoDir item UserScope
    when projectInstalled $
      case lookupItem n manifest of
        Nothing -> pure ()
        Just item -> doInstall repoDir item ProjectScope
    pure count
  TIO.putStrLn $ "Updated " <> T.pack (show updated) <> " item(s)."

--------------------------------------------------------------------------------
-- kit uninstall
--------------------------------------------------------------------------------

uninstallItem :: Text -> KitScope -> IO ()
uninstallItem n scope = do
  targetBase <- resolveTargetDir scope
  let skillDir = targetBase </> ".claude" </> "skills" </> T.unpack n
      agentFile = targetBase </> ".claude" </> "agents" </> T.unpack n <> ".md"
  skillExists <- doesDirectoryExist skillDir
  agentExists <- doesFileExist agentFile
  case (skillExists, agentExists) of
    (True, _) -> do
      removeDirectoryRecursive skillDir
      TIO.putStrLn $ "Uninstalled skill '" <> n <> "' from " <> scopeLabel scope <> " scope."
    (_, True) -> do
      removeFile agentFile
      TIO.putStrLn $ "Uninstalled agent '" <> n <> "' from " <> scopeLabel scope <> " scope."
    _ ->
      TIO.putStrLn $ "'" <> n <> "' is not installed in " <> scopeLabel scope <> " scope."

--------------------------------------------------------------------------------
-- kit status
--------------------------------------------------------------------------------

kitStatus :: IO ()
kitStatus = do
  userDir <- resolveTargetDir UserScope
  projectDir <- resolveTargetDir ProjectScope
  userItems <- scanInstalled userDir
  projectItems <- scanInstalled projectDir
  let allItems =
        map (\(n, t) -> (n, t, "user" :: Text)) userItems
          ++ map (\(n, t) -> (n, t, "project" :: Text)) projectItems
  if null allItems
    then TIO.putStrLn "No kit items installed."
    else do
      let nameW = max 4 $ maximum $ map (\(n, _, _) -> T.length n) allItems
          typeW = max 4 $ maximum $ map (\(_, t, _) -> T.length t) allItems
          hdr =
            T.justifyLeft (nameW + 2) ' ' "NAME"
              <> T.justifyLeft (typeW + 2) ' ' "TYPE"
              <> "SCOPE"
      TIO.putStrLn hdr
      mapM_ (printStatusRow nameW typeW) allItems

printStatusRow :: Int -> Int -> (Text, Text, Text) -> IO ()
printStatusRow nameW typeW (n, t, s) =
  TIO.putStrLn $
    T.justifyLeft (nameW + 2) ' ' n
      <> T.justifyLeft (typeW + 2) ' ' t
      <> s

scanInstalled :: FilePath -> IO [(Text, Text)]
scanInstalled baseDir = do
  skillItems <- scanSkills (baseDir </> ".claude" </> "skills")
  agentItems <- scanAgents (baseDir </> ".claude" </> "agents")
  pure (skillItems ++ agentItems)

scanSkills :: FilePath -> IO [(Text, Text)]
scanSkills dir = do
  exists <- doesDirectoryExist dir
  if exists
    then do
      entries <- listDirectory dir
      pure $ map (\e -> (T.pack e, "skill")) $ filter (not . ("." `isPrefixOf`)) entries
    else pure []

scanAgents :: FilePath -> IO [(Text, Text)]
scanAgents dir = do
  exists <- doesDirectoryExist dir
  if exists
    then do
      entries <- listDirectory dir
      let mdFiles = filter (\f -> ".md" `isSuffixOf` f && not ("." `isPrefixOf` f)) entries
      pure $ map (\f -> (T.pack (take (length f - 3) f), "agent")) mdFiles
    else pure []

--------------------------------------------------------------------------------
-- Git operations
--------------------------------------------------------------------------------

-- | Ensure the seihou-kit repo is cloned locally. Returns the cache directory path.
ensureKitRepo :: IO FilePath
ensureKitRepo = do
  cacheDir <- kitCacheDir
  exists <- doesDirectoryExist (cacheDir </> ".git")
  if exists
    then do
      pullKitRepo cacheDir
      pure cacheDir
    else do
      TIO.putStrLn "Fetching seihou-kit..."
      createDirectoryIfMissing True cacheDir
      (exitCode, _, errOut) <-
        readProcessWithExitCode
          "git"
          ["clone", "--depth", "1", defaultKitRepoUrl, cacheDir]
          ""
      case exitCode of
        ExitSuccess -> pure cacheDir
        ExitFailure _ -> do
          manifestExists <- doesFileExist (cacheDir </> "kit.json")
          if manifestExists
            then do
              hPutStrLn stderr $ "Warning: git clone failed, using cached data. " <> errOut
              pure cacheDir
            else do
              hPutStrLn stderr $ "Error: Failed to fetch seihou-kit: " <> errOut
              exitFailure

pullKitRepo :: FilePath -> IO ()
pullKitRepo cacheDir = do
  result <-
    try @IOException $
      readProcessWithExitCode "git" ["-C", cacheDir, "pull", "--ff-only", "--quiet"] ""
  case result of
    Right (ExitSuccess, _, _) -> pure ()
    Right (ExitFailure _, _, errOut) ->
      hPutStrLn stderr $ "Warning: git pull failed, using cached data. " <> errOut
    Left e ->
      hPutStrLn stderr $ "Warning: git pull failed: " <> show e

--------------------------------------------------------------------------------
-- Manifest operations
--------------------------------------------------------------------------------

loadManifest :: FilePath -> IO KitManifest
loadManifest repoDir = do
  let manifestPath = repoDir </> "kit.json"
  exists <- doesFileExist manifestPath
  unless exists $ do
    hPutStrLn stderr "Error: kit.json not found in seihou-kit repository."
    exitFailure
  result <- eitherDecodeFileStrict' manifestPath
  case result of
    Left err -> do
      hPutStrLn stderr $ "Error: Failed to parse kit.json: " <> err
      exitFailure
    Right m -> pure m

lookupItem :: Text -> KitManifest -> Maybe KitItem
lookupItem n manifest =
  case filter (\e -> skillName e == n) manifest.skills of
    (s : _) -> Just (KitSkillItem s)
    [] -> case filter (\e -> agentNameOf e == n) manifest.agents of
      (a : _) -> Just (KitAgentItem a)
      [] -> Nothing

--------------------------------------------------------------------------------
-- Directory helpers
--------------------------------------------------------------------------------

kitCacheDir :: IO FilePath
kitCacheDir = do
  home <- getHomeDirectory
  pure (home </> ".cache" </> "seihou" </> "kit")

resolveTargetDir :: KitScope -> IO FilePath
resolveTargetDir UserScope = do
  home <- getHomeDirectory
  pure (home </> ".config" </> "seihou" </> "agents")
resolveTargetDir ProjectScope = do
  cwd <- getCurrentDirectory
  pure (cwd </> ".seihou" </> "agents")

scopeLabel :: KitScope -> Text
scopeLabel UserScope = "user"
scopeLabel ProjectScope = "project"

isInstalled :: Text -> KitScope -> IO Bool
isInstalled n scope = do
  targetBase <- resolveTargetDir scope
  let skillDir = targetBase </> ".claude" </> "skills" </> T.unpack n
      agentFile = targetBase </> ".claude" </> "agents" </> T.unpack n <> ".md"
  skillExists <- doesDirectoryExist skillDir
  agentExists <- doesFileExist agentFile
  pure (skillExists || agentExists)

--------------------------------------------------------------------------------
-- Record field accessors (avoid DuplicateRecordFields ambiguity)
--------------------------------------------------------------------------------

skillName :: SkillEntry -> Text
skillName (SkillEntry n _ _ _) = n

skillDesc :: SkillEntry -> Text
skillDesc (SkillEntry _ d _ _) = d

skillPathOf :: SkillEntry -> Text
skillPathOf (SkillEntry _ _ p _) = p

agentNameOf :: AgentEntry -> Text
agentNameOf (AgentEntry n _ _) = n

agentDescOf :: AgentEntry -> Text
agentDescOf (AgentEntry _ d _) = d

agentPathOf :: AgentEntry -> Text
agentPathOf (AgentEntry _ _ p) = p

skillNameDesc :: SkillEntry -> (Text, Text)
skillNameDesc e = (skillName e, skillDesc e)

agentNameDesc :: AgentEntry -> (Text, Text)
agentNameDesc e = (agentNameOf e, agentDescOf e)
