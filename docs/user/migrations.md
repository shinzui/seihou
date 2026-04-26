# Migrations

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

## Chain semantics

When a user runs `seihou migrate`, the planner finds a contiguous
sequence of migrations that spans the project's recorded version up
to the target:

```text
installed: 1.0.0    target: 3.0.0
declared:  1.0.0 → 2.0.0,  2.0.0 → 3.0.0
```

picks both, in order. The chain is **strictly contiguous**: each step's
`to` must equal the next step's `from`. There is no graph search and no
skipping. Two migrations sharing the same `from` is an error
(`MigrationDuplicateEdge`); a single migration that overshoots the
target is an error (`MigrationOvershoot`).

This rule lets authors ship "fast-path" migrations
(e.g. 1.0.0 → 3.0.0) and have the planner pick whichever edge lands on
the target — without ambiguity. If you ship both `1.0.0 → 2.0.0` and
`1.0.0 → 3.0.0`, the planner refuses; pick one.

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

## Integration with `seihou upgrade`

`seihou upgrade` updates the central installed copy under
`~/.config/seihou/installed/<name>/`. By default it does **not** rewrite
project trees — that would silently mutate every consumer of a shared
installed copy. Instead, it prints a one-line advisory after each
upgrade that has migrations pending in the current project:

```text
note: haskell-base has 1 migration(s) pending (1.0.0 → 2.0.0); run 'seihou migrate haskell-base'
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

## Integration with `seihou status`

`seihou status` adds a `Pending migrations: N migration(s) pending: a → b`
sub-line under any applied module whose manifest version trails the
installed copy with a covering chain. The line is informational; run
`seihou migrate <module>` to apply.

## What happens to the manifest

After a successful (non-dry-run) migration:

1. The `files` map keys reflect the new paths exactly.
2. `genAt` is bumped to the migration's timestamp.
3. The named applied module's `moduleVersion` is updated to the
   chain's target.
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
the rollback. See [`docs/cli/run.md`](../cli/run.md) for the
`--commit` flag if you want migrations to land in a dedicated
commit.

## See also

- [`docs/cli/migrate.md`](../cli/migrate.md) — command reference
- [`docs/user/module-authoring.md`](module-authoring.md#migrations) —
  authoring section
- [`docs/user/registries-and-multi-module-repos.md`](registries-and-multi-module-repos.md#migrations-in-registries) —
  how migrations interact with multi-module repos
- `seihou help migrations` — same content, embedded in the binary
