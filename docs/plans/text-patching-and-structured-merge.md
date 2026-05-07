---
slug: text-patching-and-structured-merge
title: "Add Text Patching and Structured Merge"
kind: exec-plan
created_at: 2026-03-03T01:25:50Z
---


# Add Text Patching and Structured Merge

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

When multiple seihou modules target the same file, the system currently uses last-writer-wins:
the later module's content completely replaces the earlier one's. This works for disjoint files
but breaks down when modules need to _contribute_ to a shared file — e.g., a base module
creates a `cabal.project` file and a nix module appends extra configuration to it, or two
modules each add their own section to a shared `README.md`.

After this change, module authors can declare **patch operations** on steps. A step with
`patch = Some "append-section"` does not overwrite the existing file; instead it appends its
content as a marked section. The composition engine knows how to merge these contributions
intelligently:

- **Text files** (Template/DhallText/Copy): append, prepend, or replace marked sections with
  comment-delimited boundaries (`# --- seihou:module-name ---`).
- **Structured files** (Structured strategy): deep-merge Dhall records before serialization, so
  two modules contributing to the same `.json` or `.yaml` get their keys merged rather than
  one clobbering the other.

The user-visible behavior: running `seihou run` with modules that share output files produces
correctly merged content instead of silent overwrites.


## Progress

- [x] M1-1: Add `PatchOp` type to `Seihou.Core.Types` (2026-03-02)
- [x] M1-2: Add `stepPatch` field to `Step` type (2026-03-02)
- [x] M1-3: Update `stepDecoder` in `Seihou.Dhall.Eval` to decode `patch` field (2026-03-02)
- [x] M1-4: Force `stepPatch` thunk in `evalModuleFromFile` (2026-03-02)
- [x] M1-5: Update all existing test fixtures to include `patch = None Text` in steps (2026-03-02)
- [x] M1-6: Update `ModuleSpec`, `PlanSpec`, `GenerationSpec` — add `stepPatch = Nothing` to all positional `Step` constructions (2026-03-02)
- [x] M1-7: Add unit tests for `PatchOp` type and decoder (2026-03-02)
- [x] M1-8: Build and run all tests — 323 tests pass, `nix fmt` clean (2026-03-02)
- [x] M2-1: Create `Seihou.Engine.Section` with `SectionMarker`, `renderSectionOpen`/`Close`, `wrapInSection` (2026-03-02)
- [x] M2-2: Implement `applyTextPatch` for `AppendFile`, `PrependFile`, `AppendSection` (2026-03-02)
- [x] M2-3: Add 16 unit tests in `SectionSpec.hs` (2026-03-02)
- [x] M2-4: Build and run all tests — 339 tests pass, `nix fmt` clean (2026-03-02)
- [x] M3-1: Add `PatchFileOp` constructor to `Operation` (2026-03-02)
- [x] M3-2: Add `compilePatchStep` to `Seihou.Engine.Plan` (2026-03-02)
- [x] M3-3: Update `compileStep` dispatch to route `patch` steps to `compilePatchStep` (2026-03-02)
- [x] M3-4: Update `executeOp` in `Seihou.Engine.Execute` to handle `PatchFileOp` (2026-03-02)
- [x] M3-5: Update `dryRunPlan` for `PatchFileOp` (2026-03-02)
- [x] M3-6: Update pattern matches across the codebase for new Operation constructor (2026-03-02)
- [x] M3-7: Add unit tests for `compilePatchStep` and `PatchFileOp` execution (2026-03-02)
- [x] M3-8: Build and run all tests — 348 tests pass, `nix fmt` clean (2026-03-02)
- [x] M4-1: Implement `mergeStructuredContent` and `deepMergeJSON` in `Seihou.Composition.Plan` (2026-03-02)
- [x] M4-2: Update `mergeOperations` to dispatch to `mergeStructuredContent` for Structured-strategy WriteFileOps (2026-03-02)
- [x] M4-3: Add `ContentMerged` warning to `CompositionWarning` and `printWarning` in CLI (2026-03-02)
- [x] M4-4: Update `mergeOperations` to apply `PatchFileOp` to existing `WriteFileOp` content (2026-03-02)
- [x] M4-5: Add 6 composition tests for text patching merge (2026-03-02)
- [x] M4-6: Add 6 composition tests for structured merge (2026-03-02)
- [x] M4-7: Build and run all tests — 360 tests pass, `nix fmt` clean (2026-03-02)
- [x] M5-1: Create test fixture `haskell-shared-readme/` with patching steps (2026-03-02)
- [x] M5-2: Create test fixtures `structured-merge-a/` and `structured-merge-b/` for JSON merge (2026-03-02)
- [x] M5-3: Add integration test for text patching (haskell-base + haskell-shared-readme) (2026-03-02)
- [x] M5-4: Add integration test for structured merge (structured-merge-a + structured-merge-b) (2026-03-02)
- [x] M5-5: Final build, all 362 tests pass, `nix fmt` clean (2026-03-02)


