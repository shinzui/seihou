---
type: Improvement Request
title: Supply an initial instruction to CLI providers, or require one
description: >-
  Make seihou agent migrate work without a trailing PROMPT on the default claude-cli provider,
  which today fails on its first edge because claude -p requires a user message and seihou sends
  only a system prompt.
generated:
  by: process:claude-code
  at: "2026-08-17T16:30:00Z"
timestamp: 2026-08-17T16:30:00Z
requestId: IR-6
status: proposed
origin: mori://shinzui/okf-profiles
---

# Improvement Request: Supply an Initial Instruction to CLI Providers, or Require One

## Context

`seihou agent migrate BLUEPRINT [PROMPT]` takes an optional trailing prompt.
`docs/user/blueprint-migrations.md` describes it as a convenience:

> An optional trailing `PROMPT` argument is passed as the initial user instruction to every session
> in the chain

and the type matches that description — `initialPrompt :: !(Maybe Text)` in
`seihou-cli/src/Seihou/CLI/AgentCompletion.hs`. Every worked example in that guide omits it:

```sh
seihou agent migrate my-library
seihou agent migrate my-library --from 1.0.0 --to 3.0.0
```

## Problem

**Omitting it does not work on the default provider.** `claude-cli` invokes `claude -p`, which
requires input on stdin or as a prompt argument. With no `initialPrompt`, seihou sends a system
prompt and no user message, and the CLI exits 1 before the session starts:

```text
Error: Input must be provided either through stdin or as a prompt argument when using --print
[error] Blueprint migration kiroku-upgrade 0.7.0.1 -> 0.8.0.0 (entailed by keiro-upgrade
        0.12.0.0 -> 0.13.0.0) failed; completed earlier edges remain recorded. Provider exited
        with ExitFailure 1. Fix the provider error, then rerun the same command to resume.
```

Observed 2026-08-17 running `mori://shinzui/keiro`'s `keiro-upgrade` blueprint against
`mori://shinzui/mori`, on seihou v0.7.0.0 with no `agent.provider` configured — so this is the
default path, not an exotic configuration. Re-running the identical command with any trailing
prompt succeeds and completes both edges.

The failure is total rather than partial: it happens on the *first* edge of every chain, so a
consumer following the documented invocation never reaches a single migration. It is also
self-concealing — the error is attributed to the provider ("Fix the provider error"), which points
a user at their Claude Code installation rather than at a missing argument seihou documents as
optional.

## Why the surrounding behaviour is not at fault

Everything seihou does *around* the failure is correct and should not change:

- No receipt was written, so the chain is resumable at the failed edge.
- No source file was touched.
- The message correctly says completed earlier edges remain recorded and to rerun to resume.

The defect is only that the default invocation cannot reach a provider session at all.

## Requested change

Any of these resolves it; the first is preferable.

1. **Send a default initial instruction when none is given.** The system prompt already contains
   the entire edge — the blueprint identity, the version window, the reference files, the shared
   guidance, and the edge instructions. A neutral user message such as `Apply this migration edge
   to this repository.` adds no guidance and makes the documented invocation work. `seihou agent
   run` should be checked for the same gap.
2. **Require `PROMPT` for CLI providers** and reject its absence in the argument parser, with a
   message naming the provider. Worse ergonomics, but honest, and it fails before any edge is
   planned rather than after.
3. **Have the provider adapter supply the fallback**, so each CLI provider states what it needs
   rather than seihou encoding one CLI's requirement. This is the most correct layering if
   `codex-cli` turns out to have the same constraint.

Whichever is chosen, the API providers (`anthropic`, `openai`) already accept a system prompt with
no user message, so their behaviour should be left alone — which is an argument for shape 3.

## Scope

`seihou agent migrate` observed directly. `seihou agent run`, `assist`, `bootstrap`, and `setup`
share `buildAgentCompletionRequestWith` and should be checked for the same gap; this request does
not assume they have it.

## Related

Adjacent to [IR-5](verify-an-entailed-edge-is-reachable-by-consumers.md) only in how it was found —
both surfaced while running a real cohort migration end to end rather than previewing one. IR-5 is
about a check that passes when it should not; this is about a documented invocation that fails when
it should not. Neither is visible from `--debug`, which contacts no provider.
