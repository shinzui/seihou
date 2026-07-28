---
id: 80
slug: document-and-end-to-end-verify-the-shared-manifest-workflow
title: "Document and end-to-end verify the shared-manifest workflow"
kind: exec-plan
created_at: 2026-07-28T01:48:18Z
intention: "intention_01kyk6fnbyegxss8fqnf3j03tf"
master_plan: "docs/masterplans/9-make-the-seihou-manifest-multi-developer-safe.md"
---

# Document and end-to-end verify the shared-manifest workflow

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

Four earlier plans in this initiative changed how seihou records and reads
`.seihou/manifest.json` — the JSON file inside each project that records which modules
seihou applied, at which versions, and which files it generated, and which teams check into
git. Together they made the manifest machine-independent, made every command resolve
artifacts locally, made seihou refuse to silently downgrade a module, and gave existing
projects a way to convert their old manifests.

Those are four separate mechanisms. This plan turns them into one workflow a team can
actually follow, and proves the workflow works.

The proof is an automated end-to-end test that drives the real `seihou` binary twice against
one project tree using two different fake home directories. Developer A generates and
commits. Developer B — with an older module installed — pulls and runs. The test asserts
that B is refused, that nothing on disk changed, that `--allow-downgrade` proceeds when B
insists, and that after B upgrades their local copy the ordinary run succeeds. That test is
what stops all four mechanisms from quietly regressing.

The documentation is a new user guide, `docs/user/teams.md`, answering the questions a team
adopting seihou actually has: what do we commit, what does each developer need installed,
what happens when someone is out of date, and what do we do with a project whose manifest
predates all this.

You can see the outcome by running the new test:

```bash
cabal test seihou-cli-test --test-options='--pattern "shared manifest"'
```

and by reading `docs/user/teams.md`, linked from the guide list in `README.md`.

This plan also performs the initiative's ADR distillation pass, promoting durable decisions
from all five plans into `docs/adr/`.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] Milestone 1: `TwoDeveloperFixture` builds a project plus two independent fake homes (2026-07-28)
- [x] Milestone 2: End-to-end test — A generates, B is refused, nothing changed on disk (2026-07-28)
- [x] Milestone 2: End-to-end test — `--allow-downgrade` proceeds and says so (2026-07-28)
- [x] Milestone 2: End-to-end test — B upgrades locally and the ordinary run succeeds (2026-07-28) — asserts the generated file is untouched and only the manifest's timestamps move; see Surprises & Discoveries
- [x] Milestone 2: End-to-end test — a legacy manifest is rejected, upgraded, then usable (2026-07-28)
- [x] Milestone 2: Deliberate-breakage check proves the test bites (2026-07-28)
- [x] Milestone 3: Regression test asserting no absolute path can appear in a written manifest (2026-07-28)
- [x] Milestone 4: `docs/user/teams.md` written and linked from `README.md` (2026-07-28) — walkthrough run verbatim; see Concrete Steps
- [x] Milestone 4: `docs/user/CHANGELOG.md` entry covering the whole initiative (2026-07-28)
- [x] Milestone 4: `docs/dev/architecture/overview.md` manifest section updated (2026-07-28) — and `docs/dev/design/proposed/manifest-and-incrementality.md`, whose schema sample still showed version 1 with `source` paths
- [ ] Milestone 5: ADR distillation pass across all five plans complete


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- **A re-run is a no-op for the project but never for the manifest.** Scenario
  three was written to assert an empty `git status --porcelain` after developer
  B upgrades and re-runs, on the reasoning that regenerating from the same
  version with the same inputs changes nothing. It changes exactly four fields.
  Every `seihou run` stamps a fresh timestamp into the manifest whether or not
  any content moved.

  Evidence, from a hand-run of the same scenario outside the suite — two
  consecutive `seihou run demo` invocations against an unchanged 2.0.0 module,
  diffed field by field:

  ```text
  DIFF /generatedAt                    '…T04:51:29.638022Z' -> '…T04:51:29.715206Z'
  DIFF /modules/0/appliedAt            '…T04:51:29.638022Z' -> '…T04:51:29.715206Z'
  DIFF /applications/0/appliedAt       '…T04:51:29.638022Z' -> '…T04:51:29.715206Z'
  DIFF /files/README.md/generatedAt    '…T04:51:29.638022Z' -> '…T04:51:29.715206Z'
  ```

  Nothing else differs — not the recorded version, not the file hash, not the
  origin. So the assertion is now that the *generated file* is byte-identical
  and that `.seihou/manifest.json` is the only path git reports. That is the
  honest claim, and it still fails if a re-run rewrites the README.

  This is worth knowing beyond the test: a team that runs seihou in CI will see
  a manifest diff on every run even when nothing changed. Whether that is worth
  fixing is out of scope here, but it is recorded in
  `docs/user/teams.md` so it does not surprise anybody.

