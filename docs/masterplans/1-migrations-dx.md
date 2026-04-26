# Fix Migrations, Upgrade, Run, and Status DX

Intention: intention_01kq5pe8hhekrrb9wg4eb1jz74

This MasterPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/master-plan/MASTERPLAN.md`.


## Vision & Scope

After this initiative, the upgrade-and-migrate workflow in Seihou is trustworthy and easy to discover from the commands a user already runs. Specifically, after a module author publishes a new version, a project owner who has the previous version applied will see the upgrade and any pending migration surfaced by `seihou status`, and can finish the upgrade either by running `seihou upgrade` followed by `seihou migrate <module>` or by running a single migration-aware command. `seihou run` will never silently overwrite files that a pending migration would have moved.

In scope:

- `seihou outdated` and `seihou upgrade` correctly detect outdated installed modules even when a registry's static `version` field is stale.
- `seihou migrate <module>` works end-to-end: it discovers the latest available version for the applied module and applies the migration chain without requiring a separate `seihou upgrade` invocation.
- `seihou run` detects pending migrations and refuses to write into files a migration would have moved unless the user opts in.
- `seihou status` truthfully reports both outdated installed modules and pending migrations, and emits a copy-pasteable next command for each.
- Documentation under `docs/user/` and `docs/cli/` is updated to describe the new behavior, and integration tests cover the end-to-end flow.

Out of scope:

- Recipe migrations (still v1+ deferred per `docs/plans/13-module-migrations.md`).
- Any change to migration operation semantics (`MoveFile`, `MoveDir`, `DeleteFile`, `DeleteDir`, `RunCommand`) or to the manifest schema beyond what is needed to surface pending migrations correctly.
- Auto-syncing remote registries on every command (we will only fetch when the command already clones, e.g. `outdated`, `upgrade`, `migrate`).


## Decomposition Strategy

The decomposition follows the user-visible commands that are broken, not the internal modules. Each child plan delivers one demonstrable behavior fix that can be verified by running a concrete command in a test repo.

The principles applied:

- **Functional concerns over file boundaries.** "Detect outdated modules" and "apply pending migrations" are distinct concerns even though they touch overlapping files (`Upgrade.hs`, `Outdated.hs`, `Migrate.hs`, `Status.hs`).
- **Independent verifiability.** Each child plan ends with a command the user can run against a representative project that demonstrates the broken behavior is now correct. EP-1 demonstrates `seihou outdated` correctly flagging stale modules. EP-2 demonstrates `seihou migrate` working without prior `seihou upgrade`. EP-3 demonstrates `seihou run` blocking or auto-applying migrations. EP-4 demonstrates `seihou status` surfacing both kinds of staleness.
- **Minimum coupling.** Where two child plans must share a primitive (e.g., a function that fetches a module's true version from a remote source), one plan defines it and the other plan consumes it via a documented integration point.
- **Respect natural ordering.** Fixing version detection (EP-1) is foundational because every other downstream UX depends on a truthful answer to "is this module outdated?".

Alternatives considered:

- **One mega-plan touching all four commands at once.** Rejected: more than five milestones, more than ten files across unrelated sections of the CLI, and impossible to validate incrementally.
- **One plan per source file.** Rejected: would split related behavior across plans and force the consumer to integrate partial work. The agreed principle in the project (see `.claude/skills/master-plan/MASTERPLAN.md`) is to slice by functional concern, not by file.
- **Fold migration awareness into a generic "post-run hooks" framework.** Rejected as scope creep; nothing in the current codebase needs general-purpose hooks today.


## Exec-Plan Registry

| #   | Title                                                        | Path                                                | Hard Deps | Soft Deps | Status      |
|-----|--------------------------------------------------------------|-----------------------------------------------------|-----------|-----------|-------------|
| 1   | Fix `outdated` and `upgrade` to detect true module versions  | docs/plans/14-fix-outdated-version-detection.md     | None      | None      | Complete    |
| 2   | Make `seihou migrate` self-contained (no manual upgrade)     | docs/plans/15-make-migrate-self-contained.md        | EP-1      | None      | Complete    |
| 3   | Make `seihou run` migration-aware                            | docs/plans/16-make-run-migration-aware.md           | EP-2      | EP-1      | Not Started |
| 4   | Make `seihou status` surface staleness and pending migrations | docs/plans/17-improve-status-migration-visibility.md | EP-1      | EP-2      | Not Started |

Status values: Not Started, In Progress, Complete, Cancelled.


## Dependency Graph

EP-1 is foundational. It introduces a single source of truth — call it `fetchTrueModuleVersion :: SourceUrl -> ModuleName -> IO (Maybe Version)` — that reads the actual `module.dhall` from a cloned remote rather than from the registry's static metadata. Today both `seihou outdated` and `seihou upgrade` compare a registry-declared version string against an installed-copy version string. When the registry's metadata drifts behind the module.dhall (which the project's own `seihou registry sync` was intended to prevent but does not enforce), every comparison reports "up to date". EP-1 changes the comparison to read the true version from the cloned `module.dhall`.

EP-2 hard-depends on EP-1 because the new behavior of `seihou migrate <module>` is "fetch the latest available version for this module, then apply the chain". The "fetch the latest available version" step reuses the EP-1 primitive. Without EP-1, `seihou migrate` would still be gated on the user having run `seihou upgrade` first, which is the bug we are removing.

EP-3 hard-depends on EP-2 because the migration-aware path of `seihou run` (`run --with-migrations`) calls into the same migration-execution code path that EP-2 hardens (in particular: a path that can determine, plan, and apply a migration chain inside a single command). EP-3 also has a soft dependency on EP-1: the "block run when migrations are pending" check uses the same outdated detection.

EP-4 hard-depends on EP-1 because `seihou status --check-updates` must reflect the same truthful version comparison. It has a soft dependency on EP-2: the user-facing call-to-action ("run `seihou migrate <module>`") is more useful when migrate is actually self-contained.

Parallelism: After EP-1 ships, EP-2 and EP-4 can proceed in parallel (different files, different commands). EP-3 should wait for EP-2 because run's auto-apply path reuses migrate's plumbing.

Critical path: EP-1 → EP-2 → EP-3 (three plans serial).


## Integration Points

This section enumerates every shared artifact two or more child plans touch. Each child plan must consult this list before defining its own types or signatures.

**1. True-version fetch primitive.**

- Involved plans: EP-1 (definer), EP-2 (consumer), EP-3 (consumer via EP-2), EP-4 (consumer).
- Artifact: A function that, given a clone of a remote source repository, returns the true `version` field declared in the module's `module.dhall` for a named module. Tentative signature, to be finalized in EP-1:

        fetchTrueModuleVersion
          :: ClonedRepoPath
          -> ModuleName
          -> IO (Either FetchError SemVer)

- Owning module: `seihou-cli/src/Seihou/CLI/Outdated.hs` (or a new `Seihou.CLI.RemoteVersion` module that EP-1 introduces if multiple call sites become awkward).
- Consumers must import the function rather than re-implementing the read; this is the integration contract.

**2. Pending-migration detection.**

- Involved plans: EP-2 (definer of remote-aware variant), EP-3 (consumer for run's pre-flight check), EP-4 (consumer for status display).
- Artifact: A function that, given an `AppliedModule` and the path of an installed-or-fetched module copy, returns the migration chain the user must apply to reach that copy's version. The current `pendingChainFor` lives in `seihou-cli/src/Seihou/CLI/Migrate.hs`; EP-2 may extend it (e.g., to accept a remote module copy, not only the locally installed one) or introduce a thin wrapper. EP-3 and EP-4 import the chosen entry point.

**3. Manifest field on applied modules.**

- Involved plans: All four (read), EP-2 (write).
- Artifact: `AppliedModule.moduleVersion :: Maybe Text` in `seihou-core/src/Seihou/Core/Types.hs`. After EP-2 ships, `seihou migrate` may need to refresh this field to reflect the post-migration version; EP-3 may need to consult it during `run`'s pre-flight check; EP-4 reads it for display. No schema change; just respect the existing semantics.

**4. CLI wiring and help text.**

- Involved plans: EP-2 (changes `migrate` help to remove "run upgrade first" hint), EP-3 (adds `run --with-migrations` flag and updates help), EP-4 (adds new lines to status output).
- Artifact: `seihou-cli/src/Seihou/CLI/Commands.hs` (option-parser definitions). Coordination: each plan edits its own command's parser; no plan should touch another command's parser.

**5. Documentation.**

- Involved plans: All four.
- Artifact: `docs/user/migrations.md`, `docs/cli/migrate.md`, `docs/cli/upgrade.md` (create if absent), `docs/cli/run.md` (create if absent), `docs/cli/status.md` (create if absent), and `docs/user/CHANGELOG.md`. Each child plan owns the docs for the command it changes; the CHANGELOG receives one entry per child plan with a clear date stamp.


## Progress

Track milestone-level progress across all child plans. Each entry names the child plan and the milestone. This section provides an at-a-glance view of the entire initiative.

- [x] EP-1: Reproduce the wrong-version-detection bug with a regression test.
- [x] EP-1: Introduce the true-version fetch primitive and switch `outdated`/`upgrade` to use it.
- [x] EP-1: End-to-end demonstration: stale-registry repo correctly reports outdated modules.
- [x] EP-2: Reproduce the "migrate says nothing to do" bug in a test.
- [x] EP-2: Make `seihou migrate <module>` fetch the remote, plan the chain, apply it without requiring a prior `seihou upgrade`.
- [x] EP-2: End-to-end demonstration: a project at module v0.1.0 can run a single `seihou migrate <module>` and end up at the latest published version with files moved.
- [ ] EP-3: Reproduce the "`seihou run` overwrites files a migration would have moved" bug.
- [ ] EP-3: Add pending-migration pre-flight to `seihou run`; implement default refusal and `--with-migrations` opt-in.
- [ ] EP-3: End-to-end demonstration: `seihou run` against a project with a pending migration refuses with a clear message; `seihou run --with-migrations` applies the chain then writes the new template state.
- [ ] EP-4: Update `seihou status` to surface true outdated state.
- [ ] EP-4: Update `seihou status` to surface pending migrations with a copy-pasteable next command.
- [ ] EP-4: End-to-end demonstration: `seihou status --check-updates` against a stale-registry project lists outdated modules and pending migrations and the exact remediation command for each.


## Surprises & Discoveries

Captured during research before implementation:

- **The bug is not in upgrade's flow logic; it is in version detection.** A direct test on the seihou-project's own manifest showed `seihou outdated` reporting "0 outdated" while the actual remote module.dhall is at 0.3.0 and the manifest is at 0.1.0. The cause is that the comparison reads from the registry's static `version` field rather than the cloned module.dhall, and the project's `seihou-registry.dhall` is stale relative to the modules it indexes.

  Evidence (run from `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou` on 2026-04-26):

      $ seihou outdated
      Module             Installed  Available  Status
      master-plan        0.1.0      0.1.0      up to date
      exec-plan          0.1.3      0.1.3      up to date
      6 module(s) checked, 0 outdated.

  But `/Users/shinzui/Keikaku/bokuno/agent-seihou/modules/master-plan/module.dhall` declares `version = Some "0.3.0"`.

- **`seihou migrate` is gated on a working `seihou upgrade`.** With the upgrade detection broken, running `seihou migrate master-plan` says "✓ master-plan is already at version 0.1.0; nothing to do.", because the locally installed module copy under `~/.config/seihou/installed/master-plan/` was never refreshed. This means the migrate command, even with intact internals, cannot discover any newer version on its own. EP-2's purpose is to make migrate fetch its own remote when needed.

- **`seihou run` would silently apply the new template to old paths.** A `--dry-run` shows `[modified]` against `claude/skills/master-plan/SKILL.md` even though the master-plan 0.1.0 → 0.2.0 migration moves that file to `agents/skills/master-plan/SKILL.md`. Without the migration applied first, `seihou run` would write a stale layout. This is the most dangerous of the four bugs because it can leave a project in a broken hybrid state.

- **The agent-seihou repo at `/Users/shinzui/Keikaku/bokuno/agent-seihou` is the live test bed.** Its `seihou-registry.dhall` declares master-plan 0.1.0 / exec-plan 0.1.3, but its `modules/master-plan/module.dhall` declares 0.3.0. This is the exact "stale registry" condition every child plan must reproduce as its regression test.

- **EP-1 finalized the primitive's signature as `IO (Either FetchError (Maybe Text))`, not `IO (Either FetchError SemVer)`** (the masterplan's tentative form). Reason: the codebase has no `SemVer` type, and the entire comparison path operates on `Maybe Text`. The third state `Right Nothing` represents an unversioned module — the same case `compareVersions` already handles. The masterplan's Integration Point #1 should be read with this finalized signature; downstream EPs (EP-2 consumer, EP-3 consumer-via-EP-2, EP-4 consumer) must import `Seihou.CLI.RemoteVersion.fetchTrueModuleVersion` rather than re-implement the version read.

- **`upgrade`'s post-install version recording shared the registry-bias bug** and was fixed in EP-1 alongside the comparison itself. Before this change, after a successful `seihou upgrade`, the manifest would record the registry's stale `version` instead of the truthful `module.dhall` value. EP-2 should not need to re-fix this, but EP-2's self-contained `seihou migrate <module>` does need to refresh `AppliedModule.moduleVersion` after applying a chain — that bookkeeping is independent of the EP-1 fix.

- **`Seihou.CLI.Outdated` is in the executable target, not the `seihou-cli-internal` library.** EP-1 placed the new primitive in `Seihou.CLI.RemoteVersion` (library-exposed) so the test suite can exercise it without the executable. Future EPs that need to call `checkInstalledModulesForUpdates` from a test should be aware that the function lives in the executable; the easier path is to call `fetchTrueModuleVersion` directly (as RemoteVersionSpec does).

- **Install helpers were also executable-only and had to be moved.** During EP-2, `installModuleDir`, `cloneRepo`, `copyDirectoryRecursive`, and `OriginInfo` were extracted from `Seihou.CLI.Install` (executable target) into a new library module `Seihou.CLI.InstallShared` so `Seihou.CLI.Migrate` (library) could call them. EP-3 (run migration-aware) and EP-4 (status) should import from `Seihou.CLI.InstallShared` rather than from `Install.hs` directly. As part of the move, `cloneRepo` was changed from `IO ()` (calling `exitFailure` on failure) to `IO (Either Text ())` so callers can recover and fall back gracefully — this is the reason the migrate fetch path silently degrades to local-only on a clone failure.

- **Integration Point #2's `refreshInstalledFromRemote` was inlined into `runMigrateWithFetch` rather than extracted as a separate helper.** Reason: the migrate path needs the cloned `moduleDir` alive during chain execution (to read `module.dhall`'s migrations list), not just a finalized "installed path". A free-standing `refreshInstalledFromRemote :: AppliedModule -> IO (Either RefreshError InstalledModulePath)` would have to clone, refresh the on-disk install dir, then return the path, leaving the chain logic to re-read the freshly-installed copy — which is structurally fine but does an extra disk write under `--dry-run` (the dry-run path currently writes nothing). When EP-3 lands, the cleanest factoring is probably `withFetchedModuleDir :: AppliedModule -> (FilePath -> IO a) -> IO (Either FetchError a)` exposed from `Seihou.CLI.InstallShared`, with `runMigrateWithFetch` and EP-3's `--with-migrations` path both calling it. EP-4 (status display) can use the simpler `fetchTrueModuleVersion` since it just needs the remote's version, not the migrations list.

- **EP-2's `migrateNoFetch` flag is also the right knob for `seihou upgrade --with-migrations`.** Because `seihou upgrade` already refreshes the installed copy before invoking the post-upgrade migration hook, passing `migrateNoFetch = True` avoids a redundant clone. EP-3 should follow the same pattern when it needs to invoke `runMigrate` from inside `seihou run --with-migrations`: if EP-3 has already done its own fetch, pass `migrateNoFetch = True`; if it relies on `runMigrate` to do the fetch, pass `migrateNoFetch = False` and let the existing logic handle clone+refresh.


## Decision Log

- Decision: Decompose by user-visible command (`outdated`/`upgrade`, `migrate`, `run`, `status`) rather than by internal module.
  Rationale: Each broken DX is anchored to a single command from the user's perspective, and each fix can be verified by running that command. Slicing by file would force partial behavior across plans.
  Date: 2026-04-26.

- Decision: Make `seihou migrate <module>` fetch its own remote rather than require `seihou upgrade` first.
  Rationale: The original v1 design (per `docs/plans/13-module-migrations.md`) deliberately separated upgrade and migrate so that destructive operations were always explicit. In practice that two-command workflow is undiscoverable, and the broken upgrade detection makes it actively confusing. Self-contained migrate keeps explicitness (the user still chose to run `migrate`) without the discoverability tax.
  Date: 2026-04-26.

- Decision: Default `seihou run` behavior on a pending migration is to refuse with a clear message; `--with-migrations` is opt-in.
  Rationale: Auto-applying destructive operations during `run` would surprise users. The opt-in flag mirrors the existing `seihou upgrade --with-migrations` precedent and keeps the semantics consistent across the CLI.
  Date: 2026-04-26.

- Decision: Do not introduce a new manifest schema version for this initiative.
  Rationale: The existing `AppliedModule.moduleVersion` field is sufficient. Adding a v3 manifest would force a forward-only migration of every project that uses Seihou, for negligible benefit.
  Date: 2026-04-26.


## Outcomes & Retrospective

(To be filled during and after implementation.)
