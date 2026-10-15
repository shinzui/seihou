---
id: 106
slug: supply-default-initial-instructions-to-cli-agent-providers
title: "Supply default initial instructions to CLI agent providers"
kind: exec-plan
created_at: 2026-10-15T15:15:20Z
intention: "intention_01m5023936ehpvf6k7aaf29zge"
provenance:
  created_by:
    model: "gpt-6.1-sol"
    harness: "codex-cli"
    at: 2026-10-15T15:15:20Z
---

# Supply default initial instructions to CLI agent providers

This ExecPlan is a living document. Keep Progress, Surprises & Discoveries, Decision Log,
and Outcomes & Retrospective current. This plan implements
[IR-6](../improvement-requests/supply-an-initial-instruction-to-cli-providers.md).


## Purpose / Big Picture


A user can run `seihou agent migrate my-library` without supplying a trailing instruction
and each CLI agent session receives a request to start following its system prompt. The
same default applies to blueprint runs, including `--batch`, and other Seihou commands
that use the shared CLI launch boundaries. An explicit nonblank user prompt wins exactly
as supplied. API providers retain their existing optional-message behavior.

The visible default instruction is `Follow the instructions in the system prompt.` It
starts the task already described by Seihou; it adds no migration scope, permissions,
completion claims, or instruction to ignore an edge's preconditions. Fake executables and
provider stubs will prove this without contacting a model. Migration debug output will show
the effective initial instruction so the user can inspect the fallback before execution.


## Progress


- [ ] Milestone 1: define the shared CLI initial-prompt policy and apply it to batch completion requests, with context-capture tests for all four providers.
- [ ] Milestone 2: apply the same policy to interactive launch and migration preview, with real-binary fake-provider proofs for Claude and Codex.
- [ ] Milestone 3: prove migration-chain, explicit-prompt, batch, debug, and manifest-provenance behavior end to end.
- [ ] Milestone 4: document the behavior, distill the launch-policy decision into an ADR, run final gates, and complete IR-6 with evidence.


## Surprises & Discoveries


(To be filled during implementation.)


## Decision Log


Decision (2026-10-15): supply the neutral fallback at Seihou's provider boundaries, using
one policy exported from the existing private CLI library. Apply it to `claude-cli` and
`codex-cli` only. Seihou owns the optional user argument and knows whether a provider is a
CLI; the existing Baikai request types can already carry the instruction. A dependency
change or a required positional argument would be unnecessary for this fix.

Decision (2026-10-15): a missing or whitespace-only prompt counts as omitted for CLI
providers. Use stripping only to classify blank input; return every nonblank prompt byte
for byte, including leading/trailing whitespace and newlines. For API providers return the
original `Maybe Text`, including `Nothing` and explicit blank text, unchanged.

Decision (2026-10-15): keep the user's raw prompt in options, completion-request records,
and manifest provenance. Resolve the fallback only when constructing the provider's
message or interactive request. A synthesized start instruction is not user-authored
context and must not appear as `AppliedBlueprint.userPrompt` when the user omitted it.

Decision (2026-10-15): make the migration preview display its effective initial instruction,
using the same resolver as execution. Other commands retain their existing debug display
contract; this change does not turn `agent run --debug` into a dry run. An API migration
with no user prompt still has no initial-instruction block.

Decision (2026-10-15): use a provider-independent sentence within the two CLI adapters.
Specialized defaults at every command call site would repeat the policy, and inventing a
migration-specific task in the shared launcher could misdirect assist/setup/prompt runs.
`agent upgrade` already provides a nonblank, command-specific default; preserve it.


## Outcomes & Retrospective


(To be filled during implementation. This is a plan, not evidence that IR-6 is fixed.)


## Context and Orientation


A system prompt is the rendered task context, rules, references, and, for migrations, the
instructions for one version edge. The initial user prompt is a separate message telling
the session what to do. A CLI provider runs a local `claude` or `codex` process; an API
provider sends a request directly through the Baikai library. An interactive launch gives
the local process ownership of the terminal. A batch completion returns assistant text to
Seihou. These are separate execution paths and both need the default.

The original IR-6 report observed seihou 0.7.0.0 failing under `claude -p` in August 2026.
The current tree is different. `seihou-cli/src-exe/Seihou/CLI/AgentMigrate.hs`, in
`launchMigration`, routes Claude and Codex through `launchConfiguredAgentAddingDirs`, and
routes API providers through `runAgentCompletion`. Do not reconstruct the historical batch
migration path or claim the old provider error has been reproduced against today's code.
The current source still demonstrates the missing instruction at both relevant boundaries.