- **The deliberate-breakage check fails earlier than the plan predicted, and in
  two scenarios rather than one.** Validation and Acceptance expected scenario
  one to fail on the `git status --porcelain` assertion. With
  `enforceArtifactGuard runOpts (blockingChecks guardChecks)` in
  `seihou-cli/src-exe/Seihou/CLI/Run.hs:292` replaced by
  `enforceArtifactGuard runOpts []`, it fails one assertion earlier — on the
  exit code, since hspec stops at the first failed expectation — and scenario
  two fails too, because the `--allow-downgrade` override notice is no longer
  printed:

  ```text
  records a portable manifest and refuses a stale developer: FAIL
    predicate failed on: ExitSuccess
  proceeds under --allow-downgrade and says so:              FAIL
    predicate failed on: "Generation Plan (demo):\n\n  Variables:\n …"
  ```

  Both scenarios bite, which is the point. Restoring the line returns all four
  to green.

- **The whole-document sweep needed no exception.** Milestone 3 warned that
  asserting "no string value anywhere begins with `/`" might be too strict for
  a legitimate field and offered to narrow it. It is not too strict. A manifest
  populated in every serialized string position — parent variables, a file
  record keyed by destination with a baseline reference, a command receipt with
  a `workDir`, a removal spec with `dest` and `src`, an applied recipe, an
  applied blueprint with a user prompt, and a blueprint migration receipt —
  contains no absolute path anywhere, so the assertion is the unqualified one.
  Object *keys* are swept too, which is what covers the `files` map's
  destination paths.

  Deliberately breaking it by adding
  `"source" .= ("/Users/shinzui/.config/seihou/installed/haskell-base" :: Text)`
  to the `ToJSON AppliedModule` instance produces exactly the message the plan
  asked for — the offending JSON path, not a bare `False`:

  ```text
  records no machine-specific value anywhere in the document: FAIL
    expected: []
     but got: ["$.modules[0].source = /Users/shinzui/.config/seihou/installed/haskell-base"]
  ```

- **Running the guide's own walkthrough found two commands that did not work.**
  Validation and Acceptance says "if a command in the guide does not work as
  written, the guide is wrong". Both were in the first draft and both are fixed.

  `sed -i '' 's/…/…/' module.dhall` — the BSD idiom for in-place editing —
  fails on a machine whose `sed` is GNU sed, because GNU's `-i` takes its
  suffix attached and reads `''` as the script:

  ```text
  sed: can't read s/Some "1.0.0"/Some "2.0.0"/: No such file or directory
  ```

  A guide should not make the reader guess which `sed` they have, so the
  walkthrough now defines a `write_demo <version>` shell function that rewrites
  the module and its template from a heredoc. Publishing a version happens
  twice in the walkthrough, so the function is shorter than the edit it
  replaces.

  The second was a workflow error, not a syntax one. The draft had Ana run
  `seihou upgrade demo` and then `seihou run demo`, which is what the guide's
  own prose implied. `run` refuses:

  ```text
  Pending migrations detected:
    demo: 1.0.0 -> 2.0.0 (0 step(s))

  For a recorded project application, run 'seihou update <target>'.
  ```

  `seihou upgrade` refreshes the installed copy; `seihou update` is what
  carries the *project* forward to it. The walkthrough now uses `update`, which
  is also what `docs/user/migrations.md` says. Worth noting for anyone writing
  team-facing docs: `upgrade` and `run` are not a pair.


## Decision Log

Record every decision made while working on the plan.

- Decision: Simulate two developers with two `XDG_CONFIG_HOME` values against one project
  directory, rather than with two containers or two checkouts.
  Rationale: The variable that actually differs between developers, as far as seihou is
  concerned, is where `getXdgDirectory XdgConfig "seihou"` points — that single root
  determines both `~/.config/seihou/modules/` and `~/.config/seihou/installed/`. The
  existing end-to-end suite at `seihou-cli/test/Seihou/CLI/UpdateE2ESpec.hs` already drives
  the real binary with an overridden `XDG_CONFIG_HOME`, so this reuses a proven harness
  instead of inventing an isolation mechanism.
  Date: 2026-07-28

- Decision: Assert on `git status --porcelain` being empty after a refusal, not merely on
  the exit status.
  Rationale: The bug this initiative exists to prevent is a silent write. An exit status
  proves the command reported failure; only an unchanged working tree proves it did not
  write first. Asserting on the tree is what makes the test meaningful.
  Date: 2026-07-28


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose. Before marking the plan complete,
distill durable project context from the Decision Log, Surprises & Discoveries, and
this section into docs/adr/. Keep task-local execution details here.

(To be filled during and after implementation.)


## Context and Orientation

This section assumes no prior knowledge of the repository.

