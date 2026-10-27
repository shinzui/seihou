# seihou remove

Remove a recorded module instance, execute its removal policy, and retire ownership.

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

Removes a module that was previously applied via `seihou run` by executing the removal steps declared in its `module.dhall`. Managed-file removal requires a `removal` section (`removal = Some { steps = [...] }`). Recorded seed-only or checkout-only instances can be removed without one; seed retirement preserves the project object.

The command reads the module's `removal` field to determine which operations to perform. Each removal step is one of:

- **remove-file** — Delete a file from disk. Output: `Delete path/to/file`.
- **remove-section** — Strip a tagged section from a file (e.g., lines between `# --- seihou:module ---` markers). Output: `Strip section from path/to/file`.
- **rewrite-file** — Rewrite a file's content using a Dhall expression or template transformation. Output: `Rewrite path/to/file`.

After successful removal, the manifest retires the selected instance and its claims. Other seed owners retain their receipts. Empty parent directories from deleted managed files are cleaned up automatically; seed retirement never changes project files.

With `--force`, conflicts in declared managed-file removal proceed without confirmation. Seed objects remain protected.

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

## Seed ownership

Recorded seed-only instances can be removed without a custom removal specification.
An instance that also owns managed files needs its existing explicit removal policy.
`seihou remove MODULE` preserves every seed object and retires only that recorded
instance's claims. Ambiguous selections name the supported
`seihou remove QUALIFIED_INSTANCE --application ID` commands.

Delete, remove-section, and rewrite actions overlapping a seed render `Keep PATH
(seed file; owned by the project)` and do not read or change its contents, even with
`--force`. Other seeders retain their claims and the original settlement. After the
last claim leaves, the receipt disappears without touching disk; a later application
may seed an absent path again. Dry-run previews this metadata retirement. Arbitrary
removal shell commands are not sandboxed and must honor project ownership.
