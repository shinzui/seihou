# Bulletproof partial migration chains across status, migrate, and run

MasterPlan: docs/masterplans/1-migrations-dx.md
Intention: intention_01kq5pe8hhekrrb9wg4eb1jz74

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

After this change, `seihou status`, `seihou migrate`, and `seihou run` will all
handle the case where a module's declared migration list cannot reach the
locally installed (or target) version exactly. Today that case is silently
swallowed by the migration planner — `planMigrationChain` returns
`Left (MigrationGap …)` whenever the greedy walk runs out of edges before it
reaches the target — and every consumer treats the gap as "no chain at all":

- `seihou status` prints no pending-migration row.
- `seihou run`'s pre-flight check returns `Nothing` and lets the run proceed
  silently, even though the next `run` will write the new template layout
  over the old layout. This is the exact hazard EP-3 was meant to block.
- `seihou migrate <module>` errors out with `"no migration covers the gap from
  X to Y. The module author needs to ship a migration that starts at X."`
  rather than applying any migration step at all.

After this plan, the planner returns *both* the longest reachable prefix
*and* a description of any unreachable tail; consumers act on the prefix
when one exists and surface the tail as an advisory:

- `seihou status` always renders a pending-migration row when the manifest
  version differs from the installed-cache version, with one of three
  shapes:
    1. Full chain reachable: existing behavior — `0.1.0 → 0.3.0 (N steps).
       Run: seihou migrate <module>`.
    2. Partial chain reachable: `0.1.0 → 0.2.0 (N steps). Run: seihou
       migrate <module>` followed by `Note: no migration declared from
       0.2.0; remote is at 0.3.0`.
    3. No chain reachable at all (no edge starts at the manifest version):
       `Blocked: no migration declared from 0.1.0; remote is at 0.3.0.
       The module author must ship one before this project can move
       forward.`
- `seihou migrate <module>` (no `--to` flag) applies the longest reachable
  prefix, refreshes the manifest's `moduleVersion` to the highest reached
  version, and prints the same "remote is at X.Y.Z" advisory if any tail
  remains. With an explicit `--to TARGET`, behavior is unchanged: if the
  declared chain can't reach `TARGET`, the command errors as today (the
  user asked for a specific version they did not get).
- `seihou run` (default, no `--with-migrations`) refuses on every pending
  divergence — full chain, partial chain, or no-chain-at-all — with a clear
  message naming the next command. With `--with-migrations`, it applies
  whatever prefix exists; if there is no prefix at all it refuses (just
  applying the new template over the old layout would be the original
  hazard).

