---
id: 76
slug: record-portable-artifact-origins-in-the-manifest
title: "Record portable artifact origins in the manifest"
kind: exec-plan
created_at: 2026-07-28T01:48:18Z
intention: "intention_01kyk6fnbyegxss8fqnf3j03tf"
master_plan: "docs/masterplans/9-make-the-seihou-manifest-multi-developer-safe.md"
---

# Record portable artifact origins in the manifest

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

Seihou generates project files from *modules*. A module is a directory containing a
`module.dhall` file that declares variables, file-generation steps, and shell commands.
After generating, seihou writes a record of what it did to `.seihou/manifest.json` inside
the project. Teams check that file into git, because it is what makes later runs
incremental and what tells a reviewer which module version produced the generated files.

Today that file is not safe to share. For every module it applied, seihou records the
absolute filesystem path where that module happened to live on the machine that ran the
command — for example `/Users/shinzui/.config/seihou/installed/haskell-base`. That string
is meaningless on any other developer's machine, and on Linux it is wrong even for the
same user.

After this plan, `seihou run`, `seihou update`, and `seihou agent run` stop writing
absolute paths into the manifest. Instead each applied module, each module instance inside
an application record, and each application's target artifact carry a *portable artifact
origin*: either the git URL the artifact was installed from plus its name, or a
repository-relative path for artifacts kept inside the project, or a bare name for
artifacts that came from the user's personal module directory with no recorded provenance.

You can see it working directly. Apply a module and inspect the manifest:

```bash
cd /tmp/demo-project
seihou run haskell-base
grep -c '"/Users' .seihou/manifest.json
```

Before this plan that `grep -c` prints a non-zero count. After this plan it prints `0`,
and the manifest instead contains entries like:

```json
{
  "name": "haskell-base",
  "origin": {
    "kind": "remote",
    "url": "https://github.com/shinzui/seihou-modules.git",
    "artifact": "haskell-base",
    "repo": "seihou-modules"
  },
  "version": "1.4.0"
}
```

This plan deliberately stops short of *using* the new field. Commands still find modules
the way they do today, so nothing breaks while the data model changes. Consuming the new
field is the job of `docs/plans/77-resolve-manifest-artifact-origins-to-local-directories.md`.
Reading manifests written by older seihou versions is the job of
`docs/plans/79-upgrade-legacy-absolute-path-manifests-in-place.md`; this plan writes the
new format and leaves a clearly marked compatibility seam for that plan to fill in.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] Milestone 1: `ArtifactOrigin` type added to `seihou-core/src/Seihou/Core/Types.hs` (2026-07-28)
- [x] Milestone 1: JSON encoder and decoder for `ArtifactOrigin` in `seihou-core/src/Seihou/Manifest/Types.hs` (2026-07-28)
- [x] Milestone 1: Round-trip unit tests in `seihou-core/test/Seihou/Manifest/TypesSpec.hs` (2026-07-28)
- [x] Milestone 2: `Seihou.Core.ArtifactOriginDetect` classifies a directory into an `ArtifactOrigin` (2026-07-28)
- [x] Milestone 2: Unit tests for classification covering all three constructors (2026-07-28)
- [ ] Milestone 3: `AppliedModule`, `AppliedInstanceState`, and `AppliedComposition` carry an origin
- [ ] Milestone 3: `currentManifestVersion` bumped from 5 to 6 with an explanatory comment
- [ ] Milestone 4: `seihou run` records origins
- [ ] Milestone 4: `seihou update` records origins
- [ ] Milestone 4: `seihou agent run` records origins
- [ ] Milestone 4: End-to-end assertion that a freshly written manifest contains no absolute paths
- [ ] Milestone 5: `docs/adr/0001-manifest-is-a-checked-in-machine-independent-artifact.md` written
- [ ] Milestone 5: `docs/adr/0002-artifact-identity-is-origin-url-plus-name.md` written


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

(None yet.)


## Decision Log

Record every decision made while working on the plan.

- Decision: Model the origin as a three-constructor sum type (`RemoteOrigin`,
  `ProjectOrigin`, `LocalOrigin`) rather than a single record with optional fields.
  Rationale: The three cases have genuinely different information and genuinely different
  trust levels. A remote origin can be verified against a git URL; a project origin is
  verifiable because the directory is in the repository; a local origin cannot be verified
  at all. A record with `Maybe Text` everywhere would let impossible combinations be
  constructed and would push the case analysis into every consumer.
  Date: 2026-07-28

- Decision: Keep the existing absolute-path fields in the Haskell records for the duration
  of this plan, but stop serializing them.
  Rationale: Seven CLI modules read those fields today. Removing them in this plan would
  force the rewiring work of
  `docs/plans/77-resolve-manifest-artifact-origins-to-local-directories.md` into this plan
  and make neither independently verifiable. Keeping the fields in memory while removing
  them from the JSON means the on-disk contract is fixed immediately and the in-memory
  cleanup happens in plan 77.
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
9.12.2 and the `GHC2024` language edition. It has three packages defined in
`cabal.project`: `seihou-core` (the library holding types, Dhall loading, the generation
engine, and manifest handling), `seihou-cli` (which contains both a library at
`seihou-cli/src/` named `seihou-cli-internal` and an executable at `seihou-cli/src-exe/`
named `seihou`), and `seihou-okf-extension`. The project-level conventions file
`CLAUDE.md` at the repository root explains that new CLI code belongs in
`seihou-cli/src/` unless it needs `Options.Applicative`, `Data.FileEmbed`, `GitHash`, or
`Paths_seihou_cli`, or transitively imports a module that does.

