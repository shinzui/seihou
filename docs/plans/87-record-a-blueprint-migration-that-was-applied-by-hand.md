---
id: 87
slug: record-a-blueprint-migration-that-was-applied-by-hand
title: "Record a blueprint migration that was applied by hand"
kind: exec-plan
created_at: 2026-08-17T03:18:12Z
intention: intention_01m26cpw67eens6yw0dz028ryj
provenance:
  revisions:
    - model: "claude-opus-5"
      harness: "claude-code"
      at: 2026-09-10T19:29:37Z
      mode: "implement"
      note: "Refreshed the stale next-free-ADR-number claim, added an intention, and began implementation"
---

# Record a blueprint migration that was applied by hand

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

A **blueprint migration** is an agent-guided upgrade step that a library author ships with
their blueprint: one Markdown prompt per version edge, run by
`seihou agent migrate <blueprint>`, which starts one AI agent session per edge and writes a
**receipt** into `.seihou/manifest.json` after each session returns. The receipt is what
stops a later run from repeating work that is already done.

Plenty of people upgrade a library by hand. They read the release notes, make the changes
themselves, and never run `seihou agent migrate` at all. Today seihou has no way to be told
that. There is exactly one code path that writes a migration receipt — inside the migrate
run, after a provider session returns — so a project that upgraded by hand has no receipt,
and no supported way to create one.

The workarounds all fail in a different way. Hand-editing `.seihou/manifest.json` requires
guessing the artifact's `origin` correctly, and a wrong guess produces a receipt that matches
nothing. Running `seihou agent migrate` anyway spends a real provider session — money and
minutes — to discover there is nothing to do. Widening `--from` past the edge skips it but
records nothing, so the edge is never "done". Letting the agent report the edge
"not applicable" records an outcome that, by design, does *not* suppress a later run.

After this plan, a user who has already done the work says so, and seihou believes them:

```bash
seihou agent migrate keiro-upgrade --mark-applied
```

```text
Version window: 2.4.0 -> 3.0.0
  --from 2.4.0  [receipt: keiro-upgrade 2.0.0 -> 2.4.0, applied 2026-08-02]
  --to   3.0.0  [probe: nix eval --raw .#keiroVersion]

Marking 2 blueprint migration(s) as already applied, without running them:
  kiroku-upgrade 1.9.0 -> 2.0.0 (entailed by keiro-upgrade 2.4.0 -> 3.0.0)
  keiro-upgrade 2.4.0 -> 3.0.0

Recorded 2 receipt(s). No agent session was started and no file was changed.
```

Running `seihou agent migrate keiro-upgrade` afterwards reports that every edge in the window
already has a receipt, and exits without contacting a provider.

The flag is deliberately attached to the existing command rather than given a command of its
own, because that command already knows the four things a correct receipt needs: which
blueprint the name resolves to on this machine, what its portable origin is, which edges fall
inside the version window, and — under entailment — which *other* blueprint actually owns each
edge. A separate `seihou manifest record-migration` would have to re-derive all four, and
getting origin wrong is precisely the failure that makes a hand-written receipt useless.


## Progress

- [x] Milestone 1 — add `--mark-applied` to `BlueprintMigrationOpts` and its parser, and reject the flag combinations that cannot mean anything. (2026-09-10)
- [x] Milestone 2 — record receipts for the pending steps without launching a provider, in `handleAgentMigrate`. (2026-09-10)
- [x] Milestone 3 — report what was marked, and make the no-op and refusal messages readable. (2026-09-10)
- [x] Milestone 4 — unit tests for the pure marking summary and the flag-conflict rules. (2026-09-10; flag-conflict rules are covered end-to-end in Milestone 5 as the plan anticipated, since the checks live in `src-exe`.)
- [x] Milestone 5 — end-to-end tests: marking writes receipts, suppresses a later run, starts no session, and touches no file. (2026-09-10)
- [x] Milestone 6 — documentation: new sections in `docs/user/blueprint-migrations.md` and `docs/cli/agent.md`, the summary pages in `docs/user/migrations.md` and `docs/user/blueprints.md`, the in-binary help topic, and `docs/user/CHANGELOG.md`. (2026-09-10; the grep found three more files the plan did not name — see Surprises.)
- [x] Milestone 7 — ADR pass: record the decision that a receipt asserts a claim about the project rather than proof of an agent session. (2026-09-10; new record `docs/adr/0011-a-migration-receipt-asserts-a-claim-about-the-project.md`.)


## Surprises & Discoveries

- **2026-09-10 — the ADR corpus moved under the plan.** Milestone 7 said the next free ADR
  number was `0010` and that the corpus ended at `0009`. Between the plan being written on
  2026-08-17 and implementation starting, `docs/adr/0010-generated-documentation-is-checked-before-it-is-written.md`
  landed (commit `6745c54`). The next free number is `0011`. This is exactly why the plan told
  the implementer to list `docs/adr/` rather than trust the sentence; the sentence has now been
  corrected too.
  Everything else the plan asserts about the working tree was re-verified and still holds:
  `BlueprintMigrationOpts` has the fourteen fields listed in Interfaces and Dependencies,
  `agentMigrateParser` is positional in the order shown, the `if null pending` branch in
  `handleAgentMigrate` has the shape quoted in Milestone 2, `recordMigration` looks the owner up
  in the cohort exactly as quoted, `formatMigrationStepLabel` and `pendingBlueprintMigrations`
  are exported from `seihou-cli/src/Seihou/CLI/BlueprintMigration.hs`, the test fixtures `first`,
  `second`, `entailedStep`, `withProbeProject`, `withCohortProject` and `probeBlueprintDhall`
  all exist, `mori.dhall` still registers `docs/improvement-requests` as its only OKF bundle, and
  every documentation file named in Milestone 6 is present.


- **2026-09-10 — the fixtures could not prove a session did not start.** Milestone 5 said "the
  fake `claude` in these fixtures appends a line to a log file each time it is called", and that
  asserting the log's absence proves nothing ran. That was true of the two *inline* fixtures in
  `seihou-cli/test/Seihou/CLI/AgentMigrateE2ESpec.hs` (the ones that set `SEIHOU_FAKE_AGENT_LOG`),
  but not of the two helpers the plan named: `withProbeProject` and `withCohortProject` both wrote
  `#!/bin/sh\nexit 0\n`, a fake that succeeds silently and records nothing. Asserting an absent log
  against that fake would have passed whether or not a session started — a test that proves
  nothing while appearing to prove the central claim.
  Both helpers now write the logging fake and set `SEIHOU_FAKE_AGENT_LOG` to
  `<root>/agent-launch.log`. Existing tests using them are unaffected; they never read the log.

