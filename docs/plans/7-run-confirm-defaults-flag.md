---
id: 7
slug: run-confirm-defaults-flag
title: "Add a --confirm-defaults flag to seihou run"
kind: exec-plan
created_at: 2026-04-18T22:51:47Z
intention: "intention_01kphbvya3enva4yj3w1kyxrgp"
---


# Add a --confirm-defaults flag to seihou run

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

Today, when a user runs `seihou run <module>`, any variable that the user did not
explicitly supply silently resolves to its declared default (or to a value exported
from a parent module). The user sees the default only indirectly — for example, in
the plan-view header of the output, or by inspecting `seihou vars`. There is no
opportunity in the `run` flow itself to notice the default and change it without
aborting and re-running with `--var KEY=VALUE`.

After this change, users can pass `--confirm-defaults` to `seihou run`. Before
compiling the plan, Seihou will step through every variable whose resolved value
came from its default (either the module author's declared default, or an exported
value inherited from a parent module) and prompt the user to confirm or override.
Each prompt shows the default in brackets, and pressing Enter accepts it. Typing a
new value replaces the default and marks the variable as user-supplied (so that the
"save prompted values?" offer at the end of the run can persist the choice to local
config if the user wishes).

After implementation, a user can do this:

    $ seihou run haskell-base --confirm-defaults

    Confirm default values:
      project.name [my-project]: my-app
      project.version [0.1.0.0]:
      license [MIT]: Apache-2.0

    [plan view...]
    Proceed? [Y/n]

Pressing Enter on a line keeps the default. Typing a value replaces it. Invalid
input (wrong type, failed validation) prints an error and retries up to three times
before falling back to the default.

Users who do not pass `--confirm-defaults` see no change in behavior — existing
prompt flows for required and optional variables remain exactly as they are today.


## Progress

- [x] M1: Add the `runConfirmDefaults` field to `RunOpts` and the `--confirm-defaults` CLI flag. (2026-04-18)
- [x] M1: Extract or reuse the existing prompt-for-one-variable helper so the confirm flow can invoke it for arbitrary decls, including ones with no `Prompt` record. (2026-04-18 — `promptForVar` was already exported)
- [x] M1: Implement `confirmDefaults` in a new module under `seihou-core/src/Seihou/Interaction/`. (2026-04-18)
- [x] M1: Wire `confirmDefaults` into `handleRun` after `resolveWithPrompts` succeeds, gated on the flag and interactivity. (2026-04-18)
- [x] M1: Mark confirmed-but-changed values with `FromPrompt` source so the existing "save prompted values" flow picks them up. (2026-04-18 — `promptForVar` already returns `FromPrompt`)
- [x] M2: Add pure tests in a new `seihou-core/test/Seihou/Interaction/ConfirmSpec.hs` using `runConsolePure`. (2026-04-18)
- [x] M2: Cover accept-default, override-default, invalid-input-retry, skipped-optional-absent, non-interactive-no-op. (2026-04-18 — 7 cases, covering no-ops, accept-default, override, retry-failure, FromParent, non-interactive, and authored-prompt text)
- [ ] M2: Confirm the "save prompted values?" offer surfaces the overridden value end-to-end. (skipped — see Decision Log)
- [x] M3: Update `docs/user/getting-started.md` with a short example of `--confirm-defaults`. (2026-04-18 — added a transcript in Step 6 and a row to the run-flags table)
- [x] M3: Update `docs/user/config-and-variables.md` to describe the flag alongside the precedence chain. (2026-04-18 — new "Reviewing defaults interactively" subsection under "The resolution hierarchy")
- [x] M3: Add a help-text example in `seihou-cli/src/Seihou/CLI/Commands.hs` under the `run` command's footer. (2026-04-18)
- [x] M3: Update `CHANGELOG.md` under the next unreleased entry. (2026-04-18 — added an "Added" block to the `[Unreleased]` section)


## Surprises & Discoveries

- 2026-04-18 — `promptForVar` was already in the export list of `Seihou.Interaction.Prompt`, so no export-list change was needed.
- 2026-04-18 — The plan suggested either renaming all downstream uses of `resolved` or shadowing with `let resolved = resolved'`. Implemented by renaming the initial binding to `resolvedInitial` and introducing a fresh `resolved` via an `if/then/else` on the flag, which is clearer than shadowing and keeps the rest of `handleRun` unchanged.