## Surprises & Discoveries

- `evaluate (stepPatch s)` only forces `Maybe PatchOp` to WHNF (`Just <thunk>`), not deep enough to trigger the `error` inside `parsePatchOp`. Fixed with `mapM_ evaluate (stepPatch s)` which forces the inner value when `Just`. Same pattern as `stepWhen` but `stepWhen`'s thunk was already strict due to `parseWhen` being called eagerly.
- `PatchOp(..)` was missing from the `Types.hs` export list. The `Step(..)` export re-exports `stepPatch` accessor but not the `PatchOp` type itself.
- `bad-vartype/module.dhall` has an empty steps list with an explicit type annotation `List { strategy : Text, src : Text, dest : Text, when : Optional Text }` that also needed `patch : Optional Text` added.


## Decision Log

- Decision: PatchOp is a simple enum, not a GADT — `AppendFile | PrependFile | AppendSection | PrependSection | ReplaceSection`.
  Rationale: Keeps Dhall schema simple (a single `patch` string field). The section marker and content come from the step's source file and module name, not from PatchOp itself.
  Date: 2026-03-02

- Decision: Section markers use Haskell-style comments `-- --- seihou:module-name ---` for now, with strategy for future language-aware markers.
  Rationale: The v1 design doc specifies `# --- seihou:module-name ---` but this only works for shell/YAML/Python. For Haskell-centric dogfooding, `--` comments are more appropriate. We use a configurable comment prefix that defaults to `#`.
  Date: 2026-03-02

- Decision: Structured merge happens at the Dhall AST level (re-evaluate merged records) rather than at the JSON level.
  Rationale: Dhall's `//` (right-biased merge) and `/\` (recursive merge) are well-defined and handle nested records correctly. Merging at JSON level would require custom deep-merge logic.
  Date: 2026-03-02

- Decision: `PatchFileOp` is a new Operation constructor, separate from `WriteFileOp`.
  Rationale: `WriteFileOp` semantics are "create/overwrite a file." A patch modifies existing content. Keeping them distinct avoids ambiguity in `mergeOperations` and `executePlan`. During composition, `mergeOperations` can recognize when a `PatchFileOp` targets the same file as a `WriteFileOp` from an earlier module, and apply the patch inline.
  Date: 2026-03-02

- Decision: Defer `ReplaceSection` to a follow-up — implement `AppendFile`, `PrependFile`, and `AppendSection` first.
  Rationale: AppendFile/PrependFile are the most common use cases and don't require section marker parsing in the target file. AppendSection needs section marker generation but not replacement-in-place. ReplaceSection needs both parsing and replacement, adding complexity. Ship the simpler cases first.
  Date: 2026-03-02

- Decision: Structured merge uses JSON-level deep merge (aeson) instead of Dhall AST re-evaluation.
  Rationale: By the time `mergeOperations` sees `WriteFileOp` content, the Dhall has already been evaluated and serialized to JSON/YAML. Re-evaluating Dhall would require storing the original source alongside the serialized output or making `mergeOperations` IO. JSON-level `deepMergeJSON` is pure, uses existing aeson/yaml dependencies, and handles the common cases (disjoint keys, nested object merge, right-biased scalars) correctly.
  Date: 2026-03-02


## Outcomes & Retrospective

All 5 milestones completed. 362 tests pass (up from 321 at start), `nix fmt` clean.

**What was delivered:**
- `PatchOp` type (`AppendFile | PrependFile | AppendSection`) and `stepPatch` field on `Step`
- `Seihou.Engine.Section` module with section marker generation and `applyTextPatch`
- `PatchFileOp` Operation constructor, `compilePatchStep`, execution in `executeOp`
- Intelligent composition merge: `PatchFileOp` applies patches inline to existing `WriteFileOp` content with `ContentMerged` warnings
- Structured merge: two Structured-strategy `WriteFileOp`s targeting the same JSON/YAML get deep-merged via `deepMergeJSON`
- 3 new test fixtures (`haskell-shared-readme`, `structured-merge-a`, `structured-merge-b`)
- 41 new tests across unit, composition, and integration layers

