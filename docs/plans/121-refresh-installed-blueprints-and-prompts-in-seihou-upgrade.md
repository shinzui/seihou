---
id: 121
slug: refresh-installed-blueprints-and-prompts-in-seihou-upgrade
title: "Refresh installed blueprints and prompts in seihou upgrade"
kind: exec-plan
created_at: 2026-11-11T13:50:03Z
intention: "intention_01m75dyqjsexgvcz1ms2rqs1zn"
provenance:
  created_by:
    model: "claude-opus-5-5"
    harness: "claude-code"
    at: 2026-11-11T13:50:03Z
  revisions:
    - model: "claude-opus-5-5"
      harness: "claude-code"
      at: 2026-11-11T14:39:01Z
      mode: "implement"
      note: "Milestones 1-3 implemented"
---

# Refresh installed blueprints and prompts in seihou upgrade

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.
Record friction met while implementing in the friction-log bundle as it occurs (see FRICTION.md).

This plan implements [IR-17](../improvement-requests/refresh-installed-blueprints-in-seihou-upgrade.md)
(`docs/improvement-requests/refresh-installed-blueprints-in-seihou-upgrade.md`).


## Purpose / Big Picture

A Seihou user installs artifacts with `seihou install <git-url>`. The installed copies live in a
machine-wide cache directory, and `seihou upgrade` is the command that refreshes that cache from
the artifacts' source repositories. Today it refreshes only two of the four installable kinds,
modules and recipes. An installed **blueprint** (a `blueprint.dhall` artifact that
`seihou agent run` hands to an AI agent) or an installed **prompt** (a `prompt.dhall` artifact used
by `seihou prompt` and the agent commands) is never refreshed. Naming one explicitly fails with
`Module(s) or recipe(s) not found` and exit 1.

The failure is silent in practice. A blueprint author pushed version 0.1.1 of
`relaunch-fumadocs-docs`, ran `seihou upgrade`, and the next unattended `seihou agent run --batch`
ran for an hour on 0.1.0. `seihou agent --debug run relaunch-fumadocs-docs` still printed
`Version: 0.1.0`. Only `seihou install https://github.com/shinzui/seihou-modules.git --module
relaunch-fumadocs-docs` replaced the copy. The source of that report is
`mori://shinzui/kotei-docs/okf/friction-log/concepts/FRIC-5`. Worse, Seihou's own stale-artifact
refusal (ADR 0003, below) tells the user to run `seihou upgrade <blueprint>`, which is exactly the
command that does not work for a blueprint.

After this change:

1. `seihou upgrade` with no names also refreshes every installed blueprint and prompt that has
   origin metadata, together with the modules a blueprint installs as its baseline (its
   *closure*, defined below).
2. `seihou upgrade relaunch-fumadocs-docs` refreshes that blueprint, prints a row with its old and
   new versions (also in `--json`), and exits 0. `seihou agent --debug run relaunch-fumadocs-docs`
   then shows `Version: 0.1.1`.
3. A refresh that would overwrite a cache entry whose provenance names a different source, or has
   no provenance, is refused without touching the cache, as ADR 0006 requires. The command
   reports a failed row and exits non-zero.
4. `seihou outdated` lists installed blueprints and prompts whose source declares a newer
   version.


## Progress

- [x] Milestone 1: the library module `Seihou.CLI.InstalledRunnables` refreshes a blueprint or
  prompt closure from its recorded source. A dry run leaves the cache unchanged. A
  different-source or unprovenanced cache entry is refused with the cache byte-identical.
  Proven by the new `InstalledRunnablesSpec`. (2026-11-11: all 5 cases pass — single blueprint
  upgrade then up to date, dry run with the cache snapshot unchanged, baseline module refreshed
  through the blueprint closure, different-source refusal naming both URLs with the module entry
  and its marker byte-identical, single prompt.)
- [x] Milestone 2: `seihou upgrade` selects installed blueprints and prompts, with or without
  names. It reports them in text and `--json` and exits non-zero on a failed row. Proven by the
  new end-to-end `UpgradeRunnablesE2ESpec`, including `seihou agent --debug run` printing the new
  version. (2026-11-11: the E2E scenario passes all seven steps, `Version: 0.1.1` included; the
  `RecipeExtension`, `agent path artifact guard`, and upgrade-related groups pass, 113 tests.)
- [ ] Milestone 3: `seihou outdated` reports blueprints and prompts. `docs/cli/upgrade.md`,
  `docs/cli/outdated.md`, and both commands' `--help` text mention them. The full test suite and
  `nix flake check` pass.


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Cover prompts as well as blueprints.
  Rationale: IR-17 asks for blueprints and notes that prompts installed through `seihou install`
  have the same gap. Both kinds are installed by the same code
  (`Seihou.CLI.InstallClosure.installClosure`), and neither has dependencies a module or recipe
  would need. The refresh written here is kind-agnostic beyond locating the descriptor file, so
  prompts cost almost nothing extra. Leaving them out would require a second plan to repeat this
  one.
  Date: 2026-11-11

