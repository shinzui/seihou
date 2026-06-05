---
id: 42
slug: constrain-rendered-generation-paths
title: "Constrain rendered generation paths"
kind: exec-plan
created_at: 2026-06-05T14:34:04Z
intention: "intention_01ktc3hwwneswaz13bvr1tb6f9"
master_plan: "docs/masterplans/5-first-public-release-readiness.md"
---

# Constrain rendered generation paths

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

After this change, Seihou rejects generated file destinations and command working directories that escape the project root after variables are substituted. A user can pass arbitrary `--var` values to `seihou run` without a module writing `../outside` or running commands from an unintended parent directory.

The current validator checks the authored `dest` and `workDir` text before interpolation. That catches `dest = "../x"` but not `dest = "{{project.name}}/x"` with `--var project.name=..`.


## Progress

- [ ] Add or identify a reusable project-relative path safety helper.
- [ ] Apply the helper to rendered step destinations in `Seihou.Engine.Plan`.
- [ ] Apply the helper to rendered command `workDir` values in `Seihou.Engine.Plan`.
- [ ] Add regression tests for rendered absolute paths and rendered `..` path segments.
- [ ] Run focused plan/template tests and full core tests.


## Surprises & Discoveries

None yet.


## Decision Log

- Decision: Validate rendered paths in the planner instead of relying only on module validation.
  Rationale: The planner is where variable values are known. Validation before interpolation cannot prove the final filesystem path is safe.
  Date: 2026-06-05


## Outcomes & Retrospective

To be filled during and after implementation.


## Context and Orientation

Generation planning happens in `seihou-core/src/Seihou/Engine/Plan.hs`. Each module step has an authored destination `Step.dest :: Text`. The planner renders placeholders with `renderDestPath`, then emits operations such as `WriteFileOp destStr content Template`. Execution later joins that path to the target directory in `seihou-core/src/Seihou/Engine/Execute.hs`.

The existing validation lives in `seihou-core/src/Seihou/Core/Module.hs`. `checkSafeDestinations` rejects raw destinations beginning with `/` or containing `..`, and `checkCommandSafety` does the same for raw command work directories. Those checks are too early because placeholders are not resolved yet.

A safe project-relative path means a path that is relative, non-empty when used as a file destination, and whose normalized path segments do not contain `..`. A filename like `README.v2.md` should be allowed because `..` is not a segment. Absolute paths such as `/tmp/x` must be rejected.


## Plan of Work

Milestone 1 defines path safety. Add a helper in a module available to both this plan and `docs/plans/43-validate-migration-and-removal-paths.md`. A good location is `Seihou.Core.Module` if keeping the change small, or a new `Seihou.Core.Path` module if the helper will be reused by migration/removal code. If a new module is created, add it to `seihou-core/seihou-core.cabal`.

The helper should expose enough information to render good errors. A suitable shape is:

```haskell
validateProjectRelativePath :: Text -> Either Text FilePath
```

It should reject absolute paths, empty destinations where inappropriate, and any segment equal to `..`. It should accept nested paths such as `src/Lib.hs`, paths containing dots inside a filename such as `README.v2.md`, and ordinary directories such as `docs/user`.

Milestone 2 applies the helper after interpolation in `Seihou.Engine.Plan`. Update `compileCopyStep`, `compileTemplateStep`, `compileDhallTextStep`, `compileStructuredStep`, and `compilePatchStep` so each checks the rendered `dest` before computing `parentDirs` or building operations. Update `compileOneCommand` so a rendered `workDir` is checked before creating `RunCommandOp`.

Milestone 3 adds tests. The existing focused tests live under `seihou-core/test/Seihou/Engine/PlanSpec.hs` and related template/validation specs. Add tests proving a raw safe destination can become unsafe after interpolation and that the planner returns `Left` with a clear message rather than emitting operations.


## Concrete Steps

From the repository root, inspect the current call sites:

```bash
rg -n "renderDestPath|renderCommand|checkSafeDestinations|checkCommandSafety" seihou-core/src seihou-core/test
```

After implementation, run focused tests:

```bash
cabal test seihou-core-test --test-options '--match "Seihou.Engine.Plan"'
```

Then run the full core test suite:

```bash
cabal test seihou-core-test
```

If the focused `--match` option is not accepted by the test runner, run `cabal test seihou-core-test` directly and record that in Surprises & Discoveries.


## Validation and Acceptance

Acceptance requires:

- A destination like `{{project.name}}/README.md` with `project.name = ".."` causes `compilePlan` to return an error.
- A destination like `{{project.name}}/README.md` with `project.name = "/tmp/outside"` causes `compilePlan` to return an error.
- A destination like `docs/README.v2.md` remains valid.
- A command `workDir = Some "{{project.name}}"` rejects `project.name = ".."` after interpolation.
- Existing successful generation tests still pass.

The CLI-level observable behavior is that `seihou run` reports a planning error instead of writing outside the current project.


## Idempotence and Recovery

The edits are pure validation and planner changes. If a new helper module causes Cabal module-list failures, add it to `seihou-core/seihou-core.cabal` under `exposed-modules` or move it into an existing exposed module. Re-running the tests is safe.


## Interfaces and Dependencies

This plan may define a shared path helper for EP-3. If it does, `docs/plans/43-validate-migration-and-removal-paths.md` should reuse the same helper and error language. No external dependency is needed; use `System.FilePath` and `Data.Text`.