**Key decision change:** Structured merge uses JSON-level deep merge (aeson `KeyMap.unionWith`) instead of Dhall AST re-evaluation. By the time `mergeOperations` sees operations, content is already serialized. JSON merge is pure, simple, and handles the common cases. Dhall-level merge could be added later if needed for more complex scenarios.

**No regressions:** All 321 pre-existing tests continue to pass. The `patch = None Text` fixture addition is a no-op for existing behavior.


## Context and Orientation

### Repository Layout

```
seihou/
├── seihou-core/                        # Library package
│   ├── src/Seihou/
│   │   ├── Core/Types.hs              # All domain types (Step, Operation, etc.)
│   │   ├── Core/Module.hs             # Module discovery, validation, loading
│   │   ├── Composition/
│   │   │   ├── Graph.hs               # Topological sort for module dependencies
│   │   │   ├── Resolve.hs             # Variable export/import flow
│   │   │   └── Plan.hs               # mergeOperations (last-writer-wins)
│   │   ├── Engine/
│   │   │   ├── Plan.hs               # compilePlan, per-strategy compilation
│   │   │   ├── Execute.hs            # executePlan, dryRunPlan
│   │   │   ├── Template.hs           # Placeholder {{var}} rendering
│   │   │   ├── DhallJSON.hs          # Dhall Expr → aeson Value
│   │   │   └── Diff.hs               # Three-state diff for incrementality
│   │   └── Dhall/
│   │       └── Eval.hs               # Dhall decoders (moduleDecoder, stepDecoder)
│   ├── test/
│   │   ├── fixtures/                  # Test module directories
│   │   │   ├── haskell-base/          # Base Haskell module (5 steps)
│   │   │   ├── structured-basic/      # Structured strategy test
│   │   │   └── ...
│   │   └── Seihou/
│   │       ├── Composition/PlanSpec.hs    # mergeOperations tests
│   │       ├── Engine/PlanSpec.hs         # compilePlan tests
│   │       └── Engine/ExecuteSpec.hs      # executePlan tests
│   └── seihou-core.cabal
└── seihou-cli/                        # CLI executable package
```

### Key Types (in `seihou-core/src/Seihou/Core/Types.hs`)

**Step** (line 124): A generation step within a module. Currently has 4 fields: `stepStrategy`, `stepSrc`, `stepDest`, `stepWhen`. This plan adds `stepPatch :: Maybe PatchOp`.

**Operation** (line 145): Filesystem operations produced by the engine. Currently has 4 constructors: `WriteFileOp`, `CreateDirOp`, `CopyFileOp`, `RunCommandOp`. This plan adds `PatchFileOp`.

**Strategy** (line 117): `Copy | Template | DhallText | Structured`.

**CompositionWarning** (line 303): Currently only `FileOverwritten FilePath ModuleName ModuleName`. This plan adds `ContentMerged`.

### Current Composition Merge Logic (`seihou-core/src/Seihou/Composition/Plan.hs`)

The `mergeOperations` function (line 41) iterates through all modules' operations in topological order. For each file-targeting op (`WriteFileOp`/`CopyFileOp`), if the destination already exists in the `fileOwner` map, the previous operation is removed and a `FileOverwritten` warning is recorded. This is the logic we need to enhance: instead of always overwriting, check whether the new op is a `PatchFileOp` and if so, apply the patch to the existing content.

### Dhall Module Schema

Steps in `module.dhall` currently look like:
```dhall
{ strategy = "template"
, src = "README.md.tpl"
, dest = "README.md"
, when = None Text
}
```
We will add an optional `patch` field:
```dhall
{ strategy = "template"
, src = "section.md.tpl"
, dest = "README.md"
, patch = Some "append-section"
, when = None Text
}
```

### Design Doc References

- `docs/dev/design/proposed/composition-and-layering.md` — Specifies PatchOp, section markers, and structured merge semantics.
- `docs/dev/design/proposed/generation-strategies.md` — Per-strategy composition behavior rules.

### Term Definitions

