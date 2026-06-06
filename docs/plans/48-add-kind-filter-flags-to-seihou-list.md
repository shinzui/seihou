---
id: 48
slug: add-kind-filter-flags-to-seihou-list
title: "Add kind filter flags to seihou list"
kind: exec-plan
created_at: 2026-06-06T15:50:14Z
intention: "intention_01ktesy7m6er692f8zz7zkt2x9"
---

# Add kind filter flags to seihou list

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

`seihou` is a command-line tool that scaffolds software projects from reusable
building blocks. There are three kinds of building block, and the tool calls each
of them a "runnable artifact":

- A **module** is the smallest building block: a directory containing a
  `module.dhall` file describing files to generate and commands to run.
- A **recipe** is a directory containing a `recipe.dhall` file that composes
  several modules together.
- A **blueprint** is a directory containing a `blueprint.dhall` file that drives
  an AI-agent-assisted scaffolding flow.

The `seihou list` command scans every search path and prints all discovered
runnable artifacts of all three kinds in one combined listing. Today the only way
to narrow the output is by repository (`--repo`) or by tag (`--tag`); there is no
way to say "show me only the modules" or "show me only the blueprints."

After this change, a user can restrict the listing by kind using three new
switch flags:

- `seihou list --modules` shows only modules.
- `seihou list --recipes` shows only recipes.
- `seihou list --blueprints` shows only blueprints.

The flags combine as a union: `seihou list --modules --recipes` shows modules and
recipes but hides blueprints. With no kind flag, `seihou list` behaves exactly as
before and shows every kind. Kind flags also combine with the existing `--repo`
and `--tag` filters using AND (every active filter must match).

You can see it working by running, in a directory with a mix of installed
artifacts:

```text
$ seihou list --blueprints
Available modules, recipes, and blueprints:

  demo-agent   An AI-assisted scaffold   (installed) [blueprint]

1 blueprint found (3 sources searched) [kind: blueprint]
```

and confirming that modules and recipes no longer appear, while the summary line
records the active kind filter.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] **M1-1**: Add `entryKind :: RunnableKind` field to the `Entry` record in `seihou-cli/src/Seihou/CLI/List.hs`. (2026-06-06)
- [x] **M1-2**: Set `entryKind` in `runnableToEntryWithOrigin` (from `dr.drKind`) and in `toEntryWithOrigin`/`toEntry` (always `KindModule`). (2026-06-06)
- [x] **M1-3**: Add `filterKinds :: [RunnableKind]` field to `ListFilter`; update `noFilter`. (2026-06-06)
- [x] **M1-4**: Extend `applyFilters` with a kind predicate (empty list = all kinds). (2026-06-06)
- [x] **M1-5**: Extend `formatFilterSuffix` to report the active kind filter. (2026-06-06)
- [x] **M1-6**: Build the library — `cabal build seihou-cli-internal`. (2026-06-06)
- [x] **M2-1**: Add `listModulesOnly`, `listRecipesOnly`, `listBlueprintsOnly` switch fields to `ListOpts` in `seihou-cli/src-exe/Seihou/CLI/Commands.hs`. (2026-06-06)
- [x] **M2-2**: Add the three `switch` flags to `listParser` with help text. (2026-06-06)
- [x] **M2-3**: Update the `listInfo` footer to document the new flags. (2026-06-06)
- [x] **M2-4**: Update the `List` dispatch in `seihou-cli/src-exe/Main.hs` to translate the three booleans into `[RunnableKind]` and pass them to `ListFilter` (added `RunnableKind (..)` import). (2026-06-06)
- [x] **M2-5**: Build the executable — `cabal build seihou`. (2026-06-06)
- [x] **M3-1**: Update `mkEntry` and `noFilter` in `seihou-cli/test/Seihou/CLI/ListSpec.hs` for the new fields (added kind-aware `mkEntryK`; threaded `[]` through existing positional `ListFilter` calls). (2026-06-06)
- [x] **M3-2**: Add `applyFilters` unit tests for each single kind, a union of two kinds, kind+repo AND, and empty-result cases; extended blueprint test to assert `entryKind`. (2026-06-06)
- [x] **M3-3**: Run the full test suite — `cabal test all` — 863 core + 233 CLI tests pass. (2026-06-06)
- [x] **M4-1**: Manual end-to-end verification of `--modules`, `--recipes`, `--blueprints`, combined flags, and `--help`. (2026-06-06)
- [x] **M4-2**: Fill in Outcomes & Retrospective. (2026-06-06)


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- One pre-existing test asserted the stale header literal `"Available modules and
  recipes:"` (`ListSpec.hs:79`). Since M1 corrected the header to include
  blueprints, this test failed until updated. Evidence:

  ```text
  1 out of 233 tests failed (20.33s)
  ```

  Fixed by updating the assertion to the new header. The plan had anticipated the
  header change but not this specific test dependency — recorded here for the next
  contributor.

