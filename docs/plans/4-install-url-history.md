# Add install URL history with FZF selection

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This document is maintained in accordance with `.claude/skills/exec-plan/PLANS.md`.


## Purpose / Big Picture

After this change, `seihou install` remembers every git URL that was successfully used
for installation. When a user runs `seihou install` **without** a URL argument, the CLI
reads the URL history and presents an FZF menu (with a numbered-prompt fallback) so the
user can pick a previously used source. This removes the need to re-type or look up URLs
for repos the user has installed from before.

**User-visible behavior after implementation:**

1. `seihou install https://github.com/foo/bar.git` — works as before, and records the
   URL in `~/.config/seihou/install-history.json`.
2. `seihou install` (no URL) — opens an FZF picker showing previously used URLs, most
   recent first. Selecting one proceeds with the normal install flow. If FZF is
   unavailable, a numbered prompt is shown instead.
3. If history is empty and no URL is given, the CLI prints an error with a hint.


## Progress

- [x] **M1-1**: Add `Seihou.CLI.InstallHistory` module with types and IO helpers (2026-04-07)
- [x] **M1-2**: Add `FromJSON` / `ToJSON` instances for history entry type (2026-04-07)
- [x] **M1-3**: Wire history recording into `handleInstall` (write after successful install) (2026-04-07)
- [x] **M1-4**: Add unit tests for history read/write round-trip (2026-04-07)
- [x] **M2-1**: Make `installSource` field optional (`Maybe Text`) in `InstallOpts` (2026-04-07)
- [x] **M2-2**: Update `installParser` to accept an optional positional argument (2026-04-07)
- [x] **M2-3**: Add `resolveSource` function: if source is `Nothing`, load history and run FZF selection (2026-04-07)
- [x] **M2-4**: Add numbered-prompt fallback for non-FZF environments (2026-04-07)
- [x] **M2-5**: Wire `resolveSource` into `handleInstall` at the top of the function (2026-04-07)
- [x] **M2-6**: Add unit tests for `InstallHistory` round-trip and `resolveSource` pure logic (2026-04-07)
- [ ] **M3-1**: Manual smoke test: install a module, then re-run `seihou install` to see history
- [x] **M3-2**: Register new module in cabal files and test harness (2026-04-07)
- [x] **M3-3**: Verify existing tests still pass — 660 core + 106 CLI tests pass (2026-04-07)


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Store history in a standalone JSON file at `~/.config/seihou/install-history.json`
  rather than scanning `.seihou-origin.json` files across installed modules.
  Rationale: Origin files only exist for currently-installed modules. If a user installs
  then removes a module, the URL would be lost. A dedicated history file persists across
  removals and is simpler to read/write atomically.
  Date: 2026-04-07

- Decision: Make the positional `GIT-URL` argument optional (`Maybe Text`) rather than
  adding a separate subcommand.
  Rationale: This preserves backward compatibility — existing `seihou install <url>`
  invocations work unchanged. The only change is that omitting the URL now triggers the
  history picker instead of an error.
  Date: 2026-04-07

- Decision: Deduplicate URLs in history by source URL, keeping the most recent entry.
  Rationale: Users don't want to see the same URL multiple times. The most-recent-first
  ordering is the most useful default.
  Date: 2026-04-07

- Decision: Cap history at 50 entries to keep the file and FZF menu manageable.
  Rationale: 50 is more than enough for any realistic usage pattern.
  Date: 2026-04-07


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

### Current install flow

The `seihou install` command is implemented across three key locations:

- **CLI parser**: `seihou-cli/src/Seihou/CLI/Commands.hs` lines 582–589. The `installParser`
  function defines `InstallOpts` with a **required** positional `GIT-URL` argument, plus
  optional `--name`, `--module`, and `--all` flags.

- **`InstallOpts` type**: `seihou-cli/src/Seihou/CLI/Commands.hs` lines 115–121:
  ```haskell
  data InstallOpts = InstallOpts
    { installSource :: Text,        -- required git URL
      installName :: Maybe Text,
      installModules :: [Text],
      installAll :: Bool
    }
  ```

- **Handler**: `seihou-cli/src/Seihou/CLI/Install.hs`. The `handleInstall` function
  takes `InstallOpts`, clones the repo from `iopts.installSource`, discovers its contents
  (single-module or multi-module registry), validates, then copies to
  `~/.config/seihou/installed/<name>/` and writes `.seihou-origin.json` metadata.

