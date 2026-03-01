# CLI Commands

| Field | Value |
|---|---|
| **Status** | Proposed |
| **Created** | 2026-03-01 |
| **Subsystem** | CLI |

## Overview

Seihou exposes seven commands in v1, covering the core generation loop and module authoring experience. The CLI is built with `optparse-applicative` and follows standard Unix conventions for exit codes, error output, and flag parsing.

## Motivation

The CLI is the primary interface to Seihou. It must support:

- The generation workflow (init → run → status)
- Variable inspection and debugging (vars --explain)
- Module acquisition (install) and authoring (new-module, validate-module)
- Non-interactive usage for CI/scripting (--var flags, exit codes)

## Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| CLI framework | optparse-applicative | Standard Haskell, composable, auto-generated --help |
| V1 commands | init, run, vars, install, status, new-module, validate-module | Core loop + authoring experience |
| Variable passing | `--var key=value` | Explicit, composable, scriptable |
| Output format | Human-readable by default | Primary audience is interactive use |
| Dry run | `--dry-run` flag on `run` | Safety net; shows plan without executing |

## Command ADT

```haskell
data Command
  = Init
  | Run RunOpts
  | Vars VarsOpts
  | Install InstallOpts
  | Status
  | NewModule NewModuleOpts
  | ValidateModule ValidateOpts
  deriving stock (Eq, Show, Generic)

data RunOpts = RunOpts
  { runModule     :: ModuleName          -- Primary module
  , runAdditional :: [ModuleName]        -- Additional modules (--module)
  , runVars       :: [(Text, Text)]      -- Variable overrides (--var)
  , runDryRun     :: Bool                -- Show plan only
  , runDiff       :: Bool                -- Show diff against disk
  , runForce      :: Bool                -- Auto-resolve conflicts
  , runNoCommands :: Bool                -- Disable shell commands
  }
  deriving stock (Eq, Show, Generic)

data VarsOpts = VarsOpts
  { varsModule  :: ModuleName
  , varsExplain :: Bool                  -- Show provenance
  , varsVars    :: [(Text, Text)]        -- Variable overrides (for explain context)
  }
  deriving stock (Eq, Show, Generic)

data InstallOpts = InstallOpts
  { installSource :: Text                -- Git URL
  , installName   :: Maybe Text          -- Override module name
  }
  deriving stock (Eq, Show, Generic)

data NewModuleOpts = NewModuleOpts
  { newModuleName :: Text
  , newModulePath :: Maybe FilePath      -- Output directory (default: current dir)
  }
  deriving stock (Eq, Show, Generic)

data ValidateOpts = ValidateOpts
  { validatePath :: Maybe FilePath       -- Module path (default: current dir)
  }
  deriving stock (Eq, Show, Generic)
```

## Command Specifications

### `seihou init`

Initialize Seihou configuration directories.

```sh
seihou init
```

**What it does**:
1. Creates `~/.config/seihou/` if it doesn't exist
2. Creates `~/.config/seihou/config.dhall` with default global config
3. Creates `~/.config/seihou/modules/` directory
4. Creates `~/.config/seihou/installed/` directory
5. Prints confirmation message

**Flags**: None

**Output**:
```text
Initialized Seihou configuration at ~/.config/seihou/
  Created: config.dhall (global defaults)
  Created: modules/ (user modules)
  Created: installed/ (git-installed modules)
```

**Idempotent**: Yes. Re-running `init` skips existing files/directories.

**Exit codes**:
| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Filesystem error |

---

### `seihou run <module>`

Run one or more modules to generate or update a project.

```sh
seihou run <module> [--module <additional>...] [--var key=value...] [--dry-run] [--diff] [--force] [--no-commands]
```

**Arguments**:
| Argument | Required | Description |
|---|---|---|
| `<module>` | Yes | Primary module name or path |
| `--module <name>` | No | Additional modules to compose (repeatable) |
| `--var key=value` | No | Variable override (repeatable) |
| `--dry-run` | No | Show plan without executing |
| `--diff` | No | Show diff against current disk state |
| `--force` | No | Auto-resolve all conflicts (accept new) |
| `--no-commands` | No | Skip RunCommand steps |

