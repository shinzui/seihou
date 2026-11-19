---
id: 125
slug: run-blueprint-baseline-commands-before-launching-the-agent
title: "Run blueprint baseline commands before launching the agent"
kind: exec-plan
created_at: 2026-11-14T05:03:30Z
provenance:
  created_by:
    model: "gpt-6.1-sol"
    harness: "codex-cli"
    at: 2026-11-14T05:03:30Z
  revisions:
    - model: "gpt-6.1-sol"
      harness: "codex-cli"
      at: 2026-11-14T05:06:05Z
      mode: "other"
      note: "Ground the new plan in BUG-4, baseline execution, command receipt contracts, and public-command acceptance."
    - model: "claude-fable-5-2"
      harness: "claude-code"
      at: 2026-11-19T02:34:15Z
      mode: "update"
      note: "Fix command-phase output to stderr, specify failure text and recovery, move two Run helpers to the library, correct context and signatures."
    - model: "claude-opus-5-5"
      harness: "claude-code"
      at: 2026-11-19T02:44:28Z
      mode: "implement"
      note: "Implemented all three milestones: baseline command phase, receipt withdrawal, docs, prompt and ADR 0023 amendment."
---

# Run blueprint baseline commands before launching the agent

This ExecPlan is a living document. Keep Progress, Surprises & Discoveries, Decision Log, and Outcomes & Retrospective current during implementation. Follow `agents/skills/exec-plan/PLANS.md`, `ADR.md`, and `FRICTION.md` for plan maintenance, durable decisions, and implementation friction.


## Purpose / Big Picture

A developer who runs a blueprint should receive the complete behavior of its baseline modules before the agent starts. Today those modules generate files but silently omit their shell commands. Fix [BUG-4](../bug-reports/a-blueprint-baseline-silently-skips-its-modules-commands.md) by running the composed baseline's commands with the same ordering, variable rendering, working directories, receipt handling, and failure semantics as `seihou run`.

The normal acceptance scenario starts with an existing project containing an installed or project-local blueprint and its baseline modules. The developer runs `seihou agent run BLUEPRINT` with their usual variables and provider configuration. Files are generated, baseline commands finish, and only then the provider launches. A command failure exits unsuccessfully before provider launch and names the failing command and how to retry. There is no preliminary module run, command duplication in the blueprint prompt, internal JSON edit, or extra tool permission declaration for deterministic baseline commands. First application and repeated application use this same command. `--no-baseline` skips the entire baseline. Parent `--debug` still applies the baseline, including commands, while skipping provider launch; document this clearly.

Everything the baseline command phase prints goes to standard error. Standard output stays what it is today: the provider's response in batch mode, which callers pipe, and the rendered prompt under `--debug`.

This plan creates a source fix and verifies the built executable. Record its path and version separately from any installed or released binary. The defect was reported against 0.16.0.0 and is still present in the 0.16.0.2 release (`1fb1610`, the commit this plan was last revised against); on 2026-11-18 the installed binary was `seihou v0.16.0.1 (4540d20)`. Publishing a release and changing external producer blueprints are separate delivery actions; do not claim any installed binary is fixed until an artifact containing this change is available and verified.


## Progress

- [x] Milestone 1 (2026-11-18): `seihou-cli/test/Seihou/CLI/BaselineCommandE2ESpec.hs` reproduced BUG-4 against the unfixed source (debug run: `cmd.log` absent, "expected: True but got: False"; batch run: the stub refused with "baseline sentinel missing"; 9 of 10 cases failed). After the helper move and the `applyBaseline` command phase, the debug and batch regressions pass: the commands' output and the `Running N baseline command(s)...` line are on standard error, and the batch stub's response is the only thing beyond the seed plan on standard output.
- [x] Milestone 2 (2026-11-18): `runBaselineCommands` in `seihou-cli/src-exe/Seihou/CLI/AgentRun.hs` withdraws this application's receipts on failure or exception, prints the specified failure text, and exits 1 before provider launch. All 10 cases of `blueprint baseline commands` pass, as do `command receipts end-to-end`, `agent path artifact guard`, and the `CommandExecution` unit cases (39 tests).
- [x] Milestone 3 (2026-11-18): `docs/user/blueprints.md`, `seihou-cli/help/blueprints.md`, `docs/cli/agent.md`, the `agent run --help` text, the embedded system prompt, and ADR 0023 describe the command phase; BUG-4 is marked fixed (unreleased). `cabal test seihou-cli-test` passed 1037 tests, `nix fmt` changed nothing, `nix flake check` passed, and `git diff --check` is clean. Delivery status is in Outcomes & Retrospective.


