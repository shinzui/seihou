module Main (main) where

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
import Seihou.CLI.SavePromptedSpec qualified as SavePromptedSpec
import Seihou.CLI.UpgradeSpec qualified as UpgradeSpec
import Seihou.FzfSpec qualified as FzfSpec
import Test.Tasty

main :: IO ()
main = do
  tests <-
    sequence
      [ BrowseFormatSpec.tests,
        CommitMessageSpec.tests,
        DiffSpec.tests,
        GitSpec.tests,
        InitSpec.tests,
        InstallHistorySpec.tests,
        ListSpec.tests,
        MigrateSpec.tests,
        PendingMigrationSpec.tests,
        RegistrySyncSpec.tests,
        SavePromptedSpec.tests,
        UpgradeSpec.tests,
        FzfSpec.tests
      ]
  defaultMain (testGroup "seihou-cli" tests)