- Decision: Refresh a blueprint or prompt by restaging its whole install closure and comparing
  content hashes, as recipes already do. Do not compare versions and reinstall the single
  directory, as modules do.
  Rationale: `seihou install` installs a blueprint together with its `baseModules`, after
  validation and import normalization (`stageClosuresInto` in
  `seihou-cli/src/Seihou/CLI/InstallClosure.hs`). Reinstalling only the blueprint directory
  through `installModuleDir` would skip that validation and normalization. It would also leave the
  baseline modules stale when a new blueprint version needs newer ones. Hash comparison also
  catches a fix published without a version bump, which is a common authoring slip. `seihou
  outdated` still compares versions, because it reads only the source and never stages anything.
  Date: 2026-11-11

- Decision: Stage each selected blueprint or prompt as its own closure, from one clone per source
  URL.
  Rationale: Per-root staging keeps one broken blueprint from failing its siblings from the same
  repository. It also makes `--skip-unversioned` able to keep one root's closure together, the
  rule recipes follow. Cloning once per source keeps network cost the same as the module path.
  Date: 2026-11-11

- Decision: `seihou upgrade` exits 1 when any reported row is `failed`, for every artifact kind.
  An `unreachable` source still exits 0.
  Rationale: ADR 0006 established that a cache write that did not fully succeed exits non-zero,
  because a script cannot otherwise tell it from success. `seihou upgrade` currently exits 0 even
  when a module row says `failed: ...`. Making the new blueprint refusal exit non-zero while a
  module refusal exits 0 would be inconsistent within one command. A network outage stays exit 0
  because it is transient and says nothing about the cache's integrity. This changes existing
  module behavior and is the one deliberate scope expansion here; revisit it if a caller depends
  on the old exit code.
  Date: 2026-11-11

- Decision: Keep the `--json` entry shape unchanged (`module`, `oldVersion`, `newVersion`,
  `status`), and make `seihou upgrade --json` print nothing else on stdout.
  Rationale: Existing consumers, including `RecipeExtensionE2ESpec`, parse that array. A blueprint
  row is distinguishable by name. A `kind` field would be additive, but recipe-closure rows do not
  carry a kind today, so adding one consistently is a separate change. The module path prints
  `  Cloning <repo>...` and `    Upgraded <name>` to stdout even under `--json`, which corrupts the
  document as soon as any installed module has origin metadata. The fix is two guarded `putStrLn`
  calls in the file this plan already edits, and it is needed to make the `--json` acceptance
  reliable.
  Date: 2026-11-11


- Decision: Classify each changed closure member against the real cache before calling
  `publishStagedClosure`, and give a refused member the one-line
  `Seihou.CLI.InstallShared.summarizeInstallRefusal` text. Other changed members of the same
  closure get `not published: <name> in the same closure was refused`.
  Rationale: `publishStagedClosure` returns the multi-line `formatInstallRefusal` block, which
  does not fit in a table row and does not say which row it belongs to. The closure is still
  published all or nothing, and `publishStagedClosure` still re-checks, so a race between the
  classification and the publish still refuses. The no-origin row names the entry's real path
  rather than `~/.config/...`, because `XDG_CONFIG_HOME` may move it. `seihou upgrade --json`
  with nothing to report prints `[]` rather than the text message, so stdout is always JSON.
  Date: 2026-11-11


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

The repository is a Haskell project built with cabal. The packages that matter here are
`seihou-core` (shared types, Dhall evaluation, artifact discovery) and `seihou-cli`. `seihou-cli`
has a library, `seihou-cli-internal`, in `seihou-cli/src/`, and the `seihou` executable in
`seihou-cli/src-exe/`. The project rule in `CLAUDE.md` is library-first: new modules go in
`seihou-cli/src/`. A module may live in `src-exe/` only if it imports `Options.Applicative`,
`Data.FileEmbed`, `GitHash`, or `Paths_seihou_cli`, or imports an executable-only module such as
`Seihou.CLI.Commands`. `nix/check-cli-module-placement.sh` enforces this. Records use strict
fields, an explicit deriving strategy, and `Generic`. Fields are read and written only through
`generic-lens` labels (`x ^. #field`, `x & #field .~ v`), never with record-update syntax, and
every module using labels imports `Data.Generics.Labels ()` itself.
`nix/check-record-conventions.sh` enforces these rules.

Terms used below:

- **Install cache.** The directory `~/.config/seihou/installed/` (more precisely
  `$XDG_CONFIG_HOME/seihou/installed/`, returned by `Seihou.CLI.InstallShared.installedRoot`).
  Each installed artifact is the subdirectory `installed/<key>`. The *key* is the registry entry
  name for a multi-artifact repository, or the repository name (or `--name`) for a
  single-artifact repository. The key usually equals the name in the descriptor but is not
  guaranteed to.
- **Origin metadata / provenance.** The file `installed/<key>/.seihou-origin.json`, written at
  install time. It records `sourceUrl`, `repoName`, `version`, `tags`, and `installedAt`.
  `Seihou.Core.ArtifactOriginDetect.readOriginInfo` (re-exported by
  `Seihou.CLI.InstallShared`) reads it as `OriginInfo { sourceUrl, repoName, version }`, or
  `Nothing` when the file is absent or unreadable.
