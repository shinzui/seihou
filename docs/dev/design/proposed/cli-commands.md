# CLI Commands

| Field | Value |
|---|---|
| **Status** | Implemented |
| **Created** | 2026-03-01 |
| **Updated** | 2026-03-21 |
| **Subsystem** | CLI |

## Overview

Seihou exposes eighteen commands, covering the core generation loop (including module removal), module authoring, configuration management, context management, module discovery, version management, agent-assisted workflows, help, and shell completions. The CLI is built with `optparse-applicative` and follows standard Unix conventions for exit codes, error output, and flag parsing.

## Motivation

The CLI is the primary interface to Seihou. It must support:

- The generation workflow (init → run → status → diff)
- Variable inspection and debugging (vars --explain)
- Configuration management (config set/get/unset/list)
- Module acquisition (install, browse) and authoring (new-module, validate-module)
- Module discovery (list, browse)
- Non-interactive usage for CI/scripting (--var flags, exit codes)

## Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| CLI framework | optparse-applicative | Standard Haskell, composable, auto-generated --help |
| V1 commands | init, run, remove, vars, install, status, diff, list, new-module, validate-module, config, context, browse, outdated, upgrade, agent, help, completions | Core loop + removal + authoring + config + context + discovery + version management + agent + help + completions |
| Variable passing | `--var key=value` | Explicit, composable, scriptable |
| Output format | Human-readable by default | Primary audience is interactive use |
| Dry run | `--dry-run` flag on `run` | Safety net; shows plan without executing |
| Config scopes | `--global`, `--namespace`, `--context` flags on `config` | Matches the multi-tier config hierarchy |
| Context management | `seihou context` subcommand | UX for managing work/personal/team contexts |

## Command ADT

