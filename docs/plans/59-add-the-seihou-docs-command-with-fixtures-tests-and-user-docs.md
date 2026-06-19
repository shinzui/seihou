---
id: 59
slug: add-the-seihou-docs-command-with-fixtures-tests-and-user-docs
title: "Add the seihou docs command with fixtures tests and user docs"
kind: exec-plan
created_at: 2026-06-19T17:55:29Z
intention: "intention_01kvgg9k54efytmmeqty43t6y5"
master_plan: "docs/masterplans/7-generate-okf-documentation-bundles-for-seihou-registries.md"
---

# Add the seihou docs command with fixtures tests and user docs

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

This plan is the user-facing surface for the MasterPlan at
`docs/masterplans/7-generate-okf-documentation-bundles-for-seihou-registries.md`. Read that
file for the overall initiative; this plan stands alone for implementation.

EP-57 (`docs/plans/57-load-a-seihou-registry-into-a-documentation-model.md`) loads a registry
into a documentation model, and EP-58
(`docs/plans/58-render-the-seihou-documentation-model-to-an-okf-bundle.md`) renders that model
to an Open Knowledge Format (OKF) bundle and writes it. Neither is reachable from the command
line. This plan adds the `seihou docs` subcommand that ties them together, an end-to-end test
against a fixture registry, and seihou user documentation.

OKF, recap: a directory of Markdown documents with YAML frontmatter, cross-linked into a
graph; produced here by the okf-core library.

After this plan a user can run, inside a seihou registry repository:

    seihou docs --dir . --out okf-docs

and get an `okf-docs/` directory containing one Markdown concept document per module, recipe,
blueprint, and prompt, validated before writing. The observable outcome: running the command
against the `seihou-modules` registry produces a bundle that `okf validate` accepts and whose
`okf graph` shows the module dependency edges; and an automated test runs the whole command
flow against a fixture registry and asserts the output files exist and validate.


## Progress

- [ ] Define `DocsOpts` and add `Docs DocsOpts` to the CLI `Command` type + parser
- [ ] Implement `handleDocs :: DocsOpts -> IO ()` (clear/create out dir, load, render, write, report)
- [ ] Wire dispatch in `seihou-cli/src-exe/Main.hs`
- [ ] Add an end-to-end test against a fixture registry (output files exist + validate)
- [ ] Add user documentation for `seihou docs`
- [ ] `cabal build all`, `cabal test all`, and a manual run against `seihou-modules` all succeed


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Command shape is `seihou docs --dir <registry> --out <dir>` with `--dir`
  defaulting to `.` and `--out` defaulting to `okf-docs`.
  Rationale: Mirrors `seihou registry validate`'s `--dir` convention and matches the request
  to document a registry's modules/blueprints/prompts/recipes. Sensible defaults let a user
  run `seihou docs` with no arguments inside a registry repo.
  Date: 2026-06-19

- Decision: The command clears (or refuses to overwrite without `--force`) the output
  directory before writing, then writes the freshly rendered bundle.
  Rationale: okf-core's `writeBundle` does not remove stale files, so to guarantee
  regeneration matches the registry exactly, the command must own directory hygiene. Default
  to creating the dir if absent and overwriting concept files; require `--force` only if the
  dir exists and is non-empty and not previously a generated bundle. (Choose the simplest safe
  behavior and record it; see Plan of Work.)
  Date: 2026-06-19

- Decision: Place `DocsOpts` and `handleDocs` in `seihou-cli-internal`
  (`seihou-cli/src/Seihou/CLI/Docs.hs`); place only the optparse parser wiring in
  `src-exe/Seihou/CLI/Commands.hs` and the dispatch in `src-exe/Main.hs`.
  Rationale: Seihou's enforced "CLI library-first" convention — feature logic in the internal
  library, only optparse/Paths/file-embed-coupled code in `src-exe`.
  Date: 2026-06-19


## Context and Orientation

All paths are relative to the seihou repository root
(`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`).

How seihou adds a subcommand (three files, from prior research):