You can see this working by running these commands from
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou` after the plan ships.
At the time of writing the live state on that tree is:

    $ cat .seihou/manifest.json | jq '.modules | map({name, version})'
    [
      ...,
      {"name": "exec-plan",   "version": "0.1.3"},
      {"name": "master-plan", "version": "0.1.0"}
    ]

    $ cat ~/.config/seihou/installed/master-plan/module.dhall | grep version
        , version = Some "0.3.0"
    $ cat ~/.config/seihou/installed/exec-plan/module.dhall | grep version
        , version = Some "0.3.0"

    $ cat ~/.config/seihou/installed/master-plan/module.dhall \
        | sed -n '/migrations =/,/^      \]$/p' \
        | grep -E "from|to"
        , from = "0.1.0"
        , to = "0.2.0"

So master-plan has manifest=0.1.0, cache=0.3.0, declared `[0.1.0 → 0.2.0]`
(partial chain). exec-plan has manifest=0.1.3, cache=0.3.0, no migrations
declared (no-chain-at-all). After this plan:

- `seihou status` lists both modules with the appropriate row shape: a
  partial-chain advisory for master-plan, a "blocked" row for exec-plan.
- `seihou migrate master-plan` applies `0.1.0 → 0.2.0`, refreshes the
  manifest to 0.2.0, and prints `Note: no migration declared from 0.2.0;
  remote is at 0.3.0`.
- `seihou migrate exec-plan` errors with `Blocked: no migration declared
  from 0.1.3; the module author must ship one before this project can move
  forward.`
- `seihou run --dry-run` refuses to plan a write until the migrate is
  applied (or `--with-migrations` is passed). With `--with-migrations`,
  the partial chain for master-plan is applied in-band before the run plan
  executes; for exec-plan, run still refuses (no safe automatic upgrade).


## Progress

- [x] Repro the live-tree failure with regression tests against fixtures
      that mirror master-plan (partial chain) and exec-plan (no chain) and
      assert the current planner returns `MigrationGap` on both.
- [ ] Change the planner contract in `seihou-core/src/Seihou/Core/Migration.hs`:
      introduce a richer success type that returns a (possibly empty)
      reachable chain plus an optional unreachable tail; keep
      `MigrationGap` only as a hard error for the explicit `--to TARGET`
      case where the target cannot be reached.
- [ ] Update every existing planner test in
      `seihou-core/test/Seihou/Core/MigrationSpec.hs` to the new shape.
- [ ] Update `pendingChainFor` in `seihou-cli/src/Seihou/CLI/Migrate.hs` to
      return the new shape; update its callers in `Status.hs` (via
      `PendingMigrations.hs`), `Upgrade.hs`, and `Run.hs`.
- [ ] Update `seihou migrate <module>` to apply the longest reachable
      prefix, refresh the manifest's `moduleVersion`, and print the
      unreachable-tail advisory when one exists. Preserve the
      `--to TARGET` semantics (hard error on partial reach).
- [ ] Update `Seihou.CLI.StatusRender` to emit one of three row shapes
      (full / partial / blocked) based on the new planner result.
- [ ] Update `seihou run`'s pre-flight in `Run.hs` to refuse on every
      divergence; update `--with-migrations` to apply the reachable prefix
      and refuse the no-chain-at-all case.
- [ ] Add tests for the migrate, status, and run consumer paths covering
      full / partial / blocked cases.
- [ ] End-to-end demonstration on
      `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`: status
      shows the truth for both master-plan and exec-plan; `seihou migrate
      master-plan` lands the project at 0.2.0 with the advisory; `seihou
      run --dry-run` refuses by default and refuses for exec-plan even
      with `--with-migrations`.
- [ ] Update `docs/cli/migrate.md`, `docs/cli/status.md`, `docs/cli/run.md`,
      and `docs/user/CHANGELOG.md`.


## Surprises & Discoveries

(None yet — populated during implementation.)

Carry-overs from the parent masterplan that this plan exists to retire:

- EP-3 surprise: "`pendingChainFor` is silent on planner gaps. … This is
  a real gap on the live `seihou-project` working tree: master-plan has
  manifest=0.1.0, installed=0.3.0, migrations=[0.1.0→0.2.0]. Fixing it
  requires changing the planner contract (likely a 'longest-reachable-prefix'
  mode), which is out of EP-3's scope."
- EP-4 surprise: "EP-4 inherited the planner-gap silence rather than
  adding an 'incomplete migration coverage' advisory. … Anyone exploring
  a planner-mode change should also revisit `seihou run`'s pre-flight:
  both call sites would benefit from the same partial-coverage signal."
- Masterplan retrospective ("What stayed out of scope — deliberately"):
  the longest-reachable-prefix planner mode. "Both `seihou run`'s
  pre-flight (EP-3) and `seihou status`'s pending-migration display (EP-4)
  silently fall back to 'no chain' when the migrations list does not reach
  the installed version exactly."

Reopening this work was prompted by a live failure on the seihou-project
tree on 2026-04-26: `seihou status` reported nothing pending for
master-plan or exec-plan despite both being two minor versions behind,
and `seihou migrate master-plan --dry-run` errored with `"no migration
covers the gap from 0.2.0 to 0.3.0"`.


## Decision Log

- Decision: Treat the no-chain-at-all case as a hard refusal in `seihou
  migrate` and `seihou run --with-migrations`, but as a visible row (not
  silence) in `seihou status`.
  Rationale: `migrate` and `run` are write-paths — silently bumping the
  manifest's `moduleVersion` past a missing migration would lose the
  invariant that "the on-disk layout matches the layout the recorded
  version produced". `status` is read-only and the user benefits from
  knowing they are blocked even if no automatic action is available.
  Date: 2026-04-26.

- Decision: Preserve the `--to TARGET` strict-target semantics in
  `seihou migrate`. If the user explicitly asks for a specific version
  and the declared chain cannot reach it, the command errors.
  Rationale: An explicit target is a contract; partial fulfillment would
  be surprising. The implicit "to latest" path (no `--to` flag) is where
  longest-reachable-prefix is the right behavior.
  Date: 2026-04-26.

