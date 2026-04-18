# Dhall as a Templating Language: Evaluation

| Field | Value |
|---|---|
| **Status** | Proposed — evaluation only, no production change |
| **Created** | 2026-04-18 |
| **Updated** | 2026-04-18 |
| **Subsystem** | Core — Generation Engine |
| **ExecPlan** | `docs/plans/8-evaluate-dhall-as-templating-language.md` |

## Overview

A Seihou module in a sibling repository
(`seihou-modules/modules/haskell/nix-haskell-flake/`) hit an ergonomic
wall: its `flake.nix` needs to branch on whether PostgreSQL is enabled,
but Seihou's `template` strategy has no in-file conditionals, so the
author had to ship two near-duplicate templates — `flake.nix.tpl`
(54 lines) and `flake-with-postgres.nix.tpl` (68 lines) — gated by
mutually exclusive `when` conditions on two `Step` records. The two
files differ only in one added `pkgs.postgresql` line and one 11-line
`shellHook` block; any future edit to the shared 95% has to be made
twice, identically, in lockstep.

The ground-truth diff is checked in at
`docs/dev/design/proposed/dhall-as-templating-evaluation.diff`, and the
two templates are reproduced verbatim in the in-tree fixture at
`seihou-core/test/fixtures/evaluation/split-flake/`.

The user asked whether **"extending Dhall usage to be a templating
language"** would improve Seihou's power, pointing to a pattern
document that frames Dhall as a typed, pure, total function-evaluation
engine. This document answers that question concretely: three
prototypes under `seihou-core/test/fixtures/evaluation/` reproduce the
split flake as (A) a single `.dhall` source using the existing
`DhallText` strategy, (B) a typed-function variant that applies a
Dhall record rather than doing `{{var}}` substitution, and (C) a
`{{#if}}` extension to the existing placeholder engine that does not
involve Dhall at all. Each prototype ships a passing byte-for-byte
equivalence test against the split-flake baseline.

The recommendation at the end is backed by that prototype evidence —
not by opinion.

## Current State

Four generation strategies live in
`seihou-core/src/Seihou/Engine/Plan.hs:compileStep`:

- **`Copy`** — source bytes written verbatim.
- **`Template`** — text with `{{var}}` placeholders substituted by
  `Seihou.Engine.Template.renderTemplate`. **No conditional or loop
  syntax.** The only way to branch is to put alternatives in separate
  files and gate each step with a `when` expression.
- **`DhallText`** — a `.dhall` file is first rewritten by
  `renderTemplate` (placeholders substituted **into the Dhall
  source**), then evaluated via `Dhall.input Dhall.strictText` in
  `renderDhallText`. Two phases: string substitute, then Dhall
  evaluate.
- **`Structured`** — a `.gen` file evaluated to a Dhall record, then
  serialized to JSON or YAML via `Seihou.Engine.DhallJSON`.

The `when` expression grammar is
`IsSet <var> | Eq <var> <val> | <e> && <e> | <e> || <e> | !<e> | true | false | (<e>)`,
parsed by `Seihou.Core.Expr.parseExpr` into `Seihou.Core.Types.Expr`
and evaluated by `evalExpr`.

The spec for these strategies lives in
`docs/dev/design/proposed/generation-strategies.md`. Their tests live
in `seihou-core/test/Seihou/Engine/PlanSpec.hs`. The canonical
`DhallText` example in-tree is
`seihou-core/test/fixtures/haskell-base/files/cabal.project.dhall` —
three lines producing a one-line `cabal.project`.

**A key asymmetry in the current `DhallText`**: placeholder
substitution happens *inside* the Dhall source. `{{project.name}}`
becomes a bare token `my-app` in the text handed to `Dhall.input`. For
a `Text` position this only works if the template wraps it in quotes
(`"{{project.name}}"`); for a `Bool` position the substituted
`true`/`false` becomes an unbound Dhall identifier because Seihou
renders Bool lowercase and Dhall expects `True`/`False`. Any type
error Dhall reports refers to the post-substitution text, not the
source a human wrote. Prototype A documents this in practice.

## The User's Hypothesis

The pattern document the user provided argues Dhall can express
templating as a special case of typed function evaluation. Its seven
claims:

1. **Templates are functions `\(input : T) -> Text`.**
2. **Typed inputs give compile-time guarantees about shape.**
3. **Function composition replaces ad-hoc string concatenation.**
4. **Record merge (`//`, `⫽`) supports defaults with overrides.**
5. **Imports let templates be split across files and reused.**
6. **Dhall can emit structured data (JSON, YAML) as well as text.**
7. **"Template as Data + Interpreter"** — treat Dhall as a typed DSL
   whose output is a data structure the CLI interprets.

The pattern doc closes with a table contrasting "traditional
templating" against Dhall, and with when-to-use / when-to-avoid
heuristics.

The evaluation below engages with each claim on its merits; it does
not dismiss them.

## Three Prototypes

### Prototype A — rewrite with existing `DhallText`

Fixture:
`seihou-core/test/fixtures/evaluation/dhall-text-flake/files/flake.nix.dhall`.

A single ~100-line Dhall source produces both flake variants.
Placeholder substitution happens first, so authors must:

- wrap `Text` vars as Dhall string literals:
  `let projectName = "{{project.name}}"`;
- declare shim bindings so lowercase `true`/`false` parse:
  `let true = True  let false = False`; and
- escape every Nix `${…}` as `''${…}` and every Nix `''…''` as
  `'''…'''` inside the outer Dhall multi-line literal.

Core excerpt:

```dhall
let true  = True
let false = False
let projectName   = "{{project.name}}"
let nixPostgresql = {{nix.postgresql}}

let postgresPkg : Text =
      if    nixPostgresql
      then  "            pkgs.postgresql\n"
      else  ""

in  ''
{
  description = "${projectDescription}";
  …
  nativeBuildInputs = [
    pkgs.zlib
    …
${postgresPkg}            (haskellPackages.ghcWithPackages …)
  ];
  …
}
''
```

**Output line count:** ~100 Dhall lines replace 54+68=122 template
lines. The `if`/`then`/`else` glue plus a Dhall multi-line delimiter
eat back most of what naive branching would save.

**Authoring friction** (captured in the plan's Surprises &
Discoveries):

- `{{…}}` anywhere in the file — including inside `--` comments — is
  substituted by `renderTemplate`. Discussing placeholder syntax in a
  doc comment broke the first draft with
  `unresolved placeholder '{{var}}' at line 6`.
- Lowercase `true`/`false` from Seihou's `valueToText` does not match
  Dhall's `True`/`False`, which requires the two-line shim.
- Dhall multi-line string literals strip the longest common leading
  whitespace prefix. The postgres shell-hook block needs 12 literal
  spaces of indent on every line, so the prototype builds it with
  regular `"…"` strings concatenated via `++` and explicit `\n`.
  That block becomes 12 one-line strings joined by `++`.

**Error locality:** a seeded `let nixPostgresql : Text = True`
produces:

```
Error: Expression doesn't match annotation

- Text
+ Bool

4│                            True

(input):4:28
```

`(input)` refers to the text handed to `Dhall.input`, which is the
`.dhall` source *after* placeholder substitution. When a variable's
textual value differs in length from its `{{name}}`, the reported
column drifts from the source column.

The two variants produce byte-identical output to the baseline under
`cabal test seihou-core-test -p DhallTextFlake` (2/2 pass).

### Prototype B — typed-function `DhallText`

Fixture:
`seihou-core/test/fixtures/evaluation/typed-dhall-text-flake/files/flake.nix.dhall`.
Renderer: `Seihou.Engine.TypedDhallText.renderTypedDhallText`. Spec:
`Seihou.Evaluation.TypedDhallTextSpec`.

The source *is* a Dhall function; no `renderTemplate` pass ever runs
over it. The caller builds a typed record from `Map VarName VarValue`
and applies the function.

Core excerpt:

```dhall
\(vars :
    { project_name         : Text
    , project_description  : Text
    , ghc_version          : Text
    , nix_process_compose  : Bool
    , nix_postgresql       : Bool
    }
  ) ->
let postgresPkg : Text =
      if    vars.nix_postgresql
      then  "            pkgs.postgresql\n"
      else  ""

in  ''
{
  description = "${vars.project_description}";
  …
}
''
```