`seihou-cli/src-exe/Seihou/CLI/AgentLaunchExec.hs` builds interactive requests. Both
`launchClaude` and `launchCodex` use `interactiveLaunchRequest (promptOrEmpty initialPrompt)`;
`promptOrEmpty` is currently `maybe "" id`. This executable module owns process handling.
`seihou-cli/src/Seihou/CLI/AgentCompletion.hs` belongs to the private
`seihou-cli-internal` library and defines `AgentProvider`, `AgentModelConfig`,
`AgentCompletionRequest`, and the builders. Its `runAgentCompletionWith` converts
`Nothing` into `V.empty` and a supplied prompt into a single `Baikai.userNow` message,
then constructs a `Baikai.Context` whose system prompt is separate. Its injectable
registration action allows tests to register a stub provider and capture that context.

`seihou-cli/src-exe/Seihou/CLI/AgentRun.hs` uses the interactive launcher for CLI
providers unless batch mode is selected; it uses the completion adapter otherwise.
`handleAgentRun` also selects batch mode automatically when stdin is not a terminal, so
an ordinary subprocess test of `agent run` is not evidence for interactive launch.
`seihou-cli/src-exe/Seihou/CLI/Assist.hs`, `Bootstrap.hs`, and `Setup.hs` share these launch
boundaries. `seihou-cli/src-exe/Seihou/CLI/PromptRun.hs` delegates to
`AgentRun.runRenderedAgentPrompt`. `seihou-cli/src-exe/Seihou/CLI/AgentUpgrade.hs` already
supplies `Upgrade <target> by following the upgrade brief in your system prompt.` when
its user argument is absent. These callers need an audit, not independent fallback strings.

`AgentMigrate.handleAgentMigrate` has a local `renderDebugStep` that currently appends an
`===== Initial user instruction =====` block only for `opts.prompt`. The per-edge
`launchMigration` receives the same raw option. The system prompts are already rendered
per owner/edge; the new start sentence must not replace or flatten those instructions.
`AgentRun` records `AppliedBlueprint.userPrompt` from raw `opts.prompt`; keep that source.
There is no new manifest field or schema change.

Existing tests live in `seihou-cli/test/Seihou/CLI/AgentCompletionSpec.hs`,
`AgentMigrateE2ESpec.hs`, `AgentTraceE2ESpec.hs`, and `AgentUpgradeE2ESpec.hs`.
`AgentMigrateE2ESpec` includes fake-process fixtures, `migrationBlueprintDhall` with two
ordered edges and a required `library.name` variable, `batchBlueprintDhall`,
`withCohortProject`, and receipt-reading helpers. `AgentTraceE2ESpec` has a fake Claude
that prints successful batch JSON. Existing fakes generally succeed even with an empty
prompt, so a passing old test does not prove IR-6 fixed. The new fake must reject an
absent/blank user request and log each invocation's arguments with unambiguous boundaries.
`seihou-cli/test/Seihou/CLI/SeihouBinary.hs` finds the executable built by Cabal rather
than an installed binary. The suite declares `build-tool-depends: seihou-cli:seihou`.

