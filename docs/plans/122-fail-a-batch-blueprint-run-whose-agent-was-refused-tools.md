---
id: 122
slug: fail-a-batch-blueprint-run-whose-agent-was-refused-tools
title: "Fail a batch blueprint run whose agent was refused tools"
kind: exec-plan
created_at: 2026-11-11T13:52:47Z
intention: "intention_01m75e3qgtecntc0t04z9e9a49"
provenance:
  created_by:
    model: "claude-opus-5-5"
    harness: "claude-code"
    at: 2026-11-11T13:52:47Z
  revisions:
    - model: "claude-opus-5-5"
      harness: "claude-code"
      at: 2026-11-11T14:48:01Z
      mode: "implement"
      note: "Milestones 1-4 implemented"
---

# Fail a batch blueprint run whose agent was refused tools

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.
Record friction met while implementing in the friction-log bundle as it occurs (see FRICTION.md).

This plan implements improvement request IR-18,
[Fail a batch blueprint run whose agent was refused tools](../improvement-requests/fail-a-batch-blueprint-run-whose-agent-was-refused-tools.md).


## Purpose / Big Picture

A blueprint is a packaged prompt that `seihou agent run BLUEPRINT` sends to a coding agent
such as Claude Code. A *batch* run (`--batch`, or any run whose stdin is not a terminal) has
no human present: the agent runs to completion and Seihou prints its final message. Batch
runs are how blueprint authors qualify a blueprint before publishing it.

Today a batch run exits 0 even when Claude Code refused the commands the blueprint needed.
In the run that prompted IR-18, the blueprint declared no `allowedTools`, so Claude refused
`nix`, `bun`, `mori`, `cp` and others for about an hour. The agent's final message listed the
work it could not do, Seihou printed it, and the shell saw success. A second run that declared
those tools still had writes inside `.git/` and shell redirection refused, and also exited 0.

After this change, a batch `seihou agent run` whose Claude Code session reports any refused
tool call exits non-zero and prints each refused tool and command, for example:

```text
Error: Claude refused 2 tool calls during this unattended run: Bash (nix build .#docs), Bash (bun install). An unattended run cannot approve tools. Declare the commands the blueprint needs in its allowedTools, or run it interactively, then retry.
```

It also does not record the blueprint as applied in `.seihou/manifest.json`. A run with no
refusals prints the agent's answer and exits 0 as it does now. In addition,
`seihou validate-blueprint` warns, without failing, when a blueprint declares no
`allowedTools`, and names the only tools such a blueprint gets in a batch run.


## Progress

- [x] Milestone 1: The real Claude Code CLI's reporting of refusals is recorded in Surprises &
  Discoveries, covering an allow-list refusal, shell redirection and a write inside `.git/`.
  (2026-11-11: Claude Code 2.1.322 reports all three in `permission_denials`.)
- [x] Milestone 2: A batch `seihou agent run` whose fake `claude` reports a denial exits
  non-zero, prints the refused command and records no applied blueprint. Existing batch and
  trace end-to-end tests still pass. (2026-11-11: "fails a batch run whose agent was refused
  a tool" passes and fails with `ExitSuccess` when `AgentCompletion.hs` is reverted. Twelve
  `AgentBatchProtocolSpec` cases pass. The full suite passes, 905 tests before Milestone 3.)
- [x] Milestone 3: `seihou validate-blueprint` warns on a blueprint without `allowedTools`
  and exits 0, covered by a new end-to-end spec. (2026-11-11: three `ValidateBlueprint` e2e
  cases and three `undeclaredAllowedToolsWarning` unit cases pass. `nix flake check`
  passes.)
- [x] Milestone 4: Help, user documentation and ADR 0026 describe the behavior. IR-18 is
  marked completed with a resolution, and its bundle log is updated. (2026-11-11: `okf
  validate` passes for the improvement-request bundle. The full suite passes, 908 tests.)


## Surprises & Discoveries

