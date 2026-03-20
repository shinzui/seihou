# seihou status

Show manifest state for the current project.

## Usage

```
seihou status
```

## Description

Reads `.seihou/manifest.json` in the current directory and displays:

- Applied modules
- Tracked files
- Resolved variable values

Reports success with no output if no manifest exists (i.e., `seihou run` has not been executed in this directory).
