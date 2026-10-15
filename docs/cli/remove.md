# seihou remove

Remove an applied module by executing its declared removal steps.

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

Removes a module that was previously applied via `seihou run` by executing the removal steps declared in its `module.dhall`. Only modules that declare a `removal` section (`removal = Some { steps = [...] }`) can be removed. Modules with `removal = None` cannot be removed.

The command reads the module's `removal` field to determine which operations to perform. Each removal step is one of:

- **remove-file** — Delete a file from disk. Output: `Delete path/to/file`.
- **remove-section** — Strip a tagged section from a file (e.g., lines between `# --- seihou:module ---` markers). Output: `Strip section from path/to/file`.
- **rewrite-file** — Rewrite a file's content using a Dhall expression or template transformation. Output: `Rewrite path/to/file`.

After all removal steps execute, the manifest is updated: the module is removed from the applied modules list and its file records are deleted. Empty parent directories are cleaned up automatically.

When `--force` is used, all operations proceed without confirmation prompts.

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Error (module not applied, no removal section, no manifest) |
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

## Recorded checkout ownership

A module with checkout ownership can be removed without a custom removal spec. Automatic cleanup releases the selected application's qualified instance claim; it never authorizes unrelated file deletion or shell execution. Agreeing co-owners retain the link. Last-owner cleanup unlinks only the expected literal target; locally edited links and real objects are preserved and explained. Sources are never deleted by this automatic cleanup, and dangling links can be retired.

Use `seihou remove MODULE --application ID` when the module is recorded in multiple applications. Ambiguous bare instance names refuse with concrete qualified selection commands. `--dry-run` previews cleanup. `--force` does not override checkout collision, tracked-path or modified-link preservation rules. Custom removal steps must not duplicate automatic checkout cleanup or delete another application's files.
