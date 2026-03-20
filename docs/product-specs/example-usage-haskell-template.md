# Seihou (製法) — Example Usage: Haskell Project Template Module

> **Note**: This is an early design example from before implementation. Some details (e.g., the `cabal` strategy) were deferred to post-v1. V1 uses `dhall-text` for .cabal generation. For the current module format, see [docs/user/module-authoring.md](../user/module-authoring.md).

This document demonstrates a complete example of a Haskell project template authored in Dhall and executed by the generator.

---

# 1. Repository Layout (Template Authoring Side)

```
haskell-template/
  module.dhall
  schema/
    Module.dhall
  files/
    README.md.tpl
    cabal.project.gen
    package.cabal.gen
    src/Lib.hs.tpl
    app/Main.hs.tpl
```

* `module.dhall` defines the module logic
* `files/` contains source artifacts
* `.tpl` files use placeholder substitution
* `.gen` files use structured generators (Cabal, etc.)

---

# 2. Dhall Schema (Simplified)

`schema/Module.dhall`

```dhall
{
  name : Text,
  vars : List {
    name : Text,
    type : Text,
    default : Optional Text,
    description : Optional Text
  },
  prompts : List {
    var : Text,
    text : Text
  },
  steps : List {
    kind : Text,
    src : Text,
    dest : Text
  }
}
```

---

# 3. Haskell Module Definition (module.dhall)

```dhall
let Module = ./schema/Module.dhall

in Module::{
  name = "haskell-base",

  vars = [
    { name = "project.name"
    , type = "Text"
    , default = None Text
    , description = Some "Name of the project"
    }
  , { name = "project.version"
    , type = "Text"
    , default = Some "0.1.0.0"
    , description = Some "Initial version"
    }
  , { name = "license"
    , type = "Text"
    , default = Some "MIT"
    , description = Some "License type"
    }
  ],

  prompts = [
    { var = "project.name"
    , text = "What is the project name?"
    }
  ],

  steps = [
    { kind = "template", src = "README.md.tpl", dest = "README.md" }
  , { kind = "cabal", src = "package.cabal.gen", dest = "${project.name}.cabal" }
  , { kind = "template", src = "src/Lib.hs.tpl", dest = "src/Lib.hs" }
  , { kind = "template", src = "app/Main.hs.tpl", dest = "app/Main.hs" }
  ]
}
```

---

# 4. Example Template Files

## README.md.tpl

```
# {{project.name}}

Version: {{project.version}}
License: {{license}}
```

---

## package.cabal.gen

This file is processed by the Cabal generator (AST-based).

Fields patched programmatically:

* name
* version
* license

The source may look like:

```
name: TEMPLATE_NAME
version: TEMPLATE_VERSION
license: TEMPLATE_LICENSE

library
  exposed-modules: Lib
  build-depends: base >=4.16 && <4.20
  hs-source-dirs: src

executable {{project.name}}
  main-is: Main.hs
  hs-source-dirs: app
  build-depends:
      base
    , {{project.name}}
```

The Cabal generator replaces fields via structured patching rather than text substitution.

---

# 5. CLI Usage

## Interactive

```
seihou run haskell-base
```

Prompts:

```
What is the project name?
```

---

## Non-interactive

```
seihou run haskell-base \
  --project.name my-app \
  --project.version 0.1.0.0
```

---

# 6. Generation Plan (Dry Run)

```
seihou run haskell-base --dry-run
```

Produces operations:

```
MkDir src/
MkDir app/
WriteFile README.md
WriteFile my-app.cabal
WriteFile src/Lib.hs
WriteFile app/Main.hs
```

---

# 7. Resulting Project Structure

```
my-app/
  README.md
  my-app.cabal
  src/
    Lib.hs
  app/
    Main.hs
```

---

# 8. Configuration Layering Example

Defaults can be overridden using layered Dhall configs:

```dhall
let Base = ./module.dhall
let LocalOverrides = { project.version = "0.2.0.0" }

in Base ⫽ LocalOverrides
```

---

# 9. Key Properties Demonstrated

* Typed variable declarations
* Deterministic Dhall evaluation
* Placeholder-based templates (logic-free)
* Structured Cabal generation
* Plan-first execution
* Interactive + non-interactive usage

---

This example demonstrates how a Haskell project template is authored, evaluated, and executed in the system.
