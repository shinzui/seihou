# Manifest and Incrementality

| Field | Value |
|---|---|
| **Status** | Proposed |
| **Created** | 2026-03-01 |
| **Subsystem** | Core — Manifest |

## Overview

Seihou tracks generated state in a manifest file (`.seihou/manifest.json`). This enables incremental re-generation, conflict detection when users modify generated files, and provenance queries ("which module generated this file?"). The manifest powers a three-state comparison model: manifest (last generated), plan (what would be generated now), and disk (current filesystem).

## Motivation

Without state tracking, a scaffolding tool can only do one-shot generation. Re-running it overwrites everything, including user modifications. The manifest solves this by remembering what was generated, enabling:

- **Incremental updates**: Only regenerate files whose inputs changed
- **Conflict detection**: Know when a user has modified a generated file
- **Provenance**: Answer "which module produced this file?" and "what variables were used?"
- **Status reporting**: Show the relationship between generated and current state

## Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Storage format | JSON | Human-readable, easy to debug, widely tooled |
| Storage location | `.seihou/manifest.json` | Project-local, version-controllable |
| Hashing algorithm | SHA256 | Standard, collision-resistant, fast enough |
| Diff model | Three-state (manifest/plan/disk) | Precise conflict classification without VCS dependency |
| Conflict resolution | Show diff, user decides per-file | Pragmatic for v1; fits plan-first philosophy |
| Incremental support | Day-one | Core use case; not deferrable |

## Manifest Format

### Location

```
<project-root>/
└── .seihou/
    ├── manifest.json     # Generation state
    └── config.dhall      # Local project config (optional)
```

### Schema

```json
{
  "version": 1,
  "generatedAt": "2026-03-01T10:30:00Z",
  "modules": [
    {
      "name": "haskell-base",
      "source": "~/.config/seihou/modules/haskell-base",
      "appliedAt": "2026-03-01T10:30:00Z"
    },
    {
      "name": "nix-flake",
      "source": "~/.config/seihou/modules/nix-flake",
      "appliedAt": "2026-03-01T10:30:00Z"
    }
  ],
  "variables": {
    "project.name": "my-app",
    "project.version": "0.1.0.0",
    "license": "MIT",
    "haskell.ghc-version": "9.12.2"
  },
  "files": {
    "README.md": {
      "hash": "abc123...",
      "module": "haskell-base",
      "strategy": "template",
      "generatedAt": "2026-03-01T10:30:00Z"
    },
    "my-app.cabal": {
      "hash": "def456...",
      "module": "haskell-base",
      "strategy": "dhall-text",
      "generatedAt": "2026-03-01T10:30:00Z"
    },
    "flake.nix": {
      "hash": "789abc...",
      "module": "nix-flake",
      "strategy": "dhall-text",
      "generatedAt": "2026-03-01T10:30:00Z"
    }
  }
}
```

## Domain Model

```haskell
data Manifest = Manifest
  { manifestVersion   :: Int
  , manifestGenAt     :: UTCTime
  , manifestModules   :: [AppliedModule]
  , manifestVars      :: Map VarName Text    -- Serialized variable values
  , manifestFiles     :: Map FilePath FileRecord
  }
  deriving stock (Eq, Show, Generic)

data AppliedModule = AppliedModule
  { appliedName      :: ModuleName
  , appliedSource    :: FilePath    -- Where the module was loaded from
  , appliedAt        :: UTCTime
  }
  deriving stock (Eq, Show, Generic)

data FileRecord = FileRecord
  { fileHash         :: SHA256
  , fileModule       :: ModuleName
  , fileStrategy     :: Strategy
  , fileGeneratedAt  :: UTCTime
  }
  deriving stock (Eq, Show, Generic)

newtype SHA256 = SHA256 { unSHA256 :: Text }
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (IsString, ToJSON, FromJSON)
```

## Three-State Diff Model

The diff engine compares three sources to classify each file:

```
                 Manifest                    Plan
            (last generated)           (what would be
                  │                    generated now)
                  │                         │
                  └──────────┬──────────────┘
                             │
                          Compare
                             │
                             ▼
                           Disk
                    (current filesystem)
```

### File Classification

```haskell
data DiffResult = DiffResult
  { diffNew        :: [PlannedFile]     -- In plan, not in manifest or disk
  , diffModified   :: [ModifiedFile]    -- In plan, in manifest, plan ≠ manifest
  , diffUnchanged  :: [FilePath]        -- In plan, in manifest, plan = manifest
  , diffConflict   :: [ConflictFile]    -- User modified a generated file
  , diffOrphaned   :: [OrphanedFile]    -- In manifest, not in plan (module removed)
  , diffUntracked  :: [FilePath]        -- On disk, not in manifest or plan
  }
  deriving stock (Eq, Show, Generic)

data PlannedFile = PlannedFile
  { plannedPath    :: FilePath
  , plannedModule  :: ModuleName
  , plannedContent :: ByteString
  }
  deriving stock (Eq, Show, Generic)

data ModifiedFile = ModifiedFile
  { modifiedPath       :: FilePath
  , modifiedModule     :: ModuleName
  , modifiedOldHash    :: SHA256       -- From manifest
  , modifiedNewContent :: ByteString   -- From plan
  }
  deriving stock (Eq, Show, Generic)

data ConflictFile = ConflictFile
  { conflictPath        :: FilePath
  , conflictModule      :: ModuleName
  , conflictManifest    :: SHA256      -- What we last generated
  , conflictDisk        :: SHA256      -- What's on disk now
  , conflictPlan        :: ByteString  -- What we would generate
  }
  deriving stock (Eq, Show, Generic)

data OrphanedFile = OrphanedFile
  { orphanedPath   :: FilePath
  , orphanedModule :: ModuleName      -- Module that generated it
  }
  deriving stock (Eq, Show, Generic)
```

