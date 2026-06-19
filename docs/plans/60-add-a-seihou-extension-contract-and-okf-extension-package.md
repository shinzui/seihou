---
id: 60
slug: add-a-seihou-extension-contract-and-okf-extension-package
title: "Add a seihou extension contract and okf extension package"
kind: exec-plan
created_at: 2026-06-19T19:16:16Z
intention: "intention_01kvgg9k54efytmmeqty43t6y5"
master_plan: "docs/masterplans/7-generate-okf-documentation-bundles-for-seihou-registries.md"
---

# Add a seihou extension contract and okf extension package

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

This plan changes the OKF documentation feature from an in-core `seihou-cli` feature into
the first seihou extension. The user-visible result is a stable extension invocation
contract:

```bash
seihou extension run okf -- docs --dir <registry-repo> --out <output-dir>
```

and a directly runnable executable:

```bash
seihou-okf-extension docs --dir <registry-repo> --out <output-dir>
```

After this plan, `seihou-cli` knows how to locate and run external extension executables
named `seihou-<name>-extension`, and the repository contains a new Cabal package
`seihou-okf-extension` with a minimal executable that can be built and invoked. The OKF
registry loading, rendering, and real `docs` behavior remain in EP-57, EP-58, and EP-59; this
plan only creates the host contract and package boundary so okf-core does not live inside
`seihou-cli-internal`.


## Progress

- [x] 2026-06-19 12:58 PDT: Add a testable extension runner to `seihou-cli-internal`.
- [x] 2026-06-19 12:58 PDT: Add `seihou extension run NAME -- ARGS...` parser and top-level dispatch.
- [x] 2026-06-19 12:58 PDT: Create the `seihou-okf-extension` Cabal package with a stub `docs` command.
- [x] 2026-06-19 12:58 PDT: Move the `okf-core` package dependency from `seihou-cli-internal` to `seihou-okf-extension`.
- [x] 2026-06-19 12:58 PDT: Wire `seihou-okf-extension` into `cabal.project`, Nix package set, and package outputs.
- [x] 2026-06-19 12:58 PDT: Add CLI tests for executable lookup, missing extension errors, argument forwarding, and exit-code propagation.
- [x] 2026-06-19 12:58 PDT: Add extension contract documentation.
- [x] 2026-06-19 12:58 PDT: `cabal build all`, targeted tests, `cabal check`, formatter check, command smoke checks, and `nix build .#seihou-okf-extension` pass.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- Cabal rejects a package-local `license-file` that points outside the package directory.
  The new package therefore carries its own `LICENSE` file rather than using
  `license-file: ../LICENSE`. Evidence:

  ```text
  Error: [relative-path-outside] 'license-file: ../LICENSE' is a relative path outside of the source tree.
  ```

- `nix build .#seihou-okf-extension` cannot see a newly created package directory until the
  files are tracked in git. After staging the new package and wiring, the same command built
  successfully. Evidence:

  ```text
  error: path '/Users/shinzui/Keikaku/bokuno/seihou-project/seihou/seihou-okf-extension' does not exist
  ```


## Decision Log

- Decision: Extension executables are named `seihou-<extension>-extension`.
  Rationale: The name is explicit, shell-friendly, and avoids implying that extensions are
  linked into the main `seihou` binary. It also matches the user's proposed
  `seihou-okf-extension` package name.
  Date: 2026-06-19

- Decision: The first host command is `seihou extension run <name> -- <args...>`, not dynamic
  top-level unknown-command dispatch.
  Rationale: `seihou-cli` currently uses an explicit optparse-applicative command tree.
  Unknown-command dispatch would require lower-level argv handling and would complicate help,
  completions, and error behavior. The explicit `extension run` contract is enough for the
  first extension and can later grow aliases such as `seihou okf ...` if they prove worth the
  parser complexity.
  Date: 2026-06-19

