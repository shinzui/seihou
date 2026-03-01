# Module System

| Field | Value |
|---|---|
| **Status** | Proposed |
| **Created** | 2026-03-01 |
| **Subsystem** | Core — Module Loading |

## Overview

A module is the fundamental unit of composition in Seihou. It declares variables, prompts, generation steps, and dependencies on other modules. Modules are authored in Dhall, evaluated into typed Haskell values, and executed by the generation engine.

## Motivation

Project scaffolding systems typically use flat template directories with ad-hoc variable substitution. This leads to:

- No type checking of template variables
- No validation until generation time
- No composability between templates
- Implicit dependencies between files

Seihou modules solve these problems by making every input, output, and dependency explicit and type-checked through Dhall.

## Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Module definition language | Dhall | Type-safe, deterministic, composable via imports |
| Module discovery | Local paths + git-cloned | Simple for personal use; git enables sharing |
| Variable scoping | Shared namespace with explicit exports | Cross-module sharing is intentional; private vars stay private |
| Template logic | None — Dhall computes text before placeholders | Preserves P1 while enabling complex generation via DhallText |
| Dependency declaration | Explicit in module manifest | Avoids implicit ordering bugs |

## Module Structure

A module is a directory with this layout:

```
<module-name>/
├── module.dhall          # Module definition (required)
├── schema/               # Dhall type definitions (optional)
│   └── Module.dhall
└── files/                # Source artifacts for generation steps
    ├── README.md.tpl     # Template strategy
    ├── flake.nix.copy    # Copy strategy
    ├── package.yaml.gen  # Structured strategy
    └── cabal.project.dhall  # DhallText strategy
```

### File Extension Conventions

| Extension | Strategy | Description |
|---|---|---|
| `.tpl` | Template | Placeholder substitution |
| `.copy` | Copy | Raw file copy, no transformation |
| `.gen` | Structured | Dhall record → JSON/YAML serialization |
| `.dhall` (in `files/`) | DhallText | Dhall function → Text output |

## Domain Model

### Module

```haskell
data Module = Module
  { moduleName    :: ModuleName
  , description   :: Maybe Text
  , vars          :: [VarDecl]
  , exports       :: [VarExport]
  , prompts       :: [Prompt]
  , steps         :: [Step]
  , dependencies  :: [ModuleName]
  }
  deriving stock (Eq, Show, Generic)

newtype ModuleName = ModuleName { unModuleName :: Text }
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (IsString)
```

### Variable Declaration

```haskell
data VarDecl = VarDecl
  { varName        :: VarName
  , varType        :: VarType
  , varDefault     :: Maybe VarValue
  , varDescription :: Maybe Text
  , varRequired    :: Bool
  , varValidation  :: Maybe Validation
  }
  deriving stock (Eq, Show, Generic)

newtype VarName = VarName { unVarName :: Text }
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (IsString)

data VarType
  = VTText
  | VTBool
  | VTInt
  | VTList VarType
  | VTChoice [Text]
  deriving stock (Eq, Show, Generic)

data VarValue
  = VText Text
  | VBool Bool
  | VInt Int
  | VList [VarValue]
  deriving stock (Eq, Show, Generic)

data Validation
  = ValPattern Text        -- Regex pattern
  | ValRange Int Int       -- Min/max for Int
  | ValMinLength Int       -- Minimum length for Text
  | ValMaxLength Int       -- Maximum length for Text
  deriving stock (Eq, Show, Generic)
```

### Variable Export

```haskell
data VarExport = VarExport
  { exportVar  :: VarName       -- Local variable name
  , exportAs   :: Maybe VarName -- Alias for consuming modules (defaults to exportVar)
  }
  deriving stock (Eq, Show, Generic)
```

Exported variables are visible to modules that depend on the exporting module. Non-exported variables are private to the module.

### Prompt

```haskell
data Prompt = Prompt
  { promptVar       :: VarName
  , promptText      :: Text
  , promptWhen      :: Maybe Expr  -- Condition for displaying (Nothing = always)
  , promptChoices   :: Maybe [Text]  -- For VTChoice variables
  }
  deriving stock (Eq, Show, Generic)
```

### Step

```haskell
data Step = Step
  { stepStrategy :: Strategy
  , stepSrc      :: FilePath     -- Relative to module's files/ directory
  , stepDest     :: Text         -- Destination path (may contain {{placeholders}})
  , stepWhen     :: Maybe Expr   -- Condition for executing step
  }
  deriving stock (Eq, Show, Generic)

data Strategy
  = Copy
  | Template
  | DhallText
  | Structured
  deriving stock (Eq, Show, Generic)
```

## Dhall Schema

