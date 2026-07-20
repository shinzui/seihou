---
id: 71
slug: run-ordered-blueprint-migrations-for-library-upgrades
title: "Run Ordered Blueprint Migrations for Library Upgrades"
kind: exec-plan
created_at: 2026-07-20T13:41:01Z
intention: "intention_01kxzvmqgee4pvyxgeceawxqng"
---

# Run Ordered Blueprint Migrations for Library Upgrades

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

Library authors need a way to ship upgrade knowledge for breaking releases that is
more adaptive than Seihou's deterministic module migrations. After this change, a
normal installed blueprint can declare an ordered `migrations` list. Each entry
names a dotted numeric `from` version, a dotted numeric `to` version, and a
Markdown prompt describing the source-code changes required for that one upgrade.
A developer can then run:

```bash
seihou agent migrate my-library --from 1.0.0 --to 3.0.0
```

Seihou will select the blueprint migrations inside that version window, order them
with the same gap-tolerant rules used by module migrations, and run one agent
session per migration. It records each successfully completed edge immediately,
so an interrupted chain can resume without repeating earlier work. The parent
`seihou agent --debug` flag renders the ordered sessions without contacting a
provider or changing `.seihou/manifest.json`.

This functionality belongs in Seihou because the repository already owns all four
required concepts: blueprints as packaged agent workflows, version-window planning,
provider-neutral agent launch, and project-local provenance. It does not turn
Seihou into a language-specific package manager. The user supplies `--from` and
`--to`; Seihou does not guess versions from Cabal, npm, Cargo, or other dependency
files. The reusable domain model, planner, validation, and manifest transition
belong in the public `seihou-core` library. Testable chain orchestration belongs in
the private `seihou-cli-internal` library. Only option parsing, the embedded system
prompt, and process-facing dispatch remain in the executable package.

The feature is visible without a live model: an installed fixture with migrations
from `1.0.0 -> 2.0.0` and `2.5.0 -> 3.0.0` must render those two steps in that order
for a debug migration from `1.0.0` to `3.0.0`, despite the intentional gap. A
library-level fake-launcher test must additionally prove that a failure in the
second step records only the first, stops before the third, and resumes at the
second on the next invocation.


## Progress

- [x] (2026-07-20 14:20Z) Milestone 1: added the blueprint-migration Dhall schema, Haskell domain type,
  backwards-compatible decoder, validation rules, shared ordered planner, scaffold
  output, and core tests. `cabal test seihou-core-test` passed all 1,018 tests;
  `cabal build all` and local evaluation of `schema/BlueprintMigration.dhall` also
  succeeded.
- [x] (2026-07-20 14:29Z) Milestone 2: added the manifest-v5 applied-blueprint-migration ledger, pure
  upsert/query functions, JSON compatibility, and status formatting with core and
  CLI tests. `cabal test seihou-core-test seihou-cli-test` passed both suites.
- [x] (2026-07-20 14:40Z) Milestone 3: extracted reusable blueprint variable/reference preparation
  from the existing runner and added pure pending-step selection plus injected
  sequential orchestration to `seihou-cli-internal`. `cabal test seihou-cli-test`
  passed all 330 tests and `cabal build all` succeeded.
- [ ] Milestone 4: add `seihou agent migrate`, its migration-specific system prompt,
  provider/model configuration, debug behavior, resumable execution, executable
  wiring, and command-level tests.
- [ ] Milestone 5: publish and pin the updated schema, update author/user/CLI/help
  documentation and changelogs, run every build/test/check gate, and record the
  end-to-end debug transcript.


## Surprises & Discoveries

- Observation: Under the repository's `NoFieldSelectors` default, importing only
  the `BlueprintMigration` type does not bring its overloaded record fields into
  scope. Importing `BlueprintMigration (..)` was required before `migration.from`,
  `migration.to`, and `migration.prompt` would compile in validation.
  Evidence: the first core build reported `No instance for HasField "from"
  BlueprintMigration Text`; the next build passed after widening the import.

- Observation: Unrelated deterministic CLI-model changes appeared concurrently in
  `seihou-cli/src/Seihou/CLI/AgentCompletion.hs`,
  `seihou-cli/src/Seihou/CLI/AgentConfig.hs`, and
  `seihou-cli/test/Seihou/CLI/AgentConfigSpec.hs` during Milestone 1.
  Evidence: those paths were clean in the initial `git status --short`, then
  acquired functional diffs unrelated to blueprint migrations. They remain
  unstaged and must be preserved.

- Observation: The concurrent plan-70 commit `08c84f3` unintentionally included
  Milestone 2's already-written `seihou-core/src/Seihou/Core/Types.hs` and
  `seihou-core/src/Seihou/Manifest/Types.hs` changes alongside its own agent-model
  work.
  Evidence: `git log -1 --stat 08c84f3` lists both core files, while the commit
  carries plan-70's ExecPlan and Intention trailers. Rewriting that user-owned
  commit would be more disruptive, so the remaining Milestone 2 implementation,
  tests, and this provenance note are committed under ExecPlan 71.