**Records in this repository follow a strict convention**, described in `CLAUDE.md` and in
`docs/dev/architecture/overview.md` under "Record Conventions", and enforced mechanically
by `nix/check-record-conventions.sh` which runs in both `nix flake check` and the
pre-commit hook. Every field of a `data` record carries a strictness annotation (`!`);
`newtype` fields are exempt because GHC rejects the annotation there. Field names carry no
type-abbreviation prefix. Every type has an explicit `deriving stock (...)` clause that
includes `Generic`. Fields are read and written through `generic-lens` overloaded labels
(`config ^. #environment`, `state & #status .~ Active`), never through record-dot syntax
(the `OverloadedRecordDot` extension is disabled everywhere) and never through record
*update* syntax (`r { field = x }` is forbidden; record *construction* and record
*patterns* are fine). Any module that uses a `#label` must add `import Data.Generics.Labels ()`
itself; that import must never be added to `Seihou.Prelude`, because the instance is an
orphan and would leak into every module.

**The manifest.** The manifest is a JSON file at `.seihou/manifest.json` relative to the
project root. Its in-memory representation is the `Manifest` record defined at
`seihou-core/src/Seihou/Core/Types.hs:476`:

```haskell
data Manifest = Manifest
  { version :: !Int,
    genAt :: !UTCTime,
    modules :: ![AppliedModule],
    vars :: !(Map VarName Text),
    files :: !(Map FilePath FileRecord),
    applications :: ![AppliedComposition],
    recipe :: !(Maybe AppliedRecipe),
    blueprint :: !(Maybe AppliedBlueprint),
    blueprintMigrations :: ![AppliedBlueprintMigration]
  }
  deriving stock (Eq, Show, Generic)
```

Its JSON encoder and decoder live in `seihou-core/src/Seihou/Manifest/Types.hs`, which
also defines `currentManifestVersion` (currently `5`, at line 44) and a doc comment
recording why each previous bump happened. The decoder at
`seihou-core/src/Seihou/Manifest/Types.hs:141` refuses any manifest whose `version` field
exceeds `currentManifestVersion`, with the message
`"manifest was created by a newer version of seihou"`.

**Where absolute paths get in.** Exactly three fields serialize a machine-specific path.

The first is `AppliedModule.source`, at `seihou-core/src/Seihou/Core/Types.hs:594`:

```haskell
data AppliedModule = AppliedModule
  { name :: !ModuleName,
    parentVars :: !ParentVars,
    source :: !FilePath,
    moduleVersion :: !(Maybe Text),
    appliedAt :: !UTCTime,
    removal :: !(Maybe Removal)
  }
  deriving stock (Eq, Show, Generic)
```

It is encoded under the JSON key `"source"` at
`seihou-core/src/Seihou/Manifest/Types.hs:315`.

The second is `AppliedInstanceState.source`, at
`seihou-core/src/Seihou/Core/Types.hs:518`, encoded under `"source"` at
`seihou-core/src/Seihou/Manifest/Types.hs:177`. An `AppliedInstanceState` describes one
module instance inside a recorded *application* — seihou's term for one complete,
re-runnable top-level module or recipe composition.

The third is `AppliedComposition.targetSource`, at
`seihou-core/src/Seihou/Core/Types.hs:531`, encoded under `"targetSource"` at
`seihou-core/src/Seihou/Manifest/Types.hs:207`.

Everything else in the manifest is already portable. The `files` map is keyed by
project-relative destination paths. `CommandReceipt.workDir` comes from a module's own
declared `Command.workDir`, which is project-relative by construction. Baselines live in
`.seihou/baselines/` addressed by SHA-256 content hash.

**Why those three fields hold absolute paths.** Module discovery happens in
`seihou-core/src/Seihou/Core/Module.hs`. The function `defaultSearchPaths`, at line 152,
returns three directories in priority order:

```haskell
defaultSearchPaths :: IO [FilePath]
defaultSearchPaths = do
  cwd <- getCurrentDirectory
  xdgConfig <- getXdgDirectory XdgConfig "seihou"
  pure
    [ cwd </> ".seihou" </> "modules",
      xdgConfig </> "modules",
      xdgConfig </> "installed"
    ]
```

`getCurrentDirectory` and `getXdgDirectory` both return absolute paths, so every directory
handed back by discovery is absolute, and those are the values stored in the three fields
above.

The three roots have different meanings. `<project>/.seihou/modules/` holds modules
committed inside the project itself. `~/.config/seihou/modules/` holds the developer's
personal modules, which seihou knows nothing about beyond their name. `~/.config/seihou/installed/`
is the install cache written by `seihou install`; every directory in it carries a sibling
metadata file. `seihou-core/src/Seihou/Core/Module.hs:350` names these three cases:

```haskell
data ModuleSource = SourceProject | SourceUser | SourceInstalled
```

**The install metadata file.** `installModuleDir` in
`seihou-cli/src/Seihou/CLI/InstallShared.hs` copies a module directory into
`~/.config/seihou/installed/<name>/` and writes `.seihou-origin.json` beside it. The write
side is `OriginMeta` and the read side is `OriginInfo`, both in that same file:

```haskell
data OriginInfo = OriginInfo
  { sourceUrl :: !Text,
    repoName :: !(Maybe Text),
    version :: !(Maybe Text)
  }
  deriving stock (Eq, Generic, Show)
```

`readOriginInfo :: FilePath -> IO (Maybe OriginInfo)` takes the installed directory and
returns `Nothing` when the file is absent or unparseable. This is the source of the git
URL that this plan records into the manifest. Note that `.seihou-origin.json` lives
*outside* the project, in the developer's home directory — it describes what that machine
has installed, never what the project expects. This plan copies the URL into the manifest
precisely so the project has its own machine-independent record.

**Where manifests get written.** There are three write paths, and all three must be
updated.

`seihou run` is implemented in `seihou-cli/src-exe/Seihou/CLI/Run.hs`. Its
`updateAllModules` helper at line 795 builds the `AppliedModule` list from
`modulesInOrder :: [(ModuleInstance, Module, FilePath)]`, where the `FilePath` is the
absolute discovery directory:

```haskell
new =
  [ AppliedModule
      { name = inst ^. #module_,
        parentVars = inst ^. #parentVars,
        source = dir,
        moduleVersion = m ^. #version,
        appliedAt = now,
        removal = m ^. #removal
      }
  | (inst, m, dir) <- modulesInOrder
  ]
```

The same file calls `buildAppliedComposition` at line 401 with a `targetSource` argument
that is the absolute directory of the top-level module or recipe.

`buildAppliedComposition` itself lives in `seihou-core/src/Seihou/Core/Application.hs:42`
and populates `AppliedInstanceState.source` from the same triple.

`seihou update` is implemented in `seihou-cli/src/Seihou/CLI/Update.hs`. Its
`updateAppliedModules` at line 819 and `publishInstanceSource` at line 888 both compute a
path via `publishedArtifactSource`, which returns `installedDirectory </> name` for
artifacts that came from a URL and the original directory otherwise. The relevant type is
`CandidateArtifact` in `seihou-cli/src/Seihou/CLI/Update/Types.hs:83`, which already
carries `sourceUrl :: !(Maybe Text)` and `repoName :: !(Maybe Text)` — meaning the update
path already has everything needed to build a `RemoteOrigin` without touching the
filesystem.

`seihou agent run` is implemented in `seihou-cli/src-exe/Seihou/CLI/AgentRun.hs`, which
carries a local copy of `updateAllModules` at line 499 with the same shape as the one in
`Run.hs`.

**Architecture Decision Records.** Following the workflow in
`agents/skills/exec-plan/ADR.md`: this repository currently has **no** `docs/adr/`
directory, so there is no existing ADR corpus to consult and no relevant prior decision to
cite. This plan creates the directory and the repository's first two records, because the
decisions it makes constrain all future manifest work. Details are in Milestone 5 below.

**Build and test commands.** From the repository root:

```bash
cabal build all
cabal test all
```

`Justfile` at the repository root wraps these as `just build` and `just test`, and
`just check` runs `nix flake check`, which additionally runs
`nix/check-record-conventions.sh` and `nix/check-cli-module-placement.sh`.


## Plan of Work

The work proceeds in five milestones. Each leaves the tree compiling and the full test
suite green.

### Milestone 1 — the `ArtifactOrigin` type and its JSON form

Add the type and teach the manifest encoder about it, without yet attaching it to
anything. At the end of this milestone `cabal test all` passes and a new set of round-trip
tests proves that every origin shape survives a JSON encode/decode cycle unchanged.

Add to `seihou-core/src/Seihou/Core/Types.hs`, near the other manifest types (immediately
after the `ApplicationId` newtype at line 490 is a natural home), the following. Add
`ArtifactOrigin (..)` to the module's export list, which is the explicit list at the top
of the file.

