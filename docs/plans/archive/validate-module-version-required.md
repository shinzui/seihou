---
slug: validate-module-version-required
title: "Validate that modules declare a version"
kind: exec-plan
created_at: 2026-03-27T12:36:08Z
intention: "intention_01kjjgfv60e8y9qata1sfk8qrc"
---


# Validate that modules declare a version

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

Several downstream features now rely on modules having a version: `seihou status` displays module versions, `seihou outdated` compares installed versus available versions, and `seihou upgrade` uses version comparisons to decide whether an upgrade is needed. When a module omits its version field, these features silently degrade — status shows no version, outdated reports "unversioned", and upgrade must guess. By making version a required field at validation time, module authors get immediate feedback when they forget to declare a version, and the rest of the system can rely on the version being present.

After this change, running `seihou validate-module` on a module that lacks a `version` field will report an error: "module must declare a version". The `seihou run` pipeline, which validates before executing, will also reject versionless modules. Existing modules that already have a version will be unaffected.


## Progress

- [x] Add `checkVersionPresent` function to `seihou-core/src/Seihou/Core/Module.hs` (2026-03-27)
- [x] Wire the new check into `validateModule` in the same file (2026-03-27)
- [x] Wire the new check into `buildReport` in `seihou-core/src/Seihou/Engine/Validate.hs` (2026-03-27)
- [x] Update `goodModule` in `seihou-core/test/Seihou/Engine/ValidateSpec.hs` to include a version (2026-03-27)
- [x] Add test case for missing version detection in `ValidateSpec.hs` (2026-03-27)
- [x] Add test case for present version passing in `ValidateSpec.hs` (2026-03-27)
- [x] Update all test fixture `module.dhall` files to include `version = Some "1.0.0"` (2026-03-27)
- [x] Update `goodModule` in `seihou-core/test/Seihou/Core/ModuleSpec.hs` to include a version (2026-03-27)
- [x] Update scaffold template in `seihou-core/src/Seihou/Core/Scaffold.hs` to include version (2026-03-27)
- [x] Verify all existing tests still pass — 655/655 pass (2026-03-27)
- [x] Run `seihou validate-module` against a real module to confirm behavior (2026-03-27)


## Surprises & Discoveries

- The blast radius of making version required was larger than the plan anticipated. Beyond the three planned edits, 14 test fixture `module.dhall` files, the `goodModule` in `ModuleSpec.hs`, and the scaffold template (`Scaffold.hs`) all needed updates. The plan only accounted for updating `ValidateSpec.hs`'s `goodModule`.


## Decision Log

- Decision: Make version presence a core validation error (DiagError), not a lint warning (DiagWarning).
  Rationale: Multiple subsystems (status, outdated, upgrade) depend on version being present. A warning would still allow versionless modules to pass validation, defeating the purpose. Treating it as an error ensures modules are rejected before they enter the manifest without a version.
  Date: 2026-03-26

- Decision: Keep the `version` field as `Maybe Text` in the `Module` type and check at validation time rather than changing the type to non-optional.
  Rationale: The Dhall schema uses `Optional Text` for version, and changing it would require a coordinated schema change in seihou-schema. Validation-time enforcement achieves the same result with a smaller blast radius. The schema can be tightened later.
  Date: 2026-03-26


## Outcomes & Retrospective

Milestone 1 complete. All 655 tests pass. The `seihou validate-module` command now shows `✓ Module version declared` for modules with a version and `✗ Module version declared` with error detail `module must declare a version` for modules without one. The `validateModule` gate (used by `loadModule` and the run pipeline) also rejects versionless modules.

Additional changes beyond the original plan:
- 14 test fixture `module.dhall` files updated from `None Text` to `Some "1.0.0"`
- `goodModule` in `ModuleSpec.hs` updated
- Scaffold template (`Scaffold.hs`) updated to include `version = Some "0.1.0"` in generated modules


## Context and Orientation

Seihou is a composable project scaffolding system. A "module" is a Dhall-defined unit containing variables, steps, commands, and metadata. Modules live in directories with a `module.dhall` file. The `Module` type is defined in `seihou-core/src/Seihou/Core/Types.hs` (line 207) and has a `version :: Maybe Text` field.

Validation happens at two levels. First, the function `validateModule` in `seihou-core/src/Seihou/Core/Module.hs` (line 69) runs nine pure check functions plus one IO check (file existence), collecting error strings. If any errors are found, it returns `Left (ValidationError name errors)`. This is the gate used by `loadModule` and the run pipeline. Second, the structured report engine in `seihou-core/src/Seihou/Engine/Validate.hs` runs the same checks plus optional lint warnings, producing a `ValidateReport` with labeled `DiagCheck` entries. This powers the `seihou validate-module` CLI command, which renders a colored report.

