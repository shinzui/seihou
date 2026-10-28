---
id: 111
slug: run-blueprint-migrations-without-an-interactive-terminal
title: "Run blueprint migrations without an interactive terminal"
kind: exec-plan
created_at: 2026-10-27T20:44:30Z
intention: "intention_01m5zhn5pqe2hb12yxq9gyvqs0"
provenance:
  created_by:
    model: "gpt-6.1-sol"
    harness: "codex-cli"
    at: 2026-10-27T20:44:30Z
  reviews:
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-10-28T02:34:17Z
      verdict: "changes-requested"
      note: "Specify structured refusal and malformed-response handling before receipt creation; require real editing evidence for both CLI providers."
  revisions:
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-10-28T02:44:35Z
      mode: "update"
      note: "Define strict batch result validation before receipts and require independent authenticated Claude and Codex consumer proofs."
---

# Run blueprint migrations without an interactive terminal

This ExecPlan is a living document. Keep Progress, Surprises & Discoveries, Decision Log,
and Outcomes & Retrospective current. Implementation includes delivery to the reporting
consumer and amendment of its friction entry after verification.


## Purpose / Big Picture


A developer or coding agent can run `seihou agent migrate keiro-upgrade --from 0.21.0.0
--to 0.22.0.0` through ordinary pipes, without allocating a pseudo-terminal or manually
exiting a child session after each edge. Seihou selects a non-interactive CLI invocation,
allows the migration to edit the intended workspace, records each completed edge, and
returns success or an actionable failure. A pseudo-terminal (PTY) is an operating-system
interface that makes a process believe it owns a terminal; callers should not need to
know about it to run this command.

The starting state is an existing Seihou consumer with an installed migration blueprint
and an authenticated local Claude Code or Codex CLI. Normal adoption consists of updating
Seihou through the user's established installation method, then running the same migration
command. No blueprint rewrite, manual manifest edit, additional provider setup, trailing
instruction, or new required flag is part of adoption. With terminal input, keep the
existing interactive session behavior; offer `--batch` to request non-interactive execution
explicitly. Existing configuration and `--var` overrides remain available for blueprint
inputs. A fresh worktree uses the same command once its ordinary documented prerequisites
are present. A repeated invocation skips applied receipts and resumes outstanding work.

The source report is
`mori://tan/notification-hub/okf/friction-log/concepts/FRIC-2`. It describes an interactive
Claude process waiting silently for more than five minutes when launched through pipes.
Its current `resolved` status records a PTY workaround, not a product fix. Completion of
this plan requires replacing that resolution with evidence of the delivered fix.


## Progress


- [ ] Milestone 1: the ordinary migration command selects batch CLI execution through pipes, with separate authenticated consumer proofs and focused real-binary regressions for both Claude and Codex.
- [ ] Milestone 2: automated execution preserves workspace access, edge ownership, outcomes, stop/resume behavior, and interactive behavior under the migration regression suite.
- [ ] Milestone 3: shipped help and guides explain mode selection and recovery, relevant ADR context is recorded, and source/build/documentation checks pass.
- [ ] Milestone 4: a delivered executable passes the reporting consumer workflow with both CLI providers, and the original FRIC-2 resolution records that the product fix addressed the friction, with version and evidence.


## Surprises & Discoveries


Review finding (2026-10-27): the existing completion wrapper returns only an error or
assistant text. The inspected Codex adapter skips malformed JSON lines, and the wrapper
accepts nonempty text when no provider error survives conversion. Reusing that interface
without preserving structured run evidence cannot establish the required refusal and
protocol-failure checks before receipt creation. Source inspection is not proof of how
every installed provider version behaves; capture versioned fixtures during implementation.


## Decision Log


Decision (2026-10-27): match `agent run`: select batch execution when stdin is not a
terminal, or when `--batch` is supplied. Keep terminal-backed invocations interactive.
This makes the normal command own the reported workflow without requiring a PTY wrapper.
Redirecting only stdout does not select batch; document the explicit flag for that case.