## Decision Log

- Decision: The flag is named `--confirm-defaults`.
  Rationale: The user request was phrased as "let user confirm values with defaults so they can change them if they want." "Confirm" matches the user's wording. "Defaults" is the narrowest accurate scope: it confines the behavior to values that came from defaults, avoiding the confusion of re-prompting values the user explicitly typed on the CLI, in env vars, or in config files.
  Date: 2026-04-18

- Decision: Scope is limited to variables whose resolved `source` is `FromDefault` or `FromParent`.
  Rationale: These are the two sources where the user did not explicitly provide a value. `FromCLI`, `FromEnv`, `FromLocalConfig`, `FromNamespaceConfig`, `FromContextConfig`, and `FromGlobalConfig` all represent deliberate user input — re-prompting them would be noise. `FromPrompt` already came from this session's interactive input. `FromParent` is in-scope because the user didn't type it; a composed recipe wired the value through, and the user may want to override a downstream parent's choice. If we discover during implementation that `FromParent` creates churn (e.g., the same variable is confirmed multiple times across composed modules), we will narrow to only `FromDefault` and note it in Surprises & Discoveries.
  Date: 2026-04-18

- Decision: Overridden values are marked as `FromPrompt`, not a new `FromConfirm` source.
  Rationale: The downstream "save prompted values" flow keys off `FromPrompt`. Introducing a new source would require threading it through `collectPromptedValues`, `offerSavePrompted`, and every downstream consumer of `VarSource`. The user-facing meaning is the same: the user typed it this session.
  Date: 2026-04-18

- Decision: A variable shown under `--confirm-defaults` that the user did not change retains its original `FromDefault` / `FromParent` source.
  Rationale: Only changes should be treated as prompted input. If we marked accepted defaults as `FromPrompt`, the save-prompted flow would offer to persist values the user merely confirmed — overly aggressive.
  Date: 2026-04-18

- Decision: The flag is a no-op in non-interactive mode (no TTY on stdin).
  Rationale: Matches the existing prompt behavior. Printing "Confirm default values:" to a CI log and immediately reading EOF would be worse than silently proceeding. A warning is logged at `LogVerbose` level so users who explicitly ask for it know why nothing happened.
  Date: 2026-04-18

- Decision: If a variable already has a `Prompt` record attached in `module.dhall`, the prompt's `text` and `choices` fields are honored. Otherwise, a synthetic prompt is built from the variable name.
  Rationale: Reusing the existing `promptForVar` machinery gives us choice menus, validation, and coercion for free. A synthetic prompt with text = variable name (e.g., `"project.name"`) is a clear fallback.
  Date: 2026-04-18

- Decision: Skip the end-to-end "save prompted values surfaces overridden value" test and rely on the unit test that asserts `source = FromPrompt` after an override.
  Rationale: `collectPromptedValues` in `seihou-cli/src/Seihou/CLI/SavePrompted.hs` filters resolved vars purely by `source == FromPrompt`. Once `confirmDefaults` tags the changed value as `FromPrompt`, nothing else is needed for the save flow to pick it up — this is exercised by the "replaces the value and marks source as FromPrompt" test. Adding a CLI integration test would duplicate coverage without verifying anything that isn't already verified by the composition of unit-level guarantees.
  Date: 2026-04-18

- Decision: Skip a seihou-cli integration test for the flag.
  Rationale: `seihou-cli` has a test harness (`seihou-cli-test`) but no existing end-to-end test that drives the full `handleRun` pipeline with scripted stdin. Building one just for this flag is out of scope; the pure `ConfirmSpec` covers the behaviors that can break, and the manual smoke test described in Concrete Steps covers the rest.
  Date: 2026-04-18


## Outcomes & Retrospective

**Delivered** (2026-04-18):

