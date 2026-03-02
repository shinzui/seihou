# Implement Remaining CLI Core Commands

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

After this work, all seven `seihou` CLI commands will be functional. Today only `run` and `status` are implemented; the remaining five (`init`, `vars`, `validate-module`, `new-module`, `install`) print "not yet implemented" stubs. After this plan:

- `seihou init` creates the global configuration directory (`~/.config/seihou/`) with subdirectories for modules, installed modules, and a default config file. Running it twice is safe (idempotent).
- `seihou vars haskell-base` displays a module's variable declarations (types, defaults, required flags). Adding `--explain --var project.name=my-app` shows resolved values with provenance.
- `seihou validate-module` checks a module in the current directory (or a given path) against all nine validation rules, reporting each violation.
- `seihou new-module my-template` scaffolds a working module directory with `module.dhall`, a `files/` directory, and an example template.
- `seihou install https://github.com/user/my-module.git` clones a git repository, validates it contains a valid module, and copies it to `~/.config/seihou/installed/`.

Completing these commands closes the M3 (CLI Core) and M6 (Module Authoring) milestones from the project roadmap at `docs/dev/roadmap/v1-milestones.md`.


## Progress

- [x] M1: `init` and `vars` commands (completed 2026-03-01)
  - [x] Create `Seihou.CLI.Init` with `handleInit`
  - [x] Create `Seihou.CLI.Vars` with `handleVars`
  - [x] Wire both handlers into `Main.hs`
  - [x] Update `seihou-cli.cabal` with new modules and dependencies (`directory`)
  - [x] All tests pass (228), `nix fmt` clean, `cabal build all` clean
- [x] M2: `validate-module` command (completed 2026-03-01)
  - [x] Create `Seihou.CLI.Validate` with `handleValidateModule`
  - [x] Wire handler into `Main.hs`
  - [x] All tests pass (228), `nix fmt` clean, `cabal build all` clean
- [x] M3: `new-module` command (completed 2026-03-01)
  - [x] Create `Seihou.CLI.NewModule` with `handleNewModule`
  - [x] Wire handler into `Main.hs`
  - [x] All tests pass (228), `nix fmt` clean, `cabal build all` clean
- [x] M4: Process effect interpreter and `install` command (completed 2026-03-01)
  - [x] Create `Seihou.Effect.ProcessInterp` (real IO interpreter using `System.Process`)
  - [x] Create `Seihou.Effect.ProcessPure` (pure test interpreter with mock responses)
  - [x] Create `Seihou.CLI.Install` with `handleInstall`
  - [x] Wire handler into `Main.hs` (all 7 commands now dispatched to real handlers)
  - [x] Update both `.cabal` files with new modules and dependencies (`process`, `temporary`)
  - [x] All tests pass (228), `nix fmt` clean, `nix flake check` passes


## Surprises & Discoveries

- The `isValidModuleName` function in `Seihou.Core.Module` is not exported, so `NewModule.hs` had to reimplement the same validation logic. A future cleanup could export it from `Seihou.Core.Module` or move it to a shared utility.
- The `Install` handler uses `System.Process.readProcessWithExitCode` directly (raw IO) rather than the Process effect, since the CLI handlers run in raw IO. The Process effect and its interpreters are still available for use in the effectful pipeline (e.g., for `RunCommandOp` execution in the future).
- Removing all stub implementations from `Main.hs` also removed the `Data.Text qualified as T` import — Main.hs is now a clean dispatcher with no direct text manipulation.


## Decision Log

- Decision: Scope this plan to the five remaining CLI commands. The `run` and `status` commands are already fully implemented (see `docs/plans/filesystem-execution-and-manifest-tracking.md`).
  Rationale: Avoids re-implementing what already works. The existing `handleRun` and `handleStatus` are tested and functional.
  Date: 2026-03-01

