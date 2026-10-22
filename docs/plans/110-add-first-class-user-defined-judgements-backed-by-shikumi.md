---
id: 110
slug: add-first-class-user-defined-judgements-backed-by-shikumi
title: "Add first-class user-defined judgements backed by Shikumi"
kind: exec-plan
created_at: 2026-10-22T13:38:08Z
intention: "intention_01m5hx8k9heqcsn2ahnmxw9k6w"
provenance:
  created_by:
    model: "gpt-6.1-sol"
    harness: "codex-cli"
    at: 2026-10-22T13:38:08Z
---

# Add first-class user-defined judgements backed by Shikumi

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

Let a project author define a judgement in Dhall, apply it directly or through a module or recipe, and have Seihou review changes with a typed Shikumi program. A judgement is a versioned description of a question, the evidence it may inspect, and the findings it may return. A gate is the project policy that decides whether those findings permit an action. The first shipped example checks staged changes for secrets and contextually sensitive information before a commit.

The normal adoption command is `seihou run security-review`. Its ordinary preview explains the checks, model/data policy, and proposed Git hook integration. Accepting applies the declaration and prepares this checkout. Afterwards a developer uses ordinary `git add` and `git commit`; `seihou check` runs the same checks explicitly. A fresh clone or linked worktree uses `seihou sync` once to restore checkout setup from the manifest. Required checks also run inside Seihou's commit-producing commands before any AI commit-message request. Teams can run `seihou check --range BASE..HEAD` in CI without depending on local hooks.

Users author their own judgements without recompiling Seihou. The initial authoring surface uses one common typed evidence/finding contract, configurable instructions and categories, and labelled evaluation examples. It does not promise arbitrary user-defined Haskell types or load executable plugins.

Integrate directly with Shikumi. There is no Handan package, binary, protocol, or release dependency. Keep Shikumi types and provider details behind a Seihou-owned runtime adapter so upcoming upstream capabilities can be adopted without changing the project artifact format. Current typed generative programs are sufficient for the first delivery; planned probability-backed decision outputs are not a prerequisite.


## Progress

- [ ] M1: A thin real-consumer path applies a judgement, runs a typed Shikumi review, and blocks an ordinary commit; the required adoption and hook steps are demonstrated before expanding variants.
- [ ] M2: Authors can scaffold, validate, discover, install, compose, and evaluate custom judgement artifacts without rebuilding Seihou; the schema is available at a published immutable import.
- [ ] M3: The manifest records portable active declarations and project policies, and run/update/remove/sync preserve ownership, migration, and fresh-checkout behavior.
- [ ] M4: Staged and commit-range evidence, deterministic secret detection, the direct Shikumi adapter, coverage accounting, and redacted results satisfy the security contract.
- [ ] M5: Ordinary Git commits, Seihou commit-producing paths, and CI share the same gate semantics, with tested hook coexistence and no pre-gate AI transmission.
- [ ] M6: Help, authoring documentation, evaluation examples, source-build acceptance, and package checks demonstrate both built-in and user-authored workflows.
- [ ] M7: Released schema and Seihou artifacts, the packaged scanner dependency, and an installed executable pass the normal workflow in an existing consumer, an empty-cache clone, and a linked worktree.

Planning only is authorized in the current task. All implementation milestones remain open. The intention was created with `mina ci --json 'Add first-class user-defined judgements backed by Shikumi'`. Mina returned the frontmatter ID successfully and warned that its configured default parent is outside this project's Rei scope; changing that project association is separate from creating this plan.


## Surprises & Discoveries

(None yet.)


## Decision Log

Decision (2026-10-22): Depend directly on Shikumi through a Seihou-owned adapter; exclude Handan. The user explicitly requested this boundary because Shikumi will gain more capabilities. Neither future Shikumi decision APIs nor a separate judgement-host release may block the initial generative implementation.

Decision (2026-10-22): Make judgements separate declarative artifacts, with references from modules and recipes, rather than generation strategies or ordinary shell commands. File generation and one-time application-command receipts cannot represent a check whose answer depends on each new staged snapshot.

Decision (2026-10-22): Separate validated findings, execution/coverage status, and deterministic project enforcement. A successful model call is not approval. Missing evidence, malformed output, a runtime failure, and a request for human review cannot become an enforced pass.

Decision (2026-10-22): Store resolved active definitions and ownership in the single portable manifest. A check in a fresh clone must not need an artifact cache, reapplication, or a silently newer rubric. Store run observations only in ignored local reports, never as durable proof that future commits are safe.

Decision (2026-10-22): Put local secret detection before any remote review or AI commit-message generation. Default reporting and tracing omit raw evidence and free-form model content that has not passed output sanitization. Remote review requires an explicit project data policy and a locally configured permitted route.

Decision (2026-10-22): Ship the security example with the Seihou distribution, using the same artifact decoder and judgement contract as custom artifacts. This makes adoption one command without requiring a separate registry installation. The bundled definition carries its real Seihou repository origin and release version; it is not a new weak artifact identity.


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

Seihou is a Haskell CLI with pure/domain logic in `seihou-core`, reusable CLI services in `seihou-cli/src`, and parsers/dispatchers in `seihou-cli/src-exe`. `seihou-core/src/Seihou/Core/Types.hs` defines generation `Step`, post-generation `Command`, runnable artifacts, application ownership, and the manifest domain. A `Step` requires a source, destination and file strategy. `Seihou.CLI.CommandExecution.planCommands` in `seihou-cli/src/Seihou/CLI/CommandExecution.hs` can skip ordinary commands after a successful receipt, which is inappropriate for repeated judgement gates.