**Execution flow**:
1. Resolve module(s) via discovery
2. Build composition graph, topological sort
3. Resolve all variables (prompt for missing required vars)
4. Compile generation plan
5. If manifest exists: compute three-state diff
6. If `--dry-run`: print plan and exit
7. If `--diff`: print diff and exit
8. Show plan to user, prompt for approval
9. Resolve conflicts (or auto-resolve with `--force`)
10. Execute approved operations
11. Update/create manifest

**Output (plan view)**:
```text
Generation Plan (haskell-base + nix-flake):

  Variables:
    project.name    = "my-app"
    project.version = "0.1.0.0"
    license         = "MIT"

  Operations:
    [new]      README.md              (template, haskell-base)
    [new]      my-app.cabal           (dhall-text, haskell-base)
    [new]      src/Lib.hs             (template, haskell-base)
    [new]      app/Main.hs            (template, haskell-base)
    [new]      flake.nix              (dhall-text, nix-flake)
    [new]      .gitignore             (template, nix-flake)

  6 files to write, 0 conflicts

  Proceed? [Y/n]
```

**Exit codes**:
| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Module not found, Dhall evaluation error, validation error |
| 2 | Unresolved required variables (non-interactive mode) |
| 3 | User aborted |
| 4 | Filesystem write error |

---

### `seihou vars <module>`

Inspect resolved variable values for a module.

```sh
seihou vars <module> [--explain] [--var key=value...]
```

**Arguments**:
| Argument | Required | Description |
|---|---|---|
| `<module>` | Yes | Module name or path |
| `--explain` | No | Show provenance for each value |
| `--var key=value` | No | Provide values for resolution context |

**Output (default)**:
```text
Variables for haskell-base:

  project.name     = (required, no default)
  project.version  = "0.1.0.0"
  license          = "MIT"
```

**Output (--explain with --var)**:
```text
seihou vars haskell-base --explain --var project.name=my-app

Variables for haskell-base:

  project.name     = "my-app"          [CLI: --var project.name=my-app]
  project.version  = "0.1.0.0"         [default: module.dhall]
  license          = "BSD-3-Clause"     [namespace: haskell/config.dhall]
```

**Exit codes**:
| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Module not found or load error |

---

### `seihou install <git-url>`

Install a module from a git repository.

```sh
seihou install <git-url> [--name <name>]
```

**Arguments**:
| Argument | Required | Description |
|---|---|---|
| `<git-url>` | Yes | Git repository URL |
| `--name <name>` | No | Override the installed module name |

**What it does**:
1. Clone the git repository to a temporary directory
2. Validate that it contains a valid `module.dhall`
3. Copy to `~/.config/seihou/installed/<name>/`
4. Name defaults to the repository name (last path segment without `.git`)

**Output**:
```text
Installing module from https://github.com/user/haskell-nix-module.git...
  Cloned repository
  Validated module definition
  Installed as: haskell-nix-module

Module available as: haskell-nix-module
```

