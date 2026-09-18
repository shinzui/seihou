# seihou update

Reconcile recorded project applications with newer module or recipe sources.
For the condensed in-binary guide, run `seihou help update`.

## Usage

```text
seihou update [TARGET...] [OPTIONS]
```

With no target, Seihou updates every recorded top-level application in manifest
order. A target may name a recorded module or recipe, or a module contained in
an application. Repeated targets select a deduplicated subset.

When a generated path is also owned by an application you did not select,
Seihou asks one question: does *every* owner reach that path through an
additive, non-overlapping patch?

- **Yes** — the update proceeds. `append-line-if-absent` filters out lines
  already present, and `append-section` writes a region delimited by the
  contributing module's own comment markers, so replaying one owner leaves the
  others' lines exactly where they were. This is the ordinary case for
  `.gitignore`, which nearly every module appends to.
- **No** — the update refuses, because regenerating the file on one owner's
  behalf would discard another owner's content. This covers any path an owner
  writes wholesale (`copy`, `template`, `dhall-text`, `structured`) and the
  position-dependent patches `append-file` and `prepend-file`, whose result
  depends on what is already in the file.

The answer is recorded per path in `.seihou/manifest.json` as `sharedWriteMode`,
which schema 7 requires on every file record. It has three values:

- `additive-only` — every owner appends, so a targeted update may leave the
  others out;
- `requires-ownership-closure` — some owner writes the whole file, so every
  owner must be updated together;
- `unknown` — the manifest predates the answer (every path of a schema-6
  manifest starts here, since schema 6 could only say `additiveOnly: true`).

An `unknown` answer does not make a targeted update refuse. The update works it
out as part of its own plan: it compiles each co-owner from the exact version
the manifest records, reads which operations reach the shared path, and records
the result. It only *inspects* those co-owners. Their other files are neither
regenerated nor rewritten, and their recorded versions stay the same. A
schema-6 manifest is moved to schema 7 in the same step, and both changes are
published with the update's own manifest, so a dry run writes nothing and a
failed update leaves the old manifest in place:

```text
Manifest:    schema 6 -> 7
             .gitignore evidence unknown -> additive-only
nix-haskell-flake  0.23.2 -> 0.24.0
...
```

The JSON plan carries the same facts as an optional `manifestPreparation`
object (`fromSchema`, `toSchema`, and one `{path, from, to}` per certified
path). A plan whose only work is recording an answer is not reported as
already up to date.

A co-owner's recorded version is often no longer installed. The install cache
keeps one version of each module, so `seihou upgrade` replaces it on this
machine long before every project has moved on. In that case the update fetches
the recorded release itself. It clones the co-owner's recorded remote into its
own temporary directory, finds the newest commit at which that module declares
the recorded version, and compiles the co-owner from there. The install cache is
not read for that version and is never changed, and the temporary copy is
deleted when planning ends. The plan says where the evidence came from:

```text
Manifest:    .gitignore evidence unknown -> additive-only
             (nix-haskell-flake 0.13.2 read from https://github.com/shinzui/seihou-modules.git at ec6435e)
```

The JSON `manifestPreparation` object then carries an `evidenceSources` array,
one `{module, version, origin, revision}` per fetched release. The key is
omitted when nothing was fetched. Fetching needs `git` and network access to
the recorded remote, which the update already uses to fetch candidates, and it
happens on a dry run too, because the evidence is part of the plan.

If neither an installed copy nor the recorded remote supplies the recorded
version, the update stops with `shared_write_evidence_unavailable` and names
each owner and why. That happens when no commit declares the version, when the
recorded origin names no remote (a `local` or in-project artifact), or when the
remote cannot be reached:

```text
Update failed [shared_write_evidence_unavailable]: Seihou has to inspect how the owners of
.gitignore write it before a targeted update may leave any of them out, and it could not
read the recorded version of each application below, either installed here or from its
recorded origin: exec-plan [skill.name=exec-plan]: module exec-plan 1.2.0 is not
installed here; no commit of https://github.com/shinzui/seihou-modules.git declares
exec-plan 1.2.0 (searched 6 revisions). Install that exact version, or make its recorded
origin reachable, then update again. ...
```

