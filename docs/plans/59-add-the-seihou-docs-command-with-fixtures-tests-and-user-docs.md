---
id: 59
slug: add-the-seihou-docs-command-with-fixtures-tests-and-user-docs
title: "Add the seihou okf extension docs command with fixture tests and user docs"
kind: exec-plan
created_at: 2026-06-19T17:55:29Z
intention: "intention_01kvgg9k54efytmmeqty43t6y5"
master_plan: "docs/masterplans/7-generate-okf-documentation-bundles-for-seihou-registries.md"
---

# Add the seihou okf extension docs command with fixture tests and user docs

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

This plan is the user-facing surface for the MasterPlan at
`docs/masterplans/7-generate-okf-documentation-bundles-for-seihou-registries.md`. Read that
file for the overall initiative; this plan stands alone for implementation.

EP-60 (`docs/plans/60-add-a-seihou-extension-contract-and-okf-extension-package.md`) creates
the `seihou-okf-extension` package and a stub `docs` command. EP-57
(`docs/plans/57-load-a-seihou-registry-into-a-documentation-model.md`) loads a registry into a
documentation model, and EP-58
(`docs/plans/58-render-the-seihou-documentation-model-to-an-okf-bundle.md`) renders that model
to an Open Knowledge Format (OKF) bundle and writes it. This plan replaces the stub with the
real `seihou-okf-extension docs` command, verifies it directly and through the seihou
extension host, and adds user documentation.

OKF, recap: a directory of Markdown documents with YAML frontmatter, cross-linked into a
graph; produced here by the okf-core library.

After this plan a user can run, inside a seihou registry repository:

```bash
seihou-okf-extension docs --dir . --out okf-docs
```

or:

```bash
seihou extension run okf -- docs --dir . --out okf-docs
```

and get an `okf-docs/` directory containing one Markdown concept document per module, recipe,
blueprint, and prompt, validated before writing. The observable outcome: running the command
against the `seihou-modules` registry produces a bundle that `okf validate` accepts and whose
`okf graph` shows the module dependency edges; and automated tests run the command flow
against a fixture registry both directly and through the extension host.


## Progress

- [x] 2026-06-19 13:36 PDT: Define `DocsOpts` in `seihou-okf-extension` and replace the EP-60 stub `docs` command.
- [x] 2026-06-19 13:36 PDT: Implement testable `runDocs :: DocsOpts -> IO (Either Text Text)` plus `handleDocs`.
- [x] 2026-06-19 13:36 PDT: Add an end-to-end test against a fixture registry (output files exist + validate).
- [x] 2026-06-19 13:36 PDT: Validate hosted invocation through `seihou extension run okf -- docs ...`; fixed host forwarding so the first forwarded token is preserved.
- [x] 2026-06-19 13:36 PDT: Add user documentation for `seihou-okf-extension docs` and `seihou extension run okf`.
- [x] 2026-06-19 13:36 PDT: `cabal build all`, `cabal test seihou-okf-extension-test`, `cabal test seihou-cli-test`, command help, direct and hosted real-registry runs, and deterministic `diff -r` all succeed.


## Surprises & Discoveries

- The EP-60 optparse-based host parser did not preserve forwarded arguments after `--`; a
  fake extension showed `seihou extension run foo -- docs --dir X` invoked the extension with
  no forwarded arguments. EP-59 fixes this in `seihou-cli/src-exe/Main.hs` by detecting
  `extension run NAME -- ...` from raw argv before normal optparse dispatch. Cross-plan
  impact: hosted invocation now matches the MasterPlan's required syntax.

- The `okf` CLI was still not available on `PATH`, so validation used okf-core directly in
  tests (`walkBundle` + `validateBundle`) and through `writeDocBundle` during command runs.


## Decision Log

- Decision: Command shape is `seihou-okf-extension docs --dir <registry> --out <dir>` with
  `--dir` defaulting to `.` and `--out` defaulting to `okf-docs`.
  Rationale: The OKF generator is now an extension package. The option names still mirror
  `seihou registry validate`'s `--dir` convention and let a user run
  `seihou-okf-extension docs` with no arguments inside a registry repo.
  Date: 2026-06-19

