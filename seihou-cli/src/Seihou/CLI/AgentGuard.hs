-- | The pre-flight artifact guard for the agent path.
--
-- @seihou agent run@ and @seihou agent migrate@ both act on artifacts the
-- project records in @.seihou\/manifest.json@: the first applies a
-- blueprint's baseline modules to the working directory and rewrites the
-- manifest, the second writes a receipt per migration edge that suppresses
-- future runs of that edge. Both are therefore subject to
-- docs\/adr\/0003-a-stale-or-substituted-artifact-is-a-hard-error.md, which
-- decides that a command about to generate from an artifact refuses when the
-- local copy is older than, or came from somewhere other than, what the
-- manifest records.
--
-- This module is the glue between that decision and those two commands. The
-- comparison itself is 'Seihou.CLI.ManifestGuard'; all this adds is reading
-- the manifest, choosing what is in scope, and handing the result to
-- 'enforceArtifactGuard'.
module Seihou.CLI.AgentGuard
  ( enforceAgentArtifactGuard,
  )
where

import Data.Generics.Labels ()
import Data.Maybe (maybeToList)
import Data.Set qualified as Set
import Seihou.CLI.ManifestGuard
  ( blockingChecks,
    checkAppliedArtifactsFor,
    checkRecordedBlueprint,
    enforceArtifactGuard,
  )
import Seihou.Core.Module (defaultSearchPaths)
import Seihou.Core.Types (ModuleName)
import Seihou.Effect.FilesystemInterp (runFilesystem)
import Seihou.Effect.ManifestStore (readManifest)
import Seihou.Effect.ManifestStoreInterp (runManifestStore)
import Seihou.Prelude
import System.Directory (getCurrentDirectory)

-- | Refuse to proceed when an artifact this agent command is about to use
-- disagrees with what the project records, unless @--allow-downgrade@ says
-- otherwise.
--
-- @manifestPath@ is the project's @.seihou\/manifest.json@. @blueprintName@
-- is the blueprint the command was invoked on. @baselineModuleNames@ are the
-- modules the command is about to generate files from — every module in the
-- resolved baseline composition for @agent run@, and empty for @agent
-- migrate@, which applies no baseline.
--
-- Two situations pass without a check because there is genuinely nothing to
-- compare against: a project with no manifest at all, and a manifest that
-- cannot be read. The second is deliberate rather than lax — an unreadable
-- manifest is a problem the command's own manifest handling reports far
-- better than a guard could, and turning it into a downgrade refusal would
-- name the wrong cause.
--
-- Scope is the whole point. A blueprint recorded under a different name, or a
-- stale module the command will not touch, must not block work that has
-- nothing to do with it; that is the line ADR 0003 draws for @seihou run@ and
-- this holds it for the agent path.
--
-- Callers must not invoke this in @--debug@ mode. Debug contacts no provider,
-- applies no baseline, and writes nothing, so a developer inspecting a prompt
-- on a machine that has never installed the artifact has nothing to be
-- refused for.
enforceAgentArtifactGuard ::
  -- | @--allow-downgrade@
  Bool ->
  -- | path to @.seihou\/manifest.json@
  FilePath ->
  -- | the blueprint this command was invoked on
  ModuleName ->
  -- | modules this command is about to generate files from
  Set ModuleName ->
  IO ()
enforceAgentArtifactGuard allowDowngrade manifestPath blueprintName baselineModuleNames = do
  readResult <- runEff $ runFilesystem $ runManifestStore manifestPath readManifest
  case readResult of
    Left _ -> pure ()
    Right Nothing -> pure ()
    Right (Just manifest) -> do
      projectRoot <- getCurrentDirectory
      searchPaths <- defaultSearchPaths
      blueprintCheck <- checkRecordedBlueprint projectRoot searchPaths blueprintName manifest
      moduleChecks <-
        if Set.null baselineModuleNames
          then pure []
          else checkAppliedArtifactsFor projectRoot searchPaths (Just baselineModuleNames) manifest
      enforceArtifactGuard
        allowDowngrade
        (blockingChecks (maybeToList blueprintCheck <> moduleChecks))
