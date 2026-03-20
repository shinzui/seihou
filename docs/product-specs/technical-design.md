# Seihou (製法) — Technical Design

> **Note**: This is the original design spec from before implementation. The actual implementation diverges in several areas documented in Appendix A. For current architecture, see [docs/dev/architecture/overview.md](../dev/architecture/overview.md). For current types, see the design docs in [docs/dev/design/proposed/](../dev/design/proposed/).

## 1. Overview

This document describes the architecture and design of a language‑agnostic project bootstrap system named **Seihou (製法)**. The goal is to create a deterministic, type‑safe, extensible generator capable of bootstrapping any repository (Haskell, TypeScript, frontend, backend, GraphQL, etc.).

The system treats project generation as **configuration resolution + filesystem operations**, rather than text templating.

---

## 2. Design Principles

### P1 — Templates contain no logic

Templates perform placeholder substitution only. All logic lives in the generator.

### P2 — File format determines generation strategy

Each file declares a generation strategy (template, JSON, YAML, Cabal, copy, etc.).

### P3 — Plan first, execute second

Generation proceeds by compiling configuration into a plan before writing to disk.

### P4 — Explicitness over magic

All behavior is declared in a manifest. No implicit conventions.

---

## 3. Core Concepts

### 3.0 Dhall Integration

Modules are authored in Dhall and evaluated into typed Haskell values. Dhall provides:

* Strong typing
* Composition via imports
* Deterministic evaluation
* Built-in validation
* Layered configuration via record merging

Example:

```dhall
let Module = ./schema/Module.dhall

in Module::{
  name = "node-typescript",
  vars = [
    { name = "node.version", varType = "Text", defaultVal = Some "20.11.0", description = Some "Node.js version" }
  ],
  prompts = [],
  steps = []
}
```

All module definitions are evaluated before generation begins.

---

### 3.1 Module (formerly Seihou Formula)

A module defines inputs, prompts, and steps required to generate part of a repository.

```haskell
data Module = Module
  { name    :: Text
  , vars    :: [VarDecl]
  , prompts :: [Prompt]
  , steps   :: [Step]
  }
```

Modules are composable and may depend on other modules.

---

### 3.2 Variable Declaration

Every variable must be declared before use.

```haskell
data VarDecl = VarDecl
  { name        :: VarName
  , varType     :: VarType
  , defaultVal  :: Maybe Value
  , description :: Maybe Text
  }
```

Unresolved variables cause generation failure.

---

### 3.3 Variable Resolution Precedence

Values are resolved in the following order:

1. CLI flags
2. Environment variables
3. Local config
4. Namespace config
5. Global config
6. Module defaults

Each value retains provenance information.

```haskell
data ValueSource
  = FromCLI
  | FromEnv
  | FromLocalConfig
  | FromNamespaceConfig
  | FromGlobalConfig
  | FromDefault
```

---

### 3.4 Prompts

Prompts allow interactive overrides.

```haskell
data Prompt = Prompt
  { var  :: VarName
  , text :: Text
  , when :: Expr
  }
```

Prompts execute only when conditions evaluate to true.

---

## 4. Expression Language

A minimal expression language powers conditions.

```haskell
data Expr
  = Eq Path Value
  | And Expr Expr
  | Or Expr Expr
  | Not Expr
  | IsSet Path
```

Used for:

* conditional prompts
* conditional files
* conditional steps

---

## 5. Generation Strategies

```haskell
data Generator
  = Copy
  | Template
  | Json
  | Yaml
  | Cabal
```

Each generator converts a source artifact + config into file content.

```haskell
generate
  :: Generator
  -> Config
  -> Source
  -> Either GenError ByteString
```

---

## 6. Steps

```haskell
data Step
  = CopyFile Src Dest
  | CopyDir Src Dest
  | RenderTemplate Src Dest
  | RunCommand Command
  | UseModule ModuleName
```

Steps compile into filesystem operations.

---

## 7. Filesystem Operations

All generation reduces to:

```haskell
data Operation
  = WriteFile FilePath ByteString
  | MkDir FilePath
  | DeletePath FilePath
  | Move FilePath FilePath
```

---

## 8. Template Repository Layout

The canonical authoring format for modules is **Dhall**.

```
template/
  module.dhall
  files/
    README.md.tpl
    package.json.gen
    src/index.ts.tpl
```

`module.dhall` is the source of truth and evaluates into a typed `Module` value.

---

## 9. Placeholder Engine

Minimal syntax:

```
{{project.name}}
{{node.version}}
```

Backed by:

```haskell
type Env = Map Path Text
```