- Decision: Defer interactive prompts (Console effect interpreter) and config file loading (ConfigReader effect interpreter) to a future plan. The `vars` and `run` commands work without them by using `--var` overrides and environment variables. Missing required variables produce clear error messages telling the user what to provide.
  Rationale: Interactive prompts require TTY detection, readline-style input, and test harnesses for simulating user interaction. This is substantial work orthogonal to making the five commands functional. Config file loading similarly requires Dhall-to-map parsing logic that adds complexity. Both can be layered on later without changing the command interfaces.
  Date: 2026-03-01

- Decision: Defer Logger effect interpreter. Current handlers use `Data.Text.IO.putStrLn` directly, which is adequate for v1. Logger would add structured levels and stderr routing but is not required by any of the five commands.
  Rationale: Adding Logger to every handler increases the effect stack complexity without user-visible benefit for v1. It can be added later as a cross-cutting concern.
  Date: 2026-03-01

- Decision: The `new-module` scaffold omits the `schema/Module.dhall` directory mentioned in the design doc. The generated module contains only `module.dhall` and `files/README.md.tpl`.
  Rationale: No existing module uses a `schema/` directory (the `haskell-base` fixture does not have one). The type schema for modules is implicit in the Dhall evaluator. Adding it would require maintaining a separate type definition file with no current consumer. It can be added later if module authoring documentation calls for it.
  Date: 2026-03-01

- Decision: The `install` handler uses `System.Process.readProcessWithExitCode` directly for git clone rather than going through the Process effect and its interpreter.
  Rationale: All CLI handlers run in raw IO, not in the effectful pipeline. Introducing the effect stack just for one `git clone` call would add unnecessary complexity. The Process effect and its interpreters (`ProcessInterp`, `ProcessPure`) remain available for the effectful engine (e.g., for `RunCommandOp` execution in a future milestone).
  Date: 2026-03-01

- Decision: The `vars` command default output (without `--explain`) shows variable declarations from the module definition: name, type, default, required flag. It does not attempt variable resolution. The `--explain` mode attempts resolution using provided `--var` overrides and environment variables, and shows provenance for each resolved value. If resolution fails (missing required variables), the errors are displayed.
  Rationale: Showing declarations without resolution is the most useful default — it answers "what variables does this module need?" without requiring the user to provide values. The `--explain` mode answers "where did each value come from?" which requires actual resolution.
  Date: 2026-03-01


## Outcomes & Retrospective

All four milestones completed. All seven CLI commands now dispatch to real handlers — no stubs remain.

**New files created (8)**:
- `seihou-cli/src/Seihou/CLI/Init.hs` — idempotent XDG directory creation + default config.dhall
- `seihou-cli/src/Seihou/CLI/Vars.hs` — variable declaration display and `--explain` provenance mode
- `seihou-cli/src/Seihou/CLI/Validate.hs` — module validation against all nine rules
- `seihou-cli/src/Seihou/CLI/NewModule.hs` — module scaffolding with working module.dhall + template
- `seihou-cli/src/Seihou/CLI/Install.hs` — git clone, validate, copy to installed/
- `seihou-core/src/Seihou/Effect/ProcessInterp.hs` — real IO interpreter for Process effect
- `seihou-core/src/Seihou/Effect/ProcessPure.hs` — pure mock interpreter for Process effect

**Files modified (3)**:
- `seihou-cli/src/Main.hs` — all 7 commands dispatched, no stubs
- `seihou-cli/seihou-cli.cabal` — 5 new modules, 3 new dependencies
- `seihou-core/seihou-core.cabal` — 2 new modules, 1 new dependency

**Test count**: 228 (unchanged — these are read-only or IO-bound commands; existing core tests cover the underlying logic). The `ProcessPure` interpreter is available for future tests that need to mock subprocess calls.

**Known limitations**:
- `init` does not check `$XDG_CONFIG_HOME` explicitly (delegates to `getXdgDirectory` which handles it)
- `install` uses raw `readProcessWithExitCode` rather than the Process effect (effect stack not wired into CLI handlers)
- `new-module` duplicates `isValidModuleName` from `Seihou.Core.Module` (not exported)
- No new automated tests were added for CLI handlers (they are thin IO wrappers over tested core functions)


## Context and Orientation

### Project Structure