**Line count:** same ~100 lines as Prototype A — the Nix/Dhall
escaping and concatenation workarounds are identical; what
disappears is the placeholder-substitution scaffolding.

**Record type construction.** `fieldNameFor` maps `.` and `-` to `_`
so `project.name` becomes `project_name`, `nix.process-compose`
becomes `nix_process_compose`. The type mapping is:

| `VarValue`   | Dhall type    | Notes                                          |
|--------------|---------------|------------------------------------------------|
| `VText`      | `Text`        | `\\`, `"`, `$` escaped.                        |
| `VBool`      | `Bool`        | Direct — no lowercase/capital mismatch.       |
| `VInt`       | `Integer`     | Emitted with sign prefix.                      |
| `VList a`    | `List <T>`    | `<T>` inferred from first element.             |
| `VChoice`    | `Text`        | Seihou stores Choice as a validated `Text`.   |
| nested list  | `List Text`   | Known prototype fallback.                     |

**Friction that disappears** (relative to Prototype A): `{{…}}` in
comments is benign, no `true`/`false` shim needed, error locations
come out of the user's source — not a substituted copy.

**Friction that persists**: Nix `${…}` collision, `''` vs `'''`
Dhall escapes, common-prefix stripping on multi-line strings.
Those are artifacts of Dhall's multi-line syntax; Prototype B does
not help with them.

**Error locality.** A seeded field-name typo (`vars.nix_postgres`
where the record has `vars.nix_postgresql`) produces a Dhall type
error whose text contains the offending field:

```
Error: Expression doesn't match annotation
  …  nix_postgres  …
```

The `TypedDhallTextSpec` `reports a field-name typo` case asserts
`"nix_postgres"` appears in the error; it passes.

Byte-for-byte equivalence asserted by
`cabal test seihou-core-test -p TypedDhallText` (5/5 pass, including
the error-locality seed).

### Prototype C — inline conditionals in `template`

Fixture:
`seihou-core/test/fixtures/evaluation/conditional-template-flake/files/flake.nix.tpl`.
Renderer: `Seihou.Engine.TemplatePrototype.renderTemplatePrototype`.
Spec: `Seihou.Evaluation.ConditionalTemplateSpec`.

A single template adds `{{#if}}`/`{{/if}}` blocks around the two
postgres-specific regions. No Dhall; the existing placeholder engine
does the `{{var}}` substitution after the conditional pass.

Core excerpt (the two added blocks, elided):

```
            pkgs.pkg-config
{{#if Eq nix.postgresql true}}            pkgs.postgresql
{{/if}}            (haskellPackages.ghcWithPackages (ps: [
              ps.haskell-language-server
            ]))
…
            export LANG=en_US.UTF-8
{{#if Eq nix.postgresql true}}
            export PGHOST="$PWD/db"
            …
            fi
{{/if}}          '';
```

**Line count:** ~70 lines — roughly the longer of the two split
templates, plus four marker lines. No Dhall scaffolding, no
`${…}` escaping, no multi-line dedent rules.

**Grammar reuse.** `{{#if <expr>}}` feeds directly into
`Seihou.Core.Expr.parseExpr`. `IsSet`, `Eq`, `&&`, `||`, `!`,
`true`/`false`, parentheses all work with no new parser. The spec
case `evaluates IsSet against an unset variable as False and
excludes the block` passes without additional code.

**Error locality.** The seeded unterminated-`{{#if}}` test reports
the opener's line number (line 3 of a 4-line input). No
string-substitute-then-parse pipeline pollutes the mapping.

**Prototype scope.**
`seihou-core/src/Seihou/Engine/TemplatePrototype.hs` is ~180 lines in
one new module. It does not touch `Seihou.Engine.Template`,
`Seihou.Engine.Plan`, the `Strategy` enum, any Dhall schema, or the
manifest. Discarding it costs nothing.

**Known limitation.** The prototype caps nesting at one level and
rejects deeper nesting with `NestingTooDeep`. Promoting to a first-
class feature would likely need unbounded nesting.

## Critical Feedback on the Pattern Document

Engaging with the seven claims on their merits:

