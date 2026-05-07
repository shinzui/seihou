---
slug: persist-prompted-values-to-local-config
title: "Persist Prompted Variable Values to Local Config"
kind: exec-plan
created_at: 2026-03-26T13:32:37Z
---


# Persist Prompted Variable Values to Local Config

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

When a user runs `seihou run <module>` and answers interactive prompts for required or optional variables, those answers are lost after the run completes. If the user later re-runs the same module (e.g., after upgrading it) or runs a different module that declares the same variables, seihou asks the same questions again. This is inconvenient and surprising.

After this change, seihou will offer to save prompted values to the project's local config file (`.seihou/config.dhall`) at the end of a run. The user will see exactly which values will be saved and can accept, reject, or selectively edit the list. On subsequent runs, those saved values will be picked up automatically by the existing config resolution chain (local config sits at priority 3, above namespace/context/global config and defaults). The user remains in full control: `seihou config list` shows what's stored, `seihou config unset <key>` removes any value, and `seihou vars --explain` shows `[local config]` as the source — making it transparent that a prior prompt answer is being reused.

The key safety properties are:

1. Opt-in with clear disclosure: the user is shown the exact key-value pairs and must confirm before anything is written.
2. Non-destructive: values already in local config (set manually or by a previous save) are never overwritten without the user seeing them in the confirmation list.
3. Fully reversible: `seihou config unset <key>` removes any saved value.
4. Transparent reuse: `seihou vars --explain` and `seihou config list` make it visible that a value came from local config rather than a fresh prompt.


## Progress

- [x] M1: Add `--save-prompted` / `--no-save-prompted` CLI flags to `seihou run` (2026-03-26)
- [x] M1: Collect prompted variables from resolution result (filter by `FromPrompt` source) (2026-03-26)
- [x] M1: Display prompted values and prompt for save confirmation (2026-03-26)
- [x] M1: Write confirmed values to `.seihou/config.dhall` via ConfigWriter effect (2026-03-26)
- [x] M1: Add unit tests for prompted-value collection logic (2026-03-26)
- [x] M2: Add integration tests for offerSavePrompted using pure interpreters (2026-03-26)
  - Saves when user confirms, declines when user says no
  - Auto-saves with --save-prompted, skips with --no-save-prompted
  - Skips in non-interactive mode
  - Shows overwrite note for existing values
  - Does nothing when entries list is empty
  - Displays confirmation message after saving
- [x] M3: Update user documentation (`docs/user/config-and-variables.md`) (2026-03-26)
- [x] M3: Update CHANGELOG (2026-03-26)


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Save to local config (`.seihou/config.dhall`), not a separate file or the manifest.
  Rationale: Local config already participates in the resolution precedence chain at priority 3 (above namespace, context, global, parent, and defaults). The user can already inspect it with `seihou config list` and modify it with `seihou config set/unset`. No new concepts or files are needed. The manifest stores variable values for provenance tracking but is not a resolution source — making it one would add complexity and confuse the mental model.
  Date: 2026-03-26

- Decision: Offer save interactively after successful execution, not automatically.
  Rationale: The user asked "is there a way to do it in a safe way so the user knows that those values are being used across modules." An automatic save would be convenient but opaque. An explicit opt-in confirmation after each run ensures the user always knows what was saved and can decline. This matches the project's philosophy of transparency (provenance tracking, `--explain`, explicit layering).
  Date: 2026-03-26

- Decision: Default behavior is to ask (offer the save prompt). `--save-prompted` auto-saves without asking. `--no-save-prompted` suppresses the offer entirely.
  Rationale: Three modes cover the common workflows: interactive users who want control (default), CI/automation scripts that want to capture prompted values (`--save-prompted`), and users who never want the save offer (`--no-save-prompted`). The default is the safest option.
  Date: 2026-03-26

- Decision: Only save values whose source is `FromPrompt`. Do not save values from CLI, env, config, defaults, or parent bindings.
  Rationale: The point is to persist answers the user typed in interactively. Values from other sources are already persistent or intentionally ephemeral (env vars, CLI flags). Saving them would duplicate data and potentially conflict with the user's intent.
  Date: 2026-03-26

