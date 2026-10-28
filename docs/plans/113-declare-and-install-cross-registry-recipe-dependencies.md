---
id: 113
slug: declare-and-install-cross-registry-recipe-dependencies
title: "Declare and install cross-registry recipe dependencies"
kind: exec-plan
created_at: 2026-10-28T12:31:19Z
intention: "intention_01m617vxdmeqfaq0z518dz5e65"
provenance:
  created_by:
    model: "gpt-6-astra"
    harness: "codex-cli"
    at: 2026-10-28T12:31:19Z
  revisions:
    - model: "gpt-6.1-sol"
      harness: "codex-cli"
      at: 2026-10-28T12:57:06Z
      mode: "implement"
      note: "Implement source declarations and dependency closure installation"
    - model: "gpt-6.1-sol"
      harness: "codex-cli"
      at: 2026-10-28T14:22:49Z
      mode: "update"
      note: "Link completed request and deliver the authorized coordinated release."
---

# Declare and install cross-registry recipe dependencies

This ExecPlan is a living document. Keep Progress, Surprises & Discoveries, Decision Log, and Outcomes & Retrospective current. Record implementation friction using agents/skills/exec-plan/FRICTION.md and distill durable decisions into docs/adr/ before completion.

## Purpose / Big Picture


Implement [IR-12](../improvement-requests/declare-and-install-cross-registry-recipe-dependencies.md): a producer declares which Git registry supplies each external dependency, and a developer installs a recipe with one ordinary `seihou install SOURCE --module RECIPE` command. Installation acquires the dependency closure, meaning every directly or indirectly required module, without installing unrelated entries. The developer then runs `seihou run RECIPE` with the recipe's ordinary inputs. No transitive module list, registry-wide installs, source-path edits, or installer wrapper is required.

The starting state is a fresh machine or worktree with no installed artifacts. The same two-command workflow must work for an existing installation missing dependencies: reinstall the selected recipe, then run it. Acquisition belongs to install; run and dry-run remain local and never populate the machine-wide install cache. This plan includes the same-registry prerequisite in [BUG-2](../bug-reports/install-ignores-recipe-and-module-dependencies.md), schema integration and released executable evidence; downstream TAN producer implementation is separately owned as recorded in the release scope decision. Creating this plan does not implement or publish those changes.

## Progress


- [x] (2026-10-28) Source declarations decode compatibly, retain variable bindings, and roundtrip installed legacy names. The committed three-registry fixture expresses local, external, and transitive external edges. The initial candidate was integrated with upstream and published at `d3c78cd81d9697ebff3128732ec673a17e65c73f` in `mori://shinzui/seihou-schema`.
- [x] (2026-10-28) One ordinary install acquires exactly `local`, `leaf`, `external`, and `root` with their own origins. The public-command harness verifies missing/unavailable sources, cycles, contradictory origins even with force, repeat install, and preservation of cache markers on refusal.
- [x] (2026-10-28) Source requirements survive recipe expansion and staged definitions; run, agent baselines, recursive modules, and update check requirements locally. Public-command checks cover offline dry-run cache equality, local shadows, collisions/force, diamond closure, retry, and legacy names. Core, CLI, and extension suites pass; final evidence is recorded below.
- [x] (2026-10-28) Published schema and Seihou 0.12.0.1 pass the installed three-registry install/run and failure/recovery workflow. Native packaging, documentation and delivery evidence are complete; downstream TAN publication remains separately owned under the user-directed scope decision.

## Surprises & Discoveries

2026-10-28: The complete published-tag Nix build caught native CLI test environment
gaps after the source and flake checks passed: Python process fixtures lacked their
interpreter, and copying the schema's unrelated `mori.dhall` triggered a network import
in offline fixture installation. FRIC-5 records the detour. Fix the test inputs and
copy only schema definitions, then deliver the patch release through a full native
package build before publication. No source-only success substitutes for this gate.


