# Make `seihou status` truthful about staleness and pending migrations

MasterPlan: docs/masterplans/1-migrations-dx.md
Intention: intention_01kq5pe8hhekrrb9wg4eb1jz74

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

After this change, `seihou status` will surface every actionable migration- or upgrade-related task with a copy-pasteable next command. A user running `seihou status --check-updates` against a project with master-plan at 0.1.0 (manifest) but a 0.3.0 module published with a 0.1.0 → 0.2.0 migration declared will see:

    Applied modules:
      master-plan  v0.1.0   (applied 2026-04-15)   outdated: 0.3.0 available
        Pending migration: 0.1.0 -> 0.2.0 (6 operations). Run: seihou migrate master-plan

    ...

    To upgrade and migrate all outdated modules:
      seihou migrate <module>     # for each row above

Today the same command reports `up to date` for everything (because EP-1 has not landed) and prints no migration advisory (the existing pending-migration detection logic never fires when manifest version equals installed version, which is also the case today even when a migration is genuinely pending against the public repo).

You can see this working by running `seihou status --check-updates` from `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou` after EP-1 ships; the output should list outdated modules and pending migrations with the exact remediation command each user should run.


## Progress

- [ ] Confirm the corrected outdated detection from EP-1 flows through `seihou status --check-updates`.
- [ ] Update the pending-migration detection in `Status.hs` to use the shared `detectPendingMigrations` helper (factored by EP-3) and run on every status invocation, not only with `--check-updates`.
- [ ] Add a remediation hint per outdated/pending row.
- [ ] Add a tail summary showing the recommended remediation commands.
- [ ] Tests: golden output for the four cases (no issues / outdated only / pending migration only / both).
- [ ] End-to-end demonstration on the seihou-project working tree.
- [ ] Update `docs/cli/status.md` and `docs/user/CHANGELOG.md`.


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Show pending migrations in `seihou status` even without `--check-updates`.
  Rationale: Pending migrations are detectable purely from the local manifest and the locally installed copy; no network IO is required. Hiding them behind `--check-updates` is misleading.
  Date: 2026-04-26.

- Decision: For each problem row, show a one-line remediation command rather than a generic footer.
  Rationale: Users skim status output; a per-row hint is more discoverable than a footer note.
  Date: 2026-04-26.


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

The status command lives at `seihou-cli/src/Seihou/CLI/Status.hs`. Its current high-level shape:

1. Load the manifest and compute file statuses against disk.
2. Optionally fetch update-check entries (only with `--check-updates`).
3. Detect pending migrations via a local `detectPendingMigrations` (lines around 84–99 today) that walks each `AppliedModule`, parses the installed `module.dhall`, and calls `pendingChainFor`.
4. Render the status block.

The bug is two-fold:

- The "outdated" column uses the same registry-version comparison that `seihou outdated` does. Once EP-1 (`docs/plans/14-fix-outdated-version-detection.md`) ships, this becomes correct automatically.
- The pending-migration detection runs only inside the `--check-updates` codepath today; it should run unconditionally because it is purely local.

EP-3 (`docs/plans/16-make-run-migration-aware.md`) factors out the pending-migration detection into `seihou-cli/src/Seihou/CLI/PendingMigrations.hs`. This plan switches `Status.hs` to import that shared module.

A "remediation hint" here is a single line printed below a problem row that names the exact command to fix the situation. Examples:

    Run: seihou migrate master-plan
    Run: seihou upgrade master-plan && seihou migrate master-plan

The first form is preferred wherever EP-2's self-contained migrate covers the case (which, after EP-2, is most cases).


## Plan of Work

### Milestone 1 — Confirm EP-1's effect propagates

Before adding new behavior, run `seihou status --check-updates` against the seihou-project working tree (after EP-1 ships) and confirm `master-plan` and `exec-plan` show `outdated`. If they do not, EP-1's changes are not reaching the status command; investigate before continuing. Append findings to Surprises & Discoveries.

### Milestone 2 — Move pending-migration detection out of `--check-updates`

In `Status.hs`, lift the `detectPendingMigrations` call out of the conditional `--check-updates` block so it runs on every invocation. The function is local and pure of network IO (it reads only the local manifest and the locally installed `module.dhall`), so this adds no latency.