Decision (2026-10-27, refined by the review revision below): reuse Seihou's existing
CLI-access configuration, with a strict migration-specific result boundary.
A text-only provider call that cannot edit the workspace does not meet acceptance. Prove
actual file edits with each authenticated CLI early. If the existing boundary cannot honor
workspace access or fails to return safely, correct that boundary within this plan;
consult Baikai's source and unattended-run surface before choosing a larger dependency
change. Do not solve missing approvals with bypass-permissions or unrestricted sandbox flags.

Decision (2026-10-27): missing initial user instructions must not turn a batch migration
into an empty-prompt error. Coordinate the neutral CLI prompt policy already specified by
`docs/plans/106-supply-default-initial-instructions-to-cli-agent-providers.md`; implement
or reuse the required shared resolver rather than requiring a positional workaround.
This plan owns the migration acceptance obligation even while plan 106 remains open.

Decision (2026-10-27): amend the reporting repository's existing entry only after delivery
and consumer verification. Its profile supports `resolved`, not an `addressed` status.
Keep `resolved`, record explicitly that the cause is addressed by the product fix, preserve
historical observations/workaround and authorship, and append the new resolution evidence.
Do not mark the report fixed during plan creation or after source-only tests.


Decision (2026-10-27, review revision): batch migration success requires a validated
provider result before outcome-marker parsing or receipt creation. Preserve process exit,
protocol validity, terminal completion, and explicit provider error/refusal evidence until
that decision is made. Assistant prose alone cannot establish success. Use a migration-specific
strict boundary so ordinary completion callers retain their existing contract.

Decision (2026-10-27, review revision): Claude and Codex each need an authenticated edit,
receipt, and repeat-run proof from a fresh consumer checkpoint, both early and after delivery.
A missing executable, authentication, or supported protocol leaves that provider's acceptance
and the containing milestone open; success with the other provider cannot substitute.


## Outcomes & Retrospective


(To be filled during implementation.)


## Context and Orientation


A blueprint is an installed Dhall description and prompt material for an agent task.
A migration edge describes one library version transition. A receipt is a record in
`.seihou/manifest.json` saying that an edge was applied or was not applicable. CLI providers
start local `claude` or `codex` processes; API providers contact a remote model service.
Batch execution here means a CLI process that receives a complete request, performs its
work without terminal input, and exits so Seihou can inspect its result.

`seihou-cli/src-exe/Seihou/CLI/Commands.hs` defines `BlueprintMigrationOpts` and
`agentMigrateParser`. It currently has no migration `batch` field or flag, although
`BlueprintRunOpts` and `agentRunParser` do. `seihou-cli/src-exe/Seihou/CLI/AgentRun.hs`
checks `hIsTerminalDevice stdin` and uses `runRenderedAgentPromptMode` to select interactive
launch or `runAgentCompletionWithCliAccess`.

`seihou-cli/src-exe/Seihou/CLI/AgentMigrate.hs` discovers the requested and entailed
blueprints, resolves the version window, filters receipts, and prepares each owner's
execution context before launching anything. Its `launchMigration` always sends
`AgentProviderClaudeCli` and `AgentProviderCodexCli` to `launchInteractive`; only the API
providers use `launchCompletion`. `launchConfiguredAgentAddingDirs` in
`seihou-cli/src-exe/Seihou/CLI/AgentLaunchExec.hs` constructs interactive Baikai requests.
Changing every interactive launcher globally would affect unrelated agent commands and
is unnecessary for this migration-specific fix.

`seihou-cli/src/Seihou/CLI/AgentCompletion.hs` provides
`buildAgentCompletionRequestWith` and `runAgentCompletionWithCliAccess`. The latter
registers local providers with the current working directory, blueprint tool permissions,
and extra readable directories. Its Claude arguments include `--allowedTools` and
`--add-dir`; Codex receives `--sandbox workspace-write` and `--add-dir`, together with
Seihou kit session arguments. The source currently passes an omitted user prompt through
as no user message, so mode selection alone is insufficient proof of a usable migration.
Its `Either Text Text` result also discards structured execution evidence. Add the strict
migration boundary described below in this module, retaining the existing wrapper for
other callers. A parser that has already discarded failure information is not a suitable
input to the strict boundary.