`seihou-core/src/Seihou/Core/Module.hs` discovers modules, recipes, blueprints, and prompts. Its standard search roots are `.seihou/modules`, the user's configuration modules directory, and the install cache. `seihou-core/src/Seihou/Core/Registry.hs` defines registry entries, name collisions, repository discovery and validation. `seihou-core/src/Seihou/Core/Install.hs`, `seihou-cli/src/Seihou/CLI/InstallShared.hs`, and `seihou-cli/src-exe/Seihou/CLI/Install.hs` implement installation. `seihou-core/src/Seihou/Dhall/Eval.hs` decodes artifacts; do not add a parallel untyped configuration reader.

The `schema` directory is a Git submodule owned by `mori://shinzui/seihou-schema`, currently at commit `7d02695f5a716384ec2174a018c20ee680ab3d13`. Its project-relative `package.dhall`, `Module.dhall`, and `Recipe.dhall` are exposed here as `schema/package.dhall`, `schema/Module.dhall`, and `schema/Recipe.dhall`. A file-level Mori URI for the schema sources is pending; use the canonical project URI together with these relative paths in cross-repository work. Registry decoding is currently implemented in Seihou rather than a `schema/Registry.dhall` file. The immutable schema URL/hash for scaffolds lives in `seihou-cli/src/Seihou/CLI/SchemaVersion.hs`; `flake.nix`, `flake.lock`, and `nix/haskell-overlay.nix` also participate in schema consumption. Updating only the local submodule does not deliver a usable authoring import.

`seihou-core/src/Seihou/Manifest/Types.hs`, `seihou-core/src/Seihou/Manifest/JSON.hs`, and `seihou-core/src/Seihou/Manifest/Upgrade.hs` own manifest encoding, version checks and adjacent upgrades. The current schema is 10. Allocate the next version from the actual working tree during implementation; do not reserve a stale version number in this plan. `seihou-cli/src/Seihou/CLI/ManifestCapabilityUpgrade.hs` integrates deterministic capability upgrades. `seihou-cli/src/Seihou/CLI/CheckoutSync.hs` and `seihou-cli/src-exe/Seihou/CLI/Sync.hs` implement checkout restoration.

There are three production auto-commit callers: `seihou-cli/src-exe/Seihou/CLI/Run.hs`, `seihou-cli/src-exe/Seihou/CLI/Update.hs`, and `seihou-cli/src/Seihou/CLI/Migrate.hs`. Each uses helpers in `seihou-cli/src/Seihou/CLI/Git.hs` and `seihou-cli/src/Seihou/CLI/CommitMessage.hs`. Today they can send the staged diff to an AI before invoking `git commit`. `gitDiffCached` truncates that prompt to 4,000 characters and does not check the two diff command exit codes. Build a separate complete, checked evidence collector; that helper is not a security boundary. Gate all three callers before message generation, including fixed-message paths, and propagate a blocked/error result to the process exit status.

Shikumi is located through `mori registry show shinzui/shikumi --full`. Its typed runtime comes from `mori://shinzui/shikumi/packages/shikumi`, evaluation from `mori://shinzui/shikumi/packages/shikumi-eval`, and optional observation from `mori://shinzui/shikumi/packages/shikumi-trace`. The core API inspected for this plan is `Shikumi.Signature.mkSignature`, `Shikumi.Module.predict`, `Shikumi.Program.runProgram`, `Shikumi.Schema` derivation/validation, `Shikumi.Routing`, and `Shikumi.LLM`. `modelJudge` in the evaluation package grades a candidate against a reference; it is not the production security program. Build a dedicated typed program for the latter.

On 2026-10-22, Hackage's `https://hackage.haskell.org/package/shikumi.json` lists 0.4.1.1 as the newest version, and upstream tag `shikumi-0.4.1.1` resolves to `db4eb373803552762edc9e86a231dfb529f8105b`. This is discovery evidence, not a permanent dependency constraint. Recheck the registry and upstream tags before selecting bounds. `mori://shinzui/shikumi/masterplans/12-support-typesafe-jev-and-probability-backed-decision-outputs` describes future decision types and calibration; it is currently Not Started. The installed Mori CLI does not resolve that plan URI yet, so locate it within the registered Shikumi project, retaining the canonical URI. Do not code against those planned types as though they are released.

Provider transports below Shikumi come from `mori://shinzui/baikai`; discover and inspect any imported package with Mori before choosing an API. Existing Seihou interactive agent configuration does not automatically define an unattended judgement provider. Reuse configuration/provenance conventions where appropriate, but give judgements their own validated settings. A CLI provider that sends content to a hosted service is remote even though its executable runs locally. Shikumi trace attributes can include full request and response JSON, so its default capture stack must not be enabled unchanged for security evidence.

