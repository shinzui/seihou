---
id: 90
slug: exempt-additive-patch-paths-from-the-shared-ownership-closure
title: "Exempt additive-patch paths from the shared-ownership closure"
kind: exec-plan
created_at: 2026-09-16T12:43:44Z
intention: "intention_01m2n3x3jye499cw7mm0nmw0m8"
provenance:
  created_by:
    model: "claude-opus-5[1m]"
    harness: "claude-code"
    at: 2026-09-16T12:43:44Z
  revisions:
    - model: "claude-opus-5[1m]"
      harness: "claude-code"
      at: 2026-09-16T13:23:39Z
      mode: "implement"
      note: "Milestone 1 implemented: additiveOnly on every manifest write path"
---

# Exempt additive-patch paths from the shared-ownership closure

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

Today, a developer who wants to update one module in their project is regularly
refused. Running

```bash
seihou update nix-haskell-flake
```

prints

```text
Update failed [shared_path_requires_applications]: Path .gitignore is also owned by
application(s) <master-plan>. Select every owner or run seihou update with no targets.
```

and changes nothing. The reason is that `.gitignore` is *co-owned*: two separate
applications both contribute lines to it. Seihou refuses to touch a file on
behalf of one owner when another owner is not part of the update, because
regenerating a file normally means rewriting all of it, which would silently
discard the other owner's content.

That reasoning is correct for a file someone rewrites wholesale. It is wrong for
`.gitignore`, because every owner reaches it through an *additive patch*: each
one appends only the lines it needs (`append-line-if-absent`) or its own
marker-delimited block (`append-section`). Two owners writing that way occupy
disjoint slices of the file, and reconciling one of them provably cannot disturb
the other. Since almost every module appends something to `.gitignore`, the rail
meant for whole-file collisions fires on nearly every targeted update in the
ecosystem.

After this change, two things are true that are not true today.

First, a targeted update succeeds when the shared path is additive-only. In a
project whose `.gitignore` is co-owned by `nix-haskell-flake` and `master-plan`,
both appending, `seihou update nix-haskell-flake` runs to completion,
`master-plan`'s lines are still in `.gitignore` afterwards byte for byte, and
`.seihou/manifest.json` still lists both applications as owners of the path. A
shared path that any owner writes wholesale — a rendered template, a copied
file, an `append-file`/`prepend-file` patch whose position in the file matters —
still refuses exactly as it does today.

Second, for the paths that legitimately still require every owner, the user gets
a way to say yes without typing every name:

```bash
seihou update nix-haskell-flake --include-shared-owners
```

expands the selection to exactly the applications the closure requires, reports
each one it added and why, and updates nothing else. A bare
`seihou update <target>` is never broadened silently; the expansion happens only
under the flag, and the refusal message names the flag so the remedy is visible
at the moment it is needed.

This plan implements
[`docs/improvement-requests/exempt-additive-patch-paths-from-shared-ownership-closure.md`](../improvement-requests/exempt-additive-patch-paths-from-shared-ownership-closure.md)
(IR-8).


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] Research the update selection, reconciliation, and manifest write paths; author this plan (2026-09-16).
- [x] Milestone 1 — record `additiveOnly` honestly on every manifest write path (2026-09-16).
  - [x] No hunks to park: the partial working-tree work described at plan creation was gone by the time
    implementation began, so the schema change was written from scratch at HEAD `54bac06`
    (see Surprises & Discoveries).
  - [x] `FileRecord` gained `additiveOnly`, with `isAdditivePatchOp` and `isAdditiveOperation`
    in `seihou-core/src/Seihou/Core/Types.hs`.
  - [x] Manifest codec: emitted only when `True`, decodes as `False` when absent
    (`seihou-core/src/Seihou/Manifest/Types.hs`).
  - [x] `executePlan` folds the flag across every operation per destination
    (`seihou-core/src/Seihou/Engine/Execute.hs`).
  - [x] `DesiredFile` gained the field, set from `all isAdditiveOperation pathOperations`
    (`seihou-core/src/Seihou/Engine/Reconcile.hs`). `validateOwner` left strict for Milestone 2.
  - [x] Added the remaining `FileRecord` construction sites: 2 in `seihou-cli/src-exe`
    (`Run.hs`, `AgentRun.hs`) and 30 across `seihou-core/test` and `seihou-cli/test`.
  - [x] Taught `prepareCandidateManifest` the partial-update merge rule for owners,
    `additiveOnly`, `moduleName`, and `strategy`.
  - [x] Taught `attachApplication` the same rule for the `seihou run` path — a fail-open gap the
    plan had not named (see Surprises & Discoveries and the Decision Log).
  - [x] Unit tests: codec round-trip / key omission / legacy decode (4),
    `executePlan` flag folding (7), partial-update merge rule (6), `attachApplication` (4).
    `cabal test all --enable-tests`: 1101 core + 572 cli + 51 okf-extension, all passing.
- [x] Milestone 2 — relax both ownership gates for additive-only paths and improve the refusal
  message (2026-09-16).
  - [x] `ensureOwnershipClosure` skips records whose `additiveOnly` is true
    (`seihou-cli/src/Seihou/CLI/Update/Selection.hs`).
  - [x] `validateOwner` exempts a path only when the manifest record's flag *and* every
    candidate operation for the path agree (`seihou-core/src/Seihou/Engine/Reconcile.hs`);
    `validateInputs` now traverses `Map.toList grouped` to hand it the operations.
  - [x] Refusal message explains that the path is not recorded as additive-only and names both
    reasons (`seihou-cli/src/Seihou/CLI/Update/Render.hs`). The `--include-shared-owners`
    mention is deliberately deferred to Milestone 3, so no message names a flag that does not
    exist yet.
  - [x] Unit tests: 2 selection preflight, 4 reconciliation.
  - [x] End-to-end proof on a two-owner `.gitignore` fixture
    (`prepareSharedPathFixture` in `seihou-cli/test/Seihou/CLI/UpdateSpec.hs`, driven from
    `seihou-cli/test/Seihou/CLI/UpdateE2ESpec.hs`): the additive case applies and keeps the
    co-owner's line and both application ids; the whole-file case refuses with
    `shared_path_requires_applications` and leaves project and manifest byte-identical.
- [x] Milestone 3 — add `seihou update <target> --include-shared-owners` (2026-09-16).
  - [x] `SelectionPolicy` and the fixed-point `expandToSharedOwners`
    (`seihou-cli/src/Seihou/CLI/Update/Selection.hs`); `selectApplications` now takes the
    policy and returns its warnings.
  - [x] `SelectionExpandedForSharedPath FilePath ApplicationId` on `UpdateWarning`, rendered as
    prose by `warningText` (`seihou-cli/src/Seihou/CLI/Update/Render.hs`).
  - [x] `includeSharedOwners` on `UpdateRequest`, `UpdateOpts`, `updateParser`,
    `makeUpdateOpts`, and `requestFromOptions`; threaded through `selectAndSeedLegacy`.
  - [x] The refusal message now names `--include-shared-owners`.
  - [x] Unit tests: 3 selection (single expansion, three-application fixed point, no expansion
    for an additive path), 2 render. End-to-end: the flag updates the co-owner and reports it;
    `seihou update --help` lists it.