**The repository layout.** `seihou` is a Haskell project built with Cabal, targeting GHC
9.12.2 and the `GHC2024` language edition. `cabal.project` defines three packages:
`seihou-core` (types, Dhall loading, generation engine, manifest handling), `seihou-cli`
(a library at `seihou-cli/src/` called `seihou-cli-internal` plus an executable at
`seihou-cli/src-exe/` called `seihou`), and `seihou-okf-extension`. `CLAUDE.md` at the
repository root sets the module-placement rule (new CLI code in `seihou-cli/src/` unless it
needs `Options.Applicative`, `Data.FileEmbed`, `GitHash`, or `Paths_seihou_cli`) and the
record conventions (strict fields, `generic-lens` labels, no record update syntax, explicit
`deriving stock` including `Generic`), both enforced mechanically by
`nix/check-cli-module-placement.sh` and `nix/check-record-conventions.sh` in `nix flake
check` and the pre-commit hook.

**What the four earlier plans delivered.** All four must be complete before this plan
starts. Each is self-contained and can be read for detail; the summary here is what this
plan depends on.

`docs/plans/76-record-portable-artifact-origins-in-the-manifest.md` added
`ArtifactOrigin` to `seihou-core/src/Seihou/Core/Types.hs`:

```haskell
data ArtifactOrigin
  = RemoteOrigin { originUrl :: !Text, artifactName :: !Text, repoName :: !(Maybe Text) }
  | ProjectOrigin { relativePath :: !FilePath }
  | LocalOrigin { artifactName :: !Text }
  deriving stock (Eq, Ord, Show, Generic)
```

`RemoteOrigin` means the artifact was installed by `seihou install` from a git URL into
`~/.config/seihou/installed/<name>/`, with the URL recorded in a `.seihou-origin.json` file
beside it. `ProjectOrigin` means the artifact lives inside the project under
`.seihou/modules/<name>`, stored relative to the project root. `LocalOrigin` means the
artifact came from the developer's personal `~/.config/seihou/modules/` directory, which has
no provenance metadata. Plan 76 attached these to the manifest records, bumped
`currentManifestVersion` in `seihou-core/src/Seihou/Manifest/Types.hs` from 5 to 6, and
stopped serializing absolute paths. It also created `docs/adr/` with the initiative's first
two records.

`docs/plans/77-resolve-manifest-artifact-origins-to-local-directories.md` added
`seihou-core/src/Seihou/Core/ArtifactRef.hs` with
`resolveArtifactOrigin :: FilePath -> [FilePath] -> FilePath -> ArtifactOrigin -> IO (Either ArtifactRefError FilePath)`
and `renderArtifactRefError :: ArtifactRefError -> Text`, and rewired every command that
previously read a manifest-recorded path.

`docs/plans/78-refuse-accidental-module-downgrades-and-origin-mismatches.md` added
`seihou-cli/src/Seihou/CLI/ManifestGuard.hs` with `checkAppliedArtifacts`,
`blockingChecks`, and `formatGuardRefusal`, wired into `seihou run`, `seihou update`, and
`seihou migrate`, plus an `--allow-downgrade` flag on each.

`docs/plans/79-upgrade-legacy-absolute-path-manifests-in-place.md` added the
`seihou manifest upgrade` command with `--dry-run`, converting schema-5-and-earlier
manifests into schema 6.

**The existing end-to-end test harness.** `seihou-cli/test/Seihou/CLI/UpdateE2ESpec.hs`
already drives the real binary. Two helpers at the bottom of that file are the pattern to
follow:

```haskell
seihouBinary :: IO FilePath
seihouBinary = do
  testBinary <- getExecutablePath
  pure (takeDirectory (takeDirectory testBinary) </> "seihou" </> "seihou")

runSeihou :: FilePath -> UpdateFixture -> [String] -> IO (ExitCode, T.Text, T.Text)
runSeihou binary fixture args = do
  inherited <- getEnvironment
  let environment = ("XDG_CONFIG_HOME", fixture ^. #xdgHome) : filter ((/= "XDG_CONFIG_HOME") . fst) inherited
  runProcessText binary args (Just (fixture ^. #projectRoot)) (Just environment)
```

The test suite can locate the binary because `seihou-cli/seihou-cli.cabal`'s
`test-suite seihou-cli-test` stanza declares `build-tool-depends: seihou-cli:seihou`, which
makes Cabal build the executable before running the tests and put it in a predictable place
relative to the test binary.

The fixture it uses, `UpdateFixture`, is built by `prepareUpdateFixture` in
`seihou-cli/test/Seihou/CLI/UpdateSpec.hs` and carries `projectRoot`, `projectFile`,
`manifestPath`, `installedModule`, `remote`, and `xdgHome`. Read both files before writing
the new fixture; the new one is the same idea with *two* `xdgHome` values.