- Decision: The command clears (or refuses to overwrite without `--force`) the output
  directory before writing, then writes the freshly rendered bundle.
  Rationale: okf-core's `writeBundle` does not remove stale files, so to guarantee
  regeneration matches the registry exactly, the command must own directory hygiene. Default
  to creating the dir if absent and overwriting concept files; require `--force` only if the
  dir exists and is non-empty and not previously a generated bundle. (Choose the simplest safe
  behavior and record it; see Plan of Work.)
  Date: 2026-06-19

- Decision: Place `DocsOpts`, `runDocs`, and `handleDocs` in
  `seihou-okf-extension-internal`; keep the extension executable `src-exe/Main.hs` as parser
  and dispatch only.
  Rationale: This mirrors seihou's CLI library-first convention inside the extension package
  while keeping the main `seihou-cli` package independent of OKF internals.
  Date: 2026-06-19

- Decision: Validate the model before clearing the output directory.
  Rationale: The plan originally listed output hygiene before loading and validation, but a
  failed registry load or bundle validation should not delete an existing output bundle.
  `runDocs` now checks for a non-empty output directory first, then loads/renders/validates,
  and only removes/recreates the output directory immediately before a clean write.
  Date: 2026-06-19

- Decision: Fix hosted argument forwarding with raw argv detection in the main `seihou`
  executable.
  Rationale: `optparse-applicative` did not preserve the first forwarded token for the
  extension host contract. The extension host is an argv-forwarding boundary, so preserving
  bytes after `--` is more important than forcing this path through the normal typed parser.
  Date: 2026-06-19


## Outcomes & Retrospective

EP-59 is complete. `seihou-okf-extension docs` now loads a registry, renders and validates an
OKF bundle, refuses non-empty output directories unless `--force` is supplied, clears and
recreates the output directory for forced regeneration, writes the bundle, and prints
`Wrote N concepts to <out>`. The same command works through `seihou extension run okf -- docs
...` after fixing the host forwarding path.

Tests cover the command flow against a temp-dir registry, verify generated files exist,
re-read the output with okf-core `walkBundle`, validate it with `validateBundle
PermissiveConformance`, check the non-empty output guard, and check missing-registry errors.
User docs now exist in `docs/cli/extension.md` and `docs/cli/okf-docs.md`.

Validation completed:

```text
cabal test seihou-okf-extension-test # All 16 tests passed
cabal test seihou-cli-test           # All 253 tests passed
cabal build all                      # success
cabal run seihou-okf-extension -- docs --help # shows --dir, --out, --force defaults
cabal run seihou-okf-extension -- docs --dir /Users/shinzui/Keikaku/bokuno/seihou-modules --out /tmp/seihou-okf --force
Wrote 8 concepts to /tmp/seihou-okf
cabal exec -- seihou extension run okf -- docs --dir /Users/shinzui/Keikaku/bokuno/seihou-modules --out /tmp/seihou-okf-hosted --force
Wrote 8 concepts to /tmp/seihou-okf-hosted
diff -r /tmp/seihou-okf-a /tmp/seihou-okf-b # no output
```


## Context and Orientation

All paths are relative to the seihou repository root
(`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`).

EP-60 creates `seihou-okf-extension`, with a private library
`seihou-okf-extension-internal`, an executable `seihou-okf-extension`, and a test suite. This
plan works only in that package except for a hosted-invocation test that exercises the main
`seihou extension run okf -- ...` command added by EP-60.

Effects and IO: extension command handlers are plain `IO ()`. Use bare `System.Directory`
for output-directory hygiene and EP-58's `writeDocBundle` for validated writes. Keep the core
logic testable by factoring it as `runDocs :: DocsOpts -> IO (Either Text Text)`, where
`Left` is the user-facing error text and `Right` is the success summary.

This plan calls into EP-57 and EP-58:

```haskell
-- Seihou.OKF.Docs.Model (EP-57)
loadDocModel  :: FilePath -> IO (Either DocLoadError DocModel)
-- Seihou.OKF.Docs.Render (EP-58)
renderDocBundle :: DocModel -> Either [DocRenderError] ([Concept], [BundleValidationError])
writeDocBundle  :: FilePath -> DocModel -> IO (Either [DocBundleError] ())
```

`writeDocBundle` returns EP-58's `DocBundleError`. It wraps seihou render failures (currently
an invalid generated OKF concept ID) and okf-core `BundleValidationError`s. okf-core's
constructors are `DocumentInvalid ConceptId ValidationError | DanglingReference ConceptId
ConceptId | DuplicateConceptId ConceptId`. `Okf.ConceptId.renderConceptId :: ConceptId ->
Text` renders an ID for messages.

Test conventions (same as EP-57/EP-58): tasty + tasty-hspec + hspec; spec exports
`tests :: IO TestTree`; add to `seihou-okf-extension/test/Main.hs` and the extension test
stanza `other-modules`.
Use `System.IO.Temp.withSystemTempDirectory` for the output directory in tests. A fixture
registry already exists from EP-57 (`seihou-okf-extension/test/fixtures/docs-registry/` or
its temp-dir equivalent); reuse it.

User documentation lives under `docs/` (research found `docs/cli/`, `docs/user/`, and a
`docs/generated/` area). Add extension docs in the same style as existing command docs,
covering both direct execution and hosted execution through `seihou extension run okf`.

Build/run/test: `nix develop`; `cabal build all`; `cabal test all`;
`cabal run seihou -- docs --dir <path> --out <path>`. Or `just build` / `just test`.


## Plan of Work

Single milestone: command + tests + docs.

Step 1 — options + handler (extension internal library). Create
`seihou-okf-extension/src/Seihou/OKF/Extension/Docs.hs` exporting the options record and
handler:

```haskell
module Seihou.OKF.Extension.Docs
  ( DocsOpts (..)
  , runDocs
  , handleDocs
  ) where

data DocsOpts = DocsOpts
  { docsDir :: FilePath        -- registry directory (contains seihou-registry.dhall); default "."
  , docsOut :: FilePath        -- output bundle directory; default "okf-docs"
  , docsForce :: Bool          -- overwrite a non-empty existing output directory
  }
```

`runDocs :: DocsOpts -> IO (Either Text Text)`:

1. Resolve `docsDir`; verify `docsDir </> "seihou-registry.dhall"` exists, else print a clear
   error.
2. Output-dir hygiene: if `docsOut` exists and is non-empty and `not docsForce`, print an
   error ("output directory <out> is not empty; pass --force to overwrite").
   Otherwise remove `docsOut` if it exists (`removeDirectoryRecursive`) and recreate it
   (`createDirectoryIfMissing True`). This guarantees a pristine bundle.
3. `loadDocModel docsDir`; on `Left err` return the rendered `DocLoadError`.
4. `renderDocBundle model`; on `Left renderErrors`, print each rendered `DocRenderError` to
   the returned error. On `Right (concepts, validationProblems)`, if validation problems are
   present, return each rendered `BundleValidationError`.
5. If rendering and validation are clean, call `writeDocBundle docsOut model`; on `Left
   problems` return each rendered `DocBundleError`; on `Right ()` return
   `Wrote N concepts to <out>` where N is `length concepts`.
6. Add renderers for `DocBundleError` and `BundleValidationError`; the bundle-validation
   renderer mirrors the one in the okf CLI:
   - `DocumentInvalid cid e` → `renderConceptId cid <> ": " <> <validation error text>`
   - `DanglingReference s t` → `renderConceptId s <> ": link to missing concept: " <> renderConceptId t`
   - `DuplicateConceptId cid` → `"duplicate concept ID: " <> renderConceptId cid`

`handleDocs :: DocsOpts -> IO ()` calls `runDocs`, prints `Left` to stderr and exits
non-zero, or prints `Right` to stdout and exits success.

