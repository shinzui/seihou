---
id: 9
slug: inline-conditionals-in-template-strategy
title: "Add inline conditional blocks to the Template strategy"
kind: exec-plan
created_at: 2026-04-19T16:01:07Z
intention: "intention_01kphc0qkeewfsrht6xa7p7x20"
---


# Add inline conditional blocks to the Template strategy

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

Enable module authors to write a **single** `.tpl` file that branches on
resolved variables, instead of shipping two near-duplicate templates
gated by mutually exclusive `when` conditions on two `Step` records.

After this plan lands:

- A template file can contain `{{#if <expr>}}…{{/if}}` and
  `{{#if <expr>}}…{{#else}}…{{/if}}` blocks at any nesting depth.
  `<expr>` is the same expression grammar used by a step's `when`
  field (from `Seihou.Core.Expr`): `IsSet`, `Eq`, `&&`, `||`, `!`,
  `true`, `false`, parentheses.
- The placeholder-only behaviour of `renderDestPath` and
  `renderCommand` is unchanged — conditionals apply to template
  *body* content only, not to destination paths or shell commands.
- `Seihou.Engine.TemplatePrototype` and the
  `Seihou.Evaluation.ConditionalTemplateSpec` module are deleted.
  The prototype fixture migrates to exercise the production path
  through `compilePlan`.
- The sibling `nix-haskell-flake` module at
  `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou-modules/modules/haskell/nix-haskell-flake/`
  replaces `flake.nix.tpl` + `flake-with-postgres.nix.tpl` with a
  single `flake.nix.tpl` using the new syntax. Its `module.dhall`
  drops one `Step` record and its brittle
  `Eq nix.postgresql false || Eq nix.postgresql "false"` double-guard.

The observable outcomes a reviewer can run:

    cabal test seihou-core-test

prints (among other specs) passing cases for `{{#if}}` with nesting
and `{{#else}}`, plus the migrated fixture's byte-for-byte
equivalence to the split-flake baseline. After the module
migration, `cd …/seihou-modules && seihou run nix-haskell-flake`
against a scratch directory still produces the same `flake.nix`
as before, for both values of `nix.postgresql`.

This plan is the direct follow-up to ExecPlan 8
(`docs/plans/8-evaluate-dhall-as-templating-language.md`) and adopts
its recommendation: Prototype C.


## Progress

- [x] M1: Promote `renderTemplatePrototype` into `Seihou.Engine.Template`
      as a new public function that handles `{{#if}}/{{#else}}/{{/if}}`
      with unbounded nesting. Extend `PlaceholderError` with block-level
      variants. Add specs under `Seihou.Engine.TemplateSpec` covering
      if/else, nesting, unterminated blocks, orphaned tokens, and
      malformed expressions. (done 2026-04-18: 13 new cases pass, 708 total)
- [x] M2: Wire the new function into `Seihou.Engine.Plan.compileStep`
      for the `Template` strategy and the `Template` branch of
      `compilePatchStep`. Leave `renderDestPath` and `renderCommand`
      routed through the existing placeholder-only `renderTemplate`.
      Update `formatPlaceholderError` to handle the new variants.
      (done 2026-04-18: 3 new PlanSpec cases pass, 711 total)
- [x] M3: Decommission `Seihou.Engine.TemplatePrototype` and
      `Seihou.Evaluation.ConditionalTemplateSpec`. Migrate the
      `conditional-template-flake` fixture to a canonical test under
      `Seihou.Engine.PlanSpec` (or a sibling spec) that goes through
      `compilePlan` against `strategy = "template"`. Remove the
      experimental module from `seihou-core.cabal` and the test-suite
      `other-modules` list. (done 2026-04-18: prototype module and
      exposed-modules entry removed; ConditionalTemplateSpec kept as
      a dedicated module with a rewritten body that drives through
      `compilePlan` and preserves both byte-for-byte equivalence
      assertions against the split-flake baselines; total tests 709
      = 711 − 4 prototype-specific + 2 compilePlan)
- [x] M4: Update documentation. Extend the
      `Strategy: template` subsection of
      `docs/user/module-authoring.md` with the conditional-block
      syntax and a worked example. Add a "Conditional blocks"
      subsection to
      `docs/dev/design/proposed/generation-strategies.md` with the
      same example and a short rationale citing this plan.
      Add a CHANGELOG entry in `docs/user/CHANGELOG.md`.
      (done 2026-04-18)
