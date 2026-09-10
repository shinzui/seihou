# Migrations

Seihou has two deliberately separate migration systems:

- **Module migrations** are deterministic `MigrationOp` sequences declared in
  `module.dhall` and applied by `seihou migrate` or `seihou update`. They own
  tracked filesystem and module-version state.
- **Blueprint migrations** are agent-guided source-code upgrade prompts declared
  in `blueprint.dhall` and run by `seihou agent migrate`. They adapt arbitrary
  consumer code and record one completion receipt per version edge.

A **migration** is an author-declared sequence of file-system operations
that moves a project's working tree from one module version to another.
When a module is upgraded — say, from `haskell-base` 1.0.0 to 2.0.0 —
the consumer project may need to rename directories, drop files that
v2 doesn't ship, or run a one-off command. Migrations let module
authors ship that knowledge inside `module.dhall` so consumers don't
have to read a CHANGELOG and reconcile by hand.

This guide covers authoring migrations. For the command reference, see
[`docs/cli/migrate.md`](../cli/migrate.md). For the in-binary topic,
run `seihou help migrations`.

## Agent-guided blueprint migrations

A library repository can publish upgrade knowledge through an ordinary installed
blueprint. Each `S.BlueprintMigration` has `from`, `to`, and `prompt`; both
versions use the same dotted numeric parser as module migrations. The consumer
can name the version window explicitly, or let seihou infer either end of it:

```sh
seihou agent migrate my-library
seihou agent migrate my-library --from 1.0.0 --to 3.0.0
```

Blueprint migrations share the gap-tolerant window walker described below, but
not the deterministic filesystem engine. Seihou runs one provider session per
selected edge, writes a receipt for that exact edge after the session returns,
and stops before the next edge on provider or receipt-write failure. A rerun
skips completed edges and resumes; `--rerun` intentionally repeats them. Parent
`--debug` prints all pending sessions without contacting a provider or changing
the manifest.

Five details differ from module migrations in ways that matter, and each is
covered fully in [Blueprint Migrations](blueprint-migrations.md):

- **A receipt is keyed by origin as well as name.** Its identity is the origin
  and name of the blueprint that owns the edge plus the edge's `from` and `to`,
  so two repositories publishing a same-named blueprint keep separate ledgers.
- **A session has three outcomes, not two.** It can do the work (*applied*),
  report that this project does not meet the edge's precondition and change
  nothing (*not applicable*), or fail. Only an applied receipt suppresses a
  later run.
- **A chain can span blueprints.** An edge may declare that crossing it
  `entails` crossing an exact edge of another blueprint, so one command can
  carry a project across a cohort of libraries released together.
- **The version window can be inferred.** `--to` comes from a `versionProbe`
  the blueprint's author declares; `--from` comes from the project's own
  receipts.