## Surprises & Discoveries

`Run.hs` imports `Seihou.CLI.CommandExecution` with an explicit list, not the whole module as the plan assumed, so the helper move also added `plannedCommandText` and `setApplicationCommandReceipts` to that list. No other consequence.

The seed plan that `applyBaseline` prints with `TIO.putStr` stays on standard output, as the Decision Log intended, so a failing batch run's standard output is not empty: it holds `create once ...` lines. The failure regression therefore asserts that standard output carries none of the command phase's output, rather than that it is empty.


## Decision Log

Decision (2026-11-14): Execute baseline commands rather than documenting their omission. A module's commands are part of applying it, and the baseline path already claims parity with ordinary run. A warning-only solution would preserve the broken checks and stale generated indexes described in BUG-4.

Decision (2026-11-14): Reuse the CLI command planner and executor and the existing application identity. Keep command execution outside the core file executor and preserve ADR 0023's early receipt publication and withdrawal contract. Do not create a new manifest field or a second baseline-specific receipt store.

Decision (2026-11-14): Preserve `agent --debug run`'s existing mutation semantics and `--no-baseline`'s full skip semantics. This fix does not redesign debug into a dry run or add a separate command opt-out flag.

Decision (2026-11-18): The baseline command phase writes only to standard error: its progress line, each successful command's captured standard output, the failed command's captured output, and the recovery text. `seihou run` echoes command output on standard output, but `seihou agent run --batch` reserves standard output for the provider's response (`seihou-cli/test/Seihou/CLI/AgentTraceE2ESpec.hs` already asserts trace lines stay off it because callers pipe it), and `--debug` prints the rendered prompt there. The seed plan that `applyBaseline` already prints on standard output is left alone; moving it is a separate change.