- **Patch operation**: A step that modifies an existing file rather than creating/overwriting it. The step's source file provides the content to insert, and the `patch` field specifies how (append, prepend, etc.).
- **Section marker**: A comment line that delimits content contributed by a specific module. Format: `{comment-prefix} --- seihou:{module-name} ---` (opening) and `{comment-prefix} --- /seihou:{module-name} ---` (closing).
- **Structured merge**: When two Structured-strategy steps target the same output file, their Dhall records are merged using Dhall's `//` operator before serialization, instead of one overwriting the other.
- **Last-writer-wins**: The current behavior where the later module's content completely replaces the earlier module's for the same destination path.


## Plan of Work

### Milestone 1: Type Foundation — PatchOp and Step Extension

**Scope**: Define the `PatchOp` type, extend `Step` with an optional patch field, update the Dhall decoder, and update all existing fixtures. At the end, the system compiles and all existing tests pass, but patching has no runtime effect yet.

**Acceptance**: `cabal test` passes with 321+ tests. All existing module.dhall fixtures include the new `patch` field. The `PatchOp` type exists and can be decoded from Dhall strings.

#### M1-1: Add PatchOp type to Types.hs

In `seihou-core/src/Seihou/Core/Types.hs`, after the `Strategy` type (line 121), add:

```haskell
-- | Patch operations for modifying existing files during composition.
-- A step with a 'PatchOp' contributes content to a file that another module
-- creates, rather than overwriting it.
data PatchOp
  = AppendFile
  | PrependFile
  | AppendSection
  deriving stock (Eq, Show, Generic)
```

#### M1-2: Add stepPatch to Step

In `seihou-core/src/Seihou/Core/Types.hs`, modify the `Step` type (line 124) to add `stepPatch`:

```haskell
data Step = Step
  { stepStrategy :: Strategy,
    stepSrc :: FilePath,
    stepDest :: Text,
    stepWhen :: Maybe Expr,
    stepPatch :: Maybe PatchOp
  }
  deriving stock (Eq, Show, Generic)
```

#### M1-3: Update stepDecoder in Eval.hs

In `seihou-core/src/Seihou/Dhall/Eval.hs`, add a `patchOpDecoder` and update `stepDecoder` (line 183):

```haskell
patchOpDecoder :: Decoder PatchOp
patchOpDecoder = parsePatchOp <$> strictText
  where
    parsePatchOp :: Text -> PatchOp
    parsePatchOp t = case t of
      "append-file" -> AppendFile
      "prepend-file" -> PrependFile
      "append-section" -> AppendSection
      other -> error ("Unknown patch operation \"" <> T.unpack other
                      <> "\"; expected one of: append-file, prepend-file, append-section")
```

Update `stepDecoder` to decode the new field:

```haskell
stepDecoder :: Decoder Step
stepDecoder =
  record
    ( mkStep
        <$> field "strategy" strategyDecoder
        <*> field "src" string
        <*> field "dest" strictText
        <*> field "when" (maybe strictText)
        <*> field "patch" (maybe strictText)
    )
  where
    mkStep strat src dest whenText patchText =
      Step
        { stepStrategy = strat,
          stepSrc = src,
          stepDest = dest,
          stepWhen = parseWhen whenText,
          stepPatch = fmap parsePatchOp patchText
        }
    parsePatchOp "append-file" = AppendFile
    parsePatchOp "prepend-file" = PrependFile
    parsePatchOp "append-section" = AppendSection
    parsePatchOp other = error ("Unknown patch op: " <> T.unpack other)
```

#### M1-4: Force stepPatch thunk in evalModuleFromFile

In `seihou-core/src/Seihou/Dhall/Eval.hs`, line 54, add `stepPatch` to the force expression:

```haskell
mapM_ (\s -> evaluate (stepStrategy s) >> evaluate (stepWhen s) >> evaluate (stepPatch s)) (moduleSteps m)
```

#### M1-5: Update all existing test fixtures

Every `module.dhall` fixture must add `, patch = None Text` to each step record. The affected fixtures are:

- `test/fixtures/haskell-base/module.dhall` — 5 steps
- `test/fixtures/haskell-with-nix/module.dhall` — 1 step
- `test/fixtures/nix-base/module.dhall`
- `test/fixtures/nix-flake/module.dhall`
- `test/fixtures/structured-basic/module.dhall` — 2 steps
- `test/fixtures/invalid-module/module.dhall` (if it has steps)
- `test/fixtures/bad-strategy/module.dhall` (if it has steps)

Each step changes from:
```dhall
{ strategy = "template", src = "README.md.tpl", dest = "README.md", when = None Text }
```
to:
```dhall
{ strategy = "template", src = "README.md.tpl", dest = "README.md", when = None Text, patch = None Text }
```