- **Runnable.** Seihou's umbrella term for a module, recipe, blueprint, or prompt.
  `Seihou.Core.Module.discoverAllRunnables` (`seihou-core/src/Seihou/Core/Module.hs`) returns a
  `DiscoveredRunnable { name, description, kind, source, dir, isError, error }` for each one. Here
  `kind :: RunnableKind` is `KindModule | KindRecipe | KindBlueprint | KindPrompt`, and
  `source == SourceInstalled` marks the install cache. `name` is the descriptor's own name, or the
  directory name when the descriptor fails to load (`isError`).
- **Closure.** The set of artifacts one install brings in: the selected root plus everything it
  depends on, transitively. A blueprint's dependencies are its `baseModules`, the modules
  `seihou agent run` applies before the agent starts. A prompt has none.
- **Repository contents.** After cloning, `Seihou.Core.Registry.discoverRepoContents`
  (`seihou-core/src/Seihou/Core/Registry.hs`) classifies the clone. The possible values are
  `MultiModule Registry` (a `seihou-registry.dhall` whose `blueprints` and `prompts` lists hold
  `RegistryEntry { name, path, ... }`), `SingleModule`, `SingleRecipe`, `SingleBlueprint root`,
  `SinglePrompt root`, and `EmptyRepo`.

How `seihou upgrade` works today, in `seihou-cli/src-exe/Seihou/CLI/Upgrade.hs`:
`handleUpgrade` discovers modules and runnables. It keeps installed modules that have origin
metadata, plus installed runnables whose kind is `KindRecipe`:

```haskell
let installed = filter (\dm -> dm ^. #source == SourceInstalled) modules
    recipes = [recipe | recipe <- runnables, recipe ^. #source == SourceInstalled, recipe ^. #kind == KindRecipe]
```

Any requested name not found among those exits with `Module(s) or recipe(s) not found: ...`.
Recipes go through `upgradeRecipes`, which stages each recipe's candidate closure with
`Seihou.CLI.Update.Source.stageCandidateSources`. It compares
`Seihou.CLI.Update.Source.hashArtifactDirectory`, a content hash that ignores
`.seihou-origin.json` and `.git`, of each staged artifact against the installed copy, and
publishes the changed ones with `Seihou.CLI.InstallClosure.publishStagedClosure`. That staging
API is built around applied project compositions of module or recipe kind, so it cannot take a
blueprint. Modules go through `upgradeSource`/`upgradeModule`/`doUpgrade`. These clone each source
URL once, compare versions with `Seihou.CLI.VersionCompare.compareVersions`, and reinstall one
directory with `installModuleDir False ...`. `doUpgrade` explicitly returns "module not found in
remote" for `SingleBlueprint` and `SinglePrompt`. Rows are `UpgradeEntry { moduleName,
oldVersion, newVersion, upgradeStatus }`, with `UpgradeStatus = Upgraded | AlreadyUpToDate |
Skipped | UpgradeFailed Text | SourceUnreachable`. `renderUpgradeTable` prints them under the
headers `Artifact  Old  New  Status`, and `--json` encodes them as `{"module", "oldVersion",
"newVersion", "status"}`. After rendering, `handlePostUpgradeMigrations` prints a migration
advisory for upgraded rows whose name is a module recorded in the current project's manifest.
For any other name it does nothing, so blueprint rows are harmless there.

How `seihou install` installs a blueprint, in `seihou-cli/src-exe/Seihou/CLI/Install.hs` and
`seihou-cli/src/Seihou/CLI/InstallClosure.hs`: it clones the source and selects roots as
`(key, directory)` pairs, then calls `installClosure force cloneDir recordedUrl roots`. That
delegates to the exported `stageClosuresInto report cache force groups`, which does the following:

1. Walks the closure and validates every descriptor. A blueprint is checked with
   `validateBlueprintForInstall` and its `baseModules` become module requirements. A
   `baseModules` entry without a `source` is looked up in the same repository.
2. Copies and normalizes each artifact into a private staging directory.
3. Refuses, unless `force`, any destination in `cache` whose provenance names a different source
   or has none.
4. Atomically publishes into `cache`, then returns `[ClosureArtifact { name, sourceUrl, repoName,
   version, tags, sourceRevision, directory }]`, where `directory` is `cache </> name`.

With `report = False` it prints nothing to stdout. The function's private `readContents` refuses
to fall back to a stray root `module.dhall` when `seihou-registry.dhall` exists but does not
evaluate. `discoverRepoContents` does fall back in that case.

How `seihou outdated` works today, in `seihou-cli/src-exe/Seihou/CLI/Outdated.hs`:
`handleOutdated` checks installed modules only. It calls `checkInstalledModulesForUpdates`, which
groups modules by `sourceUrl`, clones each source, and reads the true version through
`Seihou.CLI.RemoteVersion.fetchTrueModuleVersion` (`seihou-cli/src/Seihou/CLI/RemoteVersion.hs`).
It prints `OutdatedEntry { moduleName, installedVersion, availableVersion, status }` rows under
`Module  Installed  Available  Status`. `seihou status`
(`seihou-cli/src-exe/Seihou/CLI/Status.hs`) also calls `checkInstalledModulesForUpdates`, so that
function's behavior must not change.

How the user sees a blueprint's version: `Seihou.CLI.AgentLaunch.formatBlueprintIdentity`
(`seihou-cli/src/Seihou/CLI/AgentLaunch.hs`) renders `Version: <version>` into the agent's system
prompt, which `seihou agent --debug run <name>` prints. Each descriptor reads with
`Seihou.Dhall.Eval.evalBlueprintFromFile` or `evalAgentPromptFromFile`
(`seihou-core/src/Seihou/Dhall/Eval.hs`), and both result types have `version :: Maybe Text`.

Tests live in `seihou-cli/test/`. Each spec module exports `tests :: IO TestTree`, is registered in
`seihou-cli/test/Main.hs`, and is listed under `test-suite seihou-cli-test`'s `other-modules` in
`seihou-cli/seihou-cli.cabal`. Two existing specs show the patterns needed here.
`seihou-cli/test/Seihou/CLI/RecipeExtensionE2ESpec.hs` (helpers `remoteFixture`, `initRemote`,
`commitRemote`, `invokeCommand`) creates producer git repositories under a temporary root and
routes portable URLs such as `https://example.invalid/<name>.git` to them. It does so with a
`GIT_CONFIG_GLOBAL` file containing `[url "file://<dir>"] insteadOf = <url>`, and it runs the real
binary with `HOME`/`XDG_CONFIG_HOME` pointed into the temporary root.
`seihou-cli/test/Seihou/CLI/AgentGuardE2ESpec.hs` (helpers `withGuardFixture`, `blueprintDhall`,
`noBaseModules`, `demoBaseModule`) builds a git-initialized project with a fake `claude`
executable on `PATH` and drives `seihou agent` commands. Its stale-blueprint scenario asserts
that the refusal tells the user to run `seihou upgrade upgrade-helper`. `Seihou.CLI.SeihouBinary.seihouBinary`
locates the built executable.

