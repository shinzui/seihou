---
id: 27
slug: fix-migrate-skips-partial-chain
title: "Fix seihou migrate skipping the reachable prefix when the chain stops one step short of the installed version"
kind: exec-plan
created_at: 2026-04-28T14:22:27Z
intention: "intention_01kq2gy6yde258gd30xjvs85g7"
---


# Fix `seihou migrate` skipping the reachable prefix when the chain stops one step short of the installed version

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

A user has reported that `seihou migrate <module>` does not run the
`0.1 → 0.2` migration step in the following situation:

- The project's manifest records the module at version `0.1`.
- The locally installed copy of the module's `module.dhall` declares
  `version = "0.3"`.
- The module's `migrations` field declares exactly one edge,
  `{ from = "0.1", to = "0.2", ops = [...] }`. There is no migration
  edge that starts at `0.2` (i.e. the author shipped no `0.2 → 0.3`
  step).

Per the system's contract since EP-5
(`docs/plans/23-bulletproof-partial-migration-chains.md`) and EP-6
(`docs/plans/24-distinguish-benign-version-bumps.md`), the expected
behaviour is:

1. The planner returns a "partial chain" plan: a non-empty
   `chainSteps = [ {0.1 → 0.2} ]` plus
   `planUnreachable = Just (0.2, 0.3)` plus
   `planMigrationsDeclared = True`.
2. `seihou migrate` (no `--to` flag) applies the longest reachable
   prefix — the `0.1 → 0.2` edge — refreshes the manifest's recorded
   `moduleVersion` to `0.2`, and prints a `Note: no migration
   declared from 0.2; remote is at 0.3.` advisory.

The user's report says the `0.1 → 0.2` edge is **skipped** entirely:
the manifest stays at `0.1` and the disk is not modified, even though
the chain starts at the manifest version. That is wrong: an
applicable, declared migration edge must always run. The
"unreachable tail" advisory is an *advisory*, not a refusal.

After this plan ships, the user can run the following from a project
that exhibits the bug fixture and observe the fix:

    $ seihou migrate <module>           # without --to
    Migration plan: <module>  0.1 → 0.2
      0.1 → 0.2:
        <ops...>

    1 operation(s), 0 conflict(s).

    ✓ Migrated <module> 0.1 → 0.2.
    Note: no migration declared from 0.2; remote is at 0.3.

    $ jq '.modules[] | select(.name == "<module>") | .version' .seihou/manifest.json
    "0.2"

Before the fix, the user's report says the second command would print
`"0.1"` (no apply happened) or the first command's output would be a
no-op / blocked / benign-upgrade message instead of the chain summary
above.


## Progress

- [x] Locate the precise scenario that reproduces the bug.
      (2026-04-28) Probes 1-4 (two-component versions, default fetch
      with pre-upgrade installed, default fetch with already-upgraded
      installed, stale-installed BenignUpgrade) all *pass* on master
      — the bug is not on those paths. The scenario that reproduces
      it: the local installed copy declares the partial-chain
      migrations list, but the cloned remote has dropped or never
      shipped those edges. The fetch path plans against the *clone's*
      migrations list, classifies the result as
      `MigrateBenignUpgrade` (or `MigrateBlocked`), and never applies
      the locally-declared edge. See Surprises & Discoveries
      "EP-27 reproducer: clone/local migrations divergence" for the
      transcript.
- [x] Add a regression test that pins the correct behaviour for the
      newly localized failing path (M2). (2026-04-28) Added four
      tests under "EP-27 M2:" in
      `seihou-cli/test/Seihou/CLI/MigrateSpec.hs`: applies the
      locally-declared partial chain via the fetch path, applies a
      local-only full chain, dry-run on a divergence partial chain,
      and a sanity test confirming clone-based BenignUpgrade still
      wins when the local copy has no migrations either. Three
      failed on master with `Right (MigrateBenignUpgrade …)` instead
      of the expected applied/dry-run partial.
- [x] Fix the underlying defect (M3). (2026-04-28) Added a local
      fallback in `runMigrateWithFetch` and a helper
      `fallbackToLocal` in
      `seihou-cli/src/Seihou/CLI/Migrate.hs`. When the clone-based
      plan returns `MigrateBenignUpgrade` or `MigrateBlocked`, the
      planner is re-run against the locally installed copy's
      migrations list; if that produces a chain (full or partial,
      executed or dry-run), the local result is preferred. All other
      outcomes from either side keep the original clone-based result.
- [x] Re-run the full test suite plus the live reproducer (M3 + M4).
      (2026-04-28) `cabal test all` passes (802 core + 202 CLI tests),
      `nix flake check` passes (cli-module-placement + treefmt +
      pre-commit), and the live divergence fixture at
      `/tmp/seihou-bug-divergence/` now applies the partial chain in
      one shot. The original `/tmp/seihou-bug-repro/` fixture is
      unchanged in behaviour.
