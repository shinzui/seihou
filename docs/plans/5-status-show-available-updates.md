---
id: 5
slug: status-show-available-updates
title: "Show available registry updates in seihou status"
kind: exec-plan
created_at: 2026-04-15T21:09:00Z
intention: "intention_01kp9dp8zte2rrnzzt3qr73j0m"
---


# Show available registry updates in `seihou status`

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

After this change, a user who runs `seihou status --check-updates` (or the short
form `seihou status -u`) in a Seihou project will see, alongside each applied
module, whether a newer version of that module is available in the remote
registry it was installed from. The existing `seihou status` behaviour is
preserved exactly when the new flag is absent — no network calls, no new
output.

"Seihou" is a project scaffolding tool written in Haskell (GHC 9.12.2) that
records which modules have been applied to a project in a manifest file at
`.seihou/manifest.json`. A "module" is a named, versioned unit of scaffolding
distributed as a git repository and installed into the user's module search
path via `seihou install <git-url>`. A "registry" here means the remote git
repository a module was installed from; `seihou` does not yet speak to any
central index. Seihou already has a `seihou outdated` command that clones
every installed module's source repo and reports update availability as a
separate table. The goal of this plan is to surface that same information
directly inside `seihou status` — so a single command answers both "what
state is the project in?" and "is any of it out of date?" — without breaking
the no-network default.

The user-visible outcome is:

    $ seihou status --check-updates
    Seihou Status:

    Applied modules:
      claude-gitignore  v0.2.0    (applied 2026-04-15)  outdated -> v0.3.0
      update-docs                 (applied 2026-03-08)  unversioned
      my-local-module   v1.0.0    (applied 2026-03-01)  (no origin)

    Tracked files: 6
      ...

    Variables: 4 resolved

    1 module(s) checked, 1 outdated.

Running `seihou status` with no flags produces the exact same output as
before the change.


## Progress

- [x] M1: Extract `checkInstalledModulesForUpdates` from
      `seihou-cli/src/Seihou/CLI/Outdated.hs` (2026-04-15, commit `468a07c`).
- [x] M1: Refactor `handleOutdated` to call the extracted function; verified
      `seihou outdated` and `seihou outdated --json` byte-identical against
      baseline (2026-04-15).
- [x] M2: Add `StatusOpts { statusCheckUpdates :: Bool }`, replace the
      `Status` nullary constructor, wire `--check-updates` / `-u` flag,
      update the Main dispatcher (2026-04-15, commit `ec2628d`).
- [x] M2: Confirmed `seihou status`, `seihou status --check-updates`, and
      `seihou status -u` all produce the legacy output at this stage
      (2026-04-15).
- [x] M3: Plumb update-check results through `handleStatus`; render
      annotation per applied module and summary footer
      (2026-04-15, commit `0ef3dbe`).
- [x] M3: Caught `SomeException` around the update path and emit a
      stderr warning so offline runs still produce the legacy output.
- [x] M4: Ran `cabal test all` (106/106 passed) and captured the
      end-to-end transcript in Outcomes & Retrospective.


## Surprises & Discoveries