- [x] M5: Migrate the sibling `nix-haskell-flake` module (separate
      git repository at
      `/Users/shinzui/Keikaku/bokuno/seihou-modules`).
      Replace the two `flake.nix.tpl` / `flake-with-postgres.nix.tpl`
      files with one that uses `{{#if}}`. Drop the duplicate
      `Eq nix.postgresql false || Eq nix.postgresql "false"` double-guard
      (the step no longer has a `when`). Commit in that repo with an
      `ExecPlan:` trailer pointing at **this** plan's path. Verify by
      running `seihou run` against a scratch target directory for
      both `nix.postgresql = true` and `false`.
      (done 2026-04-18 as seihou-modules commit `b6ccd2a`: version
      bumped 0.4.0→0.5.0, both scratch-dir diffs against the
      split-flake baselines empty)


## Surprises & Discoveries

- M1: Adding the three new `PlaceholderError` constructors
  (`UnterminatedIf`, `OrphanBlockToken`, `MalformedIfExpression`)
  shadowed identically-named constructors still exported from
  `Seihou.Engine.TemplatePrototype.PrototypeError`. Fixed temporarily
  by `hiding` them in the prototype's import of `Seihou.Core.Types`
  and qualifying the one pattern match in the prototype's spec. The
  hack is self-cleaning — M3 deletes the prototype module and the
  spec that matches on `PrototypeError`.
- M5: The sibling `seihou-modules` repo is checked out at
  `/Users/shinzui/Keikaku/bokuno/seihou-modules/`, not the
  `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou-modules/`
  path the plan's Context and Orientation and Plan of Work claim.
  The older path does not exist; the repo lives one level above the
  `seihou-project/` directory. All M5 commands have been executed
  against the real path.
- M5: The module's existing steps list contains more than the two
  mutually-exclusive flake.nix steps the plan described — there are
  also Copy, Template-with-patch, and conditional Template steps for
  `flake.lock`, `treefmt.nix`, `process-compose.yaml`, `.envrc`, and
  `.gitignore` entries. The M5 edit is narrower than the plan's
  "replace with a single unconditional step": only the two
  mutually-exclusive flake.nix steps are collapsed into one; the
  remaining steps are untouched.
- M3: The `git grep TemplatePrototype` / `git grep renderTemplatePrototype`
  acceptance checks in Validation and Acceptance still return hits
  against `docs/dev/design/proposed/dhall-as-templating-evaluation.md`,
  `docs/plans/8-…`, and this plan file itself. These are the
  preserved written record of the prototype (per the Decision Log
  entry "Retire …") plus the plan's own narrative, so they are
  intentional survivors, not leftover code. Source trees are clean:
  `grep --include='*.hs' --include='*.cabal'` returns nothing.


## Decision Log

- Decision: Lift the prototype's 1-level nesting cap to unbounded
  in the same milestone that promotes the code.
  Rationale: The cap was an artefact of the prototype's scope
  ("simplest thing that demonstrates the idea"); production users
  will hit it almost immediately in any non-trivial configuration
  (e.g. nested `{{#if}}` for "feature A" inside a block that gates
  on "feature bundle B"). Shipping with a cap creates a second
  follow-up plan to remove it, for no real benefit today.
  Date: 2026-04-18

- Decision: Add conditional support only to the `Template`-strategy
  *body* path, not to `renderDestPath` or `renderCommand`, and not
  to the pre-Dhall substitution pass in `compileDhallTextStep` /
  `compileStructuredStep`.
  Rationale: Dest paths and shell commands are single-line
  expressions where conditionals would be structurally awkward and
  semantically surprising. DhallText and Structured already have
  Dhall's native `if`/`then`/`else`, so adding a second conditional
  syntax at the pre-substitution layer would double the surface
  area with no new capability.
  Date: 2026-04-18

- Decision: Extend `Seihou.Core.Types.PlaceholderError` with new
  variants (`UnterminatedIf`, `OrphanBlockToken`,
  `MalformedIfExpression`) rather than introducing a sibling
  error type.
  Rationale: `PlaceholderError` is already the public error
  surface for everything `renderTemplate` produces. Adding variants
  keeps the error-formatting pipeline
  (`Seihou.Engine.Plan.formatPlaceholderError`) as a single
  function to update, and avoids threading a new `Either` type
  through five call sites.
  Date: 2026-04-18

- Decision: Inner `{{var}}` error line numbers will reflect
  **expanded** template line numbers, not source line numbers.
  Block-level errors (unterminated `{{#if}}`, orphan `{{/if}}`,
  malformed expression) continue to report source lines because
  block expansion records the opener's source line at the moment
  the block is detected.
  Rationale: Preserving source lines for inner placeholder errors
  would require a line-mapping data structure threaded through the
  expander. The prototype accepted the drift; production users
  will still get a reasonable error message with line context, and
  if the drift becomes a reported problem we can revisit with a
  dedicated line-map in a follow-up.
  Date: 2026-04-18

