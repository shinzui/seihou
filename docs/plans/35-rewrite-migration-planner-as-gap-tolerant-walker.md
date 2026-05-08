---
id: 35
slug: rewrite-migration-planner-as-gap-tolerant-walker
title: "Rewrite the migration planner as a gap-tolerant version-window walker"
kind: exec-plan
created_at: 2026-05-08T00:00:00Z
intention: "intention_01kr42z721e54rq497pxf2p9zh"
---


# Rewrite the migration planner as a gap-tolerant version-window walker

Intention: intention_01kr42z721e54rq497pxf2p9zh

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

`seihou migrate` has been patched five times (EP-5 / 23, EP-6 / 24, EP-7 / 25,
EP-27, EP-28) without ever matching the user's mental model:

> "What's so hard about looking at the current installed version of a module
> and running each migration between the current version and the latest
> version and not breaking if one version does not have a migration? So if
> 0.2 → 0.3 has a migration and 0.4 → 0.5 does not and 0.5 → 0.6 does and
> 0.6 doesn't, then migrating from 0.2 to 0.6 should run the 2 migrations
> in order."

Today's planner (`seihou-core/src/Seihou/Core/Migration.hs:185-240`) walks a
*strict chain*: at each step it requires an edge whose `from` exactly equals
the current cursor. A missing edge is a **stop signal**. The
five preceding plans bolted state onto that stop signal — `planUnreachable`
(EP-5), `planMigrationsDeclared` (EP-6), `planTailExhausted` (EP-28), the
`--bump-only` escape hatch (EP-7), the EP-27 fetch-vs-local fallback — to
paper over what users keep asking for, which is: **don't stop, just skip
the gap and keep walking**.

This plan deletes the strict-chain machinery and replaces the planner with
a single rule:

> **Apply every declared migration `m` such that `installed ≤ m.from` and
> `m.to ≤ target`, in ascending `from` order, advancing the cursor as you
> go (skipping any edge whose `from` is now behind the cursor). After all
> applicable edges have run, advance the manifest's recorded version to
> `target`.**

After this plan ships, the user runs **one** command from any of the
following starting states and lands at the locally installed copy's
declared version:

    # Scenario A — user's literal example. Manifest at 0.2, installed declares
    # 0.6, declared migrations [{0.2 → 0.3}, {0.5 → 0.6}].
    $ seihou migrate foo
    Migration plan: foo  0.2 → 0.6
      0.2 → 0.3:
        <ops>
      0.5 → 0.6:
        <ops>
    2 operation(s), 0 conflict(s).

    ✓ Migrated foo 0.2 → 0.6.

    $ jq '.modules[] | select(.name=="foo") | .version' .seihou/manifest.json
    "0.6"

    # Scenario B — pure version bump (no migrations declared at all).
    # Manifest at 0.1, installed declares 0.3, migrations = [].
    $ seihou migrate foo
    Migration plan: foo  0.1 → 0.3
      (no migration ops)

    0 operation(s), 0 conflict(s).

    ✓ Migrated foo 0.1 → 0.3.

    # Scenario C — partial cover at the head. Manifest at 0.1, installed
    # declares 0.3, migrations = [{0.1 → 0.2}]. The chain reaches 0.2 via
    # ops; the manifest still advances to 0.3.
    $ seihou migrate foo
    Migration plan: foo  0.1 → 0.3
      0.1 → 0.2:
        <ops>
    1 operation(s), 0 conflict(s).

    ✓ Migrated foo 0.1 → 0.3.

The user no longer ever has to run a second command. The terms
"unreachable tail," "blocked migration," "benign upgrade," and "bump
through" disappear from the user-facing vocabulary, because none of them
correspond to a real outcome anymore — every invocation that has work to do
either succeeds or surfaces a real error (file conflict, downgrade refused,
unparseable version string).

The work is observable in three places:

1. **`seihou-core/test/Seihou/Core/MigrationSpec.hs`** — the planner test
   matrix shrinks dramatically and pins the new behaviour.
2. **`seihou-cli/test/Seihou/CLI/MigrateSpec.hs`,
   `StatusRenderSpec.hs`, `PendingMigrationSpec.hs`** — CLI tests pin the
   collapsed `MigrateResult` ADT and the simplified pending-row renderer.
3. **A live fixture under `/tmp/seihou-walker-repro/`** that reproduces
   Scenario A end-to-end.


## Progress

- [x] M1 — Replace the planner core with the window walker
      (`seihou-core/src/Seihou/Core/Migration.hs` + tests). Done
      2026-05-08: planner rewritten to ascending-`from` window walk;
      `MigrationChain`, `MigrationGap`, `MigrationOvershoot` removed;
      `MigrationPlan` flattened to `{planModule, planFrom, planTo,
      planSteps}`; engine layer's `ExecutedMigrationPlan` now carries
      `planSource :: MigrationPlan` (renamed from `planChain`); `bumpVersion`
      reads `planTo` directly so empty-step plans still advance the
      manifest. All 16 planner specs + all 847 seihou-core tests pass.
- [x] M2 — Collapse `MigrateResult` and rewrite `dispatchPlan`
      (`seihou-cli/src/Seihou/CLI/Migrate.hs` + tests + JSON shape).
      Done 2026-05-08. Folded M4 + M5 in alongside M2 (see Decision
      Log) because the planner field removals forced the consumer
      simplifications and EP-27 fallback retune to land in the same
      commit. `MigrateResult` now has only `MigrateNoOp`,
      `MigrateApplied`, `MigrateDryRunOK`. JSON shape simplified to
      `{module, from, to, steps, operations}`. EP-27 fallback retuned
      to "local declares more in-window steps than clone."
- [x] M3 — Remove the `--bump-only` (`seihou migrate`) and
      `--bump-blocked` (`seihou run`) flags and their scaffolding.
      Done 2026-05-08. Removed `migrateBumpOnly` from `MigrateOpts`,
      `runBumpBlocked` from `RunOpts`, and the parser entries / record
      construction sites for both. `seihou migrate --help` /
      `seihou run --help` no longer mention the flags.
- [x] M4 — Simplify the pending-migration consumers
      (`StatusRender.hs`, `PendingMigrations.hs`, `Run.hs`, `Upgrade.hs`),
      including the user-facing refusal-message strings. Done
      2026-05-08, folded into M2's commit. Removed
      `isBenignUpgrade`, `isBlockedMigration`; collapsed the
      `ModuleAdvice` ADT; rewrote refusal/advisory strings.
- [x] M5 — Reconcile the EP-27 fetch-vs-local fallback against the new
      planner contract. Done 2026-05-08, folded into M2's commit.
      Renamed `fallbackToLocal` to `maybeFallbackToLocal`; trigger is
      now "local plan has strictly more steps than clone plan."
- [ ] M6 — Live verification + docs + CHANGELOG, covering every
      user-visible surface: the embedded `seihou help migrations`
      topic, the four touched CLI references (`migrate.md`, `status.md`,
      `run.md`, `upgrade.md`), the user concept guide
      (`docs/user/migrations.md`), and the migrations DX masterplan.


## Surprises & Discoveries

- M1: `Seihou.Engine.Migrate.ExecutedMigrationPlan` had a field named
  `planChain :: MigrationChain`. With the planner type's old shape gone,
  the field was renamed to `planSource :: MigrationPlan`. Field-name
  collisions with the new `MigrationPlan` record (which has its own
  `planModule`, `planFrom`, `planTo`, `planSteps`) are resolved by
  `OverloadedRecordDot` — Haskell picks the right selector by record
  type at the call site. The CLI consumers in M2/M4 will switch from
  `plan.planChain.chainSteps` to `plan.planSource.planSteps` (or
  unwrap the source for direct access to the underlying plan). Date:
  2026-05-08.


## Decision Log