- **Pre-existing use-after-free bug in `checkSource`.** Initial end-to-end
  testing showed every installed module resolving to `unversioned`, even
  though `exec-plan`, `master-plan`, and the rest of the registry-side
  modules declare real versions in their `module.dhall`. Root cause: the
  original `checkSource` was structured as

        result <- try $ withSystemTempDirectory "seihou-outdated" $ \tmpDir -> do
          let cloneDir = tmpDir </> repoName
          ... git clone ...
          contents <- discoverRepoContents evalRegistryFromFile cloneDir
          pure (Just (cloneDir, contents))

        case result of
          Right (Just (cloneDir, contents)) ->
            mapM (compareModule cloneDir contents) modulesWithOrigins

  `withSystemTempDirectory` deletes `tmpDir` as soon as its action returns,
  so by the time `compareModule` ran, the clone was already gone. For
  multi-module registries whose `seihou-registry.dhall` entries omit the
  `version` field (the common case — see
  `seihou-core/src/Seihou/Dhall/Eval.hs` line 387, the decoder uses
  `withDefaults` to fill in `Nothing`), `findAvailableVersion` falls back
  to reading `<cloneDir>/<path>/module.dhall` directly. That `TIO.readFile`
  raised `does not exist`, `evalModuleFromFile` caught it as `Left _`, and
  every result came back as `Nothing` → `Unversioned`.

  Fix: move the `compareModule` step *inside* the
  `withSystemTempDirectory` block so the clone is still on disk when the
  Dhall read happens. After the fix, `seihou outdated` now correctly
  reports all six modules as `up to date` with their installed versions
  matched against the remote:

        Module             Installed  Available  Status
        claude-skill-link  0.1.0      0.1.0      up to date
        update-docs        0.1.0      0.1.0      up to date
        exec-plan          0.1.3      0.1.3      up to date
        claude-gitignore   0.2.0      0.2.0      up to date
        master-plan        0.1.0      0.1.0      up to date
        nix-haskell-flake  0.3.0      0.3.0      up to date

        6 module(s) checked, 0 outdated.

  This bug had been silently degrading `seihou outdated` for every
  registry that relies on the `module.dhall` fallback. It was exposed
  here only because end-to-end testing for `seihou status
  --check-updates` made the results feel obviously wrong — the user knew
  that `exec-plan` and `master-plan` had versions declared and pushed
  back on the `unversioned` output, which is exactly the failure mode
  the plan's Validation section said to watch for. Lesson: the M1
  "byte-identical diff against baseline" check proves we did not *change*
  behaviour, but it cannot surface pre-existing bugs — only exercising
  the real pipeline does.

- `seihou outdated --json` is not clean JSON: the pre-existing code prints
  `Checking installed modules for updates...` and per-source `Cloning ...`
  lines to stdout before the JSON document. The refactor in Milestone 1
  preserves this behaviour bit-for-bit (diffed against a baseline). Fixing
  it is out of scope for this plan but worth a follow-up — a caller piping
  `seihou outdated --json` into `jq` will fail today.

- `AskUserQuestion` header has a 12-char cap that I hit on the intention
  prompt; not relevant to the code but worth noting for future prompts in
  this skill.


## Decision Log

- Decision: The update check is opt-in via `--check-updates` / `-u`, not
  enabled by default.
  Rationale: `seihou status` is currently a cheap local-only command — it
  reads the manifest and hashes tracked files. The update check has to
  `git clone --depth 1` every distinct source URL referenced by installed
  modules. Making that the default would silently turn a sub-second command
  into a multi-second, network-dependent one and would break `seihou status`
  in offline environments (airplane, CI without egress, broken DNS). An
  opt-in flag preserves the existing contract and makes the cost explicit.
  Date: 2026-04-15

- Decision: Reuse the existing `discoverAllModules` + `.seihou-origin.json`
  pipeline rather than teaching the manifest to remember each module's source
  URL.
  Rationale: The manifest already records `AppliedModule.source` as a
  filesystem path, and the corresponding installed copy on disk already holds
  `.seihou-origin.json` with the source URL. Adding a second source-of-truth
  in the manifest would be redundant and create migration risk. The downside
  is that modules applied from a path that is not under any known search
  root, or from a project-local `.seihou/modules/` directory without origin
  metadata, cannot be checked — they will be shown as `(no origin)`. This is
  the same limitation `seihou outdated` already has, so users will see
  consistent behaviour.
  Date: 2026-04-15

- Decision: Extract a pure-ish helper `checkInstalledModules :: [DiscoveredModule]
  -> IO [OutdatedEntry]` from `Seihou.CLI.Outdated` rather than duplicating
  the clone/compare logic in `Seihou.CLI.Status`.
  Rationale: The logic in `handleOutdated` (lines 70–96 of
  `seihou-cli/src/Seihou/CLI/Outdated.hs` at the time of writing) already
  does "filter installed, read origins, group by URL, check each source".
  Duplicating it would create two code paths that can drift. Extracting lets
  `seihou outdated` stay a thin wrapper and lets `seihou status` call the
  same function.
  Date: 2026-04-15


