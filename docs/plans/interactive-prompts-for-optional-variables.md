# Interactive Prompts for Optional Variables

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

Today, when a module declares a required variable and the user provides no value via CLI flags, environment, or config files, Seihou prompts the user interactively — that part works. But optional variables are never prompted for: they silently disappear, and any steps guarded by `IsSet` conditions quietly skip. The user never learns that these optional features exist, and has no opportunity to enable them during an interactive run.

After this change, Seihou will prompt users for optional variables too — presenting them as skippable questions that the user can answer or dismiss by pressing Enter. A module author can attach prompts to optional variables and the user will see them during `seihou run`, giving them a chance to opt in to features like CI configuration, license selection, or Docker support. The prompts appear after all required variables are resolved, clearly separated as optional. The user experience looks like:

    What is your project name? my-app
    Project version [0.1.0.0]:

    Optional configuration:
      Include a license? (MIT/Apache-2.0/BSD-3-Clause) [skip]:
      Enable GitHub Actions CI? (yes/no) [skip]: yes

Required prompts enforce non-empty input (as they do today). Optional prompts accept empty input as "skip" — leaving the variable unresolved, exactly as if it were never provided. Default values are shown in brackets so the user can accept them by pressing Enter.


## Progress

- [x] M1: Show default values in prompt text for required and optional variables (2026-03-06)
- [x] M1: Allow empty input on required variables that have a default (accept the default) (2026-03-06)
- [x] M1: Add new tests for default display behavior (4 tests: default accept, user override, skip hint, bool default) (2026-03-06)
- [x] M2: Collect optional unresolved variables after required resolution succeeds (2026-03-06)
- [x] M2: Run prompts for optional variables after required resolution (2026-03-06)
- [x] M2: Merge optional prompt results into the resolved variable map (2026-03-06)
- [x] M2: Add "Optional configuration:" separator in console output (2026-03-06)
- [x] M2: Accept empty input as "skip" for optional prompts (2026-03-06)
- [x] M2: Write pure tests for optional prompt flow in PromptSpec (6 tests) (2026-03-06)
- [x] M2: Write integration tests for resolveWithPrompts with optional variables (2026-03-06)
- [x] M3: Add test fixture module with optional prompted variables (2026-03-06)
- [x] M3: End-to-end validation with `seihou validate-module` (2026-03-06)
- [x] M3: Update user documentation (module-authoring.md prompts section) (2026-03-06)


## Surprises & Discoveries

- The optional prompt logic needed to be added in **two** places in `resolveWithPrompts`: the initial success path (when `resolveVariables` returns `Right`) and the error-recovery path (when required prompts succeed and re-resolution returns `Right`). The plan only described the success path. Discovered when the "prompts for optional variables after required resolution" test failed with a Map.! key error — the error path re-resolved successfully but skipped optional prompts.


## Decision Log

- Decision: Optional prompts appear after all required variables are resolved, not interleaved.
  Rationale: Required variables must be satisfied for the module to function. Presenting them first gives the user a clear "must answer" / "may answer" distinction and avoids the confusing situation where a required variable's condition depends on an optional variable that hasn't been prompted yet.
  Date: 2026-03-06

- Decision: Empty input on an optional prompt means "skip" (leave variable unresolved).
  Rationale: This is the least surprising behavior — the user pressed Enter without typing, which signals "I don't want to provide this." The variable remains absent, exactly matching non-interactive behavior.
  Date: 2026-03-06

- Decision: Default values are shown in bracket notation for both required and optional prompts.
  Rationale: Showing defaults is standard CLI UX (e.g., `npm init`, `cargo init`). It reduces friction by letting users accept common defaults with a single keypress.
  Date: 2026-03-06

- Decision: No new Dhall schema changes needed — the existing prompt format already supports attaching prompts to optional variables.
  Rationale: The `Prompt` type references a `VarName` and `VarDecl` has a `required :: Bool` field. A module author just needs to declare a prompt whose `var` references an optional variable declaration. The only gap is in the resolution engine, which currently ignores these prompts.
  Date: 2026-03-06


## Outcomes & Retrospective

All three milestones completed on 2026-03-06.

**What was delivered:**
- Default values now display in bracket notation for all prompts (required and optional). Users can accept defaults by pressing Enter.
- Optional variables with prompts are now presented after required resolution succeeds, under an "Optional configuration:" header. Empty input skips the variable.
- Test fixture (`seihou-core/test/fixtures/prompted-optional/`) demonstrates a module with 1 required and 2 optional prompted variables.
- User documentation updated in `docs/user/module-authoring.md`.

