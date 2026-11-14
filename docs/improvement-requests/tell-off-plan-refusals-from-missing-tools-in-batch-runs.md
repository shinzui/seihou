---
type: Improvement Request
title: Tell off-plan refusals from missing tools in a batch blueprint run
description: >-
  Let a batch blueprint run that finished its work despite refused calls the blueprint never
  asked for (wrapped commands, filesystem-wide searches, calls added by the user's own hooks)
  be reported as completed with refusals instead of failing outright, so the refusal check
  from IR-18 stops discarding finished, valid runs.
generated:
  by: process:claude-code
  at: "2026-11-14T05:05:00Z"
timestamp: 2026-11-14T05:05:00Z
requestId: IR-20
status: proposed
origin: mori://tan/tan-seihou-modules
---

# Improvement Request: Tell Off-Plan Refusals From Missing Tools in Batch Runs

## Status

Proposed. It refines, and does not reverse, IR-18
([fail a batch blueprint run whose agent was refused tools](fail-a-batch-blueprint-run-whose-agent-was-refused-tools.md))
and [ADR 0026](../adr/0026-a-batch-blueprint-run-fails-on-reported-tool-refusals.md). Raised
from `mori://tan/tan-seihou-modules/okf/friction-log/concepts/FRIC-6` against Seihou 0.16.0.0
(`63cb35d`) and Claude Code 2.1.325.

## Context

IR-18 made a batch `seihou agent run` on `claude-cli` exit 1 when Claude reports any refused
tool call. Its premise is that "a refusal is work the blueprint expected and did not get".
That holds when the agent was refused a command the prompt told it to run. It does not hold
for calls the blueprint never asked for.

`mori://tan/tan-seihou-modules` ran its `tan-staging-stack-onboarding` blueprint unattended
three times to rebuild a real Pulumi program. Each run finished the work: the program
type-checked, every test passed, and the report was complete. Each run still exited 1:

- Run 1: 11 refusals. The agent wrapped approved commands
  (`echo ... && bash scripts/check-pulumi-version.sh ...; echo EXIT=$?`,
  `cd <other repo> && ...`), and a SessionStart hook in the user's own Claude settings made
  it call `rex session rename`, which no blueprint could anticipate.
- Run 2, after the prompt demanded bare commands in the approved form: 1 refusal, a
  `cd <repo> && find / ...`.
- Run 3: 4 refusals, two of them `find /` searches, a shell loop, and
  `pnpm --dir pulumi exec vitest run ...`.

The refusals were correct, and several were exactly what the approvals exist to stop. But
widening `allowedTools` to admit them would weaken the only technical control a blueprint
has, and the prompt cannot make an agent stop wrapping commands. Under the current rule a
batch run of this blueprint cannot pass however well it does its work.

## Requested outcome

A batch run distinguishes "the agent did not get a tool it needed" from "the agent tried
something off-plan and was correctly stopped", and gives the caller a way to accept the
second. Options, not mutually exclusive:

1. A blueprint-level declaration, for example
   `batchRefusals = Some "report"`, under which refusals are listed in the output and in
   the applied-blueprint record, and the run succeeds when the provider otherwise reports
   success. The default stays IR-18's fail-closed behaviour.
2. A per-invocation flag such as `--allow-refusals`, with the same effect, for a person who
   reviews the result anyway.
3. A distinct exit status (not 0, not 1) for "completed with refusals", so automation can
   choose.

In every option the refusal list stays visible and is recorded, so nothing is hidden.

## Acceptance sketch

A batch run of a fixture blueprint whose stub agent completes and reports one refused,
undeclared command exits 1 by default (IR-18 unchanged), and succeeds with the refusal
listed and recorded when the blueprint or invocation opts in. A refusal of a command the
blueprint's own `allowedTools` should have covered is still distinguishable in the output.
