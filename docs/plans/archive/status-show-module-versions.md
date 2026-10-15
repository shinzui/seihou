---
slug: status-show-module-versions
title: "Show Module Versions in Status Output"
kind: exec-plan
created_at: 2026-03-26T14:09:30Z
intention: "intention_01kjjgfv60e8y9qata1sfk8qrc"
---


# Show Module Versions in Status Output

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

After this change, running `seihou status` in a project will display the version of each applied module alongside its name and application date. Today the output looks like:

    Applied modules:
      claude-gitignore    (applied 2026-03-26)

After this change it will look like:

    Applied modules:
      claude-gitignore  v1.2.0  (applied 2026-03-26)

If a module has no version (the version field is `None Text` in its `module.dhall`), the version column is omitted for that row:

    Applied modules:
      my-module    (applied 2026-03-26)

This gives users immediate visibility into which version of each module was applied without having to inspect `.seihou-origin.json` or re-read the module source.


## Progress

- [x] M1-1: Add `moduleVersion :: Maybe Text` field to `AppliedModule` in `seihou-core/src/Seihou/Core/Types.hs`. (2026-03-26)
- [x] M1-2: Update `ToJSON` / `FromJSON` instances for `AppliedModule` in `seihou-core/src/Seihou/Manifest/Types.hs` (backward-compatible — missing key defaults to `Nothing`). (2026-03-26)
- [x] M1-3: Update `updateAllModules` in `seihou-cli/src/Seihou/CLI/Run.hs` to propagate `Module.version` into `AppliedModule.moduleVersion`. (2026-03-26)
- [x] M1-4: Build `cabal build all` — confirm compilation succeeds. (2026-03-26)
- [x] M1-5: Fix all `AppliedModule` construction sites in test files (TypesSpec, ManifestStoreSpec, RemoveSpec). (2026-03-26)
- [x] M2-1: Update `printModule` in `seihou-cli/src/Seihou/CLI/Status.hs` to display the version when present, colored green. (2026-03-26)
- [x] M2-2: Build succeeds. (2026-03-26)
- [x] M3-1: Add 3 new tests: versioned module round-trip, unversioned module round-trip, backward-compatible parsing of old manifests without version key. (2026-03-26)
- [x] M3-2: Run full test suite — `cabal test all` — all 653 tests pass. (2026-03-26)


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Store module version in the manifest's `AppliedModule` rather than reading it from `.seihou-origin.json` or re-parsing the module source at status time.
  Rationale: The manifest is the single source of truth for what was applied. Embedding the version there keeps `seihou status` fast (no extra I/O), self-contained, and correct even if the module source is later updated or the installed copy is removed. The `seihou list` command already reads origin metadata separately; status should rely only on the manifest.
  Date: 2026-03-26

- Decision: Use the field name `moduleVersion` in the Haskell type and JSON key `"version"` in the serialized manifest.
  Rationale: In Haskell, `version` would shadow the manifest's top-level `version :: Int` field in some contexts, so `moduleVersion` is clearer. In JSON, `"version"` is the natural key and lives inside each module object, so there is no ambiguity with the top-level manifest version.
  Date: 2026-03-26

- Decision: No manifest schema version bump.
  Rationale: The new field is optional with a default of `Nothing` / absent. Old manifests parse correctly because the `FromJSON` instance uses `.:?` (optional key). New manifests written by old seihou versions will simply lack the field, which new seihou reads as `Nothing`. This is fully backward- and forward-compatible without a version gate.
  Date: 2026-03-26


## Outcomes & Retrospective

All three milestones completed. The `moduleVersion` field was added to `AppliedModule`, propagated from `Module.version` during `seihou run`, serialized as an optional `"version"` JSON key (backward-compatible), and displayed in green in `seihou status` output. Three new tests added, all 653 tests pass. The change is fully backward-compatible — old manifests without the version key parse correctly as `Nothing`.


## Context and Orientation

Seihou is a project scaffolding tool. Users install modules (collections of file templates and configuration steps) and then run `seihou run <module>` to generate files. The tool records what it did in a manifest file at `.seihou/manifest.json`.

The `seihou status` command reads this manifest and displays: which modules have been applied, which files are tracked (with disk-vs-manifest hash comparison), and how many variables are resolved.