Seihou is a multi-package Haskell workspace using GHC 9.12.2 with GHC2024 language standard:

    seihou/
    ├── cabal.project              # Workspace root listing both packages
    ├── seihou-core/               # Library: types, effects, engines
    │   ├── seihou-core.cabal
    │   ├── src/
    │   │   ├── Seihou/Core/       # Types.hs, Module.hs, Expr.hs, Variable.hs
    │   │   ├── Seihou/Dhall/      # Eval.hs
    │   │   ├── Seihou/Effect/     # Filesystem(.hs,Interp,Pure), ManifestStore(.hs,Interp,Pure),
    │   │   │                      # Console.hs, Logger.hs, DhallEval.hs, DhallEvalInterp.hs,
    │   │   │                      # ConfigReader.hs, Process.hs
    │   │   ├── Seihou/Engine/     # Plan.hs, Template.hs, Execute.hs, Diff.hs
    │   │   └── Seihou/Manifest/   # Types.hs, Hash.hs
    │   └── test/                  # 16 test modules, 228 passing tests
    │       ├── Main.hs
    │       ├── Seihou/            # Unit and integration tests
    │       └── fixtures/          # haskell-base/, invalid-module/
    ├── seihou-cli/                # Executable: CLI entry point
    │   ├── seihou-cli.cabal
    │   └── src/
    │       ├── Main.hs            # Command dispatch
    │       └── Seihou/CLI/        # Commands.hs, Run.hs, Status.hs
    └── flake.nix                  # GHC 9.12.2, treefmt, pre-commit hooks

### What Already Works

The full generation pipeline is implemented and tested (228 tests pass): module loading from Dhall, variable resolution with three-layer precedence (CLI > environment > module default), template rendering with placeholder substitution, plan compilation for Copy/Template/DhallText strategies, execution engine converting operations to filesystem writes, manifest persistence as JSON, and three-state diff (manifest vs plan vs disk) for incrementality.

The CLI parser in `seihou-cli/src/Seihou/CLI/Commands.hs` defines all seven commands with their option types. The `seihou run` and `seihou status` commands are fully implemented in `seihou-cli/src/Seihou/CLI/Run.hs` and `seihou-cli/src/Seihou/CLI/Status.hs` respectively. The remaining five commands print stub messages.

### Key Functions and Types Used by This Plan

In `seihou-core/src/Seihou/Core/Module.hs`:
- `discoverModule :: [FilePath] -> ModuleName -> IO (Either ModuleLoadError FilePath)` — finds a module directory in the search paths
- `loadModule :: [FilePath] -> ModuleName -> IO (Either ModuleLoadError Module)` — discovers, evaluates Dhall, and validates
- `validateModule :: FilePath -> Module -> IO (Either ModuleLoadError Module)` — runs nine validation rules
- `defaultSearchPaths :: IO [FilePath]` — returns `.seihou/modules/`, `~/.config/seihou/modules/`, `~/.config/seihou/installed/`

In `seihou-core/src/Seihou/Core/Variable.hs`:
- `resolveVariables :: [VarDecl] -> Map VarName Text -> Map Text Text -> Either [VarError] (Map VarName ResolvedVar)` — three-layer resolution
- `formatExplain :: Map VarName ResolvedVar -> Text` — provenance report for `--explain`

In `seihou-core/src/Seihou/Dhall/Eval.hs`:
- `evalModuleFromFile :: FilePath -> IO (Either ModuleLoadError Module)` — evaluates a `module.dhall` file

In `seihou-core/src/Seihou/Effect/Process.hs` (interface only, no interpreter yet):
- `data Process :: Effect where RunProcess :: Text -> [Text] -> Maybe FilePath -> Process m (ExitCode, Text, Text)`

In `seihou-cli/src/Seihou/CLI/Commands.hs`:
- `Command` ADT with seven constructors: `Init`, `Run RunOpts`, `Vars VarsOpts`, `Install InstallOpts`, `Status`, `NewModule NewModuleOpts`, `ValidateModule ValidateOpts`
- `VarsOpts` has fields: `varsModule :: ModuleName`, `varsExplain :: Bool`, `varsVars :: [(Text, Text)]`
- `InstallOpts` has fields: `installSource :: Text`, `installName :: Maybe Text`
- `NewModuleOpts` has fields: `newModuleName :: Text`, `newModulePath :: Maybe FilePath`
- `ValidateOpts` has fields: `validatePath :: Maybe FilePath`

