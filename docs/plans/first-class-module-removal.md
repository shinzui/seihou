# First-class module removal

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

After this change, module authors declare *how* their module is removed — not just whether it can be. A module that adds a dependency to a cabal file declares a removal step that strips it. A module that appends a section to `.gitignore` declares a removal step that removes its section markers. A module that ran `git init` declares a removal command like `echo 'Note: git init was not reversed'`. The `seihou remove` command executes these author-declared removal steps and commands instead of blindly deleting files.

After implementation, a user can:

1. Run `seihou remove haskell-base` and see the module's declared removal steps executed — sections stripped from shared files, files deleted, cleanup commands run.
2. See removal steps in `seihou remove --dry-run` output that describe exactly what will happen.
3. Author a module with a `removal` section in `module.dhall` that specifies the inverse of each forward effect.


## Progress

- [x] Milestone 1: Design the removal schema in Dhall and Haskell types (2026-03-21)
- [x] Milestone 2: Implement Dhall decoders and manifest storage for removal data (2026-03-21)
- [x] Milestone 3: Implement removal operations in the engine (remove-file, remove-section, rewrite-file) (2026-03-21)
- [x] Milestone 4: Rewrite the Remove CLI handler to use declared removal steps (2026-03-21)
- [x] Milestone 5: Tests for the new removal engine (2026-03-21)
- [x] Milestone 6: Update all documentation and agent prompts (2026-03-21)
- [ ] Milestone 7: End-to-end validation (manual — requires creating a test module with removal spec)


## Surprises & Discoveries

- The `schema/` directory inside the seihou repo is a local copy of `seihou-schema/` used by `seihou new-module` and tests. Both copies needed updating. The Scaffold tests generate Dhall via `S.Module::` record completion, so they pick up defaults from the schema automatically — once the schema was updated, the tests passed without any test code changes.


## Decision Log

- Decision: Replace the `removable :: Bool` flag with an optional `removal` record.
  Rationale: A boolean flag provides no information about *how* to remove. The presence of a `removal` section is itself the opt-in signal — if `removal` is `None`, the module is not removable. If it is `Some { steps, commands }`, those steps describe the inverse operations. This eliminates the redundancy of `removable = True` alongside a separate removal spec.
  Date: 2026-03-21

- Decision: Removal steps are a separate list of removal-specific operations, not inverses auto-derived from forward steps.
  Rationale: Auto-deriving inverses would only work for simple cases (delete a file created by Copy). For patches, structured merges, and arbitrary commands, the module author knows best what the inverse is. Explicit removal steps give authors full control. The engine provides a small set of removal actions (`remove-file`, `remove-section`, `rewrite-file`) that cover the common cases, plus removal commands for arbitrary cleanup.
  Date: 2026-03-21

- Decision: Three removal actions: `remove-file`, `remove-section`, `rewrite-file`.
  Rationale: `remove-file` deletes a file the module created (the common case). `remove-section` strips the content between `# --- seihou:module-name ---` markers from a file that another module owns — this is the exact inverse of `append-section`. `rewrite-file` reads a file, applies a Dhall text function to transform it, and writes the result back — this covers cases like removing a dependency from a cabal file or stripping an import line. These three cover the vast majority of use cases without requiring a general-purpose undo system.
  Date: 2026-03-21

- Decision: Removal commands mirror forward commands but run during `seihou remove`.
  Rationale: Some modules run shell commands during `seihou run` (e.g., `cabal build`, `git init`). The removal section's `commands` field lets authors declare cleanup commands (e.g., `cabal clean`). These follow the same shape as forward commands: `{ run, workDir, when }`.
  Date: 2026-03-21

- Decision: Store the removal spec in the manifest's `AppliedModule` record.
  Rationale: Removal must work even when the module source has been uninstalled. By capturing the removal spec at apply time (in `AppliedModule`), the `seihou remove` command has everything it needs from the manifest alone.
  Date: 2026-03-21


## Outcomes & Retrospective

