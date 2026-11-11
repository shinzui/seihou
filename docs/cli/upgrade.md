# seihou upgrade

Refresh shared installed-cache sources to their latest versions: modules,
recipes, blueprints, and prompts.

## Usage

```
seihou upgrade [ARTIFACT...] [OPTIONS]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `ARTIFACT` | No | Specific installed modules, recipes, blueprints, or prompts to upgrade (repeatable). Defaults to all. |

## Options

| Option | Description |
|--------|-------------|
| `--dry-run` | Show what would be upgraded without making changes |
| `--json` | Output as JSON |
| `--skip-unversioned` | Skip changes without version information; keep selected recipe closures together |
| `--with-migrations` | After each successful per-module upgrade, also run `seihou migrate` against the current project. Without this flag, `seihou upgrade` emits a one-line advisory pointing at the next command. |

## Description

Refreshes installed modules, recipes, blueprints, and prompts from their source repository. Only artifacts installed via `seihou install` are eligible. This is cache maintenance: it does not reconcile templates, migrations, commands, or user edits in the current project. Use [`seihou update`](update.md) for that project-aware workflow.

Each module is refetched from the URL its own `.seihou-origin.json` records, so
an upgrade is always a same-source reinstall and never hits the different-source
refusal described in [`seihou install`](install.md#when-the-name-is-already-taken).
There is correspondingly no `--force` here. If an upgrade does report a source
mismatch, the installed copy disagrees with its own provenance file — most
likely because something replaced the directory outside seihou. The module is
reported as failed rather than overwritten; inspect
`~/.config/seihou/installed/<name>/.seihou-origin.json` and reinstall
deliberately with `seihou install <url> --force`.

## Recipe closures

`seihou upgrade haskell-cli-app-with-agents --dry-run` stages and validates the
recipe's full candidate closure. Its output includes inherited bases and members,
even when the child version has not changed. Repeating a selected module name
already in that closure does not refresh it twice. With no names, upgrade includes
all installed recipe roots and deduplicates their members.

`seihou upgrade haskell-cli-app-with-agents` publishes the validated cache entries
together on handled failures. It leaves project files and manifest unchanged,
then recommends `seihou update haskell-cli-app-with-agents` for reconciliation.
Recipe closure comparison includes normalized content, so same-version base
descriptor changes also refresh. A producer's base interval or source conflict
refuses the whole recipe refresh before publication.

`--skip-unversioned` skips changes without declared version information. If one
changed entry in a selected recipe closure is skipped, the entire selected recipe
refresh is skipped to keep the cache consistent. Module-only upgrades retain their
per-module behavior. `--dry-run` never publishes cache entries.

## Blueprint and prompt closures

An installed blueprint is refreshed together with its `baseModules`, the
modules `seihou agent run` applies before the agent starts. `seihou upgrade
my-blueprint` clones the URL the blueprint's own `.seihou-origin.json` records,
restages its whole install closure exactly as `seihou install` would (validation
and import normalization included), and compares the staged bytes with the
installed copies. Only entries whose content changed are published, together.
Because the comparison is by content, a fix published without a version bump is
picked up too. A prompt has no dependencies and is refreshed the same way on its
own. With no names, every installed blueprint and prompt that records its source
is included; a baseline module refreshed through a blueprint is not refreshed a
second time as a module.

The install cache is keyed by bare name, so before overwriting any entry in the
closure Seihou reads that entry's provenance. If an entry records a different
source, or no provenance at all, the refresh is refused under
[ADR 0006](../adr/0006-the-install-cache-will-not-silently-substitute-an-artifact.md):
the cache is left untouched and the row reports `failed: refused: ...` naming
both URLs. Naming a blueprint or prompt that has no `.seihou-origin.json` is
also a failed row, because Seihou cannot know where to refresh it from;
reinstall it deliberately with `seihou install <url> --force`.

## Exit status

`seihou upgrade` exits 1 when any reported row failed, for every artifact kind:
a refusal, a validation error, or an artifact missing from its source. A row
whose source was unreachable is reported but does not change the exit status,
since a network outage says nothing about the cache's integrity. Under `--json`
the rows are still printed before the command exits, and stdout carries only
the JSON array.

## How "outdated" detection works

`seihou upgrade` (like `seihou outdated`) clones each remote source and reads
the truthful `version` field directly from the cloned `module.dhall`. The
`version` field that a multi-module repository's `seihou-registry.dhall`
publishes is *not* consulted for the comparison — it can lag behind the real
`module.dhall` if `seihou registry sync-versions` hasn't been run upstream.

Because of that, a project will see an upgrade available as soon as the
upstream `module.dhall` declares a higher version, regardless of whether the
registry index has caught up. After a successful upgrade, the version recorded
in the local manifest's `.seihou-origin.json` is the one read from
`module.dhall`, not the one declared in the registry.

## Post-upgrade advisory

After a successful upgrade, if the manifest's recorded version still
trails the freshly-installed copy's declared version, `seihou
upgrade` prints a one-line advisory naming the next command:

    note: <name> has N migration(s) pending (X → Y); run 'seihou update' to reconcile the recorded project application

`N` is the count of declared migrations whose `[from, to]` range falls
inside `[manifest.moduleVersion, installed.version]`. It may be zero.
`seihou update` is the normal remediation because it reconciles migrations and
generated content together. The compatibility flag `--with-migrations` still
runs the lower-level migration after refreshing the cache.

## Examples

```sh
# Upgrade all installed modules
seihou upgrade

# Upgrade specific modules
seihou upgrade haskell-project nix-flake

# Upgrade a blueprint and its baseline modules
seihou upgrade relaunch-fumadocs-docs

# Preview upgrades
seihou upgrade --dry-run

# Upgrade and immediately apply any pending migrations
seihou upgrade --with-migrations
```
