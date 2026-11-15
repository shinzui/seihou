---
id: 126
slug: start-interactive-blueprint-runs-with-an-initial-message
title: "Start interactive blueprint runs with an initial message"
kind: exec-plan
created_at: 2026-11-15T16:21:17Z
intention: "intention_01m7g04m37ehdryja748s5620z"
provenance:
  created_by:
    model: "gpt-6.1-sol"
    harness: "codex-cli"
    at: 2026-11-15T16:21:17Z
  revisions:
    - model: "gpt-6.1-sol"
      harness: "codex-cli"
      at: 2026-11-15T16:24:44Z
      mode: "other"
      note: "Ground IR-22 delivery in the existing shared resolver, terminal launch regressions, plan 106 coordination, and consumer acceptance."
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-11-15T18:23:33Z
      mode: "update"
      note: "Apply review: prove real interactive startup and follow-up early, isolate smoke context, and document shared-launcher scope."
    - model: "gpt-6.1-sol"
      harness: "codex-cli"
      at: 2026-11-15T19:02:01Z
      mode: "implement"
      note: "Implement shared interactive kickoff and verify terminal, display, and provenance behavior."
    - model: "gpt-6.1-sol"
      harness: "codex-cli"
      at: 2026-11-15T20:19:36Z
      mode: "implement"
      note: "Prepare patch release and installed delivery to finish the remaining acceptance."
  reviews:
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-11-15T18:23:08Z
      verdict: "changes-requested"
      note: "Source diagnosis verified; move real-provider proof before matrix expansion, verify follow-up interaction, isolate context, and name shared-launcher callers."
---

# Start interactive blueprint runs with an initial message

This ExecPlan is a living document. Keep Progress, Surprises & Discoveries, Decision Log,
and Outcomes & Retrospective current. Follow `agents/skills/exec-plan/PLANS.md`,
`agents/skills/exec-plan/ADR.md`, and `agents/skills/exec-plan/FRICTION.md` for maintenance,
durable decisions, and implementation friction. This plan delivers the interactive-blueprint
acceptance in [IR-22](../improvement-requests/start-interactive-blueprint-runs-with-an-initial-message.md)
through the shared policy owned by [plan 106](106-supply-default-initial-instructions-to-cli-agent-providers.md)
and [IR-6](../improvement-requests/supply-an-initial-instruction-to-cli-providers.md).


## Purpose / Big Picture

A developer with an installed blueprint, an authenticated CLI provider, and the blueprint's
required inputs can run `seihou agent run BLUEPRINT` and see its first turn begin without
typing a kickoff message. For example, with the provider already configured, the entire
normal workflow is `seihou agent run onboarding --var service.name=demo`. A terminal stays
interactive after that first turn. No blueprint edit, prompt wrapper, or additional adoption
command is required for existing projects or fresh worktrees.

Omitted, empty, and whitespace-only CLI prompts use the existing sentence
`Follow the instructions in the system prompt.` A nonblank explicit prompt retains its
exact text. Help, launch output, and debug rendering explain which instruction starts the
session. The manifest continues to record the original user input. API providers keep their
existing optional-message behavior.

The reported consumer is `mori://tan/tan-seihou-modules`, whose production-onboarding
session opened an empty Claude input box. Prove the fix early with a harmless installed
fixture and a terminal, then verify the reported Claude workflow. Record source-build,
installed-executable, and published-artifact evidence separately. Source tests alone do
not close delivery to the consumer.


## Progress

- [x] Milestone 1 (2026-11-15): The ordinary terminal command delivers the shared initial instruction to both interactive CLI providers, with a regression that fails against the original launcher and an early real-Claude first-turn/follow-up check.
- [x] Milestone 2 (2026-11-15): Blank and explicit inputs, debug rendering, launch guidance, and raw manifest provenance agree; batch, API, and migration behavior remain compatible.
- [ ] Milestone 3: Built-binary checks and a real Claude smoke check demonstrate automatic startup; documentation, plan 106 coordination, and consumer delivery evidence accurately state what is available.


