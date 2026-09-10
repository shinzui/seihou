# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [0.8.0.0] - 2026-09-10

### Changed

- **`seihou-okf-extension` now builds against `okf-core` 0.8.0.0** (EP-88), up from
  0.1.2.0. Both pins move together: the Cabal `build-depends` and the explicit Hackage
  pin in `nix/haskell-overlay.nix`. `validateBundle` gained a `VersionDeclaration` and a
  `BundleInventory` parameter; `ValidationError` grew from three constructors to fifteen
  and `BundleValidationError` from three to seven. `-Wall -Werror=incomplete-patterns` is
  now set on the extension's library, executable, and test stanzas, and the error
  renderers in `Seihou.OKF.Extension.Docs` are total with no catch-all, so the next
  okf-core release that adds a constructor fails the build rather than crashing the
  generator at run time.

### Added

- **`seihou agent migrate <blueprint> --mark-applied`** (EP-87): records an applied
  receipt for every pending edge in the resolved window without contacting a provider or
  reading or writing a single file in the working tree. A receipt asserts a claim about
  the project rather than reporting a completed agent session
  ([ADR 0011](docs/adr/0011-a-migration-receipt-asserts-a-claim-about-the-project.md)), so
  the hand-upgrade case that previously had no representation now has one. The window is
  resolved by the same code as a real run, so `--from`/`--to` narrow it identically and
  edges reached through `entails` are marked under their **owning** blueprint — which
  suppresses a later direct run of that blueprint too. An edge that already carries a
  receipt is skipped rather than restamped, making a repeated mark a no-op. The flag is
  refused alongside `--rerun` or `--debug`, both of which it contradicts, before anything
  is read or written. New pure helpers `formatMarkAppliedNotice` and
  `formatMarkAppliedSummary` in `Seihou.CLI.BlueprintMigration`.

#### The documentation bundle says what the registry declares
- **Every seihou artifact feature now reaches the generated page** (EP-88). A module
  document renders its variables in full (declared type, requiredness, default,
  validation rule, description), export aliases, interactive prompts with choices and
  conditions, generation steps with strategy/patch operation/condition, shell commands,
  the removal procedure, and each migration edge with its operations. Recipes and
  blueprints show the variable bindings they supply along each composition edge.
  Blueprints add their `allowedTools`, `launch` preferences, `versionProbe`, and
  migration edges with entailment; agent prompts add `commandVars` and `guidance`. A
  section the artifact declares nothing for is omitted rather than printed empty.
- **An entailed migration edge renders as a cross-link when its blueprint is in the same
  registry** and as plainly labelled text when it is not, because an entailed edge is
  owned by the blueprint that declares it and may live in another repository entirely
  ([ADR 0008](docs/adr/0008-an-entailed-migration-edge-is-owned-by-the-blueprint-that-declares-it.md)),
  while okf reports a link to a concept outside the bundle as dangling. Resolution is
  decided once, in `Seihou.OKF.Docs.Model.resolveEntryRefs`, beside module-reference
  resolution.
- **`Seihou.Core.Expr.renderExpr`**: the inverse of `parseExpr`, so a surface that wants
  to display a `when` condition can rebuild it — the original text is parsed out of
  Dhall and discarded. Parenthesizes only where the grammar's precedence would
  reassociate; round-tripped in tests over every constructor and two nesting levels.
- **The bundle is an OKF v0.2 bundle.** Its root `index.md` declares
  `okf_version: "0.2"`, every subdirectory gets a section index, and each concept carries
  a `generated` block naming `seihou-okf-extension/<version>` as its producer actor plus
  a `status: stable` lifecycle field, so `okf trust` reports a real tier per concept.
  Validation defaults to `StrictAuthoring`, which needs a non-empty description; the
  generator resolves one deterministically (registry entry, else the artifact's own, else
  a synthesized sentence) and uses it in both frontmatter and the body.
- **A registry overview concept** at `registry/<repoName>` describes the registry itself
  and links every artifact grouped by kind, so the bundle is a connected graph from one
  entry point and `okf graph` has a root.
- **A house profile the generator enforces on itself.** A Dhall descriptor declaring what
  a seihou documentation bundle's frontmatter must carry is embedded in the executable
  with `file-embed`, written to `<out>/profile.dhall`, and checked in-process *before*
  anything is written, so a violating bundle never reaches disk and a failing run does
  not clear the output directory. `ProfileViolation` is rendered locally, since
  okf-core reports it but leaves rendering to `okf-cli`.
- **New `docs` options**: `--generated-at DATE` records a generation time verbatim
  (omitted by default, so regeneration is byte-stable — nothing reads the clock),
  `--permissive` restores the old conformance profile, `--profile PATH` substitutes a
  house profile descriptor, and `--no-profile` skips the check.

## [0.7.0.0] - 2026-08-16

### Added

#### Migration fan-out across a library cohort
- **Entailed cohort edges** (EP-85, masterplan 10): a blueprint migration edge
  may declare that crossing it **entails** crossing an exact edge of another
  blueprint, through a new `EntailedEdge.dhall` and an `entails` field on
  `BlueprintMigration`. Entailed edges are expanded recursively by a pure core
  planner (`Seihou.Core.Migration`) into one ordered plan, run before the edge
  that declares them, and resolve their own owning blueprint's reference files,
  allowed tools, and variables. Their receipts are filed under the **owning**
  blueprint's identity, so a shared edge reached through an intermediary is
  crossed exactly once from either entry point. A cycle, an entailed blueprint
  that is not installed, and a named edge the entailed blueprint does not
  declare are all hard errors naming the blueprint whose author must fix them.
  New library module `Seihou.CLI.MigrationCohort`.
