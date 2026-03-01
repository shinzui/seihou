# Variable Resolution

| Field | Value |
|---|---|
| **Status** | Proposed |
| **Created** | 2026-03-01 |
| **Subsystem** | Core — Variable Resolution |

## Overview

Seihou resolves variables through a multi-layer precedence chain. Each variable retains provenance metadata indicating where its value came from, enabling the `--explain` feature and debugging. Variables are typed, validated, and scoped through the module export system.

## Motivation

Project scaffolding tools typically have flat, untyped variable systems. This leads to:

- Runtime errors from typos in variable names
- No way to know why a variable has a particular value
- No type checking (passing "yes" where a boolean is expected)
- No scoping (all variables in a global soup)

Seihou's variable resolution provides typed, validated, provenance-tracked, scoped variables.

## Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Resolution precedence | CLI → env → local → namespace → global → default | Most specific wins; standard layered config pattern |
| Type system | Text, Bool, Int, List, Choice | Covers scaffolding needs without over-engineering |
| Scoping model | Shared namespace with explicit exports | Intentional cross-module sharing; private vars stay private |
| Provenance tracking | Per-variable source annotation | Enables --explain; essential for debugging |
| Expression language | Minimal: Eq, And, Or, Not, IsSet | Just enough for conditional prompts/steps |

## Resolution Precedence

Variables are resolved in this order (first match wins):

| Priority | Source | Example |
|---|---|---|
| 1 (highest) | CLI flags | `--var project.name=my-app` |
| 2 | Environment variables | `SEIHOU_VAR_PROJECT_NAME=my-app` |
| 3 | Local project config | `.seihou/config.dhall` |
| 4 | Namespace config | `~/.config/seihou/namespaces/<ns>/config.dhall` |
| 5 | Global config | `~/.config/seihou/config.dhall` |
| 6 (lowest) | Module defaults | `default = Some "my-value"` in module.dhall |

### Environment Variable Mapping

Variable names map to environment variables by:
1. Prefixing with `SEIHOU_VAR_`
2. Uppercasing
3. Replacing `.` with `_`

Example: `project.name` → `SEIHOU_VAR_PROJECT_NAME`

## Domain Model

### Resolved Variables

```haskell
data ResolvedVar = ResolvedVar
  { resolvedValue  :: VarValue
  , resolvedSource :: VarSource
  , resolvedDecl   :: VarDecl    -- Original declaration for reference
  }
  deriving stock (Eq, Show, Generic)

data VarSource
  = FromCLI
  | FromEnv Text           -- Environment variable name
  | FromLocalConfig
  | FromNamespaceConfig Text  -- Namespace name
  | FromGlobalConfig
  | FromDefault
  | FromPrompt             -- User entered interactively
  deriving stock (Eq, Show, Generic)

newtype ResolvedVars = ResolvedVars
  { unResolvedVars :: Map VarName ResolvedVar }
  deriving stock (Eq, Show, Generic)
  deriving newtype (Semigroup, Monoid)
```

### Variable Resolution Pipeline

```haskell
-- | Resolve all variables for a set of modules
resolveVariables
  :: [Module]           -- Modules in execution order
  -> CliVars            -- CLI-provided values
  -> EnvVars            -- Environment variables
  -> ConfigLayers       -- Local/namespace/global configs
  -> Either [VarError] ResolvedVars

data VarError
  = UnresolvedRequired VarName ModuleName
  | TypeMismatch VarName VarType VarValue
  | ValidationFailed VarName Validation VarValue
  | UnknownVarReference VarName            -- Used but never declared
  | ExportNotFound ModuleName VarName      -- Module exports undeclared var
  deriving stock (Eq, Show, Generic)
```

## Type System

### Type Checking Rules

| VarType | Valid VarValues | Dhall Source Type |
|---|---|---|
| `VTText` | `VText t` | `Text` |
| `VTBool` | `VBool b` | `Bool` |
| `VTInt` | `VInt n` | `Integer` |
| `VTList t` | `VList vs` where each `v` matches `t` | `List T` |
| `VTChoice opts` | `VText t` where `t` is in `opts` | `Text` (validated) |

### Type Coercion from Strings

CLI flags and environment variables are always strings. Coercion rules:

| Target Type | Coercion Rule |
|---|---|
| `VTText` | Identity |
| `VTBool` | `"true"/"yes"/"1"` → `True`; `"false"/"no"/"0"` → `False`; else error |
| `VTInt` | Parse as integer; error on failure |
| `VTList VTText` | Split on `,` (e.g., `"a,b,c"` → `["a","b","c"]`) |
| `VTChoice opts` | Identity, then validate membership |

### Validation

```haskell
validateVar :: VarDecl -> VarValue -> Either VarError ()
validateVar decl val = do
  -- Type check
  checkType (varType decl) val
  -- Custom validation
  for_ (varValidation decl) $ \v -> case v of
    ValPattern pat    -> matchRegex pat (asText val)
    ValRange lo hi    -> checkRange lo hi (asInt val)
    ValMinLength n    -> checkMinLen n (asText val)
    ValMaxLength n    -> checkMaxLen n (asText val)
```

## Cross-Module Variable Scoping

### Visibility Rules

