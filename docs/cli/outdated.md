# seihou outdated

Check installed modules, blueprints, and prompts for newer versions.

## Usage

```
seihou outdated [OPTIONS]
```

## Options

| Option | Description |
|--------|-------------|
| `--json` | Output as JSON |

## Description

Checks each installed module's, blueprint's, and prompt's source repository for
a newer declared version. Shows artifacts as "unversioned" if they lack version
info.

Only checks artifacts installed via `seihou install`. Reads `.seihou-origin.json`
metadata to determine the source.

`outdated` compares declared versions only: it reads the source and never stages
anything. [`seihou upgrade`](upgrade.md) compares content for blueprint, prompt,
and recipe closures, so it can refresh a same-version fix that `outdated` does
not report.

## How "available" version is determined

For each installed module `seihou outdated` clones its remote source and reads
the truthful `version` field declared in the cloned `module.dhall` itself. A
blueprint's version is read from its `blueprint.dhall` and a prompt's from its
`prompt.dhall`, located through the registry's `blueprints` or `prompts` entry
of that name, or at the root of a single-artifact repository.
Multi-module repositories ship a `seihou-registry.dhall` that also lists a
per-module `version`, but `outdated` deliberately ignores that field — it can
drift behind the real `module.dhall` if the registry hasn't been re-synced.

The practical consequence: a project owner sees a module as outdated as soon as
the upstream `module.dhall` declares a higher version, even if the upstream
maintainer hasn't yet run `seihou registry sync-versions`.
