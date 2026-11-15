---
type: Improvement Request
title: Start interactive blueprint runs with an initial message
description: >-
  Make an interactive seihou agent run start the blueprint when PROMPT is omitted,
  instead of opening an empty input box and silently waiting for a first message.
generated:
  by: process:codex-cli/gpt-6.1-sol
  at: "2026-11-15T16:10:53Z"
timestamp: 2026-11-15T16:10:53Z
requestId: IR-22
status: proposed
origin: mori://tan/tan-seihou-modules
reviews:
  - kind: model
    reviewer: process:codex-cli
    provider: openai
    model: gpt-6.1-sol
    effort: unspecified
    reviewed_at: "2026-11-15T16:11:43Z"
    document_timestamp: "2026-11-15T16:10:53Z"
    scope: content-and-metadata
    outcome: commented
    context: >-
      Author check against the source friction entry, IR-6 and the current
      AgentLaunchExec implementation. No real provider session reproduced during
      this request's creation; this is not an independent approval.
---

# Improvement Request: Start Interactive Blueprint Runs with an Initial Message

## Status

Proposed. Raised from
`mori://tan/tan-seihou-modules/okf/friction-log/concepts/FRIC-15`.
This is fresh consumer evidence for the interactive-launch work remaining in
[IR-6](supply-an-initial-instruction-to-cli-providers.md) and
[ExecPlan 106](../plans/106-supply-default-initial-instructions-to-cli-agent-providers.md).
Coordinate delivery through that work rather than introducing a separate prompt policy.

## Observed workflow

During Milestone 6 of
`mori://tan/tan-seihou-modules/plans/5-onboard-tan-services-to-production-with-a-seihou-module-and-blueprint`,
the operator started the chapter-service-v2 production onboarding blueprint interactively
in a Rex tab. Claude Code opened at zero tokens with an empty input box and a placeholder.
There was no indication that a first user message was required, and no work began.

The recorded launch supplied the blueprint as a system prompt:

```text
claude --model claude-opus-4-8 --effort medium --system-prompt You are running a Seihou blueprint ...
```

The operator had to send a kickoff message such as
`Start the onboarding now: work through the blueprint steps in order`.
Passing the optional trailing `PROMPT` to `seihou agent run` is another workaround.
The friction entry does not record an executable version.

## Current source evidence

`seihou-cli/src-exe/Seihou/CLI/AgentLaunchExec.hs` constructs both Claude and Codex
interactive launch requests with `interactiveLaunchRequest (promptOrEmpty initialPrompt)`.
Its `promptOrEmpty = maybe "" id` supplies empty text when the argument is omitted.
This matches the remaining interactive-launch gap documented in IR-6. The Claude behavior
above was observed directly; this report does not claim a reproduced Codex session.

## Requested outcome

The ordinary command `seihou agent run BLUEPRINT`, with the blueprint's required variables
supplied, should start an initial turn using the blueprint instructions without requiring
the operator to discover and type a kickoff message. Apply the shared CLI-provider fallback
policy already described in IR-6 and plan 106, including omitted and whitespace-only prompts.
Preserve a nonblank explicit user prompt exactly.

Help and launch output should make the behavior discoverable: explain that omitting `PROMPT`
starts the blueprint using a default initial instruction. If a supported launch mode
deliberately waits for user input, it must say that it is waiting and state the next action.

## Acceptance sketch

- From an installed fixture blueprint, run `seihou agent run BLUEPRINT` interactively with
  no trailing prompt. The provider receives a nonblank initial user message as well as the
  blueprint system prompt, and begins its first turn without keyboard input.
- Verify the launch boundary for both supported interactive CLI providers, using a fake
  provider executable to capture arguments and a real interactive smoke check for the
  reported Claude workflow.
- Omitted, empty and whitespace-only prompts use the shared fallback; an explicit nonblank
  prompt is passed through unchanged. Debug output makes the effective initial instruction
  inspectable while recorded provenance retains the original user input.
- The normal command and its help explain what starts automatically and when input is needed.
  Record the executable/version used for the consumer check before marking this delivered.
