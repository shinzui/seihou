---
id: 114
slug: resolve-recipe-variables-and-prompts-before-module-resolution
title: "Resolve recipe variables and prompts before module resolution"
kind: exec-plan
created_at: 2026-10-28T12:32:47Z
intention: "intention_01m617w2yseak83z91rrwpp3sh"
provenance:
  created_by:
    model: "gpt-6-astra"
    harness: "codex-cli"
    at: 2026-10-28T12:32:47Z
  revisions:
    - model: "gpt-6.1-sol"
      harness: "codex-cli"
      at: 2026-10-28T13:28:31Z
      mode: "implement"
      note: "Implement shared recipe input resolution, replay, and acceptance checks"
    - model: "gpt-6.1-sol"
      harness: "codex-cli"
      at: 2026-10-28T14:22:49Z
      mode: "update"
      note: "Link completed request and verify released installed recipe inputs."
---

# Resolve recipe variables and prompts before module resolution

This ExecPlan is a living document. Keep Progress, Surprises & Discoveries, Decision Log, and Outcomes & Retrospective current. Follow `agents/skills/exec-plan/PLANS.md`, `ADR.md`, and `FRICTION.md` in that directory during implementation.


## Purpose / Big Picture


A recipe author must be able to ask once whether a feature is wanted and give that answer to every composed module, even when those modules default the feature to false. Implement [IR-11](../improvement-requests/resolve-recipe-variables-and-prompts-before-module-resolution.md): resolve recipe declarations and conditional prompts before module variables, preserve explicit false values, reject invalid or missing required input before generation, and reuse accepted inputs during updates.

The normal starting state is a project directory with a recipe and its modules available through Seihou's discovery paths. The developer runs `seihou run recipe-input-probe`, answers its two feature questions once, and accepts the existing save-input offer if desired. They need neither `--confirm-defaults` nor knowledge of module ordering. `seihou run recipe-input-probe --dry-run` previews the same choices without changing project files, config, or applied state. Later, `seihou update recipe-input-probe` reuses accepted choices and retains its ordinary preview/confirmation workflow. A fresh clone carries those choices in the checked-in manifest; a developer does not repair JSON or repeat setup answers.

For the motivating consumer, the two choices are `git.createGithub` and `nix.redpanda`. PostgreSQL, process-compose, intention tracking, and TAN Mori generation remain enabled by literal recipe bindings. GitHub owner/name questions appear only when GitHub creation is selected and the values are absent. This plan fixes the generic Seihou behavior and verifies a representative composition; implementing or publishing the TAN recipe remains the producer's work. Cross-registry installation is tracked separately in [IR-12](../improvement-requests/declare-and-install-cross-registry-recipe-dependencies.md); do not hide manual installation work in acceptance evidence or make its unfinished implementation a prerequisite for the resolver tests.


## Progress


- [x] M1 (2026-10-28; terminal true/false acceptance and closed-stdin E2E passed): The ordinary run command resolves recipe inputs before module defaults; a terminal asks each shared choice once, and closed stdin refuses unresolved required choices without changes.
- [x] M2 (2026-10-28; core prompt regressions, recipe saving tests, and consumer acceptance passed): Conditional prompting, validation, source attribution, save-input behavior, and precedence work across recipe and module resolution without changing recipes that have no inputs.
- [x] M3 (2026-10-28; schema roundtrips, historical adoption E2E, recipe-only replay, fresh-clone and new-consumer acceptance passed): Updates and fresh clones replay accepted recipe choices, including recipe-only inputs, and older supported manifests adopt the representation through the normal preview and atomic apply.
- [x] M4 (2026-10-28): Seihou 0.12.0.1 is published and installed at f529a7a. The installed terminal, replay, fresh-clone/new-consumer and representative-consumer acceptance passed, together with source and full native package checks.

Baseline: Installed `seihou --version` reported `seihou v0.11.0.1 (4ade3fb)` on 2026-10-28. IR-11 supplies the pre-fix command reproduction; the initial planning session inspected code but did not run its fixture. Implementation evidence follows below.


## Surprises & Discoveries

2026-10-28: Installed `seihou v0.11.0.1 (4ade3fb)` reproduced the required-input bug with closed stdin in `/tmp/seihou-recipe-baseline-114b`. The candidate terminal harness demonstrated both choices once and matching values in both consumers, then ordinary update from a fresh Git clone with empty config/cache. A third consumer received the saved choice despite conflicting environment input.

