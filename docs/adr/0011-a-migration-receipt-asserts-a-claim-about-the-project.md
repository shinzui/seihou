# ADR 0011 — A migration receipt asserts a claim about the project, not a completed agent session

- Status: Accepted
- Date: 2026-09-10

## Context

A blueprint migration receipt in `.seihou/manifest.json` is what stops an edge
from being planned again. Until now there was exactly one code path that wrote
one: inside a `seihou agent migrate` run, after a provider session returned. So
a receipt could only ever mean "an agent session for this edge returned", and
nothing else could produce one.

That is not the population of upgrades. Plenty of people upgrade a library by
hand — they read the release notes, make the changes, and never run
`seihou agent migrate` at all. Seihou had no way to be told, and every
workaround failed differently:

- Hand-editing the manifest requires guessing the artifact's `origin`. Per
  [ADR 0002](0002-artifact-identity-is-origin-url-plus-name.md), origin is part
  of a receipt's identity, so a wrong guess produces a receipt that matches
  nothing — worse than no receipt, because it looks like one.
- Running the migration anyway spends a real provider session, in money and
  minutes, to discover there is nothing to do.
- Widening `--from` past the edge skips it but records nothing, so the edge is
  never done and the next run with an inferred window plans it again.
- Letting the agent report the edge "not applicable" records an outcome that, by
  [ADR 0007](0007-a-deliberate-no-op-is-a-third-outcome-not-a-success.md)'s
  design, does *not* suppress a later run. That is the whole point of that
  outcome, and borrowing it here would break it for the case it exists for.

The gap becomes load-bearing the moment seihou starts surfacing *pending*
blueprint migrations, which it does not do yet. A project that upgraded by hand
would show a pending migration forever with no supported way to clear it — a
false positive manufactured by the discovery feature and dismissible only by
spending a provider session.

## Decision

A blueprint migration receipt asserts that **an edge has been attended to and
need not run again**. That is a claim about the consumer's project, and it may be
established in either of two ways: a provider interaction for that edge returned,
or the consumer asserted the work was already done.

`seihou agent migrate <blueprint> --mark-applied` is how a consumer asserts it.
It records a receipt for every pending edge in the resolved window, contacts no
provider, starts no session, and reads or writes no file in the working tree.

Four rules follow, and they are what the decision means in practice:

1. **A marked receipt records `MigrationApplied`.** It is not a third outcome
   value. ADR 0007 treats the outcome vocabulary as durable project context, so
   extending it needs real justification, and there is none here: a receipt
   already means an edge has been attended to rather than proof an agent did it,
   and a hand migration satisfies that meaning exactly. An "applied by hand"
   value would additionally force every existing reader of `outcome` to decide
   what it meant to them, for no gain. The two ways of establishing a receipt are
   deliberately indistinguishable once written.
2. **Marking goes through the same receipt-construction path a real run uses.**
   In particular it respects
   [ADR 0008](0008-an-entailed-migration-edge-is-owned-by-the-blueprint-that-declares-it.md):
   a step reached through `entails` is recorded under the blueprint that
   *declares* the edge, not the one the consumer named. A second construction
   site could drift from that rule, and a receipt filed under the wrong identity
   matches nothing.
3. **Marking is scoped to pending edges.** An edge that already has an applied
   receipt is skipped rather than rewritten, so an `appliedAt` stamp recorded
   honestly at some other time is never moved for work it did not describe.
   Marking the same window twice is therefore a no-op, and marking a wider window
   later is purely additive.
4. **The assertion is not verified, and seihou does not pretend otherwise.**
   Seihou cannot check arbitrary libraries across ecosystems — that limit already
   applies to an earned receipt, which likewise does not prove the build passes.
   `--rerun` is the correction for a mistaken marking, exactly as it is the
   correction for a receipt that says applied when the edge really did nothing.

Two flag combinations are refused rather than resolved by precedence, because
neither has a defensible winner: `--mark-applied` with `--rerun` asks to both
skip and force the same edges, and `--mark-applied` with the parent `--debug`
asks a dry run that writes nothing to write receipts.

The capability is a flag on `seihou agent migrate` rather than a standalone
`seihou manifest record-migration` command. A correct receipt needs the
blueprint's resolved origin, the planned version window, and the identity of the
blueprint that owns each edge; that command already computes all three, and
duplicating the resolution is precisely how a receipt acquires an origin that
matches nothing.

## Consequences

Nothing downstream needs to distinguish a marked receipt from an earned one, and
nothing may start: the outcome, the identity comparison, the suppression rule,
and the `--rerun` remedy are all unchanged. A future feature that reports on
receipts must not assume an agent produced every entry — that assumption was
true before this decision and is not true after it.

No new manifest field and no schema change. The receipt written is the existing
`AppliedBlueprintMigration`, through the existing writer, so
[ADR 0004](0004-the-manifest-is-the-only-record-of-applied-state.md) holds
unchanged: `.seihou/manifest.json` remains the only record of applied state, and
there is no side file recording how a receipt came to exist. Every receipt
written before this decision reads exactly as it did before.

The artifact guard from
[ADR 0003](0003-a-stale-or-substituted-artifact-is-a-hard-error.md) still runs
before a marking records anything, for both the invoked blueprint and every
blueprint the window reaches by entailment. Marking writes receipts, so a
substituted blueprint would have its edges recorded against this project's
ledger under an identity that matches nothing — the same failure the guard
exists to prevent. Marking is deliberately *not* treated as a dry run for guard
purposes.

Seihou now accepts a user assertion as a fact of record. That is a widening of
what the manifest holds, and it is bounded: the assertion is only ever that an
edge need not run again, it is visible in a checked-in, reviewed file per
[ADR 0001](0001-manifest-is-a-checked-in-machine-independent-artifact.md), and it
is reversible with a documented flag.

This decision is about blueprint migrations only. Deterministic module migrations
(`seihou migrate`) are declared file operations that seihou performs itself, so
there is nothing for a consumer to have done by hand that seihou would need to be
told about.

## References

- [ADR 0007](0007-a-deliberate-no-op-is-a-third-outcome-not-a-success.md) — the
  outcome vocabulary this decision deliberately does not extend.
- [ADR 0008](0008-an-entailed-migration-edge-is-owned-by-the-blueprint-that-declares-it.md)
  — why marking reuses the run's receipt-construction path.
- [ADR 0002](0002-artifact-identity-is-origin-url-plus-name.md) — why a
  hand-written receipt with a guessed origin matches nothing.
- [ADR 0004](0004-the-manifest-is-the-only-record-of-applied-state.md) — the
  manifest is the only record of applied state.
- [ADR 0003](0003-a-stale-or-substituted-artifact-is-a-hard-error.md) — why the
  guard still runs for a marking.
- `docs/plans/87-record-a-blueprint-migration-that-was-applied-by-hand.md` — the
  implementation.
- `docs/user/blueprint-migrations.md` — "I already upgraded by hand" and "What a
  receipt means".