- [x] Milestone 4 — documentation, changelogs, ADR, and full-suite verification (2026-09-16).
  - [x] `docs/cli/update.md`: the refusal sentence replaced with the additive rule, plus
    `--include-shared-owners` and the previously undocumented `--allow-downgrade` in the
    options table and a section on how the expansion behaves.
  - [x] `seihou-cli/help/update.md`: the same correction in the embedded help, verified with
    `seihou help update`.
  - [x] `docs/user/CHANGELOG.md` and `CHANGELOG.md` under Unreleased.
  - [x] [ADR 0012](../adr/0012-an-additive-co-write-is-not-a-shared-path-conflict.md).
  - [x] `nix flake check` passes; `cabal test all --enable-tests` passes.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- **The partial working-tree work described at plan creation was gone when implementation
  began.** Plan creation recorded five modified source files beginning the Milestone 1 and
  Milestone 2 work. At the start of the implementation session — same HEAD, `54bac06` —
  `git status --short` showed only the two improvement-request documents and this plan:

  ```text
   M docs/improvement-requests/exempt-additive-patch-paths-from-shared-ownership-closure.md
   M docs/improvement-requests/log.md
  ?? docs/plans/90-exempt-additive-patch-paths-from-the-shared-ownership-closure.md
  ```

  `grep -rn "additiveOnly\|isAdditive" --include="*.hs" .` returned nothing. The schema change
  was therefore written from scratch rather than completed, which made the "park the two
  gate-relaxing hunks" step unnecessary: the gates were already strict, so Milestone 1 landed
  with no user-visible behaviour change by construction rather than by reverting anything.

- **`attachApplication` carries the same fail-open hazard as `prepareCandidateManifest`, and
  the plan did not name it.** The plan's Decision Log identifies the partial-update merge rule
  for the `seihou update` path. `seihou run` has an independent write path:
  `seihou-cli/src-exe/Seihou/CLI/Run.hs` (line 459) calls
  `Seihou.Core.Application.attachApplication` to union the prior record's owners into the
  freshly executed record, and before this change that function set only `applicationIds`:

  ```haskell
  attachApplication applicationId previous current =
    current
      & #applicationIds .~ Set.insert applicationId (Set.union (current ^. #applicationIds) priorApplications)
  ```

  Applying module B (which appends to `.gitignore`) to a project where application A already
  wrote `.gitignore` wholesale would therefore have recorded `additiveOnly = True` — B's own
  honest answer — for a path A rewrites, opening both gates for a later targeted update that is
  not safe. `attachApplication` now weakens the flag whenever a prior owner survives outside
  the current application, by exactly the rule `prepareCandidateManifest` uses. Four tests in
  `seihou-core/test/Seihou/Core/ApplicationSpec.hs` cover it.

- **The repository's test suites are not in the default `cabal` install plan.** `cabal test all`
  fails with `[Cabal-7043] ... the solver picked a plan that does not include the test suites`.
  `cabal test all --enable-tests` works and is what this plan's commands should say; `just test`
  (which runs the bare `cabal test all`) has the same problem. Recorded here rather than fixed,
  since changing `cabal.project` is outside this plan's scope.

- **`AppendSection` is not idempotent when a module is re-applied to itself.**
  `applyTextPatch AppendSection` in `seihou-core/src/Seihou/Engine/Section.hs` appends
  unconditionally:

  ```haskell
  applyTextPatch AppendSection modName prefix existing new =
    let marker = SectionMarker {prefix = prefix, module_ = modName}
     in Right (ensureTrailingNewline existing <> wrapInSection marker new)
  ```

  Nothing anywhere in `seihou-core/src` or `seihou-cli/src` removes an existing section
  before appending (`removeSection` is used only by `seihou-core/src/Seihou/Engine/Remove.hs`).
  Because an update replays generation on top of the previously generated baseline, a
  module that contributes a section appears to grow a second copy of its own section on
  every update. **This is orthogonal to this plan**: it affects whole-project updates
  identically, and it concerns an owner's own bytes, not a co-owner's. The exemption's
  safety claim is about *cross-owner* non-interference, which holds — an appended section
  never moves or rewrites another owner's section or lines. Milestone 2 verifies the
  cross-owner claim end to end; if the self-duplication is observed while doing so, record
  it here with evidence and file it as a separate improvement request rather than widening
  this plan.


## Decision Log

Record every decision made while working on the plan.

- Decision: Record the exemption as a single boolean `FileRecord.additiveOnly`, not as a
  per-application map of write modes.
  Rationale: The only question either gate asks is conjunctive — "does *every* contribution
  to this path go through an additive, non-overlapping patch?" A boolean answers exactly
  that with the smallest possible schema change, decodes as `False` when absent so legacy
  manifests fail closed, and is already the shape the working tree started. The cost is that
  a `False` cannot distinguish "an owner writes the whole file" from "this manifest predates
  the field", so the refusal message must mention both possibilities; that is cheaper than
  carrying a per-owner map through `FileRecord`, `DesiredFile`, `DesiredFileOwner`, and both
  write paths. [ADR 0004](../adr/0004-the-manifest-is-the-only-record-of-applied-state.md)
  settles where the field belongs: a fact about applied state goes in the manifest.
  Date: 2026-09-16

- Decision: Do not bump `currentManifestVersion` (it stays at 6).
  Rationale: The field is additive, optional, and emitted only when `True`, so a manifest
  with no additive-only paths is byte-identical to one written today. A seihou build that
  predates the field ignores it and keeps enforcing the closure everywhere, which is the
  conservative behavior — no misreading is possible. Bumping to 7 would make every manifest
  written by this release unreadable to 0.8.x binaries
  ("manifest was created by a newer version of seihou") in exchange for nothing. This is a
  deliberate departure from the 3→4 and 4→5 precedent, which bumped for additive fields that
  older readers would have *misinterpreted*.
  Date: 2026-09-16

- Decision: The additive, non-overlapping set is exactly `AppendLineIfAbsent` and
  `AppendSection`. `AppendFile` and `PrependFile` stay under the closure requirement, as do
  all four whole-file strategies (`Copy`, `Template`, `DhallText`, `Structured`).
  Rationale: `AppendLineIfAbsent` filters out lines already present, so it is idempotent and
  commutative; `AppendSection` writes a region delimited by the owner's own markers, which no
  other owner's region overlaps. `AppendFile`/`PrependFile` place bytes relative to whatever
  is already there, so replaying one owner without the others can reorder the result.
  Date: 2026-09-16

- Decision: Check the exemption in two layers — the CLI preflight consults the manifest, and
  reconciliation additionally consults the candidate's own operations.
  Rationale: Selection happens before any artifact is fetched, so the manifest is the only
  evidence available there. By the time `Seihou.Engine.Reconcile` runs, the candidate's
  operations are known, so a module whose new version changed `.gitignore` from a patch step
  to a template step is caught before anything is written, instead of being trusted on the
  strength of last release's record.
  Date: 2026-09-16

- Decision: A partial update of a co-owned path must union the surviving owners into the
  manifest record rather than replacing them, must keep the prior `moduleName`/`strategy`,
  and may only keep `additiveOnly = True` if the prior record also said so.
  Rationale: `prepareCandidateManifest` currently writes `applicationIds = desired ^. #applicationIds`,
  which is the *selection's* view. Before this plan that was safe because the closure
  guaranteed the selection contained every owner. Once the exemption lets a subset through,
  the same line would quietly delete the unselected co-owner from the manifest, and
  recomputing `additiveOnly` from the selection alone could flip a `False` (set because an
  unselected owner writes the whole file) to `True`, opening the gate for a later update that
  really is unsafe. Both are fail-open bugs and must land with, or before, the gate change.
  Date: 2026-09-16