1. **Templates as functions.** *True in principle.* Under the
   current production `DhallText`, the placeholder pass
   (`renderTemplate`) runs over the Dhall source *before*
   `Dhall.input` sees it — so the "function" is actually "string
   substitute, then evaluate." The purity claim holds only if the
   substitution layer is removed (Prototype B does that).

2. **Typed inputs give compile-time guarantees.** *True only under
   Prototype B.* Production `DhallText` has no typed `Vars` record;
   it has placeholder-substituted source. Dhall's typechecker sees
   substituted text, not typed bindings, so a misspelled variable
   surfaces as `unresolved placeholder` (Seihou, pre-Dhall) or
   `Unbound variable` (Dhall, post-substitution), not as a record
   type mismatch.

3. **Function composition replaces ad-hoc string concatenation.**
   *True but irrelevant to this pain point.* Dhall's `++`, `//`,
   and `⫽` compose *Dhall values*. Seihou composes at the
   filesystem-plan layer
   (`docs/dev/design/proposed/composition-and-layering.md`) — patch
   ops like `append-file`, `append-section`, `append-line-if-absent`
   merge file content across modules. None of the three prototypes
   changes that layer, and Dhall's value composition does not
   replace it.

4. **Defaults and overrides via record merge.** *Not a gap Seihou
   has.* `Seihou.Core.Variable` already runs a nine-level precedence
   chain (CLI → env → local config → namespace config → context
   config → global config → parent → default → prompt; see
   `docs/dev/design/proposed/variable-resolution.md`). Dhall's
   record merge would duplicate that mechanism, not replace it.

5. **Imports for reuse.** *Mostly true, mostly unused.* A `.dhall`
   source can import other `.dhall` files from the module's `files/`
   directory. No existing Seihou module does this. Worth keeping on
   the radar for large modules, but not a load-bearing argument for
   switching strategies.

6. **Dhall emits JSON/YAML.** *Already covered.* The `Structured`
   strategy does exactly this. Nothing new.

7. **"Template as data + interpreter."** *Already adopted, just not
   per-file.* `module.dhall` is exactly Dhall-as-data, and
   `Seihou.Engine.Plan.compileStep` is the interpreter. Every
   `Module`'s `Step` list is "a data structure the CLI
   interprets." The pattern is already at the module level — the
   question is whether to push it down to per-file generation.

## Comparison Table

| Axis | Current (two files) | Prototype A (`DhallText`) | Prototype B (typed-fn) | Prototype C (`{{#if}}`) |
|---|---|---|---|---|
| **Ergonomics** | Author edits two files in lockstep | One file, heavy escaping | One file, heavy escaping | One file, no escaping |
| **Type safety (in practice)** | None (text only) | None (substitution before eval) | Yes (typed record) | None (text only) |
| **Error locality** | Per-template lines, accurate | Post-substitution text, drifts | User source, names fields | Source lines, accurate |
| **Composition with other modules** | Via patch ops (unchanged) | Unchanged | Unchanged | Unchanged |
| **Novice onboarding** | Obvious duplication but trivial | Multi-phase mental model, `${}` escape rules, `True`/`true` trap, dedent rule | Multi-phase mental model, `.`→`_` mapping, still has `${}` and dedent rules | One new syntax: `{{#if …}}` |
| **`${}` collision** | n/a | Every Nix `${…}` must be `''${…}` | Every Nix `${…}` must be `''${…}` | n/a |
| **Tooling** | No editor support beyond plain text | Dhall LSP sees post-substitution text; less helpful | Dhall LSP sees the real user source; more helpful | No editor support, but grammar is trivial |
| **Scope of change** | 0 lines | 0 production lines (uses existing `DhallText`) | New module + potential dispatcher change | New module; dispatcher optional |
| **Solves the reported pain** | No | Yes | Yes | Yes |

## Recommendation

**Adopt Prototype C: add `{{#if <expr>}}/{{#else}}/{{/if}}` to the
`Template` strategy.** Keep `DhallText` and `Structured` unchanged
for the cases where they genuinely pay — structured records
serialised to JSON/YAML (`Structured`) and one-off typed
configuration text (`DhallText`).