- Decision: Replace the planner algorithm rather than add a sixth boolean
  flag to the `MigrationPlan` record.
  Rationale: EP-5 / 23, EP-6 / 24, EP-7 / 25, EP-27 and EP-28 all added
  fields, variants, or branches to express what the user has now stated
  is a single coherent rule. Continuing the patch trajectory has produced
  five distinct plan shapes and four `MigrateResult` apply/dry-run pairs;
  every renderer and pre-flight check has to enumerate them. The simpler
  rule the user has described (window walker with skip-the-gap semantics)
  collapses all five shapes into one and removes every renderer branch
  except "did anything run?".
  Date: 2026-05-08

- Decision: Remove the `--bump-only` flag entirely. Default `seihou
  migrate` already does what `--bump-only` was for (advance the manifest
  even when no migration ops apply). `--to TARGET` is just a target
  override — same algorithm, user-supplied target.
  Rationale: User chose this option explicitly when scoping the plan
  (2026-05-08). The flag exists only because the strict-chain planner
  refused to advance the manifest past a gap; with the window walker the
  manifest always advances to target. Keeping the flag as a no-op alias
  would preserve scripts but document a misleading mental model. Better
  to remove it and add a one-line CHANGELOG note.
  Date: 2026-05-08

- Decision: Remove `--bump-blocked` (the `seihou run` flag) at the same
  time as `--bump-only`. They are siblings: `--bump-blocked` exists
  only to apply `--bump-only` to every "blocked" module in one go, and
  the new planner has no "blocked" classification. Default `seihou run
  --with-migrations` will, after this plan, naturally process every
  pending entry the same way (apply any in-window migrations and
  advance the manifest).
  Rationale: Leaving `--bump-blocked` behind would re-introduce the
  removed vocabulary in the help text, run handler comments, and
  pre-flight refusal strings. The flag is removed in M3 alongside
  `--bump-only` for symmetry.
  Date: 2026-05-08

- Decision: The agent-facing skill files
  (`agents/skills/master-plan/MASTERPLAN.md`,
  `agents/skills/master-plan/SKILL.md`,
  `claude/skills/exec-plan/PLANS.md`,
  `claude/skills/seihou-update-docs/SKILL.md`,
  `claude/skills/seihou-release/SKILL.md`,
  `claude/skills/update-seihou-schema/SKILL.md`) need no changes.
  Rationale: A `grep -RinE
  "bump[-_ ]only|partial chain|blocked migration|benign upgrade|bump.*through"`
  across `agents/` and `claude/` returns zero matches at the time of
  writing. The skills are domain-agnostic ExecPlan / masterplan /
  release tooling and don't reference migration vocabulary directly.
  Recording the negative finding here saves a future implementer the
  same search.
  Date: 2026-05-08

- Decision: `--to TARGET` does **not** preserve EP-5's "strict-target"
  contract. Under the new planner there is no notion of "the chain
  failed to cover the target" — the chain is whatever migrations fit in
  the window, and the manifest always lands at the supplied target.
  Rationale: The strict-target contract was a downstream consequence of
  the strict-chain algorithm. With the window walker, a target the user
  supplies is reached by definition (no migration is required to bridge
  every gap). Scripted callers that want to *check* whether a specific
  set of migrations ran can read the JSON output's `steps` array.
  Date: 2026-05-08

- Decision: `MigrationOvershoot` is removed as an error variant.
  Rationale: A migration whose `to` exceeds the supplied target is
  silently skipped under the new algorithm; it is not an authoring bug.
  Such migrations re-enter the picture once the user supplies a target
  >= their `to`.
  Date: 2026-05-08

- Decision: Keep `MigrationDuplicateEdge` as a hard error.
  Rationale: Two migrations with the same `from` are an authoring
  ambiguity, not a workflow problem. Failing loud catches it before
  shipping; silently picking one is non-deterministic on sort stability.
  Date: 2026-05-08

- Decision: Overlapping intervals (e.g. `[{0.2 → 0.5}, {0.3 → 0.4}]`)
  are resolved by ascending `from`-then-`to` sort + cursor advance: the
  first edge by sort wins; subsequent edges with `from < cursor` are
  skipped silently.
  Rationale: Authors who legitimately want a "leapfrog" migration will
  declare the longer span; the shorter overlap is then redundant. Authors
  who want both to apply must split into non-overlapping spans. Erroring
  on overlap is too aggressive (it would break the master-plan EP-5
  fixture which has `[{0.1 → 0.2}, {0.5 → 0.6}]` against installed=0.1
  target=0.6 — a non-overlapping pair this plan must support).
  Date: 2026-05-08

- Decision: Fold M4 (consumer simplification) and M5 (EP-27 fallback
  retune) into M2's commit rather than land them as separate
  milestones.
  Rationale: The planner-field removals (`planChain`, `planUnreachable`,
  `planMigrationsDeclared`, `planTailExhausted`) made it impossible to
  keep the consumer files compiling after M2's `MigrationPlan` rewrite.
  Splitting M2 / M4 / M5 across three commits would have meant either
  (a) leaving the workspace un-buildable between commits, contrary to
  PLANS.md's "every commit leaves the codebase in a working state"
  guideline, or (b) shipping a "M2-bridge" with placeholder consumer
  code only to immediately replace it in M4. Folding the three
  together preserves the milestone numbering in the plan ledger but
  produces one buildable commit. Progress checkboxes mark M4 and M5
  complete with a "folded into M2" note.
  Date: 2026-05-08

- Decision: Retain the EP-27 fetch-vs-local fallback shape, but rewrite
  its trigger condition. Under the new planner the clone may yield a
  plan with zero steps where the local install yields a plan with N
  steps; that is precisely the EP-27 hazard, just expressed in the new
  vocabulary.
  Rationale: The divergence problem (cloned remote drops a migration
  that the local install still declares) is orthogonal to the planner
  algorithm — it concerns *which* migrations list to plan against, not
  how to walk the list. EP-27's fallback is still the right shape;
  M5 just retunes the trigger to "local plan has more steps than clone
  plan."
  Date: 2026-05-08


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

**Seihou** is a project scaffolding system written in Haskell. A
*module* is a reusable bundle of templates and configuration. A user
applies a module to a project; the application is recorded in
`.seihou/manifest.json` as an `AppliedModule` with the module's version
at apply time (`Seihou.Core.Types.AppliedModule.moduleVersion`,
`seihou-core/src/Seihou/Core/Types.hs:446-453`).

A module author can declare *migrations* in `module.dhall`:

    migrations =
      [ { from = "0.2", to = "0.3", ops = [ ... ] }
      , { from = "0.5", to = "0.6", ops = [ ... ] }
      ]

The Dhall schema for a migration is at
`schema/Migration.dhall:1-31`; the ops union is at
`schema/MigrationOp.dhall:1-25`. The Haskell `Migration` and
`MigrationOp` types and the planner are in
`seihou-core/src/Seihou/Core/Migration.hs:34-49` and
`:175-240`.

The current planner is a greedy, strict-chain walker:

    walk current tgt edges acc
      | current == tgt = Right (reverse acc, current, Nothing)
      | otherwise = case [(m, f, t) | (m, f, t) <- edges, f == current] of
          []                              -> Right (reverse acc, current, Just (current, tgt))
          ((m, _f, t) : _) | t > tgt      -> Left (MigrationOvershoot current t)
                           | otherwise    -> walk t tgt edges (m : acc)

That `f == current` filter is the bug. It is what produces the
"unreachable tail" plan shape. It is what made EP-28 invent
`planTailExhausted` to distinguish "the gap is benign" from "the gap is
blocked." It is what made EP-27 invent `fallbackToLocal`. It is what
the user has been reporting against, in some form, for five plans.

The planner's caller is the CLI, which dispatches the plan in
`seihou-cli/src/Seihou/CLI/Migrate.hs:`:

- The `MigrateResult` ADT (lines 165-217 of `Migrate.hs`) currently has
  these variants:

      MigrateNoOp, MigrateDryRunOK, MigrateDryRunOKPartial,
      MigrateDryRunOKBumpedThrough, MigrateApplied,
      MigrateAppliedPartial, MigrateAppliedBumpedThrough,
      MigrateBlocked, MigrateBenignUpgrade

- `dispatchPlan` (lines 932-979) splits plans into five shapes per the
  `planChain.chainSteps` / `planUnreachable` /
  `planMigrationsDeclared` / `planTailExhausted` matrix.

- `applyChain` (lines 992-1023) applies the chain prefix and returns
  `MigrateApplied` or `MigrateAppliedPartial`.

- `applyChainBumpThrough` (lines 1034-1066) applies the prefix and
  *also* bumps the manifest's `moduleVersion` to the supplied target,
  returning `MigrateAppliedBumpedThrough`.

- The `MigrateOpts` record (lines 86-130) carries `migrateBumpOnly`,
  the field backing `--bump-only`. The bump-only path is dispatched
  before planning at lines 498-509 (`runMigrate`) via `runBumpOnly`.

The pending-migration helpers are in
`seihou-cli/src/Seihou/CLI/PendingMigrations.hs`:
`detectPendingMigrations`, `formatRefusalMessage`, `isBenignUpgrade`,
`isBlockedMigration`, `isBumpedThrough` (added in EP-28). Each function
inspects the planner output and routes to a different message. The
status renderer in `seihou-cli/src/Seihou/CLI/StatusRender.hs` has a
matching four-branch case at lines 105-117. The `seihou run` and
`seihou upgrade` consumers in
`seihou-cli/src-exe/Seihou/CLI/Run.hs` and
`seihou-cli/src-exe/Seihou/CLI/Upgrade.hs` re-encode the same case
analysis. Whenever a new plan shape was added, every one of those
four sites had to grow a new branch.

Tests covering the current planner contract:

- `seihou-core/test/Seihou/Core/MigrationSpec.hs` (≈250 lines, 23
  cases as of HEAD) pins the strict-chain semantics and the EP-28
  `planTailExhausted` field.
- `seihou-cli/test/Seihou/CLI/MigrateSpec.hs` pins the dispatch
  outcomes for every `MigrateResult` variant. Several tests under
  "EP-27 M2" and "EP-28 bump-through" exist specifically for the
  fallback / bump-through composition.
- `seihou-cli/test/Seihou/CLI/StatusRenderSpec.hs` and
  `seihou-cli/test/Seihou/CLI/PendingMigrationSpec.hs` pin the
  rendered text for each plan shape.

**User-visible surfaces** (anything the user — or an agent helping
the user — can read) that mention the partial-chain / blocked /
benign / bump-through / `--bump-only` / `--bump-blocked` vocabulary.
Every one of these must be updated by M6 or earlier:

1. **Embedded CLI help topic.** The `seihou help migrations` command
   reads from `seihou-cli/help/migrations.md`, embedded into the
   binary at compile time via Template Haskell
   (`Data.FileEmbed.embedStringFile`). The dispatcher is in
   `seihou-cli/src-exe/Seihou/CLI/Help.hs:37-60` (the
   `helpTopics` registry and the `migrationsContent` binding). The
   embedded file's path is fixed by the TH splice; the file
   *itself* must be rewritten, not relocated.
2. **CLI command references.** Four files under `docs/cli/`:
   - `docs/cli/migrate.md` — entire "Partial chains" subsection
     plus every example transcript that prints "Note: ..." or
     "Blocked: ...".
   - `docs/cli/status.md` — per-row advisory examples.
   - `docs/cli/run.md` — `--bump-blocked` flag reference (line 36),
     the "Partial chain" / "Blocked" / "Recovering from blocked
     migrations" sections (lines 70-160 ish).
   - `docs/cli/upgrade.md` — the post-upgrade advisory examples
     (lines 50-55 ish) that reference `--bump-only`.
3. **User concept guide.** `docs/user/migrations.md` is the
   end-user-facing reference for how migrations work. It currently
   describes the strict-chain mental model and the partial / blocked
   / benign distinction.
4. **CHANGELOG.** `docs/user/CHANGELOG.md` (EP-27 and EP-28 entries
   are historical and stay; M6 adds a new entry).
5. **Masterplan.** `docs/masterplans/1-migrations-dx.md` is the
   ledger that tracks EP-5 through EP-28; M6 appends a closing
   entry naming this plan as the supersession.
6. **In-source comment / docstring vocabulary.** Source files that
   embed the doomed terms in comments or refusal-message strings
   (each is updated as the relevant milestone touches its file):
   - `seihou-cli/src/Seihou/CLI/StatusRender.hs:97` (comment about
     `--bump-blocked`).
   - `seihou-cli/src/Seihou/CLI/PendingMigrations.hs:94, 99-101,
     188` (refusal-message strings naming `--bump-only` and
     `--bump-blocked`).
   - `seihou-cli/src-exe/Seihou/CLI/Commands.hs:126-128, 700-701`
     (parser-help text for `--bump-blocked` and the surrounding
     comment).
   - `seihou-cli/src-exe/Seihou/CLI/Run.hs:531-541, 665, 727, 748,
     787` (refusal-message strings, dry-run banner, internal-error
     messages).

