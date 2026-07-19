# seihou upgrade

Refresh shared installed-cache sources to their latest versions.

## Usage

```
seihou upgrade [MODULE...] [OPTIONS]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `MODULE` | No | Specific modules to upgrade (repeatable). Defaults to all. |

## Options

| Option | Description |
|--------|-------------|
| `--dry-run` | Show what would be upgraded without making changes |
| `--json` | Output as JSON |
| `--with-migrations` | After each successful per-module upgrade, also run `seihou migrate` against the current project. Without this flag, `seihou upgrade` emits a one-line advisory pointing at the next command. |

## Description

Refreshes installed modules from their source repository. Only modules installed via `seihou install` are eligible. This is cache maintenance: it does not reconcile templates, migrations, commands, or user edits in the current project. Use [`seihou update`](update.md) for that project-aware workflow.

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

# Preview upgrades
seihou upgrade --dry-run

# Upgrade and immediately apply any pending migrations
seihou upgrade --with-migrations
```