- `defaultSearchPaths` includes the developer's real `~/.config/seihou/modules/`
  and installed paths, so manual `seihou list` counts in a sandbox are larger than
  the artifacts created locally (19 total, not 3). The union arithmetic still
  validates the filter: 13 modules + 2 recipes + 4 blueprints = 19, and
  `--modules --recipes` reported 15 = 13 + 2. Evidence:

  ```text
  list --modules            -> 13 modules found ... [filtered: kind=module]
  list --recipes            ->  2 modules found ... [filtered: kind=recipe]
  list --blueprints         ->  4 modules found ... [filtered: kind=blueprint]
  list --modules --recipes  -> 15 modules found ... [filtered: kind=module+recipe]
  ```

- The summary count noun stays "module(s)" regardless of the active kind filter
  (it is driven by entry count, not kind). This was anticipated in the plan's
  Validation note 2 and left out of scope; the `[filtered: kind=...]` suffix
  disambiguates. A kind-aware count noun remains a possible future enhancement.


## Decision Log

- Decision: Expose kind filtering as three boolean switch flags (`--modules`,
  `--recipes`, `--blueprints`) rather than a single valued option like
  `--kind <module|recipe|blueprint>`.
  Rationale: The user explicitly asked for "flags to only list modules, or only
  list blueprints or only list recipes." Switches read naturally on the command
  line and compose into a union without quoting. A single `--kind` option was
  considered but rejected because it cannot express "modules and recipes" without
  repetition and is wordier for the common single-kind case.
  Date: 2026-06-06

- Decision: When no kind flag is passed, show all kinds (current behavior).
  Multiple kind flags form a union (OR among kinds); the resulting kind set then
  combines with `--repo` and `--tag` using AND.
  Rationale: Backward compatible — existing `seihou list` invocations are
  unchanged. Union-of-kinds is the only sensible meaning of passing two kind
  flags, and AND-across-filter-dimensions matches the existing repo/tag behavior
  in `applyFilters`.
  Date: 2026-06-06

- Decision: Carry the kind on the `Entry` record (`entryKind :: RunnableKind`) and
  filter in the existing pure `applyFilters` function, rather than filtering the
  `[DiscoveredRunnable]` list before conversion.
  Rationale: Keeps all filtering in one place (`applyFilters`), consistent with
  how `--repo` and `--tag` already work, and keeps the filter logic pure and unit
  testable without IO. `RunnableKind` is already imported into `List.hs` and
  derives `Eq`/`Show`, so adding it to `Entry` is cheap.
  Date: 2026-06-06

- Decision: Update the listing header from "Available modules and recipes:" to
  "Available modules, recipes, and blueprints:".
  Rationale: The listing already includes blueprints; the header was stale. While
  touching this area for kind filtering, correct the header so it matches reality.
  Date: 2026-06-06


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

**Achieved.** `seihou list` now accepts `--modules`, `--recipes`, and
`--blueprints` switches that restrict the listing by artifact kind. With no flag
the command behaves exactly as before (all kinds). Multiple flags form a union,
and kind combines with `--repo`/`--tag` via AND. Each invocation annotates its
summary line with the active kind filter (e.g. `[filtered: kind=module+recipe]`).
The stale header was corrected to `Available modules, recipes, and blueprints:`.

This matches the original purpose: a user can now ask for only modules, only
recipes, or only blueprints, verified end-to-end against a sandbox containing one
of each kind.

**Verification.** `cabal test all` passes (863 core + 233 CLI). The CLI module
placement check passes (`OK: 27 modules in executable other-modules, all
justified`) — the library/executable split was preserved: parser switches live in
the executable, filtering logic in the internal library, bridged in `Main.hs`.

**Gaps / future work.** The summary count noun is always "module(s)" regardless of
the active kind filter. This was intentionally out of scope; the `[filtered:
kind=...]` suffix disambiguates. A kind-aware count noun (e.g. "1 blueprint found")
is a candidate future enhancement.