- **2026-09-10 — the documentation grep paid for itself three times over.** Milestone 6 named
  six files. Running `rg -n "agent migrate|blueprint migration|receipt" docs/ seihou-cli/help/`
  as the plan insisted turned up three more that assert what a receipt means and would have
  silently gone stale — precisely the drift
  `docs/masterplans/10-blueprint-migration-fan-out-across-a-library-cohort.md` recorded as its
  lesson:
  - `seihou-cli/help/blueprints.md` — "A receipt records agent completion, not proof that a
    package manager now reports the target version."
  - `seihou-cli/help/migrations.md` — "A receipt means the agent interaction completed
    successfully."
  - `docs/cli/status.md` — "`applied` means the provider interaction for that edge returned".

  All three now say a receipt records that an edge has been dealt with, by a session returning
  or by the consumer marking it. Two of the three are in-binary help topics, which is the
  category the plan already flagged as easy to forget because it is not under `docs/`.

## Decision Log

- Decision: Implement this as a flag on `seihou agent migrate` rather than as a new
  `seihou manifest record-migration` subcommand.
  Rationale: A correct receipt needs the blueprint's resolved `ArtifactOrigin`, the planned
  version window, and — under entailment — the identity of the blueprint that *owns* each
  edge rather than the one the user named. `handleAgentMigrate` in
  `seihou-cli/src-exe/Seihou/CLI/AgentMigrate.hs` already computes all three, and
  `docs/adr/0008-an-entailed-migration-edge-is-owned-by-the-blueprint-that-declares-it.md`
  makes ownership load-bearing for correctness. A standalone subcommand would duplicate that
  resolution, and every duplicate is an opportunity to write a receipt whose origin matches
  nothing. The cost is one more flag on a command that already has thirteen.
  Date: 2026-08-17

- Decision: Marking records the outcome `MigrationApplied`, and does not introduce a third
  outcome such as "applied by hand".
  Rationale: `docs/adr/0007-a-deliberate-no-op-is-a-third-outcome-not-a-success.md` makes the
  outcome vocabulary durable project context, so adding a value needs real justification. There
  is none here. A receipt already means "this edge has been attended to and need not run again"
  rather than proof that an agent did it — `docs/user/blueprint-migrations.md` is explicit that
  a receipt records that a provider interaction returned, not that the build passes. A hand
  migration satisfies that meaning exactly. Recording it as a distinct outcome would also force
  every existing reader of `outcome` to decide what the new value means to it, for no gain.
  See Milestone 7, which records this reasoning as an ADR because it settles what a receipt
  *asserts*.
  Date: 2026-08-17

- Decision: `--mark-applied` marks every pending step in the resolved window, including steps
  owned by other blueprints reached through `entails`, rather than requiring one edge at a time.
  Rationale: The alternative — an `--edge FROM:TO` selector — was considered and rejected as the
  wrong default. Someone who upgraded a library by hand upgraded *the library*, across whatever
  edges the window contains; asking them to enumerate edges they never saw individually is
  busywork, and enumerating an entailed edge means knowing about a blueprint they may never have
  heard of. The window is already the unit the command works in, and `--from` / `--to` already
  narrow it precisely, so a user who genuinely wants one edge can ask for exactly that window.
  Date: 2026-08-17

- Decision: Marking is scoped to *pending* steps and silently skips steps that already have an
  applied receipt, rather than rewriting every step in the window.
  Rationale: Rewriting an existing receipt would move its `appliedAt` timestamp for work that
  was recorded honestly at a different time, destroying audit information to no purpose. The
  existing planner already computes exactly the pending set, so scoping to it is also the
  smaller change.
  Date: 2026-08-17


- Decision: The two flag-conflict refusals print a `✗` block to stdout and exit non-zero,
  rather than going through `exitErr` (which writes to stderr behind a `[error] ` prefix).
  Rationale: `enforceArtifactGuard` in `seihou-cli/src/Seihou/CLI/ManifestGuard.hs` is this
  command's other refusal, and it already prints a multi-line `✗ Refusing to run …` block to
  stdout before `exitFailure`. Two refusal kinds from the same command on two different streams
  in two different shapes would be gratuitous. `exitErr`'s existing callers pass lowercase
  sentence fragments designed to read after `[error] `, which a multi-line indented block is
  not.
  Date: 2026-09-10

- Decision: Milestone 3's completion sentence is a separate exported function,
  `formatMarkAppliedSummary`, rather than a literal in the executable.
  Rationale: The plan placed only the notice in the library, but the test suites cannot import
  from `src-exe`, so a literal there is untestable. Both sentences are pure text derived from
  the step list, so both belong in `seihou-cli/src/Seihou/CLI/BlueprintMigration.hs`.
  Date: 2026-09-10

- Decision: Milestone 7's durable decision becomes a new record,
  `docs/adr/0011-a-migration-receipt-asserts-a-claim-about-the-project.md`, rather than an
  amendment to ADR 0007.
  Rationale: The plan's own rule — amend when the decision is unchanged and only its reach grew,
  write a new record when there is a rejected alternative the existing record has nowhere to put
  — points at a new record, and reading ADR 0007 confirms it. That record's subject is the
  *outcome vocabulary*: which values `MigrationOutcome` may take and what each means for
  suppression, the chain, and identity. This plan settles a different question — what a receipt
  *asserts*, and by what means it may come to exist — and it carries a rejected alternative, a
  distinct "applied by hand" outcome, that ADR 0007 has no section for. ADR 0007 gains a
  References entry pointing at 0011, which is how it already cross-references ADR 0008.
  Date: 2026-09-10

- Decision: Keep the plan's exact summary sentence, "No agent session was started and no file was
  changed.", even though the marking does write `.seihou/manifest.json`.
  Rationale: The sentence is about the working tree, which is what a user asserting "I already did
  this" is worried about, and the receipts it just announced are self-evidently the change it
  made. Qualifying it in the terminal ("no file other than the manifest") would trade the line's
  bluntness — the thing that makes a mistaken marking obvious — for precision the user does not
  need at that moment. The documentation carries the precise version instead:
  `docs/user/blueprint-migrations.md` says no file in the working tree is read or written and
  that the only change is the receipts appended to the manifest.
  Date: 2026-09-10