- Decision: The OKF extension package lives in this repository as `seihou-okf-extension`.
  Rationale: Keeping it in-tree lets Cabal, Nix, tests, and release tooling evolve with
  seihou while preserving the dependency boundary: `seihou-okf-extension` depends on
  `seihou-core` and `okf-core`; `seihou-cli-internal` does not depend on `okf-core`.
  Date: 2026-06-19

- Decision: The EP-60 `docs` command stub exits non-zero.
  Rationale: The package boundary must be runnable, but EP-57, EP-58, and EP-59 still own
  the real registry loading, rendering, and file output. A non-zero stub prevents users from
  mistaking the placeholder for a successful documentation generator.
  Date: 2026-06-19


## Outcomes & Retrospective

EP-60 is complete. `seihou-cli-internal` now exposes `Seihou.CLI.Extension`, the main
executable parses and dispatches `seihou extension run <name> -- <args...>`, and the runner
locates `seihou-<name>-extension` on `PATH`, forwards arguments unchanged, streams stdio
through `rawSystem`, returns clear missing-executable errors, and preserves extension exit
codes.

The repository now has a `seihou-okf-extension` package with a private library, executable,
test suite, local license file, and `okf-core` smoke import. `okf-core` has been removed from
`seihou-cli-internal`; a search for `okf-core` and `Okf.` finds OKF usage only in the new
extension package and build wiring. The package is listed in `cabal.project`, the Nix
overlay, and `packages.seihou-okf-extension`. `docs/cli/extension.md` documents the extension
contract.

Validation completed:

```text
cabal check                         # in seihou-cli: no errors or warnings
cabal check                         # in seihou-okf-extension: no errors or warnings
cabal build all                     # success
cabal test seihou-cli-test          # All 253 tests passed
cabal test seihou-okf-extension-test # All 1 tests passed
nix fmt -- --fail-on-change         # formatted 1 files (0 changed)
nix build .#seihou-okf-extension    # success
```

Command smoke checks completed:

```text
cabal run seihou -- extension run missing-extension -- --help
error: extension executable not found: seihou-missing-extension-extension

cabal run seihou-okf-extension -- --help
seihou-okf-extension - OKF documentation extension for Seihou

cabal run seihou-okf-extension -- docs
seihou-okf-extension docs is not implemented yet; see EP-57/EP-58/EP-59.

cabal exec -- seihou extension run okf -- --help
seihou-okf-extension - OKF documentation extension for Seihou
```


## Context and Orientation

All paths are relative to `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`.

The repository has three Cabal packages listed in `cabal.project`: `seihou-core`,
`seihou-cli`, and `seihou-okf-extension`. `seihou-cli/seihou-cli.cabal` contains a private
library `seihou-cli-internal`, the executable `seihou`, and the test suite
`seihou-cli-test`. The old EP-56 smoke module `Seihou.CLI.Docs.Smoke` has been removed from
`seihou-cli-internal`; `okf-core` is owned by `seihou-okf-extension`, not
`seihou-cli-internal`.

The CLI parser is in `seihou-cli/src-exe/Seihou/CLI/Commands.hs`. It defines the `Command`
sum type and an explicit `hsubparser` tree. Dispatch is in `seihou-cli/src-exe/Main.hs`. The
internal handler modules are under `seihou-cli/src/Seihou/CLI/`, and tests are registered in
`seihou-cli/test/Main.hs` and `seihou-cli/seihou-cli.cabal`.

The Nix Haskell package set is in `flake.module.nix` plus `nix/haskell-overlay.nix`.
`nix/haskell-overlay.nix` builds `okf-core` from the pinned `okf-src` input added by EP-56,
and builds `seihou-core`, `seihou-cli`, and `seihou-okf-extension` with `callCabal2nix`.
`flake.module.nix` exposes `packages.seihou-okf-extension`.

An extension is an external executable that follows seihou's process contract. The host
command resolves `seihou-<name>-extension` on `PATH`, forwards every argument after `--`
unchanged, streams stdio normally, and exits with the extension's exit code. The extension is
responsible for its own command parser, help text, tests, and dependencies.


## Plan of Work

