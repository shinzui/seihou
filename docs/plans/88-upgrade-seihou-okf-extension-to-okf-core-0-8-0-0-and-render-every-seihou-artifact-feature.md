---
id: 88
slug: upgrade-seihou-okf-extension-to-okf-core-0-8-0-0-and-render-every-seihou-artifact-feature
title: "Upgrade seihou-okf-extension to okf-core 0.8.0.0 and render every seihou artifact feature"
kind: exec-plan
created_at: 2026-09-10T17:46:15Z
intention: "intention_01m266rn1dehrrxegjwwsvvnep"
provenance:
  created_by:
    model: "claude-opus-5[1m]"
    harness: "claude-code"
    at: 2026-09-10T17:46:15Z
  revisions:
    - model: "claude-opus-5[1m]"
      harness: "claude-code"
      at: 2026-09-10T18:16:21Z
      mode: "implement"
      note: "Milestone 1: okf-core pin raised to 0.8.0.0, warning flags on, error renderers made total"
---

# Upgrade seihou-okf-extension to okf-core 0.8.0.0 and render every seihou artifact feature

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

Seihou can already turn a registry repository into a browsable documentation set. Running
`seihou-okf-extension docs --dir <registry> --out okf-docs` reads that repository's
`seihou-registry.dhall`, loads every artifact it lists, and writes one Markdown document per
artifact. That generator was written against version 0.1.2.0 of the `okf-core` library and
against an older, smaller seihou artifact vocabulary. Both have moved on: `okf-core` is now
at 0.8.0.0, and seihou artifacts now declare migrations, entailed cross-library migration
edges, removal procedures, generation steps, interactive prompts, agent launch preferences,
version probes, command-derived variables, and guidance blocks — none of which appear in the
generated documentation at all.

After this change, a person who runs the generator gets documentation that actually
describes what their registry declares, and tools that can check it. Concretely, after this
work:

- `seihou-okf-extension docs --dir /path/to/seihou-modules --out okf-docs` writes **12**
  concept documents for the current `seihou-modules` registry (7 modules, 2 recipes, 3
  blueprints), plus a bundle-root `index.md` that declares `okf_version: "0.2"` and per-kind
  section indexes.
- Every generated document carries a `generated` block naming its producer
  (`seihou-okf-extension/<version>`), so `okf trust okf-docs` reports a real trust tier for
  each concept instead of nothing.
- A module document lists the module's variables **with their types, defaults, requiredness,
  and validation rules**, its generation steps and shell commands, its interactive prompts,
  its removal procedure, and its migration edges (`from → to` with the operations each edge
  performs).
- A blueprint document lists its migration edges, and each edge that *entails* another
  blueprint's edge renders as a cross-link to that blueprint's document when it lives in the
  same registry, and as a plainly-labelled external edge when it does not. It also shows the
  blueprint's agent launch preferences and its version-probe command.
- A prompt document lists its command-derived variables and guidance blocks.
- `okf validate okf-docs --strict` passes, and so does
  `okf validate okf-docs --strict --profile okf-docs/profile.dhall --profile-enforce`,
  because the generator writes a house profile beside the bundle and enforces it in-process
  before writing anything.
- `okf concepts okf-docs --filter type=SeihouBlueprint` and
  `okf concepts okf-docs --filter tags=migration` select documents, because the frontmatter
  now carries the vocabulary those filters need.

The failure this prevents is quiet documentation drift: a registry author adds a migration
edge or a launch preference, regenerates the docs, and the new declaration silently does not
appear. Today `docs/cli/okf-docs.md` even tells the reader the command writes 8 concepts for
`seihou-modules`, which stopped being true when the registry grew.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] M1: `okf-core` pin raised from 0.1.2.0 to 0.8.0.0 in `seihou-okf-extension/seihou-okf-extension.cabal` and `nix/haskell-overlay.nix` (2026-09-10). Generated output verified byte-identical before and after the upgrade against the `seihou-modules` registry (12 concepts, `diff -r` clean).
- [x] M1: `-Wall -Werror=incomplete-patterns` added to the extension's library, executable, and test stanzas; the three warnings `-Wall` surfaced in existing code are fixed, and `renderValidationError`, `renderBundleValidationError`, and the new `renderLogValidationError` are total with no catch-all (2026-09-10).
- [x] M2: bundle declares OKF v0.2 at its root, writes section indexes, stamps `generated` provenance on every concept, and validates with `StrictAuthoring` (2026-09-10). Against `seihou-modules`: `okf validate --strict` exits 0 reporting `OK: 12 concepts (okf_version 0.2)`, `okf trust` lists `unverified stable ok` for all 12, and two consecutive runs are byte-identical.
- [x] M3: `renderExpr` added to `Seihou.Core.Expr` with round-trip tests (2026-09-10). `Seihou.Core.ExprSpec` asserts `parseExpr . renderExpr == Right` over 25 hand-written expressions covering every `Expr` constructor, both associations of `&&` and `||`, `!` over each, and text values that are empty, contain a delimiter, or spell a keyword.
- [x] M3: module documents render variables in full, steps, commands, prompts, removal, and migrations (2026-09-10). Against `seihou-modules`, all 7 module documents carry `## Generation steps`; 1 carries `## Migrations`, 2 carry `## Removal`, 1 carries `## Commands` — which is exactly what those `.dhall` sources declare.
- [x] M3: blueprint documents render migrations with entailment cross-links, launch preferences, version probe, variables, and prompts (2026-09-10). No real registry declares entailment, a launch block, or a version probe, so the proof is the `richModel` fixture in `seihou-okf-extension/test/Seihou/OKF/Docs/RenderSpec.hs`; see Validation and Acceptance for the named assertions.
- [x] M3: recipe documents render supplied variable bindings and prompts; prompt documents render command variables, guidance, and launch preferences (2026-09-10). Also adds the registry overview concept the plan asks for, which gives `okf graph` a root: 13 concepts for `seihou-modules`, 14 for `agent-seihou`.
- [ ] M4: house profile descriptor authored, written beside the bundle, and enforced in-process.
- [ ] M5: `docs/cli/okf-docs.md`, `docs/user/`, `CHANGELOG.md`, and `docs/user/CHANGELOG.md` updated; end-to-end run recorded against `seihou-modules` and `agent-seihou`.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- **`cabal test all` does not resolve a build plan in this working tree; `cabal test all
  --enable-tests` does.** Running the plan's documented command fails with

    ```text
    Error: [Cabal-7043]
    Cannot test all the packages in the project because none of the components are
    available to build: the test suite 'seihou-cli-test', the test suite
    'seihou-core-test' and the test suite 'seihou-okf-extension-test' are not
    available because the solver picked a plan that does not include the test suites
    ```

    This is **not** caused by the okf-core upgrade: `git stash`ing every change in this
    plan and re-running `cabal test all --dry-run` reproduces it identically on the clean
    tree at `d83433e`. Adding `--enable-tests` makes the solver find a plan, so the
    working command throughout this plan is:

    ```bash
    cabal test all --enable-tests
    ```

    The alternative fix is a `cabal.project.local` carrying `tests: True`, which the error
    message itself suggests; that file is not checked in and this plan does not add it.

- **`BundleValidationError` also gained constructors, not just `ValidationError`.** Context
  and Orientation lists the twelve new `ValidationError` constructors but says
  `validateBundle`'s signature change "is the only" compile error. In fact
  `Okf.Validation.BundleValidationError` went from three constructors in 0.1.2.0 to seven
  in 0.8.0.0, adding `DanglingFrontmatterPath`, `LogInvalid`, `BundleVersionUnparseable`,
  and `BundleVersionNotUnderstood`. `LogInvalid` carries an `Okf.Log.LogValidationError`,
  so a third total renderer (`renderLogValidationError`, over `LogDateNotIso`,
  `LogDaysOutOfOrder`, `LogEmptyDay`) was needed as well. All three renderers now live in
  `seihou-okf-extension/src/Seihou/OKF/Extension/Docs.hs` with no catch-all branch.

