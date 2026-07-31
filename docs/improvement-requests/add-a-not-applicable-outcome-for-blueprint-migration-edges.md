---
type: Improvement Request
title: Add a not-applicable outcome for blueprint migration edges
description: >-
  Give a blueprint migration edge a way to report that its precondition is unmet so the edge is
  left unrecorded, instead of a deliberate no-op returning a receipt indistinguishable from a
  completed upgrade.
timestamp: 2026-07-31T12:19:09Z
requestId: IR-1
status: proposed
origin: mori://shinzui/okf-profiles
---

# Improvement Request: Add a Not-Applicable Outcome for Blueprint Migration Edges

## Status

Proposed. A workaround exists (`--rerun`), so this blocks nothing; it costs correctness of the
receipt chain in the one case where an edge is legitimately skipped.

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
