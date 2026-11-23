---
type: Friction Entry
title: "Codex emits a stable schema for a workspace-root field that requires experimental capability"
description: "The generated stable app-server schema includes runtimeWorkspaceRoots, but a native migration edge could not start when its reference directory used the field."
generated:
  by: "codex-cli/gpt-6.2-sol"
  at: "2026-11-23T14:38:15Z"
frictionId: FRIC-23
status: "accepted"
impact: detour
kind: interface
origin: "mori://shinzui/seihou"
affects: "https://github.com/openai/codex"
affectedVersion: "0.171.0"
plan: "docs/plans/127-let-callers-supply-tool-policy-for-batch-blueprint-runs-and-migrations.md"
workaround: "Read the current writable roots with stable config/read and append mounted directories through thread-local sandbox_workspace_write."
resolution: "Reviewed turns use stable config/read plus a thread-scoped writable-roots override and verify the effective sandbox."
amended:
  - by: "codex-cli/gpt-6.2-sol"
    at: "2026-11-23T14:43:13Z"
    change: "Verified the stable configuration path with the six-edge Keiro migration fixture and its installed reference directories."
---
# Codex emits a stable schema for a workspace-root field that requires experimental capability

## Attempted

Run the installed Keiro migration fixture through Seihou using reviewed Codex hooks and mounted blueprint references.

## Encountered

Codex rejected thread/start only for the owner that required an extra directory.

```text
thread/start.runtimeWorkspaceRoots requires experimentalApi capability
```

## Workaround

Read the current writable roots with stable config/read and append mounted directories through thread-local sandbox_workspace_write.