#### M1-6: Update ModuleSpec validation and other test helpers

Check all test files that construct `Step` values directly (not via Dhall). They need the new `stepPatch = Nothing` field. Key files to check:

- `test/Seihou/Core/ModuleSpec.hs`
- `test/Seihou/Core/TypesSpec.hs`
- `test/Seihou/Dhall/EvalSpec.hs`
- `test/Seihou/Engine/PlanSpec.hs`
- `test/Seihou/Integration/GenerationSpec.hs`

#### M1-7: Add PatchOp decoder tests

In `test/Seihou/Dhall/EvalSpec.hs`, add tests for `patchOpDecoder`:

- `"append-file"` decodes to `AppendFile`
- `"prepend-file"` decodes to `PrependFile`
- `"append-section"` decodes to `AppendSection`
- Invalid string produces an error
- `None Text` decodes to `Nothing`

#### M1-8: Build and test

```
cd seihou
cabal test all
nix fmt
```

All 321+ tests must pass.

---

### Milestone 2: Section Marker Engine

**Scope**: Implement the section marker parsing and text patching logic in a new pure module `Seihou.Engine.Section`. This module has no IO — it operates on `Text` values. At the end, section markers can be parsed and generated, and `applyTextPatch` can append content to text files.

**Acceptance**: New module with unit tests. `cabal test` passes. The module is not yet wired into the compilation pipeline.

#### M2-1: Create Seihou.Engine.Section module

Create `seihou-core/src/Seihou/Engine/Section.hs` with:

```haskell
module Seihou.Engine.Section
  ( SectionMarker (..),
    renderSectionOpen,
    renderSectionClose,
    wrapInSection,
    applyTextPatch,
  )
where

-- | A section marker identifies content contributed by a module.
data SectionMarker = SectionMarker
  { sectionPrefix :: Text,     -- Comment prefix, e.g., "#" or "--"
    sectionModule :: ModuleName
  }

-- | Render an opening section marker line.
-- Result: "# --- seihou:haskell-base ---\n"
renderSectionOpen :: SectionMarker -> Text

-- | Render a closing section marker line.
-- Result: "# --- /seihou:haskell-base ---\n"
renderSectionClose :: SectionMarker -> Text

-- | Wrap content in section markers.
wrapInSection :: SectionMarker -> Text -> Text

-- | Apply a patch operation to existing content.
applyTextPatch :: PatchOp -> ModuleName -> Text -> Text -> Text -> Either Text Text
-- Args: patchOp, moduleName, commentPrefix, existingContent, newContent
-- Returns: merged content or error
```

The `applyTextPatch` function handles each PatchOp:
- `AppendFile`: Append `newContent` to end of `existingContent` (no section markers).
- `PrependFile`: Prepend `newContent` before `existingContent` (no section markers).
- `AppendSection`: Wrap `newContent` in section markers, append after `existingContent`.

Register in `seihou-core.cabal` under `exposed-modules`.

#### M2-2: Implement the functions

The section marker format is: `{prefix} --- seihou:{module-name} ---` (opening) and `{prefix} --- /seihou:{module-name} ---` (closing).

`wrapInSection` produces:
```
# --- seihou:nix-flake ---
<content>
# --- /seihou:nix-flake ---
```

`applyTextPatch AppendSection` produces:
```
<existing content>
# --- seihou:nix-flake ---
<new content>
# --- /seihou:nix-flake ---
```

For `AppendFile` and `PrependFile`, ensure a trailing newline separates the original and new content.

#### M2-3: Add unit tests

Create `test/Seihou/Engine/SectionSpec.hs` and register it in `seihou-core.cabal` under `other-modules`. Tests:

- `renderSectionOpen` produces correct format
- `renderSectionClose` produces correct format
- `wrapInSection` wraps content with open/close markers
- `applyTextPatch AppendFile` appends content
- `applyTextPatch PrependFile` prepends content
- `applyTextPatch AppendSection` appends wrapped section
- Section markers use configured comment prefix
- Empty existing content with AppendSection still works
- Idempotence: applying same section twice doesn't duplicate

#### M2-4: Build and test

```
cd seihou
cabal test all
nix fmt
```

---

### Milestone 3: Wire Patching into the Pipeline

**Scope**: Add `PatchFileOp` to `Operation`, implement `compilePatchStep` in `Plan.hs`, update `Execute.hs` to handle `PatchFileOp`, and update all pattern matches. At the end, individual module compilation can produce `PatchFileOp` operations, but composition merge doesn't yet handle them (that's M4).