- **The test suite had its own two-argument `validateBundle` call.**
  `seihou-okf-extension/test/Seihou/OKF/Extension/DocsSpec.hs` calls `validateBundle`
  directly on a walked bundle, so the signature change broke the tests as well as the
  library. It now passes `VersionUndeclared` and `bundleInventoryOfConcepts`, matching the
  library call site.

- **`seihou-modules` exercises only some of the features milestone 3 adds.** Grepping the
  registry's `.dhall` sources: `migrations` appears in 4 files and `removal` in 3, but
  `launch`, `versionProbe`, `entails`, `guidance`, and `commandVars` appear in none.
  `/Users/shinzui/Keikaku/bokuno/agent-seihou` covers `launch` (1), `guidance` (2), and
  `commandVars` (1) but still not `versionProbe` or `entails`. Neither real registry
  declares an entailed edge or a version probe, so for those two sections the milestone 3
  unit-test fixtures are the only proof, exactly as Validation and Acceptance anticipates.


## Decision Log

Record every decision made while working on the plan.

- Decision: Upgrade straight from `okf-core` 0.1.2.0 to 0.8.0.0 rather than stepping through
  the intermediate releases.
  Rationale: the extension uses a small, stable slice of the okf-core API (document
  construction, concept construction, bundle writing, bundle validation, concept-ID
  rendering). Only one of those changed shape across the seven releases — `validateBundle`
  gained two parameters — and the error type it returns gained constructors. Stepping
  through 0.2, 0.3, 0.4, 0.5, 0.6, 0.7 would mean six build-and-test cycles to discover the
  same two facts.
  Date: 2026-09-10

- Decision: Keep this plan standalone rather than adding it as a sixth child of
  `docs/masterplans/7-generate-okf-documentation-bundles-for-seihou-registries.md`.
  Rationale: that MasterPlan is marked Complete and all five of its children are Complete.
  This work is maintenance and extension of a delivered capability, not a new milestone of
  the original initiative. The plan cites the MasterPlan for context instead.
  Date: 2026-09-10

- Decision: Stamp `generated.by` but leave `generated.at` unset unless the operator passes
  `--generated-at`.
  Rationale: OKF specification §5.2 marks only `by` required inside the `generated` mapping,
  and okf-core deliberately never reads the clock. Reading the clock in the generator would
  make every regeneration produce a different bundle, which breaks both idempotence (see
  Idempotence and Recovery) and golden-file tests. An operator who wants a date can supply
  one explicitly, which is also what a CI job that stamps a release date wants.
  Date: 2026-09-10

- Decision: Validate with `StrictAuthoring` by default and keep `--permissive` as an escape
  hatch, rather than keeping `PermissiveConformance` as the default.
  Rationale: strict mode requires a non-empty `title`, a non-empty `description`, and a
  `generated` block with an actor. The generator controls all three. `title` is the artifact
  name, `generated` is stamped by milestone 2, and `description` gets a deterministic
  three-step fallback (registry entry description, then the artifact's own description, then
  a synthesized one-liner). Generating documentation that its own format's strict checker
  rejects is a defect the generator can simply not have.
  Date: 2026-09-10

- Decision: Render an entailed migration edge that names a blueprint outside the current
  registry as plain labelled text, not as a link.
  Rationale: okf-core's `validateBundle` reports a `DanglingReference` for a cross-link
  whose target concept is not in the bundle, and the generator treats validation errors as
  fatal. A `keiro-upgrade` blueprint may legitimately entail a `kiroku` edge that lives in a
  different repository entirely; that is the whole point of entailment
  ([ADR 0008](../adr/0008-an-entailed-migration-edge-is-owned-by-the-blueprint-that-declares-it.md)).
  Refusing to generate documentation for such a registry would be wrong.
  Date: 2026-09-10

- Decision: Add `renderExpr` to `Seihou.Core.Expr` (in `seihou-core`) rather than writing a
  private copy inside the extension.
  Rationale: `Seihou.Core.Types.Expr` is parsed out of Dhall text by
  `Seihou.Core.Expr.parseExpr` and the original text is not retained anywhere, so any
  consumer that wants to display a condition needs a renderer. `seihou-core` already owns
  the parser and the AST; the renderer belongs beside them, and other surfaces (`seihou
  vars`, `seihou status`) can use it later.
  Date: 2026-09-10


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose. Before marking the plan complete,
distill durable project context from the Decision Log, Surprises & Discoveries, and
this section into docs/adr/. Keep task-local execution details here.

(To be filled during and after implementation.)


## Context and Orientation

### What this repository is

Seihou is a project-scaffolding system written in Haskell. A **module** is a deterministic
file-generation template: a Dhall file named `module.dhall` declaring variables, generation
steps, shell commands, dependencies on other modules, an optional removal procedure, and
optional migration edges. A **recipe** (`recipe.dhall`) is a named composition of modules
with preset variable bindings. A **blueprint** (`blueprint.dhall`) is an agent-driven
scaffold: a prompt, optional base modules, reference files, and optional agent-guided
migration edges. A **prompt** (`prompt.dhall`, the Haskell type is `AgentPrompt`) is a
reusable agent-session template. A **registry** is a repository whose root holds
`seihou-registry.dhall`, listing the modules, recipes, blueprints, and prompts that
repository publishes, each with a name, optional version, path, optional description, and
tags.

The repository is a three-package Cabal workspace declared in `cabal.project`:

- `seihou-core/` — the library: Dhall evaluation, types, composition, execution.
- `seihou-cli/` — the `seihou` executable (library at `seihou-cli/src/`, executable at
  `seihou-cli/src-exe/`).
- `seihou-okf-extension/` — the package this plan changes.

### What the extension does today

`seihou-okf-extension` is a separate executable, deliberately kept out of the main CLI so
that documentation-rendering dependencies never enter `seihou-core` or `seihou-cli`. The main
CLI can still invoke it: `seihou extension run okf -- docs --dir . --out okf-docs` resolves
the executable `seihou-okf-extension` on `PATH` and forwards everything after `--` to it.
That host lives in `seihou-cli/src/Seihou/CLI/Extension.hs`, and `seihou-cli/src-exe/Main.hs`
detects the `extension run NAME -- ...` shape from raw arguments before normal option parsing
so that the forwarded arguments survive.

The extension has four modules:

- `seihou-okf-extension/src/Seihou/OKF/Docs/Model.hs` — reads `seihou-registry.dhall` via
  `Seihou.Dhall.Eval.evalRegistryFromFile`, then loads each listed artifact with
  `evalModuleFromFile`, `evalRecipeFromFile`, `evalBlueprintFromFile`, and
  `evalAgentPromptFromFile`. It produces a `DocModel` holding `DocEntry` values. Each
  `DocEntry` pairs the registry's catalog metadata (`name`, `version`, `description`, `tags`,
  `path`) with the fully loaded artifact (`DocArtifact`) and a list of `ModuleRef` values —
  module names referenced by that entry, each flagged `resolved` if a module of that name is
  listed in the same registry.
- `seihou-okf-extension/src/Seihou/OKF/Docs/Render.hs` — turns the `DocModel` into okf-core
  `Concept` values, validates them, and writes them.
- `seihou-okf-extension/src/Seihou/OKF/Extension/Docs.hs` — the `docs` command: checks the
  output directory, loads, renders, validates, writes, and reports.
- `seihou-okf-extension/src/Seihou/OKF/Extension.hs` — the `optparse-applicative` command
  line and `runExtensionMain`.

Tests live in `seihou-okf-extension/test/` (`Seihou/OKF/Docs/ModelSpec.hs`,
`Seihou/OKF/Docs/RenderSpec.hs`, `Seihou/OKF/Extension/DocsSpec.hs`), driven by
`tasty`+`tasty-hspec` from `seihou-okf-extension/test/Main.hs`. They build fixture registries
in temporary directories by writing raw Dhall text, so they run offline with no remote schema
imports.

The original delivery is recorded in
`docs/masterplans/7-generate-okf-documentation-bundles-for-seihou-registries.md` and its five
child plans, `docs/plans/56-*.md` through `docs/plans/60-*.md`. They are checked in; read
them only if you need the history. Everything this plan relies on is restated here.

### What OKF is

