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

- [x] Confirm the corrected outdated detection from EP-1 flows through `seihou status --check-updates`.
- [x] Update the pending-migration detection in `Status.hs` to use the shared `detectPendingMigrations` helper (factored by EP-3) and run on every status invocation, not only with `--check-updates`.
- [x] Add a remediation hint per outdated/pending row.
- [x] Add a tail summary showing the recommended remediation commands.
- [x] Tests: golden output for the four cases (no issues / outdated only / pending migration only / both).
- [x] End-to-end demonstration on the seihou-project working tree.
- [x] Update `docs/cli/status.md` and `docs/user/CHANGELOG.md`.


## Surprises & Discoveries

- **Status.hs already used the EP-3 shared detector.** The plan
  expected EP-4 to migrate `Status.hs` from a local
  `detectPendingMigrations` to the EP-3 `Seihou.CLI.PendingMigrations`
  module, and to lift the call out of the `--check-updates`
  conditional. EP-3 already did both — by the time EP-4 started,
  `Status.hs` imported `detectPendingMigrations` and called it
  unconditionally outside the `if opts.statusCheckUpdates` block. The
  EP-4 work was therefore purely renderer-side.

- **`OutdatedEntry` had to migrate from the executable to the
  library.** Per the EP-1 surprise on `Seihou.CLI.Outdated` living in
  the executable target, the data type that the new `StatusRender`
  module needs (a library module so tests can call it without IO) was
  not reachable. EP-4 moved `OutdatedEntry`, `CheckStats`, and the
  `ToJSON OutdatedEntry` instance from `Outdated.hs` into
  `Seihou.CLI.VersionCompare`, which was already library-exposed.
  `Outdated.hs` re-exports the same names so existing call sites
  (`Upgrade.hs`, `Status.hs`) compile unchanged. EP-2/EP-3's hints
  about preferring the library variant of helpers carry forward: any
  future module that needs to *consume* outdated entries should
  import from `VersionCompare`.

- **Status rendering moved out of `Status.hs` entirely.** The new
  `Seihou.CLI.StatusRender` (library) holds `formatStatus :: Bool ->
  Manifest -> [TrackedFile] -> Maybe [OutdatedEntry] -> [(ModuleName,
  MigrationChain)] -> Text`. `Status.hs` shrank to a thin IO shell
  (load manifest, optionally fetch updates, detect pending, format,
  print). Tests construct fixtures and call `formatStatus` directly,
  no XDG-redirected fake installed dirs or fake project trees needed.
  Future status surfaces (e.g. a structured JSON output) should add a
  parallel formatter in `StatusRender` rather than re-implementing the
  walk over `manifest.modules`.

- **The "outdated" annotation reflects installed-vs-remote, not
  manifest-vs-remote.** Live demo on the seihou-project working tree
  showed `master-plan v0.1.0 ... up to date` even though the
  manifest is at 0.1.0 and the remote is at 0.3.0. The reason: the
  user had already refreshed `~/.config/seihou/installed/master-plan`
  to 0.3.0 (so `installed == remote`), but never migrated the project.
  This is consistent with `seihou outdated` semantics. The
  pending-migration row would normally bridge this gap (and surface a
  `Pending migration: ... Run: seihou migrate master-plan` hint), but
  see the next bullet.

- **The planner gap silences master-plan's pending row in the live
  demo.** master-plan ships only a `0.1.0 -> 0.2.0` migration in its
  declared chain, but the installed copy is at 0.3.0. The planner
  returns `MigrationGap` and `pendingChainFor` returns `Nothing`, so
  the row prints no hint. This is the exact carry-over that EP-3
  surfaced; EP-4 inherits the same silence and documents it in
  `docs/cli/status.md`. A "longest-reachable-prefix" planner mode
  would let `seihou status` surface a partial advisory ("a
  `0.1.0 -> 0.2.0` step is available; `0.2.0 -> 0.3.0` is uncovered")
  but is out of scope here. End-to-end demo on the seihou-project tree
  showed `exec-plan` correctly flagged outdated with a
  `Run: seihou upgrade exec-plan` hint and a Recommended actions
  block; master-plan was silent for the reason above.

- **The summary line `N module(s) checked, M outdated.` counts every
  installed module, not only applied ones.** A user can see "7
  module(s) checked, 2 outdated" but only 1 outdated row in the
  per-row list because the second outdated module is installed
  globally but not applied to this project. The Recommended actions
  block is correctly scoped to the applied modules (it walks
  `manifest.modules`), so the listed commands match the visible rows.
  No fix needed; documented in `docs/cli/status.md` so the
  count/visible-row discrepancy is not a surprise.


## Decision Log

- Decision: Show pending migrations in `seihou status` even without `--check-updates`.
  Rationale: Pending migrations are detectable purely from the local manifest and the locally installed copy; no network IO is required. Hiding them behind `--check-updates` is misleading.
  Date: 2026-04-26.

- Decision: For each problem row, show a one-line remediation command rather than a generic footer.
  Rationale: Users skim status output; a per-row hint is more discoverable than a footer note.
  Date: 2026-04-26.


## Outcomes & Retrospective

EP-4 finalized the migrations-DX initiative with a renderer-only
change. After EP-3 had already factored `detectPendingMigrations` into
a shared module and lifted it out of the `--check-updates`
conditional, the work that remained was per-row remediation hints, a
`Recommended actions:` tail block, and the new `outdated: X.Y.Z
available` annotation form.

What landed:

- A new `Seihou.CLI.StatusRender` library module containing a pure
  `formatStatus :: Bool -> Manifest -> [TrackedFile] -> Maybe
  [OutdatedEntry] -> [(ModuleName, MigrationChain)] -> Text`. The
  module also exposes `ModuleAdvice` and `moduleAdvice` so callers can
  reason about per-row precedence (a pending migration always wins
  over a bare upgrade hint).
- `Status.hs` shrank to a thin IO shell that loads the manifest,
  optionally fetches outdated entries, calls
  `detectPendingMigrations`, and prints `formatStatus`'s output.
- `OutdatedEntry`, `CheckStats`, and the `ToJSON` instance moved from
  `Outdated.hs` (executable-only) into `VersionCompare.hs`
  (library-exposed) to make the renderer testable. `Outdated.hs`
  re-exports the names so existing call sites compile unchanged.
- Four `StatusSpec` tests cover the four behavioral cases (clean,
  outdated only, pending migration only, both). All 143 tests in the
  suite pass.
- Live demo on the seihou-project tree showed the expected per-row
  hint and Recommended actions block for `exec-plan` (outdated with
  no chain → upgrade hint).

What did not land (deliberate):

- An "incomplete migration coverage" advisory for the planner-gap
  case. master-plan's row is silent on the live tree because the
  planner returns `MigrationGap` rather than a partial chain; the
  planner needs a longest-reachable-prefix mode before `seihou status`
  can surface this. Documented as a carry-over in `docs/cli/status.md`
  and flagged in the masterplan's Surprises section.

The masterplan's vision — "seihou status truthfully reports both
outdated installed modules and pending migrations, and emits a
copy-pasteable next command for each" — is met for every case the
detector currently sees. The planner-gap carve-out is the only
remaining blind spot, and it is out of scope for this masterplan.


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
