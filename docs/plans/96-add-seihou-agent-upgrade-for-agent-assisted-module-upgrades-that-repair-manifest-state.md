---
id: 96
slug: add-seihou-agent-upgrade-for-agent-assisted-module-upgrades-that-repair-manifest-state
title: "Add seihou agent upgrade for agent-assisted module upgrades that repair manifest state"
kind: exec-plan
created_at: 2026-09-18T13:18:22Z
intention: "intention_01m2tanyfae9ftvcqmaygv0960"
provenance:
  created_by:
    model: "claude-opus-5[1m]"
    harness: "claude-code"
    at: 2026-09-18T13:18:22Z
  revisions:
    - model: "claude-opus-5[1m]"
      harness: "claude-code"
      at: 2026-09-18T14:24:27Z
      mode: "update"
      note: "Defer cache swap and origin repair to plans 97 and 98; add origins-portable check"
    - model: "claude-opus-5[1m]"
      harness: "claude-code"
      at: 2026-09-18T17:34:28Z
      mode: "implement"
      note: "Implement M1-M5"
---

# Add seihou agent upgrade for agent-assisted module upgrades that repair manifest state

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

Seihou generates files into a project from reusable "modules" and records what it did in
`.seihou/manifest.json`, the *manifest*. Upgrading a module in a project is normally two
commands: `seihou upgrade <module>` refreshes the machine's installed copy of the module,
and `seihou update <module>` reconciles the project with it. Two recent initiatives,
`docs/masterplans/10-blueprint-migration-fan-out-across-a-library-cohort.md` and
`docs/masterplans/11-make-manifest-evolution-explicit-and-targeted-updates-upgrade-safe.md`,
made that path much safer. It still fails in real projects. The cause is almost never the
module itself. It is the state of the manifest: an old schema, a shared file with no
recorded answer about how its owners write it, a co-owner whose recorded version is no
longer installed, or an installed copy from a different source. Each failure has a
documented remedy, but finding and applying it costs users time. Each new failure shape has
so far been handled by writing another enhancement.

After this plan, a user who wants to upgrade a module runs one command:

```bash
seihou agent upgrade nix-haskell-flake
```

Seihou first diagnoses the project for that module without changing anything. It reads the
manifest, the installed copy, the shared-file evidence, the migration state, and a dry run
of the update. It writes those findings into an *upgrade brief*: a Markdown document that
states the current state, every failure with its stable error code, a repair playbook keyed
by those codes, the safety rules the repair must respect, and a definition of done. It then
starts an interactive coding agent session (Claude Code or Codex, the same providers
`seihou agent setup` uses) with the brief as its system prompt. The agent repairs the
manifest state through seihou's own commands, performs the upgrade, and verifies the result
with a new read-only check, `seihou agent upgrade <module> --check`. The goal is that the
*next* plain `seihou update` of that module succeeds with no agent involved.

The command never fails. It does not exit non-zero or refuse because of project state. A
missing manifest, a corrupt manifest, an unknown module name, a network timeout, a missing
`claude` binary, or a broken agent configuration each become a finding in the brief. The
brief is always written to a file whose path is printed, so the user can hand it to any
agent even when seihou cannot launch one. The only non-zero exits are unparseable
command-line syntax, which the argument parser rejects before seihou runs, and the agent
session's own exit code, which is passed through as the other `seihou agent` commands do.

You can see it working in three ways. `seihou agent --debug upgrade <module>` prints the
brief and exits 0. `seihou agent upgrade <module> --check` prints a readiness report ending
in `Upgrade readiness: ready` or `Upgrade readiness: not ready (N checks need attention)`.
A human `seihou update` failure now ends with a line pointing at `seihou agent upgrade`.


## Progress

- [x] (2026-09-18) M1: Add `seihou-cli/src/Seihou/CLI/UpgradeDiagnosis.hs` with the diagnosis types, guarded probes, readiness checks, and a read-only recovery-journal probe (`pendingUpdateRecovery` in `Update/Recovery.hs`; no core helper was needed). Also `renderUpgradeOutcome` in `ManifestUpgrade`, and exports of `errorCode` and `localModuleVersion`. `ManifestUpgradeSpec` passes unchanged (30 tests).
- [x] (2026-09-18) M1: Unit tests in `seihou-cli/test/Seihou/CLI/UpgradeDiagnosisSpec.hs` cover healthy, schema-6, evidence-unavailable, schema-5, missing-manifest, corrupt-manifest, local-origin, unknown-target, and interrupted-transaction projects, and prove diagnosis writes nothing (12 tests pass). Shared fixture helpers in `seihou-cli/test/Seihou/CLI/UpgradeFixture.hs`.
- [x] (2026-09-18) M1: Add the `origins-portable` probe and readiness check (uses `ManifestRepairOrigins.localOriginUrls` from plan 98, which had landed).
- [ ] M2: Add `AgentUpgradeOpts`, the `agent upgrade` parser, and `AgentCmdUpgrade` config keys.
- [ ] M2: Add `seihou-cli/data/upgrade-prompt.md` and `seihou-cli/src-exe/Seihou/CLI/AgentUpgrade.hs`, with brief persistence and a launch path that never fails.
- [ ] M2: E2E tests in `seihou-cli/test/Seihou/CLI/AgentUpgradeE2ESpec.hs` for `--debug`, outside-a-project, corrupt manifest, and missing provider binary.
- [ ] M3: `--check` mode and the post-session readiness summary; E2E tests.
- [ ] M4: Append the `seihou agent upgrade` hint to human `seihou update` failures; update `UpdateRenderSpec`.
- [ ] M4: Documentation: `docs/cli/agent.md`, `docs/user/agent-assistance.md`, `docs/cli/update.md`, `seihou-cli/help/agent.md`, `CHANGELOG.md`, `docs/user/CHANGELOG.md`.
- [ ] M5: Full validation (`nix fmt -- --fail-on-change`, `cabal build all`, `cabal test all`, `nix flake check`) and the manual acceptance scenario.
- [ ] M5: Write ADR 0016 and fill in Outcomes & Retrospective.


## Surprises & Discoveries

- The shared-path fixture from `UpdateSpec` records every origin as the path of a local git
  repository, so the new `origins-portable` check correctly fails on it. A "healthy"
  fixture therefore needs portable URLs. `seihou-cli/test/Seihou/CLI/UpgradeFixture.hs`
  rewrites the origins to `https://example.invalid/{alpha,beta}.git` and maps them back
  with `GIT_CONFIG_COUNT`/`url.<path>.insteadOf`, as `RepairOriginsE2ESpec` already did.
  Evidence: before the rewrite, the healthy case reported `origins-portable` as needing
  attention.
- Plans 97 and 98 had both landed before this implementation began (commits `d8c951f`
  through `5ce5152`), so the playbook and the `origins-portable` probe use them directly;
  no "before the sibling lands" text was needed.
- The update planner catches `SomeException` in several places, so interrupting it with
  `System.Timeout.timeout` would be swallowed and reported as a planning error. The
  bounded probes therefore run on a worker thread and the deadline is enforced on the
  wait for its result (`guardedWithin`).
- The recovery code recovers *every* directory under `.seihou/transactions`, committed or
  not, so "pending recovery" is simply "some directory exists there".


## Decision Log

- Decision: The command is `seihou agent upgrade MODULE [PROMPT]`, a new subcommand of the
  existing `seihou agent` group, and not a flag on `seihou update` or `seihou upgrade`.
  Rationale: The `agent` group already owns provider, model, effort, trace, and `--debug`
  handling and the interactive launch path. `seihou update` must stay deterministic and
  scriptable with stable JSON (`docs/cli/update.md`), and its failures are correct refusals.
  They should be explained and repaired, not weakened.
  Date: 2026-09-18

- Decision: Seihou diagnoses and the agent repairs. The diagnosis phase is strictly
  read-only: it writes nothing under the project, the installed cache, or the manifest. If
  an interrupted update transaction is pending, the update dry-run probe is skipped and the
  brief reports it instead.
  Rationale: `withProjectUpdate` calls `recoverAtEntry`
  (`seihou-cli/src/Seihou/CLI/Update.hs`) before planning, and recovery writes. A diagnostic
  that mutates state would make "the command never fails" unsafe. A failed or interrupted
  diagnosis must leave nothing half-done. The agent runs `seihou update --dry-run` itself
  when the brief tells it to, which performs the recovery in the open.
  Date: 2026-09-18