### Terminology

- **Module**: A directory containing `module.dhall` and a `files/` subdirectory with source templates. The Dhall file declares variables, steps, and metadata.
- **Search paths**: The three directories where `discoverModule` looks for modules: `.seihou/modules/` (project-local), `~/.config/seihou/modules/` (user modules), `~/.config/seihou/installed/` (git-installed modules).
- **XDG config directory**: `~/.config/seihou/` (or `$XDG_CONFIG_HOME/seihou/` if the environment variable is set). Determined by `System.Directory.getXdgDirectory XdgConfig "seihou"`.
- **Effect**: An `effectful` dynamic dispatch effect — a GADT describing operations that are interpreted by a handler at runtime.
- **Interpreter**: An `effectful` handler giving runtime meaning to an effect (e.g., real IO vs in-memory for testing).

### Build and Test Commands

All commands run from the workspace root (`seihou/`):

    cabal build all          # Build both packages
    cabal test all           # Run all tests
    nix fmt                  # Format with treefmt (fourmolu + cabal-gild)
    nix flake check          # Full CI: build + test + formatting


## Plan of Work

### Milestone 1: `init` and `vars` Commands

This milestone implements the two simplest remaining commands and completes the M3 (CLI Core) roadmap milestone. At the end, `seihou init` creates the global configuration directory structure, and `seihou vars <module>` displays a module's variable declarations with optional provenance via `--explain`.

**`seihou init`** creates the XDG config directory (`~/.config/seihou/`) with three subdirectories: `modules/` (for local module development), `installed/` (for git-installed modules), and `namespaces/` (for future namespace configuration). It also writes a default `config.dhall` file if one does not exist. The command is idempotent: re-running it does not error or overwrite existing files. Output reports what was created versus what already existed.

Create `seihou-cli/src/Seihou/CLI/Init.hs` with a `handleInit :: IO ()` function. The handler uses `System.Directory.getXdgDirectory XdgConfig "seihou"` to find the base path, then calls `createDirectoryIfMissing True` for each subdirectory. For the config file, it checks `doesFileExist` before writing. Each action prints a status line: "Created ~/.config/seihou/modules/" or "Already exists: ~/.config/seihou/modules/".

The default `config.dhall` should contain a comment explaining the format and an empty Dhall record (`{=}`):

    -- Seihou global configuration
    -- Add variable defaults that apply to all modules.
    -- Example: { `project.name` = "my-app", `license` = "MIT" }
    {=}

**`seihou vars <module>`** has two modes. The default mode loads the module and displays its variable declarations in a table format showing name, type, default value (or "required"), and description. This does not attempt variable resolution — it answers "what variables does this module need?" The `--explain` mode attempts resolution using `--var` overrides and environment variables, then displays each variable's resolved value with its provenance source (CLI, environment, default).

Create `seihou-cli/src/Seihou/CLI/Vars.hs` with a `handleVars :: VarsOpts -> IO ()` function. For default mode, the handler calls `loadModule` to get the `Module`, then formats `moduleVars` as a list. For `--explain` mode, it additionally calls `resolveVariables` with the provided `--var` overrides and the process environment, then calls `formatExplain` (already implemented in `Seihou.Core.Variable`). If resolution fails, it prints the errors and exits with code 1.

Update `seihou-cli/src/Main.hs` to dispatch `Init` to `handleInit` and `Vars` to `handleVars`. Add the new modules to `seihou-cli.cabal` `other-modules` and add the `directory` dependency (needed by `handleInit` for `getXdgDirectory` and `createDirectoryIfMissing`).

**Acceptance**: `cabal build all` succeeds. `cabal run seihou -- init` creates `~/.config/seihou/` with subdirectories and config file. Running it again reports all directories already exist. `cabal run seihou -- vars haskell-base` (with the fixture in `.seihou/modules/`) displays variable declarations. `cabal run seihou -- vars haskell-base --explain --var project.name=my-app` shows provenance.


