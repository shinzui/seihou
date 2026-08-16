# ADR 0006 — The install cache will not silently substitute one artifact for another

- Status: Accepted
- Date: 2026-08-16

## Context

`seihou install` copies every artifact it installs into
`~/.config/seihou/installed/<name>`. That directory is keyed by the artifact's
bare *name*, across every git repository the user has ever installed from, and
it is machine-global: it is one of the three roots
`Seihou.Core.Module.defaultSearchPaths` returns, so every project on the machine
resolves artifact names through it.

[ADR 0002](0002-artifact-identity-is-origin-url-plus-name.md) already decided
that a bare name is not an identity, because two registries can publish an
artifact with the same name. The manifest was brought into line with that
decision; the install cache was not. Nothing prevented one repository's
`shared-thing` from being written over another repository's `shared-thing`.

[ADR 0003](0003-a-stale-or-substituted-artifact-is-a-hard-error.md) decided what
to do when a project is about to *generate* from an artifact that disagrees with
what its manifest records. That refusal is the last line of defence and it works,
but it fires one layer too late and in the wrong place: the damage is done at
install time, to state shared by every project, and it is a *different* project —
possibly one the installing developer has not touched in months — that discovers
it. ADR 0003 even relies on the cache being shared when it rejects auto-fetching:

> it would mutate `~/.config/seihou/installed/`, which is shared by every project
> on the machine, as a side effect.

The same sentence is an argument about `seihou install` itself, which mutates
that directory as its whole purpose.

Before this decision, an overwrite printed one line:

```text
warning: overwriting existing installation of 'shared-thing'
```

That line read identically for the ordinary case — reinstalling the same
artifact from the same URL to pick up a new version — and for the destructive
one. The ordinary case is overwhelmingly the common one, which is exactly what
trains a reader to skip the line.

## Decision

`seihou install` reads the `.seihou-origin.json` it is about to delete and
decides from it, before removing anything:

- **Same source URL** — proceed, silently. This is the ordinary upgrade path,
  and the calling command already prints what it installed.
- **Different source URL** — refuse, name both URLs, and name `--force`.
- **No readable provenance** — refuse, saying so. Seihou cannot tell whether the
  two are the same artifact, and an entry created by hand or by a much older
  seihou is not evidence that replacing it is safe.

URLs are compared through `Seihou.Core.ArtifactIdentity.normalizeOriginUrl`, the
same normalisation the manifest guard and the blueprint-migration receipt ledger
use, so `https://host/repo`, `https://host/repo.git` and `https://host/repo/` are
one source everywhere in seihou.

`--force` is the only override and it prints what it overrode, mirroring
`--allow-downgrade` under ADR 0003.

The three commands that also write to the cache — `seihou upgrade`,
`seihou update`, and `seihou migrate`'s post-apply refresh — pass no override.
Each of them reinstalls from the URL the artifact's own provenance file or the
project's own manifest already records, so each is structurally the same-source
case and must never refuse. A refusal there means the cache disagrees with its
own record, which is real news, and each reports it in its own vocabulary rather
than suppressing it.

### Rejected: warn and continue

Rejected for the reason ADR 0003 gives, which applies here with more force
rather than less: a warning that fires on every routine reinstall is a warning
nobody reads, and the consequence of missing this one is not confined to the
project the developer is looking at.

### Rejected: namespacing the cache by repository

Keying the cache as `installed/<repo>/<name>` is the more principled fix: it
removes the collision instead of detecting it. It was considered and rejected
for now, and the reasoning is recorded in
`docs/improvement-requests/refuse-to-overwrite-an-installation-from-a-different-source.md`.
It changes artifact resolution for every command that searches the cache, and it
invalidates every existing installation on every user's machine — a migration
whose cost is out of proportion to a collision that is rare today.

This decision is deliberately compatible with that one. If the cache is ever
re-laid-out, the refusal added here stays correct and simply becomes
unreachable, because two artifacts from different repositories would no longer
contend for one directory.

### Rejected: silently renaming the incoming artifact

`--name` exists for single-artifact repositories and could in principle be
applied automatically. It was rejected because a registry entry has no rename
escape hatch — its name comes from `seihou-registry.dhall` — so the behaviour
would be available in one case and not the other, and because a project that
already resolved the old name would silently keep resolving it while the user
believed they had installed the new artifact.

## Consequences

A refusal costs nothing and leaves the cache byte-identical, because the
classification happens before `removeDirectoryRecursive`. That is the property
`seihou-cli/test/Seihou/CLI/InstallCollisionSpec.hs` asserts, using a marker file
written into the existing installation before the refused call.

The routine reinstall got quieter, not louder. The old warning is gone rather
than demoted, because `seihou install` has no verbosity flag and the surrounding
output already reports what was installed. Anyone who relied on the warning to
notice replacements is better served by the refusal, which fires on exactly the
case worth noticing.

`installModuleDir` returns an `InstallOutcome` rather than throwing, because it
has ten call sites in four commands and each reacts differently: a
single-artifact install exits non-zero, a registry batch collects every refusal
and reports them together before exiting non-zero, and the three same-source
commands report a refusal in whatever form their own output already takes.

A batch install that did not fully succeed now exits non-zero. It previously
reported `3 entries installed, 2 failed.` and exited zero, which a script could
not distinguish from a complete install. Reporting everything before exiting is
deliberate: a user installing twenty entries should see all twenty verdicts, not
stop at the first.

An artifact installed by hand, with no `.seihou-origin.json`, can no longer be
replaced by `seihou install` without `--force`. That is a real if minor
regression in convenience for a workflow seihou never officially supported, and
it is the same trade ADR 0002 makes when it reports a `LocalOrigin` artifact as
unverifiable rather than assuming a match.

## References

- [ADR 0002](0002-artifact-identity-is-origin-url-plus-name.md) — why a bare
  name is not an identity. This decision applies that conclusion to the cache
  that is keyed by one.
- [ADR 0003](0003-a-stale-or-substituted-artifact-is-a-hard-error.md) — the
  generate-time refusal this one precedes, and the source of the
  warn-and-continue rejection.
- `docs/improvement-requests/refuse-to-overwrite-an-installation-from-a-different-source.md`
- `docs/masterplans/10-blueprint-migration-fan-out-across-a-library-cohort.md`
- `docs/plans/82-refuse-to-overwrite-an-installation-from-a-different-source.md`