2026-10-28: The user supplied the checkout for `mori://tan/tan-seihou-modules`. Its verified remote is `https://github.com/topagentnetwork/tan-seihou-modules.git`, and its planned recipe is `tan-keiro-project`. The registry contains no artifacts. Its MasterPlan explicitly gates all TAN implementation on Seihou's source-install, prompt, validation, and receipt prerequisites; no TAN scaffolding was implemented here. An isolated ordinary install from the committed local checkout exits 1 with “tan-keiro-project” not found. FRIC-4 in docs/friction-log/ records this delivery blocker.

2026-10-28: Inferring implicit origins at runtime imposed new requirements on older installed definitions and displaced existing manifest-guard diagnostics. Installation now materializes implicit sources in dependency records while cloning context is available. Legacy cache files retain their behavior until reinstall; synthetic recipe/CLI additional edges never inherit the primary module's origin.

2026-10-28: Normalizing legacy bare dependencies requires typed empty variable-binding lists in the emitted Dhall. A public run after reinstall caught an invalid list annotation that decoding alone missed; the installed-definition roundtrip test and the executable legacy check now cover it.

## Decision Log

2026-10-28: The user requested completion of EPs 113–115 and their requests together
with the coordinated release. Close Seihou's prerequisite delivery against the published
schema/executable and the ordinary three-registry acceptance fixture. TAN recipe/module
implementation and its eventual consumer integration remain owned by
`mori://tan/tan-seihou-modules/plans/3-publish-and-verify-the-tan-keiro-project-recipe`;
there is no claim that this still-unimplemented producer was tested. This supersedes
the earlier requirement to keep this Seihou plan open until TAN producer publication.


2026-10-28: Keep the schema candidate local until publication. The tracked schema gitlink and public Nix input/lock pins remain unchanged together; the working checkout uses candidate `3b04970`. The authoritative schema remote HEAD was `211cd628cb7dd1a0b5ec7306c78a603f67b950bd` and had no release tags when checked. Integrate the local candidate into current upstream before publishing; do not force-push over newer upstream work. Publishing the integrated candidate and advancing all three references remains milestone 4, alongside the compatible executable and TAN producer. Do not mark source verification as installed-version delivery.

2026-10-28: Blueprint install validates payloads and dependency declaration syntax without consulting the user's installed search paths. The closure planner owns source/name/kind resolution, so an empty cache is supported. Ordinary blueprint authoring validation retains its existing local resolution behavior.

2026-10-28: Put an optional Git source on each dependency edge rather than infer sources from Mori or search all known registries. The declaring producer owns the choice, and an absent source means the registry containing that declaration during installation. This covers recipes and transitive module dependencies with one contract.

2026-10-28: Preserve the flat installed-name namespace and existing explicit `--force` policy for replacing an existing installation. Two different origins required under one name within the requested closure are always an error, even with `--force`: replacing one cannot satisfy both requirements. Generation never fetches dependencies. These choices preserve ADRs 0002, 0003, and 0006.

2026-10-28: Include same-registry closure and delivery adoption in this work. Separate requests about recipe prompt ordering and standalone recipe validation remain outside scope unless their behavior directly prevents this plan's ordinary-path acceptance. No general version solver, new lockfile, cache namespace migration, or runtime Mori dependency is introduced.

## Outcomes & Retrospective


The Seihou prerequisite implementation and published/installed delivery are complete.
At the initial source-only checkpoint the schema candidate was local and the installed
0.11.0.1 executable still reproduced the defect; the released evidence below supersedes
that delivery gap. TAN producer implementation remains tracked by its own plan.

Initial source validation passed `nix develop -c cabal test all`: 1,254 core tests, 785 CLI tests, and 51 extension tests (2,090 total). `nix develop -c cabal build all`, `nix fmt`, strict friction-bundle validation, and `git diff --check` also passed. The source executable reports `seihou v0.11.0.1 (be31390)` because it was compiled from that base commit plus this implementation working tree; this is not a released version.