The individual check functions follow a uniform pattern: each takes a `Module` and returns `[Text]` — an empty list means the check passed, non-empty means it found problems. For example, `checkNameFormat` (line 88 of Module.hs) verifies the module name matches `[a-z][a-z0-9-]*`.

Tests live in `seihou-core/test/Seihou/Engine/ValidateSpec.hs`. The test module defines `goodModule` (a valid module) and `badModule` (a module with multiple errors), plus helper functions like `hasFailedCheck` and `hasPassedCheck` that inspect `DiagCheck` labels. Currently, `goodModule` has `version = Nothing` — this must be updated to `Just "1.0.0"` so it remains valid after the new check is added.

Version is consumed in several places: `seihou-cli/src/Seihou/CLI/Status.hs` (line 77) displays it in status output, `seihou-cli/src/Seihou/CLI/Outdated.hs` (line 138) uses it for comparison, and `seihou-cli/src/Seihou/CLI/Upgrade.hs` (line 134) uses it to decide upgrade eligibility.


## Plan of Work

The work is a single milestone with four edits and a test run.

### Milestone 1: Add version-presence validation

After this milestone, `seihou validate-module` will report an error for modules missing a version, all existing tests will pass with the updated `goodModule`, and new tests will cover both the missing-version and present-version cases.

**Edit 1: Add `checkVersionPresent` to `seihou-core/src/Seihou/Core/Module.hs`.**

Add a new check function following the same pattern as the existing checks. Place it after `checkNameFormat` (around line 94) since version presence is a fundamental metadata check. The function takes a `Module` and returns `[Text]`. If `m.version` is `Nothing`, it returns `["module must declare a version"]`. If it is `Just v` where `v` is blank after stripping, it returns the same error. Otherwise it returns `[]`. Export it from the module header alongside the other check functions.

**Edit 2: Wire `checkVersionPresent` into `validateModule` in the same file.**

In the `validateModule` function (line 72), add `checkVersionPresent m` to the `pureErrors` accumulation, after `checkNameFormat m`. This ensures `loadModule` and the run pipeline reject versionless modules.

**Edit 3: Wire `checkVersionPresent` into `buildReport` in `seihou-core/src/Seihou/Engine/Validate.hs`.**

Import `checkVersionPresent` from `Seihou.Core.Module` (add it to the import list around line 15). In the `buildReport` function (line 58), add a new `DiagCheck` entry after the module name format check:

    DiagCheck "Module version declared" DiagError (checkVersionPresent m)

**Edit 4: Update tests in `seihou-core/test/Seihou/Engine/ValidateSpec.hs`.**

Change `goodModule` to have `version = Just "1.0.0"` instead of `version = Nothing`. This keeps `goodModule` valid under the new check.

Add two new test cases in the `buildReport` describe block:

1. "detects missing module version" — build a report for a module with `version = Nothing` and assert `hasFailedCheck "Module version declared"`.
2. "passes when module has a version" — build a report for `goodModule` (which now has a version) and assert `hasPassedCheck "Module version declared"`.

**Acceptance criteria:**

Run the full test suite from the repository root:

    cabal test all

All existing tests pass. The two new tests pass. Running `seihou validate-module` on a module without a version shows the error; on a module with a version, it shows a checkmark.


## Concrete Steps

All commands are run from the repository root `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`.

1. Edit `seihou-core/src/Seihou/Core/Module.hs`: add `checkVersionPresent` to the export list, define the function, and add it to `validateModule`.

2. Edit `seihou-core/src/Seihou/Engine/Validate.hs`: import `checkVersionPresent` and add the DiagCheck entry to `buildReport`.

3. Edit `seihou-core/test/Seihou/Engine/ValidateSpec.hs`: update `goodModule` version, add two test cases.

4. Run:

        cabal test all

    Expected: all tests pass, including the new "detects missing module version" and "passes when module has a version" tests.


## Validation and Acceptance

Run the test suite:

    cabal test all

Verify the two new test cases appear in the output and pass. Verify no existing tests regress.

Optionally, test against a real module:

    seihou validate-module path/to/module-without-version

Expected output includes a line like:

    ✗ Module version declared
        module must declare a version

And for a module with a version:

    ✓ Module version declared


## Idempotence and Recovery

All steps are file edits and can be repeated safely. If the test suite fails after edits, the issue is in the edits themselves — review the specific test failure and correct. No external state is modified.


## Interfaces and Dependencies

No new dependencies. The change touches three existing modules:

In `seihou-core/src/Seihou/Core/Module.hs`, define:

    checkVersionPresent :: Module -> [Text]

In `seihou-core/src/Seihou/Engine/Validate.hs`, add to the `coreChecks` list:

    DiagCheck "Module version declared" DiagError (checkVersionPresent m)

In `seihou-core/test/Seihou/Engine/ValidateSpec.hs`, update `goodModule` and add two `it` blocks.