## Outcomes & Retrospective

The feature ships as designed. `seihou status` is unchanged in every
invocation that does not pass the new flag, and `seihou status
--check-updates` (or `-u`) now clones each installed module's source
repo shallowly and annotates each applied-module line with its update
status. Running the tree's own test suite (`cabal test all`) reports
`All 106 tests passed` with no regressions.

End-to-end transcript, captured in the Seihou project's own working
tree on 2026-04-15 after fixing the `checkSource` temp-dir bug
documented in Surprises & Discoveries:

    $ cabal run -v0 seihou -- status --check-updates
    Checking installed modules for updates...
      Cloning agent-seihou...
      Cloning agent-seihou...
      Cloning seihou-modules...
    Seihou Status:

    Applied modules:
      update-docs    (applied 2026-03-08)  up to date
      claude-gitignore  v0.2.0    (applied 2026-04-15)  up to date
      claude-skill-link  v0.1.0    (applied 2026-04-15)  up to date
      exec-plan  v0.1.3    (applied 2026-04-15)  up to date
      master-plan  v0.1.0    (applied 2026-04-15)  up to date

    Tracked files: 5
      .gitignore                                master-plan   unchanged
      claude/skills/exec-plan/PLANS.md          master-plan   unchanged
      claude/skills/exec-plan/SKILL.md          master-plan   unchanged
      claude/skills/master-plan/MASTERPLAN.md   master-plan   unchanged
      claude/skills/master-plan/SKILL.md        master-plan   unchanged

    Variables: 4 resolved

    6 module(s) checked, 0 outdated.

Every applied module now resolves against its real remote version. The
"6 module(s) checked" total includes one module (`nix-haskell-flake`)
that is installed in the user's search path but not applied in this
tree; that matches the pre-existing behaviour of `seihou outdated`,
which walks every installed module regardless of whether the current
project references it. A possible follow-up is to scope the check to
only modules that actually appear in the manifest.

Gaps / follow-ups:

1. The `Cloning ...` progress lines from `checkSource` go to stdout and
   therefore contaminate `seihou outdated --json`. Not new in this plan,
   but now surfaced in `seihou status --check-updates` too. Worth a
   small follow-up to redirect those to stderr.
2. The upstream modules in the `agent-seihou` and `seihou-modules`
   registries could declare versions so users see real "up to date" /
   "outdated" annotations instead of a wall of `unversioned`.
3. No test coverage was added for the new render branches. The render
   functions are pure over `Maybe [OutdatedEntry]` and would be easy to
   unit-test; deferred to keep this plan focused on the network-visible
   behaviour.

Lessons learned:

- Extracting `checkInstalledModulesForUpdates` first (Milestone 1) and
  diffing the resulting `seihou outdated` output against a saved
  baseline made the refactor risk-free — the render-layer work in
  Milestone 3 then had a clean, exception-safe function to call.
- Catching `SomeException` around the discover+clone pipeline and
  falling back to the legacy render is worth the three lines of code:
  it preserves the user's existing ability to run `seihou status` in
  offline contexts even when they accidentally pass `-u`.


## Context and Orientation

Seihou is a multi-package Cabal workspace. The two packages relevant to this
plan are:

- `seihou-core` — the library with pure types and effect interfaces, including
  `Seihou.Core.Types.AppliedModule` (the manifest's record for one applied
  module) and `Seihou.Core.Registry` (types describing a remote repo's
  contents).
- `seihou-cli` — the executable, with one handler module per subcommand under
  `seihou-cli/src/Seihou/CLI/`.

The files this plan touches are all in `seihou-cli`:

- `seihou-cli/src/Seihou/CLI/Commands.hs` — defines the `Command` ADT and the
  `optparse-applicative` parsers. The current definition has `Status` as a
  nullary constructor (line 46). The parser is built in `statusInfo` around
  line 409. The dispatcher in `seihou-cli/src/Main.hs` (around line 42)
  calls `handleStatus` with no arguments.