### Classification Logic

For each file path across all three sources:

| Manifest | Plan | Disk | Classification |
|---|---|---|---|
| absent | present | absent | **New** — file will be created |
| absent | present | present | **Conflict** — file exists but wasn't generated by us |
| present | present | present, disk=manifest | **Modified** or **Unchanged** (compare plan to manifest) |
| present | present | present, disk≠manifest | **Conflict** — user modified generated file |
| present | absent | present | **Orphaned** — module was removed |
| present | absent | absent | **Orphaned** (already deleted by user) — remove from manifest |
| absent | absent | present | **Untracked** — not our concern |

## Conflict Resolution UX

When a conflict is detected during `seihou run`:

```
Conflict: README.md
  Generated by: haskell-base
  Last generated hash: abc123...
  Current disk hash:   def456...  (modified by user)
  New plan hash:       789abc...

  [d]iff  [a]ccept new  [k]eep current  [s]kip  [q]uit
```

### Resolution Options

```haskell
data ConflictResolution
  = AcceptNew        -- Overwrite with plan output
  | KeepCurrent      -- Leave disk version, update manifest hash
  | Skip             -- Leave disk version, don't update manifest
  | Abort            -- Stop generation entirely
  deriving stock (Eq, Show, Generic)
```

### `--force` Behavior

`--force` auto-resolves all conflicts with `AcceptNew`, overwriting user modifications without prompting.

## Incremental Re-Generation

When `seihou run` is executed on a project with an existing manifest:

1. **Load manifest** from `.seihou/manifest.json`
2. **Compile plan** from current module definitions and variable values
3. **Compute diff** using three-state model
4. **Filter operations**: Only new, modified, and resolved-conflict files are written
5. **Show plan** to user (with diff highlighting)
6. **Execute** approved operations
7. **Update manifest** with new state

### What Triggers Re-Generation

A file is re-generated when any of these change:
- The module's source template/file changed
- A variable used by the file changed
- The module itself was updated

The manifest stores content hashes, not input hashes, so change detection compares the planned output hash against the manifest hash.

## `seihou status` Output

```
Seihou Status:

Applied modules:
  haskell-base    (applied 2026-03-01, source: ~/.config/seihou/modules/haskell-base)
  nix-flake       (applied 2026-03-01, source: ~/.config/seihou/modules/nix-flake)

Tracked files: 5
  README.md           haskell-base   unchanged
  my-app.cabal        haskell-base   unchanged
  src/Lib.hs          haskell-base   modified by user
  flake.nix           nix-flake      unchanged
  .gitignore          nix-flake      unchanged

Variables: 4 resolved
  project.name = "my-app"
  project.version = "0.1.0.0"
  license = "MIT"
  haskell.ghc-version = "9.12.2"
```

## Business Rules

- The manifest is created on first `seihou run` in a project
- The manifest is updated atomically (write to temp file, rename)
- If no manifest exists, all planned files are treated as "New"
- The manifest version field enables future schema migrations
- `seihou init` creates the `.seihou/` directory but not the manifest (that's created by `run`)
- Orphaned files are reported but not automatically deleted (user must remove them)
- The manifest should be committed to version control (it's project state)

## Edge Cases

| Case | Behavior |
|---|---|
| Manifest file missing | First run; all files treated as New |
| Manifest file corrupted | Error with helpful message; suggest `--force` to regenerate |
| File on disk but not in manifest | Treated as Untracked; not touched |
| Module removed from run | Its files become Orphaned in status |
| Variable value changed | Files using that variable show as Modified in plan |
| Two modules contribute to same file | Manifest records the primary module; contributors in composition metadata |
| `.seihou/` directory missing | Created by `seihou init` or first `seihou run` |
| Manifest version newer than tool | Error: "manifest was created by a newer version of seihou" |
| Disk file deleted by user | Conflict if manifest still tracks it; re-created if in plan |

## Testing Plan

| Test | Type | Description |
|---|---|---|
| Manifest serialization roundtrip | Unit | Write → read → compare |
| Three-state diff classification | Unit/Property | All classification cases from the table |
| New file detection | Unit | File in plan, not in manifest → New |
| User modification detection | Unit | Disk hash ≠ manifest hash → Conflict |
| Orphaned file detection | Unit | In manifest, not in plan → Orphaned |
| Incremental re-generation | Integration | Change variable, re-run, only affected files regenerated |
| Conflict resolution flow | Integration | Simulate user edit, re-run, resolve conflict |
| `--force` override | Integration | All conflicts auto-resolved with AcceptNew |
| Atomic manifest write | Unit | Interrupted write doesn't corrupt manifest |
| Status command output | Integration | Correct classification of all file states |

## Future Enhancements

- Undo/rollback: Restore files to their manifest-recorded state
- Manifest diffing: Compare two manifest versions
- File ownership transfer: Move a file from one module's ownership to another
- Garbage collection: Automatically remove orphaned files (with confirmation)
- Manifest export: Generate a report of all generated files and their provenance

## Cross-References

- [Architecture Overview](../../architecture/overview.md) — Manifest's role in the pipeline
- [Module System](module-system.md) — Applied module tracking
- [Composition and Layering](composition-and-layering.md) — Multi-module file ownership
- [Generation Strategies](generation-strategies.md) — Content hashing per strategy
- [CLI Commands](cli-commands.md) — `status` command, `--force` flag
