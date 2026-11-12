# ADR 0025 — A rebound instance keeps its saved inputs

- Status: Accepted
- Date: 2026-11-11

## Context

Instance identity includes parent bindings so a composition can invoke a module
more than once. A release can change those bindings without creating a new
invocation. Exact identity lookups alone lose saved inputs, origins, version
history and migration transitions when an edge changes.

## Decision

Within each application and module name, match exact instances first. Pair a
remaining recorded instance with a remaining candidate only when exactly one
remains on each side. Both nonempty sides with any other cardinality are
ambiguous: refuse before effects and name the bindings. `--reconfigure` permits
unpaired candidates as new invocations with fresh inputs and no prior version.
Pure additions and removals do not rebind.

Use the same alignment for input resolution, origin retention, version evidence,
migrations, input summaries and removal-policy comparison. Carry the prior saved
values under the candidate identity. For a rebinding, drop keys set by the new
edge and drop old-edge keys whose saved values still equal the old binding.
Keep saved values that differ from removed bindings: these represent project
overrides. Exact matches retain their existing precedence. Explicit CLI and
recipe inputs still outrank carried values.

Rebinding is planning evidence shown in human and JSON output. The manifest
records the accepted candidate identity with ordinary resolved values; it gains
no field or schema step. The next update sees an exact match.

## Consequences

Ordinary updates preserve project choices without flags or manifest edits.
Several changed edges cannot silently exchange answers. Reconfiguration affects
the entire selected application's saved inputs, so diagnostics and previews must
make that recovery behavior clear. Pairing does not use binding similarity.

## References

- [ADR 0004](0004-the-manifest-is-the-only-record-of-applied-state.md)
- [ADR 0014](0014-every-semantic-manifest-change-advances-the-schema-version.md)
- [ADR 0021](0021-recipe-inputs-resolve-before-module-defaults.md)
- [Plan 123](../plans/123-keep-saved-inputs-when-a-release-changes-a-dependency-s-bindings.md)