```haskell
-- | Machine-independent identity of an artifact recorded in the manifest.
--
-- The manifest is checked into version control and shared between
-- developers, so it must never contain a path that is meaningful only on
-- the machine that wrote it. Every artifact reference is therefore one of
-- three cases, distinguished by how much provenance seihou can actually
-- prove.
--
-- 'RemoteOrigin' is the strong case: the artifact was installed by
-- @seihou install@ from a git URL into
-- @~\/.config\/seihou\/installed\/\<name\>@, and that URL was recorded in
-- @.seihou-origin.json@ beside it. Two developers who install from the
-- same URL are provably using the same upstream artifact.
--
-- 'ProjectOrigin' is the case where the artifact lives inside the project
-- itself, under @.seihou\/modules\/\<name\>@. The path is stored relative
-- to the project root, so it means the same thing in every clone.
--
-- 'LocalOrigin' is the weak case: the artifact was found in the
-- developer's personal @~\/.config\/seihou\/modules\/@ directory, which
-- carries no provenance metadata at all. Only the name is knowable.
-- Recording it honestly, rather than fabricating a URL, lets later
-- verification report that this artifact's provenance cannot be checked.
data ArtifactOrigin
  = RemoteOrigin
      { originUrl :: !Text,
        artifactName :: !Text,
        repoName :: !(Maybe Text)
      }
  | ProjectOrigin
      { relativePath :: !FilePath
      }
  | LocalOrigin
      { artifactName :: !Text
      }
  deriving stock (Eq, Ord, Show, Generic)
```

Note that `originUrl`, `artifactName`, `repoName`, and `relativePath` are new field names.
The package enables `DuplicateRecordFields` and `NoFieldSelectors` (see the
`default-extensions` block in `seihou-core/seihou-core.cabal`), so reusing a name that
already exists elsewhere in the file is legal, but `artifactName` deliberately avoids
colliding with the existing `name` fields to keep `generic-lens` label usage unambiguous
at call sites.

Then add the JSON instances to `seihou-core/src/Seihou/Manifest/Types.hs`, next to the
other instances in that file. The encoding is a tagged object so it stays readable in a
git diff and leaves room for future constructors:

```haskell
instance ToJSON ArtifactOrigin where
  toJSON (RemoteOrigin url artifact repo) =
    Aeson.object $
      [ "kind" .= ("remote" :: Text),
        "url" .= url,
        "artifact" .= artifact
      ]
        ++ maybe [] (\value -> ["repo" .= value]) repo
  toJSON (ProjectOrigin path) =
    Aeson.object
      [ "kind" .= ("project" :: Text),
        "path" .= T.pack path
      ]
  toJSON (LocalOrigin artifact) =
    Aeson.object
      [ "kind" .= ("local" :: Text),
        "artifact" .= artifact
      ]

instance FromJSON ArtifactOrigin where
  parseJSON = Aeson.withObject "ArtifactOrigin" $ \o -> do
    kind <- o .: "kind" :: Aeson.Parser Text
    case kind of
      "remote" ->
        RemoteOrigin
          <$> o .: "url"
          <*> o .: "artifact"
          <*> o Aeson..:? "repo"
      "project" -> ProjectOrigin . T.unpack <$> o .: "path"
      "local" -> LocalOrigin <$> o .: "artifact"
      other -> fail ("unknown artifact origin kind: " <> T.unpack other)
```

`Seihou.Manifest.Types` already imports `Data.Aeson` as `Aeson`, `Data.Text` as `T`, and
hides `(.=)` from `Seihou.Prelude` while importing it from `Data.Aeson`; no new imports
are needed beyond what is already at the top of the file.

Also add a small pure helper in the same module and export it, because three later
milestones and two later plans need to ask "does this origin have a verifiable upstream?":

```haskell
-- | The artifact name an origin refers to, for display and for matching
-- against a discovered artifact. 'ProjectOrigin' derives it from the last
-- path segment, which is how @.seihou\/modules\/\<name\>@ is laid out.
artifactOriginName :: ArtifactOrigin -> Text
artifactOriginName (RemoteOrigin _ artifact _) = artifact
artifactOriginName (LocalOrigin artifact) = artifact
artifactOriginName (ProjectOrigin path) = T.pack (takeFileName path)
```

`takeFileName` comes from `System.FilePath`, which `Seihou.Prelude` already re-exports —
verify this by checking `seihou-core/src/Seihou/Prelude.hs`; if it does not, add
`import System.FilePath (takeFileName)` to `Seihou.Manifest.Types`.

Write the tests in `seihou-core/test/Seihou/Manifest/TypesSpec.hs`, which already exists,
already imports `Data.Aeson qualified as Aeson`, `Seihou.Core.Types`, and
`Seihou.Manifest.Types`, and is already registered in both
`seihou-core/seihou-core.cabal` (line 204) and `seihou-core/test/Main.hs`. Add a
`describe "ArtifactOrigin"` block asserting that `Aeson.decode (Aeson.encode o) == Just o`
for a `RemoteOrigin` with and without a `repo`, a `ProjectOrigin`, and a `LocalOrigin`;
that a `RemoteOrigin` with `repoName = Nothing` omits the `"repo"` key entirely; and that
decoding `{"kind":"martian"}` fails.

### Milestone 2 — classify a discovered directory into an origin

Discovery hands the write sites an absolute directory. This milestone adds the function
that turns such a directory into an `ArtifactOrigin`, so the write sites in Milestone 4
have one shared, tested implementation rather than three copies.

Create `seihou-core/src/Seihou/Core/ArtifactOriginDetect.hs` and add
`Seihou.Core.ArtifactOriginDetect` to the `exposed-modules` list of the `library` stanza in
`seihou-core/seihou-core.cabal` (keep the list alphabetically sorted; it belongs between
`Seihou.Core.Application` and `Seihou.Core.Blueprint`).

