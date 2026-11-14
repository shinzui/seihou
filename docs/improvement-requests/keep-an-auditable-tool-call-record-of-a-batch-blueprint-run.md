---
type: Improvement Request
title: Keep an auditable tool-call record of a batch blueprint run
description: >-
  Give a batch seihou agent run on claude-cli a way to keep the agent's tool calls, because
  Baikai launches Claude with --no-session-persistence and the trace sink records only call
  timing, so nobody can show afterwards which commands an unattended agent executed.
generated:
  by: process:claude-code
  at: "2026-11-14T05:05:00Z"
timestamp: 2026-11-14T05:05:00Z
requestId: IR-21
status: proposed
origin: mori://tan/tan-seihou-modules
---

# Improvement Request: Keep an Auditable Tool-Call Record of a Batch Blueprint Run

## Status

Proposed. Raised from `mori://tan/tan-seihou-modules/okf/friction-log/concepts/FRIC-5`
against Seihou 0.16.0.0 (`63cb35d`), Baikai `87481ea` and Claude Code 2.1.325.

## Context

Blueprints often carry rules the tool settings cannot enforce. `allowedTools` only adds
approvals to a base set that already includes `Bash(git *)`, so a blueprint that forbids
`git commit` or `git push` relies on its prompt, and on someone checking afterwards what the
agent actually ran.

For a batch run there is nothing to check. `mori://tan/tan-seihou-modules` needed to show
that its onboarding blueprint's agent ran no forbidden command. After a batch run, the
project's directory under `~/.claude/projects` held only a subagent `meta.json`. The cause
is in `mori://shinzui/baikai`: the Claude CLI provider passes
`--output-format json --no-session-persistence`
(`baikai-claude/src/Baikai/Provider/Claude/Cli.hs`, line 142), so Claude writes no session
file, and the json output carries only the final result and `permission_denials`. Seihou's
`--trace file` records `call_started` / `call_finished` events with timing, not tool calls
(`docs/user/agent-assistance.md`, "The trace file").

The workaround was to put logging stand-ins for `git`, `gh` and `pulumi` first on `PATH` and
audit their log. It works for named executables only, not for file edits or other tools.

## Requested outcome

An opt-in record of every tool call a batch run made: the tool, its input (command line or
file path), whether it was allowed or refused, and its exit status where one exists. Ways to
get there:

1. A setting such as `agent.run.keepSession` (or `--keep-session`) that omits
   `--no-session-persistence`, and prints the session file's path at the end of the run.
   Baikai's Claude agent provider already has a persist option
   (`baikai-claude/src/Baikai/Provider/Claude/Agent.hs`).
2. Running Claude with `--output-format stream-json` in batch mode and writing each
   `tool_use` and `tool_result` event to the existing trace sink as a new event kind, while
   still deriving the final answer and `permission_denials` from the stream.

Option 2 keeps the record beside Seihou's other trace data and works the same in CI.

## Acceptance sketch

A batch run of a fixture blueprint whose agent runs one allowed and one refused command
leaves a record, at a path the run prints, listing both commands with their outcomes. With
the setting off, behaviour is unchanged.
