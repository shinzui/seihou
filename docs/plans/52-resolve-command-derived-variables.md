---
id: 52
slug: resolve-command-derived-variables
title: "Resolve command derived variables"
kind: exec-plan
created_at: 2026-06-19T16:22:12Z
intention: "intention_01kvgax2mfezgsw4rrzsk012qc"
master_plan: "docs/masterplans/6-first-class-prompt-support.md"
---

# Resolve command derived variables

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

After this change, Seihou can resolve some prompt variables by running local filesystem commands before rendering an agent prompt. This lets a reusable prompt include values such as the current git branch, changed files, package metadata, generated summaries, or tool output while still using the normal typed variable and config system for user-supplied values.

The visible proof is a prompt or focused test where `{{git.branch}}` is filled by `git branch --show-current`, while ordinary variables still come from CLI overrides, environment variables, project config, global config, defaults, or interactive prompts.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] 2026-06-19: Added `FromCommand Text` provenance to `VarSource` and rendered it in `formatExplain`.
- [x] 2026-06-19: Implemented `planCommandVars` in `seihou-core/src/Seihou/Core/CommandVar.hs` for deciding which command variables should run.
- [x] 2026-06-19: Implemented `resolveCommandVars` using `Seihou.Effect.Process.runProcess` with trimming, `maxBytes` enforcement, coercion, declaration validation, workDir safety, non-zero exit diagnostics, and command provenance.
- [x] 2026-06-19: Exposed a prompt-runner helper that fills command-derived values without overwriting already-resolved config, CLI, environment, default, parent, or prompted values.
- [x] 2026-06-19: Added pure process-interpreter tests for success, failure, conditions, safety limits, coercion, validation, and precedence.
- [x] 2026-06-19: Ran `cabal test seihou-core-test --test-options '--pattern CommandVar'`, `cabal build all`, and `cabal test seihou-core-test`.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- Discovery: EP-51 intentionally allowed command-only prompt variables that have no matching `VarDecl`, matching EP-50's schema example for `git.branch`.
  Evidence: `Seihou.Core.CommandVar.commandVarDecl` now uses a matching declaration when present and otherwise synthesizes a text declaration for prompt-only dynamic context. `Seihou.Core.CommandVarSpec` covers the command-only case.
  Date: 2026-06-19

- Discovery: `planCommandVars` must evaluate `when` conditions against both already-resolved values and explicit condition bindings.
  Evidence: the initial focused `CommandVar` test failed when `IsSet git.branch` could not see an already-resolved `git.branch`; `planCommandVars` now merges `resolvedValues existing <> bindings`.
  Date: 2026-06-19


## Decision Log

Record every decision made while working on the plan.

- Decision: Command-derived variables should run after normal config/default/prompt resolution and only fill variables that remain absent unless a command variable is explicitly marked to refresh.
  Rationale: The user specifically needs some variables pulled from global or project config. Config should remain the primary source when it supplies a value; commands are for dynamic context, not silent override of stored configuration.
  Date: 2026-06-19

- Decision: Command execution belongs in core/effect code, not directly in the CLI handler.
  Rationale: Seihou already has `Seihou.Effect.Process` and pure interpreters; using them keeps command resolution testable without spawning real processes.
  Date: 2026-06-19

- Decision: Command variables may be prompt-only dynamic context when no matching typed declaration exists.
  Rationale: EP-50 accepted a prompt schema expression with `commandVars = [ S.CommandVar::{ name = "git.branch", ... } ]` and no `vars` declaration. Requiring a matching `VarDecl` in EP-52 would invalidate that accepted schema behavior. When a declaration exists, its type and validation still govern the command output.
  Date: 2026-06-19


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

EP-52 added command-derived variable resolution as a core, process-effect-backed helper. Callers can pass declarations, command variables, and already-resolved values; the helper runs only commands that fill missing values, coerces and validates output, records `FromCommand` provenance, and returns a merged resolved map for later prompt rendering.

Validation evidence:

```text
cabal test seihou-core-test --test-options '--pattern CommandVar'
All 10 tests passed

cabal build all
completed successfully

cabal test seihou-core-test
All 916 tests passed
```


## Context and Orientation

