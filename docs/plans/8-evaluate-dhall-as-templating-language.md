---
id: 8
slug: evaluate-dhall-as-templating-language
title: "Evaluate extending Dhall usage as a templating language"
kind: exec-plan
created_at: 2026-04-18T23:38:05Z
intention: "intention_01kjjgfv60e8y9qata1sfk8qrc"
---


# Evaluate extending Dhall usage as a templating language

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

The user hit an ergonomic wall while maintaining a Seihou module in a sibling
repository (`/Users/shinzui/Keikaku/bokuno/seihou-modules`). The `nix-haskell-flake`
module needs to generate a `flake.nix` whose contents branch on whether PostgreSQL
is enabled. Because Seihou's `template` strategy has no in-file conditionals, the
author split the file into two near-duplicate templates,
`files/flake.nix.tpl` and `files/flake-with-postgres.nix.tpl`, each ~55 lines,
differing in **one added line** (`pkgs.postgresql`) and **one ~11-line block**
inside `shellHook`. The module then gates which file to copy with mutually
exclusive `when` conditions on two `Step` records. This is a textbook case of
duplication driven by missing conditional support: any future edit to the
shared 95% has to be made twice, and drift is one forgotten keystroke away.

The user asks whether "extending Dhall usage to be a templating language" would
improve Seihou's power, pointing to a pattern document that frames Dhall as a
typed, pure, total function-evaluation engine. This plan answers that question
concretely by:

1. **Establishing what Seihou already does with Dhall**. Seihou already has a
   `dhall-text` strategy (`.dhall` sources in a module's `files/` directory are
   evaluated to `Text` after placeholder substitution), and a `structured`
   strategy (`.gen` sources evaluated to Dhall records, serialized to JSON or
   YAML). The design doc at
   `docs/dev/design/proposed/generation-strategies.md` describes both as
   implemented. The unit tests under
   `seihou-core/test/Seihou/Engine/PlanSpec.hs` exercise both.

2. **Reproducing the pain point** in this repository, using the real
   `nix-haskell-flake` files, so that every claim about ergonomics is grounded
   in a concrete diff and concrete code.

3. **Prototyping three alternatives** — (A) rewrite the module using the existing
   `dhall-text` strategy, (B) a new "typed function" entry point where a Dhall
   source file exports a `\(vars : Vars) -> Text` function and Seihou applies
   a typed record instead of doing `{{var}}` string substitution, and (C) adding
   in-place conditionals (`{{#if expr}} … {{/if}}`) to the placeholder engine so
   a single `template` file can branch without invoking Dhall at all — and
   measuring each against the real module.

4. **Producing a written, critical evaluation** at
   `docs/dev/design/proposed/dhall-as-templating-evaluation.md` that names
   the tradeoffs honestly: ergonomic traps in the current `dhall-text`
   pipeline, collisions between Dhall's `${}` interpolation and the
   interpolation syntax of Nix, Bash, and Make (all of which Seihou modules
   generate), the type-safety claim vs. the string-substitute-then-evaluate
   reality, error-message locality, and the composition story under each
   alternative.

5. **Making a recommendation** the user can act on. The recommendation lands
   in the evaluation doc's conclusion as one of: stay with current primitives
   and better docs; promote `dhall-text` via a typed-function interface; add
   inline conditionals to `template`; or combine two. The recommendation is
   backed by prototype evidence, not opinion.

The observable outcome for the user is twofold. First, after running
`cabal test seihou-core-test` they can see the three prototypes pass against
fixtures that reproduce the flake split. Second, reading
`docs/dev/design/proposed/dhall-as-templating-evaluation.md` gives them a
clear, critical comparison and a next-step recommendation they can approve,
reject, or redirect.

This plan does **not** implement a new strategy in production. It delivers a
thorough evaluation plus throwaway prototypes. Any production change lands in
a follow-up ExecPlan once the user has chosen a direction.


## Progress

- [x] M1: Reproduce the pain point in-tree. Copy the two flake templates and
      the relevant `module.dhall` stanzas into a fixture under
      `seihou-core/test/fixtures/evaluation/split-flake/` and add a
      regression test that asserts the two generated files differ only in the
      known ways. (Done 2026-04-18; `Seihou.Evaluation.SplitFlakeSpec` 2/2 pass.)
- [x] M1: Produce a minimal, unambiguous diff between
      `flake.nix.tpl` and `flake-with-postgres.nix.tpl` saved as
      `docs/dev/design/proposed/dhall-as-templating-evaluation.diff` so the
      evaluation doc can cite it verbatim. (Done 2026-04-18.)
- [x] M2: Prototype A — rewrite the split as a single `.dhall` source using
      the existing `dhall-text` strategy. Land it under
      `seihou-core/test/fixtures/evaluation/dhall-text-flake/`. Capture exact
      authoring friction: `${}` escaping required for Nix interpolation,
      `{{var}}` quoting rules inside Dhall source, error-message behavior when
      a Dhall type error is introduced. (Done 2026-04-18; friction notes in
      Surprises & Discoveries below.)
- [x] M2: Run the fixture through `compileDhallTextStep` and assert the output
      is byte-for-byte identical to the non-postgres and postgres variants
      when `nix.postgresql` flips. (Done 2026-04-18;
      `Seihou.Evaluation.DhallTextFlakeSpec` 2/2 pass.)
- [x] M3: Prototype B — typed-function `dhall-text`. Add an experimental
      helper (not wired into the dispatcher) in
      `seihou-core/src/Seihou/Engine/Template.hs` or a sibling module that
      evaluates a Dhall source expected to be a `\(vars : <record type>) -> Text`
      function, then applies a record of resolved variables built from
      `Map VarName VarValue`. Write a test that shows the same flake output
      without any `{{var}}` substitution in the source. (Done 2026-04-18;
      helper lives in `seihou-core/src/Seihou/Engine/TypedDhallText.hs`;
      `Seihou.Evaluation.TypedDhallTextSpec` 5/5 pass.)
- [x] M3: Document the record-type construction: how types flow from
      `VarDecl.type` (`text`, `bool`, `int`, `list text`, `choice`) to Dhall
      (`Text`, `Bool`, `Integer`, `List Text`, …). Note any types that do not
      round-trip cleanly. (Done 2026-04-18; see the M3 notes in
      Surprises & Discoveries.)
