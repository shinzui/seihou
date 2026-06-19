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

After this initiative, the `seihou` command-line tool can turn a seihou registry into a
browsable, linked documentation set with one command:

    seihou docs --dir <registry-repo> --out <output-dir>

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
completed in that project's MasterPlan 2. This initiative makes seihou *consume* that API.

Concretely, after this work a user can:

- Run `seihou docs --dir .` inside `seihou-modules` and get an `okf-docs/` directory
  containing one Markdown concept document per module, recipe, blueprint, and prompt, each
  with frontmatter (`type`, `title`, `description`, `tags`, a `resource` pointer back to the
  authoritative `.dhall`) and a prose body.
- See the **composition graph** rendered as Markdown cross-links: a recipe links to the
  modules it composes, a blueprint links to its base modules, and a module links to its
  dependencies. Running `okf graph okf-docs --json` (the okf CLI) then yields the dependency
  DAG, and `okf index okf-docs --write` yields a catalog.
- Trust the output: the command runs okf-core's `validateBundle` before writing, so a
  generated cross-link that fails to resolve (for example, a dependency naming a module not
  in the registry) is reported instead of silently dropped.

Scope boundary. This initiative covers the seihou repository only: the `seihou-core` and
`seihou-cli` packages, the build wiring (cabal + flake) needed to depend on `okf-core`, the
new `seihou docs` command, its tests and fixtures, and seihou user documentation. It does
*not* modify `okf-core` itself (its authoring API is already complete and is treated as a
fixed dependency) and does not add Mori/Mina/BigQuery/LLM/network behavior. The generated
bundle is *derived* documentation: the `.dhall` artifacts remain the source of truth, and
each concept document carries a `resource` field pointing back at them, so regeneration —
not hand-editing — is the maintenance model.


## Decomposition Strategy

The work decomposes into four child plans by functional concern, layered from build
foundation up to the user-facing command. The two lowest layers are independent and can be
built in parallel; the upper two each depend on the layer below.

- EP-56 (build foundation) makes `okf-core` a buildable dependency of seihou. `okf-core` is
  currently a *local-only* package in the `okf` repo with no reusable flake output, and
  seihou is a flake-parts project pinned to GHC 9.12.4. This plan wires okf-core in via
  **both** mechanisms the project needs: a `source-repository-package` in `cabal.project`
  (so plain `cabal build` and HLS resolve it) and a flake input plus a `callCabal2nix`
  overlay entry (so `nix build`/`nix develop` provide it). It stands alone and is the hard
  prerequisite for any code that imports okf-core.
- EP-57 (domain loading) turns a registry into an in-memory **documentation model**: it
  reads `seihou-registry.dhall`, then loads each entry's full artifact
  (`Module`/`Recipe`/`Blueprint`/`AgentPrompt`) via the existing `Seihou.Dhall.Eval`
  loaders, and resolves the cross-references (module dependencies, recipe modules, blueprint
  base modules) into a structured value. It imports only seihou's own types and *not*
  okf-core, so it can be built and tested in parallel with EP-56.
- EP-58 (rendering) maps the documentation model to okf-core `Concept` values: frontmatter
  via the okf authoring helpers, a prose body per entity, and cross-links rendered with
  okf-core's `renderConceptLink`. It validates with `validateBundle` and writes with
  `writeBundle`. It needs both EP-56 (okf-core available) and EP-57 (the model).
- EP-59 (command + surfacing) adds the `seihou docs` subcommand (parser, options, handler)
  following seihou's CLI library-first convention, an end-to-end test against a fixture
  registry, and seihou user documentation. It needs EP-58.

The principle is layering with a thin foundation: isolate the cross-repo build risk in one
plan (EP-56), keep the pure seihou domain work (EP-57) free of any okf dependency so it can
proceed immediately, and keep the okf-specific mapping (EP-58) in one place. Alternatives
considered: a single ExecPlan (rejected — it spans the build system, seihou-core, the CLI,
tests, and docs, far beyond the ExecPlan size threshold); folding EP-57 into EP-58 (rejected
— separating the okf-free loader from the okf-dependent renderer lets EP-57 start before the
build wiring lands and keeps each independently testable); and putting the doc code in
`seihou-core` (rejected — see Integration Points: the okf-core dependency is scoped to
`seihou-cli-internal` to keep the reusable core library free of it).


## Exec-Plan Registry

