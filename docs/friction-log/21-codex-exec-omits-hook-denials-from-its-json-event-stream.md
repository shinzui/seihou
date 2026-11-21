---
type: Friction Entry
title: "Codex exec omits hook denials from its JSON event stream"
description: "A working PreToolUse denial has no structured result a batch caller can use to withhold a receipt."
generated:
  by: "codex-cli/gpt-6.2-astra"
  at: "2026-11-21T15:39:15Z"
frictionId: FRIC-21
status: "promoted"
impact: blocked
kind: interface
origin: "mori://shinzui/seihou"
affects: "https://github.com/openai/codex"
affectedVersion: "0.171.0"
plan: "docs/plans/127-let-callers-supply-tool-policy-for-batch-blueprint-runs-and-migrations.md"
promotedTo: "mori://shinzui/baikai/okf/improvement-requests/concepts/IR-14"
amended:
  - by: "codex-cli/gpt-6.2-astra"
    at: "2026-11-21T16:22:19Z"
    change: "Baikai IR-14 owns the app-server path that reports a blocked pre-tool hook and verifies existing review before a turn."
---
# Codex exec omits hook denials from its JSON event stream

## Attempted

Run a blocking PreToolUse hook in an ephemeral workspace-write Codex session and compare its JSON items with a command that exits 1.

## Encountered

The blocked run exited 0 and omitted the command item. Both runs produced identical trust warnings as error items. Only the ordinary command failure emitted a command_execution item.

```text
A diagnostic on stderr named the blocked command. The hook recorded Bash and the command produced no marker.
```