```haskell
data Command
  = Init
  | Run RunOpts
  | Vars VarsOpts
  | Install InstallOpts
  | Status
  | Diff
  | List
  | NewModule NewModuleOpts
  | ValidateModule ValidateOpts
  | Config ConfigOpts
  | Context ContextAction
  | Browse BrowseOpts
  | Outdated OutdatedOpts
  | Upgrade UpgradeOpts
  | Agent AgentOpts
  | HelpCmd HelpCommand
  | Completions CompletionsCommand
  deriving stock (Eq, Show, Generic)

data OutdatedOpts = OutdatedOpts
  { outdatedJson :: Bool                -- JSON output format
  }
  deriving stock (Eq, Show, Generic)

data UpgradeOpts = UpgradeOpts
  { upgradeModules :: [Text]            -- Specific modules to upgrade (empty = all)
  , upgradeDryRun  :: Bool              -- Show what would be upgraded
  , upgradeJson    :: Bool              -- JSON output format
  }
  deriving stock (Eq, Show, Generic)

data AgentOpts = AgentOpts
  { agentDebug   :: Bool                -- Show resolved system prompt
  , agentCommand :: AgentCommand
  }
  deriving stock (Eq, Show, Generic)

data AgentCommand
  = AgentAssist AssistOpts
  | AgentBootstrap BootstrapOpts
  | AgentSetup SetupOpts
  deriving stock (Eq, Show, Generic)

data HelpCommand
  = ListTopics                          -- List all available help topics
  | ShowTopic Text                      -- Show a specific topic
  deriving stock (Eq, Show, Generic)

data CompletionsCommand
  = CompletionsBash
  | CompletionsZsh
  | CompletionsFish
  deriving stock (Eq, Show, Generic)

data RunOpts = RunOpts
  { runModule     :: ModuleName          -- Primary module
  , runAdditional :: [ModuleName]        -- Additional modules (--module)
  , runVars       :: [(Text, Text)]      -- Variable overrides (--var)
  , runDryRun     :: Bool                -- Show plan only
  , runDiff       :: Bool                -- Show diff against disk
  , runForce      :: Bool                -- Auto-resolve conflicts
  , runNoCommands :: Bool                -- Disable shell commands
  , runNamespace  :: Maybe Text          -- Config namespace
  , runContext    :: Maybe Text          -- Context name (work, personal, etc.)
  , runVerbose    :: Bool                -- Verbose output
  }
  deriving stock (Eq, Show, Generic)

data VarsOpts = VarsOpts
  { varsModule    :: ModuleName
  , varsExplain   :: Bool                -- Show provenance
  , varsVars      :: [(Text, Text)]      -- Variable overrides (for explain context)
  , varsNamespace :: Maybe Text          -- Config namespace
  , varsContext   :: Maybe Text          -- Context name
  }
  deriving stock (Eq, Show, Generic)

data InstallOpts = InstallOpts
  { installSource  :: Text               -- Git URL or local path
  , installName    :: Maybe Text         -- Override module name
  , installModules :: [Text]             -- Specific modules from a registry (--module)
  , installAll     :: Bool               -- Install all modules from a registry (--all)
  }
  deriving stock (Eq, Show, Generic)

data NewModuleOpts = NewModuleOpts
  { newModuleName :: Text
  , newModulePath :: Maybe FilePath      -- Output directory (default: current dir)
  }
  deriving stock (Eq, Show, Generic)

data ValidateOpts = ValidateOpts
  { validatePath :: Maybe FilePath       -- Module path (default: current dir)
  , validateLint :: Bool                 -- Enable lint checks
  }
  deriving stock (Eq, Show, Generic)

data ConfigAction
  = ConfigSet Text Text
  | ConfigGet Text
  | ConfigUnset Text
  | ConfigList
  deriving stock (Eq, Show, Generic)

data ConfigOpts = ConfigOpts
  { configAction    :: ConfigAction
  , configGlobal    :: Bool              -- Target global config
  , configNamespace :: Maybe Text        -- Target namespace config
  , configContext   :: Maybe Text        -- Target context config
  , configEffective :: Bool              -- Show merged effective values
  }
  deriving stock (Eq, Show, Generic)

data ContextAction
  = ContextShow
  | ContextSet Text
  | ContextDefault Text
  | ContextClear
  | ContextClearDefault
  deriving stock (Eq, Show, Generic)

data BrowseOpts = BrowseOpts
  { browseSource :: Text                 -- Git URL, local path, or module path
  , browseTag    :: Maybe Text           -- Filter by tag
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
seihou run <module> [--module <additional>...] [--var key=value...] [--dry-run] [--diff] [--force] [--no-commands] [--namespace <ns>] [--context <ctx>] [--verbose]
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
| `--namespace <ns>` | No | Config namespace for variable resolution |
| `--context <ctx>` | No | Context for variable resolution (e.g., work, personal) |
| `--verbose` | No | Verbose output |

**Execution flow**:
1. Resolve module(s) via discovery
2. Build composition graph, topological sort
3. Resolve all variables (prompt for missing required vars interactively)
4. Prompt for optional variables that have prompts defined (interactive only)
5. Compile generation plan
6. If manifest exists: compute three-state diff
7. If `--dry-run`: print plan and exit
8. If `--diff`: print diff and exit
9. Show plan to user, prompt for approval
10. Resolve conflicts (or auto-resolve with `--force`)
11. Execute approved operations
12. Update/create manifest

**Interactive prompt behavior**:

When running interactively, unresolved required variables with prompts are presented first. After all required variables are resolved, optional variables with prompts are presented under an "Optional configuration:" header. Users can skip optional prompts by pressing Enter. Default values are shown in brackets:

```text
What is your project name? my-app
Project version [0.1.0.0]:

Optional configuration:
  Include a license? (MIT/Apache-2.0/BSD-3-Clause) [skip]:
  Enable GitHub Actions CI? (yes/no) [skip]: yes