Implementation handoff (2026-11-15): The shared launcher, blueprint guidance,
debug rendering, help, docs, ADR 0019, and IR-22 coordination are implemented.
The focused migration/blueprint group passes 39 tests, including all eight
terminal input classes with required `--var service.name=demo`, repeat runs,
raw manifest parsing, debug output, and failed-provider preservation. Final
full-suite validation passed in `nix develop` (1,788 core, 1,020 CLI, and 59 OKF
extension tests); the plain shell lacks gitleaks.
Delivery continuation (2026-11-15): the user requested completion of the plan,
including its remaining release and installation work. A 0.16.0.1 patch candidate
is prepared for all three packages, with updated internal bounds and both
changelogs. Release audit corrected stale Claude default-model docs and moved
the kickoff entry out of the previous release's user-changelog section.
The candidate passes `cabal check` for all packages, the native Nix package
build with tests, Cabal build, formatting, and flake checks. The release's full
Cabal suite passes all 2,867 tests, and the final help audit passes against
`seihou v0.16.0.1 (122c9e8)` (19 topics, 37 command pages, 6 examples,
8 provider-free renders). Haddock preparation is complete for all packages;
CLI and OKF extension documentation archives were repacked through
`just docs-tarball`. Flat module pages, documentation indexes, and absence of
colon filenames were verified. Source archives are in
`/tmp/seihou-126-release-sdist/`; core documentation is
`dist-newstyle/seihou-core-0.16.0.1-docs.tar.gz`, and dependent documentation
archives are in `dist-newstyle/repacked-docs/`. The reviewable release diff is
`/tmp/seihou-126-release-candidate.diff` and release notes are
`/tmp/seihou-126-release-notes.md`.
The user approved the 0.16.0.1 release and activation of the current Home Manager
working configuration on 2026-11-15. Release publication and installed acceptance
are now proceeding through the release skill. Preserve all pre-existing dotfiles
changes and update only the Seihou input for this delivery.


## Surprises & Discoveries


The original launcher failed both initial terminal tests: Claude argv contained
no user request; Codex's combined argument ended in `User request:` with no text.
After resolver wiring both passed. Tests capture NUL-separated argv and give
stdin a pseudo terminal, so nonempty system context cannot satisfy kickoff.
`runRenderedAgentPrompt` is also used by `prompt run`; the internal mode renderer
now receives a display name so reusable prompts say “Starting agent”, while
blueprints say “Starting blueprint”. No provider mode selection changed.

Mori remained unavailable (FRIC-19); no dependency change was needed. The first
full test invocation lacked gitleaks (FRIC-20); use `nix develop` for final gates.



## Decision Log

Decision (2026-11-15): Reuse `resolveAgentInitialPrompt` at the common interactive launch
boundary. This is the unfinished interactive slice of plan 106, not a second fallback
policy. Batch completions and migrations already use the resolver; do not reimplement
those paths or require all of plan 106's stale unchecked milestones before starting.

Decision (2026-11-15): Preserve raw options and manifest provenance. Resolve the effective
instruction only for execution and display. Preserve terminal selection, tool grants,
provider safety settings, and provider exit status. Debug remains the existing blueprint
render path, which may apply a baseline and record provenance; it is not a new dry run.


## Outcomes & Retrospective


Source behavior is implemented. Real-provider evidence on 2026-11-15 used
`dist-newstyle/build/aarch64-osx/ghc-9.12.4/seihou-cli-0.16.0.0/x/seihou/build/seihou/seihou`,
reporting `seihou v0.16.0.0 (ffb437e)`, with Claude Code 2.1.325. The exact
smoke fixture and command in Concrete Steps were run from an isolated project
and empty Seihou cache, with inherited agent settings cleared. Provider login
was already available; workspace trust was accepted for this agent-created
fixture before acceptance. Both early and final runs automatically answered
`INITIAL-TURN-STARTED`; only then was `Reply FOLLOW-UP-RECEIVED` sent, and both
sessions answered `FOLLOW-UP-RECEIVED` and exited normally through `/exit`.
The final run also printed the default-instruction launch line. No tool calls
or consumer infrastructure changes were needed.

