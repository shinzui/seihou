# Make `seihou run` migration-aware

MasterPlan: docs/masterplans/1-migrations-dx.md
Intention: intention_01kq5pe8hhekrrb9wg4eb1jz74

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

After this change, `seihou run` will not silently overwrite files that a pending migration would have moved. A user with master-plan v0.1.0 applied who then runs `seihou run master-plan` against a project that has the v0.3.0 source installed will see a clear refusal:

    Pending migration for master-plan: 0.1.0 -> 0.2.0 (6 operations).
    Run `seihou migrate master-plan` first, or pass `seihou run --with-migrations`.

If the user passes `--with-migrations`, the migration chain runs first; then the run plan executes against the migrated layout (so files end up at their new locations rather than their old ones).

Today, `seihou run` ignores migrations entirely. Its dry-run output happily lists `[modified] claude/skills/master-plan/SKILL.md` even when the migration would move that file to `agents/skills/master-plan/SKILL.md`. Without this fix, executing `seihou run` against a project with a pending migration leaves the user with a hybrid layout: stale files at the old paths, fresh template content written into the old paths, and no correspondence with what the new module actually expects.

You can see this working by running `seihou run master-plan --dry-run` from `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou` after EP-1 and EP-2 ship; before this plan, no migration is mentioned; after this plan, the dry-run begins by listing the pending chain and refuses unless `--with-migrations` is passed.


## Progress

- [x] M1+M2: Extracted `Seihou.CLI.PendingMigrations` (filter-aware `detectPendingMigrations` + `formatRefusalMessage`); refactored `Seihou.CLI.Status` to use it.
- [x] M1+M2: Tests for the new helpers in `Seihou.CLI.PendingMigrationSpec` (filter, missing module.dhall, no-chain, message formatting).
- [x] M3+M4: Added `runWithMigrations :: Bool` to `RunOpts`; threaded `--with-migrations` through `Commands.hs`; inserted pre-flight check in `Seihou.CLI.Run.handleRun` between manifest read and diff compute. Refusal path prints `formatRefusalMessage` and exits 1; opt-in path calls `runMigrate` per pending module with `migrateNoFetch=True`, persists the post-migration manifest, and continues; dry-run + opt-in prints a chain summary and proceeds with a pre-migration-state caveat.
- [ ] M5: Additional tests covering the in-band apply path and unrelated-module non-blocking.
- [ ] M6: End-to-end demonstration on the seihou-project working tree.
- [ ] M7: Update `docs/cli/run.md` and `docs/user/CHANGELOG.md`.


## Surprises & Discoveries

- **No `runRun` testable core exists, and the existing pattern doesn't grow one.** EP-3's original plan (Milestone 1) imagined a "`runRun` testable core, equivalent to `handleRun` minus IO setup". The codebase has no such factoring for `handleRun`, `handleUpgrade`, or `handleStatus`; `MigrateSpec` tests `runMigrate` (a small core inside Migrate.hs), `UpgradeSpec` tests `compareVersions` only, and `handleRun` ties together environment lookup, config reading via effectful, manifest IO, recipe expansion, and several Dhall evaluations. Extracting a deterministic core would be a large refactor that this plan does not need to deliver migration awareness. Adopted approach: test the extractable helpers (`detectPendingMigrations`, `formatRefusalMessage`) at unit level and rely on the M6 manual demonstration plus existing `runMigrate` coverage for the auto-apply path.

- **`detectPendingMigrations` previously lived privately inside `Status.hs`.** EP-3 promotes it to `Seihou.CLI.PendingMigrations` (library-exposed) and adds an optional `Maybe (Set ModuleName)` filter so `seihou run` can scope detection to only the modules being run. `Status.hs` calls it with `Nothing` (all applied modules). EP-4 (improve-status-migration-visibility) should import from this module.


## Decision Log

- Decision: Default to refusal; require explicit `--with-migrations` to auto-apply.
  Rationale: Migration ops include `RunCommand` and `DeleteDir` — destructive by design. Auto-applying during a command the user typed for "regenerate templates" would surprise them. Refusal makes the next step discoverable; opt-in keeps the one-command flow available.
  Date: 2026-04-26.

- Decision: When `--with-migrations` is passed, apply the chain before computing the run plan, not after.
  Rationale: The run plan's diff is computed against the on-disk state. Applying the migration first means the diff reflects "old layout migrated to new layout, now compared against new templates", which is what the user wants. Applying after would compute a diff against the pre-migration layout and write into the wrong paths.
  Date: 2026-04-26.