- Observation: Baikai's interactive launch result exposes a real process
  `ExitCode`, while Seihou's existing API completion path exposes provider error
  text.
  Evidence: Mori located `Baikai.Interactive.InteractiveLaunchResult` with its
  `exitCode` field and the local `runAgentCompletion` facade returning
  `Either Text Text`. The migration orchestrator therefore preserves both failure
  forms instead of inventing an API exit code.


## Decision Log

- Decision: Put ordered migration entries on one `Blueprint` as
  `migrations :: [BlueprintMigration]`; do not introduce a `Library` artifact or
  require one separately installed blueprint per breaking release.
  Rationale: A blueprint is already the installed and registry-published unit. A
  single artifact can share variables, allowed tools, reference files, and general
  library guidance across all upgrade edges. Separate artifacts would make users
  discover and install every edge and would require new cross-artifact grouping
  metadata that Seihou does not otherwise need.
  Date: 2026-07-20.

- Decision: Define `BlueprintMigration` with exactly `from`, `to`, and `prompt`.
  Render the blueprint's existing `prompt` as shared guidance and append the
  selected migration's prompt as edge-specific instructions. Reuse the blueprint's
  existing `files` and `allowedTools` for every edge.
  Rationale: Markdown files can still be imported independently for every edge,
  while one mounted `files/` directory and one tool policy remain easy to validate
  and explain. Per-edge file mounts or tool policies can be added later without
  changing the ordering/state contract.
  Date: 2026-07-20.

- Decision: Add `seihou agent migrate BLUEPRINT --from CURRENT --to TARGET` rather
  than extending the existing top-level `seihou migrate` command.
  Rationale: `seihou migrate` applies deterministic filesystem operations declared
  by modules and rewrites tracked file records. Blueprint migrations ask an agent
  to adapt arbitrary consumer source code and cannot promise the same conflict or
  rollback semantics. Keeping them under `agent` makes the execution model visible
  in the command name and avoids silently changing the established module command.
  Date: 2026-07-20.

- Decision: Require explicit `--from` and `--to` on every invocation.
  Rationale: Seihou is language-agnostic and cannot reliably determine a library's
  currently used and desired versions across Cabal, npm, Cargo, Maven, and other
  ecosystems. Automatic package-manager adapters may later supply these arguments,
  but version detection does not belong in the core migration contract.
  Date: 2026-07-20.

- Decision: Reuse the module migration planner's gap-tolerant version-window
  semantics through a shared private walker in `Seihou.Core.Migration` while
  preserving the existing `planMigrationChain` API and behavior.
  Rationale: Library authors declare entries only for releases that need help;
  version gaps therefore mean no agent intervention was declared, not a broken
  chain. Duplicate `from` versions remain errors, overlapping edges are resolved by
  the advancing cursor, overshooting edges are skipped, and selected entries run by
  ascending `from` version.
  Date: 2026-07-20.

- Decision: Run each selected migration in its own provider interaction and write a
  receipt after each successful interaction rather than combining the chain into
  one prompt or recording only at the end.
  Rationale: Separate sessions preserve the edge's success/failure boundary and let
  Seihou stop and resume deterministically. They also work uniformly for
  interactive Claude/Codex sessions and one-shot API completions. A combined
  session would make it impossible to know which edge completed before an
  interruption.
  Date: 2026-07-20.

- Decision: Add `blueprintMigrations :: [AppliedBlueprintMigration]` to the
  manifest instead of reusing `Manifest.blueprint :: Maybe AppliedBlueprint`.
  Identify a completed edge by `(blueprint name, from version, to version)` and use
  `--rerun` to intentionally ignore an existing receipt.
  Rationale: The current `blueprint` field records only the most recent general
  blueprint invocation and replaces its predecessor. Ordered migrations need a
  durable, finite history for resume. Blueprint artifact version and timestamp are
  still recorded for audit, but changing the artifact version must not silently
  repeat an arbitrary source-code migration.
  Date: 2026-07-20.

- Decision: Migration mode never applies `baseModules`; normal `seihou agent run`
  continues to ignore the new `migrations` list.
  Rationale: Baselines create or reconcile deterministic scaffolding and may
  overwrite the consumer tree being upgraded. The same blueprint may nevertheless
  be useful both for initial setup and later upgrades, so validation should not
  forbid `baseModules` and `migrations` from coexisting.
  Date: 2026-07-20.

- Decision: `seihou agent --debug migrate` renders every pending migration but
  never launches a provider and never writes a receipt, even though the existing
  normal blueprint runner records its successful debug render.
  Rationale: Marking multiple arbitrary code migrations complete merely because
  their prompts rendered would make resume state false. Migration debug is a true
  dry run; the normal runner's historical behavior remains unchanged.
  Date: 2026-07-20.

- Decision: Treat an agent exit or API response as an execution receipt, not proof
  that a package manager now reports the target version. Stop immediately on a
  provider failure or receipt-write failure and never launch a later edge.
  Rationale: Seihou cannot validate arbitrary libraries uniformly. The migration
  prompt can require relevant tests, but only the library-specific agent workflow
  can judge completion. Stopping on state-write failure avoids knowingly running a
  chain whose resume ledger is already incomplete.
  Date: 2026-07-20.