Milestone 1: add the extension host command to `seihou-cli`.

Create `seihou-cli/src/Seihou/CLI/Extension.hs` in `seihou-cli-internal`. Define:

```haskell
data ExtensionRunOpts = ExtensionRunOpts
  { extensionName :: Text
  , extensionArgs :: [String]
  }

data ExtensionRunError
  = ExtensionNotFound Text String
  | ExtensionExited Text ExitCode
  deriving stock (Eq, Show)

extensionExecutableName :: Text -> String
runExtension :: ExtensionRunOpts -> IO (Either ExtensionRunError ())
handleExtensionRun :: ExtensionRunOpts -> IO ()
```

`extensionExecutableName "okf"` returns `"seihou-okf-extension"`. `runExtension` uses
`System.Directory.findExecutable` and `System.Process.rawSystem` (or `callProcess` plus
`try`) to run the executable with `extensionArgs`, preserving argument order. It returns
`Right ()` on `ExitSuccess`, `Left (ExtensionExited name code)` on non-zero exit, and
`Left (ExtensionNotFound name exe)` if the executable cannot be found. `handleExtensionRun`
renders errors to stderr and exits with the same non-zero behavior as other handlers.

In `seihou-cli/src-exe/Seihou/CLI/Commands.hs`, add an extension command shape:

```haskell
data Command = ... | Extension ExtensionCommand
data ExtensionCommand = ExtensionRun ExtensionRunOpts
```

Add a parser for `seihou extension run NAME -- ARGS...`. Use `strArgument` for `NAME` and
`many (strArgument (metavar "ARGS..."))` for the forwarded tail after optparse's `--`. In
`seihou-cli/src-exe/Main.hs`, dispatch `Extension (ExtensionRun opts)` to
`handleExtensionRun`. Add `Seihou.CLI.Extension` to `seihou-cli-internal` exposed modules and
add tests for `extensionExecutableName` and the missing-extension path. If testing a
successful subprocess, create a temporary executable shell script in a temp directory and
prepend that directory to `PATH` only inside the test process.

Milestone 2: create the `seihou-okf-extension` package boundary.

Add a new package directory:

```text
seihou-okf-extension/
  seihou-okf-extension.cabal
  src/Seihou/OKF/Extension.hs
  src-exe/Main.hs
  test/Main.hs
```

The package has a private library `seihou-okf-extension-internal`, an executable
`seihou-okf-extension`, and a test suite. For this foundation plan, the executable only
supports help and a stub `docs` command that prints a clear placeholder such as:

```text
seihou-okf-extension docs is not implemented yet; see EP-57/EP-58/EP-59.
```

It should exit non-zero for the stub implementation so users do not mistake it for a working
generator. EP-59 replaces the stub with the real docs command.

Add `seihou-okf-extension` to `cabal.project`'s `packages:` list. Move the `okf-core`
dependency out of `seihou-cli-internal` and into the new extension package. Remove
`Seihou.CLI.Docs.Smoke` from `seihou-cli-internal` once the extension package contains an
equivalent smoke import that proves okf-core resolves there. The source-repository-package
for okf-core can stay in `cabal.project`; it is now consumed by the extension package.

Milestone 3: wire Nix and docs.

In `nix/haskell-overlay.nix`, add:

```nix
seihou-okf-extension =
  doJailbreak (final.callCabal2nix "seihou-okf-extension" ../seihou-okf-extension { });
```

If the extension package needs the schema checkout during tests, mirror the `seihou-core` /
`seihou-cli` `prePatch` staging for `seihou-schema-src`. In `flake.module.nix`, expose a
package output such as `packages.seihou-okf-extension = haskellPackages.seihou-okf-extension`
and add it to the dev shell if needed so `seihou extension run okf -- --help` can find it in
development.

Add extension documentation under `docs/cli/extension.md` or the closest existing CLI docs
location. Document the naming convention, PATH lookup, `seihou extension run <name> -- ...`,
the direct executable form, and the fact that OKF is the first extension.


## Concrete Steps

