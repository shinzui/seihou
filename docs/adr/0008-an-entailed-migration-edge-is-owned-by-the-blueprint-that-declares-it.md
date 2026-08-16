# ADR 0008 — An entailed migration edge is owned by the blueprint that declares it

- Status: Accepted
- Date: 2026-08-16

## Context

A blueprint migration is an agent-guided upgrade step a library author ships
with a blueprint: one Markdown prompt per version edge, run by
`seihou agent migrate <blueprint> --from X --to Y`, with a receipt written into
`.seihou/manifest.json` after each edge.

That machinery assumed the library whose version edge is being crossed is the
same library the consumer names on the command line. The assumption breaks the
moment a breaking change travels through an intermediary, which is the ordinary
case for a cohort of libraries released together.

The motivating shape is a three-link chain. `mori://shinzui/kiroku` ships a
breaking change. `mori://shinzui/keiro` depends on kiroku and absorbs that
change in one of its own releases. Most consuming projects — `mori://shinzui/mori`
among them — depend on keiro and never name kiroku, while a small number depend
on kiroku directly and never touch keiro. A consumer knows which keiro version
they are on; they neither know nor should have to look up which kiroku version
keiro pulls in transitively. So the only version window a consumer can supply is
the window of the library they actually declare, and the upgrade knowledge that
has to reach them lives one repository away.

Two things therefore had to be decided: how the upgrade knowledge travels, and
whose ledger entry records that it was applied.

## Decision

A migration edge may declare that crossing it **entails** crossing a named exact
edge of another blueprint (`entails` on `schema/BlueprintMigration.dhall`, a list
of `schema/EntailedEdge.dhall`). Entailed edges are expanded recursively into one
ordered plan, run before the edge that declares them, and each runs with the
reference files, allowed tools, shared prompt, and resolved variables of the
blueprint that declares it.

**The edge is owned by the blueprint whose `migrations` list declares it, not by
the blueprint the user invoked.** Ownership decides three things at once:

- Which blueprint's execution context the step runs with.
- Which blueprint's identity — origin plus name, per
  [ADR 0002](0002-artifact-identity-is-origin-url-plus-name.md) — the receipt is
  written under.
- Which receipts the step is filtered against when deciding whether it is still
  pending.

This is what makes a shared cohort edge crossed exactly once. A project that
reaches kiroku's `1.9.0 -> 2.0.0` edge by running `keiro-upgrade` files a receipt
under `kiroku-upgrade`'s identity, so running `kiroku-upgrade` directly
afterwards finds that receipt and does nothing; the reverse order behaves the
same way. Recording under the invoking blueprint would make one piece of work
look like two different edges and cross it twice.

Supporting rules, each of which is a real decision rather than an implementation
detail:

- **Entailed edges run first**, and several run in declaration order. The
  entailed edge is the deeper change and the declaring edge's guidance may assume
  it has landed.
- **Expansion is recursive**, bounded by a visited set keyed on
  `(owner, from, to)`. A three-deep cohort works without any blueprint knowing
  the whole graph.
- **Deduplication ignores what entailed a step.** Two selected edges that both
  entail the same upstream edge produce one step.
- **A reference names one exact edge**, matched on both ends of its window.
  Seihou does not window-plan inside the entailed blueprint, because that would
  let one release silently change which upstream work it implies.
- **A cycle, a missing blueprint, and a missing edge are hard errors**, never
  skipped steps. The consumer does not know the cohort, so a silently omitted
  member leaves a half-migrated project with no signal at all. A missing
  blueprint is not auto-fetched, for the reason
  [ADR 0003](0003-a-stale-or-substituted-artifact-is-a-hard-error.md) gives for
  refusing rather than repairing: it would mutate the machine-global install
  cache as a side effect of an unrelated command.
- **A blueprint may not entail an edge of its own blueprint.** Ordering within
  one `migrations` list is already decided by the version window.
- **An entailed blueprint's `launch` declaration is ignored.** A single command
  cannot switch providers between edges, so provider, model, and effort stay a
  property of the command and the invoked blueprint's declaration wins.

### Rejected: a cohort artifact