- **A not-applicable migration outcome** (EP-84, IR-1): a new
  `MigrationOutcome` type (`MigrationApplied` / `MigrationNotApplicable !Text`)
  records a deliberate no-op as a third outcome distinct from success and
  provider failure. An edge signals it through a per-edge file under `.seihou/`
  for interactive providers, or a trailing `SEIHOU: not-applicable <reason>`
  marker line for API providers; seihou's own framing prompt carries the
  convention so edge prompts need only state their precondition. The chain
  continues past an inapplicable edge, and only an *applied* receipt suppresses
  a later run — so an edge whose precondition is met later is planned again
  without `--rerun`. `seihou status` distinguishes the two outcomes.
- **An inferred migration version window** (EP-86): `seihou agent migrate`'s
  `--from` and `--to` are now optional. `--to` comes from a new optional
  `versionProbe` field on `Blueprint` — a shell command the blueprint's author
  declares, which reads the version the consuming project depends on — and
  `--from` from the highest version this project's receipts record as applied.
  An explicit flag always wins, and an inferred end is reported with its
  source. A probe that fails or prints an unparseable version is a warning that
  degrades to requiring `--to`, not a failure. The probe *is* executed under
  `--debug`, since the window decides which edges the preview shows.
  `validate-blueprint` gains a probe check.
- **Artifact origin on the agent-applied manifest records** (EP-81, IR-2):
  `AppliedBlueprint`, `AppliedBlueprintMigration`, and `AppliedRecipe` now carry
  the `ArtifactOrigin` the module records already had, and the blueprint
  migration completion key includes it — two blueprints published by different
  repositories under one name are not the same blueprint, so their
  identically-numbered edges are not the same edge. The three places that ask
  whether two recorded origins name the same artifact share one definition in
  the new `Seihou.Core.ArtifactIdentity` (`sameArtifactIdentity`), which also
  absorbed `ManifestGuard`'s private URL and path normalizers, since
  `seihou-core` cannot import `seihou-cli`. The manifest schema stays at **v6**:
  a missing `origin` decodes as `LocalOrigin` of the recorded name, so no
  conversion pass is needed and `seihou manifest upgrade` is unaffected.
- **An install-time different-source refusal** (EP-82, IR-4): `seihou install`
  reads the `.seihou-origin.json` it is about to delete and refuses when the
  incoming artifact comes from a different repository, or when the existing
  entry records no provenance at all. The refusal happens before anything is
  removed, so a refused install leaves the cache byte-identical and exits
  non-zero. A new **`--force`** replaces the entry anyway and prints what it
  overrode. `seihou upgrade`, `seihou update`, and `seihou migrate` reinstall
  from an artifact's own recorded origin and so pass `force = False`, reporting
  a mismatch rather than overriding it.
- **The artifact guard on the agent path** (EP-83, IR-3): `seihou agent run` and
  `seihou agent migrate` now consult `ManifestGuard` before applying a
  blueprint baseline and before planning migration edges, refusing a stale or
  substituted artifact on the same terms as `seihou run` with the same new
  **`--allow-downgrade`** override. `ManifestGuard` gains `checkAppliedBlueprint`
  and `checkRecordedBlueprint` over a shared `checkRecordedArtifact`, falling
  back to the newest migration receipt when no applied-blueprint entry names the
  blueprint; `enforceArtifactGuard` moved into `ManifestGuard`, generalised from
  `RunOpts` to a `Bool`. `agent run` checks the blueprint and every module its
  baseline would generate from, transitive dependencies included; `agent migrate`
  checks the blueprint only, and every blueprint in a resolved cohort chain.
  Both checks run before anything is written, so a refusal leaves the tree and
  manifest byte-identical. New library module `Seihou.CLI.AgentGuard`.
- **`seihou status` reports on the recorded blueprint**, alongside stale or
  substituted modules.

### Changed
- **Breaking:** `AppliedBlueprint`, `AppliedBlueprintMigration`, and
  `AppliedRecipe` each gain an `origin :: !ArtifactOrigin` field, and
  `AppliedBlueprintMigration` also gains `outcome :: !MigrationOutcome`.
  `Seihou.Manifest.Types.hasAppliedBlueprintMigration` takes an
  `ArtifactOrigin` as its new first argument and now counts only receipts whose
  outcome is `MigrationApplied`, matching the completion key
  `pendingBlueprintMigrations` applies. `Blueprint` gains
  `versionProbe :: !(Maybe Text)`. Both new blueprint fields decode through
  `withDefaults`, so artifacts authored against an older schema pin still load.
- **Breaking:** `BlueprintMigrationOpts`'s `from` and `to` become
  `Maybe Text`, and `InstallOpts`, `BlueprintRunOpts`, and
  `BlueprintMigrationOpts` gain `force` / `allowDowngrade` fields.
- **Breaking:** a `seihou install` run against a registry now exits non-zero
  when any entry failed, instead of reporting the failure count and exiting
  zero. Every entry is still attempted and every failure still reported.
- `seihou agent migrate` names the owning blueprint in every step label
  (`Running blueprint migration 1/2: my-library 1.0.0 -> 2.0.0`), and the
  `--debug` headers gained the same prefix; scripts matching the old shape need
  updating.
- Reinstalling an artifact from the URL it is already installed from no longer
  prints `warning: overwriting existing installation of '<name>'`. The one-line
  warning covered both the routine reinstall and the destructive substitution,
  and the routine case is overwhelmingly common; the calling command already
  reports what it installed, and the different-source refusal now surfaces the
  case worth stopping for.

### Fixed
- **A blueprint migration edge is no longer silently skipped because a
  same-named blueprint from another repository already ran it** (EP-81, IR-2).
  The completion key was the blueprint's bare name plus the edge's `from` and
  `to` versions, so an edge from a second repository's same-named blueprint was
  dropped from the plan with no message — the run looked like an ordinary
  "nothing pending" for work that never happened. Receipts now record and
  compare origin. **One-time effect:** receipts written before this release
  carry no provenance and are read as name-only, so the first `agent migrate`
  after upgrading may list an already-completed edge as pending; re-running is
  safe by design, or raise `--from` to skip it deliberately.

### Documentation
- Four **Improvement Requests** (IR-1 through IR-4) filed under
  `docs/improvement-requests/`, a bundle this repository did not have, and
  registered as an OKF bundle with the `okf-profiles` profile. All four are
  closed as completed by this release.