Relevant ADRs:

- [ADR 0006](../adr/0006-the-install-cache-will-not-silently-substitute-an-artifact.md) — the
  install cache is keyed by bare name, so before overwriting an entry Seihou reads its
  `.seihou-origin.json`. It proceeds silently for the same source URL, compared through
  `Seihou.Core.ArtifactIdentity.normalizeOriginUrl`. It refuses for a different URL or missing
  provenance. `seihou upgrade` passes no override because it reinstalls from the URL the entry
  itself records. A refusal there means the cache disagrees with its own record and must be
  reported as a failure, never suppressed. `publishStagedClosure` and `stageClosuresInto` with
  `force = False` already implement this rule.
- [ADR 0003](../adr/0003-a-stale-or-substituted-artifact-is-a-hard-error.md) — generating from an
  installed artifact older than, or from a different source than, the project's manifest records
  is a hard error. Since ExecPlan 83 this covers `seihou agent run` and `seihou agent migrate`.
  The refusal's remediation text (`Seihou.CLI.ManifestGuard`) is `seihou upgrade <label>`, which
  this plan makes work for blueprints. The guard does not fire for the IR-17 scenario, because no
  manifest recorded the newer version.
- [ADR 0002](../adr/0002-artifact-identity-is-origin-url-plus-name.md) — an artifact's identity is
  its origin URL plus its name, not the bare name. This is why refreshing must use the URL the
  entry records rather than searching anywhere for the name.

No ADR covers which kinds `seihou upgrade` refreshes. The help text and `docs/cli/upgrade.md` are
the only statement of it.


## Plan of Work

The work adds one library module that owns everything blueprint- and prompt-specific. It moves the
upgrade row type into the library so both sides can share it. The executable modules change only
to select, dispatch, and render.


### Milestone 1: refresh a blueprint or prompt closure in the library

At the end of this milestone a library function can refresh selected installed blueprints and
prompts from their recorded sources, without any CLI wiring. A new spec proves it against local
git producers.

First, move the row types. Create `seihou-cli/src/Seihou/CLI/UpgradeReport.hs` with `UpgradeStatus`,
`UpgradeEntry` (and its `ToJSON` instance, unchanged), and `isFailedEntry`, all moved verbatim
from `seihou-cli/src-exe/Seihou/CLI/Upgrade.hs`. Add it to the library's `exposed-modules` in
`seihou-cli/seihou-cli.cabal`, and import it from `Upgrade.hs`. The build must stay green with no
behavior change.

Next, in `seihou-cli/src/Seihou/CLI/InstallClosure.hs`, export the existing private
`readContents :: FilePath -> IO RepoContents`, so the new module classifies a clone with the same
no-fallback rule install uses.

Then create `seihou-cli/src/Seihou/CLI/InstalledRunnables.hs` and add it to `exposed-modules`. It
provides the following.

`selectInstalledRunnables :: [DiscoveredRunnable] -> IO [(DiscoveredRunnable, Maybe OriginInfo)]`
keeps runnables with `source == SourceInstalled` and kind `KindBlueprint` or `KindPrompt`, and
pairs each with `readOriginInfo (dir)`. Include entries with `isError = True`. A broken installed
copy is exactly what a refresh can repair. Define `installKey :: DiscoveredRunnable -> Text` as
`takeFileName (dir)`, the cache key, and
`matchesRequest :: Text -> DiscoveredRunnable -> Bool` as "equals `name` or equals the install
key".