**Surfaces that need no changes** (recorded so a future implementer
doesn't repeat the search): a `grep -RinE
"bump[-_ ]only|partial chain|blocked migration|benign upgrade|bump.*through"`
across `agents/` and `claude/` returns zero matches. The agent
skills are domain-agnostic and don't reference migration
vocabulary. Likewise the historical plans
`docs/plans/13-module-migrations.md`,
`docs/plans/15-make-migrate-self-contained.md`,
`docs/plans/16-make-run-migration-aware.md`,
`docs/plans/17-improve-status-migration-visibility.md`,
`docs/plans/23-bulletproof-partial-migration-chains.md`,
`docs/plans/24-distinguish-benign-version-bumps.md`,
`docs/plans/25-recover-from-blocked-migrations.md`,
`docs/plans/26-migrate-commit-flag.md`,
`docs/plans/27-fix-migrate-skips-partial-chain.md`, and
`docs/plans/28-bump-through-benign-tail.md` are historical records
of completed work and stay as-is per ExecPlan convention; the
masterplan close-out notes that EP-35 supersedes them.

The masterplan at `docs/masterplans/1-migrations-dx.md` is the
authoritative ledger of the migrations DX work to date. M6 of this
plan adds an entry there marking the migration DX masterplan as
complete (or at minimum noting that this plan is the last in that
arc).

Two-component versions ("0.1") and three-component versions ("0.1.0")
compare identically per `Seihou.Core.Version.Version`'s `Eq`/`Ord`
instances, which pad with trailing zeros. The user's literal example
uses two-component versions; M1 tests pin the new contract on those
shapes specifically so future regressions on shorter version strings
are caught.


## Plan of Work

The plan has six milestones. Each one is independently verifiable. M1
is the keystone: every later milestone pulls down complexity that M1's
new planner contract makes obsolete.


### Milestone 1 — Replace the planner core with the window walker

Goal: `Seihou.Core.Migration.planMigrationChain` returns a single
`MigrationPlan` shape that lists every applicable migration in
ascending order. No "unreachable tail" field, no
`planMigrationsDeclared`, no `planTailExhausted`. The plan also carries
the *target* version so downstream apply code knows where to land the
manifest.

In `seihou-core/src/Seihou/Core/Migration.hs`:

- Replace the `MigrationPlan` and `MigrationChain` records with a
  single record:

      data MigrationPlan = MigrationPlan
        { planModule :: Text
        , planFrom :: Version          -- installed (manifest)
        , planTo :: Version            -- target (manifest will land here)
        , planSteps :: [Migration]     -- in ascending `from` order
        }
        deriving stock (Eq, Show, Generic)

  The record carries everything every consumer ever needed:
  `planModule` for rendering, `planFrom` and `planTo` for the
  user-visible "X → Y" header, `planSteps` for the per-step rendering
  and execution. There is exactly one shape, so consumers branch only
  on `null planSteps` (a pure version-bump apply with no ops).

- Trim `MigrationPlanError`:

      data MigrationPlanError
        = MigrationVersionUnparseable Text
        | MigrationDowngradeNotSupported Version Version
        | MigrationDuplicateEdge Version Version
        deriving stock (Eq, Show, Generic)

  `MigrationGap` and `MigrationOvershoot` are removed. (The CLI
  no longer needs to construct them; partial coverage is a normal
  outcome and overshoot is silently skipped.)

- Replace the planner body:

      planMigrationChain modName migrations installed target
        | installed == target = Right Nothing
        | target < installed =
            Left (MigrationDowngradeNotSupported installed target)
        | otherwise = do
            parsed <- traverse parseEdges migrations
            checkDuplicates parsed
            let sorted = sortOn (\(_, f, _) -> f) parsed
            let steps = pickInWindow installed target sorted
            Right
              ( Just
                  MigrationPlan
                    { planModule = modName
                    , planFrom = installed
                    , planTo = target
                    , planSteps = steps
                    }
              )
        where
          pickInWindow _cursor _end [] = []
          pickInWindow cursor end ((m, f, t) : rest)
            | f < cursor = pickInWindow cursor end rest    -- already past
            | f >= end = []                                 -- list is sorted, done
            | t > end = pickInWindow cursor end rest        -- overshoots target, skip
            | otherwise = m : pickInWindow t end rest       -- apply, advance cursor

  Notes:

  - `sorted` ascends by `from`. A migration whose `from < cursor` is
    skipped (already covered by an earlier picked edge or precedes
    the manifest version). A migration whose `from >= end` cannot
    contribute (the list is sorted; we're done). A migration whose
    `to > end` is silently skipped (overshoots the user's target;
    the user simply hasn't asked to go that far).
  - Duplicate-from is still rejected up front via `checkDuplicates`.
    The existing helper at lines 222-227 of the current file
    transfers verbatim.
  - `parseEdges` and `parseVersionE` transfer verbatim from the
    current file (lines 211-220).

- Update the haddock at the top of `MigrationPlan` to describe the
  new contract in two paragraphs: window semantics, and "manifest
  always advances to `planTo`."

In `seihou-core/test/Seihou/Core/MigrationSpec.hs`:

- Keep these tests (they pin invariants that survive the refactor):
  - "returns Nothing when installed equals target."
  - "rejects a downgrade with MigrationDowngradeNotSupported."
  - "reports MigrationVersionUnparseable when a from string is
    malformed."
  - "reports MigrationVersionUnparseable when a to string is
    malformed."
  - "rejects two edges sharing the same from with
    MigrationDuplicateEdge."
  - "ignores migrations whose from precedes the installed version."
  - "treats version equality with trailing zeros consistently."

- Remove these (they pin behaviours the new planner deliberately
  abandons):
  - "stops one step short of the target with MigrationOvershoot."
  - "returns a partial chain plus an unreachable tail when the walk
    gets stuck mid-way."
  - "distinguishes migrations=[] from migrations=[someEdge-that-doesnt-reach]
    via planMigrationsDeclared."
  - All six `EP-28: planTailExhausted ...` tests.

- Reshape these:
  - "builds a single-edge chain" → keep, assert
    `planSteps == [edge]` and `planTo == edge.to == target`.
  - "builds a two-edge chain in order regardless of declaration
    order" → keep with the same fixture but assert the new shape
    (`planSteps` is a 2-element list; `planTo == target`).
  - "returns a partial plan for the EP-5 master-plan fixture" →
    rewrite. The fixture is `[{0.1.0 → 0.2.0}, {0.5.0 → 0.6.0}]`
    against installed=0.1.0 target=0.6.0. New expectation:
    `planSteps == [edge_01_02, edge_05_06]`, `planTo == 0.6.0`. This
    is the user's literal scenario at three-component scale.
  - "returns a blocked plan (empty chain + unreachable tail) when no
    edge starts at installed" → rewrite as "returns an empty-steps
    plan when no declared migration falls in the window," asserting
    `planSteps == []` and `planTo == target`.

- Add these new tests:
  - "User's two-component fixture: 0.2 / 0.6 with [{0.2→0.3},
    {0.5→0.6}] yields both edges." Pins the user's literal example
    against the new planner.
  - "Skips migrations that overshoot the supplied target." Fixture:
    `[{0.5 → 1.0}]` with installed=0.4 target=0.6. Expected:
    `planSteps == []`, `planTo == 0.6`.
  - "Skips overlapping migrations once the cursor has advanced past
    them." Fixture: `[{0.2 → 0.5}, {0.3 → 0.4}]` with installed=0.2
    target=0.5. Expected: `planSteps == [edge_02_05]`.
  - "Empty migrations list with installed != target yields plan with
    empty steps and target." Fixture: `migrations = []` with
    installed=0.1 target=0.3. Expected: `planSteps == []`,
    `planTo == 0.3`.
  - "Edges with `to == target` are picked." Fixture: `[{0.2 → 0.3}]`
    with installed=0.2 target=0.3. Expected: `planSteps ==
    [edge_02_03]`. (Sanity test against off-by-one in the `f >= end`
    early-stop.)

Acceptance for M1:

- `cabal --enable-tests test seihou-core:test:seihou-core-test
  --test-show-details=streaming` passes.
- The planner module exports exactly the symbols listed in its module
  header: `Migration`, `MigrationOp`, `MigrationPlan` (new shape),
  `MigrationPlanError`, `planMigrationChain`. **`MigrationChain` is
  deleted.**
- Building the workspace (`cabal build all`) at this milestone will
  fail in `seihou-cli` because dispatch code references the removed
  fields. That's expected; M2 fixes it. The library itself compiles.

Concrete commands:

    cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
    cabal --enable-tests test seihou-core:test:seihou-core-test \
      --test-show-details=streaming
    # Expected: ~12 tests passing (down from 23). All assert the new
    # plan shape.

Commit at the end of M1 with the trailer
`ExecPlan: docs/plans/35-rewrite-migration-planner-as-gap-tolerant-walker.md`
and `Intention: intention_01kr42z721e54rq497pxf2p9zh`.


### Milestone 2 — Collapse `MigrateResult` and rewrite `dispatchPlan`

Goal: every successful migrate invocation returns one of three
results: `MigrateNoOp` (already at target), `MigrateApplied` (the
manifest advanced; possibly with zero ops), or `MigrateDryRunOK`
(dry-run preview of the same). The four old "partial / bump-through /
blocked / benign" variants vanish.

In `seihou-cli/src/Seihou/CLI/Migrate.hs`:

- Replace the `MigrateResult` ADT with:

      data MigrateResult
        = MigrateNoOp Version
          -- ^ Manifest already records the target version. No work.
        | MigrateApplied ExecutedMigrationPlan Manifest Version Version
          -- ^ Manifest advanced from `from` (arg 3) to `to` (arg 4).
          -- The `ExecutedMigrationPlan` lists which steps actually ran;
          -- it may be empty (a pure version bump).
        | MigrateDryRunOK MigrationPlan Version Version
          -- ^ Dry-run companion of 'MigrateApplied'.

  Remove `MigrateAppliedPartial`, `MigrateAppliedBumpedThrough`,
  `MigrateDryRunOKPartial`, `MigrateDryRunOKBumpedThrough`,
  `MigrateBlocked`, `MigrateBenignUpgrade`.

- Rewrite `dispatchPlan` to a single branch:

      dispatchPlan opts manifest plan = do
        if plan.planFrom == plan.planTo
          then pure (Right (MigrateNoOp plan.planTo))
          else applyOrDryRun opts manifest plan

  `applyOrDryRun` is the merged successor of `applyChain` and
  `applyChainBumpThrough`: it classifies the file ops, optionally
  executes them, then advances the manifest's recorded
  `moduleVersion` from `planFrom` to `planTo`. Existing helpers
  reused verbatim:
  - `classifyFile` and the conflict check from
    `seihou-core/src/Seihou/Engine/Migrate.hs:98-156`.
  - `executeMigration` from
    `seihou-core/src/Seihou/Engine/Migrate.hs:162-197` (pass the
    new plan; the engine already advances `moduleVersion` to the
    chain target after executing ops, see lines 190-196).
  - `replaceModuleVersion` (the `--bump-only` helper, currently in
    the same file) becomes part of the standard apply path:
    after `executeMigration`, call `replaceModuleVersion` to set
    the manifest's `moduleVersion` to `planTo` (which may differ
    from the highest `to` in `planSteps`). For a plan with empty
    `planSteps`, `executeMigration` runs zero ops but
    `replaceModuleVersion` still advances the manifest, which is
    exactly the old `--bump-only` behaviour now subsumed.

- Remove `applyChainBumpThrough` and the `chainSteps`/`chainTo`
  scaffolding entirely. Anything that referenced
  `plan.planChain.chainTo` now reads `plan.planTo`; anything that
  referenced `plan.planChain.chainSteps` reads `plan.planSteps`;
  anything that constructed a `MigrationChain` is deleted.

- Update the renderer in `handleMigrate` (currently a
  multi-arm pattern match at lines 350-460 of `Migrate.hs`):

      Right (MigrateNoOp v) -> putStrLn $ "✓ <module> already at " <> show v
      Right (MigrateApplied execPlan _ from to) ->
        renderApplyTranscript execPlan from to
      Right (MigrateDryRunOK plan from to) ->
        renderDryRunTranscript plan from to

  `renderApplyTranscript` and `renderDryRunTranscript` print the
  Scenario A / B / C transcripts shown in this plan's Purpose
  section. The "Note: tail unreachable / would bump through" lines
  do not appear; they have no semantic counterpart in the new
  shape.

- Update the JSON encoder. The current file has
  `planToJsonWithTail` and `planToJsonBumpedThrough` (lines 1198-1244
  ish); replace with a single `planToJson` that emits:

      {
        "module": "<name>",
        "from": "<planFrom>",
        "to": "<planTo>",
        "steps": [
          { "from": "<step.from>", "to": "<step.to>",
            "ops": [...] },
          ...
        ]
      }

  Any consumer reading the old `bumpedThrough`, `unreachable`, or
  `manifestVersion` keys is updated by reference to the
  CHANGELOG entry in M6.

In `seihou-cli/test/Seihou/CLI/MigrateSpec.hs`:

- Delete the entire "EP-28 bump-through" describe block and the
  EP-27 M2 fallback variants that asserted bump-through composition.
  These tests pinned an old contract.
- Reshape every test that asserted `MigrateAppliedPartial`,
  `MigrateAppliedBumpedThrough`, `MigrateBlocked`, or
  `MigrateBenignUpgrade` to expect `MigrateApplied`. The fixture
  setups remain valid; only the asserted result variant changes.
- Add three new tests at the dispatch layer:
  - "User's two-component fixture (Scenario A) yields
    `MigrateApplied` with both edges in `executedSteps` and manifest
    at 0.6."
  - "Pure version bump (Scenario B, migrations = []) yields
    `MigrateApplied` with empty `executedSteps` and manifest at the
    installed-declared version."
  - "Partial cover at head (Scenario C, [{0.1 → 0.2}], target 0.3)
    yields `MigrateApplied` with one step and manifest at 0.3."

Acceptance for M2:

- `cabal --enable-tests test seihou-cli:test:seihou-cli-test
  --test-show-details=streaming` passes for every spec module
  except possibly the EP-27/EP-28 ones M2 reshapes (those are
  expected to be re-greened during M2 itself).
- `cabal build all` succeeds.
- The JSON output of `seihou migrate --json` matches the new shape.

Concrete commands:

    cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
    cabal build all
    cabal --enable-tests test seihou-cli:test:seihou-cli-test \
      --test-show-details=streaming \
      --test-options='--match "Seihou.CLI.Migrate"'

Commit at the end of M2.


### Milestone 3 — Remove the `--bump-only` and `--bump-blocked` flags

Goal: `seihou migrate <module> --bump-only` and `seihou run
--bump-blocked` both error with "unknown flag." Both flags are removed
from the parser, the docs, the help text, and every handler.

In `seihou-cli/src/Seihou/CLI/Migrate.hs`:

- Remove `migrateBumpOnly` from the `MigrateOpts` record.
- Remove `runBumpOnly` and the early `if migrateBumpOnly` branch in
  `runMigrate` (currently around lines 498-509).
- Remove the parser entry for `--bump-only` in the options-applicative
  builder (search for `bump-only` in the same file).

In `seihou-cli/src-exe/Seihou/CLI/Commands.hs`:

- Remove the `--bump-blocked` flag declaration at lines 700-701 and
  the surrounding comment at lines 126-128.
- Confirm there is no second `--bump-only` declaration at the
  executable layer (`grep -n bump-only
  seihou-cli/src-exe/Seihou/CLI/Commands.hs`).

In `seihou-cli/src-exe/Seihou/CLI/Run.hs`:

- Remove the `--bump-blocked` dry-run banner at line 531.
- Remove the `Acknowledging blocked modules (--bump-blocked)...`
  log message and the surrounding handler at lines 541 ish.
- Remove every refusal-message string that names `--bump-only` or
  `--bump-blocked` at lines 665, 727, 748, 787 ish. M4 replaces
  them with the new collapsed wording.
- Remove the `RunOpts.runBumpBlocked` field and any pattern matches
  on it. The handler simplifies to "if `--with-migrations`, run
  every pending entry through `runMigrate`; otherwise refuse."

In tests:

- Delete every test in `MigrateSpec.hs` that exercises `--bump-only`.
- Delete every test in `RunSpec.hs` that exercises `--bump-blocked`.
- Add one negative test per spec asserting that the parser rejects
  the removed flag with a clear error.

Acceptance for M3:

- `seihou migrate --help` does not mention `--bump-only`.
- `seihou run --help` does not mention `--bump-blocked`.
- `cabal --enable-tests test all` passes.
- A grep for `bump[-_](only|blocked)` (case-insensitive, hyphen and
  underscore variants) across `seihou-cli/src`,
  `seihou-cli/src-exe`, and `seihou-core/src` returns zero matches.
  Matches in `docs/user/CHANGELOG.md` (the removal note added in
  M6) and in this plan's text are expected.

Concrete commands:

    cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
    cabal build seihou-cli
    cabal run seihou -- migrate --help | grep -i 'bump-only' || echo "OK: no match"
    cabal run seihou -- run --help | grep -i 'bump-blocked' || echo "OK: no match"
    grep -RinE 'bump[-_](only|blocked)' seihou-cli/src seihou-cli/src-exe seihou-core/src

Commit at the end of M3.


### Milestone 4 — Simplify the pending-migration consumers

Goal: every consumer that currently branches on
`planMigrationsDeclared`, `planTailExhausted`, or `planUnreachable`
collapses to a single branch on `null planSteps`.

The pattern is the same in every file:

    -- Before:
    case (chainSteps == [], planMigrationsDeclared, planTailExhausted, planUnreachable) of
      ... five-way case ...

    -- After:
    if plan.planFrom == plan.planTo
      then "<module> is up to date"
      else "Pending migration: <from> → <to> (" <> show (length steps) <> " step(s)). Run: seihou migrate <name>"

Files to touch:

- `seihou-cli/src/Seihou/CLI/StatusRender.hs`:
  - Collapse the four-branch case at lines 105-117 to a single
    branch.
  - Remove the `formatAdvice` per-tail branches at lines 355-365.
  - Update the comment at line 97 that references
    `seihou run --bump-blocked` (the flag is gone after M3).
- `seihou-cli/src/Seihou/CLI/PendingMigrations.hs`:
  - Collapse the multi-branch `formatRefusalMessage` at lines 105-150
    to a single branch. The new refusal text reads roughly:
    `"<N> module(s) have pending migrations. Run 'seihou migrate
    <name>' for each, or pass --with-migrations to apply them
    inline."` No mention of "blocked," "benign," or
    `--bump-only`/`--bump-blocked` (the flags are gone).
  - Update the comment at line 94 and the strings at lines 99-101
    that name `--bump-only` and `--bump-blocked`.
  - Update the comment at line 188 that references
    `seihou run --bump-blocked`.
  - Remove the helpers `isBenignUpgrade`, `isBlockedMigration`, and
    `isBumpedThrough`. Replace any caller with the trivial
    `not (null plan.planSteps) || plan.planFrom /= plan.planTo`
    "is there pending work" check.
- `seihou-cli/src-exe/Seihou/CLI/Run.hs`:
  - `applyOneMigration` simplifies: it now only ever gets
    `MigrateApplied`, `MigrateDryRunOK`, or `MigrateNoOp` from
    `runMigrate`, plus the existing error paths. Remove the
    bump-through arm.
  - `renderPendingSummary` becomes a single line per pending module.
  - Update or remove the user-facing strings at lines 665, 727, 748,
    787 that name `--bump-only` (the flag is gone after M3). The
    new wording points the user at `seihou migrate <name>`
    directly.
- `seihou-cli/src-exe/Seihou/CLI/Upgrade.hs`:
  - `runOnePostUpgradeMigration` and `printAdvisory` collapse to
    one branch each.
  - Any reference to `--bump-only` in `printAdvisory`'s output
    string is replaced with `seihou migrate <name>`.

Tests:

- `seihou-cli/test/Seihou/CLI/StatusRenderSpec.hs`,
  `seihou-cli/test/Seihou/CLI/PendingMigrationSpec.hs`: delete
  every test that pins the wording of "Note: ... bumped through,"
  "Blocked: ...," or "no migrations declared." Reshape any test
  asserting a partial-row layout to the new "Pending migration: X →
  Y (N step(s))" wording.
- Add one test per consumer pinning the new collapsed shape.

Acceptance for M4:

- `cabal --enable-tests test all` passes.
- A grep for `bump.*through`, `blocked migration`, or
  `benign.*upgrade` (case-insensitive) in
  `seihou-cli/src/`, `seihou-cli/src-exe/`, and
  `seihou-cli/test/` returns zero matches.

Concrete commands:

    cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
    cabal --enable-tests test all --test-show-details=streaming
    grep -RinE 'bump.*through|blocked migration|benign.*upgrade' \
      seihou-cli/src seihou-cli/src-exe seihou-cli/test

Commit at the end of M4.


### Milestone 5 — Reconcile the EP-27 fetch-vs-local fallback

Goal: the EP-27 fallback (clone yields no migrations the user can
run, but local install does) survives the refactor with a simpler
trigger.

In `seihou-cli/src/Seihou/CLI/Migrate.hs`:

- The current `fallbackToLocal` helper (around lines 800-820) checks
  for `MigrateBenignUpgrade` or `MigrateBlocked` from the clone-based
  plan. Both variants are gone after M2. The new trigger is:

      let cloneSteps = case plan.planSteps of [] -> 0; _ -> length …
          localSteps = … (re-plan against installed dir) …
      in if localSteps > cloneSteps
           then preferLocal
           else preferClone

  i.e. if the *local* install declares strictly more in-window
  migrations than the clone, prefer the local plan. Otherwise the
  clone's plan stands (preserving EP-15's "freshest content" intent
  for the common case).

