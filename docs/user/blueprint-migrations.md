# Blueprint Migrations

A **blueprint migration** is an agent-guided upgrade step that a library author
ships with their blueprint. Each step describes one version edge — "moving from
1.0.0 to 2.0.0 requires these source changes" — as a Markdown prompt. Consumers
run the edges that fall inside an explicit version window:

```sh
seihou agent migrate my-library --from 1.0.0 --to 3.0.0
```

Seihou selects the declared edges inside that window, orders them, and runs one
agent session per edge. After each session returns it records a receipt in
`.seihou/manifest.json`, so an interrupted chain resumes where it stopped instead
of repeating completed work.

This guide covers both sides: publishing upgrade knowledge as a library author,
and running an upgrade as a consumer. For the command flags, see
[`seihou agent`](../cli/agent.md#agent-migrate). For deterministic module
migrations, see [Migrations](migrations.md).

## When to use one

Seihou has two migration systems, and they solve different problems.

| Use | When the upgrade is |
|-----|---------------------|
| [Module migration](migrations.md) (`seihou migrate`) | A declared sequence of file operations on files Seihou generated: rename a directory, delete a dropped file, run a fixed command. Deterministic and reversible in principle. |
| Blueprint migration (`seihou agent migrate`) | Judgement work across source code Seihou never generated: a renamed API used in arbitrary call sites, a restructured configuration record, an idiom that changed shape. |

Reach for a blueprint migration when the upgrade cannot be expressed as file
operations because the required edit depends on how each project actually uses
the library. If the change is mechanical and touches only generated files, a
module migration is the better tool: it is deterministic, it can be dry-run
exactly, and it updates tracked file state.

A blueprint migration is also different from a plain `seihou agent run`. A run
applies a blueprint's baseline modules and its single prompt once. A migration
never applies `baseModules`, selects prompts by version window, and keeps durable
per-edge state.

## How a migration runs

1. Seihou discovers and validates the named blueprint.
2. It checks the blueprint against what this project records about it — from the
   applied-blueprint entry when there is one, otherwise from the most recent
   receipt — and refuses before planning a single edge when the installed copy
   is older than, or came from a different repository than, the project records.
3. It parses `--from` and `--to` and asks the core planner which declared edges
   fall inside that window.
4. It follows any [entailed edges](#entail-another-librarys-edge) those edges
   declare, loading each named blueprint and expanding recursively, so the chain
   becomes an ordered list of steps that may span several blueprints. It checks
   each of those blueprints the same way it checked the one you named.
5. It drops steps that already have an *applied* receipt **under their own
   blueprint's identity**, unless `--rerun` was passed.
6. It resolves the variables of every blueprint that owns a remaining step, all
   before the first session starts, and renders each one's shared prompt.
7. For each remaining step, in order: start one provider session with its owning
   blueprint's reference files and allowed tools, wait for it to return, then
   write that step's receipt before starting the next.
8. On a provider failure or a receipt-write failure, it stops immediately and
   leaves earlier receipts in place.

Step 7 has three outcomes, not two. The session can return having done the work
(recorded **applied**), it can return having reported that this edge's
precondition is unmet in this project (recorded **not applicable**, and the chain
continues to the next edge), or the provider can fail (nothing recorded, and the
chain stops so you can resume at that edge). Only an applied receipt suppresses a
later run of its edge.

Step 2 runs before planning on purpose. A blueprint of the recorded name from a
different repository declares different edges, so planning first would launch a
provider session carrying another library's upgrade prompt against your source.
The check is skipped under `--debug`, which contacts no provider and writes
nothing. `--allow-downgrade` proceeds anyway and prints what it overrode.

Because the receipt is written between sessions, the chain is always resumable at
a known edge.

## For library authors

### Lay out the blueprint

`seihou new-blueprint my-library` scaffolds `blueprint.dhall`, `prompt.md`, and
`files/`. Add a `migrations/` directory yourself for the per-edge prompts:

```text
my-library/
├── blueprint.dhall
├── prompt.md          # shared guidance for every edge
├── migrations/        # one Markdown file per version edge (create this)
│   ├── 1-to-2.md
│   └── 2-5-to-3.md
└── files/             # reference material mounted for CLI providers
```

The directory name is a convention, not a requirement — an edge prompt can be
imported from any path, or written inline in `blueprint.dhall`.

### Declare the edges

Each entry in `migrations` has a dotted numeric `from`, a dotted numeric `to`,
and a prompt. Import the prompt body from `migrations/` so the Markdown stays
readable and reviewable:

```dhall
migrations =
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
```

Declare an edge only for releases that need help. The gap between `2.0.0` and
`2.5.0` above is intentional and legal: it means no agent intervention was needed
in that interval. Two entries may not start at the same `from` version.

Versions are dotted numeric values (`1`, `1.2`, `1.0.0`). Prerelease and build
syntax such as `1.0.0-rc1` is rejected, the same as in module migrations.

### Write an edge prompt

Seihou renders one system prompt per edge that contains, in order: the working
directory and project state, the blueprint's identity, the edge and its position
in the chain (`Step 1 of 2`), the declared reference files, your blueprint's
shared `prompt` under "Shared Blueprint Guidance", and your edge prompt under
"Instructions for This Edge". Seihou's own framing already tells the agent to
inspect real usage before assuming an API exists, to change only what this edge
requires, to preserve unrelated user changes, to avoid pre-applying later edges,
and to summarize changed files and validation results before exiting.

So write the edge prompt as the library-specific half of that contract:

- Name the exact APIs, modules, or configuration keys that changed, and what they
  became.
- Describe the shape of the change, not just its name — a renamed function with a
  new argument order needs the new order spelled out.
- Say which project validation proves the edge worked (`cabal build`, `npm test`,
  a type-check, a specific test suite).
- Call out anything the agent must *not* do, such as pulling in an API that only
  arrives in a later release.

`{{variable.name}}` placeholders are substituted in both the shared prompt and
edge prompts using the blueprint's resolved variables, so an edge prompt can
address the consumer's project by name.

### State the edge's precondition

Write down what has to be true of a project for the edge to mean anything: the
library is actually used here, the feature this edge upgrades was adopted, the
change is not already present. One blueprint often serves projects in very
different states, and an edge that does not apply is a normal result rather than
an error.

You do not have to invent a way to say so. Seihou's framing already tells the
agent that when the precondition is unmet the correct action is to change nothing
and report it, and gives it the mechanism — a one-line reason written to a signal
file under `.seihou/`, or a trailing `SEIHOU: not-applicable <reason>` line when
the provider cannot write files. Seihou records the attempt with that outcome,
prints the reason, and moves to the next edge; the edge is not marked done, so it
runs again once the precondition is met.

So the edge prompt only needs to say what the precondition *is*. Do not tell an
edge to exit nonzero when it does not apply: that reports a provider failure and
halts every remaining edge.

Reference files under `files/` are shared by every edge *of one blueprint*, as is
`allowedTools`; there is no per-edge `files` or `allowedTools`. A step reached
through [entailment](#entail-another-librarys-edge) is owned by another blueprint
and gets that blueprint's files and tools instead, never yours. Interactive
`claude-cli` and `codex-cli` sessions get the owning blueprint's directory
mounted and its absolute path printed in the prompt; API providers cannot read
local files and are told to ask the user instead.

Migration mode never applies `baseModules`, so a blueprint can safely serve both
purposes: scaffolding new projects through `seihou agent run` and upgrading
existing ones through `seihou agent migrate`. Normal runs ignore `migrations`
entirely.

### Entail another library's edge

Sometimes the breaking change you are helping consumers absorb is not yours.
Suppose `kiroku` ships a breaking change, your library `keiro` depends on kiroku
and absorbs that change in its `3.0.0` release, and most of your consumers depend
on keiro and have never heard of kiroku. They know their keiro version. They
neither know nor should have to look up which kiroku version keiro pulls in. So
kiroku's upgrade knowledge has to reach them through *your* version space —
without being copied into your repository, and without running twice for the
minority of projects that also depend on kiroku directly.

An edge can declare that crossing it **entails** crossing an exact edge of
another blueprint:

```dhall
migrations =
  [ S.BlueprintMigration::{
    , from = "2.4.0"
    , to = "3.0.0"
    , prompt = ./migrations/2-4-to-3.md as Text
    , entails =
      [ S.EntailedEdge::{
        , blueprint = "kiroku-upgrade"
        , from = "1.9.0"
        , to = "2.0.0"
        }
      ]
    }
  ]
```

A consumer then runs one command and gets both edges:

```sh
seihou agent migrate keiro-upgrade --from 2.4.0 --to 3.0.0
```

```text
Running blueprint migration 1/2: kiroku-upgrade 1.9.0 -> 2.0.0 (entailed by keiro-upgrade 2.4.0 -> 3.0.0)
Running blueprint migration 2/2: keiro-upgrade 2.4.0 -> 3.0.0
```

The rules, none of which are visible from the field's type, so they are worth
stating plainly:

- **Entailed edges run first**, and several of them run in the order you list
  them. The entailed edge is the deeper change, and your own edge's guidance may
  assume it has already been applied.
- **Expansion is recursive.** An entailed edge may itself entail others, so a
  three-deep cohort works without any blueprint knowing the whole graph. A cycle
  is an authoring error, reported with the chain that closed it.
- **The reference is to one exact edge**, matched on both `from` and `to`.
  Seihou will not window-plan inside the entailed blueprint on your behalf,
  because that would let one of your releases silently change which upstream work
  it implies.
- **The entailed edge runs under its own blueprint's context** — that blueprint's
  shared prompt, edge prompt, `files/`, `allowedTools`, and variables. Its
  `launch` declaration is ignored: one command cannot switch providers between
  edges, so the blueprint the consumer named decides provider, model, and effort.
- **The receipt goes to the entailed blueprint**, under its name and origin. That
  is what makes a shared edge crossed once: a project that reached kiroku's edge
  through keiro has a kiroku receipt, so running `seihou agent migrate
  kiroku-upgrade` afterwards finds nothing to do — and the reverse order works
  the same way.
- **A blueprint may not entail an edge of itself.** Ordering within your own
  `migrations` list is already decided by the version window.
- **The entailed blueprint must be installed.** If it is not, the run fails with
  an install hint rather than skipping the step, because your consumer does not
  know the cohort and a silently omitted member leaves a half-migrated project
  with no signal at all.

Write the entailed blueprint's edge so it survives being run by a project that
does not use that library directly — which, for a cohort like this one, is most
of them. That is what [the precondition](#state-the-edges-precondition) is for:
an entailed edge that finds no direct usage should report itself not applicable
and change nothing, and it will run again later if the project starts using the
library. Seihou's framing tells the agent that an indirectly reached edge is the
ordinary case for inapplicability, and tells it which edge required this one.

Nothing records the cohort. It is recomputed from these declarations on every
run, so adding, removing, or retargeting an entailment takes effect the moment
consumers install the new blueprint version.

### Validate and publish

```sh
seihou validate-blueprint my-library
```

Validation rejects an empty edge prompt, an unparseable version, an edge whose
`from` is not strictly less than its `to`, and duplicate `from` versions,
alongside the usual blueprint checks. For `entails` it rejects a malformed
blueprint name, an unparseable or non-advancing entailed window, an edge that
entails its own blueprint, and the same entailed edge listed twice. Whether the
named blueprint exists and declares that edge is a filesystem question, so it is
checked when `seihou agent migrate` resolves the cohort rather than here.

Publication uses the existing registry mechanism — there is no separate migration
registry. Point a `blueprints` entry at the directory containing
`blueprint.dhall`:

```dhall
blueprints =
  [ { name = "my-library"
    , version = Some "0.3.0"
    , path = "blueprints/my-library"
    , description = Some "Upgrade guidance for my-library consumers"
    , tags = [ "migration" ]
    }
  ]
```

Consumers then install it like any other artifact:

```sh
seihou install https://github.com/acme/my-library.git --module my-library
```

Bump the blueprint's own `version` as you add edges. That version is recorded in
receipts as audit metadata; it is not part of the identity of a completed edge,
so publishing a new blueprint version never silently re-runs an upgrade.

## For consumers

### Preview before running

`--debug` on the parent `agent` command is a true dry run for migrations: it
renders every pending session in order, contacts no provider, and writes nothing.

```sh
seihou agent --debug migrate my-library --from 1.0.0 --to 3.0.0
```

```text
Blueprint migrations for my-library: 1.0.0 -> 3.0.0
===== [1/2] my-library 1.0.0 -> 2.0.0 =====
...
===== [2/2] my-library 2.5.0 -> 3.0.0 =====
...
```

Use it to see which edges apply, read what the agent will be told, and confirm
that the reference files resolved.

Every step is labelled with the blueprint that owns it, because a chain can span
several. When a library's upgrade requires another library's, the entailed step
appears first and says what pulled it in:

```text
Blueprint migrations for keiro-upgrade: 2.4.0 -> 3.0.0
===== [1/2] kiroku-upgrade 1.9.0 -> 2.0.0 (entailed by keiro-upgrade 2.4.0 -> 3.0.0) =====
...
===== [2/2] keiro-upgrade 2.4.0 -> 3.0.0 =====
...
```

### Run the upgrade

```sh
seihou agent migrate my-library --from 1.0.0 --to 3.0.0
```

Supply both versions explicitly. Seihou is language-agnostic and does not read
Cabal, npm, Cargo, or Maven files to guess which version you are on or where you
are going.

Start from a clean working tree. Agent edits are not transactional, and Seihou
cannot roll them back — version control is your undo. Reviewing (or committing)
between edges is a good habit for long chains.

Each edge announces itself before its session starts, named by the blueprint that
owns it:

```text
Running blueprint migration 1/2: my-library 1.0.0 -> 2.0.0
```

An edge that reports its precondition unmet says so on the way past, and the run
summary counts it separately:

```text
Blueprint migration 1/2: my-library 1.0.0 -> 2.0.0 — not applicable: the project has not adopted the bundle
Running blueprint migration 2/2: my-library 2.5.0 -> 3.0.0
...
Completed 2 blueprint migration(s) for 'my-library' (1 not applicable).
```

An optional trailing `PROMPT` argument is passed as the initial user instruction
to every session in the chain, and `--var KEY=VALUE` overrides blueprint
variables. Provider, model, and reasoning effort resolve through the standard
hierarchy with `agent.migrate.provider`, `agent.migrate.model`, and
`agent.migrate.effort` overriding the shared `agent.*` defaults for this command
only; see [AI Agent Assistance](agent-assistance.md).

### One command may cross several libraries

A library author can declare that one of their edges requires an exact edge of
another library's blueprint — see
[Entail another library's edge](#entail-another-librarys-edge). Three
consequences are worth knowing before you run an upgrade:

- The chain may include steps from a blueprint you did not name and may never
  have heard of. It has to be installed; if it is not, the run refuses and prints
  what to install rather than silently skipping it.
- You may be prompted for variables that blueprint declares. Every prompt is
  asked before the first session starts, so you are not interrupted mid-chain.
  `--var`, `--namespace`, and `--context` apply to every blueprint in the chain.
- `seihou status` lists those steps' receipts under *their* blueprint's name, not
  the one you typed. That is deliberate: it is what stops the same shared edge
  being crossed twice if you later run that blueprint directly.

Provider, model, and effort stay a property of the command. An entailed
blueprint's own `launch` declaration is ignored.

### Inspect what was recorded

```sh
seihou status
```

```text
Blueprint migrations:
  my-library v0.3.0: 1.0.0 -> 2.0.0 (applied 2026-07-20 15:02 UTC)
  my-library v0.3.0: 2.5.0 -> 3.0.0 (not applicable 2026-07-20 15:19 UTC -- no direct kiroku imports)
```

The section is omitted entirely when no migration has been recorded. A long
reason is truncated here; the whole of it is in `.seihou/manifest.json`.

### Resume, repeat, and re-run

Re-running the same command skips edges that already have an applied receipt and
continues with the rest — that is the resume path after a failure, an
interruption, or a deliberate pause:

```text
Blueprint migrations for my-library: 1.0.0 -> 3.0.0
===== [1/1] my-library 2.5.0 -> 3.0.0 =====
```

When the whole window is already recorded, Seihou exits zero without doing
anything:

```text
All blueprint migrations in the requested version window already have receipts.
```

An edge recorded as **not applicable** is planned again on the next run, without
`--rerun`. That is the point of the outcome: the precondition it reported unmet
is usually the very thing the edge told you to fix, so the run after you fix it
must reach the edge. When it then does the work, its receipt is replaced in place
and the edge stops being replanned.

Pass `--rerun` to ignore matching receipts and execute the selected edges again —
the recovery path when an agent exited successfully without actually finishing the
work, and the remedy for a receipt that says applied when the edge really did
nothing. A re-run updates the existing receipt in place rather than appending a
duplicate.

`--rerun` re-runs *every* step in the expanded chain, including steps owned by
other blueprints. To re-run only one library's half, invoke that library's
blueprint directly with its own version window: running an entailed blueprint by
name never expands anything it does not need.

## How the version window is planned

Blueprint migrations use the same gap-tolerant planner as module migrations. An
edge is selected when it starts at or after the cursor (initially `--from`) and
ends at or before `--to`; selecting it advances the cursor to its `to`.

| Situation | Result |
|-----------|--------|
| Undeclared gap between edges (`2.0.0` → `2.5.0`) | Allowed. The gap needed no agent work. |
| Edge overlapping one already selected | Skipped, because the cursor has advanced past its `from`. |
| Edge whose `to` overshoots `--to` | Deferred. It runs in a later invocation with a wider window. |
| `--from` equals `--to` | `No blueprint migration needed: --from and --to resolve to the same version.` Exit 0. |
| No declared edge inside the window | `No blueprint migrations are declared inside the requested version window.` Exit 0. |
| `--to` lower than `--from` | Rejected before any prompt, launch, or manifest write. Exit 1. |
| Two edges declaring the same `from` | Rejected as an authoring error. Exit 1. |

## What a receipt means

A receipt records that the provider interaction for one exact edge returned, and
what it reported. It does **not** prove that your package manager now reports the
target version, that the build passes, or that every call site was updated.
Seihou cannot verify arbitrary libraries across ecosystems, so the burden of
proof sits in the edge prompt (which validation to run) and in your review.

Treat the receipt as chain bookkeeping — "this step has been attempted and
returned" — and verify the outcome yourself before shipping.

A receipt carries one of two outcomes:

| Outcome | Means | Effect on a later run |
|---------|-------|-----------------------|
| **applied** | The session returned having been asked to do the work. Not proof it succeeded. | The edge is skipped unless `--rerun` is passed. |
| **not applicable** | The session reported that the edge's precondition is unmet in this project and deliberately changed nothing. The reason is recorded with it. | The edge is planned again, no flag needed. |

The distinction exists because a deliberate, correct no-op used to be
indistinguishable from a completed upgrade: the edge was recorded as done, so the
run that *should* have happened once the precondition was met was silently
skipped.

### Which edge a receipt is for

A receipt identifies its edge by four things: the **origin** and the **name** of
the blueprint that owns the edge, plus the edge's `from` and `to` versions. The
blueprint's own release version and the receipt's timestamp are deliberately not
part of that identity — an edge is the same edge no matter which release of the
blueprint declared it.

"The blueprint that owns the edge" is exact wording. For a step reached through
[entailment](#entail-another-librarys-edge) the owner is the blueprint whose
`migrations` list actually declares it, not the one you typed on the command
line. That is the whole mechanism by which a shared cohort edge is crossed once
from either entry point.

Origin is part of the identity because two repositories can publish a blueprint
under the same name. If `github.com/acme/one` and `github.com/acme/two` both ship
a `shared-upgrade` blueprint with a `1.0.0 -> 2.0.0` edge, those are different
prompts doing different work, and running one must not make seihou believe the
other has been done. Each keeps its own receipt, and a project that consumes both
crosses both edges.

Two spellings of one git URL are one origin: `https://host/repo`,
`https://host/repo.git` and `https://host/repo/` all match each other.

A blueprint discovered somewhere with no provenance seihou can prove — a personal
blueprint in `~/.config/seihou/blueprints/`, for instance — is recorded honestly
as having no verifiable origin, and its receipts match only other receipts in the
same situation.

Receipts written before seihou recorded origins at all are read the same way.
The first `seihou agent migrate` run after upgrading to a seihou that does may
therefore list an edge you have already completed as pending, because seihou
genuinely cannot prove the recorded edge came from the blueprint now installed.
Re-run it — edge prompts are written to inspect real usage first, so a completed
edge finds nothing to do — or skip it deliberately by widening `--from`.

## Troubleshooting

| Message | Meaning and fix |
|---------|-----------------|
| `--from value '1.0.0-rc1' is not a valid dotted numeric version.` | Only dotted numbers are accepted. Use the release version without prerelease or build metadata. |
| `blueprint migration downgrades are not supported: --from 3.0.0, --to 2.0.0.` | Migrations only run forward. Downgrade by reverting source changes in version control. |
| `the blueprint declares more than one migration starting at 2.0.0; the author must merge or remove the duplicate.` | An authoring error in the installed blueprint. Report it upstream; the author must merge or drop one edge. |
| `'my-library' is a module, not a blueprint.` | `agent migrate` only accepts blueprints. Check the name, or use `seihou migrate` for module migrations. |
| `'keiro-upgrade' edge 2.4.0 -> 3.0.0 entails blueprint 'kiroku-upgrade', which is not installed on this machine.` | The upgrade you asked for requires another library's upgrade guidance. Install it with the printed command and re-run. Seihou will not skip it: doing so would leave the project half-migrated with no signal. |
| `'keiro-upgrade' edge 2.4.0 -> 3.0.0 entails edge 1.9.0 -> 2.0.0 of 'kiroku-upgrade', which declares no such edge.` | An authoring error in `keiro-upgrade`, usually an off-by-one in a version string; the message lists the edges `kiroku-upgrade` really declares. Report it upstream. Meanwhile you can run each blueprint directly by name — a blueprint invoked by name expands nothing it does not need, so it is unaffected by the other's mistake. |
| `blueprint migration entailment forms a cycle: …` | Two or more blueprints each declare that the other's edge must run first, so no order satisfies them all. An authoring error in the blueprints listed; report it upstream and run each directly by name in the meantime. |
| `Blueprint migration 2.5.0 -> 3.0.0 failed; completed earlier edges remain recorded. …` | The provider exited nonzero or returned an error. Fix the provider problem, then rerun the same command to resume at that edge. |
| `Agent completed blueprint migration …, but its receipt could not be recorded: …` | Source edits may already exist while the edge is unrecorded, and the next edge was not started. Repair `.seihou/manifest.json` or its permissions, then rerun the same command. |
| `Blueprint migration 1/2: 1.0.0 -> 2.0.0 — not applicable: …` | Not an error. The edge reported its precondition unmet and changed nothing; the chain continued. Fix what the reason names and rerun the same command — the edge runs, no `--rerun` needed. If you disagree with the agent's judgement, `--rerun` forces it now. |
| Nothing renders under `--debug` | Every edge in the window already has a receipt, or the blueprint declares none there. Widen the window or pass `--rerun`. |
| `✗ Refusing to run: your local copy of 'my-library' is older than the version this project expects.` | The installed blueprint predates what this project records. Run `seihou upgrade my-library`, or pass `--allow-downgrade` to pin the project to the copy installed here. |
| `✗ Refusing to run: 'my-library' is installed from a different source than this project records.` | A blueprint of that name from another repository is installed. Its edges are not this project's edges. Reinstall from the URL the message prints, or pass `--allow-downgrade` if the substitution is deliberate. |

## See also

- [Agent-Driven Blueprints](blueprints.md) — the blueprint format, validation, and publishing.
- [Migrations](migrations.md) — deterministic module migrations.
- [AI Agent Assistance](agent-assistance.md) — providers, models, effort, and debug mode.
- [`seihou agent`](../cli/agent.md) — the command reference.
- [`seihou status`](../cli/status.md) — reading recorded project state.
- [Registries and Multi-Module Repositories](registries-and-multi-module-repos.md) — publishing the blueprint.