- Decision: Apply the same weakening rule to `attachApplication`, so the `seihou run` path
  cannot strengthen `additiveOnly` either.
  Rationale: The plan's merge-rule decision covers `prepareCandidateManifest`, but
  `Seihou.Core.Application.attachApplication` is an independent second write path with the
  identical shape: it unions a prior record's owners into a record produced by executing one
  application's operations. Leaving it alone would let `seihou run <module-that-appends>` flip a
  `False` to `True` for a path a co-owner rewrites wholesale — the same fail-open bug the merge
  rule exists to prevent, reachable without ever running `seihou update`. Both write paths now
  answer the same question the same way: a partial contribution can weaken the flag, never
  strengthen it. Recorded in Surprises & Discoveries with the pre-change code.
  Date: 2026-09-16

- Decision: Set `additiveOnly = False` on the records that `seihou run` and `seihou agent run`
  synthesize for a `KeepCurrent` conflict resolution with no prior record.
  Rationale: `seihou-cli/src-exe/Seihou/CLI/Run.hs` and
  `seihou-cli/src-exe/Seihou/CLI/AgentRun.hs` mint a `FileRecord` for a path the user chose to
  keep by hand, whose bytes generation did not produce. Nothing is known about how any owner
  writes it, and the field's contract is that `False` is the reading that keeps the closure
  enforced. The sibling branch reuses the existing record through a lens set, so a genuine
  prior `True` survives untouched.
  Date: 2026-09-16

- Decision: Name the opt-in `--include-shared-owners`, expand to a fixed point, and report
  every application the expansion added.
  Rationale: The IR leaves the name to the author; this one says what it does in the
  vocabulary the error message already uses ("is also owned by application(s)"). Expansion
  must iterate because a pulled-in co-owner can itself share a different path with a third
  application. Reporting each addition preserves the plans 66/68/69 principle that a named
  selection is never *silently* broadened.
  Date: 2026-09-16


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose. Before marking the plan complete,
distill durable project context from the Decision Log, Surprises & Discoveries, and
this section into docs/adr/. Keep task-local execution details here.

**Milestone 1 (2026-09-16).** The manifest now records, per managed path, whether every
contribution to it goes through an additive, non-overlapping patch. Both ownership gates are
still strict, so nothing a user does behaves differently yet; the milestone's whole value is
that the evidence Milestone 2 acts on is now recorded honestly, on every write path.

Two things came out differently from the plan. First, the partial work the plan expected to
build on was no longer in the tree, which removed the "park the gate hunks" step and made the
"no user-visible change" property structural rather than something to maintain by hand.
Second, the plan's fail-open analysis was one write path short: `attachApplication` on the
`seihou run` path could strengthen the flag exactly as `prepareCandidateManifest` could, and
would have done so in the ordinary case of applying an appending module to a project that
already has a wholesale-written `.gitignore`. Both are recorded in Surprises & Discoveries,
and the second added a Decision Log entry and four tests. The lesson worth carrying into the
ADR: this field has two producers, not one, and the rule that a partial contribution may only
weaken it has to hold at both.

**Milestone 2 (2026-09-16).** Both gates now consult the flag, and the behaviour the plan set
out to deliver exists. In a project whose `.gitignore` is co-owned by two appending
applications, `seihou update <one-of-them>` completes, the other's lines survive byte for
byte, and both application ids stay in the manifest. A shared path any owner writes wholesale
still refuses, with a message that now says *why* the exemption did not apply.

The layered check earned its keep immediately as a test case: the reconciliation gate refuses
a module whose new version swapped its patch step for a template step even though the manifest
still records the path as additive. Without the second layer that update would have written,
on the strength of the previous release's record.

**Milestone 3 (2026-09-16).** `--include-shared-owners` lands. The fixed-point iteration is
not defensive engineering — the three-application chain test (one and two share `a.txt`, two
and three share `b.txt`, selecting one must yield all three) fails with a single pass. One
thing the plan did not specify: the expansion skips additive-only paths, because a path that
no longer requires the closure must not pull in a co-owner the user neither asked for nor
needed. There is a test for that too.

**Milestone 4 (2026-09-16).** Documentation, both changelogs, and
[ADR 0012](../adr/0012-an-additive-co-write-is-not-a-shared-path-conflict.md).

**Against the original purpose.** Both things the Purpose section promised are now true. A
targeted update succeeds when the shared path is additive-only, verified end to end through
the real binary rather than only at the unit level; and `--include-shared-owners` exists for
the paths that legitimately still need every owner, expanding to exactly those and reporting
each addition.

**Lessons.** Two worth keeping, both now in the ADR. First, this flag has *two* producers, not
one: the plan analysed `prepareCandidateManifest` carefully and missed `attachApplication` on
the `seihou run` path, which had the identical fail-open shape and would have been reachable
without ever running `seihou update`. When a derived fact is written from more than one place,
enumerate the write paths before reasoning about the invariant. Second, the deliberate
*non*-bump of the manifest schema version is the interesting decision here, and the reason
generalizes: the test for bumping is whether an older reader would **misinterpret** the new
field, not whether the field is new. A key emitted only when true, whose absence means the
conservative answer, is invisible to an older reader in the only way that matters.


## Context and Orientation

This section assumes no prior knowledge of the repository. Everything below was read from
the working tree at HEAD `54bac06`.

### What Seihou does, in one paragraph

Seihou generates project files from reusable *modules*. A module is a directory containing
a `module.dhall` definition and template files; applying one produces files in a project and
records what it did in `.seihou/manifest.json`. The Haskell workspace has two packages:
`seihou-core` (library: types, generation engine, manifest codec) and `seihou-cli` (a
library at `seihou-cli/src` plus the executable at `seihou-cli/src-exe`). Build with
`cabal build all`, test with `cabal test all --enable-tests`, both from the repository root.

### The vocabulary this plan uses

**Application.** One top-level thing a user applied: a module or a recipe, with everything it
composed. Recorded in the manifest's `applications` list, each with a stable
`ApplicationId`. A project typically has several — in the reported case, one for
`nix-haskell-flake` and one for `master-plan`.

**Managed path.** A project-relative file path Seihou generated and now tracks. The manifest's
`files` map holds one `FileRecord` per managed path
(`seihou-core/src/Seihou/Core/Types.hs`, around line 730). A `FileRecord` records the content
hash, the module name credited with the path, the generation strategy, a timestamp, an
optional generated-baseline reference, and `applicationIds` — the set of applications that
own the path.

**Co-owned path.** A managed path whose `applicationIds` holds more than one application.

**Strategy versus patch.** A generation step either writes a whole file with one of four
strategies (`Copy`, `Template`, `DhallText`, `Structured`) or *patches* an existing file with
one of four patch operations, declared in Dhall as the step's `patch` field and modelled by
`PatchOp` in `seihou-core/src/Seihou/Core/Types.hs`:

```haskell
data PatchOp
  = AppendFile
  | PrependFile
  | AppendSection
  | AppendLineIfAbsent
```

`AppendLineIfAbsent` appends only the lines not already present. `AppendSection` appends the
content wrapped in comment markers naming the module, like
`# --- seihou:nix-haskell-flake ---`. Both are implemented in
`seihou-core/src/Seihou/Engine/Section.hs` (`applyTextPatch`).