`refreshInstalledRunnables :: RefreshOptions -> FilePath -> [(DiscoveredRunnable, OriginInfo)] ->
IO ([UpgradeEntry], [Text])` takes `RefreshOptions { dryRun :: !Bool, skipUnversioned :: !Bool }`
and the cache root, which callers get from `installedRoot`. It returns the rows plus the names of
every artifact in every staged closure, which the caller uses to keep the module path from
refreshing the same module twice. It works as follows:

1. Group the inputs by `normalizeOriginUrl (origin ^. #sourceUrl)`, keeping the recorded
   `sourceUrl` text of the first member for cloning and for passing as the recorded URL.
2. For each group, clone once into a temporary directory with
   `Seihou.CLI.InstallShared.cloneRepo`. On failure, every member gets a `SourceUnreachable` row
   with its recorded `version` as old. Classify the clone with `readContents`. A
   `seihou-registry.dhall` that fails to evaluate becomes an `UpgradeFailed` row per member.
3. For each member, locate the artifact directory in the clone. For `MultiModule registry`, find
   the entry whose `name` equals the install key in `registry ^. #blueprints` (for
   `KindBlueprint`) or `registry ^. #prompts` (for `KindPrompt`), and use `cloneDir </> path`.
   For `SingleBlueprint root` with `KindBlueprint`, or `SinglePrompt root` with `KindPrompt`, use
   the clone root. Anything else becomes `UpgradeFailed "<kind> '<key>' not found in <url>"`.
4. Stage that member's closure into a fresh temporary *staging cache* with
   `stageClosuresInto False stagingCache False [(cloneDir, recordedUrl, [(key, artifactDir)])]`.
   The staging cache is empty, so no refusal can happen here. Validation errors come back as
   `Left text` and become an `UpgradeFailed text` row for the member.
5. For each returned `ClosureArtifact`, compare `hashArtifactDirectory (artifact ^. #directory)`
   with the hash of `cache </> name`, if that exists. Old version comes from
   `readOriginInfo (cache </> name)`, new version from the artifact's `version`. Decide the
   status exactly as `upgradeRecipes` does in `Upgrade.hs`: changed and skipped (under
   `skipUnversioned`, either side has no version) is `Skipped`, changed is `Upgraded`, and
   unchanged is `AlreadyUpToDate`. If any row in this closure is `Skipped`, turn its `Upgraded`
   rows into `Skipped` so the closure stays together.
6. Unless `dryRun` or the closure was skipped, publish the changed artifacts into the real cache.
   Use `publishStagedClosure cache [ClosureArtifact with directory = staged path]`. On `Left
   message` (an ADR 0006 refusal, which leaves the cache untouched), turn every `Upgraded` row of
   that closure into `UpgradeFailed message`.
7. Print nothing to stdout. The caller renders.

Because publication runs per closure and in sequence, a later closure sees the cache an earlier one
just published. A base module shared by two blueprints is then `AlreadyUpToDate` the second time.
Deduplicate the returned rows by name, keeping the first.

Write `seihou-cli/test/Seihou/CLI/InstalledRunnablesSpec.hs` (testSpec name
`"Seihou.CLI.InstalledRunnables"`), register it in `seihou-cli/test/Main.hs`, and list it in the
cabal test suite. Each case builds a producer git repository in a temporary directory, recorded
as a `file://` URL. Each case installs with `installClosureInto cache False cloneDir url [(key,
dir)]` into an explicit temporary cache, then calls `refreshInstalledRunnables` with that cache.
Use a single-blueprint repository (root `blueprint.dhall`). The `blueprintDhall` text from
`AgentGuardE2ESpec` is a working template. The cases:

- After the producer commits version `0.1.1` over `0.1.0`, the row is `UpgradeEntry key (Just
  "0.1.0") (Just "0.1.1") Upgraded`. The cache's `blueprint.dhall` now contains `0.1.1` and its
  `.seihou-origin.json` records `0.1.1`.
- The same with `dryRun = True` gives the same row, and the cache's bytes are unchanged.
- Run again after a successful refresh, the row is `AlreadyUpToDate`.
- A registry repository with a blueprint whose `baseModules` names a module in the same registry:
  bumping only the module refreshes it through the blueprint's closure (an `Upgraded` row for the
  module, `AlreadyUpToDate` for the blueprint).
- ADR 0006 refusal. In the same registry fixture, rewrite the installed *module's*
  `.seihou-origin.json` to name `file:///elsewhere/other.git`. Write a marker file into that
  module's cache entry, as `InstallCollisionSpec` does. Bump the module and refresh the
  blueprint. The blueprint is fetched from its own recorded URL, so this is the realistic
  disagreement: a cache entry in the closure whose provenance names another source.
  `publishStagedClosure` must refuse. The module's row is `UpgradeFailed`, its text names both
  URLs, and the module's cache entry, marker included, is byte-identical.
- A prompt (root `prompt.dhall`) refreshes the same way. Check the prompt descriptor shape against
  an existing fixture with `rg -l 'prompt.dhall' seihou-cli/test`.