- Decision: Retire `Seihou.Engine.TemplatePrototype` and
  `Seihou.Evaluation.ConditionalTemplateSpec` rather than keep
  them as an "implementation reference" alongside the production
  path.
  Rationale: Keeping the prototype encourages divergence (future
  edits going to only one of the two), clutters the module list,
  and breaks the "production code changes go in one place" rule.
  The evaluation doc at
  `docs/dev/design/proposed/dhall-as-templating-evaluation.md`
  preserves the prototype's role as a written record.
  Date: 2026-04-18

- Decision: Add Mustache-style standalone-block whitespace trim to
  `Seihou.Engine.Template.expandConditionals` instead of adopting
  an external templating engine (Ginger, Mustache proper, etc.).
  Rationale: Adopting Ginger would break `{{...}}` syntax
  compatibility with every existing template, require two expression
  grammars in the codebase (Ginger's own grammar alongside
  `Seihou.Core.Expr` used by step-level `when`), and pull in loops,
  filters, includes, and inheritance — features that directly
  contradict the "Templates Stay Dumb" architectural decision. The
  `DhallText` strategy already serves as the escape hatch for
  anything beyond boolean gating. The single missing feature that
  actually motivated the "switch engines?" discussion was whitespace
  control, which is ~30 LOC of bounded trim logic. Doing the small
  thing preserves the engine's scope; the "no loops, no filters,
  no inheritance" boundary is reaffirmed rather than reopened.
  Date: 2026-04-19

- Decision: Migrate the sibling `nix-haskell-flake` module as part
  of this plan rather than defer it.
  Rationale: The split-flake pain in that module is the reason
  this feature exists; a working production implementation that
  leaves the motivating module unchanged would not demonstrate
  the capability end-to-end. The cross-repo commit is small and
  well-scoped.
  Date: 2026-04-18


## Outcomes & Retrospective

Delivered 2026-04-18. All five milestones complete.

Observable outcomes matched the plan:

- `cabal test seihou-core-test` → 709 tests pass. Net change is
  +3 relative to the pre-plan baseline (708): 13 new
  `renderTemplateText` specs added in M1, 3 new `compilePlan` cases
  added in M2, 4 prototype-only specs removed in M3, 2 new
  compilePlan-driven fixture cases added in M3.
- `git grep TemplatePrototype` / `git grep renderTemplatePrototype`
  source-tree-only are clean; doc references remain, intentionally,
  as the written record cited by the Decision Log.
- `git grep 'renderTemplateText'` in `seihou-core/src/` shows one
  definition site in `Seihou.Engine.Template` and two call sites in
  `Seihou.Engine.Plan` (`compileTemplateStep` and the `Template`
  branch of `compilePatchStep`), as specified.
- User and design docs describe the syntax with a worked example.
- The sibling `nix-haskell-flake` module now has exactly one
  `dest = "flake.nix"` step (grep returns one hit); version bumped
  to 0.5.0; `flake-with-postgres.nix.tpl` deleted. Scratch-dir
  `seihou run` produced byte-identical output to the split-flake
  baselines for both `nix.postgresql = true` and `false`.
- Every commit carries both `ExecPlan:` and `Intention:` trailers,
  including the single commit in the sibling repo
  (`b6ccd2a`).

Lessons:

- The small-scale "shadowed-constructor" pain in M1 (see Surprises)
  was a direct consequence of the plan's choice to reuse
  `PlaceholderError` rather than mint a sibling error type. That
  choice still paid off — one `formatPlaceholderError` function,
  no threaded `Either` — and the shadowing was self-cleaning when
  the prototype module was deleted in M3. Worth remembering that
  constructor-level namespace clashes during an in-flight promotion
  are cheap to mitigate with `hiding`.
- The plan's Context and Orientation had two path inaccuracies:
  the sibling repo was documented at `seihou-project/seihou-modules`
  but actually lives at `seihou-modules/` (one level up), and its
  `steps` list was said to need collapsing to "a single
  unconditional step" when in fact six non-flake steps are
  present and must stay untouched. Both were caught and recorded
  in Surprises; the deliverable is unaffected. Future ExecPlans
  describing cross-repo work should probably pull the live
  `module.dhall` into the plan narrative rather than summarize it.
- The two-pass split (expand conditionals, then `renderTemplate`)
  made "untaken branches are discarded" a free consequence — the
  untaken branch never reaches the placeholder engine. This kept
  the specs simple and matches user intent.


## Context and Orientation

This section assumes the reader has not read ExecPlan 8.


### The feature being promoted

`Seihou.Engine.TemplatePrototype` at
`seihou-core/src/Seihou/Engine/TemplatePrototype.hs` (~225 lines)
exports one function:

    renderTemplatePrototype
      :: Text
      -> Map VarName VarValue
      -> Either [PrototypeError] Text