2026-10-28: Update's no-op comparison ignored application recipe inputs. Including the field is necessary to publish recipe-only changes and adoption even when generated files do not change. Direct module applications retain unknown recipe inputs, preserving their existing repeat-update behavior.


## Decision Log

2026-10-28: Prepare schema 12 when the selected applications include a recipe; retain the existing capability-driven preparation for module-only selections. Preserve module-only application records with `recipeInputs = Nothing`. Include recipe-only inputs in update summaries and application equality, and suppress module prompts for declarations owned by the recipe, including deliberately skipped optional inputs.

2026-10-28: Use one recipe-input stage shared by run and update, before module variable resolution. Loading module definitions to discover the composition may happen first; module defaults must never satisfy a required recipe decision. Reusing the same stage avoids different first-use and update semantics.

2026-10-28: Preserve literal recipe-entry binding precedence and the first-entry-wins flattening performed by `expandRecipe`. At the recipe stage use explicit CLI values, literal entry bindings, saved recipe values on ordinary update, environment, local/namespace/context/global config, and recipe defaults, in that order; prompt only for eligible unresolved declarations. Pass the resulting values as recipe-supplied bindings to modules, below explicit CLI values and literal entry bindings but above module saved values and ordinary module resolution. Preserve sources separately from precedence. This makes a recipe decision consistent across consumers without weakening existing literal bindings. Redesigning entry-specific parameterization is outside this request.

2026-10-28: Record recipe inputs at application scope in the manifest. Per-module values cannot preserve a recipe-only choice used as a prompt condition. Add a versioned, optional recipe-input record that distinguishes an older application with unknown inputs from a newly resolved empty input set. Do not create a synthetic module instance or a second state file. This is necessary to meet repeat-use acceptance, and invokes ADR 0014's schema evolution rules.

2026-10-28: Required declarations remain required even if their prompt condition is false; prompt conditions control interaction, not the declaration's requirement. Conditional GitHub detail declarations should be optional, following existing module authoring. Do not invent conditionally required schema fields or variable interpolation in literal dependency bindings.


## Outcomes & Retrospective

Source implementation includes shared recipe resolution, error-preserving prompts, recipe-aware saving and previews, schema 12 codecs/upgrades, and update replay/adoption. Durable decisions are recorded in [ADR 0021](../adr/0021-recipe-inputs-resolve-before-module-defaults.md) and the schema contract in [ADR 0014](../adr/0014-every-semantic-manifest-change-advances-the-schema-version.md). No friction entries were logged under this plan; shared release friction is triaged under plans 113 and 115.

The representative consumer wrapper uses actual modules located through Mori, without changing their definitions. Its isolated preparation copies the dependency closure and pre-supplies unrelated project inputs. Shell commands are explicitly disabled to avoid creating remote repositories; this proves generation and prompting, not execution of remote provisioning. It is not a published TAN recipe. The `mori://shinzui/seihou-modules` producer revision is `a5cbd51d7cd45c0a872e208f43bf6dd32eafe4fe` and the `mori://shinzui/agent-seihou` producer revision is `50f38289478bc13f9e8002df228cdea955a3f581`; canonical artifact references are listed in Context and Orientation. Harness transcripts and preparation records live beneath `/tmp/seihou-recipe-final-114`; this final harness run passed synthetic terminal questions, command-marker protection, fresh-clone replay, new-consumer replay, and representative real consumers.

Validation: `cabal test all` passed 1,267 core, 791 CLI, and 51 extension tests. `nix fmt`, `git diff --check`, the CLI source/runtime documentation audit, and all four native `nix flake check` checks passed. The flake checks cover the native Darwin system; incompatible systems were omitted by Nix. Those initial checks preceded publication; released and installed evidence follows.

Delivery is complete in Seihou 0.12.0.1. The initial source checkpoint used base
8ea17ac and an installed 0.11.0.1 baseline; final acceptance below uses the published
and installed Nix artifact rather than a development executable.

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


Seihou is a Haskell CLI. A module declares typed inputs, templates and commands. A recipe names a composition (several modules run as one application), declares its own inputs, and supplies literal bindings through its module entries. A module instance identifies one invocation by module name and parent bindings; distinct parameterizations must retain distinct saved values. An application is the recorded root module or recipe plus its additional modules.

