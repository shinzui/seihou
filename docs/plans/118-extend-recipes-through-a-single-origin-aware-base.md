---
id: 118
slug: extend-recipes-through-a-single-origin-aware-base
title: "Extend recipes through a single origin-aware base"
kind: exec-plan
created_at: 2026-11-01T18:38:13Z
intention: "intention_01m6c6c0theva9djfqz4prcy8q"
provenance:
  created_by:
    model: "gpt-6.1-sol"
    harness: "codex-cli"
    at: 2026-11-01T18:38:13Z
  reviews:
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-11-01T18:57:14Z
      verdict: "changes-requested"
      note: "Source review found unresolved member-origin and literal-attribution APIs, contradictory guard/failure semantics, and update requirements that could retain removed bases; corrected in the accompanying update."
  revisions:
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-11-01T18:57:29Z
      mode: "update"
      note: "Correct member-origin and literal-attribution contracts, override/default/prompt semantics, candidate closure removal, and guard/publication guarantees after source review."
    - model: "gpt-6.1-sol"
      harness: "codex-cli"
      at: 2026-11-01T19:15:11Z
      mode: "implement"
      note: "Implement descriptor validation and pure origin-aware recipe-chain expansion."
---

# Extend recipes through a single origin-aware base

This ExecPlan is a living document. Keep Progress, Surprises & Discoveries, Decision Log, and Outcomes & Retrospective current. Follow `agents/skills/exec-plan/FRICTION.md` while implementing and `agents/skills/exec-plan/ADR.md` when changing durable decisions. Creating this plan does not implement or publish the feature.


## Purpose / Big Picture


Implement [IR-14](../improvement-requests/extend-an-existing-recipe-with-a-single-base.md): a registry author publishes a recipe that reuses one existing recipe, adds modules, and specializes bindings without copying the ancestor's composition. A base chain means a sequence of recipes, each naming at most one parent. Expand the oldest ancestor first and execute the resulting module composition once. The oldest ancestor's first module remains the primary module, which supplies the default configuration namespace.

The consumer starts with an installed Seihou executable, empty artifact caches, and no author checkouts. A published recipe named `haskell-cli-app-with-agents` extends `haskell-cli-app-repo` from another registry and adds the existing `agent-gitignore` module. This is a useful real specialization: scaffold a Haskell CLI repository with agent-specific ignore rules. The complete first-use workflow is:

```bash
seihou install https://github.com/shinzui/agent-seihou.git --module haskell-cli-app-with-agents
seihou run haskell-cli-app-with-agents
```

Publish `haskell-cli-app-with-agents` in that registry and give its base the explicit source `https://github.com/shinzui/seihou-modules.git`. The base is `mori://shinzui/seihou-modules/templates/haskell-cli-app-repo`, the concrete recipe motivating the request. There is one acquisition command and one ordinary preview/confirmation command; prompts supply normal project inputs. No dependency selectors, directory-layout recreation, manual manifest changes, or Dhall imports are consumer preparation. The documentation can also show the request's hypothetical organizational `my-service` example, but acceptance uses these actual producers and commands.

Existing incomplete installations recover by repeating the same install command. A fresh clone with the checked-in manifest and no installed artifacts uses `seihou update haskell-cli-app-with-agents`; update acquires the recorded recipe's candidate closure, reuses saved inputs, and presents its ordinary preview. Routine base updates also use that command. Cache-only refresh remains `seihou upgrade haskell-cli-app-with-agents`, followed by `seihou update haskell-cli-app-with-agents` for safe reconciliation of an existing application. Explicitly rerunning `run` regenerates and reruns commands under its existing semantics. Run never fetches or installs.

This plan owns schema, executable, author documentation, manifest compatibility, and a real published registry example. Multiple parents, removal of inherited modules, module inheritance, arbitrary execution hooks, a general version solver, a new lockfile, and a cache namespace redesign are excluded.


## Progress


- [x] M1 (2026-11-01): Legacy descriptor decoding, new descriptor-local validation, origin-aware pure merging, offline chain loading and source-attributed literal resolution pass all 1,381 core tests. The source-built CLI also validates a settings-only child without an installed base, reports its local-only scope, and leaves project/config/cache bytes untouched. The schema package and derived example type-check/evaluate; producer changes are committed locally as `dbeff0d`.
- [x] M2 (2026-11-01): Kind-aware acquisition stages and validates the complete chain, materializes base sources, and repairs missing entries. Ordinary run expands offline with visible chain/origins/primary and attributed literals. The real two-registry workflow passes install, generation after removing candidate source clones, repeat preview and interactive confirmation. Shell acceptance proves shared execution once, settings-only specialization, producer requirements under `--allow-downgrade`, preserved state on refusals, and single-recipe sources; 34 Install CLI tests, 32 Recipe CLI tests and 40 Recipe core tests pass.
- [x] M3 (2026-11-01): Schema-13 chain codecs, the adjacent lossless upgrade, run/update recording and guards, read-only older-history adoption previews, and failure provenance are verified. Core validation passes 1,385 tests; the 15 RecipeExtension command regressions include accepted update adoption, base guards and transactional rollback.
- [x] M4 (2026-11-01): Ordinary update and recipe cache upgrade include base-only changes and candidate transitive sources. Real interactive producer proofs cover preview, decline, acceptance, fresh-clone cache restoration, cache-only refresh and repeat no-op. Command regressions cover new/removed sources, source/range refusals, deduplication, unversioned skipping, stale base bytes and rollback.
- [x] M5 (2026-11-01): Published schema, all three Hackage packages and Haddocks, GitHub release, tagged Nix installation, author help and both registries pass the public consumer workflow, empty-cache fresh-clone update and compatible base-only refresh.


Implementation checkpoint (2026-11-01): `Recipe` has explicit base/module/prompt override fields. `ExpandedRecipe`, `ResolvedRecipeNode`, `ResolvedRecipeMember` and `RecipeLiteral` preserve the origin and declaring-directory context; `mergeRecipeChain` implements oldest-first merging without turning literals into module-instance parent bindings. `loadRecipeChain` is offline and verifies source/range requirements. The legacy tuple wrapper rejects derived recipes explicitly. `resolveRecipeWithSources` preserves literal attribution through recipe and consumer resolution while the original API remains a flat compatibility adapter. Validation commands: `nix develop -c cabal test seihou-core-test` passed 1,381 tests; the focused Recipe run selected 40 tests. `nix develop -c cabal build exe:seihou` passed. `nix develop -c cabal test seihou-cli-test --test-options='-p ValidateRecipe'` passed all 23 selected public-command regressions, including the new derived-descriptor case and snapshot preservation. The candidate executable is `dist-newstyle/build/aarch64-osx/ghc-9.12.4/seihou-cli-0.13.0.0/x/seihou/build/seihou/seihou`, reporting `seihou v0.13.0.0 (7c56bfa)` before the implementation commit; this is a source build, not an installed release. `nix develop -c cabal test seihou-okf-extension-test` passed all 51 tests. `nix develop -c cabal build all`, Fourmolu checks on changed Haskell files, and `git diff --check` passed. The effective installed executable remains `/Users/shinzui/.nix-profile/bin/seihou`, version `0.10.1.0 (c3cbd9b)`; it has not been replaced. At the M1 boundary, public install/run/update had not yet been routed through the new expansion; subsequent work is recorded below.

