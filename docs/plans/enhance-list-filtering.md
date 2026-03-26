# Enhance `seihou list` with repoName and tag filtering

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

After this change, users can run `seihou list --repo <name>` to show only modules
installed from a specific repository, and `seihou list --tag <tag>` to show only
modules whose registry entry includes that tag. Both filters can be combined.

Currently `seihou list` shows all discovered modules with no filtering. The `browse`
command already supports `--tag` filtering against remote registries, but `list` operates
on locally-installed modules. The key challenge is that **tags are not persisted at
install time** — only `repoName` and `version` are stored in `.seihou-origin.json`.
To support tag filtering without re-evaluating Dhall at list time (which would be slow),
we must persist tags into origin metadata at install time.


## Progress

- [x] **M1-1**: Add `tags` field to `OriginMeta` in Install.hs and write it during install (2026-03-25)
- [x] **M1-2**: Add `tags` field to `OriginInfo` in List.hs and parse it from `.seihou-origin.json` (2026-03-25)
- [x] **M1-3**: Define `ListOpts` data type in Commands.hs with `--repo` and `--tag` options (2026-03-25)
- [x] **M1-4**: Update `Command` ADT: change `List` to `List ListOpts` (2026-03-25)
- [x] **M1-5**: Update CLI parser `listInfo` to parse `ListOpts` (2026-03-25)
- [x] **M1-6**: Update `Main.hs` dispatch to pass `ListOpts` to `handleList` (2026-03-25)
- [x] **M2-1**: Thread `ListFilter` through `handleList` and apply filtering (2026-03-25)
- [x] **M2-2**: Carry tags through `Entry` for tag-based filtering (2026-03-25)
- [x] **M2-3**: Update output to show active filters in summary line (2026-03-25)
- [x] **M2-4**: Preserve `formatListOutput` backward-compatible API (2026-03-25)
- [x] **M3-1**: Add unit tests for `--repo` filtering (2026-03-25)
- [x] **M3-2**: Add unit tests for `--tag` filtering (2026-03-25)
- [x] **M3-3**: Add unit test for combined `--repo` + `--tag` filtering (2026-03-25)
- [x] **M3-4**: Add unit test for no-results with filter (2026-03-25)
- [x] **M4-1**: Build and run full test suite — 650 core + 63 CLI tests pass (2026-03-25)


## Surprises & Discoveries

- The `seihou-cli-internal` library (used by test suite) only exposes a subset of modules and has a smaller dependency set than the executable. Importing `Seihou.CLI.Commands` into `List.hs` would have broken the internal library build because `Commands` depends on `optparse-applicative` which is not in the internal lib's deps. Solved by defining `ListFilter` directly in `List.hs` and converting from `ListOpts` at the `Main.hs` call site.

- The `Upgrade.hs` module also calls `installModuleDir` — the plan didn't account for this call site. Updated to pass `entry.tags` through.


## Decision Log

- Decision: Persist tags in `.seihou-origin.json` at install time rather than re-evaluating Dhall or re-cloning the registry at list time.
  Rationale: Avoids network I/O and Dhall evaluation on every `seihou list --tag` call. Tags are available during install from the `RegistryEntry`. For single-module repos (no registry), tags will be empty `[]`, which is consistent — only registry-declared tags are stored.
  Date: 2025-03-25

- Decision: Use `--repo` (not `--repo-name` or `--source`) as the flag name.
  Rationale: Concise, mirrors `repoName` field semantics. The filter matches the `repoName` stored in origin metadata (substring match would be surprising; use exact match).
  Date: 2025-03-25

- Decision: Filter is applied after module discovery and origin loading, as a pure list filter on `[Entry]`.
  Rationale: The performance cost is trivial — we're filtering a small in-memory list. The expensive part (Dhall eval, disk I/O) happens before filtering regardless. This keeps the code simple.
  Date: 2025-03-25