- [x] Update `docs/cli/migrate.md` and `docs/user/CHANGELOG.md` (M4).
      (2026-04-28) Added a "success-path local fallback" paragraph to
      `docs/cli/migrate.md` under the "Default behavior: fetch first"
      section; added a 2026-04-28 entry to `docs/user/CHANGELOG.md`.


## Surprises & Discoveries

### The basic `--no-fetch` reproducer already passes

Before writing this plan, the author built the binary at
`dist-newstyle/build/aarch64-osx/ghc-9.12.2/seihou-cli-0.1.0.0/x/seihou/build/seihou/seihou`
and assembled a hand-rolled fixture in `/tmp/seihou-bug-repro/`
mirroring the user's scenario:

    $ tree /tmp/seihou-bug-repro
    .
    ├── installed/module.dhall   # version="0.3"; migrations=[{0.1→0.2}]
    └── project
        ├── .seihou/manifest.json # moduleVersion="0.1"
        └── old.txt               # tracked file the migration moves

Running `seihou migrate demo --no-fetch` against this fixture printed:

    Migration plan: demo  0.1 → 0.2
      0.1 → 0.2:
        move-file old.txt -> new.txt

    1 operation(s), 0 conflict(s).

    ✓ Migrated demo 0.1 → 0.2.
    Note: no migration declared from 0.2; remote is at 0.3.

…and the manifest was rewritten to `"version":"0.2"` and `old.txt` was
moved to `new.txt`. The migration is **not** skipped on this path.

This means the bug almost certainly lives in one of these other paths
that the basic reproducer did not cover:

1. **The default fetch path** (`runMigrateWithFetch`). When the user
   runs `seihou migrate` without `--no-fetch`, the command clones
   `o.sourceUrl` into a temp dir, runs `discoverRepoContents`, calls
   `findRemoteModuleDir`, and dispatches to `runMigrateLocal` against
   the *clone's* module dir. The fetch path has soft-fallbacks for
   missing `.seihou-origin.json`, clone failure, and "module not in
   remote." If any soft-fallback fires silently and the locally
   installed copy is itself stale or has `migrations = []`, the
   planner could see no edges and return a benign-upgrade or blocked
   shape — not a partial chain — even though the remote does ship the
   edge. The user's terminal output would then look like a
   skipped migration.
2. **`seihou run --with-migrations`**, via
   `applyOneMigration` in `seihou-cli/src-exe/Seihou/CLI/Run.hs`,
   which calls `runMigrate` with `migrateNoFetch = True`. That path
   reads the **installed** module.dhall as the source of truth. If
   the installed copy was refreshed by a previous (successful or
   partial) `seihou migrate` to declare `version = "0.3"` but its
   migrations list lost the `0.1 → 0.2` edge somewhere, the planner
   would observe `migrations = []` against a `0.1 → 0.3` gap and
   classify the result as `MigrateBenignUpgrade` — printed as a "no
   migrations declared" advisory and exiting 0 without running the
   edge.
3. **Status / pending-migration UI in the user's report.** The user
   may be reading a status row whose text is misleading. EP-7's
   blocked-migration messaging now mentions `--bump-only` prominently
   in the refusal text; if a user sees `Note: no migration declared
   from 0.2; remote is at 0.3` and no `Migrated demo` line, they may
   conclude the chain didn't run even though the manifest DID move
   forward to 0.2. This is a UX bug, not a planner bug; the fix is in
   the renderer.

The investigation in M1 picks among these.

### Two-component vs three-component versions are equivalent

`Seihou.Core.Version.Version` pads with trailing zeros when comparing,
so `Version [0,1] == Version [0,1,0]` and the planner treats the
user's two-component versions identically to three-component ones.
This is not a bug source.

### EP-27 reproducer: clone/local migrations divergence (M1 finding)

The bug reproduces deterministically on the default fetch path when
the cloned remote's `migrations` list disagrees with the locally
installed copy's `migrations` list — specifically, when the remote
has dropped (or never shipped) the edge that the locally installed
copy still declares. The fetch path in
`seihou-cli/src/Seihou/CLI/Migrate.hs:runMigrateWithFetch` (lines
645-694 at the time of writing) calls
`runMigrateLocal opts manifest moduleDir` with `moduleDir` set to
the *clone's* module directory; the planner then sees only the
clone's migrations list, and classifies the result as
`MigrateBenignUpgrade` (or `MigrateBlocked`) when no edge in that
list starts at the manifest version. The locally-declared edge is
never consulted, so the manifest stays at the user's version and
nothing on disk moves.