### XDG config directory

All user-global seihou data lives under `~/.config/seihou/` (via `getXdgDirectory XdgConfig "seihou"`).
Installed modules go in `~/.config/seihou/installed/<name>/`. The history file will live
alongside at `~/.config/seihou/install-history.json`.

### FZF integration

FZF is already integrated into seihou:

- **`Seihou.Fzf`** (`seihou-cli/src/Seihou/Fzf.hs`): Core types (`FzfConfig`, `FzfOpts`,
  `Candidate`, `FzfResult`) and `runFzf` subprocess driver.
- **`Seihou.Effect.Fzf`** (`seihou-cli/src/Seihou/Effect/Fzf.hs`): Effectful interface
  with `selectOne` operation.
- **`Seihou.Effect.FzfInterp`** (`seihou-cli/src/Seihou/Effect/FzfInterp.hs`): IO and
  pure interpreters.
- **Existing usage**: `Install.hs` lines 170–191 use FZF for multi-module registry
  selection with `detectFzfConfig`, `isFzfUsable`, `fzfModuleSelection`, and a
  `promptModuleSelection` fallback.

### `.seihou-origin.json`

Written to each installed module dir. Contains `sourceUrl`, `repoName`, `installedAt`,
`version`, and `tags`. This is **not** the right place to store history because modules
can be removed.

### Build system

- Two cabal packages: `seihou-core` (library) and `seihou-cli` (executable + internal library + tests).
- `seihou-cli-internal` exposes modules for testing. New modules need to be added to both
  `exposed-modules` (internal library) and `other-modules` (executable).
- Tests use `tasty` + `tasty-hspec` + `hspec`. Test modules registered in
  `seihou-cli/test/Main.hs`.
- `aeson` is available in `seihou-cli` for JSON encode/decode.


## Plan of Work

### Milestone 1: History persistence layer

**Scope**: Create a new module `Seihou.CLI.InstallHistory` that handles reading, writing,
and deduplicating the install URL history file. Wire recording into the existing install
flow so that every successful install appends to history.

**What will exist at the end**: A new file `~/.config/seihou/install-history.json` is
created/updated after each successful `seihou install <url>`. The file contains an array
of `{url, lastUsed}` objects, deduplicated by URL, sorted most-recent-first, capped at 50.

**Acceptance criteria**:
- `seihou install <url>` succeeds and `~/.config/seihou/install-history.json` contains an
  entry for that URL.
- Repeating the same URL updates `lastUsed` instead of creating a duplicate.
- Unit tests pass for round-trip serialization and deduplication logic.

#### Edits

**New file: `seihou-cli/src/Seihou/CLI/InstallHistory.hs`**

```haskell
module Seihou.CLI.InstallHistory
  ( HistoryEntry (..),
    InstallHistory (..),
    readHistory,
    writeHistory,
    recordUrl,
    maxHistoryEntries,
  )
where
```

Define:

```haskell
data HistoryEntry = HistoryEntry
  { url :: Text,
    lastUsed :: Text  -- ISO8601 timestamp
  }
  deriving stock (Eq, Show, Generic)

instance FromJSON HistoryEntry
instance ToJSON HistoryEntry

newtype InstallHistory = InstallHistory
  { entries :: [HistoryEntry] }
  deriving stock (Eq, Show, Generic)

instance FromJSON InstallHistory
instance ToJSON InstallHistory

maxHistoryEntries :: Int
maxHistoryEntries = 50

-- | Path to the history file: ~/.config/seihou/install-history.json
historyFilePath :: IO FilePath
historyFilePath = do
  base <- getXdgDirectory XdgConfig "seihou"
  pure (base </> "install-history.json")

-- | Read history from disk. Returns empty history if file doesn't exist or is malformed.
readHistory :: IO InstallHistory
readHistory = do
  path <- historyFilePath
  exists <- doesFileExist path
  if not exists
    then pure (InstallHistory [])
    else do
      bs <- BS.readFile path
      case eitherDecodeStrict' bs of
        Left _ -> pure (InstallHistory [])
        Right h -> pure h

-- | Write history to disk, creating parent directories if needed.
writeHistory :: InstallHistory -> IO ()
writeHistory history = do
  path <- historyFilePath
  createDirectoryIfMissing True (takeDirectory path)
  LBS.writeFile path (encodePretty history)

-- | Record a URL in history. Deduplicates by URL, updates timestamp, keeps most-recent-first, caps at maxHistoryEntries.
recordUrl :: Text -> IO ()
recordUrl url = do
  now <- getCurrentTime
  history <- readHistory
  let timestamp = T.pack (iso8601Show now)
      newEntry = HistoryEntry url timestamp
      filtered = filter (\e -> e.url /= url) history.entries
      updated = take maxHistoryEntries (newEntry : filtered)
  writeHistory (InstallHistory updated)
```

