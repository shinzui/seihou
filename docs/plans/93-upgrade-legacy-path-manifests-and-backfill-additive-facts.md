---
id: 93
slug: upgrade-legacy-path-manifests-and-backfill-additive-facts
title: "Upgrade legacy path manifests and backfill additive facts"
kind: exec-plan
created_at: 2026-09-17T14:17:05Z
intention: "intention_01m2qvd83ae0yt8e3h7ay430bg"
master_plan: "docs/masterplans/11-make-manifest-evolution-explicit-and-targeted-updates-upgrade-safe.md"
provenance:
  created_by:
    model: "gpt-5.6-sol"
    harness: "codex-cli"
    at: 2026-09-17T14:17:05Z
---

# Upgrade legacy path manifests and backfill additive facts

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

After this plan, `seihou manifest upgrade` can move a manifest through a declared sequence
of schema versions instead of treating every older document as the same legacy shape. A
developer may preview or apply an upgrade to a requested version, see each adjacent step,
and trust that fields unknown to the current typed model survive.

The existing valuable behavior for schema 5 and earlier remains: machine-local absolute
paths are detected and replaced with portable project paths or the appropriate remote
origin recovered from install metadata. That inference stays explicit, reviewable, and
blocked by default when the current machine cannot establish the upstream. The new 6-to-7
step makes shared-write uncertainty explicit and a reusable certification service can
backfill additive or closure-required evidence by inspecting generated operations without
writing any project file. The all-manifest command certifies everything it can; the
target-scoped service is consumed by
`docs/plans/94-gate-targeted-updates-on-the-minimum-manifest-schema.md`.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [ ] M1: Refactor `seihou manifest upgrade` into a contiguous, target-versioned schema-step driver.
- [ ] M2: Preserve and strengthen schema-1-through-5 machine-local-path conversion and remote-origin reporting.
- [ ] M3: Add reusable all-path and target-scoped shared-write certification that changes only the manifest.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

(None yet.)


## Decision Log

Record every decision made while working on the plan.

- Decision: Keep the public command default as “upgrade to current,” and add `--to VERSION`
  for callers that need only a minimum schema.
  Rationale: Existing scripts retain their behavior while features and recovery workflows
  can stop at a known compatibility boundary.
  Date: 2026-09-17

- Decision: The 5-to-6 step remains explicit and may require `--force`; the pure 6-to-7
  step may be staged automatically by a feature command.
  Rationale: Recovering a remote URL from machine state is inference. Converting an old
  Boolean encoding into explicit unknown evidence is lossless.
  Date: 2026-09-17

- Decision: Certify a path only when operations for every recorded owner are available.
  Rationale: “Additive-only” is a conjunction across owners. Missing one application must
  leave the mode unknown rather than weakening the ownership gate.
  Date: 2026-09-17

- Decision: Certification compiles and inspects operations but never reconciles files,
  executes commands, applies migrations, or publishes candidate artifacts.
  Rationale: The purpose is to record a safety fact. Updating unrelated applications to
  learn that fact is the blast radius this initiative removes.
  Date: 2026-09-17


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose. Before marking the plan complete,
distill durable project context from the Decision Log, Surprises & Discoveries, and
this section into docs/adr/. Keep task-local execution details here.

(To be filled during and after implementation.)


## Context and Orientation

This plan has a hard dependency on
`docs/plans/92-define-manifest-schema-capabilities-and-ordered-upgrade-steps.md`. Implement
that plan first. It supplies schema version 7, `SharedWriteMode`, the capability-to-minimum
version mapping, and the pure 6-to-7 document transform used here.