Acceptance: `cabal test seihou-cli-test --test-options='-p "/Seihou.CLI.InstalledRunnables/"'`
passes, and the rest of the suite is unaffected by the type move.


### Milestone 2: wire blueprints and prompts into `seihou upgrade`

At the end of this milestone the command behaves as described in Purpose, and an end-to-end test
drives the real binary through the IR-17 scenario.

In `seihou-cli/src-exe/Seihou/CLI/Upgrade.hs`, `handleUpgrade` changes as follows:

- After computing `recipes`, compute `runnables' <- selectInstalledRunnables runnables`. With no
  requested names, select those with `Just origin`. With names, select those matching a requested
  name.
- Treat a requested name as found if it matches a module with origin, a recipe, or any installed
  blueprint or prompt. Rename the message to `Artifact(s) not found: ...`.
- A requested blueprint or prompt with `Nothing` origin becomes the row `UpgradeFailed "no origin
  metadata in ~/.config/seihou/installed/<key>/.seihou-origin.json; reinstall it with 'seihou
  install <url> --force'"`. ADR 0006: without provenance Seihou cannot know the source.
- Run in this order: recipes (unchanged), then `refreshInstalledRunnables`, then modules. The
  module path's `filtered` list must exclude names covered by either the recipe closures or the
  runnable closures. Concatenate the rows in that order and deduplicate by name, first wins.
- Change the empty message to `No installed modules, recipes, blueprints, or prompts with origin
  metadata found.`
- After rendering and post-upgrade migrations, `exitFailure` if any row is `UpgradeFailed`
  (Decision Log). In `--json` mode, failed rows are still printed first.
- In `upgradeSource` and `doUpgrade`, print the `  Cloning ...` and `    Upgraded ...` lines only
  when `--json` is off (Decision Log). Thread the flag or the whole `UpgradeOpts` through, since
  both are already parameters of their callers.

In `seihou-cli/src-exe/Seihou/CLI/Commands.hs`:

- Change the `upgradeParser` argument's metavar to `ARTIFACT` and its help to `Installed modules,
  recipes, blueprints, or prompts to upgrade (default: all)`.
- In `upgradeFooter`, say it refreshes installed modules, recipe closures, and blueprint and
  prompt closures, and add the example `seihou upgrade my-blueprint  # upgrade a blueprint and its
  baseline modules`.

Write `seihou-cli/test/Seihou/CLI/UpgradeRunnablesE2ESpec.hs` and register it like any spec. Reuse
the `RecipeExtensionE2ESpec` approach: a producer repository `producers/bp` routed from
`https://example.invalid/bp.git` through a `fixture-gitconfig` passed as `GIT_CONFIG_GLOBAL`, with
`HOME` and `XDG_CONFIG_HOME` inside the temporary root. Reuse the `AgentGuardE2ESpec` environment
(fake `claude` on `PATH`, `SEIHOU_AGENT_PROVIDER=claude-cli`, a git-initialized project
directory) for the agent call. Scenario:

1. The producer holds `blueprint.dhall` named `bp` at `0.1.0` with `noBaseModules`. Run
   `seihou install https://example.invalid/bp.git`. It succeeds.
2. Commit `0.1.1` in the producer.
3. `seihou upgrade bp --json` exits 0. Its stdout decodes as a JSON array with an element
   `{"module":"bp","oldVersion":"0.1.0","newVersion":"0.1.1","status":"upgraded"}`.
4. `seihou agent --debug run bp`, run in the project directory, prints `Version: 0.1.1`.
5. `seihou upgrade bp` (text) now exits 0 and shows `up to date`.
6. `seihou upgrade` with no names, after committing `0.1.2` in the producer, includes a `bp` row
   with status `upgraded`, and exits 0.
7. Delete `installed/bp/.seihou-origin.json`, commit `0.1.3`, and run `seihou upgrade bp`. It
   exits 1 with a failed `bp` row containing `no origin metadata`, and
   `installed/bp/blueprint.dhall` is unchanged. Then run `seihou upgrade` with no names. It omits
   `bp`, as it omits unprovenanced modules. The different-source refusal is proven at library
   level in Milestone 1, because an end-to-end version would need a second routed producer and
   would add nothing.

If step 4 turns out to need more than the guard fixture provides, assert instead that
`installed/bp/blueprint.dhall` contains `0.1.1`, and record that in Surprises & Discoveries. One
example of needing more: `--debug run` refusing to start without a manifest.

Also add one case to `seihou-cli/test/Seihou/CLI/AgentGuardE2ESpec.hs` only if it is cheap with
its existing fixture. Otherwise leave that spec alone: its assertion that the refusal names
`seihou upgrade upgrade-helper` is now backed by a working command, and step 3 above proves that
command.

Acceptance: `cabal test seihou-cli-test --test-options='-p "/UpgradeRunnablesE2E/"'` passes, as do
the existing `RecipeExtension` and `agent path artifact guard` groups.


### Milestone 3: `seihou outdated`, documentation, and the full suite

At the end of this milestone `seihou outdated` reports blueprints and prompts, the docs and help
describe the new coverage, and every repository check passes.