**Acceptance**: Steps with `patch = Some "append-file"` compile to `PatchFileOp` operations. Execution of `PatchFileOp` reads the target file and applies the patch. All tests pass.

#### M3-1: Add PatchFileOp to Operation

In `seihou-core/src/Seihou/Core/Types.hs`, add to the `Operation` type:

```haskell
data Operation
  = WriteFileOp { ... }
  | CreateDirOp { ... }
  | CopyFileOp { ... }
  | RunCommandOp { ... }
  | PatchFileOp
      { patchDest :: FilePath,
        patchContent :: Text,
        patchOp :: PatchOp,
        patchStrategy :: Strategy,
        patchModule :: ModuleName  -- Needed for section markers
      }
  deriving stock (Eq, Show, Generic)
```

#### M3-2: Add compilePatchStep to Plan.hs

In `seihou-core/src/Seihou/Engine/Plan.hs`, add:

```haskell
compilePatchStep ::
  FilePath -> Map VarName VarValue -> ModuleName -> Step -> IO (Either [Text] [Operation])
```

This is similar to `compileTemplateStep` but produces `PatchFileOp` instead of `WriteFileOp`. The `ModuleName` is needed for section marker generation.

#### M3-3: Update compileStep dispatch

In `compilePlan` / `compileStep`, check `stepPatch step`. If it's `Just patchOp`, route to `compilePatchStep` regardless of strategy. If `Nothing`, use the existing strategy dispatch.

Note: `compilePlan` currently takes `FilePath -> Module -> Map VarName VarValue -> IO (...)`. The `ModuleName` can be obtained from `moduleName modul` which is already in scope.

#### M3-4: Update executeOp in Execute.hs

In `seihou-core/src/Seihou/Engine/Execute.hs`, the `executeOp` function must handle `PatchFileOp`:

1. Read existing content from `patchDest` (if file exists, otherwise start with empty)
2. Call `applyTextPatch` with the patch operation
3. Write the result to `patchDest`
4. Return a `FileRecord`

#### M3-5: Update dryRunPlan

In `dryRunPlan`, format `PatchFileOp` as something like:
```
  patch  README.md  (append-section from module-name)
```

#### M3-6: Update pattern matches

Every place that pattern-matches on `Operation` must handle `PatchFileOp`. Known locations:

- `seihou-core/src/Seihou/Engine/Diff.hs` — `planToFileMap` (include patchDest)
- `seihou-core/src/Seihou/Composition/Plan.hs` — `mergeOperations`, `destOfOp`
- `seihou-cli/src/Seihou/CLI/Run.hs` — list comprehension extracting files
- `test/Seihou/Integration/ExecutionSpec.hs` — `extractPlanned`

For now, in `mergeOperations`, `PatchFileOp` should be treated like `WriteFileOp` for the purpose of `destOfOp` (so it participates in conflict detection). The intelligent merge is M4.

#### M3-7: Add tests

In `test/Seihou/Engine/PlanSpec.hs`, add tests for steps with `stepPatch = Just AppendFile` etc., verifying they produce `PatchFileOp` operations.

In `test/Seihou/Engine/ExecuteSpec.hs`, add tests for executing `PatchFileOp` operations against an existing filesystem.

#### M3-8: Build and test

```
cd seihou
cabal test all
nix fmt
```

---

### Milestone 4: Intelligent Composition Merge

**Scope**: Enhance `mergeOperations` to handle `PatchFileOp` operations by applying patches to existing `WriteFileOp` content rather than overwriting. Also implement structured merge for two `WriteFileOp`s with `Structured` strategy. At the end, multi-module composition correctly merges text patches and structured files.

**Acceptance**: Two modules targeting the same text file via append-section produce merged content. Two modules targeting the same JSON/YAML file via Structured strategy produce deep-merged output. Composition tests pass.

#### M4-1: Implement mergeStructuredOps

In `seihou-core/src/Seihou/Composition/Plan.hs`, add:

```haskell
mergeStructuredOps :: Text -> Text -> IO (Either Text Text)
```

This function takes two Dhall source texts (from two `WriteFileOp`s with `Structured` strategy), evaluates them, merges the resulting Dhall records with `//` (right-biased shallow merge), and returns the merged Dhall source. The merged result is then re-processed through the Structured pipeline.

