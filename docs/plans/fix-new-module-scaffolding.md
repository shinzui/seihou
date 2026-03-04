# Fix new-module Scaffolding to Generate Valid Modules

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

The `seihou new-module my-template` command scaffolds a new module directory with a `module.dhall` and an example template file. Currently, the generated `module.dhall` is broken: it uses wrong field names and omits required fields, so the resulting module cannot be loaded by `seihou run`, `seihou vars`, or `seihou validate-module`. After this change, the scaffolded module will be immediately usable — a user can run `seihou new-module my-template && seihou validate-module my-template` and see it pass, or run `seihou run my-template --var project.name=hello --dry-run` and see a valid plan.

There are also no tests for the new-module command. After this change, an automated test will verify that the generated module round-trips through the Dhall loader and passes validation.


## Progress

- [x] M1-1: Fix field name `variables` → `vars` in `moduleDhall` (2026-03-03)
- [x] M1-2: Fix field name `as` → `alias` in exports type annotation (2026-03-03)
- [x] M1-3: Add `patch = None Text` to the generated step (2026-03-03)
- [x] M1-4: Add `commands` field to the generated module.dhall (2026-03-03)
- [x] M1-5: Verify the generated Dhall matches fixture module structure — `seihou validate-module` passes (2026-03-03)
- [x] M2-1: Create `seihou-core/test/Seihou/Core/ScaffoldSpec.hs` with round-trip test (2026-03-03)
- [x] M2-2: Register `Seihou.Core.ScaffoldSpec` in `seihou-core/seihou-core.cabal` (2026-03-03)
- [x] M2-3: Wire ScaffoldSpec into the test runner `seihou-core/test/Main.hs` (2026-03-03)
- [x] M2-4: Build and test — all 462 tests pass (458 existing + 4 new) (2026-03-03)
- [x] M2-5: Manual verification — `seihou new-module test-mod && seihou validate-module test-mod` (2026-03-03)


## Surprises & Discoveries

- The test was placed in `Seihou.Core.ScaffoldSpec` rather than `Seihou.CLI.NewModuleSpec` since the functions moved to `Seihou.Core.Scaffold`. This is a cleaner mapping than the plan originally specified.
- Test count increased from 458 to 462 (4 new tests: 3 round-trip + 1 template content check).
- The `seihou run` command does not accept a path argument for the module directory — it uses the module registry. The `validate-module` and `vars` commands do accept paths. This means `seihou run <path> --dry-run` from the manual acceptance section does not work with a `--path` override, but this is a pre-existing CLI design choice, not a scaffolding bug.


## Decision Log

- Decision: Fix the existing `moduleDhall` function rather than introducing a Dhall serialization layer for the Module type.
  Rationale: The generated module.dhall is a simple, static template with one variable (the module name). A full Module-to-Dhall serializer would be over-engineered for this use case and would require handling recursive types (VarType), union types (Strategy), and expression serialization. String interpolation is the right tool here. The fix is four field-name/field-addition corrections.
  Date: 2026-03-03

- Decision: Place the test in `seihou-core/test/Seihou/CLI/NewModuleSpec.hs` even though `NewModule.hs` lives in seihou-cli.
  Rationale: The test verifies that the generated Dhall content can be loaded by `evalModuleFromFile` and passes `validateModule`, both of which are in seihou-core. The test does not exercise CLI argument parsing or IO side effects — it tests the `moduleDhall` function's output string. Since seihou-cli is an executable (not a library), its internal modules cannot be imported by seihou-core's test suite. Instead, we extract the Dhall content generation into a testable location or test via the file system using seihou-core's loader. We will write the generated content to a temp directory and load it with `evalModuleFromFile`.
  Date: 2026-03-03

- Decision: Keep the scaffolded module minimal — one text variable, one template step, one prompt, no commands, no exports.
  Rationale: The purpose of `new-module` is to give the user a valid starting point they can customize. A minimal module is easier to understand and modify. Users who need commands, exports, or DhallText steps can add them following the examples in the fixture modules.
  Date: 2026-03-03

- Decision: Name the test `Seihou.Core.ScaffoldSpec` rather than `Seihou.CLI.NewModuleSpec`.
  Rationale: The generation functions moved to `Seihou.Core.Scaffold` in seihou-core, so the test follows the standard naming convention of matching the module under test. No need to create a `test/Seihou/CLI/` directory in seihou-core.
  Date: 2026-03-03


## Outcomes & Retrospective

### Outcomes

All objectives met:

1. **Generated `module.dhall` is now valid.** The four field-name/field-addition bugs are fixed. Running `seihou new-module <name> && seihou validate-module <path>` succeeds — all 14 validation checks pass (Dhall eval + 9 semantic rules + source file existence + format checks).