The canonical Dhall schema for module definitions:

```dhall
let VarType = < Text | Bool | Int | List : VarType | Choice : List Text >

let VarDecl =
  { name : Text
  , type : VarType
  , default : Optional Text
  , description : Optional Text
  , required : Bool
  , validation : Optional Text
  }

let VarExport =
  { var : Text
  , as : Optional Text
  }

let Prompt =
  { var : Text
  , text : Text
  , when : Optional Text    -- Expression string, parsed by engine
  , choices : Optional (List Text)
  }

let Step =
  { strategy : Text          -- "copy" | "template" | "dhall-text" | "structured"
  , src : Text
  , dest : Text
  , when : Optional Text     -- Expression string
  }

let Module =
  { name : Text
  , description : Optional Text
  , vars : List VarDecl
  , exports : List VarExport
  , prompts : List Prompt
  , steps : List Step
  , dependencies : List Text
  }

in Module
```

## Module Discovery and Loading

### Discovery

Modules are located via a search path:

1. **Local project modules**: `.seihou/modules/` in the current project
2. **User modules**: `~/.config/seihou/modules/`
3. **Installed modules**: `~/.config/seihou/installed/<name>/` (from `seihou install`)

The first match wins. Explicit paths (`seihou run ./path/to/module`) bypass discovery.

### Loading Pipeline

```
module.dhall path
       │
       ▼
  Dhall evaluate
       │
       ▼
  Decode to RawModule (Dhall → Haskell)
       │
       ▼
  Validate (check types, required fields, file existence)
       │
       ▼
  Resolve dependencies (load transitive deps)
       │
       ▼
  Module (fully typed, validated)
```

### Loading Errors

```haskell
data ModuleLoadError
  = ModuleNotFound ModuleName [FilePath]   -- Name + searched paths
  | DhallEvalError ModuleName Text         -- Dhall evaluation failure
  | DhallDecodeError ModuleName Text       -- Type mismatch
  | ValidationError ModuleName [Text]      -- Semantic validation failures
  | CircularDependency [ModuleName]        -- Cycle in dependency graph
  | MissingSourceFile ModuleName FilePath  -- Referenced file doesn't exist
  deriving stock (Eq, Show, Generic)
```

## Module Validation Rules

A module is well-formed when:

1. `moduleName` is non-empty and matches `[a-z][a-z0-9-]*`
2. All `vars` have unique names within the module
3. All `prompts` reference declared variables
4. All `steps` reference files that exist in the module's `files/` directory
5. All `exports` reference declared variables
6. All `dependencies` reference modules that can be resolved
7. Step destinations are valid relative paths (no `..`, no absolute paths)
8. Variables referenced in step destinations are declared
9. `when` expressions parse successfully and reference declared variables or exported variables from dependencies

## Business Rules

- A module with no steps is valid (it may exist only to declare variables for other modules)
- A module may depend on modules that haven't been installed yet — validation of dependencies happens at `run` time, not at `validate-module` time
- Prompt order follows declaration order in the `prompts` list
- Step execution follows declaration order in the `steps` list
- Variable defaults are optional; missing defaults for required variables trigger prompts

## Edge Cases

| Case | Behavior |
|---|---|
| Module with no variables | Valid; all steps use no substitution |
| Module with no steps | Valid; may exist for variable/export declarations only |
| Circular dependency | Error at load time with cycle path |
| Duplicate variable names across modules | OK if in separate modules; resolved via export/import scoping |
| Empty module name | Validation error |
| Step destination contains unresolvable placeholder | Error during plan compilation |
| Module file references missing source | Error during validation |

## Testing Plan

| Test | Type | Description |
|---|---|---|
| Parse valid module.dhall | Unit | Roundtrip Dhall → Module → validate |
| Reject invalid module | Unit | Missing name, bad var type, etc. |
| Discovery search order | Unit | Local > user > installed priority |
| Circular dependency detection | Unit | A→B→C→A produces error with cycle path |
| Variable export visibility | Unit | Non-exported vars invisible to dependents |
| Loading with transitive deps | Integration | A depends on B depends on C, all load correctly |
| Real haskell-template module | Integration | End-to-end load of the example module |

## Future Enhancements

- Module versioning (semver constraints on dependencies)
- Remote module registry with namespaced discovery
- Module inheritance (extend an existing module with overrides)
- Auto-generated documentation from module definitions

## Cross-References

- [Architecture Overview](../../architecture/overview.md) — System-level context
- [Composition and Layering](composition-and-layering.md) — How modules compose
- [Variable Resolution](variable-resolution.md) — How variables are resolved
- [Generation Strategies](generation-strategies.md) — Strategy dispatch per step