The installed PATH executable still reports `seihou v0.16.0.0 (1965b35)` and
has not received this change. Release, installation, and the installed-binary
smoke remain required before Milestone 3 and IR-22 can close. IR-6 stays open
for its broader migration/other-command obligations. ADR 0019 now records
shared launch ownership and raw-input provenance; ADR 0026 is unchanged.
FRIC-19 is accepted because registry restoration is external to this fix;
terminal fixtures verify the existing request interface without a dependency upgrade.
FRIC-20 is resolved by using the development shell, which supplies gitleaks.

Final source gates (2026-11-15): `nix develop -c cabal build all` and
`nix develop -c cabal test all --enable-tests --test-show-details=direct` pass
all three suites (2,867 tests). The focused migration/blueprint group passes
39 cases; the full suite includes completion-context, tracing, artifact guard,
and upgrade checks. `--list-tests` confirms the existing groups, including
`Agent call tracing end-to-end` and `agent path artifact guard`.
The runtime/source docs audit passes 19 topics, 37 command help pages,
6 example modules, and 8 provider-free renders. Formatting, all four native
flake checks, `git diff --check`, and strict friction validation pass.
IR validation passes normally (22 concepts); strict validation retains exactly
the same ten pre-existing missing-review diagnostics as before this change.
No review provenance was fabricated to silence them.




## Context and Orientation

A blueprint is a rendered agent task with optional variables, reference files, baseline
modules that generate project files, and tool permissions. Its system prompt contains
those instructions. The initial user message is a separate request to begin following
them. A CLI provider starts the local `claude` or `codex` executable; an API provider
sends messages directly through Baikai, the provider integration library. Batch mode runs
without the provider's interactive terminal interface.

`seihou-cli/src-exe/Seihou/CLI/AgentRun.hs` implements `handleAgentRun` and
`runRenderedAgentPromptMode`. The handler selects batch mode when `--batch` is supplied
or stdin is not a terminal. The interactive CLI branch calls
`launchConfiguredAgentAddingDirs` from `seihou-cli/src-exe/Seihou/CLI/AgentLaunchExec.hs`.
Both `launchClaude` and `launchCodex` there currently construct an
`interactiveLaunchRequest (promptOrEmpty initialPrompt)`, where `promptOrEmpty = maybe "" id`.
This drops the kickoff message when the optional prompt is absent.

The same launcher is used by `seihou-cli/src-exe/Seihou/CLI/Assist.hs`,
`seihou-cli/src-exe/Seihou/CLI/Setup.hs`, and
`seihou-cli/src-exe/Seihou/CLI/Bootstrap.hs`, so the shared fix also starts their
omitted/blank CLI requests automatically. This is the policy already intended by
plan 106. Their separate early debug branches remain outside this blueprint-specific
display change; name that remaining work in plan 106 rather than claiming those
commands' full acceptance here.

`seihou-cli/src/Seihou/CLI/AgentCompletion.hs` already exports
`resolveAgentInitialPrompt :: AgentProvider -> Maybe Text -> Maybe Text`. It returns
the neutral sentence for absent or stripped-empty CLI input, preserves each nonblank
input unchanged, and leaves both API providers unchanged. `runAgentCompletionUsing`
already uses it before building initial messages, including the validated Claude batch
adapter. `seihou-cli/src-exe/Seihou/CLI/AgentMigrate.hs` already uses it for interactive
launch and debug display. These changes arrived through
[plan 111](111-run-blueprint-migrations-without-an-interactive-terminal.md); plan 106's
unchecked Progress no longer describes how much source work remains. Do not count the
same implementation twice. The broader migration-chain and other-command acceptance
in plan 106 remains there unless its evidence is actually gathered.

`AgentRun.runRenderedAgentPromptMode` returns early in debug mode and currently prints
only the system prompt, so changing the launcher's debug branch alone will not fix
blueprint debug display. `AgentRun.appliedBlueprintFromOutcome` records
`userPrompt = opts ^. #prompt`; keep that raw source. `seihou-cli/src-exe/Seihou/CLI/Commands.hs`
contains `agentRunInfo` and `agentRunParser`; the latter currently calls PROMPT an
"Optional initial user prompt" without explaining omission.

