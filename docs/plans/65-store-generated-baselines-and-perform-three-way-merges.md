---
id: 65
slug: store-generated-baselines-and-perform-three-way-merges
title: "Store generated baselines and perform three-way merges"
kind: exec-plan
created_at: 2026-07-19T16:27:05Z
intention: "intention_01kxxjwvf8e2e8r64feyk6r65b"
master_plan: "docs/masterplans/8-make-module-updates-seamless-and-conflict-aware.md"
---

# Store generated baselines and perform three-way merges

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

After this change, Seihou retains the exact generated ancestor needed to perform a real
three-way merge and exposes a tested merge engine that preserves non-overlapping user edits.
Every successfully generated text file receives a content-addressed baseline blob under
`.seihou/baselines/`, and its manifest `FileRecord.baseline` points to that blob.

The three inputs to a merge are: the prior generated baseline, the current project file,
and the newly generated content. If the user and the module changed different lines, the
result is automatic and clean. If they changed the same lines, the result carries labeled
diff3 markers and is classified as a conflict for later user resolution. Missing Git,
binary content, missing/corrupt baseline data, and unexpected driver errors never cause an
overwrite; they produce a conservative unavailable/conflict outcome.

This plan supplies the storage and merge primitives. It does not yet decide which project
files should be updated or deleted; that policy belongs to
`docs/plans/66-plan-conflict-aware-file-reconciliation-and-safe-orphan-handling.md`.


## Progress

- [x] (2026-07-19T17:52:41Z) M1: Add the `BaselineStore` effect, content-addressed real interpreter, and pure interpreter.
- [x] (2026-07-19T17:52:41Z) M1: Validate hashes on read and provide safe referenced-set pruning.
- [x] (2026-07-19T17:52:41Z) M1: Add baseline store unit and real-filesystem tests.
- [ ] M2: Add pure merge short circuits and the Git diff3 driver.
- [ ] M2: Cover clean, non-overlapping, overlapping, deletion, missing-Git, and binary cases.
- [ ] M3: Seed baseline blobs and manifest references during successful ordinary generation.
- [ ] M3: Preserve generated versus applied hash semantics for downstream reconciliation.
- [ ] M3: Run focused tests, all tests, formatting, and a real merge smoke demonstration.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- Observation: EP-64's JSON decoder wrapped any text in `BaselineRef`, even though a
  reference becomes a blob filename in this plan. Baseline decoding now requires exactly
  64 hexadecimal digits and normalizes uppercase input before any path is derived.
  Evidence: `Seihou.Manifest.Types` now rejects `"../manifest.json"`, while the focused
  storage and manifest tests pass as part of all 955 `seihou-core-test` examples.


## Decision Log

- Decision: Store baselines as content-addressed blobs rather than embedding full text in
  `manifest.json`.
  Rationale: Templates and copied files can be large or repeated. A SHA-256-addressed store
  deduplicates identical content, keeps the manifest reviewable, and lets integrity be
  verified whenever a blob is read.
  Date: 2026-07-19.

- Decision: Use the full existing SHA-256 digest as the blob filename under
  `.seihou/baselines/`.
  Rationale: The digest is already available through `Seihou.Manifest.Hash`, needs no new
  dependency, and makes blob paths derivable without an index. Truncated module-instance
  hashes are display identifiers and are not sufficient for content storage.
  Date: 2026-07-19.

- Decision: Use `git merge-file --stdout --diff3` as the merge backend after pure equality
  short circuits.
  Rationale: Installed-module updates already require Git, the local Git exposes this
  stable command, and Mori has no registered Haskell three-way merge implementation. The
  `--diff3` form includes the common ancestor in conflict markers, which is more useful than
  two-way markers for generated-file reconciliation.
  Date: 2026-07-19.

- Decision: Treat any non-success exit with marker-bearing stdout as a conflict, and any
  non-success without a usable merged body as driver unavailable.
  Rationale: `git merge-file` may encode a conflict count in its positive exit status; code
  must not assume only exit code 1 means conflict. Conversely, command-not-found and fatal
  errors must not turn empty stdout into an empty replacement file.
  Date: 2026-07-19.

- Decision: Keep the prior generated baseline distinct from the applied disk hash after a
  future automatic merge.
  Rationale: The next update needs the prior module output as its common ancestor. If the
  merged file becomes the baseline, prior user edits are reclassified as generated and can
  disappear later.
  Date: 2026-07-19.

- Decision: For an ordinary pre-update `seihou run`, seed a patch target's first baseline
  from the complete post-patch disk content.
  Rationale: Patch-only operations do not have a complete generated file before being
  applied. The first observed post-patch file is the only truthful ancestor available; EP-66
  will apply later patch sequences to that stored ancestor before merging with new disk
  edits.
  Date: 2026-07-19.


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

(To be filled during and after implementation.)


## Context and Orientation

This plan has a hard dependency on
`docs/plans/64-record-reproducible-applied-compositions-and-update-state.md`. That plan
defines `BaselineRef` and adds `FileRecord.baseline :: Maybe BaselineRef`. Confirm EP-64 is
marked Complete in the parent MasterPlan before implementation and use its checked-in types
instead of recreating them.

