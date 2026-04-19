# Generation Strategies

| Field | Value |
|---|---|
| **Status** | Implemented |
| **Updated** | 2026-03-20 |
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
  | Structured
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

Placeholder substitution plus inline conditional blocks. The engine
scans for `{{var.name}}` patterns and replaces them with resolved
variable values, and recognises `{{#if …}}{{/if}}` blocks in template
bodies for boolean gating of regions.

**Input**: Text file with `.tpl` extension containing `{{placeholders}}` and optionally `{{#if}}` blocks
**Output**: Text with all placeholders resolved and selected branches retained
**Composition**: Declarative patch operations (append-section, replace-section, prepend)

> **User-facing reference:** the full template authoring guide —
> placeholder syntax, coercion rules, escape sequence, conditional
> blocks, expression grammar, standalone-block whitespace trim,
> error taxonomy, and authoring patterns — lives at
> [`docs/user/templating.md`](../../../user/templating.md). This
> section covers the engine at the design level; for how to
> actually write a `.tpl`, start there.

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

Error taxonomy produced by the engine:

```haskell
data PlaceholderError
  = UnresolvedPlaceholder VarName Int    -- Variable name, line number
  | MalformedPlaceholder Text Int        -- Raw text, line number
  | UnterminatedIf Int                   -- Line of the {{#if}} opener
  | OrphanBlockToken Text Int            -- Stray {{/if}} or {{#else}}
  | MalformedIfExpression Text Int Text  -- Expression, opener line, parser error
  deriving stock (Eq, Show, Generic)
```

Public entry points in `Seihou.Engine.Template`:

```haskell
-- | Substitute {{placeholder}} occurrences only. Used for destination
-- paths and shell commands.
renderTemplate
  :: Text
  -> Map VarName VarValue
  -> Either [PlaceholderError] Text

-- | Render a template body: expand {{#if}}/{{#else}}/{{/if}} blocks
-- (with Mustache-style standalone-block trim), then run
-- 'renderTemplate' over the result. Used for the Template strategy's
-- body path and the Template branch of the patch pipeline.
renderTemplateText
  :: Text
  -> Map VarName VarValue
  -> Either [PlaceholderError] Text

-- | Aliases for 'renderTemplate', named for clarity at call sites.
renderDestPath :: Text -> Map VarName VarValue -> Either [PlaceholderError] Text
renderCommand  :: Text -> Map VarName VarValue -> Either [PlaceholderError] Text

-- | Coerce a resolved 'VarValue' to its rendered text representation.
valueToText :: VarValue -> Text

-- | First-pass conditional expander, exported for test access.
expandConditionals
  :: Map VarName VarValue
  -> Text
  -> Either [PlaceholderError] Text
```

### Placeholder Rules

1. All placeholders must resolve to a value. Unresolved placeholders are errors (not silently left in output).
2. `VText` values are substituted directly. Other types are converted by `valueToText`:
   - `VBool True` → `"true"`, `VBool False` → `"false"`
   - `VInt n` → decimal text representation
   - `VList vs` → comma-separated values (recursively)
3. Placeholders in destination paths (`stepDest`) and command strings follow the same syntax and rules, but are routed through `renderTemplate` / `renderDestPath` / `renderCommand` — they do not accept conditional blocks.
4. `\{{` produces a literal `{{` in the output; there is no corresponding `\}}` escape.
5. Nested placeholders (`{{{{var}}}}`) are not supported.
6. Surrounding whitespace inside the braces is ignored: `{{ foo }}` is equivalent to `{{foo}}`.

### Conditional blocks (Template only)

Template bodies (not `dest` paths or command strings) may contain conditional
blocks that branch on resolved variables:

```
{{#if <expr>}}...{{/if}}
{{#if <expr>}}...{{#else}}...{{/if}}
```

`<expr>` is the same grammar the engine uses for a step's `when` field
(see `Seihou.Core.Expr`): `IsSet`, `Eq`, `&&`, `||`, `!`, `true`, `false`,
parentheses. Blocks nest to arbitrary depth.

Example:

```
nativeBuildInputs = [
  pkgs.cabal-install
{{#if Eq nix.postgresql true}}  pkgs.postgresql
{{/if}}];
```

Semantics:

- Expansion runs as a first pass over the template body; the resulting
  text is then fed through the ordinary `{{placeholder}}` engine.
- Only the selected branch is expanded recursively. The untaken branch
  is discarded, so any `{{placeholder}}` references or nested block
  errors inside it do not surface.
- Block-level errors — unterminated `{{#if}}`, stray `{{/if}}` or
  `{{#else}}`, malformed `<expr>` — report the opener's source line.
  Inner `{{var}}` error line numbers reflect positions after block
  expansion, so they may drift from source positions when blocks are
  consumed; this is accepted as a trade-off against threading a
  line-map through the expander.
- **Standalone-block whitespace trim.** When a block tag
  (`{{#if}}`, `{{#else}}`, `{{/if}}`) is the only non-whitespace
  content on its line, the surrounding indentation and the line's
  trailing newline are absorbed by the tag — matching Mustache and
  Handlebars "standalone block" semantics. Exactly one newline is
  consumed per trim side, so deliberate blank lines inside a block
  body survive. Tags that share a line with other template content
  are left alone.
- Conditionals apply to the `Template` strategy's body path only. The
  `DhallText` and `Structured` strategies express conditionals through
  Dhall's native `if`/`then`/`else` after pre-substitution. Destination
  paths and shell commands accept only `{{placeholder}}` substitution.

Provenance: this facility was added by
[docs/plans/9-inline-conditionals-in-template-strategy.md](../../../plans/9-inline-conditionals-in-template-strategy.md).

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
