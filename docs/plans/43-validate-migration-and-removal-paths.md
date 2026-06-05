---
id: 43
slug: validate-migration-and-removal-paths
title: "Validate migration and removal paths"
kind: exec-plan
created_at: 2026-06-05T14:34:10Z
intention: "intention_01ktc3hwwneswaz13bvr1tb6f9"
master_plan: "docs/masterplans/5-first-public-release-readiness.md"
---

# Validate migration and removal paths

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

After this change, module-declared migrations and removals cannot delete, move, or rewrite paths outside the current project. Unsafe declarations fail validation or planning before any destructive filesystem operation runs.

This is release-critical because Seihou installs and runs third-party modules from git repositories. Public users need a clear boundary: module-authored file operations are project-relative unless the user explicitly chooses to run shell commands that can do more.


## Progress

- [ ] Reuse or add a shared project-relative path safety helper.
- [ ] Validate migration `MoveFile`, `MoveDir`, `DeleteFile`, `DeleteDir`, and `RunCommand.workDir` paths.
- [ ] Validate removal step destinations and removal command work directories.
- [ ] Add tests covering unsafe migration declarations.
- [ ] Add tests covering unsafe removal declarations.
- [ ] Run focused migration/removal and full core tests.


## Surprises & Discoveries

None yet.


## Decision Log

- Decision: Reject unsafe migration and removal paths before disk mutation.
  Rationale: Conflict detection protects user edits but does not protect the project boundary. Path validation must happen before `renamePath`, `removeFile`, or `removeDirectoryRecursive`.
  Date: 2026-06-05


## Outcomes & Retrospective

To be filled during and after implementation.


## Context and Orientation

Migration operations are declared in module Dhall and decoded into `Seihou.Core.Migration.MigrationOp` in `seihou-core/src/Seihou/Core/Migration.hs`. The execution engine is `seihou-core/src/Seihou/Engine/Migrate.hs`. It classifies some file operations by hash, then executes operations such as `renamePath src dest`, `removeFile p`, and `removeDirectoryRecursive p`.

Removal operations are declared in a module's `removal` field and handled by `seihou-core/src/Seihou/Engine/Remove.hs`. `buildStepOp` converts declared removal destinations to `FilePath`, and `executeRemovalOps` later deletes or rewrites those paths.

`docs/plans/42-constrain-rendered-generation-paths.md` owns the same safety concept for generated destinations. If that plan has already introduced a helper such as `validateProjectRelativePath`, use it here. If this plan runs first, introduce the helper and document that EP-2 should consume it.


## Plan of Work

Milestone 1 introduces shared safety validation if it does not already exist. The helper must reject absolute paths and any segment equal to `..`. It should accept ordinary relative paths and filenames containing dots.

Milestone 2 applies validation to migrations. The safest point is before `classifyMigration` or inside `classifyOp`, because that is before execution and still returns structured migration errors through the CLI. If the existing error types do not have a path validation variant, add one to `MigrationExecError` or the CLI-level `MigrateError` path with a clear message such as:

```text
unsafe migration path '../outside': paths must be relative and must not contain '..' segments
```

Validate all path-bearing migration fields: `MoveFile.src`, `MoveFile.dest`, `MoveDir.src`, `MoveDir.dest`, `DeleteFile.path`, `DeleteDir.path`, and `RunCommand.workDir`.

Milestone 3 applies validation to removals. Update `buildStepOp` so unsafe `RemovalStep.dest` values produce `Left RemovalError` rather than an operation. If needed, add a `RemovalUnsafePath Text` constructor to `RemovalError`. Validate `RemovalCommandOp` work directories before the CLI executes removal commands.

Milestone 4 adds regression tests. Use `seihou-core/test/Seihou/Engine/MigrateSpec.hs` and `seihou-core/test/Seihou/Engine/RemoveSpec.hs`. The tests should assert that unsafe paths fail before any file is removed or renamed.


## Concrete Steps

Inspect current path-bearing operations:

```bash
rg -n "MoveFile|MoveDir|DeleteFile|DeleteDir|RunCommand|RemovalStep|RemovalCommand|removeDirectoryRecursive|renamePath" seihou-core/src seihou-core/test
```

Run focused tests after edits:

```bash
cabal test seihou-core-test --test-options '--match "Seihou.Engine.Migrate"'
cabal test seihou-core-test --test-options '--match "Seihou.Engine.Remove"'
```

Then run:

```bash
cabal test seihou-core-test
```


## Validation and Acceptance

Acceptance requires:

- A migration declaring `DeleteDir { path = "../outside" }` is rejected before `removeDirectoryRecursive` can run.
- A migration declaring `MoveFile { src = "README.md", dest = "../outside" }` is rejected before `renamePath` can run.
- A migration command work directory of `Some "../outside"` is rejected before the command can run.
- A removal step with `dest = "../outside"` is rejected before file deletion.
- Existing migration and removal tests still pass.

When implemented through the CLI, users should see a normal `[error]` message and a non-zero exit rather than a crash.


## Idempotence and Recovery

These changes add validation before mutation, so they are safe to retry. If a test accidentally creates files outside a temporary directory while reproducing the old bug, remove only the temporary path created by the test and record the cleanup in Surprises & Discoveries.


## Interfaces and Dependencies

This plan integrates with EP-2 through the shared path safety helper. It touches `Seihou.Core.Migration`, `Seihou.Engine.Migrate`, `Seihou.Engine.Remove`, their tests, and possibly `seihou-core/seihou-core.cabal` if a new helper module is added.
