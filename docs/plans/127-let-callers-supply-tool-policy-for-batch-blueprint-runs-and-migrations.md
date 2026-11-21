---
id: 127
slug: let-callers-supply-tool-policy-for-batch-blueprint-runs-and-migrations
title: "Let callers supply tool policy for batch blueprint runs and migrations"
kind: exec-plan
created_at: 2026-11-21T13:18:14Z
intention: "intention_01m7z42mfset9bak9t8sed2t21"
provenance:
  created_by:
    model: "gpt-6.2-astra"
    harness: "codex-cli"
    at: 2026-11-21T13:18:14Z
  reviews:
    - model: "claude-fable-5-2"
      harness: "claude-code"
      at: 2026-11-21T14:24:19Z
      verdict: "changes-requested"
      note: "Repo claims verified; hook-denial reporting unproven, comma-joined rules, undefined terms, and debug flag handling needed fixing"
  revisions:
    - model: "claude-fable-5-2"
      harness: "claude-code"
      at: 2026-11-21T14:24:19Z
      mode: "update"
      note: "Applied review findings: native probe with stop condition, argv rule passing, definitions, debug and migrate flag rules"
    - model: "gpt-6.2-astra"
      harness: "codex-cli"
      at: 2026-11-21T15:39:14Z
      mode: "implement"
      note: "Run provider integration probes and implement Claude policy receipts and read-only rendering."
---

# Let callers supply tool policy for batch blueprint runs and migrations

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.
Record implementation friction as it occurs using the
[friction guide](../../agents/skills/exec-plan/FRICTION.md).


## Purpose / Big Picture

An orchestrator that already approves commands can give one unattended Seihou blueprint run the
additional Claude rules it needs, or supply the Claude settings file that installs its existing gate. A
successful run leaves a receipt in the project's `.seihou/manifest.json` identifying what the caller
supplied. A reported tool refusal still fails the run. Someone who just wants to inspect the prompt can
render it in the target checkout without applying anything.

Start in the consuming repository with the blueprint installed and Claude Code configured. For a missing
rule, run one command. For a playbook that already produces a settings file, supply that file directly.
The same options work on a migration. A caller that runs Codex CLI supplies Codex's own files through
separate flags, because Codex has no per-tool allow list. The Codex command below remains a proposed interface pending the milestone 4 decision.
Each invocation is scoped to its own process.

```bash
seihou agent run fix-nix-haskell-flake-customizations --batch --allowed-tool 'Bash(grep *)'
seihou agent run fix-nix-haskell-flake-customizations --batch --settings ./campaign/claude-settings.json
seihou agent migrate keiro-upgrade --from=0.22.0.0 --to=0.25.0.0 --batch --settings ./campaign/claude-settings.json
seihou agent run fix-nix-haskell-flake-customizations --batch --provider codex-cli --codex-hooks ./campaign/codex-hooks.json
seihou agent --debug run fix-nix-haskell-flake-customizations
```

The first example grants the inspection command. The pilot run described under Context and Orientation
was refused ten commands, and the other nine still require their own approvals. An existing project
adopts the receipt format when a policy-bearing run upgrades its manifest in place, or ahead of time
through `seihou manifest upgrade`. A fresh
clone needs the same installed blueprint and caller inputs as the original checkout. Reading or
replaying a receipt must never grant tools to a subsequent run.


## Progress

- [x] (2026-11-21) A caller can add a rule to a batch blueprint run, see that exact rule in its receipt, and observe failure when the required rule is omitted.
- [x] (2026-11-21) A caller can supply a settings file containing a working Claude hook and identify the exact file contents used by their digest.
- [x] (2026-11-21) Batch migrations apply the policy to each pending edge and record it under the blueprint that owns that edge.
- [ ] A caller can give a Codex CLI batch run or migration its own rules and hooks files, see each file's digest in the receipt, and observe a blocked command fail the run.
- [ ] Debug rendering, help and public consumer acceptance. Source checks for read-only debug and both Claude commands passed on 2026-11-21. Installed acceptance and Codex scope remain open.


## Surprises & Discoveries

Claude Code 2.1.330 returned an array of events in the live fixture. Its final
result reported an empty denial list when the supplied hook admitted the probe.
With the same hook denying the command and a matching static grant present, the
command produced no marker, the result still reported success, and
`permission_denials` named the exact command. Seihou's existing validator
recognized this refusal. Separate argv entries also passed a native command
pattern containing a comma, `Bash(./policy-probe one,two)`.

On Codex CLI 0.171.0 a single-run configuration override loaded the caller's
PreToolUse hook under the invocation-wide hook trust bypass. An ephemeral
workspace-write control with an isolated configuration directory kept the
operator's installed hook definitions out of the experiment. The gate logged
Bash and blocked the command. Codex exited 0 and the JSON stream emitted no
command item or refusal event. Its stderr diagnostic named the command. Both
the blocked session and a control running `false` emitted trust warnings as
JSON error items. Only the control emitted a completed command item with
status failed and exit code 1. The warnings cannot identify a refusal.
`codex execpolicy check --rules` parsed the forbidden rule, but `codex exec`
rejected `--rules`. Codex documents loading rules beside active configuration
layers. No per-invocation rules-file input was verified. The probe reached
milestone 4's scope-decision condition. See [FRIC-21](../friction-log/21-codex-exec-omits-hook-denials-from-its-json-event-stream.md).


## Decision Log