| #     | Title | Path | Hard Deps | Soft Deps | Status |
|-------|-------|------|-----------|-----------|--------|
| EP-56 | Make okf-core a buildable dependency of seihou | docs/plans/56-make-okf-core-a-buildable-dependency-of-seihou.md | None | None | Complete |
| EP-57 | Load a seihou registry into a documentation model | docs/plans/57-load-a-seihou-registry-into-a-documentation-model.md | None | None | Not Started |
| EP-58 | Render the seihou documentation model to an OKF bundle | docs/plans/58-render-the-seihou-documentation-model-to-an-okf-bundle.md | EP-56, EP-57 | None | Not Started |
| EP-59 | Add the seihou docs command with fixtures tests and user docs | docs/plans/59-add-the-seihou-docs-command-with-fixtures-tests-and-user-docs.md | EP-58 | EP-56 | Not Started |

Status values: Not Started, In Progress, Complete, Cancelled.
Hard Deps and Soft Deps reference other rows by their # prefix (e.g., EP-56).


## Dependency Graph

EP-56 and EP-57 have no dependencies and may be implemented in parallel. EP-56 touches the
build system (`cabal.project`, `flake.nix`/`nix/`, the `seihou-cli-internal` cabal stanza)
and adds a trivial smoke-test use of okf-core. EP-57 adds a new module under
`seihou-cli/src/Seihou/CLI/Docs/` (and possibly small helpers in `seihou-core`) that imports
only seihou types; it does not touch the build wiring beyond adding its module to the cabal
`exposed-modules`.

EP-58 has hard dependencies on both: it imports okf-core (so EP-56's wiring must exist or the
module will not compile) and consumes the documentation model type defined by EP-57. It is
the integration point where the two lower layers meet.

EP-59 has a hard dependency on EP-58 (the command handler calls the render+write function
EP-58 provides) and a soft dependency on EP-56 (the executable target also needs okf-core on
its build path if any okf type appears in handler signatures; in practice the handler only
needs seihou types and the EP-58 function, so the soft edge covers the case where error
rendering references okf-core's `BundleValidationError`).

Recommended order: EP-56 and EP-57 first (parallel), then EP-58, then EP-59. Critical path:
EP-56 → EP-58 → EP-59 (with EP-57 feeding EP-58).


## Integration Points

1. **okf-core as a dependency, scoped to `seihou-cli-internal`.** EP-56 adds `okf-core` to
   the `build-depends` of the `seihou-cli-internal` private library (in
   `seihou-cli/seihou-cli.cabal`), *not* to `seihou-core`. Rationale: `seihou-core` is the
   reusable core and should not gain a documentation-rendering dependency. EP-58's rendering
   module therefore lives in `seihou-cli-internal` (`seihou-cli/src/Seihou/CLI/Docs/...`).
   EP-57's loader also lives there (it can call the `seihou-core` `Seihou.Dhall.Eval`
   loaders without seihou-core itself depending on okf-core). EP-56 owns the cabal/flake
   wiring; EP-57 and EP-58 consume it; EP-59's executable wiring (in `src-exe/`) inherits it
   through `seihou-cli-internal`.

2. **The documentation model type** (defined by EP-57, consumed by EP-58). EP-57 defines a
   type — working name `DocModel` / `DocEntry` — that pairs each registry entry's catalog
   metadata (`name`, `version`, `description`, `tags`, `path` from
   `Seihou.Core.Registry.RegistryEntry`) with its fully loaded artifact
   (`Seihou.Core.Types.Module | Recipe | Blueprint | AgentPrompt`) and its kind. EP-57 is
   responsible for defining and exporting this type and for resolving cross-references into
   it; EP-58 consumes it read-only and must not redefine it. The exact shape is specified in
   EP-57 and referenced by EP-58.

3. **The OKF concept-ID scheme and cross-link convention** (owned by EP-58). EP-58 maps each
   seihou entity to an OKF concept ID using the scheme `modules/<name>`, `recipes/<name>`,
   `blueprints/<name>`, `prompts/<name>` (names are unique within a kind, and module
   references in dependencies/recipe-modules/blueprint-baseModules are by bare name, so a
   reference to module `X` always renders as a link to concept `modules/X`). EP-58 builds
   cross-links with okf-core's `renderConceptLink (parseConceptId "modules/<name>") label`.
   EP-59's fixture and end-to-end test assert against this scheme, so if EP-58 changes it,
   EP-59 must be updated in lockstep.