No loops or logic allowed.

---

## 10. Execution Pipeline

```
CLI input
   ↓
RawConfig
   ↓
resolve + validate
   ↓
Config
   ↓
compile modules
   ↓
Generation Plan
   ↓
[Operation]
   ↓
Filesystem
```

---

## 11. Namespaces and Configuration

Configuration layers are modeled using Dhall record merging:

* Global
* Namespace
* Local (repo)
* CLI overrides

Example:

```dhall
let Defaults = ./defaults.dhall
let Namespace = ./namespace.dhall
let Local = ./local.dhall

in Defaults // Namespace // Local
```

Merged configuration is evaluated prior to execution.

---

## 12. Commands

```
seihou init
seihou run <module>
seihou vars <module>
seihou vars <module> --explain
seihou install <git-url>
```

---

## 13. Safety and UX

* `--dry-run` prints operations
* `--diff` shows filesystem diff
* `--no-commands` disables shell steps

---

## 14. Future Extensions

* Plugin generator registry
* Remote module registry
* Typed config schemas
* IDE integration

---

## 15. Key Differentiators

| Cookiecutter   | This System       |
| -------------- | ----------------- |
| Template logic | Logic in Haskell  |
| Text-only      | Structure-aware   |
| No plan phase  | Plan-first        |
| Weak typing    | Typed variables   |
| Python-centric | Language-agnostic |

---

## 16. Summary

The system evolves Seihou's strongest ideas into a type‑safe, composable, plan‑based generator suitable for modern multi-language repositories.

---

## Appendix A: Validated Design Decisions

The following decisions were validated during detailed design and diverge from or clarify the original spec above. See the [design docs](../dev/design/proposed/) for full specifications.

### Decisions

| # | Decision | Choice | Rationale |
|---|---|---|---|
| 1 | Target audience | Personal first, ecosystem later | Design for extensibility without over-engineering distribution |
| 2 | Template logic | Templates stay dumb; Dhall computes final text | Leverages Dhall's type system and functions without inventing a template language |
| 3 | Composition model | Explicit layering — modules declare dependencies and patches | Most correct approach; avoids implicit conflicts |
| 4 | Patch model | Strategy-dependent | Dhall record merge for structured files, declarative ops for text |
| 5 | Variable scoping | Shared namespace with explicit exports | Cross-module sharing is intentional; private vars stay private |
| 6 | State tracking | Stateful manifest | Enables precise diffs, undo, "which module generated this?" |
| 7 | Incremental | Day-one support via three-state model (manifest/plan/disk) | Core use case, not deferrable |
| 8 | Conflict handling | Show diff, user decides per-file | Fits plan-first philosophy; pragmatic for v1 |
| 9 | Cabal generation | Dhall-to-text for v1 | Reduces scope; AST-based generation can come later |
| 10 | V1 CLI commands | init, run, vars, install, status, new-module, validate-module | Core loop + authoring experience |

### Key Divergences from Original Spec

1. **P1 (no template logic) preserved with escape hatch** — Dhall functions assemble text with conditionals before reaching the placeholder engine. This is the DhallText generation strategy. The placeholder engine itself remains logic-free.

2. **Composition now explicitly layered** — The original spec implied module stacking by order. The validated design requires modules to declare `dependencies` explicitly, and execution order is determined by topological sort of the dependency graph.

3. **Incremental generation added** — The original spec assumed one-shot generation. The validated design supports incremental re-generation via a three-state diff model (manifest vs plan vs disk).

4. **Manifest/state tracking added** — The original spec was stateless. The validated design introduces `.seihou/manifest.json` to track applied modules, variable values, and file hashes.

5. **Variable exports added** — The original spec had a flat variable namespace. The validated design adds explicit variable exports so modules control which variables are visible to their dependents.

6. **Cabal AST strategy deferred** — The original spec included structured Cabal generation (AST-based patching). For v1, Cabal files use the DhallText strategy (Dhall function → complete text). AST-based generation is a post-v1 enhancement.

### Reference

The detailed design documents live at:

- [Architecture Overview](../dev/architecture/overview.md)
- [Module System](../dev/design/proposed/module-system.md)
- [Composition and Layering](../dev/design/proposed/composition-and-layering.md)
- [Variable Resolution](../dev/design/proposed/variable-resolution.md)
- [Generation Strategies](../dev/design/proposed/generation-strategies.md)
- [Manifest and Incrementality](../dev/design/proposed/manifest-and-incrementality.md)
- [CLI Commands](../dev/design/proposed/cli-commands.md)
- [V1 Milestones](../dev/roadmap/v1-milestones.md)
