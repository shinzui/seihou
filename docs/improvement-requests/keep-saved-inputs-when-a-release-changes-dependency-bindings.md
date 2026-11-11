---
type: Improvement Request
title: Keep saved inputs when a release changes a dependency's bindings
description: >-
  Stop seihou update from treating an instance as new when a module release adds
  a binding to a dependency edge, which today either fails on required variables
  the project already saved or, once those are supplied, silently resets the
  project's optional inputs to their defaults.
generated:
  by: process:claude-code
  at: "2026-11-04T18:07:02Z"
timestamp: 2026-11-11T13:57:13Z
requestId: IR-15
status: accepted
targetPlan: docs/plans/123-keep-saved-inputs-when-a-release-changes-a-dependency-s-bindings.md
origin: mori://shinzui/seihou-modules
reviews:
  - kind: model
    reviewer: process:claude-code
    provider: anthropic
    model: claude-opus-5-5
    effort: unspecified
    reviewed_at: "2026-11-04T18:07:02Z"
    document_timestamp: "2026-11-04T18:07:02Z"
    scope: content-and-metadata
    outcome: commented
    context: >-
      Author check against the Seihou 0.15.0.0 source and a minimal local
      reproduction. Not an independent approval.
---

# Improvement Request: Keep Saved Inputs When a Release Changes a Dependency's Bindings

## Status

Accepted. Raised from `FRIC-10`
(`mori://shinzui/seihou-modules/okf/friction-log/concepts/FRIC-10`) against Seihou
0.15.0.0, and planned in
[ExecPlan 123](../plans/123-keep-saved-inputs-when-a-release-changes-a-dependency-s-bindings.md).
The plan pairs a recorded instance with its rebound candidate only one to one within an
application, carries saved inputs with the new edge's bindings taking precedence, refuses an
ambiguous pairing with `--reconfigure` as the escape hatch, and reports the rebinding in the
preview and in `--json`. It leaves the manifest schema unchanged and the release-time
`validate-module` check out of scope. Implementation has not started.

## Context

`docs/user/module-authoring.md` defines instance identity as the set of
parent-supplied `vars` on a dependency edge. That rule is what lets one module be
invoked twice with different bindings, and this request does not ask to change it.

The cost appears when a module that is already released adds a binding to an
existing edge. While building the opt-in container for
`mori://shinzui/seihou-modules` fumadocs 0.4.0, a new `nix.package-module` binding
on the `nix-bun-flake` dependency made `seihou update fumadocs` fail in a project
applied from 0.3.0. The binding had to be removed from the release, so consumers now
pass that variable with `--var` when they opt in.

## Problem

`savedInstanceValues` in `seihou-cli/src/Seihou/CLI/Update.hs` keys saved values by
module name and parent vars. A changed edge therefore finds no saved values for its
candidate instance. Two minimal local modules show the result, with a parent release
1.1.0 adding `child.extra=x` to its `child` dependency:

1. **Plain update fails.** `seihou update parent --json --include-shared-owners`
   and the same command with `--dry-run` both exit 1, although the project saved
   `project.name`. An identical release with no new binding updates cleanly.

   ```text
   {"error":{"code":"variable_errors","message":"Variables could not be resolved: missing required variable: project.name"},"outcome":"error","schemaVersion":1}
   ```

   The message names neither the dependency nor the binding. Non-interactive
   `--reconfigure` gives the same error.

2. **Supplying the missing value silently loses other inputs.** The natural response
   is to add `--var project.name=demo`. That succeeds, but an optional `child.opt`
   the project had set to `custom` returns to its default:

   ```text
   before: name=demo opt=custom
   after:  name=demo opt=default
   ```

   The outcome is `applied` with 0 conflicts and no warning about the lost input, and
   the `child` version is reported as `from: null`, as if it were newly applied.

The second result is the more serious one: an author's small release can change a
project's generated files without anyone being told.

## Requested change

1. When a candidate instance has no exact saved match, and exactly one recorded
   instance of the same module in that application is no longer in the candidate,
   treat the pair as a rebinding. Carry the recorded inputs across, with the new
   edge's bindings taking precedence.
2. Show the rebinding in the update preview and in `--json` output, naming the module
   and its old and new parent vars, and report the real prior version rather than
   `from: null`.
3. When the match is ambiguous, such as several recorded instances of the module,
   refuse with a diagnostic that names the module and the candidates. Never fall back
   to defaults without saying so.
4. Make any variable error caused by a changed edge name that edge, so an author or
   consumer can see the cause.

## Acceptance criteria

- With the parent and child above, `seihou update parent` succeeds with no `--var`,
  keeps `child.opt=custom` and reports the rebinding.
- A value that the new binding sets replaces the saved value for that variable only.
- A module deliberately invoked twice with different bindings keeps both instances and
  their separate inputs.
- A release that removes or changes a binding value behaves the same way as one that
  adds a binding.
- An ambiguous match exits non-zero, leaves project state unchanged and names the
  instances involved.

## Scope and design questions

Instance identity semantics for new compositions stay as documented. Changing a
binding's value may deserve a stronger preview than adding one, because it can be
intended to change output. A `seihou validate-module` warning cannot see the prior
release on its own, so whether authors also get a release-time check is left open.

## Related

- `mori://shinzui/seihou-modules/okf/friction-log/concepts/FRIC-10`
- `mori://shinzui/seihou-modules`, `docs/adr/7-keep-service-images-unmanaged-and-use-nix2container-transports.md` (artifact-level URI pending)
- `docs/user/module-authoring.md`, instance identity
- [ADR 0017](../adr/0017-a-seed-file-is-created-once-and-belongs-to-the-project.md), which already turns dependency edge bindings into saved inputs during legacy adoption
