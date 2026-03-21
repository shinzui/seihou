# seihou remove

Remove an applied module and delete its generated files.

## Usage

```
seihou remove MODULE [OPTIONS]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `MODULE` | Yes | Name of the module to remove |

## Options

| Option | Description |
|--------|-------------|
| `--dry-run` | Show removal plan without executing |
| `--force` | Delete conflicted files without prompting |
| `-v, --verbose` | Show detailed progress messages |

## Description

Removes a module that was previously applied via `seihou run` and deletes the files it generated. Only modules declared as removable in their `module.dhall` (`removable = True`) can be removed.

The command reads the manifest (`.seihou/manifest.json`) to determine which files the module generated. Each file is classified as:

- **Unchanged** — disk hash matches the manifest hash. Safe to delete.
- **Modified** — the user has edited the file since generation. Treated as a conflict.
- **Already deleted** — the file no longer exists on disk. Skipped.

When conflicts are found, the user is prompted to keep or delete each conflicted file. Use `--force` to delete all files without prompting.

After removal, the manifest is updated: the module is removed from the applied modules list and its file records are deleted. Empty parent directories are cleaned up automatically.

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Error (module not applied, not removable, no manifest) |
| 3 | User aborted |

## Examples

```sh
# Preview what would be removed
seihou remove haskell-base --dry-run

# Remove a module (prompts for confirmation)
seihou remove haskell-base

# Force-remove without conflict prompts
seihou remove haskell-base --force
```
