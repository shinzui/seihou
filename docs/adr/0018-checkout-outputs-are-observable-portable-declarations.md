# ADR 0018 — Checkout outputs are observable, portable declarations

- Status: Accepted
- Date: 2026-10-15

## Context

Seihou applies typed, composable module declarations and records the resulting project
state in a portable manifest. Some outputs are intentionally absent from a clone: ignored
links that expose project directories to local tools. A committed command receipt proves
that a command ran during an application, but cannot establish that its output exists in
another working copy. Reapplying or upgrading the declaring module to repair such state
also changes project intent and requires installed artifacts unnecessarily.

Agent skill links exposed this gap in
[IR-10](../improvement-requests/rebuild-checkout-local-outputs-in-a-fresh-clone.md).
Editor configuration links and local tool views of shared assets have the same lifecycle.
The architecture must express that lifecycle without encoding any consumer's directory
names, parsing old shell commands, or creating a second applied-state record.

This decision is implemented by
[ExecPlan 105](../plans/105-rebuild-checkout-local-symlinks-from-the-manifest-without-upgrading-artifacts.md).
The engine contract is released in Seihou 0.10.0.0. ADR 0017 is implemented by
[ExecPlan 99](../plans/99-declare-seed-steps-in-the-module-schema-and-validate-them.md)
for the seed lifecycle. This repository's
ADR directory is not a profiled OKF bundle.

## Decision

Strategy and lifecycle remain separate dimensions of a step. Strategy describes its
materialization; lifecycle describes ownership and subsequent maintenance. Managed files
participate in content reconciliation, seeds are handed to the project after creation,
and checkout outputs describe state reconstructed in each working copy. Initially only
`strategy = "symlink"` with `lifecycle = Some "checkout"` is valid for checkout outputs,
and its source must be a real project directory.

The manifest stores a destination-keyed `checkoutOutputs` map. Each record contains a typed,
tagged specification and application/module-instance owners. The initial specification is
`DirectorySymlink`, encoded with kind `directory-symlink` and a project-relative source.
Ownership belongs to the lifecycle record, outside the specification. There are no observed
timestamps, hashes, completion receipts, or machine-specific paths. Agreement on the entire
specification permits co-ownership; disagreement or overlapping output paths is an error.

The declaration, observation, pure plan, and checked application are separate layers.
Domain rules live in `seihou-core`; effects inspect and mutate the filesystem; CLI adapters
select intent and render structured outcomes. These layers are shared by sync, run, update,
remove, and status. Checkout destinations never enter managed-file content hashing,
baseline storage, text merging, or additive-write certification.

The checkout sync engine rebuilds the current recorded declaration. It needs a Git working tree, ignored and
untracked destinations, available real source directories, and safe ancestors. It can
replace an incorrect destination symlink but cannot replace a regular object or follow a
symlinked ancestor. It writes only declared link entries and necessary parents. It neither
resolves artifacts nor evaluates module/config variables, executes recorded commands,
changes tracked content, nor writes the manifest. A correct link is established by its
literal canonical relative target, not by a receipt or the target directory's contents.
Initial application can precede Git initialization under a distinct, warning-producing
policy; that does not weaken sync's contract.

Declaration changes use three inputs: prior intent, candidate intent, and disk. Candidate
intent replaces selected owners' claims while retaining all unselected claims. A false
condition, removed dependency, or renamed destination retires obsolete claims. Last-owner
retirement removes only a link still matching the old declaration; modified objects survive
with a warning. Retirement does not require its old source to exist. Changing a link's
meaning refuses a user-edited third target rather than treating it as an ordinary repair.
Unchanged specifications and owner-only changes perform no filesystem repair during
reconciliation; explicit sync repairs such drift. Automatic checkout cleanup requires no custom removal spec and cannot authorize unrelated
managed-file deletion. Application/instance selection must be unambiguous.

Plans retain all path classifications, including refusals. A refusal prevents application
of the whole plan. Dry-run reports proposed work with zero applied writes; execution and
rollback outcomes are separate from proposals. Sync uses no durable setup journal: it can
converge again from the manifest after interruption. Update extends its existing recovery
journal with literal-link snapshots. Neither repair nor rollback traverses a link target.
Portable precondition rechecks assume no hostile concurrent filesystem writer; they are
not a general filesystem sandbox.

Extension uses a closed typed specification with explicit versioning. A new output kind
must provide portable validation, observable satisfaction, safe materialization and
retirement, recovery, rendering, and common contract tests. Unknown kinds fail before
mutation. A new kind or changed semantic meaning advances the manifest schema under
[ADR 0014](0014-every-semantic-manifest-change-advances-the-schema-version.md), even when
the tagged object shape stays the same. Arbitrary JSON payloads, shell replay, and plugin
callbacks are not extension mechanisms for this contract.

## Consequences

Agent, editor, and asset use cases share an engine and can be composed through ordinary
module variables and dependencies. The first implementation remains directory-only;
file links or generated local files need new specifications and evidence rather than a
silent broadening of the directory-link contract. No general resource framework is needed
to deliver or test the present capability.

The manifest remains the single portable record under
[ADR 0001](0001-manifest-is-a-checked-in-machine-independent-artifact.md) and
[ADR 0004](0004-the-manifest-is-the-only-record-of-applied-state.md). It records that a
module established a desired checkout output, not that all clones already materialized it.
Status reports observations independently of installed artifact availability and uses
bounded, cause-specific diagnostics under ADRs 0013 and 0015.