- [x] M4: Prototype C — inline conditionals in `template`. Extend the
      placeholder parser in `Seihou.Engine.Template` with
      `{{#if <expr>}}`, `{{#else}}`, `{{/if}}` blocks, reusing
      `Seihou.Core.Expr` for the expression grammar (already supports
      `IsSet`, `Eq`, `And`, `Or`, `Not`). Keep it a *prototype*: do not wire
      it into `Strategy`, do not change Dhall schemas. Land the prototype as
      `Seihou.Engine.TemplatePrototype` alongside tests. (Done 2026-04-18;
      `renderTemplatePrototype` takes the source text and resolved vars,
      returns either `[PrototypeError]` or the expanded text.)
- [x] M4: Rewrite the split flake as a single `.tpl` using Prototype C and
      assert byte-for-byte equivalence to both original outputs.
      (Done 2026-04-18; `Seihou.Evaluation.ConditionalTemplateSpec` 4/4 pass.)
- [x] M5: Comparative evaluation. Write
      `docs/dev/design/proposed/dhall-as-templating-evaluation.md` that
      presents the pain point, the three prototypes, and a criteria-based
      comparison (ergonomics, type-safety-in-practice vs. in-claim, error
      locality, composition, novice onboarding, `${}` collision, tooling
      support). Include short code excerpts from each prototype and a
      pros/cons list per alternative. (Done 2026-04-18.)
- [x] M5: Include a "Critical feedback on the user-supplied pattern document"
      section that honestly engages with each claim (templates-as-functions,
      typed inputs, composition, defaults/overrides, imports, and the
      "Template as Data + Interpreter" pattern) and says where it holds up
      and where it does not, given Seihou's actual needs. (Done 2026-04-18.)
- [x] M6: Recommendation. In the final section of the evaluation doc, pick a
      direction and justify it with the prototype evidence. Enumerate the
      concrete follow-up work (which is **not** done in this plan).
      (Done 2026-04-18; recommendation: adopt Prototype C, inline
      conditionals in the `Template` strategy.)
- [x] M6: Summarize outcomes in the Outcomes & Retrospective section of this
      plan and link to the evaluation doc. (Done 2026-04-18.)


## Surprises & Discoveries

### M2 Prototype A — authoring friction against real flake

Working notes captured while writing
`seihou-core/test/fixtures/evaluation/dhall-text-flake/files/flake.nix.dhall`:

- **`{{…}}` in comments also substitutes.** `renderTemplate` runs line-by-line
  across the entire Dhall source, including `--` comments. The first draft
  mentioned `{{var}}` in a docstring and the test failed with
  `unresolved placeholder '{{var}}' at line 6`. The Dhall source can't
  contain the literal four-character sequence `{{…}}` anywhere — not in
  comments, not in strings — unless a matching variable is in scope. You
  can escape with `\{{` per `Seihou.Engine.Template`, but the rule is
  non-obvious for a new author.

- **Seihou renders `Bool` in lowercase; Dhall Bool literals are capitalised.**
  `Seihou.Engine.Template.valueToText` converts `VBool True` to the text
  `"true"`. After substitution `let nixPostgresql = {{nix.postgresql}}`
  becomes `let nixPostgresql = true`, which Dhall rejects with
  `Unbound variable: true`. The workaround is a pair of shim bindings
  `let true = True let false = False` at the top of the file. No error in
  `Seihou.Engine.Plan.compileDhallTextStep` warns the author about this.

- **Every Nix `${…}` interpolation must be escaped.** Nix uses `${…}` the
  same way Dhall does, and the flake has two: `pre-commit-hooks.lib.${system}`
  and `${self.checks.${system}.pre-commit-check.shellHook}`. Both had to be
  written as `''${…}` inside the outer Dhall `''…''` multi-line. One missed
  escape during the first draft produced
  `Unbound variable: system` at an unrelated line, because Dhall tried to
  evaluate `system` as if it were a Dhall identifier.

- **Nix multi-line delimiters `''…''` must be written as `'''…'''` in
  Dhall.** The flake's `shellHook = '' … ''` becomes
  `shellHook = ''' … ''';` in the source. The triple-quote escape is a
  known Dhall feature but reads poorly when an outer `''…''` already
  delimits the whole file and an inner `'''…'''` sits inside it.

- **Dhall multi-line strings strip common leading whitespace.** The
  postgres-specific shell-hook block needs 12 spaces of absolute
  indentation preserved on every line. Using a Dhall multi-line for that
  block made all 12 the common prefix, and Dhall stripped them. Falling
  back to regular `"…"` strings concatenated with `++` and explicit `\n`
  bypassed the rule but replaced a readable multi-line literal with a
  concatenation of 12 one-line strings. This is the largest structural
  penalty of the prototype.

- **Error locality lands in the post-substitution text, not the source.**
  A seeded type error (`let nixPostgresql : Text = True`) reports
  `(input):4:28` — the input being the text handed to `Dhall.input`,
  which is the `.dhall` source after `renderTemplate` has already
  substituted placeholders. For a source where placeholder values happen
  to differ in length from their names, the reported column drifts from
  the source column. A user trying to jump to the reported location in
  their editor will miss.

Despite the friction, the prototype does solve the duplication: one
~100-line source replaces two ~55-line and ~68-line templates, and the
output is byte-identical to both baselines under
`cabal test seihou-core-test -p DhallTextFlake`.

### M3 Prototype B — typed-function renderer

Notes from writing
`seihou-core/src/Seihou/Engine/TypedDhallText.hs` and its fixture at
`seihou-core/test/fixtures/evaluation/typed-dhall-text-flake/`:

- **`{{var}}` friction disappears.** The source file is a real Dhall
  function; it is never fed through `renderTemplate`. Authors can use
  literal `{{…}}` in comments or strings without special handling.
  The lowercase/capital Bool problem also goes away because `True`
  and `False` are constructed directly by the record builder, not by
  stringifying `VarValue`.

- **Field-name mapping is deterministic but surprising.** `fieldNameFor`
  replaces `.` and `-` with `_`, so the author's lambda must refer to
  `vars.nix_process_compose`, not `vars.nix.process-compose`. This
  mapping is not visible to the author of the source file unless it
  is documented in the evaluation doc. Using Dhall's backtick-quoted
  field names (``vars.`nix.process-compose` ``) would preserve the
  original names, at the cost of heavier syntax.

- **Type errors name the offending field.** The seeded typo test in
  `TypedDhallTextSpec` confirms that a mismatch between the lambda's
  record type and the supplied record produces a Dhall error whose
  text contains the offending field name. Locality is better than
  under Prototype A because the error is against the user's *typed*
  source rather than a string-substituted copy.

