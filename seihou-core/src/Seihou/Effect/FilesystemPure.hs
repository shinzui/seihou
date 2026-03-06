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
  { pureFiles :: Map FilePath Text,
    pureDirs :: Set FilePath
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
        fs <- get
        case Map.lookup path (pureFiles fs) of
          Just content -> pure content
          Nothing -> error ("runFilesystemPure: file not found: " <> path)
      WriteFileText path content -> do
        modify (\fs -> fs {pureFiles = Map.insert path content (pureFiles fs)})
      CopyFile src dest -> do
        fs <- get
        case Map.lookup src (pureFiles fs) of
          Just content ->
            put fs {pureFiles = Map.insert dest content (pureFiles fs)}
          Nothing -> error ("runFilesystemPure: source file not found: " <> src)
      ListDirectory path -> do
        fs <- get
        let prefix = if null path then "" else path <> "/"
            filesInDir =
              [ drop (length prefix) fp
              | fp <- Map.keys (pureFiles fs),
                isDirectChild prefix fp
              ]
            dirsInDir =
              [ drop (length prefix) d
              | d <- Set.toList (pureDirs fs),
                isDirectChild prefix d
              ]
        pure (filesInDir <> dirsInDir)
      CreateDirectoryIfMissing _parents path -> do
        modify (\fs -> fs {pureDirs = Set.insert path (pureDirs fs)})
      DoesFileExist path -> do
        fs <- get
        pure (Map.member path (pureFiles fs))
      DoesDirectoryExist path -> do
        fs <- get
        pure (Set.member path (pureDirs fs))
      GetCurrentDirectory -> pure "/pure-fs"

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