- Decision: Keep the planner's existing `MigrationOvershoot` and
  `MigrationDuplicateEdge` failure modes as hard errors; only the
  `MigrationGap` path softens into "reachable prefix + unreachable tail".
  Rationale: Overshoot and duplicate-edge are author-side mistakes that
  the planner cannot resolve; a gap is an author-side *omission* that
  the runtime can route around for read-only surfaces.
  Date: 2026-04-26.

- Decision: Refresh the manifest's `moduleVersion` to the highest reached
  version after a partial-chain apply.
  Rationale: This is what the existing full-chain apply does, and it
  preserves the invariant that the manifest reflects the layout currently
  on disk. The next `seihou migrate` from that state will correctly start
  from the new manifest version.
  Date: 2026-04-26.


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

The Seihou CLI is a multi-package Haskell workspace. The two packages relevant
here are:

- `seihou-core` — the pure migration planner and the core types
  (`Manifest`, `AppliedModule`, `Module`, `Migration`, `Version`).
- `seihou-cli` — split into a library (`seihou-cli/src/`) and an
  executable (`seihou-cli/src-exe/`). The library hosts shared logic that
  tests can call without spinning up the executable; the executable hosts
  command dispatch and IO shells. New CLI helper code defaults to the
  library — see `CLAUDE.md` and `docs/dev/architecture/overview.md` for
  the convention.

The migration planner lives at
`seihou-core/src/Seihou/Core/Migration.hs`. Its current contract:

    planMigrationChain ::
      Text ->                               -- module name
      [Migration] ->                        -- declared edges
      Version ->                            -- installed version
      Version ->                            -- target version
      Either MigrationPlanError (Maybe MigrationChain)

A successful return is `Right Nothing` (already at target) or
`Right (Just chain)` (a complete chain to target). Any gap fails with
`Left (MigrationGap stuck target)` — the version we got stuck at and the
target we couldn't reach.

The planner's caller in the migrate execution path is
`seihou-cli/src/Seihou/CLI/Migrate.hs`. The relevant call site is the
`Right (Just chain)` arm around line 274 inside `runMigrateInternal`;
the helper function `pendingChainFor` (line 427) is what `Status.hs`,
`PendingMigrations.hs`, `Upgrade.hs`, and `Run.hs` consume.

The shared detector for status/run is
`seihou-cli/src/Seihou/CLI/PendingMigrations.hs` —
`detectPendingMigrations` walks the manifest, parses each installed
`module.dhall`, and returns a list of `(ModuleName, MigrationChain)`
pairs. Today, modules whose planner result is `Left _` are dropped from
the result via the `Maybe` adapter inside `pendingChainFor` (line 442:
`_ -> Nothing`).

The status renderer is `seihou-cli/src/Seihou/CLI/StatusRender.hs`. It
is a pure function `formatStatus :: Bool -> Manifest -> [TrackedFile] ->
Maybe [OutdatedEntry] -> [(ModuleName, MigrationChain)] -> Text`. The
input list of `(ModuleName, MigrationChain)` is the output of the
detector, so as long as the detector is enriched the renderer surface
just needs a new advisory variant.

The run pre-flight lives in `seihou-cli/src-exe/Seihou/CLI/Run.hs`; it
calls `detectPendingMigrations` with a name filter. The
`--with-migrations` opt-in calls `runMigrate` with `migrateNoFetch =
True` (per the EP-3 surprise about avoiding double clones).

`seihou run` is also gated by `loadComposition`, which fails *before*
the pre-flight if a module declares dependencies the user has not
installed (EP-3 surprise about composition-time failures). That is out of
scope for this plan but is worth keeping in mind when running the live
demo: master-plan's 0.3.0 module.dhall declares a `link-skill`
dependency. The seihou-project tree currently has `link-skill` installed,
so this is not blocking, but check `seihou install link-skill` if a
clean checkout is being used.

The version type and parser are in `seihou-core/src/Seihou/Core/Version.hs`.
A `Version` is a record of three `Int` components plus an optional
prerelease tag; `parseVersion :: Text -> Maybe Version` and
`renderVersion :: Version -> Text` are the entry points.