In `seihou-cli/src/Seihou/CLI/RemoteVersion.hs`, add `fetchTrueRunnableVersion :: FilePath ->
RunnableKind -> Text -> IO (Either FetchError (Maybe Text))`. `KindModule` delegates to
`fetchTrueModuleVersion`. `KindBlueprint` reads the `version` from `blueprint.dhall`, located as
in Milestone 1 step 3 (registry `blueprints` entry by name, or `SingleBlueprint` root).
`KindPrompt` reads it from `prompt.dhall` (registry `prompts`, or `SinglePrompt` root).
`KindRecipe` returns `Left (RegistryNotFound path)`, because recipes are out of scope for
`outdated` today. Add a `DefinitionNotFound FilePath` constructor to `FetchError` for a missing
descriptor file, with a `renderFetchError` case. Extend `seihou-cli/test/Seihou/CLI/RemoteVersionSpec.hs`
with one blueprint and one prompt case.

In `seihou-cli/src/Seihou/CLI/InstalledRunnables.hs`, add `checkInstalledRunnablesForUpdates ::
Bool -> [(DiscoveredRunnable, OriginInfo)] -> IO [OutdatedEntry]`. The `Bool` means "print
progress". It groups by source URL, clones once per group, and compares the origin's `version`
with `fetchTrueRunnableVersion` through `compareVersions`. A failed clone is `Unreachable`, and a
lookup error collapses to `Nothing` (shown as `unversioned`), as the module check does. In
`seihou-cli/src-exe/Seihou/CLI/Outdated.hs`, `handleOutdated` appends these rows to the module
rows. It passes `not (oopts ^. #outdatedJson)` as the progress flag, renames the table header
`Module` to `Artifact` and the summary to `N artifact(s) checked, M outdated.`, and treats "no
installed modules" as "no installed artifacts" across all three kinds. Leave
`checkInstalledModulesForUpdates` unchanged, since `seihou status` uses it. In `Commands.hs`,
update `outdatedInfo`'s `progDesc` and footer to say modules, blueprints, and prompts.

Update `docs/cli/upgrade.md`:

- Change the usage to `seihou upgrade [ARTIFACT...]`.
- Change the argument table to say modules, recipes, blueprints, or prompts.
- Add a "Blueprint and prompt closures" section. It should say that a blueprint is refreshed
  together with its `baseModules` from the URL its `.seihou-origin.json` records, by content
  comparison, so a same-version fix is picked up. It should say that a refusal under ADR 0006 is a
  failed row and a non-zero exit, and that a named blueprint without provenance must be
  reinstalled with `seihou install <url> --force`.
- Document the new exit status.

Update `docs/cli/outdated.md` to say that blueprints and prompts are checked, and that `outdated`
compares declared versions while `upgrade` compares content. Run `just audit-cli-docs`, which
builds the binary and checks that the docs cover the commands, and fix anything it reports.

Acceptance: `cabal test all` passes, `nix flake check` passes (including the module-placement and
record-convention checks), and `seihou outdated` in the Milestone 2 fixture lists `bp` as
`outdated` after a producer bump.


## Concrete Steps

All commands run from the repository root, `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`
in the author's checkout, unless stated otherwise.

Build and run focused tests while working:

```bash
cabal build all
cabal test seihou-cli-test --test-options='-p "/Seihou.CLI.InstalledRunnables/"'
cabal test seihou-cli-test --test-options='-p "/UpgradeRunnablesE2E/"'
cabal test seihou-cli-test --test-options='-p "/RecipeExtension/"'
cabal test seihou-cli-test --test-options='-p "/agent path artifact guard/"'
```

Before declaring a milestone accepted, run the convention checks and the full suite:

```bash
bash nix/check-cli-module-placement.sh
bash nix/check-record-conventions.sh
cabal test all
nix flake check
```

A manual check against a real repository, after `cabal install` or with
`cabal run exe:seihou --`, in a throwaway `XDG_CONFIG_HOME` so the real cache is untouched:

```bash
export XDG_CONFIG_HOME="$(mktemp -d)"
seihou install https://github.com/shinzui/seihou-modules.git --module relaunch-fumadocs-docs
seihou upgrade relaunch-fumadocs-docs --dry-run
seihou outdated
```

Expected shape of the upgrade output when the installed copy is behind (versions illustrative):

```text
Artifact                 Old    New    Status
relaunch-fumadocs-docs   0.1.0  0.1.1  would upgrade

1 artifact(s) checked, 1 would upgrade.
```

Commit at each milestone boundary with Conventional Commit messages and both trailers, for
example:

```text
feat(upgrade): refresh installed blueprint and prompt closures

ExecPlan: docs/plans/121-refresh-installed-blueprints-and-prompts-in-seihou-upgrade.md
Intention: intention_01m75dyqjsexgvcz1ms2rqs1zn
```


## Validation and Acceptance

The plan is accepted when all of the following hold. Each maps to an IR-17 acceptance criterion.

- After a newer blueprint version is committed to its source, `seihou upgrade` replaces the
  installed copy, and `seihou agent --debug run <name>` shows the new version.
  `UpgradeRunnablesE2ESpec` steps 2–4 prove it.
- `seihou upgrade <blueprint-name>` upgrades that blueprint and exits 0, with a row showing old
  and new versions in text and `--json`. `UpgradeRunnablesE2ESpec` steps 3 and 5 prove it.