- Claude Code 2.1.322 reports allow-list refusals and both guard refusals in
  `permission_denials`, so the second Decision Log entry holds as written. The probe ran the
  three Milestone 1 commands in a scratch git repository on 2026-11-11. Each exited 0 with
  `"subtype":"success","is_error":false`, and nothing was written to disk. The trimmed denials:

  ```text
  run 1 (--allowedTools Read, "nix --version"):
    [{"tool_name":"Bash","tool_input":{"command":"nix --version",…}}, …]
  run 2 (--allowedTools "Bash(echo *)", "echo hi > out.txt"):
    [{"tool_name":"Bash","tool_input":{"command":"echo hi > out.txt",…}}]
  run 3 (--allowedTools Write, write .git/seihou-probe):
    [{"tool_name":"Write","tool_input":{"file_path":"…/probe/.git/seihou-probe","content":"probe"}}]
  ```

- Version 2.1.322 prints `--output-format json` as an array of events (`system`,
  `assistant`, `user`, `rate_limit_event`, …). Only the final `result` event carries
  `permission_denials`. Some events have `"subtype": null`.

- A `Write` or `Edit` denial has no `tool_input.command`. Its target is
  `tool_input.file_path`. Rendering the tool name alone would print a bare `Write` for the
  `.git/` case, which does not say what was refused. The renderer therefore falls back to
  `file_path` (see the Decision Log).

- A batch run inherits the user's Claude Code hooks and global instructions. In run 1, the
  developer's Rex SessionStart hook told the agent to run `rex session rename …`. Claude
  refused that twice, and the refusals sit next to `nix --version` in `permission_denials`.
  Under the fail-on-any-denial rule, a batch run in such an environment fails even when the
  blueprint declares everything it needs. The error names each refused command, so the user
  can see where it came from, either a hook or the blueprint. The Decision Log keeps the rule,
  and ADR 0026 and the user docs state this consequence.


## Decision Log

- Decision: Detect refusals with a Seihou-side adapter that runs `claude` itself and
  validates its JSON output. Do not wait for a Baikai change.
  Rationale: Baikai's Claude CLI provider decodes the result into `ClaudeCliReport`
  (`baikai/src/Baikai/Provider/Cli/Internal.hs` in `mori://shinzui/baikai`; the artifact-level
  URI is pending). That record keeps `result`, `is_error`, `session_id`, model and usage, and
  drops `permission_denials`. The `Response` it returns has no raw output, so nothing
  downstream can recover the denials. `agent migrate` already solved the same problem this way
  (`runAgentMigrationCompletionWithCliAccess`, ADR 0019). The cost is the same as for
  migrations: the adapter's response carries zero usage and none of Baikai's subprocess
  evidence, so a batch `agent run` trace loses token counts and the session id. A later Baikai
  change that exposes the denials on its report would let both adapters return to the stock
  provider. That change is out of scope here.
  Date: 2026-11-11

- Decision: Fail the run on any reported denial, whatever caused it: the blueprint's
  allow list, or a provider guard such as a write inside `.git/` or shell redirection.
  Rationale: An unattended run cannot grant any approval, so every refused call is work the
  blueprint expected and did not get. Treating some refusals as acceptable would bring back
  the false pass IR-18 reports. This answers the IR's open design question, provided
  Milestone 1 shows that guard refusals appear in `permission_denials`. If they do not,
  Seihou cannot see them, and the plan records that limit instead.
  Date: 2026-11-11

- Decision: Keep the batch path's existing acceptance rules and add only the denial check.
  A missing `permission_denials` field passes, and so does a missing or unexpected `type` or
  `subtype`. The run fails on a non-empty `permission_denials` in any event, on
  `is_error: true`, on malformed JSON, or on a blank `result`.
  Rationale: The acceptance criterion "a run with no refusals behaves as today" rules out the
  migration validator's fail-closed rules, which also require `subtype: success` and a present
  `permission_denials`. The existing `agent run` fixtures in
  `seihou-cli/test/Seihou/CLI/AgentMigrateE2ESpec.hs` and
  `seihou-cli/test/Seihou/CLI/AgentTraceE2ESpec.hs` emit
  `{"result":…,"is_error":false,"session_id":"fake"}` with neither field, as older CLI versions
  did. Current Claude Code emits `permission_denials` (the Claude Code 2.1.312 envelope captured
  in `batchMigrationProof` in the same spec file includes it), so tolerating its absence should
  not weaken detection in practice. Milestone 1 confirms this on the installed version.
  Date: 2026-11-11