- Decision: "Never fails" means seihou never exits non-zero or refuses because of project,
  machine, network, or configuration state. Every probe is wrapped in an exception handler
  and, where it can touch the network, a timeout. Its failure becomes a finding. The brief
  is always written to a file and its path printed. Launch failures fall back to printing
  how to use that file. The exceptions are argument-parser rejections and passing through
  the interactive session's own exit code.
  Rationale: This is the user's explicit requirement ("should never fail since the current
  DX is horrible"). Passing through the agent's exit code matches `seihou agent setup` and
  `seihou agent run`. It reports the session the user ran, not a seihou refusal.
  Date: 2026-09-18

- Decision: The definition of done is machine-checkable and exposed as
  `seihou agent upgrade MODULE --check`, which the agent is told to run and which seihou
  also runs after the session ends. `--check` always exits 0; its verdict is the final line
  of its output.
  Rationale: The user's goal is that future upgrades need no agent. That holds exactly
  when the checks behind a plain `seihou update MODULE` pass. Making the checks a command
  gives the agent, the user, and the tests one verdict. Exit 0 keeps the never-fail promise.
  Scripts read the stable last line instead of the exit code.
  Date: 2026-09-18

- Decision: Diagnosis stays local except for the update dry-run. It does not query remotes
  for the latest module version (that is `seihou outdated`). The update dry-run probe runs
  under a 180-second timeout.
  Rationale: Candidate planning may clone a remote, which is the most likely thing to hang.
  Finding the newest release is part of the upgrade the agent performs with
  `seihou outdated` and `seihou upgrade`, where progress is visible.
  Date: 2026-09-18

- Decision: The brief file lives outside the project, under
  `$XDG_STATE_HOME/seihou/agent-upgrade/` (via `getXdgDirectory XdgState "seihou"`), and
  falls back to the system temporary directory, then to standard output.
  Rationale: The brief records machine-local facts such as installed paths. ADR 0001 keeps
  those out of anything checked into the project, and `.seihou/` sits beside the
  checked-in manifest.
  Date: 2026-09-18

- Decision: Editing the manifest by hand is allowed only as the last resort the brief
  describes. The agent must first save a backup under the brief's directory. It must never
  invent an origin, mark a path `additive-only` without reading every owner's operations
  for it, delete file records or applications to get past a gate, or lower a recorded
  version. It must re-validate with `seihou status`, `seihou manifest upgrade --dry-run`,
  and `--check`.
  Rationale: These are the invariants of ADR 0003, ADR 0005, ADR 0012, and ADR 0014, and
  an agent under pressure to "make it pass" is the most likely thing to break them. Saying
  so in the brief costs nothing. A backup makes every manual repair reversible.
  Date: 2026-09-18

- Decision: The two failure shapes seen in the reported project are fixed in seihou
  itself by sibling plans, not worked around in the brief. `docs/plans/97-fetch-a-co-owner-s-recorded-release-to-certify-shared-write-evidence.md`
  makes `seihou update` fetch a co-owner's exact recorded release. `docs/plans/98-repair-machine-local-artifact-origins-and-stop-recording-them.md`
  adds `seihou manifest repair-origins` and stops local paths reaching the manifest. This
  plan drops its M1 prototype of a manual cache swap. It adds an `origins-portable`
  readiness check, and its playbook uses those commands instead of hand edits. The
  recommended implementation order is 98, then 97, then 96.
  Rationale: In `mori://tan/mls-service-v2` an agent had to do two things. It
  hand-edited `.seihou/manifest.json` to replace a recorded origin that was a local path
  (`…/bokuno/seihou-modules`) with the GitHub URL. It also temporarily swapped the global
  cache's `nix-haskell-flake` 0.24.0 for 0.13.2 so certification could read the recorded
  version. The first failure lasts until someone fixes it. The second recurs whenever the
  cache moves ahead of a project. Making seihou handle both serves the goal that future
  upgrades need no agent. The agent path remains for failures that need judgment.
  Date: 2026-09-18

- Decision: The library diagnosis module is named `Seihou.CLI.UpgradeDiagnosis` and the
  executable handler `Seihou.CLI.AgentUpgrade`.
  Rationale: The handler needs `Data.FileEmbed` to embed the prompt template and
  `Seihou.CLI.Commands` for its options, so the placement convention traps it in
  `src-exe/`. Everything else is testable library code. The names avoid a clash with the
  existing `Seihou.CLI.Upgrade` (cache refresh) and `Seihou.CLI.ManifestUpgrade`.
  Date: 2026-09-18


- Decision: `ReadinessStatus` is `Ready | NeedsAttention | CouldNotDetermine` with no
  payload, and every `ReadinessCheck` carries a `detail` line. The plan's sketch put a
  reason in two of the constructors and a detail beside it, which duplicated the text.
  Rationale: one field to render and assert on; the report line is always
  `mark name detail`.
  Date: 2026-09-18

- Decision: The diagnosis types grew beyond the sketch: `InstalledCopy` (name, resolved
  directory, installed and recorded versions), `SharedUnknownPath`, `LocalOriginRecord`,
  `ManifestSchemaUnreadable`, and `UpdateProbe.headline`. The installed-copy probe covers
  every module instance of the matched applications, not only a module named like the
  target, so a recipe target is checked too. The manifest-upgrade dry run is also bounded
  by the timeout, because since plan 97 it can fetch recorded releases.
  Rationale: the brief and the report need these facts, and a recipe target has no module
  of its own name.
  Date: 2026-09-18

- Decision: `saveBrief :: Text -> Text -> IO BriefLocation` became two functions,
  `createBriefDirectory :: Text -> IO (Either Text FilePath)` and
  `writeBrief :: Either Text FilePath -> Text -> IO BriefLocation`.
  Rationale: the brief names its own directory as `{{backup_dir}}`, so the directory must
  exist before the brief is rendered. Both still never throw.
  Date: 2026-09-18


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

This section describes the repository as it stands at commit `746c049` and defines the
terms the plan uses.

**The repository.** Seihou is a Haskell project (GHC 9.12, `GHC2024`, `effectful`, Dhall,
`optparse-applicative`, Nix flakes). It has three Cabal packages. `seihou-core/` holds
domain types and the engine. `seihou-cli/` holds a library, `seihou-cli-internal`, under
`seihou-cli/src/`, and the `seihou` executable under `seihou-cli/src-exe/`. The third,
`seihou-okf-extension`, is not touched here. Build with `cabal build all` and test with
`cabal test all` from the repository root. `nix flake check` additionally runs two
convention checkers, described next, which the pre-commit hook also runs.

**Module placement (enforced).** New code goes in the library (`seihou-cli/src/`) unless it
imports `Options.Applicative`, `Data.FileEmbed`, `GitHash`, or `Paths_seihou_cli`, or
imports another executable-only module such as `Seihou.CLI.Commands`. A new executable
module must be listed in `other-modules` of `executable seihou` in
`seihou-cli/seihou-cli.cabal`, and `nix/check-cli-module-placement.sh` fails the build if it
has no such trapping import. Tests (`seihou-cli/test/`) can import only the library, so any
behavior that needs a test must live in `src/`.

**Record conventions (enforced).** Every `data` record field is strict (`!`). Field names
carry no type prefix. Records use an explicit deriving strategy and derive `Generic`.
Fields are read and written through `generic-lens` labels (`x ^. #field`,
`x & #field .~ v`), never record dot syntax or record update syntax. Each module that uses
`#labels` adds `import Data.Generics.Labels ()` itself. `nix/check-record-conventions.sh`
enforces this.

**Terms.**

- *Manifest*: `.seihou/manifest.json`, committed to git, the only record of what seihou
  applied (ADR 0004). Its `version` field is the *schema version*, currently 7
  (`currentManifestVersion` in `seihou-core/src/Seihou/Manifest/Types.hs`). Version 6 is
  the oldest the ordinary decoder reads (`oldestDecodableManifestVersion`).