`seihou-cli/src/Seihou/CLI/BlueprintMigration.hs` owns the sequential runner and outcome
signal parsing. `seihou-cli/src/Seihou/CLI/AppliedBlueprintMigration.hs` writes receipts.
An interactive session reports inapplicability through a temporary signal file; a completion
can also return a marker line. `launchMigration` must continue to clear stale signals and
ignore signals from failed sessions. `seihou-cli/test/Seihou/CLI/AgentMigrateE2ESpec.hs`
contains process-level migration fixtures and existing batch tests for `agent run`.
`seihou-cli/test/Seihou/CLI/BlueprintMigrationSpec.hs` covers runner ordering and filtering;
`seihou-cli/test/Seihou/CLI/AgentCompletionSpec.hs` covers provider dispatch.
`seihou-cli/test/Seihou/CLI/SeihouBinary.hs` locates the executable built with the suite.

Relevant local ADRs were discovered by scanning filenames and headings. Preserve
[ADR 0007](../adr/0007-a-deliberate-no-op-is-a-third-outcome-not-a-success.md): not-applicable
attempts are recorded but do not suppress retries. Preserve
[ADR 0008](../adr/0008-an-entailed-migration-edge-is-owned-by-the-blueprint-that-declares-it.md):
each edge uses its declaring blueprint's tools, references, variables, and receipt identity.
[ADR 0011](../adr/0011-a-migration-receipt-asserts-a-claim-about-the-project.md) explains why
provider return is not proof that a build passes, and why `--mark-applied` remains a
provider-free user assertion. Follow
[ADR 0015](../adr/0015-diagnostics-name-things-as-users-do-and-never-fall-back-to-show.md)
for cause-specific human diagnostics. No existing ADR defines terminal mode selection.
Record that durable policy during implementation using the existing local ADR format.

Dependency discovery through Mori found `mori://shinzui/baikai`, whose CLI guide is
`mori://shinzui/baikai/docs/cli-providers` and interactive guide is
`mori://shinzui/baikai/docs/interactive-launches`. The located Claude and Codex adapters
render `claude -p --output-format json` and `codex exec --json`, respectively, and accept
extra arguments and a working directory. The guides distinguish ordinary completions from
unattended editing; acceptance must prove the editing behavior Seihou's access wrapper
promises. Source locations within `mori://shinzui/baikai` are
`baikai-claude/src/Baikai/Provider/Claude/Cli.hs` and
`baikai-openai/src/Baikai/Provider/OpenAI/Cli.hs` (artifact-level source URIs pending).

At planning time, the installed executable reports `seihou v0.11.0.1 (4ade3fb)` and the
source package is 0.11.0.1. This is baseline information, not a claim the fix is installed.
The Seihou working tree already has a modified `schema` submodule; preserve it. The
reporting consumer is `mori://tan/notification-hub`; its migration context is
`mori://tan/notification-hub/plans/109-upgrade-to-keiro-0-22-and-nix-haskell-flake-0-36-0`.
Its commit `474ce4a` selects the new dependencies before the following commit performs
the source migration. Verify that checkpoint before using it for an isolated replay.
Mori's current registry does not yet index that consumer's friction bundle: the intended
canonical FRIC-2 URI above fails resolution, but the entry and declaration in the consumer
working tree exist. Do not replace it with an ambiguous cross-repository filename.


## Plan of Work


### Milestone 1: make the ordinary command execute through pipes


Before expanding test coverage, use an isolated copy of the consumer checkpoint to
reproduce the launch choice, then exercise real editing migrations through pipes with
each provider in a separate fresh worktree at the same checkpoint.
Capture the original executable version, invocation, and observed launch. Bound the
pre-fix reproduction and terminate only its owned process tree; there is no need to wait
another five minutes after the interactive launch is established. Do not run a replay
against the reporting consumer's already migrated main working tree.

