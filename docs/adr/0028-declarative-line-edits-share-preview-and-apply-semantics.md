# ADR 0028 — Declarative line edits share preview and apply semantics

- Status: Accepted
- Date: 2026-11-11

## Context

Managed update must preview migration effects without running arbitrary shell
commands. An opaque shell command removing `.envrc` from `.gitignore` caused
preview and apply reconciliation plans to differ despite equal file counts.
Count equality cannot authorize different bytes or ownership metadata.

## Decision

Known text cleanup uses `MigrationOp.RemoveLine { path, line }`, executed by the
same filesystem effect in pure staging and real apply. It removes every exact
logical line, excluding its LF/CRLF terminator from comparison, and preserves
all nonmatching bytes and surviving terminators. Missing files or absent
matches are no-ops. Empty or multiline arguments are rejected.

The operation authorizes only the matching text; unrelated edits need no force.
Targets remain project-relative regular files with no symbolic-link components.
Seed and control paths are protected. Declared targets participate in snapshots,
stale-plan detection and rollback even without a managed ownership record. An
untracked target does not acquire ownership merely because a migration edits it.

An edit is not additive generation. It requires all shared owners under the
existing selection/expansion policy, even if generation of that path is additive.
The extra selection requirement does not rewrite recorded shared-write evidence.
Existing trusted-baseline and file-hash semantics remain unchanged.

The decoder explicitly supports both legacy five-operation and extended unions.
Old CLIs cannot decode the extended union, so schema/engine delivery precedes
producer adoption. Immutable historical declarations are never rewritten.

Opaque `RunCommand` remains an escape hatch and is not executed in preview.
Apply still compares complete accepted and actual reconciliation plans, including
observations, output and metadata. Diagnostic differences name sorted paths and
categories without printing file contents or digests; they never replace equality.

## Consequences

Authors can ship deterministic cleanup inside the ordinary update command.
Arbitrary shell effects can still invalidate a plan and cause rollback. A new
operation must update schema, decoding, pure/real execution, path enumeration,
rendering, safety checks, producer compatibility and user guidance together.

## References

- [Plan 112](../plans/112-make-gitignore-line-removal-migrations-predictable-during-managed-updates.md)
- [ADR 0012](0012-an-additive-co-write-is-not-a-shared-path-conflict.md)
- [ADR 0014](0014-every-semantic-manifest-change-advances-the-schema-version.md)
- [ADR 0015](0015-diagnostics-name-things-as-users-do-and-never-fall-back-to-show.md)