If EP-3 has shipped, import `Seihou.CLI.PendingMigrations.detectPendingMigrations` instead of using the local copy; delete the local copy.

### Milestone 3 — Render outdated column

After EP-1, the existing `--check-updates` logic should already produce a per-row "outdated: X.Y.Z available" suffix when the remote is newer. Verify the rendering shows this suffix; if it currently only prints "up to date" or nothing, update the row formatter to print "outdated: X.Y.Z available" using the same color/style as today's "up to date" marker (the codebase has helpers for this; reuse them).

### Milestone 4 — Render per-row remediation hints

For each row that is either outdated or has a pending migration:

- Pending migration only: `        Pending migration: 0.1.0 -> 0.2.0 (N operations). Run: seihou migrate <name>`
- Outdated only (no migration declared): `        Run: seihou upgrade <name>`
- Outdated + pending migration: `        Pending migration: ... Run: seihou migrate <name>` (since EP-2's migrate is self-contained, one command suffices)

Indent the hint two characters past the row's indentation so it visually attaches to its row.

### Milestone 5 — Tail summary

After the per-module list, if any rows had problems, print a short summary block listing the recommended commands. Example:

    Recommended actions:
      seihou migrate master-plan
      seihou upgrade other-thing
      seihou migrate exec-plan

If no rows had problems, omit the block.

### Milestone 6 — Tests

In `seihou-cli/test/Seihou/CLI/StatusSpec.hs` (create if absent), add four golden-output tests:

- All modules clean: no remediation, no summary.
- One module outdated, no migrations declared: row shows "outdated", hint shows `seihou upgrade <name>`, summary lists it.
- One module with pending migration, version current: row shows pending migration, hint shows `seihou migrate <name>`.
- One module both outdated and with declared migration: hint shows `seihou migrate <name>` only (single command suffices).

Each test sets up XDG-redirected fake installed dirs and a fake project working tree (similar to the EP-1 and EP-2 fixtures).

### Milestone 7 — End-to-end demonstration

From `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou` after EP-1 and EP-2 ship:

    $ cabal run seihou-cli -- status --check-updates
    # expect:
    #   master-plan v0.1.0  outdated: 0.3.0 available
    #     Pending migration: 0.1.0 -> 0.2.0 (6 operations). Run: seihou migrate master-plan
    #   exec-plan v0.1.3  outdated: 0.3.0 available
    #     Run: seihou migrate exec-plan        (or seihou upgrade exec-plan if no migration declared between 0.1.3 and 0.3.0)
    #
    # Recommended actions:
    #   seihou migrate master-plan
    #   seihou migrate exec-plan

### Milestone 8 — Documentation and CHANGELOG

Create or update `docs/cli/status.md` to describe the new output. Append to `docs/user/CHANGELOG.md`.


## Concrete Steps

From the repo root:

    $ cabal build seihou-cli
    $ cabal test seihou-cli --test-options="--match status"

Manual verification:

    $ cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
    $ cabal run seihou-cli -- status
    $ cabal run seihou-cli -- status --check-updates


## Validation and Acceptance

- `cabal test seihou-cli` passes including new tests.
- `seihou status` (without `--check-updates`) lists pending migrations with a remediation hint, even if no network IO is performed.
- `seihou status --check-updates` lists outdated modules with a remediation hint and a tail summary, and the listed commands actually fix the listed problems when run.
- The output is stable across re-runs (idempotent rendering; no spurious "modified" rows from temp file writes).


## Idempotence and Recovery

This plan only changes read paths and rendering. Repeated `seihou status` invocations have no side effects. If `detectPendingMigrations` cannot read an installed `module.dhall` (e.g., it was removed manually), the row should fall back to "Pending migration: unknown — run `seihou migrate <name>` to recover" rather than crashing the whole status command.


## Interfaces and Dependencies

This plan consumes:

- The corrected outdated detection from EP-1 (`docs/plans/14-fix-outdated-version-detection.md`).
- The `detectPendingMigrations` helper from EP-3's factoring (`Seihou.CLI.PendingMigrations`) — or, if EP-3 has not yet shipped, the existing `detectPendingMigrations` local to `Status.hs` is acceptable as a starting point and is replaced by the shared helper later.

This plan does not extend any data type. It changes only the rendering layer of `Status.hs` and the import set.