The schema producer `mori://shinzui/seihou-schema` was fast-forwarded to authoritative upstream HEAD `d3c78cd81d9697ebff3128732ec673a17e65c73f`; its new descriptor exports are committed locally as `dbeff0d`. Package type-checking and an evaluated settings-only derived example pass. The producer's unrelated `Step.dhall` edit and this repository's pre-existing modified `schema` gitlink were preserved. The new schema commit is unpublished and the CLI schema pins remain unchanged pending coordinated M5 delivery.

M2 checkpoint (2026-11-01): The committed derived producer is `mori://shinzui/agent-seihou/templates/haskell-cli-app-with-agents`, candidate revision `187f11ef5a4eaa385ab20dbd4f4e7c173b141728`, extending the unchanged base producer `mori://shinzui/seihou-modules` at `b1fcf41bf8fc0b5dcc42f0f5552365fcf216d219`. `scripts/verify-recipe-extension.py` routes the actual published URLs only through isolated Git configuration, records revisions, then physically removes its candidate clones before run. The final source proof is retained in `/tmp/118-m2-consumer-final/` (including interactive transcript and `evidence.json`); binary version is `seihou v0.13.0.0 (efc6266)` before the M2 commit. `bash scripts/test-install-closure.sh <binary>` passed the expanded fixture scenarios; `/tmp/118-m2-shell-final.log` retains output. Base source/range checks precede prompts and cannot be bypassed by `--allow-downgrade`; errors identify the derived root and give its ordinary install command. Manifest chain recording/guards and candidate update/cache refresh remain M3/M4, so the feature is not yet delivered. The candidate producer is not published and installed CLI remains unchanged.

FRIC-10 in `docs/friction-log/` records the existing closure harness's dependence on the user-modified schema gitlink. It is resolved: fixture record defaults now permit explicit source fields without changing that checkout. This fixture correction does not prepare consumer artifacts or replace the actual producer proof.

M3 run/manifest checkpoint (2026-11-01): Applications have optional ordered `AppliedRecipeNode` evidence (name, portable origin, declared version, SHA-256 of normalized descriptor). Schema 13 requires the `recipeChain` key; its 12-to-13 lossless step adds null without fabricating history and preserves unknown raw fields. Codecs reject mismatched final targets, duplicate nodes, invalid digests and nonportable node origins. New accepted runs record the actual chain, and module runs record an empty array. Checks use the selected application's history before recipe/module input resolution; same-name base substitutions and downgrades cannot pass silently. Descriptor/version/chain differences and unknown-history adoption appear in normal preview. Run no longer creates `.seihou` merely to read a missing manifest. Run's generated provenance survives a failed command while incomplete receipts are removed.

`/tmp/118-m3-consumer/` retains the real producer replay on schema 13, including portable chain evidence and unchanged-repeat checks. The genuine schema-12 project produced during M2 at `/tmp/118-m2-consumer-final/project` passed dry-run and interactive decline without byte changes, then adopted the current chain through ordinary accepted run; transcripts are `schema13-preview.txt`, `schema13-decline.txt` and `schema13-adopt.txt` in its parent directory. This was actual prior source-build state, not a manually repaired consumer manifest. `RecipeExtensionE2ESpec` covers base-only downgrade refusal, visible override, descriptor-only preview, historical fixture adoption, failed commands and cache-only no-write previews. Source executable reports `seihou v0.13.0.0 (c0d1cf2)` before the M3 commit; no installed release has changed. Full CLI validation required updating five tests whose current-version expectations or schema-5 fixture conversions still assumed schema 12. The corrected fixtures exercise the intended older states, and all 844 CLI tests pass. `nix develop -c cabal build all`, all 51 extension tests, Fourmolu checks and `git diff --check` also pass.

M4 implementation checkpoint (2026-11-01): Candidate recipe roots use the shared kind-aware closure stager to acquire only the new composition, including newly declared sources. Historical bases and removed members remain evidence rather than mandatory fetch roots. All update recipe paths use merged declarations, prompts and attributed literals; legacy adoption leaves prior chain unknown until acceptance. Base records participate in stale-plan hashes, cache publication and rollback. JSON plan schema 1 has additive `recipeChains` and `cacheChanges` arrays. Cache restoration is actionable on a fresh clone even when recorded project content already agrees. Recipe cache upgrade refreshes bases and members, deduplicates explicit/no-argument roots, validates before publication, and preserves project state. Module-only upgrade behavior remains supported.

The real accepted consumer at `/tmp/118-m3-consumer/project` passed a base-only `0.1.0` to `0.1.1` preview, decline, ordinary interactive acceptance and repeat no-op; the child stayed `0.1.0` and its command receipt stayed unchanged. Evidence is retained alongside that project as `m4-base-*.txt`. A committed clone at `/tmp/118-m4-fresh-consumer/project` with empty HOME/config/cache passed the same ordinary update sequence, restoring all six cache entries without re-entering inputs. A subsequent base-only `0.1.1` to `0.1.2` cache preview/upgrade preserved every project byte and recommended the ordinary recipe update; that update accepted provenance and skipped the unchanged command. `/tmp/118-m4-fresh-consumer/` retains transcripts. Only isolated Git transport rewrites select committed candidate producers; no release or installed executable has changed.

The interactive proof exposed an omitted optional module answer being asked again during update. Ordinary update now preserves such omissions; `--reconfigure` deliberately revisits optional configuration. The first remote regression fixture incorrectly located its installed cache inside the project, making project-relative provenance authoritative under existing origin rules. Its consumer and XDG directories are now siblings, matching the real workflow. This was fixture correction, not manifest repair or a production identity exception. The full 855-test CLI run passed 854 checks and identified one new fixture that attempted an unversioned module, which existing module validation correctly rejects. The corrected test uses a supported unversioned recipe; the complete 15-test RecipeExtension group then passes. The full run also passes the new staged-cache publication rollback check and all existing update cases. `nix develop -c cabal build all`, Fourmolu and `git diff --check` pass. The CLI now declares the already-used GHC boot dependency `transformers >=0.6 && <0.7` directly for candidate traversal; authoritative Hackage and upstream tag checks verified 0.6.3.0. M5 release validation will rerun all suites against the final package candidate.

M5 release checkpoint (2026-11-01): The schema producer commit `dbeff0dd67c15b7a1c57f90b23103afdc2fa8056` is published. Both its clean committed archive and the public HTTPS import type-check/hash as `sha256:065c27b4d26059a7641e8ee7ee9d23ed32a698052c6aa8966426e6a678ee0e82`. The CLI URL/hash, gitlink and Nix input/lock advance together to that revision. The earlier stale gitlink checkout was deliberately advanced for this integration; the producer's unrelated `Step.dhall` edit is preserved.

The user approved shared release 0.14.0.0 and both changelog drafts. All three package versions and five core bounds move together. The versioned candidate passes `just format`, `just build`, `just audit-cli-docs`, `just test`, `just check`, and all three `cabal check` commands. The suites pass 1,385 core, 856 CLI and 54 extension tests (2,295 total). Audit covers all 18 topics, 33 command help pages plus agent run, 26 packaged assets, six validated examples and eight provider-free renders. Recipe inspection uses offline merged expansion and reports attributed literals without generation; ordinary upgrade previews say what would change. ADR 0024 gathers the durable contract.

`/tmp/118-release-candidate-proof/` records the final 0.14.0.0 source executable and committed producer revisions `d1997d246e82629c2d2ed01fdd7f8395217f6d93` and `cfe5b13e22642bb94368279bcd5039c8ef13171a`. The complete harness passes install, offline run with candidate clones physically removed, interactive ordinary run, committed fresh-clone update preview/decline/acceptance, cache restoration and repeat no-op. Its update phase recreates only candidate Git transport fixtures after the offline proof; it never prepares consumer cache entries. A concurrent producer update was merged without reverting it. Producer README changes are committed locally; both registries validate and generated documentation previews validate (13 and 19 concepts). Native package builds, Hackage/GitHub publication, versioned producer documentation/publication, installed release acceptance and public base-only refresh remain open. The installed user executable is still 0.10.1.0 pending that delivery.

