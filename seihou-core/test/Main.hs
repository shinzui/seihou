module Main (main) where

import Seihou.Core.ExprSpec qualified as ExprSpec
import Seihou.Core.ModuleSpec qualified as ModuleSpec
import Seihou.Core.TypesSpec qualified as TypesSpec
import Seihou.Core.VariableSpec qualified as VariableSpec
import Seihou.Dhall.EvalSpec qualified as DhallEvalSpec
import Seihou.Engine.PlanSpec qualified as PlanSpec
import Seihou.Engine.TemplateSpec qualified as TemplateSpec
import Seihou.Integration.GenerationSpec qualified as GenerationSpec
import Seihou.Integration.ModuleLoadSpec qualified as IntegrationSpec
import Test.Tasty

main :: IO ()
main = do
  typesTests <- TypesSpec.tests
  exprTests <- ExprSpec.tests
  moduleTests <- ModuleSpec.tests
  variableTests <- VariableSpec.tests
  templateTests <- TemplateSpec.tests
  planTests <- PlanSpec.tests
  dhallEvalTests <- DhallEvalSpec.tests
  integrationTests <- IntegrationSpec.tests
  generationTests <- GenerationSpec.tests
  defaultMain (testGroup "seihou-core" [typesTests, exprTests, moduleTests, variableTests, templateTests, planTests, dhallEvalTests, integrationTests, generationTests])
