---
id: 49
slug: coerce-variable-defaults-to-declared-type-and-add-a-module-check-lint
title: "Coerce variable defaults to declared type and add a module-check lint"
kind: exec-plan
created_at: 2026-06-18T21:33:51Z
intention: "intention_01kveaes98e0mrd6fdx5s2dy1a"
---

# Coerce variable defaults to declared type and add a module-check lint

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

A module author declares a variable with a type (e.g. `type = "bool"`) and a default
(e.g. `default = Some "true"`). Today, when that variable is **not** supplied by any
source and falls through to its module default, the value reaches template/condition
evaluation as the wrong runtime type — a `VText "true"` instead of a `VBool True`.
Because the expression evaluator compares values by exact constructor
(`VBool True /= VText "true"`), a condition like `{{#if Eq nix.treefmt true}}` silently
evaluates to **false** even though the flag is "on". Generated output is then quietly
wrong — the file the author intended to emit is omitted (or vice versa) with no error.

This actually happened: a generated Haskell flake silently dropped its `treefmt-nix`
and `pre-commit-hooks` inputs and `./nix/*.nix` imports while still emitting the
`nix/treefmt.nix` file, because the module guarded file generation with the defensive
expression `Eq nix.treefmt true || Eq nix.treefmt "true"` but guarded the flake inputs
with only `Eq nix.treefmt true`. The result was a flake that referenced unwired modules
and exposed no `formatter`, breaking `nix fmt` in CI. (That module-side template was
patched separately; this plan fixes the engine so the bug class cannot recur.)

After this change:

- A `type = "bool"` (or `int`, or `choice`) variable that resolves to its module default
  arrives at evaluation as the correctly-typed `VarValue`. `Eq nix.treefmt true` is `true`
  whenever the flag is on, from every resolution source including the default.
- A malformed default (e.g. `default = Some "treu"` on a `bool`) fails **at module load
  time** with a clear `CoercionFailed` error, instead of silently degrading to text.
- `seihou validate-module --lint <dir>` flags two new authoring mistakes: a `when` clause
  or template conditional that references an **undeclared** variable, and an `Eq <var>
  <literal>` comparison whose literal type cannot match the variable's declared type
  (e.g. a `bool` variable compared against the quoted string `"true"`). This is what
  would have caught the original module bug before it shipped.

You can see it working by loading a module whose `bool` variable uses a string default and
observing that `Eq` against a bareword `true` now matches, and by running the linter on a
module that compares a `bool` variable to `"true"` and seeing it reported.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] **M1 — Coerce defaults against declared type (root fix).** Done 2026-06-18.
  - [x] Coerce the decoded `default` against the decoded `type` in `varDeclDecoder`
        (`seihou-core/src/Seihou/Dhall/Eval.hs`), failing module load on a bad default.
        Added `coerceDeclDefault` + `renderDefaultError`/`renderVarType`; applied via
        `fmap coerceDeclDefault` over the record decoder. The `Left` path `error`s with a
        clear message and is caught by the existing `try` (forced to WHNF by the existing
        `evaluate v.type_` loop).
  - [x] Harden the default branch of `resolveOne` in
        `seihou-core/src/Seihou/Core/Variable.hs` via a new exported
        `coerceDefault :: VarName -> VarType -> VarValue -> Either VarError VarValue`,
        reused by both the decoder and `resolveOne`.
  - [x] 4th edit (per resolved Decision Log item): `classifyBareWord` in
        `seihou-core/src/Seihou/Core/Expr.hs` now classifies an integer literal bareword
        (all digits, optional leading `-`) as `VInt`, so `Eq <int-var> N` matches.
  - [x] Unit tests across `ExprSpec`, `VariableSpec`, `EvalSpec`: bool/int/choice default
        coerces to the right `VarValue`; bad default errors at load and at resolve;
        `Eq feature.on true` against a defaulted bool evaluates `True`; int `Eq` matches a
        `VInt`. All 881 `seihou-core-test` cases pass.