**Why C and not B.** The user's pain is *duplicated text with one
toggle*. The simplest fix that solves it — and the one with the
smallest footprint on authors — is an inline conditional in the
text strategy they're already using. Prototype C adds one
syntactic form; its error messages point at the offender's line;
its grammar is the one they already write in `when =`. It does not
introduce a new mental model, a new escaping regime, or a new
type-checker's diagnostics vocabulary.

Prototype B is a better answer to a *different* question:
"How should Seihou express complex structured text generation
where typed inputs matter?" The flake-split pain is not that
question. Pushing all text files through a typed function just to
toggle two chunks of Nix would impose the Nix/`${}`/`''…''`
escaping tax on every module author, regardless of whether their
file needs it.

**Why not "stay and document."** The reported pain is real, the
duplication grows with every edit to the shared 95%, and the
existing `when`-gated-file workaround invites silent drift (the
very bug the author worked around in the sibling repo's
`when` expressions: `Eq nix.postgresql false || Eq nix.postgresql
"false"`, a double-sided guard hinting at a smaller bug elsewhere
in the expression comparator).

**Why not "combine B and C."** We could, but shipping both at once
doubles the surface area of new syntax module authors have to
learn. If a future module needs the typed-function approach — a
genuinely complex configuration-to-text transformation — we can
revisit Prototype B on its own merits in a separate plan.

## Followup Work

These are **not** performed by this plan. They would each be
separate ExecPlans, authored from this recommendation.

- **Promote `Seihou.Engine.TemplatePrototype` to
  `Seihou.Engine.Template`.** Fold `{{#if}}/{{/if}}/{{#else}}` into
  `renderTemplate`, reusing `PlaceholderError` (or extending it)
  and lifting the depth-1 nesting cap. Update the tokenizer to
  recognise the three block tokens alongside `{{var}}`.

- **Update documentation.** Extend
  `docs/dev/design/proposed/generation-strategies.md` with a
  "Conditional blocks" subsection for `Template`, worked examples,
  and a "split avoidance" case study citing the
  `nix-haskell-flake` module.

- **Migrate the sibling `nix-haskell-flake` module.** Replace
  `flake.nix.tpl` + `flake-with-postgres.nix.tpl` and the two
  mutually exclusive `Step` records with a single step that uses
  the new conditional blocks. Investigate and file the
  `Eq nix.postgresql false || Eq nix.postgresql "false"`
  double-guard pattern — likely a small bug in the comparator —
  separately from the feature work.

- **(Deferred.)** If a future module needs typed-function text
  generation, revisit Prototype B as a new `DhallTextTyped`
  strategy or as a replacement for the current `DhallText`
  dispatch, accepting the migration cost on existing `.dhall`
  sources.

## Cross-References

- ExecPlan that produced this evaluation:
  `docs/plans/8-evaluate-dhall-as-templating-language.md`
- Ground-truth diff between the split templates:
  `docs/dev/design/proposed/dhall-as-templating-evaluation.diff`
- Strategy spec: `docs/dev/design/proposed/generation-strategies.md`
- Composition & patch ops:
  `docs/dev/design/proposed/composition-and-layering.md`
- Variable resolution precedence:
  `docs/dev/design/proposed/variable-resolution.md`
- Fixtures:
  - `seihou-core/test/fixtures/evaluation/split-flake/`
  - `seihou-core/test/fixtures/evaluation/dhall-text-flake/`
  - `seihou-core/test/fixtures/evaluation/typed-dhall-text-flake/`
  - `seihou-core/test/fixtures/evaluation/conditional-template-flake/`
- Specs:
  - `seihou-core/test/Seihou/Evaluation/SplitFlakeSpec.hs`
  - `seihou-core/test/Seihou/Evaluation/DhallTextFlakeSpec.hs`
  - `seihou-core/test/Seihou/Evaluation/TypedDhallTextSpec.hs`
  - `seihou-core/test/Seihou/Evaluation/ConditionalTemplateSpec.hs`
- Prototype modules:
  - `seihou-core/src/Seihou/Engine/TypedDhallText.hs`
  - `seihou-core/src/Seihou/Engine/TemplatePrototype.hs`