Native gate follow-up (2026-11-01): The first clean 0.14.0.0 aggregate build passes core and extension but fails ten CLI checks. Copied local schema files retain read-only permissions in the sandbox; candidate normalization then attempts to overwrite those private copies. Development fixtures recovered from Git objects were writable and hid the defect. Normalize only owner-writable staged files, preserve source bytes/permissions and executable bits, and add read-only descriptor/payload regressions. No tag or Hackage upload has occurred. The directory-source registration was empty; FRIC-11 records recovering the exact installed 1.3.10.1 source from Hackage for permission API inspection.

Final delivery (2026-11-01): Release `v0.14.0.0` tags `b37130831bf50de78beefd33b8db0765bcf5a021`; all three packages are live on Hackage, their documentation uploads succeed, and the GitHub release is published. The final clean native aggregate passes with package tests retained; the source suites pass 1,385 core, 858 CLI and 54 extension tests (2,297 total), including both read-only staging regressions. Final flake checks pass. The effective executable `/Users/shinzui/.nix-profile/bin/seihou` reports `seihou v0.14.0.0 (b371308)`. Nix profile entry `seihou-2` records `github:shinzui/seihou/v0.14.0.0` at priority 2; all existing entries and priorities are preserved.

Published producers are `mori://shinzui/agent-seihou` revision `00a9bef` (derived recipe 0.1.0) and `mori://shinzui/seihou-modules` revision `0964697` (base recipe 0.1.1). The schema remains published revision `dbeff0dd67c15b7a1c57f90b23103afdc2fa8056`. Generated producer bundles validate with 13 and 19 concepts; rerendering agent docs with the installed extension produces no changes. The base's 0.1.1 release clarifies its reusable-parent contract without altering its module list or generated output.

`/tmp/118-released-consumer/` retains the installed-release evidence with no candidate Git rewrites: public install acquires all six entries, offline generation and ordinary interactive run succeed, repeated preview is stable, and a committed fresh clone with empty caches passes ordinary update preview, decline, acceptance, cache restoration and repeat no-op. After publishing only the compatible base change from 0.1.0 to 0.1.1, `/tmp/118-public-base-proof.log` and the fresh clone's `public-*.txt` transcripts prove cache-only upgrade preview/acceptance preserve every project byte, ordinary update preview/decline preserve project/cache bytes, accepted update records base 0.1.1 while child stays 0.1.0, command receipts remain unchanged, and repeat reports already up to date. There are no release or installation deliverables left open. The request bundle passes strict validation with its advisory profile; enforcing profile recommendations also reports existing unrelated missing review/resolution fields. The friction bundle passes strict enforced profile and log validation.

## Surprises & Discoveries


2026-11-01 review: `Dependency` retains a source requirement but no declaring directory or resolved origin. `loadComposition` accepts names and creates binding-free synthetic edges; recipe bindings are flattened globally. `resolveRecipeWithPrompts` labels all literals with the nullary `FromRecipeBinding`. The new expansion therefore needs explicit resolved-member context and a source-aware literal adapter, not just a renamed tuple. ADR 0003 permits unverifiable local origins with warnings, and ADR 0023 documents that failed run commands leave generated state while update rolls it back. The plan now distinguishes those cases.


## Decision Log


2026-11-01: Use a distinct typed recipe reference, with an optional literal Git source and optional numeric version interval. A missing source means the declaring registry during installation and is materialized there, as module edges already are under ADR 0020. Do not interpret a recipe as a module dependency or introduce a Mori runtime requirement.

2026-11-01: Select the artifact at the source repository's default-branch checkout and validate its declared version against an optional inclusive lower/exclusive upper interval. Do not search historical tags or silently fall back to another version. This matches existing acquisition and makes incompatibility actionable without introducing a version solver. A rejected candidate preserves installed and applied state.

2026-11-01: Reuse inherited modules with an explicit `moduleOverrides` field. A second member declaration with conflicting bindings is an error rather than a second execution or an implicit override. Keep existing module-instance identity, including legitimate parameterized dependencies, intact. Recipe literal bindings retain their current global variable-name semantics; extension does not add per-instance variable addressing.

2026-11-01: Preserve descriptor-only validation. Parent availability, inherited names, cycles and merged consistency are checked by install/composition, not by `validate-recipe`. Provide an explicit `promptOverrides` field so replacing an inherited question is deliberate and its original ordering remains stable.

2026-11-01: Store recipe-chain provenance at application scope in the manifest, including descriptor hashes as change evidence, while identity remains origin plus name. Unknown older history stays unknown. Source-only implementation does not close delivery; publishing and installed-version acceptance remain M5.


## Outcomes & Retrospective


Recipe inheritance is delivered through the ordinary two-command install/run workflow, with full closure acquisition, offline expansion and portable schema-13 provenance. Existing applications reconcile base-only changes and restore caches through ordinary update; cache-only upgrade preserves application files. The published 0.14.0.0 executable is installed and the complete public workflow passes, including fresh clones and a real compatible producer update. Source and native validation both pass; author/help guidance, schema pins and generated producer docs accompany the release.

ADR 0024 gathers the merge and delivery contract, with surrounding ADRs updated for identity, acquisition, resolution, validation and manifest compatibility. FRIC-10 is resolved through robust fixture schema defaults. FRIC-11 is accepted: the empty registered dependency checkout was worked around using exact-version authoritative source; maintaining that external corpus is outside this feature. The native gate exposed a real read-only staging defect and now has regression coverage. The schema producer's unrelated `Step.dhall` edit remains preserved.


## Context and Orientation


A registry is a Git repository whose `seihou-registry.dhall` lists artifact names, kinds and paths. A recipe (`recipe.dhall`) selects modules (`module.dhall`) and supplies literal variable bindings, declarations and questions. A dependency closure is every directly or indirectly required artifact. An application is one recorded invocation and its fully resolved module instances in `.seihou/manifest.json`. A module instance is a module name plus its parent-edge bindings, represented by `ModuleInstance`; distinct intentional parameterizations can execute separately.

The source request is `docs/improvement-requests/extend-an-existing-recipe-with-a-single-base.md`. [Plan 6](6-recipe-module-composition.md) introduced flat recipes and deferred inheritance. [Plan 113](113-declare-and-install-cross-registry-recipe-dependencies.md) already implemented dependency-source acquisition and closed Seihou's prerequisite delivery for [BUG-2](../bug-reports/install-ignores-recipe-and-module-dependencies.md). Extend that machinery; do not reopen the old implementation as an unexplained prerequisite. [Plan 114](114-resolve-recipe-variables-and-prompts-before-module-resolution.md), [plan 115](115-validate-recipes-without-running-their-composition.md), and [plan 117](117-let-recipes-enforce-configured-variable-values.md) establish input ordering, descriptor validation, and source-independent constraints. Their current behavior is summarized below; this standalone plan has no MasterPlan parent.

`seihou-core/src/Seihou/Core/Types.hs` defines `Recipe`, `Dependency`, `VarDecl`, `Prompt`, `AppliedComposition` and `AppliedRecipe`. `Recipe` has no base field. `seihou-core/src/Seihou/Dhall/Eval.hs` owns `recipeDecoder`, compatibility defaults, and `normalizeInstalledDefinition`, which evaluates imports and materializes sources on `modules`, `dependencies` and `baseModules`. The recipe decoder currently requires the six legacy fields; it must default new fields without dropping those checks. `seihou-core/src/Seihou/Core/Recipe.hs` validates names, nonempty and unique member lists, literal binding names, declarations, patterns and prompt references. It currently requires each prompt's names in the same descriptor.

