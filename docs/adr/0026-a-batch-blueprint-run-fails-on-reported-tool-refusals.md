# ADR 0026 — A batch blueprint run fails on reported tool refusals

- Status: Accepted
- Date: 2026-11-11

## Context

[IR-18](../improvement-requests/fail-a-batch-blueprint-run-whose-agent-was-refused-tools.md)
reported that a batch `seihou agent run` exited 0 after Claude Code had refused
the commands the blueprint needed for about an hour. A batch run (`--batch`, or
stdin that is not a terminal) has no one to approve tools. Claude ends such a
session normally, with `subtype: success` and `is_error: false`, and lists the
refusals in its result's `permission_denials` array. Baikai's Claude CLI
provider reads `result` and `is_error` and drops `permission_denials`, so
Seihou saw an ordinary success and recorded the blueprint as applied.

Claude Code 2.1.322 reports three kinds of refusal there. The first is a
command missing from `--allowedTools`. The other two are guarded writes that
`Write` or `Bash(echo *)` do not cover: a file inside `.git/`, and a shell
redirection. A batch run also inherits the user's Claude Code hooks and global
instructions, and commands they prompt are refused and reported in the same
array.

[ADR 0019](0019-non-terminal-blueprint-migrations-require-validated-batch-results.md)
already requires a migration's Claude result to carry no permission denials,
through a migration-specific adapter. It keeps that contract separate from
ordinary text completions.

## Decision

A batch `agent run` on `claude-cli` goes through a Seihou-side adapter that
runs `claude` itself and validates its JSON output. The adapter passes the
same `--allowedTools` and `--add-dir` arguments as before, and none of the
migration-only arguments: no `--permission-mode` and no Mori grants.

The run fails on any reported refusal, whatever caused it: the blueprint's
allow list, a provider guard, or the user's own hooks. Seihou cannot tell
these apart, and an unattended run cannot grant any of them. The error names
each refused tool with its command or file path, and no applied blueprint is
recorded.

Only the refusal rule is added. The run also fails on `is_error: true`,
malformed JSON and a blank result, as before. A missing `permission_denials`,
`type` or `subtype` still passes, so the older result shape is accepted. This
is deliberately looser than ADR 0019's fail-closed migration rules.

`codex-cli` batch runs keep Baikai's stock provider. Codex has no per-tool
allow list, and its failed-item events include ordinary failing commands.

`seihou validate-blueprint` warns, without failing, about a blueprint that
declares no `allowedTools` or an empty list.

## Consequences

A batch `claude-cli` run reports zero usage and none of Baikai's subprocess
evidence, so its trace has no token counts or session id. The migration
adapter has the same cost. If Baikai later exposes the denials on its report,
both adapters can return to the stock provider.

A user whose hooks or global instructions prompt commands in every session
will see batch runs fail until those commands are granted in their Claude Code
settings. The error names the commands, so the cause is visible.

A run is not stopped at its first refusal. With `--output-format json`,
refusals arrive only in the final result. Stopping early would need streamed
output. Refusals that the agent describes only in prose, without a tool call,
remain undetected.

Implementation: [plan 122](../plans/122-fail-a-batch-blueprint-run-whose-agent-was-refused-tools.md).