### Milestone 2: `validate-module` Command

This milestone adds the module validation command. At the end, running `seihou validate-module` in a directory containing `module.dhall` reports whether the module is valid and lists any violations.

**`seihou validate-module [<path>]`** validates a module at the given path (defaulting to the current directory). It first checks that `module.dhall` exists, then evaluates it via Dhall, and finally runs the nine validation rules from `Seihou.Core.Module.validateModule`. If the module is valid, it prints "Module '<name>' is valid." and exits with code 0. If invalid, it lists each error and prints "N error(s) found. Module is invalid." and exits with code 1. If `module.dhall` does not exist or Dhall evaluation fails, it reports the error and exits with code 1.

Create `seihou-cli/src/Seihou/CLI/Validate.hs` with `handleValidateModule :: ValidateOpts -> IO ()`. The handler determines the module path from `validatePath` (default: current directory), constructs the Dhall file path as `path </> "module.dhall"`, calls `evalModuleFromFile` to decode it, and then `validateModule` to check all rules. The display separates "load errors" (file not found, Dhall parse error) from "validation errors" (name format, duplicate vars, missing files, etc.).

Update `Main.hs` to dispatch `ValidateModule` to `handleValidateModule`. Add the new module to `seihou-cli.cabal`.

**Acceptance**: `cabal build all` succeeds. Running `cd seihou-core/test/fixtures/haskell-base && cabal run seihou -- validate-module` reports the module is valid. Running on `seihou-core/test/fixtures/invalid-module` reports validation errors. Running in an empty directory reports "module.dhall not found".


### Milestone 3: `new-module` Command

This milestone adds module scaffolding. At the end, `seihou new-module my-template` creates a working module directory that passes validation.

**`seihou new-module <name> [--path <dir>]`** creates a new module directory. The name must match the module naming pattern `[a-z][a-z0-9-]*`. The output directory defaults to `./<name>/` but can be overridden with `--path`. The command creates:

    <name>/
    ├── module.dhall          # Working module with one example variable and step
    └── files/
        └── README.md.tpl     # Example template using the variable

The generated `module.dhall` contains a complete working module definition with one text variable (`project.name`), one prompt, and one template step that generates `README.md`. The generated `files/README.md.tpl` contains `# {{project.name}}` followed by a newline and a description line. This ensures that running `seihou validate-module` on the scaffolded module succeeds, and `seihou run <name> --var project.name=test` produces output.

Create `seihou-cli/src/Seihou/CLI/NewModule.hs` with `handleNewModule :: NewModuleOpts -> IO ()`. The handler validates the module name format (reusing the `[a-z][a-z0-9-]*` pattern), checks that the target directory does not already exist, creates the directory structure, and writes the template files. If the directory already exists, it reports an error and exits with code 1.

Update `Main.hs` and `seihou-cli.cabal`.

**Acceptance**: `cabal build all` succeeds. `cabal run seihou -- new-module test-mod` creates `test-mod/` with `module.dhall` and `files/README.md.tpl`. Running `cabal run seihou -- validate-module test-mod` reports the module is valid. Running `cabal run seihou -- new-module test-mod` again reports the directory already exists.


### Milestone 4: Process Effect Interpreter and `install` Command

This milestone implements the Process effect interpreter (for running external commands like `git`) and the `install` command that uses it to install modules from git repositories.

**Process effect interpreter** (`seihou-core/src/Seihou/Effect/ProcessInterp.hs`) provides `runProcess :: (IOE :> es) => Eff (Process : es) a -> Eff es a`, which delegates `RunProcess` to `System.Process.readCreateProcessWithExitCode`. This is the real IO interpreter. A pure test interpreter (`seihou-core/src/Seihou/Effect/ProcessPure.hs`) is also created, using a map of expected command invocations to canned responses, enabling unit tests without real subprocesses.

