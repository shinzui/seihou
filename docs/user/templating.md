# Template reference

A complete reference for Seihou's Template strategy: placeholder
substitution, inline conditional blocks, the expression grammar,
whitespace rules, error behaviour, and common authoring patterns.

This page covers one of the four generation strategies. For the
surrounding module-authoring model — how to declare variables,
`when` guards at the step level, patching, exports — see
[Module authoring](module-authoring.md). For the other strategies
(Copy, DhallText, Structured), see the same doc.


## Where Template fits

The four generation strategies, in increasing order of power:

| Strategy | Dispatch | Use when |
|---|---|---|
| `copy` | `.copy` extension | The file should not be transformed at all (binary, license texts, lockfiles). |
| `template` | `.tpl` extension | The file needs variable substitution and/or simple boolean gating of regions. |
| `dhall-text` | `.dhall` in `files/` | The output depends on computation — loops, filters, string assembly, arithmetic, multi-way branching. |
| `structured` | `.gen` extension | The output is a Dhall record that should be serialized to JSON or YAML (composable across modules via record merge). |

Templates stay intentionally "dumb": they interpolate variables and
gate blocks on boolean expressions, nothing more. Anything richer —
counting, iterating, arithmetic — is the DhallText strategy's job.
If a conditional you want to write would need a loop or a derived
value, reach for DhallText instead of contorting the template.


## Placeholder substitution

Placeholders are the primary mechanism: `{{variable.name}}` in a
template body, destination path, or shell command is replaced with
the resolved value of `variable.name`.

### Syntax

```
{{variable.name}}      standard form
{{ variable.name }}    surrounding whitespace is ignored
\{{variable.name}}     literal "{{variable.name}}" in output (escape)
```

Variable names match `[a-zA-Z][a-zA-Z0-9._-]*`; dots are part of
the name (they are not structural). A placeholder is any text
between a `{{` opener and the next `}}` closer on the same line.

### Coercion rules

The resolved value is coerced to text depending on its type:

| `VarValue` | Rendered as |
|---|---|
| `VText "hello"` | `hello` |
| `VBool True` | `true` |
| `VBool False` | `false` |
| `VInt 42` | `42` |
| `VList [VText "a", VText "b"]` | `a,b` (comma-separated) |

Nested lists are flattened to comma-separated text recursively.

### Escape sequence

`\{{` is consumed and produces a literal `{{` in the output.
There is no corresponding `\}}` escape — unmatched closers are
emitted verbatim.

```
Use \{{name}} for placeholders   →   Use {{name}} for placeholders
```

The escape applies to placeholder syntax only. There is no escape
for conditional-block tags (`{{#if}}`, `{{/if}}`, `{{#else}}`): if a
template body needs a literal `{{#if` sequence in its output, you
cannot currently produce it from the Template strategy — use
DhallText instead.

### Where placeholders work

Placeholder substitution runs in three positions:

- **Template bodies** — the `.tpl` file's contents.
- **Destination paths** — the `dest` field (so `dest = "{{project.name}}.cabal"` becomes `"my-app.cabal"`).
- **Shell commands** — the `run` and `workDir` fields of commands.

Conditional blocks (below) run in template bodies only, not in
`dest` or command strings.


## Conditional blocks

Template bodies may contain inline conditional blocks that gate
regions of text on a boolean expression. This replaces the
"two near-duplicate templates with mutually exclusive `when` guards"
pattern with a single readable template.

### Syntax

```
{{#if <expr>}}...{{/if}}
{{#if <expr>}}...{{#else}}...{{/if}}
```

`<expr>` uses the same expression grammar as a step's `when` clause
(see below). Blocks may nest to arbitrary depth.

### Expression grammar

```ebnf
expr    = or_expr
or_expr = and_expr ("||" and_expr)*
and_expr= not_expr ("&&" not_expr)*
not_expr= "!" atom | atom
atom    = "IsSet" varname
        | "Eq" varname value
        | "(" expr ")"
        | "true" | "false"
varname = [a-zA-Z][a-zA-Z0-9._-]*
value   = quoted_string | bare_word
```