Decision (2026-11-18): Announce the command phase with a plain standard-error line at every verbosity, before the first command starts. `logInfo` is shown only under `--verbose`, and command output is captured rather than streamed, so without this line a slow command (the reporting consumer's is a Pulumi version check) looks like a hang.

Decision (2026-11-18): Move the two small helpers the baseline needs, `setApplicationCommandReceipts` and `plannedCommandText`, from `seihou-cli/src-exe/Seihou/CLI/Run.hs` into the library module `seihou-cli/src/Seihou/CLI/CommandExecution.hs`. They are private to Run today, neither needs an executable-only dependency, and `AgentRun.hs` does not import Run (it keeps a local copy of `opTargetsPath` for that reason). Do not extract the phase orchestration itself: Run's is interleaved with its own messages, judgement adoption and commit handling, and a shared wrapper would need a callback for each.

Decision (2026-11-18): The failure text names `--no-baseline` as the way to start the agent without re-running the baseline. Explicit reruns repeat every command, so a non-idempotent command that already succeeded can block the retry; the files are already on disk, so `--no-baseline` is a sufficient exit and no `--no-commands` flag is added to `agent run`. The cost is that such a run records `noBaseline: true` in blueprint provenance, which is accurate.

Decision (2026-11-18): Tell the agent, in the embedded system prompt, that the baseline modules' commands have already run. Producers worked around BUG-4 by instructing the agent to run them; without this line an unmodified producer prompt and the fixed baseline run each command twice with nothing telling the agent the first run happened.


## Outcomes & Retrospective

Outcome (2026-11-18): a blueprint baseline now applies its modules completely. In `applyBaseline`, the command plan comes from the full compiled operations under `RunAllCommands` against the shared application record's prior receipts. The expected receipts are set on `seedApplication`, so the existing generation write publishes them. `runBaselineCommands` then runs the phase after files, seeds, checkout outputs, the manifest write and baseline pruning. Run's withdrawal, confirmation and failure-reporting steps are reproduced there, with all output on standard error. The fix is commit `967e9c3`.

Acceptance evidence, all from the development executable `cabal list-bin exe:seihou` (under `dist-newstyle/`). It reports `seihou v0.16.0.2 (9df09c2)`: it was built from a working tree on top of `9df09c2` holding exactly the changes later committed as `967e9c3`, and cabal did not relink it after the commit, so the embedded hash names the parent:

```text
blueprint baseline commands (10 cases), command receipts end-to-end, agent path artifact guard: All 22 tests passed
cabal test seihou-cli-test: All 1037 tests passed
nix flake check: record-conventions, treefmt, cli-module-placement, pre-commit all passed
```

A manual failing run (`echo first...`, `echo boom >&2; exit 7`, `echo third...`) under `seihou agent --debug run proto-bp` exited 1 with empty standard output, left `cmd.log` holding only `first`, and printed the Plan of Work's failure text on standard error, preceded by `Running 3 baseline command(s)...` and the commands' captured output, and including the withdrawal sentence.

The artifact guard was not given its own command-bearing case. It runs in `handleAgentRun` before `applyBaseline` is called, so it cannot follow any shell execution, and `agent path artifact guard` still passes. The conflict refusal, which happens inside `applyBaseline`, has a dedicated case showing no command runs.

Delivery: not released. The installed executable is `/Users/shinzui/.nix-profile/bin/seihou`, `seihou v0.16.0.1 (4540d20)`, which does not contain this fix, and neither does the 0.16.0.2 release. BUG-4 records `fixedVersion: unreleased`. Producers such as `mori://tan/tan-seihou-modules` should keep their workaround until their consumers run a release containing `967e9c3`, then remove it as `docs/user/blueprints.md` describes.

No friction met the recording threshold. ADR 0023 was amended to cover the baseline path; no new ADR was needed, because the decision to keep the agent's standard output for the provider is already enforced by `AgentTraceE2ESpec` and is now stated in the user guide.


## Context and Orientation

A blueprint is an agent prompt with optional baseline modules, declared as `baseModules` in `schema/Blueprint.dhall`. A baseline is the deterministic module composition applied before that prompt is sent to a provider. Composition means the declared modules plus their recursively required dependencies in resolved order. A command operation is the rendered shell command produced from a module's declaration; `schema/Command.dhall` distinguishes ordinary `Apply` actions from repeatable `Checkout` actions.

`seihou-cli/src-exe/Seihou/CLI/AgentRun.hs` implements `handleAgentRun`, `loadBaselineComposition`, and `applyBaseline`. The handler checks artifact provenance and resolves variables, calls `applyBaseline`, renders the prompt, launches the provider, and finally records successful blueprint provenance. `applyBaseline` compiles operations through `seihou-core/src/Seihou/Composition/Plan.hs`, plans file conflicts, seeds and checkout outputs, executes files, records their state, and returns `BaselineApplied`. Its `seedApplication` is already a full applied-composition record, identified by `mkApplicationId (AppliedModuleTarget primary) []` where `primary` is the first baseline module. Extend that record instead of introducing another identity.

`buildAppliedComposition` in `seihou-core/src/Seihou/Core/Application.hs` creates the record with `commandReceipts = Map.empty`, and `applyBaseline` writes it with `replaceAppliedComposition`. `seihou run PRIMARY` with no additional modules produces the same application ID, so today a baseline run also erases the receipts an earlier `seihou run` of the primary module recorded, and the next `seihou update` re-runs those commands. Writing the expected receipts fixes that as a side effect. The ID is built with an empty additional-module list even when the blueprint declares several base modules, so the one record covers the whole composition; leave that as it is, because changing the ID would orphan the records existing projects hold.

`seihou-core/src/Seihou/Engine/Execute.hs` deliberately ignores `RunCommandOp`: the CLI owns execution. Therefore passing baseline commands to `executePlan` does not run them. `seihou-cli/src-exe/Seihou/CLI/Run.hs` supplies the missing model, in `handleRun` from the comment "Commands are planned against the previously accepted receipts" through the block that follows "Execute commands after file generation": it reads the prior application receipts, uses `planCommands`, publishes expected receipts with the file manifest, executes the command phase, and withdraws the phase's receipts on failure or exception. Two helpers that block uses, `setApplicationCommandReceipts` (replace one application's receipt map inside a manifest) and `plannedCommandText` (the rendered shell text of a planned command), are defined at the bottom of `Run.hs` and are not exported.

