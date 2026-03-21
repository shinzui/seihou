module Seihou.Effect.FilesystemPure
  ( runFilesystemPure,
    PureFS (..),
    emptyFS,
  )
where

import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Effectful.State.Static.Local (State, get, modify, put, runState)
import Seihou.Effect.Filesystem (Filesystem (..))
import Seihou.Prelude

-- | In-memory filesystem state for testing.
data PureFS = PureFS
  { files :: Map FilePath Text,
    dirs :: Set FilePath
  }
  deriving stock (Eq, Show)

-- | An empty in-memory filesystem.
emptyFS :: PureFS
emptyFS = PureFS Map.empty Set.empty

-- | Pure in-memory interpreter for the Filesystem effect.
-- Useful for testing without touching the real filesystem.
runFilesystemPure :: PureFS -> Eff (Filesystem : es) a -> Eff es (a, PureFS)
runFilesystemPure initial = reinterpret (runState initial) handler
  where
    handler :: (State PureFS :> es') => EffectHandler Filesystem es'
    handler _ = \case
      ReadFileText path -> do
        fs <- get @PureFS
        case Map.lookup path fs.files of
          Just content -> pure content
          Nothing -> error ("runFilesystemPure: file not found: " <> path)
      WriteFileText path content -> do
        modify @PureFS (\fs -> fs {files = Map.insert path content fs.files})
      CopyFile src dest -> do
        fs <- get @PureFS
        case Map.lookup src fs.files of
          Just content ->
            put fs {files = Map.insert dest content fs.files}
          Nothing -> error ("runFilesystemPure: source file not found: " <> src)
      ListDirectory path -> do
        fs <- get @PureFS
        let prefix = if null path then "" else path <> "/"
            filesInDir =
              [ drop (length prefix) fp
              | fp <- Map.keys fs.files,
                isDirectChild prefix fp
              ]
            dirsInDir =
              [ drop (length prefix) d
              | d <- Set.toList fs.dirs,
                isDirectChild prefix d
              ]
        pure (filesInDir <> dirsInDir)
      CreateDirectoryIfMissing _parents path -> do
        modify @PureFS (\fs -> fs {dirs = Set.insert path fs.dirs})
      DoesFileExist path -> do
        fs <- get @PureFS
        pure (Map.member path fs.files)
      DoesDirectoryExist path -> do
        fs <- get @PureFS
        pure (Set.member path fs.dirs)
      GetCurrentDirectory -> pure "/pure-fs"
      RemoveFile path -> do
        modify @PureFS (\fs -> fs {files = Map.delete path fs.files})
      RemoveDirectoryIfEmpty path -> do
        fs <- get @PureFS
        let hasChildren =
              any (\fp -> (path <> "/") `isPrefixOfPath` fp) (Map.keys fs.files)
                || any (\d -> (path <> "/") `isPrefixOfPath` d) (Set.toList fs.dirs)
        if hasChildren
          then pure ()
          else modify @PureFS (\fs' -> fs' {dirs = Set.delete path fs'.dirs})

-- | Check if a path is a direct child of a prefix directory.
isDirectChild :: String -> String -> Bool
isDirectChild "" fp = '/' `notElem` fp
isDirectChild prefix fp =
  prefix `isPrefixOfPath` fp
    && '/' `notElem` drop (length prefix) fp

isPrefixOfPath :: String -> String -> Bool
isPrefixOfPath [] _ = True
isPrefixOfPath _ [] = False
isPrefixOfPath (x : xs) (y : ys)
  | x == y = isPrefixOfPath xs ys
  | otherwise = False
