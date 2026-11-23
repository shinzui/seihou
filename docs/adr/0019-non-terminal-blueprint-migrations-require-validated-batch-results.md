# ADR 0019 — Non-terminal blueprint migrations require validated batch results

- Status: Accepted
- Date: 2026-10-27

## Context

Blueprint migrations start one coding-agent session per edge. An interactive
child may wait forever through pipes, and CLI print mode still requires a user
turn even when the system prompt supplies all instructions. A plain text reply
also loses the evidence needed to distinguish a completed run from a failed or
refused attempt.

## Decision

Match `agent run`: choose batch mode when stdin is not a terminal, or when the
user passes `--batch`. Detect once per migration command. Redirecting stdout
alone does not change mode. Keep terminal sessions interactive and preserve
API dispatch. Omitted or blank CLI instructions receive the neutral instruction
“Follow the instructions in the system prompt.” Explicit instructions and raw
receipt provenance retain their original meaning.

The shared interactive launcher owns this policy for blueprint runs, assist,
setup, and bootstrap, using `resolveAgentInitialPrompt` at the provider request
boundary. Resolve only execution and display input: command options and the
manifest keep the raw optional user input. Do not move the default into parsing,
templates, or persistent state. Blueprint debug shows the effective instruction
as a read-only preview. See
[plan 126](../plans/126-start-interactive-blueprint-runs-with-an-initial-message.md).

Claude batch migrations use `--permission-mode acceptEdits` for workspace
editing while retaining shell approval boundaries. Codex uses workspace-write.
Batch migrations use the existing provider command renderers and workspace,
owner tools plus specific read-only Mori discovery grants, reference directories, model, effort, and kit configuration. A
migration-specific adapter validates raw process exit and structured output
before projecting assistant text. It emits through the same Baikai trace sink.
Claude needs a successful result with no reported permission denials; Codex
needs assistant text, no reported failures or denials, and terminal turn
completion. Malformed or truncated protocol fails closed. Unknown well-formed
fields and events may coexist with the required evidence. This boundary is
separate from ordinary text completions.

A caller can supply Claude rules or a Claude settings file per invocation.
Every pending edge receives its owner's grants and the shared caller inputs.
A validated outcome records the caller inputs under the edge's owner, including
when an edge reports that it does not apply. Manually marked edges record null.

Only validated runs may consume outcome signals and create receipts. A failed
run clears its signal, leaves earlier receipts intact, and instructs the user
to inspect partial edits and retry. Neither a marker nor a signal file can
rescue a provider failure. Permission bypasses are not part of batch mode.

## Consequences

Provider protocol changes can require updating the migration adapter. Arbitrary
semantic refusals in prose cannot be detected reliably. Per [ADR 0011](0011-a-migration-receipt-asserts-a-claim-about-the-project.md), a receipt still does
not prove the project passes its checks. [ADR 0007](0007-a-deliberate-no-op-is-a-third-outcome-not-a-success.md)
and [ADR 0008](0008-an-entailed-migration-edge-is-owned-by-the-blueprint-that-declares-it.md)
continue to govern outcomes and edge ownership.
[ADR 0026](0026-a-batch-blueprint-run-fails-on-reported-tool-refusals.md)
extends the denial rule, and only that rule, to batch `agent run`.

Implementation: [plan 111](../plans/111-run-blueprint-migrations-without-an-interactive-terminal.md).

A migration with caller-supplied Codex hooks validates the native app-server
turn and its hook evidence through Baikai. An ordinary command can exit
nonzero inside a successful turn. A reported hook denial, failed gate or
missing turn evidence stops the migration and keeps earlier receipts.