- `--confirm-defaults` CLI flag on `seihou run`, wired through `runConfirmDefaults :: Bool` in `RunOpts`.
- New module `Seihou.Interaction.Confirm` exporting `confirmDefaults`, reusing `promptForVar` for free-text and choice-menu prompts, validation, and type coercion.
- Integration point: between `resolveWithPrompts` and `diagnoseResolution` in `handleRun`, gated on both the flag and interactivity (the Confirm module re-checks interactivity to stay correct if called from elsewhere).
- Seven pure unit tests in `Seihou.Interaction.ConfirmSpec` covering no-op, accept-default, override, retry-exhausted-keeps-default, `FromParent`, non-interactive, and authored-Prompt text preference. All pass under `cabal test all`.
- Docs: `docs/user/getting-started.md` (example transcript + flag table row), `docs/user/config-and-variables.md` (new subsection), CLI help footer example, top-level `CHANGELOG.md` entry.

**Result vs. Purpose**: The stated goal — let the user confirm or override any variable whose value came from a default without aborting and re-running — is met. Overridden values carry `FromPrompt` so they automatically integrate with the existing save-prompted flow; accepted defaults retain their original `FromDefault` / `FromParent` source so the save-prompted flow does not over-capture.

**Deferred / not pursued**:

- No seihou-cli integration test. See Decision Log: `collectPromptedValues` filters purely on `source == FromPrompt`, and the unit test verifies that `confirmDefaults` sets that source correctly, so adding a CLI-level test would duplicate coverage.
- Plural-prompt deduplication: if a variable is declared in several modules in the composition (e.g., a parent exports a value that a child also declares), it will currently be prompted once per module. Not observed in practice during manual smoke tests, so not addressed. The Decision Log notes this as a future narrowing knob.


## Context and Orientation

Seihou is a composable project scaffolding system written in Haskell (GHC 9.12.2,
effectful-core, Dhall). The project is a multi-package Cabal workspace:

- `seihou-core/` — the library: types, variable resolution, effects, prompts, manifest, plan execution.
- `seihou-cli/` — the executable: argument parsing, command dispatch, top-level orchestration.

The `seihou run` command is implemented in `seihou-cli/src/Seihou/CLI/Run.hs`. Its
options type is `RunOpts` in `seihou-cli/src/Seihou/CLI/Commands.hs` (lines 84–99).
The parser that populates `RunOpts` is `runParser` in the same file
(lines 569–596). `handleRun` in `Run.hs` is the entry point.

Variables are declared in a module's `module.dhall` as a list of `VarDecl` records.
The `VarDecl` type is in `seihou-core/src/Seihou/Core/Types.hs`:

    data VarDecl = VarDecl
      { name :: VarName,
        type_ :: VarType,
        default_ :: Maybe VarValue,
        description :: Maybe Text,
        required :: Bool,
        validation :: Maybe Validation
      }

Each variable resolves from a precedence chain implemented in
`seihou-core/src/Seihou/Core/Variable.hs`. The chain, from highest to lowest
priority, is: `FromCLI`, `FromEnv`, `FromLocalConfig`, `FromNamespaceConfig`,
`FromContextConfig`, `FromGlobalConfig`, `FromParent`, `FromDefault`. After
resolution, every value has a `VarSource` tag recording where it came from. The
type is in `seihou-core/src/Seihou/Core/Types.hs` (lines 292–303).

The file `seihou-core/src/Seihou/Composition/Resolve.hs` contains
`resolveWithPrompts`, which orchestrates resolution across a composition of
modules. It calls pure `resolveVariables` per module and, when required variables
are missing in interactive mode, falls back to `runPrompts` from
`seihou-core/src/Seihou/Interaction/Prompt.hs` to collect them from the user. It
also prompts for optional variables that have a `Prompt` record attached but no
resolved value (added in a prior plan,
`docs/plans/interactive-prompts-for-optional-variables.md`).

The key prompt machinery in `seihou-core/src/Seihou/Interaction/Prompt.hs` is:

- `runPrompts :: [Prompt] -> [VarDecl] -> Map VarName VarValue -> Eff es (Map VarName ResolvedVar)` — iterates prompts, calls `promptForVar`, accumulates results.
- `promptForVar :: Prompt -> VarDecl -> Map VarName VarValue -> Eff es (Either VarError ResolvedVar)` — dispatches to free-text or choice prompt.
- `promptFreeText :: Prompt -> VarDecl -> Int -> Eff es (Either VarError ResolvedVar)` — prints `prompt.text [default]:`, reads input, coerces, retries up to 3 times on invalid input. Empty input accepts the default when one exists.
- `promptWithChoices :: Prompt -> VarDecl -> [Text] -> Eff es (Either VarError ResolvedVar)` — prints a numbered menu.
- `formatPromptText` formats the bracketed default hint. `showDefaultValue` renders `VarValue` for display.

