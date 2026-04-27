# Distinguish benign version bumps from missing migrations

Intention: intention_01kq5pe8hhekrrb9wg4eb1jz74

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

After this change, `seihou status`, `seihou migrate`, and `seihou run`
will stop telling users "the module author must ship a migration"
when no migration is needed. A module that bumps its declared
`version` from `0.2.0` to `0.3.0` without changing any file paths
should not require any migration entry at all — the user should be
able to run `seihou upgrade <module>` followed by `seihou run` and
see their project re-rendered against the new template content.

Today the system conflates two real cases:

1. The author owes a migration but forgot to ship one. `seihou run`
   refusing to write the new template into the old layout is exactly
   right here — that was the EP-3 hazard.
2. The author bumped the version without needing a migration. The
   refusal is wrong: there is no destructive op to apply, and a
   normal `seihou upgrade && seihou run` is the correct path.

Both cases produce the same internal shape today (planner returns an
empty chain plus an unreachable tail) and the same user-facing
message ("Blocked: no migration declared from X; remote is at Y. The
module author must ship one before this project can move forward.").

After this change, the two cases are distinguishable and the
user-facing behavior matches:

- If the module's `migrations` field is the empty list, the version
  gap is treated as **benign**: status emits a softened advisory
  ("Pending: 0.2.0 → 0.3.0 (no migrations declared). Run: seihou
  upgrade <module> && seihou run."), `seihou migrate <module>` exits
  with the same advisory and a zero exit code, and `seihou run` does
  *not* refuse — it proceeds with the run plan, and the manifest
  catches up to the new version naturally because the run flow's
  `updateAllModules` already records `moduleVersion = m.version`.
- If the module's `migrations` field has at least one entry but no
  edge starts at the manifest version, the existing **blocked**
  semantics from EP-5 are preserved unchanged. The author started
  declaring migrations and the gap is a real omission, so refusing
  the run is still the correct default.
- Additionally, a new flag `seihou migrate <module> --bump-only`
  refreshes the manifest's recorded `moduleVersion` to match the
  installed copy's `module.dhall` version without running any
  migration ops. This is the manual escape hatch for users who want
  to acknowledge "I know the partial-chain unreachable tail is safe
  for my project; just update the bookkeeping." It is intentionally
  separate from `--no-fetch`, `--force`, and `--to TARGET`.

You can see the change working by running these commands from a
project with a synthetic empty-migrations module after this plan
ships. With manifest at `0.2.0`, installed cache at `0.3.0`, and
`module.migrations = []`:

    $ seihou status
    ...
      example  v0.2.0    (applied 2026-04-15)
        Pending: 0.2.0 -> 0.3.0 (no migrations declared). Run: seihou upgrade example && seihou run
    ...

    $ seihou migrate example
    Note: example has no migrations declared (0.2.0 -> 0.3.0). This is
    a benign version bump; run 'seihou upgrade example && seihou run'
    to refresh templates and bring the manifest up to date.
    [exit 0]

    $ seihou run example --dry-run
    [no refusal — the dry-run plan output appears]

And with manifest at `0.1.3`, installed at `0.3.0`, and
`module.migrations = [0.1.3 -> 0.2.0]` (the live `exec-plan` shape on
the seihou tree at the time of writing):

    $ seihou status
    ...
      exec-plan  v0.1.3    (applied 2026-04-15)
        Pending migration: 0.1.3 -> 0.2.0 (1 operation(s)). Run: seihou migrate exec-plan
        Note: no migration declared from 0.2.0; remote is at 0.3.0.
    ...

That existing partial-chain advisory from EP-5 is unchanged. Only
the empty-migrations case softens.


## Progress

- [x] M1 (2026-04-26): Pin today's behavior with regression tests in
      MigrationSpec, PendingMigrationSpec, MigrateSpec, StatusSpec.
      Four new tests (one per spec) explicitly capture the
      indistinguishability of empty-migrations + version-gap from
      `[orphanEdge]` + version-gap. All 966 tests green on HEAD before
      any code changes (was 962; +4 pins).
- [ ] Extend `MigrationPlan` in `seihou-core/src/Seihou/Core/Migration.hs`
      with a new `planMigrationsDeclared :: Bool` field that records
      whether the input list of migrations was non-empty. Update the
      planner and existing planner tests.
- [ ] Add a new outcome `MigrateBenignUpgrade Version Version` to
      `MigrateResult` in `seihou-cli/src/Seihou/CLI/Migrate.hs`. Update
      `dispatchPlan` to route the empty-migrations + version-gap case
      to this outcome when `--to` is not set. With `--to TARGET`,
      preserve the strict-target error so explicit targets keep
      contracting.
- [ ] Update `handleMigrate`'s renderer for the new outcome (softened
      advisory, exit zero) and the JSON path
      (`{ "module": ..., "benign": true, "from": ..., "to": ... }`).
- [ ] Update `pendingChainFor` in
      `seihou-cli/src/Seihou/CLI/Migrate.hs` so its return value
      preserves the `planMigrationsDeclared` bit, and update
      `Seihou.CLI.PendingMigrations.formatRefusalMessage` to render
      benign-upgrade entries with softened language.
- [ ] Update `Seihou.CLI.StatusRender` with a new
      `AdviceBenignUpgrade Text Version Version` variant; the
      Recommended actions tail should list `seihou upgrade <name> &&
      seihou run` for benign entries (not `[blocked]`, since this is
      not a real block).
- [ ] Update `seihou-cli/src-exe/Seihou/CLI/Run.hs`'s
      `handlePendingMigrations` so benign entries do *not* trigger a
      refusal. The default path should silently proceed with the run
      plan and let `updateAllModules` bump the manifest naturally.
      `--with-migrations` should treat benign entries as a no-op (no
      `runMigrate` invocation) and continue.
- [ ] Update `seihou-cli/src-exe/Seihou/CLI/Upgrade.hs`'s
      `printAdvisory` for the benign case (show "no migrations
      declared; run 'seihou upgrade && seihou run'" rather than the
      EP-5 blocked message).
- [ ] Add a `migrateBumpOnly :: Bool` field to `MigrateOpts` in
      `seihou-cli/src/Seihou/CLI/Migrate.hs`. When set, `runMigrate`
      bypasses the planner entirely: it reads the installed copy's
      version, writes that as the manifest's `moduleVersion`, and
      exits with a `MigrateApplied` outcome carrying an empty
      executed plan. Wire the flag into the option parser at
      `seihou-cli/src-exe/Seihou/CLI/Commands.hs`.
- [ ] Update `docs/cli/migrate.md`, `docs/cli/status.md`,
      `docs/cli/run.md`, and `docs/user/CHANGELOG.md` to describe the
      new behavior.
- [ ] End-to-end demonstration: create a synthetic empty-migrations
      fixture (a temp project with a manifest pointing at an
      `installed/example/module.dhall` declaring `migrations = []` at
      `0.3.0` and a manifest entry at `0.2.0`). Run the four commands
      shown in Purpose / Big Picture and capture the actual output in
      Surprises & Discoveries. Run `seihou migrate <module>
      --bump-only` against the live `seihou-project` tree to verify
      the partial-chain escape hatch works for `master-plan` and
      `exec-plan`.
- [ ] Run `cabal test all` and `nix flake check` and confirm both are
      green.


## Surprises & Discoveries

(None yet — populated during implementation.)

Carry-overs from the parent EP-5 plan
(`docs/plans/23-bulletproof-partial-migration-chains.md`) that this
plan refines:

- EP-5 introduced `MigrateBlocked` with the message "no migration
  declared from X; remote is at Y. The module author must ship one
  before this project can move forward." This plan keeps that
  message for the case where migrations are declared but don't reach
  the manifest version. This plan only softens the message for the
  empty-migrations case.
- EP-5's pre-flight refusal in `seihou run` was deliberate: writing
  the new template state into the old layout is the exact hazard
  EP-3 was meant to block. That hazard does not exist when no file
  paths are changing. This plan preserves the refusal for
  partial/blocked-with-declared-migrations, only relaxes the
  empty-migrations case.
- EP-5's "Lessons captured" in the parent masterplan
  (`docs/masterplans/1-migrations-dx.md`) called out that "live-tree
  fixtures decay." This plan reaffirms the lesson: the
  empty-migrations case has no live-tree fixture, so synthetic test
  fixtures carry the verification weight.


## Decision Log

- Decision: Detect "no migrations declared" by extending
  `MigrationPlan` with a new `planMigrationsDeclared :: Bool` field
  rather than checking the `Module`'s `migrations` field at every
  consumer site.
  Rationale: The planner already has the input list and can record
  the bit once. Threading it through `MigrationPlan` means every
  consumer (status, migrate, run, upgrade) gets the signal for free
  and the rule "consumers distinguish full / partial / blocked /
  benign" stays inside the data type rather than spreading across
  six call sites. Alternative considered: add a second pattern-style
  variant (e.g. `data MigrationPlan = … | BenignVersionGap Version
  Version`). Rejected because that doubles the surface for partial
  cases (full / partial / blocked / benign-empty-edges-with-gap is
  not a sensible product) and breaks the "every divergence has a
  planChain even if empty" invariant EP-5 relied on.
  Date: 2026-04-26.

- Decision: Treat the empty-migrations case as benign (no refusal)
  rather than introducing a new "informational" advisory level above
  refusal but below silent.
  Rationale: There is no plausible hazard when the author has
  explicitly declared no migration system. `seihou run` already
  records `moduleVersion = m.version` for every applied module
  during normal operation, so the manifest catches up with no extra
  step. Treating this as anything stronger than a one-line note
  introduces friction that does not match the user's mental model
  ("the upgrade is just template content").
  Date: 2026-04-26.

- Decision: Keep `--to TARGET` strict for the benign case too. If a
  user passes `seihou migrate <module> --to 0.3.0` against a benign
  empty-migrations module, the command errors with the existing
  `MigrationGap` semantics rather than silently no-opping.
  Rationale: `--to TARGET` is a contract: "I want this exact
  version." For an empty-migrations module the planner cannot
  *prove* that nothing destructive is happening (there is no edge to
  inspect), only that nothing was declared. Honoring the contract
  by erroring keeps the strict-target promise consistent with EP-5
  and gives users the explicit `--bump-only` path when they want to
  bypass it.
  Date: 2026-04-26.

- Decision: Add `--bump-only` as a separate flag rather than a
  variant of `--to TARGET` (e.g. `--to TARGET --no-ops`).
  Rationale: `--bump-only` always targets "whatever the installed
  copy declares" — it is not a per-version operation. Mixing it
  with `--to` would create combinations whose semantics are unclear
  ("does `--to 0.2.0 --bump-only` bump to 0.2.0 or to 0.3.0?"). A
  flag with a single, clear meaning is easier to teach.
  Date: 2026-04-26.

- Decision: `--bump-only` writes `moduleVersion =
  installed.version` even if the installed copy declares no version.
  In that case the flag is a no-op (no new version to write).
  Rationale: Keeps the flag's behavior idempotent and predictable.
  An installed copy without a version field is rare; when it
  happens, the flag does nothing rather than failing.
  Date: 2026-04-26.


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

The Seihou CLI is a multi-package Haskell workspace built with
Cabal and Nix. The two packages relevant here are `seihou-core` (the
pure migration planner and the core types `Manifest`,
`AppliedModule`, `Module`, `Migration`, `Version`) and `seihou-cli`
(split into a library at `seihou-cli/src/` and an executable at
`seihou-cli/src-exe/`).

A "module" in Seihou is a directory containing a `module.dhall` file
that declares variables, generation steps, and optional migrations.
The `module.dhall` schema is defined in the external repo
`shinzui/seihou-schema`; for this plan you only need the Haskell
shapes, which are at
`seihou-core/src/Seihou/Core/Types.hs` (`Module` record) and
`seihou-core/src/Seihou/Core/Migration.hs` (`Migration`,
`MigrationOp`, `MigrationChain`, `MigrationPlan`,
`MigrationPlanError`).

A "manifest" is the file `.seihou/manifest.json` written into the
project root by `seihou run`. It records every applied module, its
recorded version (the `moduleVersion` field on `AppliedModule`),
and every file that was generated. The manifest's recorded version
is what the migration planner compares against the installed copy's
declared version.

Key files this plan touches, with one-sentence orientation each:

- `seihou-core/src/Seihou/Core/Migration.hs` — pure migration
  planner. Defines `MigrationChain`, `MigrationPlan`,
  `MigrationPlanError`, and the function `planMigrationChain` that
  walks declared migrations from `installed` to `target`. After
  EP-5, the planner returns a `MigrationPlan` carrying the longest
  reachable prefix plus an optional unreachable tail. This plan
  adds a `planMigrationsDeclared :: Bool` field to that record.
- `seihou-cli/src/Seihou/CLI/Migrate.hs` — the migrate command's
  IO shell, the planner-call dispatch (`dispatchPlan`,
  `applyChain`), the `MigrateOpts` record, the `MigrateResult`
  variant set, the user-facing renderer, and the `pendingChainFor`
  helper that status and run consume.
- `seihou-cli/src/Seihou/CLI/PendingMigrations.hs` — the shared
  detector `detectPendingMigrations` and the run-time refusal
  message helper `formatRefusalMessage`.
- `seihou-cli/src/Seihou/CLI/StatusRender.hs` — the pure status
  renderer. Defines `ModuleAdvice` variants and `formatStatus`
  (called by `seihou-cli/src-exe/Seihou/CLI/Status.hs`).
- `seihou-cli/src-exe/Seihou/CLI/Run.hs` — the `seihou run` IO
  shell. Calls `detectPendingMigrations` and dispatches via
  `handlePendingMigrations`.
- `seihou-cli/src-exe/Seihou/CLI/Upgrade.hs` — the `seihou upgrade`
  IO shell. Calls `pendingChainFor` to print a one-line advisory
  after a successful upgrade.
- `seihou-cli/src-exe/Seihou/CLI/Commands.hs` — the
  `optparse-applicative` definitions. Each command has a `*Opts`
  record and a parser builder; new flags go in this file.

After EP-5 (`docs/plans/23-bulletproof-partial-migration-chains.md`,
checked into the repo), the relevant types are:

    -- in seihou-core/src/Seihou/Core/Migration.hs
    data MigrationChain = MigrationChain
      { migrationModule :: Text
      , chainFrom :: Version
      , chainTo :: Version
      , chainSteps :: [Migration]
      }

    data MigrationPlan = MigrationPlan
      { planChain :: MigrationChain
      , planUnreachable :: Maybe (Version, Version)
      }

    planMigrationChain ::
      Text ->
      [Migration] ->
      Version ->
      Version ->
      Either MigrationPlanError (Maybe MigrationPlan)

    -- in seihou-cli/src/Seihou/CLI/Migrate.hs
    data MigrateResult
      = MigrateNoOp Version
      | MigrateDryRunOK ExecutedMigrationPlan
      | MigrateDryRunOKPartial ExecutedMigrationPlan Version Version
      | MigrateApplied ExecutedMigrationPlan Manifest
      | MigrateAppliedPartial ExecutedMigrationPlan Manifest Version Version
      | MigrateBlocked Version Version

    data MigrateOpts = MigrateOpts
      { migrateModule :: ModuleName
      , migrateTo :: Maybe Text
      , migrateDryRun :: Bool
      , migrateForce :: Bool
      , migrateJson :: Bool
      , migrateVerbose :: Bool
      , migrateNoFetch :: Bool
      }

    pendingChainFor :: AppliedModule -> Module -> Maybe MigrationPlan

    -- in seihou-cli/src/Seihou/CLI/StatusRender.hs
    data ModuleAdvice
      = AdviceNone
      | AdviceUpgradeOnly Text
      | AdvicePendingMigration Text MigrationChain
      | AdvicePartialMigration Text MigrationPlan
      | AdviceBlockedMigration Text Version Version

This plan adds a `planMigrationsDeclared` field to `MigrationPlan`,
a `MigrateBenignUpgrade Version Version` variant to `MigrateResult`,
a `migrateBumpOnly :: Bool` field to `MigrateOpts`, and an
`AdviceBenignUpgrade Text Version Version` variant to `ModuleAdvice`.
Existing variants stay; the new shapes route through dedicated
branches.

The build is a Nix flake. From the repo root:

    cabal build all                                     # full build
    cabal test all --enable-tests                       # full tests
    cabal test seihou-core --enable-tests               # planner only
    cabal test seihou-cli --enable-tests                # CLI only
    cabal test seihou-cli --enable-tests \\
      --test-options="--pattern Migrate"                # one spec
    nix flake check                                     # CI parity
    cabal run seihou -- status                          # invoke status
    cabal run seihou -- migrate <name> --dry-run        # invoke migrate

Use `cabal run seihou --` while iterating; the system `seihou`
binary in `$PATH` is stale until a new release ships.

The pre-commit hook runs `treefmt` and the CLI library-first
placement check; both are green on `master` as of the EP-5 ship.
Library-first means new helper code defaults to `seihou-cli/src/`
(the library) unless it transitively imports
`Options.Applicative`, `Data.FileEmbed`, `GitHash`, or
`Paths_seihou_cli`. The dispatch in `handleMigrate`, `handleRun`,
and option parsers stays executable-side; the new `MigrateResult`
variant, `--bump-only` runtime logic, and renderer helpers go in
the library.

Test fixtures use `withSystemTempDirectory` to avoid touching the
user's `~/.config/seihou`. The `MigrateSpec` fetch-path tests use
local git repos as fake remotes; the empty-migrations case in this
plan does not need the fetch path (it can use the existing
`writeInstalledModule` helper that takes a Dhall literal for the
migrations field).


## Plan of Work


### Milestone 1 — Pin current behavior with regression tests


Before any code changes, write tests that lock down today's
"benign treated as blocked" behavior so the fix in later milestones
is visibly intentional and the regression cannot silently regrow.

In `seihou-core/test/Seihou/Core/MigrationSpec.hs`, the EP-5 case
"returns a blocked plan (empty chain + unreachable tail) when no edge
starts at installed" already covers the empty-migrations case at the
planner level. Add a more explicit pinning test that asserts the
planner returns the same shape regardless of whether the migrations
list is `[]` (genuinely empty) or `[someEdge]` where the edge
doesn't start at `installed`. The point is that *today* the planner
output cannot distinguish them. After Milestone 2 the assertions
change.

In `seihou-cli/test/Seihou/CLI/PendingMigrationSpec.hs`, add a case
that pins today's behavior: an applied module with manifest `0.2.0`,
installed `0.3.0`, and `migrations = []` produces a `MigrationPlan`
with empty chain steps and `planUnreachable = Just (0.2.0, 0.3.0)` —
indistinguishable from the `[someEdge]`-but-can't-reach case.

In `seihou-cli/test/Seihou/CLI/MigrateSpec.hs`, add a case that
pins `runMigrate` returning `MigrateBlocked` for the
empty-migrations + version-gap fixture.

In `seihou-cli/test/Seihou/CLI/StatusSpec.hs`, add a case that pins
the existing `Blocked: …` message for the empty-migrations module.

Run the tests and confirm they pass on `HEAD`. Commit with `test:
pin today's blocked behavior for empty-migrations modules`. The
acceptance for this milestone is that the new tests are green on
`HEAD` *before* any code change.


### Milestone 2 — Extend the planner contract with `planMigrationsDeclared`


In `seihou-core/src/Seihou/Core/Migration.hs`, add a new field to
`MigrationPlan`:

    data MigrationPlan = MigrationPlan
      { planChain :: MigrationChain
      , planUnreachable :: Maybe (Version, Version)
      , planMigrationsDeclared :: Bool
      }

Update the Haddock comment on `MigrationPlan` to describe the new
field: "True when the input migrations list was non-empty, False
when the module declared `migrations = []`. Consumers use this to
distinguish a benign version bump (no migrations declared, version
field changed) from a blocked migration (migrations declared but
none reach the installed version)."

Update `planMigrationChain` to compute the new field. The simplest
implementation is to set
`planMigrationsDeclared = not (null migrations)` at the single
construction site.

Update every existing planner test in
`seihou-core/test/Seihou/Core/MigrationSpec.hs` to assert the new
field's value. The new pinning tests from Milestone 1 flip their
assertions: the empty-migrations case now expects
`planMigrationsDeclared = False`, the partial-with-declared case
expects `planMigrationsDeclared = True`. All other tests get a
trivial wrapper update to set the field on their expected values.

Run `cabal test seihou-core --enable-tests` and confirm all tests
pass. Commit with `feat(migration): record planMigrationsDeclared
to distinguish benign gaps from missing edges`.

Acceptance: `cabal test seihou-core` is green; the new field is
populated correctly for empty, partial, and full cases.


### Milestone 3 — Surface the new shape in `MigrateResult` and `pendingChainFor`


In `seihou-cli/src/Seihou/CLI/Migrate.hs`, add a new variant to
`MigrateResult`:

    | -- | The module's manifest version trails its installed
      -- copy's version, but the module declares no migrations at
      -- all (migrations = []). The two 'Version's are
      -- @(manifest, target)@. The renderer prints a softened
      -- advisory pointing at "seihou upgrade && seihou run"; the
      -- exit code is zero (no work was done; no manifest change).
      -- Distinct from 'MigrateBlocked' (migrations declared but
      -- none reach the manifest version, which is a real block).
      MigrateBenignUpgrade Version Version

Update `dispatchPlan` to route the empty-migrations case to this
new variant. The relevant block is the `null plan.planChain.chainSteps`
branch:

    dispatchPlan opts manifest plan
      | null plan.planChain.chainSteps = case plan.planUnreachable of
          Just (stuck, target)
            | not plan.planMigrationsDeclared,
              not (hasExplicitTo opts) ->
                pure (Right (MigrateBenignUpgrade stuck target))
            | hasExplicitTo opts ->
                pure (Left (MigratePlanFailed (MigrationGap stuck target)))
            | otherwise ->
                pure (Right (MigrateBlocked stuck target))
          Nothing ->
            pure (Right (MigrateNoOp plan.planChain.chainTo))
      …

(The full path-rest matches the EP-5 dispatch unchanged.) The
ordering matters: the strict-target check stays the same as EP-5,
and the new "benign" branch only fires when the module declared no
migrations *and* the user didn't request a specific target.

Update `handleMigrate` to render the new variant. Human path:

    Right (MigrateBenignUpgrade from to) -> do
      let msg =
            modName.unModuleName
              <> " has no migrations declared ("
              <> renderVersion from
              <> " -> "
              <> renderVersion to
              <> "). This is a benign version bump; run 'seihou upgrade "
              <> modName.unModuleName
              <> " && seihou run' to refresh templates and bring the manifest up to date."
      TIO.putStrLn $ applyColor colorEnabled yellow ("Note: " <> msg)
      exitSuccess

JSON path:

    if opts.migrateJson
      then
        LBS.putStr
          ( encodePretty
              ( object
                  [ "module" .= modName.unModuleName
                  , "benign" .= True
                  , "from" .= renderVersion from
                  , "to" .= renderVersion to
                  ]
              )
          )

Update `pendingChainFor` — its existing return type
(`Maybe MigrationPlan`) is fine, since `MigrationPlan` now carries
`planMigrationsDeclared`. Consumers downstream get the bit for free.

In `seihou-cli/src/Seihou/CLI/PendingMigrations.hs`, update
`formatRefusalMessage`'s blocked branch to distinguish:

    renderEntry (name, plan)
      | null plan.planChain.chainSteps,
        not plan.planMigrationsDeclared,
        Just (_stuck, target) <- plan.planUnreachable =
          "  "
            <> name.unModuleName
            <> ": "
            <> renderVersion plan.planChain.chainFrom
            <> " -> "
            <> renderVersion target
            <> " (no migrations declared; benign — would not block run)"
      | null plan.planChain.chainSteps,
        Just (stuck, target) <- plan.planUnreachable =
          -- existing EP-5 blocked branch
          …

(Note: this branch never actually appears in `formatRefusalMessage`'s
output after Milestone 5, because Milestone 5 strips benign entries
from the input list. Keeping the rendering correct here is defensive
in case a future caller passes benign entries.)

Update `seihou-cli/test/Seihou/CLI/MigrateSpec.hs` to flip the
empty-migrations test from expecting `MigrateBlocked` to
`MigrateBenignUpgrade`. Update
`seihou-cli/test/Seihou/CLI/PendingMigrationSpec.hs` to add a
benign case that asserts `planMigrationsDeclared = False`.

Run `cabal test seihou-cli --enable-tests` and confirm all tests
pass. Commit with `feat(migrate): add MigrateBenignUpgrade for
empty-migrations version gaps`.

Acceptance: `cabal test seihou-cli` is green; manual run on a
synthetic empty-migrations fixture shows the softened message.


### Milestone 4 — Status renderer surfaces the benign case


In `seihou-cli/src/Seihou/CLI/StatusRender.hs`, add a new variant
to `ModuleAdvice`:

    | -- | The module's manifest version trails its installed copy's
      -- version, but the module declares no migrations at all. This
      -- is a benign version bump: the renderer prints a softened
      -- advisory pointing at "seihou upgrade <name> && seihou run".
      -- The Recommended actions tail lists the upgrade + run pair
      -- (not [blocked], because nothing is actually blocking).
      AdviceBenignUpgrade Text Version Version

Update `moduleAdvice` to map the new shape. The existing dispatch:

    case mPlan of
      Just plan
        | null plan.planChain.chainSteps,
          not plan.planMigrationsDeclared,
          Just (stuck, target) <- plan.planUnreachable ->
            AdviceBenignUpgrade am.name.unModuleName stuck target
        | null plan.planChain.chainSteps,
          Just (stuck, target) <- plan.planUnreachable ->
            AdviceBlockedMigration am.name.unModuleName stuck target
        | not (null plan.planChain.chainSteps),
          Just _ <- plan.planUnreachable ->
            AdvicePartialMigration am.name.unModuleName plan
        | not (null plan.planChain.chainSteps) ->
            AdvicePendingMigration am.name.unModuleName plan.planChain
      _ -> case mStatus of
        Just OutdatedSt -> AdviceUpgradeOnly am.name.unModuleName
        _ -> AdviceNone

Update `formatAdvice`:

    formatAdvice color (AdviceBenignUpgrade name from to) =
      [ "    "
          <> applyColor color yellow
            ( "Pending: "
                <> renderVersion from
                <> " -> "
                <> renderVersion to
                <> " (no migrations declared). Run: seihou upgrade "
                <> name
                <> " && seihou run"
            )
      ]

Update `adviceCommand`:

    adviceCommand (AdviceBenignUpgrade name _ _) =
      Just ("seihou upgrade " <> name <> " && seihou run")

Update `seihou-cli/test/Seihou/CLI/StatusSpec.hs` to add a benign
case mirroring the EP-5 partial / blocked cases. The fixture is a
manifest at `0.2.0`, a `MigrationPlan` with empty chain,
`planMigrationsDeclared = False`, and unreachable tail
`(0.2.0, 0.3.0)`. The expected output contains
"Pending: 0.2.0 -> 0.3.0 (no migrations declared)" and a
Recommended actions line "  seihou upgrade demo && seihou run".

Run `cabal test seihou-cli --enable-tests --test-options="--pattern Status"`.
Commit with `feat(status): render benign version bumps without the
blocked language`.

Acceptance: status spec is green; manual run against a synthetic
empty-migrations fixture shows the softened row.


### Milestone 5 — Run pre-flight stops refusing benign upgrades


In `seihou-cli/src-exe/Seihou/CLI/Run.hs`, update
`handlePendingMigrations` and `applyOneMigration` so benign entries
do not trigger a refusal.

The simplest factoring is to partition `pendings` upfront:

    handlePendingMigrations level runOpts manifestPath manifest pendings = do
      let (benign, blocking) = partitionBenign pendings
      mapM_ (logBenign level) benign
      handleBlocking level runOpts manifestPath manifest blocking

    partitionBenign ::
      [(ModuleName, MigrationPlan)] ->
      ([(ModuleName, MigrationPlan)], [(ModuleName, MigrationPlan)])
    partitionBenign = partition isBenign
      where
        isBenign (_, plan) =
          null plan.planChain.chainSteps
            && not plan.planMigrationsDeclared

    logBenign :: LogLevel -> (ModuleName, MigrationPlan) -> IO ()
    logBenign level (name, plan)
      | Just (from, to) <- plan.planUnreachable =
          logIO level $
            logInfo $
              "  Note: "
                <> name.unModuleName
                <> " has no migrations declared ("
                <> renderVersion from
                <> " -> "
                <> renderVersion to
                <> "); will refresh templates and bump manifest during this run."
      | otherwise = pure ()

    -- handleBlocking is the existing handlePendingMigrations body,
    -- iterating only over the blocking entries.

The dry-run + `--with-migrations` summary stays unchanged for
blocking entries; benign entries are excluded from the summary list
because they don't represent migrations to be applied.

`applyOneMigration`'s blocked branch (which handles
`null planChain.chainSteps && Just unreachable`) is unreachable for
benign entries because `partitionBenign` filters them out before the
fold. No change needed there. Add a comment noting the invariant.