**Operation.** The compiled, executable form of a step: `WriteFileOp`, `CopyFileOp`,
`PatchFileOp`, `CreateDirOp`, `RunCommandOp` (`Operation` in
`seihou-core/src/Seihou/Core/Types.hs`, around line 400). `seihou run` and `seihou update`
both work from a list of these.

**Ownership closure.** The rule this plan changes: for every managed path, if any selected
application owns it, then every application that owns it must also be selected. Enforced
before anything is fetched by `ensureOwnershipClosure` in
`seihou-cli/src/Seihou/CLI/Update/Selection.hs`, and again as defense in depth by
`validateOwner` in `seihou-core/src/Seihou/Engine/Reconcile.hs`. Both report
`SharedPathRequiresApplications`.

### How a targeted update actually reaches the disk

Understanding the safety argument requires knowing where the generated bytes come from. The
sequence, for `seihou update <target>`:

1. `seihou-cli/src-exe/Seihou/CLI/Update.hs` turns command-line options into an
   `UpdateRequest` (`requestFromOptions`) and calls `Service.withProjectUpdate`.
2. `seihou-cli/src/Seihou/CLI/Update.hs` selects applications
   (`selectAndSeedLegacy`, line 431, calling `selectApplications`). **This is where the
   preflight refusal happens, before any artifact is cloned.**
3. Each selected application is planned separately, producing operations and a
   `Map FilePath DesiredFileOwner`; `combineApplicationPlans` (line 529) merges them. Only
   *selected* applications are planned, so the operation list contains only their
   contributions.
4. `Seihou.Engine.Reconcile.planReconciliation` materializes each path. For a path with a
   prior record, `materializeOne` starts from the *trusted baseline* — the exact bytes the
   previous successful application generated, stored under `.seihou/baselines/` — and then
   replays this run's operations on top of it:

   ```haskell
   applyGenerationOperation _ path existing (PatchFileOp _ content patch _strategy moduleName) =
     pure $
       first
         (PatchMaterializationFailed path patch moduleName)
         (applyTextPatch patch moduleName "#" existing content)
   ```

   **This is the mechanism that makes the exemption safe.** The baseline for `.gitignore`
   already contains every owner's lines. Replaying only the selected owner's
   `append-line-if-absent` on top of it leaves the unselected owner's lines exactly where
   they were. A `WriteFileOp`, by contrast, discards `existing` entirely — which is precisely
   why whole-file paths must keep the closure requirement.
5. `Seihou.Engine.UpdateTransaction.prepareCandidateManifest` writes the new manifest records
   from the reconciliation result.

### What Milestone 1 has already landed

Milestone 1 is complete and committed. Plan creation had described five uncommitted source
files beginning this work; they were gone by the time implementation started, so the schema
change was written from scratch at the same HEAD (see Surprises & Discoveries). What now
exists in the tree:

- `seihou-core/src/Seihou/Core/Types.hs`: `FileRecord` has a seventh field
  `additiveOnly :: !Bool`, and the module exports `isAdditivePatchOp :: PatchOp -> Bool`
  (true for `AppendLineIfAbsent` and `AppendSection`) and
  `isAdditiveOperation :: Operation -> Bool` (true only for an additive `PatchFileOp`).
- `seihou-core/src/Seihou/Manifest/Types.hs`: `additiveOnly` is emitted only when true and
  decodes as `False` when absent. `currentManifestVersion` stays at 6, with the reasoning in
  its Haddock comment.
- `seihou-core/src/Seihou/Engine/Execute.hs`: `executePlan` folds the flag across every
  operation targeting each destination, so a path is additive-only only if *all* of its
  operations are.
- `seihou-core/src/Seihou/Engine/Reconcile.hs`: `DesiredFile` has the same field, set from
  `all isAdditiveOperation pathOperations`. **`validateOwner` is still strict** — the
  reconciliation exemption is Milestone 2 work.
- `seihou-core/src/Seihou/Engine/UpdateTransaction.hs`: `prepareCandidateManifest` applies the
  partial-update merge rule, and `replaceRecordApplications` carries the flag through.
- `seihou-core/src/Seihou/Core/Application.hs`: `attachApplication` applies the same rule on
  the `seihou run` path.
- `seihou-cli/src-exe/Seihou/CLI/Run.hs` and `.../AgentRun.hs`: the synthesized
  `KeepCurrent` records set `additiveOnly = False`.

Because both gates are still strict, no user-visible behaviour changed: the manifest simply
now tells the truth about which paths are reached only through additive patches.

What remains: the two gate exemptions, the refusal message, the `--include-shared-owners`
flag, the end-to-end fixtures, and every document. `seihou-cli/src/Seihou/CLI/Update/Selection.hs`
is untouched so far — `ensureOwnershipClosure` still refuses every co-owned path.

### Relevant ADRs

`docs/adr/` is a plain numbered directory (`NNNN-slug.md`), not an OKF bundle: there is no
`docs/adr/profile.dhall`, `index.md`, or `log.md`, and `mori.dhall` declares no bundle there.
Follow the existing filesystem convention and the heading shape used by the existing
records (`# ADR NNNN — Title`, then `- Status:`, `- Date:`, `## Context`, `## Decision`,
`## Consequences`, `## References`). Three records bear on this work:

- [ADR 0001 — The manifest is a checked-in, machine-independent project artifact](../adr/0001-manifest-is-a-checked-in-machine-independent-artifact.md).
  `.seihou/manifest.json` is committed and must contain nothing whose meaning depends on the
  machine that wrote it. A boolean derived from the module's own declared steps satisfies
  this; nothing in this plan records a path, a user, or a host.
- [ADR 0004 — The manifest is the only record of applied state; there is no lockfile](../adr/0004-the-manifest-is-the-only-record-of-applied-state.md).
  "A field that records something about the applied state belongs in the manifest." This is
  the direct authority for putting `additiveOnly` on `FileRecord` rather than re-deriving it
  by re-resolving unselected owners' modules at update time, which the IR lists as its
  option (b).
- [ADR 0005 — Legacy manifests convert through an explicit command, and the compatibility
  guard has no removal date](../adr/0005-legacy-manifests-convert-through-an-explicit-command.md).
  Schema growth is handled by versioning plus a conversion path, never by silent reinterpretation.
  This plan adds a field that is absent-means-conservative, so no conversion command and no
  version bump are needed; the reasoning is recorded in the Decision Log and belongs in the
  new ADR.

Milestone 4 added the fourth:

- [ADR 0012 — An additive co-write is not a shared-path conflict](../adr/0012-an-additive-co-write-is-not-a-shared-path-conflict.md).
  The durable record of this plan's decisions: the exact additive set and why
  `AppendFile`/`PrependFile` are excluded, the fail-closed default, why the flag lives in the
  manifest and why the schema version does not move, the two-layer check, the rule that both
  manifest write paths may only weaken the flag, and that broadening a named selection stays
  opt-in.

### Related plans

The closure requirement was introduced by
[`docs/plans/66-plan-conflict-aware-file-reconciliation-and-safe-orphan-handling.md`](66-plan-conflict-aware-file-reconciliation-and-safe-orphan-handling.md)
and its successors 68 and 69, coordinated by
[`docs/masterplans/8-make-module-updates-seamless-and-conflict-aware.md`](../masterplans/8-make-module-updates-seamless-and-conflict-aware.md).
Their principle — a named selection is never silently broadened — is preserved here: part one
narrows what counts as a conflict, and part two broadens a selection only under an explicit
flag.


