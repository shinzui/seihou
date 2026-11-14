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
---

# Run blueprint baseline commands before launching the agent

This ExecPlan is a living document. Keep Progress, Surprises & Discoveries, Decision Log, and Outcomes & Retrospective current during implementation. Follow `agents/skills/exec-plan/PLANS.md`, `ADR.md`, and `FRICTION.md` for plan maintenance, durable decisions, and implementation friction.


## Purpose / Big Picture

A developer who runs a blueprint should receive the complete behavior of its baseline modules before the agent starts. Today those modules generate files but silently omit their shell commands. Fix [BUG-4](../bug-reports/a-blueprint-baseline-silently-skips-its-modules-commands.md) by running the composed baseline's commands with the same ordering, variable rendering, working directories, receipt handling, and failure semantics as `seihou run`.

The normal acceptance scenario starts with an existing project containing an installed or project-local blueprint and its baseline modules. The developer runs `seihou agent run BLUEPRINT` with their usual variables and provider configuration. Files are generated, baseline commands finish, and only then the provider launches. A command failure exits unsuccessfully before provider launch and names the failing command and how to retry. There is no preliminary module run, command duplication in the blueprint prompt, internal JSON edit, or extra tool permission declaration for deterministic baseline commands. First application and repeated application use this same command. `--no-baseline` skips the entire baseline. Parent `--debug` still applies the baseline, including commands, while skipping provider launch; document this clearly.

This plan creates a source fix and verifies the built executable. Record its path and version separately from any installed or released binary. Publishing a release and changing external producer blueprints are separate delivery actions; do not claim the affected installed 0.16.0.0 is fixed until an artifact containing this change is available and verified.


## Progress

- [ ] Milestone 1: A public-command regression reproduces BUG-4, then baseline commands run successfully before the provider with ordinary run semantics.
- [ ] Milestone 2: Failed or interrupted command phases withdraw provisional receipts and stop the blueprint before provider launch; repeated runs and skip behavior are verified.
- [ ] Milestone 3: Documentation, diagnostics, and final built-binary acceptance demonstrate the complete workflow and accurately state delivery status.


## Surprises & Discoveries


## Decision Log

Decision (2026-11-14): Execute baseline commands rather than documenting their omission. A module's commands are part of applying it, and the baseline path already claims parity with ordinary run. A warning-only solution would preserve the broken checks and stale generated indexes described in BUG-4.

Decision (2026-11-14): Reuse the CLI command planner and executor and the existing application identity. Keep command execution outside the core file executor and preserve ADR 0023's early receipt publication and withdrawal contract. Do not create a new manifest field or a second baseline-specific receipt store.

Decision (2026-11-14): Preserve `agent --debug run`'s existing mutation semantics and `--no-baseline`'s full skip semantics. This fix does not redesign debug into a dry run or add a separate command opt-out flag.


## Outcomes & Retrospective


## Context and Orientation

A blueprint is an agent prompt with optional baseline modules, declared as `baseModules` in `schema/Blueprint.dhall`. A baseline is the deterministic module composition applied before that prompt is sent to a provider. Composition means the declared modules plus their recursively required dependencies in resolved order. A command operation is the rendered shell command produced from a module's declaration; `schema/Command.dhall` distinguishes ordinary `Apply` actions from repeatable `Checkout` actions.

`seihou-cli/src-exe/Seihou/CLI/AgentRun.hs` implements `handleBlueprintRun`, `loadBaselineComposition`, and `applyBaseline`. The handler checks artifact provenance and resolves variables, calls `applyBaseline`, renders the prompt, launches the provider, and finally records successful blueprint provenance. `applyBaseline` compiles operations through `seihou-core/src/Seihou/Composition/Plan.hs`, plans file conflicts, seeds and checkout outputs, executes files, records their state, and returns `BaselineApplied`. Its `seedApplication` is already a full applied-composition record, identified by `mkApplicationId (AppliedModuleTarget primary) []` where `primary` is the first baseline module. Extend that record instead of introducing another identity.

`seihou-core/src/Seihou/Engine/Execute.hs` deliberately ignores `RunCommandOp`: the CLI owns execution. Therefore passing baseline commands to `executePlan` does not run them. `seihou-cli/src-exe/Seihou/CLI/Run.hs` supplies the missing model: it reads the prior application receipts, uses `planCommands`, publishes expected receipts with the file manifest, executes the command phase, and withdraws the phase's receipts on failure or exception.