A **content-addressed store** names stored bytes by a digest of those same bytes. Writing
the same content twice produces the same path. Reading must recompute the digest and reject
tampered content. Seihou already computes text SHA-256 values through
`seihou-core/src/Seihou/Manifest/Hash.hs`.

Filesystem access is abstracted by `Seihou.Effect.Filesystem`. The real interpreter lives
at `seihou-core/src/Seihou/Effect/FilesystemInterp.hs`; the pure in-memory interpreter and
`PureFS` test model live at `seihou-core/src/Seihou/Effect/FilesystemPure.hs`. The manifest
store follows the desired effect pattern in `Seihou.Effect.ManifestStore`,
`ManifestStoreInterp`, and `ManifestStorePure`.

Generation operations are defined in `seihou-core/src/Seihou/Core/Types.hs` and executed by
`seihou-core/src/Seihou/Engine/Execute.hs`. `executePlan` returns a map of `FileRecord`s,
but patch operations obtain their final full content only after reading and updating the
disk file. `seihou-cli/src-exe/Seihou/CLI/Run.hs` writes the returned records into the
manifest. This plan may add a core helper that reads each successfully applied path, writes
its baseline blob, and enriches its file record before the manifest is constructed; do not
put blob logic directly into the executable handler.

The repository already depends on `process` and shells out to Git for installs, upgrades,
migrations, and commit integration. `seihou-core/src/Seihou/Effect/Process.hs` has a simple
`runProcess` effect but does not support stdin. `git merge-file` operates on three files, so
the real driver can use `withSystemTempDirectory`, write the three inputs, and invoke the
existing process machinery or `readProcessWithExitCode`. Keep the public merge API in
`seihou-core`; the implementation choice must remain replaceable and directly testable.

Register new exposed modules in `seihou-core/seihou-core.cabal` and new specs in that file
and `seihou-core/test/Main.hs`.


## Plan of Work

### Milestone 1: add baseline storage

Create `seihou-core/src/Seihou/Effect/BaselineStore.hs` with the dynamic effect and these
operations:

```haskell
data BaselineError
  = BaselineMissing BaselineRef
  | BaselineCorrupt BaselineRef SHA256
  | BaselineStoreFailure Text

putBaseline :: BaselineStore :> es => Text -> Eff es BaselineRef
readBaseline :: BaselineStore :> es => BaselineRef -> Eff es (Either BaselineError Text)
pruneBaselines :: BaselineStore :> es => Set BaselineRef -> Eff es [BaselineRef]
```

Create `Seihou.Effect.BaselineStoreInterp` and
`Seihou.Effect.BaselineStorePure`. The real interpreter takes the baseline directory, which
callers pass as `.seihou/baselines`. `putBaseline` computes the hash, creates the directory,
writes to `<digest>.tmp`, and renames to `<digest>` unless the valid final blob already
exists. `readBaseline` validates that the recomputed hash matches the requested reference.
Never concatenate unchecked user text into a path; `BaselineRef` contains a digest produced
by the decoder or hash helper, and the decoder must reject non-hex or wrong-length values.

`pruneBaselines` lists only regular files whose names parse as baseline references, removes
unreferenced valid blobs, ignores unrelated files, and returns the references it removed.
Pruning is a maintenance action after a durable manifest write; it is not part of
`putBaseline`.

Add `seihou-core/test/Seihou/Effect/BaselineStoreSpec.hs` covering deduplication, round-trip,
tamper detection, missing refs, temp-file cleanup, pure behavior, and pruning. At the end of
this milestone, storage works independently of generation.

### Milestone 2: implement three-way text merge

Create `seihou-core/src/Seihou/Engine/ThreeWayMerge.hs` with this public contract:

```haskell
data MergeOutcome
  = MergeClean Text
  | MergeConflicted Text
  | MergeUnavailable Text
  deriving stock (Eq, Show)

threeWayMerge :: Text -> Text -> Text -> IO MergeOutcome
-- arguments: generated baseline, current disk content, new generated content
```

Before invoking Git, handle three safe identities directly: current equals baseline means
take new generated; new generated equals baseline means preserve current; current equals new
generated means return either one. Reject any input containing NUL as unavailable with a
binary-content explanation.

For the remaining case, create three files in a system temporary directory and invoke:

```bash
git merge-file --stdout --diff3 \
  -L current -L generated-base -L new-generated \
  CURRENT BASE NEW
```

Pass files in exactly that order: Git treats the first as the user's side, the second as the
common ancestor, and the third as the module's new side. `ExitSuccess` returns
`MergeClean stdout`. A non-success result whose stdout contains a complete conflict-marker
body returns `MergeConflicted stdout`, regardless of the numeric conflict count. A missing
executable, exception, empty output, or fatal stderr without usable markers returns
`MergeUnavailable` with a concise reason. Do not write the result to the project here.