Tests are registered in two places: the `other-modules` list of the `test-suite
seihou-cli-test` stanza in `seihou-cli/seihou-cli.cabal`, and `seihou-cli/test/Main.hs`,
which imports each spec module qualified and adds its `tests :: IO TestTree` to a list.
Every spec module follows the shape:

```haskell
tests :: IO TestTree
tests = testSpec "Human readable group name" spec
```

using `Test.Tasty.Hspec.testSpec`.

**The documentation layout.** User guides live in `docs/user/` and are listed twice in
`README.md` — once in a prose feature summary around line 86 and once in a "Guides" list
around line 178. `docs/user/CHANGELOG.md` is a curated user-facing changelog with an
`## Unreleased` section containing `### Added` / `### Changed` / `### Fixed` subsections and
worked examples in fenced blocks; the repository-root `CHANGELOG.md` is the full engineering
log. Developer documentation lives in `docs/dev/`, with the system overview at
`docs/dev/architecture/overview.md`, whose manifest discussion is around line 732 and whose
effect table at line 105 names `ManifestStore` as reading and writing
`.seihou/manifest.json`.

There is also a `seihou-update-docs` skill at `claude/skills/seihou-update-docs/` that
compares `docs/user/CHANGELOG.md` against git history to find undocumented changes; running
it at the end of this plan is a good cross-check that nothing from the initiative was missed.

**Architecture Decision Records.** `docs/adr/` exists after plan 76 and holds at least the
two records that plan created. Read `agents/skills/exec-plan/ADR.md` in full before
Milestone 5 — it governs numbering, status vocabulary, heading structure, and whether the
directory is a plain-filesystem corpus or a profile-governed bundle requiring strict
enforcement. Follow it exactly; do not invent a format.

**Build and test commands.** From the repository root:

```bash
cabal build all
cabal test all
nix flake check
```

To run just the CLI suite, or a single group within it:

```bash
cabal test seihou-cli-test
cabal test seihou-cli-test --test-options='--pattern "shared manifest"'
```

The `--pattern` option comes from `tasty`, which the suite uses as its test driver.


## Plan of Work

Five milestones.

### Milestone 1 — a two-developer fixture

Create `seihou-cli/test/Seihou/CLI/TwoDeveloperFixture.hs`, registered in the
`other-modules` list of the `test-suite seihou-cli-test` stanza in
`seihou-cli/seihou-cli.cabal`. It is a fixture module, not a spec, so it exports no `tests`
and is not added to `seihou-cli/test/Main.hs` — `seihou-cli/test/Seihou/CLI/UpdateFixture.hs`
is the existing precedent for that arrangement.

```haskell
-- | One project shared by two simulated developers, each with their own
-- seihou configuration root.
--
-- Both developers work in the same @projectRoot@ — that is the point,
-- since it models a git checkout they both have. What differs is
-- @homeA@ and @homeB@, each of which becomes @XDG_CONFIG_HOME@ for that
-- developer's invocations, so each has an independent
-- @<home>/seihou/installed/@ and @<home>/seihou/modules/@.
data TwoDeveloperFixture = TwoDeveloperFixture
  { projectRoot :: !FilePath,
    manifestPath :: !FilePath,
    homeA :: !FilePath,
    homeB :: !FilePath,
    moduleName :: !Text
  }
  deriving stock (Eq, Show, Generic)

-- | Build the fixture under @root@. Installs the named module at
-- @versionA@ into developer A's root and at @versionB@ into developer B's,
-- both carrying the same @.seihou-origin.json@ source URL, and initialises
-- @projectRoot@ as a git repository with an initial commit so working-tree
-- assertions are meaningful.
prepareTwoDeveloperFixture ::
  FilePath ->
  -- | version installed for developer A
  Text ->
  -- | version installed for developer B
  Text ->
  IO TwoDeveloperFixture
```

Write the module `module.dhall` bodies from a small template inside the fixture, varying
only the declared version and generating one file so a run has a visible effect. Copy the
schema import line from an existing fixture rather than from documentation —
`prepareUpdateFixture` in `seihou-cli/test/Seihou/CLI/UpdateSpec.hs` already writes a valid
`module.dhall`, and reusing its exact import line keeps this test working when the schema
pin moves. Read that function first and mirror it.

Give both installed copies a `.seihou-origin.json` with the same `sourceUrl`
(`https://example.com/demo-modules.git` is fine — nothing is fetched) and differing
`version` values. The exact shape is written by `installModuleDir` in
`seihou-cli/src/Seihou/CLI/InstallShared.hs`; read `OriginMeta`'s `ToJSON` instance there for
the authoritative key names.