Live transcript against `/tmp/seihou-bug-divergence/` (a fixture
where the local install at `/tmp/seihou-bug-divergence/installed/`
declares `version = "0.3"` and `migrations = [{0.1 -> 0.2}]`, the
remote at `/tmp/seihou-bug-divergence/remote/` declares the same
version with `migrations = []`, and the project's manifest is at
`0.1`):

    $ seihou migrate demo
      Fetching /tmp/seihou-bug-divergence/remote...
    Note: demo has no migrations declared (0.1 -> 0.3). This is a
    benign version bump; run 'seihou upgrade demo && seihou run' to
    refresh templates and bring the manifest up to date.
    $ jq '.modules[0].version' .seihou/manifest.json
    "0.1"

    $ seihou migrate demo --no-fetch
    Migration plan: demo  0.1 → 0.2
      0.1 → 0.2:
        move-file old.txt -> new.txt
    1 operation(s), 0 conflict(s).
    ✓ Migrated demo 0.1 → 0.2.
    Note: no migration declared from 0.2; remote is at 0.3.
    $ jq '.modules[0].version' .seihou/manifest.json
    "0.2"

`--no-fetch` works (it plans against the local install, which
declares the edge). Default fetch silently skips. Same fixture, same
manifest, same locally-declared edge.

Why the divergence happens in real life: the user's installed copy
was acquired at a point when the migration was still declared
(e.g., they ran `seihou upgrade` against an earlier remote, or
hand-installed the module dir from a tarball that included the
migration), and the remote has since dropped the migration declaration
while keeping the version field at the same value (or while moving
to a newer version that shipped no migration covering the older
gap). The user's manifest, however, is still at the pre-migration
version, so the locally-declared edge is genuinely applicable.

The fix surface (M3) is the dispatch in `runMigrateWithFetch`: when
the clone-based plan would refuse to apply (BenignUpgrade or
Blocked), the locally installed copy's migrations list is consulted
as a fallback. If it yields a non-empty chain that starts at the
manifest version, that chain is applied instead. The clone's content
still drives the install refresh after a successful apply, so the
"freshest content" intent of EP-15 is preserved for everything
downstream (templates, version field).

### The ExecPlan registry

This bug touches the same areas as EP-5
(`docs/plans/23-bulletproof-partial-migration-chains.md`),
EP-6 (`docs/plans/24-distinguish-benign-version-bumps.md`), and
EP-7 (`docs/plans/25-recover-from-blocked-migrations.md`). All three
are marked Complete in `docs/masterplans/1-migrations-dx.md`. The
bug being reported here would represent either a regression or a gap
in those plans' test matrices.


## Decision Log

- Decision: Begin with a reproducer that mirrors the user's exact
  scenario rather than rewriting code blind. The fix surface depends
  on which code path is broken.
  Rationale: My initial investigation showed the bug does **not**
  reproduce on the basic `--no-fetch` path. Without a deterministic
  reproducer, any fix risks treating a phantom symptom and making the
  real defect harder to spot.
  Date: 2026-04-28

- Decision: This plan is intentionally a one-bug, one-fix plan with
  no scope creep. It will not refactor the planner, redesign the
  partial-chain advisory wording, or touch unrelated commands.
  Rationale: EP-5 through EP-7 already shipped the partial-chain
  contract; the planner contract is correct. The defect is somewhere
  in a downstream consumer or in a soft-fallback path. Keeping the
  plan narrow keeps the diff reviewable.
  Date: 2026-04-28

- Decision: Fix the divergence-case bug by making
  `runMigrateWithFetch` fall back to the locally installed copy's
  migrations list when the clone-based plan would have refused to
  apply (`MigrateBenignUpgrade` or `MigrateBlocked`). Do not change
  the planner contract or any `MigrateResult` variant. Do not change
  the success path (full chain, partial chain, no-op): those keep
  using the clone's migrations list, preserving EP-15's "freshest
  content" intent for the common case.
  Rationale: The user's mental model is "I have a migration declared
  on disk; running `seihou migrate` should apply it." The current
  fetch path silently throws away that declaration when the remote
  has moved on, and the user has no way to recover except by
  remembering `--no-fetch` (which is poorly discoverable and
  inappropriate as the default since it loses the freshness
  benefit). A targeted local-fallback re-uses the existing
  `runMigrateLocal` and changes only one branch of one function, so
  the diff is reviewable and the contract surface stays exactly
  what EP-5/EP-6/EP-7 settled.
  Date: 2026-04-28

- Decision: Treat `MigrateNoOp` from the local fallback as "the
  fallback has nothing to add"; keep the clone-based result. Treat
  `MigrateApplied`, `MigrateAppliedPartial`, `MigrateDryRunOK`, and
  `MigrateDryRunOKPartial` from the local fallback as "the local
  copy has applicable edges the clone doesn't"; prefer the
  fallback. Treat any error or other variant from the local
  fallback as a non-improvement; keep the clone's result. The
  install refresh from the clone runs after either path succeeds
  with an apply, exactly as before.
  Rationale: A fallback that produces only a no-op or another
  benign/blocked outcome doesn't change the user-visible answer;
  there's no point routing through it. Errors from the fallback
  are confusing if surfaced (the user didn't ask for the local
  path), so they collapse to the clone's outcome.
  Date: 2026-04-28