On 2026-11-21, select both invocation-level mechanisms in IR-23. One missing command is cheap to grant
with a flag. An existing orchestrator can pass its own hook to make decisions over command arguments.
Defer the third option, blueprint author declarations and static prompt checking, because it cannot
deliver either caller workflow. The complementary requests for refusal classification and a tool-call
history have their own acceptance criteria.
[IR-23](../improvement-requests/let-a-caller-supply-the-tool-policy-of-a-batch-blueprint-run.md) ·
[IR-20](../improvement-requests/tell-off-plan-refusals-from-missing-tools-in-batch-runs.md) ·
[IR-21](../improvement-requests/keep-an-auditable-tool-call-record-of-a-batch-blueprint-run.md)

On 2026-11-21, include BUG-5 as a separately verifiable milestone. IR-23 explicitly calls for a
byte-identical manifest after debug rendering. Baseline modules can write the manifest, run commands and
even commit it before the runner reaches the final receipt writer. Meeting that criterion requires
branching before baseline application. The originating campaign used the accidental debug receipt, so
its adoption check must use an actual batch run for an applied-blueprint claim.
[BUG-5](../bug-reports/a-debug-blueprint-run-records-the-blueprint-as-applied.md) ·
[Campaign plan](mori://shinzui/shikigami/plans/132-modernize-the-keiro-services-with-a-declared-campaign-playbook)

On 2026-11-21, after review, probe Claude directly before writing milestone 2's code. Seihou fails a run
only on refusals listed in `permission_denials`, and nobody has observed whether a hook's deny decision
appears there. If it does not, a run whose gate blocked a command would still earn a receipt. Closing
that gap would be a new guarantee, so the plan stops for a scope decision in that case and does not pick
a detection mechanism in advance.
[ADR 0026](../adr/0026-a-batch-blueprint-run-fails-on-reported-tool-refusals.md)

On 2026-11-21, at the user's direction, extend the plan to Codex CLI and keep rejecting the policy flags
on the API providers. A Codex caller supplies Codex's native files, an execpolicy rules file and a hooks
file, through Codex-only flags. Seihou does not translate Claude rules. A Claude rule permits a tool call,
while a Codex `allow` rule runs a command outside the sandbox, so a translation would be lossy and would
widen access silently. The `openai` and `anthropic` providers send one completion and run no tools, so a
tool policy has nothing to govern there. Giving those providers tools would be a separate feature. No
change to Baikai is required. Its Codex renderer already forwards extra arguments and Seihou's adapter
runs the process itself.
[Baikai OpenAI provider](mori://shinzui/baikai/packages/baikai-openai)

On 2026-11-21, treat Seihou's rendering of provider policy arguments and its parsing of refusal output
as interim. Other tools that run agents unattended need the same two things, and Baikai's unattended-run
layer is where they belong. Baikai IR-14 requests them. This plan does not wait for it. Keep the
provider-specific code in `seihou-cli/src/Seihou/CLI/AgentCompletion.hs` so a later move to Baikai
touches one module, and attach both probes' results to that request. The receipt, the file digests and
the flags stay in Seihou.
[Baikai IR-14](mori://shinzui/baikai/okf/improvement-requests/concepts/IR-14)


## Outcomes & Retrospective

The local Cabal executable reported `seihou v0.16.0.2 (cd6c0f8)` while
testing the modified working tree. A recording Claude substitute in a fresh
Git consumer ran the installed `fix-nix-haskell-flake-customizations` 0.2.0
blueprint with the supplied settings argument in the correct directory. Its
digest matched the manifest. In a separate live `policy-check` consumer, Claude
2.1.330 admitted the probe with settings alone. A subsequent hook denial
returned exit 1 and preserved the preceding receipt byte for byte. A
pseudo-terminal verified that both run and migrate reject caller policy
without batch mode. The installed `seihou v0.16.0.1 (4540d20)` rejects
`--allowed-tool`. Release and installed acceptance remain open.

Final source acceptance passed `cabal test all` and `just audit-cli-docs`
with a single, stable candidate binary. The run and migration option screens
and `seihou help agent` advertise the new flags. The audit exercised 19 help
topics, 37 command help pages plus agent run, six example modules and eight
prompt renders. The migration fixture preserved the first owner's receipt on
a later refusal and recorded the retry's new settings digest only on the
pending edge. Both provider probe reports were attached to
[Baikai IR-14](mori://shinzui/baikai/okf/improvement-requests/concepts/IR-14).

Milestone 4 awaits a scope decision about the missing Codex refusal evidence.
The Claude and debug changes do not depend on that decision. FRIC-21 remains
logged while the decision is open.


## Context and Orientation

A blueprint is an installed set of instructions for an agent. Its optional baseline is a composition of
modules Seihou applies before launching the agent. A migration runs one session per version transition,
called an edge. A transition can include edges owned by another blueprint. A receipt is the manifest
entry for the completed run or edge. Batch mode is selected by `--batch` or by standard input being
disconnected from a terminal. Select the provider after resolving the blueprint's declared launch
configuration and caller overrides.

Several names recur below. Baikai is the library Seihou uses to call model providers. Its Claude CLI
provider builds the `claude -p` command line. Shikigami is the orchestrator that raised IR-23. It runs
blueprints across many repositories (a campaign), approves each command its agents run through a Claude
`PreToolUse` hook, and writes a Claude settings file for every attempt. The pilot is that campaign's
first run, on 2026-11-16, of the `fix-nix-haskell-flake-customizations` blueprint. It exited 1 after
Claude refused ten Bash calls the blueprint's guidance asked for. A cohort is the set of blueprints one
migration loads: the invoked blueprint and each blueprint that owns an edge in the window. A manifest
capability is a named feature with the oldest schema version that can record it, listed in
`minimumManifestVersion` in `seihou-core/src/Seihou/Manifest/Types.hs`. The artifact guard
(`enforceAgentArtifactGuard`) stops a run whose installed blueprint or baseline module is older than, or
from a different source than, the manifest records.

On 2026-11-21 the installed `seihou v0.16.0.1 (4540d20)` discovered the pilot blueprint at 0.2.0. In an
empty temporary Git project, a substitute `claude` returning a refusal for
`grep -A12 fixture flake.lock` made the ordinary batch command exit 1 and left the manifest absent.
Adding `--allowed-tool 'Bash(grep *)'` failed at option parsing. Then `agent --debug run` exited 0,
printed 28,057 bytes and created a manifest naming the blueprint. There was no live model call. The
checkout at `691e7d4` declares package version 0.16.0.2 and also applies baseline commands during debug.
The blueprint already grants several individual shell commands. It illustrates why granting a single
missing command cannot guarantee the entire campaign succeeds.
[Pilot blueprint](mori://shinzui/seihou-modules/templates/fix-nix-haskell-flake-customizations)

The parsers are `agentRunParser` and `agentMigrateParser` in
`seihou-cli/src-exe/Seihou/CLI/Commands.hs`. In `seihou-cli/src/Seihou/CLI/BlueprintExecution.hs`,
`prepareBlueprintExecution` resolves variables, mounted reference files and the tool list.
`resolveBlueprintTools` in `seihou-cli/src/Seihou/CLI/AgentLaunch.hs` already combines and deduplicates
Seihou's setup tools and the blueprint's `allowedTools`. The executable handlers are
`seihou-cli/src-exe/Seihou/CLI/AgentRun.hs` and `seihou-cli/src-exe/Seihou/CLI/AgentMigrate.hs`. The
migration handler already prepares each owner separately and includes a list of preapproved commands in
the migration prompt.

In `seihou-cli/src/Seihou/CLI/AgentCompletion.hs`, the Claude batch adapters use `claudeAccessArgs`,
Baikai's command renderer and a direct subprocess call. `runAgentMigrationCompletionWithCliAccess` also
sets `acceptEdits` and adds limited Mori discovery grants.
`seihou-cli/src/Seihou/CLI/AgentMigrationProtocol.hs` validates the raw result before either handler
records success. Preserve the distinction between ordinary runs, which accept older result formats, and
migrations, which require positive completion and permission evidence. The caller supplies requests for
preapproval. Claude still decides whether a particular operation is permitted.

Three facts about this path shape the work. `claudeAccessArgs` joins every tool rule with commas into a
single `--allowedTools` value, so a rule containing a comma is not yet known to survive. Baikai's
`claudeCliCommand` appends `--` and the prompt after the extra arguments, so a variadic flag cannot
consume the prompt. A batch run also inherits the operator's own Claude hooks and global instructions.
Commands those prompt are refused and listed in the same `permission_denials` array, and they fail the
run like any other refusal. Seihou reads refusals only from that array. Whether Claude lists a command
there when a `PreToolUse` hook denies it has not been observed.

Codex CLI works differently, and milestone 4 depends on these facts. Seihou launches a Codex batch run
as `codex exec --json --sandbox workspace-write` (`codexAccessArgs`). Commands run inside that sandbox
without asking, so there is no allow list to widen. Codex 0.171.0 offers two policy inputs. An
execpolicy rules file holds lines such as `prefix_rule(pattern=["git", "push"], decision="forbidden")`.
A pattern is an exact prefix of the command's arguments, `forbidden` blocks the command, and `allow`
runs it outside the sandbox. A hooks file has the same outline as Claude's. Its `PreToolUse` event can
block a command but cannot approve one. A separate `PermissionRequest` event can approve, and it fires
only when Codex would otherwise ask. Codex skips a hook nobody has reviewed unless the run passes
`--dangerously-bypass-hook-trust`. Codex's documentation names fixed locations for both inputs: the
user's `$CODEX_HOME` and a trusted project's `.codex/` directory. It documents no flag that loads either
file for one run, and it does not say whether hooks run under `codex exec`. `-c key=value` overrides any
configuration key for one run, and hooks can be declared in configuration under `[hooks]`.
`codex execpolicy check --rules FILE COMMAND...` parses a rules file and prints its decision without
calling a model. An ordinary Codex batch run goes through Baikai's stock provider, which validates
nothing. A Codex migration already goes through Seihou's adapter, and `validateMigrationOutput` fails it
on a `declined` or `failed` item. ADR 0026 left ordinary Codex runs unvalidated because a failed item
can be an ordinary failing command.
[Codex rules](https://developers.openai.com/codex/rules) ·
[Codex hooks](https://developers.openai.com/codex/hooks)
[ADR 0026](../adr/0026-a-batch-blueprint-run-fails-on-reported-tool-refusals.md) ·
[ADR 0019](../adr/0019-non-terminal-blueprint-migrations-require-validated-batch-results.md)

A manifest is portable and is the project's single applied-state record. Adding receipt evidence
requires a schema version, a lossless adjacent upgrade, and an explicit representation of missing
historical evidence. Older machine-local origins require a reviewed upgrade. Successful migrations keep
their owner, edge identity and outcome, including a recorded reason that the edge did not apply. A user
can also mark a pending edge applied manually. That command has no provider policy to attest.
[ADR 0001](../adr/0001-manifest-is-a-checked-in-machine-independent-artifact.md) ·
[ADR 0004](../adr/0004-the-manifest-is-the-only-record-of-applied-state.md) ·
[ADR 0014](../adr/0014-every-semantic-manifest-change-advances-the-schema-version.md) ·
[ADR 0005](../adr/0005-legacy-manifests-convert-through-an-explicit-command.md) ·
[ADR 0007](../adr/0007-a-deliberate-no-op-is-a-third-outcome-not-a-success.md) ·
[ADR 0008](../adr/0008-an-entailed-migration-edge-is-owned-by-the-blueprint-that-declares-it.md) ·
[ADR 0011](../adr/0011-a-migration-receipt-asserts-a-claim-about-the-project.md)

The artifact guard currently applies to debug runs because they mutate the project. The read-only debug
path should have the same inspection exemption as migration debug. Real runs must still check artifact
versions and origins and publish baseline command receipts in their established order. The distinction
matters to tests that currently use debug as a convenient way to run a real baseline.
[ADR 0003](../adr/0003-a-stale-or-substituted-artifact-is-a-hard-error.md) ·
[ADR 0023](../adr/0023-command-receipts-are-published-before-the-command-phase-runs.md) ·
[Plan 125](125-run-blueprint-baseline-commands-before-launching-the-agent.md)


## Plan of Work

### Milestone 1. Add a rule to a run and carry it through to the receipt

First extend `withBatchBlueprintRun` in `seihou-cli/test/Seihou/CLI/AgentMigrateE2ESpec.hs`. Today its
fake Claude returns fixed JSON. Make the answer for this case depend on the actual provider arguments.
Use a command outside the fixture blueprint's list, keep the initial project identical, and drive the
ordinary CLI. Demonstrate denial, successful execution with the requested grant, and denial again on a
later invocation without the flag. Check that the last failure preserves the preceding receipt. This is
the first vertical slice. Prove it before adding migration variants.

Add repeatable `--allowed-tool PATTERN` to `agent run`. Keep caller input separate from blueprint
defaults. Compute effective static grants by appending caller rules to the existing list and keeping the
first occurrence of each exact rule. Record the ordered, deduplicated caller inputs, including a rule
the blueprint also declares. Reject blank values and option-shaped input before launch. Use provider
argument boundaries that preserve spaces and valid Claude rule syntax, including punctuation inside a
pattern. A single supplied pattern must never introduce another CLI option or consume the prompt.
Today's comma join does not meet this. Pass each rule as its own argument after `--allowedTools`, which
Claude documents as a list, unless the native probe in Concrete Steps shows the joined form keeps a
comma-bearing rule intact. Exercise the actual renderer with a quoted Bash rule and with a rule that
contains a comma. Only Claude CLI batch execution supports these
flags. Reject an interactive launch or any other resolved provider before prompts, baseline writes or
provider launch. Name the incompatible flag and show how to retry with `--batch --provider claude-cli`
or omit the caller policy. On Codex CLI, point to the Codex flags of milestone 4 once they exist. On an
API provider, say that the provider runs no tools. Check the resolved provider, including defaults and blueprint declarations.

Add receipt support to `AppliedBlueprint` and `AppliedBlueprintMigration` in
`seihou-core/src/Seihou/Core/Types.hs`. The manifest schema in this tree is 15. Add a capability for
caller policy at 16, version-aware encoding and decoding in `seihou-core/src/Seihou/Manifest/Types.hs`,
and the adjacent lossless 15-to-16 step in `seihou-core/src/Seihou/Manifest/Upgrade.hs`. Define the JSON
contract under Interfaces and Dependencies. Upgrade existing receipts to null, preserve unrelated
fields, and reject malformed policy evidence or evidence labeled as an older schema. Extend the
contiguous-upgrade tests in `seihou-core/test/Seihou/Manifest/UpgradeSpec.hs`, the codec tests in
`seihou-core/test/Seihou/Manifest/TypesSpec.hs` and the CLI version-history checks in
`seihou-cli/test/Seihou/CLI/ManifestUpgradeSpec.hs`.

Preflight the ability to persist a policy-bearing receipt before mutating the project. Use the lossless
capability-preparation pattern in `seihou-cli/src/Seihou/CLI/ManifestCapabilityUpgrade.hs`. At receipt
publication, re-read the current on-disk manifest, apply the ordered transform to that state and write
the receipt with it. Baseline and agent edits may have occurred since preflight. The run writer
currently preserves the old version, the migration writer stamps the current one, and the baseline path
also sets a version. Audit all three paths for a silent drop or a version jump. Keep legitimate baseline
receipts from a real run even if the provider later fails. A policy-bearing run whose receipt cannot be
saved must exit nonzero and explain that the agent may already have edited files. Currently
`handleAgentRun` only logs that failure. Prove the vertical slice on a fresh project and on a schema-15
manifest with existing evidence.

### Milestone 2. Run the caller's settings and identify the bytes used

Add `--settings FILE` beside the rule flag and allow both together. Resolve relative paths from the
caller's working directory. Before any mutating phase, validate the explicit file as a readable regular
file containing a JSON object, and compute SHA-256 over its bytes. Pass the absolute path of the file
the caller specified as the value of Claude's native `--settings` argument. File location has permission
semantics. For example, Claude anchors a `Read(/private/**)` rule from that file at the file's
directory. Moving its contents to a temporary directory can silently move a deny rule. Verify that the
provider sees the original location, including a read-only parent and a path with spaces, while the hook
runs from the project working directory.
[Claude permission path syntax](https://code.claude.com/docs/en/permissions#read-and-edit)

The caller owns this file and must keep it stable until the invocation finishes. Capture the digest at
preflight, check it immediately before each launch and again before publishing its receipt. If it
changes or disappears, stop, identify the affected edge or run, and preserve previously completed
receipts. Test replacement during a provider call. These boundary checks detect ordinary concurrent
edits. They cannot attest to a file deliberately changed and restored between checks. Shikigami already
generates its settings per attempt. Never put settings JSON or hook bodies in the prompt, trace, error
output or manifest. A settings digest identifies the supplied file only. The hook program and any files
it reads have their own lifetimes and contents.

Keep Claude's existing permission checks and validate provider results exactly as in milestone 1.
Preserve the migration permission mode when adding settings there. Accept settings for rules and hooks
without adding a permission-bypass launch mode. Before writing any settings code, run the native probe
in Concrete Steps. It calls `claude` directly, so it needs no Seihou change. Confirm a positive hook
decision ran the command and recorded the hook event. Check separately that a blocking hook prevents
execution even alongside a matching static grant, and note whether that blocked command appears in
`permission_denials`. If it does, Seihou already fails closed and the fixture models the hook's refusal
with that array. If it does not, a run whose hook blocked a command can exit 0 and earn a receipt. In
that case stop and ask for a scope decision before continuing, because detecting hook refusals would be
a new guarantee. Record the observed behavior in Surprises & Discoveries either way. The deterministic
CLI suite must work without credentials and independently exercise both outcomes.
[Claude CLI reference](https://code.claude.com/docs/en/cli-reference) ·
[Claude hook decisions](https://code.claude.com/docs/en/hooks#pretooluse-decision-control)

### Milestone 3. Apply the same policy to pending migration edges

Add both flags to `agent migrate`. Resolve one invocation's caller rules and settings path and digest
before version probing or launching an edge. Reject policy flags with `--mark-applied` in the existing
early conflict check (`rejectConflictingMarkApplied`). Apply milestone 1's provider and batch rule here
too. A migration can run in batch on Codex CLI or interactively, and both must reject these Claude flags
before the first edge. At each pending edge, combine that owner's tools and the migration-only grants
with the caller's additions. Render the migration permission paragraph from the same effective list used
to launch the provider. When a settings file supplies a hook, tell the agent that the caller's hook also
decides requests, so the current instruction to execute only statically listed commands does not
preclude the hook workflow. Do not infer the hook's decisions or claim all tools are approved.

Thread the receipt evidence through `launchMigration` and `recordMigration` to
`seihou-cli/src/Seihou/CLI/AppliedBlueprintMigration.hs`. Record it for every validated edge that writes
an outcome. Leave skipped receipts intact. Test a window with two different owners, a refusal on a later
edge, and a rerun that resumes from pending work. Assert each provider gets its own owner's grants, the
shared caller policy, and the existing migration grants. The earlier receipt survives and the failed
edge gets none. A changed settings file on retry gives only the newly executed edges its new digest. Use
the existing cohort and protocol fixtures in `seihou-cli/test/Seihou/CLI/AgentMigrateE2ESpec.hs`.

### Milestone 4. Give a Codex batch run the caller's rules and hooks

This milestone starts with a prototype, because Codex documents no way to load either file for one run.
Run the Codex probe in Concrete Steps before writing code. It must answer four questions. Can a hooks
file be supplied to one `codex exec` run without writing into the project or the user's `$CODEX_HOME`?
Does a `PreToolUse` deny stop the command, and how does the `--json` event stream show it? Can a rules
file be supplied the same way? Can the stream tell a blocked command from one that ran and failed?
Record the answers in Surprises & Discoveries. Promote an input only if it loads for a single run and
leaves both the checkout and `$CODEX_HOME` untouched. If hooks cannot meet that, stop and ask for a
scope decision. If only rules cannot, drop `--codex-rules` from this plan and record that it needs a
change in Codex itself. If a blocked command cannot be told from a failed one, ask for a scope decision
before choosing how the run fails.

Add `--codex-hooks FILE` and `--codex-rules FILE` to `agent run` and `agent migrate`. They are valid
only for a batch run whose resolved provider is Codex CLI. Reject them elsewhere with the same early,
named error as the Claude flags, and reject a mix of Claude and Codex flags. Validate each file before
any mutating phase: a readable regular file, a JSON object for hooks, and a rules file that
`codex execpolicy check` parses. Check how that command reports a parse failure, since its exit status
alone may not show one. Hash each file's bytes and apply milestone 2's stability checks before each
launch and before the receipt.

Pass the inputs through the mechanism the probe promoted, as extra arguments after `codexAccessArgs`.
A caller's hook has not been through Codex's trust review, so pass `--dangerously-bypass-hook-trust`
only when `--codex-hooks` is present, and say in help that the caller vouches for that file. Keep
`--sandbox workspace-write`. An `allow` rule lets a command leave the sandbox, which is the caller's
stated choice. Document that plainly beside the flag.

Send a policy-bearing Codex `agent run` through `registerValidatedCli`, as migrations already do, so
Seihou can read the event stream. Fail the run on the blocked-command evidence the probe identified and
write no receipt. Leave a Codex run without these flags on the stock provider with today's behavior.
For migrations, add the same arguments to the existing Codex adapter call and keep
`validateMigrationOutput` as it is. Tell the migration agent that the caller's hook or rules may block
commands, without listing or inferring them.

Extend the suite's fake `codex` so its event stream depends on the arguments it receives. Cover a
blocked command, the same command passing once the caller's file admits it, both flags together, a
migration with two owners, and the rejections above.

### Milestone 5. Make debug rendering read-only and verify the caller workflow

In `handleAgentRun`, separate rendering from applying the baseline and recording success. Render the
resolved blueprint, references and initial user instruction against the current project context.
Identify any declared baseline as a preview, without claiming files or commands have already been
applied. Skip baseline acquisition/application, command execution, the mutating-path artifact guard,
provider launch and manifest publication during debug. Preserve variable resolution needed for a correct
prompt. Pass an explicit preview baseline status to `formatBaselineStatus` in
`seihou-cli/src/Seihou/CLI/AgentLaunch.hs`. Keep the ordinary run's guard, baseline and provider order.
Debug accepts the policy flags with or without `--batch`, because it never launches a provider. It
applies the same provider check and the same rule and settings-file validation as a real run, then shows
the effective static grants and whether settings were supplied, or for Codex which of the two files
were supplied. It does not run a hook or print a file's contents. Preserve `agent --debug migrate` behavior.

Test both an absent manifest and an existing one with noncanonical whitespace, a baseline module that
writes a marker via a command, and a provider stub that records launches. Repeated debug renders must
print the prompt, leave the original bytes or absence intact and create neither marker nor provider
record. Move tests that intentionally apply baselines in debug to ordinary batch runs with a successful
local provider stub. Inspect `seihou-cli/test/Seihou/CLI/BaselineCommandE2ESpec.hs`,
`seihou-cli/test/Seihou/CLI/SeedRunE2ESpec.hs`, `seihou-cli/test/Seihou/CLI/UpgradeRunnablesE2ESpec.hs`,
`seihou-cli/test/Seihou/CLI/AgentGuardE2ESpec.hs` and the `agent --debug run` cases in
`seihou-cli/test/Seihou/CLI/AgentMigrateE2ESpec.hs` so that preview and actual generation each keep
meaningful coverage.

Update the two subcommand help screens, `seihou-cli/help/agent.md`, `seihou-cli/help/blueprints.md`,
`docs/cli/agent.md`, `docs/user/agent-assistance.md`, `docs/user/blueprints.md` and
`docs/user/blueprint-migrations.md`. Include a quoted single-command rule, an existing settings file
with its hook, both receipt locations, and the failure/retry procedure. Update the existing refusal
diagnostic and distinguish provider tools from baseline commands that Seihou executes itself. Explain
the receipt schema in `docs/cli/manifest.md` and `docs/user/manifest-upgrade.md`. Update the debug and
caller-policy clauses of ADRs 0003, 0019 and 0026 and the changelog with the behavior change. Set the
status of IR-23 and BUG-5 in their records and add an entry to `docs/improvement-requests/log.md` and
`docs/bug-reports/log.md`, as plan 125 did for BUG-4. Verify the
invoking campaign can substitute a normal batch command for its render-and-apply workaround in a
disposable consumer. Record the tested Seihou executable and revision, Claude version, blueprint version
and delivery state. Track published and installed acceptance separately from source acceptance if
release work is pending.


## Concrete Steps

From the Seihou repository root, enter the project's development environment with `nix develop` and run
the rest in that shell. Build the executable before running the CLI tests. The CLI test binary locates
its sibling executable and expects fixture paths relative to `seihou-cli/`. Run the cases while working
on their respective milestones, then run the suites and the embedded help audit.

```bash
cabal build seihou-cli:exe:seihou seihou-cli:test:seihou-cli-test seihou-core:test:seihou-core-test
seihou_candidate="$(cabal list-bin seihou-cli:exe:seihou)"
(cd seihou-cli && "$(cabal list-bin seihou-cli-test)" -p '/Agent migrate end-to-end/ || /blueprint baseline commands/ || /agent path artifact guard/')
cabal test all
just audit-cli-docs
```

For a real-provider probe, use an authenticated Claude CLI and the candidate executable from the
preceding shell. Create a disposable consumer with a working tree, a local blueprint declaring only
Read, and an executable that produces an observable side effect. The test hook logs its Bash decisions
and admits exactly the probe command. This setup builds test evidence. A production caller that already
has a blueprint and a gate only needs the normal command shown under Purpose.

```bash
seihou_repo="$PWD"
probe_root="$(mktemp -d)"
mkdir -p "$probe_root/project/.seihou/modules/policy-check"
ln -s "$seihou_repo/schema" "$probe_root/schema"
cd "$probe_root/project"
git init -q
cat > .seihou/modules/policy-check/blueprint.dhall <<'DHALL'
let S = ../../../../schema/package.dhall
in S.Blueprint::{
  , name = "policy-check"
  , prompt = "Call the Bash tool with exactly ./policy-probe once. Report its output."
  , allowedTools = Some [ "Read" ]
  }
DHALL
cat > policy-probe <<'SH'
#!/bin/sh
echo ran >> probe-runs
echo probe-complete
SH
chmod +x policy-probe
cat > policy-gate.py <<'PYTHON'
import json
import sys

event = json.load(sys.stdin)
command = event["tool_input"].get("command", "")
decision = "allow" if command == "./policy-probe" else "deny"
with open("hook-decisions", "a") as log:
    print(decision, command, file=log)
print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "PreToolUse", "permissionDecision": decision
}}))
PYTHON
cat > 'caller settings.json' <<'JSON'
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"python3 policy-gate.py"}]}]}}
JSON
claude --version
```

That much needs no Seihou change. Run the native probe now, before milestone 2's code, from the same
directory. Its arguments mirror the command line Seihou builds.

```bash
probe_prompt='Call the Bash tool with exactly ./policy-probe once. Report its output.'
claude -p --output-format json --no-session-persistence --settings "$PWD/caller settings.json" \
  --allowedTools 'Read' -- "$probe_prompt" | jq '{is_error, permission_denials}'
cat probe-runs hook-decisions
sed -i.bak 's/"allow" if/"deny" if/; s/else "deny"/else "allow"/' policy-gate.py
claude -p --output-format json --no-session-persistence --settings "$PWD/caller settings.json" \
  --allowedTools 'Read' 'Bash(./policy-probe)' -- "$probe_prompt" | jq '{is_error, permission_denials}'
cat probe-runs hook-decisions
mv policy-gate.py.bak policy-gate.py
rm -f probe-runs hook-decisions
```

The first call should add one `ran` line and one `allow ./policy-probe` decision with no denials. The
second inverts the hook, so it should add a `deny ./policy-probe` decision and no `ran` line despite the
static grant. Its `permission_denials` value answers the open question in milestone 2. Then continue
with the candidate executable once the flags exist. The debug line and the manifest check after it pass
only after milestone 5.

```bash
"$seihou_candidate" --version
"$seihou_candidate" agent --debug run policy-check
test ! -e .seihou/manifest.json
"$seihou_candidate" agent run policy-check --batch --provider claude-cli --allowed-tool 'Bash(./policy-probe)'
"$seihou_candidate" agent run policy-check --batch --provider claude-cli --settings 'caller settings.json'
cat probe-runs hook-decisions
shasum -a 256 'caller settings.json'
jq '.blueprint.callerToolPolicy' .seihou/manifest.json
```

Expect two lines containing `ran`, a hook decision of `allow ./policy-probe`, and a final receipt with
an empty caller rule list and a digest equal to `shasum`'s first column. To exercise a deny decision in
the same test project, change the hook's decision for that command to `deny` and run the last batch
command with the rule flag also present. Compare the number of marker lines, the hook decision and the
provider's actual refusal evidence. Record any provider-specific limitations. A refusal that names any
command other than `./policy-probe` comes from the operator's own hooks or global instructions. The
pilot met one, a `rex session rename` that a session hook requests. Record it and rerun where that hook
is quiet. Do not widen the probe's grants to hide it. Run the credential-free
fixture tests for absent-rule failures even on machines with a personal allow rule. For the
campaign-shaped check, substitute the installed pilot blueprint in a disposable consumer using the
caller's settings fixture and a recording provider stub. Verify that the intended arguments, working
directory and hook input reach the subprocess. Record live-provider evidence separately.


The Codex probe for milestone 4 uses the same disposable project and an authenticated `codex`. Its hook
blocks the probe command and stays silent otherwise, because Codex treats a bare `allow` as an error.
The rules check calls no model. The `-c` form below is the first candidate for supplying hooks to one
run and is not documented. If Codex rejects or ignores it, try the other routes Codex offers and record
which one worked.

```bash
codex --version
cat > codex-gate.py <<'PYTHON'
import json
import sys

event = json.load(sys.stdin)
command = event["tool_input"].get("command", "")
with open("codex-hook-decisions", "a") as log:
    print(command, file=log)
if "policy-probe" in command:
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse", "permissionDecision": "deny",
        "permissionDecisionReason": "blocked by the caller's gate"
    }}))
PYTHON
printf '%s\n' 'prefix_rule(pattern=["./policy-probe"], decision="forbidden")' > caller.rules
codex execpolicy check --rules caller.rules --pretty ./policy-probe
rm -f probe-runs
codex exec --json --ephemeral --skip-git-repo-check --sandbox workspace-write \
  --dangerously-bypass-hook-trust \
  -c 'hooks.PreToolUse=[{matcher="Bash",hooks=[{type="command",command="python3 codex-gate.py"}]}]' \
  -- 'Run the shell command ./policy-probe once. Report its output.' > codex-events.jsonl
cat codex-hook-decisions
test ! -e probe-runs && echo blocked
jq -c 'select(.type | startswith("item")) | .item | {type, status, command}' codex-events.jsonl
```

The rules check should print a `forbidden` decision. If the hook loaded, `codex-hook-decisions` names
the probe command, `blocked` is printed, and the last command shows how the stream reports the blocked
item. Compare that with the item a command that runs and exits 1 produces. Repeat the run without the
`-c` argument while looking for a way to load `caller.rules` for one run.


## Validation and Acceptance

Milestone 1 passes when the fixture reports the exact missing tool on exit 1, succeeds on exit 0 with
the additive rule, and fails again without it. Verify repeated flags, overlap with a default,
preservation of mounted directories and initial prompt, explicit batch and piped stdin, an actual
terminal without `--batch`, and a resolved unsupported provider. With no caller flags the existing
provider behavior and refusal tests must pass. A policy rejection must occur before a baseline command
can touch its marker.

Milestone 2 passes when the same fixture succeeds with settings alone, with matching SHA-256 evidence. A
combined invocation records both inputs. An unreadable file, invalid JSON or non-object input produces
an actionable nonzero exit before any baseline, hook, agent or receipt. Exercise different byte
encodings of equivalent JSON (for example different whitespace), replacement of the original during a
run, and a distinctive hook-body string that must be absent from the receipt and diagnostics. Confirm
the native hook probe above before claiming provider integration.

Milestone 3 passes when each executed edge's `blueprintMigrations` entry records the policy actually
supplied to its provider, and a denial, bad protocol result, manually marked edge or skipped edge cannot
acquire false provenance. Exercise both `MigrationApplied` and `MigrationNotApplicable` with real
fixture receipts. The original owner and retry rules still determine which edge runs.

Milestone 4 passes when the probe's four answers are recorded and each promoted flag works end to end
against the fake `codex`. A run whose stream reports the blocked command exits 1 with no receipt. The
same run exits 0 once the caller's file admits the command, and its receipt carries digests equal to
`shasum -a 256` of the supplied files. Neither the checkout nor `$CODEX_HOME` holds a file Seihou wrote.
Codex flags on Claude CLI, on an API provider, in an interactive session, or mixed with Claude flags
stop before any baseline write. A Codex batch run without the flags behaves exactly as before.

Milestone 5 passes when ordinary debug output includes the rendered guidance and effective initial
instruction while a byte comparison of the existing manifest succeeds, a fresh checkout still lacks a
manifest, and baseline and provider markers are absent. Verify the same fixture still applies its
baseline before a real provider launch. Run both `--help` screens and `seihou help agent` from the built
executable, then exercise the normal run and migration examples against their corresponding fixtures.
Record acceptance for the installed binary when it becomes available through the normal release channel.
Keep a pending release explicit in Outcomes & Retrospective.


## Idempotence and Recovery

A caller must pass its policy again on each invocation. An ordinary successful rerun replaces the
applied blueprint's current receipt. A migration upserts the executing owner's edge and skips already
completed edges as before. Treat the receipt evidence as historical input, including when the settings
file moves or disappears. Reading status, planning an update or resuming a migration must never load a
file or run a hook from that evidence.

A provider can edit files before reporting a refusal, and a real baseline may already have finished. On
failure, name the blocked command or input, tell the caller to inspect the working diff, then retry with
the intended rule or corrected settings. Preserve earlier successful receipts and user edits. Never roll
the tree back automatically. A failed receipt write must distinguish work already performed from
evidence still missing. The demo uses a fresh temporary directory per run so old receipts, markers and
hook logs cannot produce a false pass.


## Interfaces and Dependencies

Represent the raw CLI inputs (an ordered list of rule strings and an optional file path), the resolved
launch inputs, and the small serializable receipt as distinct values. Thread them only through the two
blueprint batch entry points. Other users of the shared completion or prompt helpers can continue with
empty caller inputs. Use the existing Baikai renderer's extra-argument facility. In the examined source
the renderer adds the option terminator and positional prompt after the extra arguments. No dependency
pin or blueprint descriptor change is required.
[Baikai Claude provider](mori://shinzui/baikai/packages/baikai-claude)

At schema 16 require a `callerToolPolicy` key on each existing blueprint or migration receipt. JSON null
means no caller-supplied policy was recorded, including historical, default and manually marked records.
A non-null object requires four keys: `allowedTools` (a list of nonblank caller patterns),
`settingsSha256`, `codexHooksSha256` and `codexRulesSha256` (each a lowercase 64-digit hexadecimal
SHA-256, or null). The first two belong to a Claude CLI run and the last two to a Codex CLI run, so one
receipt never carries both pairs. At least one caller input must be present in a non-null object. Store caller rule literals without expanding machine paths. Document the settings-file
form for machine-specific or sensitive policy. Keep settings paths, hook contents and provider defaults
out of the record. For a rule-only run the receipt contains this object.

```json
{"callerToolPolicy":{"allowedTools":["Bash(grep *)"],"settingsSha256":null,"codexHooksSha256":null,"codexRulesSha256":null}}
```

Schema 15 and earlier encode receipts without the new field. Extend the existing SHA-256 support in
`seihou-core/src/Seihou/Manifest/Hash.hs` with a byte-oriented entry point for settings. Keep
`hashContent`'s text behavior for current callers. The write boundaries are `recordAppliedBlueprint` in
`seihou-cli/src/Seihou/CLI/AppliedBlueprint.hs` and `recordAppliedBlueprintMigration` in
`seihou-cli/src/Seihou/CLI/AppliedBlueprintMigration.hs`. Neither receipt participates in provider
permission resolution. Claude owns hook execution and permission precedence. Seihou owns invocation
setup, validating the provider result and writing the corresponding receipt.


## Revision Notes

2026-11-21: Revised after a review against the working tree. Defined the recurring names, recorded the
comma join in `claudeAccessArgs` and the unobserved reporting of hook denials, added a native Claude
probe that runs before milestone 2's code with a stop condition, stated how debug treats the policy
flags, extended the provider rule to migrations, and added the IR-23 and BUG-5 record updates. The file
paths, symbols, schema version and test names the plan cites were confirmed unchanged.

2026-11-21: Extended to Codex CLI at the user's direction. Added milestone 4, which begins with a Codex
probe and promotion criteria, the `--codex-hooks` and `--codex-rules` flags, two receipt keys, and the
Codex facts in Context and Orientation. The debug and documentation milestone is now milestone 5. The
API providers still reject the policy flags because they run no tools.

2026-11-21: Recorded that the provider-specific rendering and refusal parsing are interim pending Baikai
IR-14, which was drafted alongside this revision.