- [x] **M2 — Re-coerce stored/manifest values on load (completeness).** Done 2026-06-18 —
      **audit found no code change needed.**
  - [x] Audited the manifest → variable path. **Finding: no path reconstructs a typed
        `VarValue` from manifest-stored text.** `Manifest.vars :: Map VarName Text` is
        JSON-decoded as `Map VarName Text` (`Seihou/Manifest/Types.hs`, `varsFromJSON`),
        and is only ever consumed *as text* — saved by merging
        `Map.map varValueToText allResolvedVals` (`CLI/Run.hs:333`) and shown in
        diff/status/preview. Manifest vars are **not** fed back into `resolveVariables` on a
        re-run (the manifest is read *after* resolution in `CLI/Run.hs`). The only text→
        `VarValue` constructors are the resolution chain (`coerceValue`, fixed in M1), the
        decoder (`coerceDefault`, fixed in M1), and the `{{#if}}` expression parser. The
        one composition-synthesized default (`injectExportDefault`,
        `Composition/Resolve.hs:331`) now also flows through M1's `coerceDefault` (typed
        values pass through; a `VText` export is coerced against the importing var's type).
  - [x] Regression test: `VariableSpec` "re-coerces a manifest-round-tripped bool value to
        VBool" — a bool serialized to text `"true"` re-entering via a config-style source
        resolves to `VBool True`, never `VText "true"`.