- Decision: Cover the `claude-cli` provider only. A `codex-cli` batch run keeps Baikai's
  stock provider.
  Rationale: IR-18 is about Claude's allow list. Codex has no `allowedTools`: it runs in a
  workspace-write sandbox. The migration validator's Codex rules also fail a run on any
  `failed` item, which would include an ordinary command that exits non-zero, such as a failing
  test. That is too strict for a general blueprint run, and designing a Codex rule needs its
  own evidence.
  Date: 2026-11-11

- Decision: Do not stop a run at its first refusal (IR-18's optional third request).
  Rationale: With `--output-format json`, which both Baikai and the migration adapter use,
  Claude Code writes nothing until the session ends, and the denials arrive in the final
  result. Stopping early would need streamed output (`--output-format stream-json`), read
  incrementally, which would replace the batch transport. Failing at the end already removes
  the false pass.
  Date: 2026-11-11

- Decision: Show the `validate-blueprint` warning on every run, not only with `--lint`.
  Treat an empty `allowedTools` list (`Some ([] : List Text)`) the same as an absent one.
  Rationale: IR-18's acceptance requires a plain `seihou validate-blueprint` to print it.
  `--lint` is accepted by `validate-blueprint` and currently does nothing, so tying the
  warning to it would hide the warning by default. Both spellings give a batch run only the
  setup tools.
  Date: 2026-11-11

- Decision: Render a denial as `<tool_name> (<command>)`, or else as
  `<tool_name> (<file_path>)`, or else as the tool name alone.
  Rationale: The Milestone 1 probe showed a refused `Write` carries `file_path` and no
  `command`. `Write (/repo/.git/seihou-probe)` names the refused work in the user's own terms,
  as ADR 0015 asks, and a bare `Write` does not. The migration message shares the renderer
  and gains the same detail.
  Date: 2026-11-11

- Decision: Record the decision as ADR 0026, not ADR 0025 as first planned.
  Rationale: ExecPlan 120 created `docs/adr/0025-a-module-owns-only-its-own-directory-under-seihou.md`
  after this plan was written. References in this plan were updated.
  Date: 2026-11-11

- Decision: Keep failing on every denial, including those caused by the user's own hooks or
  global instructions.
  Rationale: The probe showed ambient hooks can add refused calls. Seihou cannot tell those
  apart from the blueprint's own work, and an exemption list would be guesswork. The error
  names each command, which is enough to find the cause. A hook that needs a command in
  unattended runs can be granted it in the user's Claude Code settings.
  Date: 2026-11-11


## Outcomes & Retrospective

Completed 2026-11-11. All of IR-18's acceptance criteria hold. A batch `claude-cli`
`seihou agent run` whose agent was refused a tool exits 1, names each refusal as
`Bash (nix build .#docs)` or `Write (/repo/.git/x)`, and writes no applied-blueprint entry.
A run with no refusals behaves as before, and the legacy fixtures in the batch and trace
end-to-end specs pass unchanged. `seihou validate-blueprint` warns about a blueprint with
no or empty `allowedTools` and exits 0. The new end-to-end case fails with `ExitSuccess`
when the adapter change is reverted. The suite has 908 tests and passes, and
`nix flake check` passes.

The Milestone 1 probe was worth its cost. It confirmed that guard refusals are visible, and
it found two things the plan had not foreseen: a refused `Write` carries `file_path` and no
`command`, and the user's own hooks add refusals. Both shaped the renderer and the
documentation. The second has a practical cost. In an environment like the developer's,
where a SessionStart hook asks every session to run `rex session rename`, a batch run fails
until that command is granted in the user's Claude Code settings. The error names it, and
ADR 0026 and the docs say so.

The adapter is now shared with `agent migrate` (`registerValidatedCli`), so the two batch
paths differ only in their extra arguments, exit message and validator. As planned, batch
`claude-cli` traces lose token counts and the session id. A Baikai change that keeps
`permission_denials` on its report would let both paths return to the stock provider.

The code for Milestones 2 and 3 went into one commit, because they share `Main.hs` and the
cabal file. The ADR number in the plan changed from 0025 to 0026, because ExecPlan 120 had
taken 0025 in the meantime.

Friction: `FRIC-13` (the test binary must run from `seihou-cli/`, and `cabal test
--test-options` cannot carry a compound `-p` pattern) is left `logged`. The fix belongs in
the test harness's schema lookup, outside this plan's scope. Concrete Steps now give the
working commands.


## Context and Orientation

Seihou is a Haskell command-line tool. The command `seihou agent run BLUEPRINT` loads a
blueprint (a directory under `.seihou/modules/` or the install cache containing
`blueprint.dhall`), renders its prompt, and hands it to an agent provider. Provider and model
resolution is in `seihou-cli/src/Seihou/CLI/AgentConfig.hs`. The two local CLI providers are
`claude-cli` (Claude Code's `claude` executable) and `codex-cli`. Their calls go through
Baikai, an LLM client library in another repository (`mori://shinzui/baikai`). The CLI module
placement rule in `CLAUDE.md` applies: new code goes in the library at `seihou-cli/src/`.
`seihou-cli/src-exe/` keeps only modules that import `Options.Applicative`, `Data.FileEmbed`,
`GitHash`, `Paths_seihou_cli`, or another executable-only module.
`nix/check-cli-module-placement.sh` enforces this.

The command handler is `handleAgentRun` in `seihou-cli/src-exe/Seihou/CLI/AgentRun.hs`. It
sets `batch` to true when `--batch` is passed or stdin is not a terminal. After preparing the
blueprint it calls `runRenderedAgentPromptMode`, which has three branches. With `--debug` it
prints the prompt. An interactive run on a CLI provider launches the agent in the terminal. All
other runs take the `otherwise` branch, which is batch CLI runs and every API-provider run.
That branch calls `runAgentCompletionWithCliAccess` from
`seihou-cli/src/Seihou/CLI/AgentCompletion.hs`. On `Right text` it prints the text and returns
`True`. `handleAgentRun` then writes an applied-blueprint entry into `.seihou/manifest.json`.
On `Left err` it prints `Error: <err>` to stdout and calls `exitFailure`, which exits 1 without
recording anything. `runAgentCompletionWithCliAccess` has no other caller (check with
`grep -rn runAgentCompletionWithCliAccess seihou-cli`).

`runAgentCompletionWithCliAccess` registers providers with
`registerAgentProvidersWithCliAccess`. For `claude-cli` this is Baikai's stock
`claudeCliProvider` with `--allowedTools <tools>` and `--add-dir <dir>` added. That provider
runs `claude -p --output-format json …` and decodes stdout. A Claude Code result is a JSON
object, or, in recent versions, an array of events whose last element has `"type":"result"`.
It carries `subtype`, `is_error`, `result` (the final assistant text) and
`permission_denials`. That last field is an array with one object per refused tool call,
`{"tool_name":"Bash","tool_use_id":"…","tool_input":{"command":"nix build .#docs"}}`. Baikai
reads `result` and `is_error` and ignores `permission_denials`. So a session that ended
normally after many refusals reaches Seihou as an ordinary success. This is the cause of
IR-18.

The `tools` argument comes from `resolveBlueprintTools` in
`seihou-cli/src/Seihou/CLI/AgentLaunch.hs`. It joins the blueprint's declared `allowedTools`
onto `setupAllowedTools`, the base set: `Bash(seihou *)`, `Bash(git *)`, `Bash(ls *)`,
`Bash(mkdir *)`, `Bash(cat *)`, `Bash(pwd)`, `Read`, `Write`, `Edit`, `Glob`, `Grep`,
`EnterWorktree` and `ExitWorktree`. A blueprint that declares nothing gets only these.

`seihou agent migrate` already detects denials. Its batch path,
`runAgentMigrationCompletionWithCliAccess` in `seihou-cli/src/Seihou/CLI/AgentCompletion.hs`,
registers a narrow adapter (`registerStrict`) under the same Baikai API key. The adapter builds
the argv with Baikai's `ClaudeCli.claudeCliCommand`, runs it with
`readCreateProcessWithExitCode` in the current directory, and passes stdout to
`validateMigrationOutput` in `seihou-cli/src/Seihou/CLI/AgentMigrationProtocol.hs`. On
`Right body` it returns a Baikai response holding `body`. On `Left err` it throws
`Baikai.providerError err`, which `runAgentCompletionUsing (^. #message)` turns back into
`Left err` with the text intact. `validateMigrationOutput`'s Claude branch already has the
denial renderer this plan needs: the local `deniedTools` and `commandDetail` functions produce
`Bash (nix build .#docs)` from each denial. Its other rules are stricter than a blueprint run
can accept (see the Decision Log). The adapter also adds `--permission-mode acceptEdits` and
the read-only `mori registry` grants of `migrationAllowedTools`, which a blueprint run must not
receive.

`seihou validate-blueprint [PATH]` is handled by `handleValidateBlueprint` in
`seihou-cli/src-exe/Seihou/CLI/ValidateBlueprint.hs`. `buildBlueprintReport` builds a list of
`DiagCheck label severity details` values (from `seihou-core/src/Seihou/Engine/Validate.hs`).
A check with no details renders as `✓ label`. A `DiagWarning` with details renders as
`⚠ label` with indented detail lines and does not affect the exit code. Only `DiagError`
checks with details make the command exit 1. Every check there today is `DiagError`. The
existing "Allowed tools" check (`checkBlueprintAllowedTools` in
`seihou-core/src/Seihou/Core/Blueprint.hs`) rejects blank entries only. The core
`validateBlueprint` functions in that module are also used at install time, so the new warning
must stay out of them.

Tests live in `seihou-cli/test/` and run under one tasty suite, `seihou-cli-test`. New spec
modules must be listed in `seihou-cli/test/Main.hs` and in the test-suite `other-modules`
of `seihou-cli/seihou-cli.cabal`. The end-to-end specs run the built `seihou` binary, located
by `seihouBinary` in `seihou-cli/test/Seihou/CLI/SeihouBinary.hs`. They put a fake `claude`
shell script first on `PATH` that prints a canned JSON reply. The existing batch `agent run`
proof is the case "automatically uses the batch CLI provider when stdin is not a terminal" in
`seihou-cli/test/Seihou/CLI/AgentMigrateE2ESpec.hs`, with its fixture `batchBlueprintDhall`.
That fixture has no base modules, so a run that fails before recording leaves no
`.seihou/manifest.json`. The migration denial cases are in `batchMigrationProof` in the same
file. `seihou-cli/test/Seihou/CLI/ValidateRecipeE2ESpec.hs` is the model for a validator
end-to-end spec.

Relevant ADRs. [ADR 0019](../adr/0019-non-terminal-blueprint-migrations-require-validated-batch-results.md)
decided that batch migrations go through a migration-specific adapter that validates the raw
process exit and structured output. It requires a Claude result with no reported permission
denials, adds no permission bypasses, and keeps that boundary "separate from ordinary text
completions". This plan extends the denial rule to batch blueprint runs. It does not extend
the rest of the migration contract, and it records that in a new ADR 0026 rather than
widening 0019. [ADR 0015](../adr/0015-diagnostics-name-things-as-users-do-and-never-fall-back-to-show.md)
requires diagnostics to name things as users write them. The error must therefore print the
tool and command as Claude reported them, and the warning must name the `allowedTools` field
as written in `blueprint.dhall`, never a Haskell `show`. No other ADR applies.

Related plans: [ExecPlan 111](111-run-blueprint-migrations-without-an-interactive-terminal.md)
built the migration adapter and its validator, and
[ExecPlan 31](31-blueprint-agent-runner.md) built `seihou agent run`.


## Plan of Work

Milestone 1 is a short prototype that changes no code. It answers whether real Claude Code
reports guard refusals in `permission_denials`. In a scratch git repository, run the installed
`claude` three times in print mode, the way Seihou does. First, run with only `Read` allowed
and ask for `nix --version`. Second, run with `Bash(echo *)` allowed and ask for
`echo hi > out.txt`. Third, run with `Write` allowed and ask it to write a file inside `.git/`.
Record each run's `permission_denials` in Surprises & Discoveries with the Claude Code version.
The milestone is accepted when all three are recorded, whatever they show. If a guard refusal
does not appear, say so in Surprises & Discoveries, amend the second Decision Log entry, and
carry the limit into ADR 0026 and the help text.

Milestone 2 makes the batch run fail. In `seihou-cli/src/Seihou/CLI/AgentMigrationProtocol.hs`,
lift `deniedTools`/`commandDetail` out of `validateMigrationOutput`'s `where` clause into a
top-level renderer. Each entry renders as `<tool_name> (<command truncated to 240
characters>)`, or as the tool name alone when `tool_input.command` is absent. Identical
entries are listed once, in first-seen order. After ten entries the list ends with
`and N more`. `validateMigrationOutput` keeps its wording and uses the shared renderer. Then
add and export `validateBatchRunOutput :: ByteString -> Either Text Text`, which applies the
rules from the Decision Log. It decodes stdout as a JSON object or a non-empty array of
objects, and the result event is the last element of an array. It collects
`permission_denials` from every event, and if any are found returns
`Left "Claude refused N tool call(s) during this unattended run: <list>. An unattended run cannot approve tools. Declare the commands the blueprint needs in its allowedTools, or run it interactively, then retry."`.
Otherwise it fails on `is_error: true` with the result text, fails on malformed JSON or a
blank `result`, and returns `Right result`. Use "tool call" for N = 1 and "tool calls"
otherwise.

In `seihou-cli/src/Seihou/CLI/AgentCompletion.hs`, factor `registerStrict`'s body into a
helper parameterised by the Claude extra arguments and the validator. Change
`runAgentCompletionWithCliAccess` so that a `claude-cli` request goes through
`runAgentCompletionUsing (^. #message)` with that helper registered. Give it extra arguments
`claudeAccessArgs dirs tools`, with no `--permission-mode` and no `migrationAllowedTools`,
and `validateBatchRunOutput`. Every other provider keeps
`runAgentCompletionWith (registerAgentProvidersWithCliAccess dirs tools)` exactly as today.
Keep the `--allowedTools`/`--add-dir` argv identical to today's stock provider, because the
existing e2e test asserts it. `runRenderedAgentPromptMode` needs no change: its `Left`
branch already prints `Error: …`, exits 1 and skips the manifest write. Update the doc comment
on `runAgentCompletionWithCliAccess` to say it validates Claude's refusals.

Add tests at two levels. In `seihou-cli/test/Seihou/CLI/AgentCompletionSpec.hs`, or a new
`AgentBatchProtocolSpec.hs` if that file gets crowded, unit-test `validateBatchRunOutput`.
Cover a bare object with no denials (Right). Cover the legacy fixture shape without
`permission_denials` or `subtype` (Right). Cover an array whose result event has one Bash
denial (Left, naming the command). Cover duplicated denials (listed once), `is_error: true`
(Left), and `"not-json"` (Left). In `seihou-cli/test/Seihou/CLI/AgentMigrateE2ESpec.hs`, next
to the existing batch case, add "fails a batch run whose agent was refused a tool". It is a
copy of that case whose fake `claude` prints
`{"type":"result","subtype":"success","is_error":false,"result":"could not build","permission_denials":[{"tool_name":"Bash","tool_use_id":"t1","tool_input":{"command":"nix build .#docs"}}]}`.
It asserts a non-zero exit, that stdout contains `nix build .#docs` and `allowedTools`, and
that `.seihou/manifest.json` does not exist. Run the whole suite. The existing batch and trace
end-to-end cases must still pass with their legacy fixtures.

Milestone 3 adds the validation warning. In `seihou-cli/src/Seihou/CLI/AgentLaunch.hs`, next
to `resolveBlueprintTools`, add and export
`undeclaredAllowedToolsWarning :: Maybe [Text] -> [Text]`. It returns `[]` when the list has
at least one entry. Otherwise it returns one detail line:
`allowedTools is not declared, so an unattended run pre-approves only Seihou's setup tools: <setupAllowedTools joined by ", ">. Claude refuses every other command the prompt needs. Declare them, for example allowedTools = Some [ "Bash(nix *)" ].`
Render the list from `setupAllowedTools` itself so the two cannot drift. In
`seihou-cli/src-exe/Seihou/CLI/ValidateBlueprint.hs`, add
`DiagCheck "Allowed tools declared" DiagWarning (undeclaredAllowedToolsWarning (b ^. #allowedTools))`
after the existing "Allowed tools" check, and update `buildBlueprintReport`'s comment, which
says lint warnings are not implemented. Unit-test the function in
`seihou-cli/test/Seihou/CLI/AgentLaunchSpec.hs` for `Nothing`, `Just []` and
`Just ["Bash(nix *)"]`. Add `seihou-cli/test/Seihou/CLI/ValidateBlueprintE2ESpec.hs` and
register it in `Main.hs` and the cabal file. It writes a minimal blueprint without
`allowedTools` (`allowedTools = None (List Text)`) and asserts exit 0, `⚠ Allowed tools
declared`, `allowedTools is not declared` and `is valid.`. A second blueprint with
`allowedTools = Some [ "Read" ]` must print `✓ Allowed tools declared`.

Milestone 4 documents the behavior and closes the request. Describe the refusal failure where
batch blueprint runs are explained in `seihou-cli/help/agent.md`, `docs/user/blueprints.md`
and `docs/user/agent-assistance.md`. Describe the warning in `docs/cli/validate-blueprint.md`
and next to the `allowedTools` field in `seihou-cli/help/blueprints.md`. Write
`docs/adr/0026-a-batch-blueprint-run-fails-on-reported-tool-refusals.md` in the format of the
existing ADRs. Its context is IR-18. Its decision is the denial rule, the tolerated-absence
rule and the Claude-only scope. Its consequences are the lost trace usage and the possible
Baikai follow-up. Link it from ADR 0019's Consequences with one sentence. Then update IR-18
per the improvement-request bundle's conventions: `status: completed`, `completedAt`,
`resolution`, the Status prose, and a dated entry in `docs/improvement-requests/log.md`, as
done for IR-9.


## Concrete Steps

All commands run from the repository root,
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`, unless they say otherwise.

Milestone 1, in a throwaway directory. These calls use the developer's authenticated Claude
Code and spend a little usage:

```bash
probe=$(mktemp -d) && cd "$probe" && git init -q
claude --version
claude -p --output-format json --no-session-persistence --allowedTools "Read" \
  -- "Run the shell command: nix --version" \
  | jq '[.. | objects | select(has("permission_denials")) | .permission_denials] | add'
claude -p --output-format json --no-session-persistence --allowedTools "Bash(echo *)" \
  -- "Run exactly this shell command and nothing else: echo hi > out.txt" \
  | jq '[.. | objects | select(has("permission_denials")) | .permission_denials] | add'
claude -p --output-format json --no-session-persistence --allowedTools "Write" \
  -- "Write the text probe to the file .git/seihou-probe and do nothing else" \
  | jq '[.. | objects | select(has("permission_denials")) | .permission_denials] | add'
```

For the first call, the expected output is an array holding a `Bash` entry whose
`tool_input.command` is `nix --version`. Record all three outputs, trimmed, in Surprises &
Discoveries.

Milestones 2 and 3, building and testing:

```bash
cabal build seihou-cli:exe:seihou seihou-cli:test:seihou-cli-test
cd seihou-cli
$(cabal list-bin seihou-cli-test) -p '/refused/ || /AgentMigrationProtocol/'
$(cabal list-bin seihou-cli-test) -p '/ValidateBlueprint/ || /undeclaredAllowedToolsWarning/'
$(cabal list-bin seihou-cli-test)
```

Run the test binary from `seihou-cli/`, as `cabal test` does. The end-to-end specs find the
schema submodule at `../schema`, and from the repository root about 90 of them fail with
`git -C …/seihou-project/schema … (exit 128)`. A `-p` pattern containing spaces or `||` does
not survive `cabal test --test-options` quoting, so the commands call the binary directly.

The pre-commit hook runs the module-placement, record-convention and treefmt checks. To run
them by hand:

```bash
nix flake check
```

A manual check after Milestone 3, against any blueprint that lacks `allowedTools`:

```bash
cabal run seihou -- validate-blueprint path/to/blueprint-dir; echo "exit=$?"
```

```text
  ✓ Allowed tools
  ⚠ Allowed tools declared
      allowedTools is not declared, so an unattended run pre-approves only Seihou's setup tools: Bash(seihou *), Bash(git *), …

Blueprint 'example' is valid.
exit=0
```

Commit at each milestone boundary with Conventional Commits messages and both trailers:

```text
fix(agent): fail a batch blueprint run whose agent was refused tools

ExecPlan: docs/plans/122-fail-a-batch-blueprint-run-whose-agent-was-refused-tools.md
Intention: intention_01m75e3qgtecntc0t04z9e9a49
```


## Validation and Acceptance

These are IR-18's acceptance criteria, stated as observable behavior.

A batch run whose agent is refused a command fails. With a fake `claude` reporting the
`nix build .#docs` denial shown in the Plan of Work, `seihou agent run batch-blueprint --batch`
exits with status 1. Its stdout contains `Claude refused 1 tool call`, `Bash (nix build .#docs)`
and `allowedTools`, and `.seihou/manifest.json` is not created. The new end-to-end case in
`AgentMigrateE2ESpec` proves this, and it fails if the change is reverted.

A run with no refusals behaves as before. The existing case "automatically uses the batch CLI
provider when stdin is not a terminal" passes unchanged: exit 0, `batch complete` printed, the
manifest written, and `-p`, `--allowedTools` and `--add-dir` in the argv. So do the five
`AgentTraceE2ESpec` cases, whose fixtures omit `permission_denials` and `subtype`.

`seihou validate-blueprint` on a blueprint without `allowedTools` prints a warning that names
the field and still exits 0. The new `ValidateBlueprintE2ESpec` proves this, and its
declared-tools case shows the warning is absent when tools are declared.

A fake-provider test covers `agent run --batch`, as `AgentMigrateE2ESpec` does for
`agent migrate`. This is the new denial case above.

`cabal test seihou-cli-test` passes in full and `nix flake check` passes.

IR-18's optional early stop is out of scope (see the Decision Log). Codex batch runs are also
out of scope and keep their current behavior.


## Idempotence and Recovery

Every change is additive or a local refactor, and all steps can be repeated. The Milestone 1
probe writes only inside its own `mktemp -d` directory. A failed real run leaves the same
partial state any failed batch run leaves today. The baseline modules applied before the agent
started stay applied, and the applied-blueprint entry is not written. The user fixes the
blueprint's `allowedTools` and reruns. Reverting the Milestone 2 commit restores the old
behavior exactly. There is no schema or manifest change, so no migration or backup is needed.


## Interfaces and Dependencies

These interfaces must exist at the end. In `seihou-cli/src/Seihou/CLI/AgentMigrationProtocol.hs`
(library), export:

```haskell
validateMigrationOutput :: Bool -> ByteString -> Either Text Text   -- unchanged contract
validateBatchRunOutput :: ByteString -> Either Text Text            -- new; Claude CLI stdout
```

In `seihou-cli/src/Seihou/CLI/AgentCompletion.hs`, the signature of
`runAgentCompletionWithCliAccess :: [FilePath] -> [String] -> AgentCompletionRequest -> IO (Either Text Text)`
is unchanged. Its `claude-cli` behavior now rejects reported denials.

In `seihou-cli/src/Seihou/CLI/AgentLaunch.hs`, export:

```haskell
undeclaredAllowedToolsWarning :: Maybe [Text] -> [Text]
```

The plan depends on Baikai's `Baikai.Provider.Claude.Cli.claudeCliCommand`, `ClaudeCliConfig`
(`extraArgs`) and `Baikai.registerApiProvider`/`apiProviderWith`/`liftCompleteToStream`, all
already used by the migration adapter. It also depends on Claude Code's
`--output-format json` result fields: `result`, `is_error`, and `permission_denials` with
`tool_name` and `tool_input.command`. No new package dependency is added, and this plan has
no parent MasterPlan.
