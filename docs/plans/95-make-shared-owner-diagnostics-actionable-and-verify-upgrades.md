---
id: 95
slug: make-shared-owner-diagnostics-actionable-and-verify-upgrades
title: "Make shared-owner diagnostics actionable and verify upgrades"
kind: exec-plan
created_at: 2026-09-17T14:17:06Z
intention: "intention_01m2qvd83ae0yt8e3h7ay430bg"
master_plan: "docs/masterplans/11-make-manifest-evolution-explicit-and-targeted-updates-upgrade-safe.md"
provenance:
  created_by:
    model: "gpt-5.6-sol"
    harness: "codex-cli"
    at: 2026-09-17T14:17:06Z
---

# Make shared-owner diagnostics actionable and verify upgrades

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

After this plan, the manifest-upgrade and targeted-update behavior from EP-92 through
EP-94 is understandable without reading Haskell types or manually decoding SHA-256
application ids. Shared owners are named with stable human labels such as
`link-skill [skill.name=exec-plan]`; missing evidence leads with the command that repairs
it; `--include-shared-owners` is offered only for a proven ownership-closure requirement;
and every update warning has deliberate prose.

The full workflow is protected by a regression fixture matching BUG-1. A schema-6 project
with a template owner and two additive skill-link owners can target the template module,
upgrade its manifest evidence, and leave the skill files untouched. A legacy absolute-path
fixture demonstrates that `seihou manifest upgrade` detects the machine-local reference,
records the appropriate remote when install metadata proves it, and then continues through
schema 7. User guides, embedded help, CLI reference, architecture notes, changelog, and the
bug report all describe the shipped behavior consistently.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [ ] M1: Introduce shared application labels and exhaustive prose rendering for update warnings.
- [ ] M2: Make error remedies and JSON/human output reflect manifest preparation and proven closure states.
- [ ] M3: Add full regression fixtures, update every documentation surface, and pass release-level validation.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

(None yet.)


## Decision Log

Record every decision made while working on the plan.

- Decision: Reuse the manifest's target and parent-variable context for application labels;
  never expose a full application hash as the primary human identifier.
  Rationale: Those are the inputs users recognize and the same context `seihou status`
  already renders for repeated module instances.
  Date: 2026-09-17

- Decision: Remove the catch-all `warningText other = show other` branch and render every
  `UpdateWarning` constructor explicitly.
  Rationale: A fallback makes adding a constructor compile while leaking internal syntax to
  users, which is exactly how `CrossApplicationLastWriter` regressed.
  Date: 2026-09-17

- Decision: Keep stable error codes, but tailor remedies to explicit-upgrade,
  evidence-unavailable, and known-closure failures separately.
  Rationale: Scripts depend on the code; people depend on the message. One generic closure
  paragraph cannot be correct for all three states.
  Date: 2026-09-17

- Decision: Preserve the update JSON envelope's structural version when adding an optional
  manifest-preparation projection; bump it only if an existing key changes type or meaning.
  Rationale: The new projection is additive, while gratuitously changing the envelope
  version would create migration work unrelated to this bug.
  Date: 2026-09-17


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose. Before marking the plan complete,
distill durable project context from the Decision Log, Surprises & Discoveries, and
this section into docs/adr/. Keep task-local execution details here.

(To be filled during and after implementation.)


## Context and Orientation

This plan has a hard dependency on
`docs/plans/94-gate-targeted-updates-on-the-minimum-manifest-schema.md` and a soft
dependency on
`docs/plans/93-upgrade-legacy-path-manifests-and-backfill-additive-facts.md`. EP-94 fixes
the error taxonomy and transaction behavior; EP-93 supplies the final upgrade reports this
plan documents. Implement presentation against those completed interfaces rather than
guessing their intermediate shapes.