**Lessons.** Carrying the kind on the `Entry` record and filtering in the existing
pure `applyFilters` kept the change small, testable without IO, and consistent
with how `--repo`/`--tag` already worked. The only friction was a pre-existing test
pinned to the old header literal; correcting display strings warrants a quick grep
of the test tree first.


## Context and Orientation

This repository is a multi-package Haskell workspace (GHC, Cabal, Nix). Two Cabal
targets matter here, both under `seihou-cli/`:

- The **internal library** `seihou-cli-internal` lives at `seihou-cli/src/`. It
  holds reusable CLI logic and is the target the test suite links against. It
  deliberately does **not** depend on `optparse-applicative`.
- The **executable** `seihou` lives at `seihou-cli/src-exe/`. It holds `Main.hs`,
  the command-line parser, and command dispatchers. This is where
  `optparse-applicative` (the command-line parsing library) is used.

This split is a project convention (see `CLAUDE.md` and
`docs/dev/architecture/overview.md`, "CLI Module Placement Convention"). The
practical consequence for this plan: the parser types and switches live in the
executable, while the filtering data type and logic live in the library, and they
are bridged in `Main.hs`.

The relevant files and their current roles:

- `seihou-core/src/Seihou/Core/Module.hs` — defines artifact discovery. The type
  `RunnableKind = KindModule | KindRecipe | KindBlueprint` (around line 378) tags
  what was found. The function `discoverAllRunnables :: [FilePath] -> IO
  [DiscoveredRunnable]` (around line 395) walks every search path and returns one
  `DiscoveredRunnable` per artifact, each carrying `drKind :: RunnableKind`,
  `drName`, `drDescription`, `drSource`, `drDir`, `drIsError`, and `drError`.
  **No change is needed in this file** — discovery already classifies everything.

- `seihou-cli/src/Seihou/CLI/List.hs` — the library-side list logic. It defines:
  - `data ListFilter = ListFilter { filterRepo :: Maybe Text, filterTag :: Maybe
    Text }` and `noFilter = ListFilter Nothing Nothing`.
  - `data Entry = Entry { entryName, entryDesc, entrySource, entryIsError,
    entryRepoName, entryTags }` — the display record. Note the kind is **not** on
    `Entry` today; it is only baked into `entrySource` as a suffix string (e.g.
    `"project [blueprint]"`) by `runnableToEntryWithOrigin`.
  - `runnableToEntryWithOrigin :: Map FilePath (Maybe OriginInfo) ->
    DiscoveredRunnable -> Entry` — converts a discovered runnable into an `Entry`,
    appending `" [recipe]"`/`" [blueprint]"` to the source label based on
    `dr.drKind`.
  - `applyFilters :: ListFilter -> [Entry] -> [Entry]` — pure filter; `--repo` and
    `--tag` each combine with AND.
  - `formatFilterSuffix :: ListFilter -> Text` — builds the ` [filtered: ...]` /
    summary annotation describing active filters.
  - `handleList :: ListFilter -> IO ()` — the IO entry point: discovers runnables,
    reads origin metadata, converts to entries, applies filters, prints output.
  - `formatListOutput` and `formatListOutputEntries` — rendering. The header text
    `"Available modules and recipes:"` is in `formatListOutputEntries`.

- `seihou-cli/src-exe/Seihou/CLI/Commands.hs` — the command-line parser. It
  defines the `Command` ADT (with constructor `List ListOpts`, around line 61) and
  `data ListOpts = ListOpts { listRepo :: Maybe Text, listTag :: Maybe Text }`
  (around line 208). The parser `listParser` (around line 586) builds a `List`
  command, and `listInfo` (around line 567) holds the `--help` description/footer.

- `seihou-cli/src-exe/Main.hs` — dispatch. Around line 58 it matches
  `List listOpts -> handleList (ListFilter listOpts.listRepo listOpts.listTag)`.
  This is the bridge between the parser's `ListOpts` (executable) and the library's
  `ListFilter`.

- `seihou-cli/test/Seihou/CLI/ListSpec.hs` — Hspec/Tasty unit tests for `List.hs`.
  It builds `Entry` values via a `mkEntry` helper and `ListFilter` values
  positionally (e.g. `ListFilter Nothing Nothing`). Adding fields to either record
  requires updating these helpers and constructor calls.