Initialise git in `projectRoot` with `callProcess "git"`, following the pattern already used
in `seihou-cli/test/Seihou/CLI/UpdateE2ESpec.hs` around line 70 (`init -q`, `config
user.name`, `config user.email`, `add .`, `commit -qm`). The `user.name` and `user.email`
config are required because CI environments have no global git identity.

Add `seihouBinary` and a `runSeihouAs :: FilePath -> TwoDeveloperFixture -> FilePath -> [String] -> IO (ExitCode, Text, Text)`
helper taking the binary, the fixture, the chosen home directory, and the arguments. Do not
import the private helpers from `UpdateE2ESpec`; copy them, because that module does not
export them and widening its export list to serve a different test would couple two
unrelated specs.

### Milestone 2 — the end-to-end test

Create `seihou-cli/test/Seihou/CLI/SharedManifestE2ESpec.hs`, registered in
`seihou-cli/seihou-cli.cabal`'s `other-modules` and in `seihou-cli/test/Main.hs`. Its group
name must contain the words `shared manifest` so the `--pattern` invocation in Purpose /
Big Picture selects it:

```haskell
tests :: IO TestTree
tests = testSpec "shared manifest across developers" spec
```

Write four scenarios.

**Scenario one: the manifest developer A writes is portable and B is refused.** Prepare the
fixture with A on `2.0.0` and B on `1.4.0`. Run `["run", "demo"]` as A and assert it
succeeds. Read `.seihou/manifest.json` and assert two things: that it contains
`"kind":"remote"` and the fixture's source URL, and that no JSON string value anywhere in
the document begins with the fixture's `homeA` prefix. Commit the result with git. Then run
`["run", "demo"]` as B and assert the exit code is a failure, that stderr or stdout contains
`2.0.0`, `1.4.0`, and the string `seihou upgrade`, and — the assertion that matters most —
that `git status --porcelain` in `projectRoot` is empty. An empty working tree proves the
guard fired before any write.

**Scenario two: `--allow-downgrade` proceeds and is visible.** From the same state, run
`["run", "demo", "--allow-downgrade"]` as B, assert success, assert the output still names
both versions (a deliberate downgrade must not be silent), and assert the manifest now
records `1.4.0`.

**Scenario three: B upgrades locally and the ordinary run succeeds.** Reset the project with
`git checkout -- .` and `git clean -fd`, replace developer B's installed module with the
`2.0.0` body, and run `["run", "demo"]` as B. Assert success, an empty `git status
--porcelain` (regenerating from the same version at the same inputs should be a no-op), and
that the manifest still records `2.0.0`.

**Scenario four: a legacy manifest is rejected, upgraded, then usable.** Overwrite
`.seihou/manifest.json` with a hand-written schema-5 document whose `modules[0].source` is an
absolute path under a third, non-existent home directory — `/Users/someone-else/.config/seihou/installed/demo`
is a good choice because it belongs to neither developer. Run `["status"]` as B and assert a
failure whose output contains `schema version 5` and `seihou manifest upgrade`. Run
`["manifest", "upgrade", "--dry-run"]` as B, assert success, assert the report names the
legacy path and the inferred origin, and assert the manifest file is byte-identical to before
the dry run. Then run `["manifest", "upgrade"]`, assert success, assert the manifest now
contains `"kind":"remote"` and no longer contains `someone-else`, and finally run
`["status"]` again and assert it now succeeds.

Keep every assertion on message content loose enough to survive wording tweaks — match on the
distinguishing substrings (`2.0.0`, `seihou upgrade`, `schema version 5`) rather than on
whole sentences. `UpdateE2ESpec` uses `T.isInfixOf` with `shouldSatisfy` for exactly this
reason; follow it.

Each scenario wraps in `withSystemTempDirectory` from `System.IO.Temp` so nothing leaks
between tests, matching `UpdateE2ESpec`.

### Milestone 3 — the no-absolute-paths regression test

Scenario one asserts the manifest contains no path under `homeA`, which catches the specific
regression this initiative fixes. Add a stronger, structural version that catches *any*
future field that leaks a path.

In `seihou-core/test/Seihou/Manifest/TypesSpec.hs`, add a test that constructs a `Manifest`
populated with one `AppliedModule`, one `AppliedComposition` holding one
`AppliedInstanceState`, one `FileRecord`, one `CommandReceipt`, and one
`AppliedBlueprintMigration`, encodes it with `manifestToJSON`, decodes the bytes back to an
`Aeson.Value`, and walks the whole document asserting that no string value anywhere begins
with `'/'` **except** under the `"files"` key, where destination paths are project-relative
and could legitimately begin with a slash only if a module declared an absolute destination —
which `checkSafeDestinations` in `seihou-core/src/Seihou/Core/Module.hs` already forbids, so
in practice they never do. Simplify by asserting no string value anywhere begins with `'/'`,
and if that turns out to be too strict for a legitimate field, narrow it and record why in
Surprises & Discoveries.

