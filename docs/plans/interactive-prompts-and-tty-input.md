# Add Interactive Prompts and TTY Input Handling

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

After this change, when a user runs `seihou run <module>` and a required variable has no value from CLI flags, environment variables, or module defaults, Seihou will interactively prompt the user for that value in the terminal. Modules already declare prompts with display text, optional conditions, and optional choice lists — but the runtime currently ignores them and simply errors with "missing required variable." This plan connects the prompt declarations to actual terminal interaction.

A user running `seihou run haskell-base` in a terminal will see:

    What is the project name?

and can type a value. If the prompt declares choices (e.g., license type), the user sees a numbered menu. If the terminal is not interactive (piped input, CI), prompts are skipped and unresolved required variables produce an error. The `seihou vars --explain` output marks prompt-sourced values with "from interactive prompt."


## Progress

- [x] Milestone 1: Console effect interpreters (real TTY + pure for testing) — 2026-03-02
  - [x] Created `seihou-core/src/Seihou/Effect/ConsoleInterp.hs` (real IO interpreter)
  - [x] Created `seihou-core/src/Seihou/Effect/ConsolePure.hs` (pure scripted interpreter)
  - [x] Added both to `seihou-core/seihou-core.cabal` exposed-modules
  - [x] Build verified clean
- [x] Milestone 2: Prompt execution logic and integration into variable resolution — 2026-03-02
  - [x] Created `seihou-core/src/Seihou/Interaction/Prompt.hs` with `runPrompts` and `promptForVar`
  - [x] Added to `seihou-core/seihou-core.cabal` exposed-modules
  - [x] Build verified clean
- [x] Milestone 3: Wire prompts into the `run` command pipeline — 2026-03-02
  - [x] Added `resolveWithPrompts` to `seihou-core/src/Seihou/Composition/Resolve.hs`
  - [x] Modified `seihou-cli/src/Seihou/CLI/Run.hs` to use `resolveWithPrompts` via Console effect
  - [x] All 263 existing tests pass after changes
- [x] Milestone 4: Integration tests and end-to-end validation — 2026-03-02
  - [x] Created `seihou-core/test/Seihou/Interaction/PromptSpec.hs` with 13 tests
  - [x] Wired into `test/Main.hs` and `seihou-core.cabal`
  - [x] `nix fmt` produces no changes
  - [x] All 276 tests pass (263 existing + 13 new)


## Surprises & Discoveries

- The two-phase resolution approach (pure `resolveVariables` first, then prompt fallback) worked cleanly. No changes to the existing pure function were needed, and all 263 existing tests passed without modification after wiring prompts in.
- `nix fmt` reorders imports alphabetically, which moved the `PromptSpec` import in `Main.hs`. This is expected behavior from the Fourmolu formatter.


## Decision Log

- Decision: Build prompt logic as a standalone function that takes a list of prompts and unresolved variable declarations, returning resolved values, rather than weaving prompts into the existing `resolveVariables` function.
  Rationale: The existing `resolveVariables` is a pure function (`Either [VarError] ...`) used in many places. Adding IO/effectful prompt interaction would require changing its signature everywhere. Instead, we call `resolveVariables` first, collect the unresolved variables, run prompts for those, and merge the results. This is simpler, avoids breaking existing tests, and keeps the pure resolution logic testable in isolation.
  Date: 2026-03-01

- Decision: Use plain `System.IO.hSetBuffering`, `System.IO.hFlush`, `System.IO.hIsTerminalDevice`, and `Data.Text.IO.getLine` for TTY input rather than adding a library like `haskeline`.
  Rationale: The prompt UX is simple — display text, read a line, optionally show numbered choices. There is no need for line editing, history, or tab completion. Keeping dependencies minimal matches the project's style. If richer terminal UX is desired later, haskeline can be introduced without changing the effect interface.
  Date: 2026-03-01

- Decision: Prompt execution operates on a single module's prompts at a time, in composition order, matching how `resolveComposedVariables` already resolves module by module.
  Rationale: In a composition, earlier modules' prompts run first (since they appear earlier in topological order). Values entered for one module flow downstream via exports, which may satisfy later modules' variables without prompting. This preserves the existing composition resolution flow.
  Date: 2026-03-01


## Outcomes & Retrospective

All four milestones completed. The interactive prompt system is fully implemented and tested:

- **3 new modules** created: `ConsoleInterp.hs`, `ConsolePure.hs`, `Interaction/Prompt.hs`
- **2 modules modified**: `Composition/Resolve.hs` (added `resolveWithPrompts`), `CLI/Run.hs` (switched to prompt-aware resolution)
- **13 new tests** covering: free-text prompts, choice menus, conditional prompts, boolean coercion, retry logic, CLI bypass, non-interactive mode, cross-module export flow
- **276 total tests** pass (263 existing + 13 new)
- **No external dependencies** added — all functionality uses `System.IO` and `effectful-core`
- The existing `resolveComposedVariables` function was left untouched for backward compatibility


## Context and Orientation

Seihou is a Haskell project scaffolding system built as a Cabal multi-package workspace: `seihou-core` (library) and `seihou-cli` (executable). It uses GHC 9.12.2 with GHC2024, the `effectful` library for effects, Dhall for module definitions, and `optparse-applicative` for the CLI.

A "module" is a directory containing a `module.dhall` file and a `files/` directory with templates. Modules declare variables (typed, with optional defaults), export variables to dependents, and declare prompts. A "prompt" is a `Prompt` record that tells the runtime how to ask the user for a variable's value interactively.

The `Prompt` type is defined in `seihou-core/src/Seihou/Core/Types.hs`:

    data Prompt = Prompt
      { promptVar     :: VarName,      -- which variable this prompt fills
        promptText    :: Text,         -- display text shown to user
        promptWhen    :: Maybe Expr,   -- optional condition (Nothing = always show)
        promptChoices :: Maybe [Text]  -- optional numbered choice list
      }

The `VarSource` type already has a `FromPrompt` variant, and `showSource FromPrompt = "from interactive prompt"` is already implemented in `seihou-core/src/Seihou/Core/Variable.hs`.

The `Console` effect is defined in `seihou-core/src/Seihou/Effect/Console.hs` with five operations: `PutText`, `PutError`, `GetLine`, `Confirm`, and `IsInteractive`. However, there is currently no interpreter — neither a real IO interpreter nor a pure test interpreter. The effect interface exists but nothing implements it.

Variable resolution happens in `seihou-core/src/Seihou/Core/Variable.hs` via `resolveVariables`, a pure function with the precedence chain: CLI overrides > environment variables > module defaults. When neither source provides a value for a required variable, the function returns `Left (MissingRequiredVar name)`. Prompts would fill the gap between environment variables and module defaults — or more precisely, they act as a fallback when no higher-priority source provides a value but before giving up with an error.

For composed modules, `seihou-core/src/Seihou/Composition/Resolve.hs` contains `resolveComposedVariables`, which iterates modules in topological order, injecting exports from dependencies as synthetic defaults, then calling `resolveVariables` for each module. This is the function that would need to be augmented with prompt support.

The CLI entry point for running modules is `seihou-cli/src/Seihou/CLI/Run.hs` in the `handleRun` function. It currently calls `resolveComposedVariables`, and if resolution fails with `MissingRequiredVar` errors, it prints them and exits. The prompt logic would be inserted so that unresolved variables trigger prompts before erroring.

The existing effect pattern uses dynamic dispatch via `effectful`. For example, `Seihou.Effect.Filesystem` defines the effect and `Seihou.Effect.FilesystemInterp` provides the real IO interpreter, while `Seihou.Effect.FilesystemPure` provides a pure interpreter for testing using `Effectful.State.Static.Local`. This same pattern will be followed for the Console effect.

The `when` condition on prompts uses the expression language defined in `seihou-core/src/Seihou/Core/Expr.hs`. The `evalExpr` function takes a `Map VarName VarValue` and an `Expr` and returns `Bool`. A prompt should only be shown if its `promptWhen` is `Nothing` (always show) or `evalExpr` returns `True` for the currently-resolved variable bindings.

Fixture modules already declare prompts. For example, `seihou-core/test/fixtures/haskell-base/module.dhall` declares a prompt for `project.name` with text "What is the project name?".


## Plan of Work

The work is divided into four milestones.


### Milestone 1: Console effect interpreters

This milestone creates two interpreters for the existing `Console` effect: a real IO interpreter for production use and a pure scripted interpreter for testing.

The real interpreter goes in a new file `seihou-core/src/Seihou/Effect/ConsoleInterp.hs`. It implements each Console operation using standard IO: `PutText` writes to stdout via `Data.Text.IO.hPutStrLn stdout`, `PutError` writes to stderr, `GetLine` reads a line from stdin (with `hFlush stdout` before reading to ensure the prompt text appears), `Confirm` prints the prompt and reads a line checking for "y"/"yes", and `IsInteractive` calls `System.IO.hIsTerminalDevice stdin`. The interpreter function is `runConsole :: (IOE :> es) => Eff (Console : es) a -> Eff es a`.