## Plan of Work

Four milestones. Each leaves the tree building and the full test suite passing, and each is
verifiable on its own. Milestone 1 makes the manifest tell the truth; Milestone 2 acts on it;
Milestone 3 adds the opt-in; Milestone 4 documents and distills.

### Milestone 1 — Record `additiveOnly` honestly on every write path

**Scope.** Finish the schema change already begun in the working tree, and make every path
that writes a `FileRecord` compute the flag correctly, *including* the partial-update case
that does not yet exist but will the moment Milestone 2 lands. The ownership gates stay strict
throughout this milestone, so no user-visible behavior changes: this is the foundation.

**What exists at the end.** `cabal build all` and `cabal test all --enable-tests` succeed. After
`seihou run` or a whole-project `seihou update` in a project whose `.gitignore` is written by
`append-line-if-absent` steps, `.seihou/manifest.json` contains `"additiveOnly": true` on that
record and no `additiveOnly` key on records for templated files. A manifest written before
this change still loads, and its records read as `additiveOnly = False`.

**Work.**

First, keep both gates strict. `ensureOwnershipClosure`
(`seihou-cli/src/Seihou/CLI/Update/Selection.hs`) and `validateOwner`
(`seihou-core/src/Seihou/Engine/Reconcile.hs`) belong to Milestone 2 and must not be relaxed
before the manifest merge rule below, or a targeted update will delete a co-owner from the
manifest. The `DesiredFile` field and its
`additiveOnly = all isAdditiveOperation pathOperations` assignment are Milestone 1 work.

Second, add the field everywhere a `FileRecord` is constructed. In `seihou-core/src`:
`Seihou/Engine/UpdateTransaction.hs` at the `FileRecord` literal inside
`prepareCandidateManifest` and at `replaceRecordApplications`, which must carry the prior
record's flag through unchanged. In `seihou-cli/src-exe`: the synthesized `KeepCurrent`
records in `Seihou/CLI/Run.hs` and `Seihou/CLI/AgentRun.hs` take the conservative `False`.
In tests, thirty sites across `seihou-core/test` and `seihou-cli/test` construct `FileRecord`
positionally or with record syntax; find them with

```bash
grep -rn "FileRecord" seihou-core/test seihou-cli/test
```

and give each the conservative value `False` unless the test is specifically about additive
paths. Note `seihou-cli/test/Seihou/CLI/UpdateFixture.hs` and
`seihou-cli/test/Seihou/CLI/UpdateSpec.hs` (`prepareUpdateFixture`, around line 454).

Third, teach `prepareCandidateManifest` in
`seihou-core/src/Seihou/Engine/UpdateTransaction.hs` the partial-update merge rule. Today it
writes the selection's view of the record wholesale:

```haskell
        let record =
              FileRecord
                { hash = state ^. #recordedHash,
                  moduleName = desired ^. #moduleName,
                  strategy = desired ^. #strategy,
                  generatedAt = manifest ^. #genAt,
                  baseline = Just baseline,
                  applicationIds = desired ^. #applicationIds
                }
```

It must instead preserve everything belonging to owners outside this update. The selection is
available as `plan ^. #applicationIds`, and the prior record is `Map.lookup path files` in the
same fold. Compute:

- `retainedOwners = priorOwners \\ selected` — owners this update did not touch. Note the
  subtraction is against the *selection*, not against the desired set: a selected application
  that stopped writing the path must genuinely lose ownership, while an unselected one must
  keep it.
- `applicationIds = (desired ^. #applicationIds) `Set.union` retainedOwners`.
- `additiveOnly = (desired ^. #additiveOnly) && (Set.null retainedOwners || priorAdditive)`,
  where `priorAdditive` is the prior record's flag. The prior flag summarizes *all* owners
  including the ones absent from this run, so it can only be weakened, never strengthened, by
  a partial update.
- `moduleName` and `strategy`: keep the prior record's values when `retainedOwners` is
  non-empty, otherwise take the desired file's. A partial update has no standing to re-credit
  a path it only partly wrote, and this also avoids manifest churn where the credited module
  flips back and forth between targeted runs.

Write these with `generic-lens` labels or explicit construction; record *update* syntax is
forbidden repository-wide and mechanically rejected by `nix/check-record-conventions.sh`.

Fourth, apply the same weakening rule to `attachApplication` in
`seihou-core/src/Seihou/Core/Application.hs`. This is the `seihou run` counterpart of the
merge rule above — it unions a prior record's owners into a record produced by executing one
application's operations, and left alone it would flip a `False` to `True` for a path a
co-owner rewrites wholesale. The rule is the same: `retainedOwners` is
`priorApplications \\ {thisApplication}`, and when that is non-empty the flag becomes
`current.additiveOnly && prior.additiveOnly`. See Surprises & Discoveries.

Fifth, add the tests listed under Validation and Acceptance for this milestone.

**Acceptance.** `cabal build all` succeeds; `cabal test all --enable-tests` passes; the new
unit tests fail if the merge rule is reverted.

**Result (2026-09-16).** Done. `cabal test all --enable-tests`: 1101 `seihou-core-test`,
572 `seihou-cli-test`, 51 `seihou-okf-extension-test`, all passing;
`nix/check-record-conventions.sh` and `nix/check-cli-module-placement.sh` both clean. The
merge rule was verified by reverting `prepareCandidateManifest` to
`applicationIds = desired ^. #applicationIds` / `additiveOnly = desired ^. #additiveOnly` and
re-running the group, which failed 3 of 6:

```text
      keeps an unselected co-owner in the record:                                 FAIL
      keeps the prior attribution when an unselected co-owner survives:           FAIL
      cannot strengthen additiveOnly from a partial update:                       FAIL
3 out of 6 tests failed (0.03s)
```

### Milestone 2 — Let an additive-only shared path through both gates

**Scope.** Restore and complete the two exemptions, tighten the reconciliation one so it also
consults the candidate's operations, and improve the refusal message. This is the milestone
that changes what the user sees.

**What exists at the end.** In a project whose `.gitignore` is co-owned by two applications
that both append, `seihou update <one-of-them>` completes; the other's lines survive on disk;
the manifest still lists both owners. A co-owned path written with `template` still refuses,
now with a message that also names `--include-shared-owners` (the flag arrives in Milestone 3;
add the wording then, or add it now and land Milestone 3 immediately after — do not ship a
message naming a flag that does not exist).

**Work.**

In `seihou-cli/src/Seihou/CLI/Update/Selection.hs`, `ensureOwnershipClosure` skips any record
whose `additiveOnly` is true. This is the preflight; only the manifest is available here,
since nothing has been fetched yet.

In `seihou-core/src/Seihou/Engine/Reconcile.hs`, `validateOwner` must require *both* halves:
the manifest's record says the path was additive-only, **and** every operation this run
contributes to the path is additive. `validateInputs` already has the grouped operations
(`grouped = groupFileOperations operations`) and currently calls
`traverse_ (validateOwner selected ownerMap manifest) (Map.keys grouped)`. Pass the
operations along — for example by traversing `Map.toList grouped` and giving `validateOwner`
the `[Operation]` for the path — and exempt the path only when
`record ^. #additiveOnly && all isAdditiveOperation pathOperations`. This is what catches a
module whose new version changed `.gitignore` from a patch step to a template step: the
manifest still says additive, the candidate is not, and the update refuses before writing
anything.