Write a clear failure message: a bare `False` assertion tells a future contributor nothing.
Make the expectation report which JSON path held the offending value.

### Milestone 4 — the user guide and the changelog

Write `docs/user/teams.md`. Its audience is a team lead adopting seihou, not a seihou
developer. Answer, in prose with worked examples:

*What to commit.* `.seihou/manifest.json` yes, and explain why — it is what makes
regeneration incremental and what tells a reviewer which module version produced the
generated files. `.seihou/baselines/` — check what that directory actually contains and
whether it should be committed by reading
`seihou-core/src/Seihou/Effect/BaselineStoreInterp.hs` and
`docs/plans/65-store-generated-baselines-and-perform-three-way-merges.md`, and give a
definite answer with a reason rather than hedging. `.seihou/modules/` yes, if the team keeps
project-local modules. Give a `.gitignore` snippet for anything that should be excluded.

*What each developer needs.* The modules the manifest records, installed at the recorded
version or newer. Show `seihou status` as the way to find out what is missing or stale, and
`seihou install <url>` and `seihou upgrade <name>` as the remedies.

*What happens when someone is out of date.* Show the actual refusal message and explain each
part of it. Explain `--allow-downgrade` and when using it is legitimate — deliberately
pinning a project back — and when it is not.

*What an origin mismatch means.* Two modules with the same name from different repositories.
Show the message and explain that the fix is to install from the URL the manifest records.

*Migrating an existing project.* Point at `seihou manifest upgrade`, show the `--dry-run`
report, and explain that the resulting diff should be reviewed and committed like any other
change. Say plainly that manifests written before this feature cannot be read until they are
upgraded.

*A worked two-developer walkthrough*, mirroring the end-to-end test: A upgrades a module and
commits; B pulls, is refused, upgrades locally, and succeeds.

Link it from `README.md` in both places — the prose feature summary around line 86 and the
"Guides" list around line 178 — with a one-line description matching the style of the
neighbouring entries.

Add a `docs/user/CHANGELOG.md` entry under `## Unreleased`, covering the whole initiative
rather than one plan. It belongs under both `### Added` (the `seihou manifest upgrade`
command, the `--allow-downgrade` flag, the downgrade refusal) and `### Changed` (the manifest
schema is now version 6 and records portable origins instead of absolute paths; manifests
from earlier versions must be upgraded before use). Follow the existing entries' style:
a bold lead sentence, a short explanation, and a fenced example. Be explicit that this is a
breaking change for existing manifests and name the command that fixes it.

Update `docs/dev/architecture/overview.md`. Its manifest discussion around line 732 lists
what the manifest tracks; add that artifact references are portable origins and that the
manifest is machine-independent by design, with a pointer to the relevant ADR. Check whether
`docs/dev/design/proposed/manifest-and-incrementality.md` (referenced at line 751) needs the
same update.

Finally, run the documentation cross-check skill at `claude/skills/seihou-update-docs/` and
address anything it surfaces from this initiative that is still undocumented.

### Milestone 5 — the ADR distillation pass

This is the initiative's closing step, required by `agents/skills/exec-plan/PLANS.md` and
`agents/skills/master-plan/MASTERPLAN.md` before the parent MasterPlan at
`docs/masterplans/9-make-the-seihou-manifest-multi-developer-safe.md` can be marked complete.

Read `agents/skills/exec-plan/ADR.md` first and follow its workflow exactly.

Read the Decision Log, Surprises & Discoveries, and Outcomes & Retrospective of all five
plans — `docs/plans/76-record-portable-artifact-origins-in-the-manifest.md`,
`docs/plans/77-resolve-manifest-artifact-origins-to-local-directories.md`,
`docs/plans/78-refuse-accidental-module-downgrades-and-origin-mismatches.md`,
`docs/plans/79-upgrade-legacy-absolute-path-manifests-in-place.md`, and this one — plus the
MasterPlan's own Decision Log.

Update the two ADRs plan 76 created with anything implementation revealed. Create new ADRs
for durable decisions that emerged and are not yet recorded. Likely candidates, based on what
the plans decided going in:

The downgrade policy — hard error with an explicit opt-out, no auto-fetch — is a durable
product stance, not a task detail. It will be re-litigated by a future contributor unless the
reasoning is recorded.

The choice to keep the manifest as the single source of truth rather than introducing a
separate lockfile is a deliberate exclusion that shapes future design, and the MasterPlan's
Vision & Scope states it. A deliberate exclusion is exactly the kind of thing
`agents/skills/exec-plan/ADR.md` says belongs in an ADR.

Whatever rule the implementation settled on for how long legacy manifests remain convertible,
and whether the `< 6` guard is permanent or eventually removed, deserves a record so a future
contributor knows whether deleting the legacy decoder is safe.

