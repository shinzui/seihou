---
id: 115
slug: validate-recipes-without-running-their-composition
title: "Validate recipes without running their composition"
kind: exec-plan
created_at: 2026-10-28T12:32:47Z
intention: "intention_01m617xj25ea0vq6xc0sezcgac"
provenance:
  created_by:
    model: "gpt-6-astra"
    harness: "codex-cli"
    at: 2026-10-28T12:32:47Z
  revisions:
    - model: "gpt-6.1-sol"
      harness: "codex-cli"
      at: 2026-10-28T13:53:24Z
      mode: "implement"
      note: "Implement descriptor-only recipe validation, public CLI coverage, and authoring guidance."
    - model: "gpt-6.1-sol"
      harness: "codex-cli"
      at: 2026-10-28T14:22:49Z
      mode: "update"
      note: "Link completed request and verify released installed validator."
---

# Validate recipes without running their composition

This ExecPlan is a living document. Keep Progress, Surprises & Discoveries, Decision Log,
and Outcomes & Retrospective current during implementation. Record implementation friction
using `agents/skills/exec-plan/FRICTION.md`; distill durable decisions into `docs/adr/`
before completion.


## Purpose / Big Picture


Implement [IR-13](../improvement-requests/validate-a-recipe-without-running-its-composition.md):
a recipe author can check a local `recipe.dhall` with one command, without answering project
questions, generating project files, executing member commands, or installing modules.
A recipe is a named list of modules with optional variable declarations, prompts, and
per-module bindings. Descriptor validation checks that definition, rather than running
the modules it names.

The starting state is an existing recipe directory in a fresh checkout, potentially with
unpublished or unavailable modules and required variables without defaults. The ordinary
workflow is `seihou validate-recipe ./my-stack`; CI runs exactly
`seihou validate-recipe ./my-stack </dev/null`. No registry setup, manifest, configuration,
`--var`, or migration is needed. Omitting PATH validates the current directory. Repeating
the command after an edit has the same read-only project behavior. First-time authors can
run `seihou new-recipe my-stack --module base`, edit the descriptor, then validate it.
Scaffolding is authoring work, not a prerequisite imposed on existing recipes.

Success exits 0 and identifies the valid recipe. Failure identifies the descriptor and
field or member needing repair, and exits nonzero. This plan includes discoverable help,
CI documentation, and verification of a released, installed executable; passing source
tests alone does not complete delivery.


## Progress


- [x] Milestone 1 (2026-10-28; Cabal-built CLI: unmodified unpublished-member scaffold, current-directory invocation, both existing recipe fixtures, and missing/malformed descriptors all passed with stdin closed): The public command evaluates a local recipe and uses the shared validator; an ordinary scaffolded recipe passes with stdin closed and no installed members.
- [x] Milestone 2 (2026-10-28; shared core/composition regressions and 21 public-command cases pass, including snapshots with a valid effectful member present/absent, repeat runs, closed stdin, and isolated XDG state): Shared declaration, prompt, condition, and binding checks have actionable errors; automated public-command tests prove valid interactive recipes require no answers or composition effects.
- [x] Milestone 3 (2026-10-28): Help, CI documentation, scaffolding guidance and ADR 0022 are delivered in published/installed Seihou 0.12.0.1 at f529a7a. Source and complete native package tests pass; the installed ordinary valid/invalid workflow, help and CI invocation pass.

Delivery (2026-10-28): The user authorized the coordinated release and closure
of EPs 113–115. Seihou 0.12.0.1 is published and installed, and ordinary acceptance
passed against the installed executable. Complete delivery evidence follows below.


## Surprises & Discoveries


Dhall extraction supports both member declaration forms by bypassing a single expected
record type. Wrong-shaped member lists previously produced an internal `InvalidDecoder`
report with no enclosing field. The shared recipe decoder now gives field-specific
extraction messages, lists missing fields, and identifies a non-record descriptor.
Public-command cases cover those failures.

Forcing only the outer variable type left invalid nested types such as `list mystery`
unevaluated inside `VTList`. Recipe loading now forces nested types inside its existing
exception boundary. Core loading and public-command tests prove controlled failure.


## Decision Log


