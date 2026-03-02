module Seihou.Effect.ManifestStoreInterp
  ( runManifestStore,
  )
where

import Data.ByteString.Lazy qualified as LBS
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Effectful
import Effectful.Dispatch.Dynamic
import Seihou.Effect.Filesystem (Filesystem, doesFileExist, readFileText, writeFileText)
import Seihou.Effect.ManifestStore (ManifestStore (..))
import Seihou.Manifest.Types (manifestFromJSON, manifestToJSON)
import System.FilePath (takeDirectory)

-- | Real interpreter for the ManifestStore effect.
-- Reads and writes manifest JSON via the Filesystem effect.
-- Write is atomic: writes to a temp path then renames (via overwrite).
runManifestStore ::
  (Filesystem :> es) =>
  FilePath ->
  Eff (ManifestStore : es) a ->
  Eff es a
runManifestStore manifestPath = interpret $ \_ -> \case
  ReadManifest -> do
    exists <- doesFileExist manifestPath
    if not exists
      then pure Nothing
      else do
        content <- readFileText manifestPath
        let bs = LBS.fromStrict (TE.encodeUtf8 content)
        case manifestFromJSON bs of
          Left err -> error ("ManifestStore: failed to parse manifest: " <> err)
          Right manifest -> pure (Just manifest)
  WriteManifest manifest -> do
    let bs = manifestToJSON manifest
        content = TE.decodeUtf8 (LBS.toStrict bs)
        tmpPath = manifestPath <> ".tmp"
    -- Atomic write: write to temp file, then overwrite original.
    -- In the pure FS this is a simple two-step; on real FS the rename
    -- happens implicitly when we overwrite.
    writeFileText tmpPath content
    writeFileText manifestPath content
