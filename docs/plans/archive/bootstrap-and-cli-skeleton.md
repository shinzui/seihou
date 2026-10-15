---
slug: bootstrap-and-cli-skeleton
title: "Bootstrap Project and Initial CLI Skeleton"
kind: exec-plan
created_at: 2026-03-02T01:19:11Z
---


# Bootstrap Project and Initial CLI Skeleton

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

After this work is complete, a developer can enter the Nix devshell, build both the
`seihou-core` library and the `seihou` executable, run the test suite, and invoke
`seihou --help` to see the full command menu. Each subcommand (init, run, vars, install,
status, new-module, validate-module) will parse its flags correctly and print a stub message
acknowledging the command was understood. All core domain types (Module, Variable, Step,
Strategy, Expression, Operation) will compile with Eq, Show, and Generic instances. Seven
effect interfaces (Filesystem, Console, DhallEval, ConfigReader, ManifestStore, Process,
Logger) will be defined as effectful GADTs with smart constructors, ready for real
implementations in later milestones.

This corresponds to M0 (Project Bootstrap) from `docs/dev/roadmap/v1-milestones.md` plus
the CLI scaffolding from M3 that can be built without the generation engine.


## Progress

- [x] Milestone 1: Create cabal.project and both package .cabal files with minimal source so `cabal build all` succeeds. (2026-03-01)
- [x] Milestone 2: Define all core domain types in Seihou.Core.Types and all effect interfaces in Seihou.Effect.*, update .cabal file, verify build. (2026-03-01)
- [x] Milestone 3: Create CLI command parser (Seihou.CLI.Commands) and wire stub dispatch into Main.hs, verify `seihou --help` works. (2026-03-01)
- [x] Milestone 4: Set up tasty + hspec test infrastructure, write initial tests, update Justfile, verify `cabal test all` and `nix flake check` pass. (2026-03-01)


## Surprises & Discoveries

- GHC2024 does NOT include TypeFamilies. The `type instance DispatchOf` declarations
  required by effectful failed to compile until `TypeFamilies` was added to
  `default-extensions` in `seihou-core.cabal`. The plan assumed GHC2024 includes it but
  GHC 9.12.2's GHC2024 set does not.
  Evidence: `GHC-06206: Illegal family instance for 'DispatchOf'`

- The standalone `treefmt` binary requires a `treefmt.toml` config file in the project root,
  but this project uses `treefmt-nix` which generates the config as part of the Nix flake.
  The correct way to format files is `nix fmt`, not `treefmt`. Updated the Justfile
  accordingly.
  Evidence: `Error: failed to find treefmt config file: could not find [treefmt.toml .treefmt.toml]`


## Decision Log

- Decision: Combine M0 (bootstrap) with the CLI parser skeleton from M3 into a single plan.
  Rationale: The CLI parser and command ADT have no dependency on the generation engine
  (M1/M2). Building them now provides an executable entry point that exercises the core
  types and gives immediate feedback to the developer.
  Date: 2026-03-01

- Decision: Use manual smart constructors for effectful effects instead of Template Haskell (makeEffect).
  Rationale: Avoids a TH dependency, makes the effect interfaces explicit and readable,
  and sidesteps potential TH compatibility issues with GHC 9.12.2.
  Date: 2026-03-01

- Decision: Use wide dependency bounds without strict upper pinning.
  Rationale: This is an unpublished application, not a Hackage library. Cabal's solver
  will choose compatible versions. Tight bounds would create unnecessary maintenance
  burden. Lower bounds are included only where the API changed significantly.
  Date: 2026-03-01

- Decision: Use tasty with tasty-hspec as the testing framework.
  Rationale: Matches the technology choice in `docs/dev/architecture/overview.md`. Tasty
  provides the test runner and reporting; hspec provides the BDD-style test DSL.
  Date: 2026-03-01

- Decision: Define a placeholder Manifest type in Types.hs so the ManifestStore effect compiles.
  Rationale: The full Manifest type belongs to M5 (Incrementality), but the effect
  interface needs a concrete type to reference. A minimal placeholder lets the interface
  compile now and can be extended later.
  Date: 2026-03-01


## Outcomes & Retrospective

All four milestones completed successfully on 2026-03-01.

