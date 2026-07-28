# ADR 0004 — The manifest is the only record of applied state; there is no lockfile

- Status: Accepted
- Date: 2026-07-28

## Context

Making `.seihou/manifest.json` machine-independent
([ADR 0001](0001-manifest-is-a-checked-in-machine-independent-artifact.md)) and
giving it a verifiable artifact identity
([ADR 0002](0002-artifact-identity-is-origin-url-plus-name.md)) gave it the two
properties a lockfile has: it is committed, and it pins each dependency to a
resolved identity and version. The obvious next move — the one most package
managers have made — is to split it: a hand-maintained declaration of what the
project wants, and a generated lockfile recording what it resolved to.

Seihou is not a package manager, and the analogy misleads. There is no
declaration to separate out. A project does not declare "I depend on
haskell-base ^1.0"; a developer *applies* a module, and the manifest records
what that application did — which files it wrote, with which variables, at which
version, from which origin. The record and the resolution are the same fact.

## Decision

`.seihou/manifest.json` is the single source of truth for what has been applied
to a project. Seihou does not have, and will not add, a separate lockfile.

A field that records something about the applied state belongs in the manifest.
A field that records something about a developer's machine belongs nowhere in
the project — `~/.config/seihou/installed/<name>/.seihou-origin.json` already
holds per-machine install metadata, and it is never authoritative about what the
project expects.

## Consequences

There is one file to commit, one file to review, and one file to reason about.
A reviewer reading a manifest diff sees the whole change: which module version,
from which repository, generating which files.

There is no reconciliation problem. A two-file design has to answer what happens
when the declaration and the lockfile disagree, and every such design accretes a
command to resolve it. With one file the question does not arise.

Adding a lockfile later would be a breaking change to a committed file, so the
exclusion is worth stating rather than leaving implicit: a future contributor
reaching for one should read this record first and have a reason it does not
address.

The manifest carries a schema version and is expected to keep growing. Growth is
handled by versioning the schema and providing a conversion path, not by moving
fields into a second file — see
[ADR 0005](0005-legacy-manifests-convert-through-an-explicit-command.md).

This constrains where new state goes. Anything that must be true for every
developer on the project goes in the manifest. Anything that is true only of one
developer's machine stays out of the project entirely; it does not get a second
committed file to live in.

## References

- [ADR 0001](0001-manifest-is-a-checked-in-machine-independent-artifact.md)
- [ADR 0002](0002-artifact-identity-is-origin-url-plus-name.md)
- [ADR 0005](0005-legacy-manifests-convert-through-an-explicit-command.md)
- `docs/masterplans/9-make-the-seihou-manifest-multi-developer-safe.md` — Vision
  & Scope states the exclusion.