- **`VarValue` → Dhall type mapping.**

  | VarValue  | Dhall        | Notes                                   |
  |-----------|--------------|-----------------------------------------|
  | `VText`   | `Text`       | Backslash, quote, `$` escaped.          |
  | `VBool`   | `Bool`       | Direct.                                 |
  | `VInt`    | `Integer`    | Sign prefix (`+n` / `-n`) emitted.      |
  | `VList a` | `List <T>`   | `<T>` inferred from first element.      |
  | `VChoice` | `Text`       | Seihou stores Choice as a validated    |
  |           |              | Text, so the record sees `Text`.        |

  Nested lists (`VList (VList …)`) fall back to `List Text` and are a
  known prototype limitation.

- **Nix/Dhall escaping friction is identical to Prototype A.**
  `${…}` collisions with Nix, `''…''` vs `'''…'''` for Nix multi-line
  delimiters, and common-leading-whitespace stripping still apply,
  because those are artifacts of Dhall's multi-line syntax — not of
  the placeholder pipeline.

### M4 Prototype C — inline conditionals in `template`

Notes from writing
`seihou-core/src/Seihou/Engine/TemplatePrototype.hs` and the fixture
at `seihou-core/test/fixtures/evaluation/conditional-template-flake/`:

- **The fixture reads almost identically to the original template.**
  The single source is the non-postgres flake with two
  `{{#if Eq nix.postgresql true}}…{{/if}}` blocks — one around the
  lone `pkgs.postgresql` line, one around the 11-line shell-hook
  addendum. No Dhall, no escaping, no indentation stripping, no
  `${…}` collisions. The diff against the original `.tpl` is exactly
  the two block pairs plus the lines they gate.

- **Grammar reuse was free.** `{{#if <expr>}}` feeds straight into
  `Seihou.Core.Expr.parseExpr`, which already supports `IsSet`, `Eq`,
  `&&`, `||`, `!`, `true`/`false`, and parentheses. No new parser or
  AST needed — the test showing `IsSet maybe` returns `False` for an
  unset variable works without additional code.

- **One-level nesting cap is a real limitation but didn't hurt this
  fixture.** The block structure in the flake is two flat
  `{{#if …}}…{{/if}}` regions, neither nested inside the other. A
  promotion to first-class would likely need unbounded nesting, which
  the prototype's depth-1 rejection would make invasive to lift.

- **Line-number accuracy is acceptable.** The seeded
  `UnterminatedIf` test reports line 3 for a `{{#if}}` on line 3 of
  the source. No string-substitute-then-parse dance pollutes the
  line numbers, so unlike Prototype A an editor can jump directly to
  the offender.

- **Scope of the prototype is tiny.** ~180 lines of code in one new
  module, one fixture, one spec module. It does not touch
  `Seihou.Engine.Template`, `Seihou.Engine.Plan`, or the `Strategy`
  enum; discarding it costs nothing.


## Decision Log

- Decision: Deliverable is a written evaluation plus throwaway prototypes,
  not a production strategy.
  Rationale: The user asked to *evaluate*, not to ship. Writing a new
  strategy without a decision is premature. Prototypes are the minimum needed
  to ground the evaluation in real code behavior; they live under
  `seihou-core/test/fixtures/evaluation/` and the experimental module
  `Seihou.Engine.TemplatePrototype`, clearly isolated from production code.
  Date: 2026-04-18

- Decision: Prototype C (inline conditionals in `template`) is included even
  though the user's prompt only asked about Dhall.
  Rationale: The user's underlying problem is duplicated text, not "I want
  more Dhall." A fair evaluation has to compare against the simplest fix that
  plausibly solves the problem. If `{{#if}}` turns out to be sufficient for
  the reported pain and avoids Dhall's ergonomic traps, the honest answer to
  "should we extend Dhall as a templating language?" may be "no, extend the
  placeholder engine instead." Withholding this comparison would bias the
  evaluation toward the user's phrased hypothesis.
  Date: 2026-04-18

- Decision: Prototype B is a standalone helper, not a new `Strategy`
  variant.
  Rationale: Adding a new enum case ripples through `Strategy` decoders,
  `Operation` wiring, manifest `FileRecord.strategy`, and every pattern
  match in `Seihou.Engine.Plan`, `Seihou.Engine.Execute`, `Diff.hs`, and
  `Preview.hs` — that cost is justified only after a decision is made. A
  standalone helper in `Seihou.Engine.Template` (or a sibling module) can
  be called from a test without touching the dispatcher and discarded
  cheaply if the evaluation rejects it.
  Date: 2026-04-18

- Decision: The evaluation will name specific risks by name, not hedge.
  Rationale: The user explicitly asked for *critical* feedback. A "balanced"
  write-up that refuses to name weaknesses of Dhall-as-template would fail
  the brief. Each risk gets called out with an example from this repo
  (Nix `${}` collision in `flake.nix`, Bash `${}` in shell commands,
  Dhall string literals requiring explicit `''…''` multi-line form, the
  fact that `renderDhallText` in `Seihou.Engine.Plan` does placeholder
  substitution *into* Dhall source, which defeats the type-safety claim).
  Date: 2026-04-18


## Outcomes & Retrospective

### What was delivered

- Three prototype fixtures under
  `seihou-core/test/fixtures/evaluation/` (split-flake, dhall-text-flake,
  typed-dhall-text-flake, conditional-template-flake) reproducing the
  pain point and exercising each alternative.
- Two experimental modules: `Seihou.Engine.TypedDhallText` and
  `Seihou.Engine.TemplatePrototype`, both reachable only from tests.
- Four new spec modules under `seihou-core/test/Seihou/Evaluation/`
  contributing 13 passing specs. Full suite: 695/695 pass.
- Ground-truth diff at
  `docs/dev/design/proposed/dhall-as-templating-evaluation.diff`.
- Evaluation document at
  `docs/dev/design/proposed/dhall-as-templating-evaluation.md` with the
  pain point, three prototypes, critical engagement with the seven
  claims in the user's pattern document, a criteria-based comparison
  table, and a single recommendation.

### Recommendation

**Adopt Prototype C — inline `{{#if}}`/`{{/if}}`/`{{#else}}` in the
`Template` strategy.** Keep `DhallText` and `Structured` as they
stand. The reported pain is duplicated text with one toggle; the
closest fix is a minimal extension to the placeholder engine the
user is already writing. Prototype B's type-safety story is
genuinely better than production `DhallText`, but its Nix-escaping
tax doesn't disappear and it is the wrong answer for
"duplicate-text-with-a-toggle."