What was achieved: The Seihou project now has a fully functional Cabal multi-package
workspace with `seihou-core` (library, 8 modules) and `seihou-cli` (executable). All 14
core domain types compile with Eq, Show, and Generic instances. Seven effectful effect
interfaces are defined with GADT operations and smart constructors. The CLI parses all
seven subcommands with full flag support and dispatches to stub handlers. A test suite
with 21 tests covers all domain types. Formatting via `nix fmt` passes, and `nix flake
check` succeeds.

What remains: The stub handlers need real implementations (M1-M6 milestones from the
roadmap). The Manifest type is a placeholder. No Dhall schema files exist yet. No CI
beyond `nix flake check` is set up.

Lessons learned: GHC2024 does not include TypeFamilies, which is required for effectful's
`type instance DispatchOf` pattern. The `nix fmt` command must be used instead of standalone
`treefmt` when formatting is configured via `treefmt-nix`.


## Context and Orientation

The Seihou project lives at the repository root. It currently contains a Nix flake
(`flake.nix`) that provides a development shell with GHC 9.12.2, cabal-install,
haskell-language-server, and formatting tools. The flake also configures pre-commit hooks
that run `treefmt` (fourmolu for Haskell, nixpkgs-fmt for Nix, cabal-gild for .cabal
files). The fourmolu configuration (`fourmolu.yaml`) specifies 2-space indentation,
trailing commas, and trailing function arrows.

There are no Haskell source files, no .cabal files, and no `cabal.project` workspace file.
The entire `seihou-core/` and `seihou-cli/` directory trees described in
`docs/dev/architecture/overview.md` do not exist yet.

The design documents live under `docs/dev/`. The architecture overview at
`docs/dev/architecture/overview.md` defines the target project structure, the effectful
effect stack (`AppEffects`), and the seven-stage execution pipeline. The module system
design at `docs/dev/design/proposed/module-system.md` defines the core domain types
(Module, VarDecl, Step, Strategy, etc.) with exact Haskell type definitions. The CLI
design at `docs/dev/design/proposed/cli-commands.md` defines the Command ADT, all option
types, and the optparse-applicative parser tree. The roadmap at
`docs/dev/roadmap/v1-milestones.md` breaks implementation into milestones M0 through M6.

The `.gitignore` already excludes `dist-*` (cabal build artifacts), `.direnv`, `.envrc`,
`cabal.project.local`, and `.claude/`.

The `Justfile` currently contains only `just --list` as the default recipe.

Seihou uses the `effectful` library for its effect system. An effect in effectful is a GADT
(Generalized Algebraic Data Type — a Haskell feature that lets each constructor have a
different return type) indexed by the `Effect` kind. For example, a Filesystem effect
declares operations like `ReadFileText :: FilePath -> Filesystem m Text`. Each effect is
tagged with `type instance DispatchOf Filesystem = Dynamic`, telling effectful to use
dynamic dispatch (runtime interpretation). Smart constructors wrap each GADT constructor
with `send` so callers write `readFileText path` instead of `send (ReadFileText path)`.

The project uses GHC2024 as its default language, which enables many common extensions
including DerivingStrategies, GADTs, DataKinds, TypeFamilies, TypeOperators, and
GeneralisedNewtypeDeriving. OverloadedStrings is not part of GHC2024 and must be added
as a default extension in the .cabal files.


## Plan of Work

The work proceeds in four milestones. Each milestone leaves the repository in a buildable,
testable state.


### Milestone 1: Cabal Workspace and Minimal Compilation

This milestone creates the multi-package Cabal workspace with two packages: `seihou-core`
(library) and `seihou-cli` (executable). Each package gets a minimal source file so that
`cabal build all` succeeds. At the end of this milestone, the developer can enter the Nix
devshell and build both packages.

Create the workspace file at `cabal.project` in the repository root. It declares both
packages and disables GHC environment file generation (which clutters the repository):

    packages:
      seihou-core
      seihou-cli

    write-ghc-environment-files: never

