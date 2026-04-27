# Documentation Changelog

## Last Reviewed Commit

```
HEAD  Run parameterized dependencies once per distinct parent binding (ExecPlan 10)
```

---

## Changelog

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