`applyBaseline` reports through two channels. `logIO level` runs the logger from `seihou-core/src/Seihou/Effect/LoggerInterp.hs`, which writes to standard error and shows `logInfo` and `logDebug` only when `--verbose` is passed; the existing `Baseline applied: N new, N modified, N unchanged.` line is a `logInfo`, so an ordinary run does not show it. The seed plan is printed with `TIO.putStr` on standard output. In batch mode `runRenderedAgentPromptMode` prints the provider's response on standard output, and under `--debug` it prints the rendered system prompt there.

A receipt is a manifest entry recording successful execution of an ordinary command using a fingerprint derived from its rendered text, working directory, owning module instance, and occurrence. `seihou-cli/src/Seihou/CLI/CommandExecution.hs` exports `planCommands`, `RunAllCommands`, `expectedCommandReceipts`, `finalizeCommandReceipts`, `withReceiptWithdrawal`, and `executeCommandPlanWithOutput`. Checkout commands run in application order but do not receive ordinary completion receipts. Ordinary explicit run always executes commands, even when unchanged; only update's changed-command policy skips previously completed unchanged commands.

Relevant ADRs consulted are [ADR 0004](../adr/0004-the-manifest-is-the-only-record-of-applied-state.md), which makes the manifest the sole applied-state record; [ADR 0018](../adr/0018-checkout-outputs-are-observable-portable-declarations.md), which separates recorded checkout intent from ordinary commands and forbids sync from replaying arbitrary application commands; and [ADR 0023](../adr/0023-command-receipts-are-published-before-the-command-phase-runs.md), which requires expected receipts to be present before commands can commit the project and withdrawn if the phase fails. Preserve the existing seed and checkout application phases; this change adds the missing command phase after them.

`seihou-cli/test/Seihou/CLI/SeedRunE2ESpec.hs` exports `prepare`, `body`, `invoke`, `success`, and `readManifest` helpers with isolated home/config/cache directories and a local pinned schema. `seihou-cli/test/Seihou/CLI/CommandReceiptE2ESpec.hs` (`writeCommandModule`, `committedManifest`, `demoReceipts`) demonstrates manifest-committing commands and failure withdrawal. `seihou-cli/test/Seihou/CLI/AgentGuardE2ESpec.hs` demonstrates blueprint fixtures, baseline guards, and provider-launch sentinels. `withTraceProject` in `seihou-cli/test/Seihou/CLI/AgentTraceE2ESpec.hs` shows a real batch launch without network or credentials: it writes an executable shell script named `claude` into a directory placed first on `PATH`, and that script prints the single JSON line the `claude-cli` provider expects, `{"result":"...","is_error":false,"session_id":"fake"}`. `seihou-cli/test/Seihou/CLI/CommandExecutionSpec.hs` already covers `withReceiptWithdrawal`, including a `UserInterrupt` thrown from the phase and a withdrawal that itself throws. The executable is located using `seihou-cli/test/Seihou/CLI/SeihouBinary.hs`, which intentionally refuses to fall back to an installed binary.

