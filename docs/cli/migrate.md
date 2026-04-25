# seihou migrate

Apply module-declared migrations to the current project.

## Usage

```
seihou migrate <MODULE> [OPTIONS]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `MODULE` | Yes | The applied module to migrate. |

## Options

| Option | Description |
|--------|-------------|
| `--to VERSION` | Override the target version. Defaults to the installed module's current version. |
| `--dry-run` | Print the migration plan and exit without modifying anything. |
| `--force` | Proceed even when files have been edited since they were generated. |
| `--json` | Emit the plan as JSON instead of human-readable text. |
| `-v`, `--verbose` | Print extra detail about each operation. |

## Description

`seihou migrate` reads `.seihou/manifest.json` for the current project,
finds the named applied module, and walks the migration chain that
covers `manifest.moduleVersion → installed module's version` (or the
target you pass with `--to`). It then performs each declared
operation — file/directory rename, file/directory deletion, or shell
command — and rewrites the manifest's `files` map to reflect the new
paths.

Migrations are declared on the module's `module.dhall`. See
[module-authoring](../user/module-authoring.md#migrations) for how to
author them, and `seihou help migrations` for the full reference.

## Conflict semantics

For each move-file or delete-file op, the engine compares the disk
hash to the manifest's recorded hash:

- `safe`     — match. Free to move/delete.
- `conflict` — diverge. The user has edited the file; the engine
  refuses unless `--force` is passed.
- `gone`     — file is absent. The op is a no-op.

Without `--force`, any single conflict aborts the migration before
disk is touched. With `--force`, the migration proceeds and the
user-edited bytes ride along (a `MoveFile` preserves content; a
`DeleteFile` drops it).

## Examples

```sh
# Plan and apply the chain to the latest version of the installed copy
seihou migrate haskell-base

# Preview only
seihou migrate haskell-base --dry-run

# Stop at an intermediate version (the chain ends at 1.5.0 even if
# the installed copy is at 2.0.0)
seihou migrate haskell-base --to 1.5.0

# Overwrite files the user has edited since generation
seihou migrate haskell-base --force

# Machine-readable plan for tooling
seihou migrate haskell-base --json
```

## Exit codes

- `0` — chain applied (or dry-run completed; or already at target).
- `1` — error (no manifest, module not applied, planner refused,
  executor refused without `--force`).

## See also

- [`seihou upgrade`](upgrade.md) — fetch a newer version of an
  installed module from its source repo. Pass `--with-migrations` to
  also run `seihou migrate` against the current project for each
  upgraded module.
- [`seihou status`](status.md) — reports `Pending migrations: …`
  under any applied module whose manifest version trails the
  installed copy.
- [docs/user/migrations.md](../user/migrations.md) — full guide.
