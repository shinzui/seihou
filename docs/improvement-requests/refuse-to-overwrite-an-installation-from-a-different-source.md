---
type: Improvement Request
title: Refuse to overwrite an installation from a different source
description: >-
  Make seihou install read the origin metadata it is about to delete and refuse when the incoming
  artifact comes from a different repository, instead of warning and replacing, since the install
  cache is keyed by bare name and a registry entry has no rename escape hatch.
generated:
  by: process:claude-code
  at: "2026-08-06T17:12:58Z"
timestamp: 2026-08-06T17:12:58Z
requestId: IR-4
status: proposed
origin: mori://shinzui/okf-profiles
---

# Improvement Request: Refuse to Overwrite an Installation from a Different Source

## Status

Proposed. This is the collision that [IR-2](record-artifact-origin-for-agent-applied-artifacts.md)
and [IR-3](guard-the-agent-path-against-stale-and-substituted-artifacts.md) make detectable,
addressed one layer earlier. Either layer is useful alone; together they close it at both ends.

## Context

`seihou install` copies every artifact to `~/.config/seihou/installed/<name>`, keyed by the bare
artifact name across every repository a user has ever installed from. That cache is machine-global
and shared by every project on the machine — a property ADR 0003 relies on when it rejects
auto-fetching:

> it would mutate `~/.config/seihou/installed/`, which is shared by every project on the machine,
> as a side effect. A developer who ran seihou in one project would find another project's modules
> changed underneath them, with no obvious way to undo it.

The cache already holds the information needed to tell artifacts apart. `installModuleDir` writes a
`.seihou-origin.json` beside every installation recording the source URL, registry repository name,
version, install time, and tags.

## Problem

`installModuleDir` (`seihou-cli/src/Seihou/CLI/InstallShared.hs`) never reads that file before
destroying it:

```haskell
exists <- doesDirectoryExist installDir
when exists $ do
  logIO LogNormal (logWarn $ "overwriting existing installation of '" <> T.pack name <> "'")
  removeDirectoryRecursive installDir
```

Installing `adopt-architecture-decisions` from a second repository silently replaces the first
repository's blueprint. The warning names only the artifact; it does not say what source is being
replaced, what source is replacing it, or that the two differ at all. It reads identically to the
benign and overwhelmingly common case — reinstalling the same artifact from the same URL to pick up
a new version — which is precisely the case that trains a reader to skip it.

Every project on the machine that resolved that name is affected at once, and no project's manifest
records that anything changed.

ADR 0003 argued this exact position down for the generate path: a warning that is routinely ignored
trains developers to ignore the next one, and if the situation is not serious enough to stop, it is
not worth printing. Clobbering machine-global state that other projects depend on is at least as
consequential as generating from the wrong artifact — it is what *causes* generating from the wrong
artifact.

## Why the existing mechanisms do not cover it

- **`--name`** does not help for the case that matters. The parser accepts it for any install
  (`Commands.hs`, help text "Override installed module name"), but only the single-artifact paths
  consult it. The registry path uses the entry's own name directly — `name = T.unpack (entry ^.
  #name . #unModuleName)` in `Install.hs` — so a registry-entry collision, the only kind two
  published registries can produce, has no rename escape hatch at all. `docs/cli/install.md` is
  accurate in restricting `--name` to single-module repos; the gap is that nothing replaces it.
- **`seihou list --repo`** shows origin metadata after the fact, once the losing artifact is
  already gone.
- **IR-2 and IR-3** catch the consequence at use time, per project. They do not stop a single
  install from breaking every project on the machine that shared the name, and a user who hits the
  IR-3 refusal still has no supported way to hold both artifacts.

## Requested change

Have `installModuleDir` read the existing `.seihou-origin.json` before removing the directory, and
decide from it:

1. **Same source URL** — proceed as today. This is the ordinary upgrade path and must stay
   frictionless; the existing warning can drop to a quieter note naming the version transition.
2. **Different source URL, or no origin metadata** — refuse, printing both sources and the
   artifact name, and name the override in the message. `--force` proceeds and prints what it is
   overriding, mirroring how `--allow-downgrade` behaves under ADR 0003.

That is a small change against metadata already on disk, and it makes the collision legible at the
moment a human is present and can act.

### Considered: namespacing the install cache by repository

Keying the cache by repository — `installed/<repo>/<name>` — removes the collision instead of
reporting it, and is the more principled fix. It is not what this request asks for, because the
blast radius is disproportionate to a failure the refusal above already makes visible: it changes
`defaultSearchPaths` and artifact resolution, the `.seihou-origin.json` contract, and every command
that resolves an artifact by name (`list`, `outdated`, `update`, `migrate`, `upgrade`,
`schema-upgrade`), and it invalidates every existing installation on every machine. It also raises
a question this request does not have to answer: what a user types when two repositories publish
the same name and both are installed.

Detect-rather-than-prevent is the trade ADR 0003 already made for the generate path. If the cache
is ever re-laid-out, the refusal added here stays correct and becomes unreachable, so this is not
work that would be thrown away.

## Scope

`seihou install` and the shared `installModuleDir` primitive, which the single-artifact and
registry paths both call. `seihou migrate`'s `refreshInstalledFromClone` reinstalls from the
recorded origin URL and so is always the same-source case, but it routes through the same primitive
and should be checked against that expectation rather than exempted.

## Related

- [IR-2](record-artifact-origin-for-agent-applied-artifacts.md) — makes the collision representable
  in the manifest.
- [IR-3](guard-the-agent-path-against-stale-and-substituted-artifacts.md) — refuses to act on it at
  use time.
- [ADR 0003](../adr/0003-a-stale-or-substituted-artifact-is-a-hard-error.md) — the rejected
  warn-and-continue reasoning this applies to the install path.
