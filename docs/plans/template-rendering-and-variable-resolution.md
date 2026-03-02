# Template Rendering and Variable Resolution

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

After this work is complete, a developer can load a Seihou module and generate real project
files from it. Given the `haskell-base` test fixture module (which declares variables like
`project.name` and `project.version`, and defines template files containing `{{project.name}}`
placeholders), the generation engine will resolve variables from multiple sources (CLI overrides,
defaults, etc.), substitute placeholders into template content and destination paths, evaluate
conditional `when` expressions to decide which steps to execute, and produce a list of filesystem
operations (write file, create directory, copy file). A dry-run mode will display the planned
operations without writing anything to disk.

The user-visible outcome: calling `resolveVariables` with a module and a set of CLI overrides
produces typed, validated variable bindings with provenance metadata. Calling `compilePlan`
with a module, its base directory, and resolved variables produces a list of `Operation` values.
Tests will exercise the full pipeline: load a module from Dhall, resolve variables, compile
the plan, and verify the generated file contents are correct — including placeholder substitution,
conditional step filtering, and destination path expansion.

This corresponds to M2 (Generation Engine) from `docs/dev/roadmap/v1-milestones.md`.


## Progress

- [x] Milestone 1: Variable Resolution — implement the `ResolvedVar` and `VarSource` types,
      the `resolveVariables` function (6-layer precedence chain), type coercion from strings,
      variable validation, and the `--explain` provenance display format. (2026-03-01)
- [x] Milestone 2: Template Placeholder Engine — implement the `renderTemplate` function that
      parses `{{placeholder}}` syntax in text content, resolves each placeholder against
      resolved variables, handles type coercion to text, supports `\{{` escape sequences,
      and reports errors with line numbers for unresolved placeholders. (2026-03-01)
- [x] Milestone 3: Plan Compilation — implement the `compilePlan` function that walks a
      module's steps, evaluates `when` conditions, dispatches to the correct strategy (Copy
      and Template for this milestone), reads source files, renders templates, expands
      destination paths, and produces a list of `Operation` values. (2026-03-01)
- [x] Milestone 4: DhallText Strategy — implement the DhallText generation strategy, which
      first substitutes placeholders into a Dhall source file and then evaluates the result
      through the Dhall interpreter to produce final text output. (2026-03-01)
- [x] Milestone 5: Integration Testing and Fixture Expansion — expand the `haskell-base`
      fixture to exercise all strategies and conditional logic, write end-to-end tests that
      load, resolve, compile, and verify, run `nix fmt` and `nix flake check`. (2026-03-01)


## Surprises & Discoveries

- The `package.cabal.tpl` template references `{{license}}`, which means the LICENSE *conditional*
  step and the cabal *template* step are coupled: if `license` is not in the variable map, the
  cabal template fails with an unresolved placeholder even though the LICENSE copy step is correctly
  skipped. In a real scenario, `license` always has a default ("MIT"), so this coupling is benign.
  The integration test for "LICENSE step absent" uses a synthetic stripped-down module instead of the
  full haskell-base fixture.

- Dhall's multiline text literals (`''...''`) append a trailing newline. The `cabal.project.dhall`
  fixture produces output ending with `\n` due to this behavior. Tests account for this.


## Decision Log

- Decision: Defer the Structured strategy (`.gen` files producing JSON/YAML) to a later plan.
  Rationale: The Structured strategy requires adding `aeson` and `yaml` as dependencies and
  involves Dhall record evaluation with serialization — a distinct concern from template
  rendering. The Copy, Template, and DhallText strategies are sufficient for the M2 milestone
  and the `haskell-base` example. Structured generation can be added in M4 (Composition) or
  as a standalone follow-up plan.
  Date: 2026-03-01

- Decision: Defer interactive prompts (the `Console` effect for asking users for missing
  required variables) to M3 (CLI Core).
  Rationale: M2 focuses on the generation engine itself. Variable resolution will return
  errors for missing required variables rather than prompting. The prompt infrastructure
  (the `Console` effect interface already exists but has no interpreter) belongs in the CLI
  integration milestone. For M2, tests supply all variables explicitly.
  Date: 2026-03-01