From the repository root:

```bash
nix develop
cabal build all
cabal test seihou-cli-test
cabal test seihou-okf-extension-test
```

Check the host command:

```bash
cabal run seihou -- extension run missing-extension -- --help
```

Expected stderr contains:

```text
error: extension executable not found: seihou-missing-extension-extension
```

Check the extension executable directly:

```bash
cabal run seihou-okf-extension -- --help
cabal run seihou-okf-extension -- docs --help
```

Expected: help text for the extension and its stub `docs` command.

When the dev shell exposes `seihou-okf-extension` on `PATH`, check host delegation:

```bash
cabal run seihou -- extension run okf -- --help
```

Expected: the same top-level help text printed by `seihou-okf-extension --help`.


## Validation and Acceptance

Acceptance is behavioral:

1. `seihou-cli-internal` no longer depends on `okf-core`, and `Seihou.CLI.Docs.Smoke` is gone
   or moved into the extension package. `seihou-okf-extension` is the only seihou-owned
   package that directly depends on `okf-core`.
2. `seihou extension run missing-extension -- --help` reports a clear missing-executable
   error naming `seihou-missing-extension-extension` and exits non-zero.
3. A test with a temporary fake `seihou-okf-extension` executable proves that
   `seihou extension run okf -- docs --dir .` forwards `["docs", "--dir", "."]` unchanged.
4. `cabal build all` builds `seihou-core`, `seihou-cli`, and `seihou-okf-extension`.
5. `cabal test seihou-cli-test` passes the new extension host tests, and
   `cabal test seihou-okf-extension-test` passes the package skeleton tests.
6. Nix exposes both the existing `seihou` package and a `seihou-okf-extension` package output
   or dev-shell binary so the extension can be run under `nix develop`.


## Idempotence and Recovery

All edits are additive except moving the okf-core dependency out of `seihou-cli-internal`.
If the extension package fails to build, revert only the new package directory and the
`cabal.project` / Nix entries; the existing `seihou-cli` remains intact. If the host command
is wrong, it is isolated to `Seihou.CLI.Extension`, `Commands.hs`, `Main.hs`, and the CLI test
registration. Running the host command is safe: it only executes an extension executable that
is already on `PATH` and passes arguments through.


## Interfaces and Dependencies

This plan uses only existing `seihou-cli` dependencies for the host: `process`,
`directory`, `filepath`, `text`, `base`, and `seihou-core` as already configured. The new
extension package depends on `seihou-core` and `okf-core`; later EP-57/EP-58 add the real OKF
model/render modules there.

Required host module:

```haskell
module Seihou.CLI.Extension
  ( ExtensionRunOpts (..)
  , ExtensionRunError (..)
  , extensionExecutableName
  , runExtension
  , handleExtensionRun
  ) where
```

Required extension package artifacts:

```text
seihou-okf-extension/seihou-okf-extension.cabal
seihou-okf-extension/src/Seihou/OKF/Extension.hs
seihou-okf-extension/src-exe/Main.hs
seihou-okf-extension/test/Main.hs
```

Relationship to other plans:

- EP-56 proved okf-core can be pinned and built. This plan reuses that source-repository and
  Nix input but moves the consuming dependency out of `seihou-cli-internal`.
- EP-57 must place the documentation model under `seihou-okf-extension`, not
  `seihou-cli-internal`.
- EP-58 must place the OKF renderer under `seihou-okf-extension`, where `okf-core` is
  available.
- EP-59 replaces the stub `docs` command in `seihou-okf-extension` and updates user docs to
  show both direct and hosted extension invocation.


## Revision Notes

- 2026-06-19: Created as part of the MasterPlan update that moves OKF documentation
  generation from an in-core `seihou-cli` feature to the first external extension package,
  `seihou-okf-extension`.
- 2026-06-19: Implemented the extension host contract and `seihou-okf-extension` package.
  Updated progress, discoveries, context, and outcomes with the validation evidence from
  Cabal, Nix, tests, formatter, and command smoke checks.