Variable declarations live in `seihou-core/src/Seihou/Core/Types.hs` as `VarDecl`, `VarName`, `VarType`, `VarValue`, `ResolvedVar`, and `VarSource`. The existing resolver in `seihou-core/src/Seihou/Core/Variable.hs` coerces raw text into typed values and validates constraints. Composition-level resolution with interactive prompts lives in `seihou-core/src/Seihou/Composition/Resolve.hs`.

Seihou already has a process effect in `seihou-core/src/Seihou/Effect/Process.hs`:

```haskell
RunProcess :: Text -> [Text] -> Maybe FilePath -> Process m (ExitCode, Text, Text)
```

The real interpreter is `seihou-core/src/Seihou/Effect/ProcessInterp.hs`; the test interpreter is `seihou-core/src/Seihou/Effect/ProcessPure.hs`. Use those instead of calling `System.Process` from a prompt runner.

"Command-derived variable" means a variable declaration has a companion command record. The command produces raw text; Seihou trims it if configured, enforces a byte or character limit, coerces it to the variable's declared type, validates it, and records provenance as `FromCommand`.


## Plan of Work

Milestone 1 defines the execution model. Add a `CommandVar` type if EP-51 did not already add it, and add `FromCommand Text` or an equivalent constructor to `VarSource` so `seihou vars --explain` and future debug output can report the command source. The command-var record should refer to an existing declared variable by name; validation must reject command vars whose `name` is not in `vars`.

Milestone 2 implements command resolution in a new module such as `seihou-core/src/Seihou/Core/CommandVar.hs`. Provide a function that takes declared vars, command vars, existing resolved vars, and current bindings for `when` conditions. It should decide which commands to run, execute them through `Seihou.Effect.Process.runProcess`, and return a `Map VarName ResolvedVar` or `[VarError]`. A non-zero exit code should be a clear error that names the variable and command. Stderr should be included only as a concise diagnostic, not as a resolved value.

Milestone 3 integrates with prompt-style resolution. Do not change module/recipe resolution semantics in this plan. Instead, expose a helper that EP-53 can call after resolving regular prompt variables through the existing placeholder-module path. If future blueprint support is desired, it can call the same helper later.

Milestone 4 adds tests. Use `ProcessPure` to test success, stderr/non-zero failure, trimming, max-byte rejection, condition skipping, text-to-bool/int coercion, validation failure, and precedence. Add at least one integration-style test that starts with an already-resolved config value and proves the command does not override it by default.


## Concrete Steps

Run these commands from `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`:

```bash
sed -n '1,220p' seihou-core/src/Seihou/Effect/Process.hs
sed -n '1,260p' seihou-core/src/Seihou/Effect/ProcessPure.hs
sed -n '1,280p' seihou-core/src/Seihou/Core/Variable.hs
rg -n "VarSource|ResolvedVar|VarError|coerce|validate" seihou-core/src seihou-core/test
```

After implementation, run:

```bash
cabal test seihou-core-test --test-options '--pattern CommandVar'
cabal test seihou-core-test
```


## Validation and Acceptance

Acceptance is met when tests prove this behavior:

```text
vars = [ git.branch : text, release.ready : bool ]
existing resolved values = {}
commandVars =
  git.branch -> stdout "main\n"
  release.ready -> stdout "true\n"
result =
  git.branch = "main" from command
  release.ready = true from command
```

A second test must prove precedence:

```text
existing resolved values = { git.branch = "configured" from local config }
commandVars = git.branch -> stdout "main\n"
result = git.branch remains "configured"
```

The full core test suite must pass.


## Idempotence and Recovery

The pure tests are safe to run repeatedly. Avoid live commands in automated tests except through temporary directories and harmless commands. If a command output exceeds `maxBytes`, fail the variable resolution cleanly; do not truncate silently unless the schema explicitly adds a truncation mode.


## Interfaces and Dependencies

This plan depends on EP-50's `CommandVar` schema and should align with EP-51's `AgentPrompt` type. Required interface at completion:

```haskell
data VarSource = ... | FromCommand Text

resolveCommandVars ::
  (Process :> es) =>
  [VarDecl] ->
  [CommandVar] ->
  Map VarName ResolvedVar ->
  Map VarName VarValue ->
  Eff es (Either [VarError] (Map VarName ResolvedVar))
```

The exact function name may vary, but EP-53 must be able to call one library helper and receive new `ResolvedVar` values without spawning processes itself.