The source executable is resolved with `nix develop -c cabal list-bin exe:seihou` and lives under `dist-newstyle/build/aarch64-osx/ghc-9.12.4/seihou-cli-0.11.0.1/x/seihou/build/seihou/seihou`. `bash scripts/test-install-closure.sh <that absolute path>` exercises the ordinary install/run pair in committed isolated Git repositories and verifies the complete failure/recovery matrix. The fixture maps `root`/`local` to registry `a`, `external` to registry `b`, and `leaf` to registry `c`; all unrelated sentinel entries remain absent. Each temporary absolute Git origin is printed in the command output. No developer cache or project is modified. The fixture has no ordinary recipe inputs; variable-binding preservation is checked separately in decoder and composition tests.

The real intended consumer commands are:

```bash
seihou install https://github.com/topagentnetwork/tan-seihou-modules.git --module tan-keiro-project
seihou run tan-keiro-project
```

These remain intended commands, not successful consumer evidence: the producer's recipe and both prerequisite TAN modules do not yet exist. Normal inputs and integration acceptance remain owned by `mori://tan/tan-seihou-modules/plans/3-publish-and-verify-the-tan-keiro-project-recipe`, gated by its parent MasterPlan. FRIC-4 is accepted as downstream TAN work under the user-directed Seihou closure. FRIC-5 is resolved by the Python test-tool and offline-schema-fixture fixes in 0.12.0.1, verified by the complete native package build. Durable source/acquisition and compatibility rules are distilled into [ADR 0020](../adr/0020-dependency-sources-belong-to-producer-edges.md).

### Released and installed delivery (2026-10-28)


Seihou 0.12.0.1 is published for `seihou-core`, `seihou-cli` and
`seihou-okf-extension`, including API documentation. The GitHub release/tag is
`v0.12.0.1`, at revision `f529a7ab63609c7494240d12e52b541bf7e3643b`.
The dependency-source schema is published at
`d3c78cd81d9697ebff3128732ec673a17e65c73f` in `mori://shinzui/seihou-schema`;
the schema gitlink, emitted Dhall URL/integrity hash and Nix input/lock agree.

The effective installed executable is `/Users/shinzui/.nix-profile/bin/seihou`,
reporting `seihou v0.12.0.1 (f529a7a)`. Its Nix profile records
`github:shinzui/seihou/v0.12.0.1`, resolving to that same revision. The standalone
entry has priority 4 to preserve and override the Home Manager entry at priority 5.
The source build and installed binary are separately verified.

Source checks passed all 2,134 tests (1,271 core, 812 CLI, 51 extension), build,
formatting, package checks, documentation audit and four native flake checks.
The complete native Nix package build also passed all 2,134 tests before patch
publication. Its evidence is `/tmp/seihou-release-patch-native.log`; incompatible
platforms were not exercised. The audit covers 18 topics, 33 command pages plus
agent run, 26 assets, six validated examples and eight provider-free prompt renders.

Installed acceptance passed the following ordinary workflows, with isolated XDG
state and no real remote provisioning:

```bash
bash scripts/test-install-closure.sh /Users/shinzui/.nix-profile/bin/seihou
python3 scripts/verify-recipe-inputs.py --binary /Users/shinzui/.nix-profile/bin/seihou --area /tmp/seihou-release-0121-installed-inputs --consumer
```

The first verifies the required three-registry closure, origins, run, dry-run
cache equality, repeat install, missing/unavailable sources, collision/force,
contradictory origins, cycles, diamonds, local shadows and legacy declarations.
The second verifies terminal true/false questions once, saved recipe inputs,
fresh-clone and new-consumer replay, and representative real-module consumers
with provisioning commands disabled. It is not a published TAN recipe.

Installed `validate-recipe` also passed the unmodified unpublished-member scaffold,
current-directory invocation, an unanswered conditional recipe in a directory with
spaces, help and top-level discovery. Empty members, an undeclared prompt and
malformed Dhall exited 1 with contextual messages; missing descriptors exited 4.
Snapshots showed no project/configuration/install changes. Retained validation
fixtures are `/tmp/seihou-release-0121-validation-8_oilm8b`; transcripts are
`/tmp/seihou-release-installed-closure.log`,
`/tmp/seihou-release-installed-inputs.log` and
`/tmp/seihou-release-installed-validation.log`.