### Followup ExecPlans (not done here)

- Promote `Seihou.Engine.TemplatePrototype` to
  `Seihou.Engine.Template`, lifting the 1-level nesting cap.
- Extend `docs/dev/design/proposed/generation-strategies.md` with a
  "Conditional blocks" subsection and a worked split-avoidance
  example.
- Migrate the sibling `nix-haskell-flake` module to a single
  conditional template, and investigate the
  `Eq nix.postgresql false || Eq nix.postgresql "false"` double-guard
  as a separate bug report against the expression comparator.

### Lessons

- **Placeholder substitution before Dhall evaluation is a
  type-safety leak.** Authors can write sources that look typed
  but whose real input is string-substituted text. Prototype A's
  `true`/`True` shim and quoted-var trap are symptoms of this.
- **Nix/Dhall `${}` and `''…''` collision is a permanent cost** of
  any Dhall-based text strategy when the output is a `.nix` file.
  Neither Prototype A nor B eliminates it; Prototype C avoids it
  entirely by not involving Dhall.
- **The pain point drives the answer.** Framing the user's
  question as "should we extend Dhall?" would have pushed toward
  B. Framing as "how do we stop duplicating text with a toggle?"
  makes C obvious. Including C in the evaluation — even though
  the user asked only about Dhall — was the most consequential
  decision in this plan.

### Links

- Evaluation doc:
  `docs/dev/design/proposed/dhall-as-templating-evaluation.md`
- Diff file:
  `docs/dev/design/proposed/dhall-as-templating-evaluation.diff`


## Context and Orientation

The reader is assumed to know nothing about this repository. This section
gives the orientation needed to understand the rest of the plan.


### What Seihou is

Seihou is a Haskell project scaffolding system. A user authors a "module" —
a directory with a `module.dhall` file and a `files/` subdirectory — that
declares variables, prompts, steps, and dependencies. The CLI (`seihou`)
resolves variables (from CLI flags, environment, config files, prompts,
defaults), compiles the steps into filesystem operations, and executes them
against a target project directory. Each step names a *strategy* that
determines how its source file is transformed.

The strategies are declared in `seihou-core/src/Seihou/Core/Types.hs`:

    data Strategy = Copy | Template | DhallText | Structured

and dispatched in `seihou-core/src/Seihou/Engine/Plan.hs` inside
`compileStep`:

    case step.strategy of
      Copy       -> compileCopyStep baseDir vars step
      Template   -> compileTemplateStep baseDir vars step
      DhallText  -> compileDhallTextStep baseDir vars step
      Structured -> compileStructuredStep baseDir vars step

The strategies are:

- **Copy** — source bytes are written to destination unchanged.
- **Template** — text file with `{{var.name}}` placeholders. Placeholders
  are substituted by `renderTemplate` in
  `seihou-core/src/Seihou/Engine/Template.hs`. There is **no conditional
  or loop syntax** at the template level; the only way to exclude text is
  to put it in a separate file whose `Step` has a `when = Some "<expr>"`
  gating the whole file.
- **DhallText** — a `.dhall` file under `files/` that is expected to
  evaluate to a Dhall `Text` value. `compileDhallTextStep` first runs
  `renderTemplate` over the raw `.dhall` source (treating it as text),
  substituting `{{var.name}}` occurrences, and then invokes
  `Dhall.input Dhall.strictText` (via the `renderDhallText` helper in
  `Seihou.Engine.Plan`) on the substituted text to produce the final
  output. Two phases: string substitute, then Dhall evaluate.
- **Structured** — a `.gen` file whose Dhall expression evaluates to a
  record. The record is converted to JSON via the internal
  `Seihou.Engine.DhallJSON` module (a 45-line fallback for GHC 9.12.2
  compatibility, see `docs/plans/add-template-engine-integration.md`) and
  then serialized to JSON or YAML based on the destination extension.

The `when` expression on a `Step` is parsed by
`Seihou.Core.Expr.parseExpr` into an `Expr` AST:

    data Expr
      = Eq VarName VarValue
      | And Expr Expr
      | Or Expr Expr
      | Not Expr
      | IsSet VarName
      | Literal Bool