- *Application*: one recorded top-level `seihou run` of a module or recipe, with its saved
  inputs (`AppliedComposition`). Humans name applications through
  `Seihou.CLI.ApplicationDisplay.applicationLabel`, for example
  `exec-plan [skill.name=exec-plan]`. Never display the id hash (ADR 0015).
- *Installed copy*: the machine-local copy of a module under
  `~/.config/seihou/installed/<name>/`, with provenance in `.seihou-origin.json`.
  `seihou upgrade <name>` refreshes it; `seihou install <url>` creates it.
- *Shared-write evidence*: for every managed file, `sharedWriteMode` records how its owners
  write it: `additive-only`, `requires-ownership-closure`, or `unknown` (ADR 0012,
  ADR 0014). A targeted update needs a known answer for every path it shares with an
  application it is not updating.
- *Targeted update*: `seihou update <target>`, which updates only the named applications.
- *Readiness*: the state in which a plain `seihou update <module>` would plan without a
  manifest-state error. This plan introduces the term. M1 defines it exactly as a list of
  checks.
- *Upgrade brief*: the Markdown document this plan's command writes and gives to the agent.

**How an update fails today.** `seihou-cli/src/Seihou/CLI/Update.hs` exports
`withProjectUpdate :: UpdateRequest -> (Either UpdateError UpdatePlan -> IO a) -> IO a`,
the planning entry point. `UpdateRequest` (in `seihou-cli/src/Seihou/CLI/Update/Types.hs`)
carries `selection` (`NamedUpdateTargets [Text]`), `varOverrides`, `reconfigure`,
`promptPolicy` (`ForbidPrompts` for non-interactive use), `commandPolicy`, `dryRun`,
`allowDowngrade`, and `includeSharedOwners`. `UpdateError` has one constructor per failure,
and `seihou-cli/src/Seihou/CLI/Update/Render.hs` maps each to a stable code
(`errorCode`) and a prose message (`errorMessage`). The render module exports
`renderUpdateHuman :: Bool -> UpdateOutput -> Text`, `errorOutput`, and `planOutput`. The
codes the brief's playbook must cover are: `manifest_missing`, `manifest_unreadable`,
`manifest_upgrade_required`, `no_recorded_applications`,
`legacy_update_requires_one_target`, `target_not_found`,
`shared_path_requires_applications`, `shared_write_evidence_unavailable`,
`candidate_clone_failed`, `candidate_repository_invalid`, `candidate_artifact_missing`,
`candidate_artifact_unresolved`, `candidate_artifact_ambiguous`, `candidate_load_failed`,
`candidate_downgrade`, `candidate_version_invalid`, `conflicting_prior_versions`,
`variable_errors`, `configuration_failed`, `migration_plan_failed`,
`migration_stage_failed`, `composition_failed`, `reconciliation_failed`,
`unresolved_paths`, `recovery_failed`, `plan_stale`, `transaction_failed`,
`migration_failed`, `changed_after_migration_command`, `command_failed`,
`cache_publication_failed`, and `manifest_write_failed`. The executable handler
`seihou-cli/src-exe/Seihou/CLI/Update.hs` prints `Update failed [<code>]: <message>` and
exits 1.

Planning is not read-only. `planProjectUpdateIn` calls `recoverAtEntry`, which calls
`recoverServiceBackups` (`seihou-cli/src/Seihou/CLI/Update/Recovery.hs`) and
`recoverIncompleteTransactions` (`seihou-core/src/Seihou/Engine/UpdateTransaction.hs`).
Those roll an interrupted transaction back from its journal. A dry-run planning call
also clones remote candidates into a temporary directory, which needs the network.

**Manifest upgrade.** `seihou-cli/src/Seihou/CLI/ManifestUpgrade.hs` exports
`runManifestUpgrade :: ManifestUpgradeOpts -> IO UpgradeOutcome`, which reads the
manifest in the current directory. With `dryRun = True` it writes nothing. `UpgradeOutcome`
is `UpgradeNotNeeded`, `UpgradeWouldWrite`, `UpgradeWritten`, `UpgradeBlocked`, or
`UpgradeFailed`. The command handler `handleManifestUpgrade` in the same module renders it
with `formatUpgradeReport`, `formatUpgradeRefusal`, and `formatStillUnknown`, printing
directly to stdout. The schema 5→6 step infers artifact origins from machine-local paths,
so only this explicit command may perform it (ADR 0005). The 6→7 step is lossless and
`seihou update` performs it inside its own transaction.

**Artifact guard.** `seihou-cli/src/Seihou/CLI/ManifestGuard.hs` exports
`checkAppliedArtifactsFor :: FilePath -> [FilePath] -> Maybe (Set ModuleName) -> Manifest -> IO [ArtifactCheck]`,
`blockingChecks`, and `summarizeCheck :: ArtifactCheck -> Maybe Text`. Together they say
whether the installed copy of each recorded module is older than, or from a different
source than, what the manifest records (ADR 0003).

**Target matching.** `seihou-cli/src/Seihou/CLI/Update/Selection.hs` exports
`matchApplications :: UpdateSelection -> Manifest -> Either UpdateError MatchedApplications`,
`availableTargets`, and `applicationRef`. Matching the upgrade target through this same
function guarantees that the brief and `seihou update` agree about what the name means.

**Existing agent commands.** `seihou agent` subcommands are parsed in
`seihou-cli/src-exe/Seihou/CLI/Commands.hs` (`AgentCommand`, `agentCommandParser`,
`SetupOpts`, `agentSetupParser`) and dispatched in `seihou-cli/src-exe/Main.hs`. The
simplest model to copy is `seihou-cli/src-exe/Seihou/CLI/Setup.hs`. It embeds
`seihou-cli/data/setup-prompt.md` with `embedFile` and fills `{{key}}` placeholders with
`Seihou.CLI.AgentLaunch.substitute`. For `claude-cli` and `codex-cli` it launches an
interactive session through `Seihou.CLI.AgentLaunchExec.launchConfiguredAgent`. For the API
providers it makes a one-shot completion through `runAgentCompletion`, and under `--debug`
it prints the prompt. Two parts of that path call `exitFailure`, which this plan must avoid.
First, `launchClaude` in `seihou-cli/src-exe/Seihou/CLI/AgentLaunchExec.hs` exits when
`claude` is not on `PATH`. Second, `resolveAgentModelConfigFor` in `Main.hs` exits when the
agent configuration is invalid. Per-command configuration keys come from
`AgentCommandName` in `seihou-cli/src/Seihou/CLI/AgentConfig.hs` (`AgentCmdSetup` gives
`agent.setup.provider`, and so on), and `seihou agent config` lists every constructor.
`Seihou.CLI.AgentLaunch.setupAllowedTools` is the Claude Code tool allowlist
setup uses.

**Tests.** The CLI test suite is registered in `seihou-cli/test/Main.hs` (a `tasty` tree of
`hspec` specs via `testSpec`) and listed in the test-suite `other-modules` of
`seihou-cli/seihou-cli.cabal`. `seihou-cli/test/Seihou/CLI/SeihouBinary.hs` locates the
built binary for end-to-end tests. `seihou-cli/test/Seihou/CLI/UpdateSpec.hs` exports
`prepareSharedPathFixture :: CoOwnerWriteMode -> FilePath -> IO SharedPathFixture`. It
builds a project where applications `alpha` and `beta` co-own `.gitignore`, with a
private `XDG_CONFIG_HOME` in the fixture's `xdgHome`.
`seihou-cli/test/Seihou/CLI/UpdateE2ESpec.hs` shows how to run the binary against it
(`runSeihouShared`), how to make evidence unavailable by moving `betaInstalledPath` aside,
and how to downgrade the manifest to schema 7 with an unknown path.

**Relevant ADRs** (all local, in `docs/adr/`):

- [ADR 0001](../adr/0001-manifest-is-a-checked-in-machine-independent-artifact.md): the
  manifest is committed and machine-independent. The brief, which holds machine-local
  paths, therefore lives outside the project.
- [ADR 0003](../adr/0003-a-stale-or-substituted-artifact-is-a-hard-error.md): generating
  from an installed copy that is older than, or from a different source than, the manifest
  records is refused. `--allow-downgrade` is the only override. The agent must not work
  around this by editing recorded versions.