Decision (2026-10-28): Add `validate-recipe [PATH]` beside the existing validators, with
PATH interpreted as a recipe directory and defaulting to the current directory. Do not add
a unified validation dispatcher, a no-op lint flag, or a dependency-availability mode.
This gives authors the missing predictable command without introducing another interface.

Decision (2026-10-28): Keep `Seihou.Core.Recipe.validateRecipe` authoritative and extend it
for the descriptor-local rules below. Existing composition and update callers must receive
the same rules. Bindings target member variables and need not name recipe declarations;
validating those targets requires member discovery, which is outside this command.

Decision (2026-10-28): Condition syntax and references are checked statically, without
resolving values or evaluating which prompts will run. Required variables with no defaults
are valid declarations. No prompt ordering, cycle analysis, expression-language redesign,
or new binding interpolation semantics are introduced. Recipe prompt execution remains
owned by [IR-11](../improvement-requests/resolve-recipe-variables-and-prompts-before-module-resolution.md).

Decision (2026-10-28): Offline acceptance uses self-contained descriptors or local Dhall
imports. Normal Dhall evaluation may resolve descriptor-authored remote imports and use
its evaluator cache; the command does not promise that arbitrary remote imports work with
an empty cache offline. It never fetches or installs composition members. Document this
boundary rather than requiring authors to preinstall modules.


## Outcomes & Retrospective


The source implementation delivers `seihou validate-recipe [PATH]` without module
discovery, input resolution, composition planning or side effects. Required unanswered
conditional declarations pass. Invalid fields, declarations and prompt references have
contextual diagnostics. The same semantic rules apply to composition and candidate
recipes during update. Help, authoring prompts, CI docs and scaffolding next steps
direct authors to the command. [ADR 0022](../adr/0022-recipe-descriptor-validation-is-independent-of-composition.md)
records the durable boundary.

Source verification used the Cabal executable at
`dist-newstyle/build/aarch64-osx/ghc-9.12.4/seihou-cli-0.11.0.1/x/seihou/build/seihou/seihou`,
reporting `seihou v0.11.0.1 (c245948)` with this implementation in the working tree.
`nix develop -c cabal build all` and `nix develop -c cabal test all` passed. The 21
`ValidateRecipe` tests are included in the 812 CLI tests. The documentation audit passed
18 topics, 33 command pages plus agent run, 26 packaged assets, six example modules
and eight provider-free prompt renders. All four native aarch64-darwin flake checks
passed; incompatible systems were not checked. `cabal check` reported no warnings for
all three packages, and `cabal sdist all` included the new handler, report and tests
as well as updated embedded help/context assets.

Retained manual acceptance fixtures are under `/tmp/seihou-plan115-acceptance-pl9omy8y`:
`my-stack` is the unmodified unpublished-member scaffold, `local-import` exercises a local
Dhall import, `empty-members` and `undeclared-prompt` exit 1 with field-specific messages,
and `unreadable` demonstrated a controlled permission-denied loading error (its file
permissions have been restored). The default-directory invocation passed; a missing
directory exited 4. Shell quoting in the scaffold's next action was also checked with
spaces, a quote, dollar sign and backticks in the output path.

Published and installed delivery is complete in 0.12.0.1. The earlier installed
0.11.0.1 binary and source-build evidence above are historical checkpoints.
FRIC-6 is resolved by installing the released standalone profile at priority 4 while
preserving Home Manager. Shared FRIC-5 is resolved by the verified native packaging
fixes in 0.12.0.1.

### Released and installed delivery (2026-10-28)


Seihou 0.12.0.1 is published for `seihou-core`, `seihou-cli` and
`seihou-okf-extension`, including API documentation. The GitHub release/tag is
`v0.12.0.1`, at revision `f529a7ab63609c7494240d12e52b541bf7e3643b`.
The dependency-source schema is published at
`d3c78cd81d9697ebff3128732ec673a17e65c73f` in `mori://shinzui/seihou-schema`;
the schema gitlink, emitted Dhall URL/integrity hash and Nix input/lock agree.

The effective installed executable is `/Users/shinzui/.nix-profile/bin/seihou`,
reporting `seihou v0.12.0.1 (f529a7a)`. Its Nix profile records
`github:shinzui/seihou/v0.12.0.1`, resolving to that same revision. The standalone
entry has priority 4 to preserve and override the Home Manager entry at priority 5.
The source build and installed binary are separately verified.