Add a test fixture in `seihou-cli/test/Seihou/CLI/PendingMigrationSpec.hs`
or a new `Seihou.CLI.RunMigrationSpec` if the existing spec gets
crowded: a `partitionBenign` test that asserts a manifest with one
benign entry and one partial entry partitions to
`([benign], [partial])`. Since `partitionBenign` lives in the
executable target, expose it via the library if the test cannot
reach `Run.hs` directly. The simplest move is to add a tiny library
module `Seihou.CLI.PendingMigrations` helper:

    -- in seihou-cli/src/Seihou/CLI/PendingMigrations.hs
    isBenignUpgrade :: MigrationPlan -> Bool
    isBenignUpgrade plan =
      null plan.planChain.chainSteps
        && not plan.planMigrationsDeclared

…and have `Run.hs` consume it. Then test against `isBenignUpgrade`
directly.

Run `cabal test seihou-cli --enable-tests`. Commit with `feat(run):
proceed silently for benign empty-migrations upgrades`.

Acceptance: a synthetic empty-migrations fixture allows
`seihou run` to proceed without `--with-migrations` and the
manifest catches up via the existing `updateAllModules` path.


### Milestone 6 — Add `seihou migrate <module> --bump-only`


In `seihou-cli/src/Seihou/CLI/Migrate.hs`, add a new field to
`MigrateOpts`:

    , -- | Skip planning entirely. Read the installed copy's
      -- declared version and write it as the manifest's recorded
      -- version, exiting with a no-op-style outcome. Independent
      -- of @--no-fetch@: when both are set, no fetch happens *and*
      -- no planning happens. When @--bump-only@ is set,
      -- @--to TARGET@ is rejected with a clear error (the two flags
      -- are contradictory: @--bump-only@ targets the installed copy
      -- unconditionally).
      migrateBumpOnly :: Bool

