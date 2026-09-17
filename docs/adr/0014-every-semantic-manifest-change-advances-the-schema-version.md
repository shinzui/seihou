# ADR 0014 — Every semantic manifest change advances the schema version

- Status: Accepted
- Date: 2026-09-17

## Context

`.seihou/manifest.json` is a checked-in contract. It records the applied state
that later versions of Seihou use to decide whether an operation is safe, not
merely data that happens to deserialize. Its top-level `version` therefore has
to identify the meaning of the document as well as its JSON shape.

Schema version 6 exposed the cost of treating those concerns separately.
`FileRecord.additiveOnly` was added without advancing the version because an
older reader would ignore the new key and a newer reader could conservatively
interpret an absent key as `False`. That looked wire-compatible, but it erased
the distinction between “the path is known to require ownership closure” and
“this manifest predates the evidence.” A targeted update then had no reliable
way to decide whether it could update one owner of an additive shared path.
The failure is recorded in
`docs/bug-reports/additive-only-gate-breaks-targeted-update-on-preexisting-manifests.md`.

Compatibility is therefore not limited to whether an old binary can decode a
new field. A manifest change is compatible only when every supported reader can
identify the semantics it is reading and every feature can identify the facts
on which it relies.

## Decision

Every semantic change to the serialized manifest advances the manifest schema
version. A semantic change includes adding or removing a field, changing a
field's meaning or requiredness, changing the interpretation of an absent
value, or adding evidence that affects a command's safety or behavior. It does
not include an in-memory refactor that leaves the accepted and emitted JSON and
its interpretation unchanged.

Each version advance must include all of the following in the same change:

- a decoder and validation rules that are selected by the document's version;
- one adjacent `N` to `N + 1` upgrade step, even when the transform is small;
- focused fixtures or tests for the old representation, the transformed
  representation, and rejection of malformed input at the new version;
- an entry in the manifest version history and any affected user-facing
  upgrade documentation; and
- a classification of the upgrade step as either deterministic and lossless,
  or inference-bearing and reviewable.

Upgrade steps form one ordered, contiguous path. Code must not stamp a document
with the current version after applying a transform intended for some older
version, and it must not jump over a missing intermediate step. The upgrade
registry is tested by asking for a path from every supported version to the
current version; a gap is a test failure.

A deterministic and lossless step may be staged automatically as part of a
command that requires it, provided the command validates the fully upgraded
document and writes it atomically with its other successful changes. A step
that consults machine-local state, selects among plausible origins, loses
information, or otherwise requires judgment remains an explicit `seihou
manifest upgrade`. It must report its inferences before writing. Converting the
absolute paths in schema versions 1 through 5 to portable artifact origins is
inference-bearing and remains governed by
[ADR 0005](0005-legacy-manifests-convert-through-an-explicit-command.md).

Features that depend on manifest evidence declare a minimum schema version in
one central capability mapping. A feature must check that mapping rather than
testing optional keys or scattering numeric version comparisons through CLI
modules. If the manifest is older than the required version, the command may
stage the ordered deterministic steps up to that minimum. If reaching the
minimum crosses an inference-bearing step, the command stops before changing
project state and directs the user to the explicit upgrade command.

An absent field must not mean both a domain value and “this manifest predates
the question.” A new schema either requires the field or represents unknown
evidence explicitly. Version-aware decoding may map an older representation to
that explicit unknown state, but no upgrade may invent a stronger fact than the
old document proves.

The `additiveOnly` change is corrected by schema version 7. Version 6's explicit
`true` is evidence of an additive-only path; `false` or absence is unknown
because the version-6 encoder omitted false values. Schema 7 records an
explicit shared-write mode and the targeted additive shared-path update
capability requires at least version 7. This supersedes only ADR 0012's
decision to leave this field at schema version 6; its definition of safe
additive co-writes and its two-layer safety check remain accepted.

## Consequences

Future manifest evolution carries a small, deliberate cost: even an apparently
fail-closed field needs a version, an adjacent transform, and tests. In return,
commands no longer have to infer a document's meaning from the accidental
presence or absence of optional keys.

Older Seihou binaries reject a newer semantic contract instead of silently
operating with incomplete knowledge. Newer binaries can explain exactly which
upgrade is required and can safely compose multiple historical steps.

Lossless upgrades do not impose unnecessary prompts, while conversions that
derive a remote from machine-local installation metadata remain visible and
reviewable. The distinction is a property of each adjacent step, so a long
upgrade path stops if any intermediate conversion requires judgment.

The capability mapping makes a feature's manifest dependency reviewable and
testable. Adding a capability or a schema version requires extending total
types or exhaustive tests rather than adding an ad hoc comparison at a call
site.

## Rejected Alternatives

Keeping the schema number when an absent field appears conservative was
rejected. ADR 0012 demonstrated that fail-closed decoding can still discard the
knowledge needed to perform a safe operation.

Upgrading every old version directly to the current version was rejected. It
couples unrelated historical transforms, makes gaps invisible, and risks
running an inference intended for one schema against another.

Making every upgrade explicit was rejected. A deterministic, lossless JSON
transform does not benefit from human judgment and may be committed atomically
with the feature that requires it. Only inference-bearing steps need the
explicit review boundary.

Advancing the schema for every internal code change was rejected. The version
identifies serialized semantics, not implementation revisions.

## References

- [ADR 0001](0001-manifest-is-a-checked-in-machine-independent-artifact.md) —
  the manifest is a portable, checked-in project artifact.
- [ADR 0004](0004-the-manifest-is-the-only-record-of-applied-state.md) — schema
  evolution belongs in the manifest rather than a second lockfile.
- [ADR 0005](0005-legacy-manifests-convert-through-an-explicit-command.md) —
  machine-local path conversion is inference-bearing and reviewable.
- [ADR 0012](0012-an-additive-co-write-is-not-a-shared-path-conflict.md) — the
  decision whose unversioned field exposed the ambiguity corrected here.
- `docs/masterplans/11-make-manifest-evolution-explicit-and-targeted-updates-upgrade-safe.md`
- `docs/plans/92-define-manifest-schema-capabilities-and-ordered-upgrade-steps.md`
- `docs/plans/93-upgrade-legacy-path-manifests-and-backfill-additive-facts.md`
- `docs/plans/94-gate-targeted-updates-on-the-minimum-manifest-schema.md`