1. `seihou-cli/src-exe/Seihou/CLI/Commands.hs` — defines the `Command` sum type and the
   optparse parser. Each command has a `*Info :: ParserInfo Command` and a
   `*Parser :: Parser Command`, registered in an `hsubparser` block with
   `command "<name>" <info>`. The `*Opts` records are imported from the internal library.
   Canonical example to mirror is `migrate`:

   ```haskell
   migrateInfo :: ParserInfo Command
   migrateInfo = info (migrateParser <**> helper) (fullDesc <> progDesc "..." <> footerDoc (Just migrateFooter))

   migrateParser :: Parser Command
   migrateParser = fmap Migrate $ MigrateOpts
       <$> argument (ModuleName . T.pack <$> str) (metavar "MODULE" <> help "...")
       <*> optional (option (T.pack <$> str) (long "to" <> ...))
       <*> switch (long "dry-run" <> ...)
   ```

2. `seihou-cli/src-exe/Main.hs` — dispatch: `main = customExecParser (prefs showHelpOnEmpty)
   opts` then `case cmd of ... Migrate o -> handleMigrate o`.

3. The handler module. For `registry`, the handler lives in the internal library
   (`seihou-cli/src/Seihou/CLI/Registry.hs`, `handleRegistry :: RegistryCommand -> IO ()`),
   which is the pattern to follow here (`registry validate` already takes `--dir PATH` and
   reads `seihou-registry.dhall`).

Effects and IO: command handlers are plain `IO ()`. Filesystem work can be done in bare IO
(`System.Directory`) — as `Seihou.CLI.List.handleList` and the `eval*FromFile` loaders do — or
through seihou's `Filesystem` effect (`Seihou.Effect.Filesystem` +
`Seihou.Effect.FilesystemInterp.runFilesystem`, used via `runEff $ runFilesystem $ ...`). For
this command, bare `System.Directory` plus EP-58's `writeDocBundle` (which itself does IO) is
the simplest; match whichever style the surrounding handlers prefer.

This plan calls into EP-57 and EP-58:

```haskell
-- Seihou.CLI.Docs.Model (EP-57)
loadDocModel  :: FilePath -> IO (Either DocLoadError DocModel)
-- Seihou.CLI.Docs.Render (EP-58)
renderDocBundle :: DocModel -> ([Concept], [BundleValidationError])
writeDocBundle  :: FilePath -> DocModel -> IO (Either [BundleValidationError] ())
```

okf-core's `BundleValidationError` (from `Okf.Validation`) is what `writeDocBundle` returns on
failure; render it for the user (see Step 2). Its constructors:
`DocumentInvalid ConceptId ValidationError | DanglingReference ConceptId ConceptId |
DuplicateConceptId ConceptId`. `Okf.ConceptId.renderConceptId :: ConceptId -> Text` renders an
ID for messages.

Test conventions (same as EP-57/EP-58): tasty + tasty-hspec + hspec; spec exports
`tests :: IO TestTree`; add to `seihou-cli/test/Main.hs` and the test stanza `other-modules`.
Use `System.IO.Temp.withSystemTempDirectory` for the output directory in tests. A fixture
registry already exists from EP-57 (`seihou-cli/test/fixtures/docs-registry/` or its temp-dir
equivalent); reuse it.

User documentation lives under `docs/` (research found `docs/cli/`, `docs/user/`, and a
`docs/generated/` area). Find where existing per-command docs live (e.g. how `migrate` or
`registry` is documented) and add the `docs` command there in the same style. Also check
`seihou-cli/help/` (the executable has a `help/` data dir) — if commands ship embedded help
text via `file-embed`, add a `docs` help file in the same format.

Build/run/test: `nix develop`; `cabal build all`; `cabal test all`;
`cabal run seihou -- docs --dir <path> --out <path>`. Or `just build` / `just test`.


## Plan of Work

Single milestone: command + tests + docs.

Step 1 — options + handler (internal library). Create `seihou-cli/src/Seihou/CLI/Docs.hs`
exporting the options record and handler (re-export the model/render modules' needs as
required):

```haskell
module Seihou.CLI.Docs
  ( DocsOpts (..)
  , handleDocs
  ) where

data DocsOpts = DocsOpts
  { docsDir :: FilePath        -- registry directory (contains seihou-registry.dhall); default "."
  , docsOut :: FilePath        -- output bundle directory; default "okf-docs"
  , docsForce :: Bool          -- overwrite a non-empty existing output directory
  }
```

`handleDocs :: DocsOpts -> IO ()`:

1. Resolve `docsDir`; verify `docsDir </> "seihou-registry.dhall"` exists, else print a clear
   error to stderr and `exitFailure`.
2. Output-dir hygiene: if `docsOut` exists and is non-empty and `not docsForce`, print an
   error ("output directory <out> is not empty; pass --force to overwrite") and `exitFailure`.
   Otherwise remove `docsOut` if it exists (`removeDirectoryRecursive`) and recreate it
   (`createDirectoryIfMissing True`). This guarantees a pristine bundle.
3. `loadDocModel docsDir`; on `Left err` print the rendered `DocLoadError` and `exitFailure`.
4. `writeDocBundle docsOut model`; on `Left problems` print each `BundleValidationError`
   (rendered) to stderr and `exitFailure`; on `Right ()` print a success summary, e.g.
   `Wrote N concepts to <out>` where N is `length (fst (renderDocBundle model))`.
5. Add a renderer `renderBundleValidationError :: BundleValidationError -> Text` mirroring the
   one in the okf CLI:
   - `DocumentInvalid cid e` → `renderConceptId cid <> ": " <> <validation error text>`
   - `DanglingReference s t` → `renderConceptId s <> ": link to missing concept: " <> renderConceptId t`
   - `DuplicateConceptId cid` → `"duplicate concept ID: " <> renderConceptId cid`

Step 2 — parser (executable). In `seihou-cli/src-exe/Seihou/CLI/Commands.hs`:

- Add `Docs DocsOpts` to the `Command` sum type (import `DocsOpts` from `Seihou.CLI.Docs`).
- Add `docsInfo`/`docsParser`:

  ```haskell
  docsInfo :: ParserInfo Command
  docsInfo = info (docsParser <**> helper)
    (fullDesc <> progDesc "Generate an OKF documentation bundle for a seihou registry")

  docsParser :: Parser Command
  docsParser = fmap Docs $ DocsOpts
      <$> option str (long "dir" <> metavar "PATH" <> value "." <> showDefault
                       <> help "Registry directory containing seihou-registry.dhall")
      <*> option str (long "out" <> metavar "PATH" <> value "okf-docs" <> showDefault
                       <> help "Output directory for the generated OKF bundle")
      <*> switch (long "force" <> help "Overwrite a non-empty output directory")
  ```

- Register it in the appropriate `hsubparser` group: `command "docs" docsInfo`.

Step 3 — dispatch. In `seihou-cli/src-exe/Main.hs` add `Docs o -> handleDocs o` to the
command `case`, importing `handleDocs` from `Seihou.CLI.Docs`.

Step 4 — cabal. Add `Seihou.CLI.Docs` to the `exposed-modules` of `seihou-cli-internal`. The
`executable seihou` stanza already depends on `seihou-cli-internal`, so no new dep there; it
inherits okf-core transitively. (`Seihou.CLI.Docs.Model` and `.Render` are already exposed by
EP-57/EP-58.)

Step 5 — end-to-end test. Create `seihou-cli/test/Seihou/CLI/DocsSpec.hs` exporting
`tests :: IO TestTree`. In a `withSystemTempDirectory`:

- Point at the fixture registry from EP-57 (or write it into the temp dir).
- Run `handleDocs DocsOpts{ docsDir = <fixture>, docsOut = <temp>/out, docsForce = True }`.
- Assert the expected files exist: `<temp>/out/modules/<name>.md`,
  `<temp>/out/recipes/<name>.md`, etc., for the fixture's entities.
- Re-read the written bundle with okf-core's `Okf.Bundle.walkBundle` and run
  `Okf.Validation.validateBundle PermissiveConformance` on the result; assert it is `[]`
  (the written bundle validates clean). This proves the command produced a valid OKF bundle
  end to end, using okf-core as the oracle.
- Optionally capture that a second run with `docsForce = False` against the now-non-empty out
  dir fails (returns non-zero / throws the handled error) — test the hygiene guard. Since
  `handleDocs` calls `exitFailure`, either factor the core logic into a pure-result function
  the test can call without exiting, or test the success path only and cover the guard with a
  smaller unit. Prefer factoring `handleDocs` into `runDocs :: DocsOpts -> IO (Either Text
  ())` (returns the message) plus a thin `handleDocs` that prints and exits — this makes the
  command testable without `exitFailure`. Record this refactor in the Decision Log if adopted.