A receipt is a manifest entry recording successful execution of an ordinary command using a fingerprint derived from its rendered text, working directory, owning module instance, and occurrence. `seihou-cli/src/Seihou/CLI/CommandExecution.hs` exports `planCommands`, `RunAllCommands`, `expectedCommandReceipts`, `finalizeCommandReceipts`, `withReceiptWithdrawal`, and `executeCommandPlanWithOutput`. Checkout commands run in application order but do not receive ordinary completion receipts. Ordinary explicit run always executes commands, even when unchanged; only update's changed-command policy skips previously completed unchanged commands.

Relevant ADRs consulted are [ADR 0004](../adr/0004-the-manifest-is-the-only-record-of-applied-state.md), which makes the manifest the sole applied-state record; [ADR 0018](../adr/0018-checkout-outputs-are-observable-portable-declarations.md), which separates recorded checkout intent from ordinary commands and forbids sync from replaying arbitrary application commands; and [ADR 0023](../adr/0023-command-receipts-are-published-before-the-command-phase-runs.md), which requires expected receipts to be present before commands can commit the project and withdrawn if the phase fails. Preserve the existing seed and checkout application phases; this change adds the missing command phase after them.

`seihou-cli/test/Seihou/CLI/SeedRunE2ESpec.hs` provides `prepare`, `invoke`, and `readManifest` helpers with isolated home/config/cache directories and a local pinned schema. `seihou-cli/test/Seihou/CLI/CommandReceiptE2ESpec.hs` demonstrates manifest-committing commands and failure withdrawal. `seihou-cli/test/Seihou/CLI/AgentGuardE2ESpec.hs` demonstrates blueprint fixtures, baseline guards, and provider-launch sentinels. Use the fake-provider conventions in `seihou-cli/test/Seihou/CLI/AgentTraceE2ESpec.hs` for a real batch launch without network or credentials. The executable is located using `seihou-cli/test/Seihou/CLI/SeihouBinary.hs`, which intentionally refuses to fall back to an installed binary.

The consumer that reported this issue is `mori://tan/tan-seihou-modules`; its report describes a seed-producing module followed by a version check and an index generator. Reproduce that observable pattern locally without requiring Pulumi, private access, or consumer changes. During creation, `mori registry list` failed because its local PostgreSQL socket refused connections. No external dependency API, version, or canonical artifact beyond the supplied project reference is needed for this fix. If later implementation needs dependency APIs, discover their source through Mori first and verify releases before changing bounds.


## Plan of Work

### Milestone 1: Complete the ordinary baseline application

Create `seihou-cli/test/Seihou/CLI/BaselineCommandE2ESpec.hs` with test group name `blueprint baseline commands`, and register it in `seihou-cli/test/Main.hs` and `seihou-cli/seihou-cli.cabal`. Start with a minimal real consumer: project-local `demo` module writes a seed and a managed file; its Apply command checks that the seed exists and appends to `cmd.log`. A project-local `proto-bp` blueprint declares only `demo` as its baseline. Use isolated home/config/cache directories from the existing fixtures, without pre-running the baseline or editing the manifest. In separate fresh projects run `seihou run demo` and `seihou agent --debug run proto-bp`. Show that the former creates `cmd.log` and the latter currently fails the same assertion. Preserve this as the first regression and exercise it before broadening tests.

In `applyBaseline`, derive the command plan from the complete compiled operations, before file conflict filtering. Select `RunAllCommands` and the prior receipts belonging to this exact application ID. Compute both the failure receipt map (`finalizeCommandReceipts plan [] prior`) and the success map (`finalizeCommandReceipts plan (expectedCommandReceipts now plan) prior`). Store the success map on the applied composition written with generated files. After successful files, seeds, checkout materialization, and manifest persistence, execute the command phase via `runProcessIO` and `executeCommandPlanWithOutput`. Preserve composed declaration order, conditional filtering already performed by compilation, rendered variables, and command working directories. Do not recompile or execute commands in the file engine.

Only report `Baseline applied` and return `BaselineApplied` after the command phase succeeds. At normal verbosity give a concise command-phase count when commands exist and show captured successful stdout consistently with ordinary run. Debug logging may name individual commands. No command phase should be announced for an empty command list. Prove batch ordering with a controlled provider stub that refuses to return success unless the command sentinel already exists. Deterministic commands execute under Seihou's normal process permissions, independently of the agent's `allowedTools`.

### Milestone 2: Preserve receipt truth and failure boundaries

Wrap execution with `withReceiptWithdrawal`. A withdrawal must replace only this application's receipts in the newly accepted generation manifest, using the failure map computed above. Do not restore the whole old manifest: files, accepted seeds, and checkout declarations were already applied. Use the existing Run implementation as the semantic reference. If extracting a shared orchestration helper reduces duplication, place it in `seihou-cli/src/Seihou/CLI/CommandExecution.hs` and keep command-specific rendering and blueprint retry wording in the caller. Avoid a broad rewrite of Run or Update.

