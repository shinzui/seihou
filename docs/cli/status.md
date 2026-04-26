# seihou status

Show manifest state for the current project.

## Usage

```
seihou status [OPTIONS]
```

## Options

| Option | Description |
|--------|-------------|
| `-u, --check-updates` | Check installed modules for available updates (requires network) |

## Description

Reads `.seihou/manifest.json` in the current directory and displays:

- **Recipe** — if the project was generated from a recipe, shows the recipe
  name and version (e.g. `Recipe: haskell-library v1.0.0`).
- **Applied modules** — each line shows the module name, its recorded
  version (e.g. `v1.2.0`) when available, and the date it was applied.
  Modules without a recorded version (older manifests or unversioned
  modules) omit the version segment. When a module needs action, a
  one-line remediation hint is printed underneath the row (see
  "Pending migrations" and "Update checking" below).
- **Tracked files** — each file is listed with its owning module and a
  status: `unchanged`, `modified by user`, or `deleted by user`. Status is
  computed by comparing the current disk content against the hash recorded
  in the manifest.
- **Variables** — a count of variable values resolved during the last run.
- **Recommended actions** — a tail block listing every actionable command
  the user should run to fix the flagged rows. Omitted when no row
  needs action.

If no manifest exists (i.e., `seihou run` has not been executed in this
directory), Seihou prints `No Seihou manifest found` and exits
successfully.

### Pending migrations

Pending-migration detection runs on every `seihou status` invocation —
no `--check-updates` flag is required, because the check is purely
local (it compares the manifest's recorded `moduleVersion` against the
locally installed `module.dhall`'s version and asks the planner whether
a contiguous chain exists).

When a chain is found, the row's hint reads:

```
    Pending migration: 0.1.0 -> 0.2.0 (6 operation(s)). Run: seihou migrate <name>
```

`seihou migrate <name>` is self-contained (it fetches the source repo
on its own — see `docs/cli/migrate.md`), so a single command resolves
the row.

If the migrations list does not reach the installed version exactly
(for example, only `0.1.0 -> 0.2.0` is declared but the installed
copy is at `0.3.0`), the planner returns a "gap" and the row is
silently treated as "no pending chain". This mirrors `seihou run`'s
pre-flight behavior. A future planner mode for longest-reachable
prefixes would change this.

### Update checking

With `--check-updates`, Seihou checks each applied module against its
source registry for newer versions. The check shallow-clones each
referenced source repo, so it requires network access.

Each module line is annotated with one of:

- `up to date` — the locally installed copy is at the same version as
  the remote.
- `outdated: X.Y.Z available` — the remote declares a newer version
  than the locally installed copy. A `Run: seihou upgrade <name>`
  hint is printed under the row, unless a pending migration was also
  detected (in which case the migration hint takes precedence and
  fixes both at once).
- `unversioned` — the module's `module.dhall` does not declare a
  version field (old or partially populated module).
- `unreachable` — the source repo could not be cloned (network
  failure, deleted upstream, etc.).

A summary line reports how many modules were checked and how many are
outdated (`N module(s) checked, M outdated.`). Note that this counts
*installed* modules; modules that are installed but not applied to
this project are still surfaced in the count, even though they will
not appear in the per-row list above.

The annotation reflects the *locally installed copy* compared against
the remote — not the manifest's recorded version compared against the
remote. If a user has refreshed the install (via an earlier `seihou
upgrade`) but has not yet migrated, the row may show "up to date"
while a pending-migration row separately reports the manifest-vs-installed
gap.

### Example

```
$ seihou status --check-updates
Seihou Status:

Applied modules:
  master-plan  v0.1.0    (applied 2026-04-15)  outdated: 0.3.0 available
    Pending migration: 0.1.0 -> 0.2.0 (6 operation(s)). Run: seihou migrate master-plan
  exec-plan  v0.1.3    (applied 2026-04-15)  outdated: 0.3.0 available
    Run: seihou upgrade exec-plan

Tracked files: 5
  ...

Variables: 4 resolved

7 module(s) checked, 2 outdated.

Recommended actions:
  seihou migrate master-plan
  seihou upgrade exec-plan
```
