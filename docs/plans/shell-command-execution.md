# Wire Shell Command Execution into the Generation Pipeline

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

Module authors often need to run shell commands after file generation — initializing a git repository, running a package manager, formatting generated code, or bootstrapping a build system. Today, modules can only generate files. The `RunCommandOp` operation type exists in the codebase and is handled in dry-run previews, but no module can declare commands and no command is ever executed.

After this change, a module's `module.dhall` can declare a `commands` list of shell commands to run after file generation. When `seihou run` executes a module, it generates files first, then runs each declared command sequentially. Commands support conditional execution via `when` expressions (the same `Expr` system used by steps and prompts) and optional working directories. The `--no-commands` flag (already parsed but unused) suppresses command execution entirely. Command output is streamed to the terminal, and a non-zero exit code halts execution with an error.

The user can verify the change by adding a command to an existing module and running:

    cd seihou
    cabal run seihou -- validate-module seihou-core/test/fixtures/haskell-base
    cabal run seihou -- run haskell-base --var project.name=test-app --dry-run

The dry-run output will show `run` lines for each command. Without `--dry-run`, the commands actually execute.


## Progress

- [x] M1-1: Add `Command` type to `Seihou.Core.Types` and add `moduleCommands` field to `Module`. (2026-03-02)
- [x] M1-2: Add `commandDecoder` to `Seihou.Dhall.Eval` and update `moduleDecoder`. (2026-03-02)
- [x] M1-3: Update all 11 fixture `module.dhall` files to include `commands` field. (2026-03-02)
- [x] M1-4: Update all test files that construct `Module` values to include `moduleCommands = []`. (2026-03-02)
- [x] M1-4b: Update inline Dhall expressions in `EvalSpec.hs` to include `commands` field. (2026-03-02)
- [x] M1-5: Add `checkCommandSafety` validation to `Seihou.Core.Module` and wire into `Seihou.Engine.Validate`. (2026-03-02)
- [x] M1-6: Build and run all tests — all 404 pass. (2026-03-02)
- [x] M2-1: Generate `RunCommandOp` from `moduleCommands` in `Seihou.Engine.Plan.compilePlan`. (2026-03-02)
- [x] M2-2: Execute commands in `handleRun` after file operations, using the `Process` effect. (2026-03-02)
- [x] M2-3: Wire `--no-commands` flag to filter out command operations. (2026-03-02)
- [x] M2-4: Add `command-test` fixture and 9 new tests (5 PlanSpec, 4 ValidateSpec). (2026-03-02)
- [x] M2-5: Build and run all tests — all 413 pass. (2026-03-02)
- [x] M2-6: Manual verification — dry-run shows `run` line, `--no-commands` suppresses it, real run prints command output, validate-module shows "Command safety" check. (2026-03-02)


## Surprises & Discoveries

- `EvalSpec.hs` has two inline Dhall expressions (for patch-op tests) that construct module records directly as strings. These were missed in the M1-4 sweep because M1-4 only covered Haskell `Module` record literals, not Dhall text. The Dhall decoder requires all fields, so these needed `commands` added too. 1 test failed until fixed.


## Decision Log

- Decision: Commands are a top-level `commands` field on the Module type, not a variant of `Step`.
  Rationale: Steps are about file generation (they have `src`, `dest`, `strategy`). Commands are about running processes. Conflating them into one type would require dummy fields and conditional logic. A separate `Command` type and `moduleCommands` field is cleaner and makes the Dhall schema more readable.
  Date: 2026-03-02

- Decision: Commands execute in the CLI layer (`handleRun`), not in the engine's `executePlan`.
  Rationale: The existing comment on `RunCommandOp` in `Execute.hs` says "Command execution is deferred to the CLI layer." The engine's `executePlan` signature returns `Map FilePath FileRecord` and takes `Filesystem :> es` — commands produce no file records and need the `Process` effect. Executing commands separately in the CLI keeps the engine focused on file operations and avoids changing the effect stack of `executePlan`. The `Process` effect with its IO and pure interpreters provides testability.
  Date: 2026-03-02

- Decision: All existing fixture `module.dhall` files must be updated with a `commands` field.
  Rationale: The Dhall decoder uses `field "commands" ...` which requires the field to exist. Making it optional (via `maybe`) would be inconsistent with how all other module fields are decoded — they are all required. Since this is pre-v1, the schema change is acceptable.
  Date: 2026-03-02

- Decision: Non-zero exit from a command halts the pipeline with an error.
  Rationale: Commands are intentional post-generation actions (like `cabal update` or `git init`). If they fail, something is wrong and the user should know immediately. Silent failure would mask real problems. The user can use `when` conditions to make commands conditional or `--no-commands` to skip all commands.
  Date: 2026-03-02


