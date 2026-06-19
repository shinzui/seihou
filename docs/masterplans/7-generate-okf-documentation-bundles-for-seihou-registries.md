---
id: 7
slug: generate-okf-documentation-bundles-for-seihou-registries
title: "Generate OKF documentation bundles for seihou registries"
kind: master-plan
created_at: 2026-06-19T17:55:23Z
intention: "intention_01kvgg9k54efytmmeqty43t6y5"
---

# Generate OKF documentation bundles for seihou registries

This MasterPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Vision & Scope

After this initiative, seihou supports external extension executables and ships its first
extension package, `seihou-okf-extension`, which turns a seihou registry into a browsable,
linked documentation set. Users can run the extension directly:

```bash
seihou-okf-extension docs --dir <registry-repo> --out <output-dir>
```

or through the seihou extension host:

```bash
seihou extension run okf -- docs --dir <registry-repo> --out <output-dir>
```

A "seihou registry" is a directory whose `seihou-registry.dhall` file lists the artifacts a
repository publishes: **modules** (deterministic file-generation templates), **recipes**
(named compositions of modules with preset variables), **blueprints** (agent-driven
scaffolds: a prompt plus reference files), and **prompts** (reusable agent-session
templates, stored as `AgentPrompt` values in `prompt.dhall` files). The concrete example is
the `seihou-modules` repository, whose `seihou-registry.dhall` lists five modules, two
recipes, and one blueprint today.

The output is an **OKF bundle**. "OKF" is the Open Knowledge Format: a directory tree of
Markdown files, each beginning with a block of YAML frontmatter (metadata fenced by `---`
lines) followed by Markdown prose. Links between documents become a navigable graph. OKF is
implemented by the sibling `okf-core` Haskell library
(`/Users/shinzui/Keikaku/bokuno/okf`), whose authoring API (build frontmatter, render
guaranteed-resolvable links, construct and write concepts, validate a whole bundle) was
completed in that project's MasterPlan 2. This initiative makes the `seihou-okf-extension`
package consume that API while keeping `seihou-core` and the main `seihou-cli` package free
of the OKF dependency.

Concretely, after this work a user can:

- Run `seihou-okf-extension docs --dir .` inside `seihou-modules` and get an `okf-docs/`
  directory containing one Markdown concept document per module, recipe, blueprint, and
  prompt, each with frontmatter (`type`, `title`, `description`, `tags`, a `resource`
  pointer back to the authoritative `.dhall`) and a prose body.
- See the **composition graph** rendered as Markdown cross-links: a recipe links to the
  modules it composes, a blueprint links to its base modules, and a module links to its
  dependencies. Running `okf graph okf-docs --json` (the okf CLI) then yields the dependency
  DAG, and `okf index okf-docs --write` yields a catalog.
- Trust the output: the command runs okf-core's `validateBundle` before writing, so a
  generated cross-link that fails to resolve (for example, a dependency naming a module not
  in the registry) is reported instead of silently dropped.

Scope boundary. This initiative covers the seihou repository only: the `seihou-core`,
`seihou-cli`, and new `seihou-okf-extension` packages; the build wiring (cabal + flake)
needed to depend on `okf-core`; the extension host command; the extension's `docs` command;
its tests and fixtures; and seihou user documentation. It does
*not* modify `okf-core` itself (its authoring API is already complete and is treated as a
fixed dependency) and does not add Mori/Mina/BigQuery/LLM/network behavior. The generated
bundle is *derived* documentation: the `.dhall` artifacts remain the source of truth, and
each concept document carries a `resource` field pointing back at them, so regeneration —
not hand-editing — is the maintenance model.


## Decomposition Strategy

The work decomposes into five child plans by functional concern, layered from build
foundation to extension hosting, then domain loading, rendering, and the user-facing
extension command.

- EP-56 (build foundation) proves `okf-core` is a buildable dependency in this repository.
  `okf-core` is currently a *local-only* package in the `okf` repo with no reusable flake
  output, and seihou is a flake-parts project pinned to GHC 9.12.4. This plan wires okf-core
  in via **both** mechanisms the project needs: a `source-repository-package` in
  `cabal.project` (so plain `cabal build` and HLS resolve it) and a flake input plus a
  `callCabal2nix` overlay entry (so `nix build`/`nix develop` provide it). Its original smoke
  import in `seihou-cli-internal` is now treated as a build proof to be moved out by EP-60.
- EP-60 (extension foundation) introduces the extension contract and package boundary. It
  adds `seihou extension run <name> -- <args...>` to the main CLI, creates the
  `seihou-okf-extension` package and executable, and moves the `okf-core` dependency from
  `seihou-cli-internal` into that extension package. It is the hard prerequisite for the OKF
  model/render/command plans because those modules now live in `seihou-okf-extension`.