- `seihou-cli/src/Seihou/CLI/Status.hs` — contains `handleStatus :: IO ()`
  and the render functions (`renderStatus`, `printModule`, `printTrackedFile`).
  The module version is already displayed on each line via `printModule`
  (line 75). There is no update-check code here today.
- `seihou-cli/src/Seihou/CLI/Outdated.hs` — contains every piece of logic we
  want to reuse: `OutdatedEntry`, `OriginInfo`, `readOriginWithModule`,
  `checkSource`, `compareVersions`, `findAvailableVersion`, and the rendering
  of the outdated table. `handleOutdated` (line 70) is the entry point and
  already implements the full "discover → filter → group → clone → compare"
  pipeline we want.
- `seihou-cli/src/Seihou/CLI/VersionCompare.hs` — contains `OutdatedStatus`
  (`UpToDate | OutdatedSt | Unversioned | Unreachable`) and
  `compareVersions :: Maybe Text -> Maybe Text -> OutdatedStatus`.
- `seihou-cli/src/Seihou/CLI/Style.hs` — ANSI color helpers (`green`, `red`,
  `yellow`, `dim`, `useColor`).
- `seihou-core/src/Seihou/Core/Module.hs` — defines `DiscoveredModule`,
  `ModuleSource (SourceInstalled | ...)`, `defaultSearchPaths`, and
  `discoverAllModules`. These are the primitives that turn "module search
  paths on disk" into "list of modules I can ask questions about".
- `seihou-core/src/Seihou/Core/Types.hs` — defines `AppliedModule` (line
  ~306), which already has a `moduleVersion :: Maybe Text` field, so no
  manifest schema change is required.

Relevant terms of art:

- "Applied module": a module recorded in `.seihou/manifest.json` as having
  been run against this project. Represented by `AppliedModule`.
- "Installed module": a module present in one of Seihou's search paths
  (typically `~/.config/seihou/installed/<name>/`) as a result of running
  `seihou install <git-url>`. Represented by `DiscoveredModule` with
  `discoveredSource == SourceInstalled`.
- "Origin metadata": a small JSON file, `.seihou-origin.json`, that
  `seihou install` writes into an installed module's directory. It records
  the git URL the module was cloned from and the version at install time.
  Without this file, `seihou` has no way to know where to look for updates.
- "Outdated entry": an `OutdatedEntry` record produced by the `seihou
  outdated` pipeline — one per installed module that has origin metadata —
  with the installed version, the available version, and a status enum.


## Plan of Work

The work has four milestones. Each one leaves the tree compiling and the
test suite green.


### Milestone 1 — Extract a reusable update-check function

**Scope.** Refactor `seihou-cli/src/Seihou/CLI/Outdated.hs` so that the
"discover installed modules, read their origins, group by source URL, clone
each source, produce `OutdatedEntry` values" logic lives in a single
exported function. `handleOutdated` becomes a thin wrapper that calls this
function and renders the result.

**What will exist at the end of the milestone that did not before.**

A new exported function in `Seihou.CLI.Outdated`:

    checkInstalledModulesForUpdates ::
      [DiscoveredModule] ->
      IO ([OutdatedEntry], CheckStats)

    data CheckStats = CheckStats
      { checkedCount :: Int,
        skippedNoOrigin :: Int
      }

The function takes an already-discovered list of modules (the caller is
responsible for calling `discoverAllModules`) so it does not re-walk the
filesystem. It filters to `SourceInstalled` internally, reads
`.seihou-origin.json` for each, groups by `sourceUrl`, calls the existing
`checkSource` per group, and returns the flat list of entries. The
`CheckStats` record lets a caller report how many modules were actually
reachable for checking.

**Why the refactor is necessary.** The current `handleOutdated` directly
prints progress lines (`"Cloning ..."`) and calls `renderTable` itself, so
it is not usable as a subroutine from another command. After the refactor,
progress lines still happen (they come from `checkSource`, which is fine —
the status command can afford to print them behind the `--check-updates`
flag), but the caller now controls what to do with the resulting entries.