Python is used only by test/acceptance harnesses, not by the Seihou executable.
The three changed requests passed scoped strict profile/log validation. The full
legacy request corpus retains its pre-existing recommended-field diagnostics on
untouched requests.

## Context and Orientation

The orientation below describes the pre-implementation baseline. Current behavior and delivery evidence are recorded above.


A registry is a Git repository with `seihou-registry.dhall` listing named artifacts and their directories. A recipe lists module dependencies; modules can themselves depend on modules. `seihou-cli/src-exe/Seihou/CLI/Install.hs` owns source selection, repository discovery, and `installSingleRecipe`, `installSingleModule`, `installFromRegistry`, and `installRegistryEntry`. Currently it installs selected directories individually. Recipe branches copy a definition without following its members. `seihou-core/src/Seihou/Core/Install.hs` only supplies name parsing; it is not the installer engine.

`seihou-cli/src/Seihou/CLI/InstallShared.hs` owns cloning, recorded source selection, collision checks, directory copying, and `.seihou-origin.json`. `installedRoot` honors `XDG_CONFIG_HOME`. Its `installModuleDirInto` currently removes an accepted existing directory before copying its replacement, so a closure implementation must stage work before invoking destructive replacement. `seihou-core/src/Seihou/Core/ArtifactIdentity.hs` owns URL equivalence. Reuse it, including its limited public GitHub SSH/HTTPS equivalence; do not infer identity from equal contents or redirects.

`seihou-core/src/Seihou/Core/Types.hs` defines `Dependency` as a module name plus variable bindings. `seihou-core/src/Seihou/Dhall/Eval.hs` has a custom `dependencyDecoder` accepting both bare text and records. `schema/Dependency.dhall` is the schema submodule's producer contract; `schema/Recipe.dhall` uses it, as do module and blueprint declarations. `seihou-core/src/Seihou/Composition/Recipe.hs` currently expands dependencies into names, while `seihou-core/src/Seihou/Composition/Resolve.hs` loads names recursively from search paths. Both need attention to avoid discarding a declared source. Acquisition identity is separate from composition instances: the same installed module can run with different variable bindings.

The upstream schema is `mori://shinzui/seihou-schema/packages/seihou-schema`; its project-relative `Dependency.dhall` and `package.dhall` have artifact-level URIs pending. Mori located its checkout and the inspected Dependency definition still has only `module` and `vars`. `flake.nix` pins the public schema source independently of the `schema` Git submodule; both must advance together with `flake.lock` after publication. Do not select a release pin from the possibly stale Mori corpus. Discover the current upstream release/tag and authoritative distribution information when implementing, and record the verified chosen revision.

The consumer is `mori://tan/tan-seihou-modules/masterplans/1-bootstrap-tan-keiro-projects-with-a-cross-registry-recipe`. Its required external artifacts include `mori://shinzui/seihou-modules/templates/haskell-keiro-project`, `mori://shinzui/seihou-modules/templates/git-init`, `mori://shinzui/agent-seihou/templates/master-plan`, and transitive `mori://shinzui/seihou-modules/templates/nix-haskell-flake`. On 2026-10-28 both registry lookup and `mori path` failed because the TAN project was not registered locally. Its actual source URL and recipe name have therefore not been verified. Discover these from the producer before recording real-consumer acceptance; do not invent a GitHub URL. A representative fixture supplies early proof but does not substitute for final TAN evidence.