## Outcomes & Retrospective

### What shipped

The bug was localized to `runMigrateWithFetch` in
`seihou-cli/src/Seihou/CLI/Migrate.hs`. The fix is a 39-line addition:
when the clone-based plan returns `MigrateBenignUpgrade` or
`MigrateBlocked`, a new helper `fallbackToLocal` re-runs
`runMigrateLocal` against the locally installed copy. If that yields
a non-empty chain (`MigrateApplied`, `MigrateAppliedPartial`,
`MigrateDryRunOK`, or `MigrateDryRunOKPartial`), the local result is
preferred; otherwise the original clone-based result stands. The
clone still drives the post-apply install refresh, so the templates
and version field on disk continue to reflect the freshest remote
content.

The diff scope:

- `seihou-cli/src/Seihou/CLI/Migrate.hs` — 1 dispatch + 1 helper.
- `seihou-cli/test/Seihou/CLI/MigrateSpec.hs` — 4 EP-27 M1 probes
  (positive regression pins) + 4 EP-27 M2 regression tests (one of
  which is the negative-case sanity).
- `docs/cli/migrate.md` — one paragraph documenting the fallback.
- `docs/user/CHANGELOG.md` — one entry.

### Comparison against the original purpose

The plan's purpose section anchored the fix on this user-visible
behavior:

    $ seihou migrate <module>           # without --to
    Migration plan: <module>  0.1 → 0.2
      0.1 → 0.2:
        <ops...>
    1 operation(s), 0 conflict(s).
    ✓ Migrated <module> 0.1 → 0.2.
    Note: no migration declared from 0.2; remote is at 0.3.

    $ jq '.modules[] | select(.name == "<module>") | .version' .seihou/manifest.json
    "0.2"

The live transcript on `/tmp/seihou-bug-divergence/project/` after
the fix matches this exactly:

    $ seihou migrate demo
      Fetching /tmp/seihou-bug-divergence/remote...
    Migration plan: demo  0.1 → 0.2
      0.1 → 0.2:
        move-file old.txt -> new.txt
    1 operation(s), 0 conflict(s).
    ✓ Migrated demo 0.1 → 0.2.
    Note: no migration declared from 0.2; remote is at 0.3.
    $ jq '.modules[0].version' .seihou/manifest.json
    "0.2"

### Lessons

- The basic `--no-fetch` reproducer the plan author built was correct
  but insufficient: the bug only triggers when the *clone* and the
  *local installed copy* have *different* migrations lists. The plan
  anticipated this by listing six probes; the divergence case wasn't
  one of them but was an obvious step adjacent to probes 2-4. M1's
  transcript-based reproduction would have benefited from one
  additional probe explicitly testing the divergence shape.
- EP-15's "freshest content" intent and the user's "the migration
  declared on disk should run" mental model are in genuine tension
  when the remote has dropped a migration the local copy still
  declares. The chosen resolution preserves both: the clone is the
  source of truth for *target version* and *templates*, while the
  *migrations list* is taken as a union (clone first; local fallback
  only when the clone has nothing applicable). Future plans that
  touch this dispatch should preserve this asymmetry.
- The fix does not change the planner contract or any
  `MigrateResult` variant, in line with the Decision Log's
  no-scope-creep guardrail. The change is entirely composition-level
  in the IO shell.


## Context and Orientation

**Seihou** is a project scaffolding system written in Haskell. A
*module* is a reusable bundle of templates and configuration. A user
applies a module to a project, which records an *applied module* in
`.seihou/manifest.json` along with the module's version. The module
author can ship *migrations* in the module's `module.dhall` to move a
project from one version of the module to a newer one (e.g. by
renaming files the older template generated).

The migration *planner* is a pure function in
`seihou-core/src/Seihou/Core/Migration.hs`:

    planMigrationChain
      :: Text                        -- module name
      -> [Migration]                 -- declared edges
      -> Version                     -- installed version (manifest)
      -> Version                     -- target version (installed copy)
      -> Either MigrationPlanError (Maybe MigrationPlan)

It greedily walks declared edges starting at `installed`. If the walk
runs out of edges before reaching `target`, the planner returns:

    MigrationPlan
      { planChain          = MigrationChain { chainSteps = [reachable edges] , chainFrom, chainTo = highest reached }
      , planUnreachable    = Just (highest_reached, target)
      , planMigrationsDeclared = True   -- author shipped at least one edge
      }

A chain with a non-empty `chainSteps` and a `Just _` unreachable tail
is a **partial chain**: it ran some edges but did not reach the
target. The expected user-visible behaviour is to *apply* the edges
and *advise* about the unreachable tail.

