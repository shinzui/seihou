# Documentation Changelog

## Last Reviewed Commit

```
68da440 docs: add blueprints help topic
```

---

## Changelog

### 2026-06-05 (User docs audit: blueprints, agents, and registry items)

**Reviewed commits:** `a87088f` through `68da440`

**Documentation changes:**

- Added `docs/user/blueprints.md` — user-facing guide for authoring,
  validating, running, and publishing agent-driven blueprints.
- Added `docs/user/agent-assistance.md` — provider selection, debug mode,
  agent subcommands, and Seihou Kit provider-native installs for Claude Code
  and Codex.
- Updated `docs/user/getting-started.md` — current `new-module` scaffold
  output, blueprints as the third runnable kind, `seihou agent` workflows, and
  new help topics.
- Updated `docs/user/registries-and-multi-module-repos.md` — registry
  examples and discovery/install/validation rules now cover modules, recipes,
  and blueprints.
- Updated `docs/user/module-authoring.md` — discovery and variable precedence
  sections now match current behavior.
- Updated `docs/cli/{browse,help,install,list,registry}.md` — command references
  no longer describe registry commands as module/recipe-only.
- Updated embedded help topics for git repositories and module common commands
  to mention recipes and blueprints where relevant.

**Features documented:**

- `seihou new-blueprint`, `seihou validate-blueprint`, and
  `seihou agent run` as the blueprint authoring and execution path.
- Configurable agent providers (`claude-cli`, `codex-cli`, `anthropic`,
  `openai`) and provider/model precedence.
- `seihou kit` installing provider-native Claude Code and Codex skills and
  subagents at user or project scope.
- Registry `blueprints` entries and single-blueprint repository discovery.

**No documentation needed:**

- Nix flake/overlay updates and Baikai package source changes are build-system
  maintenance with no user-facing CLI behavior change.
- Agent API compatibility fixes preserve the already documented provider
  behavior.

### 2026-05-24 (Baikai interactive integration follow-up)

**Developer-facing maintenance:**

- Seihou now uses Baikai's interactive launcher modules for
  `claude-cli` and `codex-cli` instead of constructing provider-specific
  command arguments locally.
- `seihou kit` path helpers now delegate provider-native skill, custom
  agent, and Codex TOML rules to `Baikai.AgentAssets` while keeping
  Seihou's user/project scope policy unchanged.
- No user-facing command behavior changed in this follow-up; existing
  build and CLI tests pass against the updated Baikai packages.

### 2026-05-24 (Interactive CLI agent provider fix)

**Behavior change (user-facing):**

- `seihou agent assist --provider codex-cli` and the matching
  `bootstrap`, `setup`, and `run` forms now accept provider/model flags
  after the subcommand as well as on the parent `seihou agent` command.
- `claude-cli` and `codex-cli` now start interactive local `claude` and
  `codex` sessions. API providers still use Baikai batch completions.
- The `seihou` executable is linked with GHC's threaded runtime so
  Baikai/Cradle-backed code paths do not fail with the runtime-system
  diagnostic.

### 2026-05-23 (Configurable Baikai-backed agent assistance)

**Reviewed commits:** ExecPlans 36-39
(`docs/plans/36-add-baikai-dependency-and-agent-completion-facade.md`,
`docs/plans/37-add-configurable-agent-provider-and-model-selection.md`,
`docs/plans/38-migrate-agent-commands-to-baikai-launcher.md`,
`docs/plans/39-document-and-validate-configurable-baikai-agents.md`)
under the Baikai-backed configurable agent assistance master plan
(`docs/masterplans/4-baikai-backed-configurable-agent-assistance.md`).

**Behavior change (user-facing):**

- `seihou agent assist`, `seihou agent bootstrap`, `seihou agent
  setup`, and `seihou agent run` now route their rendered prompts
  through Baikai instead of directly launching a raw Claude process.
- The parent `seihou agent` command accepts `--provider PROVIDER`
  and `--model MODEL`. Supported providers are `claude-cli`,
  `codex-cli`, `anthropic`, and `openai`.
- Agent provider defaults can be configured with `agent.provider`
  and `agent.model` in Seihou config, or with
  `SEIHOU_AGENT_PROVIDER` and `SEIHOU_AGENT_MODEL` in the
  environment. The 2026-05-24 corrective update also allows
  subcommand-local provider/model flags, which override parent CLI
  flags.
- The original 2026-05-23 implementation routed `claude-cli` and
  `codex-cli` through Baikai batch CLI providers. The 2026-05-24
  corrective update superseded that behavior: those providers now
  start interactive local `claude` and `codex` sessions.
- `--debug` still prints the resolved prompt and exits without
  contacting any provider, so it remains safe for prompt inspection
  and smoke checks.

**Why:**

The previous direct Claude launch path made `seihou agent` behavior
hard-coded to one local tool. Baikai gives Seihou one provider facade
for Claude CLI, Codex CLI, Anthropic API, and OpenAI-compatible API
providers, while keeping provider/model selection configurable from
the same places users already expect Seihou defaults to live.

### 2026-05-08 (Migration planner: gap-tolerant version-window walker)

**Reviewed commits:** ExecPlan 35
(`docs/plans/35-rewrite-migration-planner-as-gap-tolerant-walker.md`).

**Behaviour change (user-facing):**

- The migration planner now applies every declared migration whose
  version range falls inside `[installed, target]`, in ascending
  `from` order, skipping versions that have no declared migration.
  The manifest always advances to the supplied target after
  `seihou migrate` completes — even when no declared migration covers
  the entire span.
- The previous "partial chain", "blocked migration", "benign upgrade",
  and "bump-through" outcomes are unified under a single
  `MigrateApplied` result. The corresponding advisory messages
  (`Blocked: …`, `Note: no migration declared from …`, `bumped
  through`) have been removed from CLI output.
- `seihou migrate` no longer ever requires a follow-up command. A
  single invocation either lands the manifest at the target or
  surfaces a real error (file conflict, downgrade refused,
  unparseable version).

**Removed:**

- The `--bump-only` flag (`seihou migrate`) and the `--bump-blocked`
  flag (`seihou run`) are removed. The default `seihou migrate` and
  `seihou run --with-migrations` already advance the manifest even
  when no migration ops apply, making both flags redundant. Scripts
  that relied on them should drop the flag and call the default
  invocation.
- The `MigrationGap` and `MigrationOvershoot` planner errors are
  removed. Partial coverage is no longer an error; overshoots are
  silently skipped.