The module exports one function:

```haskell
-- | Classify an absolute artifact directory into a portable origin.
--
-- @projectRoot@ is the absolute path of the project being generated into
-- (the directory holding @.seihou@). @artifactDir@ is the absolute
-- directory that holds the artifact's @module.dhall@, @recipe.dhall@,
-- @blueprint.dhall@, or @prompt.dhall@.
--
-- Classification, in order:
--
--   1. If @artifactDir@ is inside @projectRoot@, the result is a
--      'ProjectOrigin' holding the path relative to @projectRoot@ with
--      forward slashes.
--   2. Otherwise, if @artifactDir@ contains a readable
--      @.seihou-origin.json@ with a @sourceUrl@, the result is a
--      'RemoteOrigin' carrying that URL, the directory's base name, and
--      the recorded @repoName@.
--   3. Otherwise the result is a 'LocalOrigin' holding the directory's
--      base name.
detectArtifactOrigin :: FilePath -> FilePath -> IO ArtifactOrigin
```

Implementation notes. Canonicalize both paths with
`System.Directory.canonicalizePath` before comparing, so that a symlinked project root or
a path containing `..` classifies correctly; wrap each call in
`Control.Exception.try @IOException` and fall back to the uncanonicalized path on failure,
because `canonicalizePath` throws when an intermediate component does not exist. Use
`System.FilePath.makeRelative` for the containment test, and treat the result as "inside"
only when it does not start with `".."` and is not identical to the input — `makeRelative`
returns its second argument unchanged when there is no common prefix. Normalize the
relative path to forward slashes with
`map (\c -> if c == System.FilePath.pathSeparator then '/' else c)` so a Windows-generated
manifest matches a POSIX-generated one.

Reading `.seihou-origin.json` is the awkward part, because the parser
(`readOriginInfo` / `OriginInfo`) currently lives in
`seihou-cli/src/Seihou/CLI/InstallShared.hs`, and `seihou-core` cannot depend on
`seihou-cli-internal` — that would be a dependency cycle, since `seihou-cli-internal`
depends on `seihou-core`. Resolve it by moving the `OriginInfo` type and `readOriginInfo`
function down into `seihou-core`, in the new module, and re-exporting them from
`seihou-cli/src/Seihou/CLI/InstallShared.hs` so its existing importers
(`seihou-cli/src/Seihou/CLI/Migrate.hs`, `seihou-cli/src-exe/Seihou/CLI/Upgrade.hs`,
`seihou-cli/src-exe/Seihou/CLI/Outdated.hs`, and `seihou-cli/src-exe/Seihou/CLI/Status.hs`
— confirm the full set with `grep -rn "readOriginInfo\|OriginInfo" --include='*.hs' .`)
keep compiling untouched. Leave the *write* side (`OriginMeta`, `installModuleDir`) where
it is; only the read side moves. `seihou-core` already depends on `aeson`, `bytestring`,
`directory`, and `filepath`, so no new dependency is needed.

Test in a new file `seihou-core/test/Seihou/Core/ArtifactOriginDetectSpec.hs`, registered
in `seihou-core/seihou-core.cabal`'s test-suite `other-modules` and in
`seihou-core/test/Main.hs` following the pattern of the existing entries. Use
`System.IO.Temp` or `Data.Time`-free plain `createDirectoryIfMissing` under a temporary
directory — several existing specs, for example
`seihou-core/test/Seihou/Core/ScaffoldSpec.hs`, show the established pattern in this
repository. Cover: a directory nested two levels inside the project root yielding
`ProjectOrigin "\.seihou/modules/foo"`; a directory outside the root with a valid
`.seihou-origin.json` yielding `RemoteOrigin`; the same directory with a malformed
`.seihou-origin.json` falling back to `LocalOrigin`; and a directory outside the root with
no metadata file yielding `LocalOrigin`.

### Milestone 3 — attach the origin to the three manifest records

Add an `origin :: !ArtifactOrigin` field to `AppliedModule` and `AppliedInstanceState`,
and a `targetOrigin :: !ArtifactOrigin` field to `AppliedComposition`, all in
`seihou-core/src/Seihou/Core/Types.hs`. Place each new field immediately after the
existing `source` / `targetSource` field so the record reads in a natural order. Keep the
old `source` and `targetSource` fields for now — plan 77 removes them once nothing reads
them.

In `seihou-core/src/Seihou/Manifest/Types.hs`, change the three encoders to emit
`"origin"` (and `"targetOrigin"`) and to **stop emitting** `"source"` and `"targetSource"`.
Change the three decoders to read the new keys. Because this plan does not yet handle
legacy manifests, make the decoders require the new key and populate the retained
`source` / `targetSource` fields with the empty string `""`, with an inline comment
pointing at `docs/plans/79-upgrade-legacy-absolute-path-manifests-in-place.md`:

```haskell
-- Compatibility seam: schema-5-and-earlier manifests carry an absolute
-- "source" path instead of "origin". Decoding those is owned by
-- docs/plans/79-upgrade-legacy-absolute-path-manifests-in-place.md; until
-- that plan lands, an older manifest fails to decode with a clear message
-- rather than being silently misread.
```