## Outcomes & Retrospective

Implementation completed in two milestones as planned.

**What was delivered:**
- Modules can declare `commands` in `module.dhall` with `run`, `workDir`, and `when` fields.
- `compilePlan` generates `RunCommandOp` for each command whose condition passes, appended after file operations.
- `handleRun` executes commands sequentially after file generation via `sh -c`, streaming stdout and halting on non-zero exit.
- `--no-commands` filters out all command operations from both dry-run preview and real execution.
- `checkCommandSafety` validates empty command text and unsafe workDir paths.
- `validate-module` displays a "Command safety" check in its report.

**Test coverage:** 9 new tests (5 command compilation in PlanSpec, 4 command safety in ValidateSpec). Total tests: 413 (up from 404).

**Surprises:** Inline Dhall expressions in `EvalSpec.hs` needed `commands` field updates — not caught in the initial test sweep since they are string literals, not Haskell `Module` records. Added as M1-4b.

**No new dependencies** were introduced. The existing `Process` effect and `ProcessInterp` provided the IO abstraction cleanly.


## Context and Orientation

The seihou project is a Haskell workspace with two packages: `seihou-core` (library with types, engine, and effects) and `seihou-cli` (executable with command handlers and color rendering). It uses GHC 9.12.2 with GHC2024, the `effectful` library for algebraic effects, and Dhall for module definitions.

A "module" is a directory containing a `module.dhall` file that declares variables, prompts, exports, steps, and dependencies. The `seihou run` command loads modules, resolves variables, compiles a generation plan (a list of `Operation` values), executes the plan to write files, and updates the manifest. The relevant types, files, and execution flow are described below.

The **Module type** is defined in `seihou-core/src/Seihou/Core/Types.hs` (line 153):

    data Module = Module
      { moduleName :: ModuleName,
        moduleDescription :: Maybe Text,
        moduleVars :: [VarDecl],
        moduleExports :: [VarExport],
        modulePrompts :: [Prompt],
        moduleSteps :: [Step],
        moduleCommands :: [Command],
        moduleDependencies :: [ModuleName]
      }

The `moduleCommands` field was added by this plan.

The **Operation type** in the same file (line 156) includes `RunCommandOp`:

    | RunCommandOp
        { opCommand :: Text,
          opWorkDir :: Maybe FilePath
        }

This variant exists but is never generated by `compilePlan` and is stubbed in `executePlan` (line 68 of `seihou-core/src/Seihou/Engine/Execute.hs`):

    RunCommandOp _ _ -> do
      -- Command execution is deferred to the CLI layer.
      pure Nothing

The **Process effect** in `seihou-core/src/Seihou/Effect/Process.hs` provides an effectful abstraction for running shell commands:

    data Process :: Effect where
      RunProcess :: Text -> [Text] -> Maybe FilePath -> Process m (ExitCode, Text, Text)

It has a real IO interpreter in `ProcessInterp.hs` (uses `System.Process.readCreateProcessWithExitCode`) and a pure mock interpreter in `ProcessPure.hs` for testing.

The **plan compilation** in `seihou-core/src/Seihou/Engine/Plan.hs` iterates `moduleSteps` and produces `Operation` values. It never touches commands because the Module type has no commands field.

The **CLI handler** in `seihou-cli/src/Seihou/CLI/Run.hs` parses a `--no-commands` flag into `RunOpts.runNoCommands :: Bool` (line 37 of `Commands.hs`) but never reads it. After `executePlan`, it updates the manifest and reports results.

The **dry-run preview** system already handles `RunCommandOp` — the `buildPreview` function in `Preview.hs` converts it to `CommandPreview cmd`, and the color renderer in `Style.hs` displays it as a dim "run" line. This means dry-run will work automatically once `compilePlan` generates `RunCommandOp` operations.

The **composition merge** in `seihou-core/src/Seihou/Composition/Plan.hs` (line 71) already preserves all `RunCommandOp` operations during multi-module merging without deduplication.

There are **11 fixture `module.dhall` files** under `seihou-core/test/fixtures/` and **11 test source files** that construct `Module` values inline. Both sets need updating when the `Module` type gains a new field.


## Plan of Work

### Milestone 1: Command Type, Dhall Schema, and Validation

This milestone extends the module schema with a `commands` field, adds a Dhall decoder for it, updates all fixtures and test helpers, and adds a validation check for command safety. At the end, the codebase compiles with the new field, all existing tests pass (with `moduleCommands = []` everywhere), and the validate-module command checks command declarations.