Leave task-local execution details in the plans; promote only what will still matter after
the plans are closed.

Then update the MasterPlan: mark this plan Complete in its Exec-Plan Registry, check off the
remaining Progress entries, and fill in its Outcomes & Retrospective comparing the delivered
result against the original Vision & Scope.


## Concrete Steps

All commands run from the repository root,
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`.

Confirm all four prerequisite plans are complete:

```bash
grep -n "data ArtifactOrigin" seihou-core/src/Seihou/Core/Types.hs
ls seihou-core/src/Seihou/Core/ArtifactRef.hs
ls seihou-cli/src/Seihou/CLI/ManifestGuard.hs
ls seihou-cli/src/Seihou/CLI/ManifestUpgrade.hs
grep -n "currentManifestVersion = " seihou-core/src/Seihou/Manifest/Types.hs
ls docs/adr/
```

Expected: every path exists and the version constant reads `6`. If any is missing, this plan
is blocked on the corresponding earlier plan.

Read the existing harness before writing the new fixture:

```bash
sed -n '160,185p' seihou-cli/test/Seihou/CLI/UpdateE2ESpec.hs
grep -n "prepareUpdateFixture" -A 60 seihou-cli/test/Seihou/CLI/UpdateSpec.hs
```

Confirm the flags and command names the test will drive actually exist:

```bash
cabal run seihou -- run --help
cabal run seihou -- manifest upgrade --help
```

Expected: `run --help` lists `--allow-downgrade`; `manifest upgrade --help` lists
`--dry-run`. If either is missing, the corresponding plan is incomplete.

Run the new test as you build it:

```bash
cabal test seihou-cli-test --test-options='--pattern "shared manifest"'
```

After each milestone:

```bash
cabal build all && cabal test all
```

Before committing:

```bash
nix flake check
```

The `docs/user/teams.md` walkthrough was run verbatim, from an empty
`/tmp/seihou-teams`, before the guide was committed. Every stated output
appeared. The parts worth keeping as evidence:

```text
$ python3 -c "import json;d=json.load(open('.seihou/manifest.json'));print(d['modules'][0]['origin'])"
{"artifact": "demo", "kind": "remote", "url": "/tmp/seihou-teams/demo-modules"}

$ XDG_CONFIG_HOME=/tmp/seihou-teams/ben seihou run demo
✗ Refusing to run: your local copy of 'demo' is older than the
  version this project expects.

  Recorded in .seihou/manifest.json:  2.0.0
  Installed on this machine:          1.0.0
  Origin: /tmp/seihou-teams/demo-modules

  Update your local copy first:
    seihou upgrade demo

To proceed anyway — pinning this project to what is installed here —
re-run with --allow-downgrade.

$ git status --porcelain
$

$ XDG_CONFIG_HOME=/tmp/seihou-teams/ben seihou status
…
Artifacts that differ from what this project records:
  demo: this project expects 2.0.0 but 1.0.0 is installed here (run 'seihou upgrade demo')

$ XDG_CONFIG_HOME=/tmp/seihou-teams/ben seihou upgrade demo
Module  Old    New    Status
demo    1.0.0  2.0.0  upgraded

$ XDG_CONFIG_HOME=/tmp/seihou-teams/ben seihou run demo
  0 files to write, 0 conflicts
0 new, 0 modified, 1 unchanged.
$ cat README.md
# shared

generated by demo 2.0.0
```

Two commands in the first draft of the guide did not work as written and were
rewritten; see Surprises & Discoveries.

Commit with all three trailers:

```text
test(cli): prove the shared-manifest workflow across two simulated developers

Drive the real binary twice against one project with two XDG_CONFIG_HOME
roots: developer A generates and commits, developer B is refused with a
stale local module and an unchanged working tree, --allow-downgrade
proceeds, and a legacy manifest upgrades cleanly.

MasterPlan: docs/masterplans/9-make-the-seihou-manifest-multi-developer-safe.md
ExecPlan: docs/plans/80-document-and-end-to-end-verify-the-shared-manifest-workflow.md
Intention: intention_01kyk6fnbyegxss8fqnf3j03tf
```


## Validation and Acceptance

The primary acceptance is the new test passing:

```bash
cabal test seihou-cli-test --test-options='--pattern "shared manifest"'
```

Expected output ends with all four scenarios passing:

```text
shared manifest across developers
  records a portable manifest and refuses a stale developer:            OK
  proceeds under --allow-downgrade and says so:                         OK
  succeeds once the stale developer upgrades locally:                   OK
  rejects, upgrades, and then accepts a legacy manifest:                OK

