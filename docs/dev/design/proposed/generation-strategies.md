# Generation Strategies

| Field | Value |
|---|---|
| **Status** | Proposed |
| **Created** | 2026-03-01 |
| **Subsystem** | Core — Generation Engine |

## Overview

Each file in a Seihou module declares a generation strategy through its file extension. The strategy determines how the source artifact is transformed into output content. Four strategies are supported in v1: Copy, Template, DhallText, and Structured.

## Motivation

Different files in a project have fundamentally different generation needs:

- A `LICENSE` file is static — just copy it
- A `README.md` needs a few variable substitutions — use templates
- A `flake.nix` may need conditionals based on project options — use DhallText
- A `package.yaml` is structured data that merges across modules — use Structured

A single generation approach cannot serve all these needs well. Strategy-per-file lets each file use the simplest approach that works.

## Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Strategy selection | File extension convention | Explicit, no ambiguity, visible in directory listing |
| Template logic | None — placeholders only | P1: templates contain no logic |
| Complex text generation | DhallText (Dhall function → Text) | Dhall provides conditionals/loops without inventing a template language |
| Structured generation | Dhall record → JSON/YAML serialization | Dhall handles merging; serialization is mechanical |
| Cabal generation | Dhall-to-text for v1 | Reduces scope; AST-based generation deferred to post-v1 |
| Placeholder syntax | `{{var.name}}` | Familiar, unambiguous, easy to parse |

## Strategy Dispatch

File extensions map to strategies:

| Extension | Strategy | Description |
|---|---|---|
| `.tpl` | Template | Placeholder substitution only |
| `.copy` | Copy | Raw file copy, zero transformation |
| `.dhall` (in `files/`) | DhallText | Dhall function evaluated to Text |
| `.gen` | Structured | Dhall record → JSON/YAML serialization |

The extension is stripped from the destination path: `README.md.tpl` → `README.md`.

### Domain Types

```haskell
data Strategy
  = Copy
  | Template
  | DhallText
  | Structured StructuredFormat
  deriving stock (Eq, Show, Generic)

data StructuredFormat
  = JSON
  | YAML
  deriving stock (Eq, Show, Generic)

-- | A file produced by the generation engine
data GeneratedFile = GeneratedFile
  { genPath       :: FilePath      -- Output path relative to project root
  , genContent    :: ByteString    -- Generated content
  , genStrategy   :: Strategy      -- Which strategy produced this
  , genModule     :: ModuleName    -- Which module owns this step
  , genHash       :: SHA256        -- Content hash for manifest
  }
  deriving stock (Eq, Show, Generic)

-- | Strategy dispatch
generate
  :: Strategy
  -> ResolvedVars
  -> FilePath        -- Source file path
  -> ByteString      -- Source file content
  -> Either GenError ByteString

data GenError
  = PlaceholderError PlaceholderError
  | DhallTextError Text
  | StructuredSerError Text
  | SourceFileNotFound FilePath
  deriving stock (Eq, Show, Generic)
```

## Copy Strategy

The simplest strategy. Source bytes are written to the destination unchanged.

**Input**: Any file with `.copy` extension
**Output**: Exact copy of the file
**Composition**: Last-writer-wins with warning (see [Composition](composition-and-layering.md))

```haskell
generateCopy :: ByteString -> ByteString
generateCopy = id
```

### Use Cases

- License files
- Binary assets (images, fonts)
- Pre-built configuration files that shouldn't be modified

## Template Strategy

Placeholder substitution with no logic. The engine scans for `{{var.name}}` patterns and replaces them with resolved variable values.

**Input**: Text file with `.tpl` extension containing `{{placeholders}}`
**Output**: Text with all placeholders resolved
**Composition**: Declarative patch operations (append-section, replace-section, prepend)

### Placeholder Syntax

```ebnf
placeholder = "{{" path "}}"
path        = segment ("." segment)*
segment     = [a-zA-Z][a-zA-Z0-9_-]*
escaped     = "\{{"                     -- Literal {{ in output
```