Run commands from
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`. Human and JSON rendering for project
updates lives in `seihou-cli/src/Seihou/CLI/Update/Render.hs`. The current
`warningText` has a dedicated case only for `SelectionExpandedForSharedPath`; every other
constructor falls through to `T.pack (show other)`. That produces text such as
`CrossApplicationLastWriter "path" (ModuleName {unModuleName = ...}) ...`.

`SharedPathRequiresApplications` in
`seihou-cli/src/Seihou/CLI/Update/Types.hs` currently carries sets of `ApplicationId`.
`errorMessage` prints those hashes, describes absent `additiveOnly` and real whole-file
ownership in one sentence, and orders remedies as “select every owner, pass
--include-shared-owners, or run seihou update with no targets.” The first two broaden work
without recording the missing fact. EP-94 replaces bare ids with renderer-neutral
`ApplicationRef` values and splits unknown evidence from a known closure failure.

The manifest has enough context for a useful label. `AppliedComposition.target` names the
root module or recipe. Each `AppliedInstanceState` records its `ParentVars`; for a skill
link this yields context such as `skill.name=exec-plan`. The existing status renderer at
`seihou-cli/src/Seihou/CLI/StatusRender.hs` formats applied module parent variables as
`name [key=value]`. Extract or mirror that pure formatting rule in one shared CLI-library
module so status and update cannot drift. Do not print resolved secret values; only the
already-rendered parent-variable identity context is eligible.

The update JSON envelope has `schemaVersion: 1`, error `code` and `message`, and warnings as
strings. EP-94 adds `ManifestPreparation` to `UpdatePlan`. Project it into an optional
`manifestPreparation` object with source version, target version, and changed path modes.
Keep the existing types of every key. If implementation requires changing an existing
key, bump the envelope version and document the change rather than silently breaking it.

Tests are split across
`seihou-cli/test/Seihou/CLI/UpdateRenderSpec.hs` for pure rendering,
`seihou-cli/test/Seihou/CLI/UpdateSpec.hs` for service behavior, and
`seihou-cli/test/Seihou/CLI/UpdateE2ESpec.hs` plus
`seihou-cli/test/Seihou/CLI/UpdateFixture.hs` for the built binary. Extend those fixtures;
do not make an end-to-end test depend on the developer's installed module directory or a
live network remote.

Documentation surfaces are `docs/cli/update.md`, `docs/cli/manifest.md`,
`docs/user/manifest-upgrade.md`, `seihou-cli/help/update.md`,
`seihou-cli/help/manifest.md`,
`docs/dev/design/proposed/manifest-and-incrementality.md`,
`docs/dev/design/proposed/project-aware-updates.md`, and
`docs/user/CHANGELOG.md`. At completion, update
`docs/bug-reports/additive-only-gate-breaks-targeted-update-on-preexisting-manifests.md`
with resolved status and concrete regression evidence according to its existing frontmatter
convention.

Relevant decisions are
[ADR 0001](../adr/0001-manifest-is-a-checked-in-machine-independent-artifact.md),
[ADR 0004](../adr/0004-the-manifest-is-the-only-record-of-applied-state.md),
[ADR 0005](../adr/0005-legacy-manifests-convert-through-an-explicit-command.md),
[ADR 0007](../adr/0007-a-deliberate-no-op-is-a-third-outcome-not-a-success.md),
and [ADR 0012](../adr/0012-an-additive-co-write-is-not-a-shared-path-conflict.md).
The reproducing external project is referred to only by its canonical project URI,
`mori://tan/mls-service-v2`. No cross-repository ADR was found or is required.


## Plan of Work

Milestone 1 adds a single application display vocabulary. Create
`seihou-cli/src/Seihou/CLI/ApplicationDisplay.hs`, expose it from
`seihou-cli/seihou-cli.cabal`, and move the parent-variable formatting rule used by status
into it. The primary label is the target name. When the target's root instance has
non-empty parent variables, append sorted `key=value` pairs in brackets. If several
applications still share the same label in one message, disambiguate by manifest order
such as `(application 1)` rather than exposing the digest. Update
`Seihou.CLI.StatusRender` to use the helper so the promised shared vocabulary is real.

Change `Seihou.CLI.Update.Render.warningText` into an exhaustive pattern match over every
`UpdateWarning`. In particular, render `CrossApplicationLastWriter path earlier later` as
plain prose explaining that both modules contribute to the path and the later module is
recorded as the last writer; it is an attribution warning, not proof that bytes changed.
Render `SelectionExpandedForSharedPath` with the `ApplicationRef` label from EP-94. Give
the other warnings concise existing-meaning prose and add a test per constructor so a new
constructor requires an intentional renderer edit at compile/test time.

Milestone 2 repairs errors and structured output. Keep
`shared_path_requires_applications` for a known closure requirement, but list required and
selected application labels and explain that `--include-shared-owners` updates their full
applications. The explicit legacy-schema error leads with `seihou manifest upgrade`; the
evidence-unavailable error names the unresolved owners and how to make their recorded
artifacts available. Neither unknown case advertises selection expansion as a repair.

Render `ManifestPreparation` in human plans before version/file summaries and project it
into JSON. Human output should say `Manifest: schema 6 -> 7; .gitignore evidence unknown ->
additive-only` in compact form. The JSON object carries numeric source and target schema
versions plus sorted per-path changes. Extend `UpdateRenderSpec` with golden assertions
that no human output contains `ApplicationId`, `ModuleName {`,
`CrossApplicationLastWriter`, or a 64-character owner digest. Assert stable error codes and
the updated remedy ordering.

Milestone 3 adds integrated fixtures and documentation. Extend the shared-path fixture to
write a schema-6 manifest whose `.gitignore` has three owners and no old Boolean key. Give
the two unselected skill-link applications unrelated managed files. The test hashes those
files, performs targeted dry-run and apply, and proves their bytes never change. Add the
known whole-file case, unresolved evidence case, second-run no-op, and a failure-injection
rollback case if EP-94 did not already place them at binary level.

