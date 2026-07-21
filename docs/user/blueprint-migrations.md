# Blueprint Migrations

A **blueprint migration** is an agent-guided upgrade step that a library author
ships with their blueprint. Each step describes one version edge — "moving from
1.0.0 to 2.0.0 requires these source changes" — as a Markdown prompt. Consumers
run the edges that fall inside an explicit version window:

```sh
seihou agent migrate my-library --from 1.0.0 --to 3.0.0
```

Seihou selects the declared edges inside that window, orders them, and runs one
agent session per edge. After each session returns successfully it records a
receipt in `.seihou/manifest.json`, so an interrupted chain resumes where it
stopped instead of repeating completed work.

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
2. It parses `--from` and `--to` and asks the core planner which declared edges
   fall inside that window.
3. It drops edges that already have a receipt, unless `--rerun` was passed.
4. It resolves the blueprint's variables once and renders the shared prompt.
5. For each remaining edge, in ascending order: start one provider session, wait
   for it to return, then write that edge's receipt before starting the next.
6. On a provider failure or a receipt-write failure, it stops immediately and
   leaves earlier receipts in place.

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

Reference files under `files/` are shared by every edge. Interactive `claude-cli`
and `codex-cli` sessions get the directory mounted and its absolute path printed
in the prompt; API providers cannot read local files and are told to ask the user
instead. `allowedTools` is likewise shared by every edge. There is no per-edge
`files` or `allowedTools`.

Migration mode never applies `baseModules`, so a blueprint can safely serve both
purposes: scaffolding new projects through `seihou agent run` and upgrading
existing ones through `seihou agent migrate`. Normal runs ignore `migrations`
entirely.

### Validate and publish

```sh
seihou validate-blueprint my-library
```

Validation rejects an empty edge prompt, an unparseable version, an edge whose
`from` is not strictly less than its `to`, and duplicate `from` versions,
alongside the usual blueprint checks.

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
===== [1/2] 1.0.0 -> 2.0.0 =====
...
===== [2/2] 2.5.0 -> 3.0.0 =====
...
```

Use it to see which edges apply, read what the agent will be told, and confirm
that the reference files resolved.

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

Each edge announces itself before its session starts:

```text
Running blueprint migration 1/2: 1.0.0 -> 2.0.0
```

An optional trailing `PROMPT` argument is passed as the initial user instruction
to every session in the chain, and `--var KEY=VALUE` overrides blueprint
variables. Provider, model, and reasoning effort resolve through the standard
hierarchy with `agent.migrate.provider`, `agent.migrate.model`, and
`agent.migrate.effort` overriding the shared `agent.*` defaults for this command
only; see [AI Agent Assistance](agent-assistance.md).

### Inspect what was recorded

```sh
seihou status
```

```text
Blueprint migrations:
  my-library v0.3.0: 1.0.0 -> 2.0.0 (applied 2026-07-20 15:02 UTC)
  my-library v0.3.0: 2.5.0 -> 3.0.0 (applied 2026-07-20 15:19 UTC)
```

The section is omitted entirely when no migration has been recorded.

### Resume, repeat, and re-run

Re-running the same command skips edges that already have a receipt and continues
with the rest — that is the resume path after a failure, an interruption, or a
deliberate pause:

```text
Blueprint migrations for my-library: 1.0.0 -> 3.0.0
===== [1/1] 2.5.0 -> 3.0.0 =====
```

When the whole window is already recorded, Seihou exits zero without doing
anything:

```text
All blueprint migrations in the requested version window already have receipts.
```

Pass `--rerun` to ignore matching receipts and execute the selected edges again —
the recovery path when an agent exited successfully without actually finishing the
work. A re-run updates the existing receipt in place rather than appending a
duplicate.

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

A receipt records that the provider interaction for one exact
`(blueprint, from, to)` tuple returned successfully. It does **not** prove that
your package manager now reports the target version, that the build passes, or
that every call site was updated. Seihou cannot verify arbitrary libraries across
ecosystems, so the burden of proof sits in the edge prompt (which validation to
run) and in your review.

Treat the receipt as chain bookkeeping — "this step has been attempted and
returned" — and verify the outcome yourself before shipping.

## Troubleshooting

| Message | Meaning and fix |
|---------|-----------------|
| `--from value '1.0.0-rc1' is not a valid dotted numeric version.` | Only dotted numbers are accepted. Use the release version without prerelease or build metadata. |
| `blueprint migration downgrades are not supported: --from 3.0.0, --to 2.0.0.` | Migrations only run forward. Downgrade by reverting source changes in version control. |
| `the blueprint declares more than one migration starting at 2.0.0; the author must merge or remove the duplicate.` | An authoring error in the installed blueprint. Report it upstream; the author must merge or drop one edge. |
| `'my-library' is a module, not a blueprint.` | `agent migrate` only accepts blueprints. Check the name, or use `seihou migrate` for module migrations. |
| `Blueprint migration 2.5.0 -> 3.0.0 failed; completed earlier edges remain recorded. …` | The provider exited nonzero or returned an error. Fix the provider problem, then rerun the same command to resume at that edge. |
| `Agent completed blueprint migration …, but its receipt could not be recorded: …` | Source edits may already exist while the edge is unrecorded, and the next edge was not started. Repair `.seihou/manifest.json` or its permissions, then rerun the same command. |
| Nothing renders under `--debug` | Every edge in the window already has a receipt, or the blueprint declares none there. Widen the window or pass `--rerun`. |

## See also

- [Agent-Driven Blueprints](blueprints.md) — the blueprint format, validation, and publishing.
- [Migrations](migrations.md) — deterministic module migrations.
- [AI Agent Assistance](agent-assistance.md) — providers, models, effort, and debug mode.
- [`seihou agent`](../cli/agent.md) — the command reference.
- [`seihou status`](../cli/status.md) — reading recorded project state.
- [Registries and Multi-Module Repositories](registries-and-multi-module-repos.md) — publishing the blueprint.