**OKF** is the Open Knowledge Format: a directory tree ("bundle") of Markdown files, each
beginning with **frontmatter** — a block of YAML metadata fenced by `---` lines — followed by
Markdown prose. One such file is a **concept**. A concept's identity is its **concept ID**,
derived from its path within the bundle, for example `modules/haskell-library`. Links between
concepts are ordinary Markdown links that okf-core knows how to resolve, which makes the
bundle a navigable graph. `index.md` and `log.md` are reserved filenames and are not
concepts.

OKF is implemented by the `okf-core` Haskell library, published on Hackage and developed in
`mori://shinzui/okf`. The `okf` command-line tool from the same project validates, indexes,
graphs, and queries bundles; it is already installed on this machine (`okf --version` prints
`okf v0.8.0.0`).

The extension currently depends on `okf-core ^>=0.1.2.0` and uses this slice of it:

- `Okf.Document` — `OKFDocument(..)`, `Frontmatter`, `emptyFrontmatter`, `okfCommon`,
  `OkfCommon(..)`, `setTags`, `setResource`, `setField`, `serializeDocument`.
- `Okf.Bundle` — `Concept`, `conceptFromDocument`, `writeBundle`.
- `Okf.ConceptId` — `ConceptId`, `parseConceptId`, `renderConceptId`, `renderConceptLink`.
- `Okf.Validation` — `validateBundle`, `ValidationProfile(..)`, `BundleValidationError(..)`,
  `ValidationError(..)`.

### What changed in okf-core between 0.1.2.0 and 0.8.0.0

Read `okf-core`'s own changelog at
`/Users/shinzui/Keikaku/bokuno/okf/okf-core/CHANGELOG.md` if you want the full history. Only
these facts matter for this work, and they were verified by reading the 0.8.0.0 sources at
`/Users/shinzui/Keikaku/bokuno/okf/okf-core/src/Okf/`:

1. **`validateBundle` gained two parameters.** It is now

    ```haskell
    validateBundle
      :: ValidationProfile
      -> VersionDeclaration
      -> BundleInventory
      -> [Concept]
      -> [BundleValidationError]
    ```

    `VersionDeclaration` comes from `Okf.Index` and is one of `VersionDeclared OkfVersion`,
    `VersionUndeclared`, or `VersionUnparseable Text`. It says which OKF version the bundle's
    root `index.md` declares. `BundleInventory` comes from `Okf.Bundle`; for a bundle you are
    generating in memory, build it with `bundleInventoryOfConcepts concepts`. This is a
    compile error the moment the pin moves, and it is the only one.

2. **`ValidationError` gained many constructors.** 0.1.2.0 had three
   (`MissingRequiredField`, `FieldMustBeNonEmptyText`, `MissingRecommendedField`). 0.8.0.0
   adds `FieldMustBeListOfText`, `MissingGeneratedField`, `GeneratedMustHaveActor`,
   `SourceMissingResource`, `DuplicateSourceId`, `FootnoteLabelNotInSources`,
   `SourceIdNotCited`, `LegacyFieldInDeclaredV2`, `AttestedComputationMissingRuntime`,
   `AttestedComputationHasNoComputation`, `AttestedComputationHasBothComputations`, and
   `AttestedComputationHasManyBlocks`. The extension's `renderValidationError` in
   `seihou-okf-extension/src/Seihou/OKF/Extension/Docs.hs` pattern-matches on the three old
   constructors and has no catch-all. **The extension's Cabal stanzas set no `ghc-options` at
   all**, so GHC will not even warn: the upgrade would compile and then crash at runtime with
   a pattern-match failure the first time a new error was reported. Milestone 1 fixes both
   the renderer and the missing warning flags.

3. **OKF v0.2 semantics arrived** (okf-core 0.5.0.0). The parts this plan uses:
    - `Okf.Document.Generated { generatedBy :: Actor, generatedAt :: Maybe Text }` with
      `setGenerated`. `Okf.Actor.Actor` has four shapes; the relevant one is
      `ProducerActor "<producer>" "<version>"`, which renders as `<producer>/<version>`.
    - `Okf.Document.setStatus`, `setSources`, `setStaleAfter` for the lifecycle and
      provenance families. This plan uses `setStatus` and leaves the rest alone.
    - `Okf.Index.OkfVersion`, `VersionDeclaration`, `supportedOkfVersion` (currently 0.2),
      `renderRootIndex`, `writeBundleIndexes`, and
      `writeBundleIndexesWith :: Maybe OkfVersion -> FilePath -> IO (Either BundleError ())`.
      The root `index.md` is the one index permitted to carry frontmatter and the one place a
      bundle declares its version.
    - Strict authoring rules: `validateDocument StrictAuthoring` requires a non-empty `title`
      and `description`, and a `generated` mapping carrying an actor.

4. **Profiles arrived** (`Okf.Profile`, extended through 0.8.0.0). A **profile** is a house
   convention — not part of the OKF standard — authored as a Dhall descriptor and checked
   against a bundle. The API this plan uses:

    ```haskell
    loadProfileFile  :: FilePath -> IO (Either Text ProfileSpec)
    compileProfile   :: ProfileSpec -> Either (NonEmpty ProfileDefinitionError) CompiledProfile
    validateProfile  :: ValidationProfile -> CompiledProfile -> [Concept] -> [ProfileViolation]
    validateProfileVersion :: VersionDeclaration -> CompiledProfile -> [ProfileViolation]
    ```

    Note that `renderProfileViolation` lives in the `okf-cli` package, **not** in `okf-core`,
    so the extension must render `ProfileViolation` values itself.

5. **`Okf.Query` arrived** (0.6.0.0) and powers `okf concepts --filter KEY=VALUE`. Nothing in
   the extension needs to call it; it is listed because milestone 5 demonstrates it against
   the generated bundle.

Everything else the extension calls — `okfCommon`, `setTags`, `setResource`, `setField`,
`conceptFromDocument`, `writeBundle`, `parseConceptId`, `renderConceptLink`,
`renderConceptId`, `serializeDocument`, `emptyFrontmatter` — has the same name and the same
signature in 0.8.0.0 as in 0.1.2.0.

### How okf-core is pinned in this repository

Two independent mechanisms, and both must move together:

- **Cabal**: `seihou-okf-extension/seihou-okf-extension.cabal` names `okf-core ^>=0.1.2.0` in
  the library and test-suite `build-depends`. There is no `source-repository-package` for
  okf-core in `cabal.project`; it resolves from Hackage.
- **Nix**: `nix/haskell-overlay.nix` pins it explicitly:

    ```nix
    okf-core = dontCheck (hackagePackage "okf-core" "0.1.2.0"
      "sha256-p2LC8DDdqeLnlQn/n8jBL6tt6Iid+bPK15zBRwIOnJg=");
    ```

    `hackagePackage` is a local helper in that file wrapping `callHackageDirect` in
    `doJailbreak`. The comment above the pin says okf-core "is not registered" in the shared
    `haskell-nix` registry overlay. That comment is now out of date — `flake.lock` shows the
    `haskell-nix` input carries an `okf-src` input — but the registry's pinned revision is
    `18bcd46`, which is okf **0.2.0.0**. So the local Hackage pin is still the right
    mechanism and must simply be raised; do not delete it in the hope that the registry
    supplies 0.8.0.0, because it does not.

The exact values needed for the new pin were computed while writing this plan:

```text
version: 0.8.0.0
sri:     sha256-ADugvEouY5r+o1W0K09M7IX0GTVuZ1OXvA+Vem/QnBI=
```