All 4 tests passed
```

Prove the test is meaningful rather than vacuous, by checking that it fails when the
behaviour it guards is removed. Temporarily disable the downgrade guard — comment out the
`blockingChecks` call in `seihou-cli/src-exe/Seihou/CLI/Run.hs` — rebuild, and re-run.
Expected: scenario one fails on the `git status --porcelain` assertion, because the
regeneration wrote files. Restore the guard, rebuild, and confirm the suite is green again.
Record the failing output in Surprises & Discoveries as evidence that the test bites.

Do the same for Milestone 3's regression test: temporarily re-add a `"source"` key holding an
absolute path to one of the encoders in `seihou-core/src/Seihou/Manifest/Types.hs`, run
`cabal test seihou-core-test`, confirm the new test fails and names the offending JSON path,
then revert.

The full suite must be green:

```bash
cabal test all
nix flake check
```

Documentation acceptance is by reading. `docs/user/teams.md` must answer every question
listed in Milestone 4, must link from both places in `README.md`, and must contain a worked
two-developer walkthrough whose commands a reader can actually run. Verify the walkthrough by
following it yourself in a scratch directory — if a command in the guide does not work as
written, the guide is wrong.

Finally, confirm the initiative's headline claim end to end by hand, outside the test suite,
because a hand-run is what a user will do:

```bash
rm -rf /tmp/seihou-teams && mkdir -p /tmp/seihou-teams
```

then follow `docs/user/teams.md`'s walkthrough verbatim and confirm every stated output
appears. Paste the transcript into Concrete Steps as evidence.


## Idempotence and Recovery

Every test scenario runs inside `withSystemTempDirectory`, so repeated runs are independent
and leave nothing behind. Every invocation of the binary sets `XDG_CONFIG_HOME` to a
directory inside that temporary tree, so the real `~/.config/seihou/` is never touched — this
matters, because the tests install modules and a leaked write would corrupt the developer's
own seihou installation. Verify that no code path in the new fixture omits the override.

The deliberate-breakage checks in Validation and Acceptance modify source files. Do them one
at a time, revert with `git checkout -- <file>` immediately after observing the failure, and
never commit while a guard is disabled. Rebuild and confirm green before moving on.

Documentation edits are ordinary file edits, revertible with git.

Milestone 5's ADR work is additive — it creates or updates files under `docs/adr/` — and is
revertible. If `agents/skills/exec-plan/ADR.md` describes the corpus as profile-governed with
strict validation, run whatever validation it specifies before committing; a malformed ADR
that fails validation is easier to fix before it is committed than after.

The scratch directory `/tmp/seihou-teams` used for the manual walkthrough is disposable:
`rm -rf /tmp/seihou-teams`.


## Interfaces and Dependencies

No new package dependencies. The `test-suite seihou-cli-test` stanza in
`seihou-cli/seihou-cli.cabal` already depends on `directory`, `filepath`, `process`,
`temporary` (via `System.IO.Temp` — confirm the dependency is listed; `UpdateE2ESpec` already
imports it), `hspec`, `tasty`, `tasty-hspec`, `text`, `bytestring`, `aeson`,
`seihou-cli-internal`, and `seihou-core`, and declares
`build-tool-depends: seihou-cli:seihou` so the executable is available to the tests.

At the end of Milestone 1, these must exist in
`seihou-cli/test/Seihou/CLI/TwoDeveloperFixture.hs`:

```haskell
data TwoDeveloperFixture = TwoDeveloperFixture
  { projectRoot :: !FilePath,
    manifestPath :: !FilePath,
    homeA :: !FilePath,
    homeB :: !FilePath,
    moduleName :: !Text
  }
  deriving stock (Eq, Show, Generic)

prepareTwoDeveloperFixture :: FilePath -> Text -> Text -> IO TwoDeveloperFixture
seihouBinary :: IO FilePath
runSeihouAs :: FilePath -> TwoDeveloperFixture -> FilePath -> [String] -> IO (ExitCode, Text, Text)
```

This plan consumes, and must not change, the interfaces owned by the four earlier plans:
`ArtifactOrigin` and `currentManifestVersion` from
`docs/plans/76-record-portable-artifact-origins-in-the-manifest.md`;
`resolveArtifactOrigin` and `renderArtifactRefError` from
`docs/plans/77-resolve-manifest-artifact-origins-to-local-directories.md`;
`formatGuardRefusal` and the `--allow-downgrade` flag from
`docs/plans/78-refuse-accidental-module-downgrades-and-origin-mismatches.md`; and the
`seihou manifest upgrade` command and its report format from
`docs/plans/79-upgrade-legacy-absolute-path-manifests-in-place.md`. This plan asserts on the
user-visible *output* of the last two, which makes their message wording a contract: if a
later change rewords the refusal or the upgrade report, this test must be updated in the same
change, and the wording change recorded in the parent MasterPlan's Decision Log at
`docs/masterplans/9-make-the-seihou-manifest-multi-developer-safe.md`.

Nothing downstream depends on this plan; it is the initiative's terminal plan.
