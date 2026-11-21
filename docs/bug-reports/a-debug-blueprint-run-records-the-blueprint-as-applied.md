---
type: Bug Report
title: "`seihou agent --debug run` records the blueprint as applied, though no agent ran"
description: >-
  Rendering a runnable blueprint's prompt with `seihou agent --debug run <blueprint>` writes a
  `blueprint` record (name, origin, version, appliedAt) into `.seihou/manifest.json` that cannot
  be told from a real application, so a repository where someone only inspected a prompt claims
  a blueprint it never received, while migration debug leaves the manifest untouched.
bugId: BUG-5
affects: mori://shinzui/seihou
affectedVersion: 0.16.0.1
origin: mori://shinzui/shikigami
severity: degraded
status: fixed
fixedVersion: unreleased
resolution: Debug renders the prompt before baseline acquisition, agent launch, and manifest writes.
generated:
  by: process:claude-code
  at: "2026-11-16T01:45:00Z"
observed: >-
  In a clean detached worktree of kizashi at 58ec398,
  `seihou agent --debug run fix-nix-haskell-flake-customizations` printed the 28 KB resolved
  prompt and exited 0, and `git status` then showed `.seihou/manifest.json` modified: a new
  top-level `"blueprint": {"appliedAt": "2026-11-16T01:08:21Z", "name":
  "fix-nix-haskell-flake-customizations", "origin": {…seihou-modules…}, "version": "0.2.0",
  "noBaseline": false, "baselineModules": []}`, the same shape a completed `seihou agent run`
  writes. In the same worktree, `seihou agent --debug migrate keiro-upgrade --from=0.22.0.0
  --to=0.25.0.0` printed 64 KB and left the manifest byte-for-byte unchanged.
expected: >-
  Debug mode, which the guides present as the way to "audit what Seihou will send" and
  "smoke-check prompts in CI", should leave `.seihou/manifest.json` unchanged, as migration
  debug already does. If baseline application during debug must stay, the record it writes
  should say that it was a debug render (for example `"mode": "debug"`, or no `appliedAt`),
  so that `seihou status`, later updates and readers can tell it from an applied blueprint.
workaround: >-
  Render the prompt in a disposable worktree (`git worktree add --detach <dir> HEAD`, run
  `seihou agent --debug run …` there, then `git worktree remove --force <dir>`), or restore the
  manifest afterwards with `git checkout -- .seihou/manifest.json`.
reproduction:
  - In any repository whose `.seihou/manifest.json` has no `blueprint` key, run `git status --porcelain` and see it clean.
  - Run `seihou agent --debug run fix-nix-haskell-flake-customizations` (seihou-modules 0.2.0 installed); it prints the resolved prompt and exits 0 without contacting a provider.
  - Run `git status --porcelain` again and see ` M .seihou/manifest.json`; `jq .blueprint .seihou/manifest.json` shows the blueprint with an `appliedAt` timestamp.
  - For contrast, run `seihou agent --debug migrate <blueprint> --from=<v1> --to=<v2>` and see the manifest unchanged.
timestamp: "2026-11-21T15:49:46Z"
---

# Bug Report: `seihou agent --debug run` records the blueprint as applied

## What is wrong

`--debug` on `seihou agent run` resolves and prints the blueprint's prompt, and it also writes
the applied-blueprint record into `.seihou/manifest.json`. That record has the same shape and
fields as the one a completed run writes, including `appliedAt`. Nothing in the manifest marks
it as a debug render, so the manifest now says the blueprint was applied when no agent ever ran.

`docs/user/blueprints.md` and `docs/user/agent-assistance.md` both state that blueprint debug
"still applies baseline modules and records blueprint provenance; it is not a dry run". The
behavior is therefore known. The defect is in what the record claims. Those same guides offer
`--debug` to "audit what Seihou will send" and to "smoke-check prompts in CI", and the user-facing
summary is that `--debug` "prints the resolved prompt and exits without contacting a provider".
A reader who follows that advice ends up with a manifest entry that is false. Migration debug
("never writes receipts") shows that a render does not need to write anything.

## Where it was observed

In the keiro modernization campaign of `mori://shinzui/shikigami`
(`mori://shinzui/shikigami/plans/132-modernize-the-keiro-services-with-a-declared-campaign-playbook`).
A batch run of `fix-nix-haskell-flake-customizations` could not complete under the blueprint's
`allowedTools` (`mori://shinzui/seihou/okf/improvement-requests/concepts/IR-23`), so the campaign
renders each blueprint's guidance with `--debug` and has its own gated agent apply it. Rendering
the guidance in the target repository would have left kizashi claiming the blueprint before any
work was done, so the campaign renders it in a disposable worktree instead.

## Consequence

* `seihou status`, `seihou update` and any tool that reads the `blueprint` record treat the
  blueprint as applied.
* A later real run of the same blueprint looks like a re-application.
* A CI smoke check that uses `--debug`, as the guide suggests, dirties every checkout it runs in.
