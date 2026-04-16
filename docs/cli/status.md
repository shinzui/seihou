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
  modules) omit the version segment.
- **Tracked files** — each file is listed with its owning module and a
  status: `unchanged`, `modified by user`, or `deleted by user`. Status is
  computed by comparing the current disk content against the hash recorded
  in the manifest.
- **Variables** — a count of variable values resolved during the last run.

If no manifest exists (i.e., `seihou run` has not been executed in this
directory), Seihou prints `No Seihou manifest found` and exits
successfully.

### Update checking

With `--check-updates`, Seihou checks each applied module against its source
registry for newer versions. Each module line is annotated with its update
status: `up to date`, `outdated -> vX.Y.Z`, `unversioned`, or `unreachable`.
A summary line reports how many modules were checked and how many are outdated.
This requires network access (shallow clones of source repos).