Add `batch :: Bool` to `BlueprintMigrationOpts` and its parser, mirroring `agent run`.
Compute the effective mode once in `handleAgentMigrate` using the explicit flag and stdin
terminal state, then pass it to `launchMigration`. Leave `--debug`, `--mark-applied`, and
no-work paths provider-free. Route CLI providers in batch mode through
`runAgentMigrationCompletionWithCliAccess`, the new strict boundary in
`seihou-cli/src/Seihou/CLI/AgentCompletion.hs`, with only the current edge owner's mounted
files and allowed tools. Reuse the existing access-argument and request construction,
while retaining structured provider evidence until the success decision. Keep the API
branch and terminal-backed interactive branch coherent with the existing behavior. Reuse the one trace sink created for the command.

Implement or reuse `resolveAgentInitialPrompt :: AgentProvider -> Maybe Text -> Maybe Text`
in `seihou-cli/src/Seihou/CLI/AgentCompletion.hs`, following plan 106: omitted or blank CLI
instructions become `Follow the instructions in the system prompt.`; nonblank instructions
are preserved exactly, and API inputs retain their current meaning. Apply it at the
necessary dispatch boundaries and make migration preview truthful about its effective
instruction. Preserve the raw user argument in stored provenance.

Add a focused real-binary test in `AgentMigrateE2ESpec.hs` for each CLI provider using
piped stdin, no positional instruction, and no `--batch`. The fake provider must reject
interactive argv, log its actual inputs, edit a workspace file, and return the actual
provider's supported response format. Assert exit zero, the edit, and the receipt. Bound
test execution and clean up the owned child process tree so a regression fails promptly.
A fake file edit proves wiring; separate early authenticated consumer runs must prove
that both Claude and Codex really perform edits. Record each executable/version, effective
model, invocation, changed files, per-edge receipts, exit status, and repeat-run no-work
result. Never reuse one provider's migrated worktree to test the other. If permission or
transport behavior blocks either proof, repair it before expanding the remaining test
matrix; if credentials are unavailable, record that provider as unverified and keep
Milestone 1 open.

Before accepting the first receipt, implement and exercise the structured success contract
in Interfaces and Dependencies. Obtain versioned result fixtures from the supported local
CLIs and their authoritative protocol documentation, including errors and refusals. Verify
that the selected transport exposes all required fields. If Baikai's completion conversion
loses them, implement a narrow migration-specific subprocess adapter using existing process
support, or a verified upstream structured-result interface; do not inspect flattened prose
for words such as “denied”. Keep raw protocol validation separate from outcome-marker
parsing and preserve the existing single trace destination.


### Milestone 2: preserve migration lifecycle and interactive use


Extend the existing migration fixtures rather than building a second runner. Check explicit
`--batch`, explicit initial instructions, per-owner tools/references, configured model and
effort, and Codex kit arguments. Existing tests that assert interactive argv while using
`readCreateProcessWithExitCode` will now exercise batch mode: update their expectations,
and use a genuine temporary PTY for the tests intended to prove interactive behavior.
Do not weaken those tests to accept either mode. A terminal-backed run must keep the
existing interactive launch, while `--batch` under the same terminal must select batch.

Exercise a multi-edge chain where the first edge succeeds and the second fails. The first
receipt must survive, the second must remain pending, and later edges must not start.
Retry the same command and verify only pending edges run. Verify not-applicable outcomes
from the completion marker and the signal file, the existing precedence between them,
and stale/failed signal cleanup. Include an entailed edge whose owner differs from the
invoked blueprint, using distinguishable tool lists and reference directories.