- A blueprint whose cache entry names a different source is refused, with the cache
  byte-identical (`InstalledRunnablesSpec`). A named blueprint without provenance is refused with
  exit 1 (`UpgradeRunnablesE2ESpec` step 7).
- `seihou outdated` lists an installed blueprint whose source declares a newer version (Milestone 3
  acceptance).
- `docs/cli/upgrade.md`, `docs/cli/outdated.md`, `seihou upgrade --help`, and
  `seihou outdated --help` mention blueprints and prompts. `just audit-cli-docs` is clean.

Regression evidence: `RecipeExtensionE2ESpec` still parses `seihou upgrade --json` output and
passes, so the JSON contract is unchanged. `cabal test all` and `nix flake check` pass.

Out of scope, and not required for acceptance: refreshing blueprints in `seihou status`'s
update hints; suggesting `seihou agent migrate` after a blueprint upgrade raises a version a
project recorded; a `kind` field in upgrade JSON; and the pre-existing progress lines that
`seihou outdated --json` prints for modules.


## Idempotence and Recovery

Every step is additive and safe to repeat. `seihou upgrade` is idempotent by construction: a second
run finds equal hashes and reports `up to date`. Publication goes through `publishStagedClosure`,
which moves each existing entry into a `.seihou-transaction` directory inside the cache before
copying, and rolls back on a handled failure. An interrupted run leaves either the old or the new
entry plus recovery data under `~/.config/seihou/installed/.seihou-transaction*`. Tests use
temporary caches only. For manual checks, set `XDG_CONFIG_HOME` to a temporary directory as shown
above so the real cache is never touched. If the type move in Milestone 1 breaks the build midway,
`git checkout -- seihou-cli/src-exe/Seihou/CLI/Upgrade.hs` and redo the move. It is a pure
relocation.


## Interfaces and Dependencies

No new dependencies. The work uses these existing interfaces, by full module path:

- `Seihou.CLI.InstallClosure.stageClosuresInto :: Bool -> FilePath -> Bool -> [(FilePath, Text,
  [(Text, FilePath)])] -> IO (Either Text [ClosureArtifact])`, and
  `publishStagedClosure :: FilePath -> [ClosureArtifact] -> IO (Either Text ())`. Also
  `readContents :: FilePath -> IO RepoContents`, newly exported.
- `Seihou.CLI.InstallShared.cloneRepo`, `installedRoot`, `readOriginInfo`, `OriginInfo`.
- `Seihou.CLI.Update.Source.hashArtifactDirectory :: FilePath -> IO SHA256`.
- `Seihou.CLI.VersionCompare.compareVersions`, `OutdatedEntry`, `OutdatedStatus`.
- `Seihou.Core.Module.discoverAllRunnables`, `DiscoveredRunnable`, `RunnableKind`, `ModuleSource`.
- `Seihou.Core.Registry.Registry` (`blueprints`, `prompts`), `RegistryEntry`, `RepoContents`.
- `Seihou.Core.ArtifactIdentity.normalizeOriginUrl`.
- `Seihou.Dhall.Eval.evalBlueprintFromFile`, `evalAgentPromptFromFile`.

New interfaces at the end of the plan:

```haskell
-- seihou-cli/src/Seihou/CLI/UpgradeReport.hs (moved from src-exe/Seihou/CLI/Upgrade.hs)
data UpgradeStatus = Upgraded | AlreadyUpToDate | Skipped | UpgradeFailed Text | SourceUnreachable
data UpgradeEntry = UpgradeEntry
  { moduleName :: !Text, oldVersion :: !(Maybe Text), newVersion :: !(Maybe Text), upgradeStatus :: !UpgradeStatus }
isFailedEntry :: UpgradeEntry -> Bool

-- seihou-cli/src/Seihou/CLI/InstalledRunnables.hs
data RefreshOptions = RefreshOptions { dryRun :: !Bool, skipUnversioned :: !Bool }
selectInstalledRunnables :: [DiscoveredRunnable] -> IO [(DiscoveredRunnable, Maybe OriginInfo)]
installKey :: DiscoveredRunnable -> Text
matchesRequest :: Text -> DiscoveredRunnable -> Bool
refreshInstalledRunnables :: RefreshOptions -> FilePath -> [(DiscoveredRunnable, OriginInfo)] -> IO ([UpgradeEntry], [Text])
checkInstalledRunnablesForUpdates :: Bool -> [(DiscoveredRunnable, OriginInfo)] -> IO [OutdatedEntry]

-- seihou-cli/src/Seihou/CLI/RemoteVersion.hs (added)
fetchTrueRunnableVersion :: FilePath -> RunnableKind -> Text -> IO (Either FetchError (Maybe Text))
-- FetchError gains: DefinitionNotFound FilePath
```

All three modules are in the `seihou-cli-internal` library (`seihou-cli/src/`). None imports
`Options.Applicative` or `Seihou.CLI.Commands`, so the module-placement check accepts them.
`Seihou.CLI.Upgrade` and `Seihou.CLI.Outdated` stay in `src-exe/` because they import
`Seihou.CLI.Commands`.
