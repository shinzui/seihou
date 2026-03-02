module Main (main) where

import Seihou.Composition.GraphSpec qualified as GraphSpec
import Seihou.Composition.PlanSpec qualified as CompositionPlanSpec
import Seihou.Composition.ResolveSpec qualified as ResolveSpec
import Seihou.Core.ExprSpec qualified as ExprSpec
import Seihou.Core.ModuleSpec qualified as ModuleSpec
import Seihou.Core.TypesSpec qualified as TypesSpec
import Seihou.Core.VariableSpec qualified as VariableSpec
import Seihou.Dhall.EvalSpec qualified as DhallEvalSpec
import Seihou.Effect.FilesystemSpec qualified as FilesystemSpec
import Seihou.Effect.ManifestStoreSpec qualified as ManifestStoreSpec
import Seihou.Engine.DiffSpec qualified as DiffSpec
import Seihou.Engine.ExecuteSpec qualified as ExecuteSpec
import Seihou.Engine.PlanSpec qualified as PlanSpec
import Seihou.Engine.TemplateSpec qualified as TemplateSpec
import Seihou.Integration.CompositionSpec qualified as CompositionSpec
import Seihou.Integration.ExecutionSpec qualified as ExecutionSpec
import Seihou.Integration.GenerationSpec qualified as GenerationSpec
import Seihou.Integration.ModuleLoadSpec qualified as IntegrationSpec
import Seihou.Manifest.TypesSpec qualified as ManifestTypesSpec
import Test.Tasty

main :: IO ()
main = do
  graphTests <- GraphSpec.tests
  compositionPlanTests <- CompositionPlanSpec.tests
  resolveTests <- ResolveSpec.tests
  typesTests <- TypesSpec.tests
  exprTests <- ExprSpec.tests
  moduleTests <- ModuleSpec.tests
  variableTests <- VariableSpec.tests
  templateTests <- TemplateSpec.tests
  planTests <- PlanSpec.tests
  dhallEvalTests <- DhallEvalSpec.tests
  filesystemTests <- FilesystemSpec.tests
  manifestStoreTests <- ManifestStoreSpec.tests
  diffTests <- DiffSpec.tests
  executeTests <- ExecuteSpec.tests
  compositionTests <- CompositionSpec.tests
  executionTests <- ExecutionSpec.tests
  integrationTests <- IntegrationSpec.tests
  generationTests <- GenerationSpec.tests
  manifestTypesTests <- ManifestTypesSpec.tests
  defaultMain (testGroup "seihou-core" [graphTests, compositionPlanTests, resolveTests, typesTests, exprTests, moduleTests, variableTests, templateTests, planTests, dhallEvalTests, filesystemTests, manifestStoreTests, diffTests, executeTests, compositionTests, executionTests, integrationTests, generationTests, manifestTypesTests])
