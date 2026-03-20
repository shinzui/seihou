# seihou list

List available modules.

## Usage

```
seihou list
```

## Description

Scans all module search paths and lists every available module with:

- Module name
- Description
- Source location (project, user, or installed)

Shows an error indicator for modules that fail to load. Reads `.seihou-origin.json` metadata for installed modules to display origin information.