- Remove the EP-27 unit tests that assert against `MigrateBenignUpgrade`
  / `MigrateBlocked` triggers; rewrite as
  "fallback runs when local declares migrations the clone doesn't"
  with the same fixture geometry (the divergence fixture under
  `withFetchFixture` in `MigrateSpec.hs`).

Acceptance for M5:

- The EP-27 divergence fixture in `MigrateSpec.hs` continues to
  apply the locally-declared migration when the clone has no
  declarations.
- `cabal --enable-tests test all` passes.

Commit at the end of M5.


### Milestone 6 — Live verification + docs + CHANGELOG

Goal: prove the user's exact scenario works end-to-end on a
hand-rolled fixture; bring all docs in line with the new contract.

Live verification: build the binary and run against
`/tmp/seihou-walker-repro/` (recipe in Concrete Steps below). The
fixture mirrors Scenario A from the Purpose section: manifest at 0.2,
installed declares 0.6, migrations `[{0.2 → 0.3}, {0.5 → 0.6}]`.
Expected transcript shown in Concrete Steps.

Docs (every user-visible surface that mentions the doomed
vocabulary — see Context and Orientation for the full enumeration):

- `seihou-cli/help/migrations.md`: rewrite end-to-end. This is the
  embedded source for `seihou help migrations` (Template-Haskell
  embedded into the binary via
  `seihou-cli/src-exe/Seihou/CLI/Help.hs:60`). Cover: how the
  planner picks migrations (window walker), the user-visible
  invariant ("manifest always advances to target"), and updated
  worked examples for Scenarios A / B / C. Drop every reference to
  "partial chain," "blocked," "benign," "bump through,"
  `--bump-only`, and `--bump-blocked`.
