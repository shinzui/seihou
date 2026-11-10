---
type: Improvement Request
title: Fail a batch blueprint run whose agent was refused tools
description: >-
  Make seihou agent run --batch exit non-zero, and name the refused commands, when the agent
  was denied tools during the run, instead of exiting 0 after an hour of work the blueprint
  could not do; and warn at validation when a blueprint declares no allowedTools.
generated:
  by: process:claude-code
  at: "2026-11-10T22:29:39Z"
timestamp: 2026-11-10T22:29:39Z
requestId: IR-18
status: proposed
origin: mori://shinzui/kotei-docs
reviews:
  - kind: model
    reviewer: process:claude-code
    provider: anthropic
    model: claude-opus-5-5
    effort: unspecified
    reviewed_at: "2026-11-10T22:29:39Z"
    document_timestamp: "2026-11-10T22:29:39Z"
    scope: content-and-metadata
    outcome: commented
    context: >-
      Author check against the Seihou source at fcaa6f4 and two real batch runs on Seihou
      0.15.0.0. The cause of the missed denials is not established. Not an independent
      approval.
---

# Improvement Request: Fail a Batch Blueprint Run Whose Agent Was Refused Tools

## Status

Proposed. Raised from `FRIC-5`
(`mori://shinzui/kotei-docs/okf/friction-log/concepts/FRIC-5`) against Seihou 0.15.0.0.
No implementation plan exists.

## Context

The first unattended rehearsal of `relaunch-fumadocs-docs` 0.1.0 ran
`seihou agent run relaunch-fumadocs-docs --batch …` on a scratch clone of
`mori://shinzui/shomei-docs`. The blueprint declared no `allowedTools`, so the Claude
CLI refused every command outside Seihou's setup tool set: `mori`, `nix`, `bun`,
`container`, `cp`, `mktemp` and `shasum`. The agent worked around what it could for
about an hour. Its final message listed the operations it could not perform: the recipe
application, `bun install`, `nix build`, the container proofs, the source pin, and most
of the assessment. Seihou printed that message and exited 0.

A later run, with the tools declared, still reported that writes inside `.git/` and
shell redirection had needed approval that an unattended run cannot give. That run also
exited 0.

## Problem

The batch path in `runRenderedAgentPromptMode` (`seihou-cli/src-exe/Seihou/CLI/AgentRun.hs`)
goes through `runAgentCompletionWithCliAccess`, which calls `validateMigrationOutput`.
`seihou-cli/src/Seihou/CLI/AgentMigrationProtocol.hs` rejects a Claude result whose
`permission_denials` array is not empty. Despite that check, both runs above exited 0
after refusals. Either these refusals are not reported in `permission_denials`, or the
batch run takes a path that skips the check. That is not established here, and should
be the first step of any plan.

The result is costly. A batch run is how a blueprint is qualified, and an exit 0 after
refusals looks like a pass. Nothing at authoring time warns that a blueprint whose
prompt runs project tools has declared none.

## Requested change

1. Determine why the refusals above did not fail the run, and make any tool refusal in a
   batch `seihou agent run` exit non-zero. Name the refused tool and command, as the
   `agent migrate` path already does with `Claude reported permission denials: …`.
2. Have `seihou validate-blueprint` warn when a blueprint has no `allowedTools`, since a
   batch run then gets only the setup tools.
3. Optionally, stop a batch run at the first refusal instead of letting it continue for
   the whole session.

## Acceptance criteria

- A batch `seihou agent run` whose agent is refused a `Bash` command exits non-zero and
  prints the refused command.
- A run with no refusals behaves as today.
- `seihou validate-blueprint` on a blueprint without `allowedTools` prints a warning
  naming the field, and still exits 0.
- A test with a fake provider that reports a denial covers `agent run --batch`, as
  `AgentMigrateE2ESpec` does for `agent migrate`.

## Scope and design questions

Some refusals come from the provider's own guards, not from the allow list: for
example, writes inside `.git/` and shell redirection. Whether Seihou can see those, and
whether they should fail a run or only be listed, needs a decision.

## Related

- `mori://shinzui/kotei-docs/okf/friction-log/concepts/FRIC-5`
- [IR-6](supply-an-initial-instruction-to-cli-providers.md), on CLI provider batch runs
- [IR-17](refresh-installed-blueprints-in-seihou-upgrade.md), the other half of FRIC-5
