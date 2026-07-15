# Module Authoring Reference

This document is the complete reference for creating Seihou modules. For a hands-on walkthrough, see the [Getting Started Guide](getting-started.md). For reusable agent-session templates that do not generate files deterministically, see [First-Class Prompts](prompts.md).


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
, version = Some "1.0.0"
, description = Some "What this module does"
, vars = [ ... ]
, exports = [ ... ]
, prompts = [ ... ]
, steps = [ ... ]
, commands = [ ... ]
, dependencies = [ ... ]
, removal = None Removal.Type
}
```

### Field reference

**name** (Text, required): The module identifier. Must match `[a-z][a-z0-9-]*`.

**version** (Optional Text, **required at validation**): Semantic version string (e.g., `"1.0.0"`). Used by `seihou outdated` and `seihou upgrade` to compare installed vs available versions. Although the Dhall type is `Optional Text` for backwards compatibility with older module schemas, `seihou validate-module` rejects modules where `version` is `None` or an empty string. Always use `Some "1.0.0"`. `seihou schema-upgrade` can add a placeholder version to unversioned modules.

**description** (Optional Text): Human-readable description shown by `seihou list` and in validation output. Use `Some "description"` or `None Text`.

**vars** (List): Variable declarations. See [Variables](#variables) below.

**exports** (List): Variables to share with dependent modules. See [Variable exports](#variable-exports).

**prompts** (List): Interactive prompts for missing values. See [Prompts](#prompts).

**steps** (List): File generation operations. See [Steps and strategies](#steps-and-strategies).

**commands** (List): Shell commands to run after generation. See [Commands](#commands).

**dependencies** (List): Modules this module depends on, in record form. See [Dependencies and composition](#dependencies-and-composition).

**removal** (Optional Removal.Type): Declares how this module can be removed with `seihou remove`. If `None`, the module cannot be removed. If present, contains a list of removal steps (`remove-file`, `remove-section`, `rewrite-file`) that describe exactly how to reverse the module's effects. See [Removing modules](#removing-modules).


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

**patch** (Optional Text): Patching mode for when multiple modules write to the same file. Values: `"append-file"`, `"prepend-file"`, `"append-section"`, `"append-line-if-absent"`, `"replace-section"`. See [Composition patching](#composition-patching).

### Strategy: copy

```dhall
{ strategy = "copy", src = "LICENSE", dest = "LICENSE", when = None Text, patch = None Text }
```

Copies the source file verbatim to the destination. No processing is applied. Use for binary files, license texts, or any file that should not be modified.

### Strategy: template

```dhall
{ strategy = "template", src = "README.md.tpl", dest = "README.md", when = None Text, patch = None Text }
```

Replaces `{{variable.name}}` placeholders with resolved variable values, and supports inline `{{#if}}` / `{{#else}}` / `{{/if}}` conditional blocks in template bodies for gating regions on boolean expressions. This is the most common strategy.

Quick syntax summary:

- `{{project.name}}` — substitute the value of `project.name`.
- `\{{literal}}` — escape; emit a literal `{{literal}}` in output.
- `{{ project.name }}` — surrounding whitespace inside the braces is ignored.
- `{{#if <expr>}}…{{/if}}` and `{{#if <expr>}}…{{#else}}…{{/if}}` — gate a region of the body. `<expr>` uses the same grammar as a step's `when` clause (see [Expression language](#expression-language)).

Placeholders work in both the file content and the destination path:

```dhall
dest = "{{project.name}}.cabal"   -- becomes "my-app.cabal"
```

Conditional blocks apply to **template bodies only** — destination paths (`dest`) and shell commands (`run`, `workDir`) accept only `{{placeholder}}` substitution.

> **Full reference:** [Template reference](templating.md) — coercion rules for non-text values, escape semantics, full expression grammar, nesting, standalone-block whitespace trim, error taxonomy, and authoring patterns.

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

Modules can depend on other modules. Dependencies use the record form `{ module, vars }`:

```dhall
{ name = "haskell-with-nix"
, dependencies =
  [ { module = "haskell-base", vars = [] : List { name : Text, value : Text } }
  , { module = "nix-flake", vars = [ { name = "nix.system", value = "x86_64-linux" } ] }
  ]
, ...
}
```

For simple dependencies without variable bindings, `vars` is an empty list.

> **Note:** Older modules may use bare string dependencies (`["haskell-base"]`). Run `seihou schema-upgrade` to convert them to the current record format.

### How dependencies work

1. Seihou builds a dependency graph from all requested modules.
2. The graph is topologically sorted so dependencies run before dependents.
3. Circular dependencies are rejected with an error.
4. Diamond dependencies (A depends on B and C, both depend on D) are resolved correctly — D runs once.

### Parameterized dependencies

Dependencies can pre-supply variable values to the child module. These values have `FromParent` provenance — higher priority than module defaults but lower than config files:

```dhall
dependencies =
  [ { module = "nix-flake"
    , vars = [ { name = "nix.system", value = "x86_64-linux" } ]
    }
  ]
```

This sets `nix.system` to `"x86_64-linux"` in the `nix-flake` module unless overridden by a CLI flag, environment variable, or config.

### Multi-instantiation

Two dependency edges pointing at the same child module with **different** `vars` produce two independent invocations of that child. Two edges with **identical** `vars` dedupe to a single invocation. This is what makes a helper like `claude-skill-link` reusable along multiple edges in the same composition.

Worked example — picture a registry with three modules:

- `claude-skill-link` — a helper that declares one variable, `skill.name`, and runs `ln -sfn ../../claude/skills/{{skill.name}} .claude/skills/{{skill.name}}`.
- `exec-plan` — depends on `claude-skill-link` with `skill.name = "exec-plan"`.
- `master-plan` — depends on `exec-plan` **and** directly on `claude-skill-link` with `skill.name = "master-plan"`.

Running `seihou run master-plan` evaluates the composition and produces **two** distinct `claude-skill-link` invocations — one for each set of parent-supplied bindings. Both symlinks get created; neither invocation is silently dropped.

In the generated `.seihou/manifest.json`, each invocation appears as its own `AppliedModule` entry with a `parentVars` field recording the bindings. `seihou status` prints the bindings inline so you can tell the two apart:

```
Applied modules:
  claude-skill-link [skill.name=exec-plan]    v0.1.0    (applied 2026-04-19)
  claude-skill-link [skill.name=master-plan]  v0.1.0    (applied 2026-04-19)
  exec-plan [skill.name=exec-plan]            v0.1.3    (applied 2026-04-19)
  master-plan                                 v0.1.0    (applied 2026-04-19)
```

Identity is the set of parent-supplied `vars`, not any downstream override. Two invocations stay distinct even if CLI overrides later collapse their resolved variables to the same value, because the "which invocation is this" question is fixed at authoring time by the edge's `vars` field.

No new authoring syntax is required — the existing `dependencies = [ … ]` list already expresses this. If you want one child invocation to be shared by two parents, both parents supply the same bindings; if you want two independent invocations, supply different bindings.

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

- `patch = Some "append-line-if-absent"` — Appends only lines not already present in the file. Idempotent on re-runs — no duplicates, no markers. Ideal for line-oriented config files like `.gitignore` or `.dockerignore`.

**Structured files** (JSON/YAML via the `structured` strategy) use Dhall's deep record merge. Records from multiple modules are merged so that nested keys are combined rather than overwritten.


## Configuration scopes

Seihou resolves variables from multiple sources in this precedence order (first match wins):

1. **CLI flags** — `--var project.name=my-app`
2. **Environment variables** — `SEIHOU_VAR_PROJECT_NAME=my-app`
3. **Local config** — `.seihou/config.dhall` in the current project
4. **Namespace config** — `~/.config/seihou/namespaces/<ns>/config.dhall`
5. **Context config** — `~/.config/seihou/contexts/<ctx>/config.dhall`
6. **Global config** — `~/.config/seihou/config.dhall`
7. **Parent bindings** — Parameterized dependency `depVars` from parent module
8. **Module defaults** — `default = Some "value"` in `module.dhall`
9. **Interactive prompt** — User input for missing variables when a TTY is available

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

# Context scope (e.g. work vs personal)
seihou config set user.email me@work.example --context work
seihou config list --context work

# Merged view across all scopes, with provenance
seihou config list --effective
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

Each variable shows its resolved value and source (CLI, environment, local config, namespace config, context config, global config, or module default).


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


## Recipes

A **recipe** is a named, reusable composition of modules. Instead of composing modules with `-m` flags every time, you declare the combination once in a `recipe.dhall` file and run `seihou run <recipe-name>`.

The name "recipe" aligns with seihou (製法, "method of production / recipe"): modules are ingredients, recipes describe how to combine them.

### The recipe.dhall format

```dhall
{ name = "haskell-library"
, version = Some "1.0.0"
, description = Some "Haskell library with Nix integration"
, modules =
  [ { module = "haskell-base", vars = [] : List { name : Text, value : Text } }
  , { module = "nix-flake", vars = [ { name = "nix.system", value = "aarch64-darwin" } ] }
  ]
, vars = [] : List { name : Text, type : Text, default : Optional Text, description : Optional Text, required : Bool, validation : Optional Text }
, prompts = [] : List { var : Text, text : Text, when : Optional Text, choices : Optional (List Text) }
}
```

### Recipe fields

**name** (Text, required): The recipe identifier. Must match `[a-z][a-z0-9-]*`. Shares a namespace with modules and blueprints — `seihou run foo` auto-detects whether `foo` is a module or recipe, while blueprints run through `seihou agent run`.

**version** (Optional Text): Semantic version string.

**description** (Optional Text): Human-readable description shown by `seihou list`.

**modules** (List, required): The modules to compose, using the same `{ module, vars }` record format as module dependencies. The first module becomes the "primary" for namespace derivation. Variable bindings in `vars` are pre-configured values that act like CLI `--var` overrides.

**vars** (List): Recipe-level variable declarations injected into variable resolution.

**prompts** (List): Recipe-level interactive prompts.

### Creating a recipe

Use `seihou new-recipe` to scaffold a recipe:

```sh
seihou new-recipe haskell-library --module haskell-base --module nix-flake
```

This creates `haskell-library/recipe.dhall` with the listed modules pre-populated.

### Running a recipe

```sh
seihou run haskell-library
```

Seihou detects that `haskell-library` is a recipe (directory contains `recipe.dhall`), expands it into its constituent modules, and runs the existing composition pipeline. Recipe variable bindings are merged with any CLI `--var` overrides (CLI wins on conflict).

### Recipes vs dependencies vs -m flags

| Approach | When to use |
|----------|-------------|
| `dependencies` in module.dhall | Module B always needs module A |
| `-m` flags | Ad-hoc composition for a single run |
| Recipe | Reusable, shareable named composition |

### Recipe validation

Recipes are validated with these rules:

1. Name matches `[a-z][a-z0-9-]*`
2. At least one module listed
3. No duplicate module names
4. Variable binding names match `[a-z][a-z0-9.-]*`


## Module search paths

Seihou discovers modules, recipes, blueprints, and prompts from three directories, searched in order:

1. **Project-local**: `.seihou/modules/` relative to the current working directory
2. **User modules**: `~/.config/seihou/modules/`
3. **Installed modules**: `~/.config/seihou/installed/`

A directory is recognized as a module if it contains `module.dhall`, as a
recipe if it contains `recipe.dhall`, or as a blueprint if it contains
`blueprint.dhall`, or as a prompt if it contains `prompt.dhall`. Discovery
prefers `module.dhall`, then `recipe.dhall`, then `blueprint.dhall`, then
`prompt.dhall` when more than one runnable file is present. Use `seihou list`
to see all discovered modules, recipes, blueprints, and prompts and their
sources.


## Validation

Always validate modules before sharing or using them:

```sh
seihou validate-module ./my-module
```

Validation checks:

1. `module.dhall` exists and evaluates as valid Dhall
2. Module name matches `[a-z][a-z0-9-]*`
3. `version` is declared and non-empty (not `None` or `""`)
4. Variable names are unique
5. Prompts reference declared variables
6. Step source files exist in `files/`
7. Exports reference declared variables

Add `--lint` for advisory warnings about best practices.


## Schema package and record completion

Seihou publishes its Dhall schema as a separate package at [`seihou-schema`](https://github.com/shinzui/seihou-schema). Modules import it via a pinned HTTPS URL with an integrity hash, and use Dhall's record completion operator (`::`) for ergonomic authoring. Instead of spelling out all optional fields, you can use defaults:

```dhall
let S =
      https://raw.githubusercontent.com/shinzui/seihou-schema/<commit>/package.dhall
        sha256:<hash>

in  S.Module::{
    , name = "my-module"
    , steps =
      [ S.Step::{ strategy = "template", src = "README.md.tpl", dest = "README.md" }
      ]
    , dependencies =
      [ S.Dependency::{ module = "nix-base" }
      ]
    }
```

Running `seihou new-module` generates modules in this format automatically. Record completion fills in defaults for optional fields (`version = None Text`, `when = None Text`, `patch = None Text`, etc.), so you only specify what matters. Available types: `S.Module`, `S.Step`, `S.VarDecl`, `S.VarExport`, `S.Prompt`, `S.Command`, `S.Dependency`.


## Upgrading modules to the current schema

If you have modules written for an older version of Seihou, use `seihou schema-upgrade` to bring them up to date:

```sh
# Preview what would change
seihou schema-upgrade ./my-module --dry-run

# Upgrade a specific module
seihou schema-upgrade ./my-module

# Upgrade all discovered modules
seihou schema-upgrade --all
```

This adds missing fields (`version`, `patch`, `commands`), converts bare string dependencies to the record form, and injects the schema import (`let S = ...`) for modules that lack it. The command is idempotent.


## Removing modules

Modules can declare removal steps in the `removal` section of their `module.dhall`. This allows users to undo the module's effects with `seihou remove <module>`. Modules without a `removal` section (`removal = None Removal.Type`) cannot be removed.

```dhall
{ name = "my-template"
, removal = Some
    { steps =
      [ { action = "remove-file", path = "README.md", content = None Text }
      , { action = "remove-file", path = "LICENSE", content = None Text }
      ]
    }
, steps =
  [ { strategy = "template", src = "README.md.tpl", dest = "README.md"
    , when = None Text, patch = None Text }
  , { strategy = "copy", src = "LICENSE", dest = "LICENSE"
    , when = None Text, patch = None Text }
  ]
, ...
}
```

### Removal step actions

Each removal step has an `action`, a `path`, and an optional `content` field:

- **remove-file** — Delete the file at `path`. Output: `Delete path`.
- **remove-section** — Strip a tagged section (e.g., `# --- seihou:module ---` markers and their content) from the file at `path`. Output: `Strip section from path`.
- **rewrite-file** — Rewrite the file at `path` using the Dhall expression or template in `content`. Output: `Rewrite path`.

### Example: module with section patching

When a module contributes a section to a shared file (e.g., `.gitignore`), the removal section can strip just that section rather than deleting the entire file:

```dhall
{ name = "nix-flake"
, removal = Some
    { steps =
      [ { action = "remove-file", path = "flake.nix", content = None Text }
      , { action = "remove-section", path = ".gitignore", content = None Text }
      ]
    }
, steps =
  [ { strategy = "dhall-text", src = "flake.nix.dhall", dest = "flake.nix"
    , when = None Text, patch = None Text }
  , { strategy = "template", src = "gitignore.tpl", dest = ".gitignore"
    , when = None Text, patch = Some "append-section" }
  ]
, ...
}
```

### When to provide a removal section

A module should declare `removal` when its effects can be described by a combination of file deletions, section stripping, and file rewrites. This covers:

- Modules that produce standalone files (use `remove-file`)
- Modules that contribute sections to shared files (use `remove-section`)
- Modules that need to transform a file back to a previous state (use `rewrite-file`)

### When to omit removal (the default)

Leave `removal = None Removal.Type` when:

- The module's effects cannot be cleanly reversed
- Shell commands make irreversible changes (database migrations, external API calls, etc.)
- The removal logic is too complex to express declaratively

### What happens during removal

When a user runs `seihou remove my-module`:

1. The manifest is checked to confirm the module was applied and has a removal section.
2. Each removal step is shown as an operation: Delete, Strip, Rewrite, or Run.
3. The removal plan is shown and the user is prompted for confirmation.
4. If `--dry-run`: the plan is printed and no changes are made.
5. The declared removal steps are executed in order.
6. The manifest is updated to remove the module and its file records.
7. Empty parent directories are cleaned up automatically.

Use `--dry-run` to preview the removal plan without making changes, and `--force` to skip confirmation prompts.


## Migrations

When a module's `version` advances and the change shifts the **layout**
of the files it generates (a directory rename, a file removal, a path
shift), authors can declare migrations on `module.dhall` so consumers
don't have to do the moves by hand.

```dhall
let S = ./package.dhall

in S.Module::{
  , name = "haskell-base"
  , version = Some "2.0.0"
  , steps = [ … ]
  , migrations =
      [ S.Migration::{
          from = "1.0.0",
          to = "2.0.0",
          ops =
            [ S.MigrationOp.MoveDir { src = "app", dest = "src" }
            , S.MigrationOp.DeleteFile { path = "Setup.hs" }
            ]
        }
      ]
  }
```

Each migration declares a `from` version, a `to` version, and a list
of operations applied in order. The five operations are `MoveFile`,
`MoveDir`, `DeleteFile`, `DeleteDir`, and `RunCommand`. Consumers run
`seihou migrate <module>` to apply them.

For the full guide — chain semantics, conflict handling, the
`--with-migrations` upgrade flag, and the manifest path-rewrite
guarantee — see [migrations.md](migrations.md) or run
`seihou help migrations`.


## Best practices

**Keep modules focused.** Each module should do one thing well. Use composition to combine small modules rather than building monolithic ones.

**Use meaningful variable names.** Prefix with a namespace when appropriate: `project.name`, `nix.system`, `github.user`. This prevents collisions when composing modules.

**Provide defaults for optional values.** This reduces the number of prompts and makes non-interactive usage easier.

**Export variables for composition.** If other modules might need a value you declare, export it. Unexported variables are private.

**Validate before sharing.** Run `seihou validate-module` and test with `--dry-run` before distributing a module.

**Use conditional steps.** The `when` field lets you build flexible modules that adapt to the user's configuration without requiring separate modules for each variation.

**Use DhallText for complex output.** When simple placeholder substitution isn't enough, the DhallText strategy gives you Dhall's full expression language — conditionals, string interpolation, and let bindings.
