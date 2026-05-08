module Main (main) where

import Seihou.CLI.AgentLaunchSpec qualified as AgentLaunchSpec
import Seihou.CLI.AppliedBlueprintSpec qualified as AppliedBlueprintSpec
import Seihou.CLI.BrowseFormatSpec qualified as BrowseFormatSpec
import Seihou.CLI.CommitMessageSpec qualified as CommitMessageSpec
import Seihou.CLI.DiffSpec qualified as DiffSpec
import Seihou.CLI.GitSpec qualified as GitSpec
import Seihou.CLI.InitSpec qualified as InitSpec
import Seihou.CLI.InstallHistorySpec qualified as InstallHistorySpec
import Seihou.CLI.ListSpec qualified as ListSpec
import Seihou.CLI.MigrateSpec qualified as MigrateSpec
import Seihou.CLI.PendingMigrationSpec qualified as PendingMigrationSpec
import Seihou.CLI.Registry.SyncSpec qualified as RegistrySyncSpec
import Seihou.CLI.Registry.ValidateSpec qualified as RegistryValidateSpec
import Seihou.CLI.RemoteVersionSpec qualified as RemoteVersionSpec
import Seihou.CLI.RunBlueprintRefusalSpec qualified as RunBlueprintRefusalSpec
import Seihou.CLI.SavePromptedSpec qualified as SavePromptedSpec
import Seihou.CLI.StatusSpec qualified as StatusSpec
import Seihou.CLI.UpgradeSpec qualified as UpgradeSpec
import Seihou.FzfSpec qualified as FzfSpec
import Test.Tasty

main :: IO ()
main = do
  tests <-
    sequence
      [ AgentLaunchSpec.tests,
        AppliedBlueprintSpec.tests,
        BrowseFormatSpec.tests,
        CommitMessageSpec.tests,
        DiffSpec.tests,
        GitSpec.tests,
        InitSpec.tests,
        InstallHistorySpec.tests,
        ListSpec.tests,
        MigrateSpec.tests,
        PendingMigrationSpec.tests,
        RegistrySyncSpec.tests,
        RegistryValidateSpec.tests,
        RemoteVersionSpec.tests,
        RunBlueprintRefusalSpec.tests,
        SavePromptedSpec.tests,
        StatusSpec.tests,
        UpgradeSpec.tests,
        FzfSpec.tests
      ]
  defaultMain (testGroup "seihou-cli" tests)