A different version is not substituted, because it is not how the project was
written. When the recorded origin is a path on the machine that wrote the
manifest, the message ends by pointing at `seihou manifest repair-origins`.
Selecting more applications does not help here, so this error never suggests
`--include-shared-owners`. `seihou manifest upgrade --dry-run` lists every path
still unresolved across the whole project.

A manifest at schema 5 or earlier stops with `manifest_upgrade_required`.
Converting it records where each artifact came from, which is inferred from
paths on the machine that wrote it, so only `seihou manifest upgrade` does that,
where you can review it (see [`seihou manifest`](manifest.md)).

When the refusal is genuine (`shared_path_requires_applications`), the error
names the owners you selected and the ones still required, and offers a
concrete command:

```text
Update failed [shared_path_requires_applications]: At least one owner of Makefile writes
the whole file, so its owners have to be updated together. Selected: nix-haskell-flake.
Also required: master-plan. Name them as targets (seihou update master-plan
nix-haskell-flake), or pass --include-shared-owners to update their full applications too.
```

Applications are always named the way `seihou status` names them: the target,
then any parent variables in brackets, then any additional modules, as in
`exec-plan [skill.name=exec-plan]`. The application id digest is never used as
a name.

## Options

| Option | Description |
|--------|-------------|
| `--var KEY=VALUE` | Override a saved value (repeatable). |
| `--reconfigure` | Ignore saved per-instance inputs and resolve them again. |
| `--dry-run` | Render the complete plan without mutating project, cache, baselines, or manifest. |
| `--json` | Emit one versioned JSON document and disable prompts. |
| `--force` | Use generated content for safe file conflicts and retain edited orphans as tracked. |
| `--run-all-commands` | Run every declared command, including unchanged commands. |
| `--no-commands` | Disable every declared command. Mutually exclusive with `--run-all-commands`. |
| `--commit` | Commit only the managed paths reported by a successful update. |
| `--commit-message MSG` | Use `MSG` verbatim and imply `--commit`. |
| `--allow-downgrade` | Accept a candidate artifact older than the version `.seihou/manifest.json` records. |
| `--include-shared-owners` | Also update the applications that co-own a selected path, reporting each one added. |

`--commit` and `--commit-message` cannot be combined with `--dry-run`.

`--include-shared-owners` expands a named selection to exactly the applications
the shared-path rule above still requires, and prints one line per application
it added:

```text
Warning:     also updating master-plan because it co-owns .gitignore
```

The expansion iterates to a fixed point, because an application pulled in
through one path may co-own a different path with a third application. Paths
that are additive-only are skipped, so the flag never drags in an owner the
update did not need. Expansion is for a path that really requires every owner:
it updates each added application in full, all of its files, not only the
shared one. Missing evidence is never a reason to expand. Without the flag a
named selection is never broadened.

## Warnings

Every warning is a sentence. The ones you are most likely to meet:

```text
Warning:     agents/skills/exec-plan/ADR.md receives content from both exec-plan and
             link-skill; link-skill is recorded as its last writer (ownership
             attribution only, not a content change)
Warning:     demo changed content without changing its declared version
Warning:     a migration of demo runs 'cabal gen-bounds', which a dry run cannot
             simulate; the file summary assumes it changes nothing
```

The first says which module the manifest will credit for a file two modules
contribute to. It does not mean the file's bytes change; the `Files:` summary
says that.

## Saved inputs and migrations

An ordinary update reuses the exact accepted values recorded for each module
instance. `--var` has highest priority and can override those values. New
variables continue through the normal CLI, environment, project, namespace,
context, global, default, and prompt resolution chain. In JSON or another
non-interactive context, a missing required value is an error; supply it with
`--var`.

`--reconfigure` deliberately discards saved values and runs the full resolution
chain again. Use it when changing configuration, not for routine updates.

Applicable module migrations are always part of the update plan. There is no
skip-migrations flag because applying new templates against an old project
layout is unsafe. Declarative moves and deletes are staged for an honest
dry-run. A migration shell command is listed as non-simulatable and may have
external side effects that Seihou cannot roll back.

## Three-way file reconciliation

For every generated text file, Seihou compares three versions:

- **baseline**: bytes generated by the previous successful application;
- **current**: bytes now present in the project, including user edits;
- **generated**: bytes produced from the candidate source.

