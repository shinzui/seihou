module Seihou.CLI.Context
  ( handleContext,
  )
where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Seihou.CLI.Commands (ContextAction (..))
import Seihou.Core.Context (resolveContext, validateContextName)
import Seihou.Effect.Fzf (selectOne)
import Seihou.Effect.FzfInterp (runFzfIO)
import Seihou.Fzf (Candidate (..), FzfResult (..), detectFzfConfig, isFzfUsable, withAnsi, withHeight, withNoSort, withPrompt)
import Seihou.Fzf qualified
import Seihou.Prelude
import System.Directory
  ( XdgDirectory (..),
    createDirectoryIfMissing,
    doesDirectoryExist,
    doesFileExist,
    getCurrentDirectory,
    getXdgDirectory,
    listDirectory,
    removeFile,
  )
import System.Environment (getEnvironment)
import System.Exit (ExitCode (..), exitFailure, exitWith)

handleContext :: ContextAction -> IO ()
handleContext ContextShow = showContext
handleContext (ContextSet mName) = do
  name <- case mName of
    Just n -> pure n
    Nothing -> do
      fzfCfg <- detectFzfConfig
      if isFzfUsable fzfCfg
        then do
          result <- selectContextFzf fzfCfg
          case result of
            FzfSelected n -> pure n
            FzfCancelled -> exitWith ExitSuccess
            FzfNoMatch -> do
              TIO.putStrLn "No contexts found."
              exitFailure
            FzfError err -> do
              TIO.putStrLn $ "fzf error: " <> err
              exitFailure
        else do
          TIO.putStrLn "NAME argument is required when fzf is not available."
          exitFailure
  setProjectContext name
handleContext (ContextDefault name) = setGlobalDefault name
handleContext ContextClear = clearProjectContext
handleContext ContextClearDefault = clearGlobalDefault

-- | Select a context via fzf from available context directories.
selectContextFzf :: Seihou.Fzf.FzfConfig -> IO (FzfResult Text)
selectContextFzf fzfCfg = do
  base <- getXdgDirectory XdgConfig "seihou"
  let contextsDir = base </> "contexts"
  exists <- doesDirectoryExist contextsDir
  if not exists
    then pure FzfNoMatch
    else do
      entries <- listDirectory contextsDir
      dirs <- filterM (doesDirectoryExist . (contextsDir </>)) entries
      let candidates = [Candidate {candidateDisplay = T.pack d, candidateValue = T.pack d} | d <- dirs]
          opts = withPrompt "context> " <> withHeight "40%" <> withAnsi <> withNoSort
      runEff $ runFzfIO fzfCfg $ selectOne opts candidates
  where
    filterM _ [] = pure []
    filterM p (x : xs) = do
      b <- p x
      rest <- filterM p xs
      if b then pure (x : rest) else pure rest

showContext :: IO ()
showContext = do
  envPairs <- getEnvironment
  let envVars = Map.fromList [(T.pack k, T.pack v) | (k, v) <- envPairs]
  result <- resolveContext Nothing envVars
  case result of
    Nothing -> TIO.putStrLn "No active context."
    Just ctx -> do
      TIO.putStrLn $ "Active context: " <> ctx
      -- Show where it came from
      case Map.lookup "SEIHOU_CONTEXT" envVars of
        Just _ -> TIO.putStrLn "  Source: SEIHOU_CONTEXT environment variable"
        Nothing -> do
          cwd <- getCurrentDirectory
          let projectFile = cwd </> ".seihou" </> "context"
          projectExists <- doesFileExist projectFile
          if projectExists
            then TIO.putStrLn "  Source: .seihou/context (project)"
            else do
              base <- getXdgDirectory XdgConfig "seihou"
              let defaultFile = base </> "default-context"
              defaultExists <- doesFileExist defaultFile
              if defaultExists
                then TIO.putStrLn $ "  Source: " <> T.pack defaultFile <> " (global default)"
                else TIO.putStrLn "  Source: unknown"

setProjectContext :: Text -> IO ()
setProjectContext name = do
  case validateContextName name of
    Just err -> do
      TIO.putStrLn $ "Invalid context name: " <> err
      exitFailure
    Nothing -> do
      cwd <- getCurrentDirectory
      let dir = cwd </> ".seihou"
          path = dir </> "context"
      createDirectoryIfMissing True dir
      TIO.writeFile path (name <> "\n")
      TIO.putStrLn $ "Set project context to: " <> name

setGlobalDefault :: Text -> IO ()
setGlobalDefault name = do
  case validateContextName name of
    Just err -> do
      TIO.putStrLn $ "Invalid context name: " <> err
      exitFailure
    Nothing -> do
      base <- getXdgDirectory XdgConfig "seihou"
      createDirectoryIfMissing True base
      let path = base </> "default-context"
      TIO.writeFile path (name <> "\n")
      TIO.putStrLn $ "Set global default context to: " <> name

clearProjectContext :: IO ()
clearProjectContext = do
  cwd <- getCurrentDirectory
  let path = cwd </> ".seihou" </> "context"
  exists <- doesFileExist path
  if exists
    then do
      removeFile path
      TIO.putStrLn "Removed project context."
    else TIO.putStrLn "No project context set."

clearGlobalDefault :: IO ()
clearGlobalDefault = do
  base <- getXdgDirectory XdgConfig "seihou"
  let path = base </> "default-context"
  exists <- doesFileExist path
  if exists
    then do
      removeFile path
      TIO.putStrLn "Removed global default context."
    else TIO.putStrLn "No global default context set."