The consumer that reported this issue is `mori://tan/tan-seihou-modules`; its report describes a seed-producing module followed by a version check and an index generator. Reproduce that observable pattern locally without requiring Pulumi, private access, or consumer changes. During creation, `mori registry list` failed because its local PostgreSQL socket refused connections. No external dependency API, version, or canonical artifact beyond the supplied project reference is needed for this fix. If later implementation needs dependency APIs, discover their source through Mori first and verify releases before changing bounds.


## Plan of Work

### Milestone 1: Complete the ordinary baseline application

Create `seihou-cli/test/Seihou/CLI/BaselineCommandE2ESpec.hs` with test group name `blueprint baseline commands`, and register it in `seihou-cli/test/Main.hs` and `seihou-cli/seihou-cli.cabal`. Start with a minimal real consumer: project-local `demo` module writes a seed and a managed file; its Apply command checks that the seed exists and appends to `cmd.log`. A project-local `proto-bp` blueprint declares only `demo` as its baseline. Use isolated home/config/cache directories from the existing fixtures, without pre-running the baseline or editing the manifest. In separate fresh projects run `seihou run demo` and `seihou agent --debug run proto-bp`. Show that the former creates `cmd.log` and the latter currently fails the same assertion. Preserve this as the first regression and exercise it before broadening tests.

First move `setApplicationCommandReceipts` and `plannedCommandText` from `Run.hs` to `seihou-cli/src/Seihou/CLI/CommandExecution.hs`, export them, and delete the Run copies; Run already imports the whole module. This is a pure move and the existing suites must still pass.

In `applyBaseline`, derive the command plan from `ops`, the complete compiled operations, before file conflict filtering produces `opsForExec`. Select `RunAllCommands` and the prior receipts of the record in `manifest ^. #applications` whose `applicationId` equals the existing `applicationId` binding, or an empty map when there is none. Compute both the failure receipt map (`finalizeCommandReceipts plan [] prior`) and the success map (`finalizeCommandReceipts plan (expectedCommandReceipts now plan) prior`), using the `now` the function already holds. Under `RunAllCommands` the failure map holds no ordinary receipts, so a failed phase leaves this application with none, exactly as a failed `seihou run` does. Set the success map on `seedApplication` (`& #commandReceipts .~ successMap`) so the existing `writeManifest seededManifest` publishes it with the generated files. After files, seeds, checkout materialization, manifest persistence and baseline pruning succeed, execute the command phase with `runEff $ runProcessIO $ executeCommandPlanWithOutput now onSuccess plan`. Composed declaration order, conditional filtering, rendered variables and working directories come from compilation; do not recompile, and do not execute commands in the file engine.

Output follows the Decision Log: standard error only. When the plan holds at least one command, print `Running N baseline command(s)...` with `hPutStrLn stderr` before the first command, at every verbosity. Under `--verbose`, also `logDebug` one `  run  <command>` line per command as Run does. The `onSuccess` callback writes each successful command's captured standard output to standard error and drops its captured standard error, matching what `seihou run` shows. Print nothing about commands when the plan is empty. Keep the `Baseline applied: ...` line as it is and emit it, and return `BaselineApplied`, only after the phase succeeds.

Prove batch ordering with a provider stub modelled on `withTraceProject`: a fake `claude` that exits 1 unless the command's sentinel file exists and otherwise prints the JSON result line. Pass the sentinel's absolute path in an environment variable rather than relying on the provider's working directory. Assert that the batch run's standard output contains the stub's result and none of the command's output, and that the command's output and the progress line are on standard error. Deterministic commands execute under Seihou's normal process permissions, independently of the agent's `allowedTools`.

### Milestone 2: Preserve receipt truth and failure boundaries