`seihou-core/src/Seihou/Composition/Recipe.hs` exports `expandRecipe`, returning the primary module, additional modules, flattened literal overrides, recipe `VarDecl`s, and recipe `Prompt`s. `seihou-core/src/Seihou/Core/Recipe.hs` validates the recipe. The primary module still determines the default configuration namespace. `seihou-cli/src-exe/Seihou/CLI/Run.hs` ignores `_recipeVars` and `_recipePrompts`, merges literal bindings into CLI overrides, and calls `resolveWithPrompts`. `seihou-cli/src/Seihou/CLI/Update.hs` repeats the omission in `candidateRoot` and `seedInstalledLegacyApplication`; `resolveApplicationValues` currently knows only modules, saved instance values, and flattened overrides.

`seihou-core/src/Seihou/Composition/Resolve.hs` loads the dependency graph and resolves instances in dependency order. `resolveWithPromptPermission` supports `PromptsAllowed` and `PromptsForbidden`; forbidden prompting must not query terminal availability. Dependency exports currently become defaults for matching module declarations. `seihou-core/src/Seihou/Core/Variable.hs` owns coercion, validation, environment names such as `SEIHOU_VAR_GIT_CREATEGITHUB`, and the input precedence chain. Its all-or-errors return discards successful bindings when any required variable is missing. A recipe prompt condition must nevertheless see successfully resolved siblings as well as earlier answers, so do not pass only prior modules' bindings to the new stage.

`seihou-core/src/Seihou/Interaction/Prompt.hs` evaluates prompt conditions against typed values and returns `FromPrompt` values. Its current `runPrompts` discards individual prompt errors, and accepting a default directly does not perform the same coercion path as a typed answer. The recipe stage must not accidentally accept an exhausted invalid optional answer or evaluate a text `"false"` as a boolean. `seihou-core/src/Seihou/Effect/ConsolePure.hs` provides scripted interactive and noninteractive interpreters for focused tests.

`seihou-cli/src/Seihou/CLI/SavePrompted.hs` finds `FromPrompt` in resolved instance maps. Simply converting every recipe answer into a CLI string loses this source and omits recipe-only choices. `Run.hs` also derives unused-config diagnostics and default confirmations from module declarations alone. Include recipe declarations and results in these user-facing paths, without listing or saving the same choice once per module.

`seihou-core/src/Seihou/Core/Types.hs` defines `AppliedComposition` and `AppliedInstanceState`; the former has no recipe input field today. `seihou-core/src/Seihou/Core/Application.hs` builds application records. `seihou-core/src/Seihou/Manifest/Types.hs` owns version-selected JSON codecs and manifest capabilities; the current version at planning is 11. `seihou-core/src/Seihou/Manifest/Upgrade.hs` owns adjacent lossless upgrade steps. Update's existing staged preparation and transaction publish the new manifest only after accepted work succeeds. Reuse that path for recipe input adoption.

Relevant ADRs were discovered by scanning `docs/adr/` filenames and headings. [ADR 0001](../adr/0001-manifest-is-a-checked-in-machine-independent-artifact.md) requires portable checked-in state, so store names and values without checkout paths. [ADR 0004](../adr/0004-the-manifest-is-the-only-record-of-applied-state.md) makes the manifest the only applied-state record. [ADR 0014](../adr/0014-every-semantic-manifest-change-advances-the-schema-version.md) requires a new version, capability, adjacent upgrade, and version-selected encoding for new serialized semantics, with lossless preparation staged in normal operations. [ADR 0015](../adr/0015-diagnostics-name-things-as-users-do-and-never-fall-back-to-show.md) requires actionable variable and recipe names rather than constructor syntax. No existing ADR directly defines recipe prompt precedence; create a focused decision record during implementation and amend relevant manifest guidance when the contract is verified.

The schema already supports both fields: `schema/Recipe.dhall` in this checkout and `Recipe.dhall` in `mori://shinzui/seihou-schema` (artifact-level URI pending) declare `vars` and `prompts`. Mori discovery located and source inspection confirmed this; no dependency upgrade or schema-source change is planned. The motivating producer is `mori://tan/tan-seihou-modules/masterplans/1-bootstrap-tan-keiro-projects-with-a-cross-registry-recipe`. Its project was not registered locally during planning, so its proposed recipe is not claimed as tested. The real module sources were located through Mori: `mori://shinzui/seihou-modules/templates/git-init`, `mori://shinzui/seihou-modules/templates/nix-haskell-flake`, `mori://shinzui/agent-seihou/templates/master-plan`, and `mori://shinzui/seihou-modules/templates/haskell-keiro-project`.