`seihou-cli/test/Seihou/CLI/AgentMigrateE2ESpec.hs` has
`withDeclaredLaunchBlueprint`, `declaredLaunchBlueprintDhall`, and
`batchMigrationProof`. The first fixture invokes a real Seihou executable but supplies
piped stdin, so its existing blueprint tests cover batch mode. `batchMigrationProof`
already demonstrates Python's `pty.openpty()` to give a child terminal input; a pseudo
terminal is an operating-system terminal pair usable by an automated test. Reuse this
technique for the actual `agent run` command. `seihou-cli/test/Seihou/CLI/SeihouBinary.hs`
finds the Cabal-built executable and deliberately refuses an installed PATH fallback.
`seihou-cli/test/Seihou/CLI/AgentCompletionSpec.hs` tests the resolver but currently lacks
a full context-capture matrix. `AgentTraceE2ESpec.hs`, `AgentGuardE2ESpec.hs`, and
`AgentUpgradeE2ESpec.hs` cover nearby behavior that must keep working.

Installed blueprints are discovered under `XDG_CONFIG_HOME/seihou/installed/NAME` by
`seihou-core/src/Seihou/Core/Module.hs`; project-local fixtures under
`.seihou/modules/NAME` are another supported source. Isolate config and cache directories
and scrub inherited `SEIHOU_CONTEXT` and `SEIHOU_AGENT_*` settings as the existing fixtures do. Do not change
real provider authentication or user configuration to run deterministic tests.

ADR discovery scanned local filenames and headings and inspected `mori show --full`.
There is no profiled `docs/adr` bundle; preserve the existing Markdown convention.
[ADR 0019](../adr/0019-non-terminal-blueprint-migrations-require-validated-batch-results.md)
already records the neutral sentence, terminal selection, and unchanged explicit input.
[ADR 0026](../adr/0026-a-batch-blueprint-run-fails-on-reported-tool-refusals.md)
requires batch blueprint tool refusals to fail without recording an applied blueprint;
starting a turn must not bypass that validation.
[ADR 0015](../adr/0015-diagnostics-name-things-as-users-do-and-never-fall-back-to-show.md)
requires understandable, actionable diagnostics.
[ADR 0004](../adr/0004-the-manifest-is-the-only-record-of-applied-state.md)
keeps applied state in the existing manifest. No new persistent field is needed.

The supplied consumer evidence is
`mori://tan/tan-seihou-modules/okf/friction-log/concepts/FRIC-15`, raised during
`mori://tan/tan-seihou-modules/plans/5-onboard-tan-services-to-production-with-a-seihou-module-and-blueprint`.
It records Claude waiting at zero tokens and a successful manual kickoff, but no Seihou
version. No real interactive provider was reproduced during this plan's creation.
The local installed executable reports `seihou v0.16.0.0 (1965b35)`; this is inventory,
not a reproduction or proof of delivery.

During creation, `mori registry list`, `mori registry show shinzui/baikai --full`, and
`mori registry docs shinzui/baikai` failed because the registry's local PostgreSQL socket
refused connections. The implementation can reuse the existing Seihou resolver and request
construction without inventing a dependency API. If provider argument details require
investigation, first restore Mori access and locate the dependency sources there. Do not
guess Baikai layouts or search `/nix/store`. No dependency bounds change is planned.


## Plan of Work

### Milestone 1: Start the ordinary interactive command


Extend `seihou-cli/test/Seihou/CLI/AgentMigrateE2ESpec.hs` with an installed blueprint
fixture and fake `claude` and `codex` executables. Start with one no-PROMPT case per
provider using the built Seihou binary with terminal stdin, no `--batch`, and no manual
kickoff. Make each fake capture its argument vector as JSON or NUL-delimited data so
spaces, newlines, and empty arguments remain distinguishable. Assert terminal input at
the fake, assert the absence of Claude print mode or Codex exec mode, and reject a missing
or blank initial user request. Verify the rendered blueprint context separately from
the user instruction. Codex may combine these in one argument; a nonempty system prompt
alone must never satisfy the assertion. Confirm the precise render shape through Mori
dependency source lookup when needed, rather than copying a historical argv assumption.