Add `seihou-core/test/Seihou/Engine/ThreeWayMergeSpec.hs`. Pure short-circuit tests must not
need Git. Real-driver tests should first check that `git --version` succeeds and otherwise
mark only the driver-specific examples pending; CI and the normal development shell are
expected to include Git because other Seihou tests and workflows require it. Cover changes
on separate lines, overlapping replacements with the three labels, user-only deletion,
generated-only deletion, missing trailing newline, empty files, Unicode, and NUL rejection.

### Milestone 3: seed baselines during ordinary generation

Add a core helper, either to `Seihou.Engine.Execute` or a focused new
`Seihou.Engine.Baseline` module:

```haskell
recordGeneratedBaselines
  :: (Filesystem :> es, BaselineStore :> es)
  => FilePath
  -> Map FilePath FileRecord
  -> Eff es (Either BaselineError (Map FilePath FileRecord))
```

For each record returned by successful execution, read the full path now on disk, call
`putBaseline`, set `FileRecord.baseline`, and recompute `FileRecord.hash` from the same disk
content. Recomputing prevents a patch target or future execution change from leaving the
applied hash inconsistent with the captured baseline. Do not alter application ownership
added by EP-64.

Wire the helper into both deterministic baseline writers:
`seihou-cli/src-exe/Seihou/CLI/Run.hs` and the baseline portion of
`seihou-cli/src-exe/Seihou/CLI/AgentRun.hs`. Blueprints themselves remain out of scope, but
their deterministic baseline modules must receive the same file records as `seihou run`.
If baseline persistence fails, do not publish a manifest that claims a baseline exists;
return an error and leave the prior atomic manifest intact.

After the manifest is durably written, compute every referenced `BaselineRef` across the
manifest and call `pruneBaselines`. Treat prune failure as a warning, not a failed generation,
because all required blobs and the manifest are already durable.


## Concrete Steps

Run from the repository root:

```bash
cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
git --version
cabal test seihou-core-test
cabal test all
nix fmt
git diff --check
```

Add a focused temporary smoke script or Hspec example that calls `threeWayMerge` with:

```text
base:    alpha / shared / omega
current: alpha / user   / shared / omega
new:     alpha / shared / module / omega
```

The result must be clean and contain both `user` and `module`. A second example that changes
`shared` differently on both sides must return `MergeConflicted` containing labels
`current`, `generated-base`, and `new-generated`.

Every implementation commit must include:

```text
MasterPlan: docs/masterplans/8-make-module-updates-seamless-and-conflict-aware.md
ExecPlan: docs/plans/65-store-generated-baselines-and-perform-three-way-merges.md
Intention: intention_01kxxjwvf8e2e8r64feyk6r65b
```


## Validation and Acceptance

Acceptance requires all of these observable behaviors:

- writing identical text twice yields one valid blob and the same `BaselineRef`;
- a modified blob is detected as corrupt rather than returned;
- pruning deletes only valid unreferenced baseline blobs and never unrelated files;
- non-overlapping user and generated changes return `MergeClean` containing both changes;
- overlapping edits return `MergeConflicted` with the common ancestor visible in labeled
  diff3 markers;
- missing Git, fatal driver failure, or binary content returns `MergeUnavailable` and never
  returns empty replacement content;
- after an ordinary module run in a disposable project, every newly written `FileRecord`
  has a baseline reference, the referenced file exists under `.seihou/baselines/`, its hash
  matches its content, and the record's applied hash matches the project file;
- version-3 manifests with no baseline remain usable; no eager backfill rewrites an old
  manifest merely by reading it;
- `cabal test all` passes and formatting is clean.


## Idempotence and Recovery

Content-addressed writes are idempotent: rerunning `putBaseline` with the same text validates
and reuses the same path. A `.tmp` file from an interrupted write is never treated as a
baseline and may be overwritten on retry. Do not prune before the new manifest is durable;
doing so could remove the only ancestor referenced by the previous valid manifest.

Three-way merge is read-only with respect to the project. Its temporary directory is cleaned
by the temporary-file library. If Git fails, callers receive `MergeUnavailable`; they may
ask the user for a whole-file resolution but must not retry by overwriting.

An ordinary run may have written project files before baseline persistence fails. The old
manifest remains intact. After fixing disk space or permissions, re-run the same module; the
existing diff/conflict behavior protects changed files. Manual smoke tests must use a
disposable project directory.


## Interfaces and Dependencies

Hard dependency: EP-64 must be Complete. Use its exact `BaselineRef` and `FileRecord` fields.

No new Haskell dependency is authorized by this plan. `mori registry search Diff`, `diff3`,
`patience`, and `merge` produced no registered Haskell implementation. Use existing
`cryptohash-sha256`, `directory`, `filepath`, `temporary`, `process`, `text`, `containers`,
and the repository's effects. If implementation discovers that `git merge-file` semantics
are insufficient, stop and update the parent MasterPlan before adding a package or writing a
new merge algorithm.

EP-66 consumes `readBaseline`, `putBaseline`, `MergeOutcome`, and `threeWayMerge`. EP-68
uses `pruneBaselines` only after it publishes a successful update manifest. The argument
ordering of `threeWayMerge`—baseline, current, new generated—is a coordination contract and
must be documented at the definition site to prevent accidental side reversal.
