# Module Loading and Dhall Evaluation

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

After this work is complete, a developer can write a module definition in Dhall (a type-safe
configuration language), place it in the module search path, and have Seihou evaluate it into
a fully typed, validated Haskell value. The `DhallEval` effect (currently an interface-only
stub) will have a real implementation that reads a `module.dhall` file from disk, evaluates it
through the Dhall interpreter, and decodes the result into the existing `Module` type defined
in `Seihou.Core.Types`. A module discovery system will search three locations in priority
order: project-local modules, user modules, and installed modules. A validation pipeline will
check nine rules (name format, unique variables, prompt references, export references, file
existence, path safety, and expression well-formedness) and produce clear, actionable error
messages. An expression language parser will handle the conditional logic used in `when`
clauses for prompts and steps (supporting `Eq`, `And`, `Or`, `Not`, `IsSet`, and `Literal`
operations with infix syntax). A test fixture module called `haskell-base` will serve as the
integration test, proving that the full pipeline (Dhall evaluation, decoding, validation) works
end-to-end.

This corresponds to M1 (Module Loading) from `docs/dev/roadmap/v1-milestones.md`.


## Progress

- [x] Milestone 1: Dhall Spike — add the `dhall` dependency to the project, write a minimal
      Dhall file, evaluate it from Haskell, and decode it into a simple record type. This
      proves the Dhall package works with GHC 9.12.2 and GHC2024 before investing in the
      full decoder. (2026-03-01)
- [x] Milestone 2: Dhall Schema and Decoders — create the canonical Dhall schema file for
      module definitions, implement manual Dhall decoders for all core types (VarType,
      VarValue, VarDecl, VarExport, Prompt, Strategy, Step, Module), and test roundtrip
      decoding of a realistic module. (2026-03-01)
- [x] Milestone 3: Expression Language — implement the expression parser and evaluator in
      `Seihou.Core.Expr`, covering the full grammar (Eq, And, Or, Not, IsSet, Literal,
      parentheses, operator precedence). Wired parseExpr into Dhall decoders for `when`
      fields. 56 tests passing. (2026-03-01)
- [x] Milestone 4: Module Discovery and Validation — implement module discovery across the
      three search paths, implement the nine validation rules, wire everything together
      through the `DhallEval` effect's real and pure interpreters. 71 tests passing.
      (2026-03-01)
- [x] Milestone 5: Integration Testing — expanded `haskell-base` fixture to 3 vars, 4 steps,
      when expression. Created `invalid-module` fixture. Integration tests for end-to-end
      loading, error paths, and pure DhallEval interpreter. `nix fmt` and `nix flake check`
      pass. 78 tests total. (2026-03-01)


## Surprises & Discoveries

- The `dhall` package (1.42.3) compiled without issues on GHC 9.12.2. No missing system
  libraries or compatibility problems. The spike test passes on the first try.
  Evidence: `cabal build all` and `cabal test all` both succeed, 22/22 tests pass.

- The test suite needed `containers` added to its `build-depends` separately from the library
  section, since the test uses `Data.Map.Strict` directly and GHC2024 does not implicitly
  expose packages from dependency libraries to test suites.

- Dhall does NOT support recursive types. The original design doc specified `VarType` as a
  Dhall union `< Text | Bool | Int | List : VarType | Choice : List Text >`, but the
  self-reference `List : VarType` causes the Dhall evaluator to hang during normalization.
  Solution: represent VarType as a plain Text string in Dhall (e.g., `"text"`, `"bool"`,
  `"list text"`) and parse it in Haskell. This is cleaner and avoids the recursive type
  limitation entirely.
  Evidence: `cabal test` hung indefinitely when loading a fixture with the recursive type.

- `as` is a reserved keyword in Dhall (used in import expressions like `./file as Text`).
  The `VarExport` field that was named `as` in the design doc had to be renamed to `alias`
  in the Dhall schema.
  Evidence: Dhall parse error `unexpected 'e' expecting whitespace or }` at the `exports` line.

- `cabal test` runs tests from the package directory (e.g., `seihou-core/`), not the workspace
  root. Fixture paths must be relative to the package directory: `test/fixtures/...` not
  `seihou-core/test/fixtures/...`.


## Decision Log