Source checks passed all 2,134 tests (1,271 core, 812 CLI, 51 extension), build,
formatting, package checks, documentation audit and four native flake checks.
The complete native Nix package build also passed all 2,134 tests before patch
publication. Its evidence is `/tmp/seihou-release-patch-native.log`; incompatible
platforms were not exercised. The audit covers 18 topics, 33 command pages plus
agent run, 26 assets, six validated examples and eight provider-free prompt renders.

Installed acceptance passed the following ordinary workflows, with isolated XDG
state and no real remote provisioning:

```bash
bash scripts/test-install-closure.sh /Users/shinzui/.nix-profile/bin/seihou
python3 scripts/verify-recipe-inputs.py --binary /Users/shinzui/.nix-profile/bin/seihou --area /tmp/seihou-release-0121-installed-inputs --consumer
```

The first verifies the required three-registry closure, origins, run, dry-run
cache equality, repeat install, missing/unavailable sources, collision/force,
contradictory origins, cycles, diamonds, local shadows and legacy declarations.
The second verifies terminal true/false questions once, saved recipe inputs,
fresh-clone and new-consumer replay, and representative real-module consumers
with provisioning commands disabled. It is not a published TAN recipe.

Installed `validate-recipe` also passed the unmodified unpublished-member scaffold,
current-directory invocation, an unanswered conditional recipe in a directory with
spaces, help and top-level discovery. Empty members, an undeclared prompt and
malformed Dhall exited 1 with contextual messages; missing descriptors exited 4.
Snapshots showed no project/configuration/install changes. Retained validation
fixtures are `/tmp/seihou-release-0121-validation-8_oilm8b`; transcripts are
`/tmp/seihou-release-installed-closure.log`,
`/tmp/seihou-release-installed-inputs.log` and
`/tmp/seihou-release-installed-validation.log`.

Python is used only by test/acceptance harnesses, not by the Seihou executable.
The three changed requests passed scoped strict profile/log validation. The full
legacy request corpus retains its pre-existing recommended-field diagnostics on
untouched requests.




## Context and Orientation


At plan creation, the installed binary reports `seihou v0.11.0.1 (4ade3fb)` and rejects
`seihou validate-recipe --help` with `Invalid argument`. This is a verified baseline,
not delivery evidence. The intention was created with
`mina ci --json 'Validate recipes without running their composition'`; its returned ID
is recorded in frontmatter.

`seihou-core/src/Seihou/Core/Types.hs` defines `Recipe`, `Dependency`, `VarDecl`, `Prompt`,
and `Expr`. `Dependency` pairs a member name with a map of literal text bindings.
`VarDecl` describes a variable's type, optional default, required flag, and validation
constraint. A prompt names a variable and may have a `when` expression. Expressions are
parsed conditional syntax such as `Eq github.enabled true` or `IsSet github.owner`.

`seihou-core/src/Seihou/Dhall/Eval.hs` exposes `evalRecipeFromFile`, which reads and evaluates
Dhall (the typed configuration language), decodes a `Recipe`, and returns load errors.
It already forces variable types/default coercion and prompt conditions inside its exception
boundary. `promptDecoder` parses `when` through `parseWhen`; malformed syntax must remain
a controlled diagnostic, not an uncaught exception. `recipeDecoder` and the existing
`varDeclDecoder` own record shape and type decoding. Reuse them.

`seihou-core/src/Seihou/Core/Recipe.hs` currently checks only recipe name format, a nonempty
module list, duplicate members, and binding-name syntax. It does not yet check duplicate
recipe declarations, prompt targets, or condition references. Its pure interface is
`validateRecipe :: Recipe -> Either [Text] Recipe`: it returns all semantic violations or
the original valid value, without IO. `seihou-core/src/Seihou/Composition/Recipe.hs` calls
it before expansion; `seihou-cli/src/Seihou/CLI/Update/Source.hs` also calls it when loading
candidate recipes. Extending it therefore changes runtime rejection of malformed recipes
as well as the new authoring command.

`seihou-core/src/Seihou/Core/Expr.hs` provides `exprRefs`, which traverses nested conditions
and returns referenced variable names. `seihou-core/src/Seihou/Core/Module.hs` and
`seihou-core/src/Seihou/Core/Blueprint.hs` contain precedents for unique declarations and
prompt-reference checks. Do not manufacture a fake module or resolve configuration to
validate a recipe. Share small pure helpers only where that removes actual duplication.