## Plan of Work


### M1 — Resolve recipe decisions on the ordinary run path


Add a recipe-aware resolution entry point in `seihou-core/src/Seihou/Composition/Resolve.hs`, with recipe inputs retained as an explicit input/result rather than encoded as a fake module. Carry declarations and prompts from discovery through `Run.hs`. Resolve and validate recipe variables using the existing coercion/config rules, collect missing inputs using `Console`, and then resolve all module instances with the accepted recipe bindings. Each consuming declaration must validate the supplied value independently. Only declared recipe variables become broadcast recipe results; unrelated module keys remain on their existing path.

Create `seihou-cli/test/Seihou/CLI/RecipeInputsE2ESpec.hs` and register it in `seihou-cli/test/Main.hs` and `seihou-cli/seihou-cli.cabal`. Follow `SeedRunE2ESpec.hs` and `SeihouBinary.hs` for temporary roots, copying the pinned schema, and using the executable built with the tests. Use two modules that both declare a false default, a recipe that declares the same boolean required without a default, and a template in each module that displays its value. Add a marker command to prove errors do not execute commands. A closed-stdin run must fail before producing files, manifest, config, or command markers; fully supplied true and false inputs must render identically in both consumers.

Before broadening the test matrix, add `scripts/verify-recipe-inputs.py`, using the Python standard library's pseudo-terminal support as in `scripts/verify-checkout-restoration.py`. A pseudo-terminal lets the executable see an actual interactive stdin, unlike piping answers. The script should accept `--binary` and `--area`, construct the fixture, run ordinary commands, count questions, enforce timeouts, and retain transcripts and snapshots. It must first reproduce the installed binary's bug and then prove the candidate asks once and broadcasts the answer. Report a baseline failure as expected evidence, not success of the corrected acceptance. M1 passes when these checks work without `--confirm-defaults` or repairs between invocation and observation.

### M2 — Complete conditional input and human-interface behavior


Factor a declaration-resolution helper that retains both successful values and errors, so conditions see recipe CLI/config/default values despite unrelated missing required inputs. Reuse `resolveVariablesWithSaved` per declaration or factor its existing internals; do not duplicate type coercion or precedence. Process prompts in declaration-specified prompt order, adding each answer to typed current bindings. Resolve unresolved optional prompts after required answers so a newly selected feature can enable follow-up questions. Required omissions remain errors in noninteractive mode; optional skips remain absent.

Add an error-preserving prompt API in `seihou-core/src/Seihou/Interaction/Prompt.hs` for the recipe resolver, distinguishing a deliberate optional skip from invalid input exhausted after retries. Keep current module callers compatible or migrate them with regression coverage. Coerce and validate accepted defaults and answers. Fatal invalid config or CLI input must fail rather than prompting to conceal it. Prompt retry wording can repeat on invalid input; “exactly once” refers to each successful normal decision, not retries.

Retain the original `ResolvedVar.source` for recipe results and propagate meaningful sources to consumers while keeping each consumer's own declaration. A recipe default that must be confirmed under `--confirm-defaults` is confirmed once at recipe scope before broadcasting; it must not independently change in each module. Existing module-only confirmations remain supported. Update `SavePrompted.hs` to combine recipe and module prompted values, deduplicate names, preserve false, and omit unchanged local values. Save only after successful real apply, respecting both save flags and the existing optional save confirmation. Include recipe-only declarations in unused-config diagnostics and display recipe inputs in the dry-run/explain surfaces already used by run.

Extend `seihou-core/test/Seihou/Composition/ResolveSpec.hs`, `seihou-core/test/Seihou/Interaction/PromptSpec.hs`, and `seihou-cli/test/Seihou/CLI/SavePromptedSpec.hs`. Assert precedence conflicts, false versus absence, config-supplied conditions, invalid optional answers, no terminal queries when forbidden, validation by all consumers, and no extra prompts or behavior changes for empty recipe inputs and direct module runs. M2 passes when focused tests and the terminal script demonstrate these behaviors and the human error supplies a usable `--var key=value` remedy.