- Decision: Start with a Dhall spike milestone before building the full decoder.
  Rationale: The `dhall` package is a large dependency with complex type machinery. Dhall
  1.42.3 claims GHC 9.12 support, but this has not been verified in our Nix environment.
  A spike that evaluates a trivial Dhall file and decodes it into a Haskell record will prove
  feasibility before committing to the full implementation. If the spike fails, we can
  investigate alternatives (such as using the dhall binary as a subprocess) without having
  wasted effort on decoders.
  Date: 2026-03-01

- Decision: Use manual Dhall decoders (the `record`/`field`/`union`/`constructor` combinator
  API from `Dhall.Marshal.Decode`) rather than Generic-derived `FromDhall` instances.
  Rationale: The Haskell types in `Seihou.Core.Types` use field names like `moduleName` and
  `varType`, while the Dhall schema uses names like `name` and `type`. The Generic-derived
  `FromDhall` instances require Dhall field names to exactly match Haskell field names (or
  require `DerivingVia` with `InterpretOptions`). Manual decoders give explicit control over
  the mapping between Dhall field names and Haskell record fields, are easier to debug, and
  avoid surprises from Generic machinery. They also let us handle the `Strategy` type, which
  is represented as a string in Dhall (`"copy"`, `"template"`, `"dhall-text"`, `"structured"`)
  but as an ADT constructor in Haskell.
  Date: 2026-03-01

- Decision: Represent the `Expr` type used in `when` clauses differently in Dhall and Haskell.
  Rationale: The Dhall schema stores expressions as `Optional Text` (e.g.,
  `Some "IsSet license && Eq license MIT"`). The Haskell `Expr` type is a proper AST
  (`EAnd`, `EOr`, `ENot`, `EVar`, `ELit`, `EEq`, `ENeq`). An expression parser bridges
  these representations. This keeps the Dhall schema simple (authors write human-readable
  strings) while giving the engine a type-safe AST to evaluate. Note that the existing
  `Expr` type in `Types.hs` has a different structure (`EVar VarName`, `EEq Expr Expr`) from
  the design doc (`Eq VarName VarValue`, `IsSet VarName`). We will align the Haskell `Expr`
  type with the design doc during implementation.
  Date: 2026-03-01

- Decision: Defer dependency resolution (loading transitive dependencies) to a later milestone
  or to M4 (Composition).
  Rationale: M1's focus is loading and validating a single module from Dhall. The module
  validation rule about dependencies ("all dependencies reference modules that can be resolved")
  is listed as a run-time check in the design doc, not a validate-time check. Loading
  transitive dependencies requires the full discovery system to work recursively and introduces
  cycle detection complexity. We will validate that dependency names are well-formed but defer
  recursive loading and cycle detection to M4 where composition is the focus.
  Date: 2026-03-01


## Outcomes & Retrospective

All five milestones completed. 78 tests pass, `nix flake check` succeeds.

Key outcomes:
- Dhall 1.42.3 works with GHC 9.12.2 without issues.
- Manual Dhall decoders proved more maintainable than Generic-derived ones.
- String-based VarType in Dhall was the right call; recursive types would have been a blocker.
- The expression parser was straightforward as a hand-written recursive descent parser.
- Module validation collects all errors, not just the first, which produces better UX.
- The pure DhallEval interpreter enables unit testing without disk access.

Gaps:
- Dependency resolution (loading transitive deps, cycle detection) deferred to M4 as planned.
- Rule 9 (expression variable references) not fully checked — variables in expressions are
  not validated against moduleVars yet. This is a minor gap since malformed expressions
  already fail at parse time.
- The `doesDirectoryExist` import in Module.hs is unused (discovery uses `doesFileExist`
  on the module.dhall path directly). This is harmless.


## Context and Orientation

Seihou is a composable, type-safe project scaffolding system written in Haskell. It uses
Dhall (a type-safe configuration language with deterministic evaluation) to define module
definitions that declare variables, prompts, generation steps, and dependencies.

The project is structured as a Cabal multi-package workspace with two packages. The file
`cabal.project` at the repository root declares both:

    packages:
      seihou-core
      seihou-cli

The library package `seihou-core` (cabal file at `seihou-core/seihou-core.cabal`) contains
the core domain types and effect interfaces. It currently uses GHC2024 as the default
language, with `OverloadedStrings` and `TypeFamilies` as additional default extensions.
TypeFamilies is required because effectful (the effect system library) uses
`type instance DispatchOf` declarations. The current library dependencies are `base`,
`containers`, `effectful-core`, and `text`.

The executable package `seihou-cli` (cabal file at `seihou-cli/seihou-cli.cabal`) provides
the `seihou` command-line tool. It currently has a working optparse-applicative parser with
seven subcommands (init, run, vars, install, status, new-module, validate-module), all
dispatching to stub handlers that print "not yet implemented."

