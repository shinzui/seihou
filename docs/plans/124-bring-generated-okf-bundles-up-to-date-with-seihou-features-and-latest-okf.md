---
id: 124
slug: bring-generated-okf-bundles-up-to-date-with-seihou-features-and-latest-okf
title: "Bring generated OKF bundles up to date with Seihou features and latest OKF"
kind: exec-plan
intention: intention_01m76brhtbe11ag2r5ayk8fp0w
created_at: 2026-11-11T22:30:40Z
provenance:
  created_by:
    model: "gpt-6-astra"
    harness: "codex-cli"
    at: 2026-11-11T22:30:40Z
  revisions:
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-11-11T22:33:17Z
      mode: "other"
      note: "Ground initial plan in current generator, verified OKF release, and user-created Mina intention"
    - model: "gpt-6.1-sol"
      harness: "codex-cli"
      at: 2026-11-12T03:04:12Z
      mode: "implement"
      note: "Implement current declaration coverage and OKF 0.13 compatibility with real-registry acceptance"
---


# Bring generated OKF bundles up to date with Seihou features and latest OKF

This ExecPlan is a living document. Keep Progress, Surprises & Discoveries, Decision Log, and Outcomes & Retrospective current. Follow `agents/skills/exec-plan/PLANS.md`, `ADR.md`, and `FRICTION.md` during implementation.

## Purpose / Big Picture


A registry author should generate documentation that accurately explains every supported Seihou artifact declaration, including new ownership lifecycles, sourced dependencies, recipe inheritance, judgements, and declarative line-removal migrations. The resulting Open Knowledge Format (OKF) bundle—a directory of Markdown concepts, indexes, and a validation profile—must pass the latest released OKF's strict checks.

The starting state is a fresh registry checkout containing `seihou-registry.dhall`, with Seihou installed but no populated artifact installation cache. From that checkout, the normal first-use command is `seihou-okf-extension docs`; regeneration uses `seihou-okf-extension docs --force`. No dependency installation, composition execution, agent invocation, manifest editing, or per-feature flags should be necessary. Existing custom profiles remain supported. Documentation is derived from declarations, not a consumer's saved values or local review policy. Verify both the built executable and the eventual published/installed artifact; source-only success is not released delivery.

## Progress


- [x] Milestone 1 (2026-11-12): The extension builds against the verified latest OKF release and generates a strictly valid bundle from a real registry through the ordinary command. Source-built 0.15.0.0 with GHC 9.12.4 wrote 29 concepts from the producer revision recorded below; installed OKF 0.13.0.0 passed strict/profile validation.
- [x] Milestone 2 (2026-11-12): Generated concepts cover current declarations with a field-to-output inventory, source-aware relationships, complete judgement settings and literal-safe rendering. All 59 extension tests pass, including direct current-schema decoding, legacy custom-profile compatibility and strict validation of the five-kind fixture.
- [ ] Milestone 3: Source and native fresh-checkout, regeneration, failure-preservation, packaging and help acceptance pass (2026-11-12). Publication and installed-user delivery remain outstanding; do not mark this milestone complete until a release and the installed executable pass the workflow.

Implementation is authorized in this session. Publication has not been requested; milestone 3 retains its release/installed delivery obligation. Intention `intention_01m76brhtbe11ag2r5ayk8fp0w` was created with `mina ci --json` at the user's request.

## Surprises & Discoveries


The current tree is clean at implementation start; the previously uncommitted migration/schema work is now committed. Mori discovery still fails with a refused PostgreSQL notifier socket (FRIC-18 in `docs/friction-log/`), so released source was inspected from the verified tag. Module and recipe judgement references are intentionally decoded separately by `evalJudgementRefsFromFile`; they are not fields of the executable records.

The first ordinary run failed before writing output with `recipes/fumadocs-site: link to missing concept: modules/technical-docs`. Classifying dependency references before rendering fixed this real producer failure. The shared Nix registry pins older OKF source; the unmanaged application overlay now selects the exact Hackage 0.13.0.0 source without a jailbreak or changes to module-owned pins.

