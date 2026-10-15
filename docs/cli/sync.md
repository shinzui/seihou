# seihou sync

Rebuild directory links declared in the committed manifest for this working copy.

```bash
seihou sync [--dry-run] [--json]
```

Run at the Git working-tree root, including linked worktrees. Sources must already be real
project directories. Destinations must be ignored and untracked; a tracked path is protected
even when missing on disk. Sync refuses regular files, real directories, symlinked ancestors,
metadata paths, missing sources and ambiguous native path spellings. Move a collision aside
or correct the declaration explicitly; there is no force option. Invocation below the root
reports where to change directory. Nested Seihou projects are not supported by sync yet.

Sync reads `.seihou/manifest.json` once and observes every declaration before writing. It
creates missing links, replaces wrong symlinks, and leaves correct literal relative targets
alone. It creates only required parent directories. Any preflight refusal prevents all writes.
An ordinary apply failure rolls back this attempt's links and empty parents when they still
match its own writes. A killed process can leave a subset of correct links; rerunning converges.
These checks assume a single cooperating filesystem writer, not a hostile concurrent writer.

No installed module, config evaluation, migration, network fetch or recorded shell command is
involved. Sync never upgrades artifacts or rewrites the manifest. There is no command-replay
option and no completion receipt. A deleted link is detected again on the next invocation.

A module can declare the wiring for an editor directory:

```dhall
S.Step::{
  strategy = "symlink",
  src = "config/editor",
  dest = ".editor-local/config",
  lifecycle = Some "checkout"
}
```

Ignore `.editor-local/`, apply the module once with `seihou run`, and commit the source directory,
ignore rule and manifest. Each clone can then run `seihou sync`; its link text is
`../config/editor`. The same declaration supports skill directories and shared project assets.
See [module authoring](../user/module-authoring.md) for declaration constraints.

`--dry-run` performs observation only and does not create even a parent. `--json` prints one
JSON document. `mode` is `dry-run` or `apply`; sorted `outputs` carry `destination`, `kind`,
`plannedAction`, `observation`, `outcome`, `errors` and `warnings`. Each error has a stable `code`
and a human `message`. `summary.planned` counts proposed `created`, `replaced`, `retired`,
`unchanged` and `refused` actions; `summary.applied` counts actual successful actions separately.
Dry-run and refused preflights report zero applied changes. Execution outcomes include
`not-applied`, `unchanged`, `applied`, `failed`, `rolled-back` and `rollback-conflicted`.
Refusal or execution failure exits nonzero; empty and already-correct plans succeed.

Older supported manifests have no checkout declarations and report zero work. Apply a declaring
module release once to record them. Sync never infers declarations from shell receipts. Older
machine-local manifests require explicit `seihou manifest upgrade`; a newer unsupported schema
requires a newer binary. Metadata must be a real `.seihou` directory with a real manifest file.