If only one side changed, that change is preserved. Non-overlapping changes on
both sides merge automatically. Overlapping changes become a conflict with
diff3 markers labeled `current`, `baseline`, and `generated`. Interactive runs
offer four choices: use generated content, keep current content, write the
conflict markers, or abort.

When a generated file disappears from the candidate, an unchanged file is
deleted safely. An edited orphan can be deleted, retained as tracked state, or
detached and kept as an unmanaged file. `--force` never deletes an edited
orphan: it retains the file as tracked unresolved state. Binary data and merge
driver failures remain explicit conflicts unless replacement is known safe.

Generated ancestors are stored by hash under `.seihou/baselines/`. Do not edit
or delete this directory by hand; successful updates prune blobs no longer
referenced by the manifest.

## Commands

The default policy runs only new or changed rendered commands. Successful
receipts in the manifest identify unchanged commands, which are skipped.
`--run-all-commands` replays everything and `--no-commands` disables execution.
Receipts are published only after the whole command phase succeeds.

Command side effects outside Seihou's managed file, cache, baseline, and
manifest paths cannot be rolled back. A failure reports this limitation.

## Output and automation

Human output groups version changes, inputs, migrations, files, commands, and
warnings. An identical candidate prints `Already up to date.` without a prompt
or publication. Changed content under the same declared version remains
updateable and carries a visible warning so authors can correct their version.

`--json` writes exactly one document to stdout. Progress and diagnostics go to
stderr. Schema version 1 has an `outcome` of `plan`, `applied`, or `error`; plan
documents include application IDs, version/input summaries, every file
classification and resolution, command fingerprints and dispositions, and
warnings. Error documents include a stable `error.code` and human-readable
`error.message`.

```json
{"schemaVersion":1,"outcome":"plan","applications":["application-id"],"versions":[],"inputs":{"reused":4,"overridden":0,"newlyResolved":0,"removed":0,"ambiguousLegacy":[]},"migrations":[],"files":[],"commands":[],"warnings":[]}
```

JSON mode is non-interactive. An unresolved conflict fails unless `--force`
provides a permitted deterministic choice. A non-dry-run JSON plan applies
without a final confirmation after all ambiguity has been removed.

### When a failure's remedy is unclear

Every human failure message leads with its remedy and ends with one more line:

```text
If this keeps failing, run 'seihou agent upgrade <target>' to have an agent repair the manifest state and finish the upgrade.
```

`<target>` is the first target you named, or `<module>` when you named none.
[`seihou agent upgrade`](agent.md#agent-upgrade) diagnoses the project without changing it
and starts an agent with a repair playbook keyed by the error codes above.
`seihou agent upgrade <target> --check` reports whether a plain update would plan. JSON
output never carries the line; `error.code` and `error.message` are unchanged.

## Transaction and commit behavior

Before mutation, Seihou verifies that the manifest, project files, and staged
candidate sources still match the plan. Managed migrations, project files,
baseline blobs, installed-cache publication, and the manifest are protected by
a recovery journal. The manifest is the final commit marker. A later invocation
recovers an interrupted transaction before planning.

A declined confirmation, EOF, dry-run, unresolved conflict, stale plan, or
managed apply failure leaves the protected state unchanged. Arbitrary shell
command effects are the stated exception.

After a successful update, `--commit` filters ignored paths and stages only the
paths reported by the result. Generated messages use Conventional Commits;
`--commit-message` bypasses generation. A Git failure does not roll back or
misreport the already-successful update.

## Legacy manifests

Manifests without recorded applications require one explicit target for their
first update. That successful update seeds the reproducible application record,
saved instance values, ownership, baselines, and receipts. Ambiguous legacy
flat values are reported instead of guessed.

## Examples

```sh
# Preview every recorded application
seihou update --dry-run

# Update one recorded recipe and reuse its saved inputs
seihou update haskell-library

# Supply a newly required value in automation
seihou update --json --var project.owner=team-platform

# Accept safe generated conflicts, retain edited orphans, and commit
seihou update --force --commit

# Deliberately resolve all configuration again
seihou update haskell-library --reconfigure
```

## Exit status

Exit status 0 means the plan, no-op, dry-run, declined interactive confirmation,
or apply completed as reported. Invalid options, missing input, unsafe partial
selection, unresolved non-interactive conflicts, stale state, apply failure, or
requested Git commit failure exit non-zero.