- Decision: Keep all reusable policy outside `seihou-cli/src-exe`. No Baikai
  dependency is added to `seihou-core`, and no dependency bound changes are part of
  this work.
  Rationale: `seihou-core` already exposes migration planning without an agent
  provider. The existing released bounds (`baikai ^>=0.3.1.0`,
  `baikai-claude ^>=0.3.0.1`, and `baikai-openai ^>=0.3.0.1`) expose
  provider-neutral interactive requests and exit codes, which are sufficient for
  sequential sessions. The executable remains limited to modules trapped by
  `Options.Applicative` or `Data.FileEmbed`, per
  `docs/dev/architecture/overview.md`.
  Date: 2026-07-20.

- Decision: Commit the local `schema/` submodule change at the Milestone 1
  boundary, but defer pushing that exact commit and changing the immutable remote
  schema pin until Milestone 5.
  Rationale: A committed submodule pointer makes the Milestone 1 parent commit
  internally reproducible and prevents the schema work from remaining an
  anonymous dirty submodule across later milestones. Publication and the remote
  Dhall integrity proof still occur together in Milestone 5 as planned.
  Date: 2026-07-20.

- Decision: `writeAppliedBlueprintMigration` upgrades an older decoded manifest's
  `version` to `currentManifestVersion` when adding the first v5 receipt.
  Rationale: Writing the v5-only `blueprintMigrations` key while retaining a v4
  version number would mislabel the persisted schema. Reads remain non-mutating:
  a v4 manifest without receipts still decodes with `version = 4` and an empty
  ledger until a receipt is actually recorded.
  Date: 2026-07-20.

- Decision: Keep `gatherAgentContext` in the executable normal runner after its
  optional baseline phase, while moving variable resolution, reference access,
  tool selection, and shared-prompt rendering into `BlueprintExecution`.
  Rationale: Gathering project state during the shared preparation call would run
  before baseline application and could make the existing normal prompt describe
  stale workspace state. Migration mode can gather the same context after its
  preparation because it never applies a baseline.
  Date: 2026-07-20.


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

(To be filled during and after implementation.)

- Milestone 1 established one shared gap-tolerant planner for deterministic module
  migrations and agent-guided blueprint migrations without changing the existing
  module results. Legacy blueprint records decode with an empty migration list,
  new entries decode and validate, and generated blueprints expose the typed empty
  authoring surface. The complete core suite and full workspace build pass. The
  schema commit is local pending publication and pinning in Milestone 5.

- Milestone 2 added a version-5 exact-edge receipt ledger with in-place upsert,
  a query helper, backwards-compatible v4 decoding, filesystem-backed recording,
  and status output that disappears when the ledger is empty. Tests prove that
  normal blueprint provenance plus module, application, file, and recipe state
  survives receipt writes. Both core and CLI suites pass. Two foundational source
  files landed in concurrent commit `08c84f3`; the remaining milestone work lands
  in the dedicated ExecPlan 71 commit.

- Milestone 3 moved the existing resolution precedence, reference mounting and
  fallback text, tool policy, and variable substitution behind an importable
  request/result pair without changing the normal runner's baseline or provider
  behavior. The new migration runner filters exact receipts, keeps planner order,
  and enforces launch-then-record sequencing. Fake callbacks prove that a failure
  on the second of three edges records only the first and that the next invocation
  resumes at the failed edge. All 330 CLI tests and the full workspace build pass
  without contacting a provider.


## Context and Orientation

Seihou has two migration-like capabilities today, but they do not yet meet this
use case. A module is a deterministic project generator represented by `Module` in
`seihou-core/src/Seihou/Core/Types.hs`. Its `migrations :: [Migration]` field uses
the records and typed filesystem operations from
`seihou-core/src/Seihou/Core/Migration.hs`. The pure
`planMigrationChain` function parses dotted numeric versions, rejects downgrades
and duplicate starts, and selects in-window migrations in ascending order while
permitting gaps. `seihou-core/src/Seihou/Engine/Migrate.hs` then applies those
operations and rewrites the deterministic module/file state. The user-facing
command is `seihou migrate`, implemented by
`seihou-cli/src/Seihou/CLI/Migrate.hs` and documented in
`docs/user/migrations.md` and `docs/cli/migrate.md`.

A blueprint is an agent-driven workflow represented by `Blueprint` in
`seihou-core/src/Seihou/Core/Types.hs`. It has a shared Markdown prompt, typed
variables and prompts, optional deterministic `baseModules`, reference files,
allowed tools, and tags. It is decoded by `blueprintDecoder` in
`seihou-core/src/Seihou/Dhall/Eval.hs`, validated in
`seihou-core/src/Seihou/Core/Blueprint.hs`, and described by the published Dhall
schema in the `schema/` git submodule. A normal run is handled by
`seihou-cli/src-exe/Seihou/CLI/AgentRun.hs`: it discovers and validates the
blueprint, resolves variables through the standard configuration hierarchy,
optionally applies baselines, renders `seihou-cli/data/blueprint-prompt.md`, and
uses the provider facade in `seihou-cli/src-exe/Seihou/CLI/AgentLaunchExec.hs`.
The current behavior is documented in `docs/user/blueprints.md`.