## Decision Log


- Decision (2026-11-11): Treat “all new features” as complete coverage of current artifact declarations and their user-facing semantics, including already implemented features that render only partially. Preserve declaration-only generation; do not expand remote recipe bases or execute commands to create documentation. This keeps a fresh registry checkout usable without an installed dependency closure.
- Decision (2026-11-11): Target `mori://shinzui/okf/packages/okf-core` 0.13.0.0, subject to rechecking releases at implementation start. Update the standalone house profile and exhaustive diagnostic adapters together with dependency bounds. Merely changing the bound cannot establish compatibility.

- Decision (2026-11-12): Keep strict OKF validation and profile enforcement enabled. Correct the house profile's `tags` presence rule to optional, as for versions, because valid empty catalog lists cannot satisfy OKF's nonempty-list presence rule. Preserve empty source tags rather than inventing replacements. ADR 0010 records this source-schema constraint. Blueprint tool prose describes declared additions because setup tools are always pre-approved.

## Outcomes & Retrospective


Implementation and source/native acceptance are complete as of 2026-11-12; published delivery is not complete. The ordinary workflow is `seihou-okf-extension docs` for an absent output tree, or `seihou-okf-extension docs --force` for regeneration. The explicit host route is `seihou extension run okf -- docs`. Both source-built and native packaged routes generated 29 concepts from the real producer and passed the installed OKF 0.13.0.0 strict/profile validator. Unchanged regeneration and switching between the two routes produced identical bytes. No Seihou artifact installation or configuration state was created.

All 2,845 tests passed: 1,788 core, 998 CLI and 59 extension tests. After the last test/help refinements, `cabal build all` and the 59-test extension suite passed again without compiler warnings. Native builds of `.#seihou-cli`, `.#seihou-okf-extension` and `.#seihou` passed with package tests enabled. Formatting, flake checks and `git diff --check` passed. All three `cabal check` runs reported no warnings or errors; source distributions were generated and the extension tarball's final profile, bounds and writer bytes matched the working tree. The house descriptor decodes directly as OKF's current `ProfileSpec`, rather than merely succeeding through a frozen fallback.

The five-kind fixture verifies lifecycle distinctions, literal backticks/pipes/newlines, source-qualified local shadows, recipe inheritance/overrides, local and external conditional judgement references, answer/category meanings, disabled gates and every coverage limit. Existing output snapshots survive malformed input and rejecting profiles under `--force`. A profile stored within the output being replaced also succeeds: validation, profile copying and indexing now complete in a temporary sibling before output replacement. ADR 0010 records declaration-only generation, kind/origin-aware links, source-schema profile constraints and this replacement order.

FRIC-18 in `docs/friction-log/` is triaged **accepted**: the unavailable local Mori PostgreSQL connection was bypassed through verified upstream source and a disposable producer checkout. Database recovery is outside this implementation; no runtime Mori dependency was introduced.

Remaining delivery: Hackage still lists 0.15.0.0 as the latest normal extension release, and the user's installed host reports `seihou v0.15.0.0 (d67cf67)`. These results do not include this change. No release tag, upload, push or installed-user replacement was performed. When publication is authorized, use the repository release workflow for the accumulated unreleased changes, then rerun the real-registry workflow with the newly installed binaries before closing milestone 3.

## Context and Orientation


`seihou-okf-extension/src/Seihou/OKF/Docs/Model.hs` loads the registry and each module, recipe, blueprint, prompt, and judgement. `DocEntry` retains the decoded artifact and references used by `seihou-okf-extension/src/Seihou/OKF/Docs/Render.hs`. The renderer builds concepts, metadata, a registry overview, and indexes. `seihou-okf-extension/src/Seihou/OKF/Extension/Docs.hs` owns command validation, output replacement, and human diagnostics. `seihou-okf-extension/profile/seihou-registry-docs.dhall` is an embedded, standalone house profile copied into generated output. Its self-contained types currently describe an older profile schema.

