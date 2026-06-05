---
id: 44
slug: make-manifest-writes-atomic
title: "Make manifest writes atomic"
kind: exec-plan
created_at: 2026-06-05T14:34:13Z
intention: "intention_01ktc3hwwneswaz13bvr1tb6f9"
master_plan: "docs/masterplans/5-first-public-release-readiness.md"
---

# Make manifest writes atomic

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

After this change, writing `.seihou/manifest.json` uses a real atomic replacement pattern: write complete JSON to a temporary file in the same directory, then rename it over the old manifest. A crash during the write should leave either the old manifest or the new manifest, not a partially written final file.

The current implementation says it is atomic but writes the final path directly after writing a `.tmp` file.


## Progress

- [x] Replace double-write manifest persistence with temp-write and rename. Completed 2026-06-05: `WriteManifest` now writes `manifestPath <> ".tmp"` and renames it to the final path.
- [x] Ensure the parent `.seihou` directory exists before writing. Completed 2026-06-05: `runManifestStore` creates the manifest parent directory when it is not `.` or empty.
- [x] Remove or clean up stale temp files after successful writes. Completed 2026-06-05: the temp path is consumed by `renamePath`; tests assert no `.tmp` remains.
- [x] Add IO-level tests or a focused smoke test for manifest write behavior. Completed 2026-06-05: added pure filesystem and real IO smoke coverage.
- [x] Run manifest-store tests and full core tests. Completed 2026-06-05: focused manifest-store tests, full core tests, and CLI tests passed.


## Surprises & Discoveries

- The filesystem effect already had `renamePath` and both interpreters implemented it, so no effect interface change was needed.
- As with EP-2 and EP-3, the focused test command needs `--pattern` rather than `--match` for this test runner.


## Decision Log

- Decision: Use same-directory temporary file plus rename for atomicity.
  Rationale: Atomic rename is the standard way to avoid torn final files on POSIX-style filesystems, and using the same directory avoids cross-device rename failures.
  Date: 2026-06-05

- Decision: Keep the existing deterministic `manifestPath <> ".tmp"` temp path.
  Rationale: The plan does not require solving concurrent writers. Overwriting the deterministic temp file before rename also recovers cleanly from stale temp files left by older versions.
  Date: 2026-06-05


## Outcomes & Retrospective

Implemented atomic manifest replacement in `Seihou.Effect.ManifestStoreInterp`. `WriteManifest` now ensures the manifest parent directory exists, writes complete JSON to a same-directory temp file, and calls `renamePath` to replace the final manifest. The old misleading comment and direct second write are gone.

Validation evidence:

```bash
cabal test seihou-core-test --test-options '--pattern "Seihou.Effect.ManifestStore"'
```

```text
All 10 tests passed (0.01s)
```

```bash
cabal test seihou-core-test
```

```text
All 862 tests passed (0.47s)
```

```bash
cabal test seihou-cli-test
```

```text
All 226 tests passed (11.25s)
```


## Context and Orientation

Manifest persistence lives in `seihou-core/src/Seihou/Effect/ManifestStoreInterp.hs`. The manifest store effect reads and writes `Manifest` values as JSON. The current `WriteManifest` branch computes JSON text, writes `manifestPath <> ".tmp"`, and then writes `manifestPath` directly. That final direct write can truncate or partially write the manifest if the process dies.

The filesystem effect in `seihou-core/src/Seihou/Effect/Filesystem.hs` already has read, write, copy, rename, and directory creation operations. The IO interpreter is `seihou-core/src/Seihou/Effect/FilesystemInterp.hs`.


## Plan of Work

Milestone 1 checks whether the existing `Filesystem` effect exposes enough operations. If it already has `RenamePath`, use it. If not, add an operation that maps to `System.Directory.renameFile` or `renamePath`, and update both IO and pure interpreters.

Milestone 2 updates `runManifestStore` in `ManifestStoreInterp.hs`. The implementation should create the manifest parent directory if missing, write the serialized JSON to a temporary file in that directory, then rename the temporary file over the final path. The comment must match the implementation. A suitable temp path is `manifestPath <> ".tmp"`, but if concurrent writers are a concern, use a unique suffix; this plan does not require solving concurrent writes beyond avoiding a torn final file.

Milestone 3 adds tests. Existing tests live in `seihou-core/test/Seihou/Effect/ManifestStoreSpec.hs`. Add coverage that a normal write produces the final manifest and does not leave `.tmp` behind in the real interpreter path if practical. If pure interpreter support is easier, test the pure rename semantics there and add one IO smoke assertion for the final file.


## Concrete Steps

Inspect the filesystem effect:

```bash
sed -n '1,120p' seihou-core/src/Seihou/Effect/Filesystem.hs
sed -n '1,120p' seihou-core/src/Seihou/Effect/FilesystemInterp.hs
sed -n '1,120p' seihou-core/src/Seihou/Effect/FilesystemPure.hs
```

Run focused tests:

```bash
cabal test seihou-core-test --test-options '--pattern "Seihou.Effect.ManifestStore"'
```

Then run:

```bash
cabal test seihou-core-test
```


## Validation and Acceptance

Acceptance requires:

- `ManifestStoreInterp` no longer writes the final manifest with a direct second `writeFileText`.
- The final manifest file is valid JSON after a normal write.
- A successful write does not leave `.seihou/manifest.json.tmp` in normal operation.
- Existing commands that write the manifest, such as `seihou run` and `seihou migrate`, still pass their tests.


## Idempotence and Recovery

The implementation is safe to retry. If a stale `.seihou/manifest.json.tmp` exists from older versions, the new writer may overwrite it before renaming. Do not delete user manifests during implementation. Tests should use temporary directories.


## Interfaces and Dependencies

This plan touches `Seihou.Effect.ManifestStoreInterp` and possibly the `Filesystem` effect modules. It does not change the JSON manifest schema or user-facing manifest format.