**Edit: `seihou-cli/src/Seihou/CLI/Install.hs`**

In `handleInstall`, after a successful install completes (after the `case contents of`
block succeeds), call `recordUrl source` to persist the URL. Specifically:

- Import `Seihou.CLI.InstallHistory (recordUrl)` at the top of the file.
- In `handleInstall`, after the entire `withSystemTempDirectory` block succeeds
  (all branches that don't call `exitFailure`), call `recordUrl iopts.installSource`.

The cleanest approach: wrap the success paths so that `recordUrl` is called after the
temp directory block returns normally. Since `exitFailure` throws an exception, the
`recordUrl` call after `withSystemTempDirectory` only runs on success.

Add after line 75 (the close of `withSystemTempDirectory`), before the function ends:

```haskell
  -- Record URL in history for future recall
  recordUrl (iopts.installSource)
```

Wait — `installSource` will become `Maybe Text` in M2, so we need to be careful. For M1,
`installSource` is still `Text`, so this is safe. In M2 we'll adjust to use the resolved
source.

**Edit: `seihou-cli/seihou-cli.cabal`**

Add `Seihou.CLI.InstallHistory` to both:
- `exposed-modules` in the `seihou-cli-internal` library section (for testing)
- `other-modules` in the `executable seihou` section

**New test file: `seihou-cli/test/Seihou/CLI/InstallHistorySpec.hs`**

Test:
- Round-trip: `writeHistory` then `readHistory` returns the same data.
- `recordUrl` deduplicates: record same URL twice, history has one entry with updated
  timestamp.
- `recordUrl` caps at `maxHistoryEntries`: record 51 URLs, history has exactly 50.
- `readHistory` on missing file returns empty history.
- `readHistory` on malformed file returns empty history.

Since the functions use XDG paths, tests should use a temp directory and set
`XDG_CONFIG_HOME` via `System.Environment.setEnv` / `System.Environment.unsetEnv`,
or alternatively the tests can operate on `writeHistory`/`readHistory` at a known temp
path. The simplest approach: extract `readHistoryFrom :: FilePath -> IO InstallHistory`
and `writeHistoryTo :: FilePath -> InstallHistory -> IO ()` helpers that take an explicit
path, and have `readHistory`/`writeHistory` call those with the XDG-derived path. Tests
use the `*From`/`*To` variants with a temp directory.

**Edit: `seihou-cli/test/Main.hs`**

Add `Seihou.CLI.InstallHistorySpec` import and wire into the test list.


### Milestone 2: Optional URL argument with history-based FZF picker

**Scope**: Make the `GIT-URL` positional argument optional. When omitted, load history
and present an FZF selection menu (or numbered fallback). Wire the resolved URL back into
the existing install flow.

**What will exist at the end**: Running `seihou install` with no arguments shows a
picker of previously used URLs. Selecting one proceeds normally. If history is empty,
an error message with a hint is shown.

**Acceptance criteria**:
- `seihou install` (no URL, with history) shows FZF picker of URLs, most recent first.
- Selecting a URL proceeds with normal install.
- `seihou install` (no URL, empty history) prints an informative error.
- `seihou install <url>` still works as before.
- FZF fallback: numbered prompt works when FZF is unavailable.

#### Edits

**Edit: `seihou-cli/src/Seihou/CLI/Commands.hs` lines 115–121**

Change `installSource` from `Text` to `Maybe Text`:

```haskell
data InstallOpts = InstallOpts
  { installSource :: Maybe Text,  -- was: Text
    installName :: Maybe Text,
    installModules :: [Text],
    installAll :: Bool
  }
```

**Edit: `seihou-cli/src/Seihou/CLI/Commands.hs` lines 582–589**

Change `argument` to `optional`:

```haskell
installParser :: Parser Command
installParser =
  fmap Install $
    InstallOpts
      <$> optional (argument (T.pack <$> str) (metavar "GIT-URL"))
      <*> optional (option (T.pack <$> str) (long "name" <> metavar "NAME" <> help "Override installed module name"))
      <*> many (option (T.pack <$> str) (long "module" <> metavar "MODULE" <> help "Install specific module from registry (repeatable)"))
      <*> switch (long "all" <> help "Install all modules from registry")
```

**Edit: `seihou-cli/src/Seihou/CLI/Install.hs`**

Add a `resolveSource` function and update `handleInstall`:

```haskell
import Seihou.CLI.InstallHistory (readHistory, recordUrl, InstallHistory (..), HistoryEntry (..))

-- | Resolve the install source: use the explicit URL if given, otherwise pick from history.
resolveSource :: Maybe Text -> IO Text
resolveSource (Just url) = pure url
resolveSource Nothing = do
  history <- readHistory
  case history.entries of
    [] -> do
      TIO.putStrLn "No URL specified and no install history found."
      TIO.putStrLn "Usage: seihou install <git-url>"
      exitFailure
    entries -> do
      fzfCfg <- detectFzfConfig
      if isFzfUsable fzfCfg
        then fzfUrlSelection fzfCfg entries
        else promptUrlSelection entries

-- | FZF selection of a URL from history.
fzfUrlSelection :: FzfConfig -> [HistoryEntry] -> IO Text
fzfUrlSelection fzfCfg entries = do
  let candidates =
        [ Candidate
            { candidateDisplay = entry.url,
              candidateValue = entry.url
            }
        | entry <- entries
        ]
      opts = withPrompt "install> " <> withHeader "Select a previously used source:" <> withHeight "40%" <> withAnsi <> withNoSort
  result <- runEff $ runFzfIO fzfCfg $ selectOne opts candidates
  case result of
    FzfSelected url -> pure url
    FzfCancelled -> do
      TIO.putStrLn "Cancelled."
      exitFailure
    FzfNoMatch -> do
      TIO.putStrLn "No match."
      exitFailure
    FzfError err -> do
      TIO.putStrLn $ "fzf error: " <> err <> ", falling back to prompt"
      promptUrlSelection entries

-- | Numbered prompt fallback for URL selection.
promptUrlSelection :: [HistoryEntry] -> IO Text
promptUrlSelection entries = do
  TIO.putStrLn ""
  TIO.putStrLn "Previously used sources:"
  let numbered = zip [1 :: Int ..] entries
  mapM_
    (\(i, entry) -> TIO.putStrLn $ "  " <> T.pack (show i) <> ") " <> entry.url)
    numbered
  TIO.putStrLn ""
  TIO.putStr "Select a source (number): "
  hFlush stdout
  input <- TIO.getLine
  case readMaybe (T.unpack (T.strip input)) of
    Just n | n >= 1 && n <= length entries ->
      pure (entries !! (n - 1)).url
    _ -> do
      TIO.putStrLn "Invalid selection."
      exitFailure
```

Update `handleInstall` to resolve the source first:

```haskell
handleInstall :: InstallOpts -> IO ()
handleInstall iopts = do
  source <- resolveSource iopts.installSource

  TIO.putStrLn $ "Installing from " <> source <> "..."

  withSystemTempDirectory "seihou-install" $ \tmpDir -> do
    -- ... rest unchanged, but use `source` instead of `iopts.installSource` ...

  -- Record URL in history
  recordUrl source
```

All references to `iopts.installSource` inside `handleInstall` change to use the
locally-bound `source`.


### Milestone 3: Integration verification

**Scope**: Ensure all tests pass, manually verify the end-to-end flow, update cabal files.

**Acceptance criteria**:
- `cabal test all` passes.
- `seihou install <url>` creates/updates `~/.config/seihou/install-history.json`.
- `seihou install` (no arg) shows FZF picker with previously used URLs.
- `seihou install --help` shows `[GIT-URL]` as optional.


## Concrete Steps

All commands run from the repository root: `/Users/shinzui/Keikaku/bokuno/seihou-project/seihou`.

### Milestone 1

```bash
# After creating InstallHistory.hs and wiring into Install.hs:
cabal build seihou-cli
```

Expected: builds successfully.

```bash
# After creating InstallHistorySpec.hs and wiring into test Main.hs:
cabal test seihou-cli-test
```

Expected: all tests pass, including the new InstallHistory tests.

### Milestone 2

```bash
# After making installSource optional and adding resolveSource:
cabal build seihou-cli
```

Expected: builds successfully.

```bash
cabal test seihou-cli-test
```

Expected: all tests pass.

```bash
# Verify help text shows optional argument:
cabal run seihou -- install --help
```

Expected output includes `[GIT-URL]` (in brackets, indicating optional).

### Milestone 3

```bash
cabal test all
```

Expected: all tests across both packages pass.

```bash
# Manual smoke test (requires a valid git URL):
cabal run seihou -- install https://github.com/shinzui/seihou-schema.git
cat ~/.config/seihou/install-history.json
# Should show the URL with a timestamp

cabal run seihou -- install
# Should show FZF picker with the URL from above
```


## Validation and Acceptance

1. **Unit tests**: `cabal test seihou-cli-test` passes. Specifically, `InstallHistorySpec`
   verifies:
   - Empty file → empty history
   - Malformed file → empty history
   - Write then read round-trips correctly
   - Duplicate URL updates timestamp, doesn't create duplicate
   - History is capped at 50 entries

2. **CLI argument parsing**: `cabal run seihou -- install --help` shows `[GIT-URL]` as
   optional (square brackets).

3. **End-to-end**:
   - `seihou install <url>` succeeds and `~/.config/seihou/install-history.json` exists
     with the URL.
   - `seihou install` (no URL, with history) shows FZF picker / numbered fallback.
   - `seihou install` (no URL, no history) shows informative error.


## Idempotence and Recovery

- **History file corruption**: `readHistory` silently returns empty history on parse
  failure. The user can delete `~/.config/seihou/install-history.json` to reset.
- **Repeated installs**: `recordUrl` deduplicates, so running the same install multiple
  times just updates the timestamp.
- **File write atomicity**: Consider writing to a temp file and renaming for atomicity,
  but given the small file size and single-user nature, direct write is acceptable for v1.
- **All steps are repeatable**: re-running any milestone from scratch is safe.


## Interfaces and Dependencies

### New module

In `seihou-cli/src/Seihou/CLI/InstallHistory.hs`, define:

```haskell
-- | A single entry in the install URL history.
data HistoryEntry = HistoryEntry
  { url :: Text,
    lastUsed :: Text
  }

-- | The full install history.
newtype InstallHistory = InstallHistory
  { entries :: [HistoryEntry] }

-- | Read history from the XDG config path. Returns empty on missing/malformed file.
readHistory :: IO InstallHistory

-- | Read history from a specific file path (for testing).
readHistoryFrom :: FilePath -> IO InstallHistory

-- | Write history to the XDG config path.
writeHistory :: InstallHistory -> IO ()

-- | Write history to a specific file path (for testing).
writeHistoryTo :: FilePath -> InstallHistory -> IO ()

-- | Record a URL after successful install. Deduplicates, sorts recent-first, caps at 50.
recordUrl :: Text -> IO ()

-- | Record a URL to a specific history file (for testing).
recordUrlTo :: FilePath -> Text -> IO ()

-- | Maximum number of history entries to retain.
maxHistoryEntries :: Int  -- 50
```

### Modified types

In `seihou-cli/src/Seihou/CLI/Commands.hs`:

```haskell
data InstallOpts = InstallOpts
  { installSource :: Maybe Text,  -- changed from Text
    installName :: Maybe Text,
    installModules :: [Text],
    installAll :: Bool
  }
```

### New functions in Install.hs

```haskell
-- | Resolve install source: explicit URL or history-based selection.
resolveSource :: Maybe Text -> IO Text

-- | FZF-based URL selection from history entries.
fzfUrlSelection :: FzfConfig -> [HistoryEntry] -> IO Text

-- | Numbered prompt fallback for URL selection.
promptUrlSelection :: [HistoryEntry] -> IO Text
```

### Libraries used

- `aeson` (already a dependency): `FromJSON`, `ToJSON`, `eitherDecodeStrict'`
- `aeson-pretty` (already a dependency): `encodePretty`
- `directory` (already a dependency): `getXdgDirectory`, `doesFileExist`, `createDirectoryIfMissing`
- `bytestring` (already a dependency): file I/O
- `time` (already a dependency): `getCurrentTime`, `iso8601Show`
- No new dependencies required.