Current rendering is not a blank slate: judgement concepts, recipe bases and overrides, checkout commands, conditional removal, blueprint migrations, launch preferences, and prompt command variables already exist. Concrete gaps observed during creation are that `renderStep` ignores lifecycle; `renderDependencies` drops `source` and emits module links without consulting resolution; `ModuleRef` retains only name and a resolved Boolean; `renderMigrationOp` lacks the working tree's `RemoveLine`; and judgement rendering omits gate settings, answer explanations, category descriptions, and coverage limits. Audit module/recipe judgement references as well. Preserve working coverage while closing these gaps.

The source contract is `seihou-core/src/Seihou/Core/Types.hs`, `seihou-core/src/Seihou/Core/Judgement.hs`, `seihou-core/src/Seihou/Core/Migration.hs`, `seihou-core/src/Seihou/Core/Registry.hs`, and their decoders under `seihou-core/src/Seihou/Dhall/`. These records, together with the schema submodule and `CHANGELOG.md`, define the inventory, including features already present in uncommitted work. At creation the tree contains unrelated edits to migration/update code, schema, flakes, documentation, and a new ADR 0028. Preserve them and recheck their state before implementation; do not revert or bundle them incidentally into this plan's commits.

Relevant architectural decisions consulted are [ADR 0010](../adr/0010-generated-documentation-is-checked-before-it-is-written.md), requiring strict and profile checks before output mutation and deterministic output without clock reads; [ADR 0017](../adr/0017-a-seed-file-is-created-once-and-belongs-to-the-project.md), making seeds create-once project-owned files; [ADR 0018](../adr/0018-checkout-outputs-are-observable-portable-declarations.md), distinguishing checkout links and repeatable commands from managed files; [ADR 0020](../adr/0020-dependency-sources-belong-to-producer-edges.md), making source a producer-owned dependency contract; [ADR 0024](../adr/0024-recipes-extend-one-origin-aware-base.md), defining single-base inheritance and overrides; [ADR 0027](../adr/0027-judgements-decide-from-model-evidence-through-recorded-project-policy.md), distinguishing authored checks from recorded policy and local model routes; and [ADR 0028](../adr/0028-declarative-line-edits-share-preview-and-apply-semantics.md), defining exact line-removal semantics. These establish what generated prose must mean. This work does not migrate the ADR corpus to an OKF profile.

Both extension library and test bounds currently use `okf-core ^>=0.10.0.0`. Hackage's package JSON and upstream tags were checked on 2026-11-11: latest normal release is 0.13.0.0, tag `v0.13.0.0`, peeled commit `e0dd9e3047285caff6c4c4d9c6aee06e6ebb31b7`. Release 0.11 requires GHC 9.12/base 4.21 and adds profile constraints, nested unknown-field policy, `FiniteDecimal`, and new diagnostic cases; 0.12 adds profile sweep support and 0.12.0.1 fixes index whitespace. The relevant dependency is `mori://shinzui/okf/packages/okf-core`; upstream release notes belong to `mori://shinzui/okf`, project-relative `CHANGELOG.md` (artifact-level URI pending). Evidence endpoints are shown in Concrete Steps.

Mori discovery was attempted with `mori registry list` and `mori registry search okf`, but both failed because the local PostgreSQL socket refused connections. No local dependency source path was established. Repeat discovery when available and read the released source before making API changes; do not infer APIs from release notes. This limitation does not prevent defining the work and acceptance here.

## Plan of Work


### Milestone 1 — Upgrade OKF and prove the real generation path


Discover OKF through Mori and compare the authoritative published version and tag again. Read the selected release's profile decoding, validation, bundle/index writing, and error types. Update both bounds in `seihou-okf-extension/seihou-okf-extension.cabal`. Inspect `nix/haskell-overlay.nix`, `flake.module.nix`, and the shared package selection so native builds select the same release. Respect managed flake inputs; do not introduce an unexplained local jailbreak or rewrite module-owned pins. If the shared producer needs an update, include that integration under its canonical Mori reference and keep delivery open until it is available.