1. A module's own variables are always visible within that module
2. Exported variables from a dependency are visible to the dependent module
3. Non-exported variables are private (invisible to other modules)
4. If two dependencies export the same variable name, the later dependency in the `dependencies` list takes precedence

### Resolution with Exports

```
Given: Module C depends on [Module A, Module B]

Module A vars:    {project.name, project.version, internal.flag}
Module A exports: {project.name, project.version}

Module B vars:    {nix.system, internal.cache}
Module B exports: {nix.system}

Module C visible: {project.name, project.version, nix.system} ∪ {C's own vars}
Module C hidden:  {internal.flag, internal.cache}
```

### Variable Namespacing Convention

Variables use dotted paths as a namespacing convention:

- `project.name` — Project-level variables
- `nix.system` — Nix-specific variables
- `haskell.ghc-version` — Haskell-specific variables

This is a convention, not enforced by the system. The `.` is simply part of the variable name.

## Expression Language

The expression language powers conditional prompts, steps, and file generation.

### Grammar

```haskell
data Expr
  = Eq VarName VarValue      -- Variable equals value
  | And Expr Expr             -- Logical conjunction
  | Or Expr Expr              -- Logical disjunction
  | Not Expr                  -- Logical negation
  | IsSet VarName             -- Variable has been set (any source)
  | Literal Bool              -- Constant true/false
  deriving stock (Eq, Show, Generic)
```

### Dhall Representation

Expressions are serialized as strings in Dhall and parsed by the engine:

```dhall
{ when = Some "IsSet license && Eq license MIT" }
```

### Evaluation Semantics

```haskell
evalExpr :: ResolvedVars -> Expr -> Bool
evalExpr vars = \case
  Eq name val     -> lookupVar name vars == Just val
  And left right  -> evalExpr vars left && evalExpr vars right
  Or left right   -> evalExpr vars left || evalExpr vars right
  Not inner       -> not (evalExpr vars inner)
  IsSet name      -> isJust (lookupVar name vars)
  Literal b       -> b
```

### Expression Parsing

Expressions use a simple infix syntax:

```
expr     = or_expr
or_expr  = and_expr ("||" and_expr)*
and_expr = not_expr ("&&" not_expr)*
not_expr = "!" atom | atom
atom     = "IsSet" varname
         | "Eq" varname value
         | "(" expr ")"
         | "true" | "false"
varname  = [a-zA-Z][a-zA-Z0-9._-]*
value    = quoted_string | bare_word
```

## `--explain` Output

The `seihou vars <module> --explain` command shows resolution provenance:

```
Variable Resolution for haskell-base:

  project.name     = "my-app"          [CLI: --var project.name=my-app]
  project.version  = "0.1.0.0"         [default: module.dhall]
  license          = "BSD-3-Clause"     [namespace: haskell/config.dhall]
  haskell.ghc      = "9.12.2"          [global: ~/.config/seihou/config.dhall]
```

## Business Rules

- All variables used in templates or expressions must be declared in some module in the composition
- Required variables with no resolved value trigger an interactive prompt (if available) or an error (in non-interactive mode)
- Type coercion from strings is attempted only for CLI and environment sources
- Dhall config files provide native-typed values (no coercion needed)
- Variable names are case-sensitive
- Empty string is a valid `VTText` value (distinct from unset)

## Edge Cases

| Case | Behavior |
|---|---|
| Variable declared in two modules | Each module has its own declaration; exports determine visibility |
| CLI provides unknown variable name | Warning emitted, value ignored |
| Environment variable with empty value | Treated as `VText ""`, not unset |
| List variable from CLI | Split on `,`; empty string → empty list |
| Choice variable with invalid option | `ValidationFailed` error |
| Expression references undeclared variable | `IsSet` returns False; `Eq` returns False |
| Circular variable reference | Not possible — variables are values, not expressions |
| Module exports variable it doesn't declare | `ExportNotFound` error at validation time |

## Testing Plan

| Test | Type | Description |
|---|---|---|
| Precedence ordering | Unit | CLI overrides env overrides local, etc. |
| Type checking | Unit/Property | Each VarType accepts/rejects correct values |
| String coercion | Unit | Bool, Int, List coercion from strings |
| Validation rules | Unit | Pattern, range, length validation |
| Export visibility | Unit | Private vars hidden, exports visible |
| Expression evaluation | Unit/Property | All Expr constructors evaluated correctly |
| Expression parsing | Unit | Parse various expression strings |
| `--explain` output | Unit | Provenance correctly reported for each source |
| Cross-module resolution | Integration | Multi-module variable flow via exports |
| Missing required variable | Integration | Error in non-interactive, prompt in interactive |

## Future Enhancements

- Computed variables (value derived from other variables via Dhall expression)
- Variable groups (related variables declared together)
- Variable deprecation (warning when using deprecated var name)
- JSON Schema-compatible validation

## Cross-References

- [Architecture Overview](../../architecture/overview.md) — Pipeline context for resolution stage
- [Module System](module-system.md) — Variable declarations and exports
- [Composition and Layering](composition-and-layering.md) — Variable flow between modules
- [CLI Commands](cli-commands.md) — `vars` command specification