The first edit adds a new `Command` type to `seihou-core/src/Seihou/Core/Types.hs`, just after the `Step` type (around line 141). The type has three fields: `cmdRun :: Text` (the shell command string), `cmdWorkDir :: Maybe Text` (optional working directory relative to the target), and `cmdWhen :: Maybe Expr` (optional conditional expression, reusing the same `Expr` AST as steps and prompts). The `Module` type gains a new field `moduleCommands :: [Command]` after `moduleSteps`.

The second edit adds a `commandDecoder` to `seihou-core/src/Seihou/Dhall/Eval.hs`. The Dhall record has fields `run` (Text), `workDir` (optional Text), and `when` (optional Text, parsed via `parseWhen` like steps). The `moduleDecoder` is updated to include `field "commands" (list commandDecoder)`. The forced-evaluation block in `evalModuleFromFile` is extended to force `cmdWhen` thunks in commands.

The third edit updates all 11 fixture `module.dhall` files to include a `commands` field. Most get `commands = [] : List { run : Text, workDir : Optional Text, when : Optional Text }`. The `haskell-base` fixture gets one real command to serve as a test case: `{ run = "echo 'Project generated'", workDir = None Text, when = None Text }`.

The fourth edit updates all test source files that construct `Module` values to include `moduleCommands = []`. This is purely mechanical — every `Module { moduleName = ..., ... }` record literal gains the new field. The affected files are: `PlanSpec.hs`, `ValidateSpec.hs`, `ModuleSpec.hs`, `TypesSpec.hs`, `ResolveSpec.hs`, `GraphSpec.hs`, `PromptSpec.hs`, `CompositionSpec.hs`, `ModuleLoadSpec.hs`, `Validate.hs` (CLI dummy module), and `EvalSpec.hs` (if it constructs modules).

The fifth edit adds a `checkCommandSafety` function to `seihou-core/src/Seihou/Core/Module.hs` and exports it. This function checks: (a) command text is non-empty, and (b) if `workDir` is specified, it must be a safe relative path (no `..`, no absolute paths). The function follows the pattern of `checkSafeDestinations`. The `buildReport` function in `seihou-core/src/Seihou/Engine/Validate.hs` is updated to call `checkCommandSafety` and include the result as a `DiagCheck` with label "Command safety".

Acceptance: `cabal build all` compiles. `cabal test all` passes with the same count as before (all tests still use `moduleCommands = []` so no behavioral change). `cabal run seihou -- validate-module seihou-core/test/fixtures/haskell-base` shows a "Command safety" check passing.


### Milestone 2: Plan Compilation, CLI Execution, and Tests

This milestone wires command generation into the plan compiler, executes commands in the CLI after file operations, respects the `--no-commands` flag, adds a test fixture with commands, and adds unit tests for the new behavior. At the end, commands declared in modules are compiled into `RunCommandOp` operations, shown in dry-run preview, and executed (or suppressed) during real runs.

The first edit adds command compilation to `seihou-core/src/Seihou/Engine/Plan.hs`. After compiling all steps into operations, `compilePlan` appends `RunCommandOp` for each command in `moduleCommands` whose `when` condition is satisfied (or has no condition). The condition is evaluated using the same `evalExpr vars expr` pattern used for steps. The operations are appended after file operations so that commands run after file generation.

The second edit modifies `seihou-cli/src/Seihou/CLI/Run.hs` to execute commands after `executePlan`. After the existing execution block, the handler extracts all `RunCommandOp` operations from the plan, checks the `runNoCommands` flag (if true, skip all commands), and iterates the command list. Each command is executed via `runEff $ runProcessIO $ runProcess cmd [] workDir`. The command text is split into program and arguments using a simple splitting strategy: the first whitespace-delimited token is the program, the rest is passed as a single shell argument via `sh -c` (this ensures shell features like pipes and redirects work). On success (ExitSuccess), the handler continues to the next command. On failure (ExitFailure code), it prints the command, exit code, and stderr to the terminal and calls `exitFailure`.

The third edit adds a new fixture `seihou-core/test/fixtures/command-test/` with a `module.dhall` declaring one variable and two commands: one unconditional (`echo "hello"`) and one conditional (`echo "conditional"` with `when = Some "IsSet project.name"`). The fixture also has a minimal `files/` directory with one template file.

The fourth edit adds tests. In `seihou-core/test/Seihou/Engine/PlanSpec.hs`, new tests verify: (a) commands with no `when` condition produce `RunCommandOp`, (b) commands with a false `when` condition are skipped, (c) commands with a true `when` condition are included, (d) commands appear after file operations in the compiled plan. A new test in `ExecuteSpec.hs` verifies that `executePlan` still returns `Nothing` for `RunCommandOp` (preserving the existing behavior — execution happens in the CLI layer, not the engine).