**Key insight:** The `resolveWithPrompts` function has two distinct success paths — one when initial resolution succeeds and one when required prompts fill in missing values and re-resolution succeeds. Optional prompt logic was needed in both paths. The plan only described the first path; the second was discovered during testing.

**No schema changes required.** The existing `Prompt` and `VarDecl` types already supported optional prompts — the gap was entirely in the resolution engine.

**Test coverage:** 10 new pure tests (4 for default display in M1, 6 for optional prompt flow in M2) plus fixture validation in M3.


## Context and Orientation

Seihou is a composable project scaffolding system written in Haskell. Users define modules (directories with a `module.dhall` and template files), then run `seihou run <module>` to generate projects. Each module declares variables, prompts, and generation steps. Variables can be required or optional, and can be resolved from CLI flags, environment variables, config files, module defaults, or interactive prompts.

The interactive prompt system involves several files:

`seihou-core/src/Seihou/Core/Types.hs` defines the core data types. The relevant ones are:

    data VarDecl = VarDecl
      { name :: VarName,         -- e.g., VarName "project.name"
        type_ :: VarType,        -- VTText, VTBool, VTInt, VTList, VTChoice
        default_ :: Maybe VarValue,  -- e.g., Just (VText "0.1.0.0")
        description :: Maybe Text,
        required :: Bool,        -- True = must be resolved, False = optional
        validation :: Maybe Validation
      }

    data Prompt = Prompt
      { var :: VarName,          -- which variable this prompt fills
        text :: Text,            -- display text, e.g., "What is the project name?"
        condition :: Maybe Expr, -- optional when-clause
        choices :: Maybe [Text]  -- optional numbered menu choices
      }

    data VarSource = FromCLI | FromEnv Text | FromLocalConfig
                   | FromNamespaceConfig Text | FromGlobalConfig
                   | FromDefault | FromPrompt

`seihou-core/src/Seihou/Core/Variable.hs` contains `resolveVariables`, a pure function that attempts to resolve every variable from the precedence chain (CLI > env > local config > namespace config > global config > default). When a required variable has no value from any source, it returns `Left (MissingRequiredVar name)`. When an optional variable has no value, it returns `Right Nothing` — the variable is simply absent from the result map.

`seihou-core/src/Seihou/Interaction/Prompt.hs` contains the low-level prompt execution. `runPrompts` takes a list of `Prompt` values, a list of `VarDecl` values (the "unresolved" set), and the current variable bindings. It iterates through each prompt, checks its condition, and calls `promptForVar` to display the prompt, read input, coerce the value, and validate it. Free-text prompts retry up to 3 times on empty or invalid input. Choice prompts display a numbered menu.

`seihou-core/src/Seihou/Composition/Resolve.hs` contains `resolveWithPrompts`, which orchestrates the full composition-aware resolution. For each module in topological order, it calls `resolveVariables`. If resolution fails with only `MissingRequiredVar` errors and the session is interactive, it calls `runPrompts` for those missing variables, then re-resolves with the prompted values injected. This function is the main integration point and is the one that needs to be extended.

`seihou-core/src/Seihou/Effect/Console.hs` defines the `Console` effect with operations `PutText`, `PutError`, `GetLine`, `Confirm`, and `IsInteractive`. `seihou-core/src/Seihou/Effect/ConsoleInterp.hs` provides the IO interpreter, and `seihou-core/src/Seihou/Effect/ConsolePure.hs` provides a pure test interpreter that takes scripted inputs and accumulates outputs.

`seihou-core/test/Seihou/Interaction/PromptSpec.hs` contains tests for the prompt system, using `runConsolePure` to inject scripted inputs and assert outputs. It tests `runPrompts`, `promptForVar`, and `resolveWithPrompts`.

The CLI entry point is `seihou-cli/src/Seihou/CLI/Run.hs`. The `handleRun` function loads the composition, calls `resolveWithPrompts` inside an `Eff` block with the `Console` effect, then proceeds to plan compilation and execution.

A module.dhall file declares prompts in the `prompts` list. Each prompt's `var` field must reference a declared variable. Today, module authors can already write prompts for optional variables in their Dhall files — the system just ignores them because `resolveWithPrompts` only enters the prompting path when `MissingRequiredVar` errors occur.


## Plan of Work

The work breaks into three milestones: improving the existing prompt UX (default display), adding optional variable prompting to the resolution engine, and end-to-end validation.


### Milestone 1: Show default values in prompts

**Scope**: Improve the existing prompt display so that when a variable has a default value, the prompt shows it in brackets (e.g., `Project version [0.1.0.0]:`). When the user presses Enter on a required variable that has a default, the default is accepted rather than triggering the "Value cannot be empty" retry. This is a UX improvement that benefits both required and optional prompts.

