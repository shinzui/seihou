# Seihou (製法) — End-User Overview

Seihou (製法) is a composable, type-safe project scaffolding system designed to bootstrap repositories in a deterministic and structured way.

From the end-user perspective, Seihou is a tool for generating production-ready projects by composing reusable modules.

---

# 1. What Seihou Is

Seihou is:

* A project initializer
* A module composition engine
* A structured template system
* A reproducible bootstrap tool

It is not just a templating engine. It generates repositories through configuration resolution and explicit filesystem operations.

---

# 2. Installing Seihou

```
seihou init
```

This initializes:

* Global config directory
* Namespace directory
* Module registry

---

# 3. Creating a Project

## Interactive Mode

```
seihou run haskell-base
```

Seihou will:

* Resolve defaults
* Apply namespace and local config
* Prompt for missing required variables
* Show generation plan
* Execute filesystem operations

---

## Non-Interactive Mode

```
seihou run haskell-base \
  --project.name my-app \
  --license MIT
```

---

# 4. Composing Modules

Users can compose modules to extend functionality.

Example:

```
seihou run haskell-with-nix \
  --project.name my-app
```

Under the hood:

```
haskell-base + nix-haskell
```

---

# 5. Inspecting Variables

Preview resolved variables:

```
seihou vars haskell-base
```

Explain value sources:

```
seihou vars haskell-base --explain
```

This shows whether a value came from:

* CLI
* Environment
* Local config
* Namespace config
* Global config
* Module default

---

# 6. Dry Runs and Safety

Preview operations without writing files:

```
seihou run haskell-base --dry-run
```

Show diff against existing directory:

```
seihou run haskell-base --diff
```

Disable shell commands:

```
seihou run haskell-base --no-commands
```

---

# 7. Configuration Layers

Seihou merges configuration from:

1. Global config
2. Namespace config
3. Local project config
4. CLI flags

This enables team-wide defaults while allowing per-project overrides.

---

# 8. Installing Remote Modules

```
seihou install <git-url>
```

Modules are stored in namespaces and can be reused across projects.

---

# 9. Typical Workflow

1. Install or create modules
2. Configure namespace defaults
3. Run Seihou to bootstrap a project
4. Commit generated repository

---

# 10. Philosophy

Seihou means "method of making."

The tool embodies that philosophy:

* Explicit inputs
* Deterministic evaluation
* Composable modules
* Structured generation

Seihou treats project construction as a deliberate, repeatable craft rather than ad-hoc template copying.

---

Seihou (製法) provides a disciplined way to create and evolve software projects through composable methods.