## Outcomes & Retrospective

Delivered as specified. `seihou agent migrate <blueprint> --mark-applied` records a receipt for
every pending edge in the resolved window, contacts no provider, and touches no file in the
working tree:

```text
Marking 1 blueprint migration(s) as already applied, without running them:
  scratch-upgrade 1.0.0 -> 2.0.0

Recorded 1 receipt(s). No agent session was started and no file was changed.
```

Every acceptance check in Validation and Acceptance was run by hand against a scratch project
built from `probeBlueprintDhall`, and all passed: `seihou status` lists the marked edge as
applied with today's date; a later ordinary run of the same window reports "already have
receipts" and exits zero with no provider on `PATH`; `--rerun` plans the edge again despite the
marked receipt; marking the wider `1.0.0 -> 3.0.0` window leaves the first edge's `appliedAt`
byte-identical while adding a receipt for `2.0.0 -> 3.0.0`; and both refusals exit non-zero
naming each conflicting flag with no manifest left behind.

Automated: `cabal test seihou-core-test` and `cabal test seihou-cli-test` both pass (572 CLI
tests, up from 566 before the end-to-end cases). `nix flake check` passes, including the
module-placement and record-convention checks. The decisive assertions are the cohort case —
marking `keiro-upgrade 2.4.0 -> 3.0.0` files receipts under `kiroku-upgrade` and
`keiro-upgrade` separately, and the entailed receipt then suppresses a direct `kiroku-upgrade`
run — and the no-session assertion, which only became real evidence after the fixture fix
recorded in Surprises & Discoveries.

Three things are worth carrying forward.

**The plan's instruction to grep the documentation tree rather than the expected file list was
the single highest-value line in it.** It found three files the plan had not named, two of them
in-binary help topics outside `docs/`, each asserting that a receipt means an agent session
completed. Without the grep this change would have shipped the same drift the preceding
initiative spent six plans accumulating.

**A test fixture that cannot fail is worse than a missing test.** The plan's proposed
no-session assertion — that the fake provider's log is absent — would have passed unconditionally
against the two helpers it named, because their fake `claude` was `exit 0` and wrote no log. The
assertion would have looked like the proof of the plan's central claim while proving nothing.
Checking what a fixture actually does before relying on it is not optional.

**Scoping the operation to the pending set, rather than to the window, is what makes the command
idempotent for free.** No separate guard against rewriting an existing receipt was needed: the
planner's existing filter already computes exactly the right set. That was recorded as a
decision at planning time rather than discovered during implementation, and it paid off.

The plan needed one correction before implementation: it claimed the next free ADR number was
`0010`, which another change had taken in the meantime. The plan itself told the implementer to
verify by listing `docs/adr/` rather than trusting the sentence, so the stale claim cost
nothing.

The related gap named in Context and Orientation — that seihou never tells a user a blueprint
migration is *pending* — remains open and is still worth its own plan. This plan was the
prerequisite: with `--mark-applied` in place, a future discovery feature can list a pending
migration without manufacturing a false positive that a hand-upgraded project has no way to
dismiss.


## Context and Orientation

### What this repository is

Seihou is a project scaffolding system written in Haskell. It is a Cabal workspace with three
packages: `seihou-core` (a library, at `seihou-core/`), `seihou-cli` (at `seihou-cli/`), and
`seihou-okf-extension` (not touched by this plan). The `seihou-cli` package is split into a
library at `seihou-cli/src/` (the Cabal component is named `seihou-cli-internal`) and an
executable at `seihou-cli/src-exe/`.

New code goes in a library by default. The executable target is reserved for `Main.hs`,
command dispatchers, and modules that genuinely need one of `Options.Applicative`,
`Data.FileEmbed`, `GitHash`, or `Paths_seihou_cli` — plus anything that transitively imports
such a module. A shell script, `nix/check-cli-module-placement.sh`, enforces this and runs in
both `nix flake check` and the pre-commit hook, so a misplaced module fails the build rather
than merely being bad style.

The practical consequence for this plan: the code that *decides* what to mark and what to
print is pure and belongs in `seihou-cli/src/Seihou/CLI/BlueprintMigration.hs`. The code that
writes to the manifest is IO and is called from
`seihou-cli/src-exe/Seihou/CLI/AgentMigrate.hs`. There is a second, sharper reason to prefer
the library: **the test suites cannot import from `src-exe` at all**, so any behaviour placed
in the executable cannot be unit-tested.

Records in this repository are defined with strict fields (a `!` on every field of a `data`
record), an explicit deriving strategy, and `Generic` in the derive list. Fields are read and
written through `generic-lens` overloaded labels — `opts ^. #from` to read,
`state & #status .~ Active` to write — never through record dot syntax and never through
record update syntax. Any module using a `#label` must add `import Data.Generics.Labels ()`
itself. A second script, `nix/check-record-conventions.sh`, enforces this the same way.

### The command as it stands today

`seihou agent migrate` is defined by `BlueprintMigrationOpts` in
`seihou-cli/src-exe/Seihou/CLI/Commands.hs`:

```haskell
data BlueprintMigrationOpts = BlueprintMigrationOpts
  { name :: !ModuleName,
    from :: !(Maybe Text),
    to :: !(Maybe Text),
    prompt :: !(Maybe Text),
    vars :: ![(Text, Text)],
    namespace :: !(Maybe Text),
    context :: !(Maybe Text),
    verbose :: !Bool,
    rerun :: !Bool,
    provider :: !(Maybe Text),
    model :: !(Maybe Text),
    effort :: !(Maybe Text),
    trace :: !(Maybe Text),
    allowDowngrade :: !Bool
  }
  deriving stock (Eq, Show, Generic)
```

Its parser is `agentMigrateParser`, near the bottom of the same file. That parser is
*positional*: the order of the applicative combinators must match the order of the record
fields exactly, or the code compiles and silently assigns the wrong values to the wrong
fields. Read both after editing.

The handler is `handleAgentMigrate` in `seihou-cli/src-exe/Seihou/CLI/AgentMigrate.hs`. Its
current shape, in order:

1. Compute the log level and the manifest path (`.seihou/manifest.json`).
2. Discover and validate the named blueprint, producing a `CohortBlueprint` — a record holding
   the decoded blueprint, its directory on disk, and its `ArtifactOrigin`.