- Decision: For modules not installed from a registry (project/user modules), `--repo` will never match them and `--tag` will never match them (they have no origin metadata). This is correct behavior — these filters are meaningful only for installed modules.
  Rationale: Project and user modules don't have repoName or tags. Filtering them out when `--repo` or `--tag` is specified is the expected behavior.
  Date: 2025-03-25

- Decision: Existing installs without a `tags` field in `.seihou-origin.json` will decode `tags` as `[]` (empty list) via `.:?` with a default. No migration needed.
  Rationale: Backward-compatible JSON parsing. Users who reinstall or upgrade will get tags populated automatically.
  Date: 2025-03-25


## Outcomes & Retrospective

All milestones completed. The implementation adds `--repo` and `--tag` filtering to `seihou list` with:
- Tags persisted in `.seihou-origin.json` at install/upgrade time (no Dhall re-evaluation needed)
- Pure in-memory filtering via `applyFilters` — trivial performance cost
- Backward-compatible: existing installs decode `tags` as `[]`, unfiltered `seihou list` output unchanged
- 7 new unit tests covering all filter combinations
- 650 core + 63 CLI tests all passing


## Context and Orientation

### Current `list` command

The `list` command is defined in `seihou-cli/src/Seihou/CLI/Commands.hs` as a bare
constructor `List` (no options). The parser at line 427 uses `pure List` — it accepts
no arguments or flags.

The handler lives in `seihou-cli/src/Seihou/CLI/List.hs`. It:
1. Calls `defaultSearchPaths` to get 3 directories (project, user, installed).
2. Calls `discoverAllModules` to scan those directories for `module.dhall` files.
3. Reads `.seihou-origin.json` from each module's directory for origin metadata.
4. Converts each `DiscoveredModule` + origin info into an `Entry` record.
5. Formats and prints the entries.

### Origin metadata

At install time (`seihou-cli/src/Seihou/CLI/Install.hs:284-285`), an `OriginMeta`
record is written to `.seihou-origin.json` with fields: `sourceUrl`, `repoName`,
`installedAt`, `version`. **Tags are not currently stored.**

At list time (`List.hs:21-24`), `OriginInfo` reads back `repoName` and `version`
(both `Maybe Text`). **Tags are not currently read.**

### Registry and tags

`RegistryEntry` in `seihou-core/src/Seihou/Core/Registry.hs:17-23` has a `tags :: [Text]`
field. During install from a multi-module repo, each entry's tags are available but
discarded — only `name`, `version`, and `path` are used.

### Browse command (existing tag filter pattern)

`seihou-cli/src/Seihou/CLI/Browse.hs:54-56` already filters `RegistryEntry` by tag:
```haskell
let filtered = case bopts.browseTag of
      Nothing -> registry.modules
      Just tag -> filter (\e -> tag `elem` e.tags) registry.modules
```

The `BrowseOpts` type at `Commands.hs:152-156` and its parser at line 671-674
provide the pattern we'll follow for `ListOpts`.

### Test files

- `seihou-cli/test/Seihou/CLI/ListSpec.hs` — tests `formatListOutput` (the backward-compatible API without origin info)
- `seihou-core/test/Seihou/Core/ListSpec.hs` — tests `discoverAllModules` integration

### Key types

- `DiscoveredModule` (Core.Module): `{ discoveredResult, discoveredSource, discoveredDir }`
- `ModuleSource`: `SourceProject | SourceUser | SourceInstalled`
- `Entry` (CLI.List): `{ entryName, entryDesc, entrySource, entryIsError }`
- `OriginInfo` (CLI.List): `{ originRepoName, originVersion }`
- `OriginMeta` (CLI.Install): `{ sourceUrl, repoName, installedAt, version }`
- `RegistryEntry` (Core.Registry): `{ name, version, path, description, tags }`


## Plan of Work

### Milestone 1: Plumbing — persist tags and add CLI options

**Scope**: Add `tags` to origin metadata (write and read), define `ListOpts`, wire up the parser.

**What exists at the end**: `seihou list --repo X --tag Y` parses without error, `handleList` receives `ListOpts`, and newly-installed modules have tags in their origin file. No filtering logic yet.