The phrase **blueprint migration** in this plan means one agent instruction that
helps consumer source code cross one declared library version edge. It does not
mean a deterministic `MigrationOp`, does not own generated file hashes, and does
not infer or modify a language package manifest on its own. A **migration window**
is the user-supplied inclusive range from the currently used library version to
the desired version. A **receipt** is manifest evidence that the agent interaction
for one exact blueprint/from/to tuple returned successfully. It is deliberately
weaker than a proof that arbitrary library-specific tests passed.

The current `AppliedBlueprint` record in
`seihou-core/src/Seihou/Core/Types.hs` and its JSON code in
`seihou-core/src/Seihou/Manifest/Types.hs` preserve only the most recent normal
blueprint run. `writeAppliedBlueprint` replaces the earlier value, and
`seihou-cli/src/Seihou/CLI/AppliedBlueprint.hs` performs the IO write. That shape
is suitable for last-run provenance but cannot resume a multi-step migration. The
manifest schema is currently version 4. This plan adds a separate receipt list and
bumps it to version 5, with a default empty list when reading older manifests.

The Dhall schema is a git submodule at `schema/`, whose upstream is
`shinzui/seihou-schema`. `schema/Blueprint.dhall` defines the author-facing record,
and `schema/package.dhall` exports its component types. Generated blueprints use
the pinned upstream URL and integrity hash in
`seihou-cli/src/Seihou/CLI/SchemaVersion.hs`. Therefore a schema change is not
complete until the submodule commit is published and that pin is updated and
verified. The new Haskell decoder must also supply `migrations = []` when loading
legacy bare blueprint records, because not every author uses schema record
completion.

The command parser and `AgentCommand` sum type live in
`seihou-cli/src-exe/Seihou/CLI/Commands.hs`; dispatch lives in
`seihou-cli/src-exe/Main.hs`. Per-command provider/model configuration lives in
the importable library module `seihou-cli/src/Seihou/CLI/AgentConfig.hs`. Add an
`AgentCmdMigrate` entry so `agent.migrate.provider` and `agent.migrate.model` obey
the same precedence and inspection behavior as `agent.run`. Update the associated
tests in `seihou-cli/test/Seihou/CLI/AgentConfigSpec.hs` and
`seihou-cli/test/Seihou/CLI/AgentConfigShowSpec.hs`.

Dependency research for the agent-launch surface was performed through Mori:
`mori registry search baikai`, `mori registry show shinzui/baikai --full`, and
`mori registry docs shinzui/baikai` locate the source at
`/Users/shinzui/Keikaku/bokuno/baikai`. The relevant source modules are
`baikai/src/Baikai/Interactive.hs`,
`baikai-claude/src/Baikai/Provider/Claude/Interactive.hs`, and
`baikai-openai/src/Baikai/Provider/OpenAI/Interactive.hs`. The Hackage index and
upstream tags were checked on 2026-07-20: the versions already bounded by
`seihou-cli/seihou-cli.cabal` are the current releases and provide a returned
`ExitCode`, working directory, reference directories, safety configuration, model,
system prompt, and user prompt. This plan does not add or upgrade a dependency.

The repository is a three-package Cabal workspace. `cabal build all` builds it,
`cabal test all` runs the suites, and `nix flake check` runs formatting and
repository checks. Any new library module and test module must be listed in the
appropriate stanza of `seihou-core/seihou-core.cabal` or
`seihou-cli/seihou-cli.cabal`, and imported by the package's `test/Main.hs` when
that test harness requires explicit registration.


## Plan of Work

Milestone 1 establishes the authoring contract and pure plan. Add
`schema/BlueprintMigration.dhall` with a record containing required `from`, `to`,
and `prompt` text plus an empty default record for Dhall record completion, export
it from `schema/package.dhall`, and add
`migrations : List BlueprintMigration.Type` with an empty default to
`schema/Blueprint.dhall`. A library author should be able to write:

```dhall
let S = ./package.dhall

in  S.Blueprint::{
    , name = "my-library"
    , version = Some "1.2.0"
    , prompt = ./prompt.md as Text
    , migrations =
      [ S.BlueprintMigration::{
        , from = "1.0.0"
        , to = "2.0.0"
        , prompt = ./migrations/1-to-2.md as Text
        }
      , S.BlueprintMigration::{
        , from = "2.5.0"
        , to = "3.0.0"
        , prompt = ./migrations/2-5-to-3.md as Text
        }
      ]
    }
```