**`seihou install <git-url> [--name <name>]`** installs a module from a git repository. The flow is: parse the module name from the URL (last path segment of the URL, stripping any trailing `.git`), allow override via `--name`; create a temporary directory; run `git clone <url> <temp>/<name>`; validate the cloned module by checking for `module.dhall` and running `evalModuleFromFile` + `validateModule`; if valid, copy the module directory to `~/.config/seihou/installed/<name>/`; clean up the temporary directory. If the target already exists, the command reports an error (the user must remove it manually first).

Create `seihou-core/src/Seihou/Effect/ProcessInterp.hs` and `seihou-core/src/Seihou/Effect/ProcessPure.hs`. Add `process` (boot library, for `System.Process`) to `seihou-core.cabal` dependencies and add both modules to `exposed-modules`. Create `seihou-cli/src/Seihou/CLI/Install.hs` with `handleInstall :: InstallOpts -> IO ()`. Add `temporary` to `seihou-cli.cabal` for `System.IO.Temp.withSystemTempDirectory`. Update `Main.hs` and both `.cabal` files.

**Acceptance**: `cabal build all` succeeds. `cabal test all` passes (including any new Process effect tests). `nix fmt` and `nix flake check` pass. Manual test: `cabal run seihou -- install https://github.com/<user>/<repo>.git` clones and installs the module (requires a real git repository with a valid `module.dhall`). `cabal run seihou -- install https://github.com/<user>/<repo>.git` again reports the module is already installed.


## Concrete Steps

Commands are run from the workspace root: `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou/`.

### Milestone 1

    # After creating Init.hs, Vars.hs, updating Main.hs and cabal:
    cabal build all
    # Expected: compiles cleanly

    cabal run seihou -- init
    # Expected: Creates ~/.config/seihou/ with modules/, installed/, namespaces/, config.dhall

    cabal run seihou -- init
    # Expected: "Already exists" messages for all directories

    # Copy fixture to a discoverable location for testing vars:
    cabal run seihou -- vars haskell-base
    # Expected: Lists project.name (required), project.version (default "0.1.0.0"), license (default "MIT")
    # Note: This requires haskell-base to be in a search path. For manual testing,
    #       create .seihou/modules/haskell-base/ as a symlink or copy.

### Milestone 2

    cabal build all
    # Expected: compiles cleanly

    cabal run seihou -- validate-module seihou-core/test/fixtures/haskell-base
    # Expected: "Module 'haskell-base' is valid."

    cabal run seihou -- validate-module seihou-core/test/fixtures/invalid-module
    # Expected: Lists validation errors, "Module is invalid."

    cabal run seihou -- validate-module /nonexistent
    # Expected: Error about module.dhall not found

### Milestone 3

    cabal build all
    # Expected: compiles cleanly

    cabal run seihou -- new-module test-scaffold
    # Expected: Creates test-scaffold/ with module.dhall and files/README.md.tpl

    cabal run seihou -- validate-module test-scaffold
    # Expected: "Module 'test-scaffold' is valid."

    cabal run seihou -- new-module test-scaffold
    # Expected: Error that directory already exists

    # Cleanup:
    rm -rf test-scaffold

### Milestone 4

    cabal build all
    cabal test all
    # Expected: compiles and all tests pass

    nix fmt
    nix flake check
    # Expected: formatting clean, checks pass


## Validation and Acceptance

### `init` Command

Running `seihou init` for the first time creates `~/.config/seihou/` with `modules/`, `installed/`, `namespaces/` subdirectories and a `config.dhall` file. Each created item prints "Created <path>". Running it again prints "Already exists: <path>" for each item and exits with code 0.

### `vars` Command

Running `seihou vars haskell-base` displays the three variables from the haskell-base fixture: `project.name` (text, required, no default), `project.version` (text, optional, default "0.1.0.0"), `license` (text, optional, default "MIT"). Running `seihou vars haskell-base --explain --var project.name=my-app` shows all three variables with their resolved values and sources (CLI, default). Running `seihou vars nonexistent` exits with code 1 and reports the module was not found.

### `validate-module` Command

Running `seihou validate-module seihou-core/test/fixtures/haskell-base` reports the module is valid. Running on `seihou-core/test/fixtures/invalid-module` reports specific validation errors and exits with code 1.