- **MasterPlan 10** (`docs/masterplans/10-blueprint-migration-fan-out-across-a-library-cohort.md`)
  and its six ExecPlans, EP-81 through EP-86.
- Four new **ADRs**: 0006 (the install cache will not silently substitute an
  artifact), 0007 (a deliberate no-op is a third outcome, not a success), 0008
  (an entailed migration edge is owned by the blueprint that declares it), and
  0009 (seihou reads no package-manager format — artifacts declare the command).
  ADR 0002 is amended for what makes two records of the same work the same
  record, and ADR 0003 for the guard's widened scope.
- `docs/user/CHANGELOG.md`'s `Unreleased` section had accumulated across
  0.4.0.0, 0.5.0.0, and 0.6.0.0 because no release commit ever cut it; its
  entries are now filed under the releases they shipped in.
- Author and consumer guidance for `entails`, the not-applicable outcome, the
  version probe, and the agent-path guard across `docs/user/blueprint-migrations.md`,
  `docs/user/blueprints.md`, `docs/cli/agent.md`, `docs/cli/install.md`,
  `docs/cli/migrate.md`, `docs/cli/status.md`, and `docs/cli/upgrade.md`.
- Corrected the `update-seihou-schema` skill, which told two plans to run
  `dhall hash < schema/package.dhall`; relative sibling imports resolve against
  the wrong directory on stdin, so the command always failed.

### Packaging
- `seihou-schema` re-pinned twice — to `014bb79` for `EntailedEdge.dhall` and
  the `entails` field, then to `49ff1e5` for `versionProbe` — with the
  submodule pointer, `schemaUrl` / `schemaHash`, and `flake.lock` all moved
  together each time.
- The `mori-schema` pin bumped to a revision carrying `OkfBundle`.
- No dependency bounds changed in this release.

## [0.6.0.0] - 2026-07-28

### Added

#### A manifest two developers can share
- **Portable artifact origins** (EP-76, masterplan 9): `.seihou/manifest.json`
  no longer records where a module lived on the machine that ran seihou. Every
  artifact reference — `AppliedModule`, `AppliedInstanceState`,
  `AppliedComposition` — now carries an **`ArtifactOrigin`**: the git URL the
  artifact was installed from plus its name (`RemoteOrigin`), a
  repository-relative path for artifacts committed under `.seihou/modules/`
  (`ProjectOrigin`), or `LocalOrigin` for an artifact whose provenance cannot
  be verified. Two developers on different machines who apply the same module
  now produce the same manifest bytes. The manifest schema is bumped to **v6**.
- **Local origin resolution in every consumer** (EP-77): `seihou migrate`,
  `seihou upgrade`'s post-upgrade advisory, `seihou run`'s post-run migration
  and pre-flight pending-migration check, and `seihou update`'s local staging
  and same-version comparison all locate an artifact through the new
  `Seihou.Core.ArtifactRef` resolver instead of a path another machine
  recorded. A `ProjectOrigin` resolves against the project root and
  deliberately does not fall through to the search paths, so a missing
  committed module cannot be silently replaced by an installed one of the same
  name. When an artifact is not installed locally the message names the module,
  its recorded git URL, every directory searched, and the exact
  `seihou install` command that fixes it.
- **Refusal to silently downgrade or substitute** (EP-78): before generating,
  `seihou run` and `seihou migrate` compare the version recorded in the
  manifest against the copy installed on this machine. A strictly older local
  version, an artifact installed from a different git URL, and an artifact that
  does not resolve at all each stop the command before a file is written,
  naming both versions or both URLs. A new **`--allow-downgrade`** flag
  proceeds anyway, still printing the blocks. `seihou status` lists every
  artifact that differs from what the project records and always exits zero.
  `seihou update` takes the flag but not the guard: it already refuses
  backwards moves through `validateVersionChange` and clones from the origin
  URL the manifest records, so it cannot substitute a same-named artifact.
- **`seihou manifest upgrade`** (EP-79): converts a manifest already committed
  in the old absolute-path format in place. Each recorded path is rewritten
  into its inferred portable origin — a project-local artifact is recognised by
  its `.seihou/modules` suffix, an upstream URL is recovered by finding the
  artifact in this machine's search paths and reading the `.seihou-origin.json`
  beside it — and the command prints a reviewable account of every conversion.
  The document is walked as a raw JSON value, so fields this build does not
  know about survive untouched, and the result is validated by decoding it
  before anything lands on disk. `--dry-run` reports and writes nothing.
  An upgrade this machine cannot satisfy (a missing or stale artifact, meaning
  the conversion recorded a guess) is refused unless `--force` is passed.
  Documented in `docs/cli/manifest.md`, `docs/user/manifest-upgrade.md`, and a
  new `docs/user/teams.md` guide to sharing a manifest.
- The repository's first five **ADRs** (`docs/adr/`), recording that the
  manifest is a checked-in machine-independent artifact, that artifact identity
  is the origin URL plus the artifact name, that a stale or substituted
  artifact is a hard error, that the manifest is the only record of applied
  state, and that legacy manifests convert through an explicit command.