**Acceptance**: `seihou list --help` shows `--repo` and `--tag` options. `cabal build all` succeeds.

#### Step 1: Add `tags` to `OriginMeta` (Install.hs)

In `seihou-cli/src/Seihou/CLI/Install.hs`, add a `tags` field to `OriginMeta`:

```haskell
data OriginMeta = OriginMeta
  { sourceUrl :: Text,
    repoName :: Maybe Text,
    installedAt :: Text,
    version :: Maybe Text,
    tags :: [Text]           -- NEW
  }
```

Update the `ToJSON` instance to include `"tags" .= m.tags`.

Update the call site at line 284 where `OriginMeta` is constructed. For multi-module
install, the `RegistryEntry` is available — pass `entry.tags`. For single-module
install, pass `[]`.

There are two install paths to trace:
- `installSingleModule` (line 91): no registry entry, use `[]`
- The multi-module path that calls `installModuleDir`: the caller must pass tags through.

The function `installModuleDir` (line 269) currently takes `source registryName moduleVersion`.
Add a `[Text]` parameter for tags.

#### Step 2: Add `tags` to `OriginInfo` (List.hs)

In `seihou-cli/src/Seihou/CLI/List.hs`, extend `OriginInfo`:

```haskell
data OriginInfo = OriginInfo
  { originRepoName :: Maybe Text,
    originVersion :: Maybe Text,
    originTags :: [Text]         -- NEW
  }
```

Update the `FromJSON` instance. Use `.:?` with a default of `[]` for backward compatibility:

```haskell
OriginInfo <$> v .:? "repoName" <*> v .:? "version" <*> (fromMaybe [] <$> v .:? "tags")
```

#### Step 3: Define `ListOpts` (Commands.hs)

In `seihou-cli/src/Seihou/CLI/Commands.hs`, add a new data type:

```haskell
data ListOpts = ListOpts
  { listRepo :: Maybe Text,
    listTag :: Maybe Text
  }
  deriving stock (Eq, Show, Generic)
```

Export it from the module. Change the `Command` constructor from `List` to `List ListOpts`.

#### Step 4: Update `listInfo` parser (Commands.hs)

Replace `pure List` with a parser that reads `--repo` and `--tag`:

```haskell
listParser :: Parser Command
listParser =
  fmap List $
    ListOpts
      <$> optional (option (T.pack <$> str) (long "repo" <> metavar "REPO" <> help "Filter by repository name"))
      <*> optional (option (T.pack <$> str) (long "tag" <> metavar "TAG" <> help "Filter by tag"))
```

Update `listInfo` to use `listParser <**> helper` instead of `pure List <**> helper`.

#### Step 5: Update Main.hs dispatch

Change `List -> handleList` to `List listOpts -> handleList listOpts`.

Update `handleList` signature to accept `ListOpts`.


### Milestone 2: Filtering logic

**Scope**: Apply `--repo` and `--tag` filters in `handleList`. Update output to indicate active filters.

**What exists at the end**: `seihou list --repo my-repo` shows only modules from that repo. `seihou list --tag haskell` shows only modules with that tag. Filters combine with AND.

**Acceptance**: Manual test with installed modules. Filtered output shows correct subset and summary mentions the filter.

#### Step 1: Extend `Entry` with filter-relevant fields

Add `entryRepoName :: Maybe Text` and `entryTags :: [Text]` to the `Entry` record in List.hs.
Populate them from `OriginInfo` in `toEntryWithOrigin`.

#### Step 2: Apply filters in `handleList`

After building `entries`, filter based on `ListOpts`:

```haskell
let filtered = applyFilters listOpts entries
```

Where `applyFilters` does:
- If `listRepo` is `Just r`, keep only entries where `entryRepoName == Just r`
- If `listTag` is `Just t`, keep only entries where `t `elem` entryTags`
- Both filters combine with AND

#### Step 3: Update summary line

When filters are active, append to the summary, e.g.:
`"2 modules found (3 sources searched) [filtered: repo=my-repo, tag=haskell]"`


