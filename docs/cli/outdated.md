# seihou outdated

Check installed modules for newer versions.

## Usage

```
seihou outdated [OPTIONS]
```

## Options

| Option | Description |
|--------|-------------|
| `--json` | Output as JSON |

## Description

Checks each installed module's source repository for a newer version. Shows modules as "unversioned" if they lack version info.

Only checks modules installed via `seihou install`. Reads `.seihou-origin.json` metadata to determine the source.

## How "available" version is determined

For each installed module `seihou outdated` clones its remote source and reads
the truthful `version` field declared in the cloned `module.dhall` itself.
Multi-module repositories ship a `seihou-registry.dhall` that also lists a
per-module `version`, but `outdated` deliberately ignores that field — it can
drift behind the real `module.dhall` if the registry hasn't been re-synced.

The practical consequence: a project owner sees a module as outdated as soon as
the upstream `module.dhall` declares a higher version, even if the upstream
maintainer hasn't yet run `seihou registry sync-versions`.