In `seihou-cli/src/Seihou/CLI/Update/Render.hs`, extend `errorMessage` for
`SharedPathRequiresApplications` so the refusal explains itself. The current text is:

```text
Path .gitignore is also owned by application(s) <master-plan>. Select every owner or run
seihou update with no targets. Selected: <nix-haskell-flake>
```

It should also say that the path is not additive-only — either because an owner writes the
whole file or because the manifest predates the field, in which case one whole-project
`seihou update` records it — and name `--include-shared-owners`. Keep the existing
`errorCode` (`shared_path_requires_applications`) and the constructor shape so JSON consumers
and existing tests are unaffected.

**Acceptance.** The end-to-end test described under Validation and Acceptance passes:
targeted update on the two-owner `.gitignore` fixture succeeds, the co-owner's line is still
present byte for byte, and the manifest still names both applications. The whole-file variant
of the same fixture still refuses with exit status 1 and the code
`shared_path_requires_applications`.

**Result (2026-09-16).** Done. `cabal test all --enable-tests`: 1105 core + 576 cli + 51
okf-extension, all passing. The fixture is `prepareSharedPathFixture` in
`seihou-cli/test/Seihou/CLI/UpdateSpec.hs`, parameterized by a `CoOwnerWriteMode`
(`CoOwnerAppends` / `CoOwnerWritesWholeFile`) so the positive and negative cases share one
builder. On the additive fixture, `seihou update alpha --json` reports
`"outcome":"applied"` and `.gitignore` becomes `/dist-newstyle\n/result\n/alpha-v2\n` — beta's
`/result` untouched — with both application ids and `"additiveOnly":true` still in the
manifest. On the whole-file fixture the same command exits non-zero with
`shared_path_requires_applications`, and both `.gitignore` and `.seihou/manifest.json` are
byte-identical afterwards.

The refusal message gained the explanation but not the flag name, since `--include-shared-owners`
does not exist until Milestone 3; Milestone 3 adds the mention.

### Milestone 3 — `--include-shared-owners`

**Scope.** The explicit opt-in that expands a named selection to the applications the closure
still requires.

**What exists at the end.** `seihou update <target> --include-shared-owners` updates the
target plus exactly its co-owners, printing one line per added application. `seihou update
--help` lists the flag. Without the flag, behavior is unchanged.

**Work.**

Add `includeSharedOwners :: !Bool` to `UpdateOpts`
(`seihou-cli/src-exe/Seihou/CLI/Commands.hs`, around line 169) and a corresponding
`switch (long "include-shared-owners" <> help "Also update applications that co-own a
selected path")` at the end of `updateParser`'s applicative chain, threading it through the
positional `makeUpdateOpts` helper. Add the same field to `UpdateRequest`
(`seihou-cli/src/Seihou/CLI/Update/Types.hs`, around line 52) and set it in
`requestFromOptions` (`seihou-cli/src-exe/Seihou/CLI/Update.hs`, around line 57).

In `seihou-cli/src/Seihou/CLI/Update/Selection.hs`, introduce

```haskell
data SelectionPolicy
  = RequireNamedOwners
  | IncludeSharedOwners
  deriving stock (Eq, Show)
```

and change `selectApplications` to take the policy and to return the warnings it produced:

```haskell
selectApplications ::
  SelectionPolicy ->
  UpdateSelection ->
  Manifest ->
  Either UpdateError (SelectedApplications, [UpdateWarning])
```

Under `IncludeSharedOwners`, expand the selected set to a fixed point before checking the
closure: repeatedly, for every record that is *not* `additiveOnly` and whose owners intersect
the selection, add all of its owners, until nothing is added. A single pass is not enough — a
co-owner pulled in through one path may co-own a different path with a third application.
Expansion applies only to `RecordedSelection`; a `LegacySelection` (a manifest with no
recorded applications) has no ownership to close over. Afterwards run the unchanged
`ensureOwnershipClosure`, which should now pass; if it does not, that is a bug in the
expansion and the error should surface as-is rather than being suppressed.

Report each addition with a new `UpdateWarning` constructor, for example
`SelectionExpandedForSharedPath FilePath ApplicationId`, and give it an explicit case in
`warningText` (`seihou-cli/src/Seihou/CLI/Update/Render.hs`, line 325) rather than falling
through to `T.pack . show`, so the line reads like prose:

```text
Warning:     also updating master-plan because it co-owns .gitignore
```

Thread the warnings through `selectAndSeedLegacy` in `seihou-cli/src/Seihou/CLI/Update.hs`
(line 431), which already returns an `[UpdateWarning]`.

Update the two `UpdateRequest` literals in the test tree
(`seihou-cli/test/Seihou/CLI/UpdateFixture.hs`, `seihou-cli/test/Seihou/CLI/UpdateSpec.hs`)
and every `selectApplications` call in `seihou-cli/test/Seihou/CLI/UpdateSpec.hs`.

**Acceptance.** The unit and end-to-end tests described below pass, including the
fixed-point case where expanding for one path pulls in an application that forces a second
expansion for another path.

**Result (2026-09-16).** Done. `cabal test all --enable-tests`: 1105 core + 583 cli + 51
okf-extension, all passing. `seihou update --help` lists the flag:

```text
  --include-shared-owners  Also update applications that co-own a selected path
```

Two departures from the plan as written, both small. `expandToSharedOwners` skips
additive-only records: a path that no longer requires the closure must not pull in a co-owner
the user neither asked for nor needed, and there is a test for it. And `warningText` keeps a
`show` fallback for the other constructors rather than gaining an exhaustive case list, since
only the new warning needs prose; the render test asserts the constructor name does not leak.

### Milestone 4 — Documentation, changelog, ADR, and distillation

**Scope.** Everything a user or a future contributor reads.

**Work.**

- `docs/cli/update.md`: replace the sentence "Seihou refuses a partial selection when a
  generated path is also owned by an unselected application; run the no-target form or name
  every required owner" with an accurate description of the additive exemption, and add
  `--include-shared-owners` to the options table.
- `seihou-cli/help/update.md` (embedded in the binary and shown by `seihou help update`):
  the same correction around line 36.
- `docs/user/CHANGELOG.md` under `## Unreleased`: a user-facing entry explaining that a
  targeted update no longer refuses on a shared file every module appends to, and what the
  new flag does.
- `CHANGELOG.md` at the repository root under `## Unreleased`: the engineering entry, naming
  the manifest field, the two gates, and the deliberate decision not to bump the schema
  version.
- `docs/adr/0012-an-additive-co-write-is-not-a-shared-path-conflict.md`: the durable
  decision. Confirm `0012` is the next unused number with `ls docs/adr` before writing.
  Record: what the closure protects; why an additive co-write is outside it; the exact
  additive set and why `AppendFile`/`PrependFile` are excluded; the fail-closed default and
  why a `False` from a legacy manifest is the safe reading; why the flag lives in the
  manifest (ADR 0004) and why the schema version does not move; that both manifest write paths
  (`prepareCandidateManifest` for `seihou update`, `attachApplication` for `seihou run`) may
  only weaken the flag, never strengthen it, and why; and that broadening a named selection
  stays opt-in.
- Update this plan's Outcomes & Retrospective and check off Progress.