```

In non-interactive mode (piped input, no TTY), prompts are not shown and missing required variables produce errors.

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

### `seihou remove <module>`

Remove an applied module by executing its declared removal steps.

```sh
seihou remove <module> [--dry-run] [--force] [--verbose]
```

**Arguments**:
| Argument | Required | Description |
|---|---|---|
| `<module>` | Yes | Module name to remove |
| `--dry-run` | No | Show removal plan without executing |
| `--force` | No | Skip confirmation prompts |
| `--verbose` | No | Verbose output |

**Preconditions**:
- A manifest (`.seihou/manifest.json`) must exist.
- The module must appear in the manifest's applied modules list.
- The module must declare a `removal` section (`removal = Some { steps = [...] }`) in its `module.dhall`. Modules with `removal = None` cannot be removed.

**Execution flow**:
1. Read manifest
2. Verify module is applied and has a removal section
3. Build removal plan from the module's declared removal steps
4. Display removal plan showing each operation (Delete, Strip, Rewrite, Run)
5. If `--dry-run`: print plan and exit
6. Prompt for confirmation (unless `--force`)
7. Execute removal steps in order
8. Update manifest (remove module and its file records)
9. Clean up empty parent directories

**Output (removal plan)**:
```text
Removal plan for haskell-base:
  Delete README.md
  Delete src/Lib.hs
  Delete my-app.cabal
  Strip  section from .gitignore

  Proceed? [y/N] y
✓ Removed module haskell-base (3 deleted, 1 stripped).
```

**Exit codes**:
| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Module not applied, no removal section, no manifest found |
| 3 | User aborted |

---

### `seihou vars <module>`

Inspect resolved variable values for a module.

```sh
seihou vars <module> [--explain] [--var key=value...] [--namespace <ns>] [--context <ctx>]
```

**Arguments**:
| Argument | Required | Description |
|---|---|---|
| `<module>` | Yes | Module name or path |
| `--explain` | No | Show provenance for each value |
| `--var key=value` | No | Provide values for resolution context |
| `--namespace <ns>` | No | Config namespace for resolution |
| `--context <ctx>` | No | Context for resolution (e.g., work, personal) |

The `--explain` command is composition-aware: it resolves the full module composition (including all transitive dependencies) and shows how each variable was resolved, including exported values from dependencies.

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

**Diagnostics**: When using `--explain`, optional variables that have no value from any source are listed with a note that they are unresolved. Config keys that don't match any declared variable produce warnings about unused configuration.

**Exit codes**:
| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Module not found or load error |

---

### `seihou install <source>`

Install a module from a git repository or local path. Supports single-module repositories and multi-module registries.

```sh
seihou install <source> [--name <name>] [--module <name>...] [--all]
```

**Arguments**:
| Argument | Required | Description |
|---|---|---|
| `<source>` | Yes | Git repository URL or local path |
| `--name <name>` | No | Override the installed module name |
| `--module <name>` | No | Install specific module(s) from a registry (repeatable) |
| `--all` | No | Install all modules from a registry |

**What it does**:
1. Clone the git repository (or copy from local path) to a temporary directory
2. Check for `seihou-registry.dhall` — if present, treat as a multi-module registry
3. For single-module repos: validate `module.dhall`, copy to installed directory
4. For registries: list available modules, install selected ones
5. Name defaults to the repository name (last path segment without `.git`)
6. Records origin metadata (`.seihou-origin.json`) for tracking

**Output (single module)**:
```text
Installing module from https://github.com/user/haskell-nix-module.git...
  Cloned repository
  Validated module definition
  Installed as: haskell-nix-module

Module available as: haskell-nix-module
```

**Output (registry with --all)**:
```text
Installing from registry at https://github.com/user/haskell-modules.git...
  Cloned repository
  Found registry with 3 modules
  Installed: haskell-base
  Installed: nix-flake
  Installed: github-ci

3 modules installed.
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

### `seihou diff`

Show what would change if the current modules were re-run.

```sh
seihou diff
```

