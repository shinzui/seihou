# Bump through partial-chain tail when no further migrations are declared

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

After EP-27 (`docs/plans/27-fix-migrate-skips-partial-chain.md`), a
user running `seihou migrate <module>` no longer silently skips a
locally-declared migration. The chain *applies*, the manifest *moves*,
and a `Note: no migration declared from <stuckAt>; remote is at
<target>.` advisory tells the user there's still a gap.

That advisory is correct, but the user-visible workflow it asks for
is wrong by one step. After running `seihou migrate master-plan`
against a project where:

- the manifest records `master-plan` at `0.1.0`,
- the locally installed copy declares `version = "0.3.0"` with
  `migrations = [{0.1.0 → 0.2.0}]` (one edge), and
- the cloned remote agrees,

the user gets:

    $ seihou migrate master-plan
    Migration plan: master-plan  0.1.0 → 0.2.0
      0.1.0 → 0.2.0:
        <ops>
    ✓ Migrated master-plan 0.1.0 → 0.2.0.
    Note: no migration declared from 0.2.0; remote is at 0.3.0.

…and now their manifest is at `0.2.0`, not `0.3.0`. To finish the
upgrade they have to run a *second* command:

    $ seihou migrate master-plan --bump-only
    ✓ Bumped master-plan 0.2.0 → 0.3.0 (no migration ops).

That's two commands for one mental operation: "I want to upgrade to
the version the installed copy declares." The DX failure is real and
the user's frustration is real. After this plan ships, the same
project produces a one-shot transcript:

    $ seihou migrate master-plan
    Migration plan: master-plan  0.1.0 → 0.2.0
      0.1.0 → 0.2.0:
        <ops>
    ✓ Migrated master-plan 0.1.0 → 0.3.0.
      0.1.0 → 0.2.0: applied (1 migration).
      0.2.0 → 0.3.0: no migration declared; bumped through.

The manifest lands at `0.3.0`. No second command. The advisory
becomes a one-line trailer in the apply summary instead of a blocker
the user has to remember to clear.

The fix only covers cases where the *unreachable tail* of the chain
declares no further migrations at all (the migrations list is
*exhausted* past the chain's stopping point). When the migrations
list contains an edge starting at some version *past* the stopping
point but it doesn't form a continuous chain (the EP-5 master-plan
fixture shape: edges at `0.1.0 → 0.2.0` and `0.5.0 → 0.6.0`, manifest
at `0.1.0`, target `0.6.0`), the user is genuinely blocked: the
author has plans in the unreachable region but the chain doesn't
span the gap. EP-5/EP-6/EP-7's "blocked" semantics still apply there
— the manifest stops at the chain's end and the user has to either
wait for the author to ship a continuation migration or run
`--bump-only` to acknowledge.


## Progress

- [ ] M1: Add `planTailExhausted :: Bool` to `MigrationPlan` in
      `seihou-core/src/Seihou/Core/Migration.hs`. Extend the planner
      to set this field and add tests in
      `seihou-core/test/Seihou/Core/MigrationSpec.hs`.
- [ ] M2: In `seihou-cli/src/Seihou/CLI/Migrate.hs`, dispatch
      partial-chain plans with `planTailExhausted = True` to a new
      apply path that runs the chain *and* bumps the manifest to the
      target version. Add tests in
      `seihou-cli/test/Seihou/CLI/MigrateSpec.hs`. Render the new
      apply variant correctly in `handleMigrate`.