Implementation approach: concatenate the two Dhall expressions using Dhall's `//` merge operator, then evaluate and serialize the result. For example, if module A produces `{ name = "foo" }` and module B produces `{ extra = True }`, the merged expression is `{ name = "foo" } // { extra = True }`.

Note: Since the Dhall source has already had placeholders substituted, the merge operates on fully-resolved Dhall expressions.

#### M4-2: Update mergeOperations

In `mergeOperations`, change the handling logic:

1. **PatchFileOp targeting existing WriteFileOp**: Instead of replacing, apply `applyTextPatch` to the existing `WriteFileOp`'s content and produce an updated `WriteFileOp` with the merged content.

2. **Two WriteFileOps with Structured strategy**: Instead of last-writer-wins, call `mergeStructuredOps` to deep-merge the Dhall content.

3. **All other cases**: Keep current last-writer-wins behavior.

The `mergeOperations` function signature may need to change from pure to `IO` (because Dhall evaluation for structured merge is `IO`). Alternatively, the structured merge can be done at the `compileComposedPlan` level.

#### M4-3: Add ContentMerged warning

In `seihou-core/src/Seihou/Core/Types.hs`, extend `CompositionWarning`:

```haskell
data CompositionWarning
  = FileOverwritten FilePath ModuleName ModuleName
  | ContentMerged FilePath ModuleName ModuleName
  deriving stock (Eq, Show, Generic)
```

`ContentMerged` indicates two modules contributed to the same file via patching or structured merge (informational, not an error).

#### M4-4: Apply PatchFileOp in merge

When `mergeOperations` encounters a `PatchFileOp` whose `patchDest` matches an existing `WriteFileOp`:

1. Extract the existing content from the `WriteFileOp`
2. Call `applyTextPatch` with the patch operation, module name, existing content, and patch content
3. Replace the `WriteFileOp`'s content with the merged result
4. Record a `ContentMerged` warning
5. Do NOT remove the original `WriteFileOp` from the list — update it in place

If a `PatchFileOp` targets a file that doesn't yet exist in the operation list, this is an error (the base file must be created first by an earlier module in topological order).

#### M4-5: Add text patching composition tests

In `test/Seihou/Composition/PlanSpec.hs`, add tests:

- PatchFileOp AppendFile merges with existing WriteFileOp
- PatchFileOp AppendSection adds section markers and merges
- PatchFileOp targeting nonexistent file produces error
- Multiple patches from different modules accumulate correctly
- ContentMerged warning is generated

#### M4-6: Add structured merge composition tests

In `test/Seihou/Composition/PlanSpec.hs`, add tests:

- Two Structured WriteFileOps for same dest get merged
- Disjoint keys are combined
- Overlapping scalar keys use right-biased merge
- Nested records are merged

#### M4-7: Build and test

```
cd seihou
cabal test all
nix fmt
```

---

### Milestone 5: Integration Tests and Fixtures

**Scope**: Create complete test fixtures demonstrating patching and structured merge in a realistic multi-module setup. Add integration tests that exercise the full pipeline from module loading through composition to execution.

**Acceptance**: Integration tests demonstrate correct behavior for text patching and structured merge across multiple modules. All tests pass. `nix fmt` clean.

#### M5-1: Create haskell-shared-readme fixture

Create `test/fixtures/haskell-shared-readme/` with a `module.dhall` that declares a dependency on `haskell-base` and has a step with `patch = Some "append-section"` targeting `README.md`:

```dhall
{ name = "haskell-shared-readme"
, ...
, steps =
  [ { strategy = "template"
    , src = "readme-section.md.tpl"
    , dest = "README.md"
    , when = None Text
    , patch = Some "append-section"
    }
  ]
, dependencies = ["haskell-base"]
}
```

With `files/readme-section.md.tpl`:
```
## Additional Section

This was added by haskell-shared-readme.
```

#### M5-2: Create structured-merge fixture

Create `test/fixtures/structured-merge-a/` and `test/fixtures/structured-merge-b/` (or a single `structured-merge/` with two modules). Module A creates a base JSON file, module B adds keys via a Structured-strategy step targeting the same dest.

#### M5-3: Integration tests for text patching

In `test/Seihou/Integration/CompositionSpec.hs`, add a test that loads `haskell-base` + `haskell-shared-readme`, runs composition, and verifies that `README.md` contains both the base content and the appended section with markers.

#### M5-4: Integration tests for structured merge

In `test/Seihou/Integration/CompositionSpec.hs`, add a test that loads two modules contributing to the same JSON file, runs composition, and verifies the output JSON contains keys from both modules.