Create the core library cabal file at `seihou-core/seihou-core.cabal`. The library exposes
a single module for now and uses GHC2024 with OverloadedStrings:

    cabal-version: 3.0
    name:          seihou-core
    version:       0.1.0.0
    synopsis:      Core library for Seihou project scaffolding
    build-type:    Simple

    library
      default-language:   GHC2024
      default-extensions: OverloadedStrings
      hs-source-dirs:     src
      exposed-modules:    Seihou.Core.Types
      build-depends:
        , base >= 4.18 && < 5
        , text >= 2.0  && < 3

Create the minimal types module at `seihou-core/src/Seihou/Core/Types.hs`:

    module Seihou.Core.Types () where

This is an empty module that will be fleshed out in Milestone 2.

Create the CLI cabal file at `seihou-cli/seihou-cli.cabal`:

    cabal-version: 3.0
    name:          seihou-cli
    version:       0.1.0.0
    synopsis:      CLI for Seihou project scaffolding
    build-type:    Simple

    executable seihou
      default-language:   GHC2024
      default-extensions: OverloadedStrings
      hs-source-dirs:     src
      main-is:            Main.hs
      build-depends:
        , base >= 4.18 && < 5
        , text >= 2.0  && < 3

Create the minimal entry point at `seihou-cli/src/Main.hs`:

    module Main (main) where

    main :: IO ()
    main = putStrLn "seihou: not yet implemented"

Verify by running `cabal update` (to ensure a fresh Hackage index) and `cabal build all`.
Both packages should compile. Running `cabal run seihou` should print the placeholder message.


### Milestone 2: Core Domain Types and Effect Interfaces

This milestone populates `Seihou.Core.Types` with every domain type specified in M0 and
creates the seven effect interface modules. At the end, `cabal build all` still succeeds
and all types have Eq, Show, and Generic instances.

Edit `seihou-core/src/Seihou/Core/Types.hs` to define the following types. The types come
directly from the design documents at `docs/dev/design/proposed/module-system.md` and
`docs/dev/architecture/overview.md`. The module imports `Data.Text (Text)`,
`GHC.Generics (Generic)`, and `Data.String (IsString)`.

`ModuleName` is a newtype over Text representing a module identifier. It derives Eq, Ord,
Show, and Generic via `deriving stock`, and IsString via `deriving newtype` so that string
literals work with OverloadedStrings.

`VarName` is a newtype over Text for variable identifiers, with the same deriving strategy
as ModuleName.

`VarType` is a sum type with constructors: `VTText`, `VTBool`, `VTInt`, `VTList VarType`
(recursive — a list of elements of a given type), and `VTChoice [Text]` (one of a fixed set
of text options).

`VarValue` represents concrete variable values: `VText Text`, `VBool Bool`, `VInt Int`,
`VList [VarValue]`.

`Validation` describes constraints on variable values: `ValPattern Text` (a regex the value
must match), `ValRange Int Int` (minimum and maximum for integers), `ValMinLength Int`, and
`ValMaxLength Int`.

`VarDecl` is a record declaring a variable with fields: `varName :: VarName`,
`varType :: VarType`, `varDefault :: Maybe VarValue`, `varDescription :: Maybe Text`,
`varRequired :: Bool`, `varValidation :: Maybe Validation`.

`VarExport` is a record for cross-module variable visibility with fields:
`exportVar :: VarName`, `exportAs :: Maybe VarName`.

`Expr` is the expression AST for conditional logic in `when` clauses. Constructors:
`EVar VarName` (variable reference), `ELit VarValue` (literal value), `ENot Expr`
(logical not), `EAnd Expr Expr`, `EOr Expr Expr`, `EEq Expr Expr`, `ENeq Expr Expr`.

`Prompt` is a record for interactive prompts with fields: `promptVar :: VarName`,
`promptText :: Text`, `promptWhen :: Maybe Expr` (condition for displaying; Nothing means
always), `promptChoices :: Maybe [Text]` (for choice variables).

`Strategy` is an enumeration of the four generation strategies: `Copy`, `Template`,
`DhallText`, `Structured`.