**Acceptance.** `nix flake check` passes (it runs the record-convention and CLI module
placement checks along with the build and tests), and `seihou help update` shows the new
text.

**Result (2026-09-16).** Done. `nix flake check` reports
`checks.aarch64-darwin.pre-commit`, `record-conventions`, `cli-module-placement`, and
`treefmt` all green; `cabal test all --enable-tests` passes 1105 core + 583 cli + 51
okf-extension. `seihou help update` and `seihou update --help` both show the new text, the
latter listing `--include-shared-owners`.

`0012` was confirmed as the next unused number. One addition beyond the plan: the options
table in `docs/cli/update.md` was missing `--allow-downgrade` as well, so it was added in the
same edit rather than left as a known gap in a table this change was already rewriting.


## Concrete Steps

All commands run from the repository root,
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`.

Before starting, see what the working tree already contains:

```bash
git status --short
git diff --stat
```

Plan creation recorded five modified source files here; by the time implementation began they
were gone and only the documents remained (see Surprises & Discoveries). Whatever the output,
treat it as the current state and correct this plan rather than the tree.

Build and test. **`--enable-tests` is required**: the default install plan omits the test
suites, and a bare `cabal test all` fails with `[Cabal-7043]` rather than running anything.

```bash
cabal build all
cabal test all --enable-tests
```

Run one test suite, or one group within it (the suites are `tasty`, so `-p` takes a pattern):

```bash
cabal test seihou-core-test --enable-tests
cabal test seihou-cli-test --enable-tests --test-options='-p "application selection"'
```

Format and run the full repository checks before each commit:

```bash
just format
nix flake check
```

`nix flake check` runs `nix/check-record-conventions.sh` (every `data` record field carries
`!`, explicit deriving strategies, no record update syntax, no `OverloadedRecordDot`) and
`nix/check-cli-module-placement.sh` (new `seihou-cli` code belongs in `seihou-cli/src` unless
it needs `Options.Applicative`, `Data.FileEmbed`, `GitHash`, or `Paths_seihou_cli`). The
`UpdateOpts` and parser changes in Milestone 3 belong in `seihou-cli/src-exe` because they
touch `Options.Applicative`; everything else belongs in `seihou-cli/src` or `seihou-core/src`.

Commit at the end of each milestone. Every commit carries both trailers:

```text
feat(update): exempt additive-only shared paths from the ownership closure

ExecPlan: docs/plans/90-exempt-additive-patch-paths-from-the-shared-ownership-closure.md
Intention: intention_01m2n3x3jye499cw7mm0nmw0m8
```

Commit directly to `master`; this repository does not use feature branches.


## Validation and Acceptance

### Milestone 1

Unit tests, all in existing modules — no new test module and therefore no `.cabal` edit is
required:

- `seihou-core/test/Seihou/Manifest/TypesSpec.hs`: a `FileRecord` with `additiveOnly = True`
  round-trips through `manifestToJSON`/`manifestFromJSON`; the encoded JSON for
  `additiveOnly = False` contains no `additiveOnly` key; a hand-written record JSON with no
  `additiveOnly` key decodes to `False`.
- `seihou-core/test/Seihou/Engine/ExecuteSpec.hs`: `executePlan` on a single
  `PatchFileOp … AppendLineIfAbsent` records `additiveOnly = True`; on a `WriteFileOp` records
  `False`; on a `WriteFileOp` *and* a `PatchFileOp` for the same destination records `False`.
- `seihou-core/test/Seihou/Core/ApplicationSpec.hs`, `describe "attachApplication"`: the same
  weakening rule on the `seihou run` path — a prior owner with `additiveOnly = False` keeps the
  result `False` even when this run's own contribution is additive; agreement keeps `True`; a
  non-additive run weakens `True` to `False`; and with no surviving prior owner this run's own
  answer stands.
- `seihou-core/test/Seihou/Engine/UpdateTransactionSpec.hs`: the merge rule. Start from a
  manifest whose `.gitignore` record names owners `A` and `B` with `additiveOnly = True`,
  reconcile with a plan whose `applicationIds` is `{A}` and whose desired file names only `A`,
  and assert the written record still names `{A, B}`, still has `additiveOnly = True`, and
  keeps the prior `moduleName`. Then assert the fail-closed direction: the same partial plan
  against a prior record with `additiveOnly = False` writes `False`, not `True`.

### Milestone 2

Unit tests:

- `seihou-cli/test/Seihou/CLI/UpdateSpec.hs`, `describe "application selection"`: alongside
  the existing "rejects a partial selection that shares an owned path", add one that accepts
  the partial selection when the shared record has `additiveOnly = True`, and keep a case
  proving `additiveOnly = False` still refuses.
- `seihou-core/test/Seihou/Engine/ReconcileSpec.hs`: a plan for application `A` over a path
  owned by `{A, B}` with `additiveOnly = True` and an additive `PatchFileOp` succeeds; the
  same manifest with a `WriteFileOp` from the candidate fails with
  `SharedPathRequiresApplications`; a record with `additiveOnly = False` fails regardless of
  the operation.

End-to-end test in `seihou-cli/test/Seihou/CLI/UpdateE2ESpec.hs`, which drives the real
binary through `Seihou.CLI.SeihouBinary.seihouBinary`. Build a fixture modelled on
`prepareUpdateFixture` in `seihou-cli/test/Seihou/CLI/UpdateSpec.hs` (exported from that
module) with two installed modules and two recorded applications, each with a step like

```text
, steps = [{ strategy = "template", src = "ignore.tmpl", dest = ".gitignore", when = None Text, patch = Some "append-line-if-absent" }]
```

so the project's `.gitignore` starts as

```text
/dist-newstyle
/result
```

owned by both applications with `additiveOnly = True`. Then assert:

```text
$ seihou update alpha --json
"outcome":"applied"
```

and that `.gitignore` afterwards still contains `/result` (beta's line) as well as alpha's
new line, and that the manifest's `.gitignore` record still lists both application ids.
Add the negative case in the same spec: a second fixture where beta writes `.gitignore` with
`strategy = "template"` and no `patch`, where `seihou update alpha --json` exits non-zero
and the output contains `shared_path_requires_applications`.

Manual verification, useful for a reviewer and worth pasting into Outcomes & Retrospective:
in any project with a co-owned additive `.gitignore`, run `seihou update <one-module>
--dry-run` and confirm the plan renders instead of the refusal.

### Milestone 3

- `seihou-cli/test/Seihou/CLI/UpdateSpec.hs`: `selectApplications IncludeSharedOwners
  (NamedUpdateTargets ["one"])` over a manifest where `shared.txt` is owned by applications
  one and two (with `additiveOnly = False`) returns both applications in manifest order and
  one `SelectionExpandedForSharedPath` warning. A three-application fixed-point case: one and
  two share `a.txt`, two and three share `b.txt`, and selecting one returns all three.
  `RequireNamedOwners` over the same manifest still fails.
- `seihou-cli/test/Seihou/CLI/UpdateRenderSpec.hs`: the new warning renders as the prose line,
  not as a `show`n constructor, and the `SharedPathRequiresApplications` message mentions
  `--include-shared-owners`.
- End-to-end: `seihou update alpha --include-shared-owners --json` on the whole-file fixture
  from Milestone 2 now succeeds and updates both applications.

### Milestone 4

```bash
nix flake check
cabal run seihou -- help update
```

The help output must describe the additive exemption and the flag. `seihou update --help`
must list `--include-shared-owners`.


## Idempotence and Recovery

Every step here is an ordinary source edit under version control; `git diff` and
`git checkout --` are the undo. `cabal build`, `cabal test`, and `nix flake check` are
repeatable and side-effect-free.

The one durable artifact is `.seihou/manifest.json` in whatever project is used for manual
verification. The field this plan adds is written only by a successful `seihou run` or
`seihou update`, both of which already write the manifest transactionally
(`seihou-core/src/Seihou/Engine/UpdateTransaction.hs`), and the manifest is committed to git
in any real project, so reverting is a checkout. Use `--dry-run` for exploratory runs: it
renders the full plan while leaving project, manifest, baselines, and install cache
byte-identical, and there is an existing test asserting exactly that.

Two ordering hazards are worth restating, because getting them wrong is the failure mode this
plan is most concerned with. Do not land the gate relaxation (Milestone 2) before the manifest
merge rule (Milestone 1): between those two states, a targeted update of a co-owned additive
path silently removes the unselected owner from the manifest, and nothing on disk records that
it ever owned the path. And do not ship an error message naming `--include-shared-owners`
before the flag exists.

If a partially applied update is ever left behind during manual testing, the recorded state is
still the manifest plus `.seihou/baselines/`; `git checkout -- .seihou` restores both together,
which is the whole point of ADR 0001's "the manifest is a checked-in project artifact".


## Interfaces and Dependencies

No new library dependencies. Everything uses what the workspace already has: `containers`
(`Data.Map.Strict`, `Data.Set`), `aeson` for the manifest codec, `generic-lens` overloaded
labels for record access, `optparse-applicative` for the flag, and `tasty`/`hspec` for tests.

The types and signatures that must exist when the work is complete:

In `seihou-core/src/Seihou/Core/Types.hs` (landed in Milestone 1, exported from the module
header):

```haskell
data FileRecord = FileRecord
  { hash :: !SHA256,
    moduleName :: !ModuleName,
    strategy :: !Strategy,
    generatedAt :: !UTCTime,
    baseline :: !(Maybe BaselineRef),
    applicationIds :: !(Set ApplicationId),
    additiveOnly :: !Bool
  }
  deriving stock (Eq, Show, Generic)