The core domain types live in `seihou-core/src/Seihou/Core/Types.hs` and define 14 types.
The ones most relevant to this plan are:

`Module` is a record with seven fields: `moduleName :: ModuleName`, `moduleDescription ::
Maybe Text`, `moduleVars :: [VarDecl]`, `moduleExports :: [VarExport]`, `modulePrompts ::
[Prompt]`, `moduleSteps :: [Step]`, and `moduleDependencies :: [ModuleName]`. This is the
target type that Dhall module definitions will be decoded into.

`VarType` is a sum type with five constructors: `VTText`, `VTBool`, `VTInt`, `VTList VarType`
(recursive), and `VTChoice [Text]`. This represents the type of a variable declaration.

`VarValue` is a sum type with four constructors: `VText Text`, `VBool Bool`, `VInt Int`, and
`VList [VarValue]`. This represents a concrete variable value.

`Strategy` is a sum type with four constructors: `Copy`, `Template`, `DhallText`, and
`Structured`. In Dhall, strategies are represented as strings (`"copy"`, `"template"`,
`"dhall-text"`, `"structured"`).

`Expr` is a sum type for conditional logic. It currently has seven constructors: `EVar
VarName`, `ELit VarValue`, `ENot Expr`, `EAnd Expr Expr`, `EOr Expr Expr`, `EEq Expr Expr`,
`ENeq Expr Expr`. The design doc specifies a slightly different shape with `Eq VarName
VarValue`, `IsSet VarName`, and `Literal Bool` constructors. We will update the Haskell type
to match the design doc.

Seven effect interfaces are defined in `seihou-core/src/Seihou/Effect/`. The one directly
relevant is `DhallEval` in `seihou-core/src/Seihou/Effect/DhallEval.hs`, which currently has
a single operation: `EvalModuleFile :: FilePath -> DhallEval m Module`. This effect will get
a real implementation (an effectful interpreter that calls the Dhall library) in this plan.

The test infrastructure uses tasty as the test runner and hspec (via tasty-hspec) for BDD-style
assertions. Tests live in `seihou-core/test/` with the runner at `seihou-core/test/Main.hs`
and existing tests at `seihou-core/test/Seihou/Core/TypesSpec.hs` (21 passing tests).

The Dhall schema for module definitions is specified in the design doc at
`docs/dev/design/proposed/module-system.md`. It uses Dhall union types for `VarType` and
record types for `VarDecl`, `VarExport`, `Prompt`, `Step`, and `Module`. Expressions in
`when` clauses are stored as `Optional Text` strings that the Haskell engine parses.

The development environment is managed by a Nix flake at `flake.nix`. It provides GHC 9.12.2,
cabal-install, HLS, and system libraries (zlib, xz). Formatting uses `nix fmt` (which invokes
treefmt-nix with fourmolu for Haskell, cabal-gild for .cabal files, and nixpkgs-fmt for Nix).

The `dhall` Haskell package (version 1.42.3) provides the Dhall evaluation engine. The key
entry point is `Dhall.inputFile :: Decoder a -> FilePath -> IO a`, which reads a Dhall file,
type-checks it, evaluates it, and decodes it into a Haskell value using the provided `Decoder`.
The `Dhall.Marshal.Decode` module provides combinators for building decoders: `record` and
`field` for record types, `union` and `constructor` for union types. The `detailed` function
wraps an IO action to produce enhanced error messages.


## Plan of Work

The work is divided into five milestones. Each milestone builds on the previous one and is
independently verifiable.


### Milestone 1: Dhall Spike

The goal of this milestone is to prove that the `dhall` package compiles and works correctly
with GHC 9.12.2 in our Nix environment. At the end, a test will evaluate a minimal Dhall
expression from a string, decode it into a Haskell record, and assert that the decoded values
are correct.

Add `dhall >= 1.42 && < 2` to the `build-depends` of the library section in
`seihou-core/seihou-core.cabal`. The `dhall` package brings in a significant dependency tree
including `prettyprinter`, `megaparsec`, `http-client`, and others. Run `cabal build all` to
verify it compiles. If it fails due to missing system libraries, add them to the
`nativeBuildInputs` in `flake.nix`.

Create a new module `seihou-core/src/Seihou/Dhall/Eval.hs` with a function
`evalDhallExpr :: Text -> IO (Map Text Text)` that calls `Dhall.input` with a decoder for a
simple record type `{ name : Text, version : Text }`. This is a throwaway test function; its
purpose is to exercise the Dhall machinery.