`seihou-core/src/Seihou/Composition/Recipe.hs` contains `expandRecipe`, a pure function returning a six-part tuple: primary, additional names, flattened literal bindings, declarations, prompts and original dependency requirements. `Map.unions` currently makes the first member's literal win on duplicate global keys. `seihou-core/src/Seihou/Composition/Resolve.hs` loads modules, verifies source requirements, and resolves recipe inputs before module defaults. `seihou-core/src/Seihou/Composition/Instance.hs` and `seihou-core/src/Seihou/Composition/Graph.hs` own instance identity, deduplication and dependency execution order. Additional recipe names become synthetic module dependencies. Preserve actual producer edges and do not turn all module parent bindings into global overrides.

`seihou-cli/src/Seihou/CLI/InstallClosure.hs` preflights the whole acquisition graph and stages normalized definitions before touching the shared cache. Its `visit`/`inspect` path currently uses `mustBeModule :: Bool`; all followed edges require a module. `locate` also treats single-artifact dependency repositories as modules only. Both need artifact-kind awareness for base edges. Existing rollback, safe payload paths, source collisions and same-origin handling remain applicable.

`seihou-cli/src-exe/Seihou/CLI/Run.hs` discovers a recipe, expands it, checks module source requirements, resolves inputs and records one target. `seihou-cli/src/Seihou/CLI/ManifestGuard.hs` supplies origin/version comparisons. `seihou-core/src/Seihou/Manifest/Types.hs` owns JSON encoding and capability gates; the current manifest schema is 12. `seihou-core/src/Seihou/Manifest/Upgrade.hs` owns adjacent, classified upgrades. `seihou-cli/src/Seihou/CLI/ManifestCapabilityUpgrade.hs` stages lossless adoption for accepted operations. Application history, rather than the top-level last-recipe summary, must guard each recorded chain.

`seihou-cli/src/Seihou/CLI/Update.hs` currently expands the target recipe independently in candidate and legacy paths and constructs `RecipeInputSpec` directly from its declarations. `seihou-cli/src/Seihou/CLI/Update/Source.hs` stages target and instance origins, not base origins or newly introduced external sources. `seihou-cli/src/Seihou/CLI/Update/Types.hs` and `seihou-cli/src/Seihou/CLI/Update/Render.hs` carry and present candidates. `seihou-cli/src-exe/Seihou/CLI/Upgrade.hs` currently enumerates modules, so merely adding base traversal to install would leave recipe cache upgrades unusable.

The schema producer is `mori://shinzui/seihou-schema/packages/seihou-schema`. Within project `mori://shinzui/seihou-schema`, relevant paths are `Recipe.dhall`, `Dependency.dhall`, `package.dhall` and its author documentation; file-level URIs are pending. Discover its checkout with Mori. The local `schema` gitlink is user-modified at plan creation: do not reset or commit it incidentally. Its recorded revision and `flake.nix` pin are `d3c78cd81d9697ebff3128732ec673a17e65c73f`. Upstream `git ls-remote` on 2026-11-01 reported the same HEAD and no tags, while the separate local schema checkout lagged the dependency-source definition. Read current upstream/candidate source before making changes; do not design from that stale checkout alone.

Producer project `mori://shinzui/seihou-modules` contains `recipes/haskell-cli-app-repo/recipe.dhall`, currently version `0.1.0`, composing `haskell-cli-app` and `git-init`. Its intended artifact URI is `mori://shinzui/seihou-modules/templates/haskell-cli-app-repo`; Mori still failed to resolve that artifact during planning. Keep the canonical URI; use the registered project to locate source. For a real second registry use `mori://shinzui/agent-seihou`, discovered through `mori registry show --full`. Its registry has no recipes at planning time and already supplies `mori://shinzui/agent-seihou/templates/agent-gitignore`. Add the derived `mori://shinzui/agent-seihou/templates/haskell-cli-app-with-agents` recipe there, reusing that module. This proves cross-registry extension without inventing a new policy module or requiring another organization to adopt the feature. Repository-local author instructions govern each producer edit.

ADR discovery scanned filenames and headings in `docs/adr/`. Relevant decisions read were [ADR 0001](../adr/0001-manifest-is-a-checked-in-machine-independent-artifact.md) (machine-independent manifests), [ADR 0002](../adr/0002-artifact-identity-is-origin-url-plus-name.md) (normalized origin plus name), [ADR 0003](../adr/0003-a-stale-or-substituted-artifact-is-a-hard-error.md) (local generation refuses stale/substituted artifacts, accepts newer compatible copies, and never fetches), [ADR 0004](../adr/0004-the-manifest-is-the-only-record-of-applied-state.md) (manifest is the applied-state record), [ADR 0006](../adr/0006-the-install-cache-will-not-silently-substitute-an-artifact.md) (visible install collision policy), [ADR 0014](../adr/0014-every-semantic-manifest-change-advances-the-schema-version.md) (adjacent, capability-gated semantic upgrades), [ADR 0020](../adr/0020-dependency-sources-belong-to-producer-edges.md) (producer-owned sources and install-owned acquisition), [ADR 0021](../adr/0021-recipe-inputs-resolve-before-module-defaults.md) (input precedence and saved recipe inputs), and [ADR 0022](../adr/0022-recipe-descriptor-validation-is-independent-of-composition.md) (standalone validation without member discovery). Summaries here are the operative constraints; implementation should update the appropriate decisions when extending them.

Planning baseline: `/Users/shinzui/.nix-profile/bin/seihou` reports `seihou v0.10.1.0 (c3cbd9b)`. In an isolated temporary project, a raw local `my-service` descriptor with `extends`, `modules = []`, and the six legacy fields failed `run my-service --dry-run --no-save-prompted` with `Invalid recipe 'my-service': recipe must list at least one module`; no manifest was created. This proves the installed gap, not acquisition or source acceptance. `cabal list-bin exe:seihou` names a 0.13.0.0 build path, but that executable is absent; build it before candidate checks. No implementation tests or release delivery have been performed by this create operation.


## Plan of Work


### M1 — Define and implement the descriptor and merge contract


Add `RecipeReference`, `RecipeVersionRange`, and recipe fields `extends`, `moduleOverrides`, and `promptOverrides` in `seihou-core/src/Seihou/Core/Types.hs`, compatible Dhall decoding in `seihou-core/src/Seihou/Dhall/Eval.hs`, and matching schema exports. These are new proposed interfaces. Use the following Dhall authoring shape; a range compares numeric dotted versions using `Seihou.Core.Version`, including its trailing-zero equivalence:

```dhall
S.Recipe::{
, name = "haskell-cli-app-with-agents"
, version = Some "0.1.0"
, extends = Some S.RecipeReference::{
  , recipe = "haskell-cli-app-repo"
  , source = Some "https://github.com/shinzui/seihou-modules.git"
  , versionRange = Some { minimum = "0.1.0", before = "0.2.0" }
  }
, modules = [ S.Dependency::{ module = "agent-gitignore" } ]
, moduleOverrides =
  [ { module = "git-init"
    , vars = [ { name = "git.githubOwner", value = "shinzui" } ]
    }
  ]
}
```