**What it does**:
1. Read `.seihou/manifest.json` from current directory
2. Compute three-state diff: manifest vs plan vs disk
3. Display file-level differences

**Exit codes**:
| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | No manifest found or load error |

---

### `seihou list`

List available modules from all discovery paths.

```sh
seihou list
```

**What it does**:
1. Scan all module search paths (local, user, installed)
2. Display each module with its source location and origin (if installed from git)

**Exit codes**:
| Code | Meaning |
|---|---|
| 0 | Success |

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
seihou validate-module [<path>] [--lint]
```

**Arguments**:
| Argument | Required | Description |
|---|---|---|
| `<path>` | No | Path to module directory (default: current directory) |
| `--lint` | No | Enable lint checks (additional warnings) |

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

---

### `seihou config <action>`

Manage configuration values at different scopes.

```sh
seihou config set <key> <value> [--global] [--namespace <ns>] [--context <ctx>]
seihou config get <key> [--global] [--namespace <ns>] [--context <ctx>]
seihou config unset <key> [--global] [--namespace <ns>] [--context <ctx>]
seihou config list [--global] [--namespace <ns>] [--context <ctx>] [--effective]
```

**Arguments**:
| Argument | Required | Description |
|---|---|---|
| `set <key> <value>` | — | Set a config key to a value |
| `get <key>` | — | Get the current value of a config key |
| `unset <key>` | — | Remove a config key |
| `list` | — | List all config values in the target scope |
| `--global` | No | Target the global config (~/.config/seihou/config.dhall) |
| `--namespace <ns>` | No | Target a namespace config (~/.config/seihou/namespaces/<ns>/config.dhall) |
| `--context <ctx>` | No | Target a context config (~/.config/seihou/contexts/<ctx>/config.dhall) |
| `--effective` | No | Show merged effective values from all scopes (with `list`) |

**Scope resolution**: Without `--global`, `--namespace`, or `--context`, targets the local project config (`.seihou/config.dhall`).

**Output (list)**:
```text
Configuration (.seihou/config.dhall):

  project.name    = "my-app"
  project.version = "0.1.0.0"
```

**Output (list --effective)**:
```text
Effective configuration (merged):

  project.name    = "my-app"           [local]
  project.version = "0.1.0.0"         [global]
  haskell.ghc     = "9.12.2"          [namespace: haskell]
  author.email    = "jane@work.com"  [context: work]
```

**Diagnostics**: When listing config, keys that don't match any declared variable in the current project's modules are flagged as unused.

**Exit codes**:
| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Key not found (get), config file error |

---

### `seihou context`

Manage the active context for variable resolution. Contexts let you maintain separate identities or settings (e.g., "work" vs "personal").

```sh
seihou context show
seihou context set <name>
seihou context default <name>
seihou context clear
seihou context clear-default
```

**Subcommands**:
| Subcommand | Description |
|---|---|
| `show` | Show the active context and where it was resolved from |
| `set <name>` | Set a project-level context (writes `.seihou/context`) |
| `default <name>` | Set a global default context (writes `~/.config/seihou/default-context`) |
| `clear` | Remove the project-level context file |
| `clear-default` | Remove the global default context file |

**Context resolution order** (first match wins):
1. `--context` CLI flag (on `run`, `vars`, `config`)
2. `SEIHOU_CONTEXT` environment variable
3. `.seihou/context` file in the current project directory
4. `~/.config/seihou/default-context` file

**Output (show)**:
```text
Active context: work
  Source: .seihou/context (project)