Add the spec to `seihou-cli/test/Main.hs` and the test stanza `other-modules`.

Step 6 — user docs. Add documentation for `seihou docs` in the same place and style as other
commands' docs (e.g. under `docs/cli/` or `docs/user/`). Cover: what it does (generate an OKF
documentation bundle from a registry), the `--dir`/`--out`/`--force` flags and defaults, a
worked example against `seihou-modules`, a note that output is *derived* (regenerate, do not
hand-edit; each doc's `resource` points at the source `.dhall`), and how to explore the result
with the `okf` CLI (`okf validate`, `okf index --write`, `okf graph --json`). If commands ship
embedded help via `seihou-cli/help/`, add a matching `docs` help entry.


## Concrete Steps

From the seihou repository root, inside the dev shell:

```bash
nix develop
cabal build all
cabal test all
```

Manual run against the real registry:

```bash
cabal run seihou -- docs --dir /Users/shinzui/Keikaku/bokuno/seihou-modules --out /tmp/seihou-okf
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
cabal run seihou -- docs --help
```

Expected: usage showing `--dir`, `--out`, `--force` with their defaults.


## Validation and Acceptance

Acceptance is behavioral:

1. `seihou docs --dir <registry> --out <dir>` writes one Markdown document per registry entry
   into `<dir>` and prints a concept count; running it on `seihou-modules` yields a bundle
   that `okf validate` accepts.
2. `cabal test all` passes, including the new `DocsSpec`, which runs the command flow against a
   fixture registry and re-validates the written bundle with okf-core (`walkBundle` +
   `validateBundle` returns `[]`).
3. `seihou docs --help` shows the `--dir`/`--out`/`--force` options with defaults, proving the
   parser is wired into the top-level command set.
4. The output is deterministic: running the command twice (with `--force`) produces identical
   files (no timestamps), demonstrable by `diff -r` of two runs.
5. User documentation for `seihou docs` exists and its example matches real behavior.


## Idempotence and Recovery

The command is safe to re-run: with `--force` it clears and recreates the output directory, so
repeated runs converge to the same bundle. Without `--force`, it refuses to overwrite a
non-empty output directory, preventing accidental clobbering of unrelated files. If
`writeDocBundle` reports validation errors, the command exits non-zero without writing a
partial bundle is not guaranteed by okf-core (it validates before writing in `writeDocBundle`,
so nothing is written on `Left`) — confirm `writeDocBundle` returns `Left` before any write
(it does, per EP-58). Reverting the three wiring edits plus the new modules removes the command
cleanly; generated `okf-docs/` directories are disposable.


## Interfaces and Dependencies

Depends on EP-58 (`renderDocBundle`/`writeDocBundle`) and transitively EP-57 (`loadDocModel`)
and EP-56 (okf-core on the build path). Uses `optparse-applicative` (already a dependency of
the `executable seihou` target), `System.Directory`, and okf-core's `Okf.Bundle.walkBundle` +
`Okf.Validation.validateBundle` (in the test). No new package dependencies.

Artifacts that must exist at the end of this plan:

```text
seihou-cli/src/Seihou/CLI/Docs.hs                 (DocsOpts + handleDocs / runDocs)
seihou-cli/src-exe/Seihou/CLI/Commands.hs         (+ Docs constructor, docsInfo/docsParser, command "docs")
seihou-cli/src-exe/Main.hs                        (+ Docs o -> handleDocs o)
seihou-cli/seihou-cli.cabal                       (seihou-cli-internal exposed-modules: + Seihou.CLI.Docs; test other-modules: + DocsSpec)
seihou-cli/test/Seihou/CLI/DocsSpec.hs            (end-to-end test)
seihou-cli/test/Main.hs                           (+ DocsSpec in the test group)
docs/cli/ or docs/user/ (+ seihou-cli/help/)      (user documentation for `seihou docs`)
```

Relationship to other plans (see the MasterPlan's Integration Points):

- Hard dep: EP-58. Soft dep: EP-56.
- Must use the same concept-ID scheme and validation profile EP-58 established (integration
  points 3 and 4); the test asserts against them.
- Shares `seihou-cli/test/Main.hs` and the test stanza `other-modules` with EP-57 and EP-58:
  append the new spec; do not reorder existing ones.