The expression grammar (documented in
`docs/dev/design/proposed/variable-resolution.md`, section "Expression
Language") is: `||`, `&&`, `!`, plus the atoms `IsSet <varname>`,
`Eq <varname> <value>`, `true`, `false`, and parentheses.


### The exact pain point

The module at
`/Users/shinzui/Keikaku/bokuno/seihou-modules/modules/haskell/nix-haskell-flake/`
has a `files/` directory containing two templates for the same output:

    files/flake.nix.tpl                  (54 lines, no postgres)
    files/flake-with-postgres.nix.tpl    (68 lines, postgres variant)

The `module.dhall` gates them with mutually exclusive conditions:

    S.Step::{
    , strategy = "template"
    , src = "flake.nix.tpl"
    , dest = "flake.nix"
    , when = Some "Eq nix.postgresql false || Eq nix.postgresql \"false\""
    }
    , S.Step::{
    , strategy = "template"
    , src = "flake-with-postgres.nix.tpl"
    , dest = "flake.nix"
    , when = Some "Eq nix.postgresql true || Eq nix.postgresql \"true\""
    }

Diffing the two files (the exact diff lands in M1, but the shape is):

- Line 40: `flake-with-postgres` adds `pkgs.postgresql` to
  `nativeBuildInputs` in the `devShells.default` `mkShell` block.
- Lines 49–60: `flake-with-postgres` appends 11 lines to `shellHook` that
  set `PGHOST`, `PGDATA`, `PGLOG`, `PGDATABASE`, `PG_CONNECTION_STRING`,
  create the data dir, and run `initdb` if missing.

Everything else is identical, and every `{{project.name}}`,
`{{project.description}}`, `{{ghc.version}}`, `{{nix.process-compose}}`
appears in both files at the same location. Any future change to
`nativeBuildInputs`, `formatter`, the `checks` block, or the
`packages.default` binding requires the author to edit two files,
identically, in lockstep.

The `when` clauses also write "`Eq nix.postgresql \"false\"`" in addition
to `Eq nix.postgresql false`. That duplication hints at a separate, smaller
bug in the expression comparator that was worked around by covering both the
boolean and string-coerced representations. It is out of scope for this
plan but worth a note in Surprises & Discoveries if reproduced.


### The user-supplied pattern document

The user's prompt includes a document titled *"Using Dhall as a Templating
Language"* that argues Dhall can express templating as a special case of
function evaluation. Its main claims are:

1. Templates are functions `\(input : T) -> Text`.
2. Typed inputs give compile-time guarantees about shape.
3. Function composition replaces ad-hoc string concatenation.
4. Record merge (`//`, `⫽`) supports defaults with overrides.
5. Imports let templates be split across files and reused.
6. Dhall can emit structured data (JSON, YAML) as well as text.
7. The "Template as Data + Interpreter" pattern treats Dhall as a typed
   DSL whose output is a data structure the CLI interprets.

The pattern doc ends with a table contrasting "traditional templating"
against Dhall along six axes, and a list of when-to-use / when-to-avoid
heuristics.

The evaluation doc produced by M5 will engage with each of these claims,
not dismiss them.


### What's already in the repo that looks relevant

- `seihou-core/src/Seihou/Engine/Template.hs` — the placeholder engine
  (`renderTemplate`, `valueToText`, `renderDestPath`, `renderCommand`).
  95 lines. No conditionals.
- `seihou-core/src/Seihou/Engine/Plan.hs` — strategy dispatch,
  `compileDhallTextStep`, `compileStructuredStep`, `renderDhallText`
  helper that invokes `Dhall.input Dhall.strictText`.
- `seihou-core/src/Seihou/Dhall/Eval.hs` — loads `module.dhall` using
  `inputExprWithSettings` with a custom decoder. This is the piece that
  understands Dhall-to-Haskell data flow.
- `seihou-core/src/Seihou/Engine/DhallJSON.hs` — the fallback
  Dhall-expression-to-Aeson-Value converter.
- `seihou-core/test/fixtures/haskell-base/files/cabal.project.dhall` —
  the canonical DhallText example in-tree. Three lines of Dhall source
  wrap the `{{project.name}}` substitution and produce a one-line
  `cabal.project`.
- `seihou-core/test/Seihou/Engine/PlanSpec.hs` — tests for
  `compileDhallTextStep`, including the "Dhall string interpolation"
  case.
- `docs/dev/design/proposed/generation-strategies.md` — the authoritative
  spec for strategies, with example `.dhall` sources for flakes and
  cabal files. Useful to cite.
- `docs/plans/add-template-engine-integration.md` — prior ExecPlan that
  wired `DhallText` and `Structured` through the manifest. Shows how
  strategies thread through the codebase, for scope sizing.


### Terms used below

- **Strategy** — one of `Copy`, `Template`, `DhallText`, `Structured`.
  Selected per step in `module.dhall`.
- **Source** — the file in `files/` named by a step's `src` field.
- **Placeholder** — a `{{name}}` occurrence in a source file, substituted
  by the `renderTemplate` engine.
- **`when` gate** — an optional `Expr` on a `Step` that decides whether
  the step executes at all.
- **Composition** — running multiple modules together in dependency
  order. Documented in
  `docs/dev/design/proposed/composition-and-layering.md`.
- **Patch op** — `append-file`, `prepend-file`, `append-section`,
  `append-line-if-absent`. Used when multiple modules target the same
  output file. Documented in the same composition doc.


## Plan of Work

The work splits into six milestones, ordered so that each milestone can be
verified independently and so that the last step is writing the evaluation
doc with all evidence in hand.


### Milestone 1 — Reproduce the pain point in-tree

Goal: establish ground truth in this repository so every later milestone
can refer to it.

Create the directory
`seihou-core/test/fixtures/evaluation/split-flake/`. Inside it, put:

- `module.dhall` — a minimized stand-in for the real
  `nix-haskell-flake` module, declaring only the variables needed to
  reproduce the split (`project.name`, `project.description`,
  `ghc.version`, `nix.process-compose`, `nix.postgresql`). Use the
  same two `Step` records with mutually exclusive `when` gates.
- `files/flake.nix.tpl` — verbatim copy from the source repo.
- `files/flake-with-postgres.nix.tpl` — verbatim copy from the source
  repo.

Add a Spec file
`seihou-core/test/Seihou/Evaluation/SplitFlakeSpec.hs` (new directory,
add to `seihou-core.cabal` `other-modules`) with two cases:

1. With `nix.postgresql = False`, `compilePlan` produces exactly one
   `WriteFileOp` targeting `flake.nix` whose content matches
   `files/flake.nix.tpl` after placeholder substitution.
2. With `nix.postgresql = True`, `compilePlan` produces exactly one
   `WriteFileOp` targeting `flake.nix` whose content matches
   `files/flake-with-postgres.nix.tpl` after placeholder substitution.

This test is the regression harness: when a later prototype claims to
replace both templates with one source, the test re-runs with the
alternative input and the output must match byte-for-byte.

Also produce `docs/dev/design/proposed/dhall-as-templating-evaluation.diff`
by running `diff -u files/flake.nix.tpl files/flake-with-postgres.nix.tpl`
and checking the output into the repo. The evaluation doc will embed
excerpts from this diff.

Acceptance:

    cabal test seihou-core-test

prints (among the other specs) two passing cases under
`SplitFlakeSpec`, and
`docs/dev/design/proposed/dhall-as-templating-evaluation.diff` exists and
is exactly the `diff -u` output of the two fixture templates.


### Milestone 2 — Prototype A: rewrite with existing `dhall-text`

Goal: determine whether the *existing* `DhallText` strategy is sufficient
to solve the pain point, and characterize its authoring ergonomics.

Create a sibling fixture directory
`seihou-core/test/fixtures/evaluation/dhall-text-flake/`. Inside it:

- `module.dhall` — single step using `strategy = "dhall-text"` targeting
  `flake.nix`, with the same variables as the split-flake fixture.
- `files/flake.nix.dhall` — one `.dhall` source that evaluates to `Text`
  and produces either the postgres or the non-postgres variant based on
  the resolved `nix.postgresql` value.

The authoring challenge is non-trivial and must be worked through for
real rather than waved at:

1. The target is a Nix flake. Every `${system}`, `${vars.projectName}`,
   etc. in Nix conflicts with Dhall's own `${…}` interpolation. Inside
   the Dhall source, the Nix interpolations must appear inside a Dhall
   multi-line string `''…''`, and each `${` that is meant for Nix (not
   Dhall) must be written as `''${` to escape Dhall's interpolation.
   This escaping is a known Dhall feature but easy to get wrong.
2. The current `compileDhallTextStep` runs `renderTemplate` over the
   `.dhall` source *before* Dhall evaluates it. That means
   `{{project.name}}` in the source becomes a bare token in the Dhall
   text. For it to be a valid Dhall value, the author has to quote it:
   `let projectName = "{{project.name}}"`. For a boolean variable,
   `{{nix.postgresql}}` substitutes to the bare token `true` or `false`,
   which Dhall accepts as `Bool`. Type mismatches are detected only at
   Dhall evaluation, with errors phrased in terms of the substituted
   text, not the user's source.
3. Dhall does not have native "if this multi-line block, else that"
   sugar. The author uses `if cond then ''…'' else ''…''` — with two
   multi-line strings. The strings must both type-check as `Text`, so
   any interpolation inside either string must resolve. This is fine
   for `cond` being a constant `Bool` from a placeholder substitution.
4. Error messages from `Dhall.input` point into the post-substitution
   text. Reproduce this by seeding a type error and capturing the
   error surface.

Write the `.dhall` source honestly — no heroic optimizations. Target
line count is likely ~70 lines (roughly equal to the longer template,
because conditional blocks come with both branches plus `if`/`then`/`else`
glue). Note it either way.

Add a Spec file
`seihou-core/test/Seihou/Evaluation/DhallTextFlakeSpec.hs`:

1. With `nix.postgresql = False`, the fixture produces bytes identical
   to the non-postgres variant from M1.
2. With `nix.postgresql = True`, the fixture produces bytes identical
   to the postgres variant from M1.

During implementation, capture concrete friction points in the Surprises
& Discoveries section of this plan, with short code excerpts:

- The `${` escaping instances and where they bit.
- Any placeholder that had to be quoted unnaturally.
- One sample Dhall error message for a seeded type error, so the
  evaluation doc can compare error locality across prototypes.

Acceptance: `cabal test seihou-core-test` passes including the two new
cases, and the Surprises section lists at least three concrete friction
notes drawn from implementing the fixture.


### Milestone 3 — Prototype B: typed-function `dhall-text`

Goal: demonstrate what "Dhall as a templating language *without* the
string-substitution hack" would actually look like, so the evaluation
has a concrete specimen rather than a thought experiment.

Add a new experimental module
`seihou-core/src/Seihou/Engine/TypedDhallText.hs` (and list it in
`seihou-core.cabal`). It exports one function:

    renderTypedDhallText
      :: FilePath             -- Source .dhall file (absolute or base-relative)
      -> Map VarName VarValue -- Resolved variables
      -> IO (Either Text Text)

The function:

1. Reads the source file.
2. Builds a Dhall record expression from the `Map VarName VarValue`
   whose field names are the variable names (with `.` replaced by `_`
   to produce valid Dhall identifiers; document the mapping) and whose
   values are typed Dhall literals (`Text`, `Bool`, `Integer`,
   `List Text`, …) derived from each `VarValue`.
3. Parses the source as a Dhall expression expecting type
   `<varsType> -> Text` where `<varsType>` is inferred from the record
   it built.
4. Applies the expression to the record and normalizes.
5. Extracts the resulting `Text` and returns it.

The source file in the fixture looks like:

    \(vars :
        { projectName      : Text
        , projectDescription : Text
        , ghcVersion       : Text
        , nixProcessCompose : Bool
        , nixPostgresql     : Bool
        }
      ) ->
        let shellHook =
              if vars.nixPostgresql
              then "…postgres env setup…"
              else ""
        in ''
          {
            description = "${vars.projectDescription}";
            …
            devShells.default = pkgs.mkShell {
              nativeBuildInputs = [
                …
                ${if vars.nixPostgresql then "pkgs.postgresql" else ""}
                …
              ];
              shellHook = ''${shellHook}'';
            };
          }
        ''

No `{{var}}` substitution is involved. The author references vars
through typed record fields only; Dhall's typechecker catches misspelled
field names at evaluation time.

Add a fixture directory
`seihou-core/test/fixtures/evaluation/typed-dhall-text-flake/` mirroring
M2's structure, with `files/flake.nix.dhall` as the typed-function
variant.

Add a Spec file
`seihou-core/test/Seihou/Evaluation/TypedDhallTextSpec.hs`:

1. With `nix.postgresql = False`, `renderTypedDhallText` produces bytes
   matching M1's non-postgres variant.
2. With `nix.postgresql = True`, it produces the postgres variant.
3. A seeded field-name typo (`vars.nixPostgres` instead of
   `vars.nixPostgresql`) produces a Dhall type error that mentions the
   field name. Assert `"nixPostgres"` appears in the error text.

Document in the Surprises section:

- How the variable-name mapping was resolved (did `.` get replaced by
  `_`, or did the record use quoted field names like `vars."nix.postgresql"`?)
- Any `VarValue` constructor that did not map cleanly (the Choice type,
  per `variable-resolution.md`, is represented as `Text` with a
  validated options list — note whether the prototype treats it as
  `Text` or a Dhall union).
- Any difference in error-message quality vs. Prototype A.

Do **not** wire `renderTypedDhallText` into `Seihou.Engine.Plan`'s
strategy dispatcher. It must remain callable only from tests.

Acceptance: `cabal test seihou-core-test` passes the three new cases.
`Seihou.Engine.Plan.compileStep` has **not** been modified. The
evaluation doc can quote the `.dhall` source verbatim as "what the
typed-function approach reads like."


### Milestone 4 — Prototype C: inline conditionals in `template`

Goal: demonstrate the cheapest alternative that plausibly solves the
stated pain — adding `{{#if}}`/`{{/if}}` to the existing placeholder
engine — without involving Dhall at all.

Add a new experimental module
`seihou-core/src/Seihou/Engine/TemplatePrototype.hs`. It exports:

    renderTemplatePrototype
      :: Text                 -- Template source
      -> Map VarName VarValue -- Resolved variables
      -> Either [PlaceholderError] Text

The parser extends the existing tokenization in
`Seihou.Engine.Template` with three new block tokens:

- `{{#if <expr>}}` — start of a conditional block. `<expr>` uses
  `Seihou.Core.Expr.parseExpr` (already supports `IsSet`, `Eq`, `&&`,
  `||`, `!`). The expression is evaluated against the variable map
  using `Seihou.Core.Expr.evalExpr`.
- `{{#else}}` — optional; begins the else branch.
- `{{/if}}` — end of block.

Nesting depth is limited to 1 for the prototype (document the limit).
Any `{{#if}}` without a matching `{{/if}}` produces a
`MalformedPlaceholder` error naming the opening line.

Add `{{#if}}`-specific error variants to an internal error type if
needed — the prototype can define its own error sum type so
production `PlaceholderError` is not disturbed.

Create fixture
`seihou-core/test/fixtures/evaluation/conditional-template-flake/`
with a single `files/flake.nix.tpl` that uses `{{#if IsSet nix.postgresql && Eq nix.postgresql true}}…{{/if}}`
blocks to gate the postgres-specific lines.

Add Spec
`seihou-core/test/Seihou/Evaluation/ConditionalTemplateSpec.hs`:

1. With `nix.postgresql = False`, output matches the non-postgres
   variant from M1.
2. With `nix.postgresql = True`, output matches the postgres variant.
3. Unterminated `{{#if}}` produces an error whose message names the
   opening line number.
4. A `{{#if}}` whose expression references an unset variable via
   `IsSet` returns `False` (per the documented semantics of `IsSet`
   in `variable-resolution.md`) and excludes the block without
   emitting an error.

Do **not** modify `Seihou.Engine.Template` or the `Strategy` enum.

Acceptance: `cabal test seihou-core-test` passes the four new cases.
The production `Template` strategy still routes through
`Seihou.Engine.Template.renderTemplate` unchanged.


### Milestone 5 — Write the evaluation

Goal: synthesize everything above into
`docs/dev/design/proposed/dhall-as-templating-evaluation.md`,
following the rei-style format used by other docs under
`docs/dev/design/proposed/` (Status, Overview, Motivation, Design
Decisions, Domain Model where relevant, Business Rules, Edge Cases,
Testing Plan, Future Enhancements, Cross-References).

The document has these sections:

1. **Overview** — state the pain point in two paragraphs, citing the
   M1 fixture and the checked-in diff.
2. **Current state** — summarize what `Copy`, `Template`, `DhallText`,
   and `Structured` actually do today, with a short code pointer to
   each dispatch case in `Seihou.Engine.Plan`. Explicitly point out
   that `DhallText` does placeholder substitution *before* Dhall
   evaluation.
3. **The user's hypothesis** — faithfully summarize the "Using Dhall
   as a Templating Language" pattern document (the seven claims
   enumerated in Context and Orientation above). Quote short passages.