Existing planner tests are at
`seihou-core/test/Seihou/Core/MigrationSpec.hs`. Existing
`pendingChainFor` tests are at
`seihou-cli/test/Seihou/CLI/PendingMigrationSpec.hs`. Status renderer
tests are at `seihou-cli/test/Seihou/CLI/StatusSpec.hs`. Migrate
end-to-end tests are at `seihou-cli/test/Seihou/CLI/MigrateSpec.hs` and
`seihou-cli/test/Seihou/CLI/MigrateFetchSpec.hs`. Run tests are at
`seihou-cli/test/Seihou/CLI/RunMigrationsSpec.hs`.

The build is a Nix flake. Common commands:

    cabal build all                                      # quick build
    cabal test all                                       # run all tests
    cabal test seihou-cli                                # CLI-only
    cabal test seihou-core                               # core-only
    nix flake check                                      # full CI check
    cabal run seihou -- status                           # invoke the CLI
    cabal run seihou -- migrate master-plan --dry-run   # invoke migrate

Use `cabal run seihou --` rather than the system `seihou` binary while
iterating; the system binary is stale until a new release ships.


## Plan of Work

### Milestone 1 — Reproduce the bug with regression tests

Before changing any behavior, write a test that pins down the current
broken state. In `seihou-core/test/Seihou/Core/MigrationSpec.hs`, add two
cases:

1. Partial chain: declared `[0.1.0 → 0.2.0]`, installed=0.1.0,
   target=0.3.0. Today's planner returns `Left (MigrationGap 0.2.0 0.3.0)`.
   Pin this assertion explicitly so the contract change in Milestone 2 is
   visible as a deliberate test update.
2. No chain at all: declared `[]`, installed=0.1.0, target=0.3.0. Today's
   planner returns `Left (MigrationGap 0.1.0 0.3.0)`. Pin this too.

Then in `seihou-cli/test/Seihou/CLI/PendingMigrationSpec.hs`, add two
parallel cases that go through `pendingChainFor` and assert the current
behavior: both cases return `Nothing`. These tests will be updated in
Milestone 4 to reflect the new behavior; pinning them now ensures the
change is intentional and the regression cannot silently regrow.

Run `cabal test all` and confirm the new tests pass against current
`HEAD`. Commit with `test(migration): pin current MigrationGap behavior
for partial and empty chains`.

Acceptance: the new tests are green on `HEAD`, before any code changes.

### Milestone 2 — Enrich the planner contract

Change the planner result type in
`seihou-core/src/Seihou/Core/Migration.hs`. The proposed shape:

    data MigrationPlan = MigrationPlan
      { planChain :: MigrationChain
      , planUnreachable :: Maybe (Version, Version)
      }
      deriving stock (Eq, Show, Generic)

    planMigrationChain ::
      Text ->
      [Migration] ->
      Version ->                              -- installed
      Version ->                              -- target
      Either MigrationPlanError (Maybe MigrationPlan)

`Right Nothing` still means "already at target". `Right (Just plan)`
returns the longest reachable prefix as a `MigrationChain`, plus an
optional `(stuckAt, target)` describing the tail the planner could not
cover. `MigrationGap` is removed from `MigrationPlanError` since the
planner no longer treats partial coverage as a hard error.

There is one edge case the planner must still distinguish: the
no-chain-at-all case where no edge starts at `installed`. The
`MigrationChain` would have an empty `chainSteps` list and `chainFrom ==
chainTo == installed`. The unreachable tail would be
`Just (installed, target)`. Document this in a Haddock comment on
`MigrationPlan` so consumers know to check `null planChain.chainSteps`
to detect the blocked case.

The greedy walk in `walk` (line 159) is already structured for this
change: instead of returning `Left (MigrationGap current tgt)` on the
empty-edge case, return the chain accumulated so far plus
`Just (current, tgt)` as the unreachable tail.

Update `seihou-core/test/Seihou/Core/MigrationSpec.hs` to the new shape.
The assertion changes for the cases pinned in Milestone 1:

- Partial chain: was `Left (MigrationGap 0.2.0 0.3.0)`. Now: `Right (Just
  (MigrationPlan { planChain = chain[0.1.0→0.2.0],
  planUnreachable = Just (0.2.0, 0.3.0) }))`.
- No chain at all: was `Left (MigrationGap 0.1.0 0.3.0)`. Now: `Right
  (Just (MigrationPlan { planChain = chain[empty],
  planUnreachable = Just (0.1.0, 0.3.0) }))`.

Existing full-chain tests need a trivial wrapper update to extract
`planChain` from `MigrationPlan`.