`RecipeReference.Type` is `{ recipe : Text, source : Optional Text, versionRange : Optional { minimum : Text, before : Text } }`, defaulting source and range to `None`. `extends` defaults to `None`; both override lists default to typed empty lists. Retain the required `modules` field so empty child additions are explicit. Legacy evaluated records without new fields decode unchanged. A root recipe must contain a module; a derived recipe may contain none. An interval requires valid numeric endpoints with minimum strictly below before. A constrained base must have a valid version inside the interval. An unconstrained versionless base retains existing unversioned behavior and cannot provide a meaningful numeric stale comparison; explain that limitation. Both origin and interval requirements apply in install, run, update and cache refresh. No consumer flag bypasses a declared interval. Acquisition checks default-branch HEAD and reports an out-of-range version with recipe chain, source and permitted interval; it never selects another registry or searches old tags.

Split local validation from chain validation without making standalone validation effectful. `validateRecipe` checks reference shape, names, literal sources, ranges, duplicate local entries/overrides, local patterns, and root nonemptiness. With `extends`, unresolved prompt names and override targets may come from the base; defer those referential checks to full expansion. Continue rejecting malformed expressions and locally contradictory declarations. `validate-recipe` must say that a derived descriptor passed local validation and that its base/composition was not checked. Do not introduce a dependency fetch or member lookup. Existing flat validation behavior remains unchanged.

Replace the tuple at integration boundaries with an `ExpandedRecipe` record containing primary, ordered unique member dependencies, literal bindings with declaring-recipe attribution, merged declarations, merged prompts, and oldest-first resolved recipe nodes. Separate IO lookup of parents from pure merging: add `seihou-core/src/Seihou/Composition/RecipeChain.hs` for local loading/chain traversal and keep merging in `seihou-core/src/Seihou/Composition/Recipe.hs`. Preserve a compatibility wrapper for `expandRecipe` if required by the public API, or version its intentional API break under Haskell PVP. A flat-only wrapper must reject `extends` clearly rather than silently ignore it. Add `ResolvedRecipeMember` carrying the effective `Dependency`, the declaring recipe identity/directory and the resolved member origin. Verify each member source relative to its own declaring recipe, never the derived root directory. Keep these contexts through deduplication and source checks; only then pass primary/additional names to `loadComposition`. Recipe member bindings remain global literals and must not be passed as synthetic parent-edge bindings, which would change `ModuleInstance` identities and duplicate execution. Resolve source-less project-local members before identity comparison; a remote recipe's name/origin is not automatically its member's origin.

Merge oldest ancestor to child. First occurrence fixes member order and the oldest primary. Identify members by normalized origin plus module name, retaining `ProjectOrigin` for portable project-local bases. Compatible repeats have the same requirements and bindings, occupy one slot, and execute once. A name required from different origins is always a conflict because the installed cache has one slot per name. Different bindings on repeated recipe members require `moduleOverrides`; do not reinterpret them as two instances. An override must name exactly one inherited recipe member, replaces only supplied keys in that member's bindings, and never appends an executable. Reject missing/ambiguous targets. Keep duplicate local module declarations invalid. Apply compatible deduplication before graph construction, and retain the module graph's legitimate distinct parent-binding instances; do not collapse a producer's deliberate parameterizations by name alone.

Literal binding precedence is CLI above descendant recipe above ancestor recipe above saved recipe inputs above environment above local/namespace/context/global configuration above recipe declaration defaults. Within a layer of an extended chain, unequal literals for the same global variable name are an error identifying both member entries; equal literals coalesce. Preserve the historical first-member-wins behavior for existing flat recipes. `moduleOverrides` selects the inherited member to specialize, but its values still join the existing recipe-wide literal map; document that this is not per-instance addressing. A child default never defeats an inherited explicit literal. After resolving declared recipe inputs, broadcast them above module saved values, parent bindings, exports and module defaults; preserve actual source labels and validate every consumer independently. Undeclared literal recipe bindings keep their current supported behavior. Do not change module parent-edge precedence or infer recipe declarations from module defaults. Build each layer's literal delta from that descriptor's module entries plus supplied `moduleOverrides` keys, then left-bias child deltas over ancestor deltas. Do not re-flatten mutated inherited member records: unsupplied keys keep their original layer and attribution. Check same-layer unequal values across both surfaces; overrides target inherited members only, and a child cannot both redeclare and override the same member. Compare a later repeated member against the current effective bindings after earlier overrides. Add a three-level case where two base members bind `x = "old"`, the child overrides one to `"new"`, and the grandchild adds no binding: `"new"` wins globally without a false cross-layer conflict. Reject a child that also introduces `x = "different"` on another member.

Merge declarations by variable name. Repeated type, requiredness and validation must agree; differing constraints or requiredness are incompatible even if defaults happen to satisfy them. A child may replace default and description; use the nearest `Just` value (including empty text, false, and zero), without treating omission as deletion. Validate the resulting value against the retained declaration. Parent-only declarations remain available to child prompts and modules. No constraint weakening or implicit variable removal is added.

Prompt identity is its target `var`. Append new child prompts after inherited prompts. Identical repeated prompts coalesce; unequal repeated prompts require `promptOverrides`, whose entries use the existing `Prompt.Type`. Each override replaces exactly one inherited target in its original position. Reject duplicate override targets, targets also declared in the child's ordinary prompts, and inherited duplicate targets that make override ambiguous. Validate final targets and condition references against merged declarations before asking questions. Preserve the existing required-then-optional prompting passes in `resolveRecipeWithPrompts`; list position alone does not imply global execution order. This feature adds no new prompt dependency scheduler or cycle rule. Test inherited conditions and overrides in both passes, including required inputs whose conditions are false. Existing flat recipes retain their prompt-list semantics; ambiguous flat bases must be corrected before extension, rather than arbitrarily dropping questions.

M1 passes focused decoder, validator and pure merge checks for legacy flat input, a three-level chain, settings-only children, identity conflicts, precedence, declaration conflicts and prompt replacement. Begin M2's public-command proof as soon as one minimal vertical path exists, before broadening permutations.


### M2 — Make install and local run own the complete chain


Generalize `visit`, `inspect` and `locate` in `seihou-cli/src/Seihou/CLI/InstallClosure.hs` from a module-only flag to explicit expected artifact kinds. A recipe base edge requires a recipe; a module edge still requires a module. Follow bases and their module dependencies, including single-recipe repositories. Deduplicate repository acquisition by normalized URL and artifact nodes by origin/name while tracking active traversal separately to report direct and indirect cycles. A module declaration naming a recipe still fails: extension is explicit. Validate the merged recipe before publishing the closure, so a syntactically valid child with incompatible inherited declarations does not leave a supposedly ready installation.

Extend `normalizeInstalledDefinition` to materialize omitted sources on `extends` as well as member dependencies while the declaring registry checkout is known. Preserve explicit sources, version intervals and overrides. Retain import normalization so no sibling checkout is required after install. Enforce one-origin-per-name across recipes and modules too; `--force` cannot satisfy contradictory closure requirements. Stage the complete closure and retain existing payload-path checks, collision preflight and handled-error recovery. Print selected roots and required bases/modules with their origins. A missing dependency names the child-to-base chain and gives the ordinary install command for the derived root.

Route `seihou-cli/src-exe/Seihou/CLI/Run.hs` through local chain loading and the merged expansion once. Verify explicit base source and version requirements, including first-run shadows without readable provenance, before prompting or executing. Keep lookup local and do not touch the install cache. For project-local recipes with no registry origin, a source-less base uses ordinary project-local discovery, retains honest `ProjectOrigin`/`LocalOrigin`, and must not be assigned an invented remote. Installed definitions acquire deterministic same-registry sources during installation. Print the derived recipe, the oldest-first chain, versions, origins and final module count in normal preview.

