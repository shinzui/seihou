# seihou outdated

Check installed modules for newer versions.

## Usage

```
seihou outdated [OPTIONS]
```

## Options

| Option | Description |
|--------|-------------|
| `--json` | Output as JSON |

## Description

Checks each installed module's source registry for a newer version. Shows modules as "unversioned" if they lack version info.

Only checks modules installed via `seihou install`. Reads `.seihou-origin.json` metadata to determine the source.