Wrap execution with `withReceiptWithdrawal withdraw phase`; both arguments are `IO` actions and the result is the phase's `Either CommandExecutionError [CommandReceipt]`. The withdrawal writes `setApplicationCommandReceipts applicationId failureMap newManifest`, where `newManifest` is the manifest the generation step just saved, so it replaces only this application's receipts. Do not restore the whole old manifest: files, accepted seeds, and checkout declarations were already applied. Skip the withdrawal when the success and failure maps are equal (nothing was published), record in an `IORef` whether it succeeded, and report a failed withdrawal from inside the action, because `withReceiptWithdrawal` discards an exception the action throws. After a successful phase, compare `finalizeCommandReceipts plan completed prior` with the published map and rewrite the manifest only if they differ, which would indicate a defect in `expectedCommandReceipts`. Run's block is the reference for each of these steps. Do not change Run or Update beyond the helper move in Milestone 1.

A nonzero exit stops later commands and the provider and exits 1. `CommandExecutionError` carries the planned command, the exit code, and the captured output; the owning module and working directory are fields of the command's `RunCommandOp`. Print, on standard error, the failed command's captured standard output and standard error, then:

```text
[error] Baseline command failed (exit 7): exit 7
  module: demo
  directory: .
The agent was not started. Baseline files and the effects of earlier commands remain; inspect them before retrying.
Correct the failure, then rerun: seihou agent run proto-bp
To start the agent without applying the baseline again: seihou agent run proto-bp --no-baseline
```

The `[error]` prefix comes from `logError`; the blueprint name is the one the user ran. When the failed command is a Checkout command (`isCheckoutCommand`), add Run's sentence that accepted checkout declarations remain recorded and `seihou sync` retries them. When receipts were withdrawn, add that they were withdrawn from `.seihou/manifest.json`, and that if a command in this run committed or pushed the manifest, that snapshot records receipts for commands that did not complete, so the user should commit the result of the successful rerun; follow ADR 0023 without rewriting history. When the withdrawal itself failed, say the manifest may still hold provisional receipts. An IO exception or interrupt during the phase also withdraws the receipts and propagates.

Extend the real-binary regression with success, failure in the middle, and a command that commits the manifest. Assert that the command's committed application record contains expected receipts and that the baseline phase itself does not rewrite those receipts after success. Do not assert that the entire blueprint leaves Git clean: successful blueprint provenance is intentionally written after provider completion. Preserve earlier blueprint provenance on failure rather than deleting an older successful entry, and verify no new successful blueprint provenance is recorded. Assert the failure text above on standard error, including both recovery commands, and that the failing run's standard output carries no command output. Withdrawal under an interrupt is already covered by the `withReceiptWithdrawal` cases in `CommandExecutionSpec.hs`; add no timing-dependent process kill.

Verify transitive dependency commands run once in composition order, conditions suppress commands correctly, variables and workDir are honored, a second explicit baseline application runs commands again, and `--no-baseline` runs none. Include a previously applied composition whose manifest has no command receipts, representing projects affected by BUG-4; an ordinary rerun must execute commands without manual manifest repair. Cover the shared application record: after `seihou run demo` and then a successful blueprint run whose baseline is `demo`, the application still holds `demo`'s command receipts. Confirm Checkout commands execute once in their application phase and remain excluded from ordinary receipts. Confirm command-free and empty-baseline blueprints retain their behavior, and artifact/conflict refusal still precedes shell execution.

### Milestone 3: Explain and verify the user workflow

Update `docs/user/blueprints.md` under Baseline modules and run flow, `seihou-cli/help/blueprints.md`, and `docs/cli/agent.md`. Explain that baseline files are followed by module commands, failure prevents provider launch, explicit reruns repeat commands, `--no-baseline` skips both, and parent `--debug run` executes baseline commands. Clarify that agent allowed-tools configuration controls the provider, while deterministic module commands run directly, and that the command phase reports on standard error. Extend step 4 of "The runner" list in `docs/user/blueprints.md` to say the modules' commands run after their files. Add a short note for blueprint authors: releases through 0.16.0.2 skip baseline commands, so a prompt that tells the agent to run them, and the `allowedTools` entries added only for that, should be removed once consumers run a fixed release; otherwise each command runs twice.