Two notes on the pin. First, the existing comment explains `dontCheck` by saying the 0.1.2.0
sdist omits `dhall/` and `test/fixtures/`; the 0.8.0.0 sdist declares both under
`extra-source-files` and does ship them, so that specific justification no longer holds —
keep `dontCheck` anyway (this repository does not need to run a dependency's test suite) but
correct the comment. Second, okf-core 0.8.0.0 pulls in more dependencies than 0.1.2.0:
`cmark-gfm ^>=0.2`, `regex-tdfa`, `network-uri`, `frontmatter`, `attoparsec`, `yaml`,
`vector`, and `time`. The okf project itself builds on the same GHC 9.12.4 nixpkgs package
set with **no overrides for any of them** (see
`/Users/shinzui/Keikaku/bokuno/okf/nix/haskell.nix`, which overrides only `unicode-data`,
`streamly*`, `openai`, `cradle`, and the `baikai` family), so no new overlay entries are
expected here. If one of them turns out to be marked broken in this repository's package set,
the fix is the same `markUnbroken`/`doJailbreak` pattern that file already uses.

### The seihou artifact features the documentation does not show

These are the Haskell record fields in `seihou-core/src/Seihou/Core/Types.hs` and
`seihou-core/src/Seihou/Core/Migration.hs`. Everything marked "not rendered" is what
milestone 3 adds.

`Module` has `name`, `version`, `description`, `vars`, `exports`, `prompts` (not rendered),
`steps` (not rendered), `commands` (not rendered), `dependencies`, `removal` (not rendered),
and `migrations` (not rendered). Of these, `vars` is rendered as a bare bullet list of names
with `(required)` — the declared type, default, description, and validation rule are all
dropped.

`VarDecl` is `{ name, type_ :: VarType, default_ :: Maybe VarValue, description, required,
validation :: Maybe Validation }`. `VarType` is `VTText | VTBool | VTInt | VTList VarType |
VTChoice [Text]`. `Validation` is `ValPattern Text | ValRange Int Int | ValMinLength Int |
ValMaxLength Int`. `VarExport` is `{ var, alias :: Maybe VarName }`; the alias is dropped
today.

`Step` is `{ strategy :: Strategy, src, dest, condition :: Maybe Expr, patch :: Maybe PatchOp }`.
`Strategy` is `Copy | Template | DhallText | Structured` — the four generation strategies.
`PatchOp` is `AppendFile | PrependFile | AppendSection | AppendLineIfAbsent`, used when a step
contributes to a file another module owns rather than writing its own.

`Command` is `{ run :: Text, workDir :: Maybe Text, condition :: Maybe Expr }`.

`Removal` is `{ steps :: [RemovalStep], commands :: [Command] }`, and `RemovalStep` is
`{ action :: RemovalAction, dest, src :: Maybe FilePath }` where `RemovalAction` is
`RemoveFileAction | RemoveSectionAction | RewriteFileAction`.

`Migration` (module migrations) is `{ from :: Text, to :: Text, ops :: [MigrationOp] }`, and
`MigrationOp` is `MoveFile {src,dest} | MoveDir {src,dest} | DeleteFile {path} |
DeleteDir {path} | RunCommand {run, workDir}`.

`Recipe` has `name`, `version`, `description`, `modules :: [Dependency]`, `vars` (not
rendered), and `prompts` (not rendered). A `Dependency` is
`{ module_ :: ModuleName, vars :: Map VarName Text }` — the `vars` are the bindings the
composing artifact supplies along that edge, and they are dropped today, so a reader cannot
see what a recipe actually preconfigures.

`Blueprint` has `name`, `version`, `description`, `prompt`, `vars` (not rendered), `prompts`
(not rendered), `baseModules`, `files`, `allowedTools` (not rendered — only `AgentPrompt`'s
copy is), `tags`, `migrations :: [BlueprintMigration]` (not rendered), `launch :: Maybe
AgentLaunch` (not rendered), and `versionProbe :: Maybe Text` (not rendered).

`BlueprintMigration` is `{ from :: Text, to :: Text, prompt :: Text, entails :: [EntailedEdge] }`
and `EntailedEdge` is `{ blueprint :: Text, from :: Text, to :: Text }`. Entailment is how a
breaking change reaches a consumer through an intermediary library: a blueprint for `keiro`
declares that crossing its own `2.4.0 -> 3.0.0` edge entails crossing `kiroku`'s
`1.9.0 -> 2.0.0` edge, so a project that depends on `keiro` and has never heard of `kiroku`
still gets `kiroku`'s upgrade guidance in `kiroku`'s own version space.

`AgentLaunch` is `{ provider, model, effort, mode :: Maybe Text }` — the agent provider and
model a blueprint or prompt prefers, overriding the user's configuration but losing to
explicit flags and `SEIHOU_AGENT_*` environment variables.

`AgentPrompt` has `name`, `version`, `description`, `prompt`, `vars` (not rendered), `prompts`
(not rendered), `commandVars :: [CommandVar]` (not rendered), `guidance :: [PromptGuidance]`
(not rendered), `files`, `allowedTools`, `tags`, and `launch` (not rendered). `CommandVar` is
`{ name, run, workDir, condition, trim :: Bool, maxBytes :: Maybe Natural }` — a variable
whose value comes from running a local command. `PromptGuidance` is
`{ title, body, condition }` — a Markdown instruction block attached conditionally.

`Prompt` (the interactive kind, not `AgentPrompt`) is
`{ var :: VarName, text :: Text, condition :: Maybe Expr, choices :: Maybe [Text] }`.

One gap the implementer must close: `Expr` (used by every `condition` field) is parsed from
Dhall text by `Seihou.Core.Expr.parseExpr` and **the original text is not kept**. That module
exports only `parseExpr`; there is no renderer anywhere in the repository (verified by
grepping for `renderExpr` and `exprToText` across `seihou-core/src` and `seihou-cli/src`). To
display a condition, milestone 3 adds one.

### Relevant ADRs

Following the ADR workflow in `.claude/skills/exec-plan/ADR.md`: `docs/adr/` in this
repository is a **plain filesystem convention** — nine files named `NNNN-<slug>.md`, each
starting with a `# ADR NNNN — <title>` heading and `- Status:` / `- Date:` lines, with no OKF
frontmatter. `mori.dhall` at the repository root declares exactly one OKF bundle, and its
path is `docs/improvement-requests`, not `docs/adr`. So the ADR corpus here is **not** a
profile-governed OKF bundle, and per `ADR.md` you must preserve the existing convention: do
not add OKF frontmatter or `docId` values to `docs/adr/` as part of this work.

Two existing ADRs bear on this plan:

- [ADR 0008 — an entailed migration edge is owned by the blueprint that declares it](../adr/0008-an-entailed-migration-edge-is-owned-by-the-blueprint-that-declares-it.md).
  An entailed edge belongs to the declaring blueprint, and the entailed blueprint may live in
  a different repository entirely. This is why milestone 3 renders an out-of-registry
  entailed edge as labelled text rather than as a cross-link that would fail bundle
  validation.
- [ADR 0009 — Seihou reads no package-manager format; the artifact declares the command](../adr/0009-seihou-reads-no-package-manager-format-artifacts-declare-the-command.md).
  This is why `Blueprint.versionProbe` exists at all: seihou refuses to parse Cabal, npm,
  Cargo, or Maven files, so the blueprint author declares a shell command that prints the
  currently-declared version. Documenting the probe command is therefore documenting a
  user-visible contract, not an implementation detail.

No existing ADR covers documentation generation, OKF bundle conventions, or the extension
boundary. If milestone 4's house profile settles a durable convention (which frontmatter keys
a seihou documentation bundle must carry), that is a candidate for a new ADR during the
distillation pass; see Outcomes & Retrospective.

`docs/improvement-requests/` is a profiled OKF bundle in this same repository and is a useful
worked example of how a profile is pinned here — `docs/improvement-requests/profile.dhall` is
three lines that import `Profiles.coordination.improvementRequests` from a tagged, hashed
`okf-profiles` release. Milestone 4 follows the same shape but with a locally-authored
descriptor, because the shared `okf-profiles` catalogue
(`/Users/shinzui/Keikaku/bokuno/okf-profiles/profiles/`) has no profile for generated
scaffolding-registry documentation: it ships `documentation` (architecture decisions, pattern
catalog, research documents, user documentation), `coordination` (bug reports, capabilities,
improvement requests, use cases), `assurance` (failure modes, reviews), plus PostgreSQL
profiles.

### Environment and commands

Build and test from the repository root, `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`:

```bash
cabal build all
cabal test all
```