Examples:
```text
# {{project.name}}

Version: {{project.version}}
License: {{license}}

This is a literal \{{ not a placeholder }}.
```

### Placeholder Engine

```haskell
data PlaceholderError
  = UnresolvedPlaceholder Text Int  -- Variable name, line number
  | MalformedPlaceholder Text Int   -- Raw text, line number
  deriving stock (Eq, Show, Generic)

-- | Substitute all placeholders in a template
substitutePlaceholders
  :: ResolvedVars
  -> Text              -- Template content
  -> Either [PlaceholderError] Text

-- | Parse a template into segments
data Segment
  = Literal Text
  | Placeholder VarName
  deriving stock (Eq, Show, Generic)

parseTemplate :: Text -> Either [PlaceholderError] [Segment]
```

### Placeholder Rules

1. All placeholders must resolve to a value. Unresolved placeholders are errors (not silently left in output).
2. Only `VTText` values can be substituted directly. Other types are converted:
   - `VBool True` → `"true"`, `VBool False` → `"false"`
   - `VInt n` → decimal text representation
   - `VList vs` → comma-separated values
3. Placeholders in destination paths (`stepDest`) follow the same syntax and rules.
4. `\{{` produces a literal `{{` in the output.
5. Nested placeholders (`{{{{var}}}}`) are not supported.

## DhallText Strategy

For files that need conditionals, loops, or complex logic, a Dhall function produces the final text. This preserves P1 (templates contain no logic) by moving the logic into Dhall, which is evaluated before the file is written.

**Input**: Dhall file in `files/` that evaluates to `Text`
**Output**: The evaluated Text value
**Composition**: Treated as text; declarative patch operations apply

### How It Works

The source `.dhall` file is a Dhall expression that takes a record of variables and returns Text:

```dhall
-- files/flake.nix.dhall
let vars = { projectName = "{{project.name}}"
           , ghcVersion = "{{haskell.ghc-version}}"
           , enableHLS = {{haskell.enable-hls}}
           }

in ''
{
  description = "${vars.projectName}";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };
  outputs = { self, nixpkgs }:
    let pkgs = nixpkgs.legacyPackages.${vars.system};
    in {
      devShells.default = pkgs.mkShell {
        buildInputs = [
          pkgs.haskell.compiler.${vars.ghcVersion}
${if vars.enableHLS then "          pkgs.haskell-language-server" else ""}
        ];
      };
    };
}
''
```

### Evaluation Pipeline

```text
DhallText source file
       │
       ▼
  Placeholder substitution (inject variable values into Dhall source)
       │
       ▼
  Dhall evaluation (produces Text)
       │
       ▼
  Output text
```

Note: Placeholder substitution happens first, injecting resolved variable values into the Dhall source. Then Dhall evaluates the result to produce final Text output. This two-phase approach lets Dhall functions use variable values in conditionals and string interpolation.

```haskell
generateDhallText
  :: ResolvedVars
  -> FilePath        -- Source .dhall file
  -> ByteString      -- Source content
  -> Eff es ByteString
```

### When to Use DhallText vs Template

| Need | Strategy |
|---|---|
| Simple variable substitution | Template |
| Conditional sections | DhallText |
| Repeated sections (loop-like) | DhallText |
| Complex string assembly | DhallText |
| Static file, no variables | Copy |

## Structured Strategy

For structured data files (JSON, YAML), a Dhall record is serialized to the target format. This enables type-safe merging across modules via Dhall's record merge operations.