- [ADR 0004](../adr/0004-the-manifest-is-the-only-record-of-applied-state.md): there is no
  lockfile. This command adds no new project state file.
- [ADR 0005](../adr/0005-legacy-manifests-convert-through-an-explicit-command.md): schema
  5 and earlier convert only through `seihou manifest upgrade`, which reports its
  inferences. The agent runs it with `--dry-run` first and shows the user the inferred
  origins.
- [ADR 0012](../adr/0012-an-additive-co-write-is-not-a-shared-path-conflict.md): only
  `append-line-if-absent` and `append-section` are additive. A path any owner writes
  wholesale requires every owner in the update.
- [ADR 0014](../adr/0014-every-semantic-manifest-change-advances-the-schema-version.md):
  schema changes go through ordered, classified steps.
- [ADR 0015](../adr/0015-diagnostics-name-things-as-users-do-and-never-fall-back-to-show.md):
  human output names applications through `ApplicationDisplay`, never falls back to
  `show`, and leads each error with its remedy. The brief and the `--check` report follow
  the same rules.
- [ADR 0011](../adr/0011-a-migration-receipt-asserts-a-claim-about-the-project.md) is
  adjacent. `seihou agent migrate` is the agent path for *blueprint* migrations, which are
  a different mechanism: prompts shipped by a library for its consumers. This plan does
  not touch them. The brief mentions them only so the agent does not confuse the two.

**Sibling plans.** Two plans remove the failures observed so far, and this plan's
diagnosis and playbook refer to what they add.
`docs/plans/97-fetch-a-co-owner-s-recorded-release-to-certify-shared-write-evidence.md`
lets certification clone a co-owner's recorded remote and read the commit that declares
the recorded version, so a cache that moved ahead no longer causes
`shared_write_evidence_unavailable`.
`docs/plans/98-repair-machine-local-artifact-origins-and-stop-recording-them.md` adds:

- `isMachineLocalOriginUrl` in `seihou-core/src/Seihou/Core/ArtifactIdentity.hs`;
- `localOriginUrls` and the `seihou manifest repair-origins [--dry-run] [--set NAME=URL]`
  command in `seihou-cli/src/Seihou/CLI/ManifestRepairOrigins.hs`;
- the rule that a local-path `sourceUrl` is recorded as `LocalOrigin`.

If this plan is implemented before either sibling, write the corresponding playbook
entries as described in the sibling's absence (noted inline below). Add a Progress item to
revise them when the sibling lands.

No cross-repository ADR governs this work. The consumer that has repeatedly hit these
failures is `mori://tan/mls-service-v2`. It is named only as motivation; nothing here
depends on it.


## Plan of Work

The work has five milestones. M1 builds the diagnosis as a tested library with no user
surface. M2 adds the command and the brief. M3 adds the machine-checkable definition of
done. M4 points existing failures at the new command and documents it. M5 validates
everything and records the durable decision.

### Milestone 1: A read-only, never-throwing upgrade diagnosis

At the end of this milestone the library contains
`seihou-cli/src/Seihou/CLI/UpgradeDiagnosis.hs`, which answers one question: what is the
state of this project with respect to upgrading this module, and what stands between it
and a plain `seihou update` succeeding? Nothing is user-visible yet. Acceptance is a new
spec file whose tests pass, including one that proves diagnosis modifies no byte under the
project or the fixture's `XDG_CONFIG_HOME`.

Create the module with the types in Interfaces and Dependencies. The entry point is
`diagnoseUpgrade :: DiagnosisEnv -> Text -> IO UpgradeDiagnosis`. It runs these probes in
order. Each is wrapped by a helper `guarded :: Text -> IO a -> IO (Probe a)` that catches
`SomeException` (use `Control.Exception.try` and `displayException`) and returns
`ProbeFailed label message` instead of throwing. Probes that can block also get a
`System.Timeout.timeout` and return `ProbeTimedOut label seconds`.

1. *Manifest document.* Check that `<root>/.seihou/manifest.json` exists. Read it as an
   `Aeson.Value` and obtain its schema with `documentSchemaVersion` from
   `Seihou.Manifest.Upgrade`. Then try `manifestFromJSON` from `Seihou.Manifest.Types`.
   Record present/absent, raw-JSON parse failure text, schema version, and decode failure
   text separately. A schema-5 manifest parses as JSON but does not decode, and the brief
   must say which one happened.
2. *Recovery journal.* Add a read-only function
   `pendingUpdateRecovery :: FilePath -> IO Bool` beside the recovery code. It performs the
   same discovery as `recoverServiceBackups` and `recoverIncompleteTransactions` but acts on
   nothing. Put it in `seihou-cli/src/Seihou/CLI/Update/Recovery.hs`, and add a core helper
   in `seihou-core/src/Seihou/Engine/UpdateTransaction.hs` if the transaction journal's
   location is private to that module. Read both recovery functions first to learn exactly
   which files they look for.
3. *Target.* When the manifest decodes, call
   `matchApplications (NamedUpdateTargets [target]) manifest`. Record the matched
   applications as `ApplicationRef`s (via `applicationRef`), or the `UpdateTargetNotFound`
   alternatives from `availableTargets`, or the fact that the manifest has no recorded
   applications, which is the legacy case. Also record the recorded version of every
   `AppliedModule` whose name equals the target.
4. *Installed copy.* Call
   `checkAppliedArtifactsFor root searchPaths (Just (Set.singleton target)) manifest`, where
   `searchPaths` comes from `Seihou.Core.Module.defaultSearchPaths`. Keep the checks and
   their `summarizeCheck` text. Also record the installed directory and the version the
   installed `module.dhall` declares, if any; `ManifestGuard.localModuleVersion` does this
   and can be exported if it is not already.
5. *Shared-write evidence.* From the decoded manifest, list every file record whose owners
   include one of the matched applications and whose `sharedWriteMode` is `unknown`. For
   each, list its other owners by `applicationLabel`. Record the project-wide count of
   `unknown` paths as context.
6. *Manifest upgrade dry run.* Run `runManifestUpgrade` with `dryRun = True`,
   `force = False`, `targetVersion = Nothing`, under a `withCurrentDirectory root` bracket
   because the function reads the current directory. Render the outcome to text. To do
   that, refactor `handleManifestUpgrade` so that its printing comes from a new exported
   pure function `renderUpgradeOutcome :: UpgradeOutcome -> Text`. The handler keeps its
   exit behavior and prints the function's result. `ManifestUpgradeSpec` must stay green,
   and the command's output must stay byte-identical.
7. *Update dry run.* Skip this probe, and say why, when the recovery probe found pending
   work or the manifest does not decode. Otherwise call `withProjectUpdate` with
   `NamedUpdateTargets [target]`, `dryRun = True`, `promptPolicy = ForbidPrompts`,
   `commandPolicy = RunChangedCommands`, `reconfigure = False`, `allowDowngrade = False`,
   `includeSharedOwners = False`, and no overrides. Run it inside
   `withCurrentDirectory root`, because `planProjectUpdateIn` uses the current directory.
   Wrap it in a 180-second timeout. Keep the rendered result
   (`renderUpdateHuman False (errorOutput err)` or
   `renderUpdateHuman False (planOutput plan)`), the error code if any (export
   `errorCode` from `Seihou.CLI.Update.Render` if it is not exported), and whether the plan
   is a no-op (`isUpdateNoOp`).
8. *Portable origins.* From the decoded manifest, collect every recorded origin whose URL
   is a machine-local path. Use `ManifestRepairOrigins.localOriginUrls` if plan 98 has
   landed. Otherwise walk the six origin fields yourself (`modules`, application
   `targetOrigin`, instance `origin`, `recipe`, `blueprint`, `blueprintMigrations`) with a
   local copy of the prefix test. Record each path with the artifacts recorded under it.
9. *Git state.* Run `git status --porcelain` and `git rev-parse --is-inside-work-tree` with
   `System.Process.readProcessWithExitCode`, also guarded. Record whether the tree is a
   repository and whether it is clean. The brief tells the agent to ask before working on
   a dirty tree.