**Milestones 1-6 completed on 2026-03-21.**

- Schema: `removable :: Bool` replaced with `removal :: Optional Removal.Type` in both Dhall and Haskell. Three removal actions: `remove-file`, `remove-section`, `rewrite-file`. Backwards-compatible manifest decoding (`"removable": true` → `Just (Removal [] [])`).
- Engine: New step-based removal engine (`buildRemovalOps`, `executeRemovalOps`) alongside legacy `computeRemovalPlan`/`executeRemoval`. `removeSection` function strips section markers from files.
- CLI: Handler rewrites plan display to show Delete/Strip/Rewrite/Run operations.
- Tests: 22 new tests (618 → 640 total). Covers removal ops, section removal, and full round-trips.
- Documentation: All 8 doc files and 3 agent prompts updated.
- Surprise: Local `schema/` directory is a git submodule pointing to `seihou-schema` — required parallel updates.

**Remaining:** Milestone 7 (manual end-to-end validation) requires creating a real module with a `removal` section and testing `seihou run` → `seihou remove` round-trip.


## Context and Orientation

Seihou is a composable project scaffolding system built in Haskell. Users run `seihou run <module>` to generate files, and `seihou remove <module>` to reverse a module's effects. The current removal implementation (committed in `f115d6b`) treats removal as "delete all files this module generated." This plan replaces that with first-class removal where modules declare their own removal logic.

The key files and concepts:

**Dhall module schema** at `seihou-schema/Module.dhall` defines what a `module.dhall` can contain. Currently has 10 fields including `removable :: Bool`. The schema package at `seihou-schema/package.dhall` re-exports all types for record completion (`S.Module::{ ... }`).

**Haskell domain types** at `seihou-core/src/Seihou/Core/Types.hs` define `Module` (line 178), `Step`, `Command`, `PatchOp`, `Operation`, `Manifest`, `AppliedModule`, `FileRecord`, and all supporting types. The `Module` record has `removable :: Bool` (line 189). `AppliedModule` also has `removable :: Bool` (line 282).

**Dhall decoder** at `seihou-core/src/Seihou/Dhall/Eval.hs` maps Dhall fields to Haskell types. The `moduleDecoder` (line 103) uses `field "removable" bool` (line 116).

**Manifest serialization** at `seihou-core/src/Seihou/Manifest/Types.hs` encodes `AppliedModule` to JSON with `"removable"` (line 73). Decoding uses `.:? "removable" .!= False` for backwards compatibility (line 81).

**Removal engine** at `seihou-core/src/Seihou/Engine/Remove.hs` provides `computeRemovalPlan` and `executeRemoval`. Currently operates by finding files in the manifest where `FileRecord.moduleName` matches, classifying them as safe/conflict/gone, and deleting them. Has no concept of removal steps or commands.

**CLI handler** at `seihou-cli/src/Seihou/CLI/Remove.hs` reads the manifest, computes a removal plan, shows a preview, resolves conflicts interactively, and executes.

**Section markers** at `seihou-core/src/Seihou/Engine/Section.hs` define the `# --- seihou:module-name ---` / `# --- /seihou:module-name ---` format used by `append-section` patches. The `wrapInSection` function wraps content in these markers. There is currently no function to *remove* a section — that is new work in this plan.

**Run handler** at `seihou-cli/src/Seihou/CLI/Run.hs` constructs `AppliedModule` records at line 365. This is where we capture the removal spec into the manifest.

**Test files**: `seihou-core/test/Seihou/Engine/RemoveSpec.hs` has 13 tests for the current removal engine. All test fixtures in `seihou-core/test/fixtures/*/module.dhall` have `removable = False`.