Run this representative path against the original launcher before expanding the matrix.
It must fail because the neutral user message is absent. Then import
`resolveAgentInitialPrompt` into `AgentLaunchExec.hs` and call it with
`AgentProviderClaudeCli` or `AgentProviderCodexCli` at each interactive request boundary.
Convert its result to the request's required `Text` locally and remove `promptOrEmpty`
if unused. Do not put the fallback in `BlueprintRunOpts`, command parsing, or templates.
Keep model, effort, mounted directories, tools, working directory, safety policy, and
exit propagation unchanged. The resolver is idempotent, so migrations that already
resolve a prompt remain correct.

Acceptance is the focused E2E command below passing for both terminal providers, with
the original failure recorded concisely. Run the same installed fixture from a fresh
project and empty Seihou cache. Required variables must be supplied through the ordinary
`--var` option; no fixture may inject a kickoff behind the command's back.

Before expanding the matrix in Milestone 2, run the real-Claude fixture in Concrete
Steps with the changed source binary. Observe the first response without keyboard
kickoff, then send the specified follow-up and verify a second response in the same
session. This proves both automatic startup and continued interaction. Record the
binary path and versions plus both observations. If provider authentication, trust,
or availability prevents this proof, leave this acceptance open and report the
blocker; fake argv success cannot replace it. This early run need not show the
launch-guidance line until Milestone 2 adds it.


### Milestone 2: Make the instruction and its provenance consistent


Expand those terminal tests to omitted input, `""`, whitespace containing spaces/tabs/newlines,
and a nonblank multiline value with leading/trailing whitespace. The first three classes
deliver the same neutral sentence; the last reaches the provider unchanged. Inspect the
applied-blueprint record using the manifest parser: omission stays absent, explicit blank
text stays raw, and a nonblank prompt is recorded exactly. Repeat a successful ordinary
run and prove it starts another correctly instructed session using existing run semantics.
A fake nonzero exit must propagate and must not add successful blueprint provenance.

In `AgentRun.runRenderedAgentPromptMode`, render the effective instruction through the
same resolver when debug is selected. Append a clearly delimited
`===== Initial user instruction =====` block when there is an effective message.
An API debug run with omitted input retains no such block; explicit API input remains
unchanged. Keep the system prompt itself unchanged and do not feed this display block
back to execution. Preserve the existing baseline and manifest effects of blueprint
debug mode; tests must use isolated fixtures rather than assume a dry run.

Before the ordinary interactive CLI launch in `AgentRun`, print one concise line, for
example `Starting blueprint with the default initial instruction.` when the resolver
supplies the fallback, or `Starting blueprint with your initial instruction.` for a
nonblank explicit prompt. Detect fallback by comparing the resolver's result with the
raw optional input, without duplicating its blank classification or sentence. Do not print
the user's full prompt in ordinary output. Explain in help that the session starts its first turn
automatically and remains open for follow-up input. Required variable or provider approval
prompts must remain visible; automatic kickoff does not automatically approve tools.

Update `Commands.agentRunInfo` and the PROMPT argument description, `seihou-cli/help/agent.md`,
`docs/cli/agent.md`, `docs/user/blueprints.md`, and the relevant CLI-provider explanation in
`docs/user/agent-assistance.md`. Document whitespace treatment and unchanged API behavior.
Show the prompt-free command first and an explicit override second. Use the supported
debug spelling `seihou agent --debug run BLUEPRINT`, and document its baseline/provenance
effects accurately. No new wait-only mode or flag is needed.

Keep existing completion-policy tests and strengthen `AgentCompletionSpec.hs` with a
context-capturing stub using its existing provider registration pattern if execution-level
coverage is missing. Verify both CLI providers receive a user message and both API
providers retain absent/blank/explicit input, while the system prompt and raw request
remain unchanged. Keep registry-mutating stub tests sequential. For batch `agent run`,
use the existing fake JSON provider fixture to assert fallback delivery and raw provenance;
retain refusal handling from ADR 0026. Existing migration terminal/batch tests must pass,
and `agent upgrade`'s command-specific explicit default must remain unchanged.