- [ ] M3: Update `pendingChainFor`-driven displays
      (`seihou status`, `seihou run`'s pre-flight,
      `seihou upgrade --with-migrations`'s post-upgrade advisory) so
      they describe an exhausted-tail partial chain as "would
      migrate fully to <target>" rather than "Blocked at
      <chainTo>". Add tests for the affected modules
      (`StatusRenderSpec.hs`, `PendingMigrationSpec.hs`).
- [ ] M4: Live verification on the seihou-project working tree (the
      same `master-plan 0.1.0 → 0.3.0` shape the user ran into) plus
      docs: `docs/cli/migrate.md`, `docs/cli/status.md` if needed,
      and `docs/user/CHANGELOG.md`.


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Add a new planner field `planTailExhausted :: Bool`
  rather than computing the distinction at every CLI consumer.
  Rationale: The migrations list is the only input that determines
  whether the tail is exhausted vs blocked. The planner already
  decodes that list and walks it once; computing the predicate
  there is cheap and consolidates the rule. Every CLI consumer
  (migrate, status, run pre-flight, upgrade post-advisory) needs
  the same answer; duplicating the predicate across files is
  brittle.
  Date: 2026-04-28

- Decision: Treat "exhausted tail" as: no migration in the
  *declared list* has `from > stuckAt` (where `stuckAt` is the
  highest version the chain reaches, equivalently
  `chainTo`). Edges with `from < stuckAt` are either unused (the
  walker overshot them by picking a longer step) or already
  applied; either way they're not "future" edges. Edges with
  `from == stuckAt` would have been picked by the walker — if the
  tail exists at all, no edge has `from == stuckAt`.
  Rationale: The user's mental model for "is the tail benign?" is
  "did the author declare any migrations for the unreachable
  region?". Edges in the past don't count; edges starting at
  `stuckAt` would have been picked. Only future edges (with
  `from > stuckAt`) signal author plans for the gap.
  Date: 2026-04-28

- Decision: When a partial chain has an exhausted tail, the
  migrate command runs the chain (via `executeMigration`) and
  *also* writes the target version into the manifest. The chain's
  `chainTo` stays at the highest reached migration version
  (the prefix's end); only the manifest's recorded
  `moduleVersion` advances all the way to `target`. The user-facing
  result variant is a new `MigrateAppliedBumpedThrough`
  (and a corresponding `MigrateDryRunOKBumpedThrough`).
  Rationale: The chain summary needs to faithfully describe what
  migration ops ran (which is the prefix, not the bump-through
  region). The manifest summary needs to describe where the user
  lands (which is `target`). Conflating the two into the existing
  `MigrateApplied` variant would make the chain's `chainFrom →
  chainTo` field lie about either the migration ops (too wide) or
  the manifest's final version (too narrow). A new variant carries
  both pieces honestly.
  Date: 2026-04-28

- Decision: `--to TARGET` keeps the strict-target contract. If the
  user explicitly named a target version, partial-with-bumped-tail
  still surfaces as `MigrationGap` because the user asked for an
  exact version they did not get a *migration* coverage for.
  Rationale: The strict-target contract from EP-5 exists so that
  scripted callers can rely on `--to X` either reaching `X` via
  declared migrations or failing loudly. Auto-bumping through under
  `--to` would invert that contract. Users who want the bump-through
  semantics should omit `--to` (the natural default for "upgrade to
  the latest"); users who specifically want to bump the manifest
  forward without ops still have `--bump-only`.
  Date: 2026-04-28

- Decision: This plan does not change the `seihou run --bump-blocked`
  flag from EP-7. Blocked entries (with future edges declared)
  remain a separate recovery path. EP-28's auto-bump is restricted to
  exhausted-tail partial chains where the bump is unambiguous.
  Rationale: A blocked entry signals "the author owes a migration
  here." Auto-bumping in that case would silently paper over a real
  gap. `--bump-blocked` is the explicit user-driven acknowledgment
  for that case and should stay opt-in.
  Date: 2026-04-28


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

**Seihou** is a project scaffolding system written in Haskell. A
*module* is a reusable bundle of templates and configuration. A user
applies a module to a project, which records an *applied module* in
`.seihou/manifest.json` along with the module's version. The module
author can ship *migrations* in the module's `module.dhall` to move a
project from one version of the module to a newer one (e.g. by
renaming files the older template generated).

The migration *planner* lives in
`seihou-core/src/Seihou/Core/Migration.hs`. Its result type is:

    data MigrationPlan = MigrationPlan
      { planChain          :: MigrationChain
      , planUnreachable    :: Maybe (Version, Version)
      , planMigrationsDeclared :: Bool
      }

`planChain.chainSteps` is the longest reachable prefix of declared
migrations starting at the manifest's recorded version.
`planUnreachable` is `Just (stuckAt, target)` when the chain stops
short, where `stuckAt` is the highest version the chain reaches.
`planMigrationsDeclared` is `True` when the input migrations list was
non-empty.

The four shapes today (EP-5/EP-6 contract):

- **Full chain** — `chainSteps` non-empty, `planUnreachable ==
  Nothing`. The chain reaches the target exactly.
- **Partial chain** — `chainSteps` non-empty, `planUnreachable` is
  `Just`. The chain reaches some intermediate version. The migrate
  command applies the prefix and prints a `Note:` advisory.
- **Blocked** — `chainSteps == []`, `planUnreachable` is `Just`,
  `planMigrationsDeclared == True`. The author shipped migrations but
  none reach the manifest version. Migrate prints a `Blocked:`
  advisory pointing at `--bump-only`.
- **Benign** — `chainSteps == []`, `planUnreachable` is `Just`,
  `planMigrationsDeclared == False`. The author declared no
  migrations at all. Migrate prints a soft "no migrations declared"
  note pointing at `seihou upgrade && seihou run`.

EP-28 splits the **partial chain** shape into two sub-cases based on
whether the *unreachable tail* itself declares any migrations:

- **Partial chain, exhausted tail** — `chainSteps` non-empty,
  `planUnreachable = Just (stuckAt, target)`, *no* declared migration
  has `from > stuckAt`. The author ran out of declared migrations.
  EP-28 makes this case bump the manifest all the way to `target`
  while still running the chain's prefix.
- **Partial chain, blocked tail** — `chainSteps` non-empty,
  `planUnreachable = Just (stuckAt, target)`, at least one declared
  migration has `from > stuckAt`. The author has plans in the
  unreachable region but the chain doesn't span the gap. EP-28 leaves
  this case at the EP-5 contract: apply the prefix, leave the
  manifest at `chainTo`, print the Blocked advisory.

The CLI dispatcher is in `seihou-cli/src/Seihou/CLI/Migrate.hs`. The
relevant function is `dispatchPlan`, which currently splits on
`planUnreachable` and `planMigrationsDeclared`. EP-28 adds a third
discriminator: the new planner field `planTailExhausted`.

The `MigrateResult` ADT is also in
`seihou-cli/src/Seihou/CLI/Migrate.hs`. EP-28 adds two new variants:

- `MigrateAppliedBumpedThrough ExecutedMigrationPlan Manifest Version Version`
  — partial chain applied AND manifest bumped past the exhausted
  tail. The two `Version`s are `(stuckAt, target)` so the renderer
  can print the bump-through trailer.
- `MigrateDryRunOKBumpedThrough ExecutedMigrationPlan Version Version`
  — same shape for the dry-run path.

These new variants do not replace `MigrateAppliedPartial` /
`MigrateDryRunOKPartial`. The old variants stay for the
blocked-tail case. After EP-28 the partial-chain space splits into
four CLI outcomes:

- Apply, exhausted tail → `MigrateAppliedBumpedThrough`.
- Apply, blocked tail → `MigrateAppliedPartial` (unchanged).
- Dry-run, exhausted tail → `MigrateDryRunOKBumpedThrough`.
- Dry-run, blocked tail → `MigrateDryRunOKPartial` (unchanged).

The `pendingChainFor` helper used by `seihou status`,
`seihou run`'s pre-flight, and `seihou upgrade
--with-migrations`'s post-advisory is also in
`seihou-cli/src/Seihou/CLI/Migrate.hs`. It returns the planner's
`MigrationPlan` directly. Consumers in
`seihou-cli/src/Seihou/CLI/PendingMigrations.hs` and the renderers in
`seihou-cli/src/Seihou/CLI/StatusRender.hs` /
`seihou-cli/src-exe/Seihou/CLI/Upgrade.hs` /
`seihou-cli/src-exe/Seihou/CLI/Run.hs` need to learn the new
discriminator and render appropriately.

The status display currently reads (live transcript from the user's
session):

      master-plan  v0.2.0    (applied 2026-04-15)
        Blocked: no migration declared from 0.2.0; remote is at 0.3.0. To proceed, run 'seihou migrate master-plan --bump-only' to acknowledge no migration is needed, or wait for the module author to ship one.

After EP-28 the equivalent state (manifest at `0.1.0`, exhausted
tail) would render:

      master-plan  v0.1.0    (applied 2026-04-15)
        Pending migration: 0.1.0 -> 0.2.0 (1 operation(s)). Run: seihou migrate master-plan
        Note: 0.2.0 -> 0.3.0 has no declared migration; would bump through.

…or similar wording (M3 nails the exact phrasing). The point is the
user reads the row and knows that one `seihou migrate master-plan`
invocation will land them at `0.3.0`, not at `0.2.0` with a follow-up
advisory.

Existing tests covering the partial-chain path:

- `seihou-core/test/Seihou/Core/MigrationSpec.hs` covers
  `planMigrationChain` directly.
- `seihou-cli/test/Seihou/CLI/MigrateSpec.hs` has the existing
  partial-chain tests (search for "applies the longest reachable
  prefix"). EP-27 added EP-27 M1/M2 probe blocks. EP-28 adds tests
  inside the same file.

The user's actual fixture (the one they ran in this session against
the seihou-project repo) is the canonical live test. EP-28's M4
re-verifies on a fresh equivalent.


## Plan of Work

The plan has four milestones, each independently verifiable.


### Milestone 1 — Plumb `planTailExhausted` through the planner

Goal: The planner exposes whether the unreachable tail's region has
any further declared migrations. Before this milestone, every CLI
consumer would have to compute the predicate locally.

In `seihou-core/src/Seihou/Core/Migration.hs`:

- Extend the `MigrationPlan` record with a new boolean field:

      data MigrationPlan = MigrationPlan
        { planChain :: MigrationChain
        , planUnreachable :: Maybe (Version, Version)
        , planMigrationsDeclared :: Bool
        , planTailExhausted :: Bool
        }
        deriving stock (Eq, Show, Generic)

- Update the haddock above `MigrationPlan` to describe the new
  field. The semantic rule:
  `planTailExhausted = not (any (\(_, fv, _) -> fv > stuckAt) parsedMigrations)`
  where `parsedMigrations` is the post-parse, sorted list and
  `stuckAt` is the chain's `chainTo`. When `planUnreachable ==
  Nothing` (full chain), the field is conventionally `True` (the
  tail is empty, trivially exhausted) but consumers should not rely
  on it for full chains.
- Update the planner's `Right (Just MigrationPlan {…})` construction
  to compute and set `planTailExhausted`. The walker already returns
  `(steps, reached, mTail)`; compute the new field from `parsed` and
  `reached`.

In `seihou-core/test/Seihou/Core/MigrationSpec.hs`:

- Add tests for the new field across the existing fixture matrix:
  - Full chain → `planTailExhausted = True`.
  - Partial with exhausted tail (the user's fixture: `[{0.1 →
    0.2}]`, target `0.3`) → `planTailExhausted = True`.
  - Partial with blocked tail (master-plan EP-5 fixture: `[{0.1 →
    0.2}, {0.5 → 0.6}]`, target `0.6`) → `planTailExhausted =
    False`.
  - Empty migrations (benign) → `planTailExhausted = True` (no
    migrations means no future migrations).
  - Single orphan edge `[{0.5 → 0.6}]` with manifest at `0.1`,
    target `0.6` (full block) → `planTailExhausted = False`.

Acceptance: `cabal test seihou-core:test:seihou-core-test` passes.
The new field is visible in the planner's output and tests pin its
value across the four shapes.


### Milestone 2 — Dispatch the exhausted-tail case in `seihou migrate`

Goal: `seihou migrate <module>` against a partial chain with an
exhausted tail applies the prefix *and* bumps the manifest to
target. One command, manifest at target.

In `seihou-cli/src/Seihou/CLI/Migrate.hs`:

- Add two new `MigrateResult` variants:

      | -- | A partial chain was applied (prefix only), and the
        -- unreachable tail was a benign version-only bump. The
        -- chain reaches @stuckAt@ via real migration ops; the
        -- manifest is then bumped from @stuckAt@ all the way to
        -- @target@ with no further ops. The two 'Version's are
        -- @(stuckAt, target)@. Distinct from
        -- 'MigrateAppliedPartial' (blocked tail, manifest stops at
        -- @stuckAt@) and from 'MigrateApplied' (full chain via
        -- declared ops).
        MigrateAppliedBumpedThrough ExecutedMigrationPlan Manifest Version Version
      | -- | Dry-run companion of 'MigrateAppliedBumpedThrough'.
        MigrateDryRunOKBumpedThrough ExecutedMigrationPlan Version Version

- Update `dispatchPlan`:

      | Just (stuck, target) <- plan.planUnreachable =
          if hasExplicitTo opts
            then pure (Left (MigratePlanFailed (MigrationGap stuck target)))
            else if plan.planTailExhausted
              then applyChainBumpThrough opts manifest plan.planChain stuck target
              else applyChain opts manifest plan.planChain (Just (stuck, target))

- Add `applyChainBumpThrough`: classify, optionally execute, then
  bump the manifest's `moduleVersion` field from `chainTo` (=
  `stuck`) to `target`. Reuses `replaceModuleVersion` (already
  defined for the `--bump-only` path).
- Update the renderer in `handleMigrate` to handle the new
  variants. The bumped-through apply prints:

      ✓ Migrated <module> <fromV> → <target>.
        <chainFrom> → <chainTo>: <N> step(s) applied.
        <stuck> → <target>: no migration declared; bumped through.

  The dry-run variant renders a similar trailer plus the
  `(dry run — no changes made)` line.
- Update JSON output: the bumped-through apply emits a JSON object
  similar to a partial-chain plan but with a `"bumpedThrough":
  true` flag and a `"manifestVersion": "<target>"` field so
  scripted consumers can tell apart "manifest at target" from
  "manifest at chainTo".

In `seihou-cli/test/Seihou/CLI/MigrateSpec.hs`:

- Add a new `describe` block "EP-28 bump-through" with at least
  these tests:
  - `MigrateAppliedBumpedThrough` is returned when the local
    installed copy declares `[{0.1 → 0.2}]` and target is `0.3`.
    Manifest lands at `0.3`. Disk reflects the chain's prefix ops.
  - `MigrateAppliedPartial` is still returned when the migrations
    list has a future edge in the unreachable region (master-plan
    EP-5 shape). Manifest stops at `chainTo`.
  - `MigrateDryRunOKBumpedThrough` returned for `--dry-run` over an
    exhausted-tail partial chain. Disk untouched.
  - `--to TARGET` over an exhausted-tail partial still errors with
    `MigratePlanFailed (MigrationGap …)` (strict-target contract
    preserved).
  - The fetch-path local-fallback from EP-27 now also auto-bumps
    when the local fallback's plan has an exhausted tail. (Pin the
    composition: EP-27's fallback + EP-28's bump-through chain
    cleanly.)

Acceptance: `cabal test seihou-cli:test:seihou-cli-test` passes.
The new tests fail on the M1-only branch and pass after M2's
dispatch + apply changes.


### Milestone 3 — Update pending-chain consumers (status, run, upgrade)

Goal: the user-visible advisories in `seihou status`,
`seihou run` (pre-flight refusal), and `seihou upgrade
--with-migrations` (post-advisory) reflect the new
"would bump through" semantics for exhausted-tail partial chains.

The change in each consumer is the same: when rendering a
`MigrationPlan` that is partial-with-exhausted-tail, replace the
"Note: no migration declared from X; remote is at Y." advisory with
"Note: X → Y has no declared migration; would bump through" (or
shape-equivalent wording per the renderer's existing style).

Files to touch:

- `seihou-cli/src/Seihou/CLI/StatusRender.hs` — the per-module
  pending row renderer. Add a new branch for partial-with-exhausted
  that prints the bump-through note.
- `seihou-cli/src/Seihou/CLI/PendingMigrations.hs` — the
  `formatRefusalMessage` helper used by `seihou run`'s pre-flight.
  Same branch addition.
- `seihou-cli/src-exe/Seihou/CLI/Upgrade.hs` — `printAdvisory` (the
  post-upgrade advisory). Same branch addition.
- `seihou-cli/src-exe/Seihou/CLI/Run.hs` — `applyOneMigration` (the
  in-band apply driven by `--with-migrations`). The dispatch gets
  the new bump-through outcome from `runMigrate`; render the new
  per-module status line.

Tests:

- `seihou-cli/test/Seihou/CLI/StatusRenderSpec.hs` — pin the new
  partial-with-exhausted row format.
- `seihou-cli/test/Seihou/CLI/PendingMigrationSpec.hs` — pin the
  formatRefusalMessage output and the predicates (a new
  `isBumpedThrough` helper alongside `isBenignUpgrade` and
  `isBlockedMigration`, so future renderers can ask the question
  cleanly).

Acceptance: `cabal test all` passes.


### Milestone 4 — Live verification + docs

Goal: confirm the user's exact scenario now produces a one-shot
upgrade, and document the new behaviour.

Live verification: rebuild the binary and run against a fresh
fixture mirroring the user's `master-plan 0.1 → 0.3` shape (the
session-original fixture is already at 0.3 because the user
applied the migration plus `--bump-only` mid-session, so the M4
re-runs against a synthetic equivalent at `/tmp/seihou-bump-through-repro/`).
Capture the transcript and paste it into Outcomes & Retrospective.

Docs:

- `docs/cli/migrate.md` — update the Partial chains subsection to
  describe the exhausted-tail bump-through behaviour. Add an
  example transcript.
- `docs/cli/status.md` — if the partial-with-exhausted advisory is
  shown anywhere in status examples, update.
- `docs/user/CHANGELOG.md` — add a 2026-04-28+ entry summarizing
  the change in one paragraph.

Acceptance:

- The live fixture runs `seihou migrate <module>` once and lands
  the manifest at `target`.
- `cabal test all` and `nix flake check` both pass.
- `git status` is clean.


## Concrete Steps

The build path is fixed across milestones:

    cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
    cabal build seihou-cli

The binary lands at:

    dist-newstyle/build/aarch64-osx/ghc-9.12.2/seihou-cli-0.1.0.0/x/seihou/build/seihou/seihou

(The `aarch64-osx` and GHC-version path components vary by platform;
substitute as needed. The user has noted no global binary is
installed, so `cabal run -- ` is the canonical invocation in this
working tree.)

To run the migrate-related tests:

    cabal --enable-tests test seihou-cli:test:seihou-cli-test \
      --test-show-details=streaming \
      --test-options='--pattern "/Seihou.CLI.Migrate/"'

To run the core planner tests:

    cabal --enable-tests test seihou-core:test:seihou-core-test \
      --test-show-details=streaming

To rebuild the bump-through live fixture from scratch:

    rm -rf /tmp/seihou-bump-through-repro
    mkdir -p /tmp/seihou-bump-through-repro/{installed,project/.seihou}

    # Installed copy: declares 0.3 with one 0.1 → 0.2 migration edge.
    # No 0.2 → 0.3 edge, no .seihou-origin.json (so the fetch path
    # falls back to local; that's enough for this test, which is
    # exercising EP-28's dispatch, not EP-27's fetch fallback).
    cat > /tmp/seihou-bump-through-repro/installed/module.dhall <<'DHALL'
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

    echo tracked > /tmp/seihou-bump-through-repro/project/old.txt
    HASH=$(printf 'tracked\n' | shasum -a 256 | awk '{print $1}')
    cat > /tmp/seihou-bump-through-repro/project/.seihou/manifest.json <<JSON
    { "version": 2
    , "generatedAt": "2026-04-01T10:00:00Z"
    , "modules": [{ "name": "demo"
                  , "source": "/tmp/seihou-bump-through-repro/installed"
                  , "version": "0.1"
                  , "appliedAt": "2026-04-01T10:00:00Z" }]
    , "variables": {}
    , "files": { "old.txt": { "hash": "$HASH"
                            , "module": "demo"
                            , "strategy": "template"
                            , "generatedAt": "2026-04-01T10:00:00Z" } }
    }
    JSON

After the M4 build, run from the project dir:

    cd /tmp/seihou-bump-through-repro/project
    "$SEIHOU" migrate demo

…and assert manifest moves to `0.3` in one shot.


## Validation and Acceptance

The plan is complete when:

1. `seihou-core/src/Seihou/Core/Migration.hs` exposes
   `planTailExhausted :: Bool` on `MigrationPlan`. Tests in
   `seihou-core/test/Seihou/Core/MigrationSpec.hs` pin its value
   across the four canonical shapes.
2. `seihou-cli/src/Seihou/CLI/Migrate.hs` dispatches partial chains
   with `planTailExhausted = True` to a new
   `MigrateAppliedBumpedThrough` (or dry-run sibling) outcome. The
   user-visible message says "Migrated <fromV> → <target>" with a
   per-segment trailer naming the chain's prefix and the
   bumped-through region.
3. `seihou status`, `seihou run`'s pre-flight refusal, and
   `seihou upgrade --with-migrations`'s post-advisory all describe
   exhausted-tail partial chains as "would migrate fully to
   <target>" rather than "Blocked at <chainTo>".
4. The full Cabal test suite and `nix flake check` both pass.
5. The live fixture at `/tmp/seihou-bump-through-repro/` produces
   a one-command transcript that lands the manifest at `0.3` and
   moves the tracked file accordingly.
6. `docs/cli/migrate.md`, `docs/user/CHANGELOG.md`, and any other
   touched docs reflect the new behaviour.

A reviewer reading the diff should be able to point at:

- Planner change (one new field, ~2 lines of construction logic).
- Migrate dispatch + new variants (one new branch in
  `dispatchPlan`, one new helper, two new ADT variants).
- Pending-display updates (one new branch per consumer).
- The new test blocks.
- The CHANGELOG entry.

…and nothing else.


## Idempotence and Recovery

Every step in this plan is safe to run repeatedly:

- The planner change is pure; no migrations or filesystem
  side-effects.
- `cabal build` and `cabal test` are idempotent.
- The live fixture lives entirely under `/tmp/seihou-bump-through-repro/`
  and can be rebuilt from the heredoc commands in Concrete Steps.
- The new regression tests use `withSystemTempDirectory` and clean
  up after themselves.

If a milestone's commit lands in a broken state, `git revert` the
commit and re-attempt from the previous known-good HEAD.

If `nix flake check` fails because of the CLI module-placement check
(`nix/check-cli-module-placement.sh`), the failing module is in the
wrong package layer per `CLAUDE.md`'s "CLI Module Placement
(library-first)" convention. EP-28 should not introduce any new
modules — every change is to an existing file — so module-placement
failures would indicate something accidentally moved.


## Interfaces and Dependencies

This plan changes the public type
`Seihou.Core.Migration.MigrationPlan` (one new field) and the public
type `Seihou.CLI.Migrate.MigrateResult` (two new variants).
Downstream consumers of those types must be updated:

- `Seihou.CLI.Migrate.dispatchPlan` (this plan).
- `Seihou.CLI.PendingMigrations.formatRefusalMessage`,
  `isBenignUpgrade`, `isBlockedMigration` (M3).
- `Seihou.CLI.StatusRender` (M3).
- `Seihou.CLI.Upgrade.printAdvisory`,
  `Seihou.CLI.Upgrade.runOnePostUpgradeMigration` (M3).
- `Seihou.CLI.Run.applyOneMigration` (M3).

These signatures stay identical:

- `Seihou.Core.Migration.planMigrationChain :: Text -> [Migration] ->
  Version -> Version -> Either MigrationPlanError (Maybe MigrationPlan)`
- `Seihou.CLI.Migrate.runMigrate :: MigrateOpts -> Manifest ->
  FilePath -> IO (Either MigrateError MigrateResult)`

Tests use the helpers already exported by
`seihou-cli/test/Seihou/CLI/MigrateSpec.hs`:

- `writeInstalledModule :: FilePath -> Text -> Text -> IO ()`
- `mkManifest :: Text -> FilePath -> [(FilePath, Text)] -> Manifest`
- `defaultOpts :: MigrateOpts`
- `withFetchFixture :: Text -> Text -> Text -> (FetchFixture -> IO ()) -> IO ()`