### `new-module` Command

Running `seihou new-module my-template` creates a valid module directory. Immediately running `seihou validate-module my-template` confirms it passes validation. Running `seihou new-module INVALID_NAME` reports an invalid module name error.

### `install` Command

Running `seihou install <valid-git-url>` clones the repository, validates the module, and copies it to `~/.config/seihou/installed/<name>/`. Running it again on the same URL reports the module is already installed.

### Automated Tests

All 228 existing tests continue to pass. Any new tests added for the Process effect interpreter also pass. The full validation is:

    cabal test all
    nix fmt
    nix flake check


## Idempotence and Recovery

- **`init` is idempotent by design**: Uses `createDirectoryIfMissing` and checks file existence before writing. Re-running creates nothing and produces no errors.
- **`vars` and `validate-module` are read-only**: They do not modify any files.
- **`new-module` checks existence first**: If the target directory exists, it reports an error rather than overwriting. Safe to retry after removing the directory.
- **`install` checks existence first**: If the installed module directory exists, it reports an error. The temporary clone directory is cleaned up automatically via `withSystemTempDirectory`. If the process is killed during installation, only the temp directory may be left behind (cleaned up by the OS eventually).
- **All milestones are additive**: Each adds new files without modifying existing handler logic (except dispatch in `Main.hs`). If a milestone fails mid-way, previously passing tests still pass.


## Interfaces and Dependencies

### New Package Dependencies

For `seihou-core`:

| Package | Version | Purpose |
|---|---|---|
| `process` | (boot library) | `System.Process` for the Process effect interpreter |

For `seihou-cli`:

| Package | Version | Purpose |
|---|---|---|
| `directory` | `>=1.3 && <2` | Already present; used by `init` for `getXdgDirectory`, `createDirectoryIfMissing` |
| `temporary` | `>=1.3 && <2` | `System.IO.Temp` for temp directory in `install` |

### New Modules

**`seihou-cli/src/Seihou/CLI/Init.hs`**

    module Seihou.CLI.Init (handleInit) where

    handleInit :: IO ()

**`seihou-cli/src/Seihou/CLI/Vars.hs`**

    module Seihou.CLI.Vars (handleVars) where

    handleVars :: VarsOpts -> IO ()

**`seihou-cli/src/Seihou/CLI/Validate.hs`**

    module Seihou.CLI.Validate (handleValidateModule) where

    handleValidateModule :: ValidateOpts -> IO ()

**`seihou-cli/src/Seihou/CLI/NewModule.hs`**

    module Seihou.CLI.NewModule (handleNewModule) where

    handleNewModule :: NewModuleOpts -> IO ()

**`seihou-cli/src/Seihou/CLI/Install.hs`**

    module Seihou.CLI.Install (handleInstall) where

    handleInstall :: InstallOpts -> IO ()

**`seihou-core/src/Seihou/Effect/ProcessInterp.hs`**

    module Seihou.Effect.ProcessInterp (runProcess) where

    runProcess :: (IOE :> es) => Eff (Process : es) a -> Eff es a

Note: The function name `runProcess` shadows the smart constructor from `Seihou.Effect.Process`. The interpreter should use a distinct name such as `runProcessIO` to avoid ambiguity when both are imported.

**`seihou-core/src/Seihou/Effect/ProcessPure.hs`**

    module Seihou.Effect.ProcessPure (runProcessPure, ProcessMock (..)) where

    data ProcessMock = ProcessMock
      { mockCommand :: Text
      , mockArgs :: [Text]
      , mockResult :: (ExitCode, Text, Text)
      }

    runProcessPure :: [ProcessMock] -> Eff (Process : es) a -> Eff es a

### Modified Files

- `seihou-cli/src/Main.hs` — Add imports and dispatch for all five new handlers
- `seihou-cli/seihou-cli.cabal` — Add new modules to `other-modules`, add `temporary` dependency
- `seihou-core/seihou-core.cabal` — Add `process` dependency, add `ProcessInterp` and `ProcessPure` to `exposed-modules`
