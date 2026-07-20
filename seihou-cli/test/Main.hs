module Main (main) where

import Seihou.CLI.AgentCompletionSpec qualified as AgentCompletionSpec
import Seihou.CLI.AgentConfigShowSpec qualified as AgentConfigShowSpec
import Seihou.CLI.AgentConfigSpec qualified as AgentConfigSpec
import Seihou.CLI.AgentLaunchSpec qualified as AgentLaunchSpec
import Seihou.CLI.AgentMigrateE2ESpec qualified as AgentMigrateE2ESpec
import Seihou.CLI.AgentModelsSpec qualified as AgentModelsSpec
import Seihou.CLI.AppliedBlueprintMigrationSpec qualified as AppliedBlueprintMigrationSpec
import Seihou.CLI.AppliedBlueprintSpec qualified as AppliedBlueprintSpec
import Seihou.CLI.BlueprintMigrationSpec qualified as BlueprintMigrationSpec
import Seihou.CLI.BrowseFormatSpec qualified as BrowseFormatSpec
import Seihou.CLI.CommandExecutionSpec qualified as CommandExecutionSpec
import Seihou.CLI.CommitMessageSpec qualified as CommitMessageSpec
import Seihou.CLI.DiffSpec qualified as DiffSpec
import Seihou.CLI.ExtensionSpec qualified as ExtensionSpec
import Seihou.CLI.GitSpec qualified as GitSpec
import Seihou.CLI.InitSpec qualified as InitSpec
import Seihou.CLI.InstallHistorySpec qualified as InstallHistorySpec
import Seihou.CLI.ListSpec qualified as ListSpec
import Seihou.CLI.MigrateSpec qualified as MigrateSpec
import Seihou.CLI.PendingMigrationSpec qualified as PendingMigrationSpec
import Seihou.CLI.PromptRenderSpec qualified as PromptRenderSpec
import Seihou.CLI.Registry.SyncSpec qualified as RegistrySyncSpec
import Seihou.CLI.Registry.ValidateSpec qualified as RegistryValidateSpec
import Seihou.CLI.RemoteVersionSpec qualified as RemoteVersionSpec
import Seihou.CLI.RunBlueprintRefusalSpec qualified as RunBlueprintRefusalSpec
import Seihou.CLI.SavePromptedSpec qualified as SavePromptedSpec
import Seihou.CLI.StatusSpec qualified as StatusSpec
import Seihou.CLI.UpdateE2ESpec qualified as UpdateE2ESpec
import Seihou.CLI.UpdateInteractionSpec qualified as UpdateInteractionSpec
import Seihou.CLI.UpdateRenderSpec qualified as UpdateRenderSpec
import Seihou.CLI.UpdateSpec qualified as UpdateSpec
import Seihou.CLI.UpgradeSpec qualified as UpgradeSpec
import Seihou.FzfSpec qualified as FzfSpec
import Test.Tasty

main :: IO ()
main = do
  tests <-
    sequence
      [ AgentLaunchSpec.tests,
        AgentMigrateE2ESpec.tests,
        AgentCompletionSpec.tests,
        AgentConfigSpec.tests,
        AgentConfigShowSpec.tests,
        AgentModelsSpec.tests,
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
        InstallHistorySpec.tests,
        ListSpec.tests,
        MigrateSpec.tests,
        PendingMigrationSpec.tests,
        PromptRenderSpec.tests,
        RegistrySyncSpec.tests,
        RegistryValidateSpec.tests,
        RemoteVersionSpec.tests,
        RunBlueprintRefusalSpec.tests,
        SavePromptedSpec.tests,
        StatusSpec.tests,
        UpgradeSpec.tests,
        UpdateSpec.tests,
        UpdateInteractionSpec.tests,
        UpdateE2ESpec.tests,
        UpdateRenderSpec.tests,
        FzfSpec.tests
      ]
  defaultMain (testGroup "seihou-cli" tests)