Missing executables, provider errors, permission refusals, malformed or empty responses,
and receipt-write failure must return nonzero with a useful cause and recovery action.
Do not report success or write an applied receipt for a refused or failed child. Add
fixtures with nonempty assistant text followed by a provider failure, an explicit permission
denial in an otherwise successful result, malformed JSON after valid assistant text, and
truncated output lacking the provider's successful terminal result. Each must fail without
any receipt for that edge, even if a not-applicable marker or signal file also exists.
Include a successful response containing harmless unknown fields/events to prove forward
compatibility does not depend on accepting corrupt protocol data. Required
blueprint variables must either resolve through the existing normal configuration path or
fail promptly with the needed `--var KEY=VALUE`; no hanging input prompt is acceptable.
Use existing variable checks where sufficient and fix a demonstrated migration blocker
within this plan. Debug, no-work, and mark-applied tests must prove no child was spawned.


### Milestone 3: document and validate the supported workflow


Update the parser help in `Commands.hs`, `docs/cli/agent.md`,
`docs/user/blueprint-migrations.md`, and `seihou-cli/help/agent.md`; reconcile related
claims in `docs/user/agent-assistance.md` and `seihou-cli/help/blueprints.md` if they
promise interactive-only migration behavior. State automatic selection by stdin,
explicit `--batch`, authentication/input prerequisites, the preserved permission limits,
and ordinary retry behavior. Explain that interactive sessions still require normal exit
before an edge receipt is recorded, while batch processes return on completion. Default
progress output must identify the effective mode and current edge before launching it,
without claiming that a quiet provider is hung or that receipt creation proves correctness.

Add engineering and user release notes in `CHANGELOG.md` and `docs/user/CHANGELOG.md`.
Distill terminal selection and safety constraints into the appropriate local ADR. Run the
focused checks, full CLI suite, build, documentation audit, and repository checks below.
Record exact results and baseline failures rather than broadening this task to repair
unrelated pending schema or test-stack work.


### Milestone 4: deliver and address the original report


Use the repository's release workflow in `agents/skills/release/SKILL.md` when packaging
and publishing are authorized; otherwise keep this milestone open with the concrete
remaining delivery step. Do not describe an unreleased source build as installed delivery.
Verify the fixed executable using the user's normal installation path, then repeat the
isolated consumer migration through pipes with both authenticated providers, each in a
new worktree at the original checkpoint. Also verify the unchanged ordinary command under
the reporting consumer's normal provider configuration. Record
Seihou's version/commit/path, local provider version, exit status, resulting file changes,
per-edge receipts, and the second-run no-work result. Use existing consumer checks for the
files that the migration actually changed. No service deployment or persistent database
migration is needed to validate this CLI launch fix.

Finally amend FRIC-2 in its recording repository with the bundled friction script. Its
`resolution` must say the cause is addressed by the fixed Seihou version and describe
non-terminal automatic execution, with a canonical link to this plan and concise consumer
evidence. Keep `status: resolved` and append authorship through the script; retain the
original five-minute observation and PTY workaround as history. Validate the consumer's
friction bundle and inspect its generated index/log. This is the requested closure; a
Seihou-only retrospective cannot substitute for it.


## Concrete Steps


Work from the Seihou root. Resolve identity again in the implementation session and record
one provenance revision with `record-provenance.ts --mode implement`. The intention in
frontmatter is authoritative; do not ask again. Use Conventional Commits on the current
branch and include `ExecPlan: docs/plans/111-run-blueprint-migrations-without-an-interactive-terminal.md`
and `Intention: intention_01m5zhn5pqe2hb12yxq9gyvqs0` trailers in each implementation commit.
For a commit in the consumer, use the canonical plan URI in the ExecPlan trailer.

```bash
cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
git status --short
mori registry search baikai
mori registry show shinzui/baikai --full
mori registry docs shinzui/baikai
cabal build exe:seihou
cabal list-bin exe:seihou
seihou --version
```

Read the dependency sources at Mori's returned location before changing provider-facing
code, including `mori://shinzui/baikai/docs/unattended-agent-runs`. Existing dependencies
are the starting point, but their ability to preserve the strict result contract must be
verified; do not change bounds or pins speculatively. If a dependency change becomes
necessary, first verify the current released packages in the authoritative registry and upstream tags, then record the reason.
Do not search or traverse `/nix/store` or the filesystem root.