A `justfile` wraps these as `just build`, `just test`, `just check` (`nix flake check`), and
`just format` (`nix fmt`). If your shell has no GHC, enter the development shell first with
`nix develop`. The `okf` CLI is already on `PATH` at version 0.8.0.0.

Two mechanical checks run in `nix flake check` and in the pre-commit hook, and both apply to
code you write here:

- `nix/check-record-conventions.sh` — records use strict fields, an explicit deriving
  strategy, and `Generic`; fields are read and written through `generic-lens` overloaded
  labels (`entry ^. #name`, `entry & #kind .~ v`), never with record-dot or record-update
  syntax. Every module using `#label` imports `Data.Generics.Labels ()` itself.
- `nix/check-cli-module-placement.sh` — governs `seihou-cli` only; it does not constrain the
  extension package.


## Plan of Work

The work is five milestones. Milestone 1 is a pure dependency upgrade that changes no output.
Milestone 2 changes the bundle's shape but not what each document says about an artifact.
Milestone 3 is the bulk of the content work. Milestone 4 adds enforcement. Milestone 5 makes
it all visible to users. Each milestone ends with a green `cabal test all` and a commit.

Every commit in this plan carries both trailers:

```text
ExecPlan: docs/plans/88-upgrade-seihou-okf-extension-to-okf-core-0-8-0-0-and-render-every-seihou-artifact-feature.md
Intention: intention_01m266rn1dehrrxegjwwsvvnep
```

### Milestone 1 — Build against okf-core 0.8.0.0 with no change in output

Scope: raise both pins, fix the one compile error, make the error renderer total, and turn on
warnings so the next such gap is a build failure. At the end of this milestone the generator
produces byte-identical output to what it produced before, but against a library seven major
releases newer.

Edit `seihou-okf-extension/seihou-okf-extension.cabal`. Change `okf-core ^>=0.1.2.0` to
`okf-core ^>=0.8.0.0` in both the `library seihou-okf-extension-internal` and
`test-suite seihou-okf-extension-test` `build-depends` lists. Add to all three stanzas
(library, executable, test-suite):

```cabal
  ghc-options: -Wall -Werror=incomplete-patterns
```

The executable stanza already has `ghc-options: -threaded`; extend that line rather than
adding a second one. Expect `-Wall` to surface unused-import and name-shadowing warnings in
existing code; fix them, and do not add `-Werror` in general — only the incomplete-patterns
promotion, because that is the specific class of bug this upgrade would otherwise have
introduced silently.

Edit `nix/haskell-overlay.nix`. Replace the `okf-core` pin with

```nix
  # okf-core is not carried by the shared haskell-nix registry overlay at a
  # usable revision (its okf-src input sits at okf 0.2.0.0), so pin the
  # published Hackage release directly.
  #
  # dontCheck: this repository has no reason to run a dependency's own test
  # suite on every build.
  okf-core = dontCheck (hackagePackage "okf-core" "0.8.0.0"
    "sha256-ADugvEouY5r+o1W0K09M7IX0GTVuZ1OXvA+Vem/QnBI=");
```

Edit `seihou-okf-extension/src/Seihou/OKF/Docs/Render.hs`. `renderDocBundle` calls
`validateBundle PermissiveConformance concepts`; that call now needs four arguments. For this
milestone keep the behavior identical by declaring nothing:

```haskell
import Okf.Bundle (Concept, bundleInventoryOfConcepts, conceptFromDocument, writeBundle)
import Okf.Index (VersionDeclaration (..))

      Right (concepts, validateBundle PermissiveConformance VersionUndeclared (bundleInventoryOfConcepts concepts) concepts)
```

`VersionUndeclared` is exactly what the old two-argument call assumed: the bundle's root
`index.md` declares no version. Milestone 2 changes it.

Edit `seihou-okf-extension/src/Seihou/OKF/Extension/Docs.hs`. Extend `renderValidationError`
to cover every constructor of `Okf.Validation.ValidationError` listed in Context and
Orientation. Write one branch per constructor with a message a registry author can act on;
for example `MissingGeneratedField` becomes
`"concept records neither a generated block nor a legacy timestamp"`. Do **not** add a
catch-all `_ ->` branch: the point of `-Werror=incomplete-patterns` is that the next okf-core
upgrade fails the build here instead of at runtime.

Acceptance: `cabal build all` succeeds; `cabal test all` passes with the existing 15 tests
unchanged; generating a bundle from `seihou-modules` produces the same files as before the
upgrade (compare with `git diff --no-index` against a bundle generated from the pre-upgrade
binary, or simply confirm the tests that assert on rendered output still pass unmodified);
`nix build .#seihou-okf-extension` succeeds.

### Milestone 2 — Emit an OKF v0.2 bundle with provenance and strict validation

Scope: the bundle gains a root `index.md` declaring `okf_version: "0.2"`, per-kind section
indexes, a `generated` block on every concept, a `status` field, and strict validation. At the
end of this milestone `okf validate okf-docs --strict` passes and `okf trust okf-docs`
reports a tier for every concept.

In `seihou-okf-extension/src/Seihou/OKF/Docs/Render.hs`:

- Add a `RenderOptions` record — strict fields, `Generic`, read through `generic-lens` labels
  per the repository record conventions — carrying `producerVersion :: Text`,
  `generatedAt :: Maybe Text`, and `validationProfile :: ValidationProfile`. Thread it through
  `renderDocBundle` and `writeDocBundle`.
- In `frontmatterFor`, add `Okf.Document.setGenerated (Generated (ProducerActor "seihou-okf-extension" (opts ^. #producerVersion)) (opts ^. #generatedAt))`
  and `Okf.Document.setStatus` with the stable status. Import `Okf.Actor (Actor (..))`.
- Change the description fallback so strict validation can never fail on a missing
  description: use the registry entry's `description` if present; otherwise the artifact's own
  `description` (each of `Module`, `Recipe`, `Blueprint`, and `AgentPrompt` has one);
  otherwise a synthesized sentence such as
  `"Seihou module `<name>` published by the `<repoName>` registry."` — chosen by kind so it
  reads correctly for recipes, blueprints, and prompts too. Set the same value in frontmatter
  and in the body's opening paragraph so the two never disagree.
- Change `validateBundle`'s version argument to `VersionDeclared supportedOkfVersion` and its
  profile argument to `opts ^. #validationProfile`.
- After `writeBundle`, call
  `Okf.Index.writeBundleIndexesWith (Just supportedOkfVersion) outDir`. This walks the
  just-written bundle and writes the root `index.md` (with the version declaration in
  frontmatter) plus one `index.md` per subdirectory. Surface its `Left BundleError` as a new
  `DocBundleError` constructor rather than ignoring it.

The producer version string should come from Cabal rather than a hand-maintained literal. Add
to the library stanza:

```cabal
  other-modules:      Paths_seihou_okf_extension
  autogen-modules:    Paths_seihou_okf_extension
```

and read it with `Data.Version.showVersion Paths_seihou_okf_extension.version`. If that proves
awkward in the test suite (which does not build the executable), define a single
`extensionVersion :: Text` in `Seihou.OKF.Extension` and let tests import it.

In `seihou-okf-extension/src/Seihou/OKF/Extension.hs` and
`seihou-okf-extension/src/Seihou/OKF/Extension/Docs.hs`, add two options to the `docs`
command:

- `--generated-at DATE` — optional; the value goes verbatim into `generated.at`. No parsing,
  no clock reading. The help text should say "ISO-8601 date or timestamp recorded as the
  generation time; omitted by default so regeneration is byte-stable".
- `--permissive` — validate with `PermissiveConformance` instead of the new default
  `StrictAuthoring`.

Tests: extend `seihou-okf-extension/test/Seihou/OKF/Docs/RenderSpec.hs` with cases asserting
that every rendered concept's frontmatter carries `generated.by` equal to
`seihou-okf-extension/<version>`, that `--generated-at` lands in `generated.at`, that omitting
it leaves `at` absent, and that `renderDocBundle` with `StrictAuthoring` reports no errors for
a fixture entry that has no description anywhere. Extend
`seihou-okf-extension/test/Seihou/OKF/Extension/DocsSpec.hs` to assert the written bundle
contains `index.md` at its root and that the file contains `okf_version: "0.2"`.