Term definitions used in this plan:

- **Switch flag** — an `optparse-applicative` `switch`: a boolean flag that is
  `True` when present and `False` when absent (e.g. `--modules`). Contrast with an
  `option`, which takes a value (e.g. `--repo foo`).
- **Union** — the set-theoretic OR. "Modules ∪ recipes" means an entry is kept if
  it is a module *or* a recipe.


## Plan of Work

The work divides into three implementation milestones plus a verification
milestone. Milestone 1 is library-only and independently buildable. Milestone 2
adds the parser surface and wires it through. Milestone 3 covers tests. Milestone
4 is manual end-to-end verification.

### Milestone 1 — Library: carry and filter by kind

At the end of this milestone, the library `seihou-cli-internal` knows how to filter
a list of entries by kind, even though no command-line flag yet sets that filter.
It builds in isolation and the existing tests still pass (after the small helper
updates, which are in Milestone 3 — so until then expect `cabal build
seihou-cli-internal` to succeed but `cabal test` to fail to compile; that is
acceptable mid-milestone and resolved in M3).

Edits, all in `seihou-cli/src/Seihou/CLI/List.hs`:

1. Add a kind field to `Entry`:

   ```haskell
   data Entry = Entry
     { entryName :: Text,
       entryDesc :: Text,
       entrySource :: Text,
       entryIsError :: Bool,
       entryRepoName :: Maybe Text,
       entryTags :: [Text],
       entryKind :: RunnableKind
     }
     deriving stock (Eq, Show)
   ```

   `RunnableKind` is already imported from `Seihou.Core.Module` at the top of the
   file, and it already derives `Eq` and `Show`, so the `deriving stock (Eq, Show)`
   on `Entry` continues to work.

2. In `runnableToEntryWithOrigin`, set `entryKind = dr.drKind` in both the error
   branch and the success branch (the two `Entry { ... }` literals).

3. In `toEntryWithOrigin` (which converts a `DiscoveredModule`, used by the
   backward-compatible `formatListOutput` and by `toEntry`), set
   `entryKind = KindModule` in both the `Right` and `Left` branches. A
   `DiscoveredModule` is always a module, so this is correct.

4. Extend `ListFilter`:

   ```haskell
   data ListFilter = ListFilter
     { filterRepo :: Maybe Text,
       filterTag :: Maybe Text,
       filterKinds :: [RunnableKind]
     }
     deriving stock (Eq, Show)
   ```

   and update `noFilter`:

   ```haskell
   noFilter :: ListFilter
   noFilter = ListFilter Nothing Nothing []
   ```

   An empty `filterKinds` means "no kind restriction — show all kinds."

5. Extend `applyFilters` with a kind predicate:

   ```haskell
   applyFilters :: ListFilter -> [Entry] -> [Entry]
   applyFilters opts = filter match
     where
       match entry = repoMatch entry && tagMatch entry && kindMatch entry
       repoMatch entry = case opts.filterRepo of
         Nothing -> True
         Just r -> entry.entryRepoName == Just r
       tagMatch entry = case opts.filterTag of
         Nothing -> True
         Just t -> t `elem` entry.entryTags
       kindMatch entry = case opts.filterKinds of
         [] -> True
         ks -> entry.entryKind `elem` ks
   ```

6. Extend `formatFilterSuffix` so the summary line records the active kind filter.
   Render each kind with a lowercase singular noun (`module`, `recipe`,
   `blueprint`):

   ```haskell
   formatFilterSuffix :: ListFilter -> Text
   formatFilterSuffix opts =
     let parts =
           maybe [] (\r -> ["repo=" <> r]) opts.filterRepo
             <> maybe [] (\t -> ["tag=" <> t]) opts.filterTag
         kindPart = case opts.filterKinds of
           [] -> []
           ks -> ["kind=" <> T.intercalate "+" (map kindNoun ks)]
      in if null parts && null kindPart
           then ""
           else " [filtered: " <> T.intercalate ", " (parts <> kindPart) <> "]"
     where
       kindNoun KindModule = "module"
       kindNoun KindRecipe = "recipe"
       kindNoun KindBlueprint = "blueprint"
   ```

   Note: this changes the summary annotation from `[filtered: ...]` consistently;
   the existing repo/tag-only behavior is preserved when `filterKinds` is empty.

7. While here, fix the stale header in `formatListOutputEntries`: change
   `"Available modules and recipes:\n"` to
   `"Available modules, recipes, and blueprints:\n"`.