#### Agent tracing and artifact-declared launch settings
- **Baikai call tracing** (EP-74): `runAgentCompletionWith` now dispatches
  through `Baikai.Trace.withTrace` instead of `Baikai.completeRequest`, so every
  model call emits a correlated `call_started` plus `call_finished`/`call_failed`
  to a `TraceSink`. A new `TraceSetting` vocabulary (`off`, `file`, `stdout`,
  `stderr`) resolves through the existing `Seihou.CLI.AgentConfig` chain as a
  fourth setting alongside provider, model, and effort — `--trace`,
  `SEIHOU_AGENT_TRACE`, `agent.<command>.trace`, `agent.trace` — defaulting to
  `off`. The free-form file path lives in its own `agent.tracePath` key (local
  then global, no flag, no per-command variant). A new library module
  `Seihou.CLI.AgentTrace` turns a resolved setting into a live sink, adding a
  stderr sink Baikai does not ship and creating the trace file's parent
  directory. `AgentCompletionRequest` gains a `completionTraceSink` field and
  loses its `Eq`/`Show` instances, since `TraceSink` wraps a streamly fold; the
  loaders' positional flag arguments are replaced by an `AgentSettingFlags`
  record. `streamly-core` becomes a direct dependency of `seihou-cli`.

  **Behavioral note for maintainers:** `withTrace` does not report provider
  failures the way `completeRequest` did. It reaches the provider through the
  streaming path, where `liftCompleteToStream` converts both in-band failures
  and thrown exceptions into a terminal error event, so failures arrive as an
  error-shaped `Response` rather than as an exception. `runAgentCompletionWith`
  therefore checks `Response.responseError` before its empty-text guard; without
  that branch every provider error would be reported as "Provider returned no
  assistant text." The retained `try` now guards sink-side failures only.

- **Artifact-declared agent launch settings** (EP-73): a new shared
  `Launch.dhall` record in `seihou-schema`, referenced by both `Blueprint.dhall`
  and `AgentPrompt.dhall` and exported as `S.Launch`, lets a blueprint or prompt
  declare the `provider`, `model`, and reasoning `effort` its prompt was written
  for. `Seihou.CLI.AgentConfig` gains a declaration tier between the
  `SEIHOU_AGENT_*` environment variables and the config files, plus a two-phase
  resolution API (`loadPendingAgentConfig` / `resolvePendingAgentConfig`) so the
  three commands that load an artifact — `agent run`, `agent migrate`,
  `prompt run` — can resolve after decoding it. `AgentPromptLaunch` is renamed
  to `AgentLaunch` and gains `effort`; `Blueprint` gains a `launch` field. Both
  are decoded through `withDefaults`, so artifacts authored against an older
  schema pin still load. `validate-blueprint` and `validate-prompt` gain a
  "Launch settings" check, and `agent config` renumbers its precedence legend to
  nine tiers.

### Fixed
- **Provider errors on the API providers are no longer swallowed** (EP-74).
  `runAgentCompletionWith` now checks `Response.responseError` before its
  empty-text guard, so a failed `anthropic`/`openai` call reports the provider's
  message instead of `"Provider returned no assistant text."` This predates the
  tracing work: the API providers' `complete` is
  `streamingComplete claudeMessagesStream`, and `claudeMessagesStream` wraps
  `prepareCall` in `trySync` and emits an immediate error event rather than
  throwing, so the `try` in `runAgentCompletionWith` never fired and the
  error-shaped `Response` fell through to the empty-text guard. Confirmed by
  running the pre-change binary against a missing `ANTHROPIC_API_KEY`.

### Changed
- **Breaking:** `.seihou/manifest.json` schema **v6** drops the `source` and
  `targetSource` keys in favour of `origin` and `targetOrigin`. Manifests
  written by earlier releases no longer decode; running any command against one
  reports the problem and names `seihou manifest upgrade`, which converts it in
  place. Correspondingly, `AppliedModule`, `AppliedInstanceState`, and
  `AppliedComposition` no longer carry a source path, and
  `buildAppliedComposition` takes `ArtifactOrigin` values instead of paths.
- **Breaking (library API):** every record across all three packages was
  converted to the generic-lens conventions (EP-75). Records now declare strict
  fields, derive `Generic` with an explicit deriving strategy, and **drop their
  per-type field-name prefixes** — so `seihou-core` field accessors are renamed
  wholesale (`configEnvironment` → `environment`, and so on). Fields are read
  and written through `#label` overloaded labels; `OverloadedRecordDot` is
  disabled in every stanza and record update syntax is gone. `Seihou.Prelude`
  re-exports all of `Control.Lens` (hiding four names that collide with
  `Data.Aeson`, `Options.Applicative`, and `Seihou.CLI.Commands`) plus
  `Generic`; it deliberately does **not** import `Data.Generics.Labels`, whose
  `IsLabel` instance is an orphan, so each module that uses `#label` imports it
  itself. `generic-lens` and `lens` are now direct dependencies of all three
  packages. The convention is documented in
  `docs/dev/architecture/overview.md` and `docs/dev/contributing.md`, and
  enforced mechanically by `nix/check-record-conventions.sh` in both
  `nix flake check` and the pre-commit hook.
- The read side of `.seihou-origin.json` moved from `seihou-cli` down into
  `seihou-core` so the origin classifier can use it without a dependency cycle.
  `Seihou.CLI.InstallShared` re-exports it, so its importers are unchanged.
- The end-to-end specs now locate the `seihou` executable through a shared
  `Seihou.CLI.SeihouBinary` helper that probes both layouts cabal produces and
  names every directory it searched on failure. Cabal 3.16 stopped creating the
  `build-tool-depends` symlink beside the test binary that the four duplicated
  copies of this helper assumed, so every end-to-end test failed with a bare
  `posix_spawnp: does not exist`.
- Bumped the `haskell-nix` registry input to carry **baikai 0.4.1.0** and
  **baikai-claude / baikai-openai 0.4.0.0**, and widened the cabal bounds to
  match. The previous `baikai-claude` 0.3.0.2 forwarded `Options.thinking` only
  to interactive launches, so reasoning effort was dropped on the batch
  `claude -p` path. Bounds-only change: no seihou module calls the two functions
  whose signatures changed (`claudeCliCommand`, `codexCliCommand`).
- Replaced the positional `Blueprint` pattern matches in `Seihou.CLI.Install`
  and `Seihou.CLI.Browse` with field accessors so future field additions do not
  break them.

## [0.5.0.0] - 2026-07-20

### Added