A nonzero exit must show the failed command, exit code, and captured failure output; stop later commands and the provider; and leave no newly earned receipts, including for commands earlier in the failed phase. An IO exception or interrupt must also withdraw provisional receipts and propagate failure. If withdrawal itself fails, report that the manifest may still contain provisional receipts. Give a supported next action using `seihou agent run proto-bp` (the actual blueprint name in production), after the user corrects the command failure. State that earlier files and shell side effects can remain. If a command already committed or pushed the manifest before a later failure, explain that the working-copy withdrawal cannot repair that historical snapshot; follow ADR 0023 without rewriting history.

Extend the real-binary regression with success, failure in the middle, and a command that commits the manifest. Assert that the command's committed application record contains expected receipts and that the baseline phase itself does not rewrite those receipts after success. Do not assert that the entire blueprint leaves Git clean: successful blueprint provenance is intentionally written after provider completion. Preserve earlier blueprint provenance on failure rather than deleting an older successful entry, and verify no new successful blueprint provenance is recorded. Use focused library exception tests for withdrawal under an interrupt instead of timing-dependent process kills.

Verify transitive dependency commands run once in composition order, conditions suppress commands correctly, variables and workDir are honored, a second explicit baseline application runs commands again, and `--no-baseline` runs none. Include a previously applied composition whose manifest has no command receipts, representing projects affected by BUG-4; an ordinary rerun must execute commands without manual manifest repair. Confirm Checkout commands execute once in their application phase and remain excluded from ordinary receipts. Confirm command-free and empty-baseline blueprints retain their behavior, and artifact/conflict refusal still precedes shell execution.

### Milestone 3: Explain and verify the user workflow

Update `docs/user/blueprints.md` under Baseline modules and run flow, `seihou-cli/help/blueprints.md`, and `docs/cli/agent.md`. Explain that baseline files are followed by module commands, failure prevents provider launch, explicit reruns repeat commands, `--no-baseline` skips both, and parent `--debug run` executes baseline commands. Clarify that agent allowed-tools configuration controls the provider, while deterministic module commands run directly. Inspect any embedded agent guidance naming baseline behavior and align relevant statements without adding unrelated documentation.

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

A module with commands `append first`, `exit 7`, and `append third` must leave only the first append, report exit 7, and never launch the provider or claim a newly successful blueprint run. Its accepted baseline files remain, while newly provisional ordinary-command receipts are removed. The manifest-commit regression proves receipts are present when commands snapshot the application. Existing receipt tests must still pass if shared code is extracted.

Rerunning the ordinary blueprint command after fixing the failure must complete without internal edits. Existing receipt-free baseline applications must recover through that same rerun. A second explicit successful application repeats commands; `--no-baseline` suppresses both files and commands. Transitive ordering, conditions, workDir and variable rendering must match ordinary run. Guard and conflict refusals must execute no commands. Passing the full CLI suite and repository checks, along with readable help and failure diagnostics, completes source acceptance. Record the exact tested executable/version and keep any release delivery gap explicit.


## Idempotence and Recovery

Temporary fixtures isolate home, configuration, caches, generated files, and Git history. Recreate them for independent scenarios rather than manually cleaning a manifest between runs. Never modify the reporting consumer or invoke its real external tools just to establish this regression.

Explicit module and baseline application intentionally rerun shell commands. They are not generally idempotent: retain generated files and prior shell side effects on command failure, and tell the user to inspect them before retrying. Seeds continue to preserve edits and deliberate deletions under their existing contract. Receipt withdrawal removes success evidence for this failed phase, not files or arbitrary shell effects. Catchable exceptions receive withdrawal; a hard process kill can leave provisional receipts, as already documented by ADR 0023. Do not promise crash rollback or rewrite Git commits. The recovery command is the same blueprint run after correcting the underlying failure.


## Interfaces and Dependencies

This is a standalone CLI behavior fix using existing core operations and manifest records. No dependency upgrade, new schema field, migration, provider protocol, or producer release is required. `ComposedPlan.operations`, `AppliedComposition.commandReceipts`, and the current application ID remain authoritative. `planCommands RunAllCommands prior operations` decides the command list; `expectedCommandReceipts` and `finalizeCommandReceipts` build success and failure maps; `withReceiptWithdrawal` protects the phase; and `executeCommandPlanWithOutput` runs the shell in the declared working directory.

Keep core `executePlan` a file executor. Keep normal Run and Update receipt semantics intact. If a shared helper is introduced, specify its actual signature and caller responsibilities here after implementation. Blueprint success/provenance remains owned by `handleBlueprintRun` after the baseline and provider succeed. The skill's provenance scripts record authorship updates; never hand-edit their frontmatter block.