Prove a representative producer early. In `mori://shinzui/agent-seihou`, add `recipes/haskell-cli-app-with-agents/recipe.dhall`, extending `haskell-cli-app-repo` from its published source and adding the existing `agent-gitignore` module. Give the recipe a version and registry entry, including its binding override example. Keep the Haskell base intact except for meaningful schema/compatibility or versioned acceptance changes. Inspect both producer repositories' instructions and current conventions before edits. Commit candidate producer revisions and run install against their advertised remote URLs redirected to those committed checkouts through isolated Git URL rewrites. This is a candidate-routing mechanism recorded by the harness, not a shipped user step. Do not prepare normalized descriptors or preinstall members for the consumer.

Add `scripts/verify-recipe-extension.py` with `--binary`, `--area`, and repeatable `--candidate-repo` options; the latter discovers a checkout's advertised origin and installs a Git rewrite only in isolated config. The harness creates empty HOME/config/cache roots, removes ambient `SEIHOU_VAR_*`/context, performs the two public commands, records every preparation step, disables or stubs provisioning commands, and checks combined output and dependency origins. Extend `scripts/test-install-closure.sh` and `seihou-cli/test/Seihou/CLI/InstallClosureSpec.hs` for recipe-kind edges and refusal preservation. A controlled shared module writes a marker to prove exactly one execution; `--no-commands` alone cannot prove execution count or pre-effect rejection. M2 passes when imports/source clones can disappear and local run still works. Fixture acceptance complements, rather than replaces, the actual producer proof.


### M3 — Record and guard every resolved recipe


Add `recipeChain :: Maybe [AppliedRecipeNode]` to `AppliedComposition` in `seihou-core/src/Seihou/Core/Types.hs`. A node records name, portable `ArtifactOrigin`, optional declared version, and SHA-256 of its canonical normalized descriptor. Record oldest ancestor through derived target, including the target, and require the final node to match application target identity/version. The digest detects descriptor-only changes and is evidence, not artifact identity or a new lockfile. No absolute local paths or cache locations serialize; `ProjectOrigin` retains its normalized project-relative path and `LocalOrigin` retains its honest unverified name. The existing top-level `AppliedRecipe` remains the last-target summary; application-level chains are authoritative for all recorded invocations.

Advance manifest schema 12 to 13, or the next current successor if another feature has landed, with a `RecipeInheritance` capability and a lossless adjacent action adding `recipeChain = null` to older applications. Null means unrecorded history; a new accepted flat recipe records its singleton chain and a module application records an empty list. Never assert that old recipe history was singleton merely because today's descriptor is flat. Update schema-aware encoding/validation and version history. Preserve unknown JSON keys through the raw-document upgrade. Lossless schema preparation occurs in memory and publishes only with accepted application work; dry-run, decline and preflight failure leave original bytes intact; post-generation command failures follow the run/update distinction below. Older unsupported schemas retain the explicit conversion path prescribed by ADR 0014 and existing upgrade tools.

Extend `seihou-cli/src/Seihou/CLI/ManifestGuard.hs` and run integration to compare recorded base nodes as well as the target and modules before project writes. Older local bases and proven origin mismatches use the existing hard-error policy with visible `--allow-downgrade` behavior. Unverifiable `LocalOrigin` and incomparable unconstrained versions remain advisory under ADR 0003; an explicit producer source still requires proof even on first run. In particular, declared producer source/range requirements remain non-bypassable. Newer compatible bases remain legal, are listed as changes, and update the recorded chain only on success. Same-version descriptor changes produce a human warning and an actionable preview, not an invisible no-op. Detect chain insertion, removal and reparenting: a newly declared source cannot silently replace a previously recorded same-name base. Changing such identity requires the existing explicit override semantics and a clear provenance diff.

Older unknown-chain applications can adopt current resolved provenance through ordinary accepted run/update without pretending those nodes produced the old files. Attach the chain in both run application-construction paths and preserve it in `Seihou.Core.Application` helpers. Follow ADR 0023: run publishes generation provenance before commands, so a command failure may leave generated files and their new chain while withdrawing command receipts; update publishes inside its existing rollback transaction. Preflight failure and declined preview publish neither. Report adoption once in preview, keep existing target/module guards, and publish the chain with the accepted result. Add core JSON/upgrade tests in `seihou-core/test/Seihou/Manifest/TypesSpec.hs` and `seihou-core/test/Seihou/Manifest/UpgradeSpec.hs`, guard regressions in `seihou-cli/test/Seihou/CLI/ManifestGuardSpec.hs`, and public-command cases in a new `seihou-cli/test/Seihou/CLI/RecipeExtensionE2ESpec.hs`. Register the latter in the CLI Cabal file and test runner. M3 passes portable roundtrip, old-schema no-write adoption previews, base-only guard refusals and successful provenance publication.


### M4 — Include base changes in update and cache refresh


Extend `requirementsFor` and candidate staging in `seihou-cli/src/Seihou/CLI/Update/Source.hs` to retain recorded base origins as comparison evidence, then recursively discover the selected candidate roots' base/member edges to a fixed point. Only the candidate closure is required for the new composition: a removed/replaced base must not remain a mandatory fetch or cache entry solely because it occurs in history. Fetch old sources only when an existing migration/baseline requirement independently needs them, and explain that requirement. Compare matching old/new node identities and report additions/removals explicitly. A fixed point means continue until no new required origin or artifact is found. A child may add an entirely new base registry; looking only at the previous manifest's origins is insufficient. Reuse the kind-aware closure planner and normalized-definition staging from M2 in a temporary session, rather than call install against the real cache during preview. Validate each producer source and interval, origin collision and cycle before planning effects. A fresh clone can fetch remote requirements from manifest/declared edges without an installed copy.

Use the same `ExpandedRecipe` in every recipe path in `seihou-cli/src/Seihou/CLI/Update.hs`, including legacy adoption and `RecipeInputSpec` construction. Reuse saved application recipe inputs; child literals still outrank history, and constraints still apply. Carry new recipe nodes in candidate/planned application state in `seihou-cli/src/Seihou/CLI/Update/Types.hs`. Render base version, origin, descriptor and chain changes in `seihou-cli/src/Seihou/CLI/Update/Render.hs`, including the existing versioned JSON plan. Define additive recipe-chain changes explicitly in the JSON schema and test its version contract; do not represent a descriptor-only change as a fictitious module version change. A base-only change is actionable even if target version and generated bytes are unchanged: accepted provenance work advances the recorded chain and does not rerun unchanged application commands merely to record metadata. Keep the current three-way merge, command receipts, migration inclusion, source stale-plan checks and transaction recovery. Include candidate base bytes in stale-plan validation and publish required cache entries only as part of accepted work.

Extend `seihou-cli/src-exe/Seihou/CLI/Upgrade.hs` to select installed recipes as well as modules and refresh a selected recipe's full candidate closure through the shared planner. An unchanged child cannot suppress a newer base check. `upgrade haskell-cli-app-with-agents --dry-run` lists the base-only refresh without writes; `upgrade haskell-cli-app-with-agents` changes cache state only, then recommends `seihou update haskell-cli-app-with-agents` for safe project reconciliation. Retain module-only invocations and flags. If a root is selected by both explicit name and closure, plan it once. No-argument upgrade includes installed recipe roots without duplicating their modules. Do not extend this work to unrelated artifact kinds.