The pure interpreter goes in a new file `seihou-core/src/Seihou/Effect/ConsolePure.hs`. It takes a list of scripted responses and tracks output. Its state is a record with a list of remaining input lines and a list of captured output lines. The interpreter function is `runConsolePure :: [Text] -> Eff (Console : es) a -> Eff es (a, ConsoleState)`. The `IsInteractive` operation always returns `True` in the pure interpreter (tests simulate an interactive session). `GetLine` pops the next scripted input; if the list is exhausted, it returns an empty string.

Both modules must be added to the `exposed-modules` in `seihou-core/seihou-core.cabal`.

At the end of this milestone, the Console effect can be used in effectful code and tested purely. Validation: a small test that runs `putText "hello" >> getLine` through the pure interpreter with `["world"]` as input and checks the output and return value.


### Milestone 2: Prompt execution logic

This milestone creates the core prompt execution function that takes a module's prompts, the currently-resolved variables, and the unresolved variable declarations, and interactively fills in values via the Console effect.

Create a new module `seihou-core/src/Seihou/Interaction/Prompt.hs` with the function:

    runPrompts ::
      (Console :> es) =>
      [Prompt] ->
      [VarDecl] ->
      Map VarName VarValue ->
      Eff es (Map VarName ResolvedVar)

The logic is: for each prompt in order, check if the variable it references is in the set of unresolved declarations (i.e., it has no value from CLI/env/default). If the variable is already resolved, skip. Then evaluate the `promptWhen` condition against the current resolved bindings — if it evaluates to `False`, skip. If the prompt has `promptChoices`, display a numbered menu and read the user's selection number. Otherwise, display the `promptText` and read a line. Coerce the input to the variable's declared type using the existing `coerceValue` function. If coercion fails, re-prompt (up to 3 attempts, then error). If coercion succeeds, validate with `validateVarValue`. Wrap the result as `ResolvedVar` with source `FromPrompt`.

Also create a helper function:

    promptForVar ::
      (Console :> es) =>
      Prompt ->
      VarDecl ->
      Map VarName VarValue ->
      Eff es (Either VarError ResolvedVar)

This handles a single prompt interaction: display text, read input, coerce, validate, retry on failure.

Add `Seihou.Interaction.Prompt` to `exposed-modules` in `seihou-core/seihou-core.cabal`.

The test for this milestone uses the pure Console interpreter to script user input and verify that prompts resolve variables correctly, including choice selection, type coercion, and conditional prompt skipping.


### Milestone 3: Wire prompts into the run command pipeline

This milestone modifies `seihou-core/src/Seihou/Composition/Resolve.hs` to add a new function `resolveComposedVariablesWithPrompts` that incorporates prompt interaction. The existing pure `resolveComposedVariables` stays untouched — the new function wraps it with an effectful prompt layer.

The approach: for each module in topological order, first call the pure `resolveVariables` with a modification — instead of failing on missing required variables, collect which variables are unresolved. Then run the module's prompts for those unresolved variables via `runPrompts`. Merge the prompt results back and continue to the next module.

Concretely, create a new function in `Seihou.Composition.Resolve`:

    resolveWithPrompts ::
      (Console :> es) =>
      [(Module, FilePath)] ->
      Map VarName Text ->
      Map Text Text ->
      Eff es (Either [VarError] (Map ModuleName (Map VarName ResolvedVar)))

This function follows the same pattern as `resolveComposedVariables` (iterate modules in order, collect exports, inject defaults) but after `resolveVariables` returns errors, it separates `MissingRequiredVar` errors from other errors. For the missing variables, it checks `isInteractive` — if not interactive, these remain as errors. If interactive, it runs prompts for the missing variables, then merges the prompt results into the resolved map. Other errors (coercion, validation) are still fatal.

In `seihou-cli/src/Seihou/CLI/Run.hs`, modify `handleRun` to use `resolveWithPrompts` instead of `resolveComposedVariables`. This requires adding the Console effect to the effectful pipeline:

    runEff $ runConsole $ runFilesystem $ runManifestStore manifestPath $ do ...

The current `handleRun` runs part of its logic in plain IO and part in the effectful pipeline. The prompt-aware resolution needs Console, so we restructure: move the resolution step inside the effectful block, or run the resolution in a separate effectful block with Console.

