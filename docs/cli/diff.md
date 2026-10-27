# seihou diff

Show changes since last generation.

## Usage

```
seihou diff
```

## Description

Compares tracked files in `.seihou/manifest.json` against the current disk state. Shows files that have been modified or deleted since the last `seihou run`.

Does not load modules or resolve variables — it works purely from the manifest.

Diff compares managed files only. When seed receipts exist it appends
`N seed files not compared`, including when no managed files changed. Seed edits
and deletion belong to the project; diff does not read their content or list them
as changes.