Update the embedded system prompt `seihou-cli/data/blueprint-prompt.md`, workflow step 2 ("Examine the baseline"): state that the listed modules' files were generated and their commands already ran successfully before the agent started, and that the agent should not run them again unless the task asks for it. Check for tests that assert the rendered prompt before changing it.

Update ADR 0023 to include baseline application in its publication/withdrawal contract, preserving its stated residual risk, and link this plan. Inspect the local ADR convention before editing; if the manifest declares a profile-governed ADR bundle, follow `agents/skills/exec-plan/ADR.md` and its strict validation. Update the bug report's status only when implementation and acceptance are verified, keeping the affected-version history intact. Record source-build evidence, the installed version observed, and any release/install gap in Outcomes & Retrospective. Do not mark release delivery complete based on a development binary alone.


## Concrete Steps

Run from the repository root. If the host lacks the Haskell tools, enter the project shell using `nix develop`, then run the same commands. Never inspect or traverse `/nix/store`.

```bash
cabal build seihou-cli:exe:seihou seihou-cli:test:seihou-cli-test
cd seihou-cli
$(cabal list-bin seihou-cli-test) -p '/blueprint baseline commands/'
```

Before the implementation change, the first regression must fail because the baseline command's sentinel is absent. After Milestone 1, the success regression must pass and the fake batch provider must see the sentinel before launch. The test group must contain executed tests: `All 0 tests passed` is a selection failure. Run test binaries from `seihou-cli/`; these end-to-end fixtures locate the schema as `../schema`.

After Milestone 2 run the related suites from `seihou-cli/`:

```bash
$(cabal list-bin seihou-cli-test) -p '/blueprint baseline commands/ || /command receipts end-to-end/ || /agent path artifact guard/'
```

For final validation return to the repository root and run:

```bash
cd ..
cabal test seihou-cli-test
nix fmt
nix flake check
git diff --check
cabal run exe:seihou -- help blueprints
cabal run exe:seihou -- agent run --help
cabal run exe:seihou -- --version
command -v seihou
seihou --version
```

Report a missing installed executable as unavailable rather than silently substituting the development build. Inspect formatter changes and keep them within the touched files. Record concise acceptance results rather than full test transcripts. Use Conventional Commits for implementation checkpoints with `ExecPlan: docs/plans/125-run-blueprint-baseline-commands-before-launching-the-agent.md` in each commit's trailers.


## Validation and Acceptance

The decisive acceptance is the real executable applying a seed-and-command module as a blueprint baseline, from an untouched consumer fixture. The baseline's command verifies the seed and creates `cmd.log` before any provider activity. Direct `run` and debug blueprint run must agree on this command effect, and a real batch invocation with a local provider stub must prove launch ordering. Debug never launches the stub. No paid provider or private consumer access is required.

A module with commands `append first`, `exit 7`, and `append third` must leave only the first append, exit 1, report `Baseline command failed (exit 7)` with the owning module and both recovery commands on standard error, and never launch the provider or claim a newly successful blueprint run. Its accepted baseline files remain, while the application's ordinary-command receipts are removed. In batch mode standard output carries the provider's response and nothing from the command phase. The manifest-commit regression proves receipts are present when commands snapshot the application. Existing receipt tests must still pass if shared code is extracted.

Rerunning the ordinary blueprint command after fixing the failure must complete without internal edits. Existing receipt-free baseline applications must recover through that same rerun. A second explicit successful application repeats commands; `--no-baseline` suppresses both files and commands. Transitive ordering, conditions, workDir and variable rendering must match ordinary run. Guard and conflict refusals must execute no commands. Passing the full CLI suite and repository checks, along with readable help and failure diagnostics, completes source acceptance. Record the exact tested executable/version and keep any release delivery gap explicit.