Add a separate schema-5 manifest-upgrade fixture with machine-local absolute paths and a
fake installed artifact containing `.seihou-origin.json`. Prove `--dry-run --to 6` reports
the appropriate remote without writing, the real command records that `RemoteOrigin`, and
a default upgrade continues through schema 7. Also prove a missing origin blocks without
`--force` and never invents a URL.

Update all documentation surfaces named in Context. Explain schema 7's three states,
`--to`, explicit machine-local-path inference, automatic lossless preparation for targeted
updates, and the fact that evidence inspection does not update co-owner files. Add a
changelog entry and mark BUG-1 resolved only after the regression passes. Review the
MasterPlan and all four child plans for durable decisions, then complete the ADR
distillation required by the planning protocol.


## Concrete Steps

Run the pure renderer and CLI suites while iterating:

```bash
cabal test seihou-cli-test
```

The fixture's user-visible sequence is:

```bash
seihou update nix-haskell-flake --dry-run
seihou update nix-haskell-flake
seihou update nix-haskell-flake
```

Expected first-run prose is compact and actionable:

```text
Manifest:    schema 6 -> 7
Evidence:    .gitignore  unknown -> additive-only
Warning:     .gitignore has contributions from exec-plan and master-plan; evidence only was inspected
```

The actual wording may be refined, but it must use application/module labels and explain
inspection versus update. The apply reports one updated application. The third command is
already up to date and contains no closure error.

For the legacy fixture:

```bash
seihou manifest upgrade --dry-run --to 6
seihou manifest upgrade
```

The first command names the recovered remote and writes nothing. The second reports both
adjacent steps and leaves a schema-7 manifest. At completion run the release-level gates:

```bash
nix fmt -- --fail-on-change
cabal build all
cabal test all
nix flake check
```

Also run targeted searches to catch accidental raw rendering or stale docs:

```bash
rg -n 'warningText other|T\.pack \(show other\)|currentManifestVersion = 6|schema version 6' \
  seihou-cli seihou-core docs README.md
```

Any remaining schema-6 reference must be historical and explicitly labeled as such.


## Validation and Acceptance

Every `UpdateWarning` constructor renders intentional prose. The renderer has no catch-all
`Show` fallback. Human warnings and closure errors use application labels; the full
application-id digest does not appear as the primary identifier. `CrossApplicationLastWriter`
never appears literally in terminal or JSON warning text.

The unknown-evidence error leads with the evidence or manifest-upgrade remedy and does not
mention `--include-shared-owners`. The known closure error names the missing applications,
states that expansion updates their full applications, and offers either explicit target
selection or `--include-shared-owners`. Error codes remain stable and JSON remains valid.

The BUG-1 fixture proves a schema-6 targeted update succeeds, writes schema 7 and
additive-only evidence, changes only the selected target's intended files and manifest
records, and remains successful on retry. The unrelated seven-style skill files are
byte-identical. Dry-run and injected failure are non-mutating. The whole-file fixture still
fails closed.

The legacy fixture proves machine-local paths are detected and an appropriate remote is
recorded only when local metadata establishes it. The report is reviewable, `--to 6`
stops at 6, default reaches 7, and failure leaves the old file intact. Documentation and
help match those commands. Full Cabal and Nix checks pass.


## Idempotence and Recovery

Rendering and documentation changes are repeatable. Fixtures use isolated temporary
directories and fake local remotes, so interrupted tests leave no project state to repair.

The real targeted workflow inherits EP-94's update journal and rollback. The real manifest
upgrade inherits EP-93's temporary-file rename. User documentation must explain that the
manifest is checked in, `git diff .seihou/manifest.json` is the review surface, and
restoring that file from version control undoes an explicit upgrade. Do not put destructive
git commands in automated tests.

Only mark the bug report resolved after all acceptance tests pass and the changelog names
the fixed release as pending if no release version has been assigned. If the full gate
reveals unrelated existing failures, record the exact command and failure in Surprises &
Discoveries; do not weaken this initiative's assertions to hide them.


## Interfaces and Dependencies

`seihou-cli/src/Seihou/CLI/ApplicationDisplay.hs` must provide pure helpers equivalent to:

```haskell
applicationLabel :: ApplicationRef -> Text
appliedModuleLabel :: AppliedModule -> Text
```

Both use the same sorted parent-variable renderer. They must not inspect current machine
paths, resolve artifacts, or render arbitrary resolved values.

`seihou-cli/src/Seihou/CLI/Update/Render.hs` remains the sole owner of update human and
JSON text. It consumes `ApplicationRef` and `ManifestPreparation` from EP-94. If a richer
structured warning projection is added, retain the existing warning strings or version the
envelope explicitly; do not expose Haskell constructors as a wire format.

No new library dependency is required. Tests use existing `hspec`, `temporary`, the built
`seihou` test tool, and local git-remote helpers already present in
`UpdateFixture`. Documentation changes use repository-local links and the canonical
`mori://tan/mls-service-v2` reference for the external reproducer.