Key types and files involved:

**`AppliedModule`** — defined at `seihou-core/src/Seihou/Core/Types.hs:306-312`. Represents a module that was applied. Currently has four fields: `name`, `source`, `appliedAt`, `removal`. This type is what the manifest stores per module.

**`Module`** — defined at `seihou-core/src/Seihou/Core/Types.hs:207-219`. The full module definition loaded from `module.dhall`. Already has a `version :: Maybe Text` field that carries the module author's declared version.

**`Manifest`** — defined at `seihou-core/src/Seihou/Core/Types.hs:296-303`. The top-level manifest structure. Its `modules` field is `[AppliedModule]`.

**JSON instances** — defined at `seihou-core/src/Seihou/Manifest/Types.hs:66-90`. The `ToJSON` and `FromJSON` instances for `AppliedModule` control what goes into and comes out of the manifest JSON.

**`updateAllModules`** — defined at `seihou-cli/src/Seihou/CLI/Run.hs:369-383`. This function builds `AppliedModule` records from `(Module, FilePath)` pairs during `seihou run`. It currently does not transfer the module's version.

**`printModule`** — defined at `seihou-cli/src/Seihou/CLI/Status.hs:74-82`. Renders a single module line in `seihou status` output. Currently shows only name and application date.


## Plan of Work

The work has three milestones. Milestone 1 adds the data field and wires it through the run pipeline. Milestone 2 updates the status display. Milestone 3 adds test coverage.


### Milestone 1 — Add version to AppliedModule and propagate during run

This milestone adds a `moduleVersion :: Maybe Text` field to the `AppliedModule` type, updates its JSON serialization to include the version when present and tolerate its absence when parsing, and updates `updateAllModules` to copy the module's version into the applied module record.

**Step 1.1: Extend `AppliedModule`.**

In `seihou-core/src/Seihou/Core/Types.hs`, add `moduleVersion :: Maybe Text` to the `AppliedModule` record, after the `source` field:

    data AppliedModule = AppliedModule
      { name :: ModuleName,
        source :: FilePath,
        moduleVersion :: Maybe Text,
        appliedAt :: UTCTime,
        removal :: Maybe Removal
      }

**Step 1.2: Update `ToJSON AppliedModule`.**

In `seihou-core/src/Seihou/Manifest/Types.hs`, the `ToJSON` instance should include `"version"` only when the value is `Just`. Add to the optional-field list alongside `removal`:

    instance ToJSON AppliedModule where
      toJSON am =
        Aeson.object $
          [ "name" .= am.name.unModuleName,
            "source" .= am.source,
            "appliedAt" .= am.appliedAt
          ]
            ++ maybe [] (\v -> ["version" .= v]) am.moduleVersion
            ++ maybe [] (\r -> ["removal" .= removalToJSON r]) am.removal

**Step 1.3: Update `FromJSON AppliedModule`.**

In the same file, parse `"version"` as an optional key so old manifests without it decode as `Nothing`:

    AppliedModule
      <$> (ModuleName <$> o .: "name")
      <*> o .: "source"
      <*> o Aeson..:? "version"
      <*> o .: "appliedAt"
      <*> pure removal

**Step 1.4: Update `updateAllModules`.**

In `seihou-cli/src/Seihou/CLI/Run.hs`, the `AppliedModule` construction in `updateAllModules` must include the new field:

    new =
      [ AppliedModule
          { name = m.name,
            source = dir,
            moduleVersion = m.version,
            appliedAt = now,
            removal = m.removal
          }
      | (m, dir) <- modulesInOrder
      ]

**Step 1.5: Fix any other `AppliedModule` construction sites.**

Search the codebase for any other place that constructs an `AppliedModule` value (e.g., test fixtures, other commands). Each must include `moduleVersion`. Use grep for `AppliedModule` followed by an opening brace to find all construction sites.

At the end of Milestone 1, `cabal build all` must succeed. The manifest written by `seihou run` will now include module versions.


### Milestone 2 — Display version in status output

This milestone updates the `seihou status` output to show the version.

**Step 2.1: Update `printModule`.**

