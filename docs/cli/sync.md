# seihou sync

Set up and restore this project's local directory links. Older projects get a
one-time setup preview in the same command; adopted projects restore their
recorded links offline.

```bash
seihou sync [--dry-run] [--json] [--yes]
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

For recorded declarations, no installed module, config evaluation, migration, network fetch
or recorded shell command is involved. Restoration does not upgrade artifacts or rewrite
the manifest. Older projects with no declarations use the adoption workflow below. There is no command-replay
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

Older supported manifests with recorded applications but no checkout declarations trigger
automatic discovery of link setup from their recorded sources. Sync never infers
declarations from shell receipts. Older
machine-local manifests require explicit `seihou manifest upgrade`; a newer unsupported schema
requires a newer binary. Metadata must be a real `.seihou` directory with a real manifest file.

## Adopting existing skill modules

The published [link-skill](mori://shinzui/agent-seihou/templates/link-skill) 0.3.0 and
[claude-skill-link](mori://shinzui/agent-seihou/templates/claude-skill-link) 0.2.0
producers declare checkout links and require Seihou 0.10.0.0 or newer. The former
uses `agents/skills/`; the latter, used by update-docs, keeps `claude/skills/`.
Use Seihou 0.10.1.0 or newer for automatic tracked-link adoption and the clearer
sync/status guidance described below.

For an existing project, use the same command as a fresh clone:

```bash
seihou sync
```

When no links are recorded, sync checks the project's recorded producer sources,
finds compositions that declare checkout links, and previews the required changes.
It reuses saved inputs and resolves dependencies without asking you to name modules
or install them. Accept `Apply link setup?` to adopt the declarations and create the
links. Other recorded applications are not selected merely because they have updates.
The preview includes any source changes and migrations needed by the declaring
composition. Necessary owners of shared files are included automatically and
identified in the preview; developers do not have to enumerate them. Ordinary setup shell commands are disabled for this link adoption.

This one-time adoption can change the manifest and managed source files. Commit
those changes for the team. Teammates receive the commit through the team's normal
Git workflow, then run `seihou sync`; already-adopted projects need no network or
installed producers. Sync does not pull or merge Git branches.

`seihou sync --dry-run` previews without applying. For automation, use
`seihou sync --yes`, optionally with `--json`. JSON alone does not consent to a
one-time project update: it returns the adoption preview with `approvalRequired`
and exits nonzero. Cancellation also exits nonzero without applying setup.
Normal restoration of existing declarations needs no confirmation or extra flag.

For a first application, install and run the desired module as usual. Installing
modules or upgrading manifest schema alone does not record link intent.

When a newly declared destination is an unchanged tracked symlink matching the
declaration, update previews `Adopt link: … (stop tracking in Git; keep working link)`.
Accepting the update stages that link's removal from Git and keeps its working copy.
The path must be ignored; HEAD, the index and the working link must agree. Staged
edits, modified links, regular objects, tracked ancestors and unrelated entries stay
protected. Dry-run and cancellation leave the index alone; failed updates and
interrupted uncommitted updates restore the adopted entries through recovery.

Commit the updated manifest, ignore rules and source skill files, together with
any intentional removal of discovery links from the index. Subsequent clones and
linked worktrees use only:

```bash
seihou sync
```

The human output lists the links and summarizes how many were created, repaired
or already correct. When a manifest has no declarations, sync discovers and previews setup within
the command. If no recorded composition declares links, it reports that explicitly.

No installed producers are needed. Sync restores
deleted links and repairs wrong targets while preserving tracked bytes and the
manifest. Historical source-move migrations remain distinct from this one-time
adoption and are included by update when applicable.