- Decision: Skip values that already exist in local config with the same value.
  Rationale: Avoids redundant writes and confusing "already saved" noise. If a value in local config differs from what was prompted, include it in the confirmation list with a note showing the existing value, so the user can choose whether to overwrite.
  Date: 2026-03-26


## Outcomes & Retrospective

All three milestones completed on 2026-03-26.

The implementation leveraged existing infrastructure (ConfigWriter effect, Console effect, local config precedence chain) without adding new concepts or persistence mechanisms. The pure `collectPromptedValues` function was extracted into its own module (`SavePrompted.hs`) for testability, and `offerSavePrompted` was co-located there to enable integration testing with pure interpreters.

Key metrics: 728 tests pass (650 core + 78 CLI). The 15 new tests cover both the pure collection logic (7 tests) and the effectful save interaction (8 tests).

Design decisions held up well — using the existing local config as the persistence target meant zero new file formats and immediate integration with `seihou config list/unset` and `seihou vars --explain`.


## Context and Orientation

Seihou is a composable, type-safe project scaffolding system. When a user runs `seihou run <module>`, the system loads the module (and its dependencies), resolves all declared variables through a multi-layer precedence chain, generates files from templates, and writes them to disk. The resolution precedence chain, from highest to lowest priority, is:

1. CLI flags (`--var key=value`)
2. Environment variables (`SEIHOU_VAR_*`)
3. Local project config (`.seihou/config.dhall`)
4. Namespace config (`~/.config/seihou/namespaces/<ns>/config.dhall`)
5. Context config (`~/.config/seihou/contexts/<ctx>/config.dhall`)
6. Global config (`~/.config/seihou/config.dhall`)
7. Parent-supplied vars (from parameterized dependencies)
8. Module defaults
9. Interactive prompts (user input via TTY)

Interactive prompts are the lowest priority. If a variable is answered at any higher layer, the prompt is skipped. This means that once a prompted value is saved to local config (layer 3), it will be used on all subsequent runs without re-prompting — exactly the behavior we want.

The key files involved are:

- `seihou-cli/src/Seihou/CLI/Run.hs` — The `handleRun` function orchestrates the full run pipeline. After resolution and execution, it writes the manifest. This is where we will add the save-prompted logic, after execution succeeds but before the function returns.
- `seihou-cli/src/Seihou/CLI/Commands.hs` — Defines `RunOpts`, the options record for the `run` command. We will add `runSavePrompted :: Maybe Bool` here (`Nothing` = ask, `Just True` = auto-save, `Just False` = suppress).
- `seihou-core/src/Seihou/Composition/Resolve.hs` — The `resolveWithPrompts` function returns `Map ModuleName (Map VarName ResolvedVar)`. Each `ResolvedVar` carries a `VarSource` field; values the user typed have `source = FromPrompt`.
- `seihou-core/src/Seihou/Core/Types.hs` — Defines `VarSource` (including `FromPrompt`), `ResolvedVar`, `ConfigScope` (including `ScopeLocal`).
- `seihou-core/src/Seihou/Interaction/Prompt.hs` — The prompt interaction module. We will not modify this; it already tags prompted values with `FromPrompt`.
- `seihou-core/src/Seihou/Effect/ConfigWriter.hs` — The `ConfigWriter` effect with `writeConfigValue :: ConfigScope -> Text -> Text -> Eff es ()`. We will use `writeConfigValue ScopeLocal key val` to persist values.
- `seihou-core/src/Seihou/Effect/ConfigWriterInterp.hs` — The real IO interpreter for ConfigWriter. Already handles atomic writes to Dhall config files.
- `seihou-core/src/Seihou/Effect/Console.hs` — The `Console` effect with `putText`, `getLine`, `Confirm` for interactive I/O.


## Plan of Work

The work is organized into three milestones. Milestone 1 implements the core feature. Milestone 2 adds integration tests. Milestone 3 updates documentation.


