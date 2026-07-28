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
the conversion command rather than misreading them. That command, and the
decision not to date the guard's removal, are
[ADR 0005](0005-legacy-manifests-convert-through-an-explicit-command.md).

A `ProjectOrigin` that does not resolve is a hard failure and deliberately does
*not* fall through to the global search paths. If the recorded directory is
absent, the repository is incomplete; quietly substituting an installed artifact
of the same name would be exactly the invisible substitution this record exists
to prevent. `RemoteOrigin` and `LocalOrigin` do search by name, in the ordinary
discovery order, so a developer deliberately shadowing an installed module with
a project-local copy keeps that shadowing. The rule is enforced by a named test
in `seihou-core/test/Seihou/Core/ArtifactRefSpec.hs`.

Because the manifest describes the project rather than the machine, what it
records is authoritative over what the machine happens to have. A command that
is about to *generate* from an artifact must therefore refuse when the local
copy is older than, or came from somewhere other than, what the manifest
records — otherwise the machine silently overrides the project and the
regression looks like an ordinary diff in code review.
`Seihou.CLI.ManifestGuard` implements that refusal for `seihou run` and
`seihou migrate`; `--allow-downgrade` is the explicit override, and it still
prints what it overrides. The reasoning, and the alternatives rejected on the
way to it, are [ADR 0003](0003-a-stale-or-substituted-artifact-is-a-hard-error.md).

The line between the two kinds of consumer, first drawn when the resolver was
added, holds: commands that generate hard-fail on a stale or missing artifact,
while advisory consumers (pending-migration detection, `seihou status`,
`seihou update`'s same-version content comparison) skip what they cannot resolve
so that one uninstalled module cannot make the whole project unreportable.

The invariant is enforced by three tests in
`seihou-core/test/Seihou/Manifest/TypesSpec.hs` (`describe "machine
independence"`). Two encode a manifest exercising every origin position and
assert that no string in an origin position begins with `/`, `~`, or a Windows
drive prefix, and that the in-memory `source` path is not serialized at all. The
third is the one that constrains *future* fields: it encodes a manifest
populated in every serialized string position — parent variables, a file record
and its baseline, a command receipt with a working directory, a removal spec, an
applied recipe, an applied blueprint, a migration receipt — walks the whole
document, and reports the JSON path of any string, key or value, that is
machine-specific. A new field that records a location has to express it relative
to the project root or through an `ArtifactOrigin`, or that test fails.

## References

- [ADR 0002](0002-artifact-identity-is-origin-url-plus-name.md) — how artifacts
  are identified instead.
- [ADR 0003](0003-a-stale-or-substituted-artifact-is-a-hard-error.md) — what
  happens when the local copy disagrees with the manifest.
- [ADR 0004](0004-the-manifest-is-the-only-record-of-applied-state.md) — why
  there is no separate lockfile.
- [ADR 0005](0005-legacy-manifests-convert-through-an-explicit-command.md) —
  converting manifests written before schema version 6.
- `docs/masterplans/9-make-the-seihou-manifest-multi-developer-safe.md`
- `docs/plans/76-record-portable-artifact-origins-in-the-manifest.md`
- `docs/plans/77-resolve-manifest-artifact-origins-to-local-directories.md`
- `docs/plans/78-refuse-accidental-module-downgrades-and-origin-mismatches.md`
- `docs/user/teams.md` — the workflow this enables.