`Step` is a record representing one generation step: `stepStrategy :: Strategy`,
`stepSrc :: FilePath` (relative to the module's `files/` directory), `stepDest :: Text`
(destination path, may contain placeholders), `stepWhen :: Maybe Expr`.

`Module` is the top-level record with fields: `moduleName :: ModuleName`,
`moduleDescription :: Maybe Text`, `moduleVars :: [VarDecl]`,
`moduleExports :: [VarExport]`, `modulePrompts :: [Prompt]`, `moduleSteps :: [Step]`,
`moduleDependencies :: [ModuleName]`.

`Operation` represents filesystem operations produced by the generation engine:
`WriteFileOp` (with `opDest :: FilePath` and `opContent :: Text`),
`CreateDirOp` (with `opPath :: FilePath`),
`CopyFileOp` (with `opSrc :: FilePath` and `opDest :: FilePath`),
`RunCommandOp` (with `opCommand :: Text` and `opWorkDir :: Maybe FilePath`).

`Manifest` is a placeholder type for the ManifestStore effect. For now it is an empty
data declaration: `data Manifest = Manifest`. It will be expanded in M5 with file records,
hashes, and timestamps.

All record types use `deriving stock (Eq, Show, Generic)`. All newtypes that wrap Text
additionally use `deriving newtype (IsString)`.

Next, create the seven effect interface modules under `seihou-core/src/Seihou/Effect/`.
Each module defines one effectful effect as a GADT, declares its dispatch as Dynamic via
`type instance DispatchOf`, and provides smart constructor functions that wrap each GADT
constructor with `send`. Every module imports `Effectful` (for `Effect`, `Eff`, `(:>`)
and `DispatchOf`) and `Effectful.Dispatch.Dynamic` (for `send` and `Dynamic`).

The pattern for each module is:

    module Seihou.Effect.SomeEffect
      ( SomeEffect (..)
      , someOperation
      )
    where

    import Effectful
    import Effectful.Dispatch.Dynamic

    data SomeEffect :: Effect where
      SomeOperation :: ArgType -> SomeEffect m ReturnType

    type instance DispatchOf SomeEffect = Dynamic

    someOperation :: (SomeEffect :> es) => ArgType -> Eff es ReturnType
    someOperation arg = send (SomeOperation arg)

Create `seihou-core/src/Seihou/Effect/Filesystem.hs` with eight operations: `ReadFileText`
(takes a FilePath, returns Text), `WriteFileText` (takes FilePath and Text, returns unit),
`CopyFile` (takes source and destination FilePaths), `ListDirectory` (takes FilePath,
returns list of FilePaths), `CreateDirectoryIfMissing` (takes a Bool for whether to create
parents, and a FilePath), `DoesFileExist` (takes FilePath, returns Bool),
`DoesDirectoryExist` (takes FilePath, returns Bool), `GetCurrentDirectory` (returns
FilePath). The module imports `Data.Text (Text)`.

Create `seihou-core/src/Seihou/Effect/Console.hs` with five operations: `PutText` (takes
Text, prints to stdout), `PutError` (takes Text, prints to stderr), `GetLine` (returns
Text from stdin), `Confirm` (takes a prompt Text, returns Bool), `IsInteractive` (returns
Bool indicating whether stdin is a TTY). The smart constructor for `GetLine` must be named
`getLine_` to avoid clashing with `Prelude.getLine`, or the module can `import Prelude
hiding (getLine)` and name the smart constructor `getLine`. Use the hiding approach. The
module imports `Data.Text (Text)`.

Create `seihou-core/src/Seihou/Effect/DhallEval.hs` with one operation: `EvalModuleFile`
(takes a FilePath pointing to a `module.dhall` file, returns a `Module` value). The module
imports `Seihou.Core.Types (Module)`.

Create `seihou-core/src/Seihou/Effect/ConfigReader.hs` with three operations:
`ReadGlobalConfig` (returns `Map Text Text`), `ReadLocalConfig` (returns `Map Text Text`),
`ReadNamespaceConfig` (takes a namespace name as Text, returns `Map Text Text`). The module
imports `Data.Map.Strict (Map)` and `Data.Text (Text)`.

Create `seihou-core/src/Seihou/Effect/ManifestStore.hs` with two operations:
`ReadManifest` (returns `Maybe Manifest`), `WriteManifest` (takes a Manifest). The module
imports `Seihou.Core.Types (Manifest)`.