Create a test file `seihou-core/test/Seihou/Dhall/EvalSpec.hs` that calls `evalDhallExpr`
with an inline Dhall expression and asserts the decoded values. Add this test module to the
test suite in `seihou-core/test/Main.hs` and to `other-modules` in `seihou-core.cabal`.

Acceptance: `cabal build all` succeeds with the `dhall` dependency. The spike test passes,
proving Dhall evaluation and decoding works. Run `cabal test all` and observe the spike test
in the output.


### Milestone 2: Dhall Schema and Decoders

The goal of this milestone is to create the canonical Dhall schema for module definitions and
implement decoders that transform Dhall values into the existing Haskell types from
`Seihou.Core.Types`. At the end, a test fixture module written in Dhall can be decoded into
a `Module` value.

Create the directory `schema/` at the repository root. Create the file `schema/Module.dhall`
containing the Dhall type definitions for `VarType`, `VarDecl`, `VarExport`, `Prompt`, `Step`,
and `Module` as specified in the design doc at `docs/dev/design/proposed/module-system.md`.
The `VarType` is a Dhall union `< Text | Bool | Int | List : VarType | Choice : List Text >`.
The `VarDecl` is a record with fields `name : Text`, `type : VarType`,
`default : Optional Text`, `description : Optional Text`, `required : Bool`, and
`validation : Optional Text`. The `Step` record has `strategy : Text` (a string like `"copy"`
or `"template"`), `src : Text`, `dest : Text`, and `when : Optional Text`. The full `Module`
record has `name : Text`, `description : Optional Text`, `vars : List VarDecl`,
`exports : List VarExport`, `prompts : List Prompt`, `steps : List Step`, and
`dependencies : List Text`.

Replace the spike function in `seihou-core/src/Seihou/Dhall/Eval.hs` with proper decoders.
Define a `moduleDecoder :: Dhall.Decoder Module` that uses the `record`/`field` combinators
from `Dhall.Marshal.Decode`. Each nested type needs its own decoder:

For `VarType`, the Dhall representation is a union. Write a `varTypeDecoder` that uses the
`union`/`constructor` combinators. The `Text` constructor maps to `VTText`, `Bool` to
`VTBool`, `Int` to `VTInt`, `List` carries a recursive `VarType` payload (map to
`VTList`), and `Choice` carries a `List Text` payload (map to `VTChoice`).

For `Strategy`, the Dhall representation is a plain `Text` string. Write a `strategyDecoder`
that reads a `Text` value and pattern-matches: `"copy"` becomes `Copy`, `"template"` becomes
`Template`, `"dhall-text"` becomes `DhallText`, `"structured"` becomes `Structured`, and
anything else is an error.

For `VarDecl`, write a `varDeclDecoder` that decodes `name` as `VarName`, `type` using
`varTypeDecoder`, `default` as `Maybe VarValue` (the Dhall schema uses `Optional Text` for
the default value — this means defaults are always text in Dhall and need to be parsed/coerced
to the declared type by the variable resolution layer in M2, so for now we store them as
`Just (VText t)` or `Nothing`), `description` as `Maybe Text`, `required` as `Bool`, and
`validation` as `Maybe Validation` (the Dhall schema uses `Optional Text` for validation; for
now parse it as `ValPattern` when present, since that is the most common case; a richer
parsing can come later).

For `Step`, write a `stepDecoder` that decodes `strategy` using `strategyDecoder`, `src` as
`FilePath`, `dest` as `Text`, and `when` as `Maybe Text`. The `when` field is an expression
string that will be parsed into an `Expr` value by the expression parser in Milestone 3. For
now, store `Nothing` for the `stepWhen` field regardless of the Dhall value, and add a TODO
comment.

For the top-level `Module`, write `moduleDecoder` that decodes `name` as `ModuleName`,
`description` as `Maybe Text`, `vars` using `list varDeclDecoder`, `exports` using
`list varExportDecoder`, `prompts` using `list promptDecoder`, `steps` using
`list stepDecoder`, and `dependencies` as `[ModuleName]`.

Export a function `evalModuleFromFile :: FilePath -> IO (Either ModuleLoadError Module)` that
calls `Dhall.inputFile moduleDecoder` wrapped in exception handling. Catch Dhall exceptions
and translate them into `ModuleLoadError` values. Add the `ModuleLoadError` type to
`seihou-core/src/Seihou/Core/Types.hs` with the constructors specified in the design doc:
`ModuleNotFound`, `DhallEvalError`, `DhallDecodeError`, `ValidationError`,
`CircularDependency`, and `MissingSourceFile`.