- Decision: Skip the "extract a `runRun` testable core" step. Test extractable helpers at unit level; defer end-to-end verification to the M6 manual demo and the existing `runMigrate` coverage in `MigrateSpec`.
  Rationale: `handleRun` has no analogous core today, and creating one is a larger refactor that exceeds the scope of "make run migration-aware". The behaviour we need to cover (detection, message formatting, chain application) is reachable through smaller pure/IO functions.
  Date: 2026-04-26.

- Decision: `detectPendingMigrations` takes `Maybe (Set ModuleName)`; `Nothing` means all modules, `Just names` filters to those names.
  Rationale: `seihou status` reports pending chains for every applied module, while `seihou run X` should only block when `X` (or its composed deps) has a pending chain. A single function with an optional filter avoids duplicating the IO logic and keeps Status's call site short (`detectPendingMigrations manifest Nothing`).
  Date: 2026-04-26.


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

The run command lives at `seihou-cli/src/Seihou/CLI/Run.hs` (≈ 471 lines). Its high-level flow:

1. Resolve the module name (CLI argument or fzf picker).
2. Expand recipes if applicable.
3. Load composition (primary + additional + transitive deps).
4. Resolve variables.
5. Compile the composed plan.
6. Compute the diff against the existing manifest and disk state.
7. Optionally `--dry-run` or `--diff` and exit.
8. Resolve file conflicts interactively.
9. Execute the plan via `executePlan` (in `seihou-core/src/Seihou/Engine/Run.hs` or similar).
10. Write the new manifest.

The migration subsystem (after EP-2 ships) exposes:

- `pendingChainFor :: AppliedModule -> Module -> Maybe MigrationChain` — pure check.
- `runMigrate :: MigrateInputs -> IO MigrateResult` — IO execution that fetches and applies a chain and updates the manifest.
- `refreshInstalledFromRemote :: AppliedModule -> IO (Either RefreshError InstalledModulePath)` — extracted helper from EP-2 that ensures the installed copy reflects the remote.

For each module the run plan touches, this plan must:

1. Locate the corresponding `AppliedModule` in the existing manifest (by name).
2. Refresh its installed copy if a remote is newer (via the EP-2 helper, only when the user opted into `--with-migrations`).
3. Parse the installed `module.dhall` and call `pendingChainFor`.
4. If any module has a non-empty pending chain and `--with-migrations` is not passed, refuse with the actionable message.
5. If `--with-migrations` is passed, apply each pending chain via the migration engine, then proceed.

