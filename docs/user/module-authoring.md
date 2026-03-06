# Module Authoring Reference

This document is the complete reference for creating Seihou modules. For a hands-on walkthrough, see the [Getting Started Guide](getting-started.md).


## Module structure

A Seihou module is a directory containing a `module.dhall` file and a `files/` subdirectory:

```
my-module/
├── module.dhall          # Required: module definition
├── schema/               # Optional: Dhall type definitions
│   └── Module.dhall
└── files/                # Source artifacts referenced by steps
    ├── README.md.tpl     # Template strategy
    ├── LICENSE            # Copy strategy
    ├── config.dhall       # DhallText strategy
    └── package.yaml.gen   # Structured strategy
```

The `module.dhall` file is the only required file. The `files/` directory contains the source artifacts that steps reference. File extensions (`.tpl`, `.dhall`, `.gen`) are conventions — the `strategy` field in each step determines how the file is processed.

Module names must match `[a-z][a-z0-9-]*`: lowercase letters and hyphens, starting with a letter.


## The module.dhall format

The module definition is a Dhall record with these fields:

```dhall
{ name = "my-module"
, description = Some "What this module does"
, vars = [ ... ]
, exports = [ ... ]
, prompts = [ ... ]
, steps = [ ... ]
, commands = [ ... ]
, dependencies = [ ... ]
}
```

### Field reference

**name** (Text, required): The module identifier. Must match `[a-z][a-z0-9-]*`.

**description** (Optional Text): Human-readable description shown by `seihou list` and in validation output. Use `Some "description"` or `None Text`.

