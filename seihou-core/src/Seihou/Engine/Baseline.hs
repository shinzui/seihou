module Seihou.Engine.Baseline
  ( recordGeneratedBaselines,
    manifestBaselineRefs,
  )
where

import Control.Monad (foldM)
import Data.Map.Strict qualified as Map
import Data.Maybe (mapMaybe)
import Data.Set qualified as Set
import Data.Text qualified as T
import Seihou.Core.Types (BaselineRef, FileRecord (..), Manifest (..))
import Seihou.Effect.BaselineStore (BaselineError (..), BaselineStore, putBaseline)
import Seihou.Effect.Filesystem (Filesystem, doesFileExist, readFileText)
import Seihou.Manifest.Hash (hashContent)
import Seihou.Prelude

-- | Capture the exact post-execution bytes for every returned file record.
-- The same content supplies both the generated baseline and the applied disk
-- hash, which is essential for patch operations whose final content only
-- exists after execution.
recordGeneratedBaselines ::
  (Filesystem :> es, BaselineStore :> es) =>
  FilePath ->
  Map FilePath FileRecord ->
  Eff es (Either BaselineError (Map FilePath FileRecord))
recordGeneratedBaselines targetDir records =
  foldM capture (Right Map.empty) (Map.toAscList records)
  where
    capture (Left err) _ = pure (Left err)
    capture (Right captured) (path, record) = do
      let fullPath = targetDir </> path
      exists <- doesFileExist fullPath
      if not exists
        then
          pure $
            Left $
              BaselineStoreFailure
                ("generated file disappeared before baseline capture: " <> T.pack fullPath)
        else do
          content <- readFileText fullPath
          ref <- putBaseline content
          let enriched =
                record
                  { hash = hashContent content,
                    baseline = Just ref
                  }
          pure (Right (Map.insert path enriched captured))

-- | Every blob protected by the currently durable manifest. Callers pass this
-- set to 'pruneBaselines' only after publishing that manifest.
manifestBaselineRefs :: Manifest -> Set BaselineRef
manifestBaselineRefs manifest =
  Set.fromList (mapMaybe (.baseline) (Map.elems manifest.files))