Create `seihou-core/src/Seihou/Effect/Process.hs` with one operation: `RunProcess` (takes
a command as Text, a list of arguments as `[Text]`, an optional working directory as
`Maybe FilePath`, and returns a triple `(ExitCode, Text, Text)` for exit code, stdout, and
stderr). The module imports `Data.Text (Text)` and `System.Exit (ExitCode)`.

Create `seihou-core/src/Seihou/Effect/Logger.hs` with four operations: `LogDebug`,
`LogInfo`, `LogWarn`, `LogError` — each takes a Text message and returns unit. The module
imports `Data.Text (Text)`.

Update `seihou-core/seihou-core.cabal` to list all new modules in `exposed-modules` and add
`effectful-core >= 2.4 && < 3` and `containers >= 0.6 && < 1` to `build-depends`.

Verify with `cabal build all`. All nine modules in seihou-core should compile.


### Milestone 3: CLI Command Parser and Stub Dispatch

This milestone builds the full optparse-applicative command parser from the design at
`docs/dev/design/proposed/cli-commands.md` and wires it into the executable with stub
handlers. At the end, `cabal run seihou -- --help` displays the command menu, each
subcommand's `--help` shows its flags, and running any command prints a stub message.

Create `seihou-cli/src/Seihou/CLI/Commands.hs`. This module defines the `Command` ADT and
all option types exactly as specified in the CLI design doc.

`Command` is a sum type with constructors: `Init`, `Run RunOpts`, `Vars VarsOpts`,
`Install InstallOpts`, `Status`, `NewModule NewModuleOpts`,
`ValidateModule ValidateOpts`. All derive Eq, Show, and Generic.

`RunOpts` is a record with fields: `runModule :: ModuleName` (positional argument),
`runAdditional :: [ModuleName]` (repeatable `--module`/`-m` flags),
`runVars :: [(Text, Text)]` (repeatable `--var KEY=VALUE` flags),
`runDryRun :: Bool`, `runDiff :: Bool`, `runForce :: Bool`, `runNoCommands :: Bool`
(all switches).

`VarsOpts` is a record with fields: `varsModule :: ModuleName`,
`varsExplain :: Bool` (`--explain` switch),
`varsVars :: [(Text, Text)]` (repeatable `--var` flags for resolution context).

`InstallOpts` is a record with fields: `installSource :: Text` (positional git URL),
`installName :: Maybe Text` (optional `--name` flag).

`NewModuleOpts` is a record with fields: `newModuleName :: Text` (positional),
`newModulePath :: Maybe FilePath` (optional `--path` flag).

`ValidateOpts` is a record with fields:
`validatePath :: Maybe FilePath` (optional positional path).

The module exports `commandParser :: Parser Command` and `opts :: ParserInfo Command`.
The parser uses `subparser` to define all seven commands. Each command entry uses
`command "name" (info parser (progDesc "description"))`.

The `run` parser builds `RunOpts` from a positional MODULE argument (parsed as
`ModuleName . T.pack <$> str` since optparse-applicative's `str` returns String and
ModuleName wraps Text), repeatable `--module`/`-m` options, repeatable `--var` options
(using a `varPair` reader), and four switches.

The `varPair` helper has type `ReadM (Text, Text)` and uses `eitherReader` to split the
input string on the first `=` character. It rejects empty keys and missing `=` signs.

The `opts` ParserInfo wraps `commandParser` with `helper`, a `--version` flag (using
`infoOption "seihou 0.1.0.0" (long "version" <> help "Show version")`), a program
description, and a header.

The module imports `Options.Applicative` for all parser combinators,
`Data.Text qualified as T` for text conversion, and `Seihou.Core.Types (ModuleName(..))`.

Edit `seihou-cli/src/Main.hs` to import `Options.Applicative (execParser)` and
`Seihou.CLI.Commands`. The `main` function calls `execParser opts` to parse the command
line, then pattern-matches on the resulting `Command` value to dispatch each command to a
stub handler that prints a message identifying which command was invoked along with its
key parsed arguments. For example, running `seihou run my-module --dry-run` should print:

    seihou run: not yet implemented (module: my-module, dry-run: True)

And `seihou init` should print:

    seihou init: not yet implemented