Relevant ADRs were read after scanning local headings. [ADR 0002](../adr/0002-artifact-identity-is-origin-url-plus-name.md) defines identity as origin plus artifact name. [ADR 0003](../adr/0003-a-stale-or-substituted-artifact-is-a-hard-error.md) keeps generation offline and protects applied origins. [ADR 0004](../adr/0004-the-manifest-is-the-only-record-of-applied-state.md) prohibits a second applied-state lockfile. [ADR 0006](../adr/0006-the-install-cache-will-not-silently-substitute-an-artifact.md) requires refusal before replacing different or unknown provenance, with a visible explicit override. Preserve existing manifest semantics; source declarations describe producer requirements, not a second record of project application.

## Plan of Work


### Milestone 1: Declare sources and prove the producer contract


Extend the upstream Dependency schema with `source : Optional Text`, defaulting to `None Text`. `Some` contains a Git repository source accepted by the installer, identifying the registry that supplies `module`. Production declarations must use portable repository URLs; absolute local paths are reserved for isolated fixtures and existing local-install development workflows. Do not support variables or prompts in source values. Keep `vars` as generation inputs only. An example of the new declaration is:

```dhall
Dependency::{ module = "git-init", source = Some "https://github.com/shinzui/seihou-modules.git" }
```

Extend the Haskell Dependency type and `simpleDep`, and teach `dependencyDecoder` to accept bare names, legacy records without source, and new records with source. Reject malformed nonempty declarations rather than silently discarding them. Update affected constructors and schema tests without rewriting all old producers. New schemas need a compatible executable; document that adoption order.

Verify decoding in module dependencies, recipe members, and blueprint base modules because they share the type. Start a three-registry executable fixture with a root recipe, same-registry member, external member, and that member's dependency in another registry. Preserve unrelated sentinel entries in each registry. This proof is the early integration path for milestone 2. Where the real TAN recipe is available, author the minimal producer change and exercise its actual pre-change install first; count every preparation step. This milestone is accepted when old and new definitions load and source requirements survive decoding with unchanged variable bindings.

### Milestone 2: Plan the complete install before writing


Add a testable closure planner in `seihou-cli/src/Seihou/CLI/InstallClosure.hs` and expose it through `seihou-cli/seihou-cli.cabal`. Keep command selection in Install.hs and acquisition in the CLI layer. Resolve each selected root against its cloned registry. Follow recipe members, module dependencies, and blueprint base modules through the shared dependency representation; prompts without dependencies are leaves. Dependencies that composition expects to be modules must resolve to modules, with an explicit kind error otherwise.

For an absent source, look only in the declaring artifact's registry, never the user's existing search paths or unrelated registered projects. For an explicit source, fetch that repository and select the named entry. Support single-artifact repositories by matching their declared name. Deduplicate repository fetches per invocation by normalized origin and artifact nodes by origin plus name, retaining the original fetch spelling. Resolve all dependency declarations independently of variable bindings. Track active traversal separately from visited nodes to report cycles and their dependency chain. Check every candidate path stays within the fetched repository and every name is safe as an install-directory component.

Produce a deterministic plan with dependency-first entries, source identity, directory, metadata, and the parent chain that requested each dependency. Preflight missing entries, malformed definitions, unavailable sources, duplicate names with incompatible origins, and all existing-cache collisions before writing. For multiple selected roots, treat the union as one requested closure: report all collected failures and exit nonzero without installing a misleading subset. Update the existing batch-install documentation accordingly.

Stage validated artifact payloads, including self-contained dependency declarations and all Dhall imports needed after temporary clones disappear. Use the existing installation format and provenance rules. Relative imports outside an artifact directory must be materialized or normalized into the staged definition; copying a directory with dangling sibling imports is not success. Commit staged entries only after preflight; retain backups of replaced entries until the batch succeeds and restore them on handled write failure. Do not promise crash-atomic transactions unless implemented. Recheck collisions before replacement so a changed cache is not silently overwritten.

Route single-recipe, single-module, registry selection, `--all`, and applicable blueprint installs through this planner. Preserve root picker/history behavior and record success only after the required closure is installed. Output must distinguish selected roots and required dependencies and identify source and dependency chain on failure. `--force` may explicitly replace an existing foreign or unknown-provenance cache entry, with the existing visible warning, but cannot resolve contradictory declarations within the closure.