**Input**: Dhall file with `.gen` extension evaluating to a record
**Output**: JSON or YAML serialization of the record
**Composition**: Dhall record merge (`/\`) — see [Composition](composition-and-layering.md)

### Output Format Detection

The output format is determined by the destination file extension:

| Destination Extension | Format |
|---|---|
| `.json` | JSON |
| `.yaml`, `.yml` | YAML |

Example: `package.json.gen` → strategy is Structured, output format is JSON (from `package.json`).

### How It Works

```dhall
-- files/package.yaml.gen
{ name = "{{project.name}}"
, version = "{{project.version}}"
, dependencies =
    [ "base >= 4.16 && < 5"
    ]
, library =
    { source-dirs = "src"
    , exposed-modules = ["Lib"]
    }
}
```

### Evaluation Pipeline

```text
Structured source file (.gen)
       │
       ▼
  Placeholder substitution (inject variables)
       │
       ▼
  Dhall evaluation (produces record)
       │
       ▼
  Serialize to JSON/YAML
       │
       ▼
  Output
```

```haskell
generateStructured
  :: StructuredFormat
  -> ResolvedVars
  -> FilePath
  -> ByteString
  -> Eff es ByteString
```

### Cabal Files (V1 Approach)

For v1, `.cabal` files are generated using the DhallText strategy rather than AST-based generation. The Dhall function produces the complete cabal file as text:

```dhall
-- files/package.cabal.dhall
let vars = { name = "{{project.name}}"
           , version = "{{project.version}}"
           , license = "{{license}}"
           }

in ''
cabal-version: 3.0
name:          ${vars.name}
version:       ${vars.version}
license:       ${vars.license}
build-type:    Simple

library
  exposed-modules: Lib
  build-depends:   base >= 4.16 && < 5
  hs-source-dirs:  src
  default-language: GHC2024

executable ${vars.name}
  main-is:          Main.hs
  build-depends:    base, ${vars.name}
  hs-source-dirs:   app
  default-language: GHC2024
''
```

AST-based Cabal generation (parsing, patching, pretty-printing) is deferred to post-v1.

## Business Rules

- Strategy is determined solely by file extension — no runtime strategy selection
- Every placeholder in a Template file must resolve or generation fails
- DhallText evaluation must produce a value of type `Text` or generation fails
- Structured evaluation must produce a Dhall record (not a union, list, or scalar)
- Copy files are never modified, even if they contain `{{` sequences
- File extension stripping: `foo.bar.tpl` → `foo.bar` (only the strategy extension is removed)

## Edge Cases

| Case | Behavior |
|---|---|
| Template with no placeholders | Valid; equivalent to Copy but still processed |
| Placeholder in file path | Resolved during plan compilation |
| DhallText evaluation returns empty string | Valid; writes empty file |
| Structured file with no destination extension | Error — cannot determine output format |
| `.gen` file that evaluates to List | Error — must be a record |
| Template placeholder spans multiple lines | Error — placeholders must be on a single line |
| Binary file with `.tpl` extension | Undefined behavior; don't do this |
| DhallText file imports other Dhall files | Supported — Dhall's import system works normally |

## Testing Plan

| Test | Type | Description |
|---|---|---|
| Copy passthrough | Unit | Input bytes = output bytes |
| Template simple substitution | Unit | `{{var}}` replaced with value |
| Template escape | Unit | `\{{` produces literal `{{` |
| Template missing var | Unit | Returns PlaceholderError |
| Template type coercion | Unit | Bool, Int, List rendered correctly |
| DhallText with conditionals | Unit | Conditional sections included/excluded |
| DhallText evaluation error | Unit | Dhall type error reported clearly |
| Structured JSON output | Unit | Dhall record serialized to valid JSON |
| Structured YAML output | Unit | Dhall record serialized to valid YAML |
| Strategy dispatch by extension | Unit | `.tpl`→Template, `.copy`→Copy, etc. |
| Extension stripping | Unit | `foo.md.tpl`→`foo.md` |
| haskell-template end-to-end | Integration | Full module generation matches expected output |

## Future Enhancements

- AST-based Cabal generation (parse existing .cabal, patch fields, pretty-print)
- Custom strategy plugins (user-defined generators)
- Partial template rendering (leave some placeholders for later passes)
- Template includes (`{{> partial.tpl}}` — possibly, if needed)

## Cross-References

- [Architecture Overview](../../architecture/overview.md) — Strategy dispatch in the pipeline
- [Module System](module-system.md) — Step definitions that reference strategies
- [Composition and Layering](composition-and-layering.md) — Per-strategy merge semantics
- [Manifest and Incrementality](manifest-and-incrementality.md) — Content hashing for generated files