- EP-57 (domain loading) turns a registry into an in-memory **documentation model**: it
  reads `seihou-registry.dhall`, then loads each entry's full artifact
  (`Module`/`Recipe`/`Blueprint`/`AgentPrompt`) via the existing `Seihou.Dhall.Eval`
  loaders, and resolves the cross-references (module dependencies, recipe modules, blueprint
  base modules) into a structured value inside `seihou-okf-extension`. It imports only
  seihou's own types and *not* okf-core.
- EP-58 (rendering) maps the documentation model to okf-core `Concept` values: frontmatter
  via the okf authoring helpers, a prose body per entity, and cross-links rendered with
  okf-core's `renderConceptLink`. It validates with `validateBundle` and writes with
  `writeBundle`. It lives in `seihou-okf-extension` and needs EP-57's model plus the
  extension package and okf-core wiring from EP-60/EP-56.
- EP-59 (command + surfacing) replaces the extension package's stub `docs` command with the
  real `seihou-okf-extension docs` command, verifies it directly and through
  `seihou extension run okf -- docs ...`, and adds user documentation. It needs EP-58 and
  EP-60.

The principle is optional integration by package boundary: `seihou-cli` owns only the
extension host contract, `seihou-core` remains reusable domain logic, and
`seihou-okf-extension` owns every OKF-specific dependency and command. Alternatives
considered: a single ExecPlan (rejected — it spans the build system, extension host, a new
package, OKF rendering, tests, and docs); folding EP-57 into EP-58 (rejected — the loader is
okf-free and independently testable); and putting OKF directly in `seihou-cli-internal`
(rejected after review because future extensions are expected and optional integrations
should not expand the main CLI dependency graph).


## Exec-Plan Registry

| #     | Title | Path | Hard Deps | Soft Deps | Status |
|-------|-------|------|-----------|-----------|--------|
| EP-56 | Make okf-core a buildable dependency of seihou | docs/plans/56-make-okf-core-a-buildable-dependency-of-seihou.md | None | None | Complete |
| EP-60 | Add a seihou extension contract and okf extension package | docs/plans/60-add-a-seihou-extension-contract-and-okf-extension-package.md | EP-56 | None | Complete |
| EP-57 | Load a seihou registry into a documentation model | docs/plans/57-load-a-seihou-registry-into-a-documentation-model.md | EP-60 | None | Complete |
| EP-58 | Render the seihou documentation model to an OKF bundle | docs/plans/58-render-the-seihou-documentation-model-to-an-okf-bundle.md | EP-56, EP-57, EP-60 | None | Complete |
| EP-59 | Add the seihou okf extension docs command with fixture tests and user docs | docs/plans/59-add-the-seihou-docs-command-with-fixtures-tests-and-user-docs.md | EP-58, EP-60 | None | Complete |

Status values: Not Started, In Progress, Complete, Cancelled.
Hard Deps and Soft Deps reference other rows by their # prefix (e.g., EP-56).


## Dependency Graph

EP-56 is complete and proved okf-core can be resolved by cabal and Nix. EP-60 depends on it
because it reuses the pinned okf source and moves the consuming dependency into the new
extension package.

EP-57 depends on EP-60 because its model module now lives in `seihou-okf-extension`, not in
the private `seihou-cli-internal` library.

EP-58 has hard dependencies on EP-56, EP-57, and EP-60: it imports okf-core, consumes the
documentation model, and is compiled in the extension package. EP-59 has hard dependencies on
EP-58 and EP-60 because the real command replaces EP-60's stub and calls EP-58's render/write
functions.

Recommended order: EP-60, then EP-57, then EP-58, then EP-59. Critical path:
EP-56 → EP-60 → EP-57 → EP-58 → EP-59.


## Integration Points

1. **Extension host contract** (owned by EP-60). The main `seihou` executable supports
   `seihou extension run <name> -- <args...>`, resolves `seihou-<name>-extension` on `PATH`,
   forwards arguments unchanged, streams stdio, and exits according to the extension's exit
   status. EP-59 must verify the OKF command both directly and through this host contract.

2. **okf-core as a dependency, scoped to `seihou-okf-extension`.** EP-56 proved the pinned
   okf-core dependency works; EP-60 moves the consuming dependency out of
   `seihou-cli-internal` and into the new `seihou-okf-extension` package. Rationale:
   `seihou-core` and the main CLI should not gain documentation-rendering dependencies.
   EP-58's rendering module therefore lives under
   `seihou-okf-extension/src/Seihou/OKF/Docs/...`.