```

**Output (no context)**:
```text
No active context.
```

**Exit codes**:
| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Invalid context name |

---

### `seihou browse <source>`

Preview modules available in a git repository or registry before installing.

```sh
seihou browse <source> [--tag <tag>]
```

**Arguments**:
| Argument | Required | Description |
|---|---|---|
| `<source>` | Yes | Git URL, local path, or module path |
| `--tag <tag>` | No | Filter modules by tag |

**What it does**:
1. Clone/read the source (or read a local module directory)
2. Check for `seihou-registry.dhall` — if present, show all registered modules
3. For single modules: show module name and description
4. For registries: show all modules with descriptions and tags

**Output (registry)**:
```text
Registry at https://github.com/user/haskell-modules.git

  haskell-base    Base Haskell project scaffold      [haskell, base]
  nix-flake       Nix flake integration              [nix, devops]
  github-ci       GitHub Actions CI setup            [ci, github]

3 modules available. Install with:
  seihou install https://github.com/user/haskell-modules.git --module haskell-base
  seihou install https://github.com/user/haskell-modules.git --all
```

**Output (single module)**:
```text
Module: haskell-base
  Base Haskell project scaffold
```

**Exit codes**:
| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Source not found or not a valid module/registry |

### `seihou outdated`

Check installed modules for newer versions available in their source repositories.

```sh
seihou outdated [--json]
```

**Arguments**:
| Argument | Required | Description |
|---|---|---|
| `--json` | No | Output results as JSON |

**What it does**:
1. Scan `~/.config/seihou/installed/` for installed modules
2. Read `.seihou-origin.json` for each module to find the source URL
3. Clone the remote repository and compare versions
4. Display version comparison table

**Output**:
```text
Module           Installed   Available   Status
haskell-base     1.0.0       1.2.0       outdated
nix-flake        2.1.0       2.1.0       up to date
my-module        —           —           unversioned
```

**Exit codes**:
| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Error reading installed modules or cloning remote |

---

### `seihou upgrade [<module>...]`

Upgrade installed modules to their latest versions from source repositories.

```sh
seihou upgrade [<module>...] [--dry-run] [--json]
```

**Arguments**:
| Argument | Required | Description |
|---|---|---|
| `<module>...` | No | Specific modules to upgrade (default: all installed) |
| `--dry-run` | No | Show what would be upgraded without making changes |
| `--json` | No | Output results as JSON |

**What it does**:
1. For each target module, read `.seihou-origin.json` for source URL
2. Clone the remote repository
3. Validate the remote module
4. Compare versions; if newer, copy the updated module to the installed directory
5. Report status per module

**Output**:
```text
Upgrading installed modules...

  haskell-base    1.0.0 → 1.2.0    upgraded
  nix-flake       2.1.0 → 2.1.0    already up to date
  broken-module   —                 source unreachable

2 checked, 1 upgraded, 1 up to date, 0 failed
```

**Exit codes**:
| Code | Meaning |
|---|---|
| 0 | Success (including partial failures) |
| 1 | Fatal error |

---

### `seihou agent <subcommand>`

Agent-assisted commands for module authoring and project setup, powered by Claude Code.

```sh
seihou agent assist [--prompt <text>] [--debug]
seihou agent bootstrap [--debug]
seihou agent setup [--debug]
```

**Subcommands**:
| Subcommand | Description |
|---|---|
| `assist` | Interactive template authoring assistance |
| `bootstrap` | Bootstrap a new module or repository |
| `setup` | Guided project consumption setup |

**Flags**:
| Flag | Description |
|---|---|
| `--debug` | Show the resolved system prompt |
| `--prompt <text>` | Initial prompt for assist mode |

**Exit codes**:
| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Agent error |

---

### `seihou help [<topic>]`

Display help topics with detailed guidance on specific features.

```sh
seihou help              # list available topics
seihou help <topic>      # show a specific topic
```

**Available topics**: modules, variables, contexts, config, git

**Exit codes**:
| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Unknown topic |

---

### `seihou completions <shell>`

Generate shell completion scripts.

```sh
seihou completions bash
seihou completions zsh
seihou completions fish
```

Output the completion script to stdout. Pipe to a file or source directly:

```sh
seihou completions bash > ~/.local/share/bash-completion/completions/seihou
seihou completions zsh > ~/.zsh/completions/_seihou
seihou completions fish > ~/.config/fish/completions/seihou.fish
```

**Exit codes**:
| Code | Meaning |
|---|---|
| 0 | Success |

## optparse-applicative Parser Tree

```haskell
commandParser :: Parser Command
commandParser = subparser
  ( command "init" initInfo
  <> command "run" runInfo
  <> command "vars" varsInfo
  <> command "install" installInfo
  <> command "status" statusInfo
  <> command "diff" diffInfo
  <> command "list" listInfo
  <> command "new-module" newModuleInfo
  <> command "validate-module" validateInfo
  <> command "config" configInfo
  <> command "context" contextInfo
  <> command "browse" browseInfo
  <> command "outdated" outdatedInfo
  <> command "upgrade" upgradeInfo
  <> command "agent" agentInfo
  <> command "help" helpInfo
  <> command "completions" completionsInfo
  )
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
- `run` prompts for optional variables with defined prompts after required variables are resolved (interactive only)
- `run` creates `.seihou/` directory if it doesn't exist
- `status` does not modify any state
- `validate-module` does not resolve dependencies (only validates the module itself)
- `install` overwrites an existing module of the same name (with a warning)
- `install` detects registries via `seihou-registry.dhall` and supports `--module` and `--all` for selective installation
- `browse` works with both single-module repos and registries
- `config` targets local project config by default; use `--global`, `--namespace`, or `--context` for other scopes
- `context` validates context names (rejects empty, `..`, `/`)

