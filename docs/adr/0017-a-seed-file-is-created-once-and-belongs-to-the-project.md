# ADR 0017 — A seed file is created once and belongs to the project

- Status: Accepted
- Date: 2026-10-15

## Context

Starting files such as changelogs belong to the project after creation. Tracking their content forever would obscure useful managed-file drift.

## Decision

Step lifecycle is independent of strategy. An omitted lifecycle means `managed`; `seed` declares a whole file to create once and hand to the project. Seeds support copy, template, and dhall-text, with no patch or structured merge. A destination has one lifecycle. Custom removal must not delete a seed.

The declaration and schema-8 receipt foundations are implemented by [plan 99](../plans/99-declare-seed-steps-in-the-module-schema-and-validate-them.md) and [plan 100](../plans/100-record-seed-receipts-in-manifest-schema-8.md). Runtime seed creation and reporting remain the responsibility of [MasterPlan 12](../masterplans/12-seed-files-module-outputs-created-once-and-owned-by-the-project.md); until those changes land, declaring seed does not activate runtime seed behavior.

Schema 8 adds a `seeds` map keyed by project-relative path. A receipt records its module, application owners, first outcome, and settlement time. It carries no hash or baseline. A path cannot be both managed and seeded. Merging owners preserves the first settlement; dropping the last owner drops the receipt without touching disk. The schema-8 ownership representation is a foundation; the amendment below defines the correction required before runtime producers are enabled. Schema 7 upgrades losslessly by adding an empty map. Older binaries ignore the lifecycle field; producers must require a release supporting runtime seed behavior.

## Runtime contract amendment (2026-10-26)

This amendment is accepted design for the remaining work in MasterPlan 12; it is not a claim
that the runtime or the next schema has shipped. The current implementation has schema 10 and
application-only seed receipts, and still lacks runtime seed semantics.

First settlement provenance and active ownership are distinct. Preserve the original supplier,
outcome, and settlement time. Record live claims by application ID and qualified module instance,
so removing one seeder cannot erase another's receipt even within one composition. EP-2 owns a
new adjacent schema/capability for exact claims. Older application-only ownership is represented
explicitly as legacy information, losslessly; resolving it requires exact recorded artifact
and input evidence, never guessing from the first supplier. The structural upgrade must not
invent ownership facts. Last-claim retirement forgets settlement and leaves the project object
alone; reintroduction can create an absent file after that receipt is gone.

Seeds never participate in managed hashing, baselines, merging, or orphan deletion. Compilation
keeps the first proposed seed content in declared execution order and records every claimant;
the supplier is explicit, not reconstructed from set order. Mixed lifecycle and overlapping path
claims are rejected before mutation, including retained owners. Existing checkout rules remain
independent and must be preserved. Normal commands own schema/evidence preparation.

Create-only means a native no-replace operation, not an existence check followed by a replacing
write. Inspect final entries without following links and reject unsafe ancestors. A new seed
keeps an existing regular file, but refuses an occupied directory or symlink. A settled seed
is not read, recreated, or repaired, regardless of its current final entry. Update journals
actual seed creations and rolls them back only while the created object still matches its
creation evidence. Metadata-only settlement and release must never restore project bytes.
These checks are not a general sandbox against hostile concurrent filesystem changes.

Run refuses lifecycle transitions before publishing new applied metadata and directs the user
to update. Ordinary update releases managed files to seeds without a per-file prompt, preserving
bytes and absence. It excludes releases from orphan deletion and prunes only unreferenced
baseline blobs. The reverse transition requires explicit keep/accept consent; force cannot
supply it, and an absent seed can be accepted for recreation or the update aborted. Retained
owners that still claim another lifecycle block the transition.

Removal retires exact selected instance claims even without a custom removal spec for seed-only
ownership. All declarative delete, move, patch, strip, and rewrite paths must preserve seed
objects, including migrations and staged candidate generation. Arbitrary shell commands are
unsandboxed; producer authors must not mutate seed-owned files through shell. Status/diff count
receipts without reading seed content or treating deletion as drift.

No temporary adapter may reinterpret seeds as managed writes. Until all command semantics land,
update refuses selected seed transitions before mutation. Publish runtime support before producer
adoption, state the tested minimum release, and verify ordinary update from an existing consumer
with empty caches and saved inputs. An older binary ignoring lifecycle is unsafe for seeds;
this initiative does not add a module minimum-client schema field, so release/documentation
compatibility and installed-binary evidence remain explicit delivery requirements.

## Consequences

The manifest remains the only applied-state record. Later runtime plans must create only absent seeds and never overwrite, merge, report content drift, or delete them. Decoder compatibility does not establish runtime support.

## Rejected Alternatives

A boolean would not express distinct ownership modes. A new generation strategy would conflate ownership with rendering. A project ignore list would duplicate declared module intent.

## References

- [ADR 0004](0004-the-manifest-is-the-only-record-of-applied-state.md)
- [ADR 0014](0014-every-semantic-manifest-change-advances-the-schema-version.md)