Create a detached disposable worktree for the real consumer proof. This reproduces existing
state rather than hand-repairing a fixture. Inspect the checkpoint's manifest and migration
prerequisites; record every preparation action. Install any missing blueprint only through
the consumer's existing documented public installation command. Preserve the source
consumer's working tree and retain the replay directory until its evidence is recorded.

```bash
seihou_source="$PWD"
fixed_seihou="$(cabal list-bin exe:seihou)"
consumer_root="$(mori path mori://tan/notification-hub)"
replay_parent="$(mktemp -d -t seihou-migration-replay)"
replay_project="$replay_parent/notification-hub"
git -C "$consumer_root" show --stat 474ce4a
git -C "$consumer_root" worktree add --detach "$replay_project" 474ce4a
cd "$replay_project"
"$fixed_seihou" --version
"$fixed_seihou" agent --debug migrate keiro-upgrade --from 0.21.0.0 --to 0.22.0.0
"$fixed_seihou" agent migrate keiro-upgrade --from 0.21.0.0 --to 0.22.0.0 </dev/null
"$fixed_seihou" status
"$fixed_seihou" agent migrate keiro-upgrade --from 0.21.0.0 --to 0.22.0.0 </dev/null
git diff --stat
cd "$seihou_source"
```

Run this from an execution tool with PTY allocation disabled. The debug command must show
pending steps without writing receipts; the first real run must edit the project and
return; the second must report that all selected migrations have receipts and launch no
provider. No `--rerun`, `--mark-applied`, extra instruction, or PTY may manufacture this
proof. This block proves the unchanged command under the consumer's normal configuration.
Count the ordinary run toward its verified effective provider. For the other provider,
repeat the entire block in a fresh worktree, adding `--provider claude-cli` or
`--provider codex-cli` immediately after `agent` on each debug and migration invocation.
If the ordinary run uses an API provider, run both explicit CLI cases in fresh worktrees. These are validation selectors, not new adoption requirements.
Capture `claude --version` or `codex --version` and the effective configuration for each
run; do not let ambient model/effort settings select an incompatible model for the other
provider. Record any explicit supported model selection as validation setup. Repeat the ordinary command and both provider proofs with the delivered executable in Milestone 4, creating fresh replay directories
rather than reusing applied receipts. An installed blueprint cache
is an ordinary documented prerequisite, not something these commands pretend to create.
If it is unavailable, count its normal installation as a preparation step and verify that
the instructions actually work; do not silently copy a privileged local artifact.

Run focused checks while developing, followed by the final coherent checks once:

```bash
cabal test seihou-cli-test --test-options='--pattern "Agent migrate end-to-end"'
cabal test seihou-cli-test --test-options='--pattern "Seihou.CLI.BlueprintMigration"'
cabal test seihou-cli-test --test-options='--pattern "Seihou.CLI.AgentCompletion"'
cabal run seihou -- agent migrate --help
cabal build all
cabal test seihou-cli-test
just audit-cli-docs
nix fmt
nix flake check
git diff --check
```

Tests must report PASS and help must contain `--batch` and explain automatic non-terminal
selection. The new regression must fail on the pre-change launcher and pass on the fixed
one; record the reason, not a dump of every successful assertion. If the shell lacks the
project toolchain, run these checks through `nix develop --no-write-lock-file -c`.
A required check with a pre-existing failure stays explicitly unaccepted until the failure
is resolved or its limitation is agreed; never relabel a blocked gate as passing.

After delivery, set `fixed_version` to the exact version string just verified and execute
the following from Seihou. Runtime provenance must belong to the implementing session;
replace the model argument if current metadata identifies a different model.