Then compute `readiness :: UpgradeDiagnosis -> [ReadinessCheck]`, a pure function with
exactly these checks, in this order. Each check is `Ready`, `NeedsAttention reason`, or
`CouldNotDetermine reason`.

- `manifest-readable`: the manifest exists and decodes.
- `manifest-schema-current`: the document schema equals `currentManifestVersion`. A
  schema-6 manifest is `NeedsAttention`, because `seihou update` can step it to 7 itself
  but a plain upgrade should not depend on that. A schema-5 or older manifest is
  `NeedsAttention` with the reason `seihou manifest upgrade`.
- `no-interrupted-update`: the recovery probe found nothing.
- `target-recorded`: the target matches at least one recorded application. A legacy
  manifest with no recorded applications is `NeedsAttention`, and the reason names the
  one-target seeding update.
- `installed-copy-trusted`: no blocking artifact check for the target.
- `origins-portable`: no recorded origin in the manifest is a machine-local path. The
  reason names `seihou manifest repair-origins`. This check is project-wide, because one
  such origin on a co-owner is enough to break a targeted update of the target.
- `shared-evidence-known`: no `unknown` path is shared between the target's applications
  and another application.
- `update-plans-cleanly`: the update dry run returned a plan or a no-op. An error is
  `NeedsAttention` carrying its code. A timeout or skipped probe is `CouldNotDetermine`.

`isReady` is true exactly when every check is `Ready`. The git state is reported but is not
a readiness check. A dirty tree does not make a future upgrade need an agent.

Finally, write pure renderers that produce the brief's variable sections and the `--check`
report. They are described under Interfaces and Dependencies. They must name applications
only through `applicationLabel` and never `show` a value, per ADR 0015.

Write `seihou-cli/test/Seihou/CLI/UpgradeDiagnosisSpec.hs`, register it in
`seihou-cli/test/Main.hs` and the test-suite `other-modules`, and build its projects with
`prepareSharedPathFixture` from `Seihou.CLI.UpdateSpec`. Because diagnosis reads
`XDG_CONFIG_HOME` through `defaultSearchPaths`, pass search paths in through
`DiagnosisEnv` rather than reading the environment inside probes. Then tests can point at
the fixture's `xdgHome` without changing the process environment. The cases are:

- A healthy fixture (`CoOwnerAppends`, schema 7) where every check is `Ready`.
- A schema-6 fixture (`CoOwnerAppendsPredatingEvidence`), where
  `manifest-schema-current` and `shared-evidence-known` need attention and
  `update-plans-cleanly` is `Ready`, because the update certifies the path.
- The evidence-unavailable setup copied from `UpdateE2ESpec` (schema 7, unknown path, beta
  moved aside), where `update-plans-cleanly` needs attention with code
  `shared_write_evidence_unavailable`.