2. **`seihou vars` works on the generated module.** Lists `project.name (text, required)` as expected.

3. **Scaffold logic extracted to `Seihou.Core.Scaffold`.** The pure `moduleDhall` and `readmeTemplate` functions now live in seihou-core, making them testable from the core test suite. `NewModule.hs` in seihou-cli imports and uses them without duplication.

4. **4 automated tests added.** `ScaffoldSpec` verifies: Dhall round-trip loading, `validateModule` pass, expected structure (1 var, 1 step, 1 prompt, 0 commands, 0 exports, 0 deps), and template placeholder content. All 462 tests pass.

### Lessons

- Extracting pure generation functions from CLI modules into the core library is a good pattern for testability. The CLI module stays thin (IO orchestration only) while the core module is fully testable.
- The plan originally specified `Seihou.CLI.NewModuleSpec` as the test location, but since the functions moved to `Seihou.Core.Scaffold`, renaming the test to `Seihou.Core.ScaffoldSpec` was the right call — following the convention of matching test module names to source module names.


## Context and Orientation

A "module" in Seihou is a directory containing a `module.dhall` file and a `files/` subdirectory with source artifacts (templates, copy files, etc.). The `module.dhall` defines the module's metadata: its name, variable declarations, exports, prompts, generation steps, commands, and dependencies.

The Dhall schema is defined in `schema/Module.dhall`. The Haskell decoder in `seihou-core/src/Seihou/Dhall/Eval.hs` reads `module.dhall` files using field-by-field record decoding. The decoder expects these exact field names:

    Top-level: name, description, vars, exports, prompts, steps, commands, dependencies
    VarDecl:   name, type, default, description, required, validation
    VarExport: var, alias   (NOT "as" — "as" is a Dhall reserved keyword)
    Prompt:    var, text, when, choices
    Step:      strategy, src, dest, when, patch
    Command:   run, workDir, when

The current `seihou new-module` implementation lives in `seihou-cli/src/Seihou/CLI/NewModule.hs`. Its `moduleDhall` function (line 67) generates the Dhall content as a `Text` string via `T.unlines`. The generated content has four bugs:

1. Uses `variables` as the field name (line 72), but the decoder expects `vars`.
2. Uses `as` in the exports type annotation (line 81), but the decoder expects `alias`.
3. Omits the `patch` field in steps. The step decoder requires `field "patch" (maybe strictText)`.
4. Omits the `commands` field entirely. The module decoder requires `field "commands" (list commandDecoder)`.

These bugs mean the generated module.dhall fails to load with a `DhallEvalError` when the user tries to run, validate, or inspect it.

Fixture modules that demonstrate the correct structure:
- `seihou-core/test/fixtures/haskell-base/module.dhall` — 3 vars, 1 export, 1 prompt, 5 steps (including dhall-text), 1 command, no deps
- `seihou-core/test/fixtures/nix-base/module.dhall` — 1 var, 1 export, 0 prompts, 1 step, 0 commands, no deps

The test infrastructure uses Tasty with Hspec wrappers. Tests are in `seihou-core/test/`, registered in `seihou-core/seihou-core.cabal` under `test-suite seihou-core-test`, and wired together in `seihou-core/test/Main.hs`.

Module validation is performed by `validateModule` in `seihou-core/src/Seihou/Core/Module.hs`, which checks nine rules including name format, unique variable names, prompt references, step file existence, export references, dependency names, safe destinations, destination variable references, and command safety.


## Plan of Work

### Milestone 1: Fix the generated module.dhall

This milestone corrects the four bugs in `moduleDhall` so the generated content matches the Dhall schema and can be loaded by `evalModuleFromFile`. At the end, the `moduleDhall` function produces Dhall text structurally identical to the fixture modules.

In `seihou-cli/src/Seihou/CLI/NewModule.hs`, edit the `moduleDhall` function (lines 67–98):

1. Change `", variables ="` to `", vars ="` on line 72.
2. Change `", exports = [] : List { var : Text, as : Optional Text }"` to `", exports = [] : List { var : Text, alias : Optional Text }"` on line 81.
3. Add `"    , patch = None Text"` after the `when` field in the step record (after line 93).
4. Add a `commands` field after the `steps` block, before `dependencies`. Use the empty list annotation: `", commands = [] : List { run : Text, workDir : Optional Text, when : Optional Text }"`.

Acceptance: the generated Dhall text, when written to a file and loaded with `evalModuleFromFile`, returns `Right module` where `moduleName module == "test-mod"`.


### Milestone 2: Add a round-trip test