- `docs/cli/migrate.md`: rewrite the "Partial chains" subsection.
  Replace "exhausted tail" / "blocked tail" / "bump through" with
  the single window-walker rule. Show Scenario A as the canonical
  example. Remove the `--bump-only` flag entry from the flags
  table.
- `docs/cli/status.md`: update the per-row examples; remove the
  "Blocked:" and "Note: would bump through" rows.
- `docs/cli/run.md`: remove the `--bump-blocked` flag table entry
  (line 36 ish). Rewrite the "Partial chain," "Blocked," and
  "Recovering from blocked migrations" sections (lines 70-160 ish)
  as a single "Pending migrations" section with the new collapsed
  semantic. Drop every example transcript that prints "Blocked:"
  or names `--bump-only` / `--bump-blocked`.
- `docs/cli/upgrade.md`: update the post-upgrade advisory examples
  (lines 50-55 ish) to drop `--bump-only`. The new advisory
  points the user at `seihou migrate <name>`.
- `docs/user/migrations.md`: rewrite the user concept guide. This
  is the canonical end-user reference. Cover: declaring a migration
  in `module.dhall`, the window walker semantic in plain English,
  worked examples for Scenarios A / B / C, conflict-detection
  contract (unchanged), and an unambiguous "what `seihou migrate`
  does" recipe. Drop every mention of "partial chain," "blocked,"
  "benign," "bump-through," `--bump-only`, and `--bump-blocked`.
