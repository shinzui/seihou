# seihou diff

Show changes since last generation.

## Usage

```
seihou diff
```

## Description

Compares tracked files in `.seihou/manifest.json` against the current disk state. Shows files that have been modified or deleted since the last `seihou run`.

Does not load modules or resolve variables — it works purely from the manifest.
