---
type: Improvement Request
title: Add a not-applicable outcome for blueprint migration edges
description: >-
  Give a blueprint migration edge a way to report that its precondition is unmet so the edge is
  left unrecorded, instead of a deliberate no-op returning a receipt indistinguishable from a
  completed upgrade.
generated:
  by: human:nadeem
  at: "2026-07-31T12:19:09Z"
timestamp: 2026-07-31T12:19:09Z
requestId: IR-1
status: completed
completedAt: "2026-08-16T00:00:00Z"
targetPlan: docs/plans/84-add-a-not-applicable-outcome-for-blueprint-migration-edges.md
resolution: >-
  A blueprint migration edge can now report that it does not apply. Shape 2 was chosen — a distinct
  recorded outcome — reached through both of the other two vocabularies rather than either alone,
  because the signal channel differs by provider: an interactive claude-cli or codex-cli session
  communicates only through an exit code, so it writes a one-line reason to a signal file seihou
  names in the prompt and deletes around each edge, while an API provider's reply reaches seihou
  directly and is scanned for a trailing SEIHOU: not-applicable line. Shape 3, a dedicated exit
  code, was rejected: an interactive session's exit code is the shell session's, so a user could
  forge it and an agent finishing normally could not choose it. Both channels produce one
  MigrationOutcome on the receipt. The completion key now requires an applied outcome, so a
  not-applicable edge is replanned without --rerun, while the upsert key still ignores the outcome
  so a replanned edge replaces its own receipt. The chain continues past an inapplicable edge,
  seihou status renders the outcome and its reason, and seihou's framing prompt carries the
  convention so edge authors need only state their precondition.
origin: mori://shinzui/okf-profiles
---

# Improvement Request: Add a Not-Applicable Outcome for Blueprint Migration Edges

## Status