Acceptance: `cabal build all` compiles. `cabal test all` passes with new tests. Running `cabal run seihou -- run haskell-base --var project.name=test-app --dry-run` shows command lines in the preview output. Manual test with a real execution shows commands running and producing output.


## Concrete Steps

All commands run from `seihou/` (the workspace root).

### Build command

    cabal build all 2>&1

Expected: no errors.

### Test command

    cabal test all 2>&1

Expected: `All N tests passed.` (N will increase from the current 404 by the number of new tests added).

### Format command

    nix fmt 2>&1

Expected: no output (already formatted).

### Manual verification (dry-run with commands)

    cabal run seihou -- run haskell-base --var project.name=test-app --dry-run

Expected output includes command preview lines like:

        run    echo 'Project generated'

### Manual verification (real run, commands execute)

    mkdir /tmp/seihou-cmd-test && cd /tmp/seihou-cmd-test
    cabal run --project-dir=<path-to-seihou> seihou -- run haskell-base --var project.name=test-app

Expected: files are generated and commands print output to the terminal.

### Manual verification (--no-commands)

    cabal run seihou -- run haskell-base --var project.name=test-app --dry-run --no-commands

Expected: same preview but without `run` lines.


## Validation and Acceptance

### Unit Tests

New tests in `PlanSpec.hs` verify command compilation:

1. A module with one unconditional command produces one `RunCommandOp` in the compiled plan.
2. A module with a conditional command (`when = Just expr`) that evaluates to False produces no `RunCommandOp`.
3. A module with a conditional command that evaluates to True produces one `RunCommandOp`.
4. In a compiled plan, all `RunCommandOp` operations appear after all `WriteFileOp` and `CreateDirOp` operations.
5. A command with `cmdWorkDir = Just "subdir"` produces `RunCommandOp` with the correct `opWorkDir`.

New test in `ExecuteSpec.hs` confirms the existing skip behavior is preserved.

New test in `ValidateSpec.hs` verifies:

1. A module with valid commands passes the "Command safety" check.
2. A module with an empty command string fails validation.
3. A module with an absolute `workDir` path fails validation.

### Existing Tests

All existing tests continue to pass. The `Module` type change requires adding `moduleCommands = []` to all existing test module literals, but this is behavioral no-op since empty lists produce no operations.

### Integration Test

The `haskell-base` fixture gains one command. The integration test at `seihou-core/test/Seihou/Integration/GenerationSpec.hs` should still pass since it tests file generation (commands are not executed by `executePlan`).


## Idempotence and Recovery

All changes are additive. The new `Command` type and `moduleCommands` field are new code. Existing `Module` construction sites gain `moduleCommands = []` which preserves existing behavior. The `compilePlan` change appends commands after steps, which is order-preserving. Fixture updates add a new field with an empty list (except `haskell-base` which gets one test command).

If M1 is completed but M2 is not, the codebase compiles and all tests pass — commands are declared but not compiled or executed. This is a safe intermediate state.

The `--no-commands` flag was already parsed and documented in help text. Wiring it to actually suppress commands is the expected behavior.


## Interfaces and Dependencies

### No New External Dependencies

The `process` library is already in `seihou-core.cabal` (line 66: `process >=1.6 && <2`). The `Process` effect and its interpreters already exist. No new packages are needed.

### New Type in seihou-core

In `seihou-core/src/Seihou/Core/Types.hs`, define:

    data Command = Command
      { cmdRun :: Text,
        cmdWorkDir :: Maybe Text,
        cmdWhen :: Maybe Expr
      }
      deriving stock (Eq, Show, Generic)

In the same file, the `Module` type gains:

    moduleCommands :: [Command]

### New Decoder in seihou-core

In `seihou-core/src/Seihou/Dhall/Eval.hs`, add:

    commandDecoder :: Decoder Command

Export it from the module.

### Modified Function in seihou-core

In `seihou-core/src/Seihou/Engine/Plan.hs`, change `compilePlan` to also generate `RunCommandOp` from `moduleCommands`.

### New Validation in seihou-core

In `seihou-core/src/Seihou/Core/Module.hs`, add:

    checkCommandSafety :: Module -> [Text]

Export it.

### Modified Function in seihou-cli

In `seihou-cli/src/Seihou/CLI/Run.hs`, extend `handleRun` to execute commands after file operations using the `Process` effect, skipping them when `runNoCommands` is True.