4. **Frontmatter and validation-profile conventions** (owned by EP-58). EP-58 sets `type` to
   one of `SeihouModule`, `SeihouRecipe`, `SeihouBlueprint`, `SeihouPrompt`; `title` to the
   entity name; `description`, `tags`, and a `resource` field of the form
   `seihou://<repoName>/<path>` pointing back to the authoritative `.dhall`. Because OKF's
   strict profile requires a `timestamp` and seihou has no natural per-entity timestamp,
   EP-58 generates **without a timestamp by default and validates with
   `PermissiveConformance`** (which requires only a non-empty `type`); a `--strict` option
   and an explicit timestamp source are deferred to EP-59's command surface. EP-59's tests
   must use the same profile the command uses.

5. **The seihou plan/skill tooling.** All child plans use the repo's
   `agents/skills/exec-plan/init-plan.ts` (already done) and follow
   `agents/skills/exec-plan/PLANS.md`. Commits use the `MasterPlan:` and `ExecPlan:` git
   trailers plus `Intention: intention_01kvgg9k54efytmmeqty43t6y5`, per the seihou
   master-plan skill.


## Progress

Track milestone-level progress across all child plans.

- [x] EP-56: okf-core resolves under `cabal build` (source-repository-package) and builds in the Nix package set (flake input + callCabal2nix); smoke test compiles. (Full `nix build` of seihou-cli is blocked by a pre-existing, unrelated `baikai` skew — see Surprises.)
- [ ] EP-57: `seihou-registry.dhall` loads into a `DocModel` with full artifacts and resolved cross-references; unit tests on a fixture registry
- [ ] EP-58: `DocModel` renders to `[Concept]` with cross-links; `validateBundle` clean; `writeBundle` emits the bundle; unit/golden tests
- [ ] EP-59: `seihou docs --dir --out` works end to end on a fixture registry; user docs added; `okf validate` of the output passes


## Surprises & Discoveries

Document cross-plan insights, dependency changes, scope adjustments, or unexpected
interactions between child plans. Provide concise evidence.

- EP-56 found that seihou's full `nix build` fails compiling seihou-cli against `baikai`,
  **independent of this initiative**. The cause is an in-progress `baikai` migration in the
  working tree: an uncommitted edit in `seihou-cli/src/Seihou/CLI/AgentCompletion.hs`
  (`Baikai.userNow` → `Baikai.user`) migrates the library, but the test suite still uses the old
  baikai API (`Baikai.AssistantPayload` in `AgentCompletionSpec.hs`), so `nix build`'s `doCheck`
  fails there. The `cabal build` / dev-shell path is unaffected (it doesn't compile the test
  suites). Cross-plan impact: EP-59's end-to-end test and any `nix build`-based CI for the docs
  feature should run under the dev-shell `cabal` path until the baikai migration is finished
  (a separate task — finish migrating the seihou-cli test suite to the new baikai API). okf-core
  itself builds fine in Nix; only the downstream seihou-cli build is affected. Evidence:
  reproduced on pristine HEAD by stashing all changes + the WIP; `git diff flake.lock` adds only
  the `okf-src` node.


## Decision Log

- Decision: Build the feature as a new `seihou docs` subcommand that consumes okf-core as a
  library, rather than shelling out to the `okf` CLI or building a standalone generator.
  Rationale: A library dependency gives typed access to the okf authoring API
  (`conceptFromDocument`, `validateBundle`, `writeBundle`, `renderConceptLink`) and keeps the
  feature inside the tool users already run. okf's own MasterPlan 2 explicitly intends
  integrations to "consume the core library surface rather than shelling out to the CLI".
  Date: 2026-06-19

- Decision: Wire okf-core via BOTH a `cabal.project` `source-repository-package` and a flake
  input + `callCabal2nix` overlay entry.
  Rationale: The project builds two ways. Plain `cabal build`/HLS need the package resolvable
  from `cabal.project`; `nix build`/`nix develop` need it in the Nix-provided package set.
  Supplying only one breaks the other workflow. (Per the user's explicit instruction to add a
  source-repository-package for cabal builds in addition to the Nix wiring.)
  Date: 2026-06-19

- Decision: Scope the okf-core dependency to `seihou-cli-internal`, not `seihou-core`.
  Rationale: Keeps the reusable core library free of a documentation-rendering dependency;
  the docs feature is a CLI capability, and seihou's "CLI library-first" convention already
  places feature logic in `seihou-cli-internal`.
  Date: 2026-06-19

- Decision: Default to generating documents without a `timestamp` and validating with
  `PermissiveConformance`; defer `--strict` and a timestamp source to the command plan.
  Rationale: Seihou entities have no natural per-entity timestamp, and stamping wall-clock
  time would make regenerated bundles churn. Omitting it keeps output deterministic; the
  richer fields (`title`, `description`, `tags`, `resource`) still make the docs useful.
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

(To be filled during and after implementation.)
