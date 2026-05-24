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
import Control.Monad (forM, forM_, unless, when)
import Data.Aeson (FromJSON, eitherDecodeFileStrict')
import Data.List (groupBy, nub, sortOn)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import GHC.Generics (Generic)
import Options.Applicative
import Seihou.CLI.KitPaths
import Seihou.Prelude
import System.Directory
  ( copyFile,
    createDirectoryIfMissing,
    doesDirectoryExist,
    doesFileExist,
    getCurrentDirectory,
    getHomeDirectory,
    removeDirectoryRecursive,
    removeFile,
  )
import System.Exit (ExitCode (..), exitFailure)
import System.FilePath (takeDirectory, (</>))
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
      TIO.putStrLn $
        "Installed "
          <> typeLabel
          <> " '"
          <> itemN
          <> "' for Claude Code and Codex ("
          <> scopeLabel scope
          <> " scope)."

doInstall :: FilePath -> KitItem -> KitScope -> IO ()
doInstall repoDir (KitSkillItem entry) scope = do
  forM_ allKitProviderLayouts $ \layout -> do
    targetBase <- resolveProviderTargetDir layout scope
    let targetDir = skillTargetDir layout targetBase (skillName entry)
    createDirectoryIfMissing True targetDir
    mapM_ (copySkillFile repoDir entry targetDir) entry.files
doInstall repoDir (KitAgentItem entry) scope = do
  let srcFile = repoDir </> T.unpack (agentPathOf entry)
  forM_ allKitProviderLayouts $ \layout -> do
    targetBase <- resolveProviderTargetDir layout scope
    let dstFile = agentTargetFile layout targetBase (agentNameOf entry)
    createDirectoryIfMissing True (takeDirectory dstFile)
    case layout of
      ClaudeLayout -> copyFile srcFile dstFile
      CodexLayout -> do
        body <- TIO.readFile srcFile
        TIO.writeFile dstFile (codexAgentToml (agentNameOf entry) (agentDescOf entry) body)

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
  removed <- fmap concat $
    forM allKitProviderLayouts $ \layout -> do
      targetBase <- resolveProviderTargetDir layout scope
      let skillDir = skillTargetDir layout targetBase n
          agentFile = agentTargetFile layout targetBase n
      skillExists <- doesDirectoryExist skillDir
      agentExists <- doesFileExist agentFile
      when skillExists (removeDirectoryRecursive skillDir)
      when agentExists (removeFile agentFile)
      pure $
        (if skillExists then [providerLabel layout <> " skill"] else [])
          ++ (if agentExists then [providerLabel layout <> " agent"] else [])
  if null removed
    then TIO.putStrLn $ "'" <> n <> "' is not installed in " <> scopeLabel scope <> " scope."
    else
      TIO.putStrLn $
        "Uninstalled '"
          <> n
          <> "' from "
          <> scopeLabel scope
          <> " scope ("
          <> T.intercalate ", " removed
          <> ")."

--------------------------------------------------------------------------------
-- kit status
--------------------------------------------------------------------------------

kitStatus :: IO ()
kitStatus = do
  userItems <- scanInstalled UserScope
  projectItems <- scanInstalled ProjectScope
  let allItems = aggregateInstalled (userItems ++ projectItems)
  if null allItems
    then TIO.putStrLn "No kit items installed."
    else do
      let nameW = max 4 $ maximum $ map (\(n, _, _, _) -> T.length n) allItems
          typeW = max 4 $ maximum $ map (\(_, t, _, _) -> T.length t) allItems
          scopeW = max 5 $ maximum $ map (\(_, _, s, _) -> T.length s) allItems
          hdr =
            T.justifyLeft (nameW + 2) ' ' "NAME"
              <> T.justifyLeft (typeW + 2) ' ' "TYPE"
              <> T.justifyLeft (scopeW + 2) ' ' "SCOPE"
              <> "PROVIDERS"
      TIO.putStrLn hdr
      mapM_ (printStatusRow nameW typeW scopeW) allItems

printStatusRow :: Int -> Int -> Int -> (Text, Text, Text, Text) -> IO ()
printStatusRow nameW typeW scopeW (n, t, s, providers) =
  TIO.putStrLn $
    T.justifyLeft (nameW + 2) ' ' n
      <> T.justifyLeft (typeW + 2) ' ' t
      <> T.justifyLeft (scopeW + 2) ' ' s
      <> providers

scanInstalled :: KitScope -> IO [(Text, Text, Text, Text)]
scanInstalled scope = fmap concat $
  forM allKitProviderLayouts $ \layout -> do
    targetBase <- resolveProviderTargetDir layout scope
    items <- scanInstalledForProvider layout targetBase
    pure $
      map
        ( \item ->
            ( item.installedName,
              item.installedType,
              scopeLabel scope,
              item.installedProvider
            )
        )
        items

aggregateInstalled :: [(Text, Text, Text, Text)] -> [(Text, Text, Text, Text)]
aggregateInstalled rows =
  map summarize grouped
  where
    sorted = sortOn (\(n, t, s, p) -> (n, t, s, p)) rows
    grouped = groupBy sameItem sorted
    sameItem (n1, t1, s1, _) (n2, t2, s2, _) =
      n1 == n2 && t1 == t2 && s1 == s2
    summarize groupRows@((n, t, s, _) : _) =
      (n, t, s, T.intercalate "," (nub (map fourth groupRows)))
    summarize [] = error "aggregateInstalled: empty group"
    fourth (_, _, _, p) = p

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

resolveProviderTargetDir :: KitProviderLayout -> KitScope -> IO FilePath
resolveProviderTargetDir ClaudeLayout scope = resolveTargetDir scope
resolveProviderTargetDir CodexLayout UserScope = getHomeDirectory
resolveProviderTargetDir CodexLayout ProjectScope = getCurrentDirectory

scopeLabel :: KitScope -> Text
scopeLabel UserScope = "user"
scopeLabel ProjectScope = "project"

isInstalled :: Text -> KitScope -> IO Bool
isInstalled n scope = do
  or <$> forM allKitProviderLayouts isInstalledForProvider
  where
    isInstalledForProvider layout = do
      targetBase <- resolveProviderTargetDir layout scope
      skillExists <- doesDirectoryExist (skillTargetDir layout targetBase n)
      agentExists <- doesFileExist (agentTargetFile layout targetBase n)
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