Run commands from
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`. The CLI's testable library lives in
`seihou-cli/src/`, the `Options.Applicative` parser lives in
`seihou-cli/src-exe/Seihou/CLI/Commands.hs`, and tests live under `seihou-cli/test/`.

`seihou-cli/src/Seihou/CLI/ManifestUpgrade.hs` currently implements one specialized
conversion. `readLegacyManifest` parses raw JSON and returns `Nothing` for any version at
or above `currentManifestVersion`. Every lower version is assumed to contain absolute
paths. `collectRefs` locates `modules[*].source`, `applications[*].targetSource`, and
`applications[*].instances[*].source`. `inferOriginFromLegacyPath` turns a project-local
path into `ProjectOrigin`, looks up installed artifacts by name, and uses
`.seihou-origin.json` to produce `RemoteOrigin`; otherwise it reports an unverifiable
`LocalOrigin`. `applyUpgrade` rewrites those keys and sets the document directly to the
current version. `validateUpgrade` decodes the rewritten raw document before
`writeDocument` atomically renames it into place.

That module is already careful about preservation: it edits `Aeson.Value` rather than
round-tripping through `Manifest`, so producer-owned or future keys survive. The redesign
must retain that property. It must also retain `--dry-run`, `--force`, the artifact guard,
and the report that explains each inferred origin. The current behavior is covered by
`seihou-cli/test/Seihou/CLI/ManifestUpgradeSpec.hs`; versions 1 through 5 are converter
fixtures there because the ordinary manifest decoder intentionally rejects them.

`seihou-cli/src/Seihou/CLI/Update/Source.hs` stages candidate artifacts for an update, and
`Seihou.Composition.Plan.compileComposedPlan` compiles module definitions and resolved
inputs into `Operation` values. Certification needs the same loading and composition
rules, but it must not call reconciliation or execute `RunCommandOp`. Extract reusable
source/composition helpers into the library rather than importing executable-only code or
copying update logic.

An “owner” is an `ApplicationId` recorded in `FileRecord.applicationIds`. A “certification
scope” is either every unknown shared path or only unknown shared paths whose owner set
intersects a named target selection. For each scoped path, certification must obtain
operations for every owner. If every owner's contribution to that path satisfies
`isAdditivePatchOp`, the result is `SharedWriteAdditiveOnly`. If every owner is available
and at least one contribution is not additive, the result is
`SharedWriteRequiresOwnershipClosure`. If any owner cannot be resolved, composed, or
matched to the path, the result remains `SharedWriteUnknown` with a report entry explaining
why.

For an unselected owner, use the recorded artifact origin, recorded version, saved parent
variables, and resolved values. Prefer a local or project artifact whose origin and
declared version agree with the manifest. Do not silently use a newer local artifact to
make a historical fact look known. The EP-94 caller may supply the already-staged candidate
for the selected target because that is the contribution the requested update will
actually apply; every other owner remains based on its recorded state. If exact evidence
cannot be obtained, return unknown and let the caller retain the closure.

The relevant ADRs are
[ADR 0001](../adr/0001-manifest-is-a-checked-in-machine-independent-artifact.md),
[ADR 0003](../adr/0003-a-stale-or-substituted-artifact-is-a-hard-error.md),
[ADR 0004](../adr/0004-the-manifest-is-the-only-record-of-applied-state.md),
[ADR 0005](../adr/0005-legacy-manifests-convert-through-an-explicit-command.md), and
[ADR 0012](../adr/0012-an-additive-co-write-is-not-a-shared-path-conflict.md).
ADR 0001 forbids machine-local paths in the upgraded file. ADR 0003 forbids substituting a
stale or different artifact. ADR 0005 requires inferred conversions to be visible and
lossless. ADR 0012 defines the exact additive operation set. EP-92 updates the durable
policy; this plan implements it and should only amend an ADR if implementation reveals a
new durable constraint. Mori discovery found no relevant cross-repository ADR.


## Plan of Work

Milestone 1 turns the one-off converter into an adjacent-step driver. Refactor
`seihou-cli/src/Seihou/CLI/ManifestUpgrade.hs` so raw document parsing produces a source
schema version independently of any particular step. Ask `Seihou.Manifest.Upgrade` for the
contiguous source-to-target path, dispatch each step in order, and retain a step report.
Add `targetVersion :: Maybe ManifestSchemaVersion` to `ManifestUpgradeOpts`; `Nothing`
means current. Add `--to VERSION` in
`seihou-cli/src-exe/Seihou/CLI/Commands.hs`. Reject a target below the document version, a
target above the binary's current version, and any missing adjacent handler before writing.

Keep one raw `Aeson.Value` through the complete chain. Validate the result at every boundary
that has a typed decoder and once more before writing. The final `version` must be the last
successfully completed step, never the requested target assigned up front. Extend
`UpgradeOutcome` and `formatUpgradeReport` so `--dry-run` and apply list steps such as
`5 -> 6 portable artifact origins` and `6 -> 7 explicit shared-write evidence`.

Milestone 2 installs the existing path conversion as the inference-bearing 5-to-6 handler
without weakening it. Keep `collectRefs`, JSON-pointer replacement, report deduplication,
artifact guard, `--force`, and atomic raw-document writes. Strengthen tests for three
sources of truth: an existing project-local path becomes `ProjectOrigin`; a matching
installed artifact with `.seihou-origin.json` becomes `RemoteOrigin` with that URL and
artifact name; and a missing or stale artifact produces an unverifiable conversion that is
reported and blocked unless forced. A schema-6 document must never enter `collectRefs`.

Prove chained behavior from schema 5 to 7. The path step runs first and is printed first;
the pure EP-92 step then adds explicit unknown shared-write modes. `--to 6` stops before
the second step. A blocked 5-to-6 inference prevents 6-to-7 from running or changing the
file. A direct 6-to-7 upgrade does no filesystem-origin inference and never asks for
`--force`.

Milestone 3 adds `seihou-cli/src/Seihou/CLI/ManifestCapabilityUpgrade.hs` and exposes it
from `seihou-cli/seihou-cli.cabal`. Implement pure classification separately from artifact
loading: given the manifest owner sets and a map from application id to compiled operations,
classify each scoped path into additive-only, closure-required, or still unknown. Then add
the IO shell that resolves recorded applications, restores saved inputs, compiles their
operations, and feeds the pure classifier. Accept optional selected-candidate evidence so
EP-94 can reuse the candidate already staged for the target instead of cloning or compiling
it twice.

The capability service returns an updated in-memory manifest and a report; it never writes.
The public `seihou manifest upgrade` driver calls it for all unknown shared paths after
reaching schema 7, then writes only `.seihou/manifest.json`. Unresolvable evidence leaves
the path explicitly unknown and is printed; it is not a reason to fabricate either known
state. EP-94 calls the same service with a target-scoped set and owns transactionally
publishing the returned manifest.


## Concrete Steps

Before editing, re-read the existing converter and its tests:

```bash
sed -n '1,700p' seihou-cli/src/Seihou/CLI/ManifestUpgrade.hs
sed -n '1,620p' seihou-cli/test/Seihou/CLI/ManifestUpgradeSpec.hs
```

After Milestone 1, run:

```bash
cabal test seihou-cli-test
```

Use temporary-directory fixtures in tests; do not experiment on this repository's own
manifest. A schema-5-to-7 dry run should produce a concise transcript like:

```text
Reading .seihou/manifest.json (schema version 5)
  5 -> 6  portable artifact origins
  haskell-base  /machine/path/haskell-base
             -> remote https://example.test/modules.git
  6 -> 7  explicit shared-write evidence
  .gitignore  unknown -> additive-only