Make that failure message explicit and actionable rather than an Aeson key-not-found
error. In the `Manifest` `FromJSON` instance at
`seihou-core/src/Seihou/Manifest/Types.hs:141`, which already rejects manifests from the
future, add the symmetric guard:

```haskell
v <- o .: "version"
if v > currentManifestVersion
  then fail "manifest was created by a newer version of seihou"
  else
    if v < 6
      then
        fail
          ( "this manifest uses schema version "
              <> show v
              <> ", which records machine-specific absolute paths; run "
              <> "'seihou manifest upgrade' to convert it"
          )
      else ...
```

The `seihou manifest upgrade` command named in that message is delivered by plan 79. State
that in a comment beside the guard so a reader who hits the message before plan 79 lands
understands why the command does not exist yet.

Bump `currentManifestVersion` from `5` to `6` and extend its doc comment in the same style
as the existing entries:

```haskell
-- Bumped from 5 to 6 when every recorded artifact reference gained a
-- portable @origin@ and the machine-specific @source@ /
-- @targetSource@ absolute paths were dropped from the serialized form
-- (see docs/plans/76-record-portable-artifact-origins-in-the-manifest.md).
-- Version-5-and-earlier manifests are not readable directly; see
-- docs/plans/79-upgrade-legacy-absolute-path-manifests-in-place.md.
```

Update `emptyManifest`, `writeAppliedBlueprint`, and `writeAppliedBlueprintMigration` in
the same file if the compiler flags them — they construct `Manifest` positionally by field
name and so are unaffected by changes to the *nested* records, but they will need no edit
unless a field is added to `Manifest` itself, which this plan does not do.

Fix every construction site the compiler now rejects. Because the repository forbids
record update syntax, each site must be a full construction; the compiler's
missing-field warnings under `-Werror` (check the `ghc-options` in
`seihou-core/seihou-core.cabal` and `seihou-cli/seihou-cli.cabal` to confirm whether
`-Werror` is on) will point at each one. Test fixtures under `seihou-core/test/` and
`seihou-cli/test/` construct these records extensively; give them
`LocalOrigin "test-module"` or an explicit fixture origin as appropriate.

### Milestone 4 — write real origins from the three command paths

This is where the manifest on disk actually changes. At the end of this milestone,
running `seihou run` in a scratch project produces a manifest with no absolute paths.

In `seihou-core/src/Seihou/Core/Application.hs`, `buildAppliedComposition` currently takes
`targetSource :: FilePath` and a list of `(ModuleInstance, Module, FilePath)`. Widen its
signature so callers pass origins alongside the paths: change the target parameter to a
pair `(FilePath, ArtifactOrigin)` and the instance list element to
`(ModuleInstance, Module, FilePath, ArtifactOrigin)`. Keeping the paths in the tuple keeps
plan 77's later removal a mechanical deletion rather than a second signature change.
Populate `AppliedInstanceState.origin` and `AppliedComposition.targetOrigin` from the new
components.

In `seihou-cli/src-exe/Seihou/CLI/Run.hs`, compute the project root once — `handleRun`
already establishes the manifest path as `".seihou" </> "manifest.json"`, so the project
root is `System.Directory.getCurrentDirectory`. Immediately after the composition is
loaded (the `modulesInOrder` binding produced by `loadComposition`, and the target
directory bound near line 133 in the `RunnableModule modul moduleDir` branch), map
`detectArtifactOrigin projectRoot` over every directory to produce the widened tuples.
Thread those through to both `updateAllModules` (line 795) and the
`buildAppliedComposition` call (line 401).

In `seihou-cli/src/Seihou/CLI/Update.hs`, the update path already knows each artifact's
`sourceUrl` and `repoName` from `CandidateArtifact`
(`seihou-cli/src/Seihou/CLI/Update/Types.hs:83`), so it can construct the origin directly
without a filesystem probe. Add a helper next to `publishedArtifactSource` (line 894):

```haskell
candidateArtifactOrigin :: FilePath -> CandidateArtifact -> IO ArtifactOrigin
candidateArtifactOrigin projectRoot artifact = case artifact ^. #sourceUrl of
  Just url -> pure (RemoteOrigin url (artifact ^. #name) (artifact ^. #repoName))
  Nothing -> detectArtifactOrigin projectRoot (artifact ^. #originalDirectory)
```

and use it in `updateAppliedModules` (line 819) and `publishInstanceSource` (line 888).
Note that `updateAppliedModules` is currently pure; either make it take a precomputed
`Map` from artifact name to origin, or lift it into `IO`. Prefer the precomputed map — it
keeps the function pure and testable, matching how the rest of that module is structured.

In `seihou-cli/src-exe/Seihou/CLI/AgentRun.hs`, apply the same change to its local
`updateAllModules` at line 499.

Also record the origin for the blueprint itself: `AppliedBlueprint` at
`seihou-core/src/Seihou/Core/Types.hs:563` currently stores only a name and version and no
path, so it needs no new field for portability — confirm this by re-reading the record and
its encoder at `seihou-core/src/Seihou/Manifest/Types.hs:267` and note the finding in
Surprises & Discoveries if it turns out otherwise.