Requiring Git and invocation at the working-tree root limits initial sync support to that
well-defined boundary, including linked worktrees. Non-Git repair, nested Seihou projects,
external sources, and outputs requiring downloads or secrets need separate designs.
Ordinary non-Git scaffolding remains available through run's existing root semantics.

Producer adoption is a separate delivery obligation from engine availability.
Installing a declaring producer or upgrading an empty checkoutOutputs field cannot
infer desired wiring from historical command receipts. Apply or update the recorded
composition once with its saved inputs, then commit the manifest, real source content,
and ignore rules. A dependency-only producer change must be discoverable through the
ordinary update path even when the parent module version is unchanged.

A previously committed discovery symlink remains protected during sync. Ordinary
update can explicitly propose adoption of a newly declared destination when HEAD,
index and the working copy contain the same literal symlink matching the candidate,
and its destination is ignored. The normal update preview and acceptance authorize
removing just that index entry while retaining the working link. Dry-run and
cancellation never untrack it. Modified or staged entries, real objects, indexed
ancestors and unrelated tracked discovery entries remain protected. The update
journal records each adopted path's original Git object ID before any removal;
rollback and recovery restore only those entries, preserving unrelated staging
and refusing to overwrite a later index or working-link edit at an adopted path.
Adoption never writes the working link, so recovery does not replace it. Journal version 3 adds
these index snapshots while retaining readers for versions 1 and 2. Snapshot
checks compare tracked symlink text without following targets, and account for parents
that already exist because they hold unrelated tracked entries.

Remote-backed updates fetch their candidates and dependencies without a prerequisite
installation. When declarations are absent, the normal sync CLI now discovers declaring
compositions from recorded sources and offers the necessary application update
within the same command. It selects only compositions with checkout steps and
reuses saved inputs. A preview and explicit acceptance precede any adoption,
including managed file changes and eligible index transitions. This delegates to
the existing update transaction; it does not infer wiring from shell receipts.
Dry-run only previews adoption; JSON automation requires explicit `--yes` to accept
it. Once declarations exist, sync uses the offline, manifest-read-only engine
without fetching producers. Status remains offline and points to `seihou sync`
when setup has not been recorded. The original plan-107 manual untracking procedure is historical;
the reopened plan requires adoption through the normal accepted update flow.
Status treats absent remotely fetchable producers as an optional local cache,
summarized once rather than as project damage. This does not weaken command guards
or hide stale/substituted installed artifacts, missing project-owned sources, or
non-portable machine-local origins.

## Rejected Alternatives

A skill-specific command or path-discovery loop would bypass declared ownership and
solve only one consumer's convention. Replaying shell commands would require trust and
idempotence rules that cannot be inferred from a receipt. A local completion file would
still become stale when an output is deleted and duplicate applied-state authority.

A symlink-only manifest map would be sufficient for this first output but would couple
shared ownership to one output representation. A tagged specification within a lifecycle
record supplies a small extension point without implementing speculative output kinds.
A generic plugin resource manager would expand the execution and compatibility contracts
before another concrete kind establishes its needs.

## References

- [Architecture overview](../dev/architecture/overview.md)
- [ADR 0013](0013-status-is-a-bounded-summary-the-manifest-is-the-record.md)
- [ADR 0015](0015-diagnostics-name-things-as-users-do-and-never-fall-back-to-show.md)
- [ExecPlan 100](../plans/100-record-seed-receipts-in-manifest-schema-8.md)

## Implementation evidence

Schema 9 and the adjacent 8-to-9 upgrade implement this record after the schema-8 seed prerequisite. Core tests cover portable declarations, ownership laws, literal target observation, indexed tracked paths, native aliases on the macOS temporary volume, complete preflight, rollback and literal-link recovery; version-1 journals remain readable and unknown version-2 kinds fail before writes. A trace permits only declared link writes/parents and fixed read-only Git calls. Case-fold-equivalent checkout destinations are conservatively refused on every filesystem to keep declarations portable. Git check-ignore receives one `./`-prefixed pathname after `--`, because that command rejects literal pathspec magic.

Real-binary tests cover both agent discovery and editor/shared-asset wiring, clean clones with empty and newer producer caches, poisoned config, linked worktrees, same-run generated sources, agreeing owners, conflicting retarget refusal, condition retirement, preserved local edits, no-spec removal and failed-update rollback. No producer repository is adopted or released by this implementation. Validation ran on macOS; Linux execution remains a downstream CI/platform verification obligation. These changes extend [ADR 0017](0017-a-seed-file-is-created-once-and-belongs-to-the-project.md) and preserve ADRs 0001, 0004 and 0014.

The producer follow-up is [ExecPlan 107](../plans/107-adopt-manifest-owned-skill-links-in-agent-seihou-and-verify-fresh-clone-sync.md).
It publishes [link-skill](mori://shinzui/agent-seihou/templates/link-skill) 0.3.0 and
[claude-skill-link](mori://shinzui/agent-seihou/templates/claude-skill-link) 0.2.0,
using released Seihou 0.10.0.0. Real-binary producer tests establish legacy schema-6
command applications, adopt declarations without shell replay, and cover generated
sources, shared ownership, refusal, clones and linked worktrees. This adds producer
adoption evidence without changing the original engine implementation's boundary.

The committed Seihou consumer now records all four planning-skill discovery outputs.
An empty-cache fresh clone and a linked worktree restore them with sync, and deletion
or wrong-target repair changes only the affected link. Tracked bytes, the index and
manifest bytes remain unchanged. The previously tracked master-plan discovery entry
was deliberately untracked for adoption; unrelated tracked entries remain intact.