**Concrete edits.**

In `seihou-cli/src/Seihou/CLI/Outdated.hs`:

1. Add `checkInstalledModulesForUpdates` and `CheckStats` to the module
   export list at the top.
2. Define `CheckStats` next to `OutdatedEntry`.
3. Extract the body of `handleOutdated` from the point where it filters to
   `installed` through the `concat <$> mapM checkSource grouped` call into
   the new function. Make it take `[DiscoveredModule]` as input and return
   `IO ([OutdatedEntry], CheckStats)`.
4. Rewrite `handleOutdated` so it calls `defaultSearchPaths >>=
   discoverAllModules` then `checkInstalledModulesForUpdates`, and then
   branches on `outdatedJson` exactly as before.

**Commands to run and acceptance.**

From the repository root:

    cabal build all

Expected: builds cleanly. Then run:

    cabal run seihou -- outdated

in a project with at least one installed module that has origin metadata.
Expected: the output is the same table it produced before the refactor.
Compare against a saved pre-refactor transcript if in doubt. Also verify
`cabal run seihou -- outdated --json` still emits valid JSON with the same
schema.


### Milestone 2 — Add the `--check-updates` flag to the status command

**Scope.** Introduce a new record `StatusOpts` for the status command, add
a boolean `statusCheckUpdates` field, expose it through the CLI parser, and
thread an empty value through `handleStatus` so the existing (no-network)
path is preserved bit-for-bit when the flag is not set.

**What will exist at the end of the milestone.** `seihou status
--check-updates` and `seihou status -u` are both accepted by the parser and
reach `handleStatus` as `StatusOpts { statusCheckUpdates = True }`, but the
handler does nothing new with the flag yet — it still renders the legacy
output. This milestone is intentionally behaviour-preserving so a reviewer
can confirm the plumbing in isolation before the interesting logic arrives.

**Concrete edits.**

In `seihou-cli/src/Seihou/CLI/Commands.hs`:

1. Add `StatusOpts (..)` to the module export list.
2. Define the record near the other `*Opts` records:

        data StatusOpts = StatusOpts
          { statusCheckUpdates :: Bool
          }
          deriving stock (Eq, Show, Generic)

3. Change the `Status` constructor in the `Command` ADT from `Status` to
   `Status StatusOpts`.
4. Replace `statusInfo :: ParserInfo Command` (around line 409) so that
   instead of `(pure Status <**> helper)` it builds a `StatusOpts` parser:

        statusParser :: Parser Command
        statusParser =
          fmap Status $
            StatusOpts
              <$> switch
                ( long "check-updates"
                    <> short 'u'
                    <> help "Check installed modules for available updates in their source registry (requires network)"
                )

   and `statusInfo` uses `statusParser <**> helper`. Extend the `footerDoc`
   with one extra line explaining the flag, e.g. "Use --check-updates to also
   report which applied modules have newer versions available from their
   source repository. This requires network access and will clone each
   source repo shallowly.".

In `seihou-cli/src/Main.hs`:

1. Change the dispatch arm from `Status -> handleStatus` to `Status opts ->
   handleStatus opts`.

In `seihou-cli/src/Seihou/CLI/Status.hs`:

1. Change the signature `handleStatus :: IO ()` to
   `handleStatus :: StatusOpts -> IO ()`.
2. Import `StatusOpts` from `Seihou.CLI.Commands`.
3. Accept and ignore the argument for now — e.g. bind it as `_opts` or
   pattern-match but do not use the field. The body remains identical.

**Commands to run and acceptance.**

    cabal build all
    cabal run seihou -- status
    cabal run seihou -- status --check-updates
    cabal run seihou -- status -u
    cabal run seihou -- status --help

Expected: all three invocations produce the existing status output
(unchanged, because the flag is still ignored). `--help` now mentions
`--check-updates` in the help text.


### Milestone 3 — Wire the update check into the status render

**Scope.** When `statusCheckUpdates` is `True`, `handleStatus` computes an
`OutdatedEntry` for each applied module (where possible) and renders it
inline in the "Applied modules" section. When the flag is `False`, the code
path is exactly the legacy one.