Adapt exhaustive error rendering in `Extension/Docs.hs` without catch-all `show` fallbacks. Make the standalone profile compatible with the selected decoder, including separate nested and top-level rule shapes where necessary. Preserve older supported custom descriptors through OKF's compatibility path. Keep strict validation enabled. Confirm whether existing bundle format 0.2 remains correct from the released library; package version is not a bundle format version.

Before broad test expansion, use a disposable fresh checkout of `mori://shinzui/seihou-modules` located through Mori and run the actual source-built `seihou-okf-extension docs` with empty installation caches. Record checkout revision, exact executable paths/versions, setup commands, and first failure or successful summary. Fix the smallest necessary integration slice, including `RemoveLine` rendering if its new constructor prevents compilation. Pass strict validation using latest OKF. This milestone is accepted only with a generated real bundle, not a successful Cabal solver run.

### Milestone 2 — Render complete declarations and truthful links


Create a field-to-output inventory in `docs/user/registry-documentation.md`, covering every current public record field and sum-type constructor. Each field must have an output location or an explicit explanation that it is runtime-only and not part of registry declarations. Use this inventory to finish `Model.hs` and `Render.hs` and extend the existing `ModelSpec.hs`, `RenderSpec.hs`, and `DocsSpec.hs` under `seihou-okf-extension/test/Seihou/OKF/`.

Render managed, seed, and checkout step lifecycles separately from strategy, with the create-once and `seihou sync` consequences. Retain command lifecycles and conditional removal. Render exact `RemoveLine` path and text and explain that all exact matching logical lines are removed; do not describe it as a substring replacement or executable shell command. Preserve every existing migration operation.

Retain source and bindings in module references, including dependencies declared by modules, recipes, and blueprints. A local concept link must identify the correct kind and provably local target. Explicit external sources—even when a local artifact shares the name—render as labelled source/name text unless local origin equivalence is proven. Unresolved external references must not become dangling OKF links. Do not fetch dependencies to render them. Recipe output must retain its base source and interval, local additions, module and prompt overrides, variables and validation, and the declared inheritance semantics; never present an unexpanded child as a fully resolved composition.

Render judgement references on artifacts with their source and condition, linking only proven local judgement concepts. Judgement pages must expose answer meanings, categories with descriptions and severities, enforcement, concern direction, review thresholds, gate thresholds and `useGate`, evidence scopes/filters, deterministic checks, and all coverage limits. Explain model-reported probabilities without implying calibration. Do not embed a consumer's credentials, local routes, or saved policy into registry documentation.

Preserve blueprint/prompt tool restrictions, launch settings, reference files, guidance, command variables, version probes, migration entailments, registry metadata, stable concept paths, and deterministic ordering. Update house-profile descriptions and the overview to name all five artifact kinds. Test Markdown-sensitive values such as pipes, backticks, multiline prompts, and line-removal literals so literal source data cannot silently change the rendered meaning.

### Milestone 3 — Prove adoption, failure behavior, and delivery


Update `docs/cli/okf-docs.md`, `docs/user/registry-documentation.md`, `seihou-cli/help/extensions.md` and extension help in `seihou-cli/src-exe/Seihou/CLI/Commands.hs`, and `CHANGELOG.md`. Replace stale fixed registry counts with behavior-based examples. Explain fresh generation, intentional overwrite, errors, and follow-up validation. Verify the standalone executable and extension-host route expose the same behavior; do not assume the historical `seihou docs` shorthand still exists.

Exercise one fixture containing all artifact kinds and new declarations, an older supported registry, and the real producer from milestone 1. Regenerate twice and compare bytes. Replacing a populated bundle after a deliberate invalid input or rejecting custom profile must leave it untouched even with `--force`. Include empty caches and a fresh checkout; count any extra setup rather than hiding it in fixture preparation. Run the package checks below, then record source and published/installed versions separately. Coordinate release through the repository release workflow when authorized; if publication or installation remains outstanding, leave this milestone's delivery requirement open. Distill any changed durable contracts into ADR 0010 or a narrowly relevant ADR and triage implementation friction before completion.