Step 2 — parser (extension executable). In `seihou-okf-extension/src-exe/Main.hs`, replace
EP-60's stub parser with a real optparse parser:

  ```haskell
  docsInfo :: ParserInfo DocsOpts
  docsInfo = info (docsParser <**> helper)
    (fullDesc <> progDesc "Generate an OKF documentation bundle for a seihou registry")

  docsParser :: Parser DocsOpts
  docsParser = DocsOpts
      <$> option str (long "dir" <> metavar "PATH" <> value "." <> showDefault
                       <> help "Registry directory containing seihou-registry.dhall")
      <*> option str (long "out" <> metavar "PATH" <> value "okf-docs" <> showDefault
                       <> help "Output directory for the generated OKF bundle")
      <*> switch (long "force" <> help "Overwrite a non-empty output directory")
  ```

Register it under `command "docs" docsInfo`, and dispatch to `handleDocs`.

Step 3 — cabal. Add `Seihou.OKF.Extension.Docs` to the `exposed-modules` of
`seihou-okf-extension-internal`. `Seihou.OKF.Docs.Model` and `Seihou.OKF.Docs.Render` are
already exposed by EP-57/EP-58.

Step 4 — end-to-end test. Create `seihou-okf-extension/test/Seihou/OKF/Extension/DocsSpec.hs` exporting
`tests :: IO TestTree`. In a `withSystemTempDirectory`:

- Point at the fixture registry from EP-57 (or write it into the temp dir).
- Run `runDocs DocsOpts{ docsDir = <fixture>, docsOut = <temp>/out, docsForce = True }`.
- Assert the expected files exist: `<temp>/out/modules/<name>.md`,
  `<temp>/out/recipes/<name>.md`, etc., for the fixture's entities.
- Re-read the written bundle with okf-core's `Okf.Bundle.walkBundle` and run
  `Okf.Validation.validateBundle PermissiveConformance` on the result; assert it is `[]`
  (the written bundle validates clean). This proves the command produced a valid OKF bundle
  end to end, using okf-core as the oracle.
- Capture that a second run with `docsForce = False` against the now-non-empty out dir returns
  `Left`, covering the hygiene guard without triggering `exitFailure`.

Add the spec to `seihou-okf-extension/test/Main.hs` and the test stanza `other-modules`.

Step 5 — hosted invocation test. Add or update a `seihou-cli` extension-host test from EP-60
only if EP-60 did not already cover a real extension binary. The test should put the built or
temporary `seihou-okf-extension` executable on `PATH`, run `seihou extension run okf -- docs
--dir <fixture> --out <temp>/out --force`, and assert the output bundle exists. If invoking
the built binary is too heavy for a unit test, keep this as a manual validation command and
record why in Surprises & Discoveries.

Step 6 — user docs. Add documentation for the OKF extension in the same place and style as
other command docs (e.g. under `docs/cli/` or `docs/user/`). Cover: what it does (generate an
OKF documentation bundle from a registry), the direct command
`seihou-okf-extension docs`, the hosted command `seihou extension run okf -- docs`, the
`--dir`/`--out`/`--force` flags and defaults, a worked example against `seihou-modules`, a
note that output is *derived* (regenerate, do not hand-edit; each doc's `resource` points at
the source `.dhall`), and how to explore the result with the `okf` CLI (`okf validate`,
`okf index --write`, `okf graph --json`).


## Concrete Steps

From the seihou repository root, inside the dev shell:

```bash
nix develop
cabal build all
cabal test seihou-okf-extension-test
```

Manual run against the real registry:

```bash
cabal run seihou-okf-extension -- docs --dir /Users/shinzui/Keikaku/bokuno/seihou-modules --out /tmp/seihou-okf
```

Expected:

```text
Wrote 8 concepts to /tmp/seihou-okf
```

Then verify with the okf CLI (if available):

```bash
okf validate /tmp/seihou-okf       # OK: 8 concepts
okf index /tmp/seihou-okf --write  # writes catalog index.md files
okf graph /tmp/seihou-okf --json   # edges incl. haskell-library -> nix-haskell-flake
```

