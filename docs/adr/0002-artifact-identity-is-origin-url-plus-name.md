# ADR 0002 — Artifact identity in the manifest is the origin URL plus the artifact name

- Status: Accepted
- Date: 2026-07-28
- Amended: 2026-08-16 — extended from "what the manifest records about an
  artifact" to "what makes two records of the same work the same record", when
  the agent-applied records gained an origin and the blueprint migration
  completion key gained it too
  (`docs/plans/81-record-artifact-origin-for-agent-applied-artifacts.md`).

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

Identity is now enforced, not merely recorded.
`Seihou.CLI.ManifestGuard.judgeArtifact` compares the recorded origin against
the origin of the copy found locally before it compares versions, because a
differing origin URL means the two version numbers describe different artifacts
and ordering them is meaningless. Each constructor's trust level maps onto a
distinct outcome:

- Two `RemoteOrigin`s are the only pair whose identity can be confirmed or
  refuted outright. Disagreeing URLs are a hard refusal. URLs are compared after
  normalising a trailing `.git` and trailing slashes, because
  `https://host/repo`, `https://host/repo.git` and `https://host/repo/` are the
  same repository and a manifest must not read as a different module to a
  developer who typed a different spelling.
- A recorded `RemoteOrigin` that resolves to a copy carrying no provenance is
  *unverifiable*, not a mismatch. Seihou searches all three roots by name, so a
  developer deliberately shadowing an installed module with a personal copy in
  `~/.config/seihou/modules/` resolves to the personal one; calling that a
  mismatch would break a supported workflow, and calling it a match would assert
  an identity nothing checked.
- A recorded `ProjectOrigin` resolves against the project root and nowhere else,
  so anything other than the same project path is a genuine inconsistency.

The version comparison still runs in the unverifiable case: a version comes from
the artifact's own `module.dhall`, so "older than recorded" remains meaningful
even where "the same module" is not provable.

The identity also settles *when two records of the same work are the same
record*, not only what the manifest says about an artifact. A blueprint
migration receipt (`AppliedBlueprintMigration`) stands for one crossed version
edge, and `seihou agent migrate` skips an edge that already has one. What makes
two receipts the same receipt is the origin and name of the blueprint that owns
the edge together with the edge's `from` and `to` versions. The blueprint's own
release version and the receipt timestamp are deliberately excluded, because an
edge is the same edge no matter which release declared it; origin is included,
for the reason "Rejected: the bare artifact name" gives — two repositories
publishing a blueprint under one name declare different work, and a receipt for
one must not suppress the other's edge. `AppliedBlueprint` and `AppliedRecipe`
carry an origin for the same reason, though nothing keys a decision on theirs
yet.

Because three separate places have to give the same answer — the receipt upsert
and lookup in `seihou-core/src/Seihou/Manifest/Types.hs`, the pending-edge
filter in `seihou-cli/src/Seihou/CLI/BlueprintMigration.hs`, and the
pre-generation guard — the comparison has one definition,
`Seihou.Core.ArtifactIdentity.sameArtifactIdentity`, in `seihou-core` so that
core-side callers can reach it. Two answers would let a receipt be written as a
new entry while being read as a duplicate. That module owns the URL and
project-path normalisation described above; `judgeArtifact` consumes it rather
than carrying its own copy.

`sameArtifactIdentity` is a plain yes-or-no question and is not a substitute for
`judgeArtifact`'s three-way verdict. "Cannot be proved either way" is a
meaningful and necessary answer for the guard, which is deciding whether to
refuse an action. It is not a meaningful answer for a receipt lookup: a receipt
either records this identity or it does not, and two `LocalOrigin`s bearing the
same name are treated as the same identity there — the strongest statement
available about an artifact seihou can only identify by name.

One consumer deliberately does not verify identity. `seihou update` clones from
the origin URL the manifest itself records
(`remoteProvenance` in `seihou-cli/src/Seihou/CLI/Update/Source.hs`) rather than
generating from whatever is installed locally, so a same-named artifact from
another source can never be substituted and there is nothing for a guard to
catch. Adding one would also have broken updating a project whose modules are
not installed on this machine, which that command supports by design.

## References

- [ADR 0001](0001-manifest-is-a-checked-in-machine-independent-artifact.md)
- [ADR 0003](0003-a-stale-or-substituted-artifact-is-a-hard-error.md) — what
  seihou does with the verdict this identity makes possible.
- [ADR 0005](0005-legacy-manifests-convert-through-an-explicit-command.md) —
  recovering an origin for a manifest written before origins existed.
- `docs/masterplans/9-make-the-seihou-manifest-multi-developer-safe.md`
- `docs/plans/76-record-portable-artifact-origins-in-the-manifest.md`
- `docs/plans/77-resolve-manifest-artifact-origins-to-local-directories.md`
- `docs/plans/78-refuse-accidental-module-downgrades-and-origin-mismatches.md`
- `docs/masterplans/10-blueprint-migration-fan-out-across-a-library-cohort.md`
- `docs/plans/81-record-artifact-origin-for-agent-applied-artifacts.md` — the
  amendment above.