Acceptance: `cabal test all` passes; generating from `seihou-modules` and running
`okf validate okf-docs --strict` exits 0; `okf trust okf-docs` lists every concept with a
tier; `head -5 okf-docs/index.md` shows the version declaration.

### Milestone 3 — Render every seihou artifact feature

Scope: the body of each generated document grows to cover everything the artifact declares.
This is where the plan's title is earned. At the end of this milestone, a reader of the
generated documentation can see every field listed in Context and Orientation under "The
seihou artifact features the documentation does not show".

First, the prerequisite in `seihou-core`. Add to `seihou-core/src/Seihou/Core/Expr.hs`:

```haskell
renderExpr :: Expr -> Text
```

It must be the inverse of `parseExpr` for every expression `parseExpr` can produce:
`ExprEq` renders as `Eq <var> <value>`, `ExprIsSet` as `IsSet <var>`, `ExprNot` as
`!<expr>`, `ExprAnd` as `<l> && <r>`, `ExprOr` as `<l> || <r>`, and `ExprLit` as `true` /
`false`. Parenthesize sub-expressions where precedence requires it — read the parser in that
same file to get its precedence and operator spellings exactly right rather than assuming.
Add a test module (or extend the existing `Seihou.Core.ExprSpec` if there is one under
`seihou-core/test/`) asserting `parseExpr . renderExpr == Right` on a list of hand-written
expressions covering every constructor and at least two nesting levels. Export `renderExpr`
from the module's export list.

Then, in `seihou-okf-extension/src/Seihou/OKF/Docs/Render.hs`, rewrite `kindSections` and add
the rendering helpers below. Keep every helper total and deterministic — no clock, no
filesystem, no ordering that depends on a `Map`'s internal layout (sort `Map` contents by key
before rendering). Each section is omitted entirely when the artifact declares nothing for it,
except the sections that already exist today, which keep their "no X declared" sentence so
existing tests and reader expectations hold.

For a **module**, the body becomes: description paragraph; `**Version:**`; `## Dependencies`
(as today, but each dependency that supplies variable bindings shows them as
`` `name` (with `var` = `value`, ...) ``); `## Variables` where each declaration renders as
`` - `name` — <type>, required|optional, default `<value>`, matching `<pattern>` `` with the
declaration's description as a following clause when present; `## Exports` including
`` as `alias` `` when an alias is declared; `## Prompts` listing each interactive prompt's
variable, question text, choices, and condition; `## Generation steps` — a table-free bullet
list of `<strategy> <src> → <dest>`, annotated with the patch operation when one is set and
`when <condition>` when one is set; `## Commands` listing `` `run` `` with working directory
and condition; `## Removal` listing each removal step's action and target plus its commands,
or omitted when the module declares no removal; and `## Migrations` listing each edge as
`### <from> → <to>` followed by its operations rendered one per bullet (`move <src> → <dest>`,
`delete <path>`, `run <command>` with working directory).

For a **recipe**: description; `## Composes` (as today) with each composed module's supplied
variable bindings shown inline; `## Variables`; `## Prompts`.

For a **blueprint**: description; `## Base modules` (as today, with bindings); `## Agent
prompt` — keep today's first-paragraph excerpt, but follow it with the full prompt inside a
fenced ```` ```text ```` block so nothing is lost; `## Variables`; `## Prompts`; `## Reference
files` (as today); `## Tools` — `allowedTools`, which the blueprint renderer currently omits
even though the prompt renderer has it; `## Agent launch` — provider, model, and effort when
declared, with a sentence stating that these are defaults the invoking user's flags and
`SEIHOU_AGENT_*` environment variables override; `## Version probe` — the declared command in
a fenced block plus one sentence explaining that seihou reads no package-manager format and
relies on this command to discover the current version (this is
[ADR 0009](../adr/0009-seihou-reads-no-package-manager-format-artifacts-declare-the-command.md));
and `## Migrations`, where each edge renders as `### <from> → <to>` with its prompt text and,
when the edge entails others, an `Entails:` list. An entailed edge naming a blueprint that is
listed in the same registry renders as
``- [<blueprint>](<link>) `<from>` → `<to>` `` using `renderConceptLink` against
`blueprints/<name>`; one naming a blueprint outside the registry renders as
``- `<blueprint>` `<from>` → `<to>` (declared outside this registry)``.

For a **prompt** (`AgentPrompt`): description; `## Agent prompt` (excerpt plus full text as
for blueprints); `## Variables`; `## Prompts`; `## Command variables` — each `CommandVar` as
`` - `name` — runs `<run>` `` with working directory, `trimmed`/`untrimmed`, a byte cap when
set, and a condition when set; `## Guidance` — each block as `### <title>` followed by its
body, with `Applies when <condition>` when conditional; `## Reference files`; `## Tools`;
`## Agent launch`.

Extend the model layer only where it cannot be avoided.
`seihou-okf-extension/src/Seihou/OKF/Docs/Model.hs` already carries the whole artifact inside
`DocArtifact`, so most of milestone 3 needs no model change. The one addition is entailment
resolution: add a field to `DocEntry` — `entailedRefs :: [EntailedRef]` where
`EntailedRef = EntailedRef { blueprint :: Text, from :: Text, to :: Text, resolved :: Bool }`
— populated for blueprint entries from `BlueprintMigration.entails`, with `resolved` set the
same way `ModuleRef.resolved` is set today, except matched against the registry's *blueprint*
names rather than its module names. Keep `resolveEntryRefs` the single place that decides
resolution, so there is one rule.

Also add a **registry overview concept**. Today the bundle has no document describing the
registry itself, which means the root `index.md` is the only place a reader learns the
repository's name and description. Render one additional concept with ID `registry/<repoName>`
(sanitized to the concept-ID character set the same way artifact names are), type
`SeihouRegistry`, the registry's description, and a body that links to every artifact concept
grouped by kind. This makes the bundle a connected graph from a single entry point and gives
`okf graph okf-docs --json` a root.

Tests: extend `seihou-okf-extension/test/Seihou/OKF/Docs/RenderSpec.hs` with one focused
assertion per new section, built on fixture artifacts that declare that feature — a module
with two migration edges and a removal block, a blueprint with an entailed edge that resolves
and one that does not, a prompt with a command variable and a conditional guidance block, and
a recipe whose composed module carries variable bindings. Extend
`seihou-okf-extension/test/Seihou/OKF/Docs/ModelSpec.hs` with a case asserting `entailedRefs`
resolution in both directions. Keep the existing fixture-in-a-temp-directory style: write raw
Dhall text, no remote imports.

Acceptance: `cabal test all` passes. Regenerating from `seihou-modules` and grepping the
output shows the new sections — for example
`grep -c '^## Generation steps' okf-docs/modules/*.md` reports 7. `okf validate okf-docs
--strict` still exits 0, which proves no cross-link was rendered to a concept that does not
exist.

### Milestone 4 — A house profile the generator enforces on itself

Scope: a Dhall descriptor stating what a seihou documentation bundle's frontmatter must carry,
written into the bundle so downstream tools can check it, and enforced in-process so the
generator cannot emit a bundle that violates it. At the end of this milestone
`okf validate okf-docs --strict --profile okf-docs/profile.dhall --profile-enforce` exits 0,
and a deliberately broken generator run fails before writing anything.

Author `seihou-okf-extension/profile/seihou-registry-docs.dhall`. Before writing it, read
`/Users/shinzui/Keikaku/bokuno/okf-profiles/profiles/coordination/improvement-requests.dhall`
as a worked example of the descriptor language and
`/Users/shinzui/Keikaku/bokuno/okf/okf-core/src/Okf/Profile.hs` for the authoritative field
list (`ProfileSpec`, `FrontmatterRules`, `FieldRule`, `TypeRule`, `Cardinality`,
`FieldFormat`). The descriptor should declare the four concept types the generator emits
(`SeihouModule`, `SeihouRecipe`, `SeihouBlueprint`, `SeihouPrompt`) plus `SeihouRegistry`;
require `title`, `description`, `resource`, and `generated` on every concept; require `tags`
to be a list of text; and require `version` on module, recipe, and blueprint concepts where
the registry supplies one. Set the profile's required bundle version to 0.2 so
`validateProfileVersion` catches a bundle that forgets to declare it.