**vars** (List): Variable declarations. See [Variables](#variables) below.

**exports** (List): Variables to share with dependent modules. See [Variable exports](#variable-exports).

**prompts** (List): Interactive prompts for missing values. See [Prompts](#prompts).

**steps** (List): File generation operations. See [Steps and strategies](#steps-and-strategies).

**commands** (List): Shell commands to run after generation. See [Commands](#commands).

**dependencies** (List Text): Module names this module depends on. See [Dependencies and composition](#dependencies-and-composition).


## Variables

Each variable declaration has these fields:

```dhall
{ name = "project.name"
, type = "text"
, default = None Text
, description = Some "Name of the project"
, required = True
, validation = Some "[a-z][a-z0-9-]*"
}
```

### Variable types

| Type | Description | Example values |
|------|-------------|----------------|
| `text` | String value | `"my-app"`, `"MIT"` |
| `bool` | Boolean | `"true"`, `"false"`, `"yes"`, `"no"`, `"1"`, `"0"` |
| `int` | Integer | `"42"`, `"0"`, `"-1"` |
| `list` | Comma-separated list | `"base,text,containers"` |
| `choice` | Restricted text | Must be one of the values in `prompts.choices` |

All values are stored as text internally. Type declarations control validation and how values are substituted in templates:

- **bool**: Substituted as `"true"` or `"false"` in templates
- **int**: Substituted as the decimal representation
- **list**: Substituted as comma-separated values

### Required vs optional

- `required = True`: The variable must have a value from some source (CLI, config, prompt, default). If no value is found and the module is run non-interactively, generation fails.
- `required = False`: The variable may be absent. Steps with `when` conditions can test for it with `IsSet`.

### Defaults

- `default = Some "value"`: Provides a fallback value (lowest precedence in the resolution chain).
- `default = None Text`: No default. The value must come from another source.

### Validation

- `validation = Some "[a-z][a-z0-9-]*"`: A regex pattern the value must match. Applied regardless of the value's source.
- `validation = None Text`: No validation.

For `int` variables, you can specify a range: `validation = Some "0:100"` (min:max).


## Prompts

Prompts ask the user for variable values interactively when a value is not provided via CLI flags, environment variables, or configuration:

```dhall
{ var = "project.name"
, text = "What is your project name?"
, when = None Text
, choices = None (List Text)
}
```

### Fields

**var** (Text): The variable name this prompt fills. Must reference a declared variable.

**text** (Text): The prompt text shown to the user.

**when** (Optional Text): A conditional expression. If present and evaluates to false, the prompt is skipped. See [Expression language](#expression-language).

**choices** (Optional (List Text)): For `choice`-type variables, a list of allowed values presented as a numbered menu.

### Prompt behavior

- Prompts only fire when the variable has no value from a higher-precedence source (CLI, environment, config).
- In non-interactive mode (no TTY), prompts are skipped. Required variables without values cause an error.
- Prompts appear in the order they are declared in the `prompts` list.
- When a variable has a default value, the prompt shows it in brackets: `Project version [0.1.0.0]:`. Pressing Enter accepts the default.

### Prompts for optional variables

Prompts can target optional variables (`required = False`). Optional prompts appear **after** all required variables are resolved, under an "Optional configuration:" header. The user can press Enter to skip any optional prompt, leaving the variable unresolved — exactly as if it were never provided. Steps guarded by `IsSet` conditions will then be skipped as expected.

```dhall
{ name = "my-module"
, vars =
  [ { name = "project.name", type = "text", default = None Text
    , description = Some "Project name", required = True, validation = None Text }
  , { name = "license", type = "text", default = None Text
    , description = Some "License type", required = False, validation = None Text }
  ]
, prompts =
  [ { var = "project.name", text = "What is your project name?"
    , when = None Text, choices = None (List Text) }
  , { var = "license", text = "Include a license?"
    , when = None Text, choices = Some [ "MIT", "Apache-2.0", "BSD-3-Clause" ] }
  ]
, ...
}
```

When a user runs this module interactively:

```
What is your project name? my-app

Optional configuration:
  Include a license? [skip]:
    1) MIT
    2) Apache-2.0
    3) BSD-3-Clause
  Enter selection number: 1
```

If the user presses Enter without selecting, the `license` variable remains absent and any step with `when = Some "IsSet license"` is skipped.

In non-interactive mode (CI, piped input), optional prompts are not shown and optional variables without defaults are simply absent.


## Steps and strategies

Steps define the file generation operations. Each step produces one output file:

```dhall
{ strategy = "template"
, src = "README.md.tpl"
, dest = "README.md"
, when = None Text
, patch = None Text
}
```

### Fields

**strategy** (Text): How to process the source file. One of: `"copy"`, `"template"`, `"dhall-text"`, `"structured"`.

**src** (Text): Path to the source file, relative to the module's `files/` directory.

**dest** (Text): Output path, relative to the generation target directory. May contain `{{variable}}` placeholders.

**when** (Optional Text): Conditional expression. If present and evaluates to false, the step is skipped. See [Expression language](#expression-language).

**patch** (Optional Text): Patching mode for when multiple modules write to the same file. Values: `"append-file"`, `"prepend-file"`, `"append-section"`, `"replace-section"`. See [Composition patching](#composition-patching).

### Strategy: copy

```dhall
{ strategy = "copy", src = "LICENSE", dest = "LICENSE", when = None Text, patch = None Text }
```

Copies the source file verbatim to the destination. No processing is applied. Use for binary files, license texts, or any file that should not be modified.

### Strategy: template

```dhall
{ strategy = "template", src = "README.md.tpl", dest = "README.md", when = None Text, patch = None Text }
```

Replaces `{{variable.name}}` placeholders with resolved variable values. This is the most common strategy.

**Placeholder syntax:**

- `{{project.name}}` — replaced with the value of `project.name`
- `\{{not.replaced}}` — the backslash escapes the placeholder, producing the literal text `{{not.replaced}}`

Placeholders work in both the file content and the destination path:

```dhall
dest = "{{project.name}}.cabal"   -- becomes "my-app.cabal"
```

### Strategy: dhall-text

```dhall
{ strategy = "dhall-text", src = "config.dhall", dest = "cabal.project", when = None Text, patch = None Text }
```

Processes the source file in two passes:

1. **Variable injection**: `{{variable}}` placeholders are replaced with values (same as template strategy).
2. **Dhall evaluation**: The resulting Dhall expression is evaluated to Text.

This lets you use Dhall's full power — `let` bindings, `if/then/else`, string interpolation, functions — to generate complex output:

```dhall
-- files/cabal.project.dhall
let name = "{{project.name}}"
let version = "{{project.version}}"
in ''
packages: ./${name}.cabal
''
```

The Dhall expression must evaluate to `Text` (Dhall's multi-line string type).

### Strategy: structured

```dhall
{ strategy = "structured", src = "package.yaml.gen", dest = "package.yaml", when = None Text, patch = None Text }
```

Processes the source file in two passes:

1. **Variable injection**: `{{variable}}` placeholders are replaced.
2. **Dhall evaluation**: The Dhall expression is evaluated to a record, then serialized to JSON or YAML based on the destination file extension.

Output format is determined by the destination extension:
- `.json` — JSON output
- `.yaml` or `.yml` — YAML output

This strategy enables type-safe structured output and is especially powerful for composition, where records from multiple modules are deep-merged.

```dhall
-- files/package.yaml.gen
{ name = "{{project.name}}"
, version = "{{project.version}}"
, dependencies = [ "base >= 4.16" ]
, library = { source-dirs = "src" }
}
```


## Variable exports

Exports make a module's variables visible to modules that depend on it:

```dhall
exports =
  [ { var = "project.name", alias = None Text }
  , { var = "nix.system", alias = Some "system" }
  ]
```

### Fields

**var** (Text): The variable name to export. Must reference a declared variable.

**alias** (Optional Text): An alternative name for the exported variable. If `None Text`, the variable is exported with its original name.

### How exports work

When module B depends on module A:

1. Module A runs first (topological sort).
2. Module A's exported variables are available to module B during variable resolution.
3. If A exports `project.name` and B declares a variable `project.name`, B's value is resolved from A's export (unless overridden by a higher-precedence source like a CLI flag).

Variables not listed in `exports` are private to the module.


## Commands

Shell commands run after all file generation is complete:

```dhall
commands =
  [ { run = "git init"
    , workDir = None Text
    , when = None Text
    }
  , { run = "cabal build"
    , workDir = Some "{{project.name}}"
    , when = Some "IsSet enableBuild"
    }
  ]
```

### Fields

**run** (Text): The shell command to execute. May contain `{{variable}}` placeholders.

**workDir** (Optional Text): Working directory for the command. If `None Text`, uses the generation target directory. May contain `{{variable}}` placeholders.

**when** (Optional Text): Conditional expression. See [Expression language](#expression-language).

Commands execute in declaration order, after all steps. Use the `--no-commands` flag to skip them.


## Dependencies and composition

Modules can depend on other modules:

```dhall
{ name = "haskell-with-nix"
, dependencies = [ "haskell-base", "nix-flake" ]
, ...
}
```

### How dependencies work

1. Seihou builds a dependency graph from all requested modules.
2. The graph is topologically sorted so dependencies run before dependents.
3. Circular dependencies are rejected with an error.
4. Diamond dependencies (A depends on B and C, both depend on D) are resolved correctly — D runs once.

### Composing modules at the command line

Use `-m` to compose modules without declaring dependencies:

```sh
seihou run haskell-base -m nix-flake --var project.name=my-app
```

This is equivalent to running a module that depends on both `haskell-base` and `nix-flake`.

### Composition patching

When multiple modules target the same destination file, the `patch` field controls how content is merged:

**Text files** use section markers:

- `patch = Some "append-section"` — Wraps the content in section markers and appends:

  ```
  # --- seihou:haskell-base ---
  dist-newstyle/
  # --- /seihou:haskell-base ---

  # --- seihou:nix-flake ---
  result
  # --- /seihou:nix-flake ---
  ```

- `patch = Some "replace-section"` — Replaces the content between existing section markers for this module.

- `patch = Some "append-file"` — Appends content to the end of the file without section markers.

- `patch = Some "prepend-file"` — Prepends content to the beginning of the file.

**Structured files** (JSON/YAML via the `structured` strategy) use Dhall's deep record merge. Records from multiple modules are merged so that nested keys are combined rather than overwritten.


## Configuration scopes

Seihou resolves variables from multiple sources in this precedence order (first match wins):

1. **CLI flags** — `--var project.name=my-app`
2. **Environment variables** — `SEIHOU_VAR_PROJECT_NAME=my-app`
3. **Local config** — `.seihou/config.dhall` in the current project
4. **Namespace config** — `~/.config/seihou/namespaces/<ns>/config.dhall`
5. **Global config** — `~/.config/seihou/config.dhall`
6. **Module defaults** — `default = Some "value"` in `module.dhall`

### Environment variable mapping

Variable names are mapped to environment variables by:

1. Adding the `SEIHOU_VAR_` prefix
2. Converting to uppercase
3. Replacing `.` with `_`

Example: `project.name` becomes `SEIHOU_VAR_PROJECT_NAME`.

### Config file format

Config files are Dhall records mapping variable names to text values:

```dhall
{ `project.name` = "my-app"
, `project.version` = "1.0.0"
, license = "MIT"
}
```

Keys containing dots must be backtick-escaped in Dhall (`` `project.name` ``). An empty config is written as `{=}`.

### Managing config values

```sh
# Local scope (default)
seihou config set project.name my-app
seihou config get project.name
seihou config list
seihou config unset project.name

# Global scope
seihou config set license MIT --global
seihou config list --global

# Namespace scope
seihou config set license BSD-3-Clause --namespace haskell
seihou config list --namespace haskell
```

### Namespaces

Namespaces group configuration by context. For example, you might set different default licenses for Haskell vs Python projects:

```sh
seihou config set license MIT --namespace haskell
seihou config set license Apache-2.0 --namespace python
```

When running a module, use `--namespace` to select which namespace config to use:

```sh
seihou run my-module --namespace haskell
```

### Debugging variable resolution

Use `seihou vars --explain` to see exactly where each variable value comes from:

```sh
seihou vars my-module --explain --var project.name=demo
```

Each variable shows its resolved value and source (CLI, environment, local config, namespace config, global config, or module default).


## Expression language

The `when` field in prompts, steps, and commands uses a simple expression language for conditional evaluation:

### Operators

| Expression | Meaning |
|-----------|---------|
| `IsSet variable.name` | True if the variable has a resolved value |
| `Eq variable.name value` | True if the variable equals the given value |
| `true` | Always true |
| `false` | Always false |
| `expr1 && expr2` | Logical AND |
| `expr1 \|\| expr2` | Logical OR |
| `!expr` | Logical NOT |
| `(expr)` | Grouping |

### Examples

```dhall
-- Only run if the license variable has a value
when = Some "IsSet license"

-- Only run if the license is MIT
when = Some "Eq license MIT"

-- Complex condition
when = Some "IsSet license && !Eq license none"

-- Quoted values for strings with spaces
when = Some "Eq project.description \"My Project\""
```

Variable names in expressions use the pattern `[a-zA-Z][a-zA-Z0-9._-]*`. Values can be bare words or quoted strings.


## Module search paths

Seihou discovers modules from three directories, searched in order:

1. **Project-local**: `.seihou/modules/` relative to the current working directory
2. **User modules**: `~/.config/seihou/modules/`
3. **Installed modules**: `~/.config/seihou/installed/`

A directory is recognized as a module if it contains a `module.dhall` file. Use `seihou list` to see all discovered modules and their sources.


## Validation

Always validate modules before sharing or using them:

```sh
seihou validate-module ./my-module
```

Validation checks:

1. `module.dhall` exists and evaluates as valid Dhall
2. Module name matches `[a-z][a-z0-9-]*`
3. Variable names are unique
4. Prompts reference declared variables
5. Step source files exist in `files/`
6. Exports reference declared variables

Add `--lint` for advisory warnings about best practices.


## Best practices

**Keep modules focused.** Each module should do one thing well. Use composition to combine small modules rather than building monolithic ones.

**Use meaningful variable names.** Prefix with a namespace when appropriate: `project.name`, `nix.system`, `github.user`. This prevents collisions when composing modules.

**Provide defaults for optional values.** This reduces the number of prompts and makes non-interactive usage easier.

**Export variables for composition.** If other modules might need a value you declare, export it. Unexported variables are private.

**Validate before sharing.** Run `seihou validate-module` and test with `--dry-run` before distributing a module.

**Use conditional steps.** The `when` field lets you build flexible modules that adapt to the user's configuration without requiring separate modules for each variation.

**Use DhallText for complex output.** When simple placeholder substitution isn't enough, the DhallText strategy gives you Dhall's full expression language — conditionals, string interpolation, and let bindings.