3. **The documentation model type** (defined by EP-57, consumed by EP-58). EP-57 defines a
   type — working name `DocModel` / `DocEntry` — that pairs each registry entry's catalog
   metadata (`name`, `version`, `description`, `tags`, `path` from
   `Seihou.Core.Registry.RegistryEntry`) with its fully loaded artifact
   (`Seihou.Core.Types.Module | Recipe | Blueprint | AgentPrompt`) and its kind. EP-57 is
   responsible for defining and exporting this type, `DocArtifact`, `DocKind`, `ModuleRef`,
   `DocLoadError`, and `loadDocModel`, and for resolving cross-references into it. EP-58
   consumes these exports read-only and must not redefine them. These modules live in
   `seihou-okf-extension`, not in `seihou-cli-internal`.

4. **The OKF concept-ID scheme and cross-link convention** (owned by EP-58). EP-58 maps each
   seihou entity to an OKF concept ID using the scheme `modules/<name>`, `recipes/<name>`,
   `blueprints/<name>`, `prompts/<name>` (names are unique within a kind, and module
   references in dependencies/recipe-modules/blueprint-baseModules are by bare name, so a
   reference to module `X` always renders as a link to concept `modules/X`). EP-58 builds
   cross-links with okf-core's `renderConceptLink (parseConceptId "modules/<name>") label`.
   EP-59's fixture and end-to-end test assert against this scheme, so if EP-58 changes it,
   EP-59 must be updated in lockstep.

5. **Frontmatter and validation-profile conventions** (owned by EP-58). EP-58 sets `type` to
   one of `SeihouModule`, `SeihouRecipe`, `SeihouBlueprint`, `SeihouPrompt`; `title` to the
   entity name; `description`, `tags`, and a `resource` field of the form
   `seihou://<repoName>/<path>` pointing back to the authoritative `.dhall`. Because OKF's
   strict profile requires a `timestamp` and seihou has no natural per-entity timestamp,
   EP-58 generates **without a timestamp by default and validates with
   `PermissiveConformance`** (which requires only a non-empty `type`); a `--strict` option
   and an explicit timestamp source are deferred to a later command surface. EP-58 also owns
   render-time errors such as an illegal seihou name that cannot become an OKF concept ID;
   these are represented separately from okf-core `BundleValidationError`s so callers can
   report both malformed IDs and bundle validation failures. EP-59's tests must use the same
   profile the command uses.

6. **The seihou plan/skill tooling.** All child plans use the repo's
   `agents/skills/exec-plan/init-plan.ts` (already done) and follow
   `agents/skills/exec-plan/PLANS.md`. Commits use the `MasterPlan:` and `ExecPlan:` git
   trailers plus `Intention: intention_01kvgg9k54efytmmeqty43t6y5`, per the seihou
   master-plan skill.


## Progress

Track milestone-level progress across all child plans.

- [x] EP-56: okf-core resolves under `cabal build` (source-repository-package) and builds in the Nix package set (flake input + callCabal2nix); smoke test compiles. (Full `nix build` of seihou-cli is blocked by a pre-existing, unrelated `baikai` skew — see Surprises.)
- [x] EP-60: `seihou extension run okf -- ...` can delegate to `seihou-okf-extension`; `okf-core` dependency lives in the extension package, not `seihou-cli-internal`
- [x] EP-57: `seihou-registry.dhall` loads into an extension-owned `DocModel` with full artifacts and resolved cross-references; unit tests on a fixture registry
- [x] EP-58: extension-owned `DocModel` renders to `[Concept]` with cross-links; `validateBundle` clean; `writeBundle` emits the bundle; unit/golden tests
- [x] EP-59: `seihou-okf-extension docs --dir --out` and hosted invocation through `seihou extension run okf -- docs ...` work end to end on a fixture registry; user docs added; okf-core validation of the output passes


## Surprises & Discoveries

Document cross-plan insights, dependency changes, scope adjustments, or unexpected
interactions between child plans. Provide concise evidence.

- EP-56 found that seihou's full `nix build` fails compiling seihou-cli against `baikai`,
  **independent of this initiative**. The cause is an in-progress `baikai` migration in the
  working tree: an uncommitted edit in `seihou-cli/src/Seihou/CLI/AgentCompletion.hs`
  (`Baikai.userNow` → `Baikai.user`) migrates the library, but the test suite still uses the old
  baikai API (`Baikai.AssistantPayload` in `AgentCompletionSpec.hs`), so `nix build`'s `doCheck`
  fails there. The `cabal build` / dev-shell path is unaffected (it doesn't compile the test
  suites). Cross-plan impact: EP-60 and EP-59 should validate the extension path with dev-shell
  `cabal` commands until the baikai migration is finished (a separate task — finish migrating
  the seihou-cli test suite to the new baikai API). okf-core itself builds fine in Nix; only
  the downstream seihou-cli build is affected. Evidence: reproduced on pristine HEAD by stashing
  all changes + the WIP; `git diff flake.lock` adds only the `okf-src` node.