In `seihou-core/src/Seihou/Core/Migration.hs`, add `BlueprintMigration` and
`BlueprintMigrationPlan`, plus `planBlueprintMigrationChain`. Extract the existing
window walk into a private parameterized helper used by both public planners; do
not change `Migration`, `MigrationPlan`, `MigrationPlanError`, or any observable
module migration result. Add `migrations :: [BlueprintMigration]` to `Blueprint`
in `seihou-core/src/Seihou/Core/Types.hs`. Extend
`seihou-core/src/Seihou/Dhall/Eval.hs` with a decoder and a `withDefaults` fallback
that injects an empty list into legacy blueprint records. Extend
`seihou-core/src/Seihou/Core/Blueprint.hs` with validation that rejects empty
migration prompts, unparseable versions, `from >= to`, and duplicate `from`
versions. Update `seihou-core/src/Seihou/Core/Scaffold.hs` so
`seihou new-blueprint` emits an explicitly typed empty list. Update all positional
and record constructors found by `rg -n "Blueprint( |\{)" seihou-core seihou-cli`
and add focused decoder, validation, planner, and scaffold tests. This milestone is
complete when all core tests pass and the old module migration planner tests remain
unchanged and green.

Milestone 2 adds resumable state without changing agent execution. Define
`AppliedBlueprintMigration` in `seihou-core/src/Seihou/Core/Types.hs` with the
blueprint name, optional blueprint artifact version, edge `fromVersion` and
`toVersion`, application timestamp, and optional future session identifier. Append
`blueprintMigrations :: [AppliedBlueprintMigration]` to `Manifest`. In
`seihou-core/src/Seihou/Manifest/Types.hs`, bump `currentManifestVersion` from 4 to
5, encode the list as `blueprintMigrations`, default a missing key to `[]`, and add
`writeAppliedBlueprintMigration`. That helper must replace a prior receipt with the
same `(name, fromVersion, toVersion)` key in place or append a new key, preserving
unrelated manifest fields and preventing duplicate history rows on `--rerun`.

Add `recordAppliedBlueprintMigration` to a new importable module
`seihou-cli/src/Seihou/CLI/AppliedBlueprintMigration.hs`, following the read/create/
write error handling of `Seihou.CLI.AppliedBlueprint`. Add a formatter in
`seihou-cli/src/Seihou/CLI/StatusRender.hs` and call it from
`seihou-cli/src-exe/Seihou/CLI/Status.hs` so a non-empty ledger appears under a
`Blueprint migrations:` heading and an empty ledger adds no output. Cover round
trip, v4 compatibility, future-version refusal, unrelated-field preservation,
upsert, corrupt-manifest failure, and status output in
`seihou-core/test/Seihou/Manifest/TypesSpec.hs`, a new
`seihou-cli/test/Seihou/CLI/AppliedBlueprintMigrationSpec.hs`, and
`seihou-cli/test/Seihou/CLI/StatusSpec.hs`. This milestone is complete when a
synthetic receipt survives a JSON round trip and status names its blueprint and
edge.

Milestone 3 creates reusable CLI-library preparation and orchestration before any
new parser is wired. Move the existing blueprint variable substitution and
project/reference preparation that both modes need out of
`seihou-cli/src-exe/Seihou/CLI/AgentRun.hs` into a new importable module,
`seihou-cli/src/Seihou/CLI/BlueprintExecution.hs`. Keep baseline application and
the normal embedded prompt in `AgentRun.hs`. The extraction must preserve normal
`seihou agent run` output, configuration precedence, reference mounting, tool
selection, API-provider fallback text, and applied-blueprint behavior.

Create `seihou-cli/src/Seihou/CLI/BlueprintMigration.hs` for pure rendering,
receipt filtering, and callback-driven sequential execution. It must filter
already applied exact edges unless `--rerun` is true, retain planner order, call a
provided launcher for one step at a time, call a provided recorder only after a
successful launch, and stop before the next step if either callback fails. Return
a structured result that distinguishes all-applied/no-declared work, full success,
provider failure, and receipt failure. Unit tests must use fake callbacks to prove
order, gap handling, no-op, resume, rerun, provider failure, and record failure.
This milestone is independently complete when the callback tests pass without
spawning Claude, Codex, or an API request and the existing normal blueprint tests
still pass.

Milestone 4 wires the command and provider execution. Add
`BlueprintMigrationOpts` and `AgentMigrate` to
`seihou-cli/src-exe/Seihou/CLI/Commands.hs`, with required `BLUEPRINT`, `--from`,
and `--to`; optional initial `PROMPT`; repeatable `--var`; namespace, context,
verbosity, provider, and model overrides; and a `--rerun` switch. Do not expose
`--no-baseline` or module migration's `--force`, because migration mode never
applies deterministic baselines or typed filesystem operations. Add
`AgentCmdMigrate` in `seihou-cli/src/Seihou/CLI/AgentConfig.hs`, parser help, agent
config display, and dispatch in `seihou-cli/src-exe/Main.hs`.

Create `seihou-cli/data/blueprint-migration-prompt.md` and the trapped executable
handler `seihou-cli/src-exe/Seihou/CLI/AgentMigrate.hs`. The prompt must identify
the blueprint, exact edge, and chain position; include the rendered shared
blueprint prompt and rendered edge prompt; show project state and reference-file
access; direct the agent to limit itself to the current edge, preserve unrelated
user changes, inspect the library's actual usage, run relevant validation, and
summarize what remains before exiting. The handler discovers and validates the
named blueprint, parses the explicit versions, calls the core planner, prepares
shared variables once, reads existing receipts, and passes pending steps to the
library orchestrator. CLI providers use `launchConfiguredAgentAddingDirs`; API
providers use the existing `runAgentCompletion` path. Parent debug mode prints all
pending prompts in order, clearly delimited, and deliberately supplies no recorder.
Normal success writes each receipt before starting the next edge. A nonzero exit,
API error, or write error prints an actionable message, stops, and returns nonzero.
Register the new embedded file and modules in `seihou-cli/seihou-cli.cabal` and add
tests for configuration identity, formatting, dispatch-neutral orchestration, and
the debug no-write invariant.

