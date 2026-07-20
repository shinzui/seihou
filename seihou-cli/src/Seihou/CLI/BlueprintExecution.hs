-- | Shared preparation for normal and migration blueprint execution.
--
-- This module deliberately knows nothing about executable command options or
-- provider processes. It resolves the blueprint's variables through Seihou's
-- standard precedence chain, prepares reference-file access, and renders the
-- shared blueprint prompt once for downstream execution modes.
module Seihou.CLI.BlueprintExecution
  ( BlueprintExecutionRequest (..),
    PreparedBlueprintExecution (..),
    prepareBlueprintExecution,
    renderBlueprintText,
    varValueToText,
  )
where

import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text qualified as T
import Seihou.CLI.AgentLaunch
  ( formatReferenceFiles,
    formatReferenceFilesDir,
    resolveBlueprintTools,
  )
import Seihou.CLI.Shared
  ( deriveNamespace,
    toVarNameMap,
    unwrapConfig,
  )
import Seihou.Composition.Instance (primaryInstance)
import Seihou.Composition.Resolve (resolveWithPrompts)
import Seihou.Core.Context (resolveContext)
import Seihou.Core.Types
import Seihou.Effect.ConfigReader
  ( readContextConfig,
    readGlobalConfig,
    readLocalConfig,
    readNamespaceConfig,
  )
import Seihou.Effect.ConfigReaderInterp (runConfigReader)
import Seihou.Effect.ConsoleInterp (runConsole)
import Seihou.Prelude
import System.Directory (doesDirectoryExist, makeAbsolute)
import System.Environment (getEnvironment)

-- | Inputs shared by normal blueprint runs and blueprint migrations.
-- Provider capability is represented as a boolean so this library module does
-- not need to know about Baikai or the executable command model.
data BlueprintExecutionRequest = BlueprintExecutionRequest
  { executionBlueprint :: Blueprint,
    executionBlueprintDir :: FilePath,
    executionVariableOverrides :: [(Text, Text)],
    executionNamespaceOverride :: Maybe Text,
    executionContextOverride :: Maybe Text,
    executionCanMountFiles :: Bool,
    executionLogLevel :: LogLevel
  }
  deriving stock (Eq, Show)

-- | Prepared state that both execution modes consume. The mounted path is
-- absolute when present; the access text preserves the existing API-provider
-- explanation when local files cannot be mounted.
data PreparedBlueprintExecution = PreparedBlueprintExecution
  { preparedBlueprint :: Blueprint,
    preparedBlueprintDir :: FilePath,
    preparedResolvedVariables :: Map VarName ResolvedVar,
    preparedMountedFilesDir :: Maybe FilePath,
    preparedReferenceFiles :: Text,
    preparedReferenceFilesAccess :: Text,
    preparedSharedPrompt :: Text,
    preparedAllowedTools :: [String]
  }
  deriving stock (Eq, Show)

-- | Resolve one blueprint through the same CLI/environment/config/prompt
-- precedence used by @seihou run@ and the existing agent runner.
prepareBlueprintExecution ::
  BlueprintExecutionRequest ->
  IO (Either [VarError] PreparedBlueprintExecution)
prepareBlueprintExecution request = do
  let bp = request.executionBlueprint
      blueprintDir = request.executionBlueprintDir
      filesDir = blueprintDir </> "files"
  filesExist <- doesDirectoryExist filesDir
  mountedFilesDir <-
    if filesExist && request.executionCanMountFiles
      then Just <$> makeAbsolute filesDir
      else pure Nothing

  let placeholderModule =
        Module
          { name = bp.name,
            version = bp.version,
            description = bp.description,
            vars = bp.vars,
            exports = [],
            prompts = bp.prompts,
            steps = [],
            commands = [],
            dependencies = [],
            removal = Nothing,
            migrations = []
          }
      placeholderInst = primaryInstance bp.name
      placeholderTriple = (placeholderInst, placeholderModule, blueprintDir)

  envPairs <- getEnvironment
  let cliOverrides =
        Map.fromList
          [(VarName key, value) | (key, value) <- request.executionVariableOverrides]
      envVars = Map.fromList [(T.pack key, T.pack value) | (key, value) <- envPairs]
      namespace =
        fromMaybe (deriveNamespace bp.name) request.executionNamespaceOverride
  context <- resolveContext request.executionContextOverride envVars
  let contextName = fromMaybe "" context

  resolveResult <- runEff $ runConfigReader $ runConsole $ do
    localCfg <- readLocalConfig >>= unwrapConfig request.executionLogLevel
    nsCfg <- readNamespaceConfig namespace >>= unwrapConfig request.executionLogLevel
    ctxCfg <- readContextConfig contextName >>= unwrapConfig request.executionLogLevel
    globalCfg <- readGlobalConfig >>= unwrapConfig request.executionLogLevel
    resolveWithPrompts
      [placeholderTriple]
      cliOverrides
      envVars
      namespace
      contextName
      (toVarNameMap localCfg)
      (toVarNameMap nsCfg)
      (toVarNameMap ctxCfg)
      (toVarNameMap globalCfg)

  pure $ do
    allResolved <- resolveResult
    let resolved = Map.findWithDefault Map.empty placeholderInst allResolved
    Right
      PreparedBlueprintExecution
        { preparedBlueprint = bp,
          preparedBlueprintDir = blueprintDir,
          preparedResolvedVariables = resolved,
          preparedMountedFilesDir = mountedFilesDir,
          preparedReferenceFiles = formatReferenceFiles bp.files,
          preparedReferenceFilesAccess = formatReferenceFilesDir mountedFilesDir,
          preparedSharedPrompt = renderBlueprintText resolved bp.prompt,
          preparedAllowedTools = resolveBlueprintTools bp.allowedTools
        }

-- | Substitute resolved blueprint variables into any blueprint-owned text.
renderBlueprintText :: Map VarName ResolvedVar -> Text -> Text
renderBlueprintText resolved template =
  foldl'
    ( \rendered (name, value) ->
        T.replace
          ("{{" <> name.unVarName <> "}}")
          (varValueToText value.value)
          rendered
    )
    template
    (Map.toList resolved)

varValueToText :: VarValue -> Text
varValueToText (VText value) = value
varValueToText (VBool True) = "true"
varValueToText (VBool False) = "false"
varValueToText (VInt value) = T.pack (show value)
varValueToText (VList values) = T.intercalate "," (map varValueToText values)