Acceptance is observable help, launch, debug, argv, and manifest behavior through the
built binary, together with focused completion, migration, tracing, guard, and upgrade
checks. Reverting only the interactive resolver wiring must fail the terminal regression
while existing batch coverage still passes. Do this in a temporary copy or by a narrow
patch that is restored immediately; never reset unrelated work.


### Milestone 3: Verify the consumer workflow and coordinate delivery


Retain the early real-Claude evidence from Milestone 1 and rerun the harmless fixture
against the final candidate to verify the launch guidance and continued interaction. Record the executable path, Seihou version, Claude version,
command, and first-turn observation. No keyboard kickoff is allowed. Authentication or
workspace-trust setup, if required, is provider preparation and must be reported separately;
acceptance starts from an authenticated, trusted provider workspace. The fake tests prove
both provider launch boundaries; this real check proves the reported Claude startup behavior.
It need not run the production-onboarding task or change any consumer infrastructure.

Reconcile plan 106 during implementation: record which shared-policy and interactive
acceptance this plan proves, link this evidence from its Progress/handoff, and retain its
unverified broader migration-chain and other-command obligations. Use the provenance
script for the first substantive edit to each plan. Update IR-22's target plan/status and
resolution through the repository's improvement-request metadata and log conventions.
IR-6 must not be declared complete solely because IR-22's narrower checks pass. Add
changelog entries in `CHANGELOG.md` and `docs/user/CHANGELOG.md`.

Distill the shared launch ownership and raw-input rule into the existing ADR 0019 or a
focused local ADR if expanding that migration-specific record would obscure its contract.
Preserve ADR 0026. Scan current ADR allocation immediately before adding a record and
follow the established filesystem convention; no ADR number is reserved here. Record and
triage implementation friction using the bundled scripts before filling the retrospective.

Run the final gates below, then identify the artifact containing this change. A release
and installation must use the repository's release workflow when authorized; source
implementation does not silently publish or replace the user's installed executable.
Keep consumer delivery open until an available artifact and the installed executable
containing the fix have passed the prompt-free terminal smoke check. Record any remaining
release/installation action explicitly rather than mark the whole plan delivered. Existing
blueprints and recorded manifests require no migration for this launch-only fix.


## Concrete Steps

Run build and test commands from the repository root. Use `nix develop` for the project's
toolchain if needed. Python 3 supplies the terminal fixture, as it does in the existing
migration tests. Keep tests in the existing groups so these selectors remain valid:

```bash
cabal build seihou-cli:seihou
cabal test seihou-cli-test --enable-tests --test-show-details=direct --test-options='--pattern "Agent migrate end-to-end"'
cabal test seihou-cli-test --enable-tests --test-show-details=direct --test-options='--pattern Seihou.CLI.AgentCompletion'
cabal test seihou-cli-test --enable-tests --test-show-details=direct --test-options='--pattern "Agent call tracing end-to-end"'
```

Each selector must run a nonzero number of tests, including the new cases. Initially the
terminal no-PROMPT cases fail their missing-user-message assertion. After implementation
they pass for both providers. Discover exact guard/upgrade group names with the built
test binary's `--list-tests` before filtering; the full CLI suite below also covers them.

For a harmless manual Claude check, build from the repository root and prepare this
installed fixture. These are test setup commands, not additional commands required to
adopt the fix in an already configured consumer. The literal Dhall record avoids a
network schema import. The isolated project has no baseline modules or reference files.

