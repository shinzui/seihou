module Seihou.Core.Application
  ( mkApplicationId,
    buildAppliedComposition,
    replaceAppliedComposition,
    attachApplication,
  )
where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (UTCTime)
import Seihou.Composition.Instance (ModuleInstance (..))
import Seihou.Core.Types
import Seihou.Manifest.Hash (hashContent)

-- | Derive the stable identity of a top-level application. Versions,
-- source paths, and resolved values are deliberately excluded so a later
-- update replaces the same application record.
mkApplicationId :: AppliedTarget -> [ModuleName] -> ApplicationId
mkApplicationId target additional =
  ApplicationId (hashContent canonical).unSHA256
  where
    (kind, targetName) = case target of
      AppliedModuleTarget name -> ("module", name.unModuleName)
      AppliedRecipeTarget name -> ("recipe", name.unRecipeName)
    canonical =
      T.intercalate
        "\n"
        ( [ "target-kind=" <> kind,
            "target-name=" <> targetName
          ]
            ++ map ("additional=" <>) (map (.unModuleName) additional)
        )

-- | Capture a composition using the already-resolved, instance-scoped
-- values from the generation pipeline.
buildAppliedComposition ::
  AppliedTarget ->
  FilePath ->
  Maybe Text ->
  [ModuleName] ->
  Maybe Text ->
  Maybe Text ->
  [(ModuleInstance, Module, FilePath)] ->
  Map ModuleInstance (Map VarName ResolvedVar) ->
  UTCTime ->
  AppliedComposition
buildAppliedComposition target targetSource targetVersion additional namespace context modulesInOrder resolved now =
  AppliedComposition
    { applicationId = mkApplicationId target additional,
      target = target,
      targetSource = targetSource,
      targetVersion = targetVersion,
      additionalModules = additional,
      namespace = namespace,
      context = context,
      instances = map buildInstance modulesInOrder,
      commandReceipts = Map.empty,
      appliedAt = now
    }
  where
    buildInstance (inst, modul, source) =
      AppliedInstanceState
        { name = inst.instanceModule,
          parentVars = inst.instanceParentVars,
          source = source,
          moduleVersion = modul.version,
          resolvedVars = Map.map (varValueToText . (.value)) (Map.findWithDefault Map.empty inst resolved)
        }

-- | Replace an existing application in place, or append a newly-applied one.
replaceAppliedComposition :: AppliedComposition -> [AppliedComposition] -> [AppliedComposition]
replaceAppliedComposition replacement existing
  | any ((== replacement.applicationId) . (.applicationId)) existing =
      map replaceMatching existing
  | otherwise = existing ++ [replacement]
  where
    replaceMatching current
      | current.applicationId == replacement.applicationId = replacement
      | otherwise = current

-- | Attribute the current file result to an application while retaining
-- ownership from the prior record and any ownership already on the result.
-- Baseline population starts in EP-65, so ordinary records remain baseline-free
-- in this plan.
attachApplication :: ApplicationId -> Maybe FileRecord -> FileRecord -> FileRecord
attachApplication applicationId previous current =
  current
    { baseline = Nothing,
      applicationIds = Set.insert applicationId (Set.union current.applicationIds priorApplications)
    }
  where
    priorApplications = maybe Set.empty (.applicationIds) previous

varValueToText :: VarValue -> Text
varValueToText (VText value) = value
varValueToText (VBool True) = "true"
varValueToText (VBool False) = "false"
varValueToText (VInt value) = T.pack (show value)
varValueToText (VList values) = T.intercalate "," (map varValueToText values)