**Documentation files** that reference removal and need updating:
- `docs/cli/remove.md` — CLI reference
- `docs/user/module-authoring.md` — field reference, "Removing modules" section
- `docs/user/getting-started.md` — "Removing a module" section
- `docs/dev/design/proposed/cli-commands.md` — `seihou remove` spec
- `docs/dev/architecture/overview.md` — project tree, effect descriptions
- `docs/user/CHANGELOG.md` — documentation changelog
- `seihou-cli/data/assist-prompt.md` — agent assist context
- `seihou-cli/data/bootstrap-prompt.md` — agent bootstrap context
- `seihou-cli/data/setup-prompt.md` — agent setup context
- `seihou-cli/help/modules.md` — help topic


## Plan of Work

The work proceeds in seven milestones. Each is independently verifiable.


### Milestone 1: Removal Schema

At the end of this milestone, the Dhall schema accepts a `removal` section on module definitions and the Haskell types represent removal steps and commands.

The `removable :: Bool` field on `Module` and `AppliedModule` is replaced with `removal :: Maybe Removal` — where `Removal` is a new type containing a list of removal steps and a list of removal commands. When `removal` is `Nothing` (Dhall `None`), the module is not removable. When it is `Just`, the removal steps describe how to reverse the module's effects.

**New Dhall types** in `seihou-schema/`:

Create `seihou-schema/RemovalStep.dhall`:

    { Type =
        { action : Text     -- "remove-file" | "remove-section" | "rewrite-file"
        , dest : Text        -- target file path (supports {{var}} placeholders)
        , src : Optional Text  -- for rewrite-file: path to Dhall function in files/
        }
    , default =
        { src = None Text
        }
    }

Create `seihou-schema/Removal.dhall`:

    let RemovalStep = ./RemovalStep.dhall
    let Command = ./Command.dhall

    in  { Type =
            { steps : List RemovalStep.Type
            , commands : List Command.Type
            }
        , default =
            { steps = [] : List RemovalStep.Type
            , commands = [] : List Command.Type
            }
        }

Update `seihou-schema/Module.dhall`: Replace `removable : Bool` with `removal : Optional Removal.Type` in the `Type` record, and `removable = False` with `removal = None Removal.Type` in the `default` record. Add `let Removal = ./Removal.dhall` to the imports.

Update `seihou-schema/package.dhall`: Add `Removal` and `RemovalStep` exports.

**New Haskell types** in `seihou-core/src/Seihou/Core/Types.hs`:

    data RemovalAction
      = RemoveFileAction       -- delete the file entirely
      | RemoveSectionAction    -- strip this module's section markers from the file
      | RewriteFileAction      -- apply a Dhall text function to transform the file
      deriving stock (Eq, Show, Generic)

    data RemovalStep = RemovalStep
      { action :: RemovalAction
      , dest :: Text                 -- target file, supports {{var}} placeholders
      , src :: Maybe FilePath        -- for RewriteFileAction: Dhall function source
      }
      deriving stock (Eq, Show, Generic)

    data Removal = Removal
      { removalSteps :: [RemovalStep]
      , removalCommands :: [Command]  -- reuses existing Command type
      }
      deriving stock (Eq, Show, Generic)

Replace `removable :: Bool` on `Module` with `removal :: Maybe Removal`. Replace `removable :: Bool` on `AppliedModule` with `removal :: Maybe Removal` (so removal specs are captured in the manifest at apply time).

Acceptance: `cabal build all` succeeds. (Tests will need fixing for the type changes — that is expected and part of this milestone.)


### Milestone 2: Decoders, Serialization, and Type Migration

At the end of this milestone, Dhall modules with `removal` sections decode correctly into Haskell, the manifest serializes and deserializes `Removal` data, and all existing code that referenced `removable :: Bool` compiles against the new `removal :: Maybe Removal`.

**Dhall decoder** in `seihou-core/src/Seihou/Dhall/Eval.hs`: Replace `field "removable" bool` with a decoder for `field "removal" (maybe removalDecoder)`. Add `removalDecoder`, `removalStepDecoder`, and `removalActionDecoder` following the existing patterns (e.g., `strategyDecoder` for enum-from-text, `commandDecoder` for records).

