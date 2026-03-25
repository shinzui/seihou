# Add `AppendLineIfAbsent` PatchOp

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

Module authors need an idempotent way to add lines to line-oriented config files
(`.gitignore`, `.dockerignore`, `.env.example`) without creating duplicates on re-run.
Today the only options are `AppendFile` (always appends — duplicates on re-run) or
`AppendSection` (idempotent via section markers — too heavy for a single line).

After this change a module step can declare `patch = Some "append-line-if-absent"`.
The patch engine will split both the existing file and the new content into lines,
filter out lines already present, and append only the missing ones. Re-runs are
idempotent with zero visual noise.

**User-visible outcome:** A module that patches `.gitignore` with `.claude/` will add
the line on first run and do nothing on subsequent runs (no duplicates, no markers).


## Progress

- [x] M1: Add `AppendLineIfAbsent` constructor to `PatchOp` in `Types.hs` (2026-03-25)
- [x] M1: Add `applyTextPatch` clause for `AppendLineIfAbsent` in `Section.hs` (2026-03-25)
- [x] M1: Add unit tests for `AppendLineIfAbsent` in `SectionSpec.hs` (2026-03-25)
- [x] M1: Run tests — `SectionSpec` passes (2026-03-25, all 34 tests pass)
- [x] M2: Add `"append-line-if-absent"` case to `patchOpDecoder` in `Eval.hs` (top-level) (2026-03-25)
- [x] M2: Add `"append-line-if-absent"` case to `parsePatchOp` in `stepDecoder` in `Eval.hs` (nested) (2026-03-25)
- [x] M2: Add `formatPatchOp AppendLineIfAbsent` in `Execute.hs` (2026-03-25)
- [x] M2: Run tests — full suite passes (2026-03-25, all 647 tests pass)
- [x] M3: Add execution test for `PatchFileOp AppendLineIfAbsent` in `ExecuteSpec.hs` (2026-03-25)
- [x] M3: Add composition test for `PatchFileOp AppendLineIfAbsent` in `PlanSpec.hs` (Composition) (2026-03-25)
- [x] M3: Run full test suite — all green (2026-03-25, all 650 tests pass)
- [x] M4: Update Dhall schema comment in `seihou-schema/Step.dhall` (2026-03-25)


## Surprises & Discoveries

- `T.unlines` already appends a trailing newline to each element, so the plan's
  original `T.unlines missing <> "\n"` produced a double trailing newline. Fixed to
  just `T.unlines missing`. Test evidence: "expected `.claude/\n` but got `.claude/\n\n`".


## Decision Log

- Decision: Use line-level equality (exact match after splitting on `\n`) rather than
  substring or regex matching.
  Rationale: Line-oriented config files like `.gitignore` are the primary use case.
  Exact line matching is simple, predictable, and avoids false positives. Substring
  matching would risk suppressing lines that merely contain a prefix of an existing line.
  Date: 2026-03-25

- Decision: Strip trailing whitespace during comparison but preserve original lines
  in output.
  Rationale: Prevents invisible whitespace differences from defeating dedup while
  keeping the file's existing formatting intact.
  Date: 2026-03-25

- Decision: When all lines already exist, return existing content unchanged (not an error).
  Rationale: Idempotence is the whole point. A no-op patch is success.
  Date: 2026-03-25

- Decision: Ignore blank/empty lines during dedup — only dedup non-empty lines.
  Rationale: Blank lines are structural and should not prevent new content from including
  its own blank-line separators.
  Date: 2026-03-25


## Outcomes & Retrospective

All four milestones completed. The feature adds a single new `PatchOp` constructor
(`AppendLineIfAbsent`) that provides idempotent line-level patching for config files.

**Files changed (7):**
- `seihou-core/src/Seihou/Core/Types.hs` — new constructor
- `seihou-core/src/Seihou/Engine/Section.hs` — patch logic (6 lines)
- `seihou-core/src/Seihou/Dhall/Eval.hs` — two decoder sites
- `seihou-core/src/Seihou/Engine/Execute.hs` — dry-run formatting
- `seihou-core/test/Seihou/Engine/SectionSpec.hs` — 5 unit tests
- `seihou-core/test/Seihou/Engine/ExecuteSpec.hs` — 2 execution tests
- `seihou-core/test/Seihou/Composition/PlanSpec.hs` — 1 composition test
- `seihou-schema/Step.dhall` — documentation comment

**Test count:** 647 → 650 (3 new tests added). All pass.

**Lesson learned:** `T.unlines` already appends a trailing newline — the plan's original
`T.unlines missing <> "\n"` needed correction to avoid double newlines. Caught immediately
by unit tests.


## Context and Orientation

### What is PatchOp?

