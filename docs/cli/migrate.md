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
| `--to VERSION` | Override the target version. Defaults to the installed module's current version (after fetch, this is the remote's version). |
| `--dry-run` | Print the migration plan and exit without modifying anything. The remote is still fetched so the planned chain reflects what would actually run. |
| `--force` | Proceed even when files have been edited since they were generated. |
| `--json` | Emit the plan as JSON instead of human-readable text. |
| `--no-fetch` | Skip the remote fetch; plan against the locally installed copy only. Useful for offline / hermetic workflows. |
| `-v`, `--verbose` | Print extra detail about each operation. |

## Default behavior: fetch first

By default, `seihou migrate` is **self-contained** — it does not require
a separate `seihou upgrade` first. The flow:

1. Read `.seihou-origin.json` from the locally installed copy
   (`~/.config/seihou/installed/<name>/`) to discover the source URL.
2. Clone the source repository shallowly into a temp dir.
3. Locate the module within the clone (single-module or multi-module
   registry) and use its `module.dhall` as the source of truth — this
   is what supplies the migrations list and the target version.
4. Plan the chain from the manifest's recorded version to the remote's
   version.
5. On a successful non-dry-run apply, refresh the on-disk installed
   copy from the clone (the same step `seihou upgrade` performs).

If any of those steps fails softly (no `.seihou-origin.json`, clone
failure, module not present in the remote), the command emits a
one-line note and falls back to the local-only path: planning against
whatever the locally installed copy currently declares.

Pass `--no-fetch` to skip the fetch entirely. In that mode, `migrate`
performs no network IO and behaves like the pre-EP-2 implementation:
it consults only `~/.config/seihou/installed/<name>/module.dhall`. Use
this for offline workflows or when you have already refreshed the
installed copy by hand.

## Description

`seihou migrate` reads `.seihou/manifest.json` for the current project,
finds the named applied module, and walks the migration chain that
covers `manifest.moduleVersion → target_version`. By default
`target_version` is whatever the **remote**'s `module.dhall` declares
(after the fetch step described above); pass `--to` to stop earlier.
The command then performs each declared operation — file/directory
rename, file/directory deletion, or shell command — and rewrites the
manifest's `files` map to reflect the new paths.

Migrations are declared on the module's `module.dhall`. See
[module-authoring](../user/module-authoring.md#migrations) for how to
author them, and `seihou help migrations` for the full reference.

## Partial chains and blocked modules

The declared migration list does not always reach the latest remote
version exactly. `seihou migrate` distinguishes three outcomes:

- **Full chain** — the declared migrations cover
  `manifest.moduleVersion → remote_version` exactly. The chain runs to
  completion, the manifest is bumped to `remote_version`, and the
  command exits zero.
- **Partial chain** — the chain reaches some intermediate version and
  then stops because no migration starts at that version. Without
  `--to`, `migrate` applies the longest reachable prefix, refreshes the
  manifest's `moduleVersion` to the highest reached version, and prints
  a `Note: no migration declared from <stuckAt>; remote is at <target>`
  advisory. The next `seihou status` will show the same module either
  blocked or up-to-date depending on whether the author later ships a
  continuation migration.
- **Blocked** — no migration starts at the manifest version, so the
  planner has nothing to apply. Without `--to`, `migrate` prints
  `Blocked: no migration declared from <manifest-version>; remote is at
  <target>. The module author must ship one before this project can
  move forward.` and exits zero (no work was done; no manifest change).

Passing `--to TARGET` keeps the strict-target contract: if the
declared chain cannot reach `TARGET` exactly (partial *or* blocked),
the command errors with `no migration covers the gap from <X> to
<TARGET>`. Use `--to TARGET` when you need a specific version; omit it
when you want "as far as the declared chain can go."

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
# Fetch the remote, refresh the installed copy, and apply the chain in
# one shot (the new default)
seihou migrate haskell-base

# Same, but preview only — still fetches the remote so the plan is
# accurate
seihou migrate haskell-base --dry-run

# Stop at an intermediate version (the chain ends at 1.5.0 even if
# the remote is at 2.0.0)
seihou migrate haskell-base --to 1.5.0

# Overwrite files the user has edited since generation
seihou migrate haskell-base --force

# Skip the remote fetch — plan against whatever the locally installed
# copy currently declares (offline / hermetic mode)
seihou migrate haskell-base --no-fetch

# Machine-readable plan for tooling (suppresses the fetch chatter on
# stdout so the JSON stays parseable)
seihou migrate haskell-base --json
```

## Exit codes

- `0` — chain applied (or dry-run completed; or already at target;
  or blocked with no `--to` flag — the module author owes a
  migration but the command has done its part).
- `1` — error (no manifest, module not applied, planner refused with
  `--to TARGET` it cannot reach, executor refused without `--force`).

## See also

- [`seihou upgrade`](upgrade.md) — fetch a newer version of an
  installed module from its source repo. Pass `--with-migrations` to
  also run `seihou migrate` against the current project for each
  upgraded module.
- [`seihou status`](status.md) — reports `Pending migrations: …`
  under any applied module whose manifest version trails the
  installed copy.
- [docs/user/migrations.md](../user/migrations.md) — full guide.