The obvious alternative is a new artifact kind — a `Recipe`-like record listing
the member blueprints of a cohort and a version map per cohort release — which
consumers would install and migrate against.

It was rejected. Entailment reuses machinery that already exists: receipts are
already keyed per edge, so cross-entry-point deduplication falls out for free
once identity includes origin. A cohort artifact would need its own version
space, its own registry entry kind, its own receipts, and an answer for what
happens when a member is absent or when two cohorts overlap. It would also add a
third party to every release: kiroku, keiro, *and* whoever owns the cohort
record. Per-edge entailment keeps the declaration next to the change it
describes, in the repository of the library that knows about it.

Revisit only if a cohort grows past the point where per-edge declaration is
legible — not merely because a cohort exists.

### Rejected: recording the cohort

Nothing records which blueprints form a cohort. The set is recomputed from
declarations on every run, consistent with
[ADR 0004](0004-the-manifest-is-the-only-record-of-applied-state.md): there is no
lockfile, and the manifest records what was *applied*, not what was planned.

## Consequences

A cohort exists only as the transitive closure of `entails` declarations
reachable from the edges one command selected. It has no name, no version, and
no representation on disk. Adding, removing, or retargeting an entailment takes
effect the moment a consumer installs the new blueprint version, with no
migration of any recorded state.

The scope of `seihou agent migrate` grew from one artifact to a set discovered
mid-command. [ADR 0003](0003-a-stale-or-substituted-artifact-is-a-hard-error.md)
scopes its refusal to "the artifacts a command is about to use", so that set now
includes every blueprint in the resolved chain. The invoked blueprint is still
checked before planning — a substituted blueprint declares different edges, so
checking it after planning would be checking a window that was already computed
from the wrong declarations — and the entailed blueprints are checked once
discovery has found them, still before any session starts.

An entailed edge is, by construction, frequently inapplicable: one blueprint now
serves both direct and indirect consumers, and a keiro consumer who never imports
kiroku should have kiroku's edge do nothing.
[ADR 0007](0007-a-deliberate-no-op-is-a-third-outcome-not-a-success.md) is
therefore a prerequisite rather than a neighbouring feature. Without a
not-applicable outcome, every inapplicable entailed edge would write an *applied*
receipt that then suppresses the direct run of that same edge — converting the
feature into a silent-work-loss machine.

Consumers see steps from blueprints they did not name, may be prompted for
variables those blueprints declare, and find receipts filed under those
blueprints' names in `seihou status`. All three are surprising if not explained,
and all three are documented in
`docs/user/blueprint-migrations.md`.

Ownership is display-independent. `BlueprintMigrationStep` carries an
`entailedBy` field so output can say *(entailed by keiro-upgrade 2.4.0 ->
3.0.0)*, and that field deliberately takes no part in any identity comparison.
The same cohort edge reached from two different declaring edges is one edge; a
comparison that included the declaring edge would cross it twice, which is the
precise failure this decision exists to prevent.

The escape hatch when a cohort is misconfigured is to run the entailed blueprint
directly by name. A blueprint invoked by name expands only what its own selected
edges entail, so it is unaffected by another blueprint's authoring mistake.

## References

- [ADR 0002](0002-artifact-identity-is-origin-url-plus-name.md) — what makes two
  records of the same work the same record; this ADR decides *whose* record it
  is.
- [ADR 0003](0003-a-stale-or-substituted-artifact-is-a-hard-error.md) — the
  refusal whose scope now covers the resolved cohort.
- [ADR 0004](0004-the-manifest-is-the-only-record-of-applied-state.md) — why the
  cohort is recomputed rather than recorded.
- [ADR 0007](0007-a-deliberate-no-op-is-a-third-outcome-not-a-success.md) — the
  outcome that makes a frequently-inapplicable entailed edge safe.
- `docs/masterplans/10-blueprint-migration-fan-out-across-a-library-cohort.md`
- `docs/plans/85-fan-out-a-blueprint-migration-edge-to-entailed-cohort-edges.md`
- `docs/user/blueprint-migrations.md` — the authoring and consuming workflow.