`PatchOp` is an enum in `seihou-core` that describes how a module step's content should
be merged into an existing file rather than overwriting it. It lives in the `Step` record
(field `patch :: Maybe PatchOp`) and flows through the system as part of `PatchFileOp`
operations.

### Current constructors

| Constructor     | Behavior                                        |
|-----------------|-------------------------------------------------|
| `AppendFile`    | Concatenate new content after existing           |
| `PrependFile`   | Concatenate new content before existing          |
| `AppendSection` | Wrap in section markers, append to existing      |

### Key files (all paths relative to repo root)

| File | Role |
|------|------|
| `seihou-core/src/Seihou/Core/Types.hs:138-142` | `PatchOp` data type definition |
| `seihou-core/src/Seihou/Engine/Section.hs:82-89` | `applyTextPatch` — applies patch ops to text |
| `seihou-core/src/Seihou/Dhall/Eval.hs:313-325` | `patchOpDecoder` — decodes PatchOp from Dhall Text |
| `seihou-core/src/Seihou/Dhall/Eval.hs:349-352` | `parsePatchOp` (nested in `stepDecoder`) — **duplicate** decoder, must stay in sync |
| `seihou-core/src/Seihou/Engine/Execute.hs:68-88` | `executeOp` for `PatchFileOp` — reads existing file, applies patch, writes result |
| `seihou-core/src/Seihou/Engine/Execute.hs:104-106` | `formatPatchOp` — display name for dry-run output |
| `seihou-core/src/Seihou/Composition/Plan.hs:72-107` | `handlePatchOp` — merges patches during multi-module composition |
| `seihou-core/src/Seihou/Engine/Diff.hs` | Three-state diff; uses `isPatch` predicate (pattern `Just _`) — no constructor-specific logic |
| `seihou-core/src/Seihou/Engine/Preview.hs:75` | `opToPreview` — pattern match on `PatchFileOp`, no constructor-specific logic |
| `seihou-core/src/Seihou/Engine/Plan.hs:214-255` | `compilePatchStep` — compiles Step with patch into `PatchFileOp` |
| `seihou-schema/Step.dhall` | Dhall schema; `patch` is `Optional Text` with valid values listed in comment |

### Files that do NOT need changes

These files use `PatchFileOp` but do not pattern-match on `PatchOp` constructors:

- `Seihou.Engine.Diff` — checks `isPatch` via `Just _`, not individual constructors
- `Seihou.Engine.Preview` — destructures `PatchFileOp` but ignores `patchOp'`
- `Seihou.Engine.Plan` — passes `step.patch` through to `PatchFileOp`, no dispatch
- `Seihou.Composition.Plan` — passes `patchOp'` to `applyTextPatch`, no dispatch

### Test files

| File | What it tests |
|------|---------------|
| `seihou-core/test/Seihou/Engine/SectionSpec.hs:50-91` | `applyTextPatch` for all three existing ops |
| `seihou-core/test/Seihou/Engine/ExecuteSpec.hs:126-159` | `PatchFileOp` execution for all three ops |
| `seihou-core/test/Seihou/Composition/PlanSpec.hs` | Composition merge with `PatchFileOp` |
| `seihou-core/test/Main.hs` | Test runner — no changes needed (specs already registered) |

### Test infrastructure

- **Framework:** Tasty + Hspec (via `tasty-hspec`)
- **Pattern:** Each spec module exports `tests :: IO TestTree`; registered in `test/Main.hs`
- **Pure filesystem:** `PureFS` from `Seihou.Effect.FilesystemPure` for IO-free tests
- **Build/run:** `cabal test seihou-core-test` from repo root


## Plan of Work

### Milestone 1: Core type and patch logic

**Scope:** Add the new constructor and implement line-dedup logic. Unit-test it in isolation.

**What exists at the end:** `applyTextPatch AppendLineIfAbsent` works correctly.
Lines already in the file are skipped; missing lines are appended. Empty-content and
all-present cases handled.

**Acceptance:** `cabal test seihou-core-test -j --test-option='--pattern=Section'` passes.

#### Edit 1: `seihou-core/src/Seihou/Core/Types.hs`

At line 141, add `AppendLineIfAbsent` to the `PatchOp` type:

```haskell
data PatchOp
  = AppendFile
  | PrependFile
  | AppendSection
  | AppendLineIfAbsent
  deriving stock (Eq, Show, Generic)
```

#### Edit 2: `seihou-core/src/Seihou/Engine/Section.hs`

After the `AppendSection` clause of `applyTextPatch` (line 89), add:

```haskell
applyTextPatch AppendLineIfAbsent _ _ existing new =
  let existingLines = map T.stripEnd (T.lines existing)
      newLines = filter (not . T.null . T.strip) (T.lines (T.stripEnd new))
      missing = filter (\l -> T.stripEnd l `notElem` existingLines) newLines
   in if null missing
        then Right existing
        else Right (ensureTrailingNewline existing <> T.unlines missing <> "\n")
```

The logic:
1. Split existing content into lines, strip trailing whitespace for comparison.
2. Split new content into lines, drop blank lines (blank lines are structural, not identity).
3. Filter to lines whose stripped form is not in the existing set.
4. If nothing is missing, return existing unchanged (idempotent).
5. Otherwise, append missing lines with a trailing newline.

#### Edit 3: `seihou-core/test/Seihou/Engine/SectionSpec.hs`

Add new test cases inside the `describe "applyTextPatch"` block (after line 91):

```haskell
    it "AppendLineIfAbsent appends only missing lines" $ do
      let result = applyTextPatch AppendLineIfAbsent modName "#" "line1\nline2\n" "line2\nline3\n"
      result `shouldBe` Right "line1\nline2\nline3\n"

    it "AppendLineIfAbsent is idempotent when all lines present" $ do
      let existing = ".claude/\nnode_modules/\n"
          result = applyTextPatch AppendLineIfAbsent modName "#" existing ".claude/\n"
      result `shouldBe` Right existing

    it "AppendLineIfAbsent with empty existing content" $ do
      let result = applyTextPatch AppendLineIfAbsent modName "#" "" ".claude/\n"
      result `shouldBe` Right ".claude/\n"

    it "AppendLineIfAbsent ignores trailing whitespace differences" $ do
      let result = applyTextPatch AppendLineIfAbsent modName "#" "line1  \n" "line1\n"
      result `shouldBe` Right "line1  \n"

    it "AppendLineIfAbsent handles multiple new lines, some present" $ do
      let result = applyTextPatch AppendLineIfAbsent modName "#"
                     "*.log\n.env\n"
                     "*.log\n.claude/\n.env\ndist/\n"
      result `shouldBe` Right "*.log\n.env\n.claude/\ndist/\n"
```

### Milestone 2: Dhall decoder and dry-run formatting

**Scope:** Wire the new variant into the Dhall decoder so module authors can use
`patch = Some "append-line-if-absent"` in Step definitions. Update dry-run formatting.

**What exists at the end:** A Dhall module step with `patch = Some "append-line-if-absent"`
decodes correctly and shows the right label in `--dry-run` output.

**Acceptance:** `cabal test seihou-core-test -j` passes (full suite).

#### Edit 4: `seihou-core/src/Seihou/Dhall/Eval.hs` — top-level `patchOpDecoder`

At line 323, add a new case before the `other` catch-all:

```haskell
    parsePatchOp :: Text -> PatchOp
    parsePatchOp t = case t of
      "append-file" -> AppendFile
      "prepend-file" -> PrependFile
      "append-section" -> AppendSection
      "append-line-if-absent" -> AppendLineIfAbsent
      other -> error ("Unknown patch operation \"" <> T.unpack other <> "\"; expected one of: append-file, prepend-file, append-section, append-line-if-absent")
```

#### Edit 5: `seihou-core/src/Seihou/Dhall/Eval.hs` — nested `parsePatchOp` in `stepDecoder`

At line 351, add the same case:

```haskell
    parsePatchOp "append-file" = AppendFile
    parsePatchOp "prepend-file" = PrependFile
    parsePatchOp "append-section" = AppendSection
    parsePatchOp "append-line-if-absent" = AppendLineIfAbsent
    parsePatchOp other = error ("Unknown patch operation \"" <> T.unpack other <> "\"; expected one of: append-file, prepend-file, append-section, append-line-if-absent")
```

#### Edit 6: `seihou-core/src/Seihou/Engine/Execute.hs` — `formatPatchOp`

At line 106, add:

```haskell
    formatPatchOp AppendLineIfAbsent = "append-line-if-absent"
```

### Milestone 3: Execution and composition tests

**Scope:** Add test coverage for the new variant flowing through execution and composition.

**Acceptance:** `cabal test seihou-core-test -j` passes.

#### Edit 7: `seihou-core/test/Seihou/Engine/ExecuteSpec.hs`

After the existing `PatchFileOp` tests (around line 159), add:

```haskell
    it "executes PatchFileOp AppendLineIfAbsent, skipping existing lines" $ do
      let initial = PureFS (Map.singleton "/project/.gitignore" "node_modules/\n.env\n") mempty
          ops = [PatchFileOp ".gitignore" ".env\n.claude/\n" AppendLineIfAbsent Template modName]
          (records, fs) = runExecFS initial ops
      Map.member ".gitignore" records `shouldBe` True
      let content = fs.files Map.! "/project/.gitignore"
      content `shouldBe` "node_modules/\n.env\n.claude/\n"

    it "executes PatchFileOp AppendLineIfAbsent idempotently" $ do
      let initial = PureFS (Map.singleton "/project/.gitignore" "node_modules/\n.claude/\n") mempty
          ops = [PatchFileOp ".gitignore" ".claude/\n" AppendLineIfAbsent Template modName]
          (records, fs) = runExecFS initial ops
      Map.member ".gitignore" records `shouldBe` True
      let content = fs.files Map.! "/project/.gitignore"
      content `shouldBe` "node_modules/\n.claude/\n"
```

#### Edit 8: `seihou-core/test/Seihou/Composition/PlanSpec.hs`

Add a test case for `AppendLineIfAbsent` in composition (a `WriteFileOp` followed by a
`PatchFileOp AppendLineIfAbsent` targeting the same file). Follow the existing pattern
used for `AppendFile` and `AppendSection` tests in this file.

### Milestone 4: Schema documentation

**Scope:** Update the Dhall schema comment to list the new valid value.

#### Edit 9: `seihou-schema/Step.dhall`

Update the file comment at the top to mention `"append-line-if-absent"` as a valid patch
value. The schema itself is `Optional Text` and needs no structural change — only the
documentation comment.


## Concrete Steps

All commands run from the repository root: `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`

### Build after M1 edits

```bash
cabal build seihou-core-test
```

Expected: compiles without warnings related to non-exhaustive patterns.

### Run Section tests after M1

```bash
cabal test seihou-core-test -j --test-option='--pattern=Section'
```

Expected: all `applyTextPatch` tests pass, including the new `AppendLineIfAbsent` cases.

### Run full suite after M2

```bash
cabal test seihou-core-test -j
```

Expected: all tests pass. The `-Wall` flag (if enabled) should produce no new warnings
about incomplete pattern matches.

### Run full suite after M3

```bash
cabal test seihou-core-test -j
```

Expected: new execution and composition tests pass alongside existing tests.

### Verify schema after M4

```bash
cat seihou-schema/Step.dhall
```

Expected: comment lists four valid patch values.


## Validation and Acceptance

1. **Unit test — line dedup logic:**
   `applyTextPatch AppendLineIfAbsent` with overlapping, disjoint, and fully-present
   inputs produces the correct merged text. Five test cases in `SectionSpec.hs`.

2. **Execution test — end-to-end file patching:**
   `PatchFileOp` with `AppendLineIfAbsent` reads an existing `.gitignore` from the
   pure filesystem, appends only missing lines, and records the correct hash. Re-run
   with all lines present produces identical output.

3. **Composition test — multi-module merge:**
   A `WriteFileOp` followed by a `PatchFileOp AppendLineIfAbsent` targeting the same
   destination produces a merged `WriteFileOp` with no duplicate lines.

4. **Decoder test — round-trip:**
   The string `"append-line-if-absent"` decodes to `AppendLineIfAbsent` in both
   `patchOpDecoder` and the nested `parsePatchOp` in `stepDecoder`.

5. **Dry-run formatting:**
   `dryRunPlan` with a `PatchFileOp AppendLineIfAbsent` produces output containing
   `"append-line-if-absent"`.

6. **No regressions:**
   `cabal test seihou-core-test -j` — all existing tests still pass.


## Idempotence and Recovery

All edits are additive (new constructor, new pattern-match clauses, new tests). No
existing behavior is modified. Each milestone can be built and tested independently.

If a milestone fails, the fix is local to the files edited in that milestone. Since
`PatchOp` derives `Generic` and uses `-Wall`, the compiler will flag any missed pattern
matches immediately.

The Dhall schema uses `Optional Text` for `patch`, so adding a new valid string value
is a non-breaking change — existing modules that don't use `"append-line-if-absent"`
are unaffected.


## Interfaces and Dependencies

No new library dependencies. The implementation uses only `Data.Text` (already imported
in `Section.hs`).

### New type after M1

In `seihou-core/src/Seihou/Core/Types.hs`:

```haskell
data PatchOp
  = AppendFile
  | PrependFile
  | AppendSection
  | AppendLineIfAbsent
  deriving stock (Eq, Show, Generic)
```

### New function clause after M1

In `seihou-core/src/Seihou/Engine/Section.hs`:

```haskell
applyTextPatch :: PatchOp -> ModuleName -> Text -> Text -> Text -> Either Text Text
-- existing clauses...
applyTextPatch AppendLineIfAbsent _ _ existing new = ...
```

### Dhall interface (unchanged structurally)

```dhall
-- Step.dhall  (patch field)
patch : Optional Text
-- Valid values: "append-file", "prepend-file", "append-section", "append-line-if-absent"
```