**What exists at the end**: The `promptFreeText` and `promptWithChoices` functions display defaults, and empty input on a variable with a default accepts that default. All existing tests pass, plus new tests covering the default-acceptance behavior.

**Acceptance**: Run `cabal test seihou-core-test` and confirm all tests pass. Specifically, new tests in `PromptSpec.hs` verify:
- A prompt for a variable with a default shows `[default]` suffix in the prompt text.
- Pressing Enter (empty input) on a variable with a default resolves to the default value with `FromPrompt` source.
- Pressing Enter on a variable without a default still triggers the retry behavior (for required) or skip (for optional, in M2).

**Edits**:

In `seihou-core/src/Seihou/Interaction/Prompt.hs`, modify `promptFreeText` to accept the `VarDecl` and format the prompt text with a default suffix. When a variable has `default_ = Just val`, append ` [<value>]` to the prompt text. When the user provides empty input and a default exists, return the default value with `FromPrompt` source instead of retrying. The function signature changes from taking a `Prompt` to also receiving the `VarDecl` (it already does — the `decl` parameter is present but unused for default display).

Concretely, in `promptFreeText` (currently lines 81–104), after displaying the prompt text on line 88, insert logic: if `decl.default_` is `Just defVal` and `T.null (T.strip raw)`, then return `Right (ResolvedVar defVal FromPrompt decl)` instead of retrying. The prompt text itself should be formatted as `prompt.text <> " [" <> showDefaultValue defVal <> "]:"` when a default exists.

In `PromptSpec.hs`, add tests:
- `it "shows default value in prompt text and accepts Enter"` — provide a `VarDecl` with `default_ = Just (VText "0.1.0.0")`, provide empty input, verify the result value is the default and the prompt text included `[0.1.0.0]`.
- `it "still retries on empty input when no default exists"` — the existing "retries on empty input then succeeds" test covers this, verify it still passes.


### Milestone 2: Prompt for optional variables after required resolution

**Scope**: Extend `resolveWithPrompts` in `seihou-core/src/Seihou/Composition/Resolve.hs` to detect optional variables that have prompts but no resolved value, and prompt the user for them after required variables are resolved. Add a visual separator ("Optional configuration:") before optional prompts. Accept empty input as "skip" for optional prompts.

**What exists at the end**: When running `seihou run` interactively on a module with optional prompted variables, the user sees optional prompts after required ones. They can answer or press Enter to skip. Prompted optional values appear in the resolved map with `FromPrompt` source. Skipped optional variables remain absent from the resolved map, preserving existing behavior.

**Acceptance**: Run `cabal test seihou-core-test` and confirm all tests pass. New tests in `PromptSpec.hs` verify:
- An optional variable with a prompt is shown to the user in interactive mode.
- Empty input on an optional prompt leaves the variable unresolved.
- A provided value on an optional prompt resolves with `FromPrompt` source.
- The "Optional configuration:" separator appears in output.
- Optional prompts respect `when` conditions.
- Non-interactive mode still skips all prompts (no change in behavior).

**Edits**:

In `seihou-core/src/Seihou/Interaction/Prompt.hs`, modify `promptFreeText` to handle the case where the variable is optional (`decl.required == False`) and the user provides empty input — return `Right Nothing` (or a sentinel) indicating "skipped." The cleanest approach is to change `promptForVar` to return `Either VarError (Maybe ResolvedVar)` where `Nothing` means "skipped." Then `runPrompts` can distinguish between "prompt failed" (Left) and "user chose to skip" (Right Nothing) versus "user provided a value" (Right (Just rv)).

Alternatively, keep the return type as `Either VarError ResolvedVar` and have `promptFreeText` return `Left (MissingRequiredVar name)` for skipped optional variables — `runPrompts` already treats `Left` as "skip this variable" (line 55: `Left _err -> go ps acc`). This approach requires no type changes and the skipped variable simply won't appear in the result map, which is the desired behavior. This is the simpler path.

In `seihou-core/src/Seihou/Composition/Resolve.hs`, in the `resolveWithPrompts` function, after the successful resolution branch (line 135 `Right resolved ->`), add logic to:

1. Identify optional variables that have no resolved value: filter `m.vars` for declarations where `required == False`, `not (Map.member decl.name resolved)`, and there exists a prompt in `m.prompts` targeting that variable.
2. If there are any such variables and the session is interactive, output `"Optional configuration:"` via `putText`, then call `runPrompts m.prompts optionalDecls currentBindings`.
3. Merge the resulting optional resolved variables into `fullResolved`.

The key insight is that this logic belongs in the **success** path of resolution (when required variables are all resolved), not in the error path (where it currently lives). Optional variables don't produce errors — they silently disappear. So the optional prompt logic triggers when resolution succeeds but some optional prompted variables remain unresolved.

