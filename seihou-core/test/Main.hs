module Main (main) where

import Seihou.Composition.GraphSpec qualified as GraphSpec
import Seihou.Composition.PlanSpec qualified as CompositionPlanSpec
import Seihou.Composition.RecipeSpec qualified as CompositionRecipeSpec
import Seihou.Composition.ResolveSpec qualified as ResolveSpec
import Seihou.Core.ContextSpec qualified as ContextSpec
import Seihou.Core.ExprSpec qualified as ExprSpec
import Seihou.Core.InstallSpec qualified as InstallSpec
import Seihou.Core.ListSpec qualified as ListSpec
import Seihou.Core.ModuleSpec qualified as ModuleSpec
import Seihou.Core.RecipeSpec qualified as RecipeSpec
import Seihou.Core.RegistrySpec qualified as RegistrySpec
import Seihou.Core.ScaffoldSpec qualified as ScaffoldSpec
import Seihou.Core.SchemaUpgradeSpec qualified as SchemaUpgradeSpec
import Seihou.Core.StatusSpec qualified as StatusSpec
import Seihou.Core.TypesSpec qualified as TypesSpec
import Seihou.Core.VariableSpec qualified as VariableSpec
import Seihou.Core.VersionSpec qualified as VersionSpec
import Seihou.Dhall.ConfigSpec qualified as ConfigSpec
import Seihou.Dhall.EvalSpec qualified as DhallEvalSpec
import Seihou.Effect.ConfigReaderSpec qualified as ConfigReaderSpec
import Seihou.Effect.ConfigWriterSpec qualified as ConfigWriterSpec
import Seihou.Effect.FilesystemSpec qualified as FilesystemSpec
import Seihou.Effect.LoggerSpec qualified as LoggerSpec
import Seihou.Effect.ManifestStoreSpec qualified as ManifestStoreSpec
import Seihou.Engine.ConflictSpec qualified as ConflictSpec
import Seihou.Engine.DiffSpec qualified as DiffSpec
import Seihou.Engine.ExecuteSpec qualified as ExecuteSpec
import Seihou.Engine.PlanSpec qualified as PlanSpec
import Seihou.Engine.PreviewSpec qualified as PreviewSpec
import Seihou.Engine.RemoveSpec qualified as RemoveSpec
import Seihou.Engine.SectionSpec qualified as SectionSpec
import Seihou.Engine.TemplateSpec qualified as TemplateSpec
import Seihou.Engine.ValidateSpec qualified as ValidateSpec
import Seihou.Evaluation.DhallTextFlakeSpec qualified as DhallTextFlakeSpec
import Seihou.Evaluation.SplitFlakeSpec qualified as SplitFlakeSpec
import Seihou.Integration.CompositionSpec qualified as CompositionSpec
import Seihou.Integration.ExecutionSpec qualified as ExecutionSpec
import Seihou.Integration.GenerationSpec qualified as GenerationSpec
import Seihou.Integration.ModuleLoadSpec qualified as IntegrationSpec
import Seihou.Interaction.ConfirmSpec qualified as ConfirmSpec
import Seihou.Interaction.PromptSpec qualified as PromptSpec
import Seihou.Manifest.TypesSpec qualified as ManifestTypesSpec
import Test.Tasty

main :: IO ()
main = do
  graphTests <- GraphSpec.tests
  compositionPlanTests <- CompositionPlanSpec.tests
  compositionRecipeTests <- CompositionRecipeSpec.tests
  resolveTests <- ResolveSpec.tests
  typesTests <- TypesSpec.tests
  contextTests <- ContextSpec.tests
  exprTests <- ExprSpec.tests
  installTests <- InstallSpec.tests
  listTests <- ListSpec.tests
  moduleTests <- ModuleSpec.tests
  recipeTests <- RecipeSpec.tests
  registryTests <- RegistrySpec.tests
  scaffoldTests <- ScaffoldSpec.tests
  schemaUpgradeTests <- SchemaUpgradeSpec.tests
  statusTests <- StatusSpec.tests
  variableTests <- VariableSpec.tests
  versionTests <- VersionSpec.tests
  templateTests <- TemplateSpec.tests
  planTests <- PlanSpec.tests
  previewTests <- PreviewSpec.tests
  sectionTests <- SectionSpec.tests
  validateTests <- ValidateSpec.tests
  splitFlakeTests <- SplitFlakeSpec.tests
  dhallTextFlakeTests <- DhallTextFlakeSpec.tests
  configTests <- ConfigSpec.tests
  dhallEvalTests <- DhallEvalSpec.tests
  configReaderTests <- ConfigReaderSpec.tests
  configWriterTests <- ConfigWriterSpec.tests
  filesystemTests <- FilesystemSpec.tests
  loggerTests <- LoggerSpec.tests
  manifestStoreTests <- ManifestStoreSpec.tests
  conflictTests <- ConflictSpec.tests
  diffTests <- DiffSpec.tests
  executeTests <- ExecuteSpec.tests
  removeTests <- RemoveSpec.tests
  compositionTests <- CompositionSpec.tests
  executionTests <- ExecutionSpec.tests
  integrationTests <- IntegrationSpec.tests
  generationTests <- GenerationSpec.tests
  manifestTypesTests <- ManifestTypesSpec.tests
  promptTests <- PromptSpec.tests
  confirmTests <- ConfirmSpec.tests
  defaultMain (testGroup "seihou-core" [graphTests, compositionPlanTests, compositionRecipeTests, resolveTests, typesTests, contextTests, exprTests, installTests, listTests, moduleTests, recipeTests, registryTests, scaffoldTests, schemaUpgradeTests, statusTests, variableTests, versionTests, templateTests, planTests, previewTests, sectionTests, validateTests, splitFlakeTests, dhallTextFlakeTests, configTests, dhallEvalTests, configReaderTests, configWriterTests, filesystemTests, loggerTests, manifestStoreTests, conflictTests, diffTests, executeTests, removeTests, compositionTests, executionTests, integrationTests, generationTests, manifestTypesTests, promptTests, confirmTests])