Run `cabal test seihou-core` and confirm all tests pass. Commit with
`feat(migration): planner returns reachable prefix plus unreachable tail`.

Acceptance: `cabal test seihou-core` is green; planner tests cover all
four behavioral shapes (already at target, full chain, partial chain,
no chain at all).

### Milestone 3 — Adapt `pendingChainFor` and `runMigrate`

Update `seihou-cli/src/Seihou/CLI/Migrate.hs`:

- `pendingChainFor` (line 427) needs a new signature so consumers can
  distinguish full / partial / blocked. Proposed:

      pendingChainFor :: AppliedModule -> Module -> Maybe MigrationPlan

  where the `Maybe` only flips to `Nothing` for parse failures (manifest
  or `module.dhall` missing a usable version). All planner outcomes
  return `Just plan`.

- The `runMigrateInternal` planner call site around line 274 must handle
  the new shape:
    - `Right Nothing` → `MigrateNoOp toV` (already at target).
    - `Right (Just plan)` with `null plan.planChain.chainSteps` → if the
      caller passed `--to`, error with the existing
      `MigratePlanFailed (MigrationGap …)` semantics; otherwise return a
      new `MigrateBlocked` variant carrying the unreachable tail.
    - `Right (Just plan)` with steps and no unreachable tail → existing
      full-chain path.
    - `Right (Just plan)` with steps and an unreachable tail → apply the
      prefix, then return a new `MigrateAppliedPartial` variant carrying
      both the executed plan and the unreachable tail.

- The `executeMigration` call must record `chain.chainTo` (the highest
  reached version) into the manifest's `moduleVersion`. Confirm this is
  already what the full-chain path does — there is a refresh hook that
  EP-2 introduced; the partial path should reuse it unchanged.

Update the renderers (`renderPlan`, `renderMigrateOutcome`, and the
top-level `handleMigrate` in `seihou-cli/src-exe/Seihou/CLI/Migrate.hs`
if it exists, or wherever `MigrateOutcome` is matched) to print the new
variants:

- `MigrateAppliedPartial` →
  `Migration applied: <module>  <from> → <highest-reached>  (N steps).` followed by
  `Note: no migration declared from <highest-reached>; remote is at <target>.`
- `MigrateBlocked` →
  `Blocked: no migration declared from <manifest-version>; remote is at <target>. The module author must ship one before this project can move forward.`

Update `seihou-cli/test/Seihou/CLI/MigrateSpec.hs` and
`MigrateFetchSpec.hs` to cover the partial and blocked paths.

Run `cabal test all`. Commit with `feat(migrate): apply longest reachable
prefix and surface unreachable tail`.

Acceptance: `cabal test seihou-cli` is green. Manual run on the live tree:

    $ cabal run seihou -- migrate master-plan --dry-run
    [shows partial-chain plan + advisory]

    $ cabal run seihou -- migrate exec-plan --dry-run
    [shows blocked: no migration declared from 0.1.3]

### Milestone 4 — Status renderer surfaces partial and blocked rows

Update `seihou-cli/src/Seihou/CLI/StatusRender.hs`:

- Replace `MigrationChain` with `MigrationPlan` in the `pendings`
  parameter type and inside `ModuleAdvice`.
- Extend `ModuleAdvice` with two new variants:
    - `AdvicePartialMigration Text MigrationPlan` — render the chain
      summary, the migrate hint, and the unreachable-tail advisory.
    - `AdviceBlockedMigration Text Version Version` — render the
      blocked row as described under Milestone 3.
- Update `moduleAdvice` to map planner outcomes to advice variants.
- Update the renderer's per-row line and the Recommended actions tail
  block. For `AdviceBlockedMigration`, the Recommended actions line should
  read `[blocked] no migration declared for <module> (<from> → <target>)`;
  do not list a `seihou migrate <module>` command since it would error.

Update `seihou-cli/src/Seihou/CLI/PendingMigrations.hs` so that
`detectPendingMigrations` returns `[(ModuleName, MigrationPlan)]`.
Update `seihou-cli/src-exe/Seihou/CLI/Status.hs`'s call site
accordingly.

Update `seihou-cli/test/Seihou/CLI/StatusSpec.hs` golden tests to add the
partial and blocked cases.

Run `cabal test seihou-cli`. Commit with `feat(status): render partial
and blocked migration rows`.

