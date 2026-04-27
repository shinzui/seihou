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
| 3   | Make `seihou run` migration-aware                            | docs/plans/16-make-run-migration-aware.md           | EP-2      | EP-1      | Complete    |
| 4   | Make `seihou status` surface staleness and pending migrations | docs/plans/17-improve-status-migration-visibility.md | EP-1      | EP-2      | Complete    |
| 5   | Bulletproof partial migration chains across status, migrate, run | docs/plans/23-bulletproof-partial-migration-chains.md | EP-2, EP-3, EP-4 | None | In Progress |

Status values: Not Started, In Progress, Complete, Cancelled.


## Dependency Graph

EP-1 is foundational. It introduces a single source of truth — call it `fetchTrueModuleVersion :: SourceUrl -> ModuleName -> IO (Maybe Version)` — that reads the actual `module.dhall` from a cloned remote rather than from the registry's static metadata. Today both `seihou outdated` and `seihou upgrade` compare a registry-declared version string against an installed-copy version string. When the registry's metadata drifts behind the module.dhall (which the project's own `seihou registry sync` was intended to prevent but does not enforce), every comparison reports "up to date". EP-1 changes the comparison to read the true version from the cloned `module.dhall`.

EP-2 hard-depends on EP-1 because the new behavior of `seihou migrate <module>` is "fetch the latest available version for this module, then apply the chain". The "fetch the latest available version" step reuses the EP-1 primitive. Without EP-1, `seihou migrate` would still be gated on the user having run `seihou upgrade` first, which is the bug we are removing.

EP-3 hard-depends on EP-2 because the migration-aware path of `seihou run` (`run --with-migrations`) calls into the same migration-execution code path that EP-2 hardens (in particular: a path that can determine, plan, and apply a migration chain inside a single command). EP-3 also has a soft dependency on EP-1: the "block run when migrations are pending" check uses the same outdated detection.

EP-4 hard-depends on EP-1 because `seihou status --check-updates` must reflect the same truthful version comparison. It has a soft dependency on EP-2: the user-facing call-to-action ("run `seihou migrate <module>`") is more useful when migrate is actually self-contained.

Parallelism: After EP-1 ships, EP-2 and EP-4 can proceed in parallel (different files, different commands). EP-3 should wait for EP-2 because run's auto-apply path reuses migrate's plumbing.

Critical path: EP-1 → EP-2 → EP-3 (three plans serial).

EP-5 was added on 2026-04-26 as follow-up after EP-1–EP-4 shipped: the masterplan's vision is not actually delivered while the planner returns `MigrationGap` whenever the declared migration list does not reach the latest version exactly. EP-5 hard-depends on EP-2, EP-3, and EP-4 because it changes the planner contract that all three of them consume; each consumer needs a coordinated update. EP-5 has no soft dependencies because the consumers were the deferring plans, not the providing ones.


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

- Involved plans: EP-2 (definer of remote-aware variant), EP-3 (consumer for run's pre-flight check), EP-4 (consumer for status display), EP-5 (re-shapes the return type to carry partial-chain results).
- Artifact: A function that, given an `AppliedModule` and the path of an installed-or-fetched module copy, returns the migration chain the user must apply to reach that copy's version. The current `pendingChainFor` lives in `seihou-cli/src/Seihou/CLI/Migrate.hs`; EP-2 may extend it (e.g., to accept a remote module copy, not only the locally installed one) or introduce a thin wrapper. EP-3 promoted detection to `Seihou.CLI.PendingMigrations.detectPendingMigrations`. EP-5 changes `pendingChainFor`'s return type from `Maybe MigrationChain` to `Maybe MigrationPlan` (where `MigrationPlan` carries a reachable prefix plus an optional unreachable tail) so consumers can render partial-chain and blocked rows; consumers in EP-3, EP-4, and `Upgrade.hs` are updated in lockstep.

**3. Manifest field on applied modules.**

- Involved plans: All four (read), EP-2 (write).
- Artifact: `AppliedModule.moduleVersion :: Maybe Text` in `seihou-core/src/Seihou/Core/Types.hs`. After EP-2 ships, `seihou migrate` may need to refresh this field to reflect the post-migration version; EP-3 may need to consult it during `run`'s pre-flight check; EP-4 reads it for display. No schema change; just respect the existing semantics.

**4. CLI wiring and help text.**

- Involved plans: EP-2 (changes `migrate` help to remove "run upgrade first" hint), EP-3 (adds `run --with-migrations` flag and updates help), EP-4 (adds new lines to status output).
- Artifact: `seihou-cli/src/Seihou/CLI/Commands.hs` (option-parser definitions). Coordination: each plan edits its own command's parser; no plan should touch another command's parser.

**5. Documentation.**

- Involved plans: All five.
- Artifact: `docs/user/migrations.md`, `docs/cli/migrate.md`, `docs/cli/upgrade.md` (create if absent), `docs/cli/run.md` (create if absent), `docs/cli/status.md` (create if absent), and `docs/user/CHANGELOG.md`. Each child plan owns the docs for the command it changes; the CHANGELOG receives one entry per child plan with a clear date stamp. EP-5 updates `migrate.md`, `status.md`, and `run.md` to document partial / blocked migration handling.

**6. Migration planner contract.**

- Involved plans: EP-5 (definer); EP-2, EP-3, EP-4 (downstream consumers via `pendingChainFor` and `runMigrate`).
- Artifact: `planMigrationChain` in `seihou-core/src/Seihou/Core/Migration.hs`. EP-5 changes its return type from `Either MigrationPlanError (Maybe MigrationChain)` to `Either MigrationPlanError (Maybe MigrationPlan)`, where `MigrationPlan` is a record `{ planChain :: MigrationChain, planUnreachable :: Maybe (Version, Version) }`. The `MigrationGap` error variant is removed from `MigrationPlanError` and replaced with the in-band `planUnreachable` field; partial coverage is no longer a hard error. The blocked case (no edge starts at the manifest version) is represented as `MigrationPlan { planChain = empty, planUnreachable = Just (installed, target) }`. Consumers must check `null planChain.chainSteps` to distinguish blocked from partial.


## Progress

Track milestone-level progress across all child plans. Each entry names the child plan and the milestone. This section provides an at-a-glance view of the entire initiative.

- [x] EP-1: Reproduce the wrong-version-detection bug with a regression test.
- [x] EP-1: Introduce the true-version fetch primitive and switch `outdated`/`upgrade` to use it.
- [x] EP-1: End-to-end demonstration: stale-registry repo correctly reports outdated modules.
- [x] EP-2: Reproduce the "migrate says nothing to do" bug in a test.
- [x] EP-2: Make `seihou migrate <module>` fetch the remote, plan the chain, apply it without requiring a prior `seihou upgrade`.
- [x] EP-2: End-to-end demonstration: a project at module v0.1.0 can run a single `seihou migrate <module>` and end up at the latest published version with files moved.
- [x] EP-3: Reproduce the "`seihou run` overwrites files a migration would have moved" bug (synthetic temp fixture; live `seihou-project` tree was non-reproducing because the planner refuses partial chains).
- [x] EP-3: Add pending-migration pre-flight to `seihou run`; implement default refusal and `--with-migrations` opt-in.
- [x] EP-3: End-to-end demonstration: `seihou run` against a project with a pending migration refuses with a clear message; `seihou run --with-migrations` applies the chain then writes the new template state.
- [x] EP-4: Update `seihou status` to surface true outdated state.
- [x] EP-4: Update `seihou status` to surface pending migrations with a copy-pasteable next command.
- [x] EP-4: End-to-end demonstration: `seihou status --check-updates` against a stale-registry project lists outdated modules and pending migrations and the exact remediation command for each.
- [x] EP-5: Pin current `MigrationGap` behavior with regression tests for partial-chain and no-chain-at-all fixtures.
- [x] EP-5: Change the planner contract to return reachable prefix plus unreachable tail; update existing planner tests.
- [x] EP-5: Update `pendingChainFor`/`runMigrate` so migrate applies the longest reachable prefix and refreshes the manifest.
- [ ] EP-5: Update `Seihou.CLI.StatusRender` to emit full / partial / blocked migration rows.
- [ ] EP-5: Update `seihou run` pre-flight to refuse on every divergence; `--with-migrations` applies reachable prefixes and refuses blocked modules.
- [ ] EP-5: End-to-end demonstration on the live `seihou-project` tree: status, migrate, and run all behave correctly for master-plan (partial chain) and exec-plan (blocked).


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

- **EP-3 confirmed `migrateNoFetch=True` is sufficient for the run pre-flight + auto-apply path.** `detectPendingMigrations` already inspected the locally installed `module.dhall`; cloning the source repo a second time inside `runMigrate` would be wasted work. So `seihou run --with-migrations` calls `runMigrate` with `migrateNoFetch=True`, mirroring `seihou upgrade --with-migrations`. EP-4 (`seihou status`) should *not* call `runMigrate` at all (status is read-only); it only needs `detectPendingMigrations` from `Seihou.CLI.PendingMigrations`.

- **`detectPendingMigrations` is now in a library-exposed module, not in `Status.hs`.** EP-3 promoted it to `Seihou.CLI.PendingMigrations` (added to `seihou-cli-internal` library and the executable target's `other-modules`) and added a `Maybe (Set ModuleName)` filter so `seihou run` can scope detection to only the modules being run while `seihou status` keeps the unfiltered behaviour. EP-4 must import from this module rather than re-implement; Integration Point #2 in this masterplan should be read with `Seihou.CLI.PendingMigrations.detectPendingMigrations` as the canonical entry point. The exported `formatRefusalMessage` helper is `seihou run`-specific and not relevant to status; EP-4 should write its own renderer.

- **Composition-time dependency failures preempt EP-3's pre-flight.** When a newer installed copy of a module adds a dependency the user has not yet installed, `seihou run` fails inside `loadComposition` (with "module 'X' not found") before the pending-migration check fires. Encountered live during EP-3's M6: master-plan v0.3.0 ships a `link-skill` dependency that wasn't installed locally. EP-4 may want to surface a "missing dependency" advisory in `seihou status --check-updates` so users have a single place to learn that a project needs both `seihou install <new-dep>` and `seihou migrate <module>` after an upgrade.

- **`pendingChainFor` is silent on planner gaps.** When the migrations list does not reach the installed version exactly (e.g. only `1.0.0 → 2.0.0` declared but installed is 3.0.0), `planMigrationChain` returns `MigrationGap` and `pendingChainFor` returns `Nothing`. Detection is therefore a no-op in that case and `seihou run` falls back to its older behaviour (which is the failure mode EP-3 was meant to fix). This is a real gap on the live `seihou-project` working tree: master-plan has manifest=0.1.0, installed=0.3.0, migrations=[0.1.0→0.2.0]. Fixing it requires changing the planner contract (likely a "longest-reachable-prefix" mode), which is out of EP-3's scope. EP-4's status display will inherit the same silence — flag this as a design tension and decide whether to surface "incomplete migration coverage" advisories during the EP-4 work.

- **EP-4 inherited the planner-gap silence rather than adding an "incomplete migration coverage" advisory.** The decision was deliberate: surfacing partial chains requires a new planner mode (longest-reachable-prefix) plus a new return shape from `planMigrationChain`, and that change cuts across the migration engine in ways the masterplan's vision does not require. EP-4 instead documents the limitation in `docs/cli/status.md` and the EP-4 retrospective so future work can pick it up. Anyone exploring a planner-mode change should also revisit `seihou run`'s pre-flight: both call sites would benefit from the same partial-coverage signal.

- **`OutdatedEntry` migrated to the library in EP-4.** EP-1 had left `OutdatedEntry`, `CheckStats`, and the `ToJSON OutdatedEntry` instance in the executable-only `Seihou.CLI.Outdated`. EP-4 needed them in a library module so the new `Seihou.CLI.StatusRender` (and its tests) could reference the data type without IO. The fix moved the types into `Seihou.CLI.VersionCompare` (already library-exposed) and made `Outdated.hs` re-export them. Future modules that consume outdated entries (e.g. an alternate JSON status formatter, or a planned `seihou audit` command) should import from `VersionCompare` rather than `Outdated`.

- **Status rendering now lives in a library module (`Seihou.CLI.StatusRender`), not in `Status.hs`.** EP-4 extracted the entire renderer into a pure `formatStatus :: Bool -> Manifest -> [TrackedFile] -> Maybe [OutdatedEntry] -> [(ModuleName, MigrationChain)] -> Text` so the test suite could exercise it against fixtures (no XDG-redirected fake installed dirs needed — much cheaper than the EP-1/EP-2 fixture style). `Status.hs` shrank to a thin IO shell. Subsequent surfaces that want to render status — JSON output, an HTML report, an embedded view in another command — should add a parallel formatter in `StatusRender` rather than re-walking `manifest.modules`.

- **The deferred planner-gap silence is a real, recurring user-visible failure, not just a theoretical edge case.** Live verification on `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou` on 2026-04-26 (after EP-1–EP-4 had all shipped) showed:

      $ seihou status
      Applied modules:
        ...
        exec-plan  v0.1.3    (applied 2026-04-15)
        master-plan  v0.1.0    (applied 2026-04-15)
      [no pending-migration row, no advisory, no remediation]

      $ seihou migrate master-plan --dry-run
      Error: no migration covers the gap from 0.2.0 to 0.3.0.
      The module author needs to ship a migration that starts at 0.2.0.

  master-plan: manifest=0.1.0, cache=0.3.0, declared `[0.1.0 → 0.2.0]` (partial chain). exec-plan: manifest=0.1.3, cache=0.3.0, no migrations declared (no-chain-at-all). Both consumers swallow the planner's `MigrationGap` and the user sees nothing actionable. `seihou run` would silently overwrite the 0.1.0 layout with 0.3.0 templates — the exact hazard EP-3 was meant to block. EP-5 (`docs/plans/23-bulletproof-partial-migration-chains.md`) reopens the masterplan to ship the longest-reachable-prefix planner mode and update all three consumers in lockstep.


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

> **Status note (2026-04-26):** This masterplan was provisionally closed
> after EP-1–EP-4 shipped, but live verification on the
> `seihou-project` tree found that the planner-gap carve-out (deferred
> below) is the common case, not the edge case: `seihou status` is
> silent and `seihou migrate` errors out for both modules whose
> migrations don't reach the latest version exactly. EP-5 reopens the
> initiative to retire the carve-out. The retrospective below describes
> what EP-1–EP-4 delivered; the final retrospective will be rewritten
> after EP-5 lands.

The four child plans landed in the order the dependency graph
predicted (EP-1 → EP-2 → EP-3 → EP-4). What the user sees after that
work, when the declared migrations cover the entire gap exactly:

1. `seihou outdated` and `seihou upgrade` correctly flag a module as
   outdated as soon as the upstream `module.dhall` declares a higher
   version, even when the registry's static `version` field is stale
   (EP-1).
2. `seihou migrate <module>` works without a prior `seihou upgrade`:
   it fetches the source repo, plans the chain against the remote's
   `module.dhall`, applies it, and refreshes the on-disk installed
   copy. `--no-fetch` preserves the legacy local-only behavior for
   offline use and for callers that have already refreshed (EP-2).
3. `seihou run` no longer silently writes the new template into paths
   a pending migration would have moved. By default it refuses with a
   clear message naming the next command; `--with-migrations`
   applies the chain in-band before the run plan executes (EP-3).
4. `seihou status` reports both outdated installed modules and
   pending migrations whose chains reach the latest version exactly,
   with a copy-pasteable next command under each problem row plus a
   Recommended actions tail block. The pending-migration check is
   unconditional (no `--check-updates` needed) because it is purely
   local (EP-4).

What did *not* land and is now scheduled in EP-5
(`docs/plans/23-bulletproof-partial-migration-chains.md`):

- A "longest-reachable-prefix" planner mode. The `MigrationGap` error
  variant is treated as "no chain" by every consumer
  (`pendingChainFor`, `runMigrate`, `detectPendingMigrations`), so the
  user sees nothing pending and `seihou migrate` refuses to apply any
  step. Live failure: master-plan (manifest=0.1.0, cache=0.3.0,
  migrations=[0.1.0 → 0.2.0]) gets a partial-chain silence;
  exec-plan (manifest=0.1.3, cache=0.3.0, no migrations declared)
  gets a no-chain-at-all silence. EP-5 reshapes the planner contract
  and updates all three consumers.

What stays out of scope — deliberately:

- Recipe migrations (still v1+ deferred per
  `docs/plans/13-module-migrations.md`).
- A new manifest schema version. The existing
  `AppliedModule.moduleVersion` field plus careful refresh-on-apply
  bookkeeping (EP-1's post-install fix and EP-2's
  `runMigrate`-refreshes-manifest behavior) covered every case
  EP-1–EP-4 needed. EP-5 reuses the same hook.

Cross-plan coordination held up across EP-1–EP-4. The integration
points the masterplan called out — `fetchTrueModuleVersion` (EP-1
definer; EP-2, EP-3, EP-4 consumers), `detectPendingMigrations` (EP-3
definer; EP-4 consumer), `installModuleDir` and friends in
`Seihou.CLI.InstallShared` (EP-2 extractor; EP-3 consumer) — all
ended up in library-exposed modules so the test suite could reach
them without spinning up the executable. EP-5 inherits that pattern
and adds the planner contract itself as a sixth integration point.

Implementation arc per plan (EP-1–EP-4):

- EP-1 took the longest because the bug was non-obvious (registry
  metadata vs. module.dhall divergence) and required adding a new
  primitive plus rewiring two commands. The post-fix manifest
  recording bug surfaced during implementation and was fixed in the
  same plan.
- EP-2 was the largest behavioral change (self-contained fetch path,
  refresh-on-apply, soft-fallback semantics) and surfaced the need to
  move several install helpers from executable to library.
- EP-3 was structurally smaller but found two unanticipated wrinkles:
  composition-time dependency failures preempt the pre-flight, and
  the planner-gap silence affects real projects. The first is a UX
  concern for EP-4; the second is the work that became EP-5.
- EP-4 was almost entirely a renderer change once EP-1, EP-2, and
  EP-3 were in. The data-type-locality cleanup (moving
  `OutdatedEntry` to `VersionCompare`) was the only cross-cutting
  edit, and it preserved every existing call site.

Lessons captured so far:

- Decomposing by user-visible command paid off. Each child plan
  closed with a concrete `seihou <command>` invocation against the
  live tree as its acceptance criterion, which made "is this done?"
  unambiguous — and made it possible to spot, after the fact, that
  the chosen acceptance scenario didn't cover the partial-chain
  failure mode that EP-5 is now retiring.
- The Surprises & Discoveries section earned its keep. EP-3's
  planner-gap discovery directly shaped EP-4's documentation
  decisions and pre-staged the EP-5 reopen. Future masterplans should
  keep encouraging contributors to write into Surprises eagerly.
- "Out of scope, deferred to future work" without a follow-up plan
  number is a soft commitment that decays. When EP-3 first noted the
  planner-gap carve-out, the right response was to file a follow-up
  exec-plan immediately rather than relying on the masterplan
  retrospective to remember. Future masterplans should treat any
  deferred work as eligible for an exec-plan number and a Not Started
  registry row, even if implementation is months out.
- Pushing helpers from executable-only to library-exposed is a
  recurring move in this codebase. A repo-wide convention ("CLI
  helpers default to the library; executable target is for the IO
  shell only") would have saved ~3 hours of small refactors across
  EP-1, EP-2, and EP-4. (This convention has since landed via
  `docs/masterplans/2-cli-library-first-convention.md`.)


## Revisions

- 2026-04-26: Reopened the masterplan after live verification on the
  `seihou-project` working tree showed `seihou status` silent and
  `seihou migrate` erroring out for both modules with declared
  migrations that don't reach the latest version exactly (master-plan:
  partial chain; exec-plan: no chain at all). The
  longest-reachable-prefix planner mode that EP-3 and EP-4 had
  documented as "out of scope, deferred to future work" turned out to
  be the common case rather than the edge case. Added EP-5
  (`docs/plans/23-bulletproof-partial-migration-chains.md`) to retire
  the carve-out: the planner returns a reachable prefix plus an
  optional unreachable tail, `seihou migrate` applies the longest
  reachable prefix and refreshes the manifest, `seihou status` renders
  full / partial / blocked rows, and `seihou run` refuses on every
  divergence. Updated the Exec-Plan Registry, Dependency Graph,
  Integration Points (added integration point #6: planner contract;
  extended #2 with the new return shape), Progress, Surprises &
  Discoveries, and Outcomes & Retrospective to reflect the reopen.
  EP-1–EP-4 stay marked Complete within their original scopes.