- [x] **M3 — Authoring-time lint in `validate-module --lint`.** Done 2026-06-18.
  - [x] Added `exprRefs :: Expr -> [(VarName, Maybe VarValue)]` to
        `seihou-core/src/Seihou/Core/Expr.hs` (total over `Expr`, exported).
  - [x] Factored `extractIfExprs :: Text -> [Text]` out of the Template engine
        (`seihou-core/src/Seihou/Engine/Template.hs`) — pulls every `{{#if …}}` opener's
        raw expression text from a template body for the lint to `parseExpr`.
  - [x] Extended `Seihou.Engine.Validate.buildReport` with `lintConditionals` (runs in IO,
        only when `--lint`): collects step/command/prompt `when` clauses (already parsed)
        plus `{{#if …}}` conditionals from `Template`/`DhallText` source files under
        `baseDir/files/`, then flags (a) references to undeclared variables and (b)
        type-inconsistent `Eq` comparisons (e.g. `bool` vs `"true"`). Surfaced as two
        `DiagError` checks ("Conditional variable references", "Conditional comparison
        types") gated behind `--lint`, so they render through the existing formatter and
        gate exit status.
  - [x] Unit tests: `ExprSpec` `exprRefs` cases; `ValidateSpec` "conditional lint" block
        (bool-vs-string flagged, bareword not flagged, undeclared `when` ref flagged,
        template `{{#if}}` undeclared/type cases, lint-off no-op). 895 `seihou-core-test`
        cases pass; 238 `seihou-cli-test` cases pass.
  - [x] End-to-end CLI transcript captured (see Concrete Steps below): flagged module exits
        1 with both findings; corrected module (barewords) exits 0.
- [x] **M4 — Cross-repo follow-up (documented, not code in this repo).** Done 2026-06-18.
  - [x] Recorded below (Outcomes & Retrospective → "Cross-repo follow-up"). The defensive
        `|| Eq X "true"` workarounds in the `seihou-modules` `nix-haskell-flake` templates
        become removable once this engine change ships and is released; the M3 lint
        (`validate-module --lint`) run against the modules repo will flag any remaining
        string-vs-bool comparisons. No code in this repo. (The mirror note belongs in the
        `seihou-modules` repo's issue tracker when that work is scheduled.)


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- **M2 audit conclusion (2026-06-18): the manifest path is already safe — no change.** The
  manifest stores variables as raw `Text` and *never* reconstructs them into a typed
  `VarValue`, nor re-feeds them into `resolveVariables` on a re-run. They are decoded as
  `Map VarName Text` and only consumed as text (saved via `varValueToText`, rendered in
  diff/status/preview). So there is no stored-value path that bypasses `coerceValue`. M2 is
  satisfied by M1 plus a round-trip regression test; no new production code.

- The root cause is narrower and more concrete than "manifest round-trip". The decoder at
  `seihou-core/src/Seihou/Dhall/Eval.hs:428` builds the default unconditionally as text:

  ```haskell
  <*> field "default" (fmap (fmap VText) (maybe strictText))
  ```

  So `default = Some "true"` on a `type = "bool"` variable becomes `default_ = Just (VText
  "true")` regardless of the declared type. Every *other* resolution source in
  `resolveVariables` (CLI `--var`, env, the four config layers, parent vars) routes its raw
  text through `coerceValue name ty rawText`; the **default branch does not**:

  ```haskell
  -- seihou-core/src/Seihou/Core/Variable.hs, resolveOne
  Nothing -> case decl.default_ of
    Just defVal -> fmap Just (validateAndWrap decl (defVal, FromDefault))   -- no coerceValue
  ```

  The interactive prompt path *does* coerce (`Seihou.Interaction.Prompt` line ~159), which
  is why interactively-generated projects were unaffected and the bug only surfaced for a
  project generated non-interactively (defaults taken verbatim).
- `seihou validate-module` already exists with a `--lint` flag (`vopts.validateLint`),
  backed by `Seihou.Engine.Validate.buildReport` / `ValidateReport`, and
  `Seihou.Core.Module` already emits "prompt references undeclared variable" / "export
  references undeclared variable" / "step destination references undeclared variable"
  diagnostics. The new lint extends this existing surface rather than introducing a new
  `seihou module check` command. Confirmed: `buildReport` (`Seihou/Engine/Validate.hs:56`)
  builds `coreChecks` (all `DiagError`) plus a list of `lintChecks` (all `DiagWarning`,
  gated on `lint`). The new findings slot in as additional `DiagCheck` entries. Note the
  same diagnostic also lives in `Seihou/Core/Blueprint.hs:116` — keep wording consistent
  across both if the lint is shared.

- **Choice coercion gotcha (found during M1).** The Dhall `varTypeDecoder` decodes
  `type = "choice"` to `VTChoice []` unconditionally — the option list is never carried in
  the type string (the existing `lintEmptyChoices` warning at `Validate.hs:214` flags this).
  But `coerceValue name (VTChoice opts) t` rejects any value when `opts` is empty, so naively
  routing choice defaults through `coerceValue` would fail every decoded choice default at
  load time (a regression). The new `coerceDefault` therefore treats `VTChoice []` as
  *unconstrained* (keeps the text as `VText`), while a directly-constructed `VTChoice [opts]`
  (as in tests / future option-carrying types) still validates membership. `coerceValue`
  itself is unchanged.

- **Validation finding (the int sibling bug M1 does not fully close).** `parseExpr`'s
  literal classifier only promotes the barewords `true`/`false` to `VBool`
  (`classifyBareWord`, `Seihou/Core/Expr.hs:182`); **every other bareword, including a
  numeric one like `3`, becomes `VText`**. There is no surface syntax that produces a
  `VInt` literal. Consequence: even after M1 makes a defaulted `int` variable resolve to
  `VInt 3`, an expression `Eq count 3` parses to `ExprEq count (VText "3")`, and
  `evalExpr` compares `VInt 3 == VText "3"` → `False`. So the exact bug class this plan
  targets *also exists for `int`*, and M1's default-coercion does not close it at the
  expression level — for any source, not just the default. M1's planned "analogous int
  default coercion case" will pass at the *resolution* layer (`VInt`) but an `Eq <int> N`
  expression test would still mis-evaluate. Bool escapes this only because `true`/`false`
  have dedicated bareword forms. `choice`/`text` escape it because their resolved value is
  `VText`, matching the `VText` literal. **Decide explicitly (see Decision Log):** either
  (a) extend `parseValue`/`classifyBareWord` to emit `VInt` for all-digit barewords so int
  `Eq` works symmetrically — small, localized change in `Seihou/Core/Expr.hs` — or (b)
  leave int `Eq` unsupported and rely on M3's lint to flag every `Eq <int-var> <literal>`
  as type-inconsistent. Option (a) is the consistent fix and is recommended; without it the
  M3 type-inference rule must treat *all* int `Eq` comparisons as findings.


## Decision Log

Record every decision made while working on the plan.

- Decision: Fix the type at the boundary (coerce the default when decoding `module.dhall`)
  rather than making the evaluator tolerant of mixed types.
  Rationale: `Seihou.Core.Expr.evalExpr` only receives `Map VarName VarValue` and has no
  access to declared types; teaching it loose `VBool`/`VText` equality would hide the type
  error instead of fixing it and risks changing existing modules' behavior. Coercing at
  decode time makes `default_ :: Maybe VarValue` correctly typed for *every* downstream
  consumer (resolution, prompt display, preview, dhall-text emission) from one place.
  Date: 2026-06-18
- Decision: Also coerce in the `resolveOne` default branch (defense in depth) even after
  fixing the decoder.
  Rationale: `default_` can also be synthesized during composition
  (`Seihou.Composition.Resolve` sets `default_ = Just val`); routing the default through the
  same coercion contract as other sources guarantees the invariant regardless of how a
  `VarDecl` was constructed.
  Date: 2026-06-18
- Decision: Surface the lint through the existing `validate-module --lint` command, not a
  new `module check` command.
  Rationale: the command, report type, undeclared-variable diagnostics, and CLI wiring
  already exist; extending them is lower-risk and keeps one validation entry point.
  Date: 2026-06-18
- Decision: A malformed default (fails `coerceValue`) is a hard module-load error, not a
  silent fallback to text.
  Rationale: a default that does not match its declared type is an authoring bug; failing
  loudly at load time is consistent with how CLI/env/config coercion failures are already
  reported (`CoercionFailed`).
  Date: 2026-06-18
- Decision (RESOLVED 2026-06-18, user chose option (a)): How to handle `int` `Eq`
  literals, which `parseExpr` always builds as `VText` (no `VInt` literal syntax exists), so
  `Eq <int-var> N` never matches even after M1. **Resolution: extend `classifyBareWord` in
  `seihou-core/src/Seihou/Core/Expr.hs` to classify an all-digit bareword as `VInt`**, folded
  into M1 as a 4th edit, with a unit test (`parseExpr "Eq n 3"` → `ExprEq n (VInt 3)`;
  `evalExpr` of it against `VInt 3` is `True`). This is the consistent fix and makes int `Eq`
  work symmetrically; M3's type-inference rule then need not blanket-flag int `Eq`
  comparisons. Confirmed by the user during implementation kickoff.
  Date: 2026-06-18
- Decision: Removing the defensive `|| Eq X "true"` workarounds in the `seihou-modules`
  repo is out of scope for this plan (different repository) and is recorded as a follow-up.
  Rationale: this plan hardens the `seihou` engine; the module templates are a separate
  artifact that this engine fix makes safe to simplify.
  Date: 2026-06-18


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

**Completion summary (2026-06-18).** All four milestones landed, each as a separate commit
carrying the `ExecPlan:`/`Intention:` trailers.

- **M1 (root fix)** — `feat(variable): coerce module defaults to declared type`. Defaults are
  now coerced against the declared type at decode time (`coerceDeclDefault` in
  `Seihou.Dhall.Eval`) and again in `resolveOne`'s default branch (`coerceDefault` in
  `Seihou.Core.Variable`, the single shared coercion point). A `bool` default of `"true"`
  resolves to `VBool True`, so `Eq nix.treefmt true` matches from the default source; a
  malformed default fails module load with a clear message. The int sibling bug was closed
  too: `classifyBareWord` now classifies integer-literal barewords as `VInt` (user-approved
  Decision Log resolution), so `Eq <int-var> N` matches symmetrically.
- **M2 (completeness)** — `test(variable): document manifest values already coerce-safe`.
  Audit conclusion: no manifest/stored path reconstructs a typed `VarValue` from raw text;
  manifest vars live and die as `Text`. No production change; a round-trip regression test
  guards the invariant.
- **M3 (authoring guard)** — `feat(validate): lint conditionals for undeclared refs and bad
  Eq types`. `validate-module --lint` now flags undeclared variable references and
  type-inconsistent `Eq` comparisons in `when` clauses and template `{{#if}}` conditionals.
  This is precisely the check that would have caught the original module bug before it
  shipped — confirmed by the end-to-end transcript.
- **M4 (cross-repo follow-up)** — documented below.

**Result vs. purpose.** The bug class ("a defaulted typed variable reaches evaluation as the
wrong runtime type, silently dropping guarded output") is closed at the engine boundary, and
the authoring mistake that produced it is now caught by lint. Whole-tree `cabal build all &&
cabal test all` is green (895 core + 238 CLI cases).

**Cross-repo follow-up (M4).** The `seihou-modules` `nix-haskell-flake` templates carry
defensive `Eq X true || Eq X "true"` forms that were added to work around this engine bug.
Once this change ships and is released, those can be simplified back to `Eq X true`. Running
`seihou validate-module --lint` against the modules repo will flag any remaining
string-vs-bool comparisons, making the cleanup mechanical. That work lives in the
`seihou-modules` repository and is out of scope here (see Decision Log).

**Lessons / surprises.** The narrow root cause (one decoder line plus one resolution branch)
was more tractable than the "manifest round-trip" framing suggested. Two adjacent gaps
surfaced during implementation and were folded in: (1) `int` `Eq` literals had no surface
syntax and needed the `classifyBareWord` extension to be consistent; (2) the Dhall decoder
produces `VTChoice []` unconditionally, so `coerceDefault` had to treat an empty choice list
as unconstrained text to avoid regressing choice defaults.


## Context and Orientation

This repository (`seihou`) is a project scaffolding/generation engine. A **module** is a
directory containing a `module.dhall` declaration plus template files; running a module
resolves a set of **variables** and uses them to generate files. Key terms:

- **VarValue** — a resolved variable value at runtime. Defined in
  `seihou-core/src/Seihou/Core/Types.hs`:

  ```haskell
  data VarValue = VText Text | VBool Bool | VInt Int | VList [VarValue]
  ```

- **VarType** — the declared type of a variable (`VTText | VTBool | VTInt | VTList VarType
  | VTChoice [Text]`), same file.
- **VarDecl** — a variable declaration parsed from `module.dhall` (`name`, `type_`,
  `default_ :: Maybe VarValue`, `description`, `required`, `validation`), same file.
- **Expr** — the AST for conditional logic used both in file-generation `when` clauses and
  in inline `{{#if ...}}` template conditionals. Defined in `Types.hs`:

  ```haskell
  data Expr = ExprEq VarName VarValue | ExprAnd Expr Expr | ExprOr Expr Expr
            | ExprNot Expr | ExprIsSet VarName | ExprLit Bool
  ```

  Parsed from strings by `parseExpr` and evaluated by `evalExpr` in
  `seihou-core/src/Seihou/Core/Expr.hs`. The evaluator compares by exact value:

  ```haskell
  go (ExprEq name val) = Map.lookup name vars == Just val
  ```

  In `parseExpr`, a bareword `true`/`false` becomes `VBool`, while a quoted `"true"`
  becomes `VText` (`parseBareWord` / `parseValue`). So `Eq x true` and `Eq x "true"`
  build *different* `ExprEq` values that match different `VarValue` constructors.

- **coerceValue** — converts raw text to a typed `VarValue` against a `VarType`
  (`seihou-core/src/Seihou/Core/Variable.hs`, lines ~27–48). For `VTBool` it accepts
  `true/yes/1/false/no/0` (case-insensitive) and returns `CoercionFailed` otherwise.

The resolution pipeline is `resolveVariables` in
`seihou-core/src/Seihou/Core/Variable.hs` (lines ~129–220). Its `resolveOne` walks a
precedence chain of sources; **every source except the module default** coerces its raw
text via `coerceValue`. The default branch (lines ~164–166) wraps `decl.default_`
directly.

The decoder that builds `VarDecl.default_` from Dhall is `varDeclDecoder` in
`seihou-core/src/Seihou/Dhall/Eval.hs` (lines ~422–431); the offending line is 428.

Validation already exists:

- CLI command `validate-module` → `Seihou.CLI.Validate.handleValidateModule`
  (`seihou-cli/src-exe/Seihou/CLI/Validate.hs`), with a `--lint` flag carried on
  `ValidateOpts.validateLint` (`seihou-cli/src-exe/Seihou/CLI/Commands.hs`).
- Report building in `Seihou.Engine.Validate` (`buildReport`, `ValidateReport`,
  `reportHasErrors`).
- Existing undeclared-variable diagnostics in `seihou-core/src/Seihou/Core/Module.hs`
  (search for `references undeclared variable`).

Tests live under `seihou-core/test/` (hspec). Relevant existing specs:
`Seihou/Core/ExprSpec.hs`, `Seihou/Core/VariableSpec.hs`, `Seihou/Dhall/EvalSpec.hs`,
and `Seihou/Integration/ModuleLoadSpec.hs`. The test suites are `seihou-core-test`
(`seihou-core/seihou-core.cabal`) and `seihou-cli-test` (`seihou-cli/seihou-cli.cabal`).


## Plan of Work

The work is three implementation milestones plus a documented cross-repo follow-up. M1 is
the load-bearing fix (it closes the bug class). M2 is completeness. M3 adds the
authoring-time guard that would have caught the original mistake. Each milestone is
independently verifiable and should be committed separately, each commit carrying the
`ExecPlan:` and `Intention:` trailers (see below).

### Milestone 1 — Coerce defaults against the declared type (root fix)

Scope: a defaulted variable resolves to its declared type. At the end, a `bool` variable
with `default = Some "true"` produces `VBool True`, and a bad default fails module load.

Edits:

1. `seihou-core/src/Seihou/Dhall/Eval.hs`, `varDeclDecoder` (~lines 422–431): stop
   hard-wrapping the default as `VText`. Decode `default` as `Maybe Text`, then coerce it
   against the already-decoded `type` using `coerceValue`. Because `dhall`'s `record`
   applicative builds fields independently, do the coercion as a post-decode transform over
   the assembled `VarDecl` (it has both `type_` and the raw default in scope). On
   `Left (CoercionFailed ...)`, fail the decoder so module load reports the error (this is
   caught by the existing `try` in `evalModuleFromFile`). Importing `coerceValue` from
   `Seihou.Core.Variable` into `Seihou.Dhall.Eval` is acyclic (`Variable` imports only
   `Types`/`Prelude`); confirm at build time.

   Sketch:

   ```haskell
   varDeclDecoder :: Decoder VarDecl
   varDeclDecoder =
     fmap coerceDeclDefault $
       record
         ( VarDecl
             <$> field "name" varNameDecoder
             <*> field "type" varTypeDecoder
             <*> field "default" (fmap (fmap VText) (maybe strictText))  -- still raw text here
             <*> field "description" (maybe strictText)
             <*> field "required" bool
             <*> field "validation" (fmap (fmap ValPattern) (maybe strictText))
         )

   -- Coerce a raw-text default (VText) against the declared type; error on mismatch.
   coerceDeclDefault :: VarDecl -> VarDecl   -- or wrap in a decoder that can fail
   ```

   If the `dhall` `Decoder` cannot fail cleanly post-hoc, perform the coercion inside
   `evalModuleFromFile` after decoding (where `IO`/`Either` error reporting already exists)
   and add the failure to the same error channel as other module-load errors. Either
   placement is acceptable; pick whichever yields a clear load-time error message.

2. `seihou-core/src/Seihou/Core/Variable.hs`, `resolveOne` default branch (~lines 164–166):
   make the default flow through coercion like the other sources. If M1.1 guarantees
   `default_` is already correctly typed, this is a no-op safeguard; implement it so that a
   `VText` default on a typed variable is re-coerced (or asserted) rather than passed
   through. Keep the `FromDefault` provenance tag.

3. Tests in `seihou-core/test/Seihou/Dhall/EvalSpec.hs` and
   `seihou-core/test/Seihou/Core/VariableSpec.hs`:
   - A module whose `bool` var has `default = Some "true"` decodes to `default_ = Just
     (VBool True)`.
   - `resolveVariables` with no overrides yields `VBool True` for that variable.
   - `evalExpr` of `Eq <var> true` (parsed via `parseExpr`) against the resolved map is
     `True`.
   - A `bool` var with `default = Some "treu"` fails module load with a coercion error.
   - Analogous `int` and `choice` default coercion cases.

Acceptance: `cabal test seihou-core-test` passes including the new cases; the bool-default
expression evaluates `True`.

### Milestone 2 — Re-coerce stored/manifest values on load (completeness)

Scope: ensure no other path reconstructs a `VarValue` from stored text bypassing
`coerceValue`. The manifest stores resolved variables; confirm how they re-enter on a
re-run / migration / blueprint application.

Edits:

1. Audit the manifest decode path (search `loadManifest`, the manifest types under
   `seihou-core/src/Seihou/Manifest/`, and any `fromList ... VText` construction feeding
   resolution). If manifest values feed back as one of the already-coerced `Map VarName
   Text` config-style sources, no change is needed — record that finding. If any path
   constructs `VarValue` directly from stored strings, route it through `coerceValue`
   against the declared `VarType` for that variable.
2. Add a regression test (extend `Seihou/Core/VariableSpec.hs` or
   `Seihou/Manifest/TypesSpec.hs`) proving a `bool` value taken from a manifest-style
   source resolves to `VBool`.

Acceptance: `cabal test seihou-core-test` passes; the audit conclusion is recorded in
Surprises & Discoveries (either "already coerced — no change" with evidence, or the fix).

### Milestone 3 — Authoring-time lint in `validate-module --lint`

Scope: `seihou validate-module --lint <dir>` reports (a) `when`/conditional references to
undeclared variables and (b) type-inconsistent `Eq` comparisons.

Edits:

1. `seihou-core/src/Seihou/Core/Expr.hs`: export a pure helper that walks an `Expr` and
   returns the variables it references together with any literal compared via `Eq`, e.g.

   ```haskell
   exprRefs :: Expr -> [(VarName, Maybe VarValue)]
   -- ExprEq n v -> [(n, Just v)]; ExprIsSet n -> [(n, Nothing)]; And/Or/Not recurse; Lit -> []
   ```

2. `Seihou.Engine.Validate` (and/or `Seihou.Core.Module`): collect every `Expr` in the
   module — `when` clauses on steps (the `condition :: Maybe Expr` field on the step type,
   already parsed; confirmed in `Seihou/Core/Types.hs:122,162,171`) and the inline
   `{{#if ...}}` conditionals inside template files (parse with `parseExpr`). For each
   referenced variable:

   > Effort note (validation, 2026-06-18): the step side is cheap — conditions are already
   > `Maybe Expr`. The template side is the real work: `buildReport` is handed a `Module`
   > plus `baseDir` but does **not** currently read template *contents*, and `{{#if …}}`
   > blocks are extracted only inside the Template engine's expander
   > (`Seihou/Engine/Template.hs`, `parseExpr` at line 159), intertwined with expansion. M3
   > must (i) enumerate which step sources are text-bearing (`Template`/`DhallText`
   > strategies, not `Copy`/`Structured`), (ii) read those files under `baseDir`, and
   > (iii) scan for `{{#if …}}` openers and `parseExpr` each. Prefer factoring a small
   > reusable "extract `{{#if}}` expressions from template text" helper out of the Template
   > engine over duplicating its scanner. Budget M3 accordingly; it is the largest of the
   > three milestones.


   - if it is not declared in `module.vars`, emit a lint finding
     (`when clause references undeclared variable: <name>`), mirroring the existing
     `prompt references undeclared variable` wording in `Seihou.Core.Module`;
   - if it is declared and the `Eq` literal's type cannot match the declared `VarType`
     (e.g. `VTBool` compared against a `VText` literal such as `"true"`, or vice versa),
     emit a lint finding (`comparison against bool variable <name> uses a string literal
     "true"; use the bareword true`). This is exactly the smell behind the original bug.
   Thread these findings into `ValidateReport.reportChecks` so they render through the
   existing report formatter and gate exit status when appropriate.

3. Tests:
   - `seihou-core/test/Seihou/Core/ExprSpec.hs`: `exprRefs` returns the right pairs for
     `Eq x true`, `Eq x "true"`, `IsSet y && Eq z 1`.
   - A validate/engine spec (extend the existing Validate-related spec or add
     `Seihou/Engine/ValidateLintSpec.hs`): a module comparing a `bool` var to `"true"` is
     flagged; a module comparing it to bareword `true` is not; a `when` referencing an
     undeclared variable is flagged.

Acceptance: `cabal test seihou-core-test` passes; running
`cabal run seihou -- validate-module --lint <fixture>` prints the new findings (see
Concrete Steps for a transcript).

### Milestone 4 — Cross-repo follow-up (documented only)

No code in this repo. Record (here and in the seihou-modules repo's issue/notes) that once
M1 ships and is released, the defensive `Eq X true || Eq X "true"` forms added to the
`nix-haskell-flake` templates can be simplified back to `Eq X true`, and that running the
M3 lint against the modules repo will flag any remaining string-vs-bool comparisons.


## Concrete Steps

All commands run from the repository root
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou` unless noted. Use the dev shell if
the project provides one (`nix develop --command <cmd>`); otherwise `cabal` directly.

1. Reproduce the bug as a failing test first (red), in `seihou-core`:

   ```bash
   cabal test seihou-core-test 2>&1 | tail -20
   ```

   Expected after adding the M1 red test (before the fix): the new
   "bool default resolves to VBool / Eq true is True" case fails, demonstrating the
   `VText "true"` value.

2. Apply M1 edits, then:

   ```bash
   cabal build all
   cabal test seihou-core-test 2>&1 | tail -20
   ```

   Expected: the previously-failing case now passes; no regressions.

3. Commit M1 (see Git Trailers). Repeat the build/test loop for M2 and M3.

4. Exercise the lint end-to-end against a fixture module that compares a `bool` var to a
   quoted string:

   ```bash
   cabal run seihou -- validate-module --lint path/to/fixture-module
   ```

   Expected (illustrative):

   ```text
   ✗ lint: comparison against bool variable nix.treefmt uses string literal "true"
           (use the bareword: Eq nix.treefmt true)
   ✗ lint: when clause references undeclared variable: nix.treefmtt
   ```

   (Exact wording to match the existing report formatter.)

> Note: commit messages and the expected-output blocks above are illustrative; align final
> wording with the existing `Seihou.Engine.Validate` report style during implementation.

**Actual transcript (2026-06-18) — module with both lint issues:**

```text
  ✗ Conditional variable references
      step 'flake.nix' when clause references undeclared variable: nix.treefmtt
  ✗ Conditional comparison types
      step 'nix/treefmt.nix' when clause compares variable 'nix.treefmt' (declared type
      bool) against string literal "true"; the comparison can never match. Use the bareword
      true instead of the quoted "true".
  ...
2 error(s) found. Module is invalid.    (exit code 1)
```

Correcting both to barewords (`Eq nix.treefmt true`, and the template `{{#if Eq nix.treefmt
true}}`) yields `Module 'lint-demo' is valid.` and exit code 0.


## Validation and Acceptance

- **M1 (behavioral, not just compilation):** a module with
  `{ name = "feature.on", type = "bool", default = Some "true", required = False }` and a
  step `when = Some "Eq feature.on true"` generates that step's file with **no** variable
  overrides. Before the fix the file is skipped; after, it is emitted. Assert via a
  generation/integration test (`Seihou/Integration/GenerationSpec.hs` style) or via the
  unit chain decode → resolve → `evalExpr` returning `True`.
- **M1 (error path):** loading a module whose `bool` default is `Some "maybe"` fails with a
  `CoercionFailed`-style message at load time; assert in `EvalSpec.hs`.
- **M2:** a `bool` value sourced from the manifest resolves to `VBool`; assert in a spec,
  or record the audit finding that the manifest path already coerces.
- **M3:** `validate-module --lint` exits non-zero and prints a finding for a module that
  (a) compares a `bool` var to `"true"`, or (b) references an undeclared variable in a
  `when`/conditional; and exits zero for the corrected module. Assert in a spec and confirm
  with the CLI transcript above.
- **Whole change:** `cabal build all && cabal test all` is green.


## Idempotence and Recovery

- All edits are ordinary source changes under version control; re-running the build/test
  loop is safe and repeatable. Revert a milestone with `git revert` of its commit; each
  milestone is a self-contained commit leaving the tree buildable.
- M1's decoder change is the only one that can alter module-load behavior: a previously
  "loadable" module with a malformed typed default will now fail to load. This is the
  intended stricter behavior; if it surfaces a real module in the wild with a bad default,
  fix that module's `module.dhall` (the error names the variable and offending value).
- The lint (M3) is additive and gated behind `--lint`; it does not change generation.


## Interfaces and Dependencies

Libraries/modules used and why:

- `dhall` (`Dhall.Decoder`, `record`, `field`, `maybe`, `strictText`) — already used by
  `Seihou.Dhall.Eval` to decode `module.dhall`; M1 adjusts one field's decoding.
- `Seihou.Core.Variable.coerceValue :: VarName -> VarType -> Text -> Either VarError
  VarValue` — the single coercion function; reused for defaults (M1) and any
  manifest-sourced values (M2). New import into `Seihou.Dhall.Eval`.
- `Seihou.Core.Expr.parseExpr :: Text -> Either Text Expr` and
  `evalExpr :: Map VarName VarValue -> Expr -> Bool` — unchanged; the new
  `exprRefs :: Expr -> [(VarName, Maybe VarValue)]` (M3) is added alongside them.
- `Seihou.Engine.Validate` (`buildReport`, `ValidateReport`, `reportChecks`) and
  `Seihou.CLI.Validate.handleValidateModule` — extended in M3; no new CLI command.

Signatures/invariants that must hold at the end of each milestone:

- After **M1**: for any decoded `VarDecl d`, `d.default_` is `Nothing` or `Just v` where
  `v`'s constructor matches `d.type_` (bool→`VBool`, int→`VInt`, text/choice→`VText`,
  list→`VList`). `resolveVariables` returns the same-typed value for the default path as
  for the CLI/env/config paths.
- After **M2**: no code path constructs a `VarValue` for a declared variable from raw text
  without `coerceValue` (or the audit documents that the only such path is already covered).
- After **M3**: `exprRefs` is total over `Expr`; `validate-module --lint` reports undeclared
  references and type-inconsistent `Eq` comparisons and gates exit status accordingly.

### Git trailers for this plan

Every commit while working on this plan must include both trailers:

```text
<subject>

<body>

ExecPlan: docs/plans/49-coerce-variable-defaults-to-declared-type-and-add-a-module-check-lint.md
Intention: intention_01kveaes98e0mrd6fdx5s2dy1a
```


## Revision Notes

- **2026-06-18 — Plan validation pass.** Verified the plan's technical claims against the
  working tree. Confirmed accurate: the offending decoder line (`Seihou/Dhall/Eval.hs:428`,
  `<*> field "default" (fmap (fmap VText) (maybe strictText))`); `resolveOne`'s default
  branch wrapping `decl.default_` without `coerceValue` while every other source coerces
  (`Seihou/Core/Variable.hs`); `coerceValue`'s signature and per-type behavior (incl.
  `VTChoice` → `VText`); the prompt path coercing at `Seihou/Interaction/Prompt.hs:159`;
  the existing `validate-module --lint` surface (`buildReport`/`ValidateReport`/
  `reportChecks`) and undeclared-variable diagnostics; `Expr` exporting only
  `parseExpr`/`evalExpr`; and step `when` clauses stored pre-parsed as `Maybe Expr`.
  Found and recorded **one substantive gap**: `parseExpr` has no `VInt` literal syntax
  (`classifyBareWord` only promotes `true`/`false`), so the same constructor-mismatch bug
  exists for `int` variables and M1's default coercion does not close it at the expression
  layer. Added this to Surprises & Discoveries, opened a Decision Log item recommending a
  4th M1 edit to classify numeric barewords as `VInt`, and annotated M3 with an effort note
  on extracting `{{#if …}}` expressions from template file contents (not currently read by
  `buildReport`).