Create a test fixture directory `seihou-core/test/fixtures/haskell-base/` containing a
`module.dhall` file that defines a simple haskell-base module with two variables
(`project.name` and `project.version`), one prompt, and two steps. Write tests in
`seihou-core/test/Seihou/Dhall/EvalSpec.hs` that load this fixture using `evalModuleFromFile`
and assert that the decoded `Module` has the expected field values.

Acceptance: The `haskell-base` fixture module loads from disk and decodes into a `Module`
value with correct field values. The spike test from Milestone 1 can be replaced or kept
alongside. Run `cabal test all` and observe the decoder tests passing.


### Milestone 3: Expression Language

The goal of this milestone is to implement the expression parser and evaluator. At the end,
expression strings like `"IsSet license && Eq license MIT"` can be parsed into `Expr` values
and evaluated against a set of resolved variables.

First, update the `Expr` type in `seihou-core/src/Seihou/Core/Types.hs` to match the design
doc. The current type has constructors `EVar`, `ELit`, `ENot`, `EAnd`, `EOr`, `EEq`, `ENeq`.
The design doc specifies `Eq VarName VarValue`, `And Expr Expr`, `Or Expr Expr`,
`Not Expr`, `IsSet VarName`, and `Literal Bool`. Change the constructors to: `ExprEq VarName
VarValue` (variable equals a specific value), `ExprAnd Expr Expr`, `ExprOr Expr Expr`,
`ExprNot Expr`, `ExprIsSet VarName` (variable has been set), and `ExprLit Bool` (constant
true/false). Use the `Expr` prefix to avoid name clashes with Prelude functions. Update the
existing tests in `TypesSpec.hs` that reference the old constructors.

Create a new module `seihou-core/src/Seihou/Core/Expr.hs` with two functions:

`parseExpr :: Text -> Either Text Expr` parses an expression string according to the grammar
specified in the design doc. The grammar has three precedence levels: `||` (lowest), `&&`
(middle), and `!` prefix (highest). Atoms are `IsSet varname`, `Eq varname value`,
parenthesized expressions, `true`, and `false`. Variable names match
`[a-zA-Z][a-zA-Z0-9._-]*`. Values are either double-quoted strings or bare words (sequences
of non-whitespace, non-parenthesis characters). Implement this as a hand-written recursive
descent parser using `Data.Text` operations; no parser combinator library is needed for this
simple grammar.

`evalExpr :: Map VarName VarValue -> Expr -> Bool` evaluates an expression against a map of
variable bindings. `ExprEq name val` returns `True` if the variable is bound to the given
value. `ExprAnd l r` returns `True` if both sides are `True`. `ExprOr l r` returns `True` if
either side is `True`. `ExprNot e` inverts the result. `ExprIsSet name` returns `True` if the
variable is present in the map (regardless of its value). `ExprLit b` returns `b`.

Now go back to the step decoder in `Seihou.Dhall.Eval` and wire up the expression parser.
When the `when` field of a Step or Prompt is `Some expressionText`, call `parseExpr` on it.
If parsing fails, propagate the error. If parsing succeeds, store the resulting `Expr` in
`stepWhen` or `promptWhen`.

Write tests in `seihou-core/test/Seihou/Core/ExprSpec.hs` covering: parsing simple atoms
(`true`, `false`, `IsSet x`, `Eq x "hello"`), parsing compound expressions with `&&` and
`||`, parsing negation with `!`, parsing parenthesized grouping, operator precedence
(`a && b || c` parses as `(a && b) || c`), evaluation of each constructor, and error cases
(empty string, malformed syntax). Add this test module to the test runner.

Acceptance: All expression parser tests pass. The Dhall decoder now correctly parses `when`
expressions from module definitions. Run `cabal test all` and observe the expression tests
passing alongside the decoder tests.


### Milestone 4: Module Discovery and Validation

The goal of this milestone is to implement module discovery (finding modules on disk by name)
and module validation (checking that a loaded module satisfies the nine rules from the design
doc). At the end, calling `loadModule "haskell-base"` will search the module paths, evaluate
the Dhall file, decode it, validate it, and return either a validated `Module` or a descriptive
error.

Create a new module `seihou-core/src/Seihou/Core/Module.hs` with the following functions:

`discoverModule :: [FilePath] -> ModuleName -> IO (Either ModuleLoadError FilePath)` takes a
list of search directories and a module name. It looks for a directory matching the module name
(using `unModuleName`) in each search directory, checks for a `module.dhall` file inside it,
and returns the first match. If no match is found, it returns `ModuleNotFound` with the module
name and the list of directories that were searched.

`defaultSearchPaths :: IO [FilePath]` returns the three standard search paths:
`.seihou/modules/` relative to the current directory, `~/.config/seihou/modules/`, and
`~/.config/seihou/installed/`. It uses `System.Directory.getCurrentDirectory` for the first
and `System.Directory.getXdgDirectory XdgConfig "seihou"` for the latter two.

`validateModule :: FilePath -> Module -> Either ModuleLoadError Module` takes the module's
base directory (the directory containing `module.dhall`) and the decoded `Module` value, then
checks all nine validation rules. In order:

Rule 1 (name format): `moduleName` must be non-empty and match the pattern `[a-z][a-z0-9-]*`.
Rule 2 (unique variables): all entries in `moduleVars` must have distinct `varName` values.
Rule 3 (prompt references): every `promptVar` in `modulePrompts` must appear in `moduleVars`.
Rule 4 (file existence): every `stepSrc` in `moduleSteps` must correspond to a file in the
module's `files/` subdirectory. This check uses the `FilePath` argument to resolve paths.
Rule 5 (export references): every `exportVar` in `moduleExports` must appear in `moduleVars`.
Rule 6 (dependency names): every entry in `moduleDependencies` must be a well-formed module
name (same pattern as rule 1). Actual resolution of dependencies is deferred to M4.
Rule 7 (safe destinations): every `stepDest` must be a relative path with no `..` components
and must not start with `/`.
Rule 8 (destination variable references): variables referenced in `stepDest` placeholders
(anything inside `{{ }}`) must be declared in `moduleVars`.
Rule 9 (expression well-formedness): all `when` expressions must have parsed successfully
(they are already parsed during decoding in Milestone 3, so this is implicitly satisfied;
but we also check that any variable references inside expressions refer to declared variables).

Collect all validation errors and return them together as a `ValidationError` rather than
failing on the first error.

`loadModule :: [FilePath] -> ModuleName -> IO (Either ModuleLoadError Module)` is the
top-level function that combines discovery, evaluation, decoding, and validation. It calls
`discoverModule` to find the module directory, `evalModuleFromFile` to evaluate and decode
the Dhall file, and `validateModule` to check the result.

Now implement the real `DhallEval` effect interpreter. Create a new module
`seihou-core/src/Seihou/Effect/DhallEvalInterp.hs` (or name it
`Seihou.Dhall.Interpreter`) with a function
`runDhallEval :: IOE :> es => Eff (DhallEval : es) a -> Eff es a` that interprets the
`EvalModuleFile` operation by calling `evalModuleFromFile` from `Seihou.Dhall.Eval`. Also
create a test interpreter `runDhallEvalPure :: Map FilePath Module -> Eff (DhallEval : es) a
-> Eff es a` that looks up modules from an in-memory map for unit testing.

Add all new modules to `exposed-modules` in `seihou-core/seihou-core.cabal`. Add
`directory` to `build-depends` (for `System.Directory` functions used in discovery).

Write tests in `seihou-core/test/Seihou/Core/ModuleSpec.hs` covering: successful discovery
when a module exists in the search path, `ModuleNotFound` when it does not, validation of
a well-formed module (all rules pass), validation failure for each rule (bad name, duplicate
vars, prompt referencing undeclared var, missing source file, export referencing undeclared var,
unsafe destination path, bad dependency name). Add this test module to the test runner.

Acceptance: Module discovery finds modules in the correct priority order. Validation catches
all nine rule violations with descriptive error messages. The real `DhallEval` interpreter
works with the test fixture module. Run `cabal test all` and observe all tests passing.


### Milestone 5: Integration Testing

The goal of this milestone is to create a realistic `haskell-base` test fixture module (based
on the product spec example at `docs/product-specs/example-usage-haskell-template.md`) and
write end-to-end tests that exercise the full loading pipeline. At the end, every M1 exit
criterion is satisfied.

Expand the test fixture at `seihou-core/test/fixtures/haskell-base/` to include:

The `module.dhall` file with three variables (`project.name` with no default and required true,
`project.version` with default `"0.1.0.0"`, and `license` with default `"MIT"`), one prompt
for `project.name`, and four steps (README.md.tpl as template, cabal.project.gen as
structured, package.cabal.gen as structured, src/Lib.hs.tpl as template). Include a `when`
expression on one step (e.g., `Some "IsSet license"`) to test expression integration.

Create the `files/` subdirectory with the template and generator source files referenced by
the steps: `files/README.md.tpl`, `files/cabal.project.gen`, `files/package.cabal.gen`,
`files/src/Lib.hs.tpl`. These can contain placeholder content since generation is not
implemented until M2.

Also create an `invalid-module/` test fixture with deliberately broken definitions (missing
name, duplicate variable names, prompt referencing undeclared variable, step referencing
nonexistent file) for negative testing.

Write integration tests in `seihou-core/test/Seihou/Integration/ModuleLoadSpec.hs` that:

Load the `haskell-base` fixture using `loadModule` and assert the decoded `Module` has three
variables, one prompt, four steps, and the correct name. Verify that the `when` expression on
the conditional step parsed correctly into the expected `Expr` value. Verify that variables
have the expected types and defaults.

Load the `invalid-module` fixture and assert it produces the expected `ValidationError` with
all violations listed.

Test that loading a nonexistent module name produces `ModuleNotFound` with the searched paths.

Test the pure `DhallEval` interpreter by running an effect program against the in-memory map
and verifying the result.

Run `nix fmt` to ensure all new code is formatted. Run `cabal test all` to verify all tests
pass. Run `nix flake check` to verify the full CI check passes.

Acceptance: The `haskell-base` fixture loads successfully and decodes into a `Module` value
matching the product spec example. Invalid modules produce clear errors listing all violations.
Expression parsing handles the grammar correctly. All tests pass, formatting is clean,
`nix flake check` succeeds.


## Concrete Steps