--dry-run: nothing was written.
```

Exact spacing may follow the existing renderer, but step order, source/target versions,
remote URL, path result, and no-write line are required. Exercise the parser through the
built binary in the end-to-end spec:

```bash
cabal run seihou -- manifest upgrade --help
```

It must show `--to VERSION`, `--dry-run`, and `--force` with distinct explanations. At
completion run:

```bash
cabal build all
cabal test all
nix fmt -- --fail-on-change
nix flake check
```


## Validation and Acceptance

For each schema version 1 through 5, the existing fixture converts through 5-to-6 semantics,
preserves every unrelated JSON key, and can continue to 7. A manifest whose absolute path
still exists and has matching origin metadata records the actual remote URL, not a URL
derived from the directory name. A moved manifest finds a matching installed artifact by
name. A missing or stale artifact is clearly reported and blocks the write unless `--force`
is present. Project paths remain project-relative.

For schema 6, `--to 6` and a default upgrade on an already-current binary are idempotent;
`--to 7` runs only the pure 6-to-7 step. No path-inference report appears, no module install
is required merely to express unknown, and every file record receives an explicit mode.

The pure certification tests cover all-additive owners, one whole-file owner, a missing
owner, a selected scope that excludes an unrelated unknown shared path, and an application
that no longer emits an operation for a recorded path. The IO tests prove compilation uses
saved parent variables and resolved values, refuses stale or mismatched recorded artifacts,
and does not execute `RunCommandOp` or write project files. A target-scoped certification
changes only the scoped `FileRecord.sharedWriteMode` values plus the manifest schema; the
files on disk and unrelated manifest records are byte-equivalent at the JSON-value level.

Running the command twice after a successful all-manifest upgrade reports nothing to do.
`cabal test all` and `nix flake check` pass.


## Idempotence and Recovery

The driver computes and validates the full upgraded raw document before its existing
write-to-temporary-then-rename operation. Interruption before rename leaves the original
manifest; interruption after rename leaves a complete validated manifest. A blocked step
does not run later steps.

`--dry-run` performs discovery and certification but writes nothing. Re-running an applied
upgrade is a no-op. The manifest is checked into git, so `git diff
.seihou/manifest.json` reviews the result and `git checkout --
.seihou/manifest.json` restores it if the user chooses. These recovery commands belong in
the user documentation, but tests must use temporary copies rather than invoking git.

Certification is conservative and retryable. Installing the exact missing artifact or
fixing its origin metadata and rerunning may turn unknown into a known mode. It must never
turn a known closure requirement into additive-only unless operations for every owner are
recompiled successfully in that run.


## Interfaces and Dependencies

`Seihou.CLI.ManifestUpgrade` continues to own the public command. Its option and outcome
types must carry the target and the ordered report, approximately:

```haskell
data ManifestUpgradeOpts = ManifestUpgradeOpts
  { dryRun :: !Bool
  , force :: !Bool
  , targetVersion :: !(Maybe ManifestSchemaVersion)
  }