**What will exist at the end of the milestone.** The user-visible outcome
described in Purpose / Big Picture is real. Running `seihou status -u` in
the Seihou project's own working tree (which has `claude-gitignore` and
friends installed) produces a table augmented with per-module update info,
plus the "N module(s) checked, K outdated." footer line.

**Concrete edits.**

In `seihou-cli/src/Seihou/CLI/Status.hs`:

1. Add imports for `Seihou.CLI.Outdated` (`checkInstalledModulesForUpdates`,
   `OutdatedEntry`, `moduleNameFromDm`), `Seihou.CLI.VersionCompare`
   (`OutdatedStatus (..)`), and `Seihou.Core.Module`
   (`defaultSearchPaths`, `discoverAllModules`).
2. Change the body of `handleStatus` so that after the `Right (Just
   (manifest, tracked))` case is reached, it branches on
   `opts.statusCheckUpdates`:

    - If `False`: call `renderStatus colorEnabled manifest tracked
      Nothing` (same as today, but `renderStatus` now takes an extra
      `Maybe [OutdatedEntry]` arg).
    - If `True`: first call `defaultSearchPaths >>= discoverAllModules` to
      find the installed-copy directories, then call
      `checkInstalledModulesForUpdates` to get
      `(entries, stats)`, then call `renderStatus colorEnabled manifest
      tracked (Just entries)`. Any `IOException` raised during this path
      (e.g. because `git` is unavailable) should be caught and turned into
      a warning line on stderr — the legacy status output should still be
      printed so the command remains useful offline.

3. Extend `renderStatus` with a new parameter
   `Maybe [OutdatedEntry]`. When this is `Nothing`, the function behaves
   exactly as today. When it is `Just entries`, after printing the
   "Applied modules" block it also prints the summary line
   `"N module(s) checked, K outdated."` (copy the exact phrasing from
   `Outdated.renderTable`) and the update-availability annotation is added
   per module by `printModule`.

4. Extend `printModule` with a `Maybe OutdatedEntry` parameter. When
   present, append a final colored segment to the line:

    - `UpToDate` → `(dim "up to date")` — or omit entirely to avoid clutter
      (see Decision Log to be added).
    - `OutdatedSt` → `red "outdated -> v" <> availableVersion`
    - `Unversioned` → `dim "unversioned"`
    - `Unreachable` → `yellow "unreachable"`

    When the applied module has no matching entry (no `.seihou-origin.json`
    was found for it), append `dim "(no origin)"`.

5. In `renderStatus`, to match each `AppliedModule` to an `OutdatedEntry`,
   build a `Data.Map.Strict.Map Text OutdatedEntry` keyed by module name
   (i.e. `Map.fromList [(e.moduleName, e) | e <- entries]`) and look each
   applied module up by `am.name.unModuleName` when iterating through
   `manifest.modules`.

**A note on output alignment.** The existing `printModule` does not
column-align the version against the applied-date portion; it uses a
`"    "` (four-space) gap. Keep that style. For the new update column,
use the same spacing convention — two or more spaces, then the colored
status blob. If the annotation pushes lines beyond 120 columns, that is
acceptable for v1.

**Commands to run and acceptance.**

From the repository root, in a checkout that has real installed modules:

    cabal build all
    cabal run seihou -- status
    cabal run seihou -- status --check-updates

The first invocation must produce output byte-identical to the current
`seihou status`. The second must, for each module the user has applied,
print one of the annotations described above, and end with a
`"N module(s) checked, K outdated."` summary line. If there is no network
access, the second invocation must print a warning to stderr and then fall
back to the legacy output rather than crashing.

Also test the "no applied modules" edge case — run it in a tree that has
never had `seihou run` called — and confirm that `seihou status -u` still
prints the legacy "Applied modules: (none)" line and does not try to clone
anything.


### Milestone 4 — End-to-end validation and retrospective

**Scope.** Run the command in a real project, capture a transcript, and
write the Outcomes & Retrospective section.