It accepts template text, expands `{{#if <expr>}}…{{/if}}` and
`{{#if <expr>}}…{{#else}}…{{/if}}` blocks in a first pass, then
calls `Seihou.Engine.Template.renderTemplate` on the expanded text
to perform `{{var}}` substitution. Expression parsing and evaluation
reuse `Seihou.Core.Expr.parseExpr` / `evalExpr` — the same grammar
used by a `Step`'s `when` clause.

The prototype caps nesting at one level and rejects deeper
nesting with `NestingTooDeep`. That cap must be lifted.

The prototype's error type
`Seihou.Engine.TemplatePrototype.PrototypeError` has five
constructors:

- `UnterminatedIf Int` — opener line of a block with no `{{/if}}`.
- `OrphanBlockToken Text Int` — stray `{{/if}}` or `{{#else}}`.
- `MalformedIfExpression Text Int Text` — expression, line,
  parse-error.
- `NestingTooDeep Int` — **dropped** after promotion.
- `BranchPlaceholderErrors [PlaceholderError]` — wraps inner errors
  from the second pass.

`NestingTooDeep` goes away. `BranchPlaceholderErrors` becomes
unnecessary when the two passes share `PlaceholderError` as a
single error type — the inner pass can return its errors
directly into the combined list. The other three variants move
onto `PlaceholderError` verbatim.

### The production placeholder engine

`Seihou.Engine.Template` at
`seihou-core/src/Seihou/Engine/Template.hs` exports four functions:

    renderTemplate   :: Text -> Map VarName VarValue -> Either [PlaceholderError] Text
    renderDestPath   = renderTemplate
    renderCommand    = renderTemplate
    valueToText      :: VarValue -> Text