Update `seihou-cli/seihou-cli.cabal` to add `Seihou.CLI.Commands` to `other-modules`, and
add `seihou-core` and `optparse-applicative >= 0.18 && < 1` to `build-depends`.

Verify by running the following commands and checking the output:

    cabal run seihou -- --help

Expected: displays the command menu listing all seven subcommands.

    cabal run seihou -- --version

Expected: prints "seihou 0.1.0.0".

    cabal run seihou -- init

Expected: prints the init stub message.

    cabal run seihou -- run test-module --dry-run --var project.name=foo

Expected: prints a stub message showing the parsed module name, dry-run flag, and variable.

    cabal run seihou -- vars test-module --explain

Expected: prints a stub message showing the module name and explain flag.

    cabal run seihou -- status

Expected: prints the status stub message.


### Milestone 4: Test Infrastructure and Final Validation

This milestone adds the testing framework, writes initial tests for the core types, updates
the Justfile with useful recipes, and runs all final validation checks. At the end,
`cabal test all` passes and `nix flake check` succeeds.

Create `seihou-core/test/Main.hs` as the tasty test runner entry point. It calls
`defaultMain` from `Test.Tasty` with a test group containing all spec modules. Since
`tasty-hspec`'s `testSpec` function returns `IO TestTree`, the main function builds the
tree in IO before passing it to `defaultMain`:

    module Main (main) where

    import Test.Tasty
    import qualified Seihou.Core.TypesSpec as TypesSpec

    main :: IO ()
    main = do
      typesTests <- TypesSpec.tests
      defaultMain (testGroup "seihou-core" [typesTests])

Create `seihou-core/test/Seihou/Core/TypesSpec.hs` with hspec-style tests wrapped in a
tasty TestTree. The module exports `tests :: IO TestTree` which calls
`testSpec "Seihou.Core.Types" spec`. The `spec :: Spec` uses hspec's `describe` and `it`
blocks to verify:

The `ModuleName` newtype supports OverloadedStrings — creating a ModuleName from a string
literal and checking that `unModuleName` returns the original text. The `VarType` constructors
cover all five variants (construct each and verify they are distinct via inequality). A
complete `VarDecl` record can be constructed with all fields populated. The `Strategy` type
has four distinct constructors. The `Module` record can be constructed with all fields
populated (using empty lists for vars, exports, prompts, steps, and dependencies). Two
identical Module values compare equal via `==`. Calling `show` on a Module value produces a
non-empty string (verifying the Show instance works without error). The four `Operation`
constructors can each be created and compared for equality.

Add a test-suite section to `seihou-core/seihou-core.cabal`:

    test-suite seihou-core-test
      type:               exitcode-stdio-1.0
      default-language:   GHC2024
      default-extensions: OverloadedStrings
      hs-source-dirs:     test
      main-is:            Main.hs
      other-modules:      Seihou.Core.TypesSpec
      build-depends:
        , base       >= 4.18 && < 5
        , seihou-core
        , tasty      >= 1.4  && < 2
        , tasty-hspec >= 1.2 && < 2
        , hspec      >= 2.11 && < 3
        , text       >= 2.0  && < 3

Update the Justfile at the repository root to include useful development recipes:

    default:
      just --list

    build:
      cabal build all

    test:
      cabal test all

    clean:
      cabal clean

    format:
      treefmt

    check:
      nix flake check

Run `cabal test all` and verify all tests pass. Run `nix flake check` and verify the
formatting check passes — the pre-commit treefmt hook will check that all new `.hs` and
`.cabal` files are formatted according to fourmolu and cabal-gild. If formatting issues
are reported, run `treefmt` from the repository root to auto-fix them, then re-check.


## Concrete Steps

All commands below are run from the repository root, inside the Nix devshell.

Before starting, ensure the Hackage index is fresh:

    cabal update

Milestone 1 creates five files and verifies the build:

    mkdir -p seihou-core/src/Seihou/Core
    mkdir -p seihou-cli/src

Create `cabal.project`, `seihou-core/seihou-core.cabal`,
`seihou-core/src/Seihou/Core/Types.hs`, `seihou-cli/seihou-cli.cabal`, and
`seihou-cli/src/Main.hs` with the contents described in Milestone 1.

    cabal build all