```bash
seihou_test_binary="$(cabal list-bin seihou-cli:seihou)"
seihou_test_root="$(mktemp -d "${TMPDIR:-/tmp}/seihou-initial-turn.XXXXXX")"
mkdir -p "$seihou_test_root/config/seihou/installed/kickoff-smoke" "$seihou_test_root/cache" "$seihou_test_root/project"
cat > "$seihou_test_root/config/seihou/installed/kickoff-smoke/blueprint.dhall" <<'DHALL'
{ name = "kickoff-smoke"
, version = Some "1.0.0"
, description = Some "Harmless initial-turn smoke check"
, prompt = "Reply INITIAL-TURN-STARTED for {{service.name}}, then wait for further user input. No tools are needed."
, vars = [ { name = "service.name", type = "text", default = None Text, description = Some "Fixture service", required = True, validation = None Text } ]
, prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }
, baseModules = [] : List { module : Text, vars : List { name : Text, value : Text } }
, files = [] : List { src : Text, description : Optional Text }
, allowedTools = Some [ "Read" ]
, tags = [] : List Text
, migrations = [] : List { from : Text, to : Text, prompt : Text }
, launch = None { provider : Optional Text, model : Optional Text, effort : Optional Text, mode : Optional Text }
}
DHALL
"$seihou_test_binary" --version
claude --version
cd "$seihou_test_root/project"
env -u SEIHOU_CONTEXT -u SEIHOU_AGENT_PROVIDER -u SEIHOU_AGENT_MODEL -u SEIHOU_AGENT_EFFORT -u SEIHOU_AGENT_TRACE \
  XDG_CONFIG_HOME="$seihou_test_root/config" XDG_CACHE_HOME="$seihou_test_root/cache" \
  "$seihou_test_binary" agent run kickoff-smoke --provider claude-cli --var service.name=demo
```

Run the last command with real terminal input, not through a pipe or nonterminal tool
capture. Keep provider credentials available; if isolating XDG config hides authentication,
use the already authenticated provider's supported setup and record that preparation.
The expected observation is a launch line announcing the default instruction followed by
Claude's first response containing `INITIAL-TURN-STARTED` for `demo` before any user
message. After observing that first response, enter `Reply FOLLOW-UP-RECEIVED` and
verify the provider answers in the same session, then exit normally. The follow-up
must only be sent after automatic first-turn evidence is captured. A blank input box
waiting for a kickoff, or a process that exits after its first response, is failure.
Inspect the resulting manifest through the normal parser in tests to prove no user prompt
was invented. Use separate fresh project directories for failure and first-use cases.

Return to the repository root for help inspection and final checks:

```bash
cabal run seihou-cli:seihou -- agent run --help
cabal run seihou-cli:seihou -- help agent
cabal build all
cabal test all --enable-tests --test-show-details=direct
python3 scripts/audit-cli-docs.py --executable "$(cabal list-bin seihou-cli:seihou)"
nix fmt -- --fail-on-change
nix flake check
git diff --check
```

If implementation updates improvement requests, validate that bundle and its log:

```bash
okf validate docs/improvement-requests --profile docs/improvement-requests/profile.dhall --profile-enforce --log-enforce
okf validate docs/improvement-requests --strict --profile docs/improvement-requests/profile.dhall --profile-enforce --log-enforce
```

Capture the current strict-validation diagnostics before changing request metadata and
introduce none; do not reuse plan 106's historical concept counts or fabricate reviews to
silence unrelated recommendations. Record command outcomes and exact versions, not full
provider transcripts. Repeat the smoke check with the delivered installed binary after
release/installation, retaining the build-versus-installed distinction.

Creation-time validation (2026-11-15): the literal smoke blueprint above passed
`seihou validate-blueprint` with its absolute directory path on installed Seihou
`v0.16.0.0 (1965b35)`. All Bash blocks passed `bash -n`; plan structure, fence languages,
and local Markdown links were checked. This validates the plan and fixture only; no
provider session or implementation acceptance has run.


## Validation and Acceptance

The primary acceptance is `seihou agent run BLUEPRINT` in a terminal with normal required
variables, no trailing prompt, and no injected stdin. Both fake CLI providers receive a
nonblank user request as well as the blueprint instructions, and the real Claude smoke
check begins its first turn without a kickoff and answers a subsequent user message in the same session. This early real-command path must run
before broadening the test matrix. Piped subprocess success alone is batch evidence.

Omission, explicit empty input, and whitespace-only input produce the shared sentence.
Nonblank multiline input keeps every leading/trailing character and newline. Capture
argument boundaries so the assertions can distinguish empty values and multiline text.
The system prompt, reference mounts, declared tools, model/effort selection, approval
policy, working directory, and exit status retain existing behavior. API omission remains
omission. Batch mode retains its existing fallback and refusal checks. Repeat invocations
start normally; no JSON repair, hidden preparation, or special flags are required.