In `seihou-cli/src/Seihou/CLI/Status.hs`, modify `printModule` to insert the version string between the module name and the application date. When the version is `Just v`, display `v<version>`; when `Nothing`, show nothing extra. Use the `green` color function for the version text when color is enabled:

    printModule :: Bool -> AppliedModule -> IO ()
    printModule color am =
      let verText = maybe "" (\v -> "  " <> colorize (green) ("v" <> v)) am.moduleVersion
          colorize f t = if color then f t else t
      in TIO.putStrLn $
           "  "
             <> am.name.unModuleName
             <> verText
             <> "    (applied "
             <> T.pack (formatTime defaultTimeLocale "%Y-%m-%d" am.appliedAt)
             <> ")"

At the end of Milestone 2, running `seihou status` in a project with versioned modules will show the version in green. Build with `cabal build all` and verify manually.


### Milestone 3 — Test coverage

**Step 3.1: Update manifest JSON round-trip tests.**

Find existing manifest or `AppliedModule` JSON tests (likely in `seihou-core/test/`). Add cases for:

1. An `AppliedModule` with `moduleVersion = Just "1.0.0"` round-trips correctly, and the JSON contains `"version": "1.0.0"`.
2. An `AppliedModule` with `moduleVersion = Nothing` round-trips correctly, and the JSON does not contain a `"version"` key.
3. Parsing a JSON object without a `"version"` key yields `moduleVersion = Nothing` (backward compatibility).

At the end of Milestone 3, `cabal test all` passes with all existing and new tests.


## Concrete Steps

All commands are run from the repository root: `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`.

After each milestone, build:

    cabal build all

Expected: compilation succeeds with no errors.

After Milestone 2, verify manually:

    cabal run seihou -- status

Expected output includes a version next to at least one module name (if any installed modules declare a version in their `module.dhall`). If no installed modules have versions, the output looks identical to today — no version is shown for those modules.

After Milestone 3, run tests:

    cabal test all

Expected: all tests pass.


## Validation and Acceptance

1. **Versioned module**: Install or create a test module whose `module.dhall` has `version = Some "2.0.0"`. Run `seihou run <module>`, then `seihou status`. The status output must show `v2.0.0` next to the module name.

2. **Unversioned module**: Apply a module whose `module.dhall` has `version = None Text`. Run `seihou status`. That module's line must show only the name and date, with no extra spacing or empty version marker.

3. **Old manifest**: Take a `.seihou/manifest.json` written before this change (no `"version"` key in module entries). Run `seihou status`. It must parse correctly and display modules without versions.

4. **JSON round-trip**: The `AppliedModule` `ToJSON`/`FromJSON` instances round-trip correctly for both `Just` and `Nothing` version values.


## Idempotence and Recovery

All steps are safe to repeat. Editing the type and re-building is idempotent. The manifest format change is backward-compatible: old manifests parse correctly (missing `"version"` defaults to `Nothing`), and new manifests written with versions are simply ignored by older seihou versions (unknown keys are dropped by the existing `FromJSON` instance).

If a step fails mid-way, fix the compilation error and rebuild. No destructive state changes are involved.


## Interfaces and Dependencies

No new library dependencies are required. All changes use existing imports (`Data.Aeson`, `Data.Text`, `Data.Time`).

At the end of the work, the following types and functions will have changed:

In `seihou-core/src/Seihou/Core/Types.hs`:

    data AppliedModule = AppliedModule
      { name :: ModuleName,
        source :: FilePath,
        moduleVersion :: Maybe Text,
        appliedAt :: UTCTime,
        removal :: Maybe Removal
      }

In `seihou-core/src/Seihou/Manifest/Types.hs`:

    instance ToJSON AppliedModule  -- includes optional "version" key
    instance FromJSON AppliedModule  -- parses optional "version" key

In `seihou-cli/src/Seihou/CLI/Run.hs`:

    updateAllModules :: [AppliedModule] -> [(Module, FilePath)] -> UTCTime -> [AppliedModule]
    -- Now copies Module.version into AppliedModule.moduleVersion

In `seihou-cli/src/Seihou/CLI/Status.hs`:

    printModule :: Bool -> AppliedModule -> IO ()
    -- Now displays version when present