This milestone adds an automated test that generates a module, writes it to a temp directory, loads it with the Dhall loader, and validates it. This ensures future changes to either the generator or the decoder don't silently break compatibility.

Create `seihou-core/test/Seihou/CLI/NewModuleSpec.hs` with a test that:
1. Calls `moduleDhall "test-mod"` to get the Dhall content.
2. Writes it to a temp directory at `<tmp>/test-mod/module.dhall`.
3. Creates the `files/` subdirectory and writes `README.md.tpl` with the template content.
4. Calls `evalModuleFromFile` on the written file.
5. Asserts the result is `Right` and the module name is `"test-mod"`.
6. Calls `validateModule` on the loaded module and asserts it returns `Right`.
7. Verifies the module has exactly 1 variable (`project.name`), 1 step, 1 prompt, 0 commands, 0 exports, 0 dependencies.

This requires importing `moduleDhall` and `readmeTemplate` from `Seihou.CLI.NewModule`. Since `seihou-cli` is an executable, its modules are not importable from seihou-core's test suite. To solve this, move `moduleDhall` and `readmeTemplate` (pure functions with no IO or CLI dependencies) to a new module `Seihou.Core.Scaffold` in seihou-core, and re-export them from `Seihou.CLI.NewModule`. This keeps the CLI module thin and makes the generation logic testable.

Register the new modules in the appropriate `.cabal` files and wire the test into the test runner `seihou-core/test/Main.hs`.


## Concrete Steps

**Working directory**: `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`

**Step 1** (M1): Create `seihou-core/src/Seihou/Core/Scaffold.hs` with `moduleDhall` and `readmeTemplate`, moved from `NewModule.hs` and corrected.

**Step 2** (M1): Update `seihou-cli/src/Seihou/CLI/NewModule.hs` to import and re-use `moduleDhall` and `readmeTemplate` from `Seihou.Core.Scaffold`.

**Step 3** (M1): Register `Seihou.Core.Scaffold` in `seihou-core/seihou-core.cabal` under `exposed-modules`.

**Step 4** (M1): Build:

    cabal build all

Expected: compiles cleanly.

**Step 5** (M1): Manually verify the generated Dhall looks correct:

    cabal run seihou -- new-module verify-test --path /tmp/verify-test
    cat /tmp/verify-test/module.dhall

Expected: the output matches the structure of `seihou-core/test/fixtures/nix-base/module.dhall` — uses `vars`, `alias`, includes `patch` and `commands` fields.

    cabal run seihou -- validate-module /tmp/verify-test

Expected: validation passes.

    rm -rf /tmp/verify-test

**Step 6** (M2): Create `seihou-core/test/Seihou/CLI/NewModuleSpec.hs` with the round-trip test.

**Step 7** (M2): Register `Seihou.CLI.NewModuleSpec` in `seihou-core/seihou-core.cabal` under `test-suite > other-modules`.

**Step 8** (M2): Wire the test into `seihou-core/test/Main.hs`.

**Step 9** (M2): Build and run all tests:

    cabal build all
    cabal test all

Expected: all existing 458 tests pass plus the new `NewModuleSpec` tests.


## Validation and Acceptance

### Automated

    cabal test all

All 458 existing tests pass, plus the new round-trip test in `NewModuleSpec`. The new test verifies:
- The generated `module.dhall` loads via `evalModuleFromFile` without error.
- The loaded module passes `validateModule`.
- The module has the expected structure (1 variable named `project.name`, 1 template step, 1 prompt, 0 commands, 0 exports, 0 dependencies).

### Manual acceptance

    seihou new-module demo-project
    seihou validate-module demo-project

Expected output from validate: no errors, clean exit.

    seihou vars demo-project

Expected: lists `project.name (text, required)`.

    seihou run demo-project --var project.name=hello --dry-run

Expected: shows a plan preview listing `README.md` as a new file.

    rm -rf demo-project


## Idempotence and Recovery

All steps are safe to repeat. The `new-module` command already checks for directory existence and refuses to overwrite. The test uses a temp directory that is cleaned up. If a step fails partway, `git checkout` the affected files and retry.


## Interfaces and Dependencies

No new external dependencies.

In `seihou-core/src/Seihou/Core/Scaffold.hs`, define:

    moduleDhall :: Text -> Text
    readmeTemplate :: Text

These are pure functions that generate Dhall content and template content respectively. They have no IO or effect dependencies.

In `seihou-cli/src/Seihou/CLI/NewModule.hs`, the existing `moduleDhall` and `readmeTemplate` definitions are replaced with re-exports from `Seihou.Core.Scaffold`.

In `seihou-core/test/Seihou/CLI/NewModuleSpec.hs`, define:

    tests :: IO TestTree
    spec :: Spec