Embed the descriptor in the executable with `Data.FileEmbed.embedStringFile` (add
`file-embed` to the library's `build-depends`) so the generator has no runtime dependency on
its own source tree, and write it to `<out>/profile.dhall` as part of bundle generation. A
Dhall file at the bundle root is not a concept and does not disturb `walkBundle`.

Add profile enforcement to `Seihou.OKF.Docs.Render`: after rendering concepts and before
writing, load the descriptor with `Okf.Profile.loadProfileFile` (pointed at the file the
generator just wrote to a temporary location, or at `--profile PATH` when the operator
supplies one), compile it with `compileProfile`, and run both `validateProfile` and
`validateProfileVersion`. Report violations through a new `DocBundleError` constructor.
Because `renderProfileViolation` lives in `okf-cli` and not in `okf-core`, write a local
renderer over the `ProfileViolation` constructors in
`seihou-okf-extension/src/Seihou/OKF/Extension/Docs.hs`, following the same total,
no-catch-all discipline as `renderValidationError`.

Add a `--profile PATH` option to override the built-in descriptor and a `--no-profile` option
to skip enforcement entirely, for an operator whose house conventions differ.

Tests: a case asserting that a model whose entry would produce a concept missing a
profile-required field is reported as a profile violation and that **nothing is written** —
assert the output directory is still empty afterwards. A case asserting the written bundle
contains `profile.dhall`.

Acceptance: `cabal test all` passes;
`okf validate okf-docs --strict --profile okf-docs/profile.dhall --profile-enforce` exits 0
on a freshly generated bundle.

### Milestone 5 — Make it visible, and prove it end to end

Scope: documentation and a recorded end-to-end run. At the end of this milestone a user
reading the repository's docs learns what the command now produces, and the plan carries
evidence that it works on two real registries.

Update `docs/cli/okf-docs.md`: document `--generated-at`, `--permissive`, `--profile`, and
`--no-profile`; replace the stale "writes 8 concepts" claim with the current count for
`seihou-modules` (12 artifact concepts plus the registry overview concept — state the number
you actually observe, not the number this plan predicts); describe the bundle layout
(root `index.md` with the version declaration, per-kind section indexes, `profile.dhall`);
and update the follow-up checks to the strict, profile-enforcing invocation plus
`okf trust`, `okf sources`, and `okf concepts --filter`.

Add a user-facing guide. There is no page under `docs/user/` about the OKF extension at all
today (`docs/user/` holds `getting-started.md`, `registries-and-multi-module-repos.md`,
`blueprints.md`, `prompts.md`, `migrations.md`, `blueprint-migrations.md`, and others). Add
`docs/user/registry-documentation.md` explaining what the extension is for, how to run it,
what each generated section corresponds to in the author's `.dhall` files, and the fact that
the output is derived — regenerate, never hand-edit. Link it from
`docs/user/registries-and-multi-module-repos.md`.

Add entries to the engineering changelog `CHANGELOG.md` and the user changelog
`docs/user/CHANGELOG.md` under the unreleased heading, describing the okf-core upgrade and the
newly documented artifact features. Follow the existing style in those files; do not invent a
release number.

Update `nix/haskell-overlay.nix`'s stale comment about the shared registry if milestone 1 did
not already, and check whether `docs/dev/architecture/overview.md`'s mentions of okf need
adjusting.

Record the end-to-end run in Concrete Steps below with real transcript output, against both
`/Users/shinzui/Keikaku/bokuno/seihou-modules` (7 modules, 2 recipes, 3 blueprints, 0 prompts)
and `/Users/shinzui/Keikaku/bokuno/agent-seihou` (which exercises a different shape). Run the
hosted form too — `seihou extension run okf -- docs ...` — since that path has its own
argument-forwarding logic in `seihou-cli/src-exe/Main.hs` and is easy to break without
noticing.


## Concrete Steps

All commands run from the repository root
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou` unless stated otherwise. If GHC is not
on your `PATH`, prefix the session with `nix develop`.

Milestone 1:

```bash
cabal build all
cabal test all
nix build .#seihou-okf-extension
```

Expected: `cabal test all` reports the extension's existing suite passing, for example

```text
seihou-okf-extension
  Seihou.OKF.Extension
    okfSmoke
      serializes an OKF document through okf-core:  OK
  ...
All 15 tests passed
```

To confirm milestone 1 changed no output, generate a bundle before and after the pin move and
compare:

```bash
cabal run seihou-okf-extension -- docs \
  --dir /Users/shinzui/Keikaku/bokuno/seihou-modules \
  --out /tmp/okf-docs-before --force
# ... apply milestone 1 ...
cabal run seihou-okf-extension -- docs \
  --dir /Users/shinzui/Keikaku/bokuno/seihou-modules \
  --out /tmp/okf-docs-after --force
diff -r /tmp/okf-docs-before /tmp/okf-docs-after && echo "identical"
```

Milestones 2 through 4, after each change:

```bash
cabal test all
cabal run seihou-okf-extension -- docs \
  --dir /Users/shinzui/Keikaku/bokuno/seihou-modules \
  --out /tmp/okf-docs --force
okf validate /tmp/okf-docs --strict
okf validate /tmp/okf-docs --strict --profile /tmp/okf-docs/profile.dhall --profile-enforce
okf graph /tmp/okf-docs --json | head -20
okf trust /tmp/okf-docs
okf concepts /tmp/okf-docs --filter type=SeihouBlueprint
```

Milestone 5, the hosted path (requires the extension executable on `PATH`; `cabal install
--overwrite-policy=always seihou-okf-extension` or `nix build .#seihou-okf-extension` then use
the result path):

```bash
seihou extension run okf -- docs \
  --dir /Users/shinzui/Keikaku/bokuno/agent-seihou \
  --out /tmp/agent-seihou-docs --force
```

Expected output shape:

```text
Wrote 13 concepts to /tmp/agent-seihou-docs
```

(Replace with the count you actually observe; `agent-seihou` has a different artifact mix.)

Record the real transcripts here as you go, replacing the placeholders above.


## Validation and Acceptance

The plan is complete when all of the following hold, each verifiable by running a command and
reading its output.

**The dependency actually moved.** `grep okf-core seihou-okf-extension/seihou-okf-extension.cabal`
shows `^>=0.8.0.0` in both stanzas, and `grep -A2 'okf-core =' nix/haskell-overlay.nix` shows
`"0.8.0.0"` with the SRI hash `sha256-ADugvEouY5r+o1W0K09M7IX0GTVuZ1OXvA+Vem/QnBI=`.
`nix build .#seihou-okf-extension` succeeds, which proves the Nix path resolves the new
version and its new transitive dependencies.

**The error renderer is total.** `cabal build all` succeeds with
`-Werror=incomplete-patterns` active on all three stanzas. To prove the guard works, delete
one branch from `renderValidationError` and confirm the build fails; restore it.

**The bundle declares OKF v0.2 and carries provenance.** After generating,
`head -5 /tmp/okf-docs/index.md` shows frontmatter containing `okf_version: "0.2"`, and
`grep -c 'seihou-okf-extension/' /tmp/okf-docs/modules/*.md` equals the module count.
`okf trust /tmp/okf-docs` lists a tier for every concept rather than reporting unknown
provenance.

**Strict validation passes.** `okf validate /tmp/okf-docs --strict` exits 0. Confirm the
strictness is real by regenerating with `--permissive` after deliberately blanking a fixture's
description, and observing that strict mode reports it while permissive does not.

**Every artifact feature reaches the page.** For the `seihou-modules` registry, all of these
report a non-zero count:

```bash
grep -l '^## Generation steps' /tmp/okf-docs/modules/*.md | wc -l
grep -l '^## Migrations'       /tmp/okf-docs/blueprints/*.md /tmp/okf-docs/modules/*.md | wc -l
grep -l '^## Agent launch'     /tmp/okf-docs/blueprints/*.md | wc -l
grep -rl 'Entails:'            /tmp/okf-docs/blueprints/ | wc -l
```