- **A receipt can be asserted rather than earned.** Plenty of people upgrade a
  library by hand and never run `seihou agent migrate` at all.
  [`--mark-applied`](blueprint-migrations.md#i-already-upgraded-by-hand) records
  the pending edges in the window as applied on the consumer's word, starting no
  session and touching no file. There is no equivalent for a module migration,
  whose operations seihou performs itself.

Each step reuses the variables, shared prompt, reference files, and allowed tools
of the blueprint that *owns* it — which under `entails` need not be the one named
on the command line — and never applies `baseModules`. A receipt records that an edge has been
dealt with — either an agent session returned, or the consumer asserted the work
was already done — not proof that a language package manager reports the target
version.
See [Blueprint Migrations](blueprint-migrations.md) for the complete workflow, and
[Agent-Driven Blueprints](blueprints.md#library-upgrade-migrations) for the Dhall
shape and registry publication.

The rest of this guide describes deterministic module migrations.

## When to author a migration

Add a migration when a new version of your module changes the **layout**
of the files it generates: a directory rename, a file removal, a path
pattern shift. You do not need a migration for content-only changes;
re-running `seihou run <module>` already updates file content.
Migrations exist specifically for changes that `seihou run` cannot
infer.

## The `migrations` field

`Module.dhall` carries a `migrations : List Migration` field that
defaults to `[]`. Each entry is one record:

```dhall
let S = ./package.dhall

in S.Module::{
  , name = "haskell-base"
  , version = Some "2.0.0"
  , steps = [ … ]
  , migrations =
      [ S.Migration::{
          from = "1.0.0",
          to = "2.0.0",
          ops =
            [ S.MigrationOp.MoveDir { src = "app", dest = "src" }
            , S.MigrationOp.DeleteFile { path = "Setup.hs" }
            ]
        }
      ]
  }
```

- `from` and `to` are dotted versions parsed by `parseVersion`.
- `ops` is the list of operations applied **in order**.

## The five operations

Migrations compose from five typed `MigrationOp` variants:

| Variant       | Purpose                                                                | Manifest effect                                              |
|---------------|------------------------------------------------------------------------|--------------------------------------------------------------|
| `MoveFile`    | Rename one tracked file.                                               | Single key rewrite (`src` → `dest`).                         |
| `MoveDir`     | Rename a directory and everything under it.                            | Every key under `src/` is rewritten with the `dest/` prefix. |
| `DeleteFile` | Remove one tracked file.                                                | Drops the key.                                               |
| `DeleteDir`  | Recursively remove a directory.                                         | Drops every key under that prefix.                           |
| `RunCommand` | Execute a shell command. The escape hatch.                              | **Not** automatically updated.                               |

Use `RunCommand` only for changes the typed ops can't express (running
a build script, applying a patch). The engine will not infer manifest
changes from a command's effect, so if your command moves files, you
must follow it with explicit `MoveFile` / `DeleteFile` ops, or live
with manifest drift.

## Window-walker semantics

The **target** defaults to the installed module's current version; pass
`--to VERSION` to stop at an intermediate version instead. When a user runs
`seihou migrate`, the planner walks every declared migration whose `[from, to]`
range falls inside `[installed, target]` in ascending `from` order:

```text
installed: 0.2    target: 0.6
declared:  0.2 → 0.3,   0.5 → 0.6
```

picks both, in order. The cursor advances from `0.2` to `0.3` after
the first edge, then jumps the `0.3 → 0.5` gap and runs the second
edge. **Gaps are permitted**: missing edges do not stop the walk.

After the in-window migrations run, the manifest's recorded
`moduleVersion` advances to the supplied target — even when no
declared migration covers the entire span. A plan with zero in-window
migrations is a "pure version bump" that advances the manifest's
version field without running any ops.

Two migrations sharing the same `from` is an error
(`MigrationDuplicateEdge`); the chain would be ambiguous. Migrations
whose `to` exceeds the target are silently skipped — a future
invocation with a higher target will pick them up. Migrations whose
`from` is already past the cursor (because an earlier edge advanced
the cursor past it) are skipped silently as well; authors who want
both a "fast-path" leapfrog migration and the smaller intermediate
edges should declare the leapfrog and let the smaller overlapping
edges sit unused.

## Conflict semantics

Mirroring [`seihou remove`](../cli/remove.md), the engine classifies
each file-targeted op into one of three states:

| Status      | Meaning                                                  | Engine action                |
|-------------|----------------------------------------------------------|------------------------------|
| `safe`      | Disk hash matches manifest.                              | Move/delete unconditionally. |
| `conflict`  | Disk hash diverges (user edited the file).               | Refuse unless `--force`.     |
| `gone`      | File absent on disk.                                      | No-op.                       |

The conflict check runs **before** any disk mutation. With one or more
conflict files and no `--force`, the migration aborts cleanly. With
`--force`, the user-edited bytes ride along (a move preserves them; a
delete drops them).

## Dry-run

```sh
seihou migrate haskell-base --dry-run
```

prints the plan and exits without touching disk. Use this on any
non-trivial migration before the real run. For a JSON form (suitable
for piping into other tooling), pass `--json`.

## Self-contained `seihou migrate`

`seihou migrate <module>` is self-contained: by default it fetches the
module's source repository, refreshes the locally installed copy, and
applies the chain in a single command. You do **not** need to run
`seihou upgrade` first.

The fetch step uses the source URL recorded in
`~/.config/seihou/installed/<name>/.seihou-origin.json` (written by
`seihou install`) and clones shallowly into a temp dir. If you have no
network or want to plan against only what's installed locally, pass
`--no-fetch`. See [`docs/cli/migrate.md`](../cli/migrate.md) for the
full flag list.

## Integration with `seihou update`

Routine project updates use `seihou update`. It fetches candidates into a
staging area, plans applicable migrations automatically, then reconciles new
generated content with user edits before publishing the cache and manifest.
This keeps the layout transition and template transition in one consent and
recovery boundary. Use `seihou migrate` directly only for focused recovery or
an explicitly chosen intermediate `--to` version.

## Integration with `seihou upgrade`

`seihou upgrade` updates the central installed copy under
`~/.config/seihou/installed/<name>/`. By default it does **not** rewrite
project trees — that would silently mutate every consumer of a shared
installed copy. Instead, it prints a one-line advisory after each
upgrade that has migrations pending in the current project:

```text
note: haskell-base has 1 migration(s) pending (1.0.0 → 2.0.0); run 'seihou update' to reconcile the recorded project application
```

Pass `--with-migrations` to run them inline:

```sh
seihou upgrade --with-migrations
```

This still operates on the **current project only** — `seihou upgrade`
does not touch other projects on disk. (Internally,
`--with-migrations` invokes `runMigrate` with `--no-fetch` because the
upgrade step has already refreshed the installed copy; there is no
need to clone again.)

## Refusing to go backwards

A migration chain is computed from the *locally installed* module's declared
migration list. If your copy of a module is older than the version
`.seihou/manifest.json` records, that chain is computed from the wrong module:
it stops short of where the project already is, and applying it rewinds the
manifest to match. This is easy to hit on a team. A teammate upgrades
`haskell-base` to `2.0.0`, runs seihou, and commits both the regenerated files
and the updated manifest. You pull that commit but have never run
`seihou upgrade`, so you still have `1.4.0`.

Before planning or generating anything, `seihou run` and `seihou migrate`
compare what the manifest records for each module against the copy installed on
your machine. If yours is older, the command stops without touching a single
file:

```text
✗ Refusing to run: your local copy of 'haskell-base' is older than the
  version this project expects.

  Recorded in .seihou/manifest.json:  2.0.0
  Installed on this machine:          1.4.0
  Origin: https://github.com/shinzui/seihou-modules.git

  Update your local copy first:
    seihou upgrade haskell-base

To proceed anyway — pinning this project to what is installed here —
re-run with --allow-downgrade.
```

Nothing is fetched over the network. Seihou tells you what to run and leaves
the decision to you. The project is byte-identical afterwards, so a refusal
costs you nothing.

The same check catches an *origin mismatch*: a module with the right name but
installed from a different git repository than the manifest records is a
different module, and seihou says so rather than generating from it.

Pass `--allow-downgrade` when pinning back is what you actually want. The
command proceeds and the manifest moves to the older version — but the blocks
are still printed, under a `! Proceeding anyway` heading, so a deliberate
downgrade never passes unremarked.

```sh
seihou run haskell-base --allow-downgrade
seihou migrate haskell-base --allow-downgrade
```

`seihou update` reaches the same outcome by a different route and also accepts
`--allow-downgrade`. It never generates from whatever is installed locally — it
clones from the origin URL the manifest itself records — so it cannot
substitute a same-named module from elsewhere. What it checks is that the
candidate version is not lower than the recorded one; if it is, the update fails
with a `candidate_downgrade` error unless you pass the flag.

A module recorded with no provenance (found in your personal
`~/.config/seihou/modules/` rather than installed from a git URL) is reported as
unverifiable rather than blocked. Its version is still compared — that comes
from its own `module.dhall` — but its identity cannot be, and seihou says so
instead of pretending otherwise.

## Integration with `seihou status`

`seihou status` also lists any artifact that differs from what the project
records, so you find out before a command refuses:

```text
Artifacts that differ from what this project records:
  haskell-base: this project expects 2.0.0 but 1.4.0 is installed here (run 'seihou upgrade haskell-base')
```

`seihou status` never fails because of this — it is a reporting command, and it
exits zero whatever it finds.

`seihou status` adds a `Pending migration: <from> -> <to> (<N>
step(s)). Run: seihou update <target>` sub-line under any applied
module whose manifest version trails the installed copy. `<N>` is the
count of declared migrations that fall in the version window; it may
be zero (a pure version bump). Recommendations are deduplicated by recorded
top-level application. Run `seihou update <target>` normally, or
`seihou migrate <module>` for focused recovery.

## Integration with `seihou run`

`seihou run` will not silently overwrite files that a pending migration
would have moved. Before computing its diff, `seihou run` checks every
module in the current composition for a pending chain. If at least one
is pending, the command refuses with an actionable message:

```text
Pending migrations detected:
  haskell-base: 1.0.0 -> 2.0.0 (3 step(s))

For a recorded project application, run 'seihou update <target>'.
For focused recovery, run 'seihou migrate <module>' for each, or pass --with-migrations to this explicit reconfiguration run.
```

This guards the previous failure mode where re-running `seihou run`
would write fresh template content into old paths, orphaning user edits
at the old layout and skipping the migration's `RunCommand` ops.

Pass `--with-migrations` to apply pending chains in-band. The migration
runs first; the run plan's diff is then computed against the
post-migration tree:

```sh
seihou run haskell-base --with-migrations
```

A pending chain on an applied module that is *not* part of the current
composition (e.g. `haskell-base` is pending but you run `seihou run
nix-flake`) does **not** block — detection is scoped to the modules in
the run.

`--with-migrations` invokes the same code path as `seihou migrate
<module> --no-fetch`: the local installed copy was already inspected
during detection, so there is no need to clone the source repo a second
time. Migration conflicts (a tracked file the user has edited since
generation) abort the run; `seihou run --force` handles diff conflicts,
not migration conflicts. Run `seihou migrate <module> --force` first if
you want to overwrite user edits during the migration.

See [`docs/cli/run.md`](../cli/run.md#pending-migrations) for the
full behavior table.

## What happens to the manifest

After a successful (non-dry-run) migration:

1. The `files` map keys reflect the new paths exactly.
2. `genAt` is bumped to the migration's timestamp.
3. The named applied module's `moduleVersion` is updated to the
   supplied target — which may differ from the highest `to` in the
   applied migrations when a gap was skipped.
4. The applied module's `removal` field is **not** touched (the next
   `seihou run` re-derives it from the new `module.dhall`).

`seihou diff` after a clean migration is empty; `seihou status`
shows no pending migrations.

## Recovery from partial failure

If a `RunCommand` op fails halfway through a chain, the disk state
reflects the operations that succeeded but the manifest is **not**
written (the handler only persists on success). The user can
inspect, fix the cause, and re-run. Partial moves surface as `gone`
(source absent) or `safe` (source still there) on the next classify
pass — both safe.

Seihou strongly assumes the project is under version control; if a
migration leaves the tree in an unrecoverable state, `git restore` is
the rollback. To land a migration in its own commit, pass `--commit`
(auto-generated message) or `--commit-message MSG` to `seihou migrate`
itself:

```sh
seihou migrate haskell-base --commit
seihou migrate haskell-base --commit-message "chore: migrate haskell-base to 1.5.0"
```

## See also

- [`docs/user/blueprint-migrations.md`](blueprint-migrations.md) —
  agent-guided library upgrades
- [`docs/cli/migrate.md`](../cli/migrate.md) — command reference
- [`docs/user/module-authoring.md`](module-authoring.md#migrations) —
  authoring section
- [`docs/user/registries-and-multi-module-repos.md`](registries-and-multi-module-repos.md#migrations-in-registries) —
  how migrations interact with multi-module repos
- `seihou help migrations` — same content, embedded in the binary