**Manifest JSON** in `seihou-core/src/Seihou/Manifest/Types.hs`: Replace `"removable"` encoding on `AppliedModule` with `"removal"` — encoding `Nothing` as absent, `Just removal` as a nested object with `"steps"` and `"commands"` arrays. For backwards compatibility, decode `"removable": true` in old manifests as `Just (Removal [] [])` (removable but no declared steps — preserves the old delete-all-files behavior). Decode `"removable": false` or absent as `Nothing`.

**Run handler** in `seihou-cli/src/Seihou/CLI/Run.hs` at line 365: Replace `removable = m.removable` with `removal = m.removal` in the `AppliedModule` construction.

**All test files** that construct `Module` or `AppliedModule` records: Replace `removable = False` with `removal = Nothing` and `removable = True` with `Just (Removal [] [])` (or appropriate removal specs for test modules).

**All fixture module.dhall files**: Replace `removable = False` with `removal = None { steps : List { action : Text, dest : Text, src : Optional Text }, commands : List { run : Text, workDir : Optional Text, when : Optional Text } }` — or better, use the schema's default. This is verbose but Dhall-correct. Alternatively, update fixtures to import the schema and use `S.Module::{ ... }` so the default fills in automatically.

**Validate.hs** in `seihou-cli/src/Seihou/CLI/Validate.hs`: Update the `dummyModule` construction.

Acceptance: `cabal build all` succeeds. `cabal test all` passes with all existing tests adapted.

    cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou
    cabal build all
    cabal test all


### Milestone 3: Removal Operations Engine

At the end of this milestone, the removal engine executes declared removal steps: `remove-file` deletes a file, `remove-section` strips section markers from a file, and `rewrite-file` applies a Dhall text function to transform a file.

**Section removal** in `seihou-core/src/Seihou/Engine/Section.hs`: Add a new function:

    removeSection :: ModuleName -> Text -> Text -> Text

This function takes a module name, a comment prefix (e.g., `"#"`), and the file content, and returns the content with the section between `# --- seihou:module-name ---` and `# --- /seihou:module-name ---` (inclusive) removed. If the section is not found, the content is returned unchanged. Also clean up any resulting double blank lines.

**Removal engine rewrite** in `seihou-core/src/Seihou/Engine/Remove.hs`: Replace the current file-deletion-only approach with a step-based engine.

The new `computeRemovalPlan` checks that the module has `removal = Just ...` in the manifest (replacing the `removable` check). It no longer classifies files — that was the old approach. Instead, it validates that the removal spec is present and returns it.

The new `executeRemoval` iterates over the declared removal steps and executes each:

- `RemoveFileAction`: Check if the file exists. If so, compare hash to manifest; if unchanged, delete. If modified, treat as conflict (prompt or force). If gone, skip.
- `RemoveSectionAction`: Read the file, call `removeSection` to strip the module's section, write the file back, update the manifest's `FileRecord.hash` for that file.
- `RewriteFileAction`: Read the file, evaluate the Dhall function from `src` against the file content, write the result back. (This requires the `DhallEval` effect or a direct Dhall call.)

After all steps, execute removal commands (same pattern as forward commands in the run handler). Then update the manifest.

New types for the plan:

    data RemovalOp
      = DeleteFileOp FilePath RemovalFileStatus
      | StripSectionOp FilePath   -- strip this module's section from the file
      | RewriteOp FilePath FilePath  -- (dest, dhall function source)
      | RemovalCommandOp Text (Maybe FilePath)  -- (command, workDir)

    data RemovalFileStatus = RFSafe | RFConflict | RFGone

    data ExecutedRemovalPlan = ExecutedRemovalPlan
      { targetModule :: ModuleName
      , ops :: [RemovalOp]
      }

Acceptance: `cabal build all` succeeds.


### Milestone 4: CLI Handler Update

At the end of this milestone, `seihou remove` uses the declared removal steps. The output shows each removal operation (delete file, strip section, rewrite file, run command) rather than just a flat file list.

Rewrite `seihou-cli/src/Seihou/CLI/Remove.hs` to:

1. Read manifest, find the module.
2. Extract removal spec from `AppliedModule.removal`. If `Nothing`, error: "module has no removal spec."
3. Build a removal plan from the declared steps — expand `{{var}}` placeholders in `dest` fields using stored `manifest.vars`.
4. For `remove-file` steps, classify the file (safe/conflict/gone) as before.
5. Display the plan with action-specific descriptions:
   - `Delete README.md (unchanged)` for remove-file with safe file
   - `Strip section from .gitignore` for remove-section
   - `Rewrite my-app.cabal` for rewrite-file
   - `Run: cabal clean` for removal commands
6. Handle `--dry-run`, `--force`, conflicts as before.
7. Execute the plan.
8. Update manifest.

Acceptance: `cabal build all`. `seihou remove --help` works. `seihou remove nonexistent` prints appropriate error.

    cabal run seihou -- remove --help


### Milestone 5: Tests

At the end of this milestone, comprehensive tests cover the new removal engine.

Rewrite `seihou-core/test/Seihou/Engine/RemoveSpec.hs`:

1. `computeRemovalPlan` returns error when module has no removal spec (replaces `ModuleNotRemovable`).
2. `computeRemovalPlan` returns error when module is not applied.
3. `executeRemoval` with `RemoveFileAction` deletes the file.
4. `executeRemoval` with `RemoveFileAction` handles conflict (modified file).
5. `executeRemoval` with `RemoveFileAction` handles gone file.
6. `executeRemoval` with `RemoveSectionAction` strips section markers from file.
7. `executeRemoval` with `RemoveSectionAction` leaves file unchanged when no markers found.
8. `executeRemoval` removes module from manifest after all steps.
9. `executeRemoval` preserves other modules' files in manifest.
10. Full round-trip: run a module (populate manifest with removal spec), then remove it.

Add `seihou-core/test/Seihou/Engine/SectionSpec.hs` tests for `removeSection` if not already covered:

1. Removes a section between markers.
2. Leaves content outside markers intact.
3. Handles file with no markers (returns unchanged).
4. Handles multiple sections (only removes the target module's).
5. Cleans up double blank lines after removal.

Acceptance: `cabal test all` passes.

    cabal test all


### Milestone 6: Documentation and Agent Prompts

At the end of this milestone, all documentation and agent context files accurately describe the first-class removal system.

**Files to update:**

1. `docs/cli/remove.md` — Update description to reflect declared removal steps and commands. Show new output format. Document that modules without `removal` cannot be removed.

2. `docs/user/module-authoring.md` — Replace `removable` field reference with `removal` field reference. Rewrite the "Removing modules" section to explain removal steps (`remove-file`, `remove-section`, `rewrite-file`), removal commands, and show example `removal` sections in `module.dhall`. Add examples for each removal action.

3. `docs/user/getting-started.md` — Update "Removing a module" section to reference the new removal system.

4. `docs/dev/design/proposed/cli-commands.md` — Update `seihou remove` spec with new behavior, new output format, new removal step descriptions.

5. `docs/dev/architecture/overview.md` — Mention `RemovalStep`, `Removal` types in the project tree/types section if needed.

6. `docs/user/CHANGELOG.md` — Add entry for this change.

7. `seihou-cli/data/assist-prompt.md` — Update module.dhall format to show `removal` instead of `removable`. Add removal section reference.

8. `seihou-cli/data/bootstrap-prompt.md` — Same as assist-prompt.

9. `seihou-cli/data/setup-prompt.md` — Update available commands to reflect new removal behavior.

10. `seihou-cli/help/modules.md` — Update command reference.

Acceptance: All documentation is internally consistent. `cabal build all` succeeds (agent prompts are embedded data).


### Milestone 7: End-to-End Validation

Manually verify:

1. Create a module with `removal` section: two `remove-file` steps and one `remove-section` step (for `.gitignore`).
2. Run the module. Verify files are created and `.gitignore` has a section with markers.
3. `seihou remove --dry-run` shows the declared removal operations.
4. `seihou remove` executes: files deleted, section stripped from `.gitignore`, manifest updated.
5. `seihou status` shows the module is no longer applied.
6. A module without `removal` (default `None`) cannot be removed — error message shown.
7. Conflict handling: modify a file, then remove — prompt appears.


## Concrete Steps

All commands from the repository root:

    cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou

Build after each milestone:

    cabal build all

Run tests:

    cabal test all

Schema changes in the sibling repo:

    cd /Users/shinzui/Keikaku/bokuno/seihou-project/seihou-schema

Expected `seihou remove --dry-run` output after Milestone 4:

    $ seihou remove haskell-base --dry-run
    Removal plan for haskell-base:

      Delete  README.md (unchanged)
      Delete  src/Lib.hs (unchanged)
      Strip   .gitignore (remove haskell-base section)
      Run     cabal clean

    (dry run — no changes made)


## Validation and Acceptance

The feature is complete when:

1. `cabal build all` compiles cleanly.
2. `cabal test all` passes, including new removal tests.
3. A module with `removal = Some { steps = [...], commands = [...] }` can be run and then removed, with each declared step executed.
4. `remove-file` deletes the module's created files.
5. `remove-section` strips section markers from shared files.
6. `rewrite-file` transforms a file using a Dhall function.
7. Removal commands execute after removal steps.
8. A module without `removal` cannot be removed (clear error).
9. `--dry-run` shows the planned operations without executing.
10. `--force` skips conflict prompts.
11. The manifest is correctly updated after removal.
12. All documentation accurately describes the new system.


## Idempotence and Recovery

Running `seihou remove` on a module not in the manifest is idempotent — it prints an error and exits. Running it after successful removal is similarly safe.

The manifest is written atomically at the end. If removal is interrupted, the manifest remains as-is and the user can re-run. Files already deleted will be classified as gone and skipped.

The Dhall schema change is backwards-compatible for module authors: `removal` defaults to `None`, so existing modules are unaffected. Manifest backwards compatibility is handled by the decoder: old `"removable": true` manifests are interpreted as `Just (Removal [] [])` to preserve basic file-deletion behavior.


## Interfaces and Dependencies

No new library dependencies. Uses existing: `effectful`, `aeson`, `optparse-applicative`, `text`, `containers`, `directory`, `filepath`, `time`. `rewrite-file` may use `dhall` for evaluating text transformation functions.

**New Dhall schema files:**

    seihou-schema/RemovalStep.dhall
    seihou-schema/Removal.dhall

**New/modified Haskell types** in `seihou-core/src/Seihou/Core/Types.hs`:

    data RemovalAction = RemoveFileAction | RemoveSectionAction | RewriteFileAction

    data RemovalStep = RemovalStep
      { action :: RemovalAction
      , dest :: Text
      , src :: Maybe FilePath
      }

    data Removal = Removal
      { removalSteps :: [RemovalStep]
      , removalCommands :: [Command]
      }

    -- Module: removal :: Maybe Removal  (replaces removable :: Bool)
    -- AppliedModule: removal :: Maybe Removal  (replaces removable :: Bool)

**New function** in `seihou-core/src/Seihou/Engine/Section.hs`:

    removeSection :: ModuleName -> Text -> Text -> Text

**Modified module** `seihou-core/src/Seihou/Engine/Remove.hs`:

    computeRemovalPlan :: (Filesystem :> es) => Manifest -> ModuleName -> Eff es (Either RemovalError ExecutedRemovalPlan)
    executeRemoval :: (Filesystem :> es) => Manifest -> ExecutedRemovalPlan -> Set FilePath -> UTCTime -> Eff es Manifest

**New/modified Dhall decoders** in `seihou-core/src/Seihou/Dhall/Eval.hs`:

    removalDecoder :: Decoder Removal
    removalStepDecoder :: Decoder RemovalStep
    removalActionDecoder :: Decoder RemovalAction