The CLI dispatcher is in `seihou-cli/src/Seihou/CLI/Migrate.hs`:

    dispatchPlan opts manifest plan
      | null plan.planChain.chainSteps = …blocked / benign / no-op…
      | Just (stuck, target) <- plan.planUnreachable =
          if hasExplicitTo opts
            then …MigrationGap…
            else applyChain opts manifest plan.planChain (Just (stuck, target))
      | otherwise = applyChain opts manifest plan.planChain Nothing

`applyChain` either dry-runs (returning `MigrateDryRunOK` /
`MigrateDryRunOKPartial`) or executes (returning `MigrateApplied` /
`MigrateAppliedPartial`). On a partial apply the manifest is
rewritten to record `chainTo` (the highest reached version) as the
new `moduleVersion` and the IO shell in `handleMigrate` writes it
back to disk.

There are three call paths into `runMigrate`:

1. **`seihou migrate <module>`** dispatched from
   `seihou-cli/src-exe/Main.hs` via `seihou-cli/src-exe/Seihou/CLI/Commands.hs`.
   By default this calls `runMigrateWithFetch`, which clones the
   module's source repo and uses the clone's `module.dhall` as the
   source of truth. With `--no-fetch` it calls `runMigrateLocal`
   directly against the locally installed dir.
2. **`seihou run --with-migrations`** in
   `seihou-cli/src-exe/Seihou/CLI/Run.hs`, via `applyOneMigration`,
   which calls `runMigrate` with `migrateNoFetch = True` and the
   manifest's `am.source` (the locally installed dir) as
   `installedDir`.
3. **`seihou upgrade --with-migrations`** in
   `seihou-cli/src-exe/Seihou/CLI/Upgrade.hs`, which similarly calls
   `runMigrate` with `migrateNoFetch = True` after refreshing the
   installed copy.

The pending-migration *detection* helper used by `status`, `run`'s
pre-flight, and `upgrade` is `pendingChainFor` in
`seihou-cli/src/Seihou/CLI/Migrate.hs`. It calls `planMigrationChain`
with the installed copy's `version` as the target and the manifest's
recorded `moduleVersion` as the installed.

Existing tests covering the partial-chain path:

- `seihou-core/test/Seihou/Core/MigrationSpec.hs`, the test
  `"returns a partial chain plus an unreachable tail when the walk
  gets stuck mid-way"` (lines 60–70 at the time of writing) and
  `"returns a partial plan for the EP-5 master-plan fixture"`
  (lines 75–85) both pin the planner's correct behaviour.
- `seihou-cli/test/Seihou/CLI/MigrateSpec.hs`, the test
  `"applies the longest reachable prefix and surfaces the
  unreachable tail"` (lines 568–594) pins
  `runMigrate`-with-`migrateNoFetch=True` correctly producing
  `MigrateAppliedPartial`. This test passes today against the
  bug fixture's exact shape (manifest at `1.0.0`, installed
  declares `2.0.0`+`3.0.0`, only the `1.0.0 → 2.0.0` edge).

The user's two-component versions (`0.1`, `0.2`, `0.3`) compare
identically to three-component ones (`0.1.0`, `0.2.0`, `0.3.0`) per
`Seihou.Core.Version.Version`'s `Eq`/`Ord` instances, which pad with
trailing zeros to the longer length before comparing.

The fetch-path support module is
`seihou-cli/src/Seihou/CLI/InstallShared.hs` (defines
`OriginInfo`, `cloneRepo`, `installModuleDir`, `readOriginInfo`).
The remote-module-dir locator is `findRemoteModuleDir` inside
`Migrate.hs` (lines 705–717 at the time of writing).


## Plan of Work

The plan has four milestones. Each one is independently verifiable
and ends with a concrete observation.


### Milestone 1 — Localize the failing path with a focused reproducer

Goal: produce a test that fails today and that exactly mirrors the
user's scenario in the failing path.

Approach: build a matrix of probes covering the candidate paths
listed in Surprises & Discoveries, run each, and identify which one
fails. The probes go in
`seihou-cli/test/Seihou/CLI/MigrateSpec.hs` (CLI-layer scenarios) or
`seihou-cli/test/Seihou/CLI/RunSpec.hs` /
`seihou-cli/test/Seihou/CLI/UpgradeSpec.hs` (handler-layer scenarios)
depending on which path is suspected. Reuse the existing
`writeInstalledModule`, `mkManifest`, `defaultOpts`, and
`withFetchFixture` helpers in `MigrateSpec.hs` rather than writing
new fixtures from scratch.

Probes to run, each as a Haskell hspec test in the appropriate spec:

1. **Two-component-version variant of the existing partial-chain
   test.** Mirrors the user's literal version strings ("0.1", "0.2",
   "0.3" without a patch component). Reuses the existing
   `MigrateSpec` runner; expected to pass even today, but pin it to
   guard against future regressions on short version strings.