### Milestone 5 — the first two ADRs

Create `docs/adr/` and write the two records identified in the parent MasterPlan at
`docs/masterplans/9-make-the-seihou-manifest-multi-developer-safe.md`, following the
format described in `agents/skills/exec-plan/ADR.md`. Read that file before writing, and
follow whatever numbering, status vocabulary, and heading structure it prescribes; the
filenames below are indicative and should be adjusted to match it.

`docs/adr/0001-manifest-is-a-checked-in-machine-independent-artifact.md` records that
`.seihou/manifest.json` is a project artifact committed to version control, that it must
therefore never contain absolute filesystem paths or any other machine-specific value, and
that this constrains every future manifest field, not only the ones changed by this plan.
State the consequence explicitly: a new manifest field that needs to reference a location
must reference it relative to the project root or through an `ArtifactOrigin`.

`docs/adr/0002-artifact-identity-is-origin-url-plus-name.md` records that artifact
identity in the manifest is keyed on the git origin URL plus the artifact name, and
documents the two rejected alternatives with their reasons — a bare artifact name (two
registries can publish the same name, so a manifest keyed on name cannot tell a developer
they have the wrong module installed) and a content hash of the module directory (precise,
but changes on every edit, so it cannot express "the same module, one version newer",
which is the relationship the downgrade guard in
`docs/plans/78-refuse-accidental-module-downgrades-and-origin-mismatches.md` must reason
about). Also record why `LocalOrigin` exists: modules found in
`~/.config/seihou/modules/` have no provenance metadata, and fabricating a URL for them
would be a lie that later verification would act on.


## Concrete Steps

All commands run from the repository root,
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`, unless stated otherwise.

Confirm the starting state builds and tests green before changing anything:

```bash
cabal build all
cabal test all
```

Expected tail of the test output:

```text
All 1 tests passed
```

(The exact count varies; what matters is that no test fails before you start.)

Locate every construction site you will have to fix in Milestone 3:

```bash
grep -rn "AppliedModule$\|AppliedModule *{" --include='*.hs' seihou-core seihou-cli
grep -rn "AppliedInstanceState" --include='*.hs' seihou-core seihou-cli
grep -rn "AppliedComposition *{" --include='*.hs' seihou-core seihou-cli
```

Confirm the full set of importers before moving `readOriginInfo` in Milestone 2:

```bash
grep -rn "readOriginInfo\|OriginInfo" --include='*.hs' seihou-core seihou-cli
```

After each milestone:

```bash
cabal build all && cabal test all
```

Before committing, run the mechanical convention checks, because the record conventions
are enforced and a new record with a non-strict field or a missing `Generic` will be
rejected:

```bash
nix flake check
```

Commit at the end of each milestone. Every commit message must carry all three trailers:

```text
feat(manifest): add portable ArtifactOrigin type and JSON encoding

Introduce a three-constructor origin type covering git-installed,
project-local, and unverifiable personal artifacts, with a tagged JSON
encoding and round-trip tests.

MasterPlan: docs/masterplans/9-make-the-seihou-manifest-multi-developer-safe.md
ExecPlan: docs/plans/76-record-portable-artifact-origins-in-the-manifest.md
Intention: intention_01kyk6fnbyegxss8fqnf3j03tf
```


## Validation and Acceptance

The unit-level acceptance is that `cabal test all` passes with the new specs in place, and
that the round-trip property holds for every origin shape.

The behavioral acceptance is that a manifest written by the new code contains no absolute
path. Prove it by hand in a scratch project. First build and install the CLI locally:

```bash
cabal build seihou-cli
```

Then create a throwaway project with a module committed inside it, which exercises the
`ProjectOrigin` branch without needing network access:

```bash
mkdir -p /tmp/seihou-origin-demo/.seihou/modules/demo
cd /tmp/seihou-origin-demo
git init
```

Write a minimal `module.dhall` under `.seihou/modules/demo/`. Use
`docs/user/module-authoring.md` for the current schema import line and required fields —
the schema URL is pinned per release, so copy it from that document rather than from this
plan. A module must declare a `name`, a `version`, and at least one step.

Then run:

```bash
cabal run seihou -- run demo
grep -n '"origin"' .seihou/manifest.json
grep -c '"/' .seihou/manifest.json
```

Expected: the first `grep` prints one or more lines showing
`"origin": {"kind":"project","path":".seihou/modules/demo"}`, and the second prints `0`
if no other JSON string in the file begins with a slash. If the second count is non-zero,
inspect which key holds it — a project-relative destination path such as
`"src/Main.hs"` is fine and expected, an absolute path beginning `/Users` or `/home` is a
failure.

Automate the same check so it cannot regress. Add a test to
`seihou-core/test/Seihou/Manifest/TypesSpec.hs` that constructs a `Manifest` with one
`AppliedModule`, one `AppliedComposition` with one `AppliedInstanceState`, encodes it with
`manifestToJSON`, and asserts that the resulting lazy `ByteString` contains no occurrence
of the byte sequence `":"/"` (a JSON value starting with a slash) in an origin position.
The simplest robust form is to decode the encoded value back to an `Aeson.Value`, walk it,
and assert that no string under any `"origin"` or `"targetOrigin"` key starts with `'/'`.