4. **Three prototypes** — for each of A, B, C:
   - Describe what it is in two sentences.
   - Show the core source excerpt (10–20 lines).
   - State the line count for the combined output compared to the
     two-file split baseline.
   - List authoring friction as a short bulleted list, grounded in
     the Surprises & Discoveries entries from M2–M4.
   - Show one representative error message surfaced by a seeded
     mistake, for error-locality comparison.
5. **Critical feedback on the pattern document** — engage with each of
   the seven claims:
   - *Templates as functions* — true in principle; in practice,
     `Seihou.Engine.Plan.compileDhallTextStep` does string
     substitution first, which breaks the purity claim for the
     substituted region. Note.
   - *Typed inputs* — true only if Prototype B's approach is adopted.
     Under current `DhallText`, there is no type-checked Vars record;
     there's a string-substituted source.
   - *Composition* — Dhall's `++`, `//`, `⫽` are real, but they compose
     Dhall values, not files. Seihou's existing composition happens
     at the file-system plan layer (see
     `docs/dev/design/proposed/composition-and-layering.md`) and is
     not affected by any of the three prototypes.
   - *Defaults and overrides via record merge* — Seihou already handles
     variable defaults and overrides in
     `Seihou.Core.Variable` with a 9-level precedence chain. Dhall's
     record merge would duplicate this mechanism, not replace it.
   - *Imports for reuse* — Dhall imports work; a `.dhall` source file
     can import other `.dhall` files from the module's `files/`
     directory. Useful for genuinely shared Dhall functions. No
     existing Seihou module uses this; worth a note.
   - *Dhall emits JSON/YAML* — Already covered by `Structured`. Not
     new.
   - *Template as data + interpreter* — Worth discussing honestly:
     this is what `module.dhall` already is. The whole `Module` value
     (including the `Step` list) is exactly "Dhall as data, CLI as
     interpreter." The pattern is already adopted at the module
     level, just not at the per-file level.
