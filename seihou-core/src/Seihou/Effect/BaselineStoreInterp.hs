module Seihou.Effect.BaselineStoreInterp
  ( runBaselineStore,
  )
where

import Control.Monad (filterM, unless, when)
import Data.Maybe (mapMaybe)
import Data.Set qualified as Set
import Data.Text qualified as T
import Seihou.Core.Types (BaselineRef (..), SHA256 (..))
import Seihou.Effect.BaselineStore (BaselineError (..), BaselineStore (..))
import Seihou.Effect.Filesystem
import Seihou.Manifest.Hash (baselineRefForContent, baselineRefFromText, hashContent)
import Seihou.Prelude

-- | Interpret baseline operations under the supplied baseline directory, such
-- as @.seihou/baselines@. The interpreter validates every reference before
-- deriving a path, even though normal references come from the manifest
-- decoder or 'baselineRefForContent'.
runBaselineStore ::
  (Filesystem :> es) =>
  FilePath ->
  Eff (BaselineStore : es) a ->
  Eff es a
runBaselineStore baselineDir = interpret $ \_ -> \case
  PutBaseline content -> do
    let ref = baselineRefForContent content
        finalPath = checkedBaselinePath baselineDir ref
        tempPath = finalPath <> ".tmp"
    createDirectoryIfMissing True baselineDir
    tempExists <- doesFileExist tempPath
    when tempExists (removeFile tempPath)
    finalExists <- doesFileExist finalPath
    reusable <-
      if finalExists
        then ((== ref.unBaselineRef) . hashContent) <$> readFileText finalPath
        else pure False
    unless reusable $ do
      writeFileText tempPath content
      when finalExists (removeFile finalPath)
      renamePath tempPath finalPath
    pure ref
  ReadBaseline ref -> do
    case baselinePath baselineDir ref of
      Nothing -> pure (Left (BaselineStoreFailure "invalid baseline reference"))
      Just path -> do
        exists <- doesFileExist path
        if not exists
          then pure (Left (BaselineMissing ref))
          else do
            content <- readFileText path
            let actual = hashContent content
            if actual == ref.unBaselineRef
              then pure (Right content)
              else pure (Left (BaselineCorrupt ref actual))
  PruneBaselines referenced -> do
    exists <- doesDirectoryExist baselineDir
    if not exists
      then pure []
      else do
        entries <- listDirectory baselineDir
        let candidates = mapMaybe (baselineRefFromText . T.pack) entries
        removable <- filterM (isValidUnreferenced referenced) candidates
        mapM_ (removeFile . checkedBaselinePath baselineDir) removable
        pure removable
  where
    isValidUnreferenced referenced ref
      | Set.member ref referenced = pure False
      | otherwise = do
          let path = checkedBaselinePath baselineDir ref
          isFile <- doesFileExist path
          if not isFile
            then pure False
            else ((== ref.unBaselineRef) . hashContent) <$> readFileText path

baselinePath :: FilePath -> BaselineRef -> Maybe FilePath
baselinePath root ref = do
  normalized <- baselineRefFromText ref.unBaselineRef.unSHA256
  pure (root </> T.unpack normalized.unBaselineRef.unSHA256)

checkedBaselinePath :: FilePath -> BaselineRef -> FilePath
checkedBaselinePath root ref = case baselinePath root ref of
  Just path -> path
  Nothing -> error "checkedBaselinePath: internally generated invalid baseline reference"