`seihou-cli/src-exe/Seihou/CLI/Commands.hs` owns command constructors and parsers;
`seihou-cli/src-exe/Main.hs` dispatches them.
`seihou-cli/src-exe/Seihou/CLI/ValidatePrompt.hs` demonstrates directory selection and
exit codes: missing descriptor is 4, invalid descriptor is 1, valid descriptor is 0.
Use that convention, but do not copy its generic `show` rendering of load-error constructors.
New reusable report/formatting code belongs under `seihou-cli/src/`; the thin handler that
imports `Commands` belongs under `seihou-cli/src-exe/`. Register new modules in
`seihou-cli/seihou-cli.cabal`.

Tests live in `seihou-core/test/Seihou/Core/RecipeSpec.hs`,
`seihou-core/test/Seihou/Composition/RecipeSpec.hs`, and
`seihou-core/test/Seihou/Dhall/EvalSpec.hs`. Public-command tests can use
`seihou-cli/test/Seihou/CLI/SeihouBinary.hs` to find the executable built by Cabal, avoiding
accidental testing of an older PATH binary. `seihou-cli/test/Main.hs` registers CLI tests.
`justfile`, `cabal.project`, and `scripts/audit-cli-docs.py` define build, test, and command
coverage checks. `seihou-cli/help/recipes.md` currently explicitly says no validator exists.

The relevant ADR is [ADR 0015](../adr/0015-diagnostics-name-things-as-users-do-and-never-fall-back-to-show.md):
user-facing sum-type renderers must handle constructors explicitly, name things as users
do, and give remedies specific to the cause. Apply this to the new load-error output;
retain useful Dhall parser text without dumping `DhallEvalError` wrappers. No existing ADR
specifically defines recipe descriptor validation. The other ADR headings were scanned.

The originating consumer initiative is
`mori://tan/tan-seihou-modules/masterplans/1-bootstrap-tan-keiro-projects-with-a-cross-registry-recipe`.
Its recipe is planned, so implementation must not depend on that consumer existing first.
The locally reproducible scaffold workflow below proves early usability; the conditional
GitHub/Redpanda fixture represents its needed declarations. Concurrent recipe execution and
installation work may touch the same files: preserve its changes, share `validateRecipe`,
and do not absorb prompt execution or dependency installation into this command.


## Plan of Work


### Milestone 1 — Expose the ordinary command and prove it early


Add `ValidateRecipeOpts` with an optional directory path and `ValidateRecipe` to
`seihou-cli/src-exe/Seihou/CLI/Commands.hs`, including normal top-level help registration.
Add `seihou-cli/src-exe/Seihou/CLI/ValidateRecipe.hs` with
`handleValidateRecipe :: ValidateRecipeOpts -> IO ()`, register it in the Cabal executable,
and dispatch it in `seihou-cli/src-exe/Main.hs`. Resolve only the requested directory's
`recipe.dhall`, call `evalRecipeFromFile`, then `validateRecipe`, and render a clear result.
Handle missing/unreadable files and Dhall failures without an exception escaping.

Keep the handler independent of discovery, registry, configuration resolution, prompt
execution, and composition planning. Report the path on failure and a final valid/invalid
summary. Missing descriptor exits 4; other loading or semantic errors exit 1; success exits
0. Semantic errors should name fields such as `modules`, `vars`, or `prompts`, and identify
a member or prompt variable when applicable. A bad condition should identify its prompt
and `when`; if the existing decoder loses that context, add context in the decoding path
without creating a separate CLI parser.

Before expanding validation variants, build the executable and run the scaffold workflow
under Concrete Steps. Do not install `unpublished-member`, prepare configuration, or edit
the generated recipe to make it pass. Then validate the two existing recipe fixtures under
`seihou-core/test/fixtures/haskell-with-nix-recipe/` and
`seihou-core/test/fixtures/haskell-pinned-recipe/` using only their local imports. Milestone 1
passes when these public commands succeed with stdin closed, while missing and malformed
descriptors fail clearly.


### Milestone 2 — Complete shared checks and prove absence of composition effects