At the end of this milestone, `seihou run haskell-base` without `--var project.name=...` prompts in the terminal instead of erroring.


### Milestone 4: Integration tests and end-to-end validation

This milestone adds tests that verify the full prompt flow through composition.

Create `seihou-core/test/Seihou/Interaction/PromptSpec.hs` with tests for:

- A prompt that fills a required text variable reads input and produces `FromPrompt` source.
- A prompt with choices shows the menu and accepts a selection number.
- A prompt with a `when` condition that evaluates to `False` is skipped.
- A prompt for a boolean variable coerces "yes"/"no" input correctly.
- When all variables are provided via CLI, no prompts fire.
- When `isInteractive` returns `False`, prompts are skipped and missing variables produce errors.
- In a two-module composition, the first module's prompted value flows to the second module via exports.

Wire `PromptSpec` into `seihou-core/test/Main.hs` and `seihou-core/seihou-core.cabal`.

Run `nix fmt` to ensure formatting compliance. Run `cabal test all` and verify all existing tests still pass plus the new prompt tests.


## Concrete Steps

All commands are run from the repository root: `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`

After each milestone, rebuild and test:

    cabal build all
    cabal test all

After all milestones, format and check:

    nix fmt
    nix flake check

Test the interactive flow manually (Milestone 3):

    cabal run seihou -- run haskell-base

Expected: the CLI prompts "What is the project name?" and waits for input. After typing "my-app" and pressing Enter, generation proceeds.

Test non-interactive mode:

    echo "" | cabal run seihou -- run haskell-base

Expected: error message "missing required variable: project.name" because stdin is not a terminal.

Test that CLI overrides still bypass prompts:

    cabal run seihou -- run haskell-base --var project.name=my-app

Expected: no prompt, generation proceeds directly.


## Validation and Acceptance

After implementation, the following must hold:

1. `cabal test all` passes with all existing 263 tests plus new prompt tests.

2. Running `seihou run haskell-base` in a terminal (no `--var` flags) displays "What is the project name?" and accepts input. After entering a value, generation proceeds and `seihou status` shows the entered value.

3. Running `seihou run haskell-base --var project.name=my-app` does not prompt — CLI overrides bypass prompts entirely.

4. Running `echo "" | seihou run haskell-base` (piped input) produces an error for the missing required variable rather than prompting.

5. Running `seihou vars haskell-base --explain --var project.name=my-app` still works and shows "from --set flag" as the source. If prompts were used, the source would show "from interactive prompt."

6. `nix fmt` produces no changes.


## Idempotence and Recovery

All changes are additive: new modules (`ConsoleInterp`, `ConsolePure`, `Interaction.Prompt`), new tests, and modifications to `Resolve.hs` and `Run.hs`. The existing `resolveComposedVariables` function is not modified — the new `resolveWithPrompts` is added alongside it. Existing tests continue to use the pure function. Any edit can be reverted with `git checkout -- <file>`.


## Interfaces and Dependencies

No new external dependencies. All functionality uses the standard library (`System.IO` for TTY detection and flushing) and `effectful-core` (already a dependency).

New modules and their key exports:

In `seihou-core/src/Seihou/Effect/ConsoleInterp.hs`:

    runConsole :: (IOE :> es) => Eff (Console : es) a -> Eff es a

In `seihou-core/src/Seihou/Effect/ConsolePure.hs`:

    data ConsoleState = ConsoleState
      { consoleInputs :: [Text],
        consoleOutputs :: [Text],
        consoleErrors :: [Text]
      }

    runConsolePure :: [Text] -> Eff (Console : es) a -> Eff es (a, ConsoleState)

In `seihou-core/src/Seihou/Interaction/Prompt.hs`:

    runPrompts ::
      (Console :> es) =>
      [Prompt] ->
      [VarDecl] ->
      Map VarName VarValue ->
      Eff es (Map VarName ResolvedVar)

    promptForVar ::
      (Console :> es) =>
      Prompt ->
      VarDecl ->
      Map VarName VarValue ->
      Eff es (Either VarError ResolvedVar)

In `seihou-core/src/Seihou/Composition/Resolve.hs` (added export):

    resolveWithPrompts ::
      (Console :> es) =>
      [(Module, FilePath)] ->
      Map VarName Text ->
      Map Text Text ->
      Eff es (Either [VarError] (Map ModuleName (Map VarName ResolvedVar)))
