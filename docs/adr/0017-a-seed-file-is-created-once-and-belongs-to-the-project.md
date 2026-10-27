# ADR 0017 — A seed file is created once and belongs to the project

- Status: Accepted
- Date: 2026-10-15

## Context

Starting files such as changelogs belong to the project after creation. Tracking their content forever would obscure useful managed-file drift.

## Decision

Step lifecycle is independent of strategy. An omitted lifecycle means `managed`; `seed` declares a whole file to create once and hand to the project. Seeds support copy, template, and dhall-text, with no patch or structured merge. A destination has one lifecycle. Custom removal must not delete a seed.

The complete runtime contract is delivered in Seihou 0.11.0.0 and newer; 0.11.0.1 also corrects compiled command help. The declaration and schema-8 receipt foundations are implemented by [plan 99](../plans/99-declare-seed-steps-in-the-module-schema-and-validate-them.md) and [plan 100](../plans/100-record-seed-receipts-in-manifest-schema-8.md). Runtime creation, reporting, update and retirement are delivered by [MasterPlan 12](../masterplans/12-seed-files-module-outputs-created-once-and-owned-by-the-project.md). The historical implementation amendments below distinguish foundations from runtime support.

Schema 8 adds a `seeds` map keyed by project-relative path. A receipt records its module, application owners, first outcome, and settlement time. It carries no hash or baseline. A path cannot be both managed and seeded. Merging owners preserves the first settlement; dropping the last owner drops the receipt without touching disk. The schema-8 ownership representation is a foundation; the amendment below defines the correction required before runtime producers are enabled. Schema 7 upgrades losslessly by adding an empty map. Older binaries ignore the lifecycle field; producers must require a release supporting runtime seed behavior.

## Runtime contract amendment (2026-10-26)

This amendment established the design before runtime implementation. At that point the
implementation had schema 10, application-only receipts and no runtime seed semantics.
The implementation and delivery amendments below record its completion.

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

The manifest remains the only applied-state record. Runtime commands create only absent, unsettled seeds and never overwrite, merge, report content drift, or delete project-owned seeds. Decoder compatibility does not establish runtime support.

## Rejected Alternatives

A boolean would not express distinct ownership modes. A new generation strategy would conflate ownership with rendering. A project ignore list would duplicate declared module intent.

## References

- [ADR 0004](0004-the-manifest-is-the-only-record-of-applied-state.md)
- [ADR 0014](0014-every-semantic-manifest-change-advances-the-schema-version.md)

## Ownership implementation (2026-10-26)

Schema 11 implements the precise-claims prerequisite: `KnownSeedOwners` maps
applications to qualified instances; `LegacySeedOwners` retains old uncertainty.
Exact merge, subtraction, query, and selected-application replacement preserve
first settlement independently of active owners. Known claims require recorded
applications and instances and canonical, nonoverlapping output paths. Evidence
preparation is read-only and injected for testing; runtime compilation connects
it in the dependent plan. Runtime seed behavior was still pending at this stage.

## Run and removal implementation (2026-10-26)

Run and agent baselines now compile dedicated seed operations and retain every
qualified claimant while selecting the first declared supplier. Native complete
file publication uses an exclusive hard link from a private temporary file,
verified on macOS and Linux with failed writes and concurrent creators. Seed
operations cannot enter managed execution or baselines. Run refuses lifecycle
transitions before migrations. Exact historical ownership preparation reuses the
recorded-release loader and stages adjacent lossless schema steps when required.

The portable seed namespace conservatively refuses conflicting case spellings,
including ancestor components, before mutation. Existing native spelling and
unsafe-parent checks remain necessary too. This avoids accepting two logical
receipts for one object on a case-insensitive filesystem.

Status and diff count receipts without inspecting seed bytes. Removal uses the
same recorded application/instance selection as checkout, subtracts exact claims,
and preserves seed objects even through direct declarative removal operations.
Seed-only owners need no custom removal specification; managed files retain their
explicit removal policy. At this stage full seed update and released-producer
acceptance were separate open gates; intermediate update refused selected seed
changes safely. The later amendments record their completion.

## Update implementation (2026-10-27)

Update partitions seed actions before managed content materialization, migration
snapshots and orphan classification. Release/settlement/retirement are metadata-only:
the transaction never snapshots or restores those project bytes. New creations use
exclusive publication and journal version 4 records actual creation evidence. A
private hard-link anchor retains object identity until commit/recovery, preventing
inode reuse from making an identical replacement appear transaction-owned. Rollback
removes only its unchanged original creation; later edits, replacements and uncertain
interrupted publication are preserved with an actionable recovery error. Journal
versions 1–3 remain readable.

Reverse adoption always requires explicit consent, including equal or missing
content. Keep-current records the candidate generated ancestor for future merges;
accept writes generated content. Missing content permits accept/recreate or abort.
Force/JSON cannot consent. Every declarative migration source/destination is checked
against old seed and candidate release paths before mutation. Shell remains unsandboxed.

Ordinary adoption was verified against an isolated actual working-state copy of
`mori://shinzui/reiko` with schema 10, saved inputs, mixed legacy/new application
records and an empty installed cache. One `seihou update haskell-cli-app` fetched the
candidate, included its matching recorded dependency, previewed releases, and preserved
the edited changelog and both Cabal files. The repeat was a no-op. Public GitHub
transport normalization follows [ADR 0002](0002-artifact-identity-is-origin-url-plus-name.md).
Legacy adoption resolves sources from saved origins; dependency edge bindings join the
normal preview and become saved standalone inputs, while conflicting bindings refuse.
The loader deduplicates exact dependency instances, not module names alone.

These source results were followed by the completed released delivery below.

## Released delivery and durable constraints (2026-10-27)

Runtime 0.11.0.0 was published before CLI 0.4.0, library 0.3.0 and Keiro project
0.3.0 in `mori://shinzui/seihou-modules`. The installed 0.11.0.1 patch adds accurate
compiled command help. All three public producer workflows and ordinary adoption
from actual `mori://shinzui/reiko` state pass against the installed release with
empty caches. Repeated updates, forced reruns, clones/worktrees and seed-only
removal preserve project edits and deliberate deletion. MasterPlan 12 and plan 104
retain executable/release provenance and detailed acceptance evidence.

Runtime-first publication is a safety constraint: a verified 0.10.1.0 client
ignores lifecycle and can force-overwrite the same declarations. Until a future
module minimum-client contract exists, producer documentation must state the
minimum supported runtime (0.11.0.0); compatibility cannot be inferred from Dhall
decoding. User guidance must cover compiled `COMMAND --help`, conceptual help and
agent templates together, because they are distinct executable inputs.

Exclusive publication, exact live claims, content-free settlement and selective
recovery form one ownership contract. Keeping any of them as an engine-only
prerequisite does not complete delivery. The normal update must own recorded
source/dependency lookup, saved inputs and lossless preparation; hidden cache,
manifest or index repair is not an accepted adoption workflow.