## Concrete Steps


Implementation evidence (2026-11-12): verified Hackage normal release 0.13.0.0 and upstream tag peeled commit `e0dd9e3047285caff6c4c4d9c6aee06e6ebb31b7` again. Cloned that tag to `/tmp/seihou-plan124-okf` after Mori failed, and cloned `mori://shinzui/seihou-modules` to `/tmp/seihou-plan124-registry` at `6f775be46b13b55887080f402d478a1bdd72bfac`. Moved its existing generated output to `/tmp/seihou-plan124-original-docs` to preserve it. The source-built executable is `dist-newstyle/build/aarch64-osx/ghc-9.12.4/seihou-okf-extension-0.15.0.0/x/seihou-okf-extension/build/seihou-okf-extension/seihou-okf-extension` under this repository; its Cabal package version is 0.15.0.0. From the disposable checkout, invoked this absolute executable with only `docs`, isolating `XDG_CACHE_HOME`, `XDG_DATA_HOME`, and `XDG_CONFIG_HOME` under `/tmp/seihou-plan124-empty`. No artifact installation, composition, registry repair or manifest edit was needed. After the reference fix it reported `Wrote 29 concepts to okf-docs`. `/Users/shinzui/.nix-profile/bin/okf` reports `okf v0.13.0.0 (e0dd9e3)` and strict validation with the emitted profile reported `OK: 29 concepts (okf_version 0.2)`. These are source-candidate results, not published Seihou delivery.


Final native evidence (2026-11-12): `nix build .#seihou-cli .#seihou-okf-extension .#seihou --no-link` succeeded, followed by `nix build .#seihou --out-link /tmp/seihou-plan124-native`. The candidate PATH entry was `/tmp/seihou-plan124-native/bin`. The extension reports `seihou-okf-extension 0.15.0.0`; the packaged host reports `seihou v0.15.0.0 (dirty)` because this is an unreleased working-tree build. A second untouched clone of `mori://shinzui/seihou-modules` at the same revision was created at `/tmp/seihou-plan124-packaged-registry`, with all three XDG directories isolated under `/tmp/seihou-plan124-native-empty`. This checkout already tracks `okf-docs`, so the initial `docs` correctly refused with `output directory is not empty: okf-docs; pass --force to overwrite`. Following exactly that remedy, standalone `docs --force` and `seihou extension run okf -- docs --dir . --out okf-docs --force` each wrote 29 concepts and passed strict/profile validation. A snapshot at `/tmp/seihou-plan124-packaged-snapshot` matched every generated byte after host regeneration; the isolated config directory remained empty. Unlike the earlier exploratory move of existing docs, this final adoption check required no registry repair or output preparation.

Source candidate PATH was `/tmp/seihou-plan124-bin`, holding symlinks to the two exact Cabal executable paths under this repository's `dist-newstyle/build/aarch64-osx/ghc-9.12.4/` package directories. The host reported `seihou v0.15.0.0 (68db1e2)`. Both command routes passed and their complete output trees matched. Final package tarballs are under `/tmp/seihou-plan124-sdist`; they are validation artifacts, not uploaded releases.

Run development commands from the Seihou repository root. First inspect status and discover sources; Mori is a contributor lookup tool, not a runtime prerequisite for docs generation.

```bash
git status --short
mori registry list
mori registry search okf
mori registry show shinzui/okf --full
mori registry docs shinzui/okf
mori registry show shinzui/seihou-modules --full
curl -fsSL https://hackage.haskell.org/package/okf-core.json
git ls-remote --tags https://github.com/shinzui/okf.git
```