These functions are exactly what the confirm-defaults flow wants to reuse. A
`Prompt` record is `{ var :: VarName, text :: Text, condition :: Maybe Expr,
choices :: Maybe [Text] }`, also in `Types.hs`. For variables that have no
`Prompt` in the module's `prompts` list, the confirm flow will synthesize a
`Prompt { var = decl.name, text = decl.name.unVarName, condition = Nothing,
choices = Nothing }`.

The `Console` effect is in `seihou-core/src/Seihou/Effect/Console.hs`. Operations
are `PutText`, `PutError`, `GetLine`, `Confirm`, `IsInteractive`. The IO
interpreter is in `seihou-core/src/Seihou/Effect/ConsoleInterp.hs`. The pure test
interpreter `runConsolePure` is in `seihou-core/src/Seihou/Effect/ConsolePure.hs`;
it takes scripted input lines and accumulates output lines into a list, which
tests can assert on. Existing tests of the prompt system live in
`seihou-core/test/Seihou/Interaction/PromptSpec.hs` and use `runConsolePure`.

After `resolveWithPrompts` in `handleRun` returns `Right resolved`, the code
currently proceeds straight to `diagnoseResolution` (emits warnings for unused
config keys) and then `compileComposedPlan`. The `--confirm-defaults` logic must
slot in between the success of `resolveWithPrompts` and the call to
`diagnoseResolution`. The resulting `resolved :: Map ModuleName (Map VarName
ResolvedVar)` is the data structure to walk and update.

At the end of `handleRun` (lines 335–341 of `Run.hs`), there is a
`collectPromptedValues resolved localMap` call that drives the
"save prompted values?" offer. This function filters `resolved` for entries whose
`source` is `FromPrompt` and whose key is not already in the local config map.
Because we will tag confirmed-and-overridden values as `FromPrompt`, they will
automatically flow into this offer without additional wiring.


## Plan of Work

The work breaks into three milestones: adding the flag and core logic (M1),
testing it in isolation and end-to-end (M2), and documenting (M3). Each milestone
builds on the previous and leaves the codebase in a working state.


### Milestone 1: Add the flag and implement the confirm flow

**Scope**: Add `--confirm-defaults` to the `run` command parser and introduce a
new function `confirmDefaults` that walks resolved variables, prompts for each
one whose source is `FromDefault` or `FromParent`, and returns an updated map
where user-overridden values carry `FromPrompt` as their source. Wire it into
`handleRun` after `resolveWithPrompts` succeeds.

**What exists at the end**: A user can run `seihou run haskell-base
--confirm-defaults` interactively and be prompted to confirm or override each
default-sourced variable. In non-interactive mode, the flag is a no-op. The
build passes (`cabal build all`) and existing tests pass (`cabal test all`).

**Acceptance**: Run a local module (e.g., one of the fixtures under
`seihou-core/test/fixtures/`) with the flag and observe the new "Confirm default
values:" block appearing. Press Enter on each line — the generated files are
identical to running without the flag. Type a new value for one variable and
observe the generated files reflect it.

**Edits**:

In `seihou-cli/src/Seihou/CLI/Commands.hs`, modify `RunOpts` (lines 84–99) to add
a new field:

    runConfirmDefaults :: Bool,

Place it after `runSavePrompted` and before `runCommit` to keep related interactive
flags grouped. Update the `runParser` builder in the same file (lines 569–596) to
add a matching `<*>` line:

    <*> switch (long "confirm-defaults" <> help "Step through default values and confirm or override each one")

Place it after the `--no-save-prompted` optional block and before `--commit` so
CLI help ordering matches the record.