Acceptance is the three-registry public-command proof from an empty cache: only the required entries are installed, each has the correct provenance, and the recipe loads after temporary source checkouts are gone. Do this before expanding the test matrix.

### Milestone 3: Preserve requirements during local use and verify failures


Carry dependency source expectations through recipe expansion and recursive loading in Composition/Recipe.hs and Composition/Resolve.hs. Do not discard sources when converting members to additional module names. Before generating, compare explicit source requirements with the artifact actually resolved. A known different origin is an error even on the first run, when no project manifest exists. For explicitly sourced dependencies, an unproven local shadow cannot establish satisfaction: diagnose the shadow and require a verifiable installed copy or correction of the declaration. Bare legacy dependencies retain their existing local search behavior. Document this narrow new rule without changing legacy manifest guard behavior.

Implicit same-registry acquisition uses declaring origin metadata for installed artifacts; do not fabricate a remote for project-local definitions. Preserve source metadata when definitions are staged. Keep runtime checks local: no clone, install, or cache repair from run/dry-run. Existing manifest guards continue protecting previously applied state.

Add meaningful tests in `seihou-cli/test/Seihou/CLI/InstallClosureSpec.hs`, extend `seihou-cli/test/Seihou/CLI/InstallCollisionSpec.hs`, and extend the core recipe/decoder/resolution specs near existing tests. Register new test modules as required. Cover repeated install, diamond dependencies acquired once, cycles, missing dependency, unavailable external repository, malformed declaration, differing sources for one name, unknown existing provenance, normalized-equivalent URLs, explicit force, and local shadowing. Check refusal preserves existing marker files and no root is reported ready after failure. Verify install never executes module steps or prompts.

### Milestone 4: Deliver the ordinary workflow


Update `docs/cli/install.md`, `seihou-cli/help/recipes.md`, `seihou-cli/help/registry.md`, and producer schema documentation with one install followed by one run, legacy source defaults, collision handling, and actionable recovery. Distill the source and closure rules into a local ADR following agents/skills/exec-plan/ADR.md. Inspect `mori show --full` before writing an ADR to honor any current bundle profile.

Publish the schema and compatible Seihou release through their established release process; update the submodule, emitted Dhall URL/hash and Nix pins together. Verify the published executable and the user's installed executable separately from the source build using the committed three-registry public-command harness. Record exact versions, schema revision and successful install/run behavior. TAN producer implementation and its eventual end-to-end consumer sequence remain tracked by its own plan; preserve that boundary without claiming it was exercised here. Keep this milestone incomplete until published/installed Seihou acceptance passes.

## Concrete Steps


Run development commands from the Seihou repository root. First inspect dirty work and preserve unrelated changes. Discover external producer locations with Mori; use their own instructions before editing them.

```bash
mori registry show shinzui/seihou-schema --full
mori registry docs shinzui/seihou-schema
mori registry show shinzui/seihou-modules --full
mori registry show shinzui/agent-seihou --full
mori registry show tan/tan-seihou-modules --full
nix develop -c cabal build all
nix develop -c cabal test seihou-core-test seihou-cli-test
```

Expected build/test outcome is exit zero. Add an executable acceptance script at `scripts/test-install-closure.sh` that takes the absolute Seihou executable path as its first argument, creates committed temporary Git registries and isolated XDG config/cache directories, runs public install/run commands, and asserts the milestone 2 and 3 observations. It must never write the developer's actual cache. Resolve the built binary with `cabal list-bin` inside the development shell, then invoke:

```bash
bash scripts/test-install-closure.sh /absolute/path/to/built/seihou
nix develop -c cabal test all
nix fmt
git diff --check
```

The binary path above is a parameter obtained from `nix develop -c cabal list-bin exe:seihou`, not a literal installed location. After identifying the real producer URL and recipe, record their values in the acceptance evidence. The ordinary developer sequence is exactly:

```bash
seihou install "$TAN_SOURCE" --module "$TAN_RECIPE"
seihou run "$TAN_RECIPE"
```

`TAN_SOURCE` and `TAN_RECIPE` stand for the verified published source and entry name, not extra configuration required from developers. This is the downstream TAN sequence, not a Seihou completion prerequisite after the release scope decision. The committed three-registry harness prints the concrete temporary origins used for installed Seihou acceptance. For isolated acceptance, set XDG directories to new temporary directories and use an empty working directory. Add `--dry-run --no-save-prompted` for the cache immutability check; those are test instrumentation, not required normal workflow flags.

## Validation and Acceptance


The schema check must demonstrate all three dependency representations load. The first executable proof must install a root recipe across three committed repositories with no previous installation, remove access to temporary clones, and successfully resolve its members. Assert installed directory names equal the expected closure; unrelated registry entries must be absent. Verify each artifact records its own repository, not the root recipe's origin. A second install must succeed without a false different-origin warning.

For unavailable source and missing entry, require nonzero status, a dependency chain and source in ordinary output, no readiness claim, and unchanged existing cache contents. For an installed same-name foreign artifact, require refusal and preservation of its marker file. For contradictory sources inside one closure, require refusal even with force. For a known external dependency shadowed by a different local artifact, generation must fail before writing project output. Repeated module instances with different vars must still acquire only one artifact while preserving generation bindings.

Snapshot cache file contents and directory inventory before and after run dry-run; require equality. Exercise old record-only recipes and same-registry BUG-2 through ordinary install. After restoring an unavailable source or resolving an explicit cache collision, rerunning the same install command must complete without manual internal metadata edits.

Final evidence must name executable path, version/commit, schema revision, producer revision, exact commands, selected root, installed closure with origins, and observed run result. Repeat the ordinary three-registry install/run and failure/recovery checks against the delivered executable. The separate recipe prompt-order request may affect ordinary inputs; if it blocks this acceptance, record and coordinate that prerequisite rather than hide it with special source edits.

## Idempotence and Recovery


Reinstallation from the same origin is supported and repairs an incomplete older install. Discovery and validation failures leave the cache untouched. Staging must happen outside final artifact directories, and handled replacement failures restore backups and identify any unresolved recovery action. An interrupted commit may need a repeat of the same install; preserve recovery data until it succeeds. Never advise deleting the entire cache. A source collision needs a producer correction or an informed explicit override; `--force` cannot make two required origins coexist under one name.

Use isolated temporary directories for acceptance. Preserve the improvement-request changes already present when this plan was created. Keep source acquisition separate from project generation and preserve user project files. No new feature branch is required. Implementation commits use Conventional Commits and both `ExecPlan: docs/plans/113-declare-and-install-cross-registry-recipe-dependencies.md` and `Intention: intention_01m617vxdmeqfaq0z518dz5e65` trailers.

## Interfaces and Dependencies


The producer interface is Dependency's additive optional `source` field shared by recipe members, module dependencies, and blueprint base modules. It records a Git origin, not a Mori URI: Mori URIs are canonical documentation references, while install uses Git transport. Absence retains legacy decoding and means same declaring registry for acquisition. No version-range solver is added; sources use the installer's existing repository revision policy, with one fetched snapshot per source per invocation.

The internal closure result should separate validated planned entries from effects: each planned entry carries name, artifact kind, recorded source identity, staged directory, registry/version/tags, and requesting chain. Structured errors distinguish missing source/entry, malformed declaration, cycle, incompatible origins, and cache refusal. Install.hs renders those errors; InstallShared.hs retains the shared origin and collision primitives. Do not couple the pure dependency identity model to variable evaluation or prompt execution.

No new Haskell dependency is assumed. If one becomes necessary, locate its API through Mori and verify released versions against its authoritative package registry and upstream tags before changing bounds. This is a standalone ExecPlan with a downstream consumer MasterPlan reference, not an implicitly assigned child of that other repository's plan.