**Exit codes**:
| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Git clone failed, validation failed |
| 4 | Filesystem error (can't write to install directory) |

---

### `seihou status`

Show the manifest state for the current project.

```sh
seihou status
```

**What it does**:
1. Read `.seihou/manifest.json` from current directory
2. Compare manifest state against disk
3. Display applied modules, tracked files with status, and variable values

**Output**:
```text
Seihou Status:

Applied modules:
  haskell-base    (applied 2026-03-01)
  nix-flake       (applied 2026-03-01)

Tracked files: 6
  README.md           haskell-base   unchanged
  my-app.cabal        haskell-base   unchanged
  src/Lib.hs          haskell-base   modified by user
  app/Main.hs         haskell-base   unchanged
  flake.nix           nix-flake      unchanged
  .gitignore          nix-flake      unchanged

Variables: 4 resolved
```

**Output (no manifest)**:
```sh
No Seihou manifest found. Run 'seihou run <module>' to generate a project.
```

**Exit codes**:
| Code | Meaning |
|---|---|
| 0 | Success (including "no manifest" case) |
| 1 | Manifest corrupted or unreadable |

---

### `seihou new-module <name>`

Scaffold a new module directory with boilerplate.

```sh
seihou new-module <name> [--path <directory>]
```

**Arguments**:
| Argument | Required | Description |
|---|---|---|
| `<name>` | Yes | Module name |
| `--path <dir>` | No | Output directory (default: `./<name>/`) |

**What it generates**:
```text
<name>/
├── module.dhall          # Boilerplate module definition
├── schema/
│   └── Module.dhall      # Type schema
└── files/
    └── README.md.tpl     # Example template file
```

**Generated `module.dhall`**:
```dhall
let Module = ./schema/Module.dhall

in Module::{
  name = "<name>",
  description = Some "TODO: Describe this module",
  vars = [
    { name = "project.name"
    , type = "Text"
    , default = None Text
    , description = Some "Name of the project"
    , required = True
    , validation = None Text
    }
  ],
  exports = [
    { var = "project.name", as = None Text }
  ],
  prompts = [
    { var = "project.name"
    , text = "What is the project name?"
    , when = None Text
    , choices = None (List Text)
    }
  ],
  steps = [
    { strategy = "template"
    , src = "README.md.tpl"
    , dest = "README.md"
    , when = None Text
    }
  ],
  dependencies = [] : List Text
}
```

**Exit codes**:
| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Invalid module name |
| 4 | Directory already exists or filesystem error |

---

### `seihou validate-module [<path>]`

Validate that a module directory is well-formed.

```sh
seihou validate-module [<path>]
```

**Arguments**:
| Argument | Required | Description |
|---|---|---|
| `<path>` | No | Path to module directory (default: current directory) |

**Validation checks** (see [Module System](module-system.md) for full rules):
1. `module.dhall` exists and evaluates successfully
2. Module name is valid (`[a-z][a-z0-9-]*`)
3. All variable names are unique
4. All prompt references point to declared variables
5. All step source files exist in `files/`
6. All exports reference declared variables
7. Step destinations are valid relative paths
8. `when` expressions parse successfully

**Output (valid)**:
```text
Validating module at ./haskell-base/...

  ✓ module.dhall evaluates successfully
  ✓ Module name: haskell-base
  ✓ 3 variables declared
  ✓ 1 prompt defined
  ✓ 4 steps defined
  ✓ All source files exist
  ✓ All exports reference declared variables

Module is valid.
```

**Output (invalid)**:
```text
Validating module at ./broken-module/...

  ✓ module.dhall evaluates successfully
  ✗ Variable 'foo bar' has invalid name (must match [a-z][a-z0-9._-]*)
  ✗ Prompt references undeclared variable: 'missing.var'
  ✗ Step source file not found: files/nonexistent.tpl

3 errors found. Module is invalid.
```

**Exit codes**:
| Code | Meaning |
|---|---|
| 0 | Module is valid |
| 1 | Module is invalid (errors printed to stderr) |
| 4 | Path doesn't exist or module.dhall missing |

## optparse-applicative Parser Tree

```haskell
commandParser :: Parser Command
commandParser = subparser
  ( command "init"
      (info (pure Init) (progDesc "Initialize Seihou configuration"))
  <> command "run"
      (info runParser (progDesc "Run modules to generate a project"))
  <> command "vars"
      (info varsParser (progDesc "Inspect resolved variables"))
  <> command "install"
      (info installParser (progDesc "Install a module from git"))
  <> command "status"
      (info (pure Status) (progDesc "Show manifest state"))
  <> command "new-module"
      (info newModuleParser (progDesc "Scaffold a new module"))
  <> command "validate-module"
      (info validateParser (progDesc "Validate a module"))
  )

runParser :: Parser Command
runParser = fmap Run $ RunOpts
  <$> argument (ModuleName <$> str) (metavar "MODULE")
  <*> many (option (ModuleName <$> str)
        (long "module" <> short 'm' <> metavar "MODULE"
         <> help "Additional module to compose"))
  <*> many (option varPair
        (long "var" <> metavar "KEY=VALUE"
         <> help "Variable override"))
  <*> switch (long "dry-run" <> help "Show plan without executing")
  <*> switch (long "diff" <> help "Show diff against disk")
  <*> switch (long "force" <> help "Auto-resolve conflicts")
  <*> switch (long "no-commands" <> help "Skip shell command steps")

varPair :: ReadM (Text, Text)
varPair = eitherReader $ \s ->
  case T.breakOn "=" (T.pack s) of
    (k, v)
      | T.null k       -> Left "variable name cannot be empty"
      | T.null v       -> Left "expected KEY=VALUE format"
      | otherwise      -> Right (k, T.drop 1 v)
```

## Exit Code Summary

| Code | Meaning | Commands |
|---|---|---|
| 0 | Success | All |
| 1 | Input error (module not found, validation failure, Dhall error) | All |
| 2 | Unresolved required variables in non-interactive mode | run |
| 3 | User aborted | run |
| 4 | Filesystem error | run, install, new-module, validate-module |

## Error Output Conventions

- Errors go to `stderr`
- Normal output goes to `stdout`
- Error messages follow the format: `seihou: error: <message>`
- Warnings follow the format: `seihou: warning: <message>`
- `--dry-run` and `--diff` output goes to `stdout` (for piping)

## Business Rules

- All commands respect `--help` and `--version` (provided by optparse-applicative)
- `run` is interactive by default; non-interactive when all required variables are provided via `--var` or config
- `run` creates `.seihou/` directory if it doesn't exist
- `status` does not modify any state
- `validate-module` does not resolve dependencies (only validates the module itself)
- `install` overwrites an existing module of the same name (with a warning)

## Edge Cases

| Case | Behavior |
|---|---|
| `seihou run` with no arguments | Error: module argument required |
| `seihou run nonexistent` | Error: module not found + list of searched paths |
| `seihou run module --var invalid` | Error: expected KEY=VALUE format |
| `seihou init` when already initialized | Skip existing, print "already initialized" |
| `seihou status` outside a project | "No manifest found" message, exit 0 |
| `seihou install` bad git URL | Error from git clone, exit 1 |
| `seihou new-module` existing directory | Error: directory exists, exit 4 |
| `seihou validate-module /empty/dir` | Error: module.dhall not found, exit 4 |
| Ctrl+C during run | Clean exit, no partial writes (atomic operations) |
| Piped input (non-TTY) | Skip prompts, error on unresolved required variables |

## Testing Plan

| Test | Type | Description |
|---|---|---|
| Command parsing | Unit | Each command parses correct flags/arguments |
| `--var` parsing | Unit | `KEY=VALUE` format accepted, edge cases rejected |
| `init` idempotency | Integration | Running init twice doesn't corrupt state |
| `run` dry-run | Integration | Plan displayed, no files written |
| `run` end-to-end | Integration | Module generated correctly |
| `run` incremental | Integration | Re-run with changed var, only affected files updated |
| `vars` explain | Integration | Provenance correctly displayed |
| `status` display | Integration | File states correctly classified |
| `new-module` scaffold | Integration | Generated module passes validate-module |
| `validate-module` valid | Integration | Valid module reports no errors |
| `validate-module` invalid | Integration | Invalid module reports all errors |
| Exit codes | Integration | Each error condition returns correct exit code |
| Non-interactive mode | Integration | All vars via --var, no prompts, correct behavior |

## Future Enhancements

- `seihou diff <module>` — Show what would change without the full run flow
- `seihou remove <module>` — Remove a module and its orphaned files
- `seihou update <module>` — Update an installed module from git
- `seihou list` — List available modules
- JSON/machine-readable output mode (`--format json`)
- Shell completions (bash, zsh, fish)

## Cross-References

- [Architecture Overview](../../architecture/overview.md) — CLI's role in the pipeline
- [Module System](module-system.md) — Module discovery, loading, validation
- [Variable Resolution](variable-resolution.md) — `vars` command, `--explain`, `--var` flags
- [Manifest and Incrementality](manifest-and-incrementality.md) — `status` command, `--force` flag
- [Generation Strategies](generation-strategies.md) — Strategy displayed in plan output