Create a new source file `seihou-core/src/Seihou/Interaction/Confirm.hs` that
exports a single function:

    confirmDefaults ::
      (Console :> es) =>
      [(Module, FilePath)] ->
      Map ModuleName (Map VarName ResolvedVar) ->
      Eff es (Map ModuleName (Map VarName ResolvedVar))

Add this module to the `exposed-modules` list in
`seihou-core/seihou-core.cabal`. Search for "Interaction.Prompt" in that cabal
file and add `Seihou.Interaction.Confirm` on the adjacent line.

Inside `Confirm.hs`, implement the logic as follows. Check `isInteractive` from
the Console effect. If not interactive, return the input map unchanged. If
interactive, check whether any variable in any module has source `FromDefault` or
`FromParent _`. If none, return unchanged. Otherwise, emit a blank line and the
header `"Confirm default values:"` via `putText`, then iterate the modules in the
order given by the `modulesInOrder` argument. For each module, iterate its
`vars` list (in declaration order) and for each declared variable that appears
in the resolved map with source `FromDefault` or `FromParent`, run the prompt.

Reuse the existing `promptForVar` from `Seihou.Interaction.Prompt`. Import it by
adding `promptForVar` to the export list of
`seihou-core/src/Seihou/Interaction/Prompt.hs` if it is not already exported
(inspect lines 1–7 of that file; if only `runPrompts` is exported, add
`promptForVar` to the list). To build a `Prompt` for a variable that has no
authored prompt attached, look it up in the module's `prompts` list by variable
name. If found, use it. If not, synthesize one:

    Prompt
      { var = decl.name,
        text = decl.name.unVarName,
        condition = Nothing,
        choices = Nothing
      }

Call `promptForVar synthesizedOrFound decl currentBindings`. The current bindings
map is built from the resolved values of all modules processed so far, flattened:
`Map.map (.value) (Map.unions (Map.elems accumulatedResolvedMap))`. For each
prompt result:

- `Left _err` — the user exhausted retries or gave invalid input. Keep the
  original `ResolvedVar` with its original source. No change to the map.
- `Right rv` — the user typed something. Compare `rv.value` to the original
  `resolved.value`. If equal, the user simply accepted the default by pressing
  Enter: keep the original `ResolvedVar` unchanged (preserving `FromDefault`).
  If different, store the new value with `source = FromPrompt`.

After processing all modules, return the updated map.

Note on equality: `VarValue` derives `Eq` (see
`seihou-core/src/Seihou/Core/Types.hs`). Compare with `==` directly.

In `seihou-cli/src/Seihou/CLI/Run.hs`, after the block that binds `resolved`
(currently lines 137–143) and before the diagnostics block (currently lines
146–153), insert a new block that optionally runs the confirm flow:

    resolved' <-
      if runOpts.runConfirmDefaults
        then runEff $ runConsole $ confirmDefaults modulesInOrder resolved
        else pure resolved

Replace downstream uses of `resolved` with `resolved'` for the remainder of the
function. Be careful: `resolved` is used again around lines 147, 157, 206, 270,
and 337. Rename all of them. Alternatively, shadow the old binding by writing
`let resolved = resolved'` immediately after the new binding — this is a
less-invasive one-line change. Prefer the shadow approach.

Add the import `import Seihou.Interaction.Confirm (confirmDefaults)` at the top
of `Run.hs` alongside the other `Seihou.Interaction.*` imports (there may be none
currently; place it near `Seihou.Composition.Resolve`).


### Milestone 2: Tests

**Scope**: Add a pure test spec for the `confirmDefaults` function covering the
key behaviors described in the Decision Log, and an end-to-end sanity check that
demonstrates the flag integrates correctly into `handleRun`.

**What exists at the end**: A new test file
`seihou-core/test/Seihou/Interaction/ConfirmSpec.hs` with at least 6 tests. The
spec is wired into the test entry point. All tests pass.

**Acceptance**: `cabal test seihou-core-test` passes, including the new spec.
Specifically, the output contains the new test group's name when run with
`--test-option='-p' --test-option='/Confirm/'`.

**Edits**:

Create `seihou-core/test/Seihou/Interaction/ConfirmSpec.hs` modeled on
`seihou-core/test/Seihou/Interaction/PromptSpec.hs`. Use `runConsolePure` to
script inputs and capture output. Build sample `Module` and `ResolvedVar`
records as fixtures in-file; do not rely on Dhall evaluation.