- EP-60 found that `nix build .#seihou-okf-extension` cannot evaluate a new package directory
  until that directory is tracked by git, because flake sources are taken from the git
  worktree snapshot. After staging the new extension package and wiring, the Nix package
  output built successfully. Cross-plan impact: future child plans that add files under
  `seihou-okf-extension` should stage those files before validating Nix outputs.
- EP-60 found that Cabal rejects `license-file: ../LICENSE` for the new package because the
  path escapes the package source tree. The extension package now carries its own `LICENSE`
  file. Cross-plan impact: later packaging work should keep package metadata self-contained.
- EP-57 found that examples and downstream code must use record-dot syntax or constructor
  patterns because seihou packages enable `NoFieldSelectors`. Cross-plan impact: EP-58 and
  EP-59 should read `DocModel` with `model.docEntries`, `entry.entryName`, and similar
  record-dot access; examples using `docEntries model` will not compile.
- EP-57 uses temp-dir raw Dhall fixtures instead of checked-in files with remote schema
  imports. Cross-plan impact: EP-58 and EP-59 can reuse this style for focused loader and
  command fixtures when they need deterministic, offline tests.
- EP-58 found that the `okf` CLI was not available on `PATH` during validation. Cross-plan
  impact: EP-59 should validate the command primarily through the extension's library path
  and can run external `okf` CLI checks only when the CLI is available.
- EP-58 added a direct `aeson` dependency to `seihou-okf-extension` for the `version`
  frontmatter field. Cross-plan impact: EP-59 does not need to add this dependency again.
- EP-59 found that EP-60's optparse-based host parser did not preserve forwarded arguments
  after `--`. The main `seihou` executable now detects `extension run NAME -- ...` from raw
  argv before normal optparse dispatch, preserving the required hosted syntax.


## Decision Log

- Decision: Build the feature as `seihou-okf-extension`, an extension package that consumes
  okf-core as a library, rather than shelling out to the `okf` CLI or putting the generator in
  the main `seihou-cli` package.
  Rationale: A library dependency gives typed access to the okf authoring API
  (`conceptFromDocument`, `validateBundle`, `writeBundle`, `renderConceptLink`), while the
  extension package keeps optional OKF dependencies out of the main CLI. okf's own MasterPlan
  2 explicitly intends integrations to "consume the core library surface rather than shelling
  out to the CLI".
  Date: 2026-06-19

- Decision: Wire okf-core via BOTH a `cabal.project` `source-repository-package` and a flake
  input + `callCabal2nix` overlay entry.
  Rationale: The project builds two ways. Plain `cabal build`/HLS need the package resolvable
  from `cabal.project`; `nix build`/`nix develop` need it in the Nix-provided package set.
  Supplying only one breaks the other workflow. (Per the user's explicit instruction to add a
  source-repository-package for cabal builds in addition to the Nix wiring.)
  Date: 2026-06-19

- Decision: Initially scoped the okf-core dependency to `seihou-cli-internal`, not
  `seihou-core`; this decision is superseded by the later `seihou-okf-extension` package
  boundary.
  Rationale: The original goal was to keep the reusable core library free of a
  documentation-rendering dependency. The extension revision keeps both `seihou-core` and the
  main CLI free of okf-core by moving the consuming dependency into `seihou-okf-extension`.
  Date: 2026-06-19

- Decision: Supersede the in-core `seihou docs` direction with a first-class extension
  package, `seihou-okf-extension`.
  Rationale: The user expects multiple future extensions. Keeping OKF in a separate package
  preserves optional dependency boundaries and turns the OKF generator into the first
  concrete implementation of a reusable extension contract.
  Date: 2026-06-19

- Decision: The host syntax is `seihou extension run <name> -- <args...>` and the OKF
  executable is `seihou-okf-extension`.
  Rationale: This fits the current explicit optparse command tree without dynamic
  unknown-command dispatch, gives future extensions a stable executable naming convention,
  and still allows direct extension execution in tests and scripts.
  Date: 2026-06-19