Build to confirm the library compiles:

```bash
cabal build seihou-cli-internal
```

Expected: a successful build with no errors. (Test compilation is deferred to M3.)

### Milestone 2 — Parser: add the flags and wire them through

At the end of this milestone, `seihou list --modules`, `--recipes`, and
`--blueprints` parse, appear in `seihou list --help`, and actually restrict the
output. The whole executable builds.

Edits in `seihou-cli/src-exe/Seihou/CLI/Commands.hs`:

1. Extend `ListOpts` (around line 208):

   ```haskell
   data ListOpts = ListOpts
     { listRepo :: Maybe Text,
       listTag :: Maybe Text,
       listModulesOnly :: Bool,
       listRecipesOnly :: Bool,
       listBlueprintsOnly :: Bool
     }
   ```

2. Extend `listParser` (around line 586) to populate the new fields with switches:

   ```haskell
   listParser :: Parser Command
   listParser =
     fmap List $
       ListOpts
         <$> optional (option (T.pack <$> str) (long "repo" <> metavar "REPO" <> help "Filter by repository name"))
         <*> optional (option (T.pack <$> str) (long "tag" <> metavar "TAG" <> help "Filter by tag"))
         <*> switch (long "modules" <> help "Show only modules")
         <*> switch (long "recipes" <> help "Show only recipes")
         <*> switch (long "blueprints" <> help "Show only blueprints")
   ```

3. Update the `listInfo` footer (around line 567) so `--help` documents the new
   flags. Add a line after the existing `--repo`/`--tag` mention, for example:

   ```haskell
   pretty ("Use --repo and --tag to filter the output." :: String),
   pretty ("Use --modules, --recipes, and --blueprints to restrict by kind" :: String),
   pretty ("(combine them to show several kinds; omit all to show every kind)." :: String)
   ```

Edit in `seihou-cli/src-exe/Main.hs` (around line 58). Replace the single-line
`List` dispatch with one that translates the three booleans into a `[RunnableKind]`
and passes it as the third `ListFilter` argument:

```haskell
    List listOpts ->
      let kinds =
            [KindModule | listOpts.listModulesOnly]
              <> [KindRecipe | listOpts.listRecipesOnly]
              <> [KindBlueprint | listOpts.listBlueprintsOnly]
       in handleList (ListFilter listOpts.listRepo listOpts.listTag kinds)
```

This requires importing the `RunnableKind` constructors into `Main.hs`. Check the
existing import of `Seihou.Core.Module` (or add one) and ensure
`RunnableKind (..)` is brought into scope. If `Main.hs` does not already import
`Seihou.Core.Module`, add:

```haskell
import Seihou.Core.Module (RunnableKind (..))
```

(When no kind flag is given, all three booleans are `False`, `kinds` is `[]`, and
`applyFilters` keeps every kind — preserving current behavior.)

Build the executable:

```bash
cabal build seihou
```

Expected: a clean build.

### Milestone 3 — Tests

At the end of this milestone the test suite compiles and passes, including new
coverage for kind filtering. Edits in
`seihou-cli/test/Seihou/CLI/ListSpec.hs`.

1. Update `mkEntry` to set a kind. Make it kind-aware so kind tests can use it.
   Change its signature to accept a `RunnableKind`, or add a second helper. The
   simplest approach that keeps existing call sites working is to give the existing
   `mkEntry` a default kind of `KindModule` and add a `mkEntryK` that takes a kind:

   ```haskell
   mkEntry :: T.Text -> Maybe T.Text -> [T.Text] -> Entry
   mkEntry name repo tags = mkEntryK KindModule name repo tags

   mkEntryK :: RunnableKind -> T.Text -> Maybe T.Text -> [T.Text] -> Entry
   mkEntryK kind name repo tags =
     Entry
       { entryName = name,
         entryDesc = "desc",
         entrySource = "installed",
         entryIsError = False,
         entryRepoName = repo,
         entryTags = tags,
         entryKind = kind
       }
   ```

   `RunnableKind (..)` is already imported in this test module.

2. Update the local `noFilter` helper:

   ```haskell
   noFilter :: ListFilter
   noFilter = ListFilter Nothing Nothing []
   ```