### Milestone 3: Tests

**Scope**: Unit tests covering all filter combinations.

**Acceptance**: `cabal test all` passes.

Add tests to `seihou-cli/test/Seihou/CLI/ListSpec.hs`. Since the existing
`formatListOutput` API doesn't have origin info, the tests should exercise the
new filtering path. Options:
1. Export a test-facing function that takes `ListOpts` and `[Entry]` and returns filtered output.
2. Or test `applyFilters` directly if exported.

Recommended: export `applyFilters` and test it directly (pure function, easy to test).

Test cases:
- `--repo` matches: only installed modules from that repo shown
- `--repo` no match: empty result
- `--tag` matches: modules with that tag shown
- `--tag` no match: empty result
- Combined `--repo` + `--tag`: AND behavior
- No filters: all modules shown (existing behavior preserved)


### Milestone 4: Build and full test suite

Run `cabal build all && cabal test all` and fix any issues.


## Concrete Steps

All commands run from the repository root: `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`

```bash
# After all edits, build:
cabal build all

# Run tests:
cabal test all

# Verify CLI help:
cabal run seihou -- list --help
# Expected: shows --repo REPO and --tag TAG options

# Manual test (if modules are installed):
cabal run seihou -- list
cabal run seihou -- list --repo seihou-modules
cabal run seihou -- list --tag haskell
```


## Validation and Acceptance

1. `cabal build all` succeeds with no warnings in seihou-cli or seihou-core.
2. `cabal test all` passes, including new ListSpec tests.
3. `seihou list --help` shows `--repo REPO` and `--tag TAG` options with help text.
4. `seihou list` (no filters) produces identical output to before this change.
5. `seihou list --repo <existing-repo>` shows only modules from that repo.
6. `seihou list --tag <existing-tag>` shows only modules with that tag.
7. `seihou list --repo nonexistent` shows "No modules found" with filter info.
8. Reinstalling a module from a multi-module repo writes `tags` to `.seihou-origin.json`.


## Idempotence and Recovery

All steps are safe to repeat. The only persistent change outside source code is that
newly-installed modules will have a `tags` field in `.seihou-origin.json`. Existing
installs without `tags` are handled by defaulting to `[]` during JSON parsing.

If a build fails mid-way, `cabal build all` can be re-run. No database or external
state is involved.


## Interfaces and Dependencies

### Modified modules

**`seihou-cli/src/Seihou/CLI/Commands.hs`** — new type and export:
```haskell
data ListOpts = ListOpts
  { listRepo :: Maybe Text,
    listTag :: Maybe Text
  }
```
Constructor changes: `List` becomes `List ListOpts`.

**`seihou-cli/src/Seihou/CLI/List.hs`** — updated types and new function:
```haskell
data OriginInfo = OriginInfo
  { originRepoName :: Maybe Text,
    originVersion :: Maybe Text,
    originTags :: [Text]
  }

data Entry = Entry
  { entryName :: Text,
    entryDesc :: Text,
    entrySource :: Text,
    entryIsError :: Bool,
    entryRepoName :: Maybe Text,
    entryTags :: [Text]
  }

handleList :: ListOpts -> IO ()
applyFilters :: ListOpts -> [Entry] -> [Entry]
```

**`seihou-cli/src/Seihou/CLI/Install.hs`** — extended type:
```haskell
data OriginMeta = OriginMeta
  { sourceUrl :: Text,
    repoName :: Maybe Text,
    installedAt :: Text,
    version :: Maybe Text,
    tags :: [Text]
  }

installModuleDir :: FilePath -> String -> Text -> Maybe Text -> Maybe Text -> [Text] -> IO ()
```

**`seihou-cli/src/Main.hs`** — pattern match update only.

### Libraries used

- `optparse-applicative` (already a dependency) — `optional`, `option`, `long`, `metavar`, `help`
- `aeson` (already a dependency) — `.:?`, `.=`, `fromMaybe`
- No new dependencies required.