A count of zero for a section means either the registry genuinely declares nothing of that
kind — check the source `.dhall` before concluding the renderer is broken — or the renderer
dropped it. For any section where `seihou-modules` declares nothing, the unit test fixture
built in milestone 3 is the proof instead, and its assertion must be named in this section
when you fill it in.

**The profile is enforced.**
`okf validate /tmp/okf-docs --strict --profile /tmp/okf-docs/profile.dhall --profile-enforce`
exits 0. A unit test proves the generator refuses to write a violating bundle.

**The hosted path still works.** `seihou extension run okf -- docs --dir ... --out ... --force`
produces the same output as invoking the extension directly, proving the raw-argv forwarding
in `seihou-cli/src-exe/Main.hs` still handles the new options after `--`.

**Nothing else regressed.** `cabal test all` passes for all three packages — the `renderExpr`
addition touches `seihou-core`, which the CLI also depends on. `nix flake check` passes,
which runs the record-convention and CLI-placement scripts over the new code.


## Idempotence and Recovery

Every step here is repeatable. Re-running `cabal build all` or `cabal test all` is always
safe. Re-running the generator against the same registry and output directory with `--force`
removes and recreates the output directory, so a half-written bundle from an interrupted run
is never merged with a new one; without `--force` the command refuses a non-empty output
directory rather than overwriting it. Point `--out` at a scratch path such as `/tmp/okf-docs`
during development so that no checked-in file is ever at risk.

Generated output is byte-stable across runs by design: nothing in the generator reads the
clock, and `--generated-at` is the only way a timestamp enters the bundle. If you find two
consecutive runs producing different bytes, that is a defect — the most likely cause is
iterating a `Map` (for example a `Dependency`'s `vars`) without sorting, and it belongs in
Surprises & Discoveries.

If the Nix pin fails to build, the failure is contained: `cabal build all` resolves okf-core
from Hackage independently of the overlay, so you can continue implementing while
investigating. Recompute the hash rather than guessing at it:

```bash
nix-prefetch-url --unpack \
  https://hackage.haskell.org/package/okf-core-0.8.0.0/okf-core-0.8.0.0.tar.gz
nix hash convert --hash-algo sha256 --to sri <the base32 hash printed above>
```

If a transitive dependency of okf-core is marked broken in this repository's package set, add
a `markUnbroken`/`doJailbreak` entry beside the existing ones in `nix/haskell-overlay.nix`
following the pattern in `/Users/shinzui/Keikaku/bokuno/okf/nix/haskell.nix`, and record it in
Surprises & Discoveries.

To roll back at any point, `git revert` the milestone's commit. Milestones 2 through 5 change
only generated output and are safe to revert independently. Milestone 1 is the only one
others depend on. The one change outside the extension package is `renderExpr` in
`seihou-core`, which is purely additive: nothing existing calls it, so reverting milestone 3
cannot break `seihou-cli`.


## Interfaces and Dependencies

**External library: `okf-core` 0.8.0.0** (Hackage; sources for reading at
`/Users/shinzui/Keikaku/bokuno/okf/okf-core/`). The functions this plan calls, with their
exact 0.8.0.0 signatures:

```haskell
-- Okf.Validation
data ValidationProfile = PermissiveConformance | StrictAuthoring
validateBundle
  :: ValidationProfile -> VersionDeclaration -> BundleInventory -> [Concept]
  -> [BundleValidationError]

-- Okf.Bundle
bundleInventoryOfConcepts :: [Concept] -> BundleInventory
conceptFromDocument       :: ConceptId -> OKFDocument -> Concept
writeBundle               :: FilePath -> [Concept] -> IO ()

-- Okf.Index
data OkfVersion = OkfVersion { okfVersionMajor :: !Int, okfVersionMinor :: !Int }
data VersionDeclaration
  = VersionDeclared !OkfVersion | VersionUndeclared | VersionUnparseable !Text
supportedOkfVersion    :: OkfVersion                       -- currently 0.2
writeBundleIndexesWith :: Maybe OkfVersion -> FilePath -> IO (Either BundleError ())

-- Okf.Document
data Generated = Generated { generatedBy :: !Actor, generatedAt :: !(Maybe Text) }
setGenerated :: Generated -> Frontmatter -> Frontmatter
setStatus    :: Status -> Frontmatter -> Frontmatter
setTags      :: [Text] -> Frontmatter -> Frontmatter
setResource  :: Text -> Frontmatter -> Frontmatter
setField     :: Text -> Value -> Frontmatter -> Frontmatter
okfCommon    :: OkfCommon -> Frontmatter

-- Okf.Actor
data Actor = HumanActor !Text | ProcessActor !Text | ProducerActor !Text !Text
           | UnclassifiedActor !Text

-- Okf.ConceptId
parseConceptId    :: Text -> Either ConceptIdError ConceptId
renderConceptId   :: ConceptId -> Text
renderConceptLink :: ConceptId -> Text -> Text

-- Okf.Profile
loadProfileFile        :: FilePath -> IO (Either Text ProfileSpec)
compileProfile         :: ProfileSpec -> Either (NonEmpty ProfileDefinitionError) CompiledProfile
validateProfile        :: ValidationProfile -> CompiledProfile -> [Concept] -> [ProfileViolation]
validateProfileVersion :: VersionDeclaration -> CompiledProfile -> [ProfileViolation]
```

`renderProfileViolation` is **not** in `okf-core`; it lives in the `okf-cli` package, which
this repository does not depend on. Render violations locally.

**New in `seihou-core`**, exported from `Seihou.Core.Expr`:

```haskell
renderExpr :: Expr -> Text
```

**New and changed in `seihou-okf-extension`**, by module:

```haskell
-- Seihou.OKF.Docs.Model
data EntailedRef = EntailedRef
  { blueprint :: !Text, from :: !Text, to :: !Text, resolved :: !Bool }
  deriving stock (Eq, Generic, Show)
-- DocEntry gains: entailedRefs :: ![EntailedRef]

-- Seihou.OKF.Docs.Render
data RenderOptions = RenderOptions
  { producerVersion   :: !Text
  , generatedAt       :: !(Maybe Text)
  , validationProfile :: !ValidationProfile
  , profileSource     :: !(Maybe FilePath)   -- Nothing = built-in descriptor
  , enforceProfile    :: !Bool
  }
  deriving stock (Eq, Generic, Show)

renderDocBundle :: RenderOptions -> DocModel -> Either [DocRenderError] ([Concept], [BundleValidationError])
writeDocBundle  :: RenderOptions -> FilePath -> DocModel -> IO (Either [DocBundleError] ())
-- DocBundleError gains constructors for index-writing failures and profile violations.

-- Seihou.OKF.Extension.Docs
data DocsOpts = DocsOpts
  { dir :: !FilePath, out :: !FilePath, force :: !Bool
  , generatedAt :: !(Maybe Text), permissive :: !Bool
  , profile :: !(Maybe FilePath), noProfile :: !Bool
  }
  deriving stock (Eq, Generic, Show)
```

All new records follow the repository conventions enforced by
`nix/check-record-conventions.sh`: strict fields, explicit deriving strategy, `Generic`, no
type-abbreviation prefixes on field names, and access through `generic-lens` overloaded labels
with `import Data.Generics.Labels ()` in each module that uses `#label`.

**Build-system dependencies**: `file-embed` is added to
`seihou-okf-extension/seihou-okf-extension.cabal`'s library `build-depends` for milestone 4;
it is already used elsewhere in the workspace, so no new package enters the closure.
`Paths_seihou_okf_extension` is added to `other-modules` and `autogen-modules` for the
producer version string in milestone 2.

**Unchanged boundaries**: `seihou-core` and `seihou-cli` still must not depend on `okf-core`.
The only `seihou-core` change in this plan is `renderExpr`, which introduces no dependency.
The extension host contract in `seihou-cli/src/Seihou/CLI/Extension.hs` and the raw-argv
handling in `seihou-cli/src-exe/Main.hs` are unchanged; milestone 5 only verifies them.
