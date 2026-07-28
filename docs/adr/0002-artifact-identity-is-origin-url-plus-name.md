# ADR 0002 — Artifact identity in the manifest is the origin URL plus the artifact name

- Status: Accepted
- Date: 2026-07-28

## Context

[ADR 0001](0001-manifest-is-a-checked-in-machine-independent-artifact.md)
establishes that `.seihou/manifest.json` may not name a location that only
exists on the machine that wrote it. That leaves the question of what the
manifest *should* record instead, so that a second developer reading the file
can tell which artifact was applied and whether the copy they have is the same
one.

Whatever identity is chosen has to support the question the downgrade guard
asks: "is the artifact installed here the same artifact the manifest names, and
is it at least as new?" That requires an identity that is stable across
versions of the same artifact and that distinguishes artifacts which merely
share a name.

Seihou discovers artifacts from three roots
(`Seihou.Core.Module.defaultSearchPaths`): the project's own
`.seihou/modules/`, the developer's personal `~/.config/seihou/modules/`, and
the install cache `~/.config/seihou/installed/`. Only the third carries
provenance metadata, in a `.seihou-origin.json` file written by
`seihou install` recording the git URL, registry repository name, version, and
install time.

## Decision

An artifact reference in the manifest is an `ArtifactOrigin`
(`seihou-core/src/Seihou/Core/Types.hs`) — a three-constructor sum whose
constructor says how much provenance seihou can actually prove:

- `RemoteOrigin` carries the git URL the artifact was installed from, the
  artifact name, and the optional registry repository name. Two developers who
  install from the same URL are provably using the same upstream artifact. This
  is the identity: **origin URL plus artifact name**.
- `ProjectOrigin` carries a path relative to the project root, for artifacts
  committed inside the project under `.seihou/modules/<name>`. The path means
  the same thing in every clone, so it is its own identity.
- `LocalOrigin` carries only the artifact name, for artifacts found in the
  developer's personal `~/.config/seihou/modules/`, which records no provenance
  at all.

`LocalOrigin` is deliberately weak. It is the honest representation of "this
came from somewhere on that developer's machine and we cannot say where".
Fabricating a URL for such an artifact would be a lie that later verification
would act on, and modelling it as a `ProjectOrigin` would produce a path that
does not exist in the repository. Verification reports a `LocalOrigin`
artifact's provenance as unverifiable rather than pretending otherwise.

The origin is a sum type rather than one record with optional fields precisely
because the three cases carry different information *and* different trust
levels. A record of `Maybe Text` would permit impossible combinations and push
the case analysis into every consumer.

### Rejected: the bare artifact name

Recording only `"haskell-base"` is not an identity. Two registries can both
publish a module called `haskell-base`, and a manifest keyed on name alone
cannot tell a developer that the copy they have installed is a different module
from the one the project was generated with. Silently generating from the wrong
module is exactly the class of failure this design exists to prevent.

### Rejected: a content hash of the artifact directory

A content hash is precise and self-verifying, but it changes on every edit to
the artifact. It therefore cannot express "the same module, one version newer",
which is the relationship the downgrade guard has to reason about: with content
hashes, an upgrade and a substitution are indistinguishable. The hash also says
nothing a human reading a manifest diff can act on.

Content hashing remains useful for a different question — "did the bytes at this
same declared version change?" — and `seihou update` uses it for exactly that
(`versionEvidence` in `seihou-cli/src/Seihou/CLI/Update.hs`). It is not the
identity.

## Consequences

The git URL plus name is stable across versions, is already captured at install
time in `~/.config/seihou/installed/<name>/.seihou-origin.json`, and is
meaningful to a human reading a manifest diff.

`.seihou-origin.json` describes what one machine has installed. It is never
authoritative about what the *project* expects — that is the manifest's job.
Code may read it to build a `RemoteOrigin` at manifest-write time or to confirm
that a locally installed artifact really came from the recorded URL, but never
to decide what the project was generated from.

Consumers must handle all three constructors. In particular, anything that
verifies provenance has to have a defined answer for `LocalOrigin`, and that
answer is "unverifiable", not "assume it matches".

## References

- [ADR 0001](0001-manifest-is-a-checked-in-machine-independent-artifact.md)
- `docs/masterplans/9-make-the-seihou-manifest-multi-developer-safe.md`
- `docs/plans/76-record-portable-artifact-origins-in-the-manifest.md`