2. **Default fetch path with a remote that ships the partial-chain
   migrations list.** Use `withFetchFixture` to set up a local
   "remote" git repo whose `module.dhall` declares
   `version = "0.3"` and `migrations = [{0.1 → 0.2}]`, an installed
   copy at `version = "0.1"` with no migrations (the pre-upgrade
   state), and a manifest at `0.1`. Run `runMigrate
   defaultOpts {migrateNoFetch = False}` and assert
   `MigrateAppliedPartial`. This probe most directly covers the path
   I was unable to reproduce manually.
3. **Fetch-path soft-fallback when the clone succeeds but
   `findRemoteModuleDir` returns Nothing.** Construct a remote whose
   registry's `modules` entry is missing or whose path is wrong.
   Run `runMigrate` with `migrateNoFetch = False` and assert the
   command falls back to the locally installed copy and *correctly*
   classifies the partial chain there.
4. **Stale-installed scenario.** Set up an installed copy whose
   `module.dhall` declares `version = "0.3"` but `migrations = []`
   (a "broken state" in which the previous `seihou upgrade` lost the
   migrations list somehow). Run with `migrateNoFetch = True`. The
   planner returns `MigrateBenignUpgrade` here today; the user could
   plausibly read this as "the migration was skipped." If this is
   the path, the fix is to ensure `seihou upgrade` does not write a
   `migrations = []` installed copy when the remote ships edges,
   *not* to change the planner.
5. **`seihou run --with-migrations` against the partial-chain
   fixture.** Spawn the `runOpts` matching the user's scenario, call
   `Seihou.CLI.Run.handlePendingMigrations`, and assert the partial
   chain is applied (manifest moves to `0.2`, disk reflects the
   ops).
6. **`seihou upgrade --with-migrations` against the partial-chain
   fixture.** Same shape but at the upgrade-with-migrations entry
   point in `seihou-cli/src-exe/Seihou/CLI/Upgrade.hs`.

For each probe, record the exact result. The first probe that fails
is the bug; subsequent probes are not needed once the cause is
localized but should still be added as positive regression tests.

Acceptance for M1:

- A failing test exists in the test suite reproducing the
  user-reported behaviour (manifest stays at `0.1`, no apply
  happened).
- The Surprises & Discoveries section is updated with a one-paragraph
  finding naming the failing call path and the offending function /
  branch.