- The JSON output's `unreachable`, `bumpedThrough`, and
  `manifestVersion` keys are removed; consumers should read `to` (the
  manifest's new version) and inspect `steps` directly.
- The `MigrateAppliedPartial`, `MigrateAppliedBumpedThrough`,
  `MigrateBlocked`, `MigrateBenignUpgrade`,
  `MigrateDryRunOKPartial`, `MigrateDryRunOKBumpedThrough`,
  `MigrateConflictingFlags` `MigrateResult` variants are removed.
- The `Seihou.Core.Migration.MigrationChain` type is removed; the
  flattened `MigrationPlan` record (with `planModule`, `planFrom`,
  `planTo`, `planSteps`) replaces it.

**Why:**

`seihou migrate` had been patched five times (EP-5, EP-6, EP-7,
EP-27, EP-28) without ever matching the user's mental model: "look
at the current installed version, run each migration between it and
the latest, skip versions that have no migration." This rewrite
deletes the strict-chain machinery and replaces it with that single
rule.

### 2026-05-08 (Blueprints: agent-driven scaffolding for open-ended project shapes)

**Reviewed commits:** ExecPlans 29–34
(`docs/plans/29-blueprint-domain-model-and-discovery.md`,
`docs/plans/30-blueprint-authoring-and-inspection.md`,
`docs/plans/31-blueprint-agent-runner.md`,
`docs/plans/32-blueprint-manifest-and-status.md`,
`docs/plans/33-blueprint-registry-and-install.md`,
`docs/plans/34-blueprint-docs-and-ecosystem.md`) — the
agent-driven-blueprints initiative.

**Behaviour change (user-facing):**

- A new third runnable kind, the **blueprint**
  (`blueprint.dhall`), joins modules and recipes. Blueprints
  bundle a prompt template, an optional baseline of modules to
  apply before the agent takes over, and an optional `files/`
  directory of reference snippets.
- Authoring: `seihou new-blueprint NAME [--path DIR]` scaffolds
  a blueprint; `seihou validate-blueprint [PATH]` validates one.
- Running: `seihou agent run BLUEPRINT [PROMPT]` resolves the
  blueprint's variables, optionally applies the baseline
  (`--no-baseline` skips), renders the prompt, and launches an
  interactive Claude Code session with the blueprint's `files/`
  mounted as a read-only reference.
- `seihou run BLUEPRINT` refuses with an actionable message
  directing the user to `seihou agent run`. Blueprints are not
  directly runnable by design.
- `seihou status` records `Blueprint: <name> v<version> (applied
  <date>)` when a blueprint has been applied, with baseline and
  prompt sub-lines.
- `seihou list`, `seihou vars`, `seihou install`, `seihou
  browse`, `seihou registry sync-versions`, and `seihou registry
  validate` all understand the new kind. A `seihou-registry.dhall`
  can list blueprints alongside modules and recipes.

**Why:**

Modules and recipes are deterministic by design — every input
captured by a `VarDecl`, every output a function of resolved
variables. That shape works for project shapes that vary along
small, well-understood axes; it fits poorly for shapes whose
variation is inherently open-ended ("scaffold a microservice
for $domain", "wire in observability that matches our team's
pattern"). Blueprints are the escape hatch: an author writes a
prompt, the AI agent drives the open-ended customisation under
the user's supervision, and the deterministic surface stays
uncluttered.

**Docs updated:**

- `docs/dev/design/proposed/blueprints.md` — new design doc
  describing the runnable type, validation, runner workflow,
  manifest behaviour, and registry integration.
- `docs/dev/architecture/overview.md` — Module Loading paragraph
  mentions blueprint discovery; Project Structure tree adds the
  new files; Trapped-modules inventory adds the new exec-target
  modules.
- `seihou-cli/data/{assist,bootstrap,setup}-prompt.md` — the
  three AI-assisted commands now know blueprints exist and route
  users to `seihou agent run`.
- `README.md` — feature description names all three runnable kinds.

### 2026-05-08 (Manifest tracking and `seihou status` for applied blueprints)

**Reviewed commits:** ExecPlan 32
(`docs/plans/32-blueprint-manifest-and-status.md`) under the
agent-driven-blueprints master plan
(`docs/masterplans/3-agent-driven-blueprints.md`).

**Behavior change (user-facing):**

- A successful `seihou agent run BLUEPRINT` now records an
  applied-blueprint provenance entry into `.seihou/manifest.json`. The
  entry captures the blueprint name, version, applied timestamp, the
  baseline modules that were applied (or `--no-baseline` if the user
  skipped baseline application), and the user's positional `PROMPT`
  argument when supplied. A non-zero agent exit (Ctrl-C, `claude`
  failure) leaves the manifest untouched, so the recorded blueprint
  always reflects the most recent *successful* application.
- `seihou status` now surfaces the recorded blueprint above the
  applied-modules block:

      Blueprint: payments-service v0.3.1 (applied 2026-05-12 14:23 UTC)
        Baseline: nix-flake, haskell-base
        Prompt: "set this up for a payments microservice"

  The Baseline line reads `(none -- --no-baseline)` when the user
  passed `--no-baseline`, and the Prompt line is omitted when no
  positional prompt was supplied.

**Schema change:**

- The internal manifest schema (`.seihou/manifest.json`) bumps from
  version 2 to version 3 to add the optional `blueprint` field. The
  decoder reads pre-bump (v2) manifests with no blueprint entry —
  upgrading seihou does not require any user action. Downgrading to a
  pre-EP-32 build of seihou after the schema bump is rejected with the
  documented "manifest was created by a newer version of seihou"
  error, mirroring the v1→v2 precedent.

### 2026-05-08 (Agent runner for blueprints)

**Reviewed commits:** ExecPlan 31
(`docs/plans/31-blueprint-agent-runner.md`) under the
agent-driven-blueprints master plan
(`docs/masterplans/3-agent-driven-blueprints.md`).

**Behavior change (user-facing):**

- New command `seihou agent run BLUEPRINT [PROMPT]` runs an
  agent-driven blueprint. The runner discovers the blueprint by name
  (same search paths as `seihou run`), resolves the blueprint's
  declared variables through the standard precedence chain (CLI >
  env > local > namespace > context > global > defaults > interactive
  prompts), optionally applies the blueprint's `baseModules` as a
  starting scaffold, renders the prompt template with the resolved
  variables substituted in, and launches Claude Code with the
  blueprint's `files/` directory mounted via `--add-dir`.
- Pass `--var KEY=VALUE` to override individual variables;
  `--no-baseline` to skip baseline application; `--namespace`,
  `--context`, `--force`, and `--verbose` for the same overrides
  `seihou run` accepts.
- Pass `--debug` on the parent (`seihou agent --debug run …`) to
  print the resolved system prompt to stdout instead of launching
  Claude. The debug path still applies the baseline (so files are
  written to disk) but does not start an interactive session.
- Blueprints without `claude` on PATH receive the same install hint
  the existing `seihou agent assist`/`bootstrap`/`setup` commands
  produce.

Note: the manifest entry recording that a blueprint was applied
(`AppliedBlueprint`) is intentionally deferred to a follow-up plan —
the base modules' manifest entries are written on each invocation,
but the blueprint's own provenance is not yet persisted.

### 2026-05-07 (Authoring and inspection commands for blueprints)

**Reviewed commits:** ExecPlan 30
(`docs/plans/30-blueprint-authoring-and-inspection.md`) under the
agent-driven-blueprints master plan
(`docs/masterplans/3-agent-driven-blueprints.md`).

**Behavior change (user-facing):**

- New command `seihou new-blueprint NAME [--path DIR]` scaffolds a
  fresh blueprint directory containing `blueprint.dhall`,
  `prompt.md`, and an empty `files/` subdirectory. The Dhall record
  imports the prompt body via `./prompt.md as Text` so authors can
  edit Markdown directly without escaping through Dhall string
  literals. The output directory defaults to `./<name>/`.
- New command `seihou validate-blueprint [PATH] [--lint]` reports
  whether a blueprint is well-formed. Verifies that the Dhall
  evaluates, the name matches `[a-z][a-z0-9-]*`, the prompt body is
  non-empty, declared variable names are unique, every interactive
  prompt references a declared variable, every entry in `files`
  resolves under `files/`, and `baseModules` are not themselves
  blueprints. Exits 4 when `blueprint.dhall` is missing; exits 1 on
  any rule violation; exits 0 when clean. `--lint` is currently a
  no-op reserved for future advisory checks.
- `seihou list` now displays each discovered blueprint with a
  `[blueprint]` suffix in the source-tag column, alongside modules
  (no suffix) and recipes (`[recipe]`).
- `seihou vars BLUEPRINT` lists a blueprint's declared variables in
  declaration mode (heading: `Variables for <name> (blueprint):`).
  `seihou vars BLUEPRINT --explain` is refused with a four-line
  message naming `seihou agent run` (which lands in EP-31): resolving
  a blueprint's variables is the agent runner's job, not vars'.
- `seihou vars` was rewritten to dispatch through `discoverRunnable`,
  so it now handles recipes in declaration mode too — previously a
  recipe name fell through to a "module not found" error.

Documentation: `docs/cli/new-blueprint.md`,
`docs/cli/validate-blueprint.md`.

### 2026-04-28 (One-command upgrade through partial-chain tails with no further migrations)

**Reviewed commits:** ExecPlan 28
(`docs/plans/28-bump-through-benign-tail.md`) — collapsing the
legacy "seihou migrate; seihou migrate --bump-only" two-command
workflow into one for the common partial-chain shape.

**Behavior change (user-facing):**

- `seihou migrate <module>` (no `--to`) now applies the chain
  prefix *and* bumps the manifest all the way to the remote
  version when the partial chain's unreachable tail has no further
  declared migrations (the migrations list is exhausted past the
  chain's stopping point). The user gets one line of output
  `✓ Migrated <name> <fromV> → <target>.` followed by a
  per-segment trailer naming the prefix the chain ran and the
  bumped-through region.
- The "blocked tail" case (a future edge declared past the chain's
  stopping point but the chain doesn't span the gap) keeps its
  EP-5/EP-6/EP-7 semantics: `migrate` applies the prefix, leaves
  the manifest at the chain's `chainTo`, and prints the legacy
  `Note: no migration declared from <stuckAt>; remote is at
  <target>` advisory. The user is genuinely waiting for a
  continuation migration there, so auto-bumping would silently
  paper over a real gap.
- `--to TARGET` keeps the strict-target contract: an exhausted-tail
  partial chain still fails with `MigrationGap` if the user named a
  specific version they didn't get a migration coverage for. The
  bump-through behaviour is only the default (no `--to`).
- `seihou status`, `seihou run --with-migrations`, and `seihou
  upgrade --with-migrations` all describe the new exhausted-tail
  shape as "would bump through" so the user reads their pending row
  and knows that one command will land them at the target. Blocked
  tails keep the legacy "Note: no migration declared from X; remote
  is at Y" wording.

**Why:**

A user reported (in the same session that produced EP-27) that even
after EP-27 fixed the underlying "skipped" bug, the typical upgrade
workflow still required two commands: `seihou migrate <module>`
(applies the chain prefix, manifest at chainTo, blocked advisory)
followed by `seihou migrate <module> --bump-only` (bumps the
manifest the rest of the way). For the common case of "module
bumped its version field but didn't ship a migration for the tail,"
that's two commands for one mental operation. EP-28 collapses them
into one for the unambiguous case (no further migrations declared
past the chain's stopping point), preserving the two-step
recovery for cases where the author owes a continuation migration
in the unreachable region.

**Docs updated:**

- `docs/cli/migrate.md` — splits the Partial chains subsection into
  "exhausted tail" and "blocked tail" sub-cases with example
  transcripts, lifts the count of distinguished outcomes from four
  to five.
- `docs/user/CHANGELOG.md` — this entry.

### 2026-04-28 (Fetch path no longer skips locally-declared partial chains)

**Reviewed commits:** ExecPlan 27
(`docs/plans/27-fix-migrate-skips-partial-chain.md`) — fix for a
report that `seihou migrate <module>` silently skipped a declared
migration in a specific divergence scenario.

**Behavior change (user-facing):**

- The default `seihou migrate <module>` (fetch enabled) now applies
  the locally-declared migration chain when the cloned remote no
  longer ships an applicable edge. Previously, the fetch path planned
  exclusively against the cloned remote's `migrations` list; if the
  remote had dropped the edge that the locally installed
  `module.dhall` still declared, the planner returned a `MigrateBenignUpgrade`
  (or `MigrateBlocked`) outcome and the manifest stayed at the user's
  current version. Now, when the clone-based plan would refuse to
  apply, Seihou retries against the locally installed copy's
  migrations list. If that yields a chain (full or partial), it is
  applied in place of the no-op outcome.
- The clone still drives the post-apply install refresh, so the
  templates and version field on disk continue to reflect the
  freshest remote content (EP-15's "freshest content" intent).
- The fallback never fires when both the clone and the locally
  installed copy declare empty migrations: in that case the
  `MigrateBenignUpgrade` outcome is correct and is preserved.

**Why:**

A user reported that `seihou migrate demo` silently skipped a
`{ from = "0.1", to = "0.2", ops = ... }` edge declared in their
locally installed `module.dhall` even though their manifest was at
`0.1`. The basic `--no-fetch` path applied the chain correctly, but
the default fetch path classified the result as a benign version
bump and refused. Investigation localized the bug to
`runMigrateWithFetch` in `seihou-cli/src/Seihou/CLI/Migrate.hs`,
which planned exclusively against the cloned remote's migrations
list — losing visibility of the user's locally-declared edge when
the remote and local diverged. The fix preserves EP-15's "freshest
content" intent for the common case while honouring the user's
mental model ("I have the edge declared on disk; it should run") in
the divergence case.

**Docs updated:**

- `docs/cli/migrate.md` — adds a "Local fallback when remote drops a
  migration" note under the fetch behaviour subsection.
- `docs/user/CHANGELOG.md` — this entry.

### 2026-04-27 (Auto-commit flag for `seihou migrate`)

**Reviewed commits:** ExecPlan 26
(`docs/plans/26-migrate-commit-flag.md`) — porting the existing
`seihou run --commit` / `--commit-message` flag pair to
`seihou migrate`.

**Behavior change (user-facing):**

- `seihou migrate <module> --commit` stages the files migrated this
  run plus `.seihou/manifest.json` and creates a single git commit.
  The commit message is generated by invoking `claude -p` with the
  module name and the staged diff; if `claude` is not on `PATH` or
  returns an empty response, Seihou falls back to the deterministic
  template `seihou: apply module <name>`.
- `seihou migrate <module> --commit-message MSG` implies `--commit`
  and uses `MSG` verbatim, bypassing the AI call.
- The flags are silent no-ops on outcomes that did not mutate the
  working tree (dry-run, `MigrateNoOp`, `MigrateBlocked`,
  `MigrateBenignUpgrade`) and outside a git work tree.
- `RunCommand` migration ops do not contribute paths to the staged
  set: their filesystem effects are opaque to the manifest and any
  additional working-tree changes need a separate manual commit.
- `--bump-only` paths still commit when `--commit` is set; the
  staged set is just `.seihou/manifest.json`.

**Why:**

`seihou run` already supported `--commit` / `--commit-message`. The
typical migration workflow ends with the user manually staging the
moved/deleted files and writing a commit message — exactly the loop
the run-side flags eliminate. Mirroring the flag pair on
`seihou migrate` makes the two commands' UX symmetric and lets a
project's "run and migrate as upstream evolves" workflow stay
single-command end to end.

**Docs updated:**
- `docs/cli/migrate.md` — adds `--commit` and `--commit-message`
  rows to the Options table, a new `## Auto-commit` section that
  mirrors the wording in `docs/cli/run.md`, and two examples in the
  Examples block.
- `docs/user/CHANGELOG.md` — this entry.

### 2026-04-27 (Recover from blocked migrations from the user's side)

**Reviewed commits:** EP-7 of MasterPlan
`docs/masterplans/1-migrations-dx.md` — surfacing the existing
`seihou migrate <module> --bump-only` escape hatch in every
blocked-migration message and adding a new bulk recovery flag for
`seihou run`.

**Behavior change (user-facing):**

- Blocked-migration messages at every site (Migrate, StatusRender,
  PendingMigrations.formatRefusalMessage, Run.applyOneMigration,
  Upgrade.printAdvisory, Upgrade.runOnePostUpgradeMigration) drop the
  "the module author must ship one before this project can move
  forward" finality sentence. Each site now names `seihou migrate
  <name> --bump-only` (the per-module manual escape hatch shipped in
  EP-6) as the recovery path. The PendingMigrations refusal trailer
  composes itself from the actual entry shapes: blocked-only inputs
  get `--bump-only` / `--bump-blocked` wording, runnable-only inputs
  keep the legacy `--with-migrations` wording, mixed inputs get both
  joined.
- `seihou status` Recommended actions tail block lists `seihou
  migrate <name> --bump-only` for blocked modules instead of the
  non-actionable `[blocked]` annotation.
- New flag `seihou run --bump-blocked`: acknowledges every blocked
  module by running `--bump-only` on each (writing the installed
  copy's declared version into the manifest with no migration ops),
  persists the manifest, and proceeds to the rest of the run.
  Compatible with `--with-migrations` for mixed projects: a single
  invocation of `seihou run --bump-blocked --with-migrations` bumps
  blocked entries and applies runnable chains in one pass.
  `--bump-blocked --dry-run` summarizes the bumps without writing.
  Each bump prints `  Bumping <name> <from> -> <to> (no migration
  declared; user-acknowledged).` as the audit trail.

**Why:**

After EP-6 the `--bump-only` escape hatch existed but was not surfaced
anywhere in the in-CLI messaging. Live verification on the
`seihou-project` working tree on 2026-04-27 (after EP-5 partial-applied
both `master-plan` and `exec-plan` to 0.2.0 and the upstream
`agent-seihou` advanced to 0.3.0 without shipping a continuation
migration) showed the user — who is *also* the module author — locked
out. The "wait for the module author to ship one" sentence is wrong
when the user *is* the author, and the absence of `--bump-only` /
`--bump-blocked` in the messaging meant a discoverable recovery
existed only for users who had already read the EP-6 changelog.

**Docs updated:**
- `docs/cli/run.md` — adds `--bump-blocked` to the flags table, adds
  a "Recovering from blocked migrations" subsection, updates the
  refusal-listing example to show the new shape-sensitive trailer,
  and adds `--bump-blocked` invocation examples.
- `docs/cli/migrate.md` — updates the Blocked subsection's example
  text and cross-references `seihou run --bump-blocked` from the
  `--bump-only` use cases.
- `docs/cli/status.md` — updates the Blocked example to show the
  new advisory and replaces the `[blocked]` annotation in the
  Recommended actions example with `seihou migrate <name>
  --bump-only`.
- `docs/cli/upgrade.md` — adds a new "Post-upgrade advisory" section
  documenting the three shapes (full/partial, blocked, benign) and
  what each prints; documents `--with-migrations` (already shipped
  in EP-2 but undocumented here).

### 2026-04-26 (Distinguish benign version bumps from missing migrations)

**Reviewed commits:** EP-6 of MasterPlan
`docs/masterplans/1-migrations-dx.md` — splitting today's
"blocked" outcome into two cases so a module that bumps its declared
`version` without shipping any migrations is no longer treated as
broken.

**Behavior change (user-facing):**
- `seihou status` softens the row for modules whose `migrations`
  field is the empty list and whose manifest version trails the
  installed copy. Previously this rendered as `Blocked: …`; now it
  reads:

  ```
      Pending: 0.2.0 -> 0.3.0 (no migrations declared). Run: seihou upgrade <name> && seihou run
  ```

  The Recommended actions tail lists `seihou upgrade <name> && seihou
  run` (the actual remediation) instead of `[blocked]`. The
  declared-but-unreachable case is unchanged: it still renders as
  `Blocked: …` and `[blocked]` because the author owes a migration.
- `seihou migrate <module>` (no `--to`) for an empty-migrations module
  with a version gap exits zero with a softened note:

  ```
  Note: <name> has no migrations declared (X -> Y). This is a benign
  version bump; run 'seihou upgrade <name> && seihou run' to refresh
  templates and bring the manifest up to date.
  ```

  No manifest change happens at this step; the next `seihou run`
  brings the manifest up to date. With `--to TARGET`, the
  strict-target contract still rejects this case as
  `MigrationGap`. The declared-but-unreachable case is unchanged: it
  still surfaces as `Blocked: …`.
- `seihou run` no longer refuses for the empty-migrations + version
  gap case. The benign entry is reported as a quiet info-level note
  (`Note: <name> has no migrations declared …; will refresh templates
  and bump manifest during this run.`) and the run proceeds normally;
  the manifest's recorded `moduleVersion` is updated to match the
  installed copy by the run flow's existing `updateAllModules`.
  `--with-migrations` treats benign entries as a no-op and continues.
  Declared-but-unreachable entries still trigger the `Blocked: …`
  refusal.
- New flag `seihou migrate <module> --bump-only`: refreshes the
  manifest's recorded `moduleVersion` to match the installed copy's
  declared version without running any migration ops. Mutually
  exclusive with `--to TARGET`. Use case: a project pinned at an
  older version of a module whose unreachable tail (from the
  `Bulletproof partial migration chains` work) the user has manually
  verified to be safe; `--bump-only` updates the bookkeeping without
  staging any chain. Output: `✓ Bumped <name> X → Y (no migration ops).`
- `seihou upgrade --with-migrations`'s post-upgrade advisory softens
  for the benign case: rather than `is blocked: no migration declared
  …`, it reads `<name> has no migrations declared (X -> Y); run
  'seihou run' to refresh templates.`

**Internal:**
- `MigrationPlan` gains a `planMigrationsDeclared :: Bool` field that
  records whether the input migrations list was non-empty. Consumers
  use it to dispatch between `MigrateBlocked` (declared but
  unreachable) and the new `MigrateBenignUpgrade` (no migrations
  declared).
- New `MigrateResult` variant `MigrateBenignUpgrade Version Version`
  for the empty-migrations case. Renderer prints the softened note;
  JSON path emits `{"benign": true, "from": …, "to": …}`.
- New `MigrateError` variant `MigrateConflictingFlags Text` (raised by
  `--bump-only --to`).
- New `MigrateOpts` field `migrateBumpOnly :: Bool`. When set,
  `runMigrate` short-circuits planning: fetches (unless `--no-fetch`),
  evaluates the installed copy's `module.dhall`, and writes the
  declared version into the manifest with an empty
  `ExecutedMigrationPlan`.
- New `Seihou.CLI.PendingMigrations.isBenignUpgrade :: MigrationPlan
  -> Bool`. The run pre-flight uses it to partition pending entries
  into benign (skip the refusal/dispatch entirely) and blocking.
- New `Seihou.CLI.StatusRender.AdviceBenignUpgrade Text Version
  Version` variant for the softened status row.

### 2026-04-26 (Bulletproof partial migration chains)

**Reviewed commits:** EP-5 of MasterPlan
`docs/masterplans/1-migrations-dx.md` — softening the migration
planner's all-or-nothing contract so partial and blocked chains
become first-class outcomes across `seihou status`, `seihou migrate`,
and `seihou run`.

**Behavior change (user-facing):**
- `seihou status` now reports modules whose declared migrations don't
  reach the latest version. Previously these were silent. Three row
  shapes:
  - **Full chain** — `Pending migration: 0.1.0 -> 0.3.0 (N op(s)).
    Run: seihou migrate <name>` (unchanged).
  - **Partial chain** — same chain summary plus a `Note: no migration
    declared from <stuckAt>; remote is at <target>.` line.
  - **Blocked** — `Blocked: no migration declared from
    <manifest-version>; remote is at <target>. The module author must
    ship one before this project can move forward.` The Recommended
    actions tail uses `[blocked] no migration declared for <name>`
    instead of `seihou migrate <name>` because running migrate would
    just print the same blocked message.
- `seihou migrate <module>` (no `--to`) now applies the longest
  reachable prefix when the declared chain doesn't reach the remote
  exactly. The manifest's `moduleVersion` is bumped to the highest
  reached version, and a `Note: no migration declared from
  <stuckAt>; remote is at <target>.` advisory is printed. Blocked
  modules surface the same `Blocked: …` message; the command exits
  zero (no work was done; no manifest change).
- `seihou migrate <module> --to TARGET` keeps its strict-target
  contract: if the declared chain cannot reach `TARGET` exactly
  (partial or blocked), the command errors with `no migration covers
  the gap from X to TARGET`.
- `seihou run` (default) now refuses on every divergence — full,
  partial, and blocked — rather than silently falling back to "no
  pending plan" for partial/blocked. The refusal listing distinguishes
  the three shapes inline.
- `seihou run --with-migrations` applies full and partial chains
  in-band before the run plan is computed. For blocked entries it
  refuses with the same `Blocked: …` message, since there is no
  safe automatic upgrade past a missing migration.
- `seihou upgrade --with-migrations`'s post-upgrade hook now
  surfaces partial and blocked outcomes with the same advisories.

**Internal:**
- `planMigrationChain` now returns `Either MigrationPlanError (Maybe
  MigrationPlan)` where `MigrationPlan` carries a reachable
  `planChain` (possibly empty) and an optional `planUnreachable ::
  Maybe (Version, Version)` tail. The `MigrationGap` error variant
  remains in `MigrationPlanError` for the strict-target path
  (`seihou migrate --to TARGET`) but is no longer produced by the
  planner directly; CLI consumers synthesize it from
  `planUnreachable` when needed.
- `pendingChainFor` widens to `Maybe MigrationPlan`;
  `detectPendingMigrations` widens to `[(ModuleName, MigrationPlan)]`.
  All consumers (`Status`, `Run`, `Upgrade`, `formatRefusalMessage`)
  updated in lockstep.
- New `MigrateResult` variants: `MigrateAppliedPartial`,
  `MigrateDryRunOKPartial`, `MigrateBlocked`. New `ModuleAdvice`
  variants in `StatusRender`: `AdvicePartialMigration`,
  `AdviceBlockedMigration`.

### 2026-04-26 (CLI library-first: enforcement check)

**Reviewed commits:** EP-4 of MasterPlan
`docs/masterplans/2-cli-library-first-convention.md` — adding an
automated enforcement check so the convention cannot silently erode.

**Behavior change (developer-facing only):**
- Added `nix/check-cli-module-placement.sh`, a Bash script that walks
  `executable seihou`'s `other-modules` and fails when an entry does
  not import one of `Options.Applicative`, `Data.FileEmbed`,
  `GitHash`, or `Paths_seihou_cli`, and is not transitively trapped
  via importing another already-trapped seihou module. Two modules
  are exempt with inline justification: `Paths_seihou_cli` (no source
  file on disk) and `Seihou.CLI.AgentLaunchExec` (process launcher
  consumed only by trapped agent-prompt wrappers).
- Wired the script into `flake.nix`'s `checks` attribute as the new
  `cli-module-placement` check, and into the `pre-commit-check.hooks`
  block so a violating commit is rejected at commit time. Both are
  reachable via `nix flake check`.
- Promoted `Seihou.CLI.Completions.{Bash,Fish,Zsh}` from the
  executable target to `seihou-cli-internal`'s `exposed-modules`. The
  three modules generate shell-completion text and have no
  executable-only imports; they are pure helpers and were the only
  pre-EP-4 violations the script flagged.

**Documentation impact:** `CLAUDE.md` gained a one-line pointer to the
new check. No user-facing CLI behaviour changed.

### 2026-04-26 (CLI library-first: AgentLaunch split, Outdated re-exports retired)

**Reviewed commits:** EP-3 of MasterPlan
`docs/masterplans/2-cli-library-first-convention.md` — bringing the
last two known violations of the library-first convention into
compliance through source-level restructuring.

**Behavior change (developer-facing only):**
- `Seihou.CLI.AgentLaunch` is now a library module
  (`seihou-cli-internal`) carrying the pure surface and the
  IO-bearing context-gathering helpers (`AgentContext`,
  `gatherAgentContext`, `agentDirsForSession`, the three
  `*AllowedTools` constants, `substitute`, and the five `format*`
  helpers). The launcher functions (`launchAgent`,
  `launchAgentWith`) moved to a new executable-only module
  `Seihou.CLI.AgentLaunchExec` because they call
  `findExecutable`/`rawSystem`/`exitWith`. Consumers (`Assist`,
  `Bootstrap`, `Setup`) now import from both modules.
- `Seihou.CLI.Outdated`'s export list no longer re-exports
  `OriginInfo`, `OutdatedStatus`, `OutdatedEntry`, `CheckStats`, or
  `compareVersions`. Consumers import these names from their
  canonical homes: `Seihou.CLI.InstallShared` (for `OriginInfo`)
  and `Seihou.CLI.VersionCompare` (for the rest). `Status.hs` and
  `Upgrade.hs` were updated.
- Test suite gains `Seihou.CLI.AgentLaunchSpec` exercising
  `substitute` and the five `format*` helpers — coverage that was
  impossible while these helpers were trapped in the executable
  target.

### 2026-04-26 (CLI cabal restructured; executable depends on library)

**Reviewed commits:** EP-2 of MasterPlan
`docs/masterplans/2-cli-library-first-convention.md` — restructuring
`seihou-cli/seihou-cli.cabal` so the executable depends on the
library and lives in its own source directory.

**Behavior change (developer-facing only):**
- `executable seihou` in `seihou-cli/seihou-cli.cabal` now has
  `build-depends: seihou-cli-internal` and `hs-source-dirs:
  src-exe`. Main.hs and the 27 executable-only modules
  (`Seihou.CLI.AgentLaunch`, `Assist`, `Bootstrap`, `Browse`,
  `Commands`, `Completions`, `Completions.Bash`, `Completions.Fish`,
  `Completions.Zsh`, `Config`, `Context`, `Help`, `Install`, `Kit`,
  `NewModule`, `NewRecipe`, `Outdated`, `Remove`, `Run`,
  `SchemaUpgrade`, `Setup`, `Status`, `Upgrade`, `Validate`, `Vars`,
  `Version`) moved from `seihou-cli/src/` to `seihou-cli/src-exe/`.
  The library still owns `seihou-cli/src/`.
- The executable's `other-modules` list is now strictly the
  trapped-by-dependency set. Each module's trapping reason
  (`Options.Applicative`, `Data.FileEmbed`, `GitHash`,
  `Paths_seihou_cli`, or — transitively — `Seihou.CLI.Commands`) is
  recorded in a "Trapped-modules inventory" table in
  `docs/dev/architecture/overview.md`. The cabal file carries a
  single header comment pointing at the table, since the project's
  `cabal-gild` formatter floats per-line `--` comments to the top of
  `other-modules` and would silently desynchronise per-module
  annotations.
- `Seihou.CLI.SchemaVersion`, `Seihou.CLI.Shared`, and
  `Seihou.CLI.Style` are now exposed by the library
  (previously they were either executable-only or library-private).
- The build no longer compiles shared modules twice. `cabal build`
  now compiles 24 library modules + 28 executable modules per clean
  build, down from 23 + 52.

**Mid-implementation discovery (recorded in EP-2):** the original
plan assumed that removing duplicate `other-modules` entries from
the executable would suffice. Empirically GHC walks
`hs-source-dirs: src` and recompiles every reachable source file
regardless of `other-modules`, preferring local source over the
package. Splitting `hs-source-dirs` was required to make
`build-depends` actually do its job.

**No user-visible CLI behavior change.** The 143-test CLI suite
still passes; `seihou --version` and `seihou --help` still produce
their expected output.

### 2026-04-26 (CLI library-first module-placement convention documented)

**Reviewed commits:** EP-1 of MasterPlan
`docs/masterplans/2-cli-library-first-convention.md` — documenting the
convention that new code under `seihou-cli/src/Seihou/` defaults to
the `seihou-cli-internal` library.

**Behavior change (developer-facing only):**
- Added a "CLI Module Placement Convention" section to
  `docs/dev/architecture/overview.md` (the canonical home of the
  rule) between "Project Structure" and "Technology Stack". It names
  the four executable-only Haskell-package dependencies
  (`Options.Applicative`, `Data.FileEmbed`, `GitHash`,
  `Paths_seihou_cli`), the fifth transitive criterion (importing
  another executable-only seihou module, most commonly
  `Seihou.CLI.Commands`), the cabal-comment format, and the appeal
  procedure for adding an exemption.
- Created a new project-root `CLAUDE.md` carrying a one-paragraph
  summary of the convention plus pointers to the architecture doc and
  the coordinating masterplan.
- Created `docs/dev/contributing.md` as a developer-facing guide that
  mirrors the convention, documents the Conventional Commits
  expectation and the `ExecPlan:` / `MasterPlan:` / `Intention:` git
  trailers, and explains where ExecPlans and MasterPlans live.

**No user-visible CLI behavior change.** Subsequent EPs in
`docs/masterplans/2-cli-library-first-convention.md` (EP-2 cabal
restructure, EP-3 helper extraction, EP-4 enforcement check) encode
the convention in build configuration and tooling.

### 2026-04-26 (`seihou status` surfaces staleness and pending migrations)

**Reviewed commits:** EP-4 of MasterPlan
`docs/masterplans/1-migrations-dx.md` — the rewrite of `seihou status`
to surface outdated modules and pending migrations with copy-pasteable
remediation commands.

**Behavior change:**
- The "Applied modules" block now prints a remediation hint under any
  row that needs action. A row with a pending migration prints
  `Pending migration: X.Y.Z -> A.B.C (N operation(s)). Run: seihou
  migrate <name>`. A row that is merely outdated (no chain declared
  between the manifest's version and the remote) prints `Run: seihou
  upgrade <name>`. When both apply, the migration hint wins because
  `seihou migrate` (after EP-2) is self-contained.
- A new "Recommended actions:" tail block lists the exact commands to
  fix every flagged row. The block is omitted when no row needs
  action.
- The outdated annotation now reads `outdated: X.Y.Z available`
  (matching the masterplan example) instead of the older
  `outdated -> vX.Y.Z`.
- Pending-migration detection now runs on every `seihou status`
  invocation, not only with `--check-updates`. It is purely local
  (manifest + locally installed `module.dhall`), so this adds no
  network IO. `--check-updates` still controls the remote
  outdated-vs-installed check that requires shallow clones.

**Limitations carried over from EP-3:**
- A planner gap (the migrations list does not reach the installed
  version exactly) silences the pending-migration row, the same way it
  silences `seihou run`'s pre-flight. The planner's
  longest-reachable-prefix mode is still future work.
- The "outdated" annotation reflects the locally installed copy versus
  the remote, not the manifest's recorded version versus the remote.
  A user who has refreshed the install (via an earlier `seihou
  upgrade`) without migrating will see "up to date" on the row even
  though their project's manifest is behind. The pending-migration row
  bridges this gap when the planner can form a chain.

**Docs:**
- `docs/cli/status.md` — rewrote the "Update checking" section to
  cover the new remediation hint, the per-row format, and the
  Recommended actions block. Added a new "Pending migrations"
  section.

### 2026-04-26 (`seihou run` is migration-aware)

**Reviewed commits:** EP-3 of MasterPlan
`docs/masterplans/1-migrations-dx.md` — the addition of a pre-flight
pending-migration check to `seihou run` and the new `--with-migrations`
flag.

**Behavior change:**
- `seihou run` now refuses by default when at least one module in the
  current composition has a pending migration chain (the manifest's
  recorded version trails the locally installed copy and the
  intervening migrations resolve to a complete chain). The previous
  behavior — silently writing new template content into paths a
  migration would have moved, orphaning user edits at the old paths
  and skipping the migration's `RunCommand` ops — is no longer
  reachable. The refusal lists the pending range per module and points
  at the next command (`seihou migrate <module>` or
  `seihou run --with-migrations`).
- A new `--with-migrations` flag opts into in-band migration
  application. Each pending chain runs first (via the same code path
  as `seihou migrate <module> --no-fetch`); the run plan's diff is
  computed against the post-migration tree.
- `--dry-run --with-migrations` shows the chain summary plus the run
  plan computed against the *current* (pre-migration) disk, with a
  one-line note. Computing a real post-migration dry-run would
  require staging file moves to disk, which `--dry-run` declines to
  do.
- Detection is scoped to the composition: a pending chain on an
  applied module that is not part of the current run does not block.
- Detection is best-effort: planner gaps (the migrations list does
  not reach the installed version exactly) silently fall back to "no
  pending chain", so the new pre-flight is a no-op in that case and
  the older behavior is preserved.

**Docs:**
- `docs/cli/run.md` — added a "Migration awareness" subsection, the
  `--with-migrations` row in the options table, and two new examples.
- `docs/user/migrations.md` — added an "Integration with `seihou
  run`" subsection alongside the existing `upgrade` and `status`
  integrations.

### 2026-04-26 (`seihou migrate` is self-contained)

**Reviewed commits:** EP-2 of MasterPlan
`docs/masterplans/1-migrations-dx.md` — the
`runMigrate`-fetches-the-remote refactor and the new `--no-fetch` flag.

**Behavior change:**
- `seihou migrate <module>` no longer requires `seihou upgrade` to be
  run first. By default it now reads the source URL from
  `~/.config/seihou/installed/<name>/.seihou-origin.json`, clones the
  source repository shallowly, plans the chain against the remote's
  `module.dhall`, applies it, and refreshes the on-disk installed copy
  on success. The chatty progress lines (`Fetching …`) are suppressed
  with `--json`.
- A new `--no-fetch` flag preserves the legacy behavior for offline /
  hermetic workflows: in that mode `seihou migrate` performs no
  network IO and consults only the locally installed copy.
- Soft failures in the fetch path (no `.seihou-origin.json`, clone
  failure, module not present in the remote) emit a one-line note and
  silently fall back to the local-only path. JSON mode stays silent.
- `seihou upgrade --with-migrations` invokes the migration with
  `--no-fetch` internally, since the upgrade step has already
  refreshed the installed copy.

**Docs:**
- `docs/cli/migrate.md` — added a "Default behavior: fetch first"
  section, documented `--no-fetch`, and reframed the examples around
  the new default.
- `docs/user/migrations.md` — added a "Self-contained `seihou
  migrate`" subsection and updated the `seihou upgrade` integration
  note to reflect the internal `--no-fetch` reuse.

### 2026-04-26 (`outdated`/`upgrade` read true module.dhall version)

**Reviewed commits:** EP-1 of MasterPlan
`docs/masterplans/1-migrations-dx.md` — the introduction of
`Seihou.CLI.RemoteVersion.fetchTrueModuleVersion` and the rewrite of
`outdated`/`upgrade` to call it.

**Bug fix:**
- `seihou outdated` and `seihou upgrade` now report a module as outdated as
  soon as the upstream `module.dhall` declares a higher `version`, even when
  the upstream `seihou-registry.dhall` has not been re-synced. Previously, a
  registry that listed a stale `version = Some "0.1.0"` would mask a
  `modules/<name>/module.dhall` that already declared `0.3.0`, and both
  commands reported "up to date". The comparison now reads the truthful
  version from the cloned `module.dhall` and ignores the registry's static
  metadata.

**Docs:**
- `docs/cli/outdated.md` and `docs/cli/upgrade.md` each gained a section
  explaining how the "available" version is determined and why the registry
  index is intentionally bypassed.

### 2026-04-19 (parameterized dependency multi-instantiation)

**Reviewed commits:** the eight-commit ExecPlan 10 series culminating in
the multi-instance diamond fixtures.

**Features documented:**
- **Multi-instantiation of parameterized dependencies** — Two dependency edges pointing at the same child module with different `vars` now produce two independent invocations of that child. Two edges with identical `vars` dedupe to a single invocation. Before this change the second invocation was silently dropped; the real-world symptom was that `master-plan` compositions produced only one `.claude/skills/` symlink instead of two.
- **Manifest schema v2** — `.seihou/manifest.json` is now version 2. Each `AppliedModule` entry gains an optional `parentVars` field recording the parent-supplied bindings that produced the invocation. Version-1 manifests load unchanged (missing `parentVars` decodes to an empty map).
- **`seihou status` disambiguation** — When two invocations of the same module appear, the status line appends the bindings inline (`claude-skill-link [skill.name=exec-plan]`) so the two are distinguishable.

**Updates:**
- `docs/user/module-authoring.md` — added a "Multi-instantiation" subsection under "Composition and dependencies" with a worked `claude-skill-link` example showing two invocations producing two symlinks, and an explanation that identity is the edge's `vars`, not any downstream override. No new authoring syntax is required.

### 2026-04-19 (consolidated template reference; design-doc fixes)

**Reviewed commits:** this entry tracks the consolidation and cleanup
pass that follows the standalone-block trim work below.

- Added `docs/user/templating.md` — a single authoritative user-facing Template reference covering placeholder substitution (syntax, coercion rules, escape), conditional blocks (syntax, full expression grammar, nesting, untaken-branch semantics), standalone-block whitespace trim (qualification rules, what is absorbed, blank-line preservation, indentation/tabs), the five-variant error taxonomy with line-number semantics, authoring patterns (optional line, feature gate, if/else-with-default, multi-feature matrix, version-gated content), and guidance on when to escalate to DhallText or Structured.
- Trimmed `docs/user/module-authoring.md §Strategy: template` to a brief summary with a pointer to `templating.md`, removing the duplicated placeholder-syntax and conditional-blocks detail that had grown in place.
- Updated `docs/user/getting-started.md` — the Step 3 "Going further" teaser now links to `templating.md` rather than back into `module-authoring.md`.
- Fixed `docs/dev/design/proposed/generation-strategies.md §Placeholder Engine` — replaced three fictional signatures (`substitutePlaceholders`, `parseTemplate`, and the `Segment` ADT) with the actual public entry points in `Seihou.Engine.Template` (`renderTemplate`, `renderTemplateText`, `renderDestPath`, `renderCommand`, `valueToText`, `expandConditionals`). Corrected a typo in the coercion rule (`VTText` → `VText`). Added a note pointing to `docs/user/templating.md` for the authoring-level reference.

**No documentation needed:**
- Preserved the earlier 2026-04-19 standalone-trim entry as-is; this pass is a consolidation on top of it, not a replacement.

### 2026-04-19 (standalone-block whitespace trim)

**Reviewed commits:** the standalone-block addition (following the
2026-04-19 doc-sync entry below).

- Updated `docs/user/module-authoring.md` — expanded the "Conditional blocks" paragraph with a "Standalone block lines" section explaining when a tag is absorbed (only non-whitespace on its line → surrounding indent + one trailing newline consumed), and rewrote the worked example in the new readable multi-line style.
- Updated `docs/dev/design/proposed/generation-strategies.md` — added a "Standalone-block whitespace trim" bullet to the Conditional blocks semantics list, citing Mustache/Handlebars as the reference for the behavior.
- Updated `docs/plans/9-inline-conditionals-in-template-strategy.md` — Revisions entry and a Decision Log entry recording the choice to add standalone trim rather than adopt an external templating engine (Ginger/Mustache/etc.).

**Features documented:**
- **Standalone-block whitespace trim** — When a `{{#if}}`, `{{#else}}`, or `{{/if}}` tag is the only non-whitespace on its line, the tag absorbs the surrounding indent and the single trailing newline, so multi-line readable templates no longer emit blank-line cruft. Exactly one newline is consumed per trim side, preserving deliberate blank-line spacing inside blocks.

### 2026-04-19 (doc sync: --confirm-defaults, Dhall-as-templating evaluation, ExecPlan 9 M5)

**Reviewed commits:** `0d79a1c` through `154b330`. Supplements the
2026-04-16 and 2026-04-18 entries which advanced CHANGELOG content but
did not advance the "Last Reviewed Commit" pointer.

- Updated `docs/cli/run.md` — added `--confirm-defaults` to the Options table and a "Reviewing defaults interactively" subsection, plus an example. This closes the doc gap from ExecPlan 7 (2026-04-18 work landed the flag and user-guide text but not the CLI reference).
- Updated `docs/user/getting-started.md` — filled the `seihou run` flags table with `--save-prompted`, `--no-save-prompted`, `--commit`, `--commit-message`, and `-c, --context` (pre-existing omissions). Added a "Going further: conditional blocks inside a template" teaser to Step 3 with a short `{{#if IsSet license}}` example and a pointer to the `Strategy: template` section of `module-authoring.md`, so a first-time reader discovers the block form without having to read the reference.
- Updated `docs/dev/design/proposed/cli-commands.md` — added `runConfirmDefaults :: Bool` to the `RunOpts` record, the flag to the usage line, and a row to the options table.
- Updated `docs/dev/design/proposed/variable-resolution.md` — added a "Reviewing default and parent values" subsection under "Interactive Prompts" describing the `confirmDefaults` pass, its `FromDefault`/`FromParent` source filter, the `FromPrompt` retagging, and the conditions under which the flag is a no-op.
- Updated `docs/dev/architecture/overview.md` — revised the "Templates Stay Dumb" decision to reflect inline `{{#if}}` conditional blocks; updated the project-tree comment for `Template.hs`. Template bodies now support boolean gating via `{{#if}}/{{#else}}/{{/if}}`; anything richer still requires `DhallText`.
- ExecPlan 9 M5 (sibling `nix-haskell-flake` migration, `seihou-modules` commit `b6ccd2a`) and the follow-up test-coverage broadening (`154b330`) are covered by this entry; no in-repo user docs changed for those.
- ExecPlan 8 (Dhall-as-templating evaluation: `492c5ac` through `af1c372`) landed a design-only doc at `docs/dev/design/proposed/dhall-as-templating-evaluation.md` plus test-only prototypes (`Seihou.Engine.TypedDhallText`, the now-retired `TemplatePrototype`, and the `split-flake` / `dhall-text-flake` / `typed-dhall-text-flake` / `conditional-template-flake` fixtures). No user docs needed.

**Features documented:**
- **`seihou run --confirm-defaults`** — Interactive flag that pauses between variable resolution and plan compilation, re-prompting every variable whose value came from a module default (priority 8) or a parent-binding export (priority 7). Overrides flow through `FromPrompt` retagging into the existing save-prompted offer. No-op in non-interactive mode and when nothing is default- or parent-sourced.

**No documentation needed:**
- `492c5ac` Reproduce split-flake pain point in-tree (fixture-only)
- `e02cafc` Prototype A (dhall-text single-source flake; fixture + evaluation prototype)
- `cd8f8b1` Prototype B (typed-function dhall-text renderer; experimental module, test-only)
- `c4f9cdd` Prototype C (inline `{{#if}}` prototype; superseded and deleted in ExecPlan 9 M3)
- `59623d9` / `af1c372` Evaluation doc (dev-only design record)
- `154b330` Broaden `renderTemplateText` test coverage (test-only)
- `5ddfab7` Record ExecPlan 9 outcomes and sibling-repo migration (plan doc + cross-repo commit)
- `ab29a2a` / `9faa2c2` / `69e7de4` ExecPlan 7 source + test + initial doc commits — superseded here by the `docs/cli/run.md` and `docs/dev/design/proposed/` updates above

### 2026-04-18 (inline conditional blocks in template strategy)

**Reviewed commits:** ExecPlan 9 milestones M1–M4

- Updated `docs/user/module-authoring.md` — added a "Conditional blocks" subsection under "Strategy: template" documenting `{{#if}}`, `{{#else}}`, and `{{/if}}` syntax, the shared `when`-expression grammar, unbounded nesting, an optional-postgres worked example, and the restriction that blocks apply to bodies only (not dest paths or shell commands).
- Updated `docs/dev/design/proposed/generation-strategies.md` — added "Conditional blocks (Template only)" under "Strategy Dispatch" with the same syntax, semantics, and a pointer to `docs/plans/9-inline-conditionals-in-template-strategy.md`. Synced the `PlaceholderError` sketch with the three new block-level variants.

**Features documented:**
- **Inline `{{#if}}` conditional blocks in the Template strategy** — A single `.tpl` can branch on resolved variables instead of shipping two near-duplicate templates gated by mutually exclusive `when` conditions. Supports `{{#if}}…{{/if}}`, `{{#if}}…{{#else}}…{{/if}}`, arbitrary nesting, and the same expression grammar as step-level `when`. Template bodies only — `renderDestPath` and `renderCommand` remain placeholder-only.

### 2026-04-16 (recipes, status --check-updates)

**Reviewed commits:** `ee892a4` through `0d79a1c`

- Added `docs/cli/new-recipe.md` — CLI reference for the new `seihou new-recipe` command
- Updated `docs/cli/run.md` — documented transparent recipe detection, expansion, and manifest provenance
- Updated `docs/cli/list.md` — documented `[recipe]` tag on recipe entries in output
- Updated `docs/cli/install.md` — documented single-recipe repo detection and registry recipe entries
- Updated `docs/cli/browse.md` — documented recipe entries from registries and single-recipe repos
- Updated `docs/cli/status.md` — documented recipe provenance display, `--check-updates` flag with update annotations
- Updated `docs/user/getting-started.md` — added recipes overview, `seihou new-recipe` in "Other commands", recipe in fzf/list output examples
- Updated `docs/user/module-authoring.md` — added full "Recipes" section with recipe.dhall format, fields, creation, running, validation, and comparison table; updated module search paths to cover recipes
- Updated `docs/user/registries-and-multi-module-repos.md` — added `recipes` field to registry format, single-recipe repos in discovery order, name collision validation
- Updated `docs/dev/architecture/overview.md` — added `Recipe.hs`, `Recipe.hs` (Composition), `NewRecipe.hs` to project tree; noted recipe expansion in pipeline
- Updated `docs/dev/design/proposed/cli-commands.md`:
  - Command ADT now includes `NewRecipe NewRecipeOpts`, `Status StatusOpts`, `SchemaUpgrade SchemaUpgradeOpts`
  - Added `NewRecipeOpts`, `StatusOpts` type definitions
  - Added `seihou new-recipe` command specification section
  - Updated `seihou run` with recipe support note
  - Updated parser tree to include `new-recipe`
  - Command count bumped from nineteen to twenty
- Updated `docs/dev/design/proposed/manifest-and-incrementality.md` — added `AppliedRecipe` type, `recipe` field to manifest schema JSON example
- Updated `docs/dev/design/proposed/module-system.md` — added `Runnable` type and `discoverRunnable` to discovery section
- Updated `docs/dev/roadmap/v1-milestones.md` — added M15 (Status Update Checks) and M16 (Recipes)

**Features documented:**
- **Recipes** — Named, reusable module compositions declared in `recipe.dhall` files. Transparent expansion via `seihou run`, first-class in `list`, `install`, `browse`, `status`, and fzf. Authored with `seihou new-recipe`. Registry support via `recipes` field in `seihou-registry.dhall`. Manifest tracks recipe provenance (`AppliedRecipe`).
- **`seihou status --check-updates`** — Annotates each applied module with its update status (up to date, outdated, unversioned, unreachable) by checking source registries over the network.

**No documentation needed:**
- `562f460` Upgrade mori.dhall to use schema record completion defaults (tooling/meta)
- `60e792d` Fix use-after-free in checkSource temp-dir lifetime (bug fix)
- `6510055` Record ExecPlan #5 outcomes for status --check-updates (plan doc)
- `468a07c` Extract checkInstalledModulesForUpdates from handleOutdated (internal refactoring)
- `ee9da40` Add master-plan seihou module with skill and spec (tooling)
- `d5bc82c` Sync docs with kit, install history, list filters, run --commit, and version-required features (already a doc commit)

---

### 2026-04-15 (kit, install history, list filters, run --commit, version required, status versions)

**Reviewed commits:** `c771d60` through `ee892a4`

- Added `docs/cli/kit.md` — CLI reference for the new `seihou kit` command (list/install/update/uninstall/status for Claude Code skills and subagents)
- Updated `docs/cli/install.md` — documented optional `GIT-URL` argument, install history (`~/.config/seihou/install-history.json`), fzf picker fallback
- Updated `docs/cli/list.md` — documented `--repo` and `--tag` filters with origin metadata semantics
- Updated `docs/cli/run.md` — documented `--save-prompted`/`--no-save-prompted`, `--commit`, `--commit-message` flags and the AI-generated commit message integration
- Updated `docs/cli/validate-module.md` — added module version as a required validation check and listed the full set of core checks
- Updated `docs/cli/status.md` — documented module versions in applied-modules output and tracked-file status labels
- Updated `docs/user/module-authoring.md` — clarified that `version` is required at validation despite being `Optional Text` in the Dhall schema
- Updated `docs/dev/architecture/overview.md` — added `Kit.hs`, `InstallHistory.hs`, `CommitMessage.hs`, `Git.hs`, `SavePrompted.hs`, `AgentLaunch.hs` to the project layout tree; bumped "Updated" to 2026-04-15
- Updated `docs/dev/design/proposed/cli-commands.md`:
  - Command ADT now includes `Remove RemoveOpts`, `List ListOpts`, `Kit KitCommand`
  - Added `RemoveOpts`, `ListOpts`, `KitCommand` type definitions
  - `RunOpts` now shows `runModule :: Maybe ModuleName`, `runSavePrompted`, `runCommit`, `runCommitMessage`
  - `InstallOpts.installSource` is now `Maybe Text`
  - Command count bumped from eighteen to nineteen (adds `kit`)
  - Added `seihou kit <subcommand>` section
  - Updated `seihou run`, `seihou install`, `seihou list`, `seihou validate-module` sections
  - Updated optparse-applicative parser tree to include `remove` and `kit`
- Updated `docs/dev/design/proposed/module-system.md` — annotated the `version` field with a note that validation rejects `None`/empty

**Features documented:**
- `seihou kit {list,install,update,uninstall,status}` — manage Claude Code skills and subagents from the `seihou-kit` repository with user and project scopes
- `seihou install` without a source — fzf picker over install history at `~/.config/seihou/install-history.json`
- `seihou list --repo`/`--tag` — filter modules by registry name and tags recorded in `.seihou-origin.json`
- `seihou run --commit` / `--commit-message` — AI-generated or fixed commit message after successful generation, skipping gitignored files and stripping markdown code fences
- `seihou run` now accepts no module argument and opens an fzf picker
- Module `version` is required at validation (rejects `None` and empty string)
- `seihou status` shows module versions alongside applied modules and tracked-file status labels (`unchanged`/`modified by user`/`deleted by user`)

**No documentation needed:**
- `ee892a4` Add mori repo-id (tooling/meta)
- `30e44e7`, `ab22e47` Migrate mori.dhall to latest schema (tooling)
- `82df8ae` Release v0.1.0.0 (release meta)
- `0ae766c` Add seihou-release skill (tooling)
- `ce859c7` Fix --commit failing when generated files match .gitignore (bug fix)
- `a1f3c4c`, `bf9c27c` Regenerate seihou scaffolding (internal)
- `542ed58` Update manifest design doc (already a doc commit)
- `0b11612` Fix manifest losing files and variables from independent module runs (bug fix)
- `5816d08` Fix --commit stripping markdown code fences (bug fix; behavior is documented)
- `06870d5` Grant full git access to assist agent command (tooling)
- `0485b26` Add save-prompted feature (already documented in 2026-03-26 entry)
- `f4f70b1` Apply exec-plan module (internal)
- `c771d60` Document append-line-if-absent patch op (already a doc commit)

---

### 2026-03-26 (save prompted values to local config)

- Updated `docs/user/config-and-variables.md` — added "Saving prompted values" section describing automatic save-to-config after interactive prompts
- New CLI flags: `--save-prompted` (auto-save without asking) and `--no-save-prompted` (suppress the offer)
- New module: `Seihou.CLI.SavePrompted` — pure logic for collecting and persisting prompted values

**Features documented:**
- After running a module interactively, Seihou offers to save prompted variable values to `.seihou/config.dhall` so they are reused on subsequent runs without re-prompting. Values are shown for confirmation before saving. Existing config values are not silently overwritten.

---

### 2026-03-25 (append-line-if-absent patch op)

**Reviewed commits:** `0585b67` through `88b6060`

- Updated `docs/user/module-authoring.md` — added `"append-line-if-absent"` to patch field values and composition patching section
- Updated `docs/dev/design/proposed/composition-and-layering.md` — added `AppendLineIfAbsent` to `PatchOp` type definition
- Updated `docs/dev/architecture/overview.md` — updated Section.hs description and plan compilation mention
- Updated `seihou-cli/data/bootstrap-prompt.md` — added `append-line-if-absent` to patch field comment and composition patching reference
- Updated `seihou-cli/data/assist-prompt.md` — added `append-line-if-absent` to patch field comment and composition patching reference

**Features documented:**
- `patch = Some "append-line-if-absent"` — new idempotent patch operation that appends only lines not already present in the target file. Designed for line-oriented config files like `.gitignore` and `.dockerignore`. Re-runs produce no duplicates and no section markers.

**No documentation needed:**
- `0585b67` Expand bootstrap agent permissions to reduce user prompts (tooling)
- `0f91ff6` Group --help output into coherent command categories (already documented)
- `240a9f7` Preserve PatchFileOp in composed plan when no base file exists (bug fix)
- `ada7b9f` Fix patch operations incorrectly classified as conflicts (bug fix)
- `913a06a` Sync SchemaVersion.hs with latest seihou-schema pin (infrastructure)

### 2026-03-21 (remove command)

**Reviewed commits:** `cf7aeac` through `f115d6b`

- Added `docs/cli/remove.md` — CLI reference for the new `seihou remove` command
- Updated `docs/user/module-authoring.md` — added `removable` field to module.dhall format reference, added "Removing modules" section with reversibility guidance
- Updated `docs/user/getting-started.md` — added "Removing a module" to the Other commands section
- Updated `docs/dev/design/proposed/cli-commands.md` — added `seihou remove` command spec, moved from future enhancements to documented, updated command count to eighteen
- Updated `docs/dev/architecture/overview.md` — added `Remove.hs` to project tree (engine + CLI), updated Filesystem effect description

**Features documented:**
- `seihou remove <module> [--dry-run] [--force] [--verbose]` command for reversible module removal
- `removable : Bool` field in module.dhall (default `False`) — opt-in for module removal
- `RemoveFile` and `RemoveDirectoryIfEmpty` Filesystem effect operations
- Removal plan classification: safe (unchanged), conflict (modified), gone (deleted)

**No documentation needed:**
- `cf7aeac` Fix bool value comparison in conditional expressions (bug fix, no user-facing doc impact)

### 2026-03-21 (schema URL imports)

**Reviewed commits:** `87ab9c9` through `a184a71`

- Updated `docs/user/module-authoring.md` — schema package section now shows URL-based imports from `seihou-schema` GitHub repo; schema-upgrade section documents `MissingSchemaImport` detection
- Updated `docs/cli/schema-upgrade.md` — added missing schema import to the list of handled transformations
- Updated `seihou-cli/help/modules.md` — schema package section updated to show URL import pattern
- Updated `seihou-cli/data/assist-prompt.md` — schema package example uses URL import
- Updated `seihou-cli/data/bootstrap-prompt.md` — schema package example uses URL import

**Features documented:**
- Schema is now published at `github.com/shinzui/seihou-schema` and imported via pinned HTTPS URL with integrity hash
- `seihou new-module` generates modules with schema URL imports and record completion (`S.Module::`)
- `seihou schema-upgrade` detects and injects missing schema imports (`MissingSchemaImport`)
- `update-seihou-schema` Claude Code skill for bumping the schema pin

**No documentation needed:**
- `a184a71` Finalize publish-schema-repo plan (plan doc)
- `1ffde57` Fix update-seihou-schema skill location (tooling)
- `8bd9e04` Create update-seihou-schema skill (tooling)
- `c4b9bc3` Update Nix build to handle schema submodule (infrastructure)
- `e65cc51` Remove schema/ from tracking (internal git change)

### 2026-03-21

**Reviewed commits:** `378dafc` through `8daa78c`

- Added `docs/cli/schema-upgrade.md` — CLI reference for the new `seihou schema-upgrade` command
- Updated `docs/user/module-authoring.md` — standardized dependency format to record form, added schema package and record completion section, added schema-upgrade section
- Updated `docs/user/getting-started.md` — updated scaffold boilerplate to use record-form deps, added schema-upgrade to "Other commands"
- Updated `seihou-cli/help/modules.md` — added dependency record form examples, schema package section, schema-upgrade to common commands

**Features documented:**
- `seihou schema-upgrade [PATH] [--dry-run] [--all]` command for upgrading module.dhall files to current schema
- Dhall schema package (`schema/package.dhall`) with record completion (`::`) support
- Standardized dependency format: `{ module : Text, vars : List { name : Text, value : Text } }`

**No documentation needed:**
- `da7591a` Audit and update all docs to reflect current codebase state (meta — already captured in 2026-03-20 entry)
- `d849d19` Show help when seihou is invoked without a command (UX improvement, no doc change needed)

### 2026-03-20

**Reviewed commits:** `fe1819a` through `378dafc`

- Full documentation audit: all dev docs, user docs, and product specs reviewed against codebase
- Updated status on 4 design docs from "Proposed" to "Implemented" (architecture, composition, generation-strategies, manifest)
- Updated roadmap status from "In Progress" to "Done"; added milestones M10–M14
- Updated CLI commands doc with 5 new commands: outdated, upgrade, help, completions, agent
- Fixed Command ADT to match actual code (17 constructors)
- Added `version` field to Module type in module-system.md and module-authoring.md
- Added `FromParent` to variable resolution precedence chain (9 tiers, not 8)
- Fixed PatchOp type in composition doc (3 constructors, not 5)
- Fixed CompositionWarning type to match code (ContentMerged, not UnusedExport)
- Fixed Strategy type in generation-strategies doc (no StructuredFormat parameter)
- Added RegistryEvalError to ModuleLoadError
- Updated architecture overview project layout tree with all current files
- Added parameterized dependency documentation to module-authoring.md and variable-resolution.md
- Added outdated/upgrade/completions/help sections to getting-started.md
- Added parent bindings to config-and-variables.md resolution hierarchy
- Updated parser tree in cli-commands.md

**Documentation status:**
- `docs/user/getting-started.md`: Updated with outdated, upgrade, completions, help commands
- `docs/user/module-authoring.md`: Updated with version field, parameterized dependencies, FromParent
- `docs/user/config-and-variables.md`: Updated with 9-tier resolution hierarchy including parent bindings
- `docs/user/registries-and-multi-module-repos.md`: Up to date (no changes needed)
- `docs/dev/architecture/overview.md`: Updated status, project layout tree
- `docs/dev/design/proposed/cli-commands.md`: Updated with all 17 commands
- `docs/dev/design/proposed/module-system.md`: Updated Module type, Dependency type, Dhall schema
- `docs/dev/design/proposed/variable-resolution.md`: Updated with FromParent source
- `docs/dev/design/proposed/composition-and-layering.md`: Updated PatchOp, CompositionWarning
- `docs/dev/design/proposed/generation-strategies.md`: Updated Strategy type
- `docs/dev/design/proposed/manifest-and-incrementality.md`: Status updated
- `docs/dev/roadmap/v1-milestones.md`: Updated status, added M10–M14
- `docs/dev/versioning.md`: Up to date (no changes needed)

**No documentation needed:**
- `0f532a9` Add .seihou/manifest.json.tmp to gitignore (internal)
- `afb9678` Add seihou-update-docs skill (tooling)
- `fe1819a` Add documentation changelog (meta)
- `18148c6` Add ExecPlan for help topics (plan doc)
- `721d46d` Mark parameterized dependencies plan as complete (plan doc)
- `8d3527c` Add git worktree tools to agent allowed tools (tooling)
- `6b27cf1` Grant agent setup full git and seihou permissions (tooling)

### 2026-03-07

**Reviewed commits:** `94e0052` (init) through `b6baa4f`

- Initial documentation review covering all commits to date
- All user-facing features are documented

**Documentation status:**
- `docs/user/getting-started.md`: Complete end-to-end guide covering all CLI commands
- `docs/user/module-authoring.md`: Complete module format reference (variables, steps, strategies, commands, composition)
- `docs/user/config-and-variables.md`: Configuration scopes, variable resolution, and context-aware variables
- `docs/user/registries-and-multi-module-repos.md`: Registry metadata and multi-module repository support
- `docs/dev/versioning.md`: Version embedding with git SHA (dual-path: TH + Nix CPP)
- `docs/dev/architecture/overview.md`: System architecture and effect stack

**No documentation needed:**
- `49775a7` Add result to gitignore (internal)
- `ded95f8` Add haskell-nix for GHC 9.12 tool patches (infrastructure)
