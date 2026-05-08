-- | Persist 'AppliedBlueprint' provenance to a project's
-- @.seihou/manifest.json@. The runner in @src-exe/Seihou/CLI/AgentRun.hs@
-- assembles an 'AppliedBlueprint' after a successful agent session and
-- delegates the actual read-modify-write to 'recordAppliedBlueprint'.
-- Keeping this helper in @seihou-cli-internal@ (rather than next to the
-- runner) lets the test suite cover it directly: the @seihou@
-- executable target is trapped by @Options.Applicative@/@Data.FileEmbed@
-- and is not importable by @seihou-cli-test@.
module Seihou.CLI.AppliedBlueprint
  ( recordAppliedBlueprint,
  )
where

import Seihou.Core.Types (AppliedBlueprint (..))
import Seihou.Effect.Filesystem (createDirectoryIfMissing)
import Seihou.Effect.FilesystemInterp (runFilesystem)
import Seihou.Effect.ManifestStore (readManifest, writeManifest)
import Seihou.Effect.ManifestStoreInterp (runManifestStore)
import Seihou.Manifest.Types (emptyManifest, writeAppliedBlueprint)
import Seihou.Prelude
import System.FilePath (takeDirectory)

-- | Read the manifest at @manifestPath@, attach the supplied
-- 'AppliedBlueprint' as the project's blueprint provenance, and write
-- the manifest back. If no manifest exists yet, a fresh one is created
-- using the entry's @appliedAt@ timestamp as its @genAt@.
--
-- Returns @Left err@ when the existing manifest cannot be parsed —
-- callers should leave the manifest untouched in that case rather than
-- silently overwriting a hand-edited file. The directory containing
-- the manifest is created if missing, mirroring the pre-existing
-- @applyBaseline@ flow.
recordAppliedBlueprint :: FilePath -> AppliedBlueprint -> IO (Either Text ())
recordAppliedBlueprint manifestPath ab =
  runEff $ runFilesystem $ runManifestStore manifestPath $ do
    createDirectoryIfMissing True (takeDirectory manifestPath)
    mManifest <- readManifest
    case mManifest of
      Right (Just m) -> do
        writeManifest (writeAppliedBlueprint ab m)
        pure (Right ())
      Right Nothing -> do
        writeManifest (writeAppliedBlueprint ab (emptyManifest ab.appliedAt))
        pure (Right ())
      Left err -> pure (Left err)