- Decision: Defer config file resolution (local, namespace, global Dhall config files) to M3.
  Rationale: The 6-layer precedence chain described in the variable resolution design doc
  includes layers 3–5 that read config files from disk. These layers require the `ConfigReader`
  effect interpreter, which does not exist yet. For M2, the resolution chain will support
  CLI overrides (layer 1), environment variables (layer 2), and module defaults (layer 6).
  Layers 3–5 (local config, namespace config, global config) will be added when the
  `ConfigReader` interpreter is implemented in M3.
  Date: 2026-03-01

- Decision: Variable resolution is a pure function taking explicit inputs, not an effect.
  Rationale: At the M2 level, all variable sources (CLI overrides, environment map, module
  defaults) can be passed as arguments. This keeps the resolution logic pure and easy to test.
  When config file layers are added in M3, the calling code will read configs via effects and
  pass the results into the same pure resolution function.
  Date: 2026-03-01

- Decision: Use `IO` for plan compilation (not the effectful stack) for this milestone.
  Rationale: Plan compilation needs to read template source files from disk. The `Filesystem`
  effect interface exists but has no interpreter yet. Using plain `IO` for file reads keeps
  this milestone self-contained. When the `Filesystem` interpreter is built in M3, the plan
  compiler can be lifted into the effect stack.
  Date: 2026-03-01


## Outcomes & Retrospective

All 5 milestones completed. The M2 (Generation Engine) milestone from the roadmap is now
implemented. Final test count: 164 passing tests (86 new, 78 existing).

New modules created:
- `Seihou.Core.Variable` — Variable resolution with 3-layer precedence (CLI, env, default),
  type coercion, validation, and explain formatting.
- `Seihou.Engine.Template` — Template placeholder engine with `{{var}}` substitution, escape
  sequences, and line-number error reporting.
- `Seihou.Engine.Plan` — Plan compiler dispatching Copy, Template, and DhallText strategies
  with conditional step evaluation and directory creation.

New types added to `Seihou.Core.Types`: `VarSource`, `ResolvedVar`, `VarError`,
`PlaceholderError`.

The haskell-base fixture now exercises all three implemented strategies (Copy, Template,
DhallText) with conditional steps and placeholder destination paths. `nix fmt` and
`nix flake check` pass.


## Context and Orientation

Seihou is a composable, type-safe project scaffolding system. It uses Dhall (a type-safe
configuration language) to define module definitions that declare variables, prompts, generation
steps, and dependencies. The project is structured as a Cabal multi-package workspace with
`seihou-core` (the library) and `seihou-cli` (the executable), built with GHC 9.12.2 and the
GHC2024 language standard. The development environment is managed by a Nix flake at `flake.nix`.

The previous two plans (at `docs/plans/bootstrap-and-cli-skeleton.md` and
`docs/plans/module-loading-and-dhall-eval.md`) established the project structure, core types,
effect interfaces, CLI parser, Dhall module loading, expression parser, and module validation.
The current test suite has 78 passing tests.

The key files and modules relevant to this plan are described below.

`seihou-core/src/Seihou/Core/Types.hs` defines all domain types. The ones most relevant here
are: `VarName` (a newtype over `Text`, e.g., `"project.name"`), `VarType` (sum type with
constructors `VTText`, `VTBool`, `VTInt`, `VTList VarType`, `VTChoice [Text]`), `VarValue`
(sum type with constructors `VText Text`, `VBool Bool`, `VInt Int`, `VList [VarValue]`),
`VarDecl` (a record with `varName`, `varType`, `varDefault`, `varDescription`, `varRequired`,
`varValidation`), `Validation` (sum type: `ValPattern Text`, `ValRange Int Int`,
`ValMinLength Int`, `ValMaxLength Int`), `Strategy` (sum type: `Copy`, `Template`, `DhallText`,
`Structured`), `Step` (record with `stepStrategy`, `stepSrc`, `stepDest`, `stepWhen`),
`Module` (record with `moduleName`, `moduleDescription`, `moduleVars`, `moduleExports`,
`modulePrompts`, `moduleSteps`, `moduleDependencies`), `Expr` (the expression AST:
`ExprEq VarName VarValue`, `ExprAnd`, `ExprOr`, `ExprNot`, `ExprIsSet VarName`,
`ExprLit Bool`), and `Operation` (sum type: `WriteFileOp`, `CreateDirOp`, `CopyFileOp`,
`RunCommandOp`).