Update `runMigrate` (the dispatcher between fetch and local paths)
to short-circuit the `migrateBumpOnly` case before calling
`runMigrateLocal` or `runMigrateWithFetch`. The simplest path: when
`migrateBumpOnly` is set, fetch the installed copy via the existing
fetch path (so the installed version we record is the *remote*'s,
not a stale local copy), evaluate its `module.dhall`, write the
version into the manifest, and return `MigrateApplied` with an empty
executed plan. When `migrateNoFetch` is also set, skip the fetch and
read the local installed copy directly.

A reasonable implementation sketch:

    runMigrate opts manifest installedDir
      | opts.migrateBumpOnly = runBumpOnly opts manifest installedDir
      | opts.migrateNoFetch  = runMigrateLocal opts manifest installedDir
      | otherwise            = runMigrateWithFetch opts manifest installedDir

    runBumpOnly :: MigrateOpts -> Manifest -> FilePath -> IO (Either MigrateError MigrateResult)
    runBumpOnly opts manifest installedDir
      | isJust opts.migrateTo =
          pure (Left (MigrateConflictingFlags "--bump-only and --to are mutually exclusive"))
      | otherwise = do
          -- Fetch first unless --no-fetch (so we bump to the latest
          -- remote, not a possibly stale local cache).
          ... evaluate installed (or remote) module.dhall ...
          ... write manifest with moduleVersion = installedVersion ...
          pure (Right (MigrateApplied emptyExecutedPlan postManifest))