The release evidence currently selects 0.13.0.0. If discovery remains unavailable, record the failure and inspect source from the verified upstream tag in a disposable directory; do not search `/nix/store` or the filesystem root. Confirm source APIs before editing compatibility code.

```bash
nix develop -c cabal update
nix develop -c cabal build all
nix develop -c cabal test seihou-okf-extension-test --test-show-details=direct
nix develop -c cabal test all --test-show-details=direct
nix fmt
nix flake check
nix build .#seihou-cli .#seihou-okf-extension --no-link
git diff --check
```

All checks must exit zero. The native package attributes are declared in `flake.module.nix`; verify the bundled `.#seihou` package as well for host/extension delivery. Prefer local Apple containers if Linux checks become necessary. Never inspect build dependencies by traversing `/nix/store`.

From the disposable producer checkout with the candidate executables on PATH, run:

```bash
seihou-okf-extension docs
okf validate okf-docs --strict --profile okf-docs/profile.dhall --profile-enforce
seihou-okf-extension docs --force
okf validate okf-docs --strict --profile okf-docs/profile.dhall --profile-enforce
```

Generation must report `Wrote N concepts to okf-docs`, where N is the number of published artifacts plus the registry overview. Index files are not concepts. Validate identical behavior through the supported explicit route:

```bash
seihou extension run okf -- docs --dir . --out okf-docs --force
seihou-okf-extension docs --dir . --out okf-docs --force
```

Record how the candidate binaries were placed on PATH and how empty caches were isolated. Use separate output snapshots for byte comparisons; do not overwrite a producer's existing generated docs during exploratory acceptance.

## Validation and Acceptance


Acceptance requires both meaningful content assertions and latest-OKF validation. A seeded template must be visibly distinct from a managed template; a checkout symlink must explain clone restoration. A source-qualified dependency sharing a local name must not link to the local concept. Local recipe bases and local judgement references must link to the correct concept kinds. External bases must remain readable without fetching or installing them. A conditional judgement reference and gate-disabled check must retain those facts. Every coverage limit and exact line-removal literal must be recoverable from the generated page.

Regression tests must prove strict/profile validity, stable concept IDs and source resources, deterministic bytes without `--generated-at`, an explicitly supplied generation date, older descriptor compatibility, actionable new OKF diagnostics, and preservation of an existing output tree on preflight failure. Do not weaken warnings or strictness to obtain passing results. Add constructor coverage where practical so new operations fail visibly instead of being silently omitted; record-field omissions still need the inventory review.

The real registry transcript establishes that ordinary users can run the feature. Record which release, tag, compiler, extension, host CLI, and OKF validator passed. A successful source test does not satisfy publication or installation. Generation must not execute module commands, version probes, prompt commands, or judgement reviews.

## Idempotence and Recovery


Generation into a new output directory is repeatable; replacement requires existing `--force` consent because output is derived. Invalid source or profile validation must fail before removing existing output. No wall-clock values may appear unless explicitly supplied. Work in disposable consumer checkouts and preserve original generated bundles until comparison succeeds. On dependency-upgrade failure, keep the last valid output and diagnose the selected release rather than loosening validation. Preserve all unrelated working-tree edits and never reset them to obtain a clean test run.

## Interfaces and Dependencies


`loadDocModel`, `DocEntry`, `ModuleRef`, `BaseRecipeRef`, and `EntailedRef` are the declaration-to-render boundary. Extend references to retain enough kind/source information for accurate resolution, keeping classification in the model and presentation in the renderer. Public `DocsOpts` and ordinary CLI flags should remain compatible. OKF validation/profile types come from `mori://shinzui/okf/packages/okf-core`; use the verified released source for exact signatures. The standalone profile must work both embedded and copied outside the repository. No Mori service or remote dependency acquisition becomes a requirement for users generating docs.

There is no parent MasterPlan. Implementation commits use Conventional Commits and include this plan's repository-relative path in an `ExecPlan:` trailer plus `Intention: intention_01m76brhtbe11ag2r5ayk8fp0w`.
