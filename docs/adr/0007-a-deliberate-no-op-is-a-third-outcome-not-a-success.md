# ADR 0007 — A deliberate no-op is a third outcome, not a success

- Status: Accepted
- Date: 2026-08-16

## Context

`seihou agent migrate` runs one agent session per declared version edge and
writes a receipt into `.seihou/manifest.json` after each session returns, so an
interrupted chain resumes where it stopped. A later run drops any edge that
already has a receipt.

That gives seihou two boxes: the provider interaction returned (receipt written,
edge never runs again) or the provider failed (no receipt, edge resumes). Real
edges produce a third result that fits neither.

A well-written edge states its own precondition, and when the project does not
meet it the correct action is to change nothing and say so. Observed while
testing the `adopt-architecture-decisions` blueprint's `0.6.0 -> 0.7.0` edge
against `mori://shinzui/rei`: the edge upgrades an ADR bundle pinned to an older
tag, `rei` had never adopted the bundle at all, and the agent correctly changed
no file and reported that a different command was the right entry point. The
session returned, so seihou recorded a receipt indistinguishable from one written
after a real upgrade. Once `rei` adopted the bundle — which is exactly what the
refusal told the user to do — the edge that *should* then have run was silently
skipped. No message, no diff.

Collapsing the no-op into success is what causes the loss, and it is the outcome
that suppresses future runs. The failure is silent by construction: the only
evidence is a receipt that looks right.

This becomes routine rather than rare once one blueprint's edges serve both
projects that use a library directly and projects that only see it through a
wrapper — the cohort fan-out
`docs/masterplans/10-blueprint-migration-fan-out-across-a-library-cohort.md`
exists to support. Most runs of a shared edge then legitimately do nothing.

## Decision

A deliberate, correct refusal to act is a distinct recorded outcome, not a
success and not a failure.

A blueprint migration receipt carries a `MigrationOutcome`: either
`MigrationApplied`, or `MigrationNotApplicable` with the reason the edge gave.
Three rules follow, and they are what the decision means in practice:

1. **The attempt is recorded, not suppressed.** Writing nothing would also avoid
   the silent skip, but it loses the fact that the edge was evaluated. The audit
   trail is the point of the ledger.
2. **Only an applied outcome suppresses a later run.** An edge that reported its
   precondition unmet says nothing about whether it is unmet *now*, and the
   ordinary case is that satisfying it is what the edge told the user to do.
3. **The chain continues past it.** An inapplicable edge is not a failure, so it
   must not halt the remaining edges or ask the user to retry. Exiting nonzero
   was rejected for exactly this reason.

The outcome is audit metadata, not identity. It is deliberately excluded from the
comparison that upserts a receipt, so an edge replanned after reporting itself
inapplicable replaces its own receipt rather than accumulating a second one for
the same edge. It is deliberately included in the comparison that decides what is
pending. That asymmetry is intentional and is documented at both call sites.

Recording the outcome is a separate question from how an edge signals it. The
signalling mechanism is provider-dependent — a signal file for interactive
sessions, whose only other channel is an exit code, and a marker line for API
providers, whose reply seihou receives directly — and is an implementation
concern that may change. The recorded vocabulary is the durable decision.

## Consequences

The outcome is a manifest field, so it is committed, reviewed, and visible in
`seihou status` alongside every other applied-state fact — consistent with
[ADR 0004](0004-the-manifest-is-the-only-record-of-applied-state.md). No side
file records it and nothing is inferred at read time.

`--rerun` keeps its existing meaning: ignore matching receipts, applied ones
included. It is now the remedy for the opposite error — an edge recorded as
applied that really did nothing — rather than the only remedy for both.

Every receipt written before this decision is read as applied, because nothing on
disk can distinguish a completed upgrade from a deliberate no-op after the fact.
A conversion command per
[ADR 0005](0005-legacy-manifests-convert-through-an-explicit-command.md) could
only write the same value, so the decoder defaults the field instead of bumping
the schema version — the same reasoning applied to `origin` in ADR 0002's
2026-08-16 amendment. That residual case is stated in the changelog.

Edge authors write less, not more. Seihou's framing prompt carries the convention
for reporting an unmet precondition, so an edge prompt only has to state what its
precondition *is*. Without a shared convention every blueprint author would have
invented one, and seihou would have understood none of them.

This decision is about blueprint migrations only. Deterministic module migrations
(`seihou migrate`) are declared file operations with no agent judgement, so there
is nothing there that could decline to act.

The shape generalises beyond seihou. `mori://shinzui/keiro` carries a
structurally identical request for an explicit terminal rejection outcome in an
outbox, so an intentional refusal can be finalized without retrying or being
misreported as delivery success. When a system's success box means "we are done
with this", a deliberate refusal that belongs in that box and a deliberate
refusal that must be revisited are different facts, and merging them loses the
one the caller needs.

## References

- [ADR 0004](0004-the-manifest-is-the-only-record-of-applied-state.md) — the
  manifest is the only record of applied state.
- [ADR 0005](0005-legacy-manifests-convert-through-an-explicit-command.md) —
  why the decoder defaults rather than converting.
- [ADR 0002](0002-artifact-identity-is-origin-url-plus-name.md) — what makes two
  records of the same work the same record.
- `docs/improvement-requests/add-a-not-applicable-outcome-for-blueprint-migration-edges.md`
  (IR-1) — the request, its three candidate shapes, and why the obvious
  workarounds fail.
- `docs/plans/84-add-a-not-applicable-outcome-for-blueprint-migration-edges.md` —
  the implementation.
- `docs/user/blueprint-migrations.md` — "What a receipt means".