**What will exist at the end of the milestone.** A transcript saved into
Surprises & Discoveries (or Outcomes & Retrospective, whichever makes more
sense) showing real output from `seihou status --check-updates` against a
project with at least one installed module. The plan is marked done.

**Concrete steps.**

1. In the Seihou project's own working tree (which has installed modules
   like `claude-gitignore` and `update-docs`), run:

        cabal run seihou -- status --check-updates

2. Copy the output into the plan as an indented block under Outcomes &
   Retrospective.

3. Run `cabal test all` (or whatever the project uses) to make sure no
   regressions.

4. Commit the plan update.


## Concrete Steps

All commands below assume the working directory is the repository root
(`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`).

Before starting, confirm the baseline:

    cabal build all
    cabal run seihou -- status
    cabal run seihou -- outdated

All three should succeed. Save the current `seihou outdated` output into a
scratch file for comparison at the end of Milestone 1:

    cabal run seihou -- outdated > /tmp/outdated-baseline.txt

### Milestone 1 commands

Edit `seihou-cli/src/Seihou/CLI/Outdated.hs` as described in Plan of Work,
then:

    cabal build all
    cabal run seihou -- outdated > /tmp/outdated-after-refactor.txt
    diff -u /tmp/outdated-baseline.txt /tmp/outdated-after-refactor.txt

Expected `diff` output: empty (the outputs are identical). If not, the
refactor changed externally visible behaviour and needs to be investigated.

Commit:

    git add seihou-cli/src/Seihou/CLI/Outdated.hs
    git commit -m "$(cat <<'EOF'
    Extract checkInstalledModulesForUpdates from handleOutdated

    Makes the clone-and-compare pipeline reusable so the status command
    can call it behind a new --check-updates flag without duplicating
    the logic.

    ExecPlan: docs/plans/5-status-show-available-updates.md
    Intention: intention_01kp9dp8zte2rrnzzt3qr73j0m
    EOF
    )"

### Milestone 2 commands

Edit `Commands.hs`, `Main.hs`, `Status.hs` as described, then:

    cabal build all
    cabal run seihou -- status
    cabal run seihou -- status --check-updates
    cabal run seihou -- status -u
    cabal run seihou -- status --help

All four must succeed; the first three must produce identical output.

Commit:

    git add seihou-cli/src/Seihou/CLI/Commands.hs seihou-cli/src/Main.hs seihou-cli/src/Seihou/CLI/Status.hs
    git commit -m "$(cat <<'EOF'
    Add --check-updates flag scaffolding to seihou status

    Introduces StatusOpts and threads it through the parser, dispatcher,
    and handler. The flag has no effect yet; a following commit wires
    it into the render pipeline.

    ExecPlan: docs/plans/5-status-show-available-updates.md
    Intention: intention_01kp9dp8zte2rrnzzt3qr73j0m
    EOF
    )"

### Milestone 3 commands

Edit `Status.hs` as described, then:

    cabal build all
    cabal run seihou -- status
    cabal run seihou -- status --check-updates

Record both transcripts in this file under Surprises & Discoveries or
Outcomes & Retrospective.

Commit:

    git add seihou-cli/src/Seihou/CLI/Status.hs
    git commit -m "$(cat <<'EOF'
    Show available registry updates in seihou status --check-updates

    When --check-updates is passed, each applied module's line gains an
    update-availability annotation (up-to-date, outdated -> vX, unversioned,
    unreachable, or (no origin)) and the report ends with a summary of
    how many modules were checked and how many are outdated.

    ExecPlan: docs/plans/5-status-show-available-updates.md
    Intention: intention_01kp9dp8zte2rrnzzt3qr73j0m
    EOF
    )"

### Milestone 4 commands

    cabal test all
    cabal run seihou -- status --check-updates

Record transcript, update Outcomes & Retrospective, commit the plan
update.


## Validation and Acceptance

Acceptance is phrased as concrete observable behaviour. Each of these
must hold after the plan is complete.