Expected output ends with a successful build of both packages:

    Building library for seihou-core-0.1.0.0..
    [1 of 1] Compiling Seihou.Core.Types
    Building executable 'seihou' for seihou-cli-0.1.0.0..
    [1 of 1] Compiling Main

    cabal run seihou

Expected output:

    seihou: not yet implemented

Milestone 2 edits Types.hs, creates seven new modules, and updates the cabal file:

    mkdir -p seihou-core/src/Seihou/Effect

Edit `seihou-core/src/Seihou/Core/Types.hs` with the full domain types. Create the seven
effect modules under `seihou-core/src/Seihou/Effect/`. Update
`seihou-core/seihou-core.cabal` with new modules and dependencies.

    cabal build all

Expected: all nine modules in seihou-core compile with no errors.

Milestone 3 creates the command parser and updates the CLI:

    mkdir -p seihou-cli/src/Seihou/CLI

Create `seihou-cli/src/Seihou/CLI/Commands.hs`. Edit `seihou-cli/src/Main.hs` for command
dispatch. Update `seihou-cli/seihou-cli.cabal` with new module and dependencies.

    cabal build all
    cabal run seihou -- --help

Expected help output:

    seihou - composable project scaffolding

    Usage: seihou COMMAND

    Available commands:
      init                       Initialize Seihou configuration
      run                        Run modules to generate a project
      vars                       Inspect resolved variables
      install                    Install a module from git
      status                     Show manifest state
      new-module                 Scaffold a new module
      validate-module            Validate a module

    cabal run seihou -- run test-module --dry-run

Expected stub output:

    seihou run: not yet implemented (module: test-module, dry-run: True)

Milestone 4 adds tests, updates the Justfile, and runs final checks:

    mkdir -p seihou-core/test/Seihou/Core

Create `seihou-core/test/Main.hs` and `seihou-core/test/Seihou/Core/TypesSpec.hs`. Update
`seihou-core/seihou-core.cabal` with the test-suite section. Update `Justfile`.

    cabal test all

Expected: all tests pass:

    Test suite seihou-core-test: RUNNING...
    seihou-core
      Seihou.Core.Types
        ModuleName
          supports OverloadedStrings: OK
        ...
    All N tests passed.
    Test suite seihou-core-test: PASS

    nix flake check

Expected: all checks pass. If formatting issues occur, run:

    treefmt

Then re-run `nix flake check`.


## Validation and Acceptance

The implementation is complete when all of the following hold:

`cabal build all` compiles both seihou-core (library) and seihou (executable) without
errors or warnings.

`cabal test all` runs the seihou-core-test suite and all tests pass. The tests verify that
every core domain type can be constructed, compared for equality, and shown as a string.

`cabal run seihou -- --help` prints the command menu listing all seven subcommands with
their descriptions.

`cabal run seihou -- --version` prints "seihou 0.1.0.0".

`cabal run seihou -- init` prints a stub message acknowledging the init command.

`cabal run seihou -- run test-module --var project.name=foo --dry-run` parses the module
name, variable override, and dry-run flag, and prints a stub message showing the parsed
values.

`cabal run seihou -- vars test-module --explain` parses the module and explain flag.

`cabal run seihou -- status` prints a stub message.

`nix flake check` passes (formatting checks succeed for all new files).

The Justfile has recipes for build, test, clean, format, and check.


## Idempotence and Recovery

All steps are safe to repeat. Running `cabal build all` after a successful build is a
no-op. Running `cabal test all` reruns all tests. Running `cabal clean` resets the build
state so the next build starts fresh.

If a milestone fails partway through (for example, a type error in Types.hs), fix the
error and re-run `cabal build all`. No cleanup is needed between attempts.

If dependency resolution fails (cabal cannot find a compatible version of effectful-core
for GHC 9.12.2), check the Hackage index is up to date with `cabal update`. If the latest
effectful-core does not support GHC 9.12, add an `allow-newer` stanza to `cabal.project`
for the affected package, or pin a known-good version with a `constraints` stanza.


## Interfaces and Dependencies

External libraries:

`effectful-core` (Hackage) provides the `Effect` kind, `Eff` monad, `(:>)` constraint,
`send` function, `DispatchOf` type family, and the `Dynamic` dispatch tag used to define
all seven effect interfaces. Import `Effectful` for core types and
`Effectful.Dispatch.Dynamic` for `send` and `Dynamic`.

`optparse-applicative` (Hackage) provides `Parser`, `ParserInfo`, `subparser`, `command`,
`argument`, `option`, `switch`, `str`, `eitherReader`, `info`, `progDesc`, `helper`,
`infoOption`, `execParser`, and related functions for building the CLI parser tree.

`tasty` (Hackage) provides the test framework runner: `defaultMain`, `testGroup`,
`TestTree`.

`tasty-hspec` (Hackage) bridges hspec and tasty. Provides `testSpec` to convert an hspec
`Spec` into a tasty `TestTree`.

`hspec` (Hackage) provides the BDD test DSL: `describe`, `it`, `shouldBe`, `Spec`.

`text` (bundled with GHC) provides the `Text` type used throughout for string values.

`containers` (bundled with GHC) provides the `Map` type used in the ConfigReader effect.

Modules and signatures defined by this plan:

In `seihou-core/src/Seihou/Core/Types.hs`:

    module Seihou.Core.Types

    Exports: ModuleName(..), VarName(..), VarType(..), VarValue(..),
      Validation(..), VarDecl(..), VarExport(..), Prompt(..), Expr(..),
      Strategy(..), Step(..), Module(..), Operation(..), Manifest(..)

In `seihou-core/src/Seihou/Effect/Filesystem.hs`:

    readFileText :: (Filesystem :> es) => FilePath -> Eff es Text
    writeFileText :: (Filesystem :> es) => FilePath -> Text -> Eff es ()
    copyFile :: (Filesystem :> es) => FilePath -> FilePath -> Eff es ()
    listDirectory :: (Filesystem :> es) => FilePath -> Eff es [FilePath]
    createDirectoryIfMissing :: (Filesystem :> es) => Bool -> FilePath -> Eff es ()
    doesFileExist :: (Filesystem :> es) => FilePath -> Eff es Bool
    doesDirectoryExist :: (Filesystem :> es) => FilePath -> Eff es Bool
    getCurrentDirectory :: (Filesystem :> es) => Eff es FilePath

In `seihou-core/src/Seihou/Effect/Console.hs`:

    putText :: (Console :> es) => Text -> Eff es ()
    putError :: (Console :> es) => Text -> Eff es ()
    getLine :: (Console :> es) => Eff es Text
    confirm :: (Console :> es) => Text -> Eff es Bool
    isInteractive :: (Console :> es) => Eff es Bool

In `seihou-core/src/Seihou/Effect/DhallEval.hs`:

    evalModuleFile :: (DhallEval :> es) => FilePath -> Eff es Module

In `seihou-core/src/Seihou/Effect/ConfigReader.hs`:

    readGlobalConfig :: (ConfigReader :> es) => Eff es (Map Text Text)
    readLocalConfig :: (ConfigReader :> es) => Eff es (Map Text Text)
    readNamespaceConfig :: (ConfigReader :> es) => Text -> Eff es (Map Text Text)

In `seihou-core/src/Seihou/Effect/ManifestStore.hs`:

    readManifest :: (ManifestStore :> es) => Eff es (Maybe Manifest)
    writeManifest :: (ManifestStore :> es) => Manifest -> Eff es ()

In `seihou-core/src/Seihou/Effect/Process.hs`:

    runProcess :: (Process :> es) => Text -> [Text] -> Maybe FilePath
      -> Eff es (ExitCode, Text, Text)

In `seihou-core/src/Seihou/Effect/Logger.hs`:

    logDebug :: (Logger :> es) => Text -> Eff es ()
    logInfo :: (Logger :> es) => Text -> Eff es ()
    logWarn :: (Logger :> es) => Text -> Eff es ()
    logError :: (Logger :> es) => Text -> Eff es ()

In `seihou-cli/src/Seihou/CLI/Commands.hs`:

    data Command = Init | Run RunOpts | Vars VarsOpts | Install InstallOpts
      | Status | NewModule NewModuleOpts | ValidateModule ValidateOpts
    commandParser :: Parser Command
    opts :: ParserInfo Command