### M3 — Persist and replay accepted recipe inputs through update


Add `recipeInputs :: Maybe (Map VarName Text)` to `AppliedComposition`: `Nothing` means no recipe-resolution record is available, while `Just Map.empty` means the recipe stage ran and recorded no values. Use the project's canonical value-to-text conversion for persistence. Store only resolved recipe declarations here, independently of module instance values. Remove values for declarations no longer present when reconfiguring a candidate. Do not serialize ephemeral prompt source tags or filesystem locations.

Add the next manifest version and a `RecipeInputs` capability in `Core/Types.hs`, `Manifest/Types.hs`, and `Manifest/Upgrade.hs`. At this planning baseline the adjacent step is 11 to 12; recheck the current version before implementation because other plans may advance it. Older codecs must retain their old representation. Lossless upgrade records unknown recipe inputs without manufacturing historical choices; stage it through the normal run/update path and include the change in the ordinary preview. A dry run or failed apply must leave original bytes untouched. Update application constructors, fixtures, codecs, upgrade tests, and the human schema description where needed.

Carry recipe declarations/prompts through both update root paths and reuse the M1 resolver in `resolveApplicationValues`. Ordinary update uses saved recipe values before ambient config and defaults; `--reconfigure` drops them along with saved instance values, and explicit CLI values still win. A saved recipe choice must also reach a newly added module declaring the same input. Use `PromptsForbidden` for JSON/noninteractive callers as today. New required choices without saved/config/CLI values must fail clearly or prompt when permitted; an already accepted optional omission must not become a repeated question merely because the recipe is reevaluated.

For pre-change applications without recipe inputs, derive a replay value only from agreeing saved values of relevant declaring instances, re-coerced using the recipe declaration. This is runtime input selection during normal preview, not fabrication in the schema upgrade. Retain an old false even if it came from the bug's module default; do not assume the developer intended true. When recorded consumers disagree, do not silently use the first map entry: report the conflicting recipe key and require a current explicit value or `--reconfigure` under the existing interaction policy. A recipe-only required input with no historical value is genuinely new information and follows the normal missing-input path. Preserve the existing ambiguity rules for legacy flat manifests; do not flatten distinct parameterized instances to manufacture agreement.

Extend `seihou-cli/test/Seihou/CLI/UpdateE2ESpec.hs` using its local Git producer fixtures, and `seihou-core/test/Seihou/Manifest/TypesSpec.hs` and `UpgradeSpec.hs`. Verify first run followed by ordinary update with changed ambient config, a changed module default, a new consuming module, and a recipe-only condition variable. Repeat with a fresh clone and empty user config/cache through the supported source acquisition workflow. Verify old supported application records, conflicting old values, explicit overrides, reconfigure, dry-run byte preservation, and unchanged repeat updates. M3 passes without hand-editing user manifests or requiring an extra upgrade command for lossless adoption.

### M4 — Verify the consumer workflow and deliver discoverable behavior


Extend the acceptance script with a representative consumer mode, using the four canonical module references above. Resolve their directories with `mori path`, retain their Git revisions, and create an isolated recipe around their actual declarations. Set `nix.postgresql`, `nix.process-compose`, `intentions.enabled`, and `mori.generate` true and `mori.namespace` to `tan`; make `git.createGithub` and `nix.redpanda` required recipe booleans with no defaults. Pre-supply unrelated project inputs in ordinary configuration and document each preparation command, so the transcript isolates the two requested decisions without pretending they are the only inputs a new project ever needs.

Run the real composition's preview interactively with both choices false and then true. Verify only selected GitHub questions appear, actual modules see the values, and Redpanda operations change accordingly. Use dry-run for real GitHub operations; no remote repository needs to be created to prove resolution. The synthetic fixture's harmless command marker supplies apply/side-effect evidence. If the TAN producer has since published the recipe, use its actual artifact instead of the acceptance-only wrapper and record the exact acquisition command. If it remains unavailable, report that boundary plainly while completing generic Seihou delivery.