In `PromptSpec.hs`, add a new `describe "optional prompts"` block with tests:
- Module with one required and one optional variable, both with prompts. Provide input for both. Verify both are resolved.
- Same module, but provide empty input for the optional variable. Verify the required variable is resolved and the optional one is absent.
- Module with only optional prompted variables (no required). Verify prompts fire and "Optional configuration:" separator appears.
- Module with optional prompted variable whose `when` condition is false. Verify the prompt is skipped.
- Non-interactive mode: optional prompts are skipped entirely.


### Milestone 3: End-to-end validation and documentation

**Scope**: Create a test fixture module that uses optional prompted variables, run an end-to-end test with `seihou run --dry-run`, and update the user documentation to describe the optional prompt behavior.

**What exists at the end**: A test fixture at `seihou-core/test/fixtures/prompted-optional/` demonstrates the feature. The user guide at `docs/user/module-authoring.md` documents how to attach prompts to optional variables.

**Acceptance**: The fixture module validates with `seihou validate-module`. The user guide accurately describes the prompt behavior for both required and optional variables.

**Edits**:

Create `seihou-core/test/fixtures/prompted-optional/module.dhall` with a module that has one required prompted variable (`project.name`) and two optional prompted variables (`license` with choices, `enable.ci` as a bool). Create a minimal `files/` directory with a template that references all three variables using `IsSet` guards.

In `docs/user/module-authoring.md`, in the Prompts section (currently lines 110–137), add a subsection explaining that prompts can target optional variables. Describe the behavior: optional prompts appear after required prompts, empty input means skip, defaults are shown in brackets. Include a short Dhall example showing a module with both required and optional prompts.

In `docs/user/getting-started.md`, update the example output in the generation section to show what optional prompts look like.


## Concrete Steps

All commands run from the repository root: `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`

Build and test after each milestone:

    cabal build all 2>&1 | tail -5
    cabal test seihou-core-test 2>&1 | tail -20
    cabal test seihou-cli-test 2>&1 | tail -10


## Validation and Acceptance

After Milestone 1, verify that the default display works by running the PromptSpec tests:

    cabal test seihou-core-test --test-option='-p' --test-option='/default/' 2>&1 | tail -10

After Milestone 2, verify the full prompt flow with a pure test that scripts both required and optional inputs:

    cabal test seihou-core-test --test-option='-p' --test-option='/optional/' 2>&1 | tail -15

After Milestone 3, validate the fixture module:

    cabal run seihou -- validate-module seihou-core/test/fixtures/prompted-optional

The final acceptance criterion is that a module with optional prompted variables produces the following interactive flow (paraphrased):

    $ seihou run prompted-optional --var project.name=my-app

    Optional configuration:
      Include a license? (MIT/Apache-2.0/BSD-3-Clause) [skip]: MIT
      Enable GitHub Actions CI? (yes/no) [skip]:

    [generation proceeds with license=MIT, enable.ci absent]

In non-interactive mode (piped input, CI), the same command produces no prompts and optional variables are absent — identical to current behavior.


## Idempotence and Recovery

All changes are additive. The prompt system's existing behavior is preserved: required prompts work as before, non-interactive mode is unaffected. Optional prompts are a new code path that only activates when the session is interactive and optional prompted variables exist.

Each milestone can be implemented independently. If M1 (default display) is completed but M2 is abandoned, the codebase is strictly better than before. If M2 is partially implemented, the worst case is that optional prompts don't fire — identical to current behavior.

Tests can be run repeatedly. The pure `ConsolePure` interpreter ensures no IO side effects in tests.


## Interfaces and Dependencies

No new library dependencies are needed. All changes use the existing effectful-core effect system and the Console effect.

**Modified interfaces**:

In `seihou-core/src/Seihou/Interaction/Prompt.hs`, `promptFreeText` gains default-value display logic but its signature does not change:

    promptFreeText :: (Console :> es) => Prompt -> VarDecl -> Int -> Eff es (Either VarError ResolvedVar)

In `seihou-core/src/Seihou/Composition/Resolve.hs`, `resolveWithPrompts` keeps its existing signature but adds an optional-prompt phase in the success branch:

    resolveWithPrompts ::
      (Console :> es) =>
      [(Module, FilePath)] ->
      Map VarName Text ->
      Map Text Text ->
      Text ->
      Map VarName Text ->
      Map VarName Text ->
      Map VarName Text ->
      Eff es (Either [VarError] (Map ModuleName (Map VarName ResolvedVar)))

No public type signatures change. The `Prompt`, `VarDecl`, `ResolvedVar`, and `VarSource` types remain unchanged.
