---
slug: schema-upgrade-command
title: "Add seihou schema-upgrade Command"
kind: exec-plan
created_at: 2026-03-21T12:15:05Z
---


# Add `seihou schema-upgrade` Command

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

When seihou evolves its module schema — adding fields like `commands`, `patch`, or `version` — existing `module.dhall` files become stale. They are missing fields the decoder now requires, and attempting to load them with `seihou run` or `seihou validate-module` produces a Dhall evaluation error. Users currently have to figure out what changed and hand-edit every module file.

After this change, a user can run `seihou schema-upgrade ./my-module` (or `seihou schema-upgrade` in a module directory) and the tool will detect which fields are missing from the module's `module.dhall`, report what needs to change, and — unless `--dry-run` is passed — rewrite the file with the missing fields filled in using safe defaults. The command also supports `--all` to upgrade every installed and project-local module at once.

Additionally, the schema has been restructured into a Dhall package supporting record completion (`::`) for ergonomic module authoring, and dependencies have been standardized on the record form (`{ module, vars }`).


## Progress

- [x] M1: Restructure schema/ as Dhall package with Type/default (2026-03-21)
- [x] M2: Core schema-upgrade logic in seihou-core (2026-03-21)
- [x] M3: Tests for SchemaUpgrade (13 tests, all passing) (2026-03-21)
- [x] M4: CLI plumbing + handler for schema-upgrade command (2026-03-21)
- [x] M5: Update fixtures and scaffold to canonical dep format (2026-03-21)


## Surprises & Discoveries

- The `prompts` type annotation contains `Optional (List Text)` which includes the substring `List Text`. Initial test assertions checking for `List Text` absence in the full output were too broad. The replacement correctly targets only `[] : List Text` (the dependency type annotation), not all occurrences of `List Text`.

- Step blocks in fixtures are preceded by `[ ` (e.g., `[ { strategy = ...}`), requiring `containsStepStart` to use `T.isInfixOf` rather than `T.isPrefixOf` on the stripped line.

- The converted record form `{ module = "foo", vars = ... }` naturally contains `"foo",` as a substring, making naive assertions about bare string removal unreliable. Tests must check for the specific bare format (e.g., `"foo", "bar"` adjacency) instead.


## Decision Log

- Decision: Use text-based detection and rewriting rather than Dhall AST manipulation.
  Rationale: Old modules fail Dhall decoding precisely because they are missing required fields. Text-based detection is simple, reliable for Dhall's deterministic formatting, and avoids depending on a Dhall AST manipulation library.
  Date: 2026-03-21

- Decision: No explicit schema version number in module.dhall. The presence or absence of fields is the version indicator.
  Rationale: Adding a `schemaVersion` field would itself be a schema change requiring migration. Field detection is sufficient.
  Date: 2026-03-21

- Decision: Restructure schema/ into a Dhall package with `{ Type, default }` records for record completion (`::`) support.
  Rationale: Dhall's record completion operator provides type safety and ergonomic defaults. Module authors can write `S.Step::{ strategy = "template", src = "foo.tpl", dest = "foo" }` instead of spelling out all optional fields.
  Date: 2026-03-21

- Decision: Standardize dependencies on the record form `{ module : Text, vars : List { name : Text, value : Text } }`.
  Rationale: The dual-format dependency system (bare strings vs records) prevents using Dhall's record completion for type-safe module authoring. The record form is strictly more expressive. The Haskell decoder retains backward compatibility for bare strings as a safety net.
  Date: 2026-03-21


## Outcomes & Retrospective

All milestones completed. The implementation delivers:

1. **Schema package** — 7 new schema files (`VarDecl.dhall`, `VarExport.dhall`, `Prompt.dhall`, `Step.dhall`, `Command.dhall`, `Dependency.dhall`, `package.dhall`) plus a rewritten `Module.dhall` with `{ Type, default }` records. Verified with `dhall type` and record completion tests.

2. **Core upgrade logic** — `Seihou.Core.SchemaUpgrade` module with `detectIssues`, `upgradeModuleText`, and `issueMessage`. Handles 5 issue types: missing version, missing patch, missing commands, bare string deps, and `List Text` type annotation.

3. **CLI command** — `seihou schema-upgrade [PATH] [--dry-run] [--all]` with colored output, summary reporting, and idempotent operation.

4. **Test coverage** — 13 new tests covering detection, rewriting, idempotency, and edge cases. Full test suite (647 tests) passes.

5. **Canonical format** — All 15 fixtures and the scaffold updated to use record-form dependencies.


## Context and Orientation

See the approved plan at `.claude/plans/jazzy-foraging-toast.md` for full context, file paths, and implementation details.

Key files:
- `schema/package.dhall` — Entry point for the Dhall schema package
- `seihou-core/src/Seihou/Core/SchemaUpgrade.hs` — Core detection and rewriting logic
- `seihou-cli/src/Seihou/CLI/SchemaUpgrade.hs` — CLI handler
- `seihou-cli/src/Seihou/CLI/Commands.hs` — Command type and parser
- `seihou-core/test/Seihou/Core/SchemaUpgradeSpec.hs` — Tests