- `docs/user/CHANGELOG.md`: add an entry under the next release
  version. Suggested wording:

      ### Changed
      - The migration planner now applies every declared migration
        whose version range falls inside [installed, target], in
        ascending order, skipping versions that have no declared
        migration. The manifest always advances to the target
        version after `seihou migrate` completes. The previous
        "partial chain" / "blocked migration" / "benign upgrade" /
        "bump-through" outcomes are unified under a single
        `MigrateApplied` result; their corresponding advisory
        messages have been removed.

      ### Removed
      - The `--bump-only` flag (`seihou migrate`) and the
        `--bump-blocked` flag (`seihou run`) are removed. Default
        `seihou migrate` and `seihou run --with-migrations` now
        advance the manifest even when no migration ops apply,
        making both flags redundant. Scripts that relied on them
        should drop the flag and call the default invocation.
      - The `MigrationGap` and `MigrationOvershoot` planner errors
        are removed. Partial coverage is no longer an error;
        overshoots are silently skipped.
      - The JSON output's `unreachable`, `bumpedThrough`, and
        `manifestVersion` keys are removed; consumers should read
        `to` (the manifest's new version) and inspect `steps`
        directly.

- `docs/masterplans/1-migrations-dx.md`: append a closing entry
  noting that EP-35 supersedes the EP-23 / EP-24 / EP-25 / EP-27 /
  EP-28 sequence and replaces their plan-shape vocabulary with a
  single uniform contract.

Acceptance for M6:

- `cabal --enable-tests test all` passes.
- `nix flake check` passes.
- The live fixture transcript matches the Scenario A "after"
  transcript in this plan's Purpose section.
- `seihou help migrations` (run from the rebuilt binary) prints
  the new content embedded from `seihou-cli/help/migrations.md`.
  Verify with: `cabal run seihou -- help migrations | head -40`.
- `git status` is clean.
- A grep across `seihou-cli/`, `seihou-core/`, and `docs/cli/`,
  `docs/user/`, and `seihou-cli/help/` for the strings
  `bump[-_](only|blocked)`, `partial chain`, `blocked migration`,
  `benign upgrade`, `bump.*through`, `MigrationGap`,
  `MigrationOvershoot`, `MigrationChain`, `planUnreachable`,
  `planMigrationsDeclared`, `planTailExhausted`,
  `MigrateAppliedPartial`, `MigrateAppliedBumpedThrough`,
  `MigrateBlocked`, `MigrateBenignUpgrade`,
  `MigrateDryRunOKPartial`, `MigrateDryRunOKBumpedThrough`,
  `isBenignUpgrade`, `isBlockedMigration`, or `isBumpedThrough`
  returns zero matches except in `docs/user/CHANGELOG.md` (the
  removal note) and the historical `docs/plans/{13,15,16,17,
  23,24,25,26,27,28}-*.md` and `docs/masterplans/1-migrations-dx.md`
  (historical records of the work this plan supersedes).

Commit at the end of M6.


## Concrete Steps

The build path is fixed across milestones:

    cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
    cabal build all

The binary lands at:

    dist-newstyle/build/aarch64-osx/ghc-9.12.2/seihou-cli-0.1.0.0/x/seihou/build/seihou/seihou

(Substitute platform / GHC components as needed.)

Test commands per milestone:

- M1 (planner only):

      cabal --enable-tests test seihou-core:test:seihou-core-test \
        --test-show-details=streaming

- M2-M5 (full CLI):

      cabal --enable-tests test all \
        --test-show-details=streaming

- Single-spec run:

      cabal --enable-tests test seihou-cli:test:seihou-cli-test \
        --test-show-details=streaming \
        --test-options='--match "Seihou.CLI.Migrate"'

To rebuild the live fixture from scratch (M6):

    rm -rf /tmp/seihou-walker-repro
    mkdir -p /tmp/seihou-walker-repro/{installed,project/.seihou}

    cat > /tmp/seihou-walker-repro/installed/module.dhall <<'DHALL'
    let MigrationOpUnion =
          < MoveFile : { src : Text, dest : Text }
          | MoveDir : { src : Text, dest : Text }
          | DeleteFile : { path : Text }
          | DeleteDir : { path : Text }
          | RunCommand : { run : Text, workDir : Optional Text }
          >
    in
    { name = "foo"
    , version = Some "0.6"
    , description = None Text
    , vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }
    , exports = [] : List { var : Text, alias : Optional Text }
    , prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }
    , steps = [] : List { strategy : Text, src : Text, dest : Text, when : Optional Text, patch : Optional Text }
    , commands = [] : List { run : Text, workDir : Optional Text, when : Optional Text }
    , dependencies = [] : List { module : Text, vars : List { name : Text, value : Text } }
    , removal = None { steps : List { action : Text, dest : Text, src : Optional Text }, commands : List { run : Text, workDir : Optional Text, when : Optional Text } }
    , migrations =
        [ { from = "0.2"
          , to = "0.3"
          , ops = [ MigrationOpUnion.MoveFile { src = "v2.txt", dest = "v3.txt" } ]
          }
        , { from = "0.5"
          , to = "0.6"
          , ops = [ MigrationOpUnion.MoveFile { src = "v5.txt", dest = "v6.txt" } ]
          }
        ]
    }
    DHALL

    echo at-v2 > /tmp/seihou-walker-repro/project/v2.txt
    echo at-v5 > /tmp/seihou-walker-repro/project/v5.txt
    HASH_V2=$(printf 'at-v2\n' | shasum -a 256 | awk '{print $1}')
    HASH_V5=$(printf 'at-v5\n' | shasum -a 256 | awk '{print $1}')

    cat > /tmp/seihou-walker-repro/project/.seihou/manifest.json <<JSON
    { "version": 2
    , "generatedAt": "2026-05-08T10:00:00Z"
    , "modules": [{ "name": "foo"
                  , "source": "/tmp/seihou-walker-repro/installed"
                  , "version": "0.2"
                  , "appliedAt": "2026-05-08T10:00:00Z" }]
    , "variables": {}
    , "files": { "v2.txt": { "hash": "$HASH_V2"
                           , "module": "foo"
                           , "strategy": "template"
                           , "generatedAt": "2026-05-08T10:00:00Z" }
               , "v5.txt": { "hash": "$HASH_V5"
                           , "module": "foo"
                           , "strategy": "template"
                           , "generatedAt": "2026-05-08T10:00:00Z" } }
    }
    JSON

(Note: the fixture pretends two files exist that "0.2 → 0.3" and
"0.5 → 0.6" both rename. Realistically the user's project will not
have both files at once when manifest=0.2; the fixture uses both so
that both rename ops have something to operate on. This is an
intentional artefact of the synthetic fixture, not a bug.)

Run from the project dir:

    cd /tmp/seihou-walker-repro/project
    SEIHOU=/Users/shinzui/Keikaku/bokuno/seihou-project/seihou/dist-newstyle/build/aarch64-osx/ghc-9.12.2/seihou-cli-0.1.0.0/x/seihou/build/seihou/seihou
    "$SEIHOU" migrate foo --no-fetch

Expected transcript (Scenario A from the Purpose section):

    Migration plan: foo  0.2 → 0.6
      0.2 → 0.3:
        move-file v2.txt -> v3.txt
      0.5 → 0.6:
        move-file v5.txt -> v6.txt

    2 operation(s), 0 conflict(s).

    ✓ Migrated foo 0.2 → 0.6.

Then verify the manifest landed at 0.6:

    jq '.modules[] | select(.name=="foo") | .version' \
      /tmp/seihou-walker-repro/project/.seihou/manifest.json
    # Expected: "0.6"


## Validation and Acceptance

The plan is complete when:

1. The planner's exported types are exactly `Migration`, `MigrationOp`,
   `MigrationPlan` (the new flat record), `MigrationPlanError`, and
   `planMigrationChain`. `MigrationChain`, `planUnreachable`,
   `planMigrationsDeclared`, and `planTailExhausted` are gone.
2. The CLI's `MigrateResult` ADT has exactly three constructors:
   `MigrateNoOp`, `MigrateApplied`, `MigrateDryRunOK`.
3. The `--bump-only` flag is gone from the parser, the handler, the
   docs, and the test suite.