3. Update every positional `ListFilter` construction in the existing tests to pass
   the new third argument `[]` (no kind restriction). There are several:
   `ListFilter (Just "repo-x") Nothing`, `ListFilter Nothing (Just "haskell")`,
   `ListFilter (Just "repo-x") (Just "haskell")`, `ListFilter (Just "nonexistent")
   Nothing`, and `ListFilter Nothing (Just "ruby")`. Each becomes
   `ListFilter ... ... []`.

4. Add a new `describe "applyFilters (by kind)"` block. Build a mixed-kind entry
   list and assert:

   ```haskell
   describe "applyFilters (by kind)" $ do
     let mixed =
           [ mkEntryK KindModule "mod-a" Nothing [],
             mkEntryK KindRecipe "rec-a" Nothing [],
             mkEntryK KindBlueprint "bp-a" Nothing [],
             mkEntryK KindModule "mod-b" (Just "repo-x") ["haskell"]
           ]

     it "keeps all kinds when filterKinds is empty" $ do
       length (applyFilters (ListFilter Nothing Nothing []) mixed) `shouldBe` 4

     it "keeps only modules with --modules" $ do
       let result = applyFilters (ListFilter Nothing Nothing [KindModule]) mixed
       map (.entryName) result `shouldBe` ["mod-a", "mod-b"]

     it "keeps only recipes with --recipes" $ do
       let result = applyFilters (ListFilter Nothing Nothing [KindRecipe]) mixed
       map (.entryName) result `shouldBe` ["rec-a"]

     it "keeps only blueprints with --blueprints" $ do
       let result = applyFilters (ListFilter Nothing Nothing [KindBlueprint]) mixed
       map (.entryName) result `shouldBe` ["bp-a"]

     it "unions kinds when several flags are given" $ do
       let result = applyFilters (ListFilter Nothing Nothing [KindModule, KindRecipe]) mixed
       map (.entryName) result `shouldBe` ["mod-a", "rec-a", "mod-b"]

     it "combines kind and repo with AND" $ do
       let result = applyFilters (ListFilter (Just "repo-x") Nothing [KindModule]) mixed
       map (.entryName) result `shouldBe` ["mod-b"]

     it "returns empty when kind matches nothing in the set" $ do
       let onlyRecipes = filter (\e -> e.entryKind == KindRecipe) mixed
           result = applyFilters (ListFilter Nothing Nothing [KindBlueprint]) onlyRecipes
       result `shouldBe` []
   ```

5. (Optional but recommended) Extend the existing
   `runnableToEntryWithOrigin (blueprint)` test to also assert
   `entry.entryKind == KindBlueprint`, proving the kind is carried through from the
   discovered runnable.

Run the suite:

```bash
cabal test all
```

Expected: all tests pass. Record the exact module/recipe/blueprint test counts in
Progress and Outcomes (the prior baseline reported in `enhance-list-filtering.md`
was 650 core + 63 CLI; the count here will be higher because of the new cases).

### Milestone 4 — Manual end-to-end verification

Exercise the real binary as a user would. See "Validation and Acceptance" for the
exact transcript expectations.


## Concrete Steps

Run all commands from the repository root
`/Users/shinzui/Keikaku/bokuno/seihou-project/seihou` unless stated otherwise.

Milestone 1 (library):

```bash
cabal build seihou-cli-internal
```

Expected tail:

```text
[n of m] Compiling Seihou.CLI.List ...
Linking ... (or up to date)
```

Milestone 2 (executable):

```bash
cabal build seihou
```

Expected: clean build, no parser/type errors.

Inspect the help to confirm flags are registered:

```bash
cabal run seihou -- list --help
```

Expected to include lines resembling:

```text
  --modules                Show only modules
  --recipes                Show only recipes
  --blueprints             Show only blueprints
```

Milestone 3 (tests):

```bash
cabal test all
```

Expected: a passing summary, e.g. `All N tests passed`. Record the number.

Milestone 4 (manual). With at least one module, one recipe, and one blueprint
installed (or present in `.seihou/modules/`):

```bash
cabal run seihou -- list
cabal run seihou -- list --modules
cabal run seihou -- list --recipes
cabal run seihou -- list --blueprints
cabal run seihou -- list --modules --recipes
```

Compare against the acceptance transcripts below.


## Validation and Acceptance

Acceptance is behavioral. After implementation:

1. `seihou list` (no kind flag) lists every kind, exactly as before this change.
   The header reads `Available modules, recipes, and blueprints:` and the summary
   line carries no `kind=` annotation.