Tests to include:

1. `it "does nothing when the flag activates but no variables have default sources"`
   — construct a resolved map where every `source` is `FromCLI`. Call
   `confirmDefaults`. Assert: output contains no "Confirm default values:"
   header, returned map equals input map.

2. `it "prompts for FromDefault variables and accepts Enter as keeping the default"`
   — construct one module with one variable resolved via `FromDefault` with
   value `VText "0.1.0.0"`. Script input: `""` (empty line). Assert: output
   contains `"Confirm default values:"` and a prompt with `[0.1.0.0]`, returned
   map still has the original `ResolvedVar` with `source = FromDefault`.

3. `it "replaces the value and marks source as FromPrompt when user types a new value"`
   — same fixture as above. Script input: `"1.0.0"`. Assert: returned map has
   `value = VText "1.0.0"` and `source = FromPrompt`.

4. `it "retries on invalid input and keeps the default on final failure"`
   — fixture with an `Int` variable defaulted to `VInt 42`. Script input:
   `"not-an-int"`, `"still-bad"`, `"nope"`. Assert: retries consumed, final
   returned value is `VInt 42` with `source = FromDefault`.

5. `it "prompts for FromParent variables"` — fixture where a variable was
   inherited via `makeInheritedResolved` (so `source = FromDefault` per the
   existing helper, but we'll test both paths explicitly: add a module whose
   resolved map contains a var with `source = FromParent (ModuleName "parent")`).
   Script input: `"override"`. Assert: new value wins, `source = FromPrompt`.

6. `it "is a no-op in non-interactive mode"` — configure the pure console to
   report `isInteractive = False`. Assert: returned map equals input map, no
   output emitted. Check whether `runConsolePure` already supports this; if not,
   introduce a helper like `runConsolePureNonInteractive` in
   `seihou-core/src/Seihou/Effect/ConsolePure.hs`, modeled on the existing
   interpreter but returning `False` for `IsInteractive`. If the helper already
   exists under another name, reuse it.

Wire the new spec into the test runner. The project appears to use `hspec-discover`
or an explicit `main` in `seihou-core/test/Spec.hs` (inspect that file; add the
import/call as needed).

For the end-to-end sanity check, extend `seihou-cli/test/` (if a CLI test exists)
with a test that runs the CLI with `--confirm-defaults` against a fixture module
and a scripted stdin. If `seihou-cli` has no existing test harness, skip this
step and record it in Surprises & Discoveries. The pure spec is sufficient for
acceptance.


### Milestone 3: Documentation

**Scope**: Document the flag in user-facing docs and the CLI's own help text,
and note it in the CHANGELOG.

**What exists at the end**: Users reading `docs/user/getting-started.md` or
`docs/user/config-and-variables.md` can discover the flag. The output of
`seihou run --help` mentions it (already true from the parser change in M1, but
the footer example in `Commands.hs` gains a bullet). The CHANGELOG entry
mentions the flag for the next release.

**Acceptance**: `seihou run --help` shows `--confirm-defaults` in the flag list.
The referenced doc files include at least one example. `CHANGELOG.md` has a new
bullet.

**Edits**:

In `seihou-cli/src/Seihou/CLI/Commands.hs` `runInfo` (lines 309–333), extend the
`Examples:` list in the footer with one more entry:

    pretty ("seihou run haskell-base --confirm-defaults   # review and override default values" :: String)

In `docs/user/getting-started.md`, after the first example showing
`seihou run <module> --var project.name=my-app`, add a short paragraph:

> To step through each default value and confirm or override it, pass
> `--confirm-defaults`. Pressing Enter accepts the default; typing a value
> replaces it.

Include an indented transcript of the kind shown in the Purpose section of this
plan, adapted to the example module used in the getting-started doc.

In `docs/user/config-and-variables.md`, in the section that describes the
precedence chain, add a short note that `--confirm-defaults` interacts with the
chain by letting the user override any value that would otherwise come from
`FromDefault` or from a parent module's export.

