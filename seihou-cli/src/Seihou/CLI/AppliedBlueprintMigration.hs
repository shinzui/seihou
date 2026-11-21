-- | Durable manifest receipts for agent-guided blueprint migrations.
module Seihou.CLI.AppliedBlueprintMigration (recordAppliedBlueprintMigration) where

import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as KM
import Data.Generics.Labels ()
import Data.Vector qualified as V
import Seihou.CLI.AppliedBlueprint (updateReceiptDocument)
import Seihou.Core.Types (AppliedBlueprintMigration (..))
import Seihou.Manifest.Types (writeAppliedBlueprintMigration)
import Seihou.Prelude

recordAppliedBlueprintMigration :: FilePath -> AppliedBlueprintMigration -> IO (Either Text ())
recordAppliedBlueprintMigration path receipt =
  updateReceiptDocument path (receipt ^. #appliedAt) True $ \manifest fields ->
    let updated = writeAppliedBlueprintMigration receipt manifest
        -- Upsert replaces in place or appends. Preserve the original JSON of
        -- every skipped edge, even when this invocation ran another owner.
        originals = case KM.lookup "blueprintMigrations" fields of
          Just (Aeson.Array values) -> values
          _ -> V.empty
        previous = V.fromList (manifest ^. #blueprintMigrations)
        encodeEdge i edge
          | previous V.!? i == Just edge, Just raw <- originals V.!? i = raw
          | otherwise = Aeson.toJSON edge
        edges = V.imap encodeEdge (V.fromList (updated ^. #blueprintMigrations))
     in KM.insert "blueprintMigrations" (Aeson.Array edges) fields