Completed 2026-08-16 by
[`docs/plans/84-add-a-not-applicable-outcome-for-blueprint-migration-edges.md`](../plans/84-add-a-not-applicable-outcome-for-blueprint-migration-edges.md).
See [Resolution](#resolution). Depended on
[IR-2](record-artifact-origin-for-agent-applied-artifacts.md), which landed first: both changes
rewrite `AppliedBlueprintMigration` and the completion key, and sequencing them kept two plans off
the same predicate.

## Context

`seihou agent migrate` records a receipt in `.seihou/manifest.json` after each edge's provider
session returns, and drops edges that already have a receipt unless `--rerun` is passed.

`docs/user/blueprint-migrations.md` is explicit that this is bookkeeping, not proof:

> A receipt records that the provider interaction for one exact `(blueprint, from, to)` tuple
> returned successfully. It does **not** prove that your package manager now reports the target
> version, that the build passes, or that every call site was updated.

So the current behaviour matches the documented contract. This request is not that the contract is
violated — it is that the contract has no way to express a third outcome that edges genuinely
produce.

## Problem

An edge prompt can legitimately conclude that it must do nothing. A well-written edge states its
own precondition, and when the target repository does not meet it, the correct action is to change
nothing and say so.

Observed while testing the `adopt-architecture-decisions` blueprint's new
`0.6.0 -> 0.7.0` edge against `mori://shinzui/rei`:

- That edge upgrades an ADR bundle already pinned to an older `okf-profiles` tag.
- `rei` had never adopted the profile at all — no `docs/adr/profile.dhall`, no frontmatter.
- The edge's first instruction is to read the real pin and stop if the bundle was never adopted.
- The agent did exactly that: it changed no file and reported that
  `seihou agent run adopt-architecture-decisions` was the correct entry point.

The session returned successfully, so seihou recorded:

```json
{
  "appliedAt": "2026-07-31T12:11:00.060261Z",
  "from": "0.6.0",
  "name": "adopt-architecture-decisions",
  "to": "0.7.0",
  "version": "0.7.0"
}
```

The receipt is indistinguishable from one written after a real upgrade. Once `rei` adopts the
profile — which is exactly what the refusal told the user to do — the edge that *should* then run
is silently skipped, because its receipt already exists. The failure is quiet: no message, no
diff, and the bundle stays on whatever pin adoption happened to install.

The two outcomes seihou can currently distinguish are provider-returned (receipt written) and
provider-failed (no receipt, resumable). A deliberate, correct no-op is neither. It collapses into
the first, which is the one outcome that suppresses future runs.

## Why the existing escapes do not cover it

- **`--rerun`** works, but only for someone who already knows the receipt is meaningless. Nothing
  in the manifest, in `seihou status`, or in the migrate output marks that edge as skipped rather
  than applied.
- **Exiting nonzero** from the edge would suppress the receipt, but it is wrong: it reports a
  provider failure, prints `Fix the provider problem, then rerun the same command to resume`, and
  halts a multi-edge chain that should have continued past an inapplicable step.
- **Narrowing the edge window** does not help. Applicability here depends on repository state, not
  on a version number — the same `--from`/`--to` is correct for a repository that has adopted and
  one that has not.

## Requested change

Give an edge a way to report *not applicable* as a first-class outcome, distinct from both success
and failure. Any of these would resolve it:

1. **A sentinel the agent can emit** (for example a final line such as
   `SEIHOU: not-applicable <reason>`), which suppresses the receipt, prints the reason, and lets
   the chain continue to the next edge.
2. **A distinct receipt status** — record the attempt with `outcome: "not-applicable"` and treat
   only `outcome: "applied"` as a reason to skip on a later run. This keeps the audit trail, which
   is preferable to writing nothing.
3. **A dedicated exit code** reserved for inapplicability, documented alongside the existing
   failure path.

Option 2 is the most informative: it preserves the record that the edge was evaluated, keeps
`seihou status` honest, and makes the skip decision depend on what actually happened.

Whichever shape is chosen, the framing guidance seihou prepends to every migration session should
tell the agent how to signal it, so edge authors do not each invent their own convention.

## Scope

Blueprint migrations only (`seihou agent migrate`). Module migrations (`seihou migrate`) are
declared file operations with no agent judgement, so they have no equivalent outcome.

## Related

Structurally identical to `mori://shinzui/keiro`'s IR-3, which asks for an explicit terminal
rejection outcome in an outbox so an intentional refusal can be finalized without retrying or
being misreported as delivery success. The shared shape is that a deliberate, correct refusal is a
third outcome, and collapsing it into success loses information the caller needs.

## Resolution

Shape 2 was chosen and both other shapes were folded into it as signal channels.

An `AppliedBlueprintMigration` receipt now carries a `MigrationOutcome`, either `MigrationApplied`
or `MigrationNotApplicable` with the reason inside the constructor, so the type cannot express a
reason for an applied edge or a skipped edge with no reason. The completion key in
`pendingBlueprintMigrations` requires an applied outcome, which is what makes the edge run again;
the upsert key in `writeAppliedBlueprintMigration` deliberately still ignores the outcome, so a
replanned edge replaces its own receipt rather than accumulating a second one. That asymmetry is
the one place a receipt comparison leaves the outcome out, and both are documented as such.

Shape 1 alone would not have worked, and neither would shape 3. The channel available to an edge
depends on its provider: `claude-cli` and `codex-cli` sessions are spawned interactively and
communicate only through an exit code, so seihou never sees a sentinel line in the transcript;
`anthropic` and `openai` hand seihou the assistant text directly, and there is no process of the
agent's to carry an exit code. So the prompt describes one convention with two mechanics — write a
one-line reason to a signal file under `.seihou/`, or, failing that, end the reply with
`SEIHOU: not-applicable <reason>` — and both reach the same recorded outcome.

Shape 3 was rejected outright rather than used for the interactive half. An interactive agent
session's exit code is the *shell session's* exit code: a user who types `exit 3`, or whose
terminal is killed, would forge the signal, and an agent that finishes normally cannot choose it. A
file the agent writes with its own tools is a deliberate act, carries a reason, and can be
inspected afterwards. Seihou deletes it before each edge and after reading it, so a stale file from
a crashed run cannot mark the next edge inapplicable.

The marker-line parser is deliberately forgiving about formatting and strict about the marker: it
scans the last few non-empty lines, tolerates backticks and emphasis, and requires the line to
*begin* with `SEIHOU:` followed by `not-applicable` as a whole word. Prose that merely discusses
applicability is not a signal, because a false positive silently skips real work — strictly worse
than missing a signal the agent could also have written to the file.

The chain continues past an inapplicable edge, as the request requires; the run summary counts them
(`Completed 2 blueprint migration(s) for 'my-library' (1 not applicable).`), and `seihou status`
renders the outcome with a truncated reason. Seihou's framing prompt carries the convention, so
edge authors state only their precondition.

One thing the change cannot do: receipts written before this release are all read as applied,
because nothing on disk distinguishes a completed upgrade from a deliberate no-op after the fact.
`--rerun` remains the remedy for those, as it was before, and the changelog says so.