`MigrateConflictingFlags` is a new variant of `MigrateError`. The
error message reads "--bump-only and --to are mutually exclusive;
--bump-only always targets the installed copy's declared version."

For the empty executed plan: build a minimal `ExecutedMigrationPlan`
with `planChain = MigrationChain { migrationModule = ..., chainFrom
= installed, chainTo = installed, chainSteps = [] }` and
`planOps = []`. The renderer should treat this as "nothing to
print" since there are no steps.

Update `handleMigrate`'s `MigrateApplied` branch to detect the
empty-plan case and print a different message:

    Right (MigrateApplied plan manifest')
      | null plan.planChain.chainSteps -> do
          -- bump-only path
          let toV = … installed version we just wrote …
          runEff $ runFilesystem $ runManifestStore manifestPath $ writeManifest manifest'
          unless opts.migrateJson $
            TIO.putStrLn $
              applyColor colorEnabled green "✓"
                <> " Bumped "
                <> applyColor colorEnabled bold modName.unModuleName
                <> " to "
                <> renderVersion toV
                <> " (no migration ops)."
      | otherwise -> -- existing chain-applied rendering

Wire `--bump-only` into the option parser at
`seihou-cli/src-exe/Seihou/CLI/Commands.hs`. The flag joins the
existing `--no-fetch`, `--force`, `--dry-run`, `--json` flags on
the migrate subcommand.

Add tests in `seihou-cli/test/Seihou/CLI/MigrateSpec.hs`:

1. `--bump-only` with manifest at `0.1.0` and installed at `0.3.0`
   refreshes the manifest to `0.3.0` without running ops.
2. `--bump-only --to 0.2.0` errors with `MigrateConflictingFlags`.
3. `--bump-only` is idempotent: running it twice in a row, the
   second invocation also sets manifest to the installed version
   (no error).
4. `--bump-only` against a partial-chain fixture (master-plan
   shape) bumps to the installed version (`0.3.0`), bypassing the
   declared `0.1.0 -> 0.2.0` migration entirely. This is the
   "manual escape hatch" use case — verify it works as documented.

Run `cabal test seihou-cli --enable-tests`. Commit with `feat(migrate):
add --bump-only for manual manifest version refresh`.

Acceptance: the four tests pass; manual run on a partial-chain
fixture using `cabal run seihou -- migrate <name> --bump-only`
catches the manifest up to the installed version.


### Milestone 7 — Documentation, end-to-end demo, changelog


Update the per-command docs to describe the new behavior.

`docs/cli/migrate.md` — Add a paragraph under "Partial chains and
blocked modules" titled "No migrations declared" that describes the
benign case: when the module's `migrations` field is `[]` and the
manifest version is older than the installed copy, the command
prints a softened advisory and exits zero. Add a paragraph
describing `--bump-only`: its purpose, its interaction with
`--to TARGET` (mutually exclusive), and the partial-chain escape
hatch use case.

`docs/cli/status.md` — Add a fourth row shape under "Pending
migrations" labelled "No migrations declared" with a rendered
example. Update the example output at the bottom to include a
benign row.

`docs/cli/run.md` — Update "Migration awareness" to note that benign
empty-migrations gaps do not trigger the refusal; only declared but
missing migrations do.

`docs/user/CHANGELOG.md` — Add a new dated entry summarizing the
user-visible changes: status's softened "Pending: …" row for
empty-migrations modules, migrate's softened "Note: …" message,
run no longer refusing for benign upgrades, and the new
`--bump-only` flag.

Run the live-tree demo. Create a synthetic empty-migrations fixture
(a temp project; do not modify the live `seihou-project` manifest
unless the user asks) and capture the actual output. Run
`seihou migrate master-plan --bump-only` and `seihou migrate
exec-plan --bump-only` against the live tree to verify the escape
hatch works on real partial-chain modules. Capture the output in
the Surprises & Discoveries section.

Run `nix flake check` and confirm green.

Commit with `docs(migrate,status,run): document benign upgrades and
--bump-only`.

Acceptance: every command in the demo produces the expected output;
`nix flake check` passes.


## Concrete Steps


To start a fresh implementation session, run from
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`:

    git status                    # confirm clean working tree
    git log -1 --format='%h %s'   # confirm HEAD is at the EP-5 ship
    cabal build all               # confirm the tree builds
    cabal test all --enable-tests # confirm all tests are green

Expected: `master` is at the EP-5 closing commit ("docs: document
partial-chain handling"), build succeeds, 962 tests pass (795 in
seihou-core, 167 in seihou-cli at EP-5 close — counts go up as M1's
pinning tests land).

Each milestone ends with a commit. Before committing, run:

    cabal test all --enable-tests

…and confirm green. The pre-commit hook will run `treefmt` and the
CLI library-first placement check; both should pass.

For the final live demo (Milestone 7), the synthetic empty-migrations
fixture is a temp directory layout:

    mkdir -p /tmp/seihou-benign-demo/example
    cat > /tmp/seihou-benign-demo/example/module.dhall <<'EOF'
    -- minimal module.dhall with version=Some "0.3.0" and migrations = []
    -- (use the same shape as test fixtures in MigrateSpec.hs)
    EOF
    mkdir -p /tmp/seihou-benign-demo/proj/.seihou
    cat > /tmp/seihou-benign-demo/proj/.seihou/manifest.json <<'EOF'
    -- manifest with one module entry: name="example",
    -- moduleVersion=Just "0.2.0", source=/tmp/seihou-benign-demo/example
    EOF

    cd /tmp/seihou-benign-demo/proj
    cabal run --project-dir /Users/shinzui/Keikaku/bokuno/seihou-project/seihou \\
              seihou -- status
    cabal run --project-dir /Users/shinzui/Keikaku/bokuno/seihou-project/seihou \\
              seihou -- migrate example
    cabal run --project-dir /Users/shinzui/Keikaku/bokuno/seihou-project/seihou \\
              seihou -- run example --dry-run

The exact shape of `module.dhall` and `manifest.json` is what the
existing test fixtures produce; copy from
`seihou-cli/test/Seihou/CLI/MigrateSpec.hs`'s `writeInstalledModule`
helper for the Dhall body and from `Seihou.Manifest.Types` for the
manifest layout.


## Validation and Acceptance


The change is complete when all of the following are true.

`cabal test all --enable-tests` is green, including these new
behaviors verified by tests:

- The planner returns `planMigrationsDeclared = False` when the
  input migrations list is empty, and `True` otherwise.
- `runMigrate` returns `MigrateBenignUpgrade from to` when the
  installed module declares no migrations and the manifest version
  trails the installed version (no `--to` flag).
- `runMigrate` returns `MigrateApplied` with an empty executed plan
  when `--bump-only` is set, regardless of whether migrations are
  declared.
- `runMigrate` returns `MigrateConflictingFlags` when both
  `--bump-only` and `--to TARGET` are set.
- `formatStatus` emits a "Pending: 0.2.0 -> 0.3.0 (no migrations
  declared). Run: seihou upgrade <name> && seihou run" row for
  benign cases and lists the upgrade-and-run pair in the
  Recommended actions tail.
- `partitionBenign` (or `isBenignUpgrade`) splits a list of
  `(ModuleName, MigrationPlan)` into benign and blocking entries
  with the correct invariants.

`nix flake check` is green.

The synthetic empty-migrations end-to-end demo shows `seihou status`
without the "Blocked: …" message, `seihou migrate <name>` exiting
zero with the softened note, and `seihou run <name>` proceeding
without refusal.

The partial-chain `--bump-only` demo against the live
`seihou-project` tree (master-plan and exec-plan) successfully
catches the manifest up to `0.3.0` without applying any migration
ops. After the demo, restore the original manifest if the user did
not intend to commit the bump (use `git checkout
.seihou/manifest.json` from the seihou tree).

The four documentation files (`docs/cli/migrate.md`,
`docs/cli/status.md`, `docs/cli/run.md`, `docs/user/CHANGELOG.md`)
describe the new behavior and the new flag.


## Idempotence and Recovery


Each milestone is independently committable. If a later milestone
regresses, earlier commits remain useful. Specifically:

- Milestone 1's pinning tests are flipped in Milestones 2-4 to
  match the new behavior. They are not deleted, so the regression
  cannot silently regrow.
- Milestone 6's `--bump-only` is purely additive (a new flag
  defaults to false). Reverting just M6 leaves the rest of the
  benign-upgrade work intact.
- The live-tree `--bump-only` demo writes to the
  `seihou-project/.seihou/manifest.json` file. If the user did not
  intend to commit the bump, run `git checkout
  .seihou/manifest.json` from the seihou tree to restore the
  pre-demo manifest. The synthetic-fixture demo writes only to
  `/tmp` and requires no cleanup.

If `nix flake check` fails for an unrelated reason during M7, the
implementation is still correct — investigate the failure
separately rather than rolling back this plan's work.


## Interfaces and Dependencies


This plan introduces no new external dependencies. All work is
internal to the seihou-core and seihou-cli packages, using only
modules and types already on the build path.

At the end of Milestone 2, the following types must exist:

In `seihou-core/src/Seihou/Core/Migration.hs`:

    data MigrationPlan = MigrationPlan
      { planChain :: MigrationChain
      , planUnreachable :: Maybe (Version, Version)
      , planMigrationsDeclared :: Bool
      }
      deriving stock (Eq, Show, Generic)

At the end of Milestone 3, the following types and signatures must
exist:

In `seihou-cli/src/Seihou/CLI/Migrate.hs`:

    data MigrateResult
      = MigrateNoOp Version
      | MigrateDryRunOK ExecutedMigrationPlan
      | MigrateDryRunOKPartial ExecutedMigrationPlan Version Version
      | MigrateApplied ExecutedMigrationPlan Manifest
      | MigrateAppliedPartial ExecutedMigrationPlan Manifest Version Version
      | MigrateBlocked Version Version
      | MigrateBenignUpgrade Version Version
      deriving stock (Eq, Show, Generic)

In `seihou-cli/src/Seihou/CLI/PendingMigrations.hs`:

    isBenignUpgrade :: MigrationPlan -> Bool

At the end of Milestone 4, the following must exist:

In `seihou-cli/src/Seihou/CLI/StatusRender.hs`:

    data ModuleAdvice
      = AdviceNone
      | AdviceUpgradeOnly Text
      | AdvicePendingMigration Text MigrationChain
      | AdvicePartialMigration Text MigrationPlan
      | AdviceBlockedMigration Text Version Version
      | AdviceBenignUpgrade Text Version Version
      deriving stock (Eq, Show)

At the end of Milestone 6, the following must exist:

In `seihou-cli/src/Seihou/CLI/Migrate.hs`:

    data MigrateOpts = MigrateOpts
      { migrateModule :: ModuleName
      , migrateTo :: Maybe Text
      , migrateDryRun :: Bool
      , migrateForce :: Bool
      , migrateJson :: Bool
      , migrateVerbose :: Bool
      , migrateNoFetch :: Bool
      , migrateBumpOnly :: Bool
      }
      deriving stock (Eq, Show, Generic)

    data MigrateError = … | MigrateConflictingFlags Text

These signatures are the contract; M3-M6 each verify their slice
ends with the listed types in place by running `cabal build all`
between the implementation step and the test step. If a type
shape changes during implementation (for example, if the dispatch
helper turns out to need an extra argument), record the deviation
in the Decision Log and update this section before committing the
final milestone.