3. Unless `--debug` was passed, call `enforceAgentArtifactGuard` for the invoked blueprint.
4. Resolve the agent provider, model, and effort.
5. Read the migration receipts from the manifest.
6. Resolve the version window (`resolveWindow`), possibly running the blueprint's declared
   version probe, and print what was inferred.
7. Plan the chain with `planBlueprintMigrationChain`.
8. Resolve the *cohort*: every blueprint reachable through `entails` from the planned steps.
9. Guard those entailed blueprints too.
10. Expand entailed edges into a flat, ordered list of `BlueprintMigrationStep`.
11. Filter out steps that already have a receipt, via `pendingBlueprintMigrations`.
12. If nothing is pending, print a message and stop. Otherwise prepare one execution context
    per owning blueprint (resolving that blueprint's variables, which may prompt the user),
    then either print every prompt (`--debug`) or run the chain with
    `runBlueprintMigrationsWith`.

This plan inserts a branch after step 11 and before step 12's preparation work, because
resolving execution contexts prompts for variables and mounts reference files — all of which
are pointless when no session will start.

### What a receipt is, and how one is written

The receipt type is `AppliedBlueprintMigration` in `seihou-core/src/Seihou/Core/Types.hs`:

```haskell
data AppliedBlueprintMigration = AppliedBlueprintMigration
  { name :: !ModuleName,
    origin :: !ArtifactOrigin,
    blueprintVersion :: !(Maybe Text),
    fromVersion :: !Text,
    toVersion :: !Text,
    outcome :: !MigrationOutcome,
    appliedAt :: !UTCTime,
    agentSessionId :: !(Maybe Text)
  }
  deriving stock (Eq, Show, Generic)
```

`MigrationOutcome`, in the same file, has two constructors: `MigrationApplied`, and
`MigrationNotApplicable !Text` carrying a reason.

On disk, one receipt looks like this — copied from a real `.seihou/manifest.json` produced by
running the command in a scratch project:

```json
{
  "appliedAt": "2026-08-16T20:59:32.443203Z",
  "from": "1.0.0",
  "name": "scratch-upgrade",
  "origin": {
    "kind": "project",
    "path": ".seihou/modules/scratch-upgrade"
  },
  "outcome": {
    "status": "applied"
  },
  "to": "2.0.0",
  "version": "3.0.0"
}
```

Note that the JSON keys are not all identical to the Haskell field names (`from`, `to`, and
`version` rather than `fromVersion`, `toVersion`, and `blueprintVersion`). This is why
hand-editing the manifest is a poor workaround and why this plan exists.

Receipts are written by `recordAppliedBlueprintMigration` in
`seihou-cli/src/Seihou/CLI/AppliedBlueprintMigration.hs`, which reads the manifest, upserts
one receipt, and writes it back atomically. A corrupt existing manifest is reported and left
untouched rather than replaced. **This function already does everything this plan needs; it is
called with a different trigger, not modified.** Its single production caller today is
`recordMigration` in `seihou-cli/src-exe/Seihou/CLI/AgentMigrate.hs`, which runs only after a
provider session returns.

The upsert itself is `writeAppliedBlueprintMigration` in
`seihou-core/src/Seihou/Manifest/Types.hs`. It replaces a receipt for the same edge in place
rather than appending a duplicate, where "same edge" means the same artifact identity, name,
`from`, and `to` — deliberately *ignoring* the outcome, so an edge that reported itself not
applicable and later runs for real replaces its own receipt.

### Why "which blueprint owns the edge" matters here

A migration edge may declare that crossing it **entails** crossing an exact edge of another
blueprint. That is how a breaking change reaches consumers who depend on the library that
absorbed it rather than the library that shipped it. One command can therefore cross edges
belonging to several different blueprints.

Each step's receipt is written under the identity of the blueprint that *declares* the edge,
not the blueprint named on the command line. This is what makes a shared edge crossed exactly
once from either entry point. The mechanism is `recordMigration` in
`seihou-cli/src-exe/Seihou/CLI/AgentMigrate.hs`, which looks the step's `owner` up in the
cohort map to find the right name and origin:

```haskell
recordMigration manifestPath cohort step migrationOutcome =
  case Map.lookup (step ^. #owner) cohort of
    Nothing -> pure (Left (missingOwnerMessage step))
    Just owner -> do
      now <- getCurrentTime
      recordAppliedBlueprintMigration
        manifestPath
        AppliedBlueprintMigration
          { name = owner ^. #blueprint . #name,
            origin = owner ^. #origin,
            ...
          }
```

**This plan must reuse `recordMigration` rather than writing a second receipt-construction
site.** Duplicating it would create exactly the divergence risk the ownership rule exists to
prevent.

### Relevant ADRs

`docs/adr/` in this repository is a plain filesystem corpus, not a profile-governed OKF
bundle — `mori.dhall` registers exactly one bundle, and it is `docs/improvement-requests`.
New or revised ADRs therefore follow the established convention: one file per decision named
`NNNN-slug.md`, a `# ADR NNNN — Title` heading, and `Status` / `Date` lines. Do not add OKF
frontmatter, do not run `okf id next` against `docs/adr`, and do not allocate a Mori handle
for an ADR as an incidental edit.

Four local records matter to this work.

`docs/adr/0002-artifact-identity-is-origin-url-plus-name.md` decides that an artifact's
identity in the manifest is its origin URL plus its name, and explicitly rejects a bare name as
an identity because two registries can publish the same name. Everything in this plan that
touches a receipt must respect that: a receipt written with the wrong origin matches nothing
and is worse than no receipt at all.

`docs/adr/0004-the-manifest-is-the-only-record-of-applied-state.md` decides there is no
lockfile and that `.seihou/manifest.json` is the single record of what has been applied. This
plan adds no new state file; it writes the same receipts through the same function.

`docs/adr/0007-a-deliberate-no-op-is-a-third-outcome-not-a-success.md` decides that an edge
which deliberately does nothing records a distinct `not applicable` outcome rather than being
recorded as a success, and treats the recorded outcome vocabulary as durable. That is the
record this plan must *not* casually extend: see the Decision Log for why marking records
`MigrationApplied` instead of inventing a third value.

`docs/adr/0008-an-entailed-migration-edge-is-owned-by-the-blueprint-that-declares-it.md`
decides that an entailed edge is owned by the blueprint whose `migrations` list declares it,
and that ownership decides which identity the receipt is written under. This is why the plan
reuses `recordMigration` rather than constructing receipts directly.

No cross-repository ADR governs blueprint migration receipts. This was checked when
`docs/masterplans/10-blueprint-migration-fan-out-across-a-library-cohort.md` was written: the
Mori registry hits for "migration" and "artifact identity" were about database migration
histories and are not relevant.

There is no Improvement Request behind this plan. It originates from a gap found while closing
`docs/plans/86-infer-the-blueprint-migration-version-window.md`.

### A related gap this plan deliberately does not close

Seihou never tells a user that a blueprint migration is *pending*. `seihou status` prints the
receipts of migrations already recorded and never computes outstanding ones — the function
`pendingBlueprintMigrations` in `seihou-cli/src/Seihou/CLI/BlueprintMigration.hs` has exactly
one caller, inside `handleAgentMigrate`, and it runs only after the user has named a blueprint
and a window. A user learns that an upgrade exists by reading the library's release notes.

Closing that gap — a sweep across installed blueprints, surfaced in `seihou status` or as an
`--all` flag — is deliberately out of scope here and should be its own plan. It is mentioned
because it is *why this plan comes first*: the moment seihou starts listing pending
migrations, a project that upgraded by hand would show a pending migration forever, and until
this plan lands there would be no supported way to clear it. Shipping discovery first would
manufacture a false positive that users cannot dismiss.


## Plan of Work

### Milestone 1 — the flag, and the combinations it forbids

At the end of this milestone the flag exists, is documented in `--help`, and the invocations
that cannot mean anything are refused with a message that says why. Nothing marks anything
yet.

In `seihou-cli/src-exe/Seihou/CLI/Commands.hs`, add a field to `BlueprintMigrationOpts`
immediately after `rerun`, keeping the record's strict-field and comment conventions:

```haskell
    -- | When 'True', record a receipt for every pending step in the window
    -- without starting an agent session, on the user's assertion that the
    -- upgrade has already been performed by hand. No provider is contacted
    -- and no file in the working tree is touched.
    markApplied :: !Bool,
```

Add the matching combinator to `agentMigrateParser`, in the position that corresponds to the
new field:

```haskell
      <*> switch
        ( long "mark-applied"
            <> help "Record the pending migrations in the window as already applied, without running them"
        )
```

Re-read the record and the parser side by side afterwards. The parser is positional; a
mismatch compiles cleanly and assigns the wrong values.

Two flag combinations must be refused, both in `handleAgentMigrate`, before any other work:

`--mark-applied` together with `--rerun` is contradictory. `--rerun` means "ignore existing
receipts and run these edges again"; `--mark-applied` means "do not run anything". Refuse with
an actionable message rather than silently letting one win:

```text
✗ --mark-applied and --rerun cannot be combined.

  --rerun runs edges that already have receipts; --mark-applied records
  receipts without running anything. Pick one.
```

`--mark-applied` together with the parent `--debug` flag is also refused. `--debug` for this
subcommand is a true dry run that writes nothing, and marking writes receipts, so honouring
both is impossible and honouring either silently would surprise someone:

```text
✗ --mark-applied cannot be combined with --debug.

  --debug renders prompts without changing anything; --mark-applied writes
  migration receipts. Run it without --debug when you are ready to record.
```

Note that `debug` is not a field of `BlueprintMigrationOpts`; it is the first argument of
`handleAgentMigrate`, passed down from the parent `agent` command. Both checks belong at the
top of `handleAgentMigrate`, before the blueprint is discovered, so an invalid invocation
fails fast and without touching the filesystem.

Verify with the built binary:

```bash
cabal build seihou
$(cabal list-bin seihou) agent migrate --help
```

The help output must list `--mark-applied` with its description.

### Milestone 2 — record without running

At the end of this milestone the flag does its job: pending steps get receipts, no provider is
contacted, and no working-tree file changes.

In `seihou-cli/src-exe/Seihou/CLI/AgentMigrate.hs`, inside `handleAgentMigrate`, find the
branch that begins:

```haskell
      if null pending
        then reportNoPending expandedPlan
        else do
          preparedByOwner <- prepareCohort level modelConfig opts cohort pending
```

Insert the marking branch between those two, so that marking happens *instead of*
`prepareCohort` and everything after it:

```haskell
      if null pending
        then reportNoPending expandedPlan
        else
          if opts ^. #markApplied
            then markPendingAsApplied level manifestPath cohort pending
            else do
              preparedByOwner <- prepareCohort level modelConfig opts cohort pending
              ...
```

Placing the branch here rather than earlier is deliberate and worth understanding. Everything
above this point — discovering the blueprint, guarding it, resolving the window, planning the
chain, resolving the cohort, guarding entailed blueprints, expanding entailed edges, and
filtering out steps that already have receipts — is exactly the work needed to know *which
receipts to write*. Everything below it — resolving variables (which prompts the user),
mounting reference files, building a trace sink, gathering agent context — exists only to run
a session. Marking needs all of the former and none of the latter.

Write `markPendingAsApplied` in the same module:

```haskell
-- | Record every pending step as applied without running it.
--
-- Each receipt goes through 'recordMigration', the same function the real run
-- uses, so a marked receipt is indistinguishable from a run one and is written
-- under the identity of the blueprint that /owns/ the edge rather than the one
-- the user named. Reusing it is the point: a second receipt-construction site
-- could drift from the ownership rule in
-- docs\/adr\/0008-an-entailed-migration-edge-is-owned-by-the-blueprint-that-declares-it.md,
-- and a receipt written under the wrong identity matches nothing.
--
-- Recording stops at the first failure and reports it, leaving earlier
-- receipts in place, which is the same contract the real run has.
markPendingAsApplied ::
  LogLevel ->
  FilePath ->
  Map Text CohortBlueprint ->
  [BlueprintMigrationStep] ->
  IO ()
```

Its body announces what it is about to do, then folds over the steps calling
`recordMigration manifestPath cohort step MigrationApplied`, stopping at the first `Left` and
reporting it through `exitErr`. The failure message should match the shape the real run uses
for a receipt-write failure, which is in `handleRunResult` in the same file — the user needs to
know which edges were recorded before the failure.

The outcome recorded is `MigrationApplied`. See the Decision Log for why this does not get a
third `MigrationOutcome` constructor.

### Milestone 3 — say what happened

At the end of this milestone the command's output makes it obvious that nothing ran, which
matters because the whole point is that the user is asserting something rather than observing
it.

The pure formatting belongs in `seihou-cli/src/Seihou/CLI/BlueprintMigration.hs` so it can be
unit-tested — remember that the test suites cannot import from `src-exe`. Add:

```haskell
-- | Announce the steps a --mark-applied run is about to record.
--
-- Every step is named with 'formatMigrationStepLabel', the one function every
-- user-facing step label goes through, so a marked chain reads the same as a
-- run one and an entailed step still says what pulled it in.
formatMarkAppliedNotice :: [BlueprintMigrationStep] -> Text
```

It should produce, for a two-step cohort chain:

```text
Marking 2 blueprint migration(s) as already applied, without running them:
  kiroku-upgrade 1.9.0 -> 2.0.0 (entailed by keiro-upgrade 2.4.0 -> 3.0.0)
  keiro-upgrade 2.4.0 -> 3.0.0
```

Use `formatMigrationStepLabel`, which already exists in that module and is what the launch
announcement, the `--debug` headers, and both failure messages use. Do not re-derive a label;
the owner prefix and the entailed-by suffix must not drift between surfaces.

Add a matching completion line, printed after the receipts are written:

```text
Recorded 2 receipt(s). No agent session was started and no file was changed.
```

That last sentence is doing real work. A user who mistypes and marks a migration they have not
actually performed needs the output to make the mistake obvious immediately, and the remedy
discoverable — which is `--rerun`, since a marked receipt is an ordinary applied receipt.

Finally, `reportNoPending` in the same file prints "All blueprint migrations in the requested
version window already have receipts." when nothing is pending. That sentence is correct for a
`--mark-applied` run too, so it needs no change; confirm this by reading it rather than
assuming.

### Milestone 4 — unit tests

Core tests live under `seihou-core/test/` and run with `cabal test seihou-core-test`; CLI
tests live under `seihou-cli/test/` and run with `cabal test seihou-cli-test`. Both use
`tasty` with `hspec` through `Test.Tasty.Hspec.testSpec`. Each spec module exports
`tests :: IO TestTree` and is registered in its suite's `Main.hs`.

Add to `seihou-cli/test/Seihou/CLI/BlueprintMigrationSpec.hs`, which already has fixtures for
steps and receipts — reuse `first`, `second`, and `entailedStep` rather than building new
ones:

- `formatMarkAppliedNotice` names every step it is about to record, with the owner prefix.
- `formatMarkAppliedNotice` labels an entailed step with what entailed it, proving it goes
  through `formatMigrationStepLabel` rather than a second label derivation.
- The count in its first line matches the number of steps.

Flag-conflict refusal is checked end-to-end in Milestone 5 rather than by a unit test, because
the checks live in the executable where a unit test cannot reach them.

### Milestone 5 — end-to-end tests

`seihou-cli/test/Seihou/CLI/AgentMigrateE2ESpec.hs` runs the built binary against scratch
projects in temporary directories. Read it before adding to it: it already has helpers that
stand up a project with a fake `claude` executable first on `PATH`, a scrubbed environment so
no real user config leaks in, and an empty `XDG_CONFIG_HOME`. `withProbeProject` and
`withCohortProject` are the two to reuse — the first has a single blueprint with two
consecutive edges, the second has a keiro/kiroku cohort where one edge entails another.

The fake `claude` in these fixtures appends a line to a log file each time it is called. That
log is the mechanism for proving no session started: assert the log does not exist, or is
unchanged.

Add these cases:

The **core case**, using `withProbeProject`: run
`agent migrate probe-upgrade --from 1.0.0 --to 2.0.0 --mark-applied`. Assert the output
contains the marking notice and the "No agent session was started" line; assert the fake
provider's log file does not exist; assert `.seihou/manifest.json` now contains a receipt for
`1.0.0 -> 2.0.0` with outcome applied; and assert that a subsequent ordinary
`agent migrate probe-upgrade --from 1.0.0 --to 2.0.0` reports "already have receipts" and
still starts no session.

The **cohort case**, using `withCohortProject`: run
`agent migrate keiro-upgrade --from 2.4.0 --to 3.0.0 --mark-applied` and assert that the two
resulting receipts are filed under `kiroku-upgrade` and `keiro-upgrade` respectively — the same
assertion the existing test "crosses a shared cohort edge once regardless of entry point"
makes, but reached without running anything. This is the test that proves marking respects the
ownership rule. Then run `agent migrate kiroku-upgrade --from 1.9.0 --to 2.0.0` and assert it
reports "already have receipts", proving a marked entailed receipt suppresses the direct entry
point exactly as a run one does.

The **no-write case**: assert that marking leaves the working tree unchanged. The scratch
projects contain the blueprint directory and nothing else, so listing the project root before
and after and comparing is sufficient and readable.

The **conflict cases**: `--mark-applied --rerun` exits non-zero and names both flags;
`agent --debug migrate ... --mark-applied` exits non-zero and names both. Both must fail
before writing anything, so also assert `.seihou/manifest.json` does not exist afterwards.

The **help case**: extend the existing test named "exposes an optional version window and the
rerun option in help" — or add a sibling — asserting `--mark-applied` appears in
`agent migrate --help`.

### Milestone 6 — documentation

This milestone is not optional and is not an afterthought: a capability nobody can discover
has not been delivered. It also carries a lesson learned while closing
`docs/masterplans/10-blueprint-migration-fan-out-across-a-library-cohort.md`, recorded in that
MasterPlan's Integration Points section — **grep the documentation tree for the behaviour, not
for the files you expect to edit.** Six consecutive plans in that initiative each updated the
guide they were thinking about and left two summary pages describing blueprint migrations from
elsewhere silently stale for months. Before declaring this milestone done, run:

```bash
rg -n "agent migrate|blueprint migration|receipt" docs/ seihou-cli/help/
```

and check every hit, not only the files named below.

**New content** in `docs/user/blueprint-migrations.md`. This is the main guide, structured as
"For library authors" then "For consumers". Add a subsection under **For consumers**, placed
after "Resume, repeat, and re-run" since it belongs with the other after-the-fact operations,
titled something like "I already upgraded by hand". It must explain what the flag asserts (that
the work is done, on the user's word), that no session runs and no file changes, that it marks
every pending step in the window including entailed steps owned by other blueprints, that it
skips steps that already have receipts rather than rewriting their timestamps, and that
`--rerun` is the remedy if it was used by mistake. Include a worked transcript.

Also add a row to that file's **Troubleshooting** table for each of the two refusal messages,
following the existing rows' style — message on the left, meaning and fix on the right.

**Updates** to `docs/cli/agent.md`, the command reference. Add `--mark-applied` to the
`agent migrate` options table with a one-line description, and a short paragraph explaining
the flag near the "Inferring the version window" section. Its "Artifact Guard" section says
the guard runs before planning; marking does not change that, but confirm the section's claims
are still literally true after your change rather than assuming.

**Updates** to the two summary pages that describe blueprint migrations from elsewhere, which
is exactly where the previous initiative's drift happened. `docs/user/migrations.md` has an
"Agent-guided blueprint migrations" section listing the ways blueprint migrations differ from
module migrations; a receipt that can be asserted rather than earned belongs in that list.
`docs/user/blueprints.md` has a "Library upgrade migrations" section; check whether its
description of what a receipt means needs the same qualification.

**Update** the in-binary help topic at `seihou-cli/help/agent.md`, which is embedded into the
executable with `Data.FileEmbed` and shown by `seihou help agent`. Its `agent migrate` entry
lists the flags and their behaviour and must mention `--mark-applied`. This file is easy to
forget because it is not under `docs/`.

**Append** to `docs/user/CHANGELOG.md` under `## Unreleased` → `### Added`. The release
immediately before this work is `0.7.0.0`; `## Unreleased` already carries an `### Added`
heading with entries from later work, so append a new bullet under it rather than creating the
heading. The entry should lead with the problem
— there was no way to tell seihou about an upgrade you did yourself — and state plainly that a
marked receipt is an ordinary applied receipt, with `--rerun` as the correction.

### Milestone 7 — the ADR pass

At the end of this milestone the durable decision this plan settles is recorded where it will
outlive the plan.

The decision is **what a migration receipt asserts**. Before this change a receipt could only
mean "an agent session for this edge returned", because that was the only way to create one.
After it, a receipt means "this edge has been attended to and need not run again" — which is a
claim about the *project*, established either by a session returning or by a human saying so.
That is a genuine widening of a contract several parts of the system depend on, and it is the
kind of thing a future contributor will need to know before, say, adding a receipt-based
report that assumes an agent produced every entry.

Judge, following `.claude/skills/exec-plan/ADR.md`, whether this amends
`docs/adr/0007-a-deliberate-no-op-is-a-third-outcome-not-a-success.md` or warrants a new
record. The rule the preceding initiative applied consistently, and which is worth applying
here, is: **amend when the decision is unchanged and only its reach grew; write a new record
when there is a rejected alternative the existing record has nowhere to put.** There is a
rejected alternative here — a distinct "applied by hand" outcome value — and ADR 0007 is
specifically about the *outcome vocabulary* rather than about what a receipt asserts, so a new
record is the likelier answer. Make the call deliberately and record which you chose and why in
the Decision Log.

If a new record: the next free number is `0011` (the corpus ends at
`docs/adr/0010-generated-documentation-is-checked-before-it-is-written.md`, which landed after
this plan was written); verify by listing `docs/adr/` rather than trusting this sentence, since
another plan may have landed first. Follow the local convention exactly — `NNNN-slug.md`, a `# ADR NNNN — Title` heading,
`Status: Accepted` and `Date:` lines, then Context, Decision, Consequences, and References
sections. Cite ADRs 0002, 0004, 0007, and 0008 by repository-relative path where they bear on
the reasoning. Do not add OKF frontmatter.


## Concrete Steps

Run everything from the repository root,
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`.

Orient yourself first, and confirm the two facts this plan depends on. The first prints the
single production caller of the receipt writer; the second prints the branch you will be
inserting into:

```bash
rg -n "recordAppliedBlueprintMigration" seihou-cli/src seihou-cli/src-exe
rg -n "if null pending" -A 4 seihou-cli/src-exe/Seihou/CLI/AgentMigrate.hs
```

Build and test after each milestone:

```bash
cabal build all
cabal test seihou-core-test
cabal test seihou-cli-test
```

Run the full gate before committing. It includes the module-placement and record-convention
checks, which fail the build rather than merely warning:

```bash
nix flake check
```

Commit with both trailers. The plan's frontmatter carries
`intention: intention_01m26cpw67eens6yw0dz028ryj`, so every commit for this work gets an
`Intention:` trailer alongside the `ExecPlan:` one:

```text
feat(agent): let a user record a migration they applied by hand

--mark-applied records a receipt for every pending step in the window
without starting an agent session, on the user's assertion that the
upgrade has already been performed. Receipts are written through the
same path a real run uses, so an entailed step is still recorded under
the blueprint that owns it.

ExecPlan: docs/plans/87-record-a-blueprint-migration-that-was-applied-by-hand.md
Intention: intention_01m26cpw67eens6yw0dz028ryj
```


## Validation and Acceptance

**Automated.** Both suites pass: `cabal test seihou-core-test` and `cabal test seihou-cli-test`.
The decisive assertions are the cohort end-to-end case — that marking files receipts under
`kiroku-upgrade` and `keiro-upgrade` separately, and that the entailed receipt then suppresses
a direct `kiroku-upgrade` run — and the no-session assertion, that the fake provider's log file
was never created.

**By hand.** Build a throwaway project with a blueprint declaring two consecutive edges. The
existing test fixture `probeBlueprintDhall` in
`seihou-cli/test/Seihou/CLI/AgentMigrateE2ESpec.hs` is a working example to copy; write it to
`.seihou/modules/scratch-upgrade/blueprint.dhall` under a temporary directory and run from
there.

Mark the first edge:

```bash
seihou agent migrate scratch-upgrade --from 1.0.0 --to 2.0.0 --mark-applied
```

Expected:

```text
Marking 1 blueprint migration(s) as already applied, without running them:
  scratch-upgrade 1.0.0 -> 2.0.0

Recorded 1 receipt(s). No agent session was started and no file was changed.
```

Then confirm the receipt is real and suppresses a later run:

```bash
seihou status
seihou agent migrate scratch-upgrade --from 1.0.0 --to 2.0.0
```

`seihou status` must list the edge under "Blueprint migrations:" as applied, with today's
date. The second command must print "All blueprint migrations in the requested version window
already have receipts." and exit zero without contacting a provider — verifiable by running it
with no provider configured at all.

**The correction path works.** `seihou agent migrate scratch-upgrade --from 1.0.0 --to 2.0.0
--rerun` must plan the edge again despite the marked receipt, proving a mistaken marking is
recoverable by the documented remedy.

**Marking is additive, not destructive.** Mark the first edge, note its `appliedAt` timestamp
in `.seihou/manifest.json`, then run `--mark-applied` again for the whole window
`--from 1.0.0 --to 3.0.0`. The first edge's timestamp must be unchanged — it was already
applied, so it is not pending and is not rewritten — while a new receipt appears for
`2.0.0 -> 3.0.0`.

**The refusals fire before anything is written.** In a fresh project with no manifest:

```bash
seihou agent migrate scratch-upgrade --from 1.0.0 --to 2.0.0 --mark-applied --rerun
seihou agent --debug migrate scratch-upgrade --from 1.0.0 --to 2.0.0 --mark-applied
```

Both must exit non-zero, name both conflicting flags, and leave `.seihou/manifest.json`
absent.

**Nothing that works today changes.** `seihou agent migrate scratch-upgrade --from 1.0.0 --to
3.0.0` without the new flag must behave exactly as before, and the existing end-to-end tests
covering the ordinary run, the not-applicable outcome, and the cohort chain must all still
pass unmodified.


## Idempotence and Recovery

Every step in this plan is a source edit; there is no migration of existing data and no
published artifact. The schema submodule at `schema/` is not touched, so there is no push to
coordinate and nothing to re-pin.

The command itself is idempotent by construction. Marking a window twice records the same
receipts the second time: the first run makes those steps non-pending, so the second finds
nothing pending and reports so. Marking a wider window later adds only the newly pending
edges. This falls out of scoping the operation to the pending set rather than to the whole
window, which is why that scoping is a recorded decision rather than an implementation detail.

For a user, the recovery path from a mistaken marking is `--rerun`, which ignores existing
receipts and plans the edges again. This is the same remedy the documentation already gives
for a receipt that says applied when the edge really did nothing, so it needs no new
machinery — but it must be stated in the new documentation, because a user who has just been
handed a way to assert something will eventually assert it wrongly.

Receipt writing stops at the first failure rather than continuing, matching the real run's
contract. If the manifest becomes unwritable partway through a multi-step marking, the earlier
receipts remain and the command reports which edge failed; re-running the same command records
only what is still pending.

If work stops mid-plan, the safe stopping point is the end of Milestone 3 — the flag works
end-to-end and is only untested and undocumented. Do not stop after Milestone 1 with Milestone
2 incomplete: the flag would parse and be accepted while doing nothing at all, which is worse
than not having it.


## Interfaces and Dependencies

No new library dependencies. No schema change. No new manifest fields, and
`currentManifestVersion` does not move — this plan writes existing receipts through an
existing function.

At the end of the plan these must exist.

`seihou-cli/src-exe/Seihou/CLI/Commands.hs`

```haskell
data BlueprintMigrationOpts = BlueprintMigrationOpts
  { name :: !ModuleName,
    from :: !(Maybe Text),
    to :: !(Maybe Text),
    prompt :: !(Maybe Text),
    vars :: ![(Text, Text)],
    namespace :: !(Maybe Text),
    context :: !(Maybe Text),
    verbose :: !Bool,
    rerun :: !Bool,
    markApplied :: !Bool,
    provider :: !(Maybe Text),
    model :: !(Maybe Text),
    effort :: !(Maybe Text),
    trace :: !(Maybe Text),
    allowDowngrade :: !Bool
  }
  deriving stock (Eq, Show, Generic)
```

`seihou-cli/src/Seihou/CLI/BlueprintMigration.hs` — exported from the module:

```haskell
formatMarkAppliedNotice :: [BlueprintMigrationStep] -> Text
```

`seihou-cli/src-exe/Seihou/CLI/AgentMigrate.hs` — module-private:

```haskell
markPendingAsApplied ::
  LogLevel ->
  FilePath ->
  Map Text CohortBlueprint ->
  [BlueprintMigrationStep] ->
  IO ()
```

Reused without modification: `recordMigration` and `exitErr` in
`seihou-cli/src-exe/Seihou/CLI/AgentMigrate.hs`; `recordAppliedBlueprintMigration` in
`seihou-cli/src/Seihou/CLI/AppliedBlueprintMigration.hs`; `formatMigrationStepLabel` and
`pendingBlueprintMigrations` in `seihou-cli/src/Seihou/CLI/BlueprintMigration.hs`;
`writeAppliedBlueprintMigration` in `seihou-core/src/Seihou/Manifest/Types.hs`.

This plan has no dependency on another plan and nothing depends on it. It is, however, a
sensible prerequisite for any future plan that surfaces *pending* blueprint migrations across
installed blueprints, for the reason given at the end of Context and Orientation.

---

## Revision note — 2026-09-10

Refreshed before implementation and closed after it.

**Refresh.** Milestone 7 claimed the next free ADR number was `0010` and that the corpus ended at
`0009`; `docs/adr/0010-generated-documentation-is-checked-before-it-is-written.md` had landed in
the meantime, so the number is now `0011`. Every other claim the plan makes about the working
tree was re-verified against it and still held — the record and parser shapes, the
`if null pending` branch, `recordMigration`, the library exports, the test fixtures, `mori.dhall`'s
single OKF bundle, and every documentation file named in Milestone 6. An Intention was minted for
this work (`intention_01m26cpw67eens6yw0dz028ryj`) and added to the frontmatter, so Concrete Steps
now shows both git trailers instead of saying no Intention applies. The CHANGELOG note was
corrected: `## Unreleased` already carries an `### Added` heading, so the entry is appended under
it rather than creating it.

**Implementation.** All seven milestones are complete. Two findings are recorded in Surprises &
Discoveries: the documentation grep found three files Milestone 6 had not named, all asserting
that a receipt means an agent session completed; and the two end-to-end helpers the plan named for
the no-session assertion used a fake provider that wrote no log, so the assertion the plan proposed
would have passed unconditionally. Four decisions were added to the Decision Log, covering the
refusal output stream, the second exported formatter, the new-ADR-versus-amendment call, and the
summary sentence's wording.