- A hand-written schema-5 manifest (reuse the literal from
  `seihou-cli/test/Seihou/CLI/SharedManifestE2ESpec.hs`'s `legacyManifest` if it fits),
  where `manifest-readable` needs attention and the manifest-upgrade section is present.
- No manifest, where the result is not an exception and `manifest-readable` needs
  attention.
- A manifest containing `{not json`, which produces the same kind of result.
- A schema-7 fixture whose beta origins are rewritten to `/nonexistent/seihou-modules`,
  where `origins-portable` needs attention and names beta.
- An unknown target `nope`, where `target-recorded` needs attention and lists alpha and
  beta.
- A pending transaction created by writing the journal file the recovery code looks for,
  where `no-interrupted-update` needs attention and the update probe is skipped.
- A write-nothing property. Snapshot every file under the project root and `xdgHome`
  (path plus bytes) before and after `diagnoseUpgrade` in each fixture, and assert
  equality.

**No cache-swap prototype.** An earlier revision of this plan prototyped a manual
sequence for swapping a co-owner's recorded version into the install cache. The reported
project showed that the sequence works but is exactly the toil to remove, so plan 97
builds it into `seihou update`. Do not put a cache-swap procedure in the brief. See the
playbook entry for `shared_write_evidence_unavailable` in M2.

### Milestone 2: The command and the upgrade brief

At the end of this milestone `seihou agent upgrade MODULE [PROMPT]` exists.
`seihou agent --debug upgrade alpha` in a fixture prints the full brief and exits 0. With
`claude` absent from `PATH` it prints where the brief was saved and how to use it, and
exits 0.

In `seihou-cli/src-exe/Seihou/CLI/Commands.hs`:

- Add `AgentUpgrade AgentUpgradeOpts` to `AgentCommand`.
- Add the `AgentUpgradeOpts` record (fields in Interfaces). Export it with the others.
- Add `command "upgrade" agentUpgradeInfo` to `agentCommandParser`, and add a line
  `upgrade     Upgrade a module with an agent that repairs manifest state` to the
  subcommand list in `agentInfo`'s footer.
- Model the parser on `agentSetupParser`. Take a required `MODULE` argument, an optional
  `PROMPT` argument, the shared `providerOption`, `modelOption`, `effortOption`, and
  `traceOption`, and a `--check` switch that M3 uses. Leave `--check` parsed but unused
  until M3.
- Give it a `progDesc` and examples, as `agentSetupInfo` has.

In `seihou-cli/src/Seihou/CLI/AgentConfig.hs`, add `AgentCmdUpgrade` to `AgentCommandName`
after `AgentCmdMigrate`, with segment `"upgrade"`. Because `allAgentCommands` enumerates
the type, `seihou agent config` lists it automatically. Update the expected output in
`seihou-cli/test/Seihou/CLI/AgentConfigShowSpec.hs` and any spec that enumerates commands.
`artifactKind` falls through to `"blueprint"`, which is harmless because `agent upgrade`
loads no artifact launch declaration. Check that this is so, and add an explicit case if a
test or the output shows otherwise.

In `seihou-cli/src-exe/Main.hs`, dispatch `AgentUpgrade opts`. Do not use
`resolveAgentModelConfigFor`, because it exits on a configuration error. Call
`loadAgentModelConfigFor AgentCmdUpgrade ...` directly. On `Left err`, keep the error text
as a finding and fall back to the built-in default configuration for `claude-cli`: find
the function `AgentConfig` uses for defaults and reuse it. Pass both the configuration and
the optional configuration error to `handleAgentUpgrade`.

Add `upgradeAllowedTools :: [String]` to `seihou-cli/src/Seihou/CLI/AgentLaunch.hs`. It is
`setupAllowedTools` plus `Bash(cp *)`, `Bash(mv *)`, `Bash(diff *)`, `Bash(mktemp *)`,
`Bash(find *)`, `Bash(head *)`, `Bash(tail *)`, and `Bash(jq *)`, with duplicates removed.
Anything else, such as a project build, prompts the user in the session as usual.

Create `seihou-cli/data/upgrade-prompt.md`. It is the fixed part of the brief, with
`{{placeholders}}` for the diagnosis sections. Write it in the direct second-person style of
`seihou-cli/data/setup-prompt.md`. Its sections, in order:

1. *Role and goal.* The agent upgrades `{{module}}` in `{{cwd}}` to the newest available
   release. It leaves the manifest in a state where the next plain `seihou update
   {{module}}` needs no agent. The user's own request, if given, is `{{user_request}}`.
2. *Current state.* The placeholders `{{seihou_version}}`, `{{diagnosis_summary}}` (the
   readiness report), `{{manifest_section}}`, `{{target_section}}`,
   `{{installed_section}}`, `{{shared_evidence_section}}`,
   `{{manifest_upgrade_section}}`, `{{update_dry_run_section}}`, `{{git_section}}`, and
   `{{findings_section}}`. Findings are probe failures, timeouts, and configuration
   fallbacks.
3. *Upgrade procedure.* In order:
   - Confirm with the user if the tree is dirty.
   - `seihou outdated` to find the newest release.
   - `seihou upgrade {{module}}` to refresh the installed copy.
   - `seihou update {{module}} --dry-run` and review it with the user.
   - `seihou update {{module}}`.
   - `seihou agent upgrade {{module}} --check` until it prints
     `Upgrade readiness: ready`.
   - Offer a Conventional Commit of the changed paths.
4. *Repair playbook.* One subsection per error code listed in Context and Orientation.
   Each says what the code means in plain words and gives the commands that repair it.
   The important entries are:
   - `manifest_upgrade_required`: run `seihou manifest upgrade --dry-run`, show the
     inferred origins, then run it, never with `--force` unless the user agrees after seeing
     which artifacts are missing.
   - `shared_write_evidence_unavailable`. Once plan 97 has landed, the update already
     tried to fetch the recorded release, and the message says why that failed. If the
     reason is a machine-local recorded origin, run `seihou manifest repair-origins`,
     dry run first, and retry. If no commit of the remote declares the recorded version,
     explain that to the user, who decides whether to update the co-owner too
     (`--include-shared-owners`, which updates it in full). Never swap versions in
     `~/.config/seihou/installed/`. Before plan 97 lands, the entry says to install the
     recorded version and explains the limitation.
   - An origin mismatch reported by `seihou status`, the artifact guard, or certification
     ("installed here from a different origin than recorded"). If the recorded origin is
     a local path, run `seihou manifest repair-origins --dry-run`, show the report, and
     then run it, passing `--set NAME=URL` for anything unresolved, with the user's
     confirmation of the URL. If both origins are remote URLs, the installed copy really
     is from a different source. Ask the user which is right, and reinstall from the
     recorded origin (`seihou install <url> --force`) rather than editing the manifest.
   - `shared_path_requires_applications`: name every owner as a target, or use
     `--include-shared-owners` after telling the user it updates those applications in
     full.
   - `legacy_update_requires_one_target` and `no_recorded_applications`: run one
     `seihou update {{module}}` to seed the record.
   - `candidate_downgrade`: explain the downgrade and never pass `--allow-downgrade`
     without consent.
   - `unresolved_paths`: resolve conflicts with the user in an interactive `seihou update`.
   - `recovery_failed`, `plan_stale`, and a pending recovery found by diagnosis: run
     `seihou update --dry-run` once to let recovery run, then diagnose again.
   - `variable_errors`: supply values with `--var` or `seihou config set`, asking the user
     for anything that is not already recorded.
5. *Safety rules.* The Decision Log rules on manual manifest edits, stated as rules: back up
   to `{{backup_dir}}` first; never invent origins; never mark `additive-only` without
   reading every owner's operations for the path; never delete records to get past a gate;
   never lower a recorded version; never pass `--force` or `--allow-downgrade` without the
   user's agreement. After any manual edit, run `seihou status`,
   `seihou manifest upgrade --dry-run`, and the `--check` command. Blueprint migrations
   (`seihou agent migrate`) are a different mechanism and are in scope only if the user
   asks.
6. *Finish with a repair report.* Tell the user, in a short section titled
   `Repair report`, which checks failed at the start, what fixed each one, and whether any
   manual manifest edit was needed. If one was, say which seihou command could not express
   the fix. That tells the maintainers what to automate next.

Create `seihou-cli/src-exe/Seihou/CLI/AgentUpgrade.hs` exporting
`handleAgentUpgrade :: Bool -> Text -> AgentModelConfig -> Maybe Text -> AgentUpgradeOpts -> IO ()`.
The arguments are debug, the seihou version text, the resolved configuration, the
configuration-fallback message, and the options. Pass the version text from
`Seihou.CLI.Version`, which is where the `GitHash`-derived version lives. Read that module
to find the exported function. List `Seihou.CLI.AgentUpgrade` in `executable seihou`'s
`other-modules`. The handler:

1. Builds `DiagnosisEnv` from the current directory and `defaultSearchPaths`.
2. Runs `diagnoseUpgrade`. Diagnosis never throws, but wrap the call in one outer `try`
   anyway. If something escapes, the brief says so and the command continues with an
   empty diagnosis.
3. Renders the brief with `substitute` over the embedded template.
4. Saves the brief with `saveBrief :: Text -> Text -> IO BriefLocation` from
   `UpgradeDiagnosis`. The path is
   `<XdgState>/seihou/agent-upgrade/<UTC yyyymmddThhmmssZ>-<module>/brief.md`; the
   directory is also `{{backup_dir}}`. Fall back to the canonical temporary directory,
   then to `BriefNotSaved reason`.
5. Prints one line to stderr: `Upgrade brief: <path>`, or the reason it could not be saved.
6. Under `--debug`, prints the brief to stdout and exits 0.
7. For `claude-cli` or `codex-cli`, first checks with `findExecutable` that the binary is on
   `PATH`. If it is missing, prints the fallback text: the brief path and a one-line
   example, `claude --append-system-prompt "$(cat <path>)"`, or "open the file in any
   coding agent". It then exits 0. Otherwise it calls `launchConfiguredAgent
   modelConfig upgradeAllowedTools False brief userPrompt` inside a `try`. A thrown
   exception prints the same fallback and exits 0. A returned `ExitCode` is kept for step 8.
8. For `anthropic` or `openai`, runs a one-shot completion as `Setup.hs` does. On `Left`,
   prints the error as a finding plus the fallback text, and exits 0. On success, prints
   the response and exits 0.
9. M3 inserts the post-session summary here. Then the handler exits with the session's
   exit code.

Write `seihou-cli/test/Seihou/CLI/AgentUpgradeE2ESpec.hs`, registered like the others. Run
the binary with `XDG_CONFIG_HOME` and `XDG_STATE_HOME` pointed into the temporary root. The
cases are:

- `agent --debug upgrade alpha` on the schema-6 fixture. Exit 0; stdout contains
  `seihou agent upgrade alpha --check`, the heading of the repair playbook, `schema 6`, and
  `.gitignore`. Stdout contains no 64-character hex digest. The project and manifest bytes
  are unchanged.
- The same command in an empty temporary directory. Exit 0; the output says there is no
  manifest.
- The same command with a manifest containing `{not json`. Exit 0.
- `agent --provider claude-cli upgrade alpha` with `PATH` set to a directory that holds
  only `git`, found by resolving `git` from the inherited `PATH` and symlinking it in.
  Exit 0; stderr or stdout contains `Upgrade brief:` and the fallback text, and the brief
  file exists.
- `agent --provider not-a-provider --debug upgrade alpha`. Exit 0, with a finding that
  mentions the configuration fallback. This proves a bad configuration does not stop the
  command.

### Milestone 3: The definition of done as a command

At the end of this milestone, `seihou agent upgrade MODULE --check` prints the readiness
report and exits 0 without contacting a provider or writing a brief. After an interactive
session ends, the same report is printed under the heading
`After the session:`.

In `handleAgentUpgrade`, when `opts ^. #check` is true, run the diagnosis, print
`renderReadinessReport`, and exit 0 before saving or launching anything. Otherwise, after
an interactive session returns, run the diagnosis again, print the heading and report to
stdout, and then exit with the session's code. The report format is fixed so the agent,
users, and tests can rely on it:

```text
Upgrade readiness for alpha
  ✓ manifest-readable        .seihou/manifest.json is schema 7 and decodes
  ✓ manifest-schema-current  schema 7 is current
  ✓ no-interrupted-update    no update transaction is waiting to be recovered
  ✓ target-recorded          alpha
  ✓ installed-copy-trusted   module alpha 1.1.0 is installed and matches the manifest's source
  ✓ origins-portable         every recorded origin is a remote URL or a project path
  ✗ shared-evidence-known    .gitignore is shared with beta and its write mode is unknown
  ✓ update-plans-cleanly     seihou update alpha --dry-run: alpha 1.0.0 -> 1.1.0
Upgrade readiness: not ready (1 check needs attention)
```

`?` marks a check that could not be determined. The final line is exactly
`Upgrade readiness: ready` or
`Upgrade readiness: not ready (<N> check needs attention)`, using "checks" when N is not 1.
A `CouldNotDetermine` check counts toward N. Checkmarks are plain text, with no ANSI
colour, so the line survives piping.

Add E2E cases to `AgentUpgradeE2ESpec`:

- `--check` on the healthy fixture ends in `Upgrade readiness: ready` with exit 0.
- `--check` on the schema-6 fixture ends in `not ready` with exit 0 and names `.gitignore`.
- `--check` on the schema-6 fixture after running `seihou update alpha` through the binary
  ends in `ready`. This is the loop the agent performs, run deterministically.
- `--check` in an empty directory exits 0 and is not ready.
- The post-session summary is not E2E-tested, because that needs a real provider. Test
  the rendering in `UpgradeDiagnosisSpec` instead.

### Milestone 4: Point failures at the command, and document it

At the end of this milestone every human `seihou update` failure ends with the extra line

```text
If this keeps failing, run 'seihou agent upgrade <target>' to have an agent repair the manifest state and finish the upgrade.
```

The line uses the first named target, or `<module>` when the update named none. JSON output
is unchanged; its `error.message` stays exactly as it is. The new line comes after the
remedy-first message, as ADR 0015 requires.

Make the change where `renderUpdateHuman` produces the `Update failed [...]` text for
`UpdateFailedOutput`, or in the executable's `handlePlanned` if the target list is only
available there. Prefer the render module, and thread the targets through the output value
if necessary. Extend `seihou-cli/test/Seihou/CLI/UpdateRenderSpec.hs`: every error in its
all-constructors fixture ends with the hint in human output, and no JSON output contains
it. Adjust the E2E assertions in `UpdateE2ESpec` that match whole stderr text.

Documentation, in the same milestone:

- `docs/cli/agent.md`: an `### agent upgrade` section after `### agent setup`, covering
  usage, options (`--check` and the provider flags), what diagnosis reads, where the brief
  is saved, the never-fail behavior, the readiness report format, and the safety rules.
  Add `upgrade` to the per-command config list in `### agent config`.
- `docs/user/agent-assistance.md`: an `### Upgrade` section under `## Agent commands`,
  written as a user walkthrough with a transcript.
- `docs/cli/update.md`: a short paragraph near the error descriptions saying that
  `seihou agent upgrade <target>` is the escape hatch when a remedy is unclear, with the
  hint line.
- `seihou-cli/help/agent.md`, the in-binary help topic: one entry for `upgrade`.
- `CHANGELOG.md` and `docs/user/CHANGELOG.md`: an `Added` entry under `Unreleased` for the
  command and `--check`, and a `Changed` entry for the update failure hint.
- Grep the documentation tree for the behavior, not only for these files, as
  `docs/masterplans/10-blueprint-migration-fan-out-across-a-library-cohort.md` recommends.
  Search `docs/` for `shared_write_evidence_unavailable`,
  `seihou manifest upgrade`, and `Update failed`. Add a pointer wherever a page tells a
  user how to recover from an update failure (for example `docs/user/manifest-upgrade.md`
  and `docs/user/teams.md`).

### Milestone 5: Validation and the durable record

Run the full validation in Concrete Steps and the manual acceptance scenario in Validation
and Acceptance. Then write `docs/adr/0016-agent-assisted-upgrade-diagnoses-read-only-and-never-fails.md`
in the existing convention: a `# ADR 0016 — Title` heading and `Status` and `Date` lines.
`docs/adr/` is a plain filesystem corpus, not a profiled OKF bundle; confirm that with
`mori show --full` before writing. The ADR records:

- The diagnosis is read-only.
- The command never exits non-zero because of project state, and the brief is always
  persisted outside the project.
- Readiness is defined as the checks behind a plain `seihou update`, exposed as `--check`.
- The agent repairs through seihou commands, with manual manifest edits as a guarded last
  resort.
- Rejected alternatives:
  - A `--repair` mode inside `seihou update`, rejected because it would weaken
    deterministic refusals.
  - An automatic repair without an agent, rejected because the remaining failures need
    judgment (origins, conflicts, consent to broaden).
  - Storing the brief in `.seihou/`, rejected under ADR 0001.

Fill in Outcomes & Retrospective and record a provenance revision.


## Concrete Steps

Run everything from the repository root,
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`, or wherever the working tree is
checked out.

Build and run the focused specs while iterating:

```bash
cabal build all
cabal test seihou-cli --test-options='-p "UpgradeDiagnosis"'
cabal test seihou-cli --test-options='-p "AgentUpgrade"'
cabal test seihou-cli --test-options='-p "UpdateRender"'
```

If the pattern syntax differs, `cabal test seihou-cli --test-options='--help'` lists the
tasty options. A tree name is the `describe` text in the spec.

Try the command by hand against a scratch copy of a project. There is no need to create
one: after `cabal build all`, point `cabal list-bin seihou` at any seihou-managed checkout
you are willing to inspect. `--debug` and `--check` write nothing to the project:

```bash
SEIHOU=$(cabal list-bin seihou)
cd /path/to/some/seihou-project
"$SEIHOU" agent --debug upgrade nix-haskell-flake | head -60
"$SEIHOU" agent upgrade nix-haskell-flake --check
git status --porcelain   # expect: no change caused by the two commands above
```

Expected `--check` tail on a project whose manifest is still schema 6:

```text
  ✗ manifest-schema-current  schema 6 is older than 7; seihou update steps it forward, or run seihou manifest upgrade
...
Upgrade readiness: not ready (2 checks need attention)
```

Full validation before each milestone's commit:

```bash
nix fmt -- --fail-on-change
cabal build all
cabal test all
nix flake check
```

Expected: all suites pass, with the new specs included. `nix flake check` reports the
module-placement and record-convention checks as passing. If the placement check fails,
the new executable module lacks a trapping import (it must import `Data.FileEmbed`) or
library code was placed in `src-exe/`.

Commit per milestone with Conventional Commits and both trailers, for example:

```text
feat(agent): diagnose a module upgrade without touching the project

Add Seihou.CLI.UpgradeDiagnosis: guarded, read-only probes of the manifest,
target, installed copy, shared-write evidence, manifest upgrade, and update
dry run, plus the readiness checks that define a clean upgrade.

ExecPlan: docs/plans/96-add-seihou-agent-upgrade-for-agent-assisted-module-upgrades-that-repair-manifest-state.md
Intention: intention_01m2tanyfae9ftvcqmaygv0960
```


## Validation and Acceptance

The change is accepted when all of the following hold.

1. `cabal test all` passes. The new specs are `UpgradeDiagnosisSpec` and
   `AgentUpgradeE2ESpec`, and the extended specs are `UpdateRenderSpec` and
   `AgentConfigShowSpec`. The write-nothing property holds for every diagnosis fixture.
2. `seihou agent --debug upgrade <module>` exits 0 in each of these situations: a healthy
   project, a schema-6 project, a schema-5 project, a project with unavailable co-owner
   evidence, an empty directory, a corrupt manifest, an unknown module name, and an invalid
   `--provider`. Each time it prints a brief that names what is wrong in plain prose, with
   no Haskell constructor syntax and no full application-id digest.
3. `seihou agent upgrade <module>` with `claude` missing from `PATH` exits 0, prints
   `Upgrade brief: <path>`, and that file exists and contains the brief.
4. `seihou agent upgrade <module> --check` exits 0 and ends with exactly one of the two
   verdict lines. On the schema-6 fixture it is `not ready`. After
   `seihou update <module>` on the same fixture it is `ready`.
5. A failing human `seihou update` ends with the `seihou agent upgrade` hint, and `--json`
   output is byte-identical to before for the same failure.
6. The manual scenario works. On a real project that fails `seihou update <module>` for a
   manifest-state reason, running `seihou agent upgrade <module>` starts a Claude Code
   session. Following the brief, the session reaches `Upgrade readiness: ready`, and
   afterwards a plain `seihou update <module>` either says `Already up to date.` or plans
   cleanly. Record the transcript's key lines in Outcomes & Retrospective. If the session
   needed a manual manifest edit, record which one and file an improvement request or bug
   report for the missing command.
7. `nix flake check` and `nix fmt -- --fail-on-change` pass.


## Idempotence and Recovery

Diagnosis, `--debug`, and `--check` write nothing to the project, the installed cache, or
the manifest, so they can be run any number of times. The only write is the brief. Each
run creates a new timestamped directory under `$XDG_STATE_HOME/seihou/agent-upgrade/`, so
runs never overwrite each other. Deleting that directory at any time is safe.

The interactive session changes the project only through the commands the agent runs.
Those have their own guarantees: `seihou update` is transactional with a recovery journal,
and `seihou manifest upgrade` writes atomically. The brief tells the agent to back up the
manifest into the brief directory before any manual edit. To undo a session's changes,
restore that backup or use `git checkout -- .seihou/manifest.json` and
`git checkout -- <paths>`. The brief also tells the agent to ask before working on a
dirty tree.

During implementation every milestone leaves the build green and can be committed on its
own. The refactor of `handleManifestUpgrade` into `renderUpgradeOutcome` must keep
`ManifestUpgradeSpec` passing without edits to its expected strings. If it does not, the
refactor changed output and must be corrected, not the spec.


## Interfaces and Dependencies

No new package dependencies. Everything used is already a dependency of `seihou-cli`:
`aeson`, `directory` (`getXdgDirectory XdgState`, `withCurrentDirectory`,
`findExecutable`), `process`, `time`, `text`, `containers`, `file-embed`, `generic-lens`,
and `lens`. `System.Timeout` comes from `base`.

At the end of M1, `seihou-cli/src/Seihou/CLI/UpgradeDiagnosis.hs` (library, listed in
`seihou-cli-internal`'s `exposed-modules`) exports at least the following. The field sets
may grow during implementation; record any change in the Decision Log.

```haskell
module Seihou.CLI.UpgradeDiagnosis
  ( DiagnosisEnv (..),
    Probe (..),
    ManifestState (..),
    TargetState (..),
    UpdateProbe (..),
    GitState (..),
    UpgradeDiagnosis (..),
    ReadinessStatus (..),
    ReadinessCheck (..),
    BriefLocation (..),
    diagnoseUpgrade,
    readiness,
    isReady,
    renderReadinessReport,
    briefSections,
    saveBrief,
  )
where

data DiagnosisEnv = DiagnosisEnv
  { projectRoot :: !FilePath,
    searchPaths :: ![FilePath],
    -- | Upper bound for the update dry-run probe, in seconds (180 in production).
    updateTimeoutSeconds :: !Int
  }
  deriving stock (Eq, Show, Generic)

-- | The outcome of one guarded probe. Never an exception.
data Probe a
  = ProbeOk !a
  | ProbeSkipped !Text
  | ProbeFailed !Text
  | ProbeTimedOut !Int
  deriving stock (Eq, Show, Generic, Functor)

data ManifestState
  = ManifestAbsent
  | ManifestNotJson !Text
  | -- | Parsed as JSON, has this schema, did not decode (for example schema 5).
    ManifestUndecodable !ManifestSchemaVersion !Text
  | ManifestDecoded !ManifestSchemaVersion !Manifest
  deriving stock (Eq, Show, Generic)

data TargetState
  = TargetMatched ![ApplicationRef] ![Text] -- matched applications; recorded versions
  | TargetNotFound ![Text] -- available targets
  | TargetLegacyManifest
  deriving stock (Eq, Show, Generic)

data UpdateProbe = UpdateProbe
  { errorCode :: !(Maybe Text),
    noOp :: !Bool,
    rendered :: !Text
  }
  deriving stock (Eq, Show, Generic)

data GitState = GitState
  { isRepository :: !Bool,
    dirtyPaths :: ![Text]
  }
  deriving stock (Eq, Show, Generic)

data UpgradeDiagnosis = UpgradeDiagnosis
  { target :: !Text,
    projectRoot :: !FilePath,
    manifest :: !(Probe ManifestState),
    pendingRecovery :: !(Probe Bool),
    targetState :: !(Probe TargetState),
    installedChecks :: !(Probe [ArtifactCheck]),
    unknownSharedPaths :: !(Probe [(FilePath, [ApplicationRef])]),
    projectUnknownCount :: !(Probe Int),
    -- | Machine-local recorded origin URLs, each with the artifact names recorded under it.
    localOrigins :: !(Probe [(Text, [Text])]),
    manifestUpgrade :: !(Probe Text), -- rendered with renderUpgradeOutcome
    updateDryRun :: !(Probe UpdateProbe),
    git :: !(Probe GitState)
  }
  deriving stock (Eq, Show, Generic)

data ReadinessStatus = Ready | NeedsAttention !Text | CouldNotDetermine !Text
  deriving stock (Eq, Show, Generic)

data ReadinessCheck = ReadinessCheck
  { name :: !Text, -- e.g. "manifest-readable"; stable, used in the report
    status :: !ReadinessStatus,
    detail :: !Text
  }
  deriving stock (Eq, Show, Generic)

data BriefLocation = BriefSaved !FilePath | BriefNotSaved !Text
  deriving stock (Eq, Show, Generic)

diagnoseUpgrade :: DiagnosisEnv -> Text -> IO UpgradeDiagnosis
readiness :: UpgradeDiagnosis -> [ReadinessCheck]
isReady :: [ReadinessCheck] -> Bool
renderReadinessReport :: Text -> [ReadinessCheck] -> Text
-- | Placeholder name/value pairs for the prompt template, e.g.
-- ("manifest_section", ...). Findings from the caller (a config fallback,
-- an escaped exception) are passed in and rendered into "findings_section".
briefSections :: UpgradeDiagnosis -> [Text] -> [(Text, Text)]
-- | Save under <XdgState>/seihou/agent-upgrade/<stamp>-<module>/brief.md,
-- falling back to the temporary directory. Never throws.
saveBrief :: Text -> Text -> IO BriefLocation
```

A module whose code runs these helpers may also need its own
`import Data.Generics.Labels ()`. `ArtifactCheck` comes from `Seihou.CLI.ManifestGuard`,
`ApplicationRef` from `Seihou.CLI.Update.Types`, and `Manifest` and
`ManifestSchemaVersion` from `seihou-core`. If the `Functor` derivation on `Probe`
conflicts with strictness, use `deriving stock (Functor)` as written. Strict fields are
compatible with a stock `Functor`.

Also at the end of M1:

```haskell
-- seihou-cli/src/Seihou/CLI/ManifestUpgrade.hs (new export)
renderUpgradeOutcome :: UpgradeOutcome -> Text

-- seihou-cli/src/Seihou/CLI/Update/Recovery.hs (new export; read-only)
pendingUpdateRecovery :: FilePath -> IO Bool

-- seihou-cli/src/Seihou/CLI/Update/Render.hs (export if not already)
errorCode :: UpdateError -> Text
```

At the end of M2:

```haskell
-- seihou-cli/src-exe/Seihou/CLI/Commands.hs
data AgentUpgradeOpts = AgentUpgradeOpts
  { -- | The MODULE argument; named target because module is a Haskell keyword.
    target :: !Text,
    prompt :: !(Maybe Text),
    check :: !Bool,
    provider :: !(Maybe Text),
    model :: !(Maybe Text),
    effort :: !(Maybe Text),
    trace :: !(Maybe Text)
  }
  deriving stock (Eq, Show, Generic)

-- AgentCommand gains:  | AgentUpgrade AgentUpgradeOpts

-- seihou-cli/src/Seihou/CLI/AgentConfig.hs
-- AgentCommandName gains AgentCmdUpgrade (segment "upgrade")

-- seihou-cli/src/Seihou/CLI/AgentLaunch.hs
upgradeAllowedTools :: [String]

-- seihou-cli/src-exe/Seihou/CLI/AgentUpgrade.hs
handleAgentUpgrade :: Bool -> Text -> AgentModelConfig -> Maybe Text -> AgentUpgradeOpts -> IO ()
```

M3 and M4 add no new exported interfaces beyond the rendering already listed. M4 may add a
field to the update output value to carry the target names for the hint. If it does, record
the exact change in the Decision Log.


## Revision Notes

- 2026-09-18: The reported `mori://tan/mls-service-v2` failure (a hand-edited
  local-path origin and a temporary cache swap to read `nix-haskell-flake` 0.13.2) led to
  two sibling plans, 97 and 98, which fix those failure shapes in seihou itself. This
  plan was revised to match:
  - The M1 cache-swap prototype is removed.
  - An `origins-portable` probe and readiness check are added, and the `--check` example
    grows to eight checks.
  - The playbook entries for `shared_write_evidence_unavailable` and origin mismatches now
    use the new behavior and `seihou manifest repair-origins` instead of manual repair.
  - The recommended order is 98, then 97, then 96.