Dependency lookup used Mori to find and read
[mori://shinzui/baikai/docs/interactive-launches](mori://shinzui/baikai/docs/interactive-launches)
and [mori://shinzui/baikai/docs/cli-providers](mori://shinzui/baikai/docs/cli-providers),
plus `Baikai.Provider.Claude.Interactive`, `Baikai.Provider.Claude.Cli`, and
`Baikai.Provider.OpenAI.Interactive` in the packages
[mori://shinzui/baikai/packages/baikai-claude](mori://shinzui/baikai/packages/baikai-claude)
and [mori://shinzui/baikai/packages/baikai-openai](mori://shinzui/baikai/packages/baikai-openai).
Interactive requests already accept a user prompt. Claude batch passes its system prompt
separately; Codex batch wraps system and user text into one string. Therefore a nonempty
combined Codex argument alone is insufficient evidence that a user request was supplied.
Assert the user message in the captured context as well. Keep the current dependency
bounds; if implementation unexpectedly needs a dependency change, use Mori and verify the
released package registry version and upstream tags before selecting it.

ADR discovery inspected local filenames/headings and `mori show --full`. `docs/adr` is
not a profiled OKF bundle, so preserve its existing Markdown convention. Relevant decisions
are [ADR 0007](../adr/0007-a-deliberate-no-op-is-a-third-outcome-not-a-success.md), which
keeps not-applicable separate from applied and failure;
[ADR 0011](../adr/0011-a-migration-receipt-asserts-a-claim-about-the-project.md), which
separates recording a migration from merely completing a session; and
[ADR 0016](../adr/0016-agent-assisted-upgrade-diagnoses-read-only-and-never-fails.md),
which constrains upgrade diagnosis and session handling. A fallback must preserve all of
those rules. There is no existing ADR defining the initial-prompt fallback policy; distill
that decision during implementation without editing the concurrently proposed checkout ADR.


## Plan of Work


### Milestone 1: a shared provider policy reaches batch completions


Export `resolveAgentInitialPrompt :: AgentProvider -> Maybe Text -> Maybe Text` from
`seihou-cli/src/Seihou/CLI/AgentCompletion.hs`. For either CLI provider, return the original
nonblank `Just` value or `Just "Follow the instructions in the system prompt."` for
missing/blank input. For either API provider, return the original value. Document why this
is Seihou launch policy and why classification must not trim a real user prompt.

In `runAgentCompletionWith`, apply the resolver immediately before building
`initialMessages`. Use `req.modelConfig.provider` to select the policy. Keep the builders
and `AgentCompletionRequest.initialPrompt` raw. This also covers callers that construct a
request directly, and means no command needs to remember to normalize it first.

Extend `AgentCompletionSpec` with a context-capturing stub, parameterized by provider and
raw input. Register under the API tag selected by `buildBaikaiModel`, capture the actual
`Context` with an IORef, and return the existing successful response shape. Keep tests
sequential because Baikai's provider registry is process-global. Assert the delivered
system prompt and user-message contents, not just the helper's own answer. Cover both CLI
providers with omitted, empty, whitespace-only, and explicit multiline prompts; both API
providers with absent, blank, and explicit prompts; and preservation of the raw builder
field. Use the existing Baikai message constructors/accessors found through Mori rather
than introducing an assumed representation.

Acceptance: the focused completion tests pass and prove that an omitted CLI prompt
creates one user message, an omitted API prompt creates none, explicit nonblank text is
unchanged, and the system prompt is unchanged. Run the first focused command in Concrete
Steps. These are the regression tests for the historical batch failure.


### Milestone 2: interactive launches and migration previews use the same policy


In `seihou-cli/src-exe/Seihou/CLI/AgentLaunchExec.hs`, import the resolver and use it when
constructing Claude and Codex interactive requests. Remove the old `promptOrEmpty` helper
if unused. The final conversion from `Maybe Text` to `Text` belongs here because the
interactive request requires text; choose the correct CLI provider explicitly. Do not
change model, effort, directory mounts, allowed tools, sandbox, approval policy, process
exit propagation, or the early debug branch.

In `seihou-cli/src-exe/Seihou/CLI/AgentMigrate.hs`, derive the instruction appended by
`renderDebugStep` through the same resolver with the resolved `modelConfig.provider`.
Leave options and recorded prompts raw. API previews with no input still omit the block;
CLI previews display the shared fallback; explicit text displays unchanged.

Extend `AgentMigrateE2ESpec` to run migration fixtures with both `--provider claude-cli`
and `--provider codex-cli`. Use fake executables on PATH that capture arguments per
invocation and reject an empty user request. Claude's initial request follows `--`;
Codex combines system and user text, so check the `User request:` section specifically,
not whether its whole argument is nonempty. Confirm the fake sees the expected fallback
and the existing per-edge system instructions. An executable-library placement rule keeps
`AgentLaunchExec` out of direct library unit tests; real-binary tests are the intended
way to cover its wiring.

Acceptance: both fake interactive providers receive the fallback, explicit text survives,
and CLI debug preview displays the fallback without invoking either executable. Run the
migration focused command in Concrete Steps. A fake returning zero without inspecting its
request does not satisfy this milestone.


### Milestone 3: prove the complete command behavior and preserve provenance


Add behavior tests to the existing E2E specs rather than a new parallel fixture framework.
For each CLI provider, run a two-edge migration with no trailing prompt and assert two
launches, the fallback at each launch, the correct edge instructions in each system prompt,
and two applied receipts. Rerun the same command and assert no additional launch. Run a
fresh fixture with a nonblank, multiline user prompt and assert that exact text reaches
every edge instead of the default. Exercise a fake failure on the second edge and retain
the first receipt only, then resume at the failed edge. Retain the existing not-applicable
and entailed-owner tests as guards against changing outcome or identity semantics.

For batch execution, strengthen or extend the existing `agent run --batch` fake Claude
fixture to reject blank requests, then invoke it with no user prompt. Assert success,
a nonempty delivered fallback, and a manifest whose applied blueprint still records no
user-supplied prompt. Add the explicit-prompt counterpart, retaining the exact user text
in the manifest. The context-capture tests from Milestone 1 cover both CLI batch providers;
do not mistake Codex's nonempty combined system/user string for a valid user message.

Audit `Assist.hs`, `Bootstrap.hs`, `Setup.hs`, and `PromptRun.hs`: they already reach the
shared boundaries, so add a small table-driven fake-CLI invocation test covering their
omitted-prompt paths, supplying any fixture prompt/module variables needed. The test can
live in `AgentMigrateE2ESpec`, which already covers blueprint runs as well as migrations.
For `prompt run`, write a minimal local `prompt.dhall` fixture following the existing
PromptRenderSpec/PromptRun types. Avoid live providers. Keep `agent upgrade`'s existing
specialized default; assert it reaches the fake unchanged in `AgentUpgradeE2ESpec` if
current tests do not already capture it.

A debug migration test must assert no launch log and no manifest creation/modification.
Do not make that blanket assertion for `agent run --debug`: that command can apply a
baseline and record provenance today. Existing artifact-guard, receipt, tracing, and
failure tests must keep passing. No test needs to access the network or a real model.

Acceptance: focused suites pass; reverting either the completion-boundary change or the
interactive-boundary change makes a corresponding regression fail. Record which tests
failed under each revert and restore the implementation before the final run.


### Milestone 4: documentation, durable decision, and request completion


Update `docs/cli/agent.md`, `docs/user/blueprint-migrations.md`, and
`docs/user/agent-assistance.md` to explain that CLI providers receive the neutral start
instruction when their optional prompt is omitted/blank, while explicit prompts override
it and API behavior is unchanged. Mirror the command summary in `seihou-cli/help/agent.md`.
Update `docs/cli/prompt.md` if it describes the optional user prompt. Add concise entries
under the appropriate Unreleased sections of `CHANGELOG.md` and `docs/user/CHANGELOG.md`.

Distill the shared initial-prompt policy into a new local ADR using the existing Markdown
convention. Inspect current allocation immediately before creating it; do not reserve a
number in this plan, reuse the checkout-output ADR's number, or edit unrelated ADR work.
The decision should explain shared ownership of the policy, API compatibility, preservation
of raw user provenance, and the reason the fallback does not claim a migration succeeded.

After all acceptance evidence is recorded, set IR-6 to `completed`, add `completedAt`
using the actual verification time, keep its `targetPlan`, write a resolution describing
both current paths, and update its Status section and bundle log. Until then it stays
accepted/planned, or in-progress during implementation. Validate the bundle as below.
Fill this plan's Outcomes & Retrospective with results and limitations, update Progress,
and record one implementation provenance entry using the bundled script.

Acceptance: final build, full test suite, formatting and flake checks pass; bundle profile
and log validation pass; strict bundle validation adds no diagnostic to the baseline of
nine existing missing-reviews recommendations. Do not invent review records to silence
that unrelated baseline.


## Concrete Steps


Run all commands from the repository root. Use the project's development environment
(`nix develop`) if Cabal/GHC or formatting tools are unavailable in the current shell.
The checked-in `cabal.project` already has `tests: True`; `--enable-tests` below also
makes the intent explicit. Tests are Tasty/Hspec, so select groups with `--pattern`.

```bash
cabal test seihou-cli-test --enable-tests --test-show-details=direct --test-options='--pattern Seihou.CLI.AgentCompletion'
cabal test seihou-cli-test --enable-tests --test-show-details=direct --test-options='--pattern "Agent migrate end-to-end"'
cabal test seihou-cli-test --enable-tests --test-show-details=direct --test-options='--pattern "Agent call tracing end-to-end"'
```

Each command must report passing tests with a nonzero test count. Check that new test
names appear; a filter that selects no tests proves nothing. Discover exact other group
names with the test binary's `--list-tests` option before selecting an upgrade group.
The final validation is not limited to the focused groups:

```bash
cabal build all
cabal test all --enable-tests --test-show-details=direct
nix fmt -- --fail-on-change
nix flake check
okf validate docs/improvement-requests --profile docs/improvement-requests/profile.dhall --profile-enforce --log-enforce
okf validate docs/improvement-requests --strict --profile docs/improvement-requests/profile.dhall --profile-enforce --log-enforce
git diff --check
```

The ordinary OKF command currently prints `OK: 10 concepts (okf_version 0.2)` and exits
zero. The strict command currently exits one solely for nine existing missing `reviews`
recommendations. Capture its diagnostic set before editing and compare afterward; a new
missing completedAt/resolution or broken link is not part of that allowance. Update these
counts if concurrent request additions change the baseline, with evidence.

For a manual preview, use a temporary fixture directory containing
`.seihou/modules/payments/blueprint.dhall` with the `migrationBlueprintDhall` contents in
`AgentMigrateE2ESpec`. Run the newly built executable from that temporary directory:

```bash
seihou agent --debug --provider claude-cli migrate payments --from 1.0.0 --to 3.0.0 --var library.name=baikai
```

Here `seihou` must denote the executable built by this checkout, obtained before changing
directory with `cabal list-bin seihou-cli:exe:seihou`. Both step blocks must include:

```text
===== Initial user instruction =====
Follow the instructions in the system prompt.
```

The scratch manifest and provider log must remain absent. The automated fake-provider
cases are the authoritative reproduction and do not require installing or authenticating
Claude/Codex. A real-model run is optional and is not a completion prerequisite.

Record implementation provenance once per session at the first plan update, resolving the
current runtime identity again rather than copying this plan's author:

```bash
bun agents/skills/exec-plan/record-provenance.ts revision --plan docs/plans/106-supply-default-initial-instructions-to-cli-agent-providers.md --codex-session-file <current-agent-session-file> --mode implement --note 'Implement IR-6 initial-prompt fallback and record validation'
```

Use Conventional Commits on the current branch. Every implementation commit carries these
trailers; do not stage concurrent changes outside this plan:

```text
ExecPlan: docs/plans/106-supply-default-initial-instructions-to-cli-agent-providers.md
Intention: intention_01m5023936ehpvf6k7aaf29zge
```


## Validation and Acceptance


The decisive before/after proof is a fake CLI that exits nonzero when the initial user
request is missing. Before the boundary changes, the omitted-prompt tests fail; afterward
the same commands supply the shared start sentence and complete. A multi-edge run must
supply it on every edge, keep edge instructions distinct, write the ordinary receipts,
and skip completed edges on a repeat run. A failed edge must not acquire a receipt.

For each CLI provider, missing, empty, and whitespace-only inputs produce the fallback.
A nonblank input such as `  Follow these extra constraints.\nDo not commit.  ` reaches
the provider exactly, with no trimming or appended fallback. For both API providers,
missing remains no user message and supplied input remains unchanged. Capture the actual
Baikai context to prove that system instructions, model/effort settings, and user text are
separate and correctly preserved.

A blueprint run using a fallback must not record that synthesized sentence as the user's
prompt. A blueprint run with explicit text records the original text. No schema changes,
new configuration, permission changes, receipt-identity changes, or migration-outcome
changes are required. The provider-stub tests prove transport construction, and the fake
process tests prove executable wiring; neither is a claim about a live model's behavior.


## Idempotence and Recovery


Resolving an already resolved nonblank prompt returns the same value, so applying the
policy twice is harmless. The policy performs no IO and writes no state. Test fixtures
must use temporary project/config/cache directories, scrub inherited `SEIHOU_AGENT_*`
settings, and place only fake executables at the front of PATH. Never run migration
acceptance commands in a real consumer repository as a substitute for a fixture.

Preserve the current per-edge receipt publication and retry behavior. If a regression
test fails, fix the corresponding boundary and rerun its focused group before the final
suite. Reverting the implementation for the negative proof means reverting only this
plan's exact source hunks temporarily, then restoring them; do not use a repository-wide
reset/restore or touch other work. The current tree has separate plan-105 and checkout-ADR
edits; they are outside this plan. Mark IR-6 complete only after verification, and retain
its plan link if implementation pauses.


## Interfaces and Dependencies


The new shared interface belongs in the existing private library module
`seihou-cli/src/Seihou/CLI/AgentCompletion.hs`:

```haskell
resolveAgentInitialPrompt :: AgentProvider -> Maybe Text -> Maybe Text
```

Its provider-specific semantics are specified in the Decision Log and validation section.
Keep `AgentCompletionRequest`, `buildAgentCompletionRequest`,
`buildAgentCompletionRequestWith`, and all three interactive launcher signatures unchanged.
The raw completion request remains inspectable by existing callers; its normalization
happens only at dispatch. The executable module imports the pure library policy, so no
new executable-module placement exception or public core API is necessary.

Use the already declared `text`, `vector`, Baikai, and test dependencies. No dependency
bounds, pins, Dhall schemas, or manifest versions need changing. Dependency source and
documentation must continue to be discovered through Mori; never search the Nix store.


Revision note (2026-10-15): Created to address IR-6 against the current interactive and
batch implementations, linked to a newly created intention. The historical batch-migration
error is treated as context; acceptance proves the present launch boundaries instead.