## Edge Cases

| Case | Behavior |
|---|---|
| `seihou run` with no arguments | Error: module argument required |
| `seihou run nonexistent` | Error: module not found + list of searched paths |
| `seihou run module --var invalid` | Error: expected KEY=VALUE format |
| `seihou init` when already initialized | Skip existing, print "already initialized" |
| `seihou status` outside a project | "No manifest found" message, exit 0 |
| `seihou install` bad git URL | Error from git clone, exit 1 |
| `seihou install` registry without `--module` or `--all` | Interactive module selection or error |
| `seihou new-module` existing directory | Error: directory exists, exit 4 |
| `seihou validate-module /empty/dir` | Error: module.dhall not found, exit 4 |
| `seihou config list --effective` no modules | Shows raw config without variable matching |
| `seihou browse` non-module, non-registry | Error: not a valid module or registry |
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
| `run` interactive prompts | Integration | Required and optional prompts displayed correctly |
| `vars` explain | Integration | Provenance correctly displayed |
| `vars` diagnostics | Integration | Unused config keys and unresolved optionals reported |
| `status` display | Integration | File states correctly classified |
| `diff` display | Integration | Three-state diff shown correctly |
| `list` discovery | Integration | Modules from all paths shown |
| `new-module` scaffold | Integration | Generated module passes validate-module |
| `validate-module` valid | Integration | Valid module reports no errors |
| `validate-module` invalid | Integration | Invalid module reports all errors |
| `config` set/get/unset | Integration | Config values persist across commands |
| `config` list --effective | Integration | Merged view shows all scopes |
| `browse` registry | Integration | Registry modules listed with tags |
| `browse` single module | Integration | Module name and description shown |
| `install` single module | Integration | Module cloned, validated, installed |
| `install` from registry | Integration | Selected modules installed |
| Exit codes | Integration | Each error condition returns correct exit code |
| Non-interactive mode | Integration | All vars via --var, no prompts, correct behavior |

## Future Enhancements

- JSON/machine-readable output mode (`--format json`) for all commands

## Cross-References

- [Architecture Overview](../../architecture/overview.md) — CLI's role in the pipeline
- [Module System](module-system.md) — Module discovery, loading, validation
- [Variable Resolution](variable-resolution.md) — `vars` command, `--explain`, `--var` flags
- [Manifest and Incrementality](manifest-and-incrementality.md) — `status` command, `--force` flag
- [Generation Strategies](generation-strategies.md) — Strategy displayed in plan output
