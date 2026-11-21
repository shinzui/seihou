---
type: Improvement Request
title: Let a caller supply the tool policy of a batch blueprint run
description: >-
  Give an orchestrator that already gates and records commands, such as a Shikigami playbook,
  a way to supply or widen the tool policy of a batch seihou agent run, because a blueprint
  whose allowedTools are narrower than its own instructions cannot run unattended at all, and
  the --debug route that would let the caller apply it another way writes a blueprint receipt.
generated:
  by: process:claude-code
  at: "2026-11-16T01:25:00Z"
timestamp: "2026-11-21T15:49:46Z"
requestId: IR-23
status: in-progress
targetPlan: docs/plans/127-let-callers-supply-tool-policy-for-batch-blueprint-runs-and-migrations.md
origin: mori://shinzui/shikigami
---

# Improvement Request: Let a Caller Supply the Tool Policy of a Batch Blueprint Run

## Status

Claude support has passed source-level consumer acceptance. Release and installed acceptance are pending. It builds on IR-18
([fail a batch blueprint run whose agent was refused tools](fail-a-batch-blueprint-run-whose-agent-was-refused-tools.md)),
whose fail-closed exit is what surfaced the problem, and is complementary to IR-20
([tell off-plan refusals from missing tools](tell-off-plan-refusals-from-missing-tools-in-batch-runs.md))
and IR-21 ([keep an auditable tool-call record](keep-an-auditable-tool-call-record-of-a-batch-blueprint-run.md)).
Raised from the keiro modernization campaign of
`mori://shinzui/shikigami/masterplans/22-rebuild-shikigami-as-a-kernel-where-use-cases-are-declared-not-coded`
(ExecPlan `mori://shinzui/shikigami/plans/132-modernize-the-keiro-services-with-a-declared-campaign-playbook`).

## Context

A Shikigami playbook runs each selected blueprint as a declared, durable tool step:
`seihou agent run <blueprint> --batch` (or `migrate … --from=<v> --batch`) in the target
repository, under a deadline of hours. Shikigami already decides every command its own coding
agents run, through a PreToolUse hook that admits only declared argument patterns and records
each decision. Seihou's batch run starts its own Claude session whose tool limits come only
from the blueprint's `allowedTools`.

## Problem

On 2026-11-16 the kizashi pilot ran
`seihou agent run fix-nix-haskell-flake-customizations --batch` (seihou-modules 0.2.0). After
316 seconds and about 1,100 lines of edits it exited 1, because Claude refused ten Bash calls
that the blueprint's own guidance leads the agent to make:

* backups before editing (`mkdir -p /tmp/kizashi-fix && cp flake.nix … /tmp/kizashi-fix/`);
* the before/after dev-shell comparison
  (`nix print-dev-env --accept-flake-config 2>/dev/null > .dev/fix-backup/devenv.before`, and
  pipelines over its output);
* inspections such as `seihou list | grep …` and `grep -A12 … flake.lock`;
* a `rex session rename` that the operator's own session hook asks every Claude session for.

IR-18 worked as designed: the run failed and recorded no applied blueprint. The working tree,
however, was left half-applied, with no receipt and no way to resume. The caller has no lever.
It cannot widen the policy for one run, and it cannot give the run its own gate, even though it
already confines and records commands more precisely than a static allow list can.

The obvious workaround fails too. A caller that wants to apply the blueprint itself can render
its prompt with `seihou agent --debug run <blueprint>`, but that command writes a `blueprint`
record (name, origin, version, `appliedAt`) into `.seihou/manifest.json`, as if the blueprint
had been applied. The campaign had to render the prompt in a throwaway worktree.

## Requested outcome

A batch run accepts a tool policy from its caller, recorded with the run. Options, not mutually
exclusive:

1. `--allowed-tool PATTERN` (repeatable), which adds Claude permission rules to the
   blueprint's `allowedTools` for this invocation, recorded in the applied-blueprint record.
2. `--settings FILE` passed through to the provider, so an orchestrator can install its own
   PreToolUse hook and permission rules; Seihou records the file's digest.
3. A blueprint-level declaration of the commands its guidance requires (backups, dev-shell
   comparison), checked by `seihou validate-blueprint` against the prompt's own instructions.

Separately, `seihou agent --debug run` should not record the blueprint as applied; that defect
is tracked as [BUG-5](../bug-reports/a-debug-blueprint-run-records-the-blueprint-as-applied.md).

## Acceptance sketch

A batch run of a fixture blueprint whose stub agent needs one command outside the blueprint's
`allowedTools` fails as today (IR-18). It succeeds, with the extra rule recorded, when the
invocation supplies that rule, or a settings file whose hook admits it. `seihou agent --debug
run <fixture>` leaves `.seihou/manifest.json` byte-for-byte unchanged.
