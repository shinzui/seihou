---
type: Friction Entry
title: "update-seihou-schema skill describes a superseded flake input"
description: "The update-seihou-schema skill says flake.nix follows the schema submodule by git+file path with nothing to edit, but flake.nix now pins seihou-schema-src by GitHub revision, so following the skill leaves the flake on the old schema."
generated:
  by: "claude-code/claude-opus-5-5"
  at: "2026-11-11T17:46:56Z"
frictionId: FRIC-14
status: logged
impact: slowdown
kind: documentation
origin: "mori://shinzui/seihou"
affects: "mori://shinzui/seihou"
plan: "docs/plans/110-add-first-class-user-defined-judgements-backed-by-shikumi.md"
workaround: "Edited the revision in flake.nix by hand, then ran nix flake update seihou-schema-src"
---
# update-seihou-schema skill describes a superseded flake input

## Attempted

Re-pinning the schema after publishing the Judgement type, following .claude/skills/update-seihou-schema/SKILL.md step 4

## Encountered

nix flake update seihou-schema-src changed nothing; flake.nix line 55 pins github:shinzui/seihou-schema/<rev>

## Workaround

Edited the revision in flake.nix by hand, then ran nix flake update seihou-schema-src
