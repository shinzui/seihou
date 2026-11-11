# ADR 0025 — A module owns only its own directory under .seihou

- Status: Accepted
- Date: 2026-11-11

## Context

`.seihou/` holds Seihou's own state: the manifest every command trusts (ADR
0004), generated baselines, crash-safe update transactions, project-local
modules, configuration, context and a trace. Published modules also keep their
own helper scripts and configuration there, each in a directory named after
itself, such as `.seihou/docs-mori-bootstrap/bootstrap-docs.py`.

`seihou run` applied no rule to `.seihou/` at all, so a module could overwrite
the manifest. `seihou update` refused every path whose first segment was exactly
`.seihou` or `.git`, so once a module wrote under `.seihou/` its application
could only be reapplied with `--force`, losing the three-way merge. The refusal
was also case-sensitive, so `.SEIHOU/manifest.json` passed it on a
case-insensitive volume. Several of Seihou's own entry names (`baselines`,
`transactions`, `modules`, `context`) are also valid module names.

## Decision

A module owns exactly one directory under `.seihou/`: `.seihou/<module-name>/`,
named and spelled exactly as the generating module. Files it generates there are
ordinary managed files, written by `run` and merged by `update`.

Seihou's own entries directly under `.seihou/` are one explicit list,
`reservedSeihouEntries` in `seihou-core/src/Seihou/Core/Path.hs`, compared
case-insensitively: `manifest.json`, `manifest.json.tmp`, `baselines`,
`transactions`, `transactions-quarantine`, `modules`, `context`, `config.dhall`,
`trace.jsonl`, and every name beginning with `.`. Everything under `.git` is
control data too. The `.seihou` directory itself may be created but never written
as a file, deleted, moved or restored over. A module whose name is on the list
has no state directory. New Seihou state under `.seihou/` must be added to the
list and must use a name that is not a valid module name (one not matching
`[a-z][a-z0-9-]*`), so it can never collide with a module's directory.

The rule is enforced at two strengths through one classifier,
`classifyProjectPath`:

- The control rule (the reserved list and `.git`) applies wherever a
  module-supplied path is validated: module loading, plan compilation,
  reconciliation, the update transaction and its journal, update recovery,
  migrations and removal.
- The own-directory rule applies only where a module produces new output: plan
  compilation of steps, shared by `run` and the desired side of `update`, and
  the "Module state destinations" check of `seihou validate-module`. It is not
  enforced at module load, so a module with older output elsewhere under
  `.seihou/` still loads for `status` and `remove`, and migrations may move such
  a file into the module's own directory.

Command working directories are not restricted: a command runs arbitrary shell
text and can already reach any file. Seed files and checkout outputs keep their
stricter rule and may not live under `.seihou/` at all (ADRs 0017 and 0018).

## Consequences

Every path `run` accepts is accepted by `update`, so applications of modules
that keep files in their own directory become updatable without any module
change. Module output can no longer reach the manifest, baselines or transactions
through either command, in any letter case. A module that writes elsewhere under
`.seihou/` (known case: `gcp-kube-env`, which writes `.seihou/gcp-kube-env.conf`)
now fails when it runs and must move that file into its own directory.

Refusals name what a path targets ("path targets Seihou's own state at
.seihou/manifest.json") or the directory the module may use, in user words as
ADR 0015 requires.

The reserved list is a maintained artifact: adding Seihou state under `.seihou/`
without adding it to the list would expose it to module output. The ExecPlan's
grep over `".seihou" </> "..."` constructions is the check.

## Alternatives considered

Refusing all module output under `.seihou/` (option 2 of the improvement
request) was rejected: three published modules and the docs-mori-bootstrap
README already use `.seihou/<module-name>/`, and every existing application of
them would need a migration. A purely structural rule ("any entry that is not a
valid module name is Seihou's") was rejected because it would make a legacy
file such as `.seihou/gcp-kube-env.conf` permanently unmovable by a migration.

## References

- [ExecPlan 120](../plans/120-let-seihou-update-reconcile-module-owned-files-under-seihou.md)
- [IR-19](../improvement-requests/update-module-files-that-seihou-run-wrote-under-dot-seihou.md)
- [ADR 0004](0004-the-manifest-is-the-only-record-of-applied-state.md)
- [ADR 0012](0012-an-additive-co-write-is-not-a-shared-path-conflict.md)
- [ADR 0015](0015-diagnostics-name-things-as-users-do-and-never-fall-back-to-show.md)
- [ADR 0017](0017-a-seed-file-is-created-once-and-belongs-to-the-project.md)
- [ADR 0018](0018-checkout-outputs-are-observable-portable-declarations.md)
