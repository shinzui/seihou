# seihou registry

Authoring-time operations on a multi-module repository's `seihou-registry.dhall`.

## Usage

```
seihou registry COMMAND [OPTIONS]
```

## Subcommands

| Command | Description |
|---------|-------------|
| `sync-versions` | Copy each module's declared version into the registry |
| `validate`      | Check that entries and versions match their modules |

The `registry` group is designed to extend. Future subcommands (e.g. `registry add`, `registry publish`) will live on this page.

## Description

Run `seihou registry` commands inside a writable checkout of a multi-module repo — the one that owns the `seihou-registry.dhall`. They are intended for registry **authors**, not consumers. They never touch the network and never read installed modules.

---

## seihou registry sync-versions

Populate every registry entry's `version` field from the matching module or recipe.

### Usage

```
seihou registry sync-versions [OPTIONS]
```

### Options

| Option | Description |
|--------|-------------|
| `--dir PATH` | Registry repo root. Defaults to the current directory. |
| `--dry-run` | Print the diff table but do not write the file. |
| `--check` | Exit 1 if any entry is out of sync; do not write. Takes precedence over `--dry-run`. |

### Description

Reads each entry's `module.dhall` or `recipe.dhall`, compares the declared version against the registry entry's `version` field, and rewrites `seihou-registry.dhall` with the current values. The diff table classifies each entry:

- **missing** — Registry has no version; the module declares one.
- **stale** — Registry version differs from the module.
- **no change** — Already in sync.
- **orphan** — The module directory or its `module.dhall` is unreadable; the entry is left untouched (and `validateRegistry` flags the missing file separately).

The rewrite is whole-file: hand-written comments and formatting in `seihou-registry.dhall` are lost. This matches how `new-module` and `new-recipe` emit Dhall. If you maintain comments in your registry file, run `sync-versions` and then manually reapply them, or keep registry metadata outside the file.

Running the command twice in a row is a no-op on the second pass ("0 entries updated").

### Why it matters

External tools like `seihou browse` and `seihou outdated` prefer a registry entry's version over re-evaluating each module. A populated registry lets those tools skip N Dhall evaluations per repo — worth it for any registry with more than one or two modules.

`seihou browse` and `seihou install` now also print a one-line warning per out-of-sync entry when operating against a multi-module repo. The warning is a soft hint, not an error — the operation continues.

### Examples

```sh
# Update the registry in the current directory
seihou registry sync-versions

# Preview the diff without writing
seihou registry sync-versions --dry-run

# Fail a CI job if any entry is out of sync
seihou registry sync-versions --check

# Operate on a registry in a different directory
seihou registry sync-versions --dir ./my-templates --dry-run
```

### CI usage

Drop this into a `just` recipe or GitHub Actions step:

```sh
seihou registry sync-versions --check
```

It exits 0 if everything is in sync and 1 if any entry is missing, stale, or orphaned. Pair it with `seihou validate-module` to check the modules themselves.

---

## seihou registry validate

Check that a multi-module repository's `seihou-registry.dhall` is well-formed and that every entry's `version` field agrees with the underlying `module.dhall` or `recipe.dhall`.

### Usage

```
seihou registry validate [OPTIONS]
```

### Options

| Option | Description |
|--------|-------------|
| `--dir PATH` | Registry repo root. Defaults to the current directory. |

### Description

Combines two existing checks into a single command:

1. **Structural** — every entry's `path` resolves to a `module.dhall` or `recipe.dhall`, every `name` matches `[a-z][a-z0-9-]*`, no module name collides with a recipe name, no path is absolute or contains `..`.
2. **Version** — every entry's `version` field equals the `version` declared in the on-disk `module.dhall` / `recipe.dhall`. A missing registry version (where the module declares one) and a stale registry version both fail validation.

Exits 0 on a clean registry and 1 on any failure. Suitable for CI pre-merge checks. Unlike `seihou registry sync-versions --check`, this also catches structural problems (renamed modules, illegal paths, name collisions).

### Examples

```sh
seihou registry validate
seihou registry validate --dir ./my-templates
```

### CI usage

```yaml
- run: seihou registry validate
```
