module Main (main) where

import Seihou.CLI.AgentCompletionSpec qualified as AgentCompletionSpec
import Seihou.CLI.AgentConfigShowSpec qualified as AgentConfigShowSpec
import Seihou.CLI.AgentConfigSpec qualified as AgentConfigSpec
import Seihou.CLI.AgentGuardE2ESpec qualified as AgentGuardE2ESpec
import Seihou.CLI.AgentLaunchSpec qualified as AgentLaunchSpec
import Seihou.CLI.AgentMigrateE2ESpec qualified as AgentMigrateE2ESpec
import Seihou.CLI.AgentModelsSpec qualified as AgentModelsSpec
import Seihou.CLI.AgentTraceE2ESpec qualified as AgentTraceE2ESpec
import Seihou.CLI.AgentTraceSpec qualified as AgentTraceSpec
import Seihou.CLI.AgentUpgradeE2ESpec qualified as AgentUpgradeE2ESpec
import Seihou.CLI.AppliedBlueprintMigrationSpec qualified as AppliedBlueprintMigrationSpec
import Seihou.CLI.AppliedBlueprintSpec qualified as AppliedBlueprintSpec
import Seihou.CLI.BlueprintMigrationSpec qualified as BlueprintMigrationSpec
import Seihou.CLI.BrowseFormatSpec qualified as BrowseFormatSpec
import Seihou.CLI.CheckoutSyncE2ESpec qualified as CheckoutSyncE2ESpec
import Seihou.CLI.CheckoutSyncSpec qualified as CheckoutSyncSpec
import Seihou.CLI.CommandExecutionSpec qualified as CommandExecutionSpec
import Seihou.CLI.CommitMessageSpec qualified as CommitMessageSpec
import Seihou.CLI.DiffSpec qualified as DiffSpec
import Seihou.CLI.ExtensionSpec qualified as ExtensionSpec
import Seihou.CLI.GitSpec qualified as GitSpec
import Seihou.CLI.InitSpec qualified as InitSpec
import Seihou.CLI.InstallClosureSpec qualified as InstallClosureSpec
import Seihou.CLI.InstallCollisionSpec qualified as InstallCollisionSpec
import Seihou.CLI.InstallHistorySpec qualified as InstallHistorySpec
import Seihou.CLI.InstallSourceSpec qualified as InstallSourceSpec
import Seihou.CLI.ListSpec qualified as ListSpec
import Seihou.CLI.ManifestCapabilityUpgradeSpec qualified as ManifestCapabilityUpgradeSpec
import Seihou.CLI.ManifestGuardSpec qualified as ManifestGuardSpec
import Seihou.CLI.ManifestRepairOriginsSpec qualified as ManifestRepairOriginsSpec
import Seihou.CLI.ManifestUpgradeSpec qualified as ManifestUpgradeSpec
import Seihou.CLI.MigrateSpec qualified as MigrateSpec
import Seihou.CLI.PendingMigrationSpec qualified as PendingMigrationSpec
import Seihou.CLI.PromptRenderSpec qualified as PromptRenderSpec
import Seihou.CLI.RecipeInputsE2ESpec qualified as RecipeInputsE2E
import Seihou.CLI.RecordedReleaseSpec qualified as RecordedReleaseSpec
import Seihou.CLI.Registry.SyncSpec qualified as RegistrySyncSpec
import Seihou.CLI.Registry.ValidateSpec qualified as RegistryValidateSpec
import Seihou.CLI.RemoteVersionSpec qualified as RemoteVersionSpec
import Seihou.CLI.RepairOriginsE2ESpec qualified as RepairOriginsE2ESpec
import Seihou.CLI.RunBlueprintRefusalSpec qualified as RunBlueprintRefusalSpec
import Seihou.CLI.SavePromptedSpec qualified as SavePromptedSpec
import Seihou.CLI.SeedRunE2ESpec qualified as SeedRunE2E
import Seihou.CLI.SeedUpdateE2ESpec qualified as SeedUpdateE2E
import Seihou.CLI.SharedManifestE2ESpec qualified as SharedManifestE2ESpec
import Seihou.CLI.StatusSpec qualified as StatusSpec
import Seihou.CLI.UpdateE2ESpec qualified as UpdateE2ESpec
import Seihou.CLI.UpdateInteractionSpec qualified as UpdateInteractionSpec
import Seihou.CLI.UpdateRenderSpec qualified as UpdateRenderSpec
import Seihou.CLI.UpdateSpec qualified as UpdateSpec
import Seihou.CLI.UpgradeDiagnosisSpec qualified as UpgradeDiagnosisSpec
import Seihou.CLI.UpgradeSpec qualified as UpgradeSpec
import Seihou.FzfSpec qualified as FzfSpec
import Test.Tasty

main :: IO ()
main = do
  tests <-
    sequence
      [ AgentLaunchSpec.tests,
        AgentMigrateE2ESpec.tests,
        AgentGuardE2ESpec.tests,
        AgentCompletionSpec.tests,
        AgentConfigSpec.tests,
        AgentConfigShowSpec.tests,
        AgentModelsSpec.tests,
        AgentTraceSpec.tests,
        AgentTraceE2ESpec.tests,
        AppliedBlueprintSpec.tests,
        AppliedBlueprintMigrationSpec.tests,
        BlueprintMigrationSpec.tests,
        BrowseFormatSpec.tests,
        CommitMessageSpec.tests,
        CommandExecutionSpec.tests,
        DiffSpec.tests,
        ExtensionSpec.tests,
        GitSpec.tests,
        InitSpec.tests,
        InstallClosureSpec.tests,
        InstallCollisionSpec.tests,
        InstallHistorySpec.tests,
        InstallSourceSpec.tests,
        ListSpec.tests,
        ManifestGuardSpec.tests,
        ManifestCapabilityUpgradeSpec.tests,
        ManifestRepairOriginsSpec.tests,
        ManifestUpgradeSpec.tests,
        MigrateSpec.tests,
        PendingMigrationSpec.tests,
        PromptRenderSpec.tests,
        RegistrySyncSpec.tests,
        RegistryValidateSpec.tests,
        RecordedReleaseSpec.tests,
        RemoteVersionSpec.tests,
        RepairOriginsE2ESpec.tests,
        RunBlueprintRefusalSpec.tests,
        SavePromptedSpec.tests,
        CheckoutSyncSpec.tests,
        CheckoutSyncE2ESpec.tests,
        SharedManifestE2ESpec.tests,
        StatusSpec.tests,
        UpgradeSpec.tests,
        UpdateSpec.tests,
        UpdateInteractionSpec.tests,
        UpdateE2ESpec.tests,
        UpdateRenderSpec.tests,
        UpgradeDiagnosisSpec.tests,
        AgentUpgradeE2ESpec.tests,
        FzfSpec.tests
      ]
  seedUpdateTests <- SeedUpdateE2E.tests
  recipeInputsTests <- RecipeInputsE2E.tests
  seedRunTests <- SeedRunE2E.tests
  defaultMain (testGroup "seihou-cli" (recipeInputsTests : seedUpdateTests : seedRunTests : tests))