A "pending migration" is a non-empty `MigrationChain` returned by `pendingChainFor` for at least one applied module touched by the run plan. The check should consider the modules in the plan, not every applied module in the project (so adding a new module via `run` is not blocked by an unrelated module's pending migration; document this scope decision in the user-facing docs).


## Plan of Work

### Milestone 1 — Reproduce the bug

In `seihou-cli/test/Seihou/CLI/RunSpec.hs` (create if absent), add a test that:

1. Sets up an applied module `demo` at version 1.0.0 in a test project with file `old.txt` recorded.
2. Updates the installed copy to v2.0.0 with a migration `{ from = "1.0.0", to = "2.0.0", ops = [MoveFile { src = "old.txt", dest = "new.txt" }] }` and a new template generating `new.txt`.
3. Invokes `runRun` (the testable core, equivalent to `handleRun` minus IO setup) with no migration flags.
4. Asserts the command refuses with exit non-zero and a message mentioning "Pending migration" and "Run `seihou migrate demo`".

Add a second test exercising the `--with-migrations` path: same fixture, pass `runWithMigrations = True`, assert that `old.txt` is removed, `new.txt` exists with the new template content, and the manifest reflects v2.0.0.

Acceptance: both tests fail on master (the first because run ignores migrations; the second because no flag exists yet).

### Milestone 2 — Add the pre-flight check

Locate the place in `Run.hs` between "compute diff" and "resolve conflicts" (after the manifest has been read but before any disk write). Insert a function:

    detectPendingMigrations
      :: Manifest
      -> [Module]                     -- modules in the run plan
      -> IO [(ModuleName, MigrationChain)]

that, for each module in the plan that is also present in the manifest as an `AppliedModule`, calls `pendingChainFor` and collects any non-empty chains. The function may share its name with the one already in `Status.hs` (lines 84–99); if so, factor the shared logic into a single home (e.g., a new `seihou-cli/src/Seihou/CLI/PendingMigrations.hs`) and have both `Status.hs` and `Run.hs` import it.

### Milestone 3 — Implement the refusal path

If the result of `detectPendingMigrations` is non-empty and `runWithMigrations` is `False`, print:

    Pending migrations detected:
      master-plan: 0.1.0 -> 0.2.0 (6 operations)
      exec-plan:   0.1.3 -> 0.2.0 (4 operations)

    Run `seihou migrate <module>` for each, or pass `--with-migrations` to apply during this run.

…and exit with status 1. Do not execute the plan, do not write the manifest, do not modify any files.

### Milestone 4 — Add `--with-migrations` flag

In `seihou-cli/src/Seihou/CLI/Commands.hs`, locate the `run` option parser. Add a `--with-migrations` boolean flag. Thread it into the run options record.

When the flag is `True` and `detectPendingMigrations` returns chains:

1. For each pending module, invoke the migration engine (the helper EP-2 exposes — likely `runMigrateChain :: MigrationChain -> InstalledModulePath -> ProjectPath -> IO MigrateResult`).
2. After all chains succeed, re-read the manifest (the migrate step updates it).
3. Re-compute the run plan's diff against the now-migrated on-disk state.
4. Proceed with the rest of the run flow as today.

If any chain fails, halt; do not proceed with the run plan.

### Milestone 5 — Tests

Cover:

- No pending migrations: run proceeds normally (regression check that the new path is invisible).
- Pending migrations, no flag: refusal with exit 1 and the expected message.
- Pending migrations, `--with-migrations`: chains applied, plan executed, manifest reflects new versions, files at new paths.
- Pending migration on a module not in the run plan: run is not blocked by it (e.g., user runs only `run X` while module `Y` has pending migrations; only `X`'s chain matters).

### Milestone 6 — End-to-end demonstration

From `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou` after EP-1 and EP-2 ship and `seihou outdated` correctly reports master-plan/exec-plan as outdated:

    $ cabal run seihou-cli -- run master-plan --dry-run
    # expect: refusal listing "Pending migration: master-plan 0.1.0 -> 0.2.0"

    $ cabal run seihou-cli -- run master-plan --with-migrations --dry-run
    # expect: chain shown, plan shown against the post-migration layout

### Milestone 7 — Documentation and CHANGELOG

Update `docs/cli/run.md` (create if absent): add a "Migration awareness" section. Append to `docs/user/CHANGELOG.md`. Update `docs/user/migrations.md` to mention the run-side guardrail and the `--with-migrations` flag.


## Concrete Steps

From the repo root:

    $ cabal build seihou-cli
    $ cabal test seihou-cli --test-options="--match run"

Manual verification:

    $ cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
    $ git diff
    $ cabal run seihou-cli -- run master-plan --dry-run
    # expect refusal with actionable message


## Validation and Acceptance

- `cabal test seihou-cli` passes including new tests.
- `seihou run master-plan --dry-run` against a project with a pending migration refuses with the expected message and exits non-zero.
- `seihou run master-plan --with-migrations` against the same project applies the chain (file moves visible in `git status`) and then writes the new template state into the new paths.
- `seihou run other-module` (a module without a pending migration) succeeds normally even when other applied modules have pending migrations.


## Idempotence and Recovery

The pre-flight check is read-only; repeated invocations are safe. The `--with-migrations` path applies migrations via the same engine as `seihou migrate`, which is best-effort; on partial failure mid-chain, the user is left in an intermediate state and must re-run `seihou migrate <module>` to complete the chain. Document this in `docs/cli/run.md`.

`--dry-run` performs no writes regardless of `--with-migrations`. If both flags are passed, the dry-run shows both the migration chain and the post-migration plan.


## Interfaces and Dependencies

This plan consumes from EP-2 (`docs/plans/15-make-migrate-self-contained.md`):

- `pendingChainFor :: AppliedModule -> Module -> Maybe MigrationChain`
- `runMigrateChain` (or whatever EP-2 exposes as the in-process chain executor)
- `refreshInstalledFromRemote` (when a remote check is needed during the pre-flight)

This plan extends:

    data RunOpts = RunOpts
      { ...
      , runWithMigrations :: Bool   -- new
      }

The integration contract with EP-4 (`docs/plans/17-improve-status-migration-visibility.md`): the shared `detectPendingMigrations` helper this plan factors out (in `Seihou.CLI.PendingMigrations`) is the same one EP-4 calls from `Status.hs`. EP-4 must import this module rather than duplicate the logic.