`seihou-core/src/Seihou/Core/Expr.hs` provides `parseExpr :: Text -> Either Text Expr` and
`evalExpr :: Map VarName VarValue -> Expr -> Bool`. The expression evaluator is pure and takes
a `Map VarName VarValue` as its variable context.

`seihou-core/src/Seihou/Core/Module.hs` provides module discovery, validation, and loading.
It includes `extractPlaceholders :: Text -> [Text]` which extracts variable references from
placeholder syntax like `"src/{{project.name}}/Main.hs"`. The `loadModule` function chains
discovery, Dhall evaluation, decoding, and validation.

`seihou-core/src/Seihou/Dhall/Eval.hs` provides `evalModuleFromFile` and all Dhall decoders.
It also provides the spike function `evalDhallExpr :: Text -> IO (Map Text Text)` which
evaluates arbitrary Dhall expressions — this will be useful for the DhallText strategy.

The test fixture at `seihou-core/test/fixtures/haskell-base/` contains a `module.dhall` file
declaring 3 variables (`project.name`, `project.version`, `license`), 1 prompt, 4 steps
(2 Template, 1 Copy with `when` condition, 1 Template with placeholder destination), and
template files in `files/` (including `README.md.tpl` with `{{project.name}}` and
`{{project.version}}` placeholders).

The test infrastructure uses tasty as the runner and hspec (via `tasty-hspec`) for assertions.
Tests are in `seihou-core/test/` with the runner at `seihou-core/test/Main.hs`. The current
test modules are: `TypesSpec`, `ExprSpec`, `ModuleSpec`, `DhallEvalSpec`, and
`Integration.ModuleLoadSpec`.

The `seihou-core/seihou-core.cabal` file lists the library's exposed modules and dependencies.
Current library dependencies are: `base`, `containers`, `dhall`, `directory`, `effectful-core`,
`filepath`, `text`. The test suite additionally depends on `hspec`, `tasty`, `tasty-hspec`,
`temporary`.


## Plan of Work

The work is divided into five milestones. Each builds on the previous one and is independently
verifiable.


### Milestone 1: Variable Resolution

The goal is to implement the variable resolution pipeline. At the end, a function takes a
module's variable declarations, a map of CLI overrides, and a map of environment variables,
and produces a map of resolved variables with provenance metadata — or returns errors for
missing required variables and validation failures.

Add two new types to `seihou-core/src/Seihou/Core/Types.hs`. The `VarSource` type is a sum
type that tracks where a variable's value came from: `FromCLI`, `FromEnv Text` (carrying the
environment variable name), `FromLocalConfig`, `FromNamespaceConfig Text`, `FromGlobalConfig`,
`FromDefault`, or `FromPrompt`. The `ResolvedVar` type is a record with three fields:
`resolvedValue :: VarValue`, `resolvedSource :: VarSource`, and `resolvedDecl :: VarDecl`. Also
add a `VarError` sum type with constructors for the error conditions: `MissingRequiredVar
VarName`, `TypeMismatch VarName VarType VarValue`, `ValidationFailed VarName Text`, and
`CoercionFailed VarName VarType Text`.

Create a new module `seihou-core/src/Seihou/Core/Variable.hs` with the following functions.

`resolveVariables` is the main entry point. It takes a list of `VarDecl` values (from a
module), a `Map VarName Text` of CLI overrides, and a `Map Text Text` of environment variables.
It walks each `VarDecl` and resolves the value using the precedence chain: first check CLI
overrides, then check environment variables (the env var name is derived by uppercasing the
variable name, replacing `.` with `_`, and prepending `SEIHOU_VAR_`), then use the module
default if present. If no value is found and the variable is required, return
`MissingRequiredVar`. For each resolved value, coerce it from text (if from CLI or env) to
the declared type, validate it against the variable's `Validation` constraint, and record the
provenance. Return either a list of errors or a `Map VarName ResolvedVar`.

`coerceValue` takes a `VarType` and a `Text` value and attempts to convert it. For `VTText`,
the text is used as-is. For `VTBool`, the strings `"true"`, `"yes"`, and `"1"` produce
`VBool True`; `"false"`, `"no"`, and `"0"` produce `VBool False`; anything else is a
`CoercionFailed` error. For `VTInt`, parse as a decimal integer. For `VTList VTText`, split on
commas. For `VTChoice options`, validate that the text is one of the allowed options.

