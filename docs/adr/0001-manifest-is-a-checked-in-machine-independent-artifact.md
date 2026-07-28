# ADR 0001 — The manifest is a checked-in, machine-independent project artifact

- Status: Accepted
- Date: 2026-07-28

## Context

`seihou run` records what it generated in `.seihou/manifest.json` inside the
project. That file is what makes later runs incremental, and it is what tells a
reviewer which module version produced the generated files. Because it
describes the project rather than the machine, teams check it into git
alongside the code it describes.

Until schema version 6 the manifest also recorded, for every applied module and
every module instance inside an application, the absolute filesystem directory
that module happened to occupy on the machine that ran the command — entries
like `/Users/shinzui/.config/seihou/installed/haskell-base`. That string is
meaningless in any other clone. A teammate on a different account, or on Linux
where the XDG configuration root differs, gets a path that does not exist. Every
command that re-read a module from the recorded path (`seihou update`,
`seihou migrate`, `seihou upgrade`) either failed or silently fell back to a
different module than the manifest described.

The mistake was not the specific field. It was treating a shared, committed file
as a place to cache per-machine state.

## Decision

`.seihou/manifest.json` is a project artifact committed to version control. It
must never contain a value whose meaning depends on the machine that wrote it —
no absolute filesystem path, no home directory, no XDG root, no
platform-specific path separator, no username.

Every location the manifest needs to name is expressed one of two ways:

- Relative to the project root, with forward slashes, as the `files` map has
  always done for generated destinations.
- Through an `ArtifactOrigin`
  (`seihou-core/src/Seihou/Core/Types.hs`), the portable identity of an
  installable artifact. See
  [ADR 0002](0002-artifact-identity-is-origin-url-plus-name.md).

This constrains every future manifest field, not only the ones changed when the
schema moved to version 6. A new field that needs to reference a location must
reference it relative to the project root or through an `ArtifactOrigin`. If
neither fits, the value does not belong in the manifest.

The in-memory `Manifest` record may still carry machine-local paths — the
`source` and `targetSource` fields exist to hold the directory an artifact was
loaded from during the current run — but those fields are not serialized, and
nothing that reads a decoded manifest may depend on them.

## Consequences

Two developers who apply the same module produce the same bytes in every origin
position, so a manifest diff in code review shows a real change rather than a
change of laptop.

Anything that needs an artifact's bytes must first resolve its recorded origin
to a directory on the current machine. That resolution can fail — the artifact
may not be installed here — and the failure has to be reported as a named,
actionable error rather than as a "file not found" from deep inside a Dhall
evaluation.

Manifests written before schema version 6 cannot be read directly, because their
only record of a module's source is another developer's absolute path.
`Seihou.Manifest.Types.checkManifestVersion` refuses them with a message naming
the conversion command rather than misreading them.

The invariant is enforced by a test in
`seihou-core/test/Seihou/Manifest/TypesSpec.hs` (`describe "machine
independence"`), which encodes a manifest exercising every origin position and
asserts that no string in an origin position begins with `/`, `~`, or a Windows
drive prefix, and that the in-memory `source` path is not serialized at all.

## References

- `docs/masterplans/9-make-the-seihou-manifest-multi-developer-safe.md`
- `docs/plans/76-record-portable-artifact-origins-in-the-manifest.md`