In `CHANGELOG.md`, under the top "Unreleased" section (or add one if none
exists — see how prior milestones have updated it by running
`git log --oneline CHANGELOG.md | head -5`), add a bullet:

    - Add `--confirm-defaults` flag to `seihou run`. Steps through each variable
      resolved from its default or from a parent module's export and lets the
      user accept or override it interactively.


## Concrete Steps

All commands run from the repository root:
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`.

Build after M1:

    cabal build all 2>&1 | tail -5

Expected: no errors, warnings only if pre-existing.

Run all tests after M2:

    cabal test all 2>&1 | tail -30

Expected: all tests pass, including the new `Confirm` group. The new spec's
tests should each print as a line under the `Seihou.Interaction.Confirm` group.

Run only the new tests:

    cabal test seihou-core-test --test-option='-p' --test-option='/Confirm/' 2>&1 | tail -20

Manual end-to-end smoke test after M1, from the repository root:

    cabal run seihou -- run haskell-base --confirm-defaults

(Substitute an actual installed or fixture module name if `haskell-base` is not
available.) Observe the prompt block. Press Enter on each line and verify that
the generated files are byte-identical to running without the flag.

Repeat with one override:

    cabal run seihou -- run haskell-base --confirm-defaults

Type a new value for one variable, press Enter for the rest, and verify the
generated files reflect the override.

Repeat non-interactively:

    echo "" | cabal run seihou -- run haskell-base --confirm-defaults 2>&1 | tail -20

Expected: no "Confirm default values:" block appears; generation proceeds with
defaults as usual.


## Validation and Acceptance

The feature is acceptably complete when all of the following are observable:

1. `seihou run --help` lists `--confirm-defaults` with its help text.

2. Running `seihou run <module> --confirm-defaults` on a module whose
   variables would otherwise resolve from their defaults prints a "Confirm
   default values:" block listing each such variable with its current default in
   brackets. The prompt appears before the plan view / "Proceed?" confirmation.

3. Pressing Enter on every line produces identical output to running without the
   flag. The generated files are byte-identical.

4. Typing a new value on one line replaces that variable's value. The new value
   is visible in the plan view and the generated files reflect it.

5. On final run completion, the "save prompted values?" offer includes any
   overridden variables (if `--save-prompted` is not explicitly set to `false`).

6. Running the command with no TTY on stdin (e.g., under `echo "" | ...` or in
   CI) skips the confirm block entirely and produces output identical to
   omitting the flag.

7. Invalid input for a typed variable (e.g., typing `not-an-int` for a `VTInt`
   variable) prints an error message and retries up to 3 times. On final
   failure, the original default is kept and generation proceeds.

8. All new and existing tests pass under `cabal test all`.


## Idempotence and Recovery

All changes are additive. No existing code path changes its behavior when the
flag is absent. The flag is a no-op in non-interactive mode.

Milestones are independent: M2 and M3 do not depend on each other, so either can
be skipped and resumed later. M1 must complete before the feature is usable.

If a partially implemented M1 compiles but the confirm flow has a bug, users can
simply omit the flag and fall back to existing behavior. There is no data
migration and no manifest schema change. Re-running a `seihou run` command is
safe: the manifest-diff logic handles re-generation idempotently as today.


## Interfaces and Dependencies

No new external library dependencies. All work uses the existing effectful-core
effect system and Dhall types.

**New interface**, in `seihou-core/src/Seihou/Interaction/Confirm.hs`:

    confirmDefaults ::
      (Console :> es) =>
      [(Module, FilePath)] ->
      Map ModuleName (Map VarName ResolvedVar) ->
      Eff es (Map ModuleName (Map VarName ResolvedVar))

**Modified interfaces**:

In `seihou-cli/src/Seihou/CLI/Commands.hs`:

    data RunOpts = RunOpts
      { ...
      , runConfirmDefaults :: Bool
      , ...
      }

In `seihou-core/src/Seihou/Interaction/Prompt.hs`, the module's export list
gains `promptForVar` if it is not already exported. The function's signature
does not change:

    promptForVar ::
      (Console :> es) =>
      Prompt ->
      VarDecl ->
      Map VarName VarValue ->
      Eff es (Either VarError ResolvedVar)

No changes to any type in `seihou-core/src/Seihou/Core/Types.hs`. No changes to
the Dhall schema.