- `IsSet foo` — true iff `foo` has a resolved value.
- `Eq foo <value>` — true iff `foo`'s resolved value equals
  `<value>`. Values are type-sensitive: `Eq flag true` compares
  against a `VBool True`, while `Eq flag "true"` compares against
  the string `"true"`. A variable declared `type = "bool"` should
  be compared against bare-word `true`/`false`, not against their
  quoted-string forms.
- `&&`, `||`, `!` — the usual boolean operators.
- Parentheses group sub-expressions.
- `true` / `false` — literal constants.

The same grammar is documented in the
[Expression language](module-authoring.md#expression-language)
section of Module authoring and implemented by
`Seihou.Core.Expr.parseExpr` / `evalExpr`.

### Nesting

Blocks nest to arbitrary depth. The parser tracks depth so that a
`{{/if}}` always matches its nearest open `{{#if}}`:

```
{{#if Eq os "linux"}}
  {{#if Eq use.systemd true}}
  --systemd
  {{/if}}
{{/if}}
```

### Untaken-branch semantics

Only the selected branch is recursively expanded. The untaken
branch's text is discarded before it reaches the second-pass
placeholder engine. This means:

- `{{variable}}` references in the untaken branch are **never**
  evaluated. An unresolved placeholder in a branch that doesn't run
  will not produce an `UnresolvedPlaceholder` error.
- The same applies to nested `{{#if}}` blocks inside an untaken
  branch: they are not parsed for errors. A malformed expression
  inside the untaken branch is silent.

This is deliberate: it matches what a reader expects ("the `false`
branch isn't run, so its bugs shouldn't surface") and lets template
authors gate optional features without having to guarantee that
every variable referenced inside the gate is always declared.

### Where conditional blocks work

Template bodies only. The following positions accept only
`{{placeholder}}` substitution and will treat `{{#if}}` literally
as a placeholder name (which then fails to resolve):

- Destination paths (`dest`).
- Shell command strings (`run`, `workDir`).
- Pre-Dhall substitution for the `dhall-text` and `structured`
  strategies — those strategies express conditionals via Dhall's
  native `if`/`then`/`else` after the placeholder substitution pass.


## Standalone-block whitespace trim

A block tag is **standalone** on its line when:

1. Everything before the tag on its line is spaces or tabs (or the
   tag starts at the beginning of the template), and
2. Everything after the tag on its line is spaces or tabs followed
   by a newline (or the template ends).

A standalone tag absorbs the leading indentation of its line and
the single terminating newline. A tag that shares a line with
template content does not trigger the trim and retains all its
surrounding whitespace verbatim.

### What gets absorbed

When the trim triggers, exactly one newline is consumed on each
side. So a block written in the readable "standalone" style:

```
prev
  {{#if Eq flag true}}
  body
  {{/if}}
next
```

produces `prev\n  body\nnext\n` when `flag = True` and
`prev\nnext\n` when `flag = False` — no blank-line cruft either
way. The author's indentation of the body is preserved; the
indentation of the tag lines is not.

### Preserving blank lines inside a block

Because only one newline is consumed per trim side, a blank line
inside the block body survives:

```
prev
{{#if Eq x true}}

beta
{{/if}}
gamma
```

With `x = True`, emits `prev\n\nbeta\ngamma\n` (one blank line
between `prev` and `beta`). With `x = False`, emits `prev\ngamma\n`
(no blank line — the entire block disappears).

This is the intended way to emit a deliberate blank separator at
the boundary of a gated region: put the blank inside the block
body, not outside.

### Compact tags are unaffected

A tag that shares a line with template content does not trigger the
trim. The original compact style:

```
nativeBuildInputs = [
  pkgs.cabal-install
{{#if Eq nix.postgresql true}}  pkgs.postgresql
{{/if}}];
```

still works and still produces tightly-packed output. Mixing
standalone and compact tag styles in the same template is fine —
the trim is a per-tag decision based only on its own line.

### Indentation and tabs

Only ASCII spaces (`0x20`) and tabs (`0x09`) qualify as "whitespace"
for the trim check. Unicode whitespace such as `U+00A0` (NBSP) does
not trigger the trim.


## Errors

The engine reports five error kinds, each with a line number:

| Error | When | Line reported |
|---|---|---|
| `UnresolvedPlaceholder` | `{{name}}` references a variable with no resolved value. | Line of the `{{`. |
| `MalformedPlaceholder` | `{{` opened on a line with no closing `}}` before the line ends. | Line of the opener. |
| `UnterminatedIf` | `{{#if}}` opener with no matching `{{/if}}` before end of template. | Line of the opener. |
| `OrphanBlockToken` | `{{/if}}` or `{{#else}}` encountered outside any open `{{#if}}`. | Line of the stray tag. |
| `MalformedIfExpression` | The expression inside a `{{#if …}}` failed to parse. | Line of the opener. |

Human-readable messages are produced by
`Seihou.Engine.Plan.formatPlaceholderError` and shown to the user
when a run fails.

### Line numbers

- **Block-level errors** (`UnterminatedIf`, `OrphanBlockToken`,
  `MalformedIfExpression`) always report the source line of the
  offending tag in the original template.
- **Placeholder errors** inside a taken branch
  (`UnresolvedPlaceholder`, `MalformedPlaceholder`) use the line
  number from the text that reaches the placeholder engine — i.e.,
  after block expansion and standalone-trim absorption. When no
  blocks intervene, this matches the source line exactly. When
  blocks have been consumed, the reported line can drift by the
  number of absorbed newlines. The error is still informative
  (the variable name and line number are right; the line number is
  measured in the post-expansion text, not the raw source).

If precise source-line reporting for inner placeholder errors ever
becomes important, a line-map can be threaded through the expander
without changing user-facing semantics.


## Patterns

### Optional single line

Toggle one line based on a bool variable:

```
nativeBuildInputs = [
  pkgs.cabal-install
  {{#if Eq nix.postgresql true}}
  pkgs.postgresql
  {{/if}}
];
```

### Feature gate covering several lines

Wrap a multi-line region — preserve a blank separator by placing
it inside the block:

```
export LANG=en_US.UTF-8
{{#if Eq nix.postgresql true}}

export PGHOST="$PWD/db"
export PGDATA="$PGHOST/db"
{{/if}}
```

### If / else with a default

```
runtime = "{{#if IsSet docker.registry}}{{docker.registry}}/{{project.name}}{{#else}}{{project.name}}{{/if}}";
```

Writing it all on one line keeps the output on one line too (no
standalone trim triggers). Use this shape inside non-line-oriented
contexts.

### Multi-feature matrix

Each gate is independent; writing them in the standalone style
keeps the template readable:

```
  outputs = { self, nixpkgs, flake-utils{{#if Eq nix.treefmt true}}, treefmt-nix{{/if}}{{#if Eq nix.pre-commit true}}, pre-commit-hooks{{/if}} }:
```

For cases where several gates bring in several sections, write each
section as a standalone block.

### Version-gated content

```
{{#if Eq ghc.version "ghc912"}}
  -- ghc912-specific build flags
  ghc-options: -Wno-x-partial
{{/if}}
```

`Eq` does string-equal comparisons for text variables, so this
works directly against the declared `type = "text"` version.

### When you need more than gating

If you find yourself wanting to:

- Loop over a list and emit one line per element,
- Compute a value (e.g. `major.minor` from `ghc.version`),
- Choose among more than a handful of discrete cases,
- Merge structured data across modules,

…then switch the step to `dhall-text` (for freeform Text output)
or `structured` (for JSON/YAML with record-level composition).
Both are substitution-then-evaluation pipelines: `{{variable}}`
placeholders are substituted first, then the resulting Dhall
expression is evaluated to produce the final output. Full power of
Dhall — `let`, `if`/`then`/`else`, list operations, records — is
available after substitution.


## Cross-references

- [Module authoring](module-authoring.md) — variable declarations, step fields, patch operations, the four strategies in context.
- [Configuration and variables](config-and-variables.md) — how variables are resolved, including the `--confirm-defaults` interactive review flag.
- [Getting started](getting-started.md) — a complete walkthrough that uses template output in context.
- [Command reference: run](../cli/run.md) — flags for rendering, previewing, and applying modules.