4. Every CLI consumer (`StatusRender`, `PendingMigrations`, `Run`,
   `Upgrade`) has at most a single branch on
   `null plan.planSteps` or `plan.planFrom == plan.planTo` for the
   pending-migration display logic.
5. The live fixture at `/tmp/seihou-walker-repro/project/` produces
   the Scenario A transcript with one `seihou migrate foo --no-fetch`
   invocation and lands the manifest at `0.6`.
6. `cabal --enable-tests test all` and `nix flake check` both pass.
7. `docs/cli/migrate.md`, `docs/cli/status.md`,
   `docs/user/CHANGELOG.md`, and
   `docs/masterplans/1-migrations-dx.md` are updated.
8. A grep across the `seihou-cli` package for the strings
   `bump.*through`, `blocked migration`, `benign.*upgrade`,
   `planUnreachable`, `planMigrationsDeclared`,
   `planTailExhausted`, `MigrationChain`, `MigrationGap`,
   `MigrationOvershoot`, `MigrateAppliedPartial`,
   `MigrateAppliedBumpedThrough`, `MigrateBlocked`,
   `MigrateBenignUpgrade`, or `MigrateDryRunOKPartial` returns zero
   non-comment, non-CHANGELOG matches.

A reviewer reading the final diff should be able to point at:

- The new planner (M1; ~30 lines of Haskell, including comments).
- The collapsed `MigrateResult` and `dispatchPlan` (M2).
- The `--bump-only` deletion (M3; mechanical).
- The four consumer simplifications (M4; mechanical).
- The retuned EP-27 fallback (M5; ~15 lines).
- The CHANGELOG entry, masterplan closing note, and migrate.md
  rewrite (M6).

…and nothing else. Do not refactor the engine layer
(`seihou-core/src/Seihou/Engine/Migrate.hs`) beyond what M2 requires
(making `executeMigration` work cleanly with empty-step plans, if it
doesn't already). Do not touch the Dhall schema for migrations. Do
not change `seihou run`'s default-no-`--with-migrations` refusal
contract — that's orthogonal and EP-23 settled it correctly.


## Idempotence and Recovery

Every step in this plan is safe to repeat:

- The hand-rolled fixture lives entirely under
  `/tmp/seihou-walker-repro/` and can be rebuilt from the heredocs in
  Concrete Steps.
- `cabal build` and `cabal test` are idempotent.
- The new regression tests use `withSystemTempDirectory` (existing
  helper) and clean up after themselves.

If a milestone's commit lands in a broken state (test fails after a
clean checkout, or `nix flake check` fails on the CLI module-placement
script), `git revert` the commit and reattempt from the previous
known-good HEAD. Do not amend or force-push.

If the test suite shows persistent failures across multiple specs after
M2, consider that the dispatch refactor accidentally drifted from
`executeMigration`'s precondition: the engine's `executeMigration`
expects a non-empty step list in some code paths. Read
`seihou-core/src/Seihou/Engine/Migrate.hs:162-197` and check whether
the empty-step case needs an explicit early-return inside
`applyOrDryRun` (call `replaceModuleVersion` directly instead of
routing through `executeMigration`). Document the finding in
Surprises & Discoveries.

If `nix flake check` fails because of the CLI module-placement check
(`nix/check-cli-module-placement.sh`), trace the offending module's
imports per `CLAUDE.md`'s "CLI Module Placement (library-first)"
section. This plan should not move modules across the
`seihou-cli/src/` ↔ `seihou-cli/src-exe/` boundary; failures there
indicate something accidentally drifted.


## Interfaces and Dependencies

This plan changes two public types and removes three:

- **Changed:** `Seihou.Core.Migration.MigrationPlan` is rewritten with
  fields `planModule`, `planFrom`, `planTo`, `planSteps`. Old fields
  `planChain`, `planUnreachable`, `planMigrationsDeclared`,
  `planTailExhausted` are removed.
- **Changed:** `Seihou.Core.Migration.MigrationPlanError` loses
  `MigrationGap` and `MigrationOvershoot`. The remaining variants are
  `MigrationVersionUnparseable`, `MigrationDowngradeNotSupported`,
  `MigrationDuplicateEdge`.
- **Changed:** `Seihou.CLI.Migrate.MigrateResult` is rewritten with
  variants `MigrateNoOp`, `MigrateApplied`, `MigrateDryRunOK`.
- **Removed:** `Seihou.Core.Migration.MigrationChain` (folded into
  `MigrationPlan`).
- **Removed:** `Seihou.CLI.PendingMigrations.isBenignUpgrade`,
  `isBlockedMigration`, `isBumpedThrough` (no caller after M4).

These signatures stay identical:

- `Seihou.Core.Migration.planMigrationChain :: Text -> [Migration] ->
  Version -> Version -> Either MigrationPlanError (Maybe MigrationPlan)`
  (the body changes; the signature is preserved so that callers
  recompile cleanly.)
- `Seihou.CLI.Migrate.runMigrate :: MigrateOpts -> Manifest ->
  FilePath -> IO (Either MigrateError MigrateResult)`
  (the result variants change; the signature is preserved.)

Tests use the helpers already exported by
`seihou-cli/test/Seihou/CLI/MigrateSpec.hs`:

- `writeInstalledModule :: FilePath -> Text -> Text -> IO ()`
- `mkManifest :: Text -> FilePath -> [(FilePath, Text)] -> Manifest`
- `defaultOpts :: MigrateOpts`
- `withFetchFixture :: Text -> Text -> Text ->
  (FetchFixture -> IO ()) -> IO ()`

If `defaultOpts` carries `migrateBumpOnly = False` today, M3 removes
that field and any test reaches that record's update syntax must drop
the field too.

The Dhall schema for migrations (`schema/Migration.dhall`,
`schema/MigrationOp.dhall`) does not change. The decoder in
`seihou-core/src/Seihou/Dhall/Eval.hs:167-232` does not change. The
filesystem-execution code in
`seihou-core/src/Seihou/Engine/Migrate.hs` does not change unless M2
discovers an empty-step precondition (see Idempotence and Recovery).

The `seihou run` default-no-`--with-migrations` refusal contract
(EP-23) is unchanged. The conflict-detection contract (file edited by
user, refuse without `--force`) is unchanged. The EP-15 "freshest
content from clone" intent is unchanged: the clone is still the
source of truth for templates and the `version` field; only the
fallback trigger condition changes (M5).


## Revision History

- **2026-05-08 (initial)**: Plan created (six milestones; window
  walker + collapsed `MigrateResult` + `--bump-only` removal +
  consumer simplification + EP-27 fallback retune + docs).
- **2026-05-08 (post-review revision)**: User asked to ensure agent
  context and help guides are covered. Expanded the plan to:
  (1) enumerate every user-visible surface in Context and
  Orientation (embedded `seihou help migrations` topic; CLI refs
  for `migrate`, `status`, `run`, `upgrade`; user concept guide;
  CHANGELOG; masterplan; in-source comments and refusal-message
  strings); (2) record the negative finding that
  `agents/skills/`, `claude/skills/`, and the historical EP-13/15/
  16/17/23/24/25/26/27/28 plans need no edits; (3) fold the
  `--bump-blocked` flag into M3 alongside `--bump-only` (the two
  are siblings; both vocabulary surfaces collapse together);
  (4) extend M4 to cover the user-facing refusal-message strings
  in `Run.hs`, `PendingMigrations.hs`, `StatusRender.hs`, and
  `Upgrade.hs`; (5) extend M6 docs to include
  `seihou-cli/help/migrations.md`, `docs/cli/run.md`,
  `docs/cli/upgrade.md`, and `docs/user/migrations.md`; (6) tighten
  the M6 acceptance criteria with a comprehensive grep checklist.
  Decision Log gains three new entries (`--bump-blocked` removal,
  agent-skill negative finding).