```bash
consumer_root="$(mori path mori://tan/notification-hub)"
bun agents/skills/exec-plan/record-friction.ts update \
  --bundle "$consumer_root/docs/friction-log" \
  --id FRIC-2 --status resolved \
  --resolution "Addressed by $fixed_version: CLI migrations automatically run without terminal input; the consumer migration and repeat invocation passed. See mori://shinzui/seihou/plans/111-run-blueprint-migrations-without-an-interactive-terminal." \
  --change "Replaced the PTY workaround resolution with verified product-fix and installed-consumer evidence." \
  --model gpt-6.1-sol --harness codex-cli
okf validate "$consumer_root/docs/friction-log" --strict \
  --profile "$consumer_root/docs/friction-log/profile.dhall" \
  --profile-enforce --log-enforce
git -C "$consumer_root" diff -- docs/friction-log
```

Add concise exact consumer evidence to the amendment or entry body as needed; do not
hand-edit generated authorship metadata. Do not execute this closure command during
planning. Discover and honor consumer-local AGENTS.md instructions before writing there.


## Validation and Acceptance


The decisive behavior is the reported command, with ordinary authenticated CLI prerequisites,
through pipes and without a trailing instruction: it edits the intended workspace and returns,
then the second run finds the applied receipts. This must be proved with the real consumer
checkpoint early and with the delivered executable at completion, separately for Claude
and Codex in fresh worktrees, including the unchanged command under the reporting
consumer's normal configuration. That ordinary run may also satisfy its effective CLI
provider's matrix entry. Record source-build, released, and installed evidence separately
for each provider. Unavailable authentication or an unsupported provider leaves its proof
and the containing milestone open. A debug run, fake process, or process exit
alone does not prove a working real migration.

Real-binary automated tests must show Claude receives `-p` and Codex receives `exec` in
automatic batch mode, while a genuine terminal retains interactive argv and explicit
`--batch` overrides it. Capture request content to verify system and initial prompts,
model/effort, and only the declaring owner's reference directories and tools. Codex must
retain workspace-write and kit configuration; no unrestricted permission flags may appear.
A CLI lacking a user prompt must receive the neutral initial instruction; explicit nonblank
instructions must be preserved exactly. Keep API dispatch behavior covered by existing
provider-stub tests without real network requests.

For an applied first edge and failed second edge, assert exactly one applied receipt,
no third launch, a nonzero exit, and a cause-specific error. A retry must skip the first
and complete the rest. A not-applicable result must record its reason and remain eligible
on a later run. A failed provider cannot leave a success receipt or reuse an old signal.
Nonempty assistant text never overrides an explicit failure/refusal, malformed protocol,
or missing successful terminal result. The adversarial fixtures in Milestone 2 must each
return nonzero, leave the failing edge without any receipt, consume its signal, and stop
the chain. Unknown well-formed events may be ignored only when they do not replace a
required terminal result; malformed protocol lines may not be silently skipped.
A receipt-write failure stops the chain and says source edits may already exist. Debug,
no-work, and `--mark-applied` must not start a provider; debug must leave manifest bytes
unchanged. Existing guard and cohort tests must remain meaningful after their fixture
stdin begins selecting batch automatically.

Help and human output must let the user understand the chosen mode, current edge, final
success/failure, and exact next action without reading source or JSON. Provider startup
must not wait for terminal interaction when none exists. The focused regressions, full CLI
suite, build, documentation audit, formatter, flake check, and whitespace check form the
source gate. The original FRIC-2 amendment and strict consumer bundle validation form the
closure gate. Keep Milestone 4 open until the fixed executable is usable by the reporting
consumer and the entry records that evidence.


## Idempotence and Recovery


Mode detection and the new flag write no state by themselves. Receipt filtering and
`--rerun` retain their existing meanings. Batch work is not transactional: a failed child
can leave edits even though no receipt was written for that edge. Preserve earlier
successful receipts, inspect partial edits, repair the reported problem, and rerun the same
command. Never erase receipts or mark an edge applied to make acceptance pass.