Milestone 5 publishes the authoring surface and proves the whole feature. Commit
and push the `schema/` submodule change with a Conventional Commit, update
`seihou-cli/src/Seihou/CLI/SchemaVersion.hs` to the published immutable raw URL
and Dhall hash, and verify a remote `S.Blueprint::{ ... }` containing migrations
evaluates. Update `schema/README.md`, `docs/user/blueprints.md`,
`docs/user/migrations.md`, `docs/cli/agent.md`, `seihou-cli/help/agent.md`,
`seihou-cli/help/blueprints.md`, `seihou-cli/help/migrations.md`,
`docs/dev/architecture/overview.md`, `docs/user/CHANGELOG.md`, and `CHANGELOG.md`.
The documentation must distinguish deterministic module migrations from agent
blueprint migrations, show how a library repository publishes the blueprint
through the existing registry mechanism, state that versions are explicit dotted
numbers, explain gaps/overlaps/resume/`--rerun`, and warn that each receipt records
agent completion rather than package-manager verification. Run the full format,
build, test, and Nix gates, then perform the debug demo in Validation and
Acceptance. Update the living sections of this plan after every milestone and
fill Outcomes & Retrospective when the work is complete.


## Concrete Steps

Work from the repository root:

```bash
cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
git status --short
```

The concurrently developed
`docs/plans/70-support-per-command-hierarchical-agent-model-and-provider-configuration.md`
and its implementation commits belong to the user. Preserve them and any later
unrelated changes. Do not create a feature branch unless the user explicitly
requests one.

Before editing dependency-facing launch code, repeat the Mori lookup and read the
located source rather than relying on memory:

```bash
mori registry search baikai
mori registry show shinzui/baikai --full
mori registry docs shinzui/baikai
```

Implement Milestone 1, register new source/test modules in
`seihou-core/seihou-core.cabal` and `seihou-core/test/Main.hs`, format, and run the
focused package test:

```bash
nix fmt
cabal test seihou-core-test
```

Expected final lines contain a passing test-suite result and no regression in the
existing `Seihou.Core.Migration` group:

```text
Test suite seihou-core-test: PASS
```

Implement Milestone 2 and run both affected suites:

```bash
nix fmt
cabal test seihou-core-test
cabal test seihou-cli-test
```

Implement Milestones 3 and 4, updating both Cabal module inventories and the
test-suite registration. Verify parser help before attempting a provider run:

```bash
cabal build all
cabal run seihou -- agent migrate --help
cabal test seihou-cli-test
```

The help must contain the required range and the resume override:

```text
Usage: seihou agent migrate BLUEPRINT --from VERSION --to VERSION [PROMPT]
  --rerun  Run matching migrations even when a receipt already exists
```

For the schema publication in Milestone 5, inspect the submodule first, commit its
change on its current branch using a Conventional Commit and both active trailers,
push that exact commit, then update the parent repository pin. Do not use an
unpinned branch URL. The commit message shape for every implementation commit in
both repositories is:

```text
feat(blueprint): add ordered library migrations

Describe the independently working change in this commit.

ExecPlan: docs/plans/71-run-ordered-blueprint-migrations-for-library-upgrades.md
Intention: intention_01kxzvmqgee4pvyxgeceawxqng
```

Use the repository's existing Dhall pin workflow to calculate the new integrity
hash, and prove the remote import is usable before committing the parent pin:

```bash
git -C schema status --short
git -C schema log -1 --oneline
dhall freeze seihou-core/test/fixtures/sample-blueprint/blueprint.dhall
dhall --file seihou-core/test/fixtures/sample-blueprint/blueprint.dhall >/dev/null
```

If `dhall freeze` would rewrite a fixture that intentionally uses a local schema
path, instead create a temporary Dhall file containing the immutable remote import,
freeze/evaluate that file, record the successful command in this plan, and leave
the fixture local. Never hand-guess the SHA-256 hash.

Run the complete gate from the repository root after documentation and schema pin
updates:

```bash
nix fmt
cabal build all
cabal test all
nix flake check
git diff --check
git status --short
```

All implementation commits must use Conventional Commits and end with the two
trailers shown above. Commit after each milestone only when the repository is in a
working state. Do not fold unrelated plan-70 work or other unrelated files into
this feature's commits.


## Validation and Acceptance

Acceptance begins with core behavior. `planMigrationChain` must continue to satisfy
every pre-existing module-migration test. `planBlueprintMigrationChain` must select
`1.0.0 -> 2.0.0` and `2.5.0 -> 3.0.0`, in that order, for a `1.0.0 -> 3.0.0`
request. It must return no work for equal versions, reject a downgrade, reject an
unparseable version, reject duplicate starts, skip an edge whose `to` exceeds the
target, and allow an intentional gap. Blueprint validation must reject an empty
edge prompt, `from >= to`, malformed versions, and duplicate `from`, while an old
blueprint with no migrations field must still decode to `migrations = []`.