Use Gitleaks as the initial deterministic scanner adapter, with its invocation and output schema verified against the selected release. Mori currently has no registered Gitleaks source. Its [official source and CLI documentation](https://github.com/gitleaks/gitleaks) describe `stdin`, directory and Git scanning and redacted reports. The adapter must scan the exact captured material and translate machine findings into Seihou findings; scanning a mutable worktree while judging a different index is unacceptable. Avoid building a second regex secret scanner inside Seihou.

Relevant local decisions constrain this work. [ADR 0001](../adr/0001-manifest-is-a-checked-in-machine-independent-artifact.md) excludes paths, credentials and machine state from the manifest. [ADR 0002](../adr/0002-artifact-identity-is-origin-url-plus-name.md) makes origin plus name the artifact identity; definition hashes identify reviewed bytes, not a replacement artifact identity. [ADR 0003](../adr/0003-a-stale-or-substituted-artifact-is-a-hard-error.md) and [ADR 0006](../adr/0006-the-install-cache-will-not-silently-substitute-an-artifact.md) require explicit handling of stale/substituted artifacts. [ADR 0004](../adr/0004-the-manifest-is-the-only-record-of-applied-state.md) disallows a separate applied-state lockfile. [ADR 0014](../adr/0014-every-semantic-manifest-change-advances-the-schema-version.md) requires a schema advance, adjacent upgrade, capability mapping and version-aware validation for this new state. [ADR 0015](../adr/0015-diagnostics-name-things-as-users-do-and-never-fall-back-to-show.md) requires exhaustive, actionable human diagnostics. [ADR 0018](../adr/0018-checkout-outputs-are-observable-portable-declarations.md) supplies the intent/observation/sync pattern, but does not currently authorize a new hook resource kind. Do not encode hooks as fake directory symlinks or infer setup from shell receipts. No existing ADR defines judgement semantics; add that durable decision during implementation. This repository's ADR directory is not a profiled OKF bundle.

Follow the library-first and record conventions in `docs/dev/contributing.md`: runtime/evidence/rendering services belong in the internal library; only optparse/file-embedding/dispatch code belongs in the executable directory. New data-record fields are strict, unprefixed, and accessed with overloaded labels. Never traverse `/nix/store` or the filesystem root to locate dependency code.


## Plan of Work

### M1 — Prove the ordinary consumer path early


Start with a representative existing Git consumer, recording its current Seihou version, manifest version, hooks, hook manager, staged changes and developer commands. Seihou itself is an appropriate first consumer because `nix/pre-commit.nix` and `flake.module.nix` already install managed checks; do not replace those checks with a pristine fixture and claim coexistence. Work in a disposable clone/worktree and temporary user configuration, preserving the real pre-change committed state. Count build/install/provider preparation separately from ongoing developer commands.

Implement only enough of the proposed domain, bundled definition, `run`, `check`, direct Shikumi adapter and hook wiring to exercise the vertical path. Use an actual supported provider for a small synthetic live review, and an offline typed stub to force pass/block/error branches deterministically. Test injection belongs in the test harness, never in a public flag that can cause an enforced production gate to report a fake pass. First-use provider/data-policy selection happens inside adoption's existing preview/configuration flow. Noninteractive adoption must require explicit settings rather than silently consent to transmission.

Acceptance is that `seihou run security-review` previews and activates the judgement, a benign staged change can commit, and a seeded fake credential prevents an ordinary `git commit` with a redacted reason and no provider request. Also submit a contextual synthetic confidential example through the typed review and observe the expected finding. Record every prerequisite, prompt and manual edit. Promote this path into the final implementation; if hook integration or Shikumi decoding needs a different approach, correct it here before building the full artifact surface. A source-only demonstration verifies this milestone, not release delivery.

### M2 — Make custom judgements normal artifacts


Add `Judgement.dhall`, `JudgementRef.dhall` and supporting closed types to `mori://shinzui/seihou-schema` (artifact-level file URIs pending); export them through its project-relative `package.dhall`. Extend its module and recipe schemas with default-empty judgement references. Preserve decoding of supported older artifacts. References resolve through the ordinary composition/search machinery and may use the existing conditional-expression mechanism; do not require users to list transitive references.

In Seihou add `seihou-core/src/Seihou/Core/Judgement.hs` for domain/validation and `seihou-core/src/Seihou/Core/JudgementArtifact.hs` for resolution and definition construction. Extend `seihou-core/src/Seihou/Dhall/Eval.hs`, `seihou-core/src/Seihou/Core/Module.hs`, `seihou-core/src/Seihou/Core/Registry.hs`, installation, list/browse rendering, registry synchronization and full validation. Discover `judgement.dhall` as an artifact; reject ambiguous co-located artifact kinds when adding the new kind rather than silently hiding it. Extend registry name-collision checks and default missing legacy judgement lists to empty. Provide a judgement kind filter in list/browse and completion of judgement names.

Expose `seihou judgement new NAME`, `seihou judgement validate NAME`, `seihou judgement eval NAME`, and `seihou judgement configure NAME`. New creates `.seihou/modules/NAME/judgement.dhall` and a synthetic `examples.json` by default, with `--path` for registry authors. It refuses to overwrite an existing directory. The scaffold carries a useful rubric and annotated examples rather than a vacuous instruction to "review carefully". Editing one instructions field and adding examples must be sufficient for the normal custom judgement. Configuration explains provider/model/data-policy selection and project enforcement; it does not store credentials in an artifact or manifest.

Define `judgement configure NAME` to work before or after application. Before application it prepares settings consumed by the normal preview; after application it previews and atomically records an explicit policy change. Support `--provider PROVIDER`, `--model MODEL`, `--data-policy local-only|approved-remote`, and `--enforcement enforced|advisory` for noninteractive configuration, with the interactive wizard selecting the same values. Provider/model availability is checked against the actual runtime catalogue; no model identifier is guessed. Provider credentials remain in the selected transport's normal environment/credential store. Local runtime choices may narrow the committed permitted destinations but cannot broaden them. Unconfigured noninteractive adoption fails with the exact configure command and performs no partial activation.

Publish the compatible schema commit, advance the submodule and immutable scaffold URL/hash together, and update the flake schema input. The schema producer must be published before a consumer scaffold relies on it. This plan's creation does not authorize performing that release now; implementation includes the producer work and records any remaining publication boundary.

Acceptance is an author creating `customer-data-review`, editing its instructions through the normal file, validating it, running its examples, and applying it using `seihou run customer-data-review`. A second author can install the same definition from a registry using ordinary `seihou install SOURCE`, find it through list/browse, and apply it. Invalid categories, bad paths, ambiguous identity and malformed examples fail with named diagnostics before any provider call. Older modules/recipes and registries still load.

### M3 — Record portable intent and restore checkout integration


Extend `seihou-core/src/Seihou/Core/Types.hs`, manifest encoders/decoders, upgrade registry and capability mapping. Persist active, resolved definitions with their origin/name/version, definition digest, instruction text, allowed finding categories, evidence/trigger declarations, coverage limits and application owners. Persist enforcement/data policy separately from model findings. Store no raw review evidence, provider credentials, absolute paths, timestamps of "last safe" commits, or artifact-cache paths. Snapshot definitions so checks work offline with respect to artifact discovery, even though the chosen model may require a network connection. Evaluation-only fixture files need not be stored in the manifest.

Declare an explicit portable representation for project-selected judgement policy and owners. `run` resolves references once and records the resolved program definition; `update` previews definition/policy changes and replaces selected owners while preserving unselected ones. Agreeing references co-own a declaration; conflicting definitions or policies for the same identity refuse before publication. Disabling a condition or dropping a reference retires only that owner's claim. `remove` removes the last owner's active declaration and Seihou-owned hook contribution safely. Judgements have no ordinary command success receipt. A user editing an artifact must apply/update it to change project intent, and the command must say when the active snapshot differs from the authoring source.

Add one adjacent deterministic manifest upgrade that introduces empty judgement state without inventing active checks for old projects. The normal adoption command stages the lossless supported upgrade atomically. Inference-bearing legacy upgrades remain explicit, with the existing repair command. Check commands are read-only: if a manifest cannot be interpreted at the required capability, they name the necessary adoption/upgrade command and make no implicit state changes.

Implement hook setup as a dedicated typed judgement service, `seihou-cli/src/Seihou/CLI/Judgement/Hooks.hs`, invoked by application and sync. Its desired input is derived from active declarations, and its observations are local hook/config state. Keep this service distinct from ADR 0018's directory-link specification; amend that ADR only if sharing an actual common interface, and document the hook lifecycle explicitly. Resolve Git's hook directory correctly for linked worktrees and `core.hooksPath`. Compose with supported existing hook managers or a preserved existing hook. Preserve original literal symlinks without reading their external targets. Never overwrite user hooks, replace a shared hooks directory globally, or report setup success if the effective hook is unchanged. Unsupported integration must block adoption with a precise supported next action. Solve coexistence with Seihou's own pre-commit/Nix setup as part of the feature, including regeneration of manager-owned hooks.

`seihou sync` repairs missing owned setup from the manifest without resolving producer artifacts or changing tracked files/index/manifest. Repeating sync is a no-op when setup is correct. Status distinguishes declared, operational and misconfigured judgement setup without running the model. Existing hooks remain in effect, and removal only removes an unchanged Seihou-owned contribution. A hook overwritten by another manager is detected and repairable through the normal sync path, never assumed active from a prior receipt.

Acceptance includes an old supported manifest upgraded through ordinary adoption, unchanged pre-existing application state, agreeing owners, conflict rejection, last-owner retirement, and fresh-clone/linked-worktree sync with empty producer caches. A complete failed application/update must not publish a partial active policy. Keep transient check reports out of manifest diffs.

### M4 — Implement complete evidence and a bounded direct Shikumi review


Add reusable services under `seihou-cli/src/Seihou/CLI/Judgement/`: `Evidence.hs`, `Scanner.hs`, `Runtime.hs`, `Config.hs`, `Report.hs`, and `Evaluate.hs`. Domain decisions remain in `Seihou.Core.Judgement`; these services gather bytes, invoke tools/providers and render observations. The sole production language-model adapter is direct Shikumi. Add its dependencies to the internal CLI library, with `shikumi-eval` where evaluation needs it, and update `mori.dhall` and `nix/haskell-overlay.nix` as appropriate. Keep `seihou-core` independent of Shikumi and transport packages.

For staged checks capture the index tree and checked Git metadata using argument-vector subprocess calls and NUL-delimited paths. Derive snapshot identity from indexed paths, modes and blob IDs without refreshing or writing the index; do not use an index-writing tree/cache refresh as a supposedly read-only check. Read blob contents from the index, not the working tree. Disable external diff/text-conversion execution and avoid filesystem traversal through Git attributes. Handle partial staging, additions/deletions, renames, spaces, unusual filenames and linked worktrees. Reject unresolved index entries and failed Git reads. Use complete captured content for relevant changed files, with explicit before/after identity and line mappings; do not silently restrict review to a truncated patch. Sensitive deleted/context material must also be locally scanned before any of it is transmitted. Do not follow staged symlinks or descend into submodules. Unsupported binary/LFS/submodule/archive content is reported as uncovered unless the selected scope explicitly excludes it; it cannot disappear from coverage counts.

For `--range BASE..HEAD`, resolve immutable commits up front and inspect every introduced commit change in the range, not merely the final net diff. A secret introduced and later removed must still be found. Record the ordered commit/blob scope in the snapshot digest. Refuse invalid ranges, shallow-history gaps and missing objects with concrete remedies. Range checking does not use or alter the worktree/index. An empty staged set or empty range reports `NoChanges`, which is an explicit no-op rather than a claimed semantic review.

Run the scanner on the same captured material, supplying sanitized machine-readable reports. Pin/verify its output contract and pass an explicit trusted scanner configuration; repository-local ignore comments, allowlists, environment variables and ambient config must not silently weaken the required baseline. Gitleaks stdin or an isolated private snapshot are possible implementations; validate source-to-line mapping with the selected released CLI rather than assuming Git mode reads an immutable snapshot. Temporary files, if unavoidable, use private permissions and are removed on success, failure and cancellation. Raw scanner output and model errors never stream directly to the terminal or a trace. Missing scanner or scanner failure yields an error, not "no secrets found".

The bundled security definition requires a deterministic local secret scan before any remote request. A deterministic blocking finding stops further transmission. For remaining semantic review, project data policy must explicitly allow the selected route and evidence scope. A local executable is not proof of local processing. Never silently fall back to another provider, model, data policy, or unstructured output path. No reviewed content is treated as instructions to execute; the reviewer has no tools, shell, browsing, file-writing or agent loop. Malicious text in code/documents is evidence, not an authority over the rubric.

Build a `Program JudgementInput JudgementOutput` with a `Signature` populated from the resolved definition. Derive schema/decoding through the current Shikumi API and enforce domain validation in Seihou after decoding as well: declared category/severity, valid file/location references, bounded output sizes, and explicit uncertainty. The model may return findings and request human review; it does not choose project policy or manufacture the coverage count. Invalid or inconsistent outputs are errors. Reuse Shikumi's typed transient retry handling, with a bounded overall timeout, input/output limits and attempt count. Do not use repeated calls until the model changes its mind about a block. Report model, actual runtime version, attempts and available usage. Shikumi's optimistic cost admission is not a strict monetary cap; describe its actual limit honestly.

Chunk large but supported evidence deterministically within declared limits, retaining complete coverage accounting. Aggregate any block, uncertainty or runtime error so it prevents an enforced pass. If limits prevent complete review, name the uncovered files and the supported next step; never truncate and pass. Before each provider request apply the same local data checks to every outgoing field, including instructions and contextual snippets. Redact and bound all human/JSON report strings, including model-generated text that may echo source contents. Default local reports contain only sanitized findings, scope/digests and operational metadata. No raw Shikumi prompt/response capture, shared response cache or telemetry export is enabled for production security checks in this delivery. Offline synthetic fixtures provide replay/evaluation without retaining real secret-bearing inputs.

Acceptance is the same immutable evidence driving scanner and semantic review, a fake credential caught beyond character 4,000, a contextual confidential finding, no remote call after scanner block, a malformed reply producing an error, and no test-secret marker in stdout/stderr/local reports/telemetry. Capture coverage and exact version/route in the report. Verify that bypass-like strings in evidence and model output cannot change policy.

### M5 — Share gate enforcement across Git, Seihou and CI


Add parser options and dispatch in `seihou-cli/src-exe/Seihou/CLI/Commands.hs` and `seihou-cli/src-exe/Main.hs`, with thin new `Check.hs` and `Judgement.hs` dispatchers. `seihou check` defaults to all active checks on staged changes; an optional NAME selects one active judgement for diagnosis. `--staged` makes the default explicit. `--range BASE..HEAD` selects commit-range evidence and is mutually exclusive with staged selection. `--dry-run` reports the checks, permitted route, evidence scope and coverage plan without provider calls or setup changes; its output must never claim approval. `--json` emits the stable versioned report, while ordinary output identifies the judgement, reviewed scope, findings, and next action.

Use exit 0 for pass or explicit NoChanges, 10 for a policy block, 11 for needs-human-review, and 1 for runtime/configuration/incomplete-coverage errors. Parser errors retain normal CLI behavior. An advisory policy may permit exit 0 despite reported findings, but the report must retain their actual status and mark enforcement as advisory. For the security example, block, needs-review, error and incomplete coverage all prevent the action. All active enforced judgements must pass; a named diagnostic invocation is not a substitute for running them all. Existing `--force`, `--no-commands`, receipt reuse and agent settings do not bypass an enforced gate. No generic skip/force-pass flag is introduced.

Create `seihou-cli/src/Seihou/CLI/Judgement/CommitGate.hs` and route run/update/migrate through it after normal intentional staging, before AI message generation, and immediately before committing. Check all staged changes that Git will commit, including unrelated pre-staged files, without staging or unstaging them. If the gate blocks after files were generated, leave those user-visible changes and staging intact and return nonzero with "changes applied; commit blocked" and the exact check command. Do not pretend external file generation or shell effects were rolled back.

Bind approval to index tree, active-definition digests, policy and selected runtime configuration. Recheck those inputs after model/message generation and before commit; if they changed, rerun the required review or refuse with an actionable stale-result message. The ordinary pre-commit hook verifies the final staged tree too, including modifications made by earlier hooks. With a pre-commit framework, arrange the judgement after mutating formatters or force a new review if they change the index. A process-local approved snapshot may avoid duplicate model work only for the exact same gate invocation; no committed success receipt authorizes future content. Do not add an environment variable that can forge approval for a later hook process. Prefer a second review over an unverifiable cross-process bypass; measure this cost before considering a dedicated protected local handoff protocol.

Hook and Seihou paths cover ordinary cooperative development, not a hostile local process deliberately replacing Git hooks or racing the index. State that boundary without claiming an atomic Git security sandbox. CI is the independent enforcement path for hooks bypassed with Git's own facilities. For required CI policy, use the policy from a trusted base commit/branch, not unreviewed policy weakening in the change under test; support `--policy-ref REF` with immutable resolution, and use explicit initial-adoption review when no trusted policy exists. Read that policy from Git objects rather than checking it out. Local hooks may use active manifest policy, but staged policy removal/weakening must be visibly reported rather than mistaken for an ordinary clean result.

Acceptance covers all three auto-commit callers, fixed and generated commit messages, a staged-tree change during review, an existing hook changing staged content, and JSON/exit-code agreement. An instrumented provider/message generator must see zero secret-bearing requests when the scanner blocks. CI catches a secret introduced and removed within a range and does not accept a proposed weakening of its base policy.

### M6 — Make authoring, evaluation and source delivery reviewable


Ship the bundled `security-review` definition and synthetic evaluation corpus under `seihou-cli/data/judgements/security-review/`, with explicit Cabal source packaging and a small executable-only embedding adapter. Decode bundled and custom definitions through the same path. Use ordinary artifact search first and the bundled catalogue as a final fallback for a new application; always preview origin/version. Once applied, the manifest snapshot wins, so a same-named cache artifact or a newer binary cannot silently replace it. Custom judgement artifacts installed from registries get the same validation and reporting as bundled ones.

Add `JudgementSpec.hs`, `JudgementArtifactSpec.hs` and manifest upgrade tests under `seihou-core/test/Seihou/`; add evidence, runtime, output-sanitization, hook/commit and real-binary consumer tests under `seihou-cli/test/Seihou/CLI/`. Register them in each test `Main.hs` and Cabal manifest. Match existing test conventions rather than introducing a second runner. Use offline Shikumi stub/loopback facilities verified from upstream sources for protocol/ordering tests. A stub proves orchestration and rejection behavior, not the quality of a real model.

`seihou judgement eval NAME` loads the author's labelled `examples.json`, runs the same program under an explicitly configured permitted model, and reports missed unsafe cases, false blocks on benign cases, undecided cases, runtime failures, latency and available usage. Cases contain synthetic inputs, expected category/location/status, and stable IDs; validation catches malformed or secret-bearing example data before remote submission. Default invocation may incur model calls and must say so in help. Add an explicit offline mode that validates the corpus and tests deterministic policy/scanner behavior without claiming model accuracy. Offline mode cannot emit evidence usable as a production gate pass.

For release qualification use at least 20 benign and 20 unsafe labelled synthetic cases spanning fake credentials, contextual confidential data, synthetic fixtures, removed secrets, and instruction-injection attempts. Require zero missed critical seeded credential cases and no more than 10 percent false blocks on the benign release set for the route advertised in documentation. Record uncertainty/error counts separately; abstention is not a detected finding. If the semantic route cannot meet the declared qualification, keep that route unqualified and the delivery milestone open rather than lowering acceptance silently. This corpus bounds a release check, not a proof that unknown sensitive data cannot escape. Re-evaluate before changing the advertised model/rubric/runtime defaults.

Write `docs/cli/check.md`, `docs/cli/judgement.md`, `docs/user/judgements.md`, and embedded `seihou-cli/help/judgements.md`. Update README command/artifact tables, `seihou-cli/help/workflow.md`, `seihou-cli/data/module-reference.md`, architecture docs, CLI completions, changelog and affected generated OKF rendering in `seihou-okf-extension`. The documentation must distinguish local scanner findings from probabilistic semantic review, name scope/coverage limits, explain provider consent and credentials, and show a complete custom artifact. Update/create the durable judgement ADR when the interface is accepted; do not turn a proposed design into a falsely implemented ADR during plan creation.

Acceptance is that a new author follows only the public help to create, edit, validate, evaluate and activate a custom judgement, while a developer follows the one-command built-in adoption and ordinary commit workflow. Dry-run performs no model request or mutation. All required focused and repository gates pass on the final source candidate, and the plan records actual executable versions and observations rather than test counts alone.

### M7 — Deliver published artifacts and verify the installed workflow


Include Gitleaks in the supported Nix development/runtime packaging, with a verified version and subprocess contract. Make the packaged `seihou` find its scanner without requiring a global PATH edit. For Cabal/Hackage installations, clearly document the external scanner prerequisite and check it during adoption, with an exact supported installation action for the detected platform; do not silently download executables during a check. Packaging differences are visible acceptance limits, not hidden preparation. Verify the source archive includes judgement definitions, help and examples.

Use the existing release workflow when implementation reaches release, including its dependency-order and PVP checks. Recheck current released Shikumi/transport versions and upstream tags before choosing bounds; validate the minimum supported runtime and selected current release without declaring compatibility with future APIs. Update schema pins and build metadata together. Publish the schema first, then the Seihou packages, then verify the installed binary against those published artifacts. If publication/installation awaits authorization or credentials, stop at the concrete release-ready candidate and leave M7 open.

From the actual existing consumer, use the released installed `seihou run security-review`, exercise benign/blocked commits, and activate a user-authored judgement. Clone it into an empty artifact cache and create a linked worktree; use only documented `seihou sync` and normal provider credential setup before ordinary Git commands. Prove existing hook checks survive, scanner discovery works, tracked bytes/index/manifest do not change during sync/check, and no source-tree absolute paths are needed. Record installed `seihou --version`, schema revision, Shikumi/scanner versions, selected route, platforms tested, and any remaining release gap before marking the plan complete.


## Concrete Steps

All repository commands below run from the Seihou repository root unless a consumer directory is named. Public judgement commands are proposed interfaces implemented by this plan; they do not exist in Seihou 0.10.1.0. Do not report these transcripts as already observed.

Refresh upstream discovery before implementation and bounds selection:

```bash
mori registry list
mori registry search shikumi
mori registry show shinzui/shikumi --full
mori registry docs shinzui/shikumi
mori registry show shinzui/seihou-schema --full
mori registry docs shinzui/seihou-schema
mori registry search baikai
curl -fsSL https://hackage.haskell.org/package/shikumi.json
git ls-remote --tags https://github.com/shinzui/shikumi.git 'refs/tags/shikumi-*'
git status --short
git submodule status schema
```

Read the source at the paths returned by Mori and check the selected released APIs. Use the registered schema producer checkout for schema commits. Do not make an untracked schema-only edit and leave consumers pinned to old bytes.

Build in the repository's supported development environment. For repeatable noninteractive commands use:

```bash
nix develop -c cabal build all
nix develop -c cabal run seihou -- --version
nix develop -c cabal run seihou -- check --help
nix develop -c cabal run seihou -- judgement --help
```

For the early source-build consumer run, obtain the absolute executable path with `cabal list-bin seihou` in that same development environment and put its containing directory on the disposable consumer's PATH. Hooks must invoke that same binary, not an older global installation. Record this source-build setup explicitly. Release acceptance repeats the workflow with the installed executable and no source-build PATH override.

In the chosen disposable consumer, with an installed or explicitly recorded development executable and no prior judgement state:

```bash
seihou --version
seihou run security-review --dry-run
seihou run security-review
seihou check --dry-run
git add README.md
git commit -m 'docs: clarify the project description'
seihou check --staged --json
```

Adoption's normal preview/configuration flow selects the permitted provider/model/data policy once, displays hook changes and scanner availability, and uses the existing confirmation boundary. The benign commit succeeds. An empty staged set after the commit reports NoChanges, not "security verified". To test a secret, stage a synthetic scanner fixture from the checked-in test corpus in a disposable consumer; never use a real credential. Its ordinary commit is refused with a redacted finding, and the provider stub/request observer records zero transmissions.

Custom authoring, starting in that consumer, uses:

```bash
seihou judgement new customer-data-review
```

Edit `.seihou/modules/customer-data-review/judgement.dhall` and its `examples.json` through the normal authoring workflow. For example, the new schema must support this minimal definition, with evidence/category/limit defaults documented by the scaffold:

```dhall
let S = ../../../schema/package.dhall

in S.Judgement::{
     name = "customer-data-review",
     version = Some "1.0.0",
     instructions = ''
       Identify real customer information in fixtures, logs, and documentation.
       Synthetic examples are acceptable. Request human review when uncertain.
     ''
   }
```

The relative import above illustrates a repository fixture under `.seihou/modules/NAME` only. Real generated consumer scaffolds must contain the published immutable schema URL/hash from `Seihou.CLI.SchemaVersion`, not a source-checkout-relative import. No consumer is asked to repair that import manually.

Continue through the public commands:

```bash
seihou judgement validate customer-data-review
seihou judgement eval customer-data-review --offline
seihou judgement eval customer-data-review
seihou run customer-data-review
seihou list --judgements
seihou check customer-data-review
```

The live evaluation uses the explicitly selected permitted route; offline evaluation labels itself as corpus/scanner/policy validation. Apply previews the changed project intent and hook setup. The named check reads the active snapshot and reports which version/definition was reviewed. A typical human block has this meaning; wording may improve without changing the structured codes:

```text
security-review  BLOCKED
Scope: staged changes; complete for 3 changed text files
config/example.env:12  critical  embedded-credential
Remove the credential from the staged content, then run seihou check.
No remote review was requested. No commit was created.
```

For a clone or linked worktree, from its project root:

```bash
seihou sync --dry-run
seihou sync
seihou check --dry-run
```

For CI, with required base history fetched and a trusted base containing the adopted policy:

```bash
seihou check --range origin/main..HEAD --policy-ref origin/main --json
```

The command resolves both refs to immutable commits at startup and returns nonzero for blocked, uncertain or failed enforced checks. First adoption without a trusted base policy needs explicit CI configuration/review rather than pretending there is an existing baseline.

Run focused tests while implementing, then these final source checks after all code/schema/build changes:

```bash
nix develop -c cabal test all --test-show-details=direct
nix develop -c bash nix/check-record-conventions.sh
nix develop -c bash nix/check-cli-module-placement.sh
nix fmt
nix flake check
git diff --check
```

Record provenance revisions with the skill script when implementation begins, and use Conventional Commits with `ExecPlan: docs/plans/110-add-first-class-user-defined-judgements-backed-by-shikumi.md` and the frontmatter `Intention:` trailer. Continue on the current branch unless the user requests a branch. Use the release skill only when executing the delivery milestone, and record its actual published/installed validation separately from source checks.


## Validation and Acceptance

The early integration proof is M1's real pre-change consumer using the actual public commands and the actual managed-hook environment. The uncertain boundaries are schema-to-artifact decoding, typed Shikumi replies, scanner-to-snapshot mapping, and hook composition. Prove each through that path before broadening combinations. No private fixture script may perform schema adoption, hook repair, index changes, provider configuration or artifact resolution that the normal command omits.

Artifact acceptance includes project-local and installed custom definitions, direct application and transitive module/recipe references, registry collision/validation behavior, immutable schema imports and packaged scaffolds. Applying the same judgement twice is idempotent. An updated definition is an explicit reviewed project-intent change. Removing one owner preserves others, and fresh checks use the recorded definition with an empty artifact cache.

Evidence acceptance covers staged versus unstaged differences, partially staged files, renames, deletion context, filenames requiring NUL-delimited parsing, unresolved index entries, binary/LFS/submodule exclusions, input limits, a finding beyond 4,000 characters, and a secret added then removed inside a commit range. Invalid Git reads, uncovered required content and truncated model inputs are errors. Scope and coverage are independently measured by Seihou. Tests must verify actual input blob IDs as well as final verdicts.

Security acceptance uses synthetic credentials only. A scanner block prevents every remote request, including AI commit-message generation. An approved remote semantic review receives only the permitted scope after preflight; local-only policy never falls back to remote processing. Injected instructions in evidence, unknown categories, invented locations, oversized output, echoed secrets, malformed JSON, timeout, provider refusal and missing scanner each produce bounded redacted output and the intended nonzero outcome. Test sentinel strings must be absent from stdout, stderr, ignored reports and configured telemetry sinks. A clean scanner report is never described as a proof that semantic review is complete.

Gate acceptance observes ordinary Git and all three Seihou commit paths. The same inputs produce the same policy decision regardless of entry point. A fixed commit message does not skip checking. Generation success followed by a judgement block returns nonzero and explains the remaining applied changes. Earlier hooks and concurrent ordinary edits invalidate stale snapshots. Existing hooks still run in their supported order; no hook installation writes outside the selected checkout/configuration boundary without a visible preview. Dry-run and check do not mutate setup or tracked state. CI uses trusted policy independently of the proposed change and detects intermediate leaking commits.

Evaluation acceptance separates offline runtime/protocol correctness from real model quality. Run the labelled release corpus against the documented route, report missed unsafe examples and false blocks independently, and satisfy M6's stated thresholds. Record the rubric digest, corpus revision, provider/model identity, runtime/package versions, errors, uncertainty and latency. Synthetic examples and finite observed rates do not justify a universal "safe to commit" guarantee. Future optimizer/calibration features may be evaluated later; they must not silently rewrite an active rubric or policy.

Delivery acceptance requires the released schema import, source archive contents, scanner availability, packaged Seihou and installed executable to pass the exact consumer workflow. Record the commands and version outputs for macOS and Linux when supported; an untested platform remains a named delivery limitation. Neither source tests nor a successful release upload proves that the installed user's binary works. M7 remains open until installed verification succeeds, or the final handoff explicitly identifies its remaining release/installation gap.


## Idempotence and Recovery

Judgement creation refuses an existing destination. Validation, evaluation planning, check and dry-run do not alter project intent, staging or hook setup. Live evaluation may incur provider cost, which help reports; retry is bounded and never used to erase an adverse decision. Reapplying an identical definition/policy does not duplicate owners or hook entries.

Manifest capability upgrades are adjacent and deterministic where evidence permits. Apply/update publish definitions and ownership only after full validation, using existing atomic/transactional publication boundaries. A failed check cannot leave a pass receipt. Failed hook setup is reported as failed adoption/setup rather than as operational enforcement; restore only unchanged owned contributions and preserve user edits. A later `seihou sync` converges from recorded intent after an interrupted setup.

Checks are read-only with respect to the Git index and worktree. If Seihou staged generated files before a block, it leaves them staged and explains that the commit was not created. Do not clean up unrelated staged files, reset the index or roll back arbitrary shell effects. Re-running after the developer corrects content gathers a new snapshot. Old reports are diagnostic observations and never authorize a different tree.

Temporary scanner material is private and short-lived. Default reports are ignored, sanitized and replaceable; deleting them does not change policy or disable checks. No default raw replay archive or shared model cache exists for sensitive reviews. Hook retirement removes only a byte-identical owned contribution or restores the recorded original local integration when still unchanged; third-party changes cause a named conflict, not destructive cleanup.

Use disposable clones/worktrees and isolated configuration for acceptance. Keep any original index, hooks and user configuration untouched. Publishing producer artifacts and installing releases are distinct delivery actions; follow the repository's release procedure and retain existing release tags. Do not amend unrelated commits or create a feature branch as incidental planning work.


## Interfaces and Dependencies

There is no parent MasterPlan or prerequisite child plan. Schema publication and the released Shikumi APIs used by the implementation are integration dependencies owned by this delivery, not reasons to leave authoring or consumer adoption to another unspecified task. Re-read producer instructions before editing another repository and use canonical Mori references in durable cross-repository messages.

`seihou-core/src/Seihou/Core/Judgement.hs` owns the following conceptual interfaces. Final constructor details may follow repository conventions, but the distinctions are acceptance requirements:

```haskell
data JudgementStatus = Passed | Blocked | NeedsReview | Failed | NoChanges
data JudgementEnforcement = Enforced | Advisory
data EvidenceScope = StagedChanges | CommitRange CommitId CommitId

-- Records are strict and Generic in the implementation.
-- Definition: artifact identity/version, instruction, categories and limits.
-- Input: immutable evidence records with safe file IDs and coverage metadata.
-- Output: typed findings plus an explicit request for human review.
-- Policy: enforcement, severity/category rules and permitted data destinations.
-- Report: execution status, coverage, findings, policy decision and provenance.

validateJudgementOutput
  :: JudgementDefinition
  -> JudgementInput
  -> JudgementOutput
  -> Either JudgementError JudgementOutput

decideJudgement
  :: JudgementPolicy
  -> JudgementObservation
  -> JudgementDecision
```

The status report may use separate execution and decision fields instead of one sum if that makes advisory and coverage behavior clearer; do not collapse successful execution into approval. Findings include a declared category, severity, validated source location, sanitized explanation and supported remedy. Seihou supplies actual coverage and snapshot identity. Empty evidence is NoChanges, deliberate exclusions are counted, and absent/malformed evidence cannot become Passed.

`seihou-cli/src/Seihou/CLI/Judgement/Runtime.hs` owns the only conversion to Shikumi types:

```haskell
judgementProgram
  :: JudgementDefinition
  -> Program JudgementInput JudgementOutput
```

It constructs the typed signature from author instructions, runs bounded provider effects, validates results and converts typed Shikumi errors into Seihou errors. Its callable service accepts a Seihou execution configuration and returns a Seihou observation. Public schemas, manifest encodings, core policy tests and CLI callers must not import Shikumi `Params`, tracing records or future decision wrappers. Tests can supply a typed interpreter through this same service boundary.

Persisted definition digests cover the normalized definition bytes and schema/contract version. Snapshot identity covers ordered blob/commit identities and evidence scope. An approval identity additionally includes all active definition digests, effective policy, selected provider/model and relevant request configuration. These are invalidation keys, not artifact identities or permanent attestations. Do not serialize credentials or model-generated content into applied state.

The initial public contract supports custom instructions/categories and synthetic evaluation corpora over staged/commit-range evidence. It does not add arbitrary executable judgement plugins, user-defined output schemas, automatic fixes, an agent tool loop, background daemons, per-user approval bypasses, whole-history retroactive scanning, or automatic rubric optimization. Future probability-backed judgements can extend the runtime adapter and a versioned evidence/report contract after upstream release and evaluation; do not invent a probability threshold from an uncalibrated model confidence today.

Add Shikumi and any necessary Baikai transport/evaluation packages only after inspecting their current source through Mori and checking Hackage/upstream tags. Select and test concrete bounds at implementation time. Add no Handan dependency. The packaged Gitleaks adapter uses a verified released CLI contract and local configuration owned by the selected project policy. The existing Seihou executable remains the single user entry point; no separate judgement host installation is required.