- Decision: Default to generating documents without a `timestamp` and validating with
  `PermissiveConformance`; defer `--strict` and a timestamp source until a future plan defines
  deterministic timestamp semantics.
  Rationale: Seihou entities have no natural per-entity timestamp, and stamping wall-clock
  time would make regenerated bundles churn. Omitting it keeps output deterministic; the
  richer fields (`title`, `description`, `tags`, `resource`) still make the docs useful.
  Date: 2026-06-19

- Decision: Keep the first `seihou-okf-extension docs` command surface permissive only; do not add
  `--strict` until there is a deterministic timestamp source.
  Rationale: The command plan does not currently define timestamp input semantics, and adding
  a strict flag without that source would either fail by default or tempt wall-clock stamps
  that make regenerated bundles non-deterministic.
  Date: 2026-06-19

- Decision: Treat okf-core as a pinned, explicit local/repository dependency rather than a
  Mori-registered project for this initiative.
  Rationale: `mori registry search okf` returns no registered project as of this validation,
  while EP-56 already pins `shinzui/okf` by commit through cabal and Nix. The plan must
  continue to read okf-core source directly from the explicit checkout or pinned remote until
  okf is added to Mori.
  Date: 2026-06-19

- Decision: Primary input is a registry repository selected with `--dir` (read its
  `seihou-registry.dhall` and load each entry), mirroring `seihou registry validate`.
  Rationale: The request is to document "the seihou modules, blueprints, prompts, and
  recipes" of a registry, and the registry file is the explicit catalog. Search-path
  discovery (`discoverAllRunnables`, as used by `seihou list`) is recorded as a possible
  future alternative mode but is out of scope for the first version.
  Date: 2026-06-19


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion. Compare
the result against the original vision.

EP-60 completed the extension foundation. The main `seihou` executable now supports
`seihou extension run <name> -- <args...>`, and the new `seihou-okf-extension` package is
buildable through Cabal and Nix with the OKF dependency scoped to the extension package.
At that milestone the command exposed a non-zero `docs` placeholder; EP-59 later replaced it
with the real docs command after EP-57 and EP-58 supplied registry loading and OKF rendering.

EP-57 completed the extension-owned documentation model. `loadDocModel` now loads a registry
directory into full module, recipe, blueprint, and prompt entries, preserving catalog
metadata and resolving module references as present or dangling without importing okf-core.
The loader passes fixture tests and a spot-check against
`/Users/shinzui/Keikaku/bokuno/seihou-modules` with `(8,"seihou-modules")`.

EP-58 completed OKF rendering for the documentation model. `renderDocBundle` now produces
okf-core concepts with deterministic frontmatter, resource pointers, and Markdown graph
links, while `writeDocBundle` validates and writes only clean bundles. A spot-check wrote the
real `seihou-modules` registry to `/tmp/seihou-okf-demo` as eight Markdown concepts.

EP-59 completed the user-facing command. `seihou-okf-extension docs --dir --out --force` and
`seihou extension run okf -- docs --dir --out --force` both generate the real
`seihou-modules` OKF bundle with 8 concepts, and forced repeated runs are deterministic by
`diff -r`.


## Revision Notes

- 2026-06-19: Validated the MasterPlan and child plan contracts against the current seihou
  repository and okf-core source. Updated the plan to use fenced command examples, explicitly
  name the EP-57 exports consumed by EP-58, separate EP-58 render errors from okf-core bundle
  validation errors, defer strict/timestamp CLI behavior, and record that okf-core is not yet
  Mori-registered.
- 2026-06-19: Revised the initiative from an in-core `seihou docs` command to an extension
  architecture. Added EP-60 for the extension host and `seihou-okf-extension` package,
  retargeted EP-57/EP-58/EP-59 to the extension package, and updated dependency and
  integration sections so `okf-core` is no longer a final dependency of `seihou-cli-internal`.
- 2026-06-19: Marked EP-60 complete after implementing the extension host, adding the
  `seihou-okf-extension` package, moving OKF dependency ownership into that package, adding
  tests and docs, and validating with Cabal, Nix, formatter, and command smoke checks.
- 2026-06-19: Marked EP-57 complete after implementing `Seihou.OKF.Docs.Model`, adding
  temp-dir loader tests for all registry kinds and resolved/unresolved module references,
  and validating the loader against the real `seihou-modules` registry.
- 2026-06-19: Marked EP-58 complete after implementing `Seihou.OKF.Docs.Render`, adding
  render tests for concept IDs, frontmatter, cross-links, clean validation, dangling
  references, and invalid concept IDs, and writing a real `seihou-modules` OKF bundle.
- 2026-06-19: Marked EP-59 complete after replacing the docs stub with the real command,
  validating direct and hosted real-registry runs, adding command-flow tests and user docs,
  and fixing hosted argv forwarding.