Extend `validateRecipe` to reject duplicate recipe variable declarations, prompts targeting
undeclared recipe variables, and undeclared variable references anywhere in a prompt's
condition, using `exprRefs`. Preserve the existing four checks and literal binding behavior.
Dhall loading continues to reject malformed field shapes, invalid variable types/defaults,
and malformed condition syntax. Do not demand values for required declarations, compare
bindings to unavailable member schemas, or reject a binding simply because its name is
absent from recipe `vars`. Do not promote the module validator's optional expression type
lint into an unrelated new recipe error contract.

Expand the existing core recipe and Dhall tests for these rules, including multiple
independent semantic errors reported together, nested conditions, and legacy recipes with
empty `vars`/`prompts`. Add a composition regression showing `expandRecipe` rejects the
same malformed prompt references and continues to expand valid legacy bindings.

Add `seihou-cli/test/Seihou/CLI/ValidateRecipeE2ESpec.hs`, registering it in the test runner
and Cabal. Test the actual executable with closed stdin, captured output, a timeout, and
isolated XDG paths. Build a self-contained recipe declaring required booleans
`github.enabled` and `redpanda.enabled`, plus required `github.owner` prompted only when
`Eq github.enabled true`. Give these variables no defaults. Include a member module that
requires unanswered input and declares generation and a command that would create a marker
if run. Validate successfully with that member present, then remove it from the temporary
fixture and validate again successfully. Snapshot project bytes and directory entries plus
Seihou configuration/install state before and after validation; no project outputs,
manifest, command marker, or installed member may appear. Do not confuse ordinary Dhall
cache activity with Seihou composition effects.

The negative cases are missing descriptor (4), malformed Dhall/type/default/condition (1),
empty members (1), invalid recipe name (1), duplicate members (1), invalid binding name
(1), duplicate declarations (1), undeclared prompt target (1), and undeclared condition
reference (1). Check contextual messages, not whole terminal reports. Include directory
paths containing spaces, default-current-directory invocation, multiple errors, and a
repeat run. These tests establish the command's behavior rather than merely reflecting
which helper functions it calls.


### Milestone 3 — Document, release, and verify installed delivery


Create `docs/cli/validate-recipe.md` with usage, directory/default behavior, exit codes,
the exact CI command, static-check boundaries, and Dhall import caveats. Update
`docs/cli/new-recipe.md`, the recipe section of `docs/user/module-authoring.md`,
`seihou-cli/help/recipes.md`, `seihou-cli/help/registry.md`, command coverage in
`docs/cli/help.md`, and the command index in `README.md`. Update relevant embedded authoring
guidance in `seihou-cli/data/bootstrap-prompt.md` and `seihou-cli/data/assist-prompt.md` so
recipe authors are directed to this command. Add the validator as the next action printed
by `seihou-cli/src-exe/Seihou/CLI/NewRecipe.hs`. Explain that registry metadata validation,
descriptor validation, and a composition preview answer different questions.

Run the focused and final checks below. Add release notes to `CHANGELOG.md` and
`docs/user/CHANGELOG.md` describing new validation and newly rejected malformed recipe
prompts/declarations. Before declaring delivery complete, carry the accepted implementation
through the repository release workflow in `agents/skills/release/SKILL.md`, with whatever
release authorization applies at implementation time. Record actual published versions and
revision; do not choose a speculative version in this plan. Install the published CLI via
the user's established installation method and rerun the ordinary valid and invalid cases,
`--help`, and `help recipes` against the installed executable. Record its path, version,
revision, and artifact origin separately from source-build evidence. Keep this milestone
open if publishing or installed verification remains outstanding.

Distill the descriptor-versus-execution boundary into the appropriate local ADR following
`agents/skills/exec-plan/ADR.md`, and triage any friction records. This plan creation does
not itself implement, publish, or install the feature.


## Concrete Steps


Run development commands at the Seihou repository root. The pinned environment supplies
GHC and Cabal; no new library dependency is intended.

```bash
nix develop -c cabal build exe:seihou
nix develop -c cabal test seihou-core-test --test-options='-p Recipe'
nix develop -c cabal test seihou-cli-test --test-options='-p ValidateRecipe'
```