If, after running every probe, none fails, document that result in
Surprises & Discoveries and re-engage the user: the report's
real-world conditions must differ from every probe in some way we
have not captured (different module shape, different sequence of
prior commands, stale binary in the user's PATH, etc.). At that
point, switch to investigating with the user rather than guessing
further.

Concrete commands:

    cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
    cabal test seihou-cli:test:seihou-cli-test \
      --test-show-details=streaming \
      --test-options='--match "Seihou.CLI.Migrate"'

Expected: at least one new test fails with a `MigrateNoOp` /
`MigrateBenignUpgrade` / `MigrateBlocked` outcome where the test
asserted `MigrateAppliedPartial`. Capture the failure transcript and
paste it into Surprises & Discoveries.


### Milestone 2 — Pin the correct behaviour with a regression test

Goal: convert the failing probe from M1 into a permanent regression
test that mirrors the user's scenario as closely as possible. The
test goes in the spec file most appropriate to the failing path
(probably `MigrateSpec.hs`).

The test must:

1. Use two-component version strings (`"0.1"`, `"0.2"`, `"0.3"`),
   not the three-component shape of the existing partial-chain
   tests, so the user's literal report is locked in.
2. Use the same fetch / no-fetch / run / upgrade entry point as the
   failing path. Do not "translate" the test into a different
   layer — that would skip the bug.
3. Assert the full expected outcome: result variant
   (`MigrateAppliedPartial` for `runMigrate` callers; equivalent for
   run / upgrade), manifest's `moduleVersion` field after the apply
   (must be `"0.2"`), and disk state if the migration's ops touch
   files.

Acceptance for M2:

- The new test fails on `master`'s current binary with a clear
  message naming the wrong outcome.
- The test does not depend on network access (use
  `withFetchFixture` for fetch-path coverage; it uses a local file://
  remote with `GIT_ALLOW_PROTOCOL=file`).

Run the same `cabal test` command from M1 and confirm the new test is
the only failure (or one of a small known set).


### Milestone 3 — Fix the defect

Goal: change the smallest possible code surface to make the M2 test
pass without regressing any existing test.

The actual fix surface depends on which path M1 localized. Likely
candidates with sketches of the fix:

- **If the fetch path returns the clone's contents but
  `findRemoteModuleDir` mismatches the module name:** examine
  `findRemoteModuleDir` in `seihou-cli/src/Seihou/CLI/Migrate.hs`
  and the contract it shares with
  `Seihou.Core.Registry.discoverRepoContents`. The fix may be a
  case-sensitivity issue, a registry-vs-single-module dispatch
  mistake, or a path-construction bug.
- **If `seihou upgrade` writes a `migrations = []` installed copy:**
  trace `installModuleDir` and the surrounding upgrade flow in
  `seihou-cli/src-exe/Seihou/CLI/Upgrade.hs`. The fix is to copy
  the migrations field through faithfully. Add a unit test in
  `UpgradeSpec.hs` that an upgrade preserves the remote's migrations
  list.
- **If `applyOneMigration` in `Run.hs` exits early on the
  partial-chain shape:** the existing branch on
  `null plan.planChain.chainSteps` is correct (it triggers only on
  blocked plans). Look for an upstream caller that filters partial
  chains out of the pending list — possibly `detectPendingMigrations`
  or `handlePendingMigrations` mistakenly partitioning partial chains
  into the benign or blocked bucket.

Whatever the fix, do not change the planner's contract or any of the
`MigrateResult` variants. Those are settled by EP-5 and EP-6.

Acceptance for M3:

- The M2 regression test passes.
- `cabal test all` passes with no other regressions.
- `nix flake check` passes (the CLI module-placement check is wired
  there per `CLAUDE.md`).

Concrete validation commands:

    cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
    cabal test all --test-show-details=streaming
    nix flake check

Expected: every existing test continues to pass; the new test passes;
no module-placement or formatting failure.


### Milestone 4 — Live verification and docs

Goal: prove the fix end-to-end against a synthetic remote and update
the user-facing docs.

Live verification: re-run the hand-rolled fixture in
`/tmp/seihou-bug-repro/` (described in Surprises & Discoveries above).
Rebuild the binary:

    cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
    cabal build seihou-cli

…then run the failing path manually. Capture the exact transcript
and paste it into Outcomes & Retrospective.

Docs: edit `docs/cli/migrate.md` only if the fix changed any
user-visible behaviour. Edit `docs/user/CHANGELOG.md` to add an entry
under the next release version describing the bug and the fix in one
or two sentences. Format:

    ### Fixed

    - `seihou migrate <module>` no longer skips the longest
      reachable prefix when no migration starts at the chain's
      stopping point. Previously, in the specific scenario where
      the manifest was at `X`, the installed copy declared
      `version = Z` (with no edge from `Y → Z`), and the only
      declared edge was `X → Y`, the command [insert wrong
      behaviour discovered in M1]. Now the `X → Y` edge is applied,
      the manifest is bumped to `Y`, and a `Note: no migration
      declared from Y; remote is at Z` advisory is printed.

Acceptance for M4:

- The hand-rolled live fixture transcript shows the correct
  behaviour after the fix.
- `docs/cli/migrate.md` and `docs/user/CHANGELOG.md` are updated.
- `git status` is clean.


## Concrete Steps

The build path is fixed across milestones:

    cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
    cabal build seihou-cli

The binary lands at:

    dist-newstyle/build/aarch64-osx/ghc-9.12.2/seihou-cli-0.1.0.0/x/seihou/build/seihou/seihou

(The `aarch64-osx` and GHC-version path components vary by platform;
substitute as needed.)

To run the existing migrate-related tests:

    cabal test seihou-cli:test:seihou-cli-test \
      --test-show-details=streaming \
      --test-options='--match "Seihou.CLI.Migrate"'

Expected output today (before any change):

    Seihou.CLI.Migrate.runMigrate
      …
      applies the longest reachable prefix and surfaces the unreachable tail
      …
    All N tests passed.

To rebuild the hand-rolled live fixture from scratch:

    rm -rf /tmp/seihou-bug-repro
    mkdir -p /tmp/seihou-bug-repro/{installed,project/.seihou}

    # Installed copy: declares 0.3 with one 0.1 → 0.2 migration edge.
    cat > /tmp/seihou-bug-repro/installed/module.dhall <<'DHALL'
    { name = "demo"
    , version = Some "0.3"
    , description = None Text
    , vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }
    , exports = [] : List { var : Text, alias : Optional Text }
    , prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }
    , steps = [] : List { strategy : Text, src : Text, dest : Text, when : Optional Text, patch : Optional Text }
    , commands = [] : List { run : Text, workDir : Optional Text, when : Optional Text }
    , dependencies = [] : List { module : Text, vars : List { name : Text, value : Text } }
    , removal = None { steps : List { action : Text, dest : Text, src : Optional Text }, commands : List { run : Text, workDir : Optional Text, when : Optional Text } }
    , migrations =
        [ { from = "0.1"
          , to = "0.2"
          , ops =
              [ (< MoveFile : { src : Text, dest : Text } | MoveDir : { src : Text, dest : Text } | DeleteFile : { path : Text } | DeleteDir : { path : Text } | RunCommand : { run : Text, workDir : Optional Text } >).MoveFile { src = "old.txt", dest = "new.txt" }
              ]
          }
        ]
    }
    DHALL

    # Project: tracked file old.txt at hash matching its content; manifest at 0.1.
    echo tracked > /tmp/seihou-bug-repro/project/old.txt
    HASH=$(printf 'tracked\n' | shasum -a 256 | awk '{print $1}')
    cat > /tmp/seihou-bug-repro/project/.seihou/manifest.json <<JSON
    { "version": 2
    , "generatedAt": "2026-04-01T10:00:00Z"
    , "modules": [{ "name": "demo"
                  , "source": "/tmp/seihou-bug-repro/installed"
                  , "version": "0.1"
                  , "appliedAt": "2026-04-01T10:00:00Z" }]
    , "variables": {}
    , "files": { "old.txt": { "hash": "$HASH"
                            , "module": "demo"
                            , "strategy": "template"
                            , "generatedAt": "2026-04-01T10:00:00Z" } }
    }
    JSON