6. **Comparison table** — rows: Ergonomics, Type safety (in practice),
   Error locality, Composition, Novice onboarding, `${}` collision,
   Tooling, Scope of change. Columns: Current state (two files),
   Prototype A, Prototype B, Prototype C.
7. **Recommendation** — one of:
   - *Stay and document.* The fix for the user's pain is to rewrite
     the module using the existing `dhall-text` strategy (Prototype A)
     and to update `docs/dev/design/proposed/generation-strategies.md`
     with a worked "split avoidance" example. No code change.
   - *Promote to typed-function DhallText.* Replace or augment the
     current `DhallText` dispatcher with Prototype B's approach,
     accepting the migration cost on existing `.dhall` sources (just
     `cabal.project.dhall` in-tree plus user modules). Rationale: the
     type-safety claim in the pattern document only holds under this
     approach.
   - *Add conditionals to Template.* Promote Prototype C to a first
     class feature. Keep `Template` for text files, leave
     `DhallText`/`Structured` for structured outputs where Dhall's
     value-oriented nature genuinely pays off. Rationale: the
     reported pain is about duplicated text, not about missing
     typed function evaluation; the simpler fix is the closer fix.
   - *Combine B and C.* Offer both; use C for simple branching,
     use B for complex structured text.

   Pick one. Justify with prototype evidence. Do not hedge. The user
   asked for critical feedback.

8. **Followup work** — list the concrete ExecPlans that would
   implement the recommendation. Do **not** author them in this plan.

Acceptance: the file
`docs/dev/design/proposed/dhall-as-templating-evaluation.md` exists,
cross-references the three fixtures, cites the M1 diff file, and its
"Recommendation" section names exactly one of the four options with
a one-paragraph justification.


### Milestone 6 — Outcomes & cleanup

Goal: close the plan so it can be restarted from only this document.

Fill in Outcomes & Retrospective on this plan with: the chosen
recommendation, a pointer to the evaluation doc, and a pointer to any
follow-up ExecPlans the user decides to open.

Run `nix fmt` (or the project's `just fmt`, whichever is current per
`Justfile`) on all changed Haskell files and confirm clean.

Run `cabal test seihou-core-test` and record the final pass count in
the retrospective.