#### Seamless, conflict-aware project updates
- New **`seihou update [TARGET...]`** reconciles recorded module and recipe
  applications with newer sources while preserving user edits. With no target
  it updates every recorded top-level application in manifest order; targets
  select a deduplicated subset (refusing a partial selection that would strand a
  shared generated path). Supports `--var`, `--reconfigure`, `--dry-run`,
  `--json`, `--force`, `--run-all-commands` / `--no-commands`, and
  `--commit` / `--commit-message` (masterplan 8).
- **Three-way file reconciliation** (EP-65, EP-66): for every generated text
  file Seihou compares the baseline (previously generated bytes), the current
  on-disk file (including user edits), and the newly generated bytes.
  Non-overlapping changes are merged; true conflicts are surfaced or resolved
  with `--force`. Stored **generated baselines** back the merge, and orphan
  handling is edit-aware so hand-edited orphans are retained rather than
  silently removed.
- **Reproducible applied compositions** (EP-64): the manifest now records the
  exact accepted per-instance inputs of each application so updates can replay
  the same values. The manifest schema is bumped to **v5** while legacy
  manifests still decode.
- **Command fingerprinting** (EP-67): declared module commands are fingerprinted
  so unchanged commands are skipped during an update; `--run-all-commands`
  forces every declared command and `--no-commands` disables them all.
- **Staged update service** (EP-68): update planning and application run as a
  staged pipeline so a dry-run renders the complete plan without mutating the
  project, cache, baselines, or manifest. Applicable module migrations are
  always folded into the plan (there is no skip-migrations flag); declarative
  moves and deletes are staged for an honest dry-run, and migration shell steps
  are flagged as non-simulatable.
- New `docs/cli/update.md`, a `seihou help update` topic, and ecosystem
  guidance (EP-69); the `README`, `run`, and `upgrade` docs are reframed around
  the initial-apply vs. reconcile split.

#### Agent model, provider, and effort configuration
- **Per-command hierarchical provider/model configuration** (EP-70): each agent
  command can be configured independently via `agent.<command>.provider` and
  `agent.<command>.model`, falling back to the shared `agent.provider` /
  `agent.model` defaults, with a local project value always overriding a global
  one and a documented CLI → environment → config → default precedence chain.
  Agent commands gained a `--model` flag.
- **Deterministic default models** (EP-70): when no model is configured Seihou
  pins a per-provider default (`claude-cli` → `claude-opus-4-8`,
  `codex-cli` → `gpt-5.6-terra`) and always passes it explicitly, so a CLI
  session never inherits whatever model another `claude` / `codex` session left
  active.
- **`seihou agent config`** (EP-70): a read-only command that prints the
  resolved provider, model, and reasoning effort for every agent command
  (`assist`, `bootstrap`, `setup`, `run`, `migrate`, `prompt run`), each
  labelled with the source that supplied the value.
- **`seihou agent models`** (EP-63): lists the 31 Anthropic and OpenAI models in
  the shipped Baikai catalog, with optional API/CLI provider filtering and
  guidance that provider-native aliases and custom model IDs remain accepted.
- **Per-command reasoning effort** (EP-72): a new `--effort LEVEL`
  (`minimal` / `low` / `medium` / `high` / `xhigh` / `max`) flag plus
  `agent.<command>.effort` and shared `agent.effort` config keys, surfaced in
  `seihou agent config`.

#### Blueprint upgrade migrations
- **Ordered, agent-driven blueprint upgrade migrations** (EP-71): the Dhall
  schema and Haskell domain now carry migration edges; shared version-window
  planning rejects malformed chains; validation checks migration metadata;
  legacy manifests still decode while manifest v5 records exact-edge receipts;
  `status` reports pending work; and **`seihou agent migrate`** shares blueprint
  preparation, resumes after each durable receipt, supports `--rerun`, and
  offers a side-effect-free `--debug` prompt preview.

### Changed

- Updated **`baikai` to 0.4.0.0** (reasoning-effort support), with
  `baikai-claude` / `baikai-openai` at `^>=0.3.0.1` and `baikai-kit` at
  `^>=0.1.0.2` in the Cabal bounds. The Nix build now sources the whole baikai
  family from the shared haskell-nix registry (baikai 0.4.0.0,
  baikai-claude/openai 0.3.0.2, baikai-kit 0.1.0.3) instead of local Hackage
  overrides.
- `seihou run` is now framed as initial application or deliberate reconfigure,
  and `seihou upgrade` as refreshing the shared installed-cache sources —
  reconciling an existing project is `seihou update`'s job.

### Packaging

- All three packages share version `0.5.0.0`, and intra-repo components pin
  `seihou-core ^>=0.5.0.0`.

## [0.4.0.0] - 2026-07-15

### Added

#### First-class prompts
- New first-class **`Prompt`** runnable type: a `prompt.dhall` schema,
  `AgentPrompt` domain types, Dhall decoding, validation, and
  prompt-aware runnable discovery (with blueprint-over-prompt
  precedence) (EP-50, EP-51).
- **Command-derived variables**: `commandVars` resolve shell-command
  output into variables (`FromCommand` provenance), with precedence,
  type coercion, validation, trimming, size limits, conditions, and
  command-failure diagnostics (EP-52).
- **Prompt CLI workflows**: `seihou new-prompt` scaffolds a prompt,
  `seihou prompt run` renders and launches a provider prompt, and
  `seihou validate-prompt` lints prompt definitions (EP-53).
- **Registry integration**: prompts are discovered, installed, browsed,
  and listed alongside modules, recipes, and blueprints, and are covered
  by `seihou registry sync-versions` / `validate` (EP-55).
- **Prompt guidance blocks**: `prompt.dhall` can declare conditional
  Markdown guidance rendered with project context around
  `seihou prompt run` provider prompts. `--debug` prints the complete
  provider prompt, and `validate-prompt` checks guidance titles, bodies,
  and condition references. The agent `bootstrap`/`assist` context prompts
  now teach the full `prompt.dhall` schema (EP-61).
- New `docs/user/prompts.md`, per-command CLI docs, and a
  `seihou help prompts` topic (EP-54).

