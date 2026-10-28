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

Implementation: [plan 111](../plans/111-run-blueprint-migrations-without-an-interactive-terminal.md).