Acceptance: `cabal test seihou-cli` is green. Manual run on the live
tree:

    $ cabal run seihou -- status
    [shows partial-migration row for master-plan and blocked row for exec-plan]

### Milestone 5 — Run pre-flight handles partial and blocked cases

Update `seihou-cli/src-exe/Seihou/CLI/Run.hs`:

- The pre-flight today uses `detectPendingMigrations` and refuses if the
  result is non-empty. After Milestone 4, every divergence (full /
  partial / blocked) appears in the result, so the existing refusal logic
  fires correctly for all cases by default.
- `--with-migrations` currently calls `runMigrate` for each pending
  module. Update so that:
    - For full-chain and partial-chain entries, call `runMigrate` with
      `migrateNoFetch = True` as today; check the outcome and surface
      `MigrateBlocked` from the partial path as a hard refusal at the run
      level.
    - For blocked entries (where `null planChain.chainSteps && isJust
      planUnreachable`), refuse the run with the same blocked message
      the migrate path would have printed.

Update `seihou-cli/src/Seihou/CLI/PendingMigrations.hs`'s
`formatRefusalMessage` to render partial and blocked entries
distinguishably.

Update `seihou-cli/test/Seihou/CLI/RunMigrationsSpec.hs` to cover the
partial-chain and blocked cases.

Run `cabal test seihou-cli`. Commit with `feat(run): refuse and apply
partial chains; refuse blocked modules`.

Acceptance: `cabal test seihou-cli` is green. Manual run on the live
tree:

    $ cabal run seihou -- run --dry-run
    [refuses with both master-plan partial chain and exec-plan blocked listed]

    $ cabal run seihou -- run --with-migrations --dry-run
    [for master-plan, would apply partial chain; for exec-plan, refuses]

### Milestone 6 — Documentation, end-to-end demo, and changelog

Update the per-command docs:

- `docs/cli/migrate.md` — document the partial-apply semantics, the
  unreachable-tail advisory, and the blocked refusal. Keep the `--to
  TARGET` strict-target note.
- `docs/cli/status.md` — document the three pending-migration row shapes
  (full / partial / blocked). Remove the carry-over note that
  `seihou status` is silent on planner gaps.
- `docs/cli/run.md` — document that pre-flight refuses on every
  divergence (including blocked) and that `--with-migrations` applies
  reachable prefixes.

Add an entry to `docs/user/CHANGELOG.md` summarizing the user-visible
behavior changes:

- `seihou status` now reports modules whose declared migrations don't
  reach the latest version (previously silent).
- `seihou migrate <module>` now applies the longest reachable prefix
  rather than refusing the whole upgrade.
- `seihou run` now refuses on any pending divergence (previously
  silent on planner gaps).

Run the full live-tree demo and capture the output in this plan's
Surprises & Discoveries section so future readers can confirm the fix
landed:

    cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
    cabal run seihou -- status
    cabal run seihou -- migrate master-plan --dry-run
    cabal run seihou -- migrate master-plan
    cabal run seihou -- migrate exec-plan --dry-run
    cabal run seihou -- run --dry-run
    cabal run seihou -- run --with-migrations --dry-run
    cabal run seihou -- status

Commit with `docs(migrate,status,run): document partial-chain handling`.

Run `nix flake check`.

Acceptance: every command in the demo produces the expected output;
`nix flake check` passes; the masterplan's Outcomes & Retrospective is
updated to reflect that the longest-reachable-prefix work shipped.


## Risks and Trade-offs

The planner contract change ripples into every existing test in
`seihou-core/test/Seihou/Core/MigrationSpec.hs` and every consumer in
`seihou-cli`. This is the cost of pulling EP-3 and EP-4's deferred work
in. Each milestone is independently committable; if a later milestone
regresses, earlier commits remain useful.

The strict `--to TARGET` semantics are preserved deliberately. A future
plan could introduce `--to TARGET --partial` if there's user demand, but
that is out of scope here.

The status display still reports cache-vs-remote outdated state via
`OutdatedEntry`, while the new pending-migration row reports
manifest-vs-cache. These are different facts and both are useful, but
the existing `outdated: X.Y.Z available` annotation on a row that also
has a partial-chain advisory may look redundant. Consider suppressing
the bare outdated annotation when a pending-migration row covers the
same module — but only as a polish item if the display gets noisy in
practice.