#### OKF documentation extension
- New **`seihou extension`** host command and an external
  **`seihou-okf-extension`** package that defines the extension contract
  and moves OKF usage out of the CLI core (EP-60).
- OKF **DocModel loader** for Seihou registries: loads modules, recipes,
  blueprints, and prompts with resolved module references (EP-57).
- OKF **rendering** of a `DocModel` to a documentation bundle, with
  concept IDs, frontmatter, module cross-links, and validation (EP-58).
- **`seihou docs`** (via the OKF extension): turn a registry into an OKF
  documentation bundle (EP-59).
- The default Nix package now bundles the OKF extension alongside the CLI
  so `seihou docs` / `seihou extension run okf` work from a single
  install.

#### Validation and variables
- `seihou validate-module --lint` now flags two authoring mistakes: a
  `when` clause or `{{#if}}` conditional that references an undeclared
  variable, and an `Eq <var> <literal>` comparison whose literal type
  cannot match the variable's declared type (EP-49).
- **Defaulted variables coerce to their declared type**: a `bool`
  variable with `default = Some "true"` now resolves to `VBool True`
  (not `VText "true"`), so `Eq` comparisons match from the default
  source. A malformed default (e.g. `Some "treu"` on a bool) now fails
  module load with a clear error (EP-49).

### Changed

- The CLI kit is now built on the shared **`baikai-kit`** package;
  `Seihou.CLI.KitPaths` was removed and `Seihou.CLI.Kit` slimmed
  accordingly.
- Agent dependencies (`baikai`, `baikai-claude`, `baikai-openai`,
  `baikai-kit`) and `okf-core` now resolve from published **Hackage**
  releases; adapted to baikai interactive API changes (`modelId`,
  `AssistantPayload.timestamp :: Maybe UTCTime`).

### Fixed

- The blueprint runner now mounts an existing blueprint `files/` directory for
  interactive Claude Code and Codex sessions and points the agent at its
  absolute path; providers without local directory access receive explicit
  fallback guidance.
- Blueprint `allowedTools` entries are now unioned with the base runner tool
  set, de-duplicated, and passed to the interactive launcher so Claude Code can
  pre-approve the effective set.

### Packaging

- New third package **`seihou-okf-extension`** (BSD-3-Clause, with
  `LICENSE` and Hackage metadata).
- All three packages share version `0.4.0.0`, and intra-repo components
  pin `seihou-core ^>=0.4.0.0`.

## [0.3.0.0] - 2026-06-12

### Added

#### Blueprints (agent-driven scaffolding)
- New first-class **`Blueprint`** runnable type: a `blueprint.dhall`
  schema, Dhall decoder, validator, and run-refusal semantics for
  agent-driven scaffolding that complements modules and recipes
  (EP-29).
- Blueprint authoring and inspection commands: `seihou new-blueprint`
  scaffolds a blueprint and `seihou validate-blueprint` lints it
  (EP-30).
- `seihou agent run BLUEPRINT` parses and executes a blueprint through
  the configured agent provider (EP-31).
- **Applied-blueprint provenance**: a new `AppliedBlueprint` record is
  written to the manifest after an agent run (manifest schema bumped to
  **v3**), and `seihou status` surfaces which blueprint was applied
  (EP-32).
- **Registry support for blueprints**: the `Registry` type and the
  `SingleBlueprint` repository shape gained blueprints; `seihou install`
  and `seihou browse` handle blueprints alongside modules and recipes,
  and `seihou registry sync-versions` / `validate` understand blueprint
  entries (EP-33).
- New `seihou help blueprints` topic and user-guide coverage of
  agent-driven blueprints (EP-34).