`validateVarValue` takes a `VarDecl` and a `VarValue` and checks the `Validation` constraint.
`ValPattern pat` checks that the text value matches the pattern (for M2, implement a simple
check using `Data.Text` functions — full regex can come later). `ValRange lo hi` checks that
an integer value is in range. `ValMinLength n` and `ValMaxLength n` check text length.

`formatExplain` takes a `Map VarName ResolvedVar` and produces a human-readable text block
showing each variable's value and provenance, matching the format described in the variable
resolution design doc.

`envVarName` takes a `VarName` and returns the corresponding environment variable name
(e.g., `VarName "project.name"` becomes `"SEIHOU_VAR_PROJECT_NAME"`).

Write tests in `seihou-core/test/Seihou/Core/VariableSpec.hs` covering: resolution from CLI
overrides, resolution from environment variables, resolution from module defaults, missing
required variable error, type coercion (bool, int, list, choice), coercion failure, validation
(pattern, range, length), the precedence chain (CLI beats env beats default), and the explain
format.

Add `Seihou.Core.Variable` to `exposed-modules` in `seihou-core/seihou-core.cabal`. Add
`Seihou.Core.VariableSpec` to `other-modules` in the test suite. Update `seihou-core/test/Main.hs`
to include the new test module.

Acceptance: `cabal test all` passes with the new variable resolution tests alongside the
existing 78 tests.


### Milestone 2: Template Placeholder Engine

The goal is to implement the template rendering engine. At the end, a function takes a template
text and a map of resolved variables and produces the rendered output with all placeholders
substituted — or returns errors listing unresolved placeholders with line numbers.

Create a new module `seihou-core/src/Seihou/Engine/Template.hs` with the following functions.

`renderTemplate` is the main entry point. It takes a `Text` (the template content) and a
`Map VarName VarValue` (the resolved variable values) and returns `Either [PlaceholderError]
Text`. It scans the input for `{{...}}` placeholders, looks up each variable name in the map,
coerces the value to text, and substitutes it. The escape sequence `\{{` produces a literal
`{{` in the output (the backslash is consumed). If any placeholder references an undefined
variable, the function returns `Left` with a list of `PlaceholderError` values.

`valueToText` converts a `VarValue` to its text representation for template substitution.
`VText t` returns `t`. `VBool True` returns `"true"`, `VBool False` returns `"false"`.
`VInt n` returns the decimal representation. `VList vs` returns a comma-separated rendering
of the elements (each element recursively converted via `valueToText`).

`renderDestPath` takes a destination path text (which may contain `{{...}}` placeholders) and
a `Map VarName VarValue` and returns the expanded path. This reuses the same placeholder
substitution logic as `renderTemplate`.

Add a `PlaceholderError` type to `seihou-core/src/Seihou/Core/Types.hs` with constructors
`UnresolvedPlaceholder VarName Int` (variable name and line number) and
`MalformedPlaceholder Text Int` (raw text and line number).

Write tests in `seihou-core/test/Seihou/Engine/TemplateSpec.hs` covering: simple placeholder
substitution, multiple placeholders on one line, placeholders across multiple lines,
`VBool`/`VInt`/`VList` coercion to text, escape sequence `\{{`, unresolved placeholder error
with correct line number, template with no placeholders (passthrough), empty template, and
destination path expansion.

Add `Seihou.Engine.Template` to `exposed-modules` in `seihou-core/seihou-core.cabal`. Add the
test module to the test suite. Create the `seihou-core/src/Seihou/Engine/` directory.

Acceptance: `cabal test all` passes with template rendering tests. A template containing
`"# {{project.name}}\nVersion: {{project.version}}"` rendered with
`{project.name = VText "my-app", project.version = VText "0.1.0.0"}` produces
`"# my-app\nVersion: 0.1.0.0"`.


### Milestone 3: Plan Compilation

The goal is to implement the plan compiler that transforms a module's steps into filesystem
operations. At the end, a function takes a module, its base directory, and resolved variables,
evaluates `when` conditions, reads source files, renders templates, expands destination paths,
and produces a list of `Operation` values.

Create a new module `seihou-core/src/Seihou/Engine/Plan.hs` with the following functions.