`renderDestPath` and `renderCommand` are *aliases* for
`renderTemplate`. Both are called by
`Seihou.Engine.Plan.compilePlan` on single-line inputs (a step's
`dest` field and a command's `run`/`workDir` fields). Conditional
blocks have no place there; this plan **keeps those aliases
unchanged** and introduces a **new** entry point for body text
(see Plan of Work).

Current `PlaceholderError` at
`seihou-core/src/Seihou/Core/Types.hs:322`:

    data PlaceholderError
      = UnresolvedPlaceholder VarName Int
      | MalformedPlaceholder Text Int

### Dispatch in `compileStep`

`Seihou.Engine.Plan.compileStep` in
`seihou-core/src/Seihou/Engine/Plan.hs` has five call sites of
`renderTemplate`:

| Line | Call site                    | Role                                   |
|------|------------------------------|----------------------------------------|
| 136  | `compileTemplateStep`        | `.tpl` body → output                   |
| 160  | `compileDhallTextStep`       | pre-Dhall substitution into `.dhall`   |
| 189  | `compileStructuredStep`      | pre-Dhall substitution into `.gen`     |
| 233  | `compilePatchStep` (Template) | patch-body rendering for Template-strategy patches |
| 237  | `compilePatchStep` (DhallText) | pre-Dhall substitution for DhallText patches |

Only lines 136 and 233 are *template body* rendering. Those two
sites switch to the new entry point. The other three sites stay
on `renderTemplate` (pre-Dhall substitution; Dhall has its own
conditional syntax).

`renderDestPath` is called on dest paths at lines 116, 140, 168,
200, 249 (same file). `renderCommand` is called at Plan.hs:70
and in `compileOneCommand`. None of those change.

### Validation

`Seihou.Core.Module.extractPlaceholders` (same-name function at
`seihou-core/src/Seihou/Core/Module.hs:263`) is **only** used to
scan step `dest` fields (for `checkDestVarRefs`, a validation rule
that rejects steps referencing undeclared variables in the dest
path). It never runs over template bodies. Adding `{{#if}}` to
body syntax does not require any change to that validator.

### The prototype fixture

`seihou-core/test/fixtures/evaluation/conditional-template-flake/`
has:

    module.dhall                       -- currently unused (no step)
    files/flake.nix.tpl               -- single template with two
                                      -- {{#if Eq nix.postgresql true}}…{{/if}} blocks

It is exercised only through `renderTemplatePrototype` in
`seihou-core/test/Seihou/Evaluation/ConditionalTemplateSpec.hs`
— the fixture has no `module.dhall` wired into `compilePlan`.
During this plan, we switch the fixture to drive through
`compilePlan` with `strategy = "template"` (via a proper
`module.dhall`) and delete the prototype-specific spec module.

### The sibling module to migrate

`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou-modules` is a
separate git repository (`git log` there shows unrelated commits).
Its `modules/haskell/nix-haskell-flake/` directory contains:

- `module.dhall` — declares two mutually exclusive steps gated by
  `when = Some "Eq nix.postgresql false || Eq nix.postgresql \"false\""`
  and the matching `true` guard.
- `files/flake.nix.tpl` (54 lines, no postgres).
- `files/flake-with-postgres.nix.tpl` (68 lines, postgres variant).

The `module.dhall` imports the Seihou schema via a GitHub URL:

    let S =
          https://raw.githubusercontent.com/shinzui/seihou-schema/…/package.dhall
            sha256:…

The schema is unchanged by this plan, so the import pin does not
need to move. Migration changes only the `steps` list and the two
fixture files.

The duplicate-guard pattern `Eq nix.postgresql false || Eq nix.postgresql "false"`
hints at a separate, smaller bug in
`Seihou.Core.Expr.parseBareWord` / `evalExpr` around VBool vs VText
comparison. That bug is **out of scope** for this plan; a separate
plan should own it. After migration, the single combined step has
no `when` clause at all, so the workaround disappears from the
module regardless of the underlying bug status.

### Terms

- **Template body** — the content of a `.tpl` file as read from
  disk, distinct from the step's `dest` path or a `Command`'s
  `run`/`workDir`.
- **Block token** — one of `{{#if <expr>}}`, `{{#else}}`, `{{/if}}`.
- **Placeholder** — a `{{var}}` occurrence.
- **Expansion pass** — the first of two passes run by the new
  entry point; consumes block tokens and emits plain template text.


## Plan of Work


### Milestone 1 — Promote conditional rendering into `Seihou.Engine.Template`

Goal: a production-quality renderer with unbounded nesting, full
test coverage, and no dependency on the prototype module.

Add two new public identifiers to
`seihou-core/src/Seihou/Engine/Template.hs`:

    renderTemplateText
      :: Text
      -> Map VarName VarValue
      -> Either [PlaceholderError] Text

    -- (internal helper, also exported for test access)
    expandConditionals
      :: Map VarName VarValue
      -> Text
      -> Either [PlaceholderError] Text

`renderTemplateText` runs `expandConditionals` and then pipes the
result through the existing `renderTemplate`. `expandConditionals`
is a first-pass expander modelled on the prototype's function of
the same name (study
`seihou-core/src/Seihou/Engine/TemplatePrototype.hs:72` as the
reference) with these changes:

1. **Unbounded nesting.** The prototype rejects `depth >= 1`; the
   production version tracks depth for matching `{{/if}}` to its
   opener but does not cap it.
2. **Error type.** Errors are emitted as `PlaceholderError` values;
   the prototype's `PrototypeError` is deleted.
3. **Orphan detection** stays. `{{/if}}` or `{{#else}}` outside
   any open block produces `OrphanBlockToken`.
4. **Malformed expression** (`MalformedIfExpression`) stays, with
   the opener's source line.
5. **Unterminated `{{#if}}`** (`UnterminatedIf`) stays, with the
   opener's source line.

Extend `Seihou.Core.Types.PlaceholderError` with three new
constructors:

    data PlaceholderError
      = UnresolvedPlaceholder VarName Int
      | MalformedPlaceholder Text Int
      | UnterminatedIf Int
      | OrphanBlockToken Text Int
      | MalformedIfExpression Text Int Text
      deriving stock (Eq, Show, Generic)

Extend `Seihou.Engine.Plan.formatPlaceholderError` (line 313 of
`seihou-core/src/Seihou/Engine/Plan.hs`) with matching cases.
Sample human-readable messages:

- `unterminated {{#if}} opened at line N`
- `stray {{/if}} at line N` / `stray {{#else}} at line N`
- `malformed {{#if}} expression 'X' at line N: <parser error>`

Add specs to
`seihou-core/test/Seihou/Engine/TemplateSpec.hs` under a new
`describe "renderTemplateText"` block. Minimum coverage:

1. Plain template with no blocks — behaviour unchanged from
   `renderTemplate`.
2. `{{#if Eq x true}}A{{/if}}` with `x = True` emits `A`; with
   `x = False` emits empty.
3. `{{#if IsSet foo}}…{{#else}}…{{/if}}` — selects the correct
   branch for both "set" and "unset".
4. `{{#if A}}outer{{#if B}}inner{{/if}}outer2{{/if}}` — two-level
   nesting; both nested blocks expand correctly; outer `{{/if}}`
   matches outer `{{#if}}` (depth tracking works).
5. `{{#if A}}{{#if B}}{{#if C}}deep{{/if}}{{/if}}{{/if}}` — three-
   level nesting smoke test.
6. Unterminated `{{#if}}` reports the opener line.
7. Orphan `{{/if}}` at top level reports its line.
8. Orphan `{{#else}}` at top level reports its line.
9. Malformed expression `{{#if &&garbage}}…{{/if}}` reports the
   opener line and the parser error text.
10. `{{var}}` substitution inside a block works (including inside
    both the taken and untaken branches — the taken branch's
    errors surface; the untaken branch's errors do **not**, since
    untaken branches are discarded).

Acceptance:

    cabal test seihou-core-test --enable-tests --test-options="--pattern=/renderTemplateText/"

prints at least 10 new passing cases, and the total spec count
rises accordingly without disturbing pre-existing tests.


### Milestone 2 — Wire the new entry point into the dispatcher

Goal: `Template`-strategy steps exercise the new path; every other
dispatch stays identical.

Edit `seihou-core/src/Seihou/Engine/Plan.hs`:

- Add `renderTemplateText` to the import list alongside
  `renderCommand`, `renderDestPath`, `renderTemplate`.
- `compileTemplateStep` (line 136): switch the body-render call
  from `renderTemplate content vars` to
  `renderTemplateText content vars`.
- `compilePatchStep`'s `Template` case (line 233): same switch.
- Leave the `DhallText`, `Structured`, and pre-Dhall pre-substitution
  call sites on the existing `renderTemplate`.
- Leave `renderDestPath` and `renderCommand` call sites untouched.

Add a spec case to
`seihou-core/test/Seihou/Engine/PlanSpec.hs` under `describe "compilePlan"`:

1. `compileTemplateStep` compiles a `.tpl` containing a
   `{{#if}}…{{/if}}` block and produces the expected output for
   both branches of a Bool variable.
2. A `{{#if}}`-bearing `.tpl` used as a patch step produces a
   `PatchFileOp` whose content reflects the taken branch.

Acceptance:

    cabal test seihou-core-test

passes end-to-end (all pre-existing specs still green, two new
`compileStep` cases added).


### Milestone 3 — Decommission the prototype

Goal: one path in the tree, not two.

Delete:

- `seihou-core/src/Seihou/Engine/TemplatePrototype.hs`
- `seihou-core/test/Seihou/Evaluation/ConditionalTemplateSpec.hs`

Remove the corresponding entries from:

- `seihou-core/seihou-core.cabal` (`exposed-modules` and
  `other-modules`).
- `seihou-core/test/Main.hs` (import + binding + group membership).

Migrate the fixture at
`seihou-core/test/fixtures/evaluation/conditional-template-flake/`:

- Rewrite `module.dhall` with a single `Step` record using
  `strategy = "template"`, `src = "flake.nix.tpl"`,
  `dest = "flake.nix"`, `when = None Text`, `patch = None Text`.
  Add the five variables referenced by the template
  (`project.name`, `project.description`, `ghc.version`,
  `nix.process-compose`, `nix.postgresql`) and any schema-required
  fields matching the style of
  `seihou-core/test/fixtures/evaluation/split-flake/module.dhall`.
- Keep `files/flake.nix.tpl` as it is (the prototype fixture
  already uses `{{#if}}` syntax).

Replace `ConditionalTemplateSpec` with a new spec — either folded
into `Seihou.Engine.PlanSpec` as two cases under a
`describe "conditional-template-flake fixture"` block, or stood up
under `Seihou.Evaluation.ConditionalTemplateSpec` **with a
rewritten body** that routes through `compilePlan` rather than
`renderTemplatePrototype`. Either placement satisfies acceptance;
pick the one that minimises churn (`Seihou.Engine.PlanSpec` if the
existing module already has a clear split-flake-style block, a
dedicated module otherwise). Whichever is chosen, the migration
preserves both byte-for-byte equivalence assertions: non-postgres
and postgres baselines from
`seihou-core/test/fixtures/evaluation/split-flake/files/`.

Acceptance:

    cabal test seihou-core-test

passes. `git grep TemplatePrototype` returns no matches.
`git grep renderTemplatePrototype` returns no matches.


### Milestone 4 — Documentation

Goal: an author reading the docs can use `{{#if}}` without reading
source code.

Edit `docs/user/module-authoring.md` in the
`### Strategy: template` subsection (line 218 onward). After the
current placeholder-syntax paragraph, add a `**Conditional blocks:**`
paragraph covering:

- Syntax: `{{#if <expr>}}`, `{{#else}}`, `{{/if}}`.
- Expression grammar (reference the same grammar used by
  step-level `when`, with a link to the `variable-resolution.md`
  section that documents it).
- Nesting is supported to arbitrary depth.
- A short worked example: toggling an optional line in a Nix file
  based on a `Bool` variable.
- Note: conditionals apply to template bodies only, not to
  destination paths or shell commands.

Edit `docs/dev/design/proposed/generation-strategies.md`. Under
the `## Strategy Dispatch` section, add a subsection
`### Conditional blocks (Template only)` covering the same syntax
and semantics, with a pointer to this plan
(`docs/plans/9-inline-conditionals-in-template-strategy.md`) as
the provenance record.

Edit `docs/user/CHANGELOG.md` with a new entry under the next
unreleased version describing the feature and syntax in one
paragraph. Follow the tone of existing entries (check the
CHANGELOG's top few entries for style).

Acceptance: a fresh reader can find the syntax in at most two
clicks from either the user docs or the design spec. No broken
cross-links (run `grep -n '\[[^]]*\](.*)'` manually on edited
files and spot-check paths exist).


### Milestone 5 — Migrate `nix-haskell-flake` in the sibling repo

Goal: the motivating module stops duplicating its flake template.

This milestone operates in
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou-modules`, a
**separate git repository**. All commits in this milestone happen
in that repo, not this one.

1. In `modules/haskell/nix-haskell-flake/files/flake.nix.tpl`,
   re-author the template so it matches the non-postgres variant
   with two `{{#if Eq nix.postgresql true}}…{{/if}}` blocks:
   - One around the single `pkgs.postgresql` line in
     `nativeBuildInputs`.
   - One around the 11-line `shellHook` block that configures
     `PGHOST`/`PGDATA`/`PGLOG`/`PGDATABASE`/`PG_CONNECTION_STRING`
     and runs `initdb` if missing.

   The reference is
   `seihou-core/test/fixtures/evaluation/conditional-template-flake/files/flake.nix.tpl`
   in *this* repo — copy its structure.

2. Delete `modules/haskell/nix-haskell-flake/files/flake-with-postgres.nix.tpl`.

3. Edit `modules/haskell/nix-haskell-flake/module.dhall`: in the
   `steps` list, remove both of these records:

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

   Replace with a single unconditional step:

        S.Step::{
        , strategy = "template"
        , src = "flake.nix.tpl"
        , dest = "flake.nix"
        }

4. Bump the module's `version` field per the repo's conventional
   versioning (check `git log` in that repo for prior version
   bumps to see whether this is a minor or patch change; the
   change is user-visible but non-breaking, so **minor** is the
   conservative choice).

5. Verify the module works by running in a scratch directory:

        cd $(mktemp -d)
        seihou run nix-haskell-flake --var nix.postgresql=false --var project.name=demo --var project.description="demo" --var nix.process-compose=false --var nix.treefmt=true --var nix.pre-commit=true
        diff flake.nix /path/to/expected-non-postgres-baseline
        rm flake.nix
        seihou run nix-haskell-flake --var nix.postgresql=true  --var project.name=demo --var project.description="demo" --var nix.process-compose=false --var nix.treefmt=true --var nix.pre-commit=true
        diff flake.nix /path/to/expected-postgres-baseline

   Both diffs must be empty. The "expected" baselines are the
   unmodified original templates, rendered with the matching
   variable values (reuse
   `seihou-core/test/fixtures/evaluation/split-flake/files/`).

6. Commit in the sibling repo with both trailers pointing at
   *this* plan in the seihou repo:

        Migrate nix-haskell-flake to inline {{#if}} conditionals

        Replaces flake.nix.tpl + flake-with-postgres.nix.tpl with a single
        template gated by {{#if Eq nix.postgresql true}} blocks. Drops the
        two mutually-exclusive Step records and the double-guard
        Eq workaround that those steps used in 'when'.

        ExecPlan: /Users/shinzui/Keikaku/bokuno/seihou-project/seihou/docs/plans/9-inline-conditionals-in-template-strategy.md
        Intention: intention_01kphc0qkeewfsrht6xa7p7x20

   Do **not** push; leave it local for review.

Acceptance: in the sibling repo, `git status` is clean after the
commit; `git show HEAD --stat` shows exactly three files touched
(`module.dhall`, `flake.nix.tpl`, `flake-with-postgres.nix.tpl` as
a deletion); the scratch-dir `seihou run` commands from step 5
produce byte-identical output to the baselines.


## Concrete Steps

Run all commands from
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou` unless
stated otherwise.

Confirm the baseline builds before starting:

    cabal build all

Expected: `Up to date` or a clean rebuild with no errors.

For each milestone, after completing the edits, run:

    cabal test seihou-core-test --enable-tests

and record the pass count in the Progress section.

For M5 (cross-repo), run commands from the sibling repo
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou-modules`.
Use absolute paths when referencing fixtures in this repo so
there's no ambiguity about which file is being diffed.


## Validation and Acceptance

The plan is complete when all of the following are true:

1. `cabal test seihou-core-test` passes. The spec count is at
   least ten higher than before this plan (from the M1 test list).
2. `git grep TemplatePrototype` in this repo returns no matches.
3. `git grep renderTemplatePrototype` returns no matches.
4. `git grep 'renderTemplateText'` in `seihou-core/src/` returns
   exactly one definition site and two call sites in
   `Seihou.Engine.Plan.compileStep` (`compileTemplateStep` and
   `compilePatchStep`).
5. `docs/user/module-authoring.md` and
   `docs/dev/design/proposed/generation-strategies.md` both
   describe the new syntax with a worked example.
6. The sibling repo's `nix-haskell-flake/module.dhall` has exactly
   one `Step` record for `flake.nix` (grep for
   `dest = "flake.nix"` — expected: one match).
7. `flake-with-postgres.nix.tpl` is deleted in the sibling repo.
8. Running `seihou run nix-haskell-flake` with `nix.postgresql`
   toggled produces byte-identical output to the baselines
   (step 5 of M5).
9. Every commit in this repo produced by the plan carries
   `ExecPlan: docs/plans/9-inline-conditionals-in-template-strategy.md`
   and `Intention: intention_01kphc0qkeewfsrht6xa7p7x20`
   trailers. The sibling repo's single commit carries both
   trailers referencing **this** plan by absolute path.


## Idempotence and Recovery

- M1 and M2 are additive: introducing `renderTemplateText` and
  re-routing two call sites does not change behaviour for any
  template that does not contain `{{#if}}`/`{{/if}}`/`{{#else}}`.
  Rolling back is `git revert` on the commits.
- M3 deletes files; recoverable from git history.
- M4 is pure documentation; trivially revertable.
- M5 is in a separate repo. Because the commit is local (not
  pushed), revert is a single `git reset --hard HEAD^` in the
  sibling repo — but note this plan does **not** authorise
  destructive resets without user confirmation. If the
  migration must be redone, prefer `git revert` followed by a
  fresh attempt.

If a prior plan's prototype files somehow remain after M3, a
safe way to detect is:

    git grep -l TemplatePrototype
    git grep -l renderTemplatePrototype
    git grep -l ConditionalTemplateSpec

Each must return empty output at the end of M3.


## Interfaces and Dependencies

No new library dependencies. The work reuses:

- `Seihou.Core.Expr` — `parseExpr` and `evalExpr`, unchanged.
- `Seihou.Core.Types` — `PlaceholderError` gains three new
  constructors; no other type changes.
- `Seihou.Engine.Template` — gains `renderTemplateText` and
  (exported for tests) `expandConditionals`. Existing exports
  (`renderTemplate`, `renderDestPath`, `renderCommand`,
  `valueToText`) remain as-is.
- `Seihou.Engine.Plan` — two call sites re-routed, plus the
  `formatPlaceholderError` switch extended.
- `hspec`/`tasty-hspec` — the existing test harness.

Signatures to exist at end of each milestone:

- End of M1, in `seihou-core/src/Seihou/Engine/Template.hs`:

        renderTemplateText
          :: Text
          -> Map VarName VarValue
          -> Either [PlaceholderError] Text

        expandConditionals
          :: Map VarName VarValue
          -> Text
          -> Either [PlaceholderError] Text

- End of M1, in `seihou-core/src/Seihou/Core/Types.hs`,
  `PlaceholderError` includes:

        | UnterminatedIf Int
        | OrphanBlockToken Text Int
        | MalformedIfExpression Text Int Text

- End of M2, in `seihou-core/src/Seihou/Engine/Plan.hs`:
  `compileTemplateStep` body render uses `renderTemplateText`;
  `compilePatchStep` Template branch uses `renderTemplateText`;
  `formatPlaceholderError` covers the three new variants with
  human-readable messages.

No Dhall schema changes.
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou/schema/` is
unchanged. The sibling-repo module's schema pin is unchanged.


## Revisions

- 2026-04-19: Standalone-block whitespace trim addendum. After M5
  landed, authoring the first real multi-variable flake template in
  the sibling repo revealed that the engine's lack of whitespace
  control made readable multi-line templates impractical — tags on
  their own lines left blank-line cruft in the output, pushing
  authors back toward dense single-line forms. Rather than adopt a
  full external templating engine (Ginger, Mustache, etc.), added
  Mustache-style "standalone block" semantics to
  `Seihou.Engine.Template.expandConditionals`: when a block tag is
  the only non-whitespace on its line, the surrounding indentation
  and the line's terminating newline are absorbed as part of the
  tag. Exactly one newline per side is consumed, so deliberate
  blank-line spacing survives. Decision Log entry below.
  The `conditional-template-flake` fixture is restructured in the
  new readable style; byte-identical output to both split-flake
  baselines is preserved.