data UpgradeStepReport = UpgradeStepReport
  { fromVersion :: !ManifestSchemaVersion
  , toVersion :: !ManifestSchemaVersion
  , summary :: !Text
  }
```

Preserve the existing `LegacyRef`, `InferenceOutcome`, and origin-report detail where they
remain useful; do not duplicate those types in the new core module.

`Seihou.CLI.ManifestCapabilityUpgrade` must expose a renderer-neutral service equivalent
to:

```haskell
data CertificationScope
  = CertifyAllUnknownSharedPaths
  | CertifyPathsForApplications !(Set ApplicationId)

data SharedWriteCertification = SharedWriteCertification
  { manifest :: !Manifest
  , entries :: ![SharedWriteCertificationEntry]
  }

certifySharedWriteModes ::
  CertificationScope ->
  Manifest ->
  Map ApplicationId [Operation] ->
  SharedWriteCertification
```

Add an IO orchestration function beside it that obtains operation evidence from recorded
applications and accepts caller-supplied selected-candidate operations. Keep the pure
function free of filesystem and network effects so EP-94 can test selection behavior with
small fixtures. Return per-path unknown reasons rather than throwing away partial success.

Use existing dependencies only: `aeson`, `containers`, `directory`, `temporary`, `text`,
and Seihou's composition/source modules. Do not add a generic migration framework package.