2. `seihou list --blueprints` shows only entries whose source label ends in
   `[blueprint]`; no plain modules and no `[recipe]` entries appear. The summary
   line ends with ` [filtered: kind=blueprint]`. For example:

   ```text
   Available modules, recipes, and blueprints:

     demo-agent   An AI-assisted scaffold   (installed) [blueprint]

   1 blueprint found (3 sources searched) [filtered: kind=blueprint]
   ```

   Note: the count noun in the existing summary code is driven by entry count and
   currently always says "module(s)"; do not change that pluralization logic in
   this plan — only the `[filtered: ...]` suffix needs to reflect kind. (If a
   reader wants kind-aware count nouns, that is a separate enhancement; record it
   as a future item, not part of this plan.)

3. `seihou list --modules` shows only modules (no `[recipe]` or `[blueprint]`
   suffixes), with ` [filtered: kind=module]` in the summary.

4. `seihou list --recipes` shows only recipes, with ` [filtered: kind=recipe]`.

5. `seihou list --modules --recipes` shows modules and recipes but no blueprints,
   with ` [filtered: kind=module+recipe]`.

6. `seihou list --blueprints --repo someRepo` shows only blueprints that also came
   from `someRepo`, demonstrating AND across the kind and repo dimensions.

7. `seihou list --help` documents `--modules`, `--recipes`, and `--blueprints`.

8. Unit tests in `seihou-cli/test/Seihou/CLI/ListSpec.hs` cover: empty filter keeps
   all kinds; each single kind; a two-kind union; kind+repo AND; and an empty
   result. `cabal test all` passes.

The decisive proof beyond compilation is steps 2–6: the same installed artifacts
produce different listings depending solely on the kind flags, and the summary
line names the active kind filter.


## Idempotence and Recovery

All edits are additive field/flag additions and a pure predicate extension; they
can be re-applied safely. If a build fails because a positional `ListFilter` or
`ListOpts` constructor call was missed, the compiler will name the exact file and
line with an arity mismatch — add the missing argument (`[]` for `filterKinds`, or
`False` for an omitted switch field) and rebuild. The change touches no on-disk
state, no manifest, and no network; rerunning `seihou list` with any flag
combination is read-only and side-effect-free. To revert, `git checkout` the four
touched files (`Module.hs` is not touched): `List.hs`, `Commands.hs`, `Main.hs`,
and `ListSpec.hs`.


## Interfaces and Dependencies

No new library dependencies. The change relies only on existing imports.

Types and signatures that must exist at the end of the milestones:

- After M1, in `seihou-cli/src/Seihou/CLI/List.hs`:
  - `data Entry = Entry { ..., entryKind :: RunnableKind }` deriving `Eq`, `Show`.
  - `data ListFilter = ListFilter { filterRepo :: Maybe Text, filterTag :: Maybe
    Text, filterKinds :: [RunnableKind] }` deriving `Eq`, `Show`.
  - `noFilter :: ListFilter` = `ListFilter Nothing Nothing []`.
  - `applyFilters :: ListFilter -> [Entry] -> [Entry]` (now also filtering by kind).

- After M2, in `seihou-cli/src-exe/Seihou/CLI/Commands.hs`:
  - `data ListOpts = ListOpts { listRepo :: Maybe Text, listTag :: Maybe Text,
    listModulesOnly :: Bool, listRecipesOnly :: Bool, listBlueprintsOnly :: Bool }`.
  - `listParser :: Parser Command` populating all five fields.

  And in `seihou-cli/src-exe/Main.hs`:
  - The `List listOpts ->` dispatch builds `[RunnableKind]` from the three booleans
    and calls `handleList (ListFilter listOpts.listRepo listOpts.listTag kinds)`.
    `RunnableKind (..)` must be in scope (imported from `Seihou.Core.Module`).

- `RunnableKind = KindModule | KindRecipe | KindBlueprint` in
  `seihou-core/src/Seihou/Core/Module.hs` is used unchanged; it already derives
  `Eq`, `Show`, `Generic`.

The library/executable split must be respected: the parser switches live in the
executable (`optparse-applicative`), the `ListFilter`/`Entry`/`applyFilters` logic
lives in the internal library, and `Main.hs` bridges them. Adding kind parsing in
the executable and kind filtering in the library keeps
`nix/check-cli-module-placement.sh` satisfied because no library module gains a
trapped dependency.