Update `seihou-cli/help/recipes.md`, `seihou-cli/help/variables.md`, `docs/cli/run.md`, `docs/cli/update.md`, `docs/user/config-and-variables.md`, `CHANGELOG.md`, and `docs/user/CHANGELOG.md`. Explain recipe precedence, required choices versus defaults, conditional optional prompts, noninteractive values, saving, and update replay with one short recipe example. Distill the durable resolution contract into an ADR using the repository's ADR workflow; do not add unrelated schema authoring features.

Run the checks below, then record candidate executable path, Git revision, package version, fixture revisions, and observations. Follow the repository's release workflow when release is authorized, and rerun acceptance with the released installed binary. Do not close the delivery obligation on the strength of `cabal run` alone: if release or installation remains, record the exact gap and leave M4 open. Implementation was authorized on 2026-10-28. On 2026-10-28 the user authorized the coordinated release and installed-executable delivery; record the verified result before closing M4.


## Concrete Steps


Run development commands from the Seihou repository root. Use `nix develop` for the declared toolchain when the ambient shell lacks the dependencies; do not inspect or traverse `/nix/store`. Initialize the pinned schema submodule in a fresh checkout if needed.

```bash
git submodule update --init schema
nix develop
cabal build seihou-cli:seihou
cabal run seihou-cli:seihou -- --version
```

Add the fixture script described in M1 before using these proposed commands. Its interface is part of this plan: `--expect-unresolved-bug` records and checks the pre-fix failure, the default mode runs corrected synthetic acceptance, and `--consumer` additionally exercises the actual module composition. `--area` must be a fresh directory and all generated test state must remain beneath it. From the repository root, substitute the executable path printed by `cabal list-bin seihou-cli:seihou` for `CANDIDATE_BINARY`; this substitution is contributor test setup, not a user workflow.

```bash
seihou --version
python3 scripts/verify-recipe-inputs.py --binary seihou --area /tmp/seihou-recipe-baseline --expect-unresolved-bug
cabal list-bin seihou-cli:seihou
python3 scripts/verify-recipe-inputs.py --binary CANDIDATE_BINARY --area /tmp/seihou-recipe-candidate
python3 scripts/verify-recipe-inputs.py --binary CANDIDATE_BINARY --area /tmp/seihou-recipe-consumer --consumer
```

The fixture is named `recipe-input-probe`. In its generated project directory, normal commands are:

```bash
seihou run recipe-input-probe
seihou run recipe-input-probe --dry-run
seihou run recipe-input-probe --dry-run --var git.createGithub=false --var nix.redpanda=true </dev/null
seihou update recipe-input-probe
seihou update recipe-input-probe --dry-run </dev/null
```

The first command asks `Create a GitHub repository?` and `Enable Redpanda?` once each. With true for GitHub and absent detail inputs it additionally asks owner and name, subject to ordinary optional prompt semantics. The save-input confirmation is separate from feature questions. The third command needs neither stdin nor default confirmation and renders false/true in every declaring consumer. Removing either required flag with empty config must produce a named missing-variable error before any generated output. After apply, the two update commands reuse recorded decisions.

Run focused suites as the corresponding milestones land, from the repository root:

```bash
cabal test seihou-core-test --test-show-details=direct --test-options='-p "Seihou.Composition"'
cabal test seihou-core-test --test-show-details=direct --test-options='-p "Seihou.Interaction.Prompt"'
cabal test seihou-cli-test --test-show-details=direct --test-options='-p "Recipe inputs"'
cabal test seihou-cli-test --test-show-details=direct --test-options='-p "SavePrompted"'
cabal test seihou-core-test --test-show-details=direct --test-options='-p "Seihou.Manifest"'
cabal test seihou-cli-test --test-show-details=direct --test-options='-p "Update"'
```

Name the new end-to-end test group `Recipe inputs`; verify each filter selects tests rather than accepting a zero-test pass. At the coherent final source boundary run:

```bash
cabal test all --test-show-details=direct
nix fmt
git diff --check
nix flake check
python3 scripts/audit-cli-docs.py --executable CANDIDATE_BINARY
```

Replace `CANDIDATE_BINARY` with the same absolute path printed by `cabal list-bin` above so the docs audit exercises the candidate. Record environmental failures and their scope; never substitute old-binary results for candidate acceptance. No application test run is required just to create this plan.


## Validation and Acceptance