`compilePlan` is the main entry point. It takes a `FilePath` (the module's base directory,
containing the `files/` subdirectory), a `Module`, and a `Map VarName VarValue` (resolved
variable values). It walks `moduleSteps m` in declaration order. For each step, it first
evaluates the `stepWhen` expression (if present) using `evalExpr` from `Seihou.Core.Expr`; if
the expression evaluates to `False`, the step is skipped. Then it dispatches based on
`stepStrategy`:

For the `Copy` strategy: read the source file from `baseDir </> "files" </> stepSrc` as raw
bytes, expand the destination path using `renderDestPath`, and produce a `WriteFileOp` with the
file content. Also produce `CreateDirOp` operations for any parent directories in the
destination path that would need to be created.

For the `Template` strategy: read the source file from `baseDir </> "files" </> stepSrc` as
text, call `renderTemplate` with the resolved variables, expand the destination path, and
produce a `WriteFileOp` with the rendered content. Report template errors (unresolved
placeholders) as failures.

For the `DhallText` strategy: defer to Milestone 4 (return an error indicating the strategy
is not yet implemented).

For the `Structured` strategy: defer (return an error indicating the strategy is not yet
implemented).

`compilePlan` returns `Either [Text] [Operation]`, where the left side is a list of error
messages (from template rendering failures, missing files, etc.) and the right side is the
ordered list of operations.

Also create a helper `parentDirs :: FilePath -> [FilePath]` that extracts the parent directory
chain from a path (e.g., `"src/Lib.hs"` produces `["src"]`, `"a/b/c.txt"` produces
`["a", "a/b"]`). These are used to emit `CreateDirOp` operations before the file write.

Write tests in `seihou-core/test/Seihou/Engine/PlanSpec.hs` covering: compiling a Copy step
(produces WriteFileOp with unchanged content), compiling a Template step (produces WriteFileOp
with rendered content), skipping a step when `when` evaluates to `False`, including a step when
`when` evaluates to `True`, destination path expansion with placeholders, parent directory
creation operations, template error propagation (unresolved placeholder), and compiling the
full `haskell-base` fixture module end-to-end (load module, resolve variables, compile plan,
verify operations).

Add `Seihou.Engine.Plan` to `exposed-modules`. Add the test module to the test suite.

Acceptance: `cabal test all` passes. The `haskell-base` fixture compiles to a plan that
includes: `CreateDirOp "src"`, `WriteFileOp "README.md" "# my-app\nVersion: 0.1.0.0\n"`,
`WriteFileOp "src/Lib.hs" "module Lib where\n"`, `WriteFileOp "LICENSE" ""` (the copy, only
when `license` is set), and `WriteFileOp "my-app.cabal" ...` (the template with expanded
destination).


### Milestone 4: DhallText Strategy

The goal is to implement the DhallText generation strategy. At the end, a `.dhall` source file
in a module's `files/` directory is first processed through the placeholder engine (to inject
variable values as Dhall string literals), then evaluated through the Dhall interpreter, and
the resulting `Text` value is used as the file content.

Add a new function `renderDhallText` to `seihou-core/src/Seihou/Engine/Plan.hs` (or create
`seihou-core/src/Seihou/Engine/Strategy/DhallText.hs` if the module is getting large). This
function takes the template-substituted Dhall source text and evaluates it using
`Dhall.input Dhall.strictText`. If evaluation succeeds, return the text. If it fails, return
an error message.

Wire the DhallText strategy into `compilePlan` so that steps with `stepStrategy = DhallText`
go through: read source file, substitute placeholders, evaluate as Dhall, produce `WriteFileOp`.

Create a test fixture `.dhall` file in the test fixtures that uses Dhall features (string
interpolation, conditionals) to produce text output. For example, a `cabal.project.dhall` file
that takes `project.name` via placeholder and uses Dhall string interpolation to produce the
final content.

Write tests covering: a simple DhallText file that produces literal text, a DhallText file with
Dhall string interpolation using injected variables, error handling for invalid Dhall, and
integration with the plan compiler.

Acceptance: `cabal test all` passes. A DhallText source file containing Dhall logic evaluates
to the correct text output with variables injected.


### Milestone 5: Integration Testing and Fixture Expansion

The goal is to verify the full pipeline end-to-end and ensure code quality. At the end, the
`haskell-base` fixture exercises Copy, Template, and DhallText strategies with conditional
steps, and integration tests verify correct output for each.