## Idempotence and Recovery

Temporary fixtures isolate home, configuration, caches, generated files, and Git history. Recreate them for independent scenarios rather than manually cleaning a manifest between runs. Never modify the reporting consumer or invoke its real external tools just to establish this regression.

Explicit module and baseline application intentionally rerun shell commands. They are not generally idempotent: retain generated files and prior shell side effects on command failure, and tell the user to inspect them before retrying. Seeds continue to preserve edits and deliberate deletions under their existing contract. Receipt withdrawal removes success evidence for this failed phase, not files or arbitrary shell effects. Catchable exceptions receive withdrawal; a hard process kill can leave provisional receipts, as already documented by ADR 0023. Do not promise crash rollback or rewrite Git commits. The recovery command is the same blueprint run after correcting the underlying failure.


## Interfaces and Dependencies

This is a standalone CLI behavior fix using existing core operations and manifest records. No dependency upgrade, new schema field, migration, provider protocol, or producer release is required. `ComposedPlan.operations`, `AppliedComposition.commandReceipts`, and the current application ID remain authoritative. `planCommands RunAllCommands prior operations` decides the command list; `expectedCommandReceipts` and `finalizeCommandReceipts` build success and failure maps; `withReceiptWithdrawal` protects the phase; and `executeCommandPlanWithOutput` runs the shell in the declared working directory.

The signatures the baseline calls, all from `seihou-cli/src/Seihou/CLI/CommandExecution.hs`:

```haskell
planCommands :: CommandPolicy -> Map CommandFingerprint CommandReceipt -> [Operation] -> CommandPlan
expectedCommandReceipts :: UTCTime -> CommandPlan -> [CommandReceipt]
finalizeCommandReceipts :: CommandPlan -> [CommandReceipt] -> Map CommandFingerprint CommandReceipt -> Map CommandFingerprint CommandReceipt
withReceiptWithdrawal :: IO () -> IO (Either CommandExecutionError a) -> IO (Either CommandExecutionError a)
executeCommandPlanWithOutput :: (Process :> es, IOE :> es) => UTCTime -> (PlannedCommand -> Text -> Text -> Eff es ()) -> CommandPlan -> Eff es (Either CommandExecutionError [CommandReceipt])

-- moved here from Run.hs by this plan, unchanged
setApplicationCommandReceipts :: ApplicationId -> Map CommandFingerprint CommandReceipt -> Manifest -> Manifest
plannedCommandText :: PlannedCommand -> Text
```

The callback's two `Text` arguments are the command's captured standard output and standard error. `CommandExecutionError` has fields `command`, `exitCode`, `stdout`, and `stderr`; a command that could not be launched reports exit code 127.

Keep core `executePlan` a file executor. Keep normal Run and Update receipt semantics intact. `applyBaseline`'s signature and `BaselineStatus` do not change, and no CLI flag is added. Blueprint success/provenance remains owned by `handleAgentRun` after the baseline and provider succeed. The skill's provenance scripts record authorship updates; never hand-edit their frontmatter block.


## Revision Notes

2026-11-18: Reviewed against the working tree at `1fb1610` for developer experience and interface accuracy. Fixed the command phase's output to standard error with a progress line shown at every verbosity, because batch callers pipe standard output and the existing `Baseline applied` line is visible only under `--verbose`. Specified the failure text, including the owning module and `--no-baseline` as the way to proceed. Replaced the optional shared-helper extraction with a definite move of two private Run helpers into the library, and recorded the exact signatures. Added the system-prompt change and the author migration note so producers' BUG-4 workarounds do not double-run commands. Corrected the context: the handler is `handleAgentRun`, the baseline currently erases receipts recorded by `seihou run` of the primary module, interrupt withdrawal is already tested, and the release and installed versions have moved on from 0.16.0.0.