### Milestone 1: Core Implementation — Save Prompted Values

At the end of this milestone, running `seihou run <module>` interactively will, after successful execution, display any values that were collected via interactive prompts and offer to save them to `.seihou/config.dhall`. The user can accept (all values saved), decline (nothing saved), or the behavior can be controlled via `--save-prompted` / `--no-save-prompted` flags.

**Step 1: Add CLI flags to RunOpts.** In `seihou-cli/src/Seihou/CLI/Commands.hs`, add a new field `runSavePrompted :: Maybe Bool` to the `RunOpts` record. Add two mutually exclusive flags to the `run` subcommand parser: `--save-prompted` (sets `Just True`) and `--no-save-prompted` (sets `Just False`). When neither is provided, the value is `Nothing` (meaning: ask interactively). The parser should use `optional` with `flag'` for each, combined with `<|>`.

**Step 2: Extract prompted values from resolution result.** In `seihou-cli/src/Seihou/CLI/Run.hs`, after the `resolved` map is obtained (around line 121) and after execution succeeds (around line 258, after `writeManifest`), collect all `ResolvedVar` entries across all modules whose `source` is `FromPrompt`. Deduplicate by variable name (if the same variable was prompted in multiple modules, keep the first occurrence since they'd have the same value). Convert each to a `(VarName, Text)` pair using the existing `varValueToText` helper. Also read the current local config to identify which prompted values are already present with identical values (skip those) and which would overwrite an existing different value (flag those).

**Step 3: Display and confirm.** If there are promptable values to save (after filtering out already-saved ones), and the mode is not `--no-save-prompted`, display them in a formatted list:

    Save prompted values to .seihou/config.dhall?

      project.name = "my-app"
      license      = "MIT"
      haskell.ghc  = "9.12.2"  (overwrites current: "9.10.3")

    Save? [Y/n]

If `--save-prompted` was passed, skip the confirmation and save directly. If `--no-save-prompted` was passed, skip the entire block. If the user declines (or is non-interactive and no flag was given), do nothing.

**Step 4: Write values via ConfigWriter.** For each confirmed value, call `writeConfigValue ScopeLocal key val`. The ConfigWriter effect and its interpreter already exist and handle atomic read-modify-write of Dhall config files. The `handleRun` function currently does not use `ConfigWriter` in its effect stack, so we need to add `runConfigWriter` to the `runEff` block that handles execution (the one starting around line 239). Specifically, the save step should happen inside a new `runEff` block after the execution block, since the execution block's effect stack is already closed.

**Step 5: Inform the user.** After saving, print a confirmation message:

    Saved 3 values to .seihou/config.dhall
    Use 'seihou config list' to view or 'seihou config unset <key>' to remove.

**Step 6: Unit tests.** Add a test module `test/Seihou/CLI/SavePromptedSpec.hs` (or extend an existing test file) that tests the pure logic of extracting prompted values from a resolution result map and filtering against existing local config. This does not require IO; it operates on `Map ModuleName (Map VarName ResolvedVar)` values.


### Milestone 2: Integration Tests

At the end of this milestone, we have automated tests proving the end-to-end behavior: prompted values are saved correctly, existing values are not silently overwritten, and the `--no-save-prompted` flag suppresses the offer.

**Test 1: Save and reuse.** Create a test module with one required variable that has no default. Run it in a simulated interactive session (using the pure Console interpreter to supply the prompted value). Verify that `.seihou/config.dhall` contains the value after the run. Then run again with the pure Console interpreter providing no input (simulating non-interactive). Verify resolution succeeds (the value is picked up from local config) and no prompt is triggered.

**Test 2: No overwrite.** Pre-populate `.seihou/config.dhall` with a value for a variable. Run a module that prompts for the same variable. The prompted value should differ from the config value. Since local config has higher priority than prompts, the prompt should not even fire (the variable is already resolved). Verify the config file is unchanged.

**Test 3: Overwrite with flag.** Use `--save-prompted` with a CLI override that causes a different value to be prompted. Verify the config file is updated. (This test validates the overwrite-with-disclosure path.)

**Test 4: Suppress.** Run with `--no-save-prompted`. Verify no save offer is made and the config file is unchanged.

Each test should use the existing pure effect interpreters (`ConsolePure`, `ConfigReaderPure`, `ConfigWriterPure`, `ManifestStorePure`, `FilesystemPure`) to avoid real IO.


### Milestone 3: Documentation

Update `docs/user/config-and-variables.md` to describe the new save-prompted behavior: what happens after a run, how to control it with flags, how to inspect and remove saved values. Add a section titled "Saving Prompted Values" between the existing "Interactive Prompts" and "Config File Layers" sections.

Update `docs/user/CHANGELOG.md` with an entry describing the feature.


## Concrete Steps

All commands should be run from the repository root (`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`).

Build the project:

    cabal build all

Run the test suite:

    cabal test all

Run a specific test:

    cabal test seihou-core-test --test-option='-p "save prompted"'

After implementation, verify manually by running a module that has prompts:

    cabal run seihou -- run <module-with-prompts>

Then check the saved config:

    cabal run seihou -- config list

Then re-run the same module and observe that no prompts appear:

    cabal run seihou -- run <module-with-prompts>

And verify provenance:

    cabal run seihou -- vars <module-with-prompts> --explain

Expected output should show `[local config]` for previously-prompted values.


## Validation and Acceptance

The feature is accepted when:

1. Running `seihou run <module>` interactively, answering prompts, and accepting the save offer causes the prompted values to appear in `.seihou/config.dhall`.
2. Re-running the same module does not re-prompt for the saved values.
3. `seihou vars <module> --explain` shows `[local config]` as the source for saved values.
4. `seihou config list` shows the saved values.
5. `seihou config unset <key>` removes a saved value, and re-running the module prompts for it again.
6. `--no-save-prompted` suppresses the save offer entirely.
7. `--save-prompted` saves without asking.
8. Values already in local config with the same value are not re-offered for saving.
9. Values that would overwrite an existing different local config value are shown with the existing value in the confirmation display.
10. All existing tests continue to pass.
11. New tests cover the core logic paths described in Milestone 2.


## Idempotence and Recovery

All steps are idempotent. The ConfigWriter effect uses atomic read-modify-write, so partial failures leave the config file unchanged. If the save step fails (e.g., disk error), the module's generated files are already written (the save happens after execution), so no work is lost. The user can manually run `seihou config set <key> <value>` to achieve the same result.

Running the save confirmation multiple times (e.g., by re-running the module) will detect that the values are already in local config and skip them, showing no save offer.


## Interfaces and Dependencies

No new dependencies are required. All needed effects and interpreters already exist.

In `seihou-cli/src/Seihou/CLI/Commands.hs`, add to the `RunOpts` record:

    runSavePrompted :: Maybe Bool

In `seihou-cli/src/Seihou/CLI/Run.hs`, add a helper function:

    collectPromptedValues
      :: Map ModuleName (Map VarName ResolvedVar)
      -> Map VarName Text   -- existing local config
      -> [(VarName, Text, Maybe Text)]
      -- ^ (variable name, prompted value, Just existingValue if overwrite)

This function is pure and testable. It filters the resolution result for `FromPrompt` sources, deduplicates, and compares against existing local config.

In `seihou-cli/src/Seihou/CLI/Run.hs`, add a function to handle the save interaction:

    offerSavePrompted
      :: (Console :> es, ConfigWriter :> es)
      => Maybe Bool          -- Nothing=ask, Just True=save, Just False=skip
      -> [(VarName, Text, Maybe Text)]
      -> Eff es ()

This function displays the confirmation prompt (or auto-saves/skips based on the flag) and calls `writeConfigValue ScopeLocal` for each accepted value.

The existing `ConfigWriter` effect (`seihou-core/src/Seihou/Effect/ConfigWriter.hs`) and its IO interpreter (`seihou-core/src/Seihou/Effect/ConfigWriterInterp.hs`) handle the actual file writes. The `Console` effect handles interactive confirmation.
