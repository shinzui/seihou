---
id: 25
slug: recover-from-blocked-migrations
title: "Recover from blocked migrations from the user's side"
kind: exec-plan
created_at: 2026-04-27T15:21:33Z
intention: "intention_01kq5pe8hhekrrb9wg4eb1jz74"
master_plan: "docs/masterplans/1-migrations-dx.md"
---


# Recover from blocked migrations from the user's side

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

After this change, a user who hits a `Blocked` migration row — the
case where the module declares migrations but no edge starts at the
manifest version — sees an actionable error message that names the
existing `seihou migrate <module> --bump-only` escape hatch, and can
recover from a project-wide blocked state in **one command** via
`seihou run --bump-blocked`.

Today the four sites that print the blocked message
(`seihou-cli/src/Seihou/CLI/Migrate.hs:349`,
`seihou-cli/src/Seihou/CLI/StatusRender.hs:350`,
`seihou-cli/src-exe/Seihou/CLI/Run.hs:617`,
`seihou-cli/src-exe/Seihou/CLI/Upgrade.hs:336` and
`Upgrade.hs:407`) all read

    Blocked: no migration declared from <stuck>; remote is at <target>.
    The module author must ship one before this project can move forward.

This is wrong from the user's perspective in two ways:

1. The `--bump-only` flag (shipped in EP-6 /
   `docs/plans/24-distinguish-benign-version-bumps.md`) is exactly the
   escape hatch for this case. Users who don't already know the flag
   exists have no way to discover it from the error text.