Finally, confirm the guard against old manifests produces the intended message rather than
a raw Aeson error:

```bash
printf '{"version":5,"generatedAt":"2026-01-01T00:00:00Z","modules":[],"variables":{},"files":{},"applications":[],"blueprintMigrations":[]}' > /tmp/old-manifest.json
```

and add a unit test in `seihou-core/test/Seihou/Manifest/TypesSpec.hs` asserting that
`manifestFromJSON` on those bytes returns a `Left` whose message contains
`"seihou manifest upgrade"`.


## Idempotence and Recovery

Every step in this plan is an ordinary source edit and can be repeated or reverted with
git. Nothing here mutates a user's project or their `~/.config/seihou/` directory.

The one step with a lasting external effect is Milestone 4's behavioral check, which
writes `.seihou/manifest.json` into `/tmp/seihou-origin-demo`. Delete that directory to
reset:

```bash
rm -rf /tmp/seihou-origin-demo
```

Milestone 3 is the risky one, because bumping `currentManifestVersion` to 6 makes the
build reject every manifest written by a released seihou. Do not run a locally built
`seihou` against a real project you care about between Milestone 3 and the completion of
`docs/plans/79-upgrade-legacy-absolute-path-manifests-in-place.md`; use scratch projects.
If you need to recover a project whose manifest was written by the in-progress build,
`git checkout -- .seihou/manifest.json` restores the committed version, which is why the
manifest being checked in matters.

If Milestone 2's move of `readOriginInfo` from `seihou-cli` into `seihou-core` turns out
to create a dependency problem you did not anticipate, the fallback is to duplicate the
tiny `OriginInfo` decoder in `seihou-core` rather than move it, and leave the `seihou-cli`
copy alone. Record that in the Decision Log if you take it, and note that the duplication
must be removed before the MasterPlan is marked complete.


## Interfaces and Dependencies

No new package dependencies are required. `seihou-core` already depends on `aeson`,
`bytestring`, `containers`, `directory`, `filepath`, `generic-lens`, `lens`, and `text`,
which is everything this plan uses.

At the end of Milestone 1, these must exist:

```haskell
-- seihou-core/src/Seihou/Core/Types.hs
data ArtifactOrigin
  = RemoteOrigin { originUrl :: !Text, artifactName :: !Text, repoName :: !(Maybe Text) }
  | ProjectOrigin { relativePath :: !FilePath }
  | LocalOrigin { artifactName :: !Text }
  deriving stock (Eq, Ord, Show, Generic)

-- seihou-core/src/Seihou/Manifest/Types.hs
instance ToJSON ArtifactOrigin
instance FromJSON ArtifactOrigin
artifactOriginName :: ArtifactOrigin -> Text
```

At the end of Milestone 2:

```haskell
-- seihou-core/src/Seihou/Core/ArtifactOriginDetect.hs
detectArtifactOrigin :: FilePath -> FilePath -> IO ArtifactOrigin
data OriginInfo = OriginInfo
  { sourceUrl :: !Text,
    repoName :: !(Maybe Text),
    version :: !(Maybe Text)
  }
  deriving stock (Eq, Generic, Show)
readOriginInfo :: FilePath -> IO (Maybe OriginInfo)
```

At the end of Milestone 3, `AppliedModule` and `AppliedInstanceState` each carry
`origin :: !ArtifactOrigin`, `AppliedComposition` carries `targetOrigin :: !ArtifactOrigin`,
and `currentManifestVersion == 6`.

At the end of Milestone 4:

```haskell
-- seihou-core/src/Seihou/Core/Application.hs
buildAppliedComposition ::
  AppliedTarget ->
  (FilePath, ArtifactOrigin) ->
  Maybe Text ->
  [ModuleName] ->
  Maybe Text ->
  Maybe Text ->
  [(ModuleInstance, Module, FilePath, ArtifactOrigin)] ->
  Map ModuleInstance (Map VarName ResolvedVar) ->
  UTCTime ->
  AppliedComposition
```

Downstream consumers of these interfaces are
`docs/plans/77-resolve-manifest-artifact-origins-to-local-directories.md`, which turns an
`ArtifactOrigin` back into a directory on the current machine;
`docs/plans/78-refuse-accidental-module-downgrades-and-origin-mismatches.md`, which
compares the recorded origin and version against what is installed locally;
`docs/plans/79-upgrade-legacy-absolute-path-manifests-in-place.md`, which fills in the
compatibility seam left in Milestone 3; and
`docs/plans/80-document-and-end-to-end-verify-the-shared-manifest-workflow.md`, which
proves the whole workflow. None of those may change the shape of `ArtifactOrigin` without
a decision recorded in the parent MasterPlan's Decision Log at
`docs/masterplans/9-make-the-seihou-manifest-multi-developer-safe.md`.