#### Agent provider integration (Baikai)
- Agent commands are now routed through a configurable **provider**
  backed by [Baikai](https://hackage.haskell.org/package/baikai): a
  completion facade, configurable provider selection, and interactive
  CLI provider launches. New `baikai`, `baikai-claude`, and
  `baikai-openai` dependencies.
- `seihou kit` installs Codex-compatible kit content, with reduced CLI
  approval prompts for the Codex provider.
- New `seihou help agent` topic and a Baikai-backed agent-configuration
  guide.

#### CLI flags and UX
- `seihou list` gained `--modules`, `--recipes`, and `--blueprints`
  filters to narrow output by kind, and its summary count is now
  kind-aware.

### Changed

- **Migration planner rewritten** as a gap-tolerant window walker:
  migration chains with version gaps are walked more robustly, and the
  walker contract is documented in `docs/cli/migrate.md` and
  `docs/user/migrations.md` (EP-35).
- Agent dependencies now resolve from the published **Hackage** `baikai`
  packages, and the git `streamly` pin tracks the official
  `composewell/streamly` repository.

### Removed

- **Breaking:** removed the `seihou migrate --bump-only` and
  `seihou run --bump-blocked` recovery flags. The rewritten gap-tolerant
  migration planner advances recorded versions through benign
  empty-migration gaps and exhausted partial-chain tails automatically,
  so the manual escape hatches are no longer needed (EP-35).

### Fixed

- `seihou migrate` no longer crashes with
  `getDirectoryContents:openDirStream: does not exist` when a migration
  chain mixes a `MoveFile` op with a `RunCommand` step (e.g.
  `rm -rf <src-dir>`) that removes the source's parent directory before
  `cleanupEmptyDirs` runs. The IO interpreter of
  `Filesystem.RemoveDirectoryIfEmpty` now treats a missing path as a
  no-op, matching the pure interpreter's semantics. On the affected
  chain the manifest had already been rolled back even though the disk
  moves had completed, so a second `seihou migrate` invocation
  succeeded — the fix removes the need for that retry dance.
- Manifests are now written **atomically** (write-to-temp-then-rename),
  avoiding corruption if the process is interrupted mid-write.
- Recipe expansion is now **total** — malformed or cyclic recipes
  surface as structured errors instead of throwing.
- Generation, migration, and removal paths are validated and constrained
  to stay within the project tree, rejecting paths that escape it.
- The `seihou` executable now packages its **embedded source assets**
  (`data/` prompts and `help/` topics) via `extra-source-files`, so the
  Hackage tarball and installed binary carry them.

### Packaging

- Added Hackage metadata (`license`, `license-file`, `author`,
  `maintainer`, `homepage`, `bug-reports`, `category`, `description`)
  and a `LICENSE` (BSD-3-Clause) file to both packages.
- `seihou-cli` now pins `seihou-core ^>=0.3.0.0`.
- Both packages share version `0.3.0.0`.

## [0.2.0.0] - 2026-04-29

### Added

#### Module migrations
- **Module migrations**: a new `migrations` field on `module.dhall` lets
  authors declare file-system operations (`MoveFile`, `MoveDir`,
  `DeleteFile`, `DeleteDir`, `RunCommand`) that move a project's
  working tree from one module version to another. New `seihou migrate
  <module>` command applies the chain to the current project, rewrites
  the manifest's `files` map to reflect new paths, and bumps the
  applied module's recorded version. Supports `--dry-run`, `--force`
  (mirroring `seihou remove` conflict semantics), `--to VERSION`, and
  `--json`. New `seihou help migrations` topic embeds the full
  reference in the binary; new `docs/user/migrations.md` and
  `docs/cli/migrate.md` cover authoring and CLI usage. Schema-upgrade
  detects and adds the `migrations` field on legacy modules.
- `seihou migrate` is self-contained: it fetches the latest module
  before planning so users no longer need a manual `seihou upgrade`
  first. `--no-fetch` opts out for offline/pinned workflows.
- `seihou migrate --commit` / `--commit-message`: stage and commit the
  migration result with an autogenerated or user-supplied message.
- `seihou upgrade --with-migrations` runs migrations against the
  current project for each successfully-upgraded module. Without the
  flag, `seihou upgrade` prints a one-line advisory pointing at
  `seihou migrate <module>` when migrations are pending.
- `seihou run` is migration-aware: refuses to apply when modules have
  partial chains or are blocked, and prints actionable remediation hints.
- `seihou status` renders pending-migration, partial-chain, and blocked
  rows; reports `Pending migrations: N migration(s) pending: a → b`
  under any applied module whose installed copy has advanced past the
  manifest's recorded version.
- **Recovery escape hatches** for migration edge cases:
  - `seihou migrate --bump-only`: refresh the manifest's recorded
    version without applying any operations, for benign empty-migrations
    version gaps.
  - `seihou run --bump-blocked`: bump-through blocked modules in a
    single command when the chain is provably benign.
  - Benign empty-migrations upgrades (versions that declare no
    file-system ops) now proceed silently in `seihou run` and render
    without blocked-language in `seihou status`.
  - Bump-through for exhausted partial-chain tails: when the reachable
    prefix terminates with no further declared edges, `seihou migrate`
    advances the recorded version through the unreachable tail rather
    than leaving the manifest stuck mid-chain.
  - `seihou migrate` falls back to local migrations when an upstream
    fetch drops applicable edges, preventing partial-chain skips.

#### Recipes (module composition presets)
- New `Recipe` type and `recipe.dhall` schema — named, ordered
  compositions of modules with optional pre-bound parameters.
- Recipe discovery, expansion, and validation across local and registry
  sources, with provenance recorded in the manifest and surfaced in
  `seihou status`.
- Recipes integrated into `seihou run`, `seihou list`, `seihou install`,
  and `seihou browse`; new `seihou new-recipe` scaffolds a recipe.
- FZF selector covers recipes alongside modules.

#### Registry tooling
- `seihou registry` authoring command group with `sync-versions` and
  `validate` subcommands. `sync-versions` reads each entry's
  `module.dhall` / `recipe.dhall`, compares against the registry, and
  rewrites `seihou-registry.dhall` with current versions; `--dry-run`
  and `--check` (CI-friendly, exits 1 on drift) supported.
- `seihou registry validate`: structural + strict `version` equality
  check across registry entries, exiting non-zero on any failure, so it
  works as a single CI pre-merge gate. See `docs/cli/registry.md`.
- `seihou browse` and `seihou install` emit per-entry warnings to
  stderr when a multi-module registry has versions out of sync with the
  underlying modules — without blocking the operation.
- Documented `version` field on registry entries in
  `docs/user/registries-and-multi-module-repos.md` and the bootstrap
  prompt.

#### Templating
- Inline `{{#if cond}} … {{/if}}` conditional blocks in the Template
  strategy with unbounded nesting, routed through the standard
  `renderTemplateText` renderer.
- Standalone-block whitespace trim: lines that contain only
  `{{#if}}`/`{{/if}}` tags collapse cleanly without leaving stray
  blank lines.
- Decommissioned the legacy `Seihou.Engine.TemplatePrototype` and
  promoted the production renderer to handle all template paths.
- New consolidated templating reference: `docs/user/templating.md` and
  in-binary `seihou help templating`. Getting-started doc gains a
  `{{#if}}` teaser and a populated run-flags table.
- Written evaluation of Dhall-as-templating with three prototypes
  (split-flake reproduction, dhall-text single-source flake, typed
  dhall-text renderer, inline-conditional template) and a comparison
  doc with recommendation.

#### Composition
- **Parameterized-dep multi-instantiation**: parents can instantiate
  the same dependency multiple times with different parameter sets.
  Threaded `ModuleInstance` through the loader, resolver, and planner;
  introduced `ParentVars` and a manifest v2 schema; `Execute` now
  attributes each `FileRecord` via an ownership map and `seihou status`
  shows parent bindings. Diamond fixtures cover the new behaviour.

#### CLI flags and UX
- `seihou run --confirm-defaults`: walk through each variable resolved
  from a default or from a parent module's export and accept or
  override it interactively. Overridden values are tagged as prompted
  input so they flow into the "save prompted values?" offer.
- `seihou status --check-updates`: surface available registry updates
  alongside the existing status output.
- Schema upgrade detects and injects the new `migrations` field on
  legacy modules.

#### Infrastructure
- Library-first CLI module placement: `seihou-cli` now exposes a
  private `seihou-cli-internal` library (`src/`) with the `seihou`
  executable reduced to `src-exe/` (`Main.hs`, command dispatchers, and
  modules trapped by `optparse-applicative`, `file-embed`, `githash`,
  or `Paths_seihou_cli`). New `nix/check-cli-module-placement.sh`
  enforces the convention via `nix flake check` and the pre-commit
  hook.
- Master-plan seihou module shipped (`agents/skills/master-plan`),
  with skill and spec.

### Fixed

- `seihou migrate` no longer skips partial chains when an upstream
  fetch drops applicable edges (EP-27).
- `seihou outdated` version detection corrected via the new
  library-exposed `VersionCompare` module.
- Use-after-free in `checkSource`: temp-dir lifetime extended past
  consumer reads.
- Nix CLI test sandbox now provides `git` so `seihou-cli` tests run
  under `nix flake check`.

### Changed

- Pinned `seihou-schema` URL bumped to the published Migration commit;
  `mori-schema` upgraded to `9b1d6ee`.
- Both packages share version `0.2.0.0`.

## [0.1.0.0] - 2026-04-15

Initial public release of seihou — a composable, type-safe project scaffolding
system driven by Dhall modules, with stateful manifests and incremental
regeneration.

### Added

#### Core pipeline
- **Dhall module loading**: module discovery, validation, decoders, and
  expression evaluation with graceful schema evolution.
- **Variable resolution**: six-layer resolution (defaults, module, repo config,
  user config, context, CLI) with context-aware selection (work/personal),
  composition-aware `--explain`, and variable exports for cross-module scoping.
- **Generation strategies**: `Copy`, `Template`, `DhallText`, and `Structured`
  strategies, plus text patching with `Section` and `PatchOp` (including
  `AppendLineIfAbsent` for idempotent line-level patching).
- **Composition and layering**: module composition with declared dependencies,
  topological ordering, parameterized dependencies for parent-to-child variable
  passing, and intelligent composition merge for text and structured files.
- **Plan compilation and execution**: filesystem execution with shell command
  hooks, `{{var}}` interpolation in commands, and structured error propagation.
- **Manifest tracking**: stateful `.seihou/manifest.json` for incrementality,
  three-state diff engine (manifest / plan / disk), and scoped orphan detection
  that preserves files and variables across independent module runs.
- **Interactive conflict resolution**: per-file conflict prompts during
  `seihou run` with TTY input handling.
- **First-class module removal**: reversible `seihou remove` backed by declared
  removal steps and a step-based removal engine.

#### Module system
- **Module versions**: required version field at validation time, version
  comparison via a dedicated `Version` type, `seihou outdated`, and
  `seihou upgrade` with support for upgrading unversioned modules.
- **Schema evolution**: `seihou-schema` git submodule, `SchemaVersion` module,
  schema-import-based modules, `seihou schema-upgrade` command, and
  `MissingSchemaImport` detection and injection.

#### CLI commands
- `seihou init` — initialize a new project
- `seihou run` — apply modules, with `--commit` for AI-generated commit
  messages, colored dry-run preview, and interactive conflict resolution
- `seihou vars` — show resolved variables with composition-aware `--explain`
- `seihou install` — install modules, with URL history and FZF selection
- `seihou browse` — inspect remote registries
- `seihou list` — list installed modules with `--repo` and `--tag` filtering
- `seihou status` — show file state classification and module versions
- `seihou diff` — compare manifest vs. disk
- `seihou validate-module` — structured diagnostics and lint checks
- `seihou new-module` — scaffold a new module
- `seihou config` — `set`, `get`, `list` (with `--effective`), `unset`
- `seihou context` — manage active context
- `seihou remove` — reversible module removal
- `seihou upgrade` / `seihou outdated` — module version management
- `seihou schema-upgrade` — upgrade modules to the latest schema
- `seihou agent bootstrap` / `agent assist` / `agent setup` — agent workflows
- `seihou help topics` — embedded help topics

#### Registries
- Multi-module registry support with discovery and validation.
- Registry metadata types, Dhall decoders, and registry origin in `seihou list`.

#### Configuration and prompts
- Config file layering and dedicated `ConfigWriter` effect with IO and pure
  interpreters.
- Interactive prompts with default values, optional variable handling, and
  `save-prompted` to persist answers to local config.

#### DX
- Shell completion for Bash, Zsh, and Fish.
- FZF integration for module, registry, and context selection.
- `Logger` effect with `--verbose` flag wired through all CLI handlers.
- Version with git SHA in CLI output.
- Help topics subcommand and grouped `--help` output.

### Infrastructure
- Multi-package cabal workspace: `seihou-core` (library) and `seihou-cli`
  (executable and test suite).
- Nix flakes build with `haskell-nix` for GHC 9.12 tool patches, and schema
  submodule support.
- Integration and golden tests for scaffold, composition merge, text patching,
  structured merge, removal engine, and CLI output formats.

[Unreleased]: https://github.com/shinzui/seihou/compare/v0.8.0.0...HEAD
[0.8.0.0]: https://github.com/shinzui/seihou/compare/v0.7.0.0...v0.8.0.0
[0.7.0.0]: https://github.com/shinzui/seihou/compare/v0.6.0.0...v0.7.0.0
[0.6.0.0]: https://github.com/shinzui/seihou/compare/v0.5.0.0...v0.6.0.0
[0.5.0.0]: https://github.com/shinzui/seihou/compare/v0.4.0.0...v0.5.0.0
[0.4.0.0]: https://github.com/shinzui/seihou/compare/v0.3.0.0...v0.4.0.0
[0.3.0.0]: https://github.com/shinzui/seihou/compare/v0.2.0.0...v0.3.0.0
[0.2.0.0]: https://github.com/shinzui/seihou/compare/v0.1.0.0...v0.2.0.0
[0.1.0.0]: https://github.com/shinzui/seihou/releases/tag/v0.1.0.0