Run automated tests in temporary project/config/cache directories with fake executables
at the front of PATH and inherited `SEIHOU_AGENT_*` settings scrubbed. Tests contact no
real model. The separate authenticated consumer replay uses only its disposable worktree;
do not reset or clean the original project. Keep test/reproduction deadlines and child
cleanup scoped to processes owned by the check, without blanket process kills. Remove a
replay worktree only after saving evidence and confirming it contains no work to retain.

The friction update appends an amendment and regenerates index/log; inspect its diff
before committing. If validation fails after a write, fix and revalidate the existing
entry rather than creating a duplicate or weakening the profile. Its historical generated
record and observation remain intact. A release or installation gap is an open delivery
milestone, not a reason to close the consumer's report early.


## Interfaces and Dependencies


`BlueprintMigrationOpts` gains the migration-only `batch` switch and the parser/help expose
`--batch`. `handleAgentMigrate` computes effective batch mode once; `launchMigration`
receives that choice explicitly. These are executable-internal interfaces. Update their
construction sites together; no manifest format, migration planner, receipt identity,
blueprint schema, or artifact upgrade is required.

Keep the existing completion interface for ordinary callers and add a strict migration
interface in `seihou-cli/src/Seihou/CLI/AgentCompletion.hs`:

```haskell
runAgentCompletionWithCliAccess
  :: [FilePath] -> [String] -> AgentCompletionRequest -> IO (Either Text Text)

runAgentMigrationCompletionWithCliAccess
  :: [FilePath] -> [String] -> AgentCompletionRequest -> IO (Either Text Text)

resolveAgentInitialPrompt :: AgentProvider -> Maybe Text -> Maybe Text
```

The first signature already exists. The new migration function may return `Right` only
after checking the full structured run result; its text result is a validated projection,
not a substitute for validation. Internally retain process exit status, protocol validity,
terminal outcome, explicit provider errors, permission denials, and assistant text until
classification finishes. Map failure to `Left` with a cause and recovery action; the caller
clears the signal and maps it to `BlueprintMigrationProviderFailure` before returning to
the sequential runner. Keep the existing public wrapper's behavior for unrelated callers.

For Claude, require a decodable final result with a successful outcome, `is_error` false,
no reported permission denials, and nonblank result text. For Codex, validate the JSON event
stream through a successful terminal turn result, requiring nonblank assistant text and
no explicit run error, failed turn, or reported permission denial. Verify the exact field
and event shapes against the supported executable versions before coding the adapters;
record those versions alongside fixtures. Exit failure always wins, even after useful text.
Missing required result fields, malformed protocol, or an absent terminal result are protocol
failures. Ignore unknown well-formed fields/events only while retaining all required checks.
A reported denial conservatively fails this attempt even if the agent later reports success;
the developer inspects partial edits, fixes permission configuration, and retries. Do not
claim to detect semantic refusal expressed only in arbitrary prose or to verify migration
correctness from the response; consumer checks remain necessary under ADR 0011.

Only a validated `Right` reaches `sessionResultFromSignal`, where the existing signal-file
over-text-marker precedence determines applied versus not-applicable. Neither channel may
rescue a failed or unvalidated run. The final signature is the shared initial-instruction
policy specified by plan 106 and must be reused if that plan lands first. Keep the three
interactive launcher signatures intact and retain existing API dispatch behavior.

Use existing Baikai, `directory`, `process`, `text`, and test dependencies initially.
No bounds or pin change is proposed. If genuine provider execution demonstrates that an
unattended-run adapter is necessary, use Mori to inspect `mori://shinzui/baikai` and verify
released versions before recording the revised interface and delivery requirements here.
That is work toward this plan's existing editing acceptance, not a separate task the user
must commission. The report's owner remains `mori://tan/notification-hub`; use canonical
cross-repository references in amendments, commits, and durable documentation.


Revision note (2026-10-27): addressed the review by defining a strict migration result
boundary before receipt creation, adversarial protocol/refusal regressions, and separate
real Claude and Codex proofs from fresh consumer checkpoints at source and delivery stages.
The prior review remains in provenance as history; these edits do not claim implementation
or provider validation has passed.