Commit everything under a single final commit named:

    Evaluate Dhall-as-templating: prototypes + written evaluation

    Adds three prototype fixtures and one evaluation doc. No
    production code paths changed. Recommends <chosen option>.

    ExecPlan: docs/plans/8-evaluate-dhall-as-templating-language.md
    Intention: intention_01kjjgfv60e8y9qata1sfk8qrc

Acceptance: `git log -1` shows the commit with both trailers.
`docs/plans/8-evaluate-dhall-as-templating-language.md` has its
Outcomes & Retrospective section filled in.


## Concrete Steps

Run all commands from the repository root
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou` unless stated
otherwise.

Before starting, confirm the baseline builds:

    cabal build all

Expected: no errors; possibly warnings. Record build time in the
Surprises section if it feels unusually long.

For M1, copy the real flake templates in:

    cp /Users/shinzui/Keikaku/bokuno/seihou-modules/modules/haskell/nix-haskell-flake/files/flake.nix.tpl \
       seihou-core/test/fixtures/evaluation/split-flake/files/flake.nix.tpl
    cp /Users/shinzui/Keikaku/bokuno/seihou-project/seihou/../seihou-modules/modules/haskell/nix-haskell-flake/files/flake-with-postgres.nix.tpl \
       seihou-core/test/fixtures/evaluation/split-flake/files/flake-with-postgres.nix.tpl

Generate the diff file:

    diff -u seihou-core/test/fixtures/evaluation/split-flake/files/flake.nix.tpl \
            seihou-core/test/fixtures/evaluation/split-flake/files/flake-with-postgres.nix.tpl \
      > docs/dev/design/proposed/dhall-as-templating-evaluation.diff

Expected transcript (prefix only):

    --- .../flake.nix.tpl
    +++ .../flake-with-postgres.nix.tpl
    @@ -37,6 +37,7 @@
             pkgs.pkg-config
    +        pkgs.postgresql

Continue with M2–M6 as outlined above. For each new Spec file, add its
module to the `other-modules` stanza in `seihou-core/seihou-core.cabal`
and verify with:

    cabal test seihou-core-test

and record the spec counts in this document as you go.

If the `dhall` library build fails on a typed-function expression in
M3, capture the error in Surprises & Discoveries. One likely cause:
Dhall's `input` function expects the source to have a Dhall type
annotation at the top, or to be applied against a `Type` the caller
supplies. Resolve by using `Dhall.Core.normalize` and `Dhall.TypeCheck`
from `Dhall.Core` directly rather than `Dhall.input`, the same escape
hatch used in `Seihou.Dhall.Eval.evalModuleFromFile` for the
`dependencies` field.


## Validation and Acceptance

The plan is complete when all of the following are true:

1. `cabal test seihou-core-test` passes, and the test output includes
   at least nine new specs across
   `SplitFlakeSpec`, `DhallTextFlakeSpec`, `TypedDhallTextSpec`, and
   `ConditionalTemplateSpec`.
2. `docs/dev/design/proposed/dhall-as-templating-evaluation.md` exists,
   has every section listed in M5, includes the comparison table, and
   names exactly one recommendation with justification.
3. `docs/dev/design/proposed/dhall-as-templating-evaluation.diff`
   exists and is the direct `diff -u` output of the two split
   templates.
4. The production strategy dispatcher
   (`Seihou.Engine.Plan.compileStep`) is unchanged. `git diff master --stat`
   on `seihou-core/src/Seihou/Engine/Plan.hs` shows zero lines added
   or removed.
5. A user reading only this ExecPlan, the evaluation doc, and the
   three fixture directories can reconstruct the reasoning, re-run
   the prototypes, and make their own decision.
6. The final commit carries both the `ExecPlan:` and `Intention:`
   trailers.


## Idempotence and Recovery

All steps are additive. If implementation stalls in any milestone, the
branch can be force-reset to `master` with no cleanup in production code
(nothing in production is modified). Rebuilding from scratch costs only
the time to recreate the fixtures.

If a prototype milestone discovers a genuine blocker (e.g., the Dhall
library cannot type-check a typed function with the field-naming
strategy chosen), record the blocker in Surprises & Discoveries and
update the Plan of Work to narrow the prototype's scope. Do **not**
abandon the evaluation; a blocker on Prototype B is itself a finding
that belongs in the evaluation doc.

If `cabal build` starts failing partway through M3 because the
experimental `TypedDhallText` module imports something unavailable on
GHC 9.12.2 (compare to the `dhall-json` incompatibility captured in
`docs/plans/add-template-engine-integration.md`), check the import
list against the `dhall` API surface already used by
`Seihou.Dhall.Eval` and `Seihou.Engine.Plan` — those modules represent
the GHC-9.12.2-safe baseline.


## Interfaces and Dependencies

No new library dependencies are introduced. The work reuses:

- The existing `dhall` library as used in
  `seihou-core/src/Seihou/Dhall/Eval.hs` and
  `seihou-core/src/Seihou/Engine/Plan.hs`.
- `Seihou.Core.Expr` for expression parsing and evaluation in
  Prototype C.
- `Seihou.Engine.Template`'s existing parser for the placeholder
  tokenizer in Prototype C.
- `hspec` and the project's test harness for every Spec file.

New module signatures to exist at end of the relevant milestone:

- End of M3, in `seihou-core/src/Seihou/Engine/TypedDhallText.hs`:

        module Seihou.Engine.TypedDhallText (renderTypedDhallText) where

        renderTypedDhallText
          :: FilePath
          -> Map VarName VarValue
          -> IO (Either Text Text)

- End of M4, in
  `seihou-core/src/Seihou/Engine/TemplatePrototype.hs`:

        module Seihou.Engine.TemplatePrototype (renderTemplatePrototype) where

        renderTemplatePrototype
          :: Text
          -> Map VarName VarValue
          -> Either [PlaceholderError] Text

Neither module is imported by any production code path. Both live
alongside their tests under `seihou-core/test/Seihou/Evaluation/`.

No Dhall schema changes. `schema/Step.dhall`, `schema/Module.dhall`,
`schema/VarDecl.dhall`, and the rest of
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou/schema/` are
unchanged.

No changes to `docs/dev/design/proposed/generation-strategies.md` —
its "Status: Implemented" table entry stays accurate. A later ExecPlan
authored from the recommendation of this one would revise it.


## Revisions

(Revision notes are appended here as the plan is updated. None yet.)