M4 passes the public workflow from an accepted prior application: move only a base version/descriptor, keep the derived version fixed, preview and accept `update haskell-cli-app-with-agents`, then repeat to observe a real no-op. Also test a newly introduced external base/module, a version beyond the declared upper bound, a substituted base, settings-only changes, fresh-clone empty-cache replay and old unknown-chain adoption. Preview, refusal, EOF, stale candidate and failed apply must preserve files, cache, baselines, manifest and command markers. Use the existing update transaction tests where possible and add base-specific cases rather than duplicate the entire generic rollback suite.


### M5 — Document, publish and verify installed delivery


Update `docs/user/module-authoring.md`, `docs/user/config-and-variables.md`, `docs/cli/install.md`, `docs/cli/update.md`, `docs/cli/upgrade.md`, `docs/cli/manifest.md`, `seihou-cli/help/recipes.md`, `seihou-cli/help/registry.md` and affected embedded agent instructions. Show the exact author shape, root versus derived nonemptiness, inheritance order, global binding semantics, defaults versus literals, prompt overrides, interval selection and failure recovery. Update generated recipe guidance in `seihou-cli/src-exe/Seihou/CLI/NewRecipe.hs` so it points authors to the supported extension shape and does not claim all recipes require local members. Update recipe presentation in `seihou-okf-extension/src/Seihou/OKF/Docs/Model.hs` and `seihou-okf-extension/src/Seihou/OKF/Docs/Render.hs` so generated registry docs retain the parent relationship and override rules rather than describing an empty child as empty composition.

Distill durable semantics into relevant ADRs, including descriptor-local versus merged checks in ADR 0022, acquisition in ADR 0020, binding sources in ADR 0021, guards in ADR 0003, and manifest evolution in ADR 0014. A new recipe-inheritance ADR can gather the merge contract without duplicating all surrounding decisions. Discover the current ADR contract with `mori show --full` before writing; use the established plain-file convention unless a profile has since been adopted. Link the request to this plan and record its implemented/delivered state accurately through the repository's request/log conventions.

Follow the release skill when publication is authorized; this create request does not publish anything. Publish a compatible CLI before publishing producer descriptors that depend on its decoder. Publish schema changes and coordinate the `schema` gitlink, `flake.nix` input, `flake.lock`, and emitted Dhall URL/hash with the actual released schema. Choose Haskell package versions under PVP from final public API changes, not a preselected number. Verify current package-registry releases and upstream tags before selecting bounds/pins. Publish both producer registries' versioned examples and generated documentation, then replay the exact consumer commands without candidate rewrites. Complete the native Nix package build with tests, not just flake evaluation.

Record source executable path/version, package releases and revision, schema revision, producer revisions/artifact versions, and the user's effective installed executable path/version. Run the complete harness with the released installed binary and empty isolated caches. Verify first use, repeated use, fresh-clone update and a compatible base-only upgrade. Publishing or authorized local installation left undone keeps M5 open; source tests are not a delivered feature. At completion, triage friction entries under this plan and cite their outcomes, then fill Outcomes & Retrospective and complete ADR distillation.


## Concrete Steps


Run development commands from the Seihou repository root. Discover producer sources before reading or editing dependency APIs; never traverse `/nix/store` or the filesystem root. Check producer-local instructions and preserve unrelated changes. Start with:

```bash
mori registry list
mori registry search seihou
mori registry show shinzui/seihou-schema --full
mori registry docs shinzui/seihou-schema
mori registry show shinzui/seihou-modules --full
mori registry docs shinzui/seihou-modules
mori registry show shinzui/agent-seihou --full
mori registry docs shinzui/agent-seihou
mori show --full
nix develop -c cabal build exe:seihou
nix develop -c cabal list-bin exe:seihou
```

The last command prints the candidate executable path; verify it exists and run its `--version`. It is separate from `command -v seihou` and installed `seihou --version`. Use the printed absolute path in candidate harness invocations. The harness below is to be created in M2, not an existing command:

```bash
python3 scripts/verify-recipe-extension.py \
  --binary /absolute/path/to/source-built/seihou \
  --area /tmp/seihou-118-candidate \
  --candidate-repo /absolute/path/to/committed/seihou-modules \
  --candidate-repo /absolute/path/to/committed/agent-seihou
```

The harness resolves each committed checkout's remote, routes fetches through its isolated Git configuration, records all candidate revisions, installs `haskell-cli-app-with-agents` by the real published URL and runs it with ordinary project inputs. Select provisioning disabled through existing recipe variables, or use argument-recording stubs in the harness PATH; no live repository creation is required. Run one interactive preview/confirmation with those same producers to verify prompts and human output. A preview transcript should communicate these facts; exact wording is implementation-owned:

```text
Recipe: haskell-cli-app-with-agents
Base chain: haskell-cli-app-repo -> haskell-cli-app-with-agents
Each recipe's version and source are shown.
The oldest base's primary module is retained.
The composition lists base modules and agent-gitignore once.
```

After the candidate proof passes, broaden meaningful checks. Existing focused suites and final gates are:

```bash
nix develop -c cabal test seihou-core-test --test-options='-p Recipe'
nix develop -c cabal test seihou-core-test --test-options='-p Resolve'
nix develop -c cabal test seihou-core-test --test-options='-p Manifest'
nix develop -c cabal test seihou-cli-test --test-options='-p Recipe'
nix develop -c cabal test seihou-cli-test --test-options='-p Install'
nix develop -c cabal test seihou-cli-test --test-options='-p Update'
nix develop -c cabal build all
nix develop -c cabal test all
nix fmt
nix flake check
nix build .#seihou
nix develop -c just audit-cli-docs
git diff --check
```

Require exit 0 and confirm focused patterns actually select the new tests. The full suites include the extension package. `nix build .#seihou` is the native package build with tests; verify the current flake output name before use if packaging changes. For schema authoring, type-check/evaluate the producer's package and representative old/new descriptors with `dhall type` and `dhall normalize` from that producer's root, plus its existing checks. No new third-party package is required by this plan; reuse text/map/graph/version/hash machinery.

After publication, run from this repository root:

```bash
python3 scripts/verify-recipe-extension.py \
  --binary /Users/shinzui/.nix-profile/bin/seihou \
  --area /tmp/seihou-118-installed
```

Omit all candidate rewrites. The harness must print exact executable/version and schema/producer evidence, then report successful first use, replay, base-only update and refusal checks. Use new area paths to retain evidence rather than overwrite an unrelated fixture. Public command names and interval/override field names above are the implementation contract, not claims that today's executable accepts them.


## Validation and Acceptance


First-use acceptance starts from actual published or committed candidate producers, empty isolated config/cache roots, and an empty project. Installation must acquire all base recipes and required modules, each with the correct origin, and no unrelated registry entries. Remove temporary source clones before generation. Ordinary run previews the whole chain and module count; acceptance generates base files plus the agent ignore rules with the oldest base primary/namespace. A shared harmless command executes once. A child with no added modules can specialize settings successfully.

Exercise ancestor binding `team`, child binding `organization`, personal global configuration `personal`, a declaration default `default`, and CLI `explicit`: child literal wins without CLI and CLI wins when supplied, subject to validation. A child declaration default alone must leave the ancestor literal selected. Saved inputs retain their documented tier. Cover undeclared literal bindings and a rejected consumer constraint with original source attribution. Compatible shared modules deduplicate; different origins and conflicting repeated member bindings fail unless the latter is expressed through the explicit override. Legitimate distinct module parent-binding instances keep existing behavior.