Help explains the default and follow-up interaction. Ordinary launch output says which
kind of instruction starts the session without dumping explicit text. Debug exposes the
effective message and retains raw input in recorded provenance; it does not contact a
provider. Required input or provider approval waits remain visible with an actionable
next step. A nonzero provider exit cannot create successful blueprint provenance.

All required tests, docs checks, formatting, and build checks pass. Plan 106 and IR-6
accurately distinguish delivered shared behavior from their unverified remaining scope.
IR-22 and this plan remain open for any unverified real-provider or published/installed
delivery obligation. No production onboarding run, provider permission expansion, new
schema, dependency upgrade, or wait-only capability is required by this plan.


## Idempotence and Recovery

Tests use temporary projects, isolated Seihou config/cache, deterministic fake providers,
and bounded process waits. Close terminal file descriptors in exception-safe cleanup and
terminate only subprocesses created by the fixture, by their saved process handles or
PIDs. A hung test must report a timeout instead of blocking indefinitely. Do not use
process-name matching to stop providers.

Repeat commands in the same fixture to verify existing run behavior; use fresh projects
for first-use and failure evidence. Real smoke checks request only a short textual reply.
Do not rerun production onboarding to prove startup, reset consumer manifests, change
authentication files, or broaden approvals. On provider startup failure, report the actual
error and supported installation/authentication remedy, then retry the same ordinary
command after preparation. Keep any partial baseline effects consistent with the existing
runner; this work does not promise rollback of generated project files.

Record one implementation provenance revision per touched plan per session with
`agents/skills/exec-plan/record-provenance.ts`. Implementation commits use Conventional
Commits with this plan's `ExecPlan:` trailer and the frontmatter Intention ID; a commit
that substantively updates plan 106 also includes its `ExecPlan:` trailer. Do not rewrite
existing provenance or silently replace plan 106's authoritative intention.


## Interfaces and Dependencies

The existing Seihou interface is sufficient:

```haskell
-- seihou-cli/src/Seihou/CLI/AgentCompletion.hs
resolveAgentInitialPrompt :: AgentProvider -> Maybe Text -> Maybe Text
```

`AgentProviderClaudeCli` and `AgentProviderCodexCli` require the initial-turn fallback;
`AgentProviderAnthropic` and `AgentProviderOpenAI` preserve raw input. Blank classification
uses `Text.strip` only for deciding whether to fall back. It must never trim returned
explicit text. Keep `AgentCompletionRequest.initialPrompt`, `BlueprintRunOpts.prompt`,
and `AppliedBlueprint.userPrompt` raw. The effective instruction belongs to the provider
request and display, with no new manifest field or parser-required argument.

`seihou-cli/src-exe/Seihou/CLI/AgentLaunchExec.hs` remains responsible for Baikai
interactive requests and process outcomes. `seihou-cli/src-exe/Seihou/CLI/AgentRun.hs`
owns blueprint mode selection and user guidance. Baikai request construction and provider
configuration already exist; retain current bounds. Before any unforeseen dependency
change, locate sources with Mori and verify authoritative registry releases and upstream
tags rather than selecting a workaround from memory or stale corpus versions.

This is a coordinated follow-up to plan 106, not a child of a MasterPlan. The resolver
already in the working tree is its prerequisite and is available now. Cross-reference
actual evidence rather than blocking on plan 106's entire unchecked list. Source delivery,
real interactive verification, and published/installed availability are distinct outcomes
and must remain visible until each required outcome is verified.


Revision note (2026-11-15): Review against the current launchers and acceptance workflow
moved real-provider startup and follow-up proof into Milestone 1, retaining final-candidate
verification in Milestone 3. The smoke command now clears inherited context, and Context
and Orientation names the other callers affected by the shared launch policy. Mori
registry access still fails with a refused local PostgreSQL connection; dependency argv
rendering and the external consumer friction reference remain unverified in this review.