Manifest acceptance requires a version-4 JSON fixture with no
`blueprintMigrations` key to decode as `[]`, a version-5 receipt to round-trip, and
two writes of the same exact edge to leave one updated row. Existing modules,
applications, files, recipe, and last normal blueprint provenance must survive a
migration receipt write unchanged. `seihou status` must omit the migration section
for an empty list and show the blueprint, `from -> to`, artifact version when
present, and timestamp for a populated list.

The callback-driven CLI-library tests are the main end-to-end proof of ordered and
resumable behavior without a live provider. Given three planned entries, configure
the fake launcher to succeed for the first and fail for the second. Assert that the
launch log is `[first, second]`, the recorder log is `[first]`, and the third is
never called. Run again with the first receipt supplied and a successful launcher;
assert that only `[second, third]` launches and records. With `--rerun`, assert that
all three launch. Configure a recorder failure after a successful first launch and
assert that the second never launches. Run the debug orchestration and assert that
no launcher and no recorder is invoked.

Add two migrations to a checked-in blueprint fixture and copy it into an isolated
XDG configuration for a human-observable dry run. From the repository root:

```bash
demo_root="$(mktemp -d)"
demo_project="$demo_root/project"
mkdir -p "$demo_root/config/seihou/installed" "$demo_project"
cp -R seihou-core/test/fixtures/sample-blueprint "$demo_root/config/seihou/installed/sample-blueprint"
cd "$demo_project"
XDG_CONFIG_HOME="$demo_root/config" cabal run --project-dir=/Users/shinzui/Keikaku/bokuno/seihou-project/seihou seihou -- agent --debug migrate sample-blueprint --from 1.0.0 --to 3.0.0 --var project.name=demo
test ! -e .seihou/manifest.json
```

The output wording may include provider and context details, but it must visibly
preserve these delimiters and order:

```text
Blueprint migrations for sample-blueprint: 1.0.0 -> 3.0.0
[1/2] 1.0.0 -> 2.0.0
...
[2/2] 2.5.0 -> 3.0.0
```

The final `test` command must succeed, proving debug did not fabricate receipts.
Then verify the no-op and validation paths:

```bash
XDG_CONFIG_HOME="$demo_root/config" cabal run --project-dir=/Users/shinzui/Keikaku/bokuno/seihou-project/seihou seihou -- agent --debug migrate sample-blueprint --from 3.0.0 --to 3.0.0 --var project.name=demo
XDG_CONFIG_HOME="$demo_root/config" cabal run --project-dir=/Users/shinzui/Keikaku/bokuno/seihou-project/seihou seihou -- agent --debug migrate sample-blueprint --from 3.0.0 --to 2.0.0 --var project.name=demo
```

The first command exits zero with an explicit no-work message. The downgrade exits
nonzero before variable prompts, provider launch, or manifest creation. Finally,
`cabal build all`, `cabal test all`, `nix flake check`, and `git diff --check` must
all succeed. Record the actual transcripts and dates in Progress or Surprises &
Discoveries during implementation.


## Idempotence and Recovery

Schema, decoder, planner, and test edits are ordinary source changes and can be
repeated safely. The schema submodule publication is append-only: if a published
schema commit is wrong, publish a correcting commit and update the parent pin;
never rewrite a published tag or immutable URL. `dhall freeze` is the source of
truth for the integrity hash and may be rerun after every schema edit.

At runtime, receipt filtering makes the command resumable. A successful edge is
recorded before the next begins. Re-running the same blueprint and range skips
that exact `(blueprint, from, to)` edge and continues with remaining work.
`--rerun` deliberately bypasses filtering and then upserts the receipt instead of
duplicating it. Equal start and target is a no-op. A window with no declared or no
pending edges prints a no-work message and does not create a manifest.

Agent-driven source edits are not transactional. The migration-specific prompt
must tell the agent to preserve unrelated work and run library-relevant checks,
but Seihou cannot roll back arbitrary edits. Users should begin from version
control and inspect or commit after each session. On a provider failure, Seihou
does not write that edge's receipt and does not start later edges. The user may
fix or revert the partial working tree and rerun. On a receipt-write failure,
Seihou stops immediately and reports that source edits may already exist but the
edge is unrecorded; after repairing `.seihou/manifest.json` or filesystem
permissions, the user may rerun the edge. `--rerun` is also the recovery path when
an agent exited successfully before actually completing a migration.

Debug mode is safe to repeat because it does not launch providers or change the
ledger. It may still resolve variables and read project/configuration files to
render truthful prompts. Tests must use temporary directories and fake callbacks,
never a developer's real `~/.config/seihou` or working project.


## Interfaces and Dependencies

`seihou-core/src/Seihou/Core/Migration.hs` must export these author and planner
interfaces while retaining every existing export:

```haskell
data BlueprintMigration = BlueprintMigration
  { from :: Text
  , to :: Text
  , prompt :: Text
  }

data BlueprintMigrationPlan = BlueprintMigrationPlan
  { blueprintPlanName :: Text
  , blueprintPlanFrom :: Version
  , blueprintPlanTo :: Version
  , blueprintPlanSteps :: [BlueprintMigration]
  }

planBlueprintMigrationChain
  :: Text
  -> [BlueprintMigration]
  -> Version
  -> Version
  -> Either MigrationPlanError (Maybe BlueprintMigrationPlan)
```

The blueprint-prefixed fields deliberately avoid adding more ambiguous selectors
beside the existing `MigrationPlan`. Do not change the source-compatible signature
of `planMigrationChain`. Both planners must delegate to one private gap-tolerant
window walker so their ordering cannot drift.

`Blueprint` in `seihou-core/src/Seihou/Core/Types.hs` gains the final field:

```haskell
migrations :: [BlueprintMigration]
```

`seihou-core/src/Seihou/Dhall/Eval.hs` must export
`blueprintMigrationDecoder :: Decoder BlueprintMigration` for direct decoder
tests. `seihou-core/src/Seihou/Core/Blueprint.hs` must export
`checkBlueprintMigrations :: Blueprint -> [Text]`. Older Dhall records that omit
the field must decode as an empty list.

The manifest interfaces in `seihou-core/src/Seihou/Core/Types.hs` and
`seihou-core/src/Seihou/Manifest/Types.hs` are:

```haskell
data AppliedBlueprintMigration = AppliedBlueprintMigration
  { name :: ModuleName
  , blueprintVersion :: Maybe Text
  , fromVersion :: Text
  , toVersion :: Text
  , appliedAt :: UTCTime
  , agentSessionId :: Maybe Text
  }

blueprintMigrations :: [AppliedBlueprintMigration]

writeAppliedBlueprintMigration
  :: AppliedBlueprintMigration
  -> Manifest
  -> Manifest
```

The JSON key is `blueprintMigrations`; each row uses `name`, optional `version`,
`from`, `to`, `appliedAt`, and optional `agentSessionId`. Missing manifest keys
decode to `[]`. The exact-edge key excludes blueprint artifact version and
timestamp.

`seihou-cli/src/Seihou/CLI/BlueprintExecution.hs` should expose a small
library-neutral request/result pair and helpers shared by normal and migration
blueprint execution. The final names may follow existing style, but the interface
must carry the blueprint, blueprint directory, resolved variables, optional
absolute mounted-files directory, and rendered shared prompt without importing
`Options.Applicative` or the executable `Commands` module. It must reuse
`resolveWithPrompts`, `resolveContext`, `formatReferenceFilesDir`, and
`resolveBlueprintTools` rather than implementing a second precedence hierarchy.

`seihou-cli/src/Seihou/CLI/BlueprintMigration.hs` must expose a pure pending-step
selector and an injected sequential runner with an outcome type. A suitable shape
is:

```haskell
data BlueprintMigrationRunResult
  = BlueprintMigrationNoWork
  | BlueprintMigrationComplete [BlueprintMigration]
  | BlueprintMigrationLaunchFailed BlueprintMigration ExitCode
  | BlueprintMigrationRecordFailed BlueprintMigration Text

pendingBlueprintMigrations
  :: Bool
  -> ModuleName
  -> [AppliedBlueprintMigration]
  -> BlueprintMigrationPlan
  -> [BlueprintMigration]

runBlueprintMigrationsWith
  :: (Int -> Int -> BlueprintMigration -> IO ExitCode)
  -> (BlueprintMigration -> IO (Either Text ()))
  -> [BlueprintMigration]
  -> IO BlueprintMigrationRunResult
```

If API completions need a richer error than `ExitCode`, replace the launch
callback's return with a small local success/failure type rather than losing the
provider error text. Preserve the essential contract: ordered one-at-a-time
launch, record-after-success, and stop-on-either-failure.

`seihou-cli/src/Seihou/CLI/AppliedBlueprintMigration.hs` exports:

```haskell
recordAppliedBlueprintMigration
  :: FilePath
  -> AppliedBlueprintMigration
  -> IO (Either Text ())
```

`seihou-cli/src-exe/Seihou/CLI/Commands.hs` adds an `AgentMigrate` constructor and
an option record carrying blueprint name, optional prompt, vars, `from`, `to`,
namespace, context, verbosity, rerun, provider, and model. The implementation must
use `Seihou.Core.Version.parseVersion`; it must not add a SemVer dependency or
accept prerelease syntax that module migrations reject.

The only external runtime APIs are the already-used Baikai interfaces reached
through `Seihou.CLI.AgentLaunchExec` and `Seihou.CLI.AgentCompletion`. Preserve the
current Cabal bounds. Claude and Codex interactive providers receive the same
mounted `files/` directory and effective allowed tools as normal blueprint runs;
Codex retains workspace-write/on-request safety. API providers receive rendered
text and the existing explanation that local reference files cannot be mounted.
No registry schema change is needed: the existing blueprint registry entry points
to the one blueprint artifact, whose internal `migrations` list travels with it.