After Milestone 1, exercise first use from a new temporary directory. This creates only the
author's recipe before validation. XDG isolation is test instrumentation, not an extra
step required of users. `recipe_probe` is an absolute temporary path.

```bash
recipe_binary=$(nix develop -c cabal list-bin exe:seihou)
recipe_probe=$(mktemp -d)
cd "$recipe_probe"
"$recipe_binary" new-recipe my-stack --module unpublished-member
XDG_CONFIG_HOME="$recipe_probe/config" XDG_CACHE_HOME="$recipe_probe/cache" \
  "$recipe_binary" validate-recipe ./my-stack </dev/null
cd my-stack
XDG_CONFIG_HOME="$recipe_probe/config" XDG_CACHE_HOME="$recipe_probe/cache" \
  "$recipe_binary" validate-recipe </dev/null
```

Both validation calls must exit 0 and finish with a human-readable statement equivalent to:

```text
Recipe 'my-stack' is valid.
```

Return to the repository root for final checks:

```bash
nix develop -c cabal test all
nix develop -c just audit-cli-docs
git diff --check
nix flake check
```

Expect passing suites, a successful source/runtime CLI documentation audit, no whitespace
errors, and passing flake checks. If formatting fails, use `nix fmt`, inspect the changed
paths, and rerun affected checks. Do not rewrite unrelated work.

For installed delivery, from a checkout containing the accepted `my-stack` fixture, run:

```bash
command -v seihou
seihou --version
seihou validate-recipe --help
seihou help recipes
seihou validate-recipe ./my-stack </dev/null
```

Also run the accepted empty-members and undeclared-prompt fixtures against that executable;
record exit 1 and field-specific messages. Replace example paths with the retained fixture
locations in the completion evidence. Do not use `seihou upgrade` to update the CLI: it
refreshes installed artifacts rather than the executable.


## Validation and Acceptance


Acceptance is the single ordinary validation command working on an existing local recipe
in a fresh checkout, with no answers or installed modules. The early scaffold run proves
that no hidden setup is necessary. The automated conditional recipe proves that validation
is independent of prompt execution, even with required inputs and potentially effectful
members. An offline run with empty isolated caches and a descriptor containing no remote
imports must pass. Descriptor-authored remote imports retain normal Dhall behavior; missing
imports report a loading error and never trigger module installation.

All negative cases in Milestone 2 must terminate and identify a descriptor field/member,
with the documented exit status and no generated project state. Core validation and
composition tests must agree on descriptor semantics. Existing recipes without declarations
or prompts remain accepted, including bindings to variables known only by member modules.
The CLI's success text must not claim that unavailable members or the eventual composition
have been validated.

The command must appear in top-level help and recipe authoring guidance. The documentation
audit must pass with the new command registered. The published artifact and installed
binary must reproduce the same success/failure behavior; record evidence sufficient to
distinguish them from a locally built development executable.


## Idempotence and Recovery


Validation reads the descriptor and its Dhall imports; it never repairs files or starts a
composition. Authors correct the named field and rerun the same command. No rollback,
manifest migration, dependency installation, or configuration cleanup is part of normal
use. Tests allocate fresh temporary directories and must never alter a real user's cache.
Keep source changes additive and preserve concurrent work. Release failures leave delivery
open; do not treat an unpublished build as a release or attempt to overwrite an immutable
published package version.


## Interfaces and Dependencies


Preserve `Seihou.Core.Recipe.validateRecipe :: Recipe -> Either [Text] Recipe` and
`Seihou.Dhall.Eval.evalRecipeFromFile :: FilePath -> IO (Either ModuleLoadError Recipe)`.
The CLI adapter composes those interfaces; it does not call `expandRecipe`, registry
installation, or variable resolution. `exprRefs :: Expr -> [(VarName, Maybe VarValue)]`
is the existing local interface for condition traversal. Error/report helpers should stay
pure where practical and have no alternate semantic rules.

No schema change, new package, version pin, or external service is required for the command.
Use existing parser, text, directory, and test facilities. If implementation needs an
unfamiliar dependency API, locate source/docs with Mori first; verify registry releases and
upstream tags before changing bounds. This is a standalone plan with no MasterPlan
prerequisite. Coordinate shared recipe validation with adjacent recipe work while retaining
this plan's offline authoring and installed-delivery acceptance obligations.