Exercise a three-level chain, same-registry implicit source, external explicit source, normalized equivalent URLs, a settings-only child, bounded and unbounded versions, and an unversioned unconstrained local base. Reject missing base, wrong kind, malformed source/range, interval boundary violations, direct and indirect cycles, incompatible type/requiredness/validation, missing override targets and ambiguous prompts. Diagnostics name the derived root, relevant chain, conflicting names and a supported repair. Use marker commands and byte snapshots to prove failure precedes generation, prompting/config saving where appropriate, shell effects and manifest publication. Verify standalone descriptor validation succeeds without installed parents and clearly limits its claim.

After accepting a run, inspect the committed manifest: every recipe node has name, portable origin, version and descriptor digest, while target and module records remain consistent. Serialize/decode with no absolute paths, including project-relative and unverifiable local-origin fixtures. Run from a fresh clone and empty cache through `seihou update haskell-cli-app-with-agents`; it must obtain required sources using normal network-enabled staging and replay saved values. Test supported older schema fixtures with unknown chain history. Dry-run, declined adoption, preflight failures and failed transactional updates preserve old bytes; accepted work records current evidence without inventing prior provenance.

Change only a base version and then only a base descriptor under an unchanged derived version. Ordinary update must show both changes, record accepted provenance even for metadata-only work, reconcile actual file changes, preserve user edits, and skip unchanged commands. An unchanged repeat says it is up to date. Cache-only recipe upgrade must also discover base-only changes. Stale/substituted bases must fail local generation before project writes; an out-of-range candidate must fail acquisition/update without cache publication. Explicit existing overrides remain visible and never bypass producer constraints. Prevent network access during run and compare the install-cache snapshot afterward to prove no acquisition occurs there.

Preserve the existing flat recipe suite, descriptor exit statuses, module parameterization tests and old manifest capability checks. Verify human help, generated registry docs and actionable error text; ordinary users must not need JSON or source inspection. M5 requires the same acceptance against published producers and the effective installed released executable. Record any platform or publication limitation and keep its deliverable open.


## Idempotence and Recovery


Use disposable projects and isolated state; do not repair fixtures by editing internal JSON or preinstalling transitive artifacts. Candidate rewrites live only in the harness Git config and never enter committed provenance. Repeating the ordinary install repairs a partial older cache through closure acquisition. Run stays offline and reports the derived-root install command when required dependencies are absent. Updating existing projects uses the normal preview rather than replacing user edits with fixture preparation.

Retain existing cache backups and update recovery journals through publication. Validate the entire closure before replacing any installation. A handled install staging/publication failure restores its cache replacements; a handled update staging/apply failure restores protected files, cache, baselines and manifest; preserve recovery data when rollback itself fails. Arbitrary provisioning command effects keep the existing rollback limitation, so acceptance uses harmless markers/stubs. Do not promise a stronger crash-atomic install transaction than the current installer provides.

Do not reset the existing modified `schema` gitlink or producer edits. Integrate published schema changes against current upstream without force-pushing. Commit implementation at meaningful boundaries on the current branch with Conventional Commits and trailers `ExecPlan: docs/plans/118-extend-recipes-through-a-single-origin-aware-base.md` and `Intention: intention_01m6c6c0theva9djfqz4prcy8q`. Producer commits use `ExecPlan: mori://shinzui/seihou/plans/118-extend-recipes-through-a-single-origin-aware-base` plus the same intention; never a foreign repository-relative path. Release retries follow the release skill and preserve already published artifacts.


## Interfaces and Dependencies


`RecipeReference` distinguishes a recipe name from a module name, carries a literal optional Git source, and carries an optional `RecipeVersionRange` with `minimum` inclusive and `before` exclusive. No source means declaring registry during install; project-local discovery remains honest about absent remote provenance. `Recipe` adds optional `extends`, `moduleOverrides :: [RecipeModuleOverride]` and `promptOverrides :: [Prompt]`. `RecipeModuleOverride.Type` is `{ module : Text, vars : List { name : Text, value : Text } }`, with `vars` defaulting to a typed empty list. Export it, `RecipeReference`, and `RecipeVersionRange` from the schema package. The Haskell override contains a module name and a map of literal binding values; descriptor order is retained long enough to diagnose duplicate keys rather than silently overwrite them during map decoding. Apply the same duplicate-binding-key check to new extended-chain authoring surfaces.

`ExpandedRecipe` is a named result shared by run and update. It exposes primary, ordered resolved members with their effective `Dependency` records, merged declarations/prompts, recipe literal values with recipe-source labels, and oldest-first `ResolvedRecipeNode` values. Compute each descriptor digest through the same shared canonicalization for installed and candidate definitions: evaluate imports, supply decoder defaults, materialize producer-owned implicit sources, and normalize field ordering. Exclude runtime paths and installation timestamps so identical source content hashes equally before and after install. Each resolved node retains origin, name, optional version, descriptor digest and an in-memory local directory; only the portable subset becomes `AppliedRecipeNode`. Chain lookup accepts local search paths for run and a staged candidate catalog for update, while a pure merger validates resolved descriptors. `ExpandedRecipe.members` contains `ResolvedRecipeMember` rather than context-free dependencies alone. Its literal map carries value plus declaring recipe identity; extend the source-aware resolution path in `seihou-core/src/Seihou/Composition/Resolve.hs` and the source representation/renderers in `seihou-core/src/Seihou/Core/Types.hs` and their callers to retain this attribution. Preserve the legacy `FromRecipeBinding` path for flat callers as needed, and avoid persisting ephemeral source directories. A value rejected by a consuming module must identify the ancestor or child that actually supplied it. Errors should be typed and rendered as human text in core/CLI boundaries; update retains its existing JSON error envelope. Do not serialize Haskell `Show` output or lose the chain in a generic Dhall decoder error.

The acquisition planner accepts expected recipe/module kinds, reports origin-qualified chains and validates the complete merged closure before publication. Factor reusable staging out of `seihou-cli/src/Seihou/CLI/InstallClosure.hs` as needed so update and upgrade can plan in temporary roots without mutating installed state. Keep closure selection independent of generation bindings. Runtime verification uses `Seihou.Core.ArtifactIdentity`, `Seihou.Core.ArtifactRef`, `Seihou.Core.Version` and existing provenance guards; hashing is evidence through the existing SHA-256 facilities. No new dependency bounds, general constraint-language parser, runtime Mori process or registry search is needed.

Cross-repository delivery participants are `mori://shinzui/seihou-schema`, `mori://shinzui/seihou-modules`, and `mori://shinzui/agent-seihou`. Discover paths with Mori and verify current upstream revisions before pins; use their canonical artifact URIs in durable references. Add intended canonical URIs for the published new recipes even if registry indexing lags. Keep schema exports, CLI decoding, generated help and actual producer adoption coordinated. Completion means the ordinary installed consumer workflow passes, not merely that every internal type has been extended.


Revision note (2026-11-01): Reviewed the original gpt-6.1-sol plan (no prior recorded reviews) against the decoder, composition/input APIs, install/update/upgrade paths, producer descriptors and ADRs 0003/0020–0023. Clarified resolved-member context, layer-based literal merging and attribution, optional values, prompt execution, removed-base acquisition, local-origin guards, and run versus update publication/failure semantics. This is a plan correction, not implementation or released acceptance.

Validation evidence (2026-11-01 review/update): `dhall type` accepted the plan's exact authoring example against temporary proposed record types and existing local `Recipe`, `Dependency`, `VarDecl`, and `Prompt` schema definitions. This validates the proposed Dhall shape only; the published schema and Haskell decoder do not yet expose the new fields. Relative Markdown links and fenced-block language/pairing checks passed; `git diff --check` passed. No implementation suites or consumer delivery checks were claimed.