The minimum distinguishing regression is a required recipe boolean with no default consumed by two modules whose defaults are false. Before this work, closed stdin succeeds with false. Afterward it fails with the recipe/variable named; interactive true produces true twice and interactive false produces false twice, with one question. Explicit CLI values bypass the question. Fatal recipe or consumer validation prevents output files, command markers, config changes and manifest writes. Capture exit codes and byte snapshots, not just messages.

Cover CLI versus literal binding, literal binding versus config, saved recipe values versus ambient config on update, environment versus each config scope, config versus recipe default, recipe result versus module default/parent/export, and true/false values in each relevant path. A recipe-only condition variable must not become an unused-config warning or disappear from saved application state. Unrelated parameterized module values retain their own precedence and identities. Empty-input recipes and direct module runs retain existing behavior.

Conditions must see values supplied through CLI, config, recipe defaults and earlier prompts, even when another required field is missing. False disables optional GitHub owner/name prompts; true enables absent details exactly once, including when GitHub was supplied by CLI rather than prompted. Invalid values are retried under existing limits and then rejected; deliberately skipping an optional value remains valid. Noninteractive/JSON update never asks questions. `--confirm-defaults` may explicitly request confirmation but is not necessary for required recipe decisions.

After one accepted run, updates preserve selected true and false values without a question, even when candidate module defaults or local config change. A new consumer receives the saved recipe answer. Recipe-only inputs survive fresh-clone update, including a user declining the local config save offer. Older applications adopt without an extra command when their recorded values agree; genuinely unknown required inputs and conflicting legacy values produce actionable recovery through CLI values or reconfigure. Preview, cancellation and failure preserve original state, and an unchanged repeated update is a no-op.

For the real composition, retain module revisions and the complete ordinary command transcript. Count installation/configuration preparation explicitly, separate feature questions from unrelated project questions and save/apply confirmations, and assert both Redpanda outcomes and conditional GitHub details. Distinguish a representative wrapper from a published TAN recipe. Delivery evidence must identify source-build acceptance, released artifact availability, and the actual installed executable independently.


## Idempotence and Recovery


All acceptance fixtures live in fresh temporary directories with isolated XDG config/cache and no inherited `SEIHOU_VAR_` values. Tests may set a child process's home directory to the fixture home, but contributor commands must not repurpose the shell's `HOME`. Refuse to reuse a nonempty acceptance area; retain failed areas and transcripts for diagnosis. Do not modify the real developer's config, installed artifact cache, or remote GitHub repositories.

Recipe resolution occurs before compilation/application and before saving prompts. Cancellation or invalid input requires only a corrected rerun. A dry run must not apply schema preparation, save config, generate outputs, or run module commands; dependency/Dhall caches may be populated in the isolated test environment and must be distinguished from project writes. The update transaction stages lossless schema preparation and recipe inputs with the accepted result, restoring the old manifest on failure. Existing migration recovery remains authoritative; no manual index manipulation or JSON repair is part of normal acceptance.

Changes made while implementing use Conventional Commits with `ExecPlan: docs/plans/114-resolve-recipe-variables-and-prompts-before-module-resolution.md` and `Intention: intention_01m617w2yseak83z91rrwpp3sh` trailers. Preserve unrelated work and stay on the current branch unless the user requests otherwise.


## Interfaces and Dependencies


Keep `expandRecipe` validation and module ordering intact. Introduce an explicit recipe-resolution input containing declarations, prompts, literal bindings and optional saved inputs; return recipe `ResolvedVar`s alongside the per-instance map. Run needs the recipe result for display and saving, while update needs it for candidate application persistence. Make prompt permission an explicit argument. Existing module-only entry points can delegate with no recipe input, avoiding unrelated blueprint/manifest-capability caller changes.

`Seihou.Core.Variable` remains the coercion/validation authority; `Seihou.Interaction.Prompt` remains the Console interaction authority. Preserve source tags such as `FromPrompt`, `FromApplication` and config sources across the recipe boundary without mislabeling all accepted answers `FromCLI`. Add source variants only if required for accurate human output, with exhaustive rendering and tests. The application input record is distinct from source tags and module instance identity.

No new package or schema dependency is required. If implementation uncovers a need to change one, use Mori to inspect its source/docs and verify authoritative registry releases and upstream tags before choosing bounds or pins. Canonical cross-repository references above remain valid even where local Mori resolution is not yet available. Installation dependency closure and standalone recipe validation are separate requests; this work must integrate with them when present without silently expanding their scope.
