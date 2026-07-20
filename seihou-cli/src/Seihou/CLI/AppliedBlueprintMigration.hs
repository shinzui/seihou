-- | Durable manifest receipts for agent-guided blueprint migrations.
module Seihou.CLI.AppliedBlueprintMigration
  ( recordAppliedBlueprintMigration,
  )
where

import Seihou.Core.Types (AppliedBlueprintMigration (..))
import Seihou.Effect.Filesystem (createDirectoryIfMissing)
import Seihou.Effect.FilesystemInterp (runFilesystem)
import Seihou.Effect.ManifestStore (readManifest, writeManifest)
import Seihou.Effect.ManifestStoreInterp (runManifestStore)
import Seihou.Manifest.Types (emptyManifest, writeAppliedBlueprintMigration)
import Seihou.Prelude
import System.FilePath (takeDirectory)

-- | Read or create the project manifest, upsert one exact migration receipt,
-- and write it atomically. A corrupt existing manifest is reported and left
-- untouched rather than being replaced.
recordAppliedBlueprintMigration :: FilePath -> AppliedBlueprintMigration -> IO (Either Text ())
recordAppliedBlueprintMigration manifestPath receipt =
  runEff $ runFilesystem $ runManifestStore manifestPath $ do
    createDirectoryIfMissing True (takeDirectory manifestPath)
    mManifest <- readManifest
    case mManifest of
      Right (Just manifest) -> do
        writeManifest (writeAppliedBlueprintMigration receipt manifest)
        pure (Right ())
      Right Nothing -> do
        writeManifest (writeAppliedBlueprintMigration receipt (emptyManifest receipt.appliedAt))
        pure (Right ())
      Left err -> pure (Left err)