Help text check:

```bash
cabal run seihou-okf-extension -- docs --help
```

Expected: usage showing `--dir`, `--out`, `--force` with their defaults.


## Validation and Acceptance

Acceptance is behavioral:

1. `seihou-okf-extension docs --dir <registry> --out <dir>` writes one Markdown document per
   registry entry into `<dir>` and prints a concept count; running it on `seihou-modules`
   yields a bundle that `okf validate` accepts.
2. `cabal test seihou-okf-extension-test` passes, including the new `DocsSpec`, which runs
   the command flow against a fixture registry and re-validates the written bundle with
   okf-core (`walkBundle` + `validateBundle` returns `[]`).
3. `seihou-okf-extension docs --help` shows the `--dir`/`--out`/`--force` options with
   defaults.
4. The output is deterministic: running the command twice (with `--force`) produces identical
   files (no timestamps), demonstrable by `diff -r` of two runs.
5. User documentation for `seihou-okf-extension docs` and the hosted
   `seihou extension run okf -- docs` form exists and its example matches real behavior.


## Idempotence and Recovery

The extension command is safe to re-run: with `--force` it clears and recreates the output directory, so
repeated runs converge to the same bundle. Without `--force`, it refuses to overwrite a
non-empty output directory, preventing accidental clobbering of unrelated files. If
`writeDocBundle` reports validation errors, the command exits non-zero without writing a
partial bundle is not guaranteed by okf-core (it validates before writing in `writeDocBundle`,
so nothing is written on `Left`) — confirm `writeDocBundle` returns `Left` before any write
(it does, per EP-58). Reverting the three wiring edits plus the new modules removes the command
cleanly; generated `okf-docs/` directories are disposable.


## Interfaces and Dependencies

Depends on EP-60 (extension package and host), EP-58 (`renderDocBundle`/`writeDocBundle`), and
transitively EP-57 (`loadDocModel`) and EP-56 (okf-core source/build wiring). Uses
`optparse-applicative` in the `seihou-okf-extension` executable, `System.Directory`, and
okf-core's `Okf.Bundle.walkBundle` + `Okf.Validation.validateBundle` in the test. No new
package dependencies beyond those already assigned to `seihou-okf-extension`.

Artifacts that must exist at the end of this plan:

```text
seihou-okf-extension/src/Seihou/OKF/Extension/Docs.hs      (DocsOpts + runDocs + handleDocs)
seihou-okf-extension/src-exe/Main.hs                       (docs parser + dispatch)
seihou-okf-extension/seihou-okf-extension.cabal            (exposed module + test other-modules)
seihou-okf-extension/test/Seihou/OKF/Extension/DocsSpec.hs (end-to-end test)
seihou-okf-extension/test/Main.hs                          (+ DocsSpec in the test group)
docs/cli/ or docs/user/                                    (user documentation for the OKF extension)
```

Relationship to other plans (see the MasterPlan's Integration Points):

- Hard deps: EP-58 and EP-60.
- Must use the same concept-ID scheme and validation profile EP-58 established (integration
  points 3 and 4); the test asserts against them.
- Shares `seihou-okf-extension/test/Main.hs` and the extension test stanza `other-modules`
  with EP-57 and EP-58: append the new spec; do not reorder existing ones.


## Revision Notes

- 2026-06-19: Updated EP-59 to consume EP-58's corrected render/write API. The command now
  explicitly handles seihou render errors separately from okf-core bundle validation errors,
  uses the already-rendered concept count for success output, and keeps strict/timestamp
  behavior out of the first command surface.
- 2026-06-19: Retargeted EP-59 from a main `seihou docs` subcommand to the
  `seihou-okf-extension docs` command plus hosted invocation through
  `seihou extension run okf -- docs`. Parser, handler, tests, and docs now live under the
  extension package boundary introduced by EP-60.
- 2026-06-19: Implemented the real docs command, added command-flow tests and user docs,
  fixed hosted argument forwarding, and recorded validation evidence for direct, hosted, and
  deterministic real-registry runs.