All commands assume the working directory is the repository root:
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`.

Build the project at any point with:

    cabal build all

Run the full test suite with:

    cabal test all

Format all code with:

    nix fmt

Run the full Nix check (formatting + build) with:

    nix flake check

After adding the `dhall` dependency, the first `cabal build all` will download and compile
the `dhall` package and its transitive dependencies. This may take several minutes on the
first build. Expected output includes lines like:

    Resolving dependencies...
    Build profile: -w ghc-9.12.2 ...
    Building library for seihou-core-0.1.0.0...

After all milestones are complete, `cabal test all` should show output like:

    Test suite seihou-core-test: RUNNING...
    seihou-core
      Seihou.Core.Types
        ...                                   PASS (21 existing tests)
      Seihou.Dhall.Eval
        decodes a minimal module              PASS
        decodes VarType union                 PASS
        decodes Strategy from string          PASS
        ...
      Seihou.Core.Expr
        parses true literal                   PASS
        parses IsSet atom                     PASS
        parses Eq atom                        PASS
        parses compound && expression         PASS
        ...
      Seihou.Core.Module
        discovers module in search path       PASS
        returns ModuleNotFound                PASS
        validates well-formed module          PASS
        rejects bad module name               PASS
        ...
      Seihou.Integration.ModuleLoad
        loads haskell-base fixture            PASS
        rejects invalid module                PASS
        ...


## Validation and Acceptance

The M1 milestone is complete when all of the following are true:

The `haskell-base` test fixture module (matching the product spec example) loads from disk
through the full pipeline: Dhall evaluation, decoding into `Module`, expression parsing, and
validation. A test asserts the decoded module has `moduleName == "haskell-base"`, three
variables, one prompt, four steps, and zero dependencies.

Invalid modules produce `ModuleLoadError` values with all violations listed (not just the
first). A test provides a module with multiple violations and asserts all are reported.

The expression parser handles the full grammar: `true`, `false`, `IsSet varname`,
`Eq varname "value"`, `&&`, `||`, `!`, parentheses, and correct operator precedence. A test
parses `"IsSet license && Eq license \"MIT\""` and evaluates it against both a matching and
non-matching variable map.

Module discovery searches directories in the correct order (local, user, installed) and
returns the first match. A test creates a temporary directory structure with modules in
multiple search paths and verifies priority.

The real `DhallEval` interpreter (using the `dhall` library) works when wired into the
effectful effect stack. The pure test interpreter allows unit testing without disk access.

All existing tests continue to pass (the 21 tests from M0). No regressions.

`cabal build all`, `cabal test all`, and `nix flake check` all succeed.


## Idempotence and Recovery

Every step in this plan is additive. New files are created; existing files are modified only
to add exports, extend types, or add dependencies. No files are deleted.

If the `dhall` dependency fails to compile in Milestone 1, the spike is isolated and can be
removed without affecting the rest of the codebase. The only change to existing files would
be the addition of `dhall` to `build-depends` in `seihou-core.cabal`, which can be reverted.

If Dhall decoding fails for a particular type, the decoders can be debugged individually.
Each decoder is a standalone value of type `Decoder a` that can be tested in isolation using
`Dhall.input decoder "{ ... }"` in GHCi.

The expression parser uses no mutable state and can be re-run on the same input any number
of times. Tests provide the expected parse tree so regressions are caught immediately.

Module validation collects all errors rather than failing on the first one, so adding a new
validation rule does not require re-running the entire validation pipeline.


## Interfaces and Dependencies

### New Haskell Package Dependencies

`dhall >= 1.42 && < 2` — The Dhall evaluation engine. Provides `Dhall.inputFile`,
`Dhall.Marshal.Decode` (decoders), and `Dhall.Core` (AST). Version 1.42.3 is available in
nixpkgs-unstable for GHC 9.12.2.

`directory >= 1.3 && < 2` — Provides `System.Directory` functions for module discovery:
`doesDirectoryExist`, `doesFileExist`, `getCurrentDirectory`, `getXdgDirectory`.

### New Modules to Create

In `seihou-core/src/Seihou/Dhall/Eval.hs`:

    evalModuleFromFile :: FilePath -> IO (Either ModuleLoadError Module)
    moduleDecoder :: Dhall.Decoder Module
    varTypeDecoder :: Dhall.Decoder VarType
    varDeclDecoder :: Dhall.Decoder VarDecl
    varExportDecoder :: Dhall.Decoder VarExport
    promptDecoder :: Dhall.Decoder Prompt
    stepDecoder :: Dhall.Decoder Step
    strategyDecoder :: Dhall.Decoder Strategy

In `seihou-core/src/Seihou/Core/Expr.hs`:

    parseExpr :: Text -> Either Text Expr
    evalExpr :: Map VarName VarValue -> Expr -> Bool

In `seihou-core/src/Seihou/Core/Module.hs`:

    discoverModule :: [FilePath] -> ModuleName -> IO (Either ModuleLoadError FilePath)
    defaultSearchPaths :: IO [FilePath]
    validateModule :: FilePath -> Module -> Either ModuleLoadError Module
    loadModule :: [FilePath] -> ModuleName -> IO (Either ModuleLoadError Module)

In `seihou-core/src/Seihou/Effect/DhallEvalInterp.hs`:

    runDhallEval :: IOE :> es => Eff (DhallEval : es) a -> Eff es a
    runDhallEvalPure :: Map FilePath Module -> Eff (DhallEval : es) a -> Eff es a

### Types to Add or Modify

In `seihou-core/src/Seihou/Core/Types.hs`:

Add the `ModuleLoadError` type:

    data ModuleLoadError
      = ModuleNotFound ModuleName [FilePath]
      | DhallEvalError ModuleName Text
      | DhallDecodeError ModuleName Text
      | ValidationError ModuleName [Text]
      | CircularDependency [ModuleName]
      | MissingSourceFile ModuleName FilePath
      deriving stock (Eq, Show, Generic)

Update the `Expr` type to match the design doc:

    data Expr
      = ExprEq VarName VarValue
      | ExprAnd Expr Expr
      | ExprOr Expr Expr
      | ExprNot Expr
      | ExprIsSet VarName
      | ExprLit Bool
      deriving stock (Eq, Show, Generic)

### New Test Modules

    seihou-core/test/Seihou/Dhall/EvalSpec.hs
    seihou-core/test/Seihou/Core/ExprSpec.hs
    seihou-core/test/Seihou/Core/ModuleSpec.hs
    seihou-core/test/Seihou/Integration/ModuleLoadSpec.hs

### Test Fixture Files

    seihou-core/test/fixtures/haskell-base/module.dhall
    seihou-core/test/fixtures/haskell-base/files/README.md.tpl
    seihou-core/test/fixtures/haskell-base/files/cabal.project.gen
    seihou-core/test/fixtures/haskell-base/files/package.cabal.gen
    seihou-core/test/fixtures/haskell-base/files/src/Lib.hs.tpl
    seihou-core/test/fixtures/invalid-module/module.dhall

### Dhall Schema Files

    schema/Module.dhall