Probe the failing path against this fixture; on the basic
`--no-fetch` path, the migration applies correctly today (transcript
captured in Surprises & Discoveries).


## Validation and Acceptance

The plan is complete when:

1. A regression test exists in
   `seihou-cli/test/Seihou/CLI/MigrateSpec.hs` (or a sibling spec
   identified in M1) that:
   - Uses two-component version strings ("0.1", "0.2", "0.3").
   - Asserts the partial chain's `0.1 → 0.2` edge is applied.
   - Asserts the manifest's `moduleVersion` is bumped to `"0.2"`.
   - Asserts the working-tree side effects of the edge's ops.
   - Was failing on `master` before the fix and passes after.
2. The full Cabal test suite and `nix flake check` both pass.
3. The hand-rolled live fixture in `/tmp/seihou-bug-repro/` produces
   a transcript matching the "after the fix" wording in the Purpose
   section above.
4. `docs/cli/migrate.md` and `docs/user/CHANGELOG.md` are updated to
   describe the fix in one paragraph.

A reviewer reading the final diff should be able to point at:

- The new regression test (one or two `it` blocks).
- The targeted fix (one bug, one site).
- The CHANGELOG entry.

…and nothing else. If the diff sprawls beyond those three areas, scope
has crept and the plan should be revised.


## Idempotence and Recovery

Every step in this plan is safe to run repeatedly:

- The hand-rolled fixture lives entirely under `/tmp/seihou-bug-repro/`
  and can be rebuilt from the heredoc commands in Concrete Steps.
- `cabal build` and `cabal test` are idempotent.
- The regression tests use `withSystemTempDirectory` and clean up
  after themselves.

If a milestone's commit lands in a broken state (test fails,
unrelated failure introduced), `git revert` the commit and re-attempt
from the previous known-good HEAD. Do not amend or force-push.

If `nix flake check` fails because of the CLI module-placement check
(`nix/check-cli-module-placement.sh`), trace the offending module's
imports and decide whether it belongs in `seihou-cli/src/` (library)
or `seihou-cli/src-exe/` (executable) per the rules in
`CLAUDE.md` and `docs/dev/architecture/overview.md`.


## Interfaces and Dependencies

This plan's intended scope keeps every existing public type
identical. Specifically, none of these signatures should change:

- `Seihou.Core.Migration.planMigrationChain :: Text -> [Migration] ->
  Version -> Version -> Either MigrationPlanError (Maybe MigrationPlan)`
- `Seihou.Core.Migration.MigrationPlan` (record fields:
  `planChain`, `planUnreachable`, `planMigrationsDeclared`).
- `Seihou.CLI.Migrate.runMigrate :: MigrateOpts -> Manifest ->
  FilePath -> IO (Either MigrateError MigrateResult)`
- `Seihou.CLI.Migrate.MigrateResult` (variants:
  `MigrateNoOp`, `MigrateDryRunOK`, `MigrateDryRunOKPartial`,
  `MigrateApplied`, `MigrateAppliedPartial`, `MigrateBlocked`,
  `MigrateBenignUpgrade`).
- `Seihou.CLI.Migrate.pendingChainFor`,
  `Seihou.CLI.PendingMigrations.detectPendingMigrations`,
  `Seihou.CLI.PendingMigrations.isBenignUpgrade`,
  `Seihou.CLI.PendingMigrations.isBlockedMigration`.

The fix surface is internal: a soft-fallback branch, a renderer
mistake, or a misclassification helper — whichever M1 localizes.

Tests use the helpers already exported by
`seihou-cli/test/Seihou/CLI/MigrateSpec.hs`:

- `writeInstalledModule :: FilePath -> Text -> Text -> IO ()`
- `mkManifest :: Text -> FilePath -> [(FilePath, Text)] -> Manifest`
- `defaultOpts :: MigrateOpts`
- `withFetchFixture :: Text -> Text -> Text -> (FetchFixture -> IO ()) -> IO ()`

Use these as-is; don't introduce new fixture helpers unless the
failing path requires shape the existing helpers can't express.