isAdditivePatchOp :: PatchOp -> Bool
isAdditiveOperation :: Operation -> Bool
```

In `seihou-core/src/Seihou/Engine/Reconcile.hs`:

```haskell
data DesiredFile = DesiredFile
  { path :: !FilePath,
    generatedContent :: !Text,
    moduleName :: !ModuleName,
    strategy :: !Strategy,
    applicationIds :: !(Set ApplicationId),
    additiveOnly :: !Bool
  }
```

with `validateOwner` exempting a path only when the manifest record's `additiveOnly` is true
*and* every operation this run contributes to the path satisfies `isAdditiveOperation`.

In `seihou-cli/src/Seihou/CLI/Update/Selection.hs`:

```haskell
data SelectionPolicy
  = RequireNamedOwners
  | IncludeSharedOwners
  deriving stock (Eq, Show)

selectApplications ::
  SelectionPolicy ->
  UpdateSelection ->
  Manifest ->
  Either UpdateError (SelectedApplications, [UpdateWarning])
```

In `seihou-cli/src/Seihou/CLI/Update/Types.hs`: `UpdateRequest` gains
`includeSharedOwners :: !Bool`, and `UpdateWarning` gains
`SelectionExpandedForSharedPath FilePath ApplicationId`.

`Seihou.Core.Application.attachApplication` keeps its existing signature but gained the same
weakening rule as `prepareCandidateManifest`; see the Decision Log.

In `seihou-cli/src-exe/Seihou/CLI/Commands.hs`: `UpdateOpts` gains
`includeSharedOwners :: !Bool`, wired through `updateParser` and `makeUpdateOpts`.

Record conventions apply to every record touched here: strict fields on `data` records,
`deriving stock`, `Generic` in the derive list, access through `generic-lens` labels
(`record ^. #additiveOnly`, `record & #applicationIds .~ owners`), never record update syntax,
and `import Data.Generics.Labels ()` in each module that uses a `#label`. The convention is in
`docs/dev/architecture/overview.md` under "Record Conventions" and is enforced by
`nix/check-record-conventions.sh`.


## Revision notes

### 2026-09-16 — Milestone 1 implemented

Milestone 1 landed and the plan was corrected against the tree it was actually implemented
against.

- **Progress**: Milestone 1 checked off with what each step became; Milestone 2's checklist
  reworded from "restore" to "add", since there were no working-tree hunks to restore.
- **Surprises & Discoveries**: replaced the "working tree already contains partial work" entry
  with what was actually there (only documents, at the same HEAD); added the
  `attachApplication` fail-open gap with the pre-change code; added the `cabal test all`
  install-plan problem and the `--enable-tests` workaround.
- **Decision Log**: added the decision to apply the weakening rule to `attachApplication`, and
  the decision to set `additiveOnly = False` on the synthesized `KeepCurrent` records in
  `seihou run` / `seihou agent run`.
- **Context and Orientation**: "The state of the working tree at plan creation" became "What
  Milestone 1 has already landed", listing the committed state module by module and noting
  that `validateOwner` and `ensureOwnershipClosure` are deliberately still strict.
- **Plan of Work, Milestone 1**: the park step became "keep both gates strict"; the
  construction-site count corrected from "roughly twenty" to thirty plus the two
  `seihou-cli/src-exe` sites; `attachApplication` added as a fourth step; a Result block records
  the test counts and the revert check.
- **Validation and Acceptance, Milestone 1**: added the `ApplicationSpec` cases.
- **Concrete Steps** and **Context and Orientation**: every `cabal test all` became
  `cabal test all --enable-tests`.
- **Milestone 4**: the ADR must now also record that both write paths may only weaken the flag.
- **Outcomes & Retrospective**: Milestone 1 outcome recorded.

No scope changed. Milestones 2, 3, and 4 stand as written.

### 2026-09-16 — Milestones 2, 3, and 4 implemented; plan complete

All four milestones landed in one session. Recorded here rather than in three separate notes
because the changes to the plan were of one kind: each milestone's `Acceptance` gained a
`Result` block with the observed output, and the living-document sections were brought up to
date at the end.

- **Progress**: Milestones 2, 3, and 4 checked off with what each step became.
- **Plan of Work**: a `Result (2026-09-16)` block under each milestone's Acceptance, recording
  test counts, the fixture names, and the two places the implementation departed from the plan
  as written — `expandToSharedOwners` skipping additive-only paths, and `warningText` keeping
  a `show` fallback rather than becoming exhaustive.
- **Context and Orientation**: "Relevant ADRs" now lists ADR 0012 and what it records, in
  place of the note that no such ADR existed.
- **Interfaces and Dependencies**: noted that `attachApplication` kept its signature but
  gained the weakening rule.
- **Outcomes & Retrospective**: outcomes for Milestones 2-4, the comparison against the
  original Purpose, and the two lessons distilled into ADR 0012 — that this flag has two
  producers rather than one, and that the test for bumping a schema version is
  misinterpretation by an older reader, not novelty.

No scope changed and no milestone was dropped. Two additions beyond the plan's text, both
recorded in the Decision Log and Surprises & Discoveries at the time: the `attachApplication`
weakening rule (Milestone 1) and the additive-only skip in the selection expansion
(Milestone 3).