Expand the `haskell-base` fixture at `seihou-core/test/fixtures/haskell-base/` to include a
DhallText step. Add a `files/cabal.project.dhall` file that uses Dhall features to generate
a `cabal.project` file. Update `module.dhall` to include this step. Populate the template
files with realistic placeholder content: `README.md.tpl` should include `{{project.name}}`,
`{{project.version}}`, and `{{license}}`; `package.cabal.tpl` should include name, version,
and license placeholders.

Write integration tests in `seihou-core/test/Seihou/Integration/GenerationSpec.hs` that:
load the `haskell-base` module via `loadModule`, resolve variables with explicit overrides
(`project.name = "my-app"`), compile the plan, and assert the exact content of each generated
file. Test the conditional LICENSE step (present when `license` is set, absent when not).
Test destination path expansion (`{{project.name}}.cabal` becomes `my-app.cabal`). Test that
the DhallText step produces correct Dhall-evaluated output.

Run `nix fmt` to format all new code. Run `nix flake check` to verify the full CI passes.

Acceptance: All tests pass. `nix flake check` succeeds. The full pipeline (load module,
resolve variables, compile plan) produces correct operations for the `haskell-base` fixture.


## Concrete Steps

All commands assume the working directory is the repository root:
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`.

Build the project at any point with:

    cabal build all

Run the full test suite with:

    cabal test all

Format all code with:

    nix fmt

Run the full Nix check with:

    nix flake check

After all milestones are complete, `cabal test all` should show output including test groups
for the new modules:

    seihou-core
      Seihou.Core.Types
        ...                                           (22 existing tests)
      Seihou.Core.Expr
        ...                                           (27 existing tests)
      Seihou.Core.Module
        ...                                           (15 existing tests)
      Seihou.Core.Variable
        resolves from CLI overrides                   PASS
        resolves from environment variables            PASS
        resolves from module defaults                  PASS
        rejects missing required variable              PASS
        coerces bool from string                       PASS
        coerces int from string                        PASS
        CLI override beats env and default             PASS
        validates pattern constraint                   PASS
        formats explain output                         PASS
        ...
      Seihou.Engine.Template
        substitutes simple placeholder                 PASS
        handles escape sequence                        PASS
        reports unresolved placeholder with line number PASS
        coerces VBool to text                          PASS
        renders destination path                       PASS
        ...
      Seihou.Engine.Plan
        compiles Copy step                             PASS
        compiles Template step with rendering          PASS
        skips step when condition is false              PASS
        expands destination path                       PASS
        creates parent directories                     PASS
        compiles haskell-base fixture end-to-end       PASS
        ...
      Seihou.Dhall.Eval
        ...                                           (7 existing tests)
      Seihou.Integration.ModuleLoad
        ...                                           (7 existing tests)
      Seihou.Integration.Generation
        full pipeline produces correct README.md       PASS
        conditional LICENSE step present when set       PASS
        conditional LICENSE step absent when not set    PASS
        destination path expanded correctly             PASS
        DhallText step produces evaluated output       PASS
        ...


## Validation and Acceptance

The M2 milestone is complete when all of the following are true.

Variable resolution takes a module's variable declarations, CLI overrides, and environment
variables, and produces a `Map VarName ResolvedVar` with correct values and provenance. A test
resolves `project.name` from a CLI override (`VarSource = FromCLI`), `project.version` from
a module default (`VarSource = FromDefault`), and `license` from an environment variable
(`VarSource = FromEnv "SEIHOU_VAR_LICENSE"`), and asserts all three have the correct values
and sources. A test with a missing required variable (no CLI, no env, no default) returns
`MissingRequiredVar`.

Template rendering substitutes `{{project.name}}` with the resolved value and returns the
correct output. A test renders `"# {{project.name}}\nVersion: {{project.version}}"` with
`project.name = VText "my-app"` and `project.version = VText "0.1.0.0"` and asserts the output
is `"# my-app\nVersion: 0.1.0.0"`. An unresolved placeholder returns `UnresolvedPlaceholder`
with the correct line number. The escape `\{{` produces literal `{{`.

Plan compilation walks a module's steps, skips steps whose `when` condition is `False`, renders
templates, expands destination paths, and produces the correct list of `Operation` values. A
test loads the `haskell-base` fixture, resolves variables with `project.name = "my-app"`, and
asserts the plan contains `WriteFileOp "README.md" "# my-app\nVersion: 0.1.0.0\n"` and
`WriteFileOp "my-app.cabal" ...` (destination path expanded from `{{project.name}}.cabal`).

DhallText evaluation takes a Dhall source file with injected variables and produces the
evaluated text output.

All existing 78 tests continue to pass (no regressions).

`cabal build all`, `cabal test all`, and `nix flake check` all succeed.


## Idempotence and Recovery

Every step is additive. New modules and files are created; existing files are modified only to
add imports, exports, or dependencies. No files are deleted.

Variable resolution is a pure function with no side effects. It can be called repeatedly with
the same inputs and will always produce the same output.

Template rendering is pure (given the same template text and variable map, it always produces
the same output). It does not modify any files.

Plan compilation reads source files from disk but does not write anything. The compiled plan
is a data structure (list of `Operation` values) that can be inspected, serialized, or discarded
without affecting the filesystem.

If a milestone fails partway through, the codebase remains in a compilable state because each
new module is self-contained. The worst case is a new module that does not compile, which can
be fixed or removed without affecting existing code.


## Interfaces and Dependencies

### New Haskell Package Dependencies

No new package dependencies are required for Milestones 1–3. The existing `text`, `containers`,
and `filepath` packages provide all needed functionality. For Milestone 4, the existing `dhall`
dependency provides `Dhall.input` for evaluating DhallText source files.

### New Modules to Create

In `seihou-core/src/Seihou/Core/Variable.hs`:

    resolveVariables
      :: [VarDecl]
      -> Map VarName Text      -- CLI overrides
      -> Map Text Text         -- Environment variables
      -> Either [VarError] (Map VarName ResolvedVar)

    coerceValue :: VarType -> Text -> Either VarError VarValue

    validateVarValue :: VarDecl -> VarValue -> Either VarError ()

    formatExplain :: Map VarName ResolvedVar -> Text

    envVarName :: VarName -> Text

In `seihou-core/src/Seihou/Engine/Template.hs`:

    renderTemplate :: Text -> Map VarName VarValue -> Either [PlaceholderError] Text

    valueToText :: VarValue -> Text

    renderDestPath :: Text -> Map VarName VarValue -> Either [PlaceholderError] Text

In `seihou-core/src/Seihou/Engine/Plan.hs`:

    compilePlan
      :: FilePath             -- Module base directory
      -> Module
      -> Map VarName VarValue -- Resolved variable values
      -> IO (Either [Text] [Operation])

### Types to Add to `seihou-core/src/Seihou/Core/Types.hs`

    data VarSource
      = FromCLI
      | FromEnv Text
      | FromLocalConfig
      | FromNamespaceConfig Text
      | FromGlobalConfig
      | FromDefault
      | FromPrompt
      deriving stock (Eq, Show, Generic)

    data ResolvedVar = ResolvedVar
      { resolvedValue  :: VarValue
      , resolvedSource :: VarSource
      , resolvedDecl   :: VarDecl
      }
      deriving stock (Eq, Show, Generic)

    data VarError
      = MissingRequiredVar VarName
      | TypeMismatch VarName VarType VarValue
      | ValidationFailed VarName Text
      | CoercionFailed VarName VarType Text
      deriving stock (Eq, Show, Generic)

    data PlaceholderError
      = UnresolvedPlaceholder VarName Int
      | MalformedPlaceholder Text Int
      deriving stock (Eq, Show, Generic)

### New Test Modules

    seihou-core/test/Seihou/Core/VariableSpec.hs
    seihou-core/test/Seihou/Engine/TemplateSpec.hs
    seihou-core/test/Seihou/Engine/PlanSpec.hs
    seihou-core/test/Seihou/Integration/GenerationSpec.hs

### Test Fixture Updates

    seihou-core/test/fixtures/haskell-base/module.dhall  (add license var, DhallText step)
    seihou-core/test/fixtures/haskell-base/files/README.md.tpl  (add license placeholder)
    seihou-core/test/fixtures/haskell-base/files/package.cabal.tpl  (add real content)
    seihou-core/test/fixtures/haskell-base/files/cabal.project.dhall  (new, DhallText)
