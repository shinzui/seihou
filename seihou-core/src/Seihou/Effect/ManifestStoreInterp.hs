module Seihou.Effect.ManifestStoreInterp
  ( runManifestStore,
  )
where

import Control.Monad (unless)
import Data.ByteString.Lazy qualified as LBS
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Seihou.Effect.Filesystem (Filesystem, createDirectoryIfMissing, doesFileExist, readFileText, renamePath, writeFileText)
import Seihou.Effect.ManifestStore (ManifestStore (..))
import Seihou.Manifest.Types (manifestFromJSON, manifestToJSON)
import Seihou.Prelude
import System.FilePath (takeDirectory)

-- | Real interpreter for the ManifestStore effect.
-- Reads and writes manifest JSON via the Filesystem effect.
-- Write is atomic within one filesystem: writes to a temp path in the
-- manifest directory, then renames that complete file over the final path.
runManifestStore ::
  (Filesystem :> es) =>
  FilePath ->
  Eff (ManifestStore : es) a ->
  Eff es a
runManifestStore manifestPath = interpret $ \_ -> \case
  ReadManifest -> do
    exists <- doesFileExist manifestPath
    if not exists
      then pure (Right Nothing)
      else do
        content <- readFileText manifestPath
        let bs = LBS.fromStrict (TE.encodeUtf8 content)
        case manifestFromJSON bs of
          Left err -> pure (Left (T.pack err))
          Right manifest -> pure (Right (Just manifest))
  WriteManifest manifest -> do
    let bs = manifestToJSON manifest
        content = TE.decodeUtf8 (LBS.toStrict bs)
        tmpPath = manifestPath <> ".tmp"
        parentDir = takeDirectory manifestPath
    unless (parentDir == "." || null parentDir) $
      createDirectoryIfMissing True parentDir
    writeFileText tmpPath content
    renamePath tmpPath manifestPath
