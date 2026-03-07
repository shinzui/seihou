# Versioning with Git SHA

## Overview

Seihou embeds the git commit SHA into the CLI binary at compile time, producing version output like:

```
seihou v0.1.0.0 (ded95f8)
```

This makes it easy to identify exactly which commit a binary was built from.

## Architecture

The version system has two paths to obtain the git SHA, because Nix builds strip the `.git` directory:

```
┌─────────────────┐     ┌──────────────────┐
│  cabal build     │     │  nix build        │
│  (local dev)     │     │  (CI / release)   │
└────────┬────────┘     └────────┬──────────┘
         │                       │
   Template Haskell        CPP flag injection
   (githash library)       (-DGIT_HASH="...")
         │                       │
         └───────────┬───────────┘
                     │
           Seihou.CLI.Version
           gitCommitShort :: Maybe Text
```

### Local builds (cabal)

The `githash` library uses Template Haskell (`tGitInfoCwdTry`) to read `.git/` at compile time and extract the commit hash. This works automatically with `cabal build`.

### Nix builds

Nix copies the source into the store without `.git`, so Template Haskell fails. Instead:

1. `flake.nix` captures `self.shortRev` (or `"dirty"` for uncommitted flakes)
2. `nix/haskell-overlay.nix` passes the first 7 characters as a GHC CPP flag: `--ghc-option=-DGIT_HASH="<sha>"`
3. `Version.hs` uses `#ifdef GIT_HASH` to pick up the injected value

### Fallback

If neither path succeeds (e.g. building from a tarball without `.git` and without Nix), the version output omits the commit suffix: `seihou v0.1.0.0`.

## Key Files

| File | Role |
|------|------|
| `seihou-cli/src/Seihou/CLI/Version.hs` | Version module — TH + CPP dual-path logic |
| `nix/haskell-overlay.nix` | Nix overlay — injects `GIT_HASH` CPP define |
| `flake.nix` | Captures `self.shortRev` as `gitRev` |
| `seihou-cli/seihou-cli.cabal` | Declares `githash` dependency and `Paths_seihou_cli` autogen |
| `seihou-cli/src/Seihou/CLI/Commands.hs` | Wires `seihouVersionWithGit` into `--version` flag |

## Cabal Version

The base version (`0.1.0.0`) comes from `Paths_seihou_cli`, which Cabal auto-generates from the `version` field in `seihou-cli.cabal`. Update that field to bump the version number.

## Pattern Origin

This pattern is copied from the [mori](https://github.com/shinzui) project (`mori-cli/src/Mori/Version.hs`).
