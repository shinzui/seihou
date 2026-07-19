module Seihou.CLI.UpdateFixture
  ( minimalPlan,
    conflictPlan,
    unavailableConflictPlan,
    orphanPlan,
  )
where

import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Time (UTCTime, defaultTimeLocale, parseTimeOrError)
import Seihou.CLI.CommandExecution (CommandPlan (..), CommandPolicy (..))
import Seihou.CLI.Update
  ( InputChangeSummary (..),
    PromptPolicy (..),
    UpdatePlan (..),
    UpdateRequest (..),
    UpdateSelection (..),
  )
import Seihou.CLI.Update.Types (UpdateSnapshot (..))
import Seihou.Core.Types
  ( FileRecord (..),
    ModuleName (..),
    SHA256 (..),
    Strategy (..),
  )
import Seihou.Engine.Reconcile
  ( DesiredFile (..),
    FileReconciliation (..),
    ObservedFile (..),
    ReconciliationPlan (..),
    ReconciliationReason (..),
  )
import Seihou.Manifest.Types (emptyManifest)

fixedTime :: UTCTime
fixedTime =
  parseTimeOrError True defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ" "2026-07-19T12:00:00Z"

minimalPlan :: ReconciliationPlan -> UpdatePlan
minimalPlan reconciliation =
  UpdatePlan
    { applications = [],
      versionChanges = [],
      inputChanges = InputChangeSummary 0 0 0 0 [],
      migrations = [],
      reconciliation,
      commandPlan = CommandPlan [],
      candidateArtifacts = [],
      warnings = [],
      request =
        UpdateRequest
          { selection = AllRecordedApplications,
            varOverrides = [],
            reconfigure = False,
            promptPolicy = ForbidPrompts,
            commandPolicy = RunChangedCommands,
            dryRun = True
          },
      snapshot =
        UpdateSnapshot
          { sessionDirectory = "/tmp/session",
            projectRoot = "/tmp/project",
            manifestPath = "/tmp/project/.seihou/manifest.json",
            baselineDirectory = "/tmp/project/.seihou/baselines",
            installedDirectory = "/tmp/installed",
            originalManifest = emptyManifest fixedTime,
            candidateHashes = Map.empty,
            observedProjectHashes = Map.empty,
            transactionTargets = Set.empty
          },
      plannedApplications = []
    }

conflictPlan :: UpdatePlan
conflictPlan = minimalPlan (oneFile conflict)
  where
    conflict =
      FileConflict
        desired
        "title: user\nbody: old\n"
        "<<<<<<< current\ntitle: user\n||||||| baseline\ntitle: old\n=======\ntitle: generated\n>>>>>>> generated\n"
        OverlappingEdits
        (ObservedFile True (Just (SHA256 "current")))
        Nothing
        Nothing

unavailableConflictPlan :: UpdatePlan
unavailableConflictPlan = minimalPlan (oneFile conflict)
  where
    conflict =
      FileConflict
        desired
        "binary-current"
        "binary-current"
        (MergeDriverUnavailable "binary input")
        (ObservedFile True (Just (SHA256 "current")))
        Nothing
        Nothing

orphanPlan :: UpdatePlan
orphanPlan = minimalPlan (oneFile orphan)
  where
    orphan =
      FileOrphanEdited
        "README.md"
        FileRecord
          { hash = SHA256 "applied",
            moduleName = ModuleName "demo",
            strategy = Template,
            generatedAt = fixedTime,
            baseline = Nothing,
            applicationIds = Set.empty
          }
        "user edit"
        (ObservedFile True (Just (SHA256 "current")))
        Nothing

desired :: DesiredFile
desired =
  DesiredFile
    { path = "README.md",
      generatedContent = "title: generated\nbody: old\n",
      moduleName = ModuleName "demo",
      strategy = Template,
      applicationIds = Set.empty
    }

oneFile :: FileReconciliation -> ReconciliationPlan
oneFile reconciliation =
  ReconciliationPlan
    { applicationIds = Set.empty,
      files = Map.singleton "README.md" reconciliation,
      requiredDirectories = Set.empty
    }