#### M5-5: Final validation

```
cd seihou
cabal test all
nix fmt
```

All tests pass, no warnings, formatting clean.


## Concrete Steps

All commands run from `seihou/` (the workspace root).

### Build command
```
cabal test all 2>&1
```
Expected: `All N tests passed.`

### Format command
```
nix fmt 2>&1
```
Expected: No output (already formatted).


## Validation and Acceptance

### Text Patching

Given modules A (creates `README.md` via Template) and B (appends a section to `README.md` via `patch = Some "append-section"`):

1. `compilePlan` for module B produces a `PatchFileOp` with `patchOp = AppendSection`
2. `mergeOperations` for [A, B] produces a single `WriteFileOp` for `README.md` whose content includes both A's original content and B's section wrapped in markers
3. The merged content looks like:
   ```
   # my-app

   Version: 0.1.0.0
   # --- seihou:haskell-shared-readme ---
   ## Additional Section

   This was added by haskell-shared-readme.
   # --- /seihou:haskell-shared-readme ---
   ```

### Structured Merge

Given modules A and B both targeting `config.json` via Structured strategy:

1. Module A's Dhall evaluates to `{ "name": "foo" }`
2. Module B's Dhall evaluates to `{ "extra": true }`
3. `mergeOperations` produces a single `WriteFileOp` for `config.json` with `{ "extra": true, "name": "foo" }`

### No Regressions

All 321+ existing tests continue to pass. The new `patch = None Text` field in fixtures does not change any existing behavior.


## Idempotence and Recovery

Every milestone leaves the codebase in a compilable, test-passing state. If a milestone is partially completed, incomplete changes can be identified from the Progress checklist and reverted via `git checkout` on affected files.

Adding `patch = None Text` to fixtures is safe — it's an additive Dhall schema change and existing `Nothing` handling means no behavior change.

The `PatchFileOp` constructor addition requires updating all pattern matches, similar to the `opStrategy` field addition in the template-engine-integration plan. The same systematic approach applies: grep for `WriteFileOp` and `CopyFileOp` pattern matches, update each one.


## Interfaces and Dependencies

### New Module

In `seihou-core/src/Seihou/Engine/Section.hs`, define:

```haskell
renderSectionOpen :: SectionMarker -> Text
renderSectionClose :: SectionMarker -> Text
wrapInSection :: SectionMarker -> Text -> Text
applyTextPatch :: PatchOp -> ModuleName -> Text -> Text -> Text -> Either Text Text
```

### Modified Types (in `seihou-core/src/Seihou/Core/Types.hs`)

```haskell
data PatchOp = AppendFile | PrependFile | AppendSection
  deriving stock (Eq, Show, Generic)

data Step = Step
  { stepStrategy :: Strategy,
    stepSrc :: FilePath,
    stepDest :: Text,
    stepWhen :: Maybe Expr,
    stepPatch :: Maybe PatchOp
  }

data Operation
  = WriteFileOp { opDest :: FilePath, opContent :: Text, opStrategy :: Strategy }
  | CreateDirOp { opPath :: FilePath }
  | CopyFileOp { opSrc :: FilePath, opDest :: FilePath }
  | RunCommandOp { opCommand :: Text, opWorkDir :: Maybe FilePath }
  | PatchFileOp
      { patchDest :: FilePath,
        patchContent :: Text,
        patchOp :: PatchOp,
        patchStrategy :: Strategy,
        patchModule :: ModuleName
      }

data CompositionWarning
  = FileOverwritten FilePath ModuleName ModuleName
  | ContentMerged FilePath ModuleName ModuleName
```

### Modified Functions

In `seihou-core/src/Seihou/Dhall/Eval.hs`:
```haskell
stepDecoder :: Decoder Step  -- add patch field decoding
```

In `seihou-core/src/Seihou/Engine/Plan.hs`:
```haskell
compilePatchStep :: FilePath -> Map VarName VarValue -> ModuleName -> Step -> IO (Either [Text] [Operation])
```

In `seihou-core/src/Seihou/Composition/Plan.hs`:
```haskell
mergeOperations :: [(ModuleName, [Operation])] -> ([Operation], [CompositionWarning])
-- Enhanced to handle PatchFileOp and structured merge
```

### No New Library Dependencies

All functionality is implemented using existing dependencies (text, containers, dhall, aeson, yaml). No new cabal dependencies needed.