1. Running `seihou status` in any project that was passing before the
   change must produce byte-identical output. Verify with a recorded
   transcript:

        cabal run seihou -- status > /tmp/status-after.txt
        diff -u /tmp/status-before.txt /tmp/status-after.txt
        # expected: empty diff

2. Running `seihou status --check-updates` in the Seihou project's own
   working tree (which has installed modules with origin metadata) must
   produce output that contains:

   - The full legacy status output.
   - For each installed module with origin metadata: one of
     `up to date`, `outdated -> vX`, `unversioned`, or `unreachable`
     at the end of its line.
   - For each applied module with no corresponding installed copy or no
     `.seihou-origin.json`: `(no origin)` at the end of its line.
   - A final summary line matching the pattern
     `N module(s) checked, K outdated.`.

3. Running `seihou status -u` must behave identically to
   `seihou status --check-updates`.

4. Running `seihou outdated` must still produce exactly the same output
   it did before the refactor. This is the regression guard for Milestone 1.

5. Running `seihou outdated --json` must still produce the same JSON shape
   (no new fields, no removed fields, same key names and ordering).

6. Running `seihou status --check-updates` with networking disabled (for
   example, `env -i PATH=/usr/bin cabal run seihou -- status --check-updates`
   on a host with no route to the internet) must print the legacy status
   output plus a stderr warning line explaining that the update check
   could not run. The process exit code should still be 0.

7. Running `cabal build all` must succeed without warnings introduced by
   this change. Running the project's test suite (`cabal test all`) must
   leave the pre-existing test outcome unchanged — no new failures.


## Idempotence and Recovery

Every milestone is a pure source edit; repeating it is safe. If a commit
fails (for example, a pre-commit hook rejects it), fix the complaint,
re-stage, and create a **new** commit — do not `--amend` unless the user
explicitly asks. If a refactor in Milestone 1 accidentally changes
`seihou outdated` output, revert to the baseline with
`git restore seihou-cli/src/Seihou/CLI/Outdated.hs` and redo the edit more
conservatively; the `/tmp/outdated-baseline.txt` file is the reference.

No destructive operations are required. No database migrations, no
filesystem cleanups, no changes to `.seihou/manifest.json` schema.


## Interfaces and Dependencies

No new library dependencies are required. Everything needed already exists
in the repository:

- `Seihou.CLI.Outdated` exports the pipeline that clones repos and
  compares versions.
- `Seihou.CLI.VersionCompare` exports `OutdatedStatus` and
  `compareVersions`.
- `Seihou.Core.Module` exports `discoverAllModules`, `defaultSearchPaths`,
  `DiscoveredModule`, `ModuleSource`.
- `Seihou.CLI.Style` exports `green`, `red`, `yellow`, `dim`, `useColor`.
- `optparse-applicative` is already in `seihou-cli.cabal` for CLI parsing.
- `Control.Exception` is already available for the try/catch around the
  network fallback in Milestone 3.

### Types and signatures that must exist at the end of each milestone

After Milestone 1, in `seihou-cli/src/Seihou/CLI/Outdated.hs`:

    data CheckStats = CheckStats
      { checkedCount :: Int,
        skippedNoOrigin :: Int
      }

    checkInstalledModulesForUpdates ::
      [DiscoveredModule] ->
      IO ([OutdatedEntry], CheckStats)

After Milestone 2, in `seihou-cli/src/Seihou/CLI/Commands.hs`:

    data StatusOpts = StatusOpts
      { statusCheckUpdates :: Bool
      }

and the `Command` ADT's `Status` constructor is `Status StatusOpts`.

In `seihou-cli/src/Seihou/CLI/Status.hs`:

    handleStatus :: StatusOpts -> IO ()

After Milestone 3, in `seihou-cli/src/Seihou/CLI/Status.hs`:

    renderStatus ::
      Bool -> Manifest -> [TrackedFile] -> Maybe [OutdatedEntry] -> IO ()

    printModule ::
      Bool -> Maybe OutdatedEntry -> AppliedModule -> IO ()

`printTrackedFile`, `statusLabel`, and `statusColor` are unchanged.