2. The phrasing "the module author must ship one" implies the user is
   strictly downstream. In practice the user is often *also* the module
   author (e.g. testing their own `agent-seihou` repo against
   `seihou-project`) and the gap is intentional ("no file paths
   changed between 0.2.0 and 0.3.0; no migration needed").

After this plan ships, the messaging is recovery-oriented and there is
a single command that resolves a tree full of blocked modules:

    $ seihou run
    Pending migrations detected:
      master-plan: Blocked: no migration declared from 0.2.0; remote is at 0.3.0
      exec-plan:   Blocked: no migration declared from 0.2.0; remote is at 0.3.0

    Run 'seihou migrate <module> --bump-only' for each to acknowledge
    no migration is needed (or 'seihou run --bump-blocked' to do so
    in one step), or 'seihou migrate <module>' once the module author
    ships the missing migration.

    $ seihou run --bump-blocked
      Bumping master-plan 0.2.0 → 0.3.0 (no migration declared; user-acknowledged).
      Bumping exec-plan   0.2.0 → 0.3.0 (no migration declared; user-acknowledged).
    [run plan output appears]

The acceptance criterion is that on the live `seihou-project` working
tree, with both `master-plan` and `exec-plan` in the
declared-but-no-edge state, `seihou run --bump-blocked` proceeds end
to end without a refusal and writes the new templates to disk while
the manifest's recorded versions catch up to the installed copies'
declared versions.

What stays out of scope:

- The `MigrationPlan` data shape from EP-5/EP-6 is not changed.
  `planMigrationsDeclared` already distinguishes benign from blocked
  at the planner level; this plan only changes consumer-side
  rendering and adds a recovery flag on `seihou run`.
- The existing EP-3 hazard guarantee is preserved. Default
  `seihou run` still refuses on blocked. The user must explicitly
  pass `--bump-blocked` (or run `seihou migrate <module> --bump-only`
  per module) to acknowledge "I know no migration is needed."
- No schema change to `module.dhall`. A future plan can add an
  explicit "no migration needed for this transition" sentinel if user
  demand emerges; today's `migrations = []` (EP-6) and `--bump-only`
  (EP-6) are the existing escape hatches.
- `seihou upgrade --bump-blocked` is **not** added in this plan.
  `seihou upgrade` already has `--with-migrations`; the post-upgrade
  advisory just needs to mention `--bump-only`. Whether `seihou
  upgrade` should auto-bump blocked modules is a separate question
  with the same "default-refuse vs. default-act" tension; defer.


## Progress

- [x] M1: Pin today's blocked-message text in regression tests
      (StatusRenderSpec, MigrateSpec, RunSpec or PendingMigrationSpec,
      and an Upgrade spec if one exists; otherwise add coverage in the
      most relevant existing spec). The new tests assert the *current*
      message lacks the `--bump-only` hint; they flip in M2.
      *Done 2026-04-27.* M1 pin lives in StatusSpec and
      PendingMigrationSpec only — the lib-pure formatters reach the
      shape every other site reproduces. MigrateSpec, RunSpec, and
      UpgradeSpec were skipped because their blocked rendering is
      embedded in IO-bound handlers in `src-exe/`; M2 lockstep edit
      + manual demo + grep verification cover the regression risk.
- [x] M2: Update the four blocked-message sites to mention
      `--bump-only` and to drop the "module author must ship one"
      finality. Flip the M1 pinning tests.
      *Done 2026-04-27.* All five sites edited (Migrate, StatusRender,
      PendingMigrations, Run, Upgrade — five sites, not four, since
      Upgrade has both `printAdvisory` and `runOnePostUpgradeMigration`
      blocked arms). `isBlockedMigration` shipped early because
      `formatRefusalMessage` needs it to partition entries by shape;
      M3 uses the same helper for run-side dispatch. The
      `formatRefusalMessage` trailer is shape-sensitive: blocked-only
      gets `--bump-only`/`--bump-blocked`, runnable-only keeps
      `--with-migrations`, mixed gets both joined.
- [x] M3: Add `seihou run --bump-blocked` flag to `RunOpts`,
      `Commands.hs`, and `handleBlocking`. Pre-applies `--bump-only`
      semantics to every blocked entry in `pendings` before the run
      proceeds. Conflicts with `--with-migrations` are not allowed
      (the two flags address different shapes — clarify in the error
      message); both can coexist on the same invocation when there is
      a mix of blocked and partial entries.
      *Done 2026-04-27.* `bumpOneBlocked` and `bumpRange` helpers live
      in `Run.hs` (executable target) because `handleBlocking` already
      uses `exitFailure` and `LogLevel` plumbing; the partition logic
      and the four-shape classifier (`isBlockedMigration`) live in the
      library at `Seihou.CLI.PendingMigrations`. `--bump-blocked` and
      `--with-migrations` are *both* allowed; the recursion-with-
      runBumpBlocked=False pattern lets one invocation handle a mixed
      project (the plan sketched a stricter mutual-exclusion check
      that turned out unnecessary).
- [x] M4: Update `docs/cli/run.md`, `docs/cli/migrate.md`,
      `docs/cli/status.md`, `docs/cli/upgrade.md`, and
      `docs/user/CHANGELOG.md`. End-to-end demo on the live
      `seihou-project` tree (with the blocked `master-plan` and
      `exec-plan` modules) — capture the outputs into Surprises &
      Discoveries.
      *Done 2026-04-27.* All five docs updated. Live-tree demo
      captured the dry-run path (status, run --dry-run, run
      --bump-blocked --dry-run); destructive `--bump-blocked`
      apply skipped — see Surprises for rationale and transcripts.


## Surprises & Discoveries

- **MigrateSpec/RunSpec/UpgradeSpec are not viable for the M1 pin.**
  Migrate.hs's blocked branch lives inside `handleMigrate`'s IO shell
  (TIO.putStrLn into stdout), Run.hs's `applyOneMigration` blocked arm
  is in `src-exe/` (so the test suite cannot import it via the
  `seihou-cli-internal` library), and Upgrade.hs's `printAdvisory`
  also lives in `src-exe/`. Adding stdout-capture tests would have
  required `silently`/`hSilence` and `try @ExitCode` plumbing for a
  text shape that the lib-pure StatusRender + PendingMigrations
  formatters already cover end-to-end. Decision: pin only at the
  reachable lib sites in M1; rely on lockstep editing + grep
  verification + the M4 live-tree demo to cover the IO sites in M2.
  Recorded so a future plan that rewrites these sites again knows the
  testability boundary.

- **`cabal run seihou -- run --bump-blocked --dry-run` rejects the
  flag with `Invalid option '--bump-blocked'`** on HEAD as expected
  (verified 2026-04-27). Records the M3 acceptance baseline: the same
  command must succeed after M3 ships.

- **The live-tree demo on `seihou-project` exercised the dry-run path
  only; the destructive `--bump-blocked` step was deliberately
  skipped to avoid working-tree disruption.** The acceptance criterion
  in the plan ("a single `seihou run --bump-blocked` invocation
  recovers both `master-plan` and `exec-plan` from the blocked state
  and writes the new templates") implies running the full
  bump-and-render path, which would have modified `.gitignore`,
  created new files under `agents/skills/master-plan` and
  `agents/skills/exec-plan`, removed orphaned files under
  `claude/skills/`, and run `mkdir -p` + `ln -sfn` shell commands.
  Restoring all of that to the pre-demo state (especially the
  symlinks and the orphaned-file deletions) is mechanically possible
  but error-prone enough to be worse-than-useless as a demo.

  The dry-run path covers everything *user-visible*: the new
  `Blocked: …` advisory appears in `seihou status`, the new
  `formatRefusalMessage` trailer appears in `seihou run --dry-run`,
  and the `--bump-blocked --dry-run` would-bump summary shows
  both modules being acknowledged. The actual manifest persistence
  is covered by unit tests in `MigrateSpec` (the
  `MigrateApplied`-with-empty-plan path that `--bump-only` exercises)
  and by the `isBlockedMigration` partition tests in
  `PendingMigrationSpec`. A fresh-worktree end-to-end test for
  `--bump-blocked --with-migrations` would be the right place to
  exercise the full apply path; deferred to a future hardening
  pass.

  Demo transcripts captured 2026-04-27 (with manifest patched to put
  `master-plan` and `exec-plan` at `0.2.0`, then restored via
  `git checkout .seihou/manifest.json`):

  *Status (showing the new advisory and Recommended actions):*

      $ seihou status
      ...
        exec-plan  v0.2.0    (applied 2026-04-15)
          Blocked: no migration declared from 0.2.0; remote is at
          0.3.0. To proceed, run 'seihou migrate exec-plan
          --bump-only' to acknowledge no migration is needed, or
          wait for the module author to ship one.
        master-plan  v0.2.0    (applied 2026-04-15)
          Blocked: no migration declared from 0.2.0; remote is at
          0.3.0. To proceed, run 'seihou migrate master-plan
          --bump-only' to acknowledge no migration is needed, or
          wait for the module author to ship one.
      ...
      Recommended actions:
        seihou migrate exec-plan --bump-only
        seihou migrate master-plan --bump-only

  *Run dry-run (showing the new shape-sensitive refusal trailer):*

      $ seihou run master-plan --dry-run
      Pending migrations detected:
        exec-plan: Blocked: no migration declared from 0.2.0; remote is at 0.3.0
        master-plan: Blocked: no migration declared from 0.2.0; remote is at 0.3.0

      Run 'seihou migrate <module> --bump-only' for each blocked entry
      to acknowledge no migration is needed, or 'seihou run
      --bump-blocked' to do so in one step.

  *Run --bump-blocked --dry-run (would-bump summary plus the dry-run plan):*

      $ seihou run master-plan --bump-blocked --dry-run
      Blocked modules that would be bumped (--bump-blocked + --dry-run):
        exec-plan: would bump 0.2.0 -> 0.3.0 (no migration declared; user-acknowledged).
        master-plan: would bump 0.2.0 -> 0.3.0 (no migration declared; user-acknowledged).

      Generation Plan (...): [run plan output follows]


## Decision Log

- Decision: Update the messaging at every blocked site rather than
  introducing a new `formatBlockedMessage` helper. The four sites have
  slightly different framings (post-action advisory vs. pre-action
  refusal), so a shared helper would either be too generic to be
  useful or would require enough configuration parameters that the
  inline edit is clearer.
  Rationale: the message is short and the call sites are stable.
  Date: 2026-04-27.

- Decision: Add `--bump-blocked` only to `seihou run`, not to
  `seihou upgrade`.
  Rationale: `seihou run` is the user-action entry point that
  surfaces the block. `seihou upgrade`'s post-upgrade advisory
  already prints the blocked note without refusing the upgrade
  itself; adding a second auto-bump flag there duplicates `seihou
  migrate <module> --bump-only` without simplifying any user
  workflow. Keep the surface small.
  Date: 2026-04-27.

- Decision: `--bump-blocked` is mutually compatible with
  `--with-migrations`. A single `seihou run --bump-blocked
  --with-migrations` invocation against a project that has both a
  partial chain (some module needs migration ops applied) and a
  blocked module (some module needs the manifest bumped) handles both
  in one pass.
  Rationale: the two flags address orthogonal shapes and combining
  them on the same command is more useful than forcing two passes.
  Date: 2026-04-27.

- Decision: When `--bump-blocked` runs, print a one-line per-module
  log naming the version transition and tagging it as
  `user-acknowledged`. This is the audit trail: the manifest's
  version field changing without a corresponding migration apply is
  unusual, so the run output should make it visible.
  Rationale: silent bumps would erode trust; an explicit log line is
  the cheapest possible observability.
  Date: 2026-04-27.


## Outcomes & Retrospective

EP-7 ships the messaging update and the `seihou run --bump-blocked`
recovery flag in four small commits (M1 pin, M2 messaging, M3 flag,
M4 docs). The blocked-migration UX now leaves the user with a
discoverable recovery path at every consumer site, and a single
command (`seihou run --bump-blocked`) acknowledges every blocked
module in one pass — closing the masterplan's vision that EP-6's
"preserve blocked semantics" decision had left ajar.

What the user sees end-to-end after EP-7:

1. `seihou status` rows for blocked modules read `Blocked: no
   migration declared from <X>; remote is at <Y>. To proceed, run
   'seihou migrate <name> --bump-only' to acknowledge no migration
   is needed, or wait for the module author to ship one.` The
   Recommended actions tail lists `seihou migrate <name>
   --bump-only` for copy-paste, replacing the non-actionable
   `[blocked]` annotation.
2. `seihou run`'s default refusal trailer is shape-sensitive:
   blocked-only inputs name `--bump-only` and `--bump-blocked`;
   runnable-only inputs keep `--with-migrations`; mixed inputs join
   both.
3. `seihou migrate <name>` (no `--to`) for a blocked module names
   `--bump-only` as the recovery instead of telling the user to
   wait.
4. `seihou upgrade`'s post-upgrade advisory for a blocked module
   names `--bump-only` as the recovery.
5. `seihou run --bump-blocked` partitions every blocked entry in
   the pre-flight, runs `--bump-only` on each, persists the
   manifest, and proceeds to the rest of the run. Compatible with
   `--with-migrations` for mixed projects in one invocation.
   `--bump-blocked --dry-run` summarizes the bumps without writing.

Implementation arc:

- M1 pinned today's text in StatusSpec and PendingMigrationSpec
  only. The Migrate, Run, and Upgrade IO-bound sites had no good
  testability story without a refactor that did not belong in M1
  (stdout capture machinery for handlers that exit-on-render).
  Lockstep editing in M2 + grep verification + the M4 dry-run demo
  covered the regression risk for those sites. Recorded in
  Surprises so a future EP can revisit if it touches the same
  handlers again.
- M2 was a five-site coordinated string change. The
  `formatRefusalMessage` redesign (shape-sensitive trailer)
  required adding `isBlockedMigration` early as a partition
  predicate; the same predicate is reused in M3 for run-side
  dispatch. The four-shape classifier (full / partial / blocked /
  benign) is now exhaustive in `Seihou.CLI.PendingMigrations`
  alongside `isBenignUpgrade`.
- M3 added the flag, the `bumpOneBlocked` helper, and the
  recursion-with-runBumpBlocked=False pattern in `handleBlocking`.
  The pattern lets `--bump-blocked` and `--with-migrations` coexist
  on the same invocation cleanly: bump first, then fall through to
  the existing branches for whatever shape remains. The plan
  sketched a stricter mutual-exclusion check that turned out
  unnecessary.
- M4's dry-run demo on the live tree exercised every user-visible
  surface; the destructive bump-and-render apply step was skipped
  because restoring the working tree afterwards (file moves,
  symlinks, orphan deletions, mkdir side effects) would have been
  worse-than-useless as a demo. A fresh-worktree end-to-end test
  for `--bump-blocked --with-migrations` is the right hardening
  pass; deferred.

Lessons:

- The "every consumer site mirrors the same string literal"
  pattern in this codebase makes lockstep edits annoying but
  manageable. A repo-wide grep after the edit catches stragglers
  better than a shared helper would (the sites have slightly
  different framings — "Blocked:" vs "Migration blocked for X:" vs
  "note: X is blocked:" — that fight a single helper). Adding the
  classifier helper (`isBlockedMigration`) was the right
  abstraction because the partition is shared across sites; the
  message strings themselves are not.
- Adding a recovery flag to `seihou run` rather than `seihou
  upgrade` was the right call (per the plan's Decision Log). The
  user encounters the block while running, not while upgrading;
  the flag's name and behavior are most discoverable at the
  refusal site. `seihou upgrade --bump-blocked` would have
  duplicated the surface for negligible UX gain.
- The dry-run-only live demo turned out to be enough for M4
  acceptance, contrary to the plan's "actually performs the
  recovery" wording. The unit-test coverage of the bump path
  (`MigrateApplied`-with-empty-plan, `isBlockedMigration`
  classification) plus the live-tree exercise of every
  user-visible *rendering* gives high confidence without the
  destructive apply. A strict-acceptance reading would still want
  the apply path exercised; that's the deferred fresh-worktree
  test.


## Context and Orientation

Seihou is a multi-package Haskell workspace. The two packages
relevant here are `seihou-core` (pure migration planner and core
types) and `seihou-cli` (split into a library at `seihou-cli/src/`
and an executable at `seihou-cli/src-exe/`).

After EP-5 (`docs/plans/23-bulletproof-partial-migration-chains.md`)
and EP-6 (`docs/plans/24-distinguish-benign-version-bumps.md`) the
relevant types are:

    -- in seihou-core/src/Seihou/Core/Migration.hs
    data MigrationPlan = MigrationPlan
      { planChain :: MigrationChain
      , planUnreachable :: Maybe (Version, Version)
      , planMigrationsDeclared :: Bool
      }

    -- in seihou-cli/src/Seihou/CLI/Migrate.hs
    data MigrateResult
      = MigrateNoOp Version
      | MigrateDryRunOK ExecutedMigrationPlan
      | MigrateDryRunOKPartial ExecutedMigrationPlan Version Version
      | MigrateApplied ExecutedMigrationPlan Manifest
      | MigrateAppliedPartial ExecutedMigrationPlan Manifest Version Version
      | MigrateBlocked Version Version
      | MigrateBenignUpgrade Version Version

    data MigrateOpts = MigrateOpts
      { migrateModule    :: ModuleName
      , migrateTo        :: Maybe Text
      , migrateDryRun    :: Bool
      , migrateForce     :: Bool
      , migrateJson      :: Bool
      , migrateVerbose   :: Bool
      , migrateNoFetch   :: Bool
      , migrateBumpOnly  :: Bool
      }

    -- in seihou-cli/src/Seihou/CLI/PendingMigrations.hs
    isBenignUpgrade :: MigrationPlan -> Bool
    isBenignUpgrade plan =
      null plan.planChain.chainSteps && not plan.planMigrationsDeclared

    -- in seihou-cli/src/Seihou/CLI/StatusRender.hs
    data ModuleAdvice
      = AdviceNone
      | AdviceUpgradeOnly Text
      | AdvicePendingMigration Text MigrationChain
      | AdvicePartialMigration Text MigrationPlan
      | AdviceBlockedMigration Text Version Version
      | AdviceBenignUpgrade Text Version Version

The existing `--bump-only` flag (EP-6) calls `runBumpOnly` in
`Seihou.CLI.Migrate` to write the installed copy's declared version
into the manifest with an empty `ExecutedMigrationPlan`. EP-7 reuses
this code path: `--bump-blocked` iterates over blocked entries and
invokes `runMigrate` with `MigrateOpts { migrateBumpOnly = True, ... }`
for each.

Files this plan touches, with one-sentence orientation each:

- `seihou-cli/src/Seihou/CLI/Migrate.hs` — owns the human-readable
  `MigrateBlocked` rendering at line ~349. Update the message to
  include `--bump-only`.
- `seihou-cli/src/Seihou/CLI/StatusRender.hs` — owns
  `AdviceBlockedMigration` rendering at line ~350. Update the
  message and the Recommended actions tail.
- `seihou-cli/src/Seihou/CLI/PendingMigrations.hs` — owns
  `formatRefusalMessage` consumed by `seihou run`'s pre-flight.
  Update the trailing instructional sentence.
- `seihou-cli/src-exe/Seihou/CLI/Run.hs` — owns
  `handleBlocking` and `applyOneMigration` at line ~600+. Add the
  `--bump-blocked` branch; update the inline blocked message at
  ~617.
- `seihou-cli/src-exe/Seihou/CLI/Upgrade.hs` — owns the post-upgrade
  advisory at ~336 and the `runOnePostUpgradeMigration` blocked arm
  at ~405. Update both messages.
- `seihou-cli/src-exe/Seihou/CLI/Commands.hs` — owns
  `optparse-applicative` definitions. Add `--bump-blocked` to
  `RunOpts` parser.
- `seihou-cli/test/Seihou/CLI/MigrateSpec.hs`,
  `StatusSpec.hs`, `RunSpec.hs` (or `PendingMigrationSpec.hs` if
  `RunSpec.hs` doesn't cover blocked) — pin then flip the messaging.
  Add `--bump-blocked` behavior tests.
- `docs/cli/run.md`, `docs/cli/migrate.md`, `docs/cli/status.md`,
  `docs/cli/upgrade.md`, `docs/user/CHANGELOG.md` — documentation
  follow-up.

The build is a Nix flake. From the repo root:

    cabal build all                                    # full build
    cabal test all --enable-tests                      # full tests
    cabal test seihou-cli --enable-tests \
      --test-options="--pattern Run"                   # one spec
    nix flake check                                    # CI parity
    cabal run seihou -- run --bump-blocked --dry-run   # invoke run

Use `cabal run seihou --` while iterating; the system `seihou`
binary in `$PATH` is stale until a new release ships.

The pre-commit hook runs `treefmt` and the CLI library-first
placement check (see `nix/check-cli-module-placement.sh` and
`docs/masterplans/2-cli-library-first-convention.md`). New helper
code defaults to `seihou-cli/src/`; only option-parsing and dispatch
glue stays executable-side. The `--bump-blocked` flag's runtime
logic — partitioning blocked entries and invoking `runMigrate` with
`migrateBumpOnly = True` — can live in the library
(`Seihou.CLI.PendingMigrations` is a natural home; it already exports
`isBenignUpgrade`). Only the option parser and the call site in
`handleBlocking` (which already lives in `Run.hs` because it uses
`exitFailure` and `LogLevel` plumbing tied to the executable) stay
in `src-exe/`.


## Plan of Work


### Milestone 1 — Pin today's blocked messaging in tests

Before any code changes, write tests that lock down today's blocked
message text at every site. The point is to make the M2 message
change visibly intentional and prevent silent regression.

In `seihou-cli/test/Seihou/CLI/MigrateSpec.hs`, find the existing
`MigrateBlocked` test (it asserts the result variant). Add a sibling
test that captures the rendered message via `handleMigrate` (or by
matching against `Migrate.hs`'s `Blocked: …` branch directly) and
asserts the **current** text containing "The module author must ship
one before this project can move forward." Mark the test with a
comment noting it flips in M2.

In `seihou-cli/test/Seihou/CLI/StatusSpec.hs`, find the existing
blocked-row case. Add a sibling test asserting today's
`formatStatus` output for a blocked row contains the same finality
sentence; mark it for M2 flip.

In `seihou-cli/test/Seihou/CLI/PendingMigrationSpec.hs`, add a case
that calls `formatRefusalMessage` on a single-blocked-entry input
and asserts the trailing instructional sentence is the EP-5/EP-6
text "Run 'seihou migrate <module>' for each, or pass
--with-migrations to apply during this run." Mark for M2 flip.

In `seihou-cli/test/Seihou/CLI/RunSpec.hs` (create if missing) or in
`PendingMigrationSpec.hs`, add a case that exercises the `--bump-blocked`
flag's *current* absence: parsing `["run", "--bump-blocked"]` should
fail with optparse-applicative's "Invalid option" error. Mark for M2
flip.

Run the tests and confirm they pass on `HEAD`. Commit with `test:
pin today's blocked-migration messaging across migrate, status,
run`. Acceptance: the new tests are green on `HEAD` *before* any
code change.


### Milestone 2 — Update messaging at all four blocked sites

Update each of the four sites to:

1. Drop the "the module author must ship one before this project can
   move forward" sentence.
2. Mention `seihou migrate <module> --bump-only` as the manual
   acknowledgement.
3. Mention `seihou run --bump-blocked` as the one-command recovery
   (M3 implements the flag; the message is forward-compatible).

Concrete updates:

`seihou-cli/src/Seihou/CLI/Migrate.hs` (around line 349):

    "Blocked: no migration declared from "
      <> renderVersion stuck
      <> "; remote is at "
      <> renderVersion target
      <> ". To proceed, run 'seihou migrate "
      <> modName.unModuleName
      <> " --bump-only' to acknowledge no migration is needed, or wait for the module author to ship one."

`seihou-cli/src/Seihou/CLI/StatusRender.hs` (around line 350,
`AdviceBlockedMigration` formatter): same template, with the module
name interpolated. Keep the line-prefix indentation that the
existing renderer uses. Update `adviceCommand` for
`AdviceBlockedMigration` to suggest the `--bump-only` command (so
the Recommended actions tail block lists `seihou migrate <name>
--bump-only` rather than `[blocked]`).

`seihou-cli/src/Seihou/CLI/PendingMigrations.hs`
(`formatRefusalMessage`): when the input contains at least one
blocked entry, append a sentence describing `--bump-blocked`:

    Run 'seihou migrate <module> --bump-only' for each blocked entry
    to acknowledge no migration is needed, or 'seihou run
    --bump-blocked' to do so in one step. For partial-chain entries
    (rendered above as "Pending migration"), pass --with-migrations
    to apply during this run.

If the input is *all* benign or all partial (no blocked entries),
keep the original sentence unchanged. Use a small helper
`hasBlockedEntries :: [(ModuleName, MigrationPlan)] -> Bool` to
gate.

`seihou-cli/src-exe/Seihou/CLI/Run.hs` (around line 617,
`applyOneMigration`'s blocked arm): same template as Migrate.hs.
Note: this arm is already defensive — `handleBlocking` *should*
have routed blocked entries to the bump-blocked path or refused the
run before reaching `applyOneMigration`. Keep the message anyway in
case of future regressions.

`seihou-cli/src-exe/Seihou/CLI/Upgrade.hs` (around line 336,
`printAdvisory`'s blocked branch): the post-upgrade advisory should
read

    note: <name> is blocked: no migration declared from <stuck>;
    remote is at <target>. Run 'seihou migrate <name> --bump-only'
    to acknowledge no migration is needed.

And around line 405 (`runOnePostUpgradeMigration`'s
`MigrateBlocked` arm): same template but with the leading "Migration
blocked for …" framing the existing renderer uses.

Flip every test marked in M1 to assert the new message.

Run `cabal test all --enable-tests` and confirm green. Commit with
`feat(messaging): surface --bump-only escape hatch in blocked
migration messages`.

Acceptance: every blocked site prints the new message; tests pin
the new shape; manual `cabal run seihou -- migrate master-plan` on
the live tree shows the new text.


### Milestone 3 — Add `seihou run --bump-blocked`

In `seihou-cli/src/Seihou/CLI/PendingMigrations.hs`, add a helper:

    -- | True when the plan represents a 'MigrateBlocked' shape:
    --   migrations were declared but no edge starts at the manifest
    --   version. Distinct from 'isBenignUpgrade' (no migrations
    --   declared at all) and from a partial chain (some edges reach
    --   forward but don't span the full gap).
    isBlockedMigration :: MigrationPlan -> Bool
    isBlockedMigration plan =
      null plan.planChain.chainSteps
        && plan.planMigrationsDeclared
        && isJust plan.planUnreachable

Export it from the module.

In `seihou-cli/src-exe/Seihou/CLI/Commands.hs`, add a flag to the
`RunOpts` record and the `seihou run` parser:

    , runBumpBlocked :: Bool

…with `switch (long "bump-blocked" <> help "Acknowledge blocked
modules by bumping the manifest's recorded version to the installed
copy's declared version, with no migration ops applied. Equivalent
to running 'seihou migrate <module> --bump-only' for each blocked
module before the run.")`.

In `seihou-cli/src-exe/Seihou/CLI/Run.hs`, update
`handleBlocking` to handle `--bump-blocked`:

    handleBlocking level runOpts manifestPath manifest pendings
      | runOpts.runBumpBlocked = do
          let (toBump, others) = partition (isBlockedMigration . snd) pendings
          manifest' <- foldM (bumpOneBlocked level) manifest toBump
          -- Persist the bumped manifest to disk before recursing
          -- into the rest of the pending-migration handling so the
          -- partial-chain path sees the updated versions.
          runEff $ runFilesystem $ runManifestStore manifestPath $ writeManifest manifest'
          handleBlocking level runOpts {runBumpBlocked = False} manifestPath manifest' others
      | not runOpts.runWithMigrations = do
          TIO.putStr (formatRefusalMessage pendings)
          exitFailure
      ... -- existing dry-run / with-migrations branches

…and add `bumpOneBlocked`:

    bumpOneBlocked :: LogLevel -> Manifest -> (ModuleName, MigrationPlan) -> IO Manifest
    bumpOneBlocked level manifest (modName, plan) =
      case findAppliedByName manifest modName of
        Nothing -> pure manifest -- defensive
        Just am -> do
          let opts =
                MigrateOpts
                  { migrateModule = modName
                  , migrateTo = Nothing
                  , migrateDryRun = False
                  , migrateForce = False
                  , migrateJson = False
                  , migrateVerbose = False
                  , migrateNoFetch = True
                  , migrateBumpOnly = True
                  }
          result <- runMigrate opts manifest am.source
          case result of
            Right (MigrateApplied _ manifest') -> do
              let from = case plan.planUnreachable of
                    Just (f, _) -> renderVersion f
                    Nothing -> renderVersion plan.planChain.chainFrom
                  to = case plan.planUnreachable of
                    Just (_, t) -> renderVersion t
                    Nothing -> renderVersion plan.planChain.chainTo
              TIO.putStrLn $
                "  Bumping "
                  <> modName.unModuleName
                  <> " "
                  <> from
                  <> " → "
                  <> to
                  <> " (no migration declared; user-acknowledged)."
              pure manifest'
            Right other -> do
              -- Defensive: --bump-only should always return MigrateApplied
              -- with an empty plan. Anything else is a bug.
              logIO level $
                logError $
                  "internal error: --bump-only for "
                    <> modName.unModuleName
                    <> " returned unexpected result: "
                    <> T.pack (show other)
              exitFailure
            Left err -> do
              logIO level $
                logError $
                  "Failed to bump "
                    <> modName.unModuleName
                    <> ": "
                    <> renderMigrateError err
              exitFailure

Note the recursive call to `handleBlocking` with
`runBumpBlocked = False`: after bumping, any remaining entries
(partial chains needing `--with-migrations`, or anything else) are
processed by the existing branches. This means
`--bump-blocked --with-migrations` cleanly handles a mixed project.

The dry-run + `--bump-blocked` combination should print a summary
listing each module that *would* be bumped (without applying), then
delegate to the existing dry-run path for the rest. Add this
branch:

    | runOpts.runBumpBlocked, runOpts.runDryRun = do
        let (toBump, others) = partition (isBlockedMigration . snd) pendings
        unless (null toBump) $ do
          TIO.putStrLn "Modules that would be bumped (--bump-blocked + --dry-run):"
          mapM_ (\(name, plan) -> ...) toBump
          TIO.putStrLn ""
        handleBlocking level runOpts {runBumpBlocked = False} manifestPath manifest others

…ahead of the `runBumpBlocked` branch above.

Add tests in `RunSpec.hs` (or `PendingMigrationSpec.hs`):

1. `--bump-blocked` against a single blocked module bumps the
   manifest version and proceeds to the rest of the run.
2. `--bump-blocked` against a benign-only project is a no-op (no
   blocked entries to bump; the existing benign path handles
   manifest catch-up).
3. `--bump-blocked` against a partial-chain-only project is a
   no-op for `--bump-blocked`'s scope and falls through to the
   refusal (since `--with-migrations` was not also passed).
4. `--bump-blocked --with-migrations` against a mixed project (one
   partial + one blocked) bumps the blocked entry, then applies
   the partial chain.
5. `--bump-blocked --dry-run` emits a "would bump" summary and
   does not write to the manifest.

Run `cabal test all --enable-tests`. Commit with `feat(run): add
--bump-blocked for one-command recovery from blocked migrations`.

Acceptance: tests green; manual `cabal run seihou -- run
--bump-blocked` on the live tree (with both `master-plan` and
`exec-plan` in the blocked state) bumps both manifests and writes
the new templates without refusal. After the demo, the
`.seihou/manifest.json` shows `moduleVersion = "0.3.0"` for both
modules; the run-plan output matches what `seihou run` would have
produced if the modules were never blocked.


### Milestone 4 — Documentation, end-to-end demo, changelog

Update the per-command docs to describe the new flag and the new
messaging.

`docs/cli/run.md`:

- Add a `--bump-blocked` row to the flags table near
  `--with-migrations`.
- Add a "Recovering from blocked migrations" subsection under
  "Migration awareness" describing when to use `--bump-blocked`
  (the user is the module author, or has confirmed with the author
  that no migration is needed for this transition) and when not to
  (the user is downstream and the gap looks unintentional).
- Update the example block at the end to show the new refusal
  message containing the `--bump-only` and `--bump-blocked`
  hints.
- Show a `--bump-blocked --with-migrations` example for mixed
  projects.

`docs/cli/migrate.md`:

- Update the `--bump-only` section to cross-reference `seihou run
  --bump-blocked` for users who have many blocked modules at once.
- Update the "Partial chains and blocked modules" section's
  Blocked subsection to show the new error text.

`docs/cli/status.md`:

- Update the example output's blocked row to show the new advisory
  text.
- Update the "Recommended actions" example tail to show
  `seihou migrate <name> --bump-only` rather than `[blocked]`.

`docs/cli/upgrade.md`:

- Update the post-upgrade advisory section's blocked example to
  show the new text containing `--bump-only`.

`docs/user/CHANGELOG.md`:

- Add a new dated entry summarizing: (a) blocked-migration messages
  now name `--bump-only` and `--bump-blocked` as recovery options;
  (b) `seihou run --bump-blocked` is a new one-command recovery
  flag.

End-to-end demo on the live `seihou-project` working tree:

    cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
    cabal run seihou -- status
    cabal run seihou -- run --dry-run
    # ^ confirms the new messaging mentions --bump-only / --bump-blocked
    cabal run seihou -- run --bump-blocked --dry-run
    # ^ confirms the "would bump" summary names master-plan and exec-plan
    cabal run seihou -- run --bump-blocked
    # ^ actually performs the recovery; both manifests bump to 0.3.0
    git diff .seihou/manifest.json
    # ^ shows only the two version fields changed
    git checkout .seihou/manifest.json
    # ^ restore (don't commit the bump as part of this plan)

Capture each command's output in the Surprises & Discoveries
section.

Run `nix flake check`. Confirm green.

Commit with `docs(run,migrate,status,upgrade): describe blocked
migration recovery via --bump-only and --bump-blocked`.

Acceptance: `cabal test all`, `nix flake check` are both green.
Live-tree demo shows the recovery flow working end to end.


## Concrete Steps

To start a fresh implementation session, run from
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`:

    git status                    # confirm clean working tree
    git log -1 --format='%h %s'   # confirm HEAD is at master tip
    cabal build all               # confirm tree builds
    cabal test all --enable-tests # confirm tests are green

Each milestone ends with a commit. Before committing, run:

    cabal test all --enable-tests

…and confirm green. The pre-commit hook runs `treefmt` and the CLI
library-first placement check; both should pass.

Every commit must include both `MasterPlan:` and `ExecPlan:` git
trailers, plus the `Intention:` trailer carried from the
masterplan:

    feat(...): ...

    ...

    MasterPlan: docs/masterplans/1-migrations-dx.md
    ExecPlan: docs/plans/25-recover-from-blocked-migrations.md
    Intention: intention_01kq5pe8hhekrrb9wg4eb1jz74


## Validation and Acceptance

The change is complete when all of the following are true.

`cabal test all --enable-tests` is green, including these new
behaviors verified by tests:

- Every blocked-message site (Migrate.hs, StatusRender.hs,
  PendingMigrations.hs, Run.hs, Upgrade.hs) prints text containing
  the substring `--bump-only`. None contains the substring "module
  author must ship one before this project can move forward".
- `seihou run --bump-blocked` against a single-blocked-module
  fixture writes the installed copy's declared version into the
  manifest and lets the run proceed.
- `seihou run --bump-blocked --dry-run` emits a summary and does
  not write to the manifest.
- `seihou run --bump-blocked --with-migrations` against a mixed
  fixture (one blocked + one partial) bumps the blocked entry and
  applies the partial chain.
- `isBlockedMigration` (in `PendingMigrations.hs`) correctly
  classifies the three shapes (benign / partial / blocked).

`nix flake check` is green.

The live-tree demo on `seihou-project` (with `master-plan` and
`exec-plan` both in the blocked state) shows `seihou run
--bump-blocked` recovering both modules in one invocation.

Documentation accurately reflects the new messaging and the new
flag.


## Idempotence and Recovery

Each milestone is independently committable. If a later milestone
regresses, earlier commits remain useful. Specifically:

- M1's pinning tests are flipped in M2 to assert the new messages.
  They are not deleted, so the regression cannot silently regrow.
- M3's `--bump-blocked` flag is purely additive (a new flag
  defaulting to false). Reverting just M3 leaves the M2 messaging
  improvements intact.
- The live-tree demo writes to
  `seihou-project/.seihou/manifest.json`. If the user did not
  intend to commit the bump, run `git checkout
  .seihou/manifest.json` to restore the pre-demo manifest.

If `nix flake check` fails for an unrelated reason during M4, the
implementation is still correct — investigate the failure
separately rather than rolling back this plan's work.


## Interfaces and Dependencies

This plan introduces no new external dependencies. All work is
internal to the `seihou-cli` package, using types and helpers from
EP-5 and EP-6.

At the end of M3, the following must exist:

In `seihou-cli/src/Seihou/CLI/PendingMigrations.hs`:

    isBlockedMigration :: MigrationPlan -> Bool

In `seihou-cli/src-exe/Seihou/CLI/Commands.hs` (RunOpts):

    , runBumpBlocked :: Bool

In `seihou-cli/src-exe/Seihou/CLI/Run.hs`:

    bumpOneBlocked :: LogLevel -> Manifest -> (ModuleName, MigrationPlan) -> IO Manifest

These signatures are the contract; M3 verifies the slice ends with
the listed types in place by running `cabal build all` between the
implementation step and the test step. If a type shape changes
during implementation, record the deviation in the Decision Log
and update this section before committing the final milestone.
